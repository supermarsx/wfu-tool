# wfu-tool Specification

## 1. Overview

`wfu-tool` is a Windows-only PowerShell upgrade orchestration tool for:

- Sequential feature upgrades across supported Windows 10 and Windows 11 releases
- Direct ISO-based in-place upgrades to a target release
- Resume-after-reboot execution for multi-step upgrade paths
- Optional unattended or semi-attended operation through config-driven headless mode
- Creation of bootable USB media from downloaded installation media
- Hardware requirement bypass application for unsupported Windows 11 upgrade scenarios

The current codebase is implemented primarily in:

- [wfu-tool.ps1](C:\Projects\wfu-tool\wfu-tool.ps1)
- [launch-wfu-tool.ps1](C:\Projects\wfu-tool\launch-wfu-tool.ps1)
- [resume-wfu-tool.ps1](C:\Projects\wfu-tool\resume-wfu-tool.ps1)
- [modules\Upgrade](C:\Projects\wfu-tool\modules\Upgrade)

This specification describes the current implementation and supported behavior visible in the repository as of March 31, 2026.

## 2. Primary Goals

- Detect the current Windows release reliably
- Move a machine from older Windows 10 releases through supported intermediate releases up to a requested target
- Support both sequential upgrades and direct target jumps via ISO
- Work around common Windows Setup blockers, Windows Update policy restrictions, and unsupported hardware checks
- Persist enough state to survive reboot boundaries and continue work
- Provide multiple media acquisition methods with retries and fallback handling
- Offer an interactive launcher as well as config-based automation

## 3. Non-Goals

Based on the current codebase, the tool is not designed as:

- A Linux or macOS tool
- A GUI desktop application beyond console-hosted interaction
- A general package manager or Windows servicing framework
- A guaranteed zero-touch enterprise deployment system
- A replacement for activation, licensing, or compliance tooling

## 4. Runtime Environment

### 4.1 Platform

- Windows PowerShell / PowerShell on Windows
- Requires local administrator privileges
- Uses Windows-specific services, registry, COM, DISM, SFC, scheduled tasks, BITS, and ISO mount APIs

### 4.2 External OS Components Used

- Windows Update COM APIs
- `UsoClient`
- scheduled tasks
- `dism.exe`
- `sfc.exe`
- `cleanmgr.exe`
- `diskpart.exe`
- `reg.exe`
- `route.exe`
- `shutdown.exe`
- `curl.exe` as a fallback in some paths
- BITS transfers

### 4.3 Network Expectations

The tool assumes network access for most upgrade and metadata flows unless the user provides media manually.

Network-backed sources include:

- direct Windows Update release metadata
- Windows Update catalog or COM-discovered updates
- Microsoft download APIs used for direct ISO retrieval
- Media Creation Tool downloads
- Windows 11 Installation Assistant download
- pinned legacy manifest URLs for older Windows 10 media

## 5. Top-Level Components

### 5.1 Main Engine

[wfu-tool.ps1](C:\Projects\wfu-tool\wfu-tool.ps1)

Responsibilities:

- parse CLI parameters
- load module files
- resolve effective runtime options
- maintain runtime state and checkpoints
- run preflight checks
- choose sequential vs direct ISO execution
- trigger reboots and resume registration
- capture session summary and abnormal-exit warnings

### 5.2 Interactive Launcher

[launch-wfu-tool.ps1](C:\Projects\wfu-tool\launch-wfu-tool.ps1)

Responsibilities:

- enforce admin elevation expectations
- provide console UI helpers
- collect and normalize user options
- read config files
- discover available target versions
- display system info and upgrade path
- hand off execution to the main engine

Also launched by:

- [launch-wfu-tool.bat](C:\Projects\wfu-tool\launch-wfu-tool.bat)

### 5.3 Resume Wrapper

[resume-wfu-tool.ps1](C:\Projects\wfu-tool\resume-wfu-tool.ps1)

Responsibilities:

- run after reboot in a visible console
- recover stored state from registry and/or checkpoint JSON
- reconstruct execution parameters
- invoke the main engine in resume mode

### 5.4 Windows Update Metadata Client

[wfu-tool-windows-update.ps1](C:\Projects\wfu-tool\wfu-tool-windows-update.ps1)

Responsibilities:

- query release metadata and ESD information from Microsoft update endpoints

### 5.5 Upgrade Modules

[modules\Upgrade\Core.ps1](C:\Projects\wfu-tool\modules\Upgrade\Core.ps1)

- logging
- phases
- registry helpers
- retry wrapper
- service recovery
- network readiness

[modules\Upgrade\Automation.ps1](C:\Projects\wfu-tool\modules\Upgrade\Automation.ps1)

- default options
- INI parsing and serialization
- CLI/config merge logic
- mode normalization
- checkpoint read/write
- source health ordering
- headless-mode requirement validation

[modules\Upgrade\UpgradePreparation.ps1](C:\Projects\wfu-tool\modules\Upgrade\UpgradePreparation.ps1)

- hardware bypass application
- upgrade blocker removal
- current version detection
- enablement package installation
- feature update orchestration

[modules\Upgrade\SystemHealth.ps1](C:\Projects\wfu-tool\modules\Upgrade\SystemHealth.ps1)

- diagnostics bundle capture
- DISM/SFC repair
- pending reboot detection
- disk space validation and cleanup

[modules\Upgrade\DownloadSources.ps1](C:\Projects\wfu-tool\modules\Upgrade\DownloadSources.ps1)

- remote version discovery
- edition key lookup
- direct ISO URL discovery
- ESD source resolution

[modules\Upgrade\LegacyMedia.ps1](C:\Projects\wfu-tool\modules\Upgrade\LegacyMedia.ps1)

- pinned legacy Windows 10 manifest
- per-source health status
- source descriptors and download planning

[modules\Upgrade\MediaTools.ps1](C:\Projects\wfu-tool\modules\Upgrade\MediaTools.ps1)

- hashing
- ESD extraction
- download implementation
- language handling
- TLS repair
- Media Creation Tool flows
- USB planning and writing
- ISO mount/copy/split operations

[modules\Upgrade\Assistant.ps1](C:\Projects\wfu-tool\modules\Upgrade\Assistant.ps1)

- Installation Assistant support
- SetupHost IFEO hook
- upgrade-start verification

## 6. Supported Modes

The code recognizes four normalized modes:

- `Interactive`
- `Headless`
- `Resume`
- `CreateUsb`

### 6.1 Interactive

Primary human-operated mode.

Behavior:

- can prompt for target family and target version
- can show source health labels
- can save config state
- can run normal upgrade orchestration

### 6.2 Headless

Config- or CLI-driven non-interactive mode.

Current enforced requirements:

- target version must be present

If USB creation is also requested:

- either `UsbDiskNumber` or `UsbDiskId` must be provided

### 6.3 Resume

Used after reboot to continue work.

Inputs can come from:

- explicit CLI arguments
- `HKLM:\SOFTWARE\wfu-tool`
- checkpoint JSON payload

### 6.4 CreateUsb

Media-creation mode rather than system-upgrade completion mode.

Current behavior:

- forces `CreateUsb = true`
- forces `DirectIso = true`
- expects an ISO or a flow that results in an ISO or staged setup media
- hands off to USB writer helpers
- does not require reboot on successful media creation

## 7. Version Model

### 7.1 Version Map

The code maintains a build-mapped version table for:

- `W10_1507`
- `W10_1511`
- `W10_1607`
- `W10_1703`
- `W10_1709`
- `W10_1803`
- `W10_1809`
- `W10_1903`
- `W10_1909`
- `W10_2004`
- `W10_20H2`
- `W10_21H1`
- `W10_21H2`
- `W10_22H2`
- `21H2`
- `22H2`
- `23H2`
- `24H2`
- `25H2`

Default target:

- `25H2`

### 7.2 Current Build Values in Code

- `W10_1507` = 10240
- `W10_1511` = 10586
- `W10_1607` = 14393
- `W10_1703` = 15063
- `W10_1709` = 16299
- `W10_1803` = 17134
- `W10_1809` = 17763
- `W10_1903` = 18362
- `W10_1909` = 18363
- `W10_2004` = 19041
- `W10_20H2` = 19042
- `W10_21H1` = 19043
- `W10_21H2` = 19044
- `W10_22H2` = 19045
- `21H2` = 22000
- `22H2` = 22621
- `23H2` = 22631
- `24H2` = 26100
- `25H2` = 26200

### 7.3 Upgrade Chain

The sequential engine contains an explicit chain from Windows 10 1507 through Windows 11 25H2.

It supports two step types:

- `EnablementPackage`
- `FeatureUpdate`

Conceptually:

- older Windows 10 releases move through full feature updates
- eligible adjacent releases can use enablement packages
- cross-generation Windows 10 to Windows 11 automatically promotes to direct ISO mode

## 8. Execution Flow

### 8.1 Entry

The engine:

1. loads helper modules
2. resolves runtime options from defaults, config, checkpoint, registry, and CLI
3. creates or validates download/log paths
4. optionally loads checkpoint state
5. starts main orchestration unless `WFU_TOOL_TEST_MODE=1`

### 8.2 Preflight Sequence

Implemented preflight sequence:

1. TLS configuration repair
2. pending reboot detection
3. disk space check
4. network readiness check
5. hardware bypass application
6. upgrade blocker removal
7. component store repair
8. cumulative update handling
9. checkpoint update

Each step can be skipped by explicit flags for the corresponding areas.

### 8.3 Upgrade Execution Decision

After preflight, the engine chooses:

- direct ISO flow if `DirectIso` is true
- forced direct ISO for Windows 10 to Windows 11 transitions
- otherwise sequential execution through remaining chain steps

### 8.4 Completion and Exit

The engine always emits a session summary and, on abnormal exit or Ctrl+C, warns about possible partial state depending on the last phase.

## 9. Upgrade Methods

### 9.1 Enablement Package Path

The implementation supports enablement package installation using:

1. Windows Update COM search/install
2. offline package application via DISM when applicable
3. Windows Update scan trigger as a final prompting mechanism

### 9.2 Feature Update Path

The feature update path attempts methods in order, subject to enabled/disabled flags:

1. direct ISO / media-based in-place upgrade
2. Installation Assistant fallback when allowed
3. Windows Update COM fallback when allowed and enabled
4. scan trigger and manual guidance if automatic methods fail

### 9.3 Direct ISO Path

The direct ISO path skips intermediate releases and attempts to move directly to the target release.

If direct ISO fails:

- default behavior is abort
- fallback is only attempted when `-AllowFallback` is set

## 10. Media Acquisition Strategy

### 10.1 Source Families

Current source identifiers:

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

### 10.2 Source Ordering Controls

The implementation supports:

- `PreferredSource`
- `ForceSource`
- `AllowDeadSources`
- `SourceHealth` overrides from config

Rules:

- `ForceSource` wins and produces a single-source order
- `PreferredSource` is moved to the front when selectable
- dead sources are excluded from auto-order unless explicitly allowed

### 10.3 Modern Release Sources

For modern targets, the engine can use some combination of:

- direct Windows Update release metadata and ESD retrieval
- ESD catalog flows
- Microsoft software-download API for direct ISO URLs
- Media Creation Tool

### 10.4 Legacy Windows 10 Sources

For older Windows 10 targets, the code uses a pinned local manifest with:

- release metadata
- known MCT URLs
- catalog URL references
- source health judgments

The manifest includes health annotations for known broken endpoints. Examples present in code:

- some legacy XML catalog hosts marked dead
- some CAB endpoints marked dead
- several older pinned MCT URLs marked dead for specific releases

This is important because the tool does not treat every manifest source as equally healthy or auto-eligible.

## 11. ISO and ESD Handling

### 11.1 Existing Media Reuse

Before downloading, the engine checks the download directory for an existing ISO named after the target version.

Behavior:

- large enough ISO is reused
- suspiciously small ISO is deleted

### 11.2 ESD Handling

Implemented capabilities:

- download ESD payloads
- optional SHA1 verification when metadata provides a hash
- extract setup-capable media layout from ESD using DISM
- export only the matching or fallback edition image rather than every edition

### 11.3 ISO Upgrade Preparation

When running a media-based upgrade, the engine can:

- mount the ISO
- locate `setup.exe`
- copy media to a writable staging location if patching is needed
- patch compatibility-related files such as `appraiserres.dll` or `hwreqchk.dll`
- run setup with compatibility bypass arguments

The code explicitly uses the `/Product Server` trick in relevant setup launch paths to reduce hardware enforcement during in-place upgrade.

## 12. Installation Assistant Support

Windows 11 Installation Assistant is supported through a dedicated fallback path.

Implemented behavior:

1. download the assistant executable if missing
2. install an IFEO debugger hook on `SetupHost.exe`
3. apply bypasses via hook script
4. zero `appraiserres.dll` in the temporary setup source tree
5. launch the actual setup host with bypass-oriented arguments
6. verify whether an upgrade really started
7. remove the hook on cleanup

Evidence used to decide whether upgrade activity started includes:

- `$WINDOWS.~BT` contents
- running setup processes
- pending reboot registry markers
- recently updated Panther logs
- recent large files in setup source directories

## 13. Hardware Bypass and Blocker Removal

### 13.1 Hardware Bypasses

The bypass subsystem applies multiple overlapping strategies, including:

- removal of cached appraiser keys
- `HwReqChkVars` spoofing as `REG_MULTI_SZ`
- `MoSetup` unsupported CPU/TPM keys
- `LabConfig` bypass keys for TPM, Secure Boot, RAM, storage, and CPU
- appraiser DWORD-based bypass values
- setup-related skip flags
- update UX preferences
- OS upgrade allowance flags

### 13.2 Telemetry Suppression

The current implementation includes telemetry suppression inside the bypass flow:

- policy registry keys
- service disablement
- scheduled task disablement
- route-based blocking of known telemetry hosts

This behavior is significant because it affects more than setup compatibility alone.

### 13.3 Upgrade Blocker Removal

The blocker-removal logic is intended to clear:

- TargetReleaseVersion policies
- WSUS locks and `UseWUServer` restrictions
- feature-update deferrals
- stale update state
- disabled Windows Update service conditions

The tool also stores enough state to restore some changed policy state later, such as original `UseWUServer`.

## 14. Health, Repair, and Diagnostics

### 14.1 Network Readiness

Network checks are performed unless skipped.

Purpose:

- verify the system can reach Windows Update-related endpoints before starting media acquisition or update install

### 14.2 Disk Space

Disk check behavior:

- validates free space on system drive
- default threshold in code is 15 GB
- attempts cleanup via:
  - Disk Cleanup configuration and run
  - temp folder cleanup
- aborts if still critically low

### 14.3 Component Store Repair

Repair behavior:

- runs `DISM /Online /Cleanup-Image /RestoreHealth`
- runs `sfc /scannow`
- streams progress in the console where possible

### 14.4 Pending Reboot Detection

Checks include:

- CBS reboot markers
- Windows Update reboot markers
- pending file rename operations
- computer rename pending state

### 14.5 Diagnostic Bundle

On major failure paths, the tool can capture a diagnostics folder containing:

- `CBS.log`
- `DISM.log`
- Panther logs such as `setupact.log` and `setuperr.log`
- `DISM_Health.txt`
- generated `WindowsUpdate.log`
- installed update list
- system info snapshot
- error summary
- copy of the tool log

## 15. Resume and Checkpoint Model

### 15.1 Persistence Mechanisms

The tool persists state through:

- registry under `HKLM:\SOFTWARE\wfu-tool`
- scheduled task `wfu-tool-resume`
- RunOnce fallback entry
- checkpoint JSON file

### 15.2 Checkpoint Path

Default checkpoint path shape:

- `<DownloadPath>\session-<SessionId>.checkpoint.json`

### 15.3 Checkpoint Payload

Current checkpoint payload includes:

- `SavedAt`
- `Stage`
- `CurrentVersion`
- `TargetVersion`
- `CurrentStep`
- `NextStep`
- `SelectedSource`
- `Options`
- `Artifacts`

Artifact tracking currently includes fields such as:

- `IsoPath`
- `StagedMediaPath`
- `LegacyWorkspace`
- `DownloadedArtifacts`

### 15.4 Resume Registration

Before reboot, the engine:

- stores state in registry
- updates the checkpoint to `awaiting reboot`
- registers a scheduled task that launches the resume wrapper in a visible console
- registers a RunOnce backup path

### 15.5 Resume Recovery

On restart, the resume wrapper can reconstruct state from:

- explicit CLI options
- registry values
- checkpoint payload values

It then launches the main engine again.

## 16. USB Media Creation

### 16.1 Purpose

The codebase includes a USB creation workflow for turning acquired installation media into bootable upgrade/install media.

### 16.2 Planning Inputs

Supported inputs include:

- `IsoPath`
- `UsbDiskNumber`
- `UsbDiskId`
- `UsbPartitionStyle`
- `KeepIso`

### 16.3 Supported Operations

Implemented helper capabilities include:

- disk discovery and selection
- diskpart script generation
- USB disk initialization
- ISO mount/dismount
- copying source tree to USB
- WIM size checks for FAT32 constraints
- WIM splitting into `.swm` files when necessary

### 16.4 Output Expectations

The writer logs:

- target disk identity
- partition style
- source ISO
- write progress and failures

On success, `CreateUsb` mode ends without scheduling reboot.

## 17. Configuration Model

### 17.1 Config Format

Config files are INI files parsed by [modules\Upgrade\Automation.ps1](C:\Projects\wfu-tool\modules\Upgrade\Automation.ps1).

Recognized sections:

- `[general]`
- `[checks]`
- `[sources]`
- `[usb]`
- `[resume]`
- `[source_health]`

### 17.2 General Section

Current supported keys include:

- `mode`
- `target_version`
- `log_path`
- `download_path`
- `no_reboot`
- `direct_iso`
- `allow_fallback`
- `force_online_update`

### 17.3 Checks Section

Controls whether preflight phases run:

- `bypasses`
- `blocker_removal`
- `telemetry`
- `repair`
- `cumulative_updates`
- `network_check`
- `disk_check`

The implementation stores these as positive booleans in config and inverts them into `Skip*` options internally where needed.

### 17.4 Sources Section

Current keys:

- `direct_esd`
- `esd`
- `fido`
- `mct`
- `assistant`
- `windows_update`
- `preferred_source`
- `force_source`
- `allow_dead_sources`

Source toggles support tri-state interpretation:

- enabled
- disabled
- auto

### 17.5 USB Section

Current keys:

- `create_usb`
- `disk_number`
- `disk_id`
- `keep_iso`
- `partition_style`

### 17.6 Resume Section

Current keys:

- `enabled`
- `checkpoint_path`
- `resume_from_checkpoint`

### 17.7 Source Health Section

Allows explicit health overrides per source ID, for example:

- `healthy`
- `degraded`
- `dead`

### 17.8 Option Resolution Order

Current effective precedence:

1. built-in defaults
2. INI config
3. checkpoint options when resuming
4. current CLI overrides

## 18. Command-Line Interface

### 18.1 Main Script Parameters

Current top-level parameters in [wfu-tool.ps1](C:\Projects\wfu-tool\wfu-tool.ps1):

- `ConfigPath`
- `Mode`
- `Interactive`
- `Headless`
- `TargetVersion`
- `NoReboot`
- `LogPath`
- `DownloadPath`
- `ForceOnlineUpdate`
- `MaxRetries`
- `DirectIso`
- `CreateUsb`
- `UsbDiskNumber`
- `UsbDiskId`
- `KeepIso`
- `UsbPartitionStyle`
- `PreferredSource`
- `ForceSource`
- `AllowDeadSources`
- `CheckpointPath`
- `SessionId`
- `ResumeFromCheckpoint`
- `AllowFallback`
- `SkipBypasses`
- `SkipBlockerRemoval`
- `SkipTelemetry`
- `SkipRepair`
- `SkipCumulativeUpdates`
- `SkipNetworkCheck`
- `SkipDiskCheck`
- `SkipDirectEsd`
- `SkipEsd`
- `SkipFido`
- `SkipMct`
- `SkipAssistant`
- `SkipWindowsUpdate`

### 18.2 Important Behavioral Flags

- `-DirectIso` bypasses intermediate versions and targets the final release directly
- `-AllowFallback` permits alternate methods after ISO failure
- `-NoReboot` suppresses immediate reboot but still prepares resume state
- `-CreateUsb` changes the task from upgrading the current machine to producing USB media
- `-Skip*` flags disable safety or acquisition subflows and should be treated as advanced usage

## 19. Logging and UX

### 19.1 Logging

The tool logs to file and console simultaneously.

Log levels:

- `INFO`
- `WARN`
- `ERROR`
- `SUCCESS`
- `DEBUG`

### 19.2 Phase UX

The console experience tracks active phases with:

- start message
- elapsed time
- success or fail closure

### 19.3 Launcher UX

The launcher includes:

- colored output
- target-family selection
- target-version selection
- toggle menus for options
- system info display

## 20. Testing Surface

The repository includes a broad script-based test suite under [tests](C:\Projects\wfu-tool\tests).

Coverage areas include:

- script parsing
- version detection
- retry logic
- registry helpers
- TLS configuration
- source health
- remote version discovery
- direct metadata
- ESD catalog
- Fido API paths
- bypass methods
- checkpoint handling
- automation config parsing and writing
- resume behavior
- USB planning helpers
- batch passthrough
- legacy media manifest, normalization, discovery, staging, and acquisition

Primary test runner:

- [tests\Test-Runner.ps1](C:\Projects\wfu-tool\tests\Test-Runner.ps1)

Developer utility scripts also exist in [devscripts](C:\Projects\wfu-tool\devscripts).

## 21. Current Constraints and Risks

### 21.1 Administrative Requirement

Most meaningful flows require elevation. The launcher explicitly checks for administrator access.

### 21.2 Windows-Specific Side Effects

The tool intentionally changes:

- registry values
- scheduled tasks
- Windows Update policy state
- telemetry-related settings
- service states
- local routes
- disk contents and USB disks

### 21.3 Endpoint Fragility

Some acquisition paths rely on Microsoft endpoints or pinned legacy URLs that can change or fail over time. The code partly addresses this through:

- source health flags
- retries
- fallbacks
- manual media reuse

### 21.4 Partial-State Interruptions

The engine explicitly warns that cancellation or fatal errors can leave:

- partial bypass state
- partial policy changes
- incomplete downloads
- mounted ISOs
- pending setup artifacts

### 21.5 Legacy Release Practicality

The code contains support scaffolding for very old Windows 10 releases, but some historical source endpoints are already marked dead in the manifest. Support in code should not be interpreted as guaranteed current download availability for every legacy release.

## 22. Acceptance Criteria for the Current Tool

The current implementation can be considered functionally complete against this spec when it:

- detects a supported current Windows release
- resolves a valid target release
- performs configured preflight checks unless skipped
- can select and execute an upgrade path or direct target jump
- can persist and recover state across reboot
- can acquire or reuse installation media through at least one enabled source
- can produce diagnostic output on failure
- can create bootable USB media when run in `CreateUsb` mode with valid disk input

## 23. Suggested Future Documentation Additions

Useful next documents, not currently present in the repository:

- a user-facing README with safe usage guidance
- an operator runbook for headless mode
- a source-matrix document listing each release and supported acquisition paths
- a checkpoint schema reference with examples
- a risk/rollback playbook for interrupted upgrades

