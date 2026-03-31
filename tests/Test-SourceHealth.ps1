function Import-WfuAutomationModule {
    if (-not (Get-Command New-WfuSourceState -ErrorAction SilentlyContinue)) {
        $projectRoot = Split-Path $PSScriptRoot -Parent
        . (Join-Path $projectRoot 'modules\Upgrade\Automation.ps1')
    }
}

Import-WfuAutomationModule

Assert-NotNull (Get-Command New-WfuSourceState -ErrorAction SilentlyContinue) 'SourceHealth: module loaded'

$dead = New-WfuSourceState -SourceId 'MCT' -Health 'dead' -Reason '404'
Assert-Equal 'MCT' $dead.SourceId 'SourceHealth: source id normalized'
Assert-Equal 'dead' $dead.Health 'SourceHealth: dead health preserved'
Assert-True $dead.Selectable 'SourceHealth: dead source remains selectable'
Assert-True (-not $dead.AutoEligible) 'SourceHealth: dead source is not auto-eligible'
Assert-Equal '404' $dead.HealthReason 'SourceHealth: dead reason preserved'

$healthy = New-WfuSourceState -SourceId 'WU_DIRECT' -Health 'healthy'
Assert-True $healthy.AutoEligible 'SourceHealth: healthy source is auto-eligible'

$healthMap = @{
    WU_DIRECT = 'healthy'
    FIDO = 'degraded'
    MCT = 'dead'
    LEGACY_CAB = 'healthy'
}

$ordered = Get-WfuOrderedSourceIds -DefaultOrder @('MCT','LEGACY_CAB','WU_DIRECT','FIDO') -HealthMap $healthMap
Assert-True (-not ($ordered -contains 'MCT')) 'SourceHealth: dead sources skipped from auto order'
Assert-Equal 'LEGACY_CAB' $ordered[0] 'SourceHealth: healthy sources keep order'
Assert-True ($ordered -contains 'WU_DIRECT') 'SourceHealth: healthy source retained'

$preferred = Get-WfuOrderedSourceIds -DefaultOrder @('WU_DIRECT','LEGACY_CAB','FIDO') -PreferredSource 'FIDO' -HealthMap $healthMap
Assert-Equal 'FIDO' $preferred[0] 'SourceHealth: preferred source moved to front'

$forced = Get-WfuOrderedSourceIds -DefaultOrder @('WU_DIRECT','LEGACY_CAB','FIDO') -ForceSource 'MCT' -HealthMap $healthMap
Assert-Equal 1 @($forced).Count 'SourceHealth: force source collapses to single choice'
Assert-Equal 'MCT' @($forced)[0] 'SourceHealth: force source wins over health'

$deadPreferred = Get-WfuOrderedSourceIds -DefaultOrder @('WU_DIRECT','LEGACY_CAB') -PreferredSource 'MCT' -HealthMap $healthMap -AllowDeadSources
Assert-Equal 'MCT' $deadPreferred[0] 'SourceHealth: dead preferred source can be explicitly selected'

$health = Get-WfuSourceHealth -SourceId 'LEGACY_CAB' -HealthMap $healthMap
Assert-Equal 'healthy' $health 'SourceHealth: source health lookup returns configured state'

$families = Get-WfuTargetFamilies -AvailableTargets @('W10_1507','W10_22H2','21H2','23H2','24H2')
Assert-Equal 2 $families['Windows 10'].Count 'SourceHealth: Windows 10 family contains legacy targets'
Assert-Equal 3 $families['Windows 11'].Count 'SourceHealth: Windows 11 family contains modern targets'
