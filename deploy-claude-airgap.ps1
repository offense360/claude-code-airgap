#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ToolVersionValue = "0.1.0"
$ManagedSettingsFallback = [ordered]@{
    env = [ordered]@{
        DISABLE_AUTOUPDATER = "1"
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
        DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1"
        ANTHROPIC_BASE_URL = "http://127.0.0.1:4000"
        ANTHROPIC_AUTH_TOKEN = "no-token"
    }
}

function Show-Banner {
    param([string]$Mode)

    Write-Host "========================================"
    Write-Host "Claude Code Airgap"
    Write-Host $Mode
    Write-Host "========================================"

    if ($env:CLAUDE_CODE_AIRGAP_BANNER -eq "1") {
        @'
   ______ _                 _      
  / ____/ /___ ___  _______(_)___ _
 / /   / / __ `/ / / / ___/ / __ `/
/ /___/ / /_/ / /_/ / /  / / /_/ / 
\____/_/\__,_/\__,_/_/  /_/\__,_/  
'@ | Write-Host
        Write-Host ""
    }
}

function Show-Help {
    @"
deploy-claude-airgap.ps1

Usage:
  .\deploy-claude-airgap.ps1
  .\deploy-claude-airgap.ps1 -V
  .\deploy-claude-airgap.ps1 -h

Options:
  -V, --tool-version  Print tool version.
  -h, --help          Print help.
  -tui                Reserved for a later release. Not available in phase 1.

Supported platform in phase 1:
  win32-x64
"@
}

function Get-CurrentPlatform {
    if (-not [Environment]::Is64BitProcess) {
        throw "64-bit PowerShell is required."
    }

    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $env:PROCESSOR_ARCHITEW6432 -eq "ARM64") {
        throw "ARM64 is not supported in phase 1."
    }

    return "win32-x64"
}

function Find-BundleDirectory {
    $downloadsCandidate = Join-Path $PSScriptRoot "downloads"
    if ((Test-Path -LiteralPath (Join-Path $downloadsCandidate "VERSION.json")) -and (Test-Path -LiteralPath (Join-Path $downloadsCandidate "manifest.json"))) {
        return $downloadsCandidate
    }

    if ((Test-Path -LiteralPath (Join-Path $PSScriptRoot "VERSION.json")) -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot "manifest.json"))) {
        return $PSScriptRoot
    }

    throw "Unable to locate bundle metadata. Expected VERSION.json and manifest.json either in the script directory or in a downloads subdirectory."
}

function Get-BinaryFileName {
    param(
        [string]$Version,
        [string]$Platform
    )

    if ($Platform -like "win32-*") {
        return "claude-$Version-$Platform.exe"
    }

    return "claude-$Version-$Platform"
}

function Get-LowerFileHash {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        $Data,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $tempPath = "$Path.tmp"
    $json = $Data | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($tempPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
}

function ConvertTo-Hashtable {
    param($InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-Hashtable -InputObject $InputObject[$key]
        }
        return $hash
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $InputObject) {
            [void]$list.Add((ConvertTo-Hashtable -InputObject $item))
        }
        return @($list)
    }

    if ($InputObject -is [pscustomobject]) {
        $hash = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
        }
        return $hash
    }

    return $InputObject
}

function Get-ManagedSettings {
    $templatePath = Join-Path $PSScriptRoot "settings\settings.json.template"
    if (Test-Path -LiteralPath $templatePath) {
        $template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json
        $settings = ConvertTo-Hashtable -InputObject $template
    } else {
        $settings = ConvertTo-Hashtable -InputObject $ManagedSettingsFallback
    }

    $gitBashCandidate = "C:\Program Files\Git\bin\bash.exe"
    if ((Test-Path -LiteralPath $gitBashCandidate) -and -not $settings.env.Contains("CLAUDE_CODE_GIT_BASH_PATH")) {
        $settings.env["CLAUDE_CODE_GIT_BASH_PATH"] = $gitBashCandidate
    }

    return $settings
}

function Ensure-UserPathContains {
    param([string]$PathEntry)

    $currentUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $entries = @()
    if (-not [string]::IsNullOrWhiteSpace($currentUserPath)) {
        $entries = @($currentUserPath.Split(";") | Where-Object { $_ })
    }

    $alreadyPresent = $false
    foreach ($entry in $entries) {
        if ($entry.TrimEnd("\").ToLowerInvariant() -eq $PathEntry.TrimEnd("\").ToLowerInvariant()) {
            $alreadyPresent = $true
            break
        }
    }

    if (-not $alreadyPresent) {
        $newUserPath = if ([string]::IsNullOrWhiteSpace($currentUserPath)) { $PathEntry } else { "$currentUserPath;$PathEntry" }
        [Environment]::SetEnvironmentVariable("PATH", $newUserPath, "User")
    }

    if (-not (($env:PATH -split ";") | Where-Object { $_.TrimEnd("\").ToLowerInvariant() -eq $PathEntry.TrimEnd("\").ToLowerInvariant() })) {
        $env:PATH = "$PathEntry;$env:PATH"
    }
}

function Merge-SettingsFile {
    param(
        [string]$TargetPath,
        $ManagedSettings
    )

    $parentDir = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $TargetPath) {
        $existingRaw = Get-Content -LiteralPath $TargetPath -Raw
        try {
            $existing = ConvertTo-Hashtable -InputObject ($existingRaw | ConvertFrom-Json)
        } catch {
            throw "Existing settings file is not valid JSON: $TargetPath"
        }

        $backupPath = "$TargetPath.bak.$((Get-Date).ToString('yyyyMMddHHmmss'))"
        Copy-Item -LiteralPath $TargetPath -Destination $backupPath -Force
    } else {
        $existing = [ordered]@{}
    }

    if ($existing.Contains("env") -and $existing.env -isnot [System.Collections.IDictionary]) {
        throw "Existing settings file has a non-object env value. Refusing to merge: $TargetPath"
    }

    if (-not $existing.Contains("env")) {
        $existing.env = [ordered]@{}
    }

    foreach ($key in $ManagedSettings.env.Keys) {
        $existing.env[$key] = $ManagedSettings.env[$key]
    }

    Write-JsonFile -Data $existing -Path $TargetPath
}

function Invoke-HealthChecks {
    Write-Host "Running health checks..."

    $command = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Claude command was not found on PATH after installation."
    }

    & claude --version
    $doctorOutput = & claude doctor 2>&1
    $doctorExitCode = $LASTEXITCODE
    $doctorOutput | ForEach-Object { Write-Host $_ }

    if ($doctorExitCode -ne 0) {
        Write-Warning "claude doctor returned a non-zero exit code ($doctorExitCode). This does not block deployment."
    }
}

$showHelp = $false
$showToolVersion = $false
$enableTui = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    switch -CaseSensitive ($args[$i]) {
        "-h" { $showHelp = $true }
        "--help" { $showHelp = $true }
        "-V" { $showToolVersion = $true }
        "--tool-version" { $showToolVersion = $true }
        "-tui" { $enableTui = $true }
        default {
            throw "Unknown argument: $($args[$i])"
        }
    }
}

if ($showHelp) {
    Show-Help
    exit 0
}

if ($showToolVersion) {
    Write-Output $ToolVersionValue
    exit 0
}

if ($enableTui) {
    throw "TUI is deferred in phase 1."
}

Show-Banner -Mode "Deploy Offline Bundle"

$currentPlatform = Get-CurrentPlatform
$bundleDirectory = Find-BundleDirectory
$versionMetadataPath = Join-Path $bundleDirectory "VERSION.json"
$manifestPath = Join-Path $bundleDirectory "manifest.json"

$versionMetadata = Get-Content -LiteralPath $versionMetadataPath -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$claudeVersion = $versionMetadata.claude_version
if ([string]::IsNullOrWhiteSpace($claudeVersion)) {
    throw "VERSION.json does not contain claude_version."
}

if ($manifest.version -ne $claudeVersion) {
    throw "Manifest version mismatch. VERSION.json=$claudeVersion manifest=$($manifest.version)"
}

if ($versionMetadata.downloaded_platforms -notcontains $currentPlatform) {
    throw "The bundle does not include the current platform: $currentPlatform"
}

$platformRecord = $manifest.platforms.$currentPlatform
if (-not $platformRecord) {
    throw "Manifest does not include platform $currentPlatform."
}

$binaryPath = Join-Path $bundleDirectory (Get-BinaryFileName -Version $claudeVersion -Platform $currentPlatform)
if (-not (Test-Path -LiteralPath $binaryPath)) {
    throw "Bundle binary is missing: $binaryPath"
}

$expectedChecksum = $platformRecord.checksum
$expectedSize = [Int64]$platformRecord.size
$actualSize = (Get-Item -LiteralPath $binaryPath).Length
if ($actualSize -ne $expectedSize) {
    throw "Binary size mismatch. Expected $expectedSize bytes, got $actualSize."
}

$actualChecksum = Get-LowerFileHash -Path $binaryPath
if ($actualChecksum -ne $expectedChecksum) {
    throw "Binary checksum mismatch for $binaryPath"
}

$managedSettings = Get-ManagedSettings
$settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
$pathEntry = Join-Path $env:USERPROFILE ".local\bin"

Ensure-UserPathContains -PathEntry $pathEntry
Merge-SettingsFile -TargetPath $settingsPath -ManagedSettings $managedSettings

$workingDirectory = Join-Path $env:TEMP "claude-code-airgap\$claudeVersion"
if (-not (Test-Path -LiteralPath $workingDirectory)) {
    New-Item -ItemType Directory -Path $workingDirectory -Force | Out-Null
}

$workingBinary = Join-Path $workingDirectory (Split-Path -Leaf $binaryPath)
Copy-Item -LiteralPath $binaryPath -Destination $workingBinary -Force

if ($env:CLAUDE_CODE_AIRGAP_SKIP_INSTALL -eq "1") {
    Write-Host "Skipping install because CLAUDE_CODE_AIRGAP_SKIP_INSTALL=1"
} else {
    & $workingBinary install
    Invoke-HealthChecks
}

Write-Host "Bundle directory: $bundleDirectory"
Write-Host "Verified version: $claudeVersion"
Write-Host "PATH entry ensured: $pathEntry"
Write-Host "Settings path: $settingsPath"
