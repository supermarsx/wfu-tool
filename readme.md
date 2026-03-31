<p align="center">
  <img src="./wfu-logo.png" alt="wfu-tool logo" width="300" height="300" />
</p>

<h1 align="center">wfu-tool</h1>

<p align="center">
  Windows feature upgrade orchestration for legacy Windows 10 through current Windows 11,
  with interactive TUI flows, headless automation, resume checkpoints, media acquisition,
  and USB creation.
</p>

<p align="center">
  <a href="./spec.md">Specification</a> |
  <a href="./third-party-notices.md">Third-Party Notices</a> |
  <a href="./license.md">License</a>
</p>

## What It Does

`wfu-tool` is a Windows-only PowerShell upgrade tool built to move machines across supported Windows feature releases with real orchestration instead of one-off scripting.

It can:

- detect the current Windows release and build a valid upgrade path
- sequentially upgrade from old Windows 10 releases through newer Windows 10 and Windows 11 targets
- perform direct target upgrades through ISO/media flows
- run interactively or headlessly from CLI and `.ini` config
- persist checkpoints and resume after reboot
- acquire media from multiple Microsoft-backed sources with source-health controls
- create bootable USB media from staged ISO content
- apply compatibility and policy workarounds needed for difficult upgrade paths

## Highlights

- Windows 10 and Windows 11 targets are separated in the interactive selector
- Headless automation supports `CLI > INI > checkpoint` resolution
- Dead sources stay selectable without being auto-picked
- Legacy Windows 10 media support is built in through a pinned manifest layer
- Resume is checkpoint-driven, with scheduled-task and `RunOnce` bootstrap support
- The repo includes CI, packaging, release, winget, and Chocolatey scaffolding

## Project Layout

- [wfu-tool.ps1](/C:/Projects/wfu-tool/wfu-tool.ps1): main engine
- [launch-wfu-tool.ps1](/C:/Projects/wfu-tool/launch-wfu-tool.ps1): interactive launcher
- [launch-wfu-tool.bat](/C:/Projects/wfu-tool/launch-wfu-tool.bat): elevation-friendly batch entrypoint
- [resume-wfu-tool.ps1](/C:/Projects/wfu-tool/resume-wfu-tool.ps1): post-reboot resume wrapper
- [wfu-tool-windows-update.ps1](/C:/Projects/wfu-tool/wfu-tool-windows-update.ps1): direct Windows Update metadata client
- [modules](/C:/Projects/wfu-tool/modules): upgrade, automation, media, USB, and helper modules
- [tests](/C:/Projects/wfu-tool/tests): script-based validation suite
- [devscripts](/C:/Projects/wfu-tool/devscripts): CI, packaging, release, and developer utilities

## Quick Start

### Interactive launcher

```powershell
.\launch-wfu-tool.ps1
```

Or via batch:

```bat
launch-wfu-tool.bat
```

### Headless run

```powershell
.\wfu-tool.ps1 -Mode Headless -TargetVersion 25H2 -NoReboot
```

### Create USB media

```powershell
.\wfu-tool.ps1 -Mode CreateUsb -TargetVersion 25H2 -UsbDiskNumber 3
```

### Resume from checkpoint

```powershell
.\resume-wfu-tool.ps1 -ResumeFromCheckpoint
```

## Configuration

`wfu-tool` supports `.ini`-driven automation.

Example:

```ini
[general]
mode=headless
target_version=25H2
download_path=C:\wfu-tool
no_reboot=true
allow_fallback=true

[sources]
preferred_source=WU_DIRECT
allow_dead_sources=false

[usb]
create_usb=false
partition_style=gpt

[resume]
enabled=true
resume_from_checkpoint=true
```

Use it like this:

```powershell
.\launch-wfu-tool.ps1 -Headless -ConfigPath .\configs\job.ini
```

## Source Model

The engine uses normalized source IDs across CLI, config, logs, and selection logic:

- `WU_DIRECT`
- `ESD_CATALOG`
- `FIDO`
- `MCT`
- `ASSISTANT`
- `WINDOWS_UPDATE`
- `LEGACY_XML`
- `LEGACY_CAB`
- `LEGACY_MCT_X64`
- `LEGACY_MCT_X86`

Source health is first-class:

- `healthy`: selectable and auto-eligible
- `degraded`: selectable and auto-eligible, but warned
- `dead`: selectable only when explicitly requested

## Resume and Safety

The tool keeps session state in a checkpoint file and can re-enter after reboot without forcing the user to rebuild the run manually.

It also performs or supports:

- pending reboot detection
- disk space checks
- network readiness checks
- DISM and SFC health repair
- media reuse where possible
- diagnostics capture on failure

This is still a Windows upgrade tool. It touches registry, scheduled tasks, services, update state, and optionally USB disks. It should be run elevated and intentionally.

## CI and Release

The repository includes a Windows GitHub Actions pipeline in [ci-release.yml](/C:/Projects/wfu-tool/.github/workflows/ci-release.yml) with this order:

1. `format`
2. `type`
3. `lint`
4. `test`
5. `build_test`
6. `package`
7. `release / publish`

Release versioning uses calendar tags in `YY.N` format, for example:

- `26.1`
- `26.2`

Packaging and release helpers live in:

- [Package.ps1](/C:/Projects/wfu-tool/devscripts/Package.ps1)
- [Build-Test.ps1](/C:/Projects/wfu-tool/devscripts/Build-Test.ps1)
- [Get-ReleaseVersion.ps1](/C:/Projects/wfu-tool/devscripts/Get-ReleaseVersion.ps1)
- [Publish-GitHubRelease.ps1](/C:/Projects/wfu-tool/devscripts/Publish-GitHubRelease.ps1)
- [Publish-Winget.ps1](/C:/Projects/wfu-tool/devscripts/Publish-Winget.ps1)
- [Publish-Chocolatey.ps1](/C:/Projects/wfu-tool/devscripts/Publish-Chocolatey.ps1)

## Testing

Run the full suite:

```powershell
.\tests\Test-Runner.ps1
```

Useful targeted checks:

```powershell
.\devscripts\Check-Type.ps1
.\devscripts\Check-Lint.ps1
.\devscripts\Build-Test.ps1
.\devscripts\Package.ps1 -Version 26.1
```

## Notes

- This project is Windows-only.
- Administrator rights are required for real upgrade and USB flows.
- Some live Microsoft endpoints can be unstable or change over time.
- Legacy support exists in code and source planning, but old Microsoft media endpoints are not equally reliable.

## Documentation

- [spec.md](/C:/Projects/wfu-tool/spec.md)
- [third-party-notices.md](/C:/Projects/wfu-tool/third-party-notices.md)
- [license.md](/C:/Projects/wfu-tool/license.md)
