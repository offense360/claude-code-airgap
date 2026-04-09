# Offline Deployment Rehearsal Runbook

This runbook describes a conservative end-to-end rehearsal for Claude Code Airgap.

Use it when you want to verify that:
- staging works on an online machine
- the bundle can be transferred intact
- deploy works on an offline or restricted machine
- `claude` is discoverable after installation
- the generated `settings.json` matches the expected policy

This runbook is written for phase 1 support only:
- Windows x64
- Linux x64 with glibc

## Goal

The rehearsal proves the deployment path, not the entire Claude runtime path.

It confirms:
- official artifacts can be staged
- bundle metadata remains consistent after transfer
- offline deploy can execute successfully
- PATH is configured
- health checks run

It does not confirm:
- Anthropic-hosted runtime access
- local gateway correctness
- model quality
- account or auth setup outside the generated `settings.json`

## Test Roles

Recommended role split:
- Online operator: runs `stage`
- Transfer operator: copies the prepared bundle
- Offline operator: runs `deploy`

One person can do all three roles, but the checklist is easier to follow if each phase is treated separately.

## Required Inputs

Prepare these before starting:
- a machine with internet access
- a target offline or restricted machine
- this repository
- enough disk space for the requested artifacts
- a transfer method such as removable media or a controlled file share

Optional but recommended:
- a temporary test user profile on the deploy machine
- a known local gateway endpoint if you plan to test runtime connectivity later

## Preflight Checklist

### Online machine

Confirm:
- PowerShell 5.1+ on Windows or `bash` on Linux
- outbound access to `https://storage.googleapis.com`
- enough free disk space in the repository working directory

### Offline Windows machine

Confirm:
- PowerShell 5.1+ or PowerShell 7+
- write access to the user profile
- enough free disk space for the installer and installation output

### Offline Linux machine

Confirm:
- `bash`
- `sha256sum`
- `ldd`
- `grep`
- `sed`
- `awk`
- glibc-based distribution
- write access to `$HOME`

## Phase 1: Stage On The Online Machine

### Windows example

Stage Windows and Linux artifacts:

```powershell
.\stage-claude-airgap.ps1 -p win32-x64,linux-x64
```

Stage a fixed version:

```powershell
.\stage-claude-airgap.ps1 -v 2.1.97 -p win32-x64,linux-x64
```

### Linux example

```bash
./stage-claude-airgap.sh -p linux-x64,win32-x64
```

Or with a fixed version:

```bash
./stage-claude-airgap.sh -v 2.1.97 -p linux-x64,win32-x64
```

### Expected result

You should have a `downloads/` directory containing:
- `VERSION.json`
- `manifest.json`
- one or more Claude binaries for the requested platforms

Minimum verification:
- no checksum error was reported
- no version mismatch was reported
- `downloads/VERSION.json` lists the expected platforms

## Phase 2: Freeze The Transfer Set

The safest transfer set is the repository folder plus the generated bundle.

Minimum transfer contents:
- `deploy-claude-airgap.ps1` for Windows deploy
- `deploy-claude-airgap.sh` for Linux deploy
- `settings/settings.json.template`
- `downloads/VERSION.json`
- `downloads/manifest.json`
- the staged platform binary or binaries

Recommended transfer layouts:

Full repository copy:

```text
claude-code-airgap/
├── deploy-claude-airgap.ps1
├── deploy-claude-airgap.sh
├── settings/
└── downloads/
```

Minimal bundle copy:

```text
bundle/
├── deploy-claude-airgap.ps1
├── settings/
└── downloads/
```

Do not rename the staged Claude binary files.

## Phase 3: Verify The Copied Bundle Before Deploy

On the offline machine, confirm that:
- `VERSION.json` exists
- `manifest.json` exists
- the platform-specific binary exists
- file sizes match what you expect from the source copy

Recommended checks:
- compare directory listing against the online machine
- verify timestamps are plausible
- confirm the copied folder is not partially missing `settings/`

Do not edit `VERSION.json` or `manifest.json` manually.

## Phase 4: Deploy On Windows

From the transferred folder:

```powershell
.\deploy-claude-airgap.ps1
```

### Expected deploy actions

The script should:
- detect `win32-x64`
- locate the bundle
- verify version consistency
- recompute SHA256 and size
- copy the verified installer to a temporary working directory
- run the installer
- ensure `%USERPROFILE%\.local\bin` is in User PATH
- create or merge `%USERPROFILE%\.claude\settings.json`
- run `claude --version`
- run `claude doctor` as best-effort

### Post-deploy checks

Confirm:

```powershell
Get-Command claude
claude --version
```

Inspect:
- `%USERPROFILE%\.claude\settings.json`
- `%USERPROFILE%\.local\bin`

If Git Bash is installed, also confirm whether `CLAUDE_CODE_GIT_BASH_PATH` was added.

## Phase 5: Deploy On Linux

From the transferred folder:

```bash
chmod +x ./deploy-claude-airgap.sh
./deploy-claude-airgap.sh
```

### Expected deploy actions

The script should:
- detect `linux-x64`
- reject non-glibc environments
- locate the bundle
- verify version consistency
- recompute SHA256 and size
- copy the verified installer to a temporary working directory
- run the installer
- ensure `$HOME/.local/bin` is configured for the current shell and future shells
- create `$HOME/.claude/settings.json`
- run `claude --version`
- run `claude doctor` as best-effort

### Post-deploy checks

Confirm:

```bash
command -v claude
claude --version
```

Inspect:
- `$HOME/.claude/settings.json`
- `$HOME/.local/bin`
- `~/.bashrc`
- `~/.profile`

## Settings Validation

Default managed keys should exist under `env`:
- `DISABLE_AUTOUPDATER`
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`
- `DISABLE_NON_ESSENTIAL_MODEL_CALLS`
- `ANTHROPIC_BASE_URL`
- `ANTHROPIC_AUTH_TOKEN`

Expected default values:

```json
{
  "env": {
    "DISABLE_AUTOUPDATER": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "DISABLE_NON_ESSENTIAL_MODEL_CALLS": "1",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4000",
    "ANTHROPIC_AUTH_TOKEN": "no-token"
  }
}
```

Interpretation:
- auto-update is disabled
- nonessential traffic is disabled
- a local gateway endpoint is assumed by default
- the auth token is a placeholder

## Rehearsal Pass Criteria

Count the rehearsal as successful only if all of these are true:
- stage completed without checksum or version errors
- copied bundle contains the full expected file set
- deploy completed without fatal validation errors
- `claude --version` succeeded after deploy
- generated or merged `settings.json` matches the expected managed keys
- the PATH target exists in the user environment

Treat these as warnings, not immediate failure:
- `claude doctor` reports a runtime or connectivity warning
- local gateway is not reachable yet

## Known Fail-Closed Cases

Windows:
- invalid existing `%USERPROFILE%\.claude\settings.json`
- existing `env` value is not a JSON object
- bundle version and manifest version do not match
- staged platform is missing

Linux:
- non-glibc host
- existing `$HOME/.claude/settings.json` without `CLAUDE_CODE_AIRGAP_REPLACE_SETTINGS=1`
- bundle version and manifest version do not match
- staged platform is missing

These are intentional safety stops.

## Update Rehearsal

To rehearse an upgrade:
1. Clear `downloads/` on the online machine if you want a different Claude version.
2. Stage the new version.
3. Transfer the new bundle.
4. Run `deploy` again on the offline machine.
5. Confirm `claude --version` shows the new version.

Remember:
- auto-update is disabled
- updates are manual by design

## Logging Recommendations

For change-controlled environments, capture:
- the exact staging command used
- the exact deploy command used
- the resulting `VERSION.json`
- the resulting `settings.json`
- the output of `claude --version`
- any `claude doctor` warning text

Suggested Windows capture:

```powershell
.\deploy-claude-airgap.ps1 *>&1 | Tee-Object -FilePath .\deploy.log
```

Suggested Linux capture:

```bash
./deploy-claude-airgap.sh 2>&1 | tee ./deploy.log
```

## Final Operator Notes

This tool is designed to fail closed when metadata, platform, or settings safety assumptions are violated.

If a rehearsal fails:
- do not hand-edit bundle metadata as a shortcut
- fix the source issue
- rerun stage or deploy cleanly

The safest production rollout is:
1. rehearse once on disposable test targets
2. capture the exact successful commands
3. repeat the same sequence on the real restricted targets
