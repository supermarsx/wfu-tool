<#
.SYNOPSIS
    Validates that legacy Windows 10 releases expose a coherent media acquisition path.
#>

Write-Host '    (Legacy acquisition tests use local legacy manifest helpers)' -ForegroundColor DarkGray

$legacyVersions = @(
    'W10_1507',
    'W10_1607',
    'W10_1903',
    'W10_20H2',
    'W10_21H2',
    'W10_22H2'
)

foreach ($version in $legacyVersions) {
    $spec = Get-LegacyMediaSpec -Version $version
    Assert-NotNull $spec "LegacyAcquire[$version]: manifest spec exists"
    if (-not $spec) { continue }

    $sources = Get-LegacyMediaSourceDescriptors -Version $version
    Assert-NotNull $sources "LegacyAcquire[$version]: source descriptors exist"
    if (-not $sources) { continue }

    if ($sources -isnot [System.Collections.IEnumerable] -or $sources -is [string]) {
        $sources = @($sources)
    }

    Assert-True ($sources.Count -ge 1) "LegacyAcquire[$version]: has at least one acquisition source"

    $catalogSource = $sources | Where-Object { $_.Kind -in @('CAB', 'XML') } | Select-Object -First 1
    $mctSource = $sources | Where-Object { $_.Kind -eq 'MCTEXE' } | Select-Object -First 1

    if ($catalogSource) {
        Assert-Match '^https://' $catalogSource.Url "LegacyAcquire[$version]: catalog source uses HTTPS"
        Assert-True ($catalogSource.Architecture -in @('neutral', 'x64')) "LegacyAcquire[$version]: catalog source has normalized architecture"
    }

    if ($mctSource) {
        Assert-Match '^https://' $mctSource.Url "LegacyAcquire[$version]: MCT source uses HTTPS"
        Assert-True ($mctSource.Kind -eq 'MCTEXE') "LegacyAcquire[$version]: MCT source is normalized"
    }

    $planCmd = Get-Command 'New-LegacyMctFallbackPlan' -ErrorAction SilentlyContinue
    if ($planCmd) {
        $plan = New-LegacyMctFallbackPlan -Version $version
        Assert-NotNull $plan "LegacyAcquire[$version]: MCT fallback plan exists"
        if ($plan) {
            Assert-NotNull $plan.CommandLine "LegacyAcquire[$version]: MCT plan has command line"
            Assert-NotNull $plan.WorkingDirectory "LegacyAcquire[$version]: MCT plan has working directory"
            Assert-True ($plan.OutputIsoPath -match "\\$version\.iso$") "LegacyAcquire[$version]: output ISO path is versioned"
            if ($version -in @('W10_1507', 'W10_1511', 'W10_1607', 'W10_1703', 'W10_1709', 'W10_1803', 'W10_1809')) {
                Assert-True ($plan.SupportsMediaEdition -eq $false) "LegacyAcquire[$version]: old releases do not force MediaEdition arg"
            }
        }
    }
    else {
        Skip-Test "LegacyAcquire[$version]: MCT fallback plan" 'Helper not surfaced in the current session'
    }
}
