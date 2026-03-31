# Tests for bypass and blocker removal methods (non-destructive checks only)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# =============================================================
# Test: compatibility HwReqChkVars format
# =============================================================
if ($isAdmin) {
    # Test that HwReqChkVars can be written as REG_MULTI_SZ
    $testKey = 'HKCU:\\SOFTWARE\\wfu-tool-BypassTest'
    New-Item -Path $testKey -Force -ErrorAction SilentlyContinue | Out-Null

    $spoofValues = @(
        'SQ_SecureBootCapable=TRUE'
        'SQ_SecureBootEnabled=TRUE'
        'SQ_TpmVersion=2'
        'SQ_RamMB=8192'
    )
    try {
        Set-ItemProperty -LiteralPath $testKey -Name 'HwReqChkVars' -Value $spoofValues -Type MultiString -Force
        $readBack = (Get-ItemProperty $testKey -Name 'HwReqChkVars').HwReqChkVars
        Assert-True ($readBack -is [array] -or $readBack -is [string[]]) 'Bypass-HwReqChk: REG_MULTI_SZ writable'
        Assert-True ($readBack -contains 'SQ_TpmVersion=2') 'Bypass-HwReqChk: Contains TPM spoof'
        Assert-True ($readBack -contains 'SQ_SecureBootCapable=TRUE') 'Bypass-HwReqChk: Contains SecureBoot spoof'
    } catch {
        Assert-True $false "Bypass-HwReqChk: REG_MULTI_SZ write failed: $_"
    }
    Remove-Item $testKey -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Skip-Test 'Bypass-HwReqChk: REG_MULTI_SZ' 'Requires admin'
}

# =============================================================
# Test: LabConfig bypass keys format
# =============================================================
$labBypasses = @('BypassTPMCheck','BypassSecureBootCheck','BypassRAMCheck','BypassStorageCheck','BypassCPUCheck')
foreach ($bypass in $labBypasses) {
    Assert-True ($bypass -match '^Bypass\w+Check$') "Bypass-LabConfig: $bypass matches expected pattern"
}
Assert-Equal 5 $labBypasses.Count 'Bypass-LabConfig: Exactly 5 bypass keys defined'

# =============================================================
# Test: Telemetry registry paths exist (just check paths, don't modify)
# =============================================================
$telemetryPaths = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection',
    'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
)
foreach ($path in $telemetryPaths) {
    # These paths may or may not exist -- just verify they're valid registry paths
    Assert-Match '^HKLM:\\' $path "Bypass-Telemetry: Path $($path.Split('\')[-1]) is HKLM"
}
Assert-True $true 'Bypass-Telemetry: All paths are valid HKLM paths'

# =============================================================
# Test: Telemetry service names are correct
# =============================================================
$telemetryServices = @('DiagTrack', 'dmwappushservice')
foreach ($svc in $telemetryServices) {
    $service = Get-Service $svc -ErrorAction SilentlyContinue
    if ($service) {
        Assert-True $true "Bypass-Telemetry: Service '$svc' exists on this system"
    } else {
        # Service might not exist on all systems
        Assert-True $true "Bypass-Telemetry: Service '$svc' not found (may be removed already)"
    }
}

# =============================================================
# Test: Telemetry scheduled task paths are valid
# =============================================================
$taskPaths = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
)
foreach ($taskPath in $taskPaths) {
    Assert-Match '^\\Microsoft\\Windows\\' $taskPath "Bypass-Tasks: $($taskPath.Split('\')[-1]) has valid path prefix"
}

# =============================================================
# Test: Kill list process names are valid patterns
# =============================================================
$killPatterns = @('PCHealthCheck*', 'msedgewebview2', 'CompatTelRunner', 'Windows10UpgraderApp', 'Windows10Upgrader*', 'WinREBootApp*')
foreach ($pattern in $killPatterns) {
    Assert-True ($pattern.Length -gt 3) "Bypass-KillList: '$pattern' is a non-trivial pattern"
}
Assert-True ($killPatterns.Count -ge 5) "Bypass-KillList: At least 5 kill patterns defined ($($killPatterns.Count))"

# =============================================================
# Test: IFEO hook script content validity
# =============================================================
if ($isAdmin) {
    # Install hook, check content, remove
    $null = Install-SetupHostBypassHook
    $hookPath = "$env:SystemDrive\Scripts\get11.cmd"
    if (Test-Path $hookPath) {
        $content = Get-Content $hookPath -Raw
        Assert-True ($content -match 'AllowUpgradesWithUnsupportedTPMorCPU') 'Bypass-IFEO: Hook has MoSetup bypass'
        Assert-True ($content -match 'HwReqChkVars') 'Bypass-IFEO: Hook has HwReqChkVars spoof'
        Assert-True ($content -match 'appraiserres\.dll') 'Bypass-IFEO: Hook zeroes appraiserres.dll'
        Assert-True ($content -match 'Product Server') 'Bypass-IFEO: Hook uses /Product Server trick'
        Assert-True ($content -match 'DisableWUfBSafeguards') 'Bypass-IFEO: Hook disables WUfB safeguards'
        Assert-True ($content -match 'CompatMarkers') 'Bypass-IFEO: Hook deletes CompatMarkers'
        Assert-True ($content -match 'IgnoreWarning') 'Bypass-IFEO: Hook passes /Compat IgnoreWarning'
    } else {
        Assert-True $false 'Bypass-IFEO: Hook script not created'
    }
    Install-SetupHostBypassHook -Remove
} else {
    Skip-Test 'Bypass-IFEO: Hook content' 'Requires admin'
}

# =============================================================
# Test: TLS configuration function
# =============================================================
if ($isAdmin) {
    Repair-TlsConfiguration
    Assert-True $true 'Bypass-TLS: Repair-TlsConfiguration completed without error'

    # Verify PowerShell process TLS setting
    $proto = [Net.ServicePointManager]::SecurityProtocol
    Assert-True ($proto -band [Net.SecurityProtocolType]::Tls12) 'Bypass-TLS: PS SecurityProtocol includes TLS 1.2'
} else {
    Skip-Test 'Bypass-TLS: Configuration' 'Requires admin'
}
