function Get-WfuSourceIds {
    [CmdletBinding()]
    param()

    [ordered]@{
        DirectMetadata = 'WU_DIRECT'
        ESD            = 'ESD_CATALOG'
        Fido           = 'FIDO'
        MCT            = 'MCT'
        Assistant      = 'ASSISTANT'
        WindowsUpdate  = 'WINDOWS_UPDATE'
        LegacyXml      = 'LEGACY_XML'
        LegacyCab      = 'LEGACY_CAB'
        LegacyMctX64   = 'LEGACY_MCT_X64'
        LegacyMctX86   = 'LEGACY_MCT_X86'
    }
}

function Get-WfuDefaultOptions {
    [CmdletBinding()]
    param()

    [ordered]@{
        Mode              = 'Interactive'
        TargetVersion     = '25H2'
        LogPath           = $null
        DownloadPath      = 'C:\wfu-tool'
        NoReboot          = $false
        DirectIso         = $false
        AllowFallback     = $false
        ForceOnlineUpdate = $false
        MaxRetries        = 2
        SkipBypasses      = $false
        SkipBlockerRemoval = $false
        SkipTelemetry     = $false
        SkipRepair        = $false
        SkipCumulativeUpdates = $false
        SkipNetworkCheck  = $false
        SkipDiskCheck     = $false
        SkipDirectEsd     = $false
        SkipEsd           = $false
        SkipFido          = $false
        SkipMct           = $false
        SkipAssistant     = $false
        SkipWindowsUpdate = $false
        CreateUsb         = $false
        UsbDiskNumber     = $null
        UsbDiskId         = $null
        KeepIso           = $false
        UsbPartitionStyle = 'gpt'
        PreferredSource   = $null
        ForceSource       = $null
        AllowDeadSources  = $false
        CheckpointPath    = $null
        SessionId         = $null
        ResumeFromCheckpoint = $false
        ResumeEnabled     = $true
        DiscardCachedMedia = $false
        SourceHealth      = [ordered]@{}
    }
}

function Get-WfuIniSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$IniData,

        [Parameter(Mandatory)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if ($IniData.Contains($name)) {
            return $IniData[$name]
        }
    }

    return [ordered]@{}
}

function ConvertTo-WfuBoolean {
    param(
        [AllowNull()]
        $Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return $Value }

    $text = ([string]$Value).Trim().ToLowerInvariant()
    switch ($text) {
        '1' { return $true }
        'true' { return $true }
        'yes' { return $true }
        'on' { return $true }
        'enabled' { return $true }
        '0' { return $false }
        'false' { return $false }
        'no' { return $false }
        'off' { return $false }
        'disabled' { return $false }
        default { return $Default }
    }
}

function ConvertTo-WfuTriState {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return 'auto' }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -in @('true','1','yes','on','enabled')) { return 'enabled' }
    if ($text -in @('false','0','no','off','disabled')) { return 'disabled' }
    return 'auto'
}

function Read-WfuIniFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Config file not found: $Path"
    }

    $result = [ordered]@{}
    $section = 'global'
    $result[$section] = [ordered]@{}

    foreach ($rawLine in (Get-Content -Path $Path)) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith(';') -or $line.StartsWith('#')) {
            continue
        }

        if ($line -match '^\[(.+)\]$') {
            $section = $matches[1].Trim().ToLowerInvariant()
            if (-not $result.Contains($section)) {
                $result[$section] = [ordered]@{}
            }
            continue
        }

        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { continue }

        $key = $line.Substring(0, $idx).Trim().ToLowerInvariant()
        $value = $line.Substring($idx + 1).Trim()
        $result[$section][$key] = $value
    }

    return $result
}

function ConvertFrom-WfuIniOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$IniData
    )

    $options = Get-WfuDefaultOptions
    # Older configs sometimes stored keys at the root. Keep those readable by
    # falling back to the synthetic global section when a named section is absent.
    $general = Get-WfuIniSection -IniData $IniData -Names @('general', 'global')
    $checks = Get-WfuIniSection -IniData $IniData -Names @('checks')
    $sources = Get-WfuIniSection -IniData $IniData -Names @('sources')
    $usb = Get-WfuIniSection -IniData $IniData -Names @('usb')
    $resume = Get-WfuIniSection -IniData $IniData -Names @('resume')
    $sourceHealth = Get-WfuIniSection -IniData $IniData -Names @('source_health')

    if ($general['mode']) { $options.Mode = (Get-WfuNormalizedMode -Mode $general['mode']) }
    if ($general['target_version']) { $options.TargetVersion = $general['target_version'] }
    if ($general['log_path']) { $options.LogPath = $general['log_path'] }
    if ($general['download_path']) { $options.DownloadPath = $general['download_path'] }
    $options.NoReboot = ConvertTo-WfuBoolean $general['no_reboot'] $options.NoReboot
    $options.DirectIso = ConvertTo-WfuBoolean $general['direct_iso'] $options.DirectIso
    $options.AllowFallback = ConvertTo-WfuBoolean $general['allow_fallback'] $options.AllowFallback
    $options.ForceOnlineUpdate = ConvertTo-WfuBoolean $general['force_online_update'] $options.ForceOnlineUpdate

    $options.SkipBypasses = -not (ConvertTo-WfuBoolean $checks['bypasses'] $true)
    $options.SkipBlockerRemoval = -not (ConvertTo-WfuBoolean $checks['blocker_removal'] $true)
    $options.SkipTelemetry = -not (ConvertTo-WfuBoolean $checks['telemetry'] $true)
    $options.SkipRepair = -not (ConvertTo-WfuBoolean $checks['repair'] $false)
    $options.SkipCumulativeUpdates = -not (ConvertTo-WfuBoolean $checks['cumulative_updates'] $true)
    $options.SkipNetworkCheck = -not (ConvertTo-WfuBoolean $checks['network_check'] $true)
    $options.SkipDiskCheck = -not (ConvertTo-WfuBoolean $checks['disk_check'] $true)

    $options.SkipDirectEsd = (ConvertTo-WfuTriState $sources['direct_esd']) -eq 'disabled'
    $options.SkipEsd = (ConvertTo-WfuTriState $sources['esd']) -eq 'disabled'
    $options.SkipFido = (ConvertTo-WfuTriState $sources['fido']) -eq 'disabled'
    $options.SkipMct = (ConvertTo-WfuTriState $sources['mct']) -eq 'disabled'
    $options.SkipAssistant = (ConvertTo-WfuTriState $sources['assistant']) -eq 'disabled'
    $options.SkipWindowsUpdate = (ConvertTo-WfuTriState $sources['windows_update']) -eq 'disabled'
    if ($sources['preferred_source']) { $options.PreferredSource = $sources['preferred_source'].ToUpperInvariant() }
    if ($sources['force_source']) { $options.ForceSource = $sources['force_source'].ToUpperInvariant() }
    $options.AllowDeadSources = ConvertTo-WfuBoolean $sources['allow_dead_sources'] $options.AllowDeadSources

    $options.CreateUsb = ConvertTo-WfuBoolean $usb['create_usb'] $options.CreateUsb
    if ($usb['disk_number'] -match '^\d+$') { $options.UsbDiskNumber = [int]$usb['disk_number'] }
    if ($usb['disk_id']) { $options.UsbDiskId = $usb['disk_id'] }
    $options.KeepIso = ConvertTo-WfuBoolean $usb['keep_iso'] $options.KeepIso
    if ($usb['partition_style']) { $options.UsbPartitionStyle = $usb['partition_style'].ToLowerInvariant() }

    $options.ResumeEnabled = ConvertTo-WfuBoolean $resume['enabled'] $options.ResumeEnabled
    if ($resume['checkpoint_path']) { $options.CheckpointPath = $resume['checkpoint_path'] }
    $options.ResumeFromCheckpoint = ConvertTo-WfuBoolean $resume['resume_from_checkpoint'] $options.ResumeFromCheckpoint

    foreach ($key in $sourceHealth.Keys) {
        $options.SourceHealth[$key.ToUpperInvariant()] = ([string]$sourceHealth[$key]).ToLowerInvariant()
    }

    return $options
}

function Merge-WfuOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Base,

        [Parameter(Mandatory)]
        [hashtable]$Override
    )

    $merged = [ordered]@{}
    foreach ($key in $Base.Keys) {
        $merged[$key] = $Base[$key]
    }

    foreach ($key in $Override.Keys) {
        if ($key -eq 'SourceHealth') {
            $health = [ordered]@{}
            if ($merged[$key]) {
                foreach ($healthKey in $merged[$key].Keys) { $health[$healthKey] = $merged[$key][$healthKey] }
            }
            if ($Override[$key]) {
                foreach ($healthKey in $Override[$key].Keys) { $health[$healthKey] = $Override[$key][$healthKey] }
            }
            $merged[$key] = $health
            continue
        }

        if ($null -ne $Override[$key]) {
            $merged[$key] = $Override[$key]
        }
    }

    return $merged
}

function Get-WfuNormalizedMode {
    [CmdletBinding()]
    param([string]$Mode)

    if (-not $Mode) { return 'Interactive' }

    $normalized = ($Mode -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    switch ($normalized) {
        'interactive' { return 'Interactive' }
        'isodownload' { return 'IsoDownload' }
        'usbfromiso' { return 'UsbFromIso' }
        'automatedupgrade' { return 'AutomatedUpgrade' }
        'resume' { return 'Resume' }
        'headless' { return 'AutomatedUpgrade' }
        'createusb' { return 'UsbFromIso' }
        default { return 'Interactive' }
    }
}

function Get-WfuCheckpointPath {
    [CmdletBinding()]
    param(
        [string]$CheckpointPath,
        [string]$DownloadPath,
        [string]$SessionId
    )

    if ($CheckpointPath) { return $CheckpointPath }
    $root = if ($DownloadPath) { $DownloadPath } else { 'C:\wfu-tool' }
    if (-not $SessionId) { $SessionId = [guid]::NewGuid().ToString() }
    return (Join-Path $root "session-$SessionId.checkpoint.json")
}

function ConvertTo-WfuJsonCompatibleObject {
    param($InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string] -or $InputObject -is [int] -or $InputObject -is [bool] -or $InputObject -is [double]) {
        return $InputObject
    }
    if ($InputObject -is [hashtable] -or $InputObject -is [System.Collections.Specialized.OrderedDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $copy[$key] = ConvertTo-WfuJsonCompatibleObject $InputObject[$key]
        }
        return $copy
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) { $items += @(ConvertTo-WfuJsonCompatibleObject $item) }
        return $items
    }
    if ($InputObject.PSObject) {
        $copy = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $copy[$property.Name] = ConvertTo-WfuJsonCompatibleObject $property.Value
        }
        return $copy
    }
    return $InputObject
}

function Save-WfuCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [hashtable]$Options,

        [string]$CurrentVersion,
        [string]$TargetVersion,
        [string]$CurrentStep,
        [string]$NextStep,
        [string]$SelectedSource,
        [string]$Stage = 'initialized',
        [hashtable]$Artifacts,
        [switch]$PassThru
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $payload = [ordered]@{
        SavedAt        = (Get-Date).ToString('o')
        Stage          = $Stage
        CurrentVersion = $CurrentVersion
        TargetVersion  = $TargetVersion
        CurrentStep    = $CurrentStep
        NextStep       = $NextStep
        SelectedSource = $SelectedSource
        Options        = ConvertTo-WfuJsonCompatibleObject $Options
        Artifacts      = ConvertTo-WfuJsonCompatibleObject $(if ($Artifacts) { $Artifacts } else { [ordered]@{} })
    }

    $json = $payload | ConvertTo-Json -Depth 10
    Set-Content -Path $Path -Value $json -Encoding UTF8

    if ($PassThru) { return $payload }
}

function Read-WfuCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) { return $null }
    try {
        return (Get-Content -Path $Path -Raw | ConvertFrom-Json -AsHashtable)
    } catch {
        return $null
    }
}

function Get-WfuSourceHealth {
    [CmdletBinding()]
    param(
        [string]$SourceId,
        [hashtable]$HealthMap
    )

    if (-not $SourceId) { return 'unknown' }
    $normalized = $SourceId.ToUpperInvariant()
    if ($HealthMap -and $HealthMap.Contains($normalized)) {
        return ([string]$HealthMap[$normalized]).ToLowerInvariant()
    }
    return 'healthy'
}

function New-WfuSourceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceId,
        [string]$Health = 'healthy',
        [string]$Reason = ''
    )

    $normalizedHealth = $Health.ToLowerInvariant()
    [pscustomobject]@{
        SourceId     = $SourceId.ToUpperInvariant()
        Health       = $normalizedHealth
        Selectable   = $true
        AutoEligible = ($normalizedHealth -ne 'dead')
        HealthReason = $Reason
    }
}

function Get-WfuOrderedSourceIds {
    [CmdletBinding()]
    param(
        [string[]]$DefaultOrder,
        [string]$PreferredSource,
        [string]$ForceSource,
        [hashtable]$HealthMap,
        [switch]$AllowDeadSources,
        [switch]$IncludeDeadInAutoOrder
    )

    if ($ForceSource) {
        return @($ForceSource.ToUpperInvariant())
    }

    $ordered = @()
    foreach ($id in $DefaultOrder) {
        if (-not $id) { continue }
        $normalized = $id.ToUpperInvariant()
        $health = Get-WfuSourceHealth -SourceId $normalized -HealthMap $HealthMap
        if (-not $IncludeDeadInAutoOrder -and $health -eq 'dead') {
            continue
        }
        $ordered += $normalized
    }

    if ($PreferredSource) {
        $preferred = $PreferredSource.ToUpperInvariant()
        if ($ordered -contains $preferred) {
            $ordered = @($preferred) + @($ordered | Where-Object { $_ -ne $preferred })
        } elseif ($AllowDeadSources -and (Get-WfuSourceHealth -SourceId $preferred -HealthMap $HealthMap) -eq 'dead') {
            $ordered = @($preferred) + $ordered
        }
    }

    return @($ordered | Select-Object -Unique)
}

function ConvertTo-WfuCliOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$BoundParameters,
        [Parameter(Mandatory)]
        [hashtable]$CurrentValues
    )

    $cli = [ordered]@{}
    foreach ($key in $BoundParameters.Keys) {
        if ($key -eq 'ConfigPath') { continue }
        if ($key -eq 'Interactive' -or $key -eq 'Headless') { continue }
        $cli[$key] = $CurrentValues[$key]
    }

    if ($BoundParameters.Contains('Headless') -and $CurrentValues['Headless']) {
        $cli['Mode'] = 'AutomatedUpgrade'
    } elseif (($BoundParameters.Contains('CreateUsb') -and $CurrentValues['CreateUsb']) -and -not $cli.Contains('Mode')) {
        $cli['Mode'] = 'UsbFromIso'
    } elseif ($BoundParameters.Contains('Interactive') -and $CurrentValues['Interactive']) {
        $cli['Mode'] = 'Interactive'
    }

    return $cli
}

function Resolve-WfuModeOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Options
    )

    $resolved = [ordered]@{}
    foreach ($key in $Options.Keys) {
        $resolved[$key] = $Options[$key]
    }

    $mode = Get-WfuNormalizedMode -Mode $resolved['Mode']
    if ($mode -eq 'Interactive') {
        if ($resolved.Contains('Headless') -and (ConvertTo-WfuBoolean $resolved['Headless'] $false)) {
            $mode = 'AutomatedUpgrade'
        } elseif ($resolved.Contains('CreateUsb') -and (ConvertTo-WfuBoolean $resolved['CreateUsb'] $false)) {
            $mode = 'UsbFromIso'
        }
    }

    $resolved['Mode'] = $mode

    switch ($mode) {
        'AutomatedUpgrade' {
            $resolved['CreateUsb'] = $false
            if ($resolved.Contains('Headless')) { $resolved['Headless'] = $false }
        }
        'UsbFromIso' {
            $resolved['CreateUsb'] = $true
            $resolved['DirectIso'] = $true
            if ($resolved.Contains('Headless')) { $resolved['Headless'] = $false }
        }
        'IsoDownload' {
            $resolved['CreateUsb'] = $false
            $resolved['DirectIso'] = $true
            if ($resolved.Contains('Headless')) { $resolved['Headless'] = $false }
        }
        default {
            if ($resolved.Contains('Headless')) { $resolved['Headless'] = $false }
        }
    }

    return $resolved
}

function New-WfuResolvedOptions {
    [CmdletBinding()]
    param(
        [string]$ConfigPath,
        [hashtable]$CliOptions
    )

    $defaults = Get-WfuDefaultOptions
    if (-not $defaults.LogPath) {
        $defaults.LogPath = Join-Path $PSScriptRoot '..\..\wfu-tool.log'
    }

    $merged = $defaults
    if ($ConfigPath) {
        $ini = Read-WfuIniFile -Path $ConfigPath
        $merged = Merge-WfuOptions -Base $merged -Override (ConvertFrom-WfuIniOptions -IniData $ini)
    }
    if ($CliOptions) {
        $merged = Merge-WfuOptions -Base $merged -Override $CliOptions
    }

    $merged = Resolve-WfuModeOptions -Options $merged
    $merged.Mode = Get-WfuNormalizedMode -Mode $merged.Mode
    if (-not $merged.SessionId) { $merged.SessionId = [guid]::NewGuid().ToString() }
    if (-not $merged.LogPath) { $merged.LogPath = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'wfu-tool.log' }
    $merged.CheckpointPath = Get-WfuCheckpointPath -CheckpointPath $merged.CheckpointPath -DownloadPath $merged.DownloadPath -SessionId $merged.SessionId

    if ($merged.Mode -eq 'UsbFromIso') {
        $merged.CreateUsb = $true
        if (-not $merged.DirectIso) { $merged.DirectIso = $true }
    } elseif ($merged.Mode -eq 'IsoDownload') {
        $merged.CreateUsb = $false
        $merged.DirectIso = $true
    } elseif ($merged.Mode -eq 'AutomatedUpgrade') {
        if ($merged.Contains('Headless')) { $merged.Headless = $true }
        $merged.CreateUsb = $false
    }

    return $merged
}

function Test-WfuHeadlessRequirements {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Options
    )

    return @(Test-WfuModeRequirements -Options $Options)
}

function Test-WfuModeRequirements {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Options
    )

    $errors = @()
    $mode = Get-WfuNormalizedMode -Mode $Options.Mode

    if ($mode -in @('IsoDownload', 'UsbFromIso', 'AutomatedUpgrade') -and -not $Options.TargetVersion) {
        $errors += "$mode mode requires a target version."
    }
    if (($mode -eq 'UsbFromIso' -or $Options.CreateUsb) -and $null -eq $Options.UsbDiskNumber -and [string]::IsNullOrWhiteSpace($Options.UsbDiskId)) {
        $errors += 'USB creation requires UsbDiskNumber or UsbDiskId.'
    }
    return @($errors)
}

function Get-WfuVersionFamily {
    [CmdletBinding()]
    param([string]$Version)

    if ($Version -like 'W10_*') { return 'Windows 10' }
    return 'Windows 11'
}

function Get-WfuTargetFamilies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$AvailableTargets
    )

    $win10 = @($AvailableTargets | Where-Object { $_ -like 'W10_*' })
    $win11 = @($AvailableTargets | Where-Object { $_ -notlike 'W10_*' })
    [ordered]@{
        'Windows 10' = $win10
        'Windows 11' = $win11
    }
}

function ConvertTo-WfuIniBoolean {
    param([bool]$Value)

    return $Value.ToString().ToLowerInvariant()
}

function ConvertTo-WfuIniLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Options
    )

    $sourceIds = Get-WfuSourceIds
    $sourceHealth = if ($Options.Contains('SourceHealth') -and $Options.SourceHealth) { $Options.SourceHealth } else { [ordered]@{} }

    $sections = [ordered]@{
        general = [ordered]@{
            mode = ([string]$Options.Mode).ToLowerInvariant()
            target_version = $Options.TargetVersion
            log_path = $Options.LogPath
            download_path = $Options.DownloadPath
            no_reboot = ConvertTo-WfuIniBoolean ([bool]$Options.NoReboot)
            direct_iso = ConvertTo-WfuIniBoolean ([bool]$Options.DirectIso)
            allow_fallback = ConvertTo-WfuIniBoolean ([bool]$Options.AllowFallback)
            force_online_update = ConvertTo-WfuIniBoolean ([bool]$Options.ForceOnlineUpdate)
        }
        checks = [ordered]@{
            bypasses = ConvertTo-WfuIniBoolean ([bool](-not $Options.SkipBypasses))
            blocker_removal = ConvertTo-WfuIniBoolean ([bool](-not $Options.SkipBlockerRemoval))
            telemetry = ConvertTo-WfuIniBoolean ([bool](-not $Options.SkipTelemetry))
            repair = ConvertTo-WfuIniBoolean ([bool](-not $Options.SkipRepair))
            cumulative_updates = ConvertTo-WfuIniBoolean ([bool](-not $Options.SkipCumulativeUpdates))
            network_check = ConvertTo-WfuIniBoolean ([bool](-not $Options.SkipNetworkCheck))
            disk_check = ConvertTo-WfuIniBoolean ([bool](-not $Options.SkipDiskCheck))
        }
        sources = [ordered]@{
            direct_esd = if ($Options.SkipDirectEsd) { 'disabled' } else { 'auto' }
            esd = if ($Options.SkipEsd) { 'disabled' } else { 'auto' }
            fido = if ($Options.SkipFido) { 'disabled' } else { 'auto' }
            mct = if ($Options.SkipMct) { 'disabled' } else { 'auto' }
            assistant = if ($Options.SkipAssistant) { 'disabled' } else { 'auto' }
            windows_update = if ($Options.SkipWindowsUpdate) { 'disabled' } else { 'auto' }
            preferred_source = $Options.PreferredSource
            force_source = $Options.ForceSource
            allow_dead_sources = ConvertTo-WfuIniBoolean ([bool]$Options.AllowDeadSources)
        }
        usb = [ordered]@{
            create_usb = ConvertTo-WfuIniBoolean ([bool]$Options.CreateUsb)
            disk_number = if ($null -ne $Options.UsbDiskNumber) { [string]$Options.UsbDiskNumber } else { '' }
            disk_id = $Options.UsbDiskId
            keep_iso = ConvertTo-WfuIniBoolean ([bool]$Options.KeepIso)
            partition_style = $Options.UsbPartitionStyle
        }
        resume = [ordered]@{
            enabled = ConvertTo-WfuIniBoolean ([bool]$Options.ResumeEnabled)
            checkpoint_path = $Options.CheckpointPath
            resume_from_checkpoint = ConvertTo-WfuIniBoolean ([bool]$Options.ResumeFromCheckpoint)
        }
        source_health = [ordered]@{}
    }

    foreach ($id in @(
        $sourceIds.DirectMetadata,
        $sourceIds.ESD,
        $sourceIds.Fido,
        $sourceIds.MCT,
        $sourceIds.Assistant,
        $sourceIds.WindowsUpdate,
        $sourceIds.LegacyXml,
        $sourceIds.LegacyCab,
        $sourceIds.LegacyMctX64,
        $sourceIds.LegacyMctX86
    )) {
        if ($sourceHealth.Contains($id)) {
            $sections.source_health[$id] = $sourceHealth[$id]
        }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($sectionName in $sections.Keys) {
        [void]$lines.Add("[$sectionName]")
        foreach ($key in $sections[$sectionName].Keys) {
            $value = $sections[$sectionName][$key]
            if ($null -eq $value) { $value = '' }
            [void]$lines.Add("$key=$value")
        }
        [void]$lines.Add('')
    }

    return @($lines)
}

function ConvertTo-WfuIniTemplateLines {
    [CmdletBinding()]
    param(
        [string]$Mode = 'Interactive'
    )

    $normalizedMode = Get-WfuNormalizedMode -Mode $Mode

    return @(
        '[general]'
        "mode=$($normalizedMode.ToLowerInvariant())"
        '; target_version='
        '; log_path='
        '; download_path='
        ''
        '[checks]'
        '; bypasses='
        '; blocker_removal='
        '; telemetry='
        '; repair='
        '; cumulative_updates='
        '; network_check='
        '; disk_check='
        ''
        '[sources]'
        '; direct_esd='
        '; esd='
        '; fido='
        '; mct='
        '; assistant='
        '; windows_update='
        '; preferred_source='
        '; force_source='
        '; allow_dead_sources='
        ''
        '[usb]'
        '; create_usb='
        '; disk_number='
        '; disk_id='
        '; keep_iso='
        '; partition_style='
        ''
        '[resume]'
        '; enabled='
        '; checkpoint_path='
        '; resume_from_checkpoint='
        ''
    )
}

function Save-WfuIniConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [hashtable]$Options
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $lines = ConvertTo-WfuIniLines -Options $Options
    Set-Content -Path $Path -Value $lines -Encoding UTF8
    return $Path
}

function Save-WfuDefaultIniTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Mode = 'Interactive'
    )

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $lines = ConvertTo-WfuIniTemplateLines -Mode $Mode
    Set-Content -Path $Path -Value $lines -Encoding UTF8
    return $Path
}
