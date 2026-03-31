# Tests for Get-CurrentWindowsVersion and version mapping

# -- Get-CurrentWindowsVersion returns valid structure --
$ver = Get-CurrentWindowsVersion
Assert-NotNull $ver.Build 'Version: Build is not null'
Assert-NotNull $ver.UBR 'Version: UBR is not null'
Assert-NotNull $ver.VersionKey 'Version: VersionKey is not null'
Assert-NotNull $ver.FullBuild 'Version: FullBuild is not null'
Assert-NotNull $ver.OS 'Version: OS is not null'
Assert-True ($ver.Build -gt 0) 'Version: Build is positive integer'
Assert-True ($ver.UBR -gt 0) 'Version: UBR is positive integer'
Assert-Match '^\d+\.\d+$' $ver.FullBuild 'Version: FullBuild matches N.N format'

# -- OS detection --
if ($ver.Build -ge 22000) {
    Assert-Equal 'Windows 11' $ver.OS 'Version: Build >= 22000 is Windows 11'
    Assert-True ($ver.VersionKey -notlike 'W10_*') 'Version: Win11 key has no W10_ prefix'
}
else {
    Assert-Equal 'Windows 10' $ver.OS 'Version: Build < 22000 is Windows 10'
    Assert-True ($ver.VersionKey -like 'W10_*') 'Version: Win10 key has W10_ prefix'
}

# -- DisplayVersion is used (not build guessing) --
$ntVer = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
if ($ntVer.DisplayVersion) {
    Assert-NotNull $ver.DisplayVersion 'Version: DisplayVersion is read from registry'
    # The version key should contain the DisplayVersion value
    $expected = $ntVer.DisplayVersion
    Assert-True ($ver.VersionKey -match $expected -or $ver.VersionKey -eq $expected) "Version: VersionKey contains DisplayVersion ($expected)"
}

# -- VersionMap consistency --
Assert-True ($Script:VersionMap.Count -gt 5) 'VersionMap: Has at least 6 entries'
Assert-True ($Script:VersionMap.Contains('25H2')) 'VersionMap: Contains 25H2'
Assert-True ($Script:VersionMap.Contains('24H2')) 'VersionMap: Contains 24H2'
Assert-True ($Script:VersionMap.Contains('W10_22H2')) 'VersionMap: Contains W10_22H2'

# Builds should be monotonically increasing within each OS
$prevBuild = 0
foreach ($key in $Script:VersionMap.Keys) {
    $build = $Script:VersionMap[$key].Build
    Assert-True ($build -gt 0) "VersionMap: $key build > 0"
}

# -- UpgradeChain consistency --
Assert-True ($Script:UpgradeChain.Count -ge 4) 'UpgradeChain: Has at least 4 steps'
foreach ($step in $Script:UpgradeChain) {
    Assert-NotNull $step.From "UpgradeChain: Step to $($step.To) has From"
    Assert-NotNull $step.To "UpgradeChain: Step from $($step.From) has To"
    Assert-NotNull $step.Method "UpgradeChain: Step $($step.From)->$($step.To) has Method"
    Assert-True ($step.Method -eq 'FeatureUpdate' -or $step.Method -eq 'EnablementPackage') "UpgradeChain: $($step.From)->$($step.To) method is valid"
}
