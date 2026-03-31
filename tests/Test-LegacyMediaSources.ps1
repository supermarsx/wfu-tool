<#
.SYNOPSIS
    Validates legacy Windows 10 source selection and download-plan metadata.
#>

$expectedVersions = @(
    'W10_1507', 'W10_1511', 'W10_1607', 'W10_1703', 'W10_1709',
    'W10_1803', 'W10_1809', 'W10_1903', 'W10_1909', 'W10_2004',
    'W10_20H2', 'W10_21H1', 'W10_21H2', 'W10_22H2'
)

$versions = @(Get-LegacyMediaVersions)
Assert-Equal $expectedVersions.Count $versions.Count 'Legacy sources: version count'
Assert-Equal $expectedVersions[0] $versions[0] 'Legacy sources: first version is W10_1507'
Assert-Equal $expectedVersions[-1] $versions[-1] 'Legacy sources: last version is W10_22H2'

$manifest1507 = Get-LegacyMediaSpec -Version 'W10_1507'
Assert-NotNull $manifest1507 'Legacy sources: W10_1507 manifest entry exists'
if ($manifest1507) {
    Assert-Equal 'XML' $manifest1507.CatalogKind 'Legacy sources: W10_1507 catalog is XML'
    Assert-Equal '1507' $manifest1507.DisplayVersion 'Legacy sources: W10_1507 display version'
    Assert-True ($manifest1507.SupportsMediaEditionArg -eq $false) 'Legacy sources: W10_1507 omits MediaEdition'
}

$preferred1507 = @(Get-LegacyMediaPreferredSources -Version 'W10_1507' -Architecture 'x64')
$allPreferred1507 = @(Get-LegacyMediaPreferredSources -Version 'W10_1507' -Architecture 'x64' -IncludeDead)
Assert-True ($preferred1507.Count -ge 1) 'Legacy sources: W10_1507 x64 has at least one auto-eligible preferred source'
Assert-True ($allPreferred1507.Count -ge 2) 'Legacy sources: W10_1507 x64 exposes dead and live sources when requested'
if ($allPreferred1507.Count -ge 2) {
    $deadCatalog1507 = @($allPreferred1507 | Where-Object { $_.Health -eq 'dead' -and $_.Kind -in @('XML', 'CAB') })
    Assert-True ($deadCatalog1507.Count -ge 1) 'Legacy sources: W10_1507 x64 keeps dead catalog sources selectable'
}
if ($preferred1507.Count -ge 1) {
    Assert-True ($preferred1507[0].Health -ne 'dead') 'Legacy sources: W10_1507 x64 auto ordering excludes dead sources'
    Assert-Equal 'MCTEXE' $preferred1507[0].Kind 'Legacy sources: W10_1507 x64 prefers the live launcher source first'
    Assert-Equal 'x64' $preferred1507[0].Architecture 'Legacy sources: W10_1507 x64 first source architecture'
    Assert-Match 'MediaCreationTool.*\.exe$' $preferred1507[0].FileName 'Legacy sources: W10_1507 x64 first source filename looks correct'
}

$preferred1607 = @(Get-LegacyMediaPreferredSources -Version 'W10_1607' -Architecture 'x64')
$allPreferred1607 = @(Get-LegacyMediaPreferredSources -Version 'W10_1607' -Architecture 'x64' -IncludeDead)
Assert-True ($preferred1607.Count -ge 1) 'Legacy sources: W10_1607 x64 has at least one auto-eligible preferred source'
Assert-True ($allPreferred1607.Count -ge 2) 'Legacy sources: W10_1607 x64 exposes dead and live sources when requested'
if ($preferred1607.Count -ge 1) {
    Assert-True ($preferred1607[0].Health -ne 'dead') 'Legacy sources: W10_1607 x64 auto ordering excludes dead sources'
    Assert-Equal 'MCTEXE' $preferred1607[0].Kind 'Legacy sources: W10_1607 x64 prefers the live launcher source first'
    Assert-Match 'MediaCreationTool.*\.exe$' $preferred1607[0].FileName 'Legacy sources: W10_1607 x64 first source filename looks correct'
}

$preferred1507X86 = @(Get-LegacyMediaPreferredSources -Version 'W10_1507' -Architecture 'x86')
$allPreferred1507X86 = @(Get-LegacyMediaPreferredSources -Version 'W10_1507' -Architecture 'x86' -IncludeDead)
Assert-True ($preferred1507X86.Count -ge 1) 'Legacy sources: W10_1507 x86 has at least one auto-eligible preferred source'
Assert-True ($allPreferred1507X86.Count -ge 2) 'Legacy sources: W10_1507 x86 exposes dead and live sources when requested'
if ($preferred1507X86.Count -ge 1) {
    Assert-True ($preferred1507X86[0].Kind -in @('MCTEXE', 'XML')) 'Legacy sources: W10_1507 x86 selects a usable first source'
    Assert-True ($preferred1507X86[0].Health -ne 'dead') 'Legacy sources: W10_1507 x86 auto ordering excludes dead sources'
    $x86MctSources = @($allPreferred1507X86 | Where-Object { $_.Kind -eq 'MCTEXE' -and $_.Architecture -eq 'x86' })
    Assert-True ($x86MctSources.Count -ge 1) 'Legacy sources: W10_1507 x86 exposes an x86 MCT source when requested'
}

$resolved = Resolve-LegacyMediaSource -Version 'W10_1507' -Architecture 'x64' -Mode 'Preferred'
Assert-NotNull $resolved 'Legacy sources: preferred source resolves'
if ($resolved) {
    Assert-Equal 'W10_1507' $resolved.Version 'Legacy sources: resolved preferred source version matches'
    Assert-True ($resolved.Health -ne 'dead') 'Legacy sources: resolved preferred source is auto-eligible'
}

$allSources = @(Resolve-LegacyMediaSource -Version 'W10_1507' -Architecture 'x64' -Mode 'All')
Assert-True ($allSources.Count -ge 1) 'Legacy sources: all-mode resolves source descriptors'

$plan = Get-LegacyMediaDownloadPlan -Version 'W10_1507' -Architecture 'x64'
Assert-NotNull $plan 'Legacy sources: download plan exists'
if ($plan) {
    Assert-Equal 'W10_1507' $plan.Version 'Legacy sources: plan version matches'
    Assert-Equal '1507' $plan.DisplayVersion 'Legacy sources: plan display version matches'
    Assert-Equal 10240 $plan.Build 'Legacy sources: plan build matches'
    Assert-Equal 'Windows 10' $plan.OS 'Legacy sources: plan OS matches'
    Assert-Equal 'x64' $plan.Architecture 'Legacy sources: plan architecture matches'
    Assert-True ($plan.Sources.Count -ge 1) 'Legacy sources: plan contains at least one staged source'
    Assert-True ($plan.Sources[0].Health -ne 'dead') 'Legacy sources: plan excludes dead sources from auto staging'
    Assert-Equal $preferred1507[0].Kind $plan.Sources[0].Kind 'Legacy sources: plan preserves preferred order'
}
