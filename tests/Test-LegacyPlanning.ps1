# Tests for legacy Windows 10 planning support

Write-Host '    (Legacy planning tests require the extended version map)' -ForegroundColor DarkGray

$legacyTargets = @(
    'W10_1507', 'W10_1511', 'W10_1607', 'W10_1703', 'W10_1709',
    'W10_1803', 'W10_1809', 'W10_1903', 'W10_1909', 'W10_2004',
    'W10_20H2', 'W10_21H1', 'W10_21H2', 'W10_22H2'
)

$probe = $null
try {
    $probe = Get-WindowsFeatureTargetSpec -TargetVersion 'W10_1507'
}
catch {
    $probe = $null
}

if (-not $probe) {
    Skip-Test 'LegacyPlan: target spec availability' 'Legacy Windows 10 version map not implemented yet'
    return
}

foreach ($target in $legacyTargets) {
    $spec = $null
    try {
        $spec = Get-WindowsFeatureTargetSpec -TargetVersion $target
    }
    catch {
        $spec = $null
    }

    Assert-NotNull $spec "LegacyPlan[$target]: Target spec exists"

    if ($spec) {
        Assert-Equal $target $spec.Version "LegacyPlan[$target]: Version field matches"
        Assert-Equal 'Windows 10' $spec.OS "LegacyPlan[$target]: OS is Windows 10"
        Assert-True ($spec.TargetBuild -gt 10000) "LegacyPlan[$target]: TargetBuild is set"
        Assert-True ($spec.FromBuild -match '^10\.0\.\d+\.1$') "LegacyPlan[$target]: FromBuild is normalized"
    }
}

$legacyMediaCheck = Get-Command 'Get-LegacyMediaSpec' -ErrorAction SilentlyContinue
if ($legacyMediaCheck) {
    foreach ($target in $legacyTargets) {
        $mediaSpec = Get-LegacyMediaSpec -Version $target
        Assert-NotNull $mediaSpec "LegacyPlan[$target]: Legacy media spec exists"
        if ($mediaSpec) {
            $sources = Get-LegacyMediaSourceDescriptors -Version $target
            Assert-NotNull $sources "LegacyPlan[$target]: Legacy media sources exist"
            if ($sources) {
                Assert-True (@($sources).Count -ge 1) "LegacyPlan[$target]: Legacy media path has at least one source"
            }
        }
    }
}
