#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ToolVersionValue = "0.1.0"
$ReleaseBaseUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
$SupportedPlatforms = @("win32-x64", "linux-x64")
$BundleDirectory = Join-Path $PSScriptRoot "downloads"

function Initialize-NetworkDefaults {
    # Windows PowerShell 5.1 may negotiate legacy TLS defaults depending on machine policy.
    # Force modern TLS before any HTTPS request to the official release bucket.
    if ($PSVersionTable.PSEdition -ne "Core") {
        $securityProtocol = [Net.SecurityProtocolType]::Tls12
        if ([Enum]::GetNames([Net.SecurityProtocolType]) -contains "Tls13") {
            $securityProtocol = $securityProtocol -bor [Net.SecurityProtocolType]::Tls13
        }

        [Net.ServicePointManager]::SecurityProtocol = $securityProtocol
        [Net.ServicePointManager]::Expect100Continue = $false
    }
}

function Invoke-TextRequest {
    param([string]$Uri)

    try {
        return (Invoke-RestMethod -Uri $Uri -ErrorAction Stop).ToString().Trim()
    } catch {
        throw "Network request failed for $Uri. If you are using Windows PowerShell 5.1, verify TLS 1.2 is allowed on this machine or retry with PowerShell 7 (`pwsh`). Underlying error: $($_.Exception.Message)"
    }
}

function Invoke-DownloadRequest {
    param(
        [string]$Uri,
        [string]$Path
    )

    try {
        Invoke-WebRequest -Uri $Uri -OutFile $Path -ErrorAction Stop | Out-Null
    } catch {
        throw "Download failed for $Uri. If you are using Windows PowerShell 5.1, verify TLS 1.2 is allowed on this machine or retry with PowerShell 7 (`pwsh`). Underlying error: $($_.Exception.Message)"
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
stage-claude-airgap.ps1

Usage:
  .\stage-claude-airgap.ps1 [-v VERSION] [-p PLATFORM[,PLATFORM]]
  .\stage-claude-airgap.ps1 -V
  .\stage-claude-airgap.ps1 -h

Options:
  -v, --version       Claude version to stage. Defaults to latest.
  -p, --platform      Comma-separated platform list or all. Defaults to current platform.
  -V, --tool-version  Print tool version.
  -h, --help          Print help.
  -tui                Reserved for a later release. Not available in phase 1.

Supported platforms in phase 1:
  win32-x64
  linux-x64
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

function Test-VersionString {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return
    }

    if ($Version -notmatch '^(stable|latest|\d+\.\d+\.\d+(-[A-Za-z0-9._-]+)?)$') {
        throw "Invalid version format: $Version"
    }
}

function Resolve-Platforms {
    param([string]$PlatformArg)

    if ([string]::IsNullOrWhiteSpace($PlatformArg)) {
        return @(Get-CurrentPlatform)
    }

    if ($PlatformArg -eq "all") {
        return $SupportedPlatforms
    }

    $items = @($PlatformArg.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($items.Count -eq 0) {
        throw "Platform list is empty."
    }

    foreach ($item in $items) {
        if ($SupportedPlatforms -notcontains $item) {
            throw "Unsupported platform: $item"
        }
    }

    return $items
}

function Resolve-ClaudeVersion {
    param([string]$VersionArg)

    if ([string]::IsNullOrWhiteSpace($VersionArg)) {
        $channel = "latest"
    } elseif ($VersionArg -in @("latest", "stable")) {
        $channel = $VersionArg
    } else {
        return $VersionArg
    }

    $channelUrl = "$ReleaseBaseUrl/$channel"
    $resolved = Invoke-TextRequest -Uri $channelUrl
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        throw "Unable to resolve release version from $channelUrl"
    }
    return $resolved
}

function Get-BinaryLeafName {
    param([string]$Platform)

    if ($Platform -like "win32-*") {
        return "claude.exe"
    }

    return "claude"
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

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        $Data,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $tempPath = "$Path.tmp"
    $json = $Data | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($tempPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
}

function Get-ExistingPlatformsForVersion {
    param(
        [string]$VersionJsonPath,
        [string]$ExpectedVersion
    )

    if (-not (Test-Path -LiteralPath $VersionJsonPath)) {
        return @()
    }

    $existingMetadata = Get-Content -LiteralPath $VersionJsonPath -Raw | ConvertFrom-Json
    if ($existingMetadata.claude_version -ne $ExpectedVersion) {
        throw "Bundle already contains version $($existingMetadata.claude_version). Remove the downloads directory before staging version $ExpectedVersion."
    }

    return @($existingMetadata.downloaded_platforms)
}

function Save-UriToFile {
    param(
        [string]$Uri,
        [string]$Path
    )

    $tempPath = "$Path.tmp"
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force
    }

    Invoke-DownloadRequest -Uri $Uri -Path $tempPath
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
}

function Get-LowerFileHash {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-ArtifactIntegrity {
    param(
        [string]$Path,
        [string]$Checksum,
        [Int64]$Size
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -ne $Size) {
        return $false
    }

    return (Get-LowerFileHash -Path $Path) -eq $Checksum
}

function Download-Artifact {
    param(
        [string]$Uri,
        [string]$Path,
        [string]$Checksum,
        [Int64]$Size
    )

    $tempPath = "$Path.part"
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force
    }

    Invoke-DownloadRequest -Uri $Uri -Path $tempPath

    $actualSize = (Get-Item -LiteralPath $tempPath).Length
    if ($actualSize -ne $Size) {
        Remove-Item -LiteralPath $tempPath -Force
        throw "Downloaded size mismatch for $Path. Expected $Size bytes, got $actualSize."
    }

    $actualChecksum = Get-LowerFileHash -Path $tempPath
    if ($actualChecksum -ne $Checksum) {
        Remove-Item -LiteralPath $tempPath -Force
        throw "Checksum mismatch for $Path."
    }

    Move-Item -LiteralPath $tempPath -Destination $Path -Force
}

$showHelp = $false
$showToolVersion = $false
$enableTui = $false
$versionArg = ""
$platformArg = ""

for ($i = 0; $i -lt $args.Count; $i++) {
    switch -CaseSensitive ($args[$i]) {
        "-h" { $showHelp = $true }
        "--help" { $showHelp = $true }
        "-V" { $showToolVersion = $true }
        "--tool-version" { $showToolVersion = $true }
        "-tui" { $enableTui = $true }
        "-v" {
            if ($i + 1 -ge $args.Count) {
                throw "Missing value for -v."
            }
            $i++
            $versionArg = $args[$i]
        }
        "--version" {
            if ($i + 1 -ge $args.Count) {
                throw "Missing value for --version."
            }
            $i++
            $versionArg = $args[$i]
        }
        "-p" {
            if ($i + 1 -ge $args.Count) {
                throw "Missing value for -p."
            }
            $i++
            $platformArg = $args[$i]
        }
        "--platform" {
            if ($i + 1 -ge $args.Count) {
                throw "Missing value for --platform."
            }
            $i++
            $platformArg = $args[$i]
        }
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

Initialize-NetworkDefaults

Show-Banner -Mode "Stage Offline Bundle"

Test-VersionString -Version $versionArg
$selectedPlatforms = Resolve-Platforms -PlatformArg $platformArg
$resolvedVersion = Resolve-ClaudeVersion -VersionArg $versionArg

if (-not (Test-Path -LiteralPath $BundleDirectory)) {
    New-Item -ItemType Directory -Path $BundleDirectory -Force | Out-Null
}

$manifestUrl = "$ReleaseBaseUrl/$resolvedVersion/manifest.json"
$manifestPath = Join-Path $BundleDirectory "manifest.json"
$versionJsonPath = Join-Path $BundleDirectory "VERSION.json"
$existingPlatforms = Get-ExistingPlatformsForVersion -VersionJsonPath $versionJsonPath -ExpectedVersion $resolvedVersion
Save-UriToFile -Uri $manifestUrl -Path $manifestPath
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

if ($manifest.version -ne $resolvedVersion) {
    throw "Manifest version mismatch. Expected $resolvedVersion, got $($manifest.version)."
}

$successfulPlatforms = New-Object System.Collections.Generic.List[string]

foreach ($platform in $selectedPlatforms) {
    $platformRecord = $manifest.platforms.$platform
    if (-not $platformRecord) {
        throw "Manifest does not include platform $platform."
    }

    $checksum = $platformRecord.checksum
    $size = [Int64]$platformRecord.size
    if ([string]::IsNullOrWhiteSpace($checksum) -or $size -le 0) {
        throw "Manifest data is incomplete for platform $platform."
    }

    $fileName = Get-BinaryFileName -Version $resolvedVersion -Platform $platform
    $destinationPath = Join-Path $BundleDirectory $fileName
    $downloadUrl = "$ReleaseBaseUrl/$resolvedVersion/$platform/$(Get-BinaryLeafName -Platform $platform)"

    if (Test-ArtifactIntegrity -Path $destinationPath -Checksum $checksum -Size $size) {
        Write-Host "Verified existing artifact: $fileName"
        $successfulPlatforms.Add($platform)
        continue
    }

    if (Test-Path -LiteralPath $destinationPath) {
        Remove-Item -LiteralPath $destinationPath -Force
    }

    Write-Host "Downloading $platform ..."
    Download-Artifact -Uri $downloadUrl -Path $destinationPath -Checksum $checksum -Size $size
    $successfulPlatforms.Add($platform)
}

$finalPlatforms = New-Object System.Collections.Generic.List[string]
foreach ($platform in ($existingPlatforms + $successfulPlatforms)) {
    if (-not $finalPlatforms.Contains($platform)) {
        $finalPlatforms.Add($platform)
    }
}

if ($finalPlatforms.Count -eq 0) {
    throw "No platform artifacts were staged successfully."
}

$metadata = [ordered]@{
    schema_version = 1
    tool_version = $ToolVersionValue
    claude_version = $resolvedVersion
    download_date_utc = (Get-Date).ToUniversalTime().ToString("o")
    downloaded_platforms = @($finalPlatforms)
    source_latest_url = "$ReleaseBaseUrl/latest"
    source_manifest_url = $manifestUrl
}

Write-JsonFile -Data $metadata -Path $versionJsonPath

Write-Host "Bundle directory: $BundleDirectory"
Write-Host "Staged version: $resolvedVersion"
Write-Host "Platforms: $($finalPlatforms -join ',')"
