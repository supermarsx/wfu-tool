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
Assert-True ($preferred1507.Count -ge 2) 'Legacy sources: W10_1507 x64 has at least two preferred sources'
if ($preferred1507.Count -ge 2) {
    Assert-Equal 'XML' $preferred1507[0].Kind 'Legacy sources: W10_1507 x64 prefers catalog XML first'
    Assert-Equal 'MCTEXE' $preferred1507[1].Kind 'Legacy sources: W10_1507 x64 prefers MCT second'
    Assert-Equal 'x64' $preferred1507[1].Architecture 'Legacy sources: W10_1507 x64 MCT source is x64'
    Assert-Match 'MediaCreationTool.*\.exe$' $preferred1507[1].FileName 'Legacy sources: W10_1507 MCT filename looks correct'
}

$preferred1607 = @(Get-LegacyMediaPreferredSources -Version 'W10_1607' -Architecture 'x64')
Assert-True ($preferred1607.Count -ge 2) 'Legacy sources: W10_1607 x64 has at least two preferred sources'
if ($preferred1607.Count -ge 2) {
    Assert-Equal 'CAB' $preferred1607[0].Kind 'Legacy sources: W10_1607 x64 prefers CAB first'
    Assert-Equal 'MCTEXE' $preferred1607[1].Kind 'Legacy sources: W10_1607 x64 prefers MCT second'
    Assert-Match 'Products_20170116\.cab$|products_20170116\.cab$' $preferred1607[0].FileName 'Legacy sources: W10_1607 CAB filename looks correct'
}

$preferred1507X86 = @(Get-LegacyMediaPreferredSources -Version 'W10_1507' -Architecture 'x86')
Assert-True ($preferred1507X86.Count -ge 2) 'Legacy sources: W10_1507 x86 has at least two preferred sources'
if ($preferred1507X86.Count -ge 2) {
    Assert-True ($preferred1507X86[0].Kind -in @('MCTEXE','XML')) 'Legacy sources: W10_1507 x86 selects a usable first source'
    $x86MctSources = @($preferred1507X86 | Where-Object { $_.Kind -eq 'MCTEXE' -and $_.Architecture -eq 'x86' })
    Assert-True ($x86MctSources.Count -ge 1) 'Legacy sources: W10_1507 x86 exposes an x86 MCT source'
}

$resolved = Resolve-LegacyMediaSource -Version 'W10_1507' -Architecture 'x64' -Mode 'Preferred'
Assert-NotNull $resolved 'Legacy sources: preferred source resolves'
if ($resolved) {
    Assert-Equal 'XML' $resolved.Kind 'Legacy sources: resolved preferred source is XML'
    Assert-Equal 'W10_1507' $resolved.Version 'Legacy sources: resolved preferred source version matches'
}

$allSources = @(Resolve-LegacyMediaSource -Version 'W10_1507' -Architecture 'x64' -Mode 'All')
Assert-True ($allSources.Count -ge 2) 'Legacy sources: all-mode resolves multiple source descriptors'

$plan = Get-LegacyMediaDownloadPlan -Version 'W10_1507' -Architecture 'x64'
Assert-NotNull $plan 'Legacy sources: download plan exists'
if ($plan) {
    Assert-Equal 'W10_1507' $plan.Version 'Legacy sources: plan version matches'
    Assert-Equal '1507' $plan.DisplayVersion 'Legacy sources: plan display version matches'
    Assert-Equal 10240 $plan.Build 'Legacy sources: plan build matches'
    Assert-Equal 'Windows 10' $plan.OS 'Legacy sources: plan OS matches'
    Assert-Equal 'x64' $plan.Architecture 'Legacy sources: plan architecture matches'
    Assert-True ($plan.Sources.Count -ge 2) 'Legacy sources: plan contains multiple staged sources'
    Assert-Equal $preferred1507[0].Kind $plan.Sources[0].Kind 'Legacy sources: plan preserves preferred order'
}
