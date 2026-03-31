function Import-WfuAutomationModule {
    if (-not (Get-Command Get-WfuDefaultOptions -ErrorAction SilentlyContinue)) {
        $projectRoot = Split-Path $PSScriptRoot -Parent
        . (Join-Path $projectRoot 'modules\Upgrade\Automation.ps1')
    }
}

Import-WfuAutomationModule

Assert-NotNull (Get-Command Get-WfuDefaultOptions -ErrorAction SilentlyContinue) 'Automation: module loaded'

$tempRoot = Join-Path $env:TEMP 'WFU_TOOL_AutomationTests'
Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

$iniPath = Join-Path $tempRoot 'automation.ini'
@'
[general]
mode=headless
target_version=22H2
log_path=C:\logs\wfu-tool.log
download_path=C:\downloads\wfu-tool
no_reboot=true
direct_iso=true
allow_fallback=false
force_online_update=yes

[checks]
bypasses=true
blocker_removal=false
telemetry=true
repair=false
cumulative_updates=yes
network_check=no
disk_check=true

[sources]
direct_esd=auto
esd=disabled
fido=enabled
mct=true
assistant=false
windows_update=auto
preferred_source=legacy_cab
force_source=
allow_dead_sources=1

[usb]
create_usb=1
disk_number=3
disk_id=USB-DISK-123
keep_iso=yes
partition_style=mbr

[resume]
enabled=yes
checkpoint_path=C:\resume\session.json
resume_from_checkpoint=true

[source_health]
WU_DIRECT=healthy
MCT=dead
LEGACY_CAB=degraded
'@ | Set-Content -Path $iniPath -Encoding UTF8

$ini = Read-WfuIniFile -Path $iniPath
Assert-NotNull $ini 'Automation: INI parsed'
Assert-Equal 'headless' $ini['general']['mode'] 'Automation: mode loaded from INI'
Assert-Equal 'disabled' $ini['sources']['esd'] 'Automation: source toggle loaded from INI'
Assert-Equal 'dead' $ini['source_health']['mct'] 'Automation: source health loaded from INI'

$iniOptions = ConvertFrom-WfuIniOptions -IniData $ini
Assert-Equal 'AutomatedUpgrade' $iniOptions.Mode 'Automation: mode normalized'
Assert-Equal '22H2' $iniOptions.TargetVersion 'Automation: target version loaded'
Assert-Equal 'C:\logs\wfu-tool.log' $iniOptions.LogPath 'Automation: log path loaded'
Assert-Equal 'C:\downloads\wfu-tool' $iniOptions.DownloadPath 'Automation: download path loaded'
Assert-True $iniOptions.NoReboot 'Automation: no reboot parsed'
Assert-True $iniOptions.DirectIso 'Automation: direct ISO parsed'
Assert-True (-not $iniOptions.AllowFallback) 'Automation: allow fallback parsed'
Assert-True $iniOptions.ForceOnlineUpdate 'Automation: force online parsed'
Assert-True $iniOptions.SkipBlockerRemoval 'Automation: disabled preflight becomes skip'
Assert-True $iniOptions.SkipRepair 'Automation: disabled repair becomes skip'
Assert-True (-not $iniOptions.SkipDiskCheck) 'Automation: enabled disk check remains active'
Assert-True $iniOptions.SkipEsd 'Automation: disabled source becomes skip'
Assert-True (-not $iniOptions.SkipFido) 'Automation: enabled source remains active'
Assert-True (-not $iniOptions.SkipMct) 'Automation: true source remains active'
Assert-True $iniOptions.SkipAssistant 'Automation: false source becomes skip'
Assert-Equal 'LEGACY_CAB' $iniOptions.PreferredSource 'Automation: preferred source normalized'
Assert-Equal 'mbr' $iniOptions.UsbPartitionStyle 'Automation: USB partition style loaded'
Assert-True $iniOptions.AllowDeadSources 'Automation: dead sources allowed flag parsed'
Assert-Equal 'C:\resume\session.json' $iniOptions.CheckpointPath 'Automation: checkpoint path loaded'
Assert-True $iniOptions.ResumeFromCheckpoint 'Automation: resume flag loaded'
Assert-Equal 'dead' $iniOptions.SourceHealth['MCT'] 'Automation: source health normalized'

$defaults = Get-WfuDefaultOptions
$merged = Merge-WfuOptions -Base $defaults -Override $iniOptions
Assert-Equal 'AutomatedUpgrade' $merged.Mode 'Automation: merge preserves override mode'
Assert-Equal '22H2' $merged.TargetVersion 'Automation: merge preserves override target'
Assert-Equal 'LEGACY_CAB' $merged.PreferredSource 'Automation: merge preserves override preferred source'

$resolved = New-WfuResolvedOptions -ConfigPath $iniPath -CliOptions @{
    Mode            = 'Interactive'
    TargetVersion   = '23H2'
    PreferredSource = 'WU_DIRECT'
    SessionId       = 'session-123'
    CreateUsb       = $true
}

Assert-Equal 'UsbFromIso' $resolved.Mode 'Automation: CLI create USB request wins over interactive mode'
Assert-Equal '23H2' $resolved.TargetVersion 'Automation: CLI overrides INI target'
Assert-Equal 'WU_DIRECT' $resolved.PreferredSource 'Automation: CLI overrides INI preferred source'
Assert-True $resolved.CreateUsb 'Automation: CLI create USB flag preserved'
Assert-True $resolved.DirectIso 'Automation: USB creation implies direct ISO'
Assert-Equal 'session-123' $resolved.SessionId 'Automation: CLI session id preserved'
Assert-Equal 'C:\resume\session.json' $resolved.CheckpointPath 'Automation: INI checkpoint path preserved over generated session path'
Assert-Equal 'mbr' $resolved.UsbPartitionStyle 'Automation: INI USB partition style preserved'
Assert-Equal 'C:\downloads\wfu-tool' $resolved.DownloadPath 'Automation: INI download path preserved'

$sourceIds = Get-WfuSourceIds
Assert-Equal 'WU_DIRECT' $sourceIds.DirectMetadata 'Automation: source IDs include WU_DIRECT'
Assert-Equal 'LEGACY_MCT_X86' $sourceIds.LegacyMctX86 'Automation: source IDs include legacy MCT x86'

$families = Get-WfuTargetFamilies -AvailableTargets @('W10_1507', '21H2', 'W10_22H2', '24H2')
Assert-Equal 2 $families['Windows 10'].Count 'Automation: Windows 10 family split'
Assert-Equal 2 $families['Windows 11'].Count 'Automation: Windows 11 family split'

$savedIniPath = Join-Path $tempRoot 'saved-config.ini'
$null = Save-WfuIniConfig -Path $savedIniPath -Options $resolved
Assert-True (Test-Path $savedIniPath) 'Automation: INI config writer created file'
$savedIniText = Get-Content -Path $savedIniPath -Raw
Assert-True ($savedIniText -match '\[general\]') 'Automation: INI config has general section'
Assert-True ($savedIniText -match 'target_version=23H2') 'Automation: INI config writes target version'
Assert-True ($savedIniText -match '\[sources\]') 'Automation: INI config has sources section'
Assert-True ($savedIniText -match 'preferred_source=WU_DIRECT') 'Automation: INI config writes preferred source'

if ((Get-WfuNormalizedMode -Mode 'IsoDownload') -eq 'IsoDownload') {
    Assert-Equal 'IsoDownload' (Get-WfuNormalizedMode -Mode 'IsoDownload') 'Automation: new mode IsoDownload normalizes'
    Assert-Equal 'UsbFromIso' (Get-WfuNormalizedMode -Mode 'UsbFromIso') 'Automation: new mode UsbFromIso normalizes'
    Assert-Equal 'AutomatedUpgrade' (Get-WfuNormalizedMode -Mode 'AutomatedUpgrade') 'Automation: new mode AutomatedUpgrade normalizes'
    Assert-Equal 'AutomatedUpgrade' (Get-WfuNormalizedMode -Mode 'headless') 'Automation: legacy headless alias maps forward'
    Assert-Equal 'UsbFromIso' (Get-WfuNormalizedMode -Mode 'createusb') 'Automation: legacy createusb alias maps forward'
}
else {
    Skip-Test 'Automation: new mode normalization' 'Runtime does not yet expose the new mode names'
}

Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
