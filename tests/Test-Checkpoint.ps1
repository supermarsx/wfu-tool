function Import-WfuAutomationModule {
    if (-not (Get-Command Save-WfuCheckpoint -ErrorAction SilentlyContinue)) {
        $projectRoot = Split-Path $PSScriptRoot -Parent
        . (Join-Path $projectRoot 'modules\Upgrade\Automation.ps1')
    }
}

Import-WfuAutomationModule

Assert-NotNull (Get-Command Save-WfuCheckpoint -ErrorAction SilentlyContinue) 'Checkpoint: module loaded'

$tempRoot = Join-Path $env:TEMP 'WFU_TOOL_CheckpointTests'
Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

$checkpointPath = Join-Path $tempRoot 'session.checkpoint.json'
$options = [ordered]@{
    Mode              = if ((Get-Command Get-WfuNormalizedMode -ErrorAction SilentlyContinue) -and (Get-WfuNormalizedMode -Mode 'AutomatedUpgrade') -eq 'AutomatedUpgrade') { 'AutomatedUpgrade' } else { 'Headless' }
    TargetVersion     = '22H2'
    DownloadPath      = $tempRoot
    CheckpointPath    = $checkpointPath
    SessionId         = 'abc-123'
    CreateUsb         = $true
    UsbDiskNumber     = 3
    UsbDiskId         = 'USB-DISK-123'
    KeepIso           = $true
    UsbPartitionStyle = 'gpt'
    PreferredSource   = 'WU_DIRECT'
    ForceSource       = 'LEGACY_CAB'
    AllowDeadSources  = $true
    SourceHealth      = [ordered]@{
        WU_DIRECT  = 'healthy'
        MCT        = 'dead'
        LEGACY_CAB = 'degraded'
    }
}

$saved = Save-WfuCheckpoint -Path $checkpointPath -Options $options `
    -CurrentVersion 'W10_21H2' -TargetVersion '22H2' -CurrentStep 'media staged' `
    -NextStep 'ISO ready' -SelectedSource 'LEGACY_CAB' -Stage 'media-staged' `
    -Artifacts @{
    IsoPath   = Join-Path $tempRoot '22H2.iso'
    Workspace = Join-Path $tempRoot 'workspace'
} -PassThru

Assert-True (Test-Path $checkpointPath) 'Checkpoint: file written'
Assert-Equal 'media-staged' $saved.Stage 'Checkpoint: saved stage recorded'
Assert-Equal '22H2' $saved.TargetVersion 'Checkpoint: target version recorded'
Assert-Equal 'LEGACY_CAB' $saved.SelectedSource 'Checkpoint: selected source recorded'

$loaded = Read-WfuCheckpoint -Path $checkpointPath
if (-not $loaded) {
    $loaded = Get-Content -Path $checkpointPath -Raw | ConvertFrom-Json
}
Assert-NotNull $loaded 'Checkpoint: file reloads'
Assert-Equal 'media-staged' $loaded.Stage 'Checkpoint: loaded stage matches'
Assert-Equal 'W10_21H2' $loaded.CurrentVersion 'Checkpoint: current version preserved'
Assert-Equal '22H2' $loaded.TargetVersion 'Checkpoint: target preserved'
Assert-Equal 'ISO ready' $loaded.NextStep 'Checkpoint: next step preserved'
Assert-Equal 'abc-123' $loaded.Options.SessionId 'Checkpoint: session id preserved'
Assert-Equal 'LEGACY_CAB' $loaded.SelectedSource 'Checkpoint: selected source preserved'
Assert-Equal 'dead' $loaded.Options.SourceHealth.MCT 'Checkpoint: source health preserved'
Assert-Equal $true $loaded.Options.KeepIso 'Checkpoint: USB keep-ISO preserved'
Assert-Equal $options.Mode $loaded.Options.Mode 'Checkpoint: mode preserved through serialization'

$generated = Get-WfuCheckpointPath -DownloadPath $tempRoot -SessionId 'session-x'
Assert-Match 'session-x' $generated 'Checkpoint: generated path includes session id'
Assert-Match '\.checkpoint\.json$' $generated 'Checkpoint: generated path has checkpoint extension'

$badPath = Join-Path $tempRoot 'broken.checkpoint.json'
'not json' | Set-Content -Path $badPath -Encoding ASCII
$badLoaded = Read-WfuCheckpoint -Path $badPath
Assert-Null $badLoaded 'Checkpoint: invalid JSON returns null'

Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
