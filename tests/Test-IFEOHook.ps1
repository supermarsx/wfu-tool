# Tests for Install-SetupHostBypassHook (install and remove)

$ifeoBase = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\SetupHost.exe'
$hookScript = "$env:SystemDrive\Scripts\get11.cmd"

# Check if we have admin rights (needed for HKLM writes)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Skip-Test 'IFEO: Install hook' 'Requires admin privileges'
    Skip-Test 'IFEO: Hook script exists' 'Requires admin privileges'
    Skip-Test 'IFEO: Registry entries set' 'Requires admin privileges'
    Skip-Test 'IFEO: Remove hook' 'Requires admin privileges'
    Skip-Test 'IFEO: Cleanup complete' 'Requires admin privileges'
}
else {
    # Clean any leftover from previous runs
    Install-SetupHostBypassHook -Remove

    # Install
    $result = Install-SetupHostBypassHook
    Assert-True ($result -eq $true) 'IFEO: Install hook returns true'

    # Verify hook script
    Assert-True (Test-Path $hookScript) 'IFEO: Hook script exists at expected path'
    if (Test-Path $hookScript) {
        $content = Get-Content $hookScript -Raw
        Assert-True ($content -match 'AllowUpgradesWithUnsupportedTPMorCPU') 'IFEO: Hook script contains MoSetup bypass'
        Assert-True ($content -match 'HwReqChkVars') 'IFEO: Hook script contains HwReqChkVars spoof'
        Assert-True ($content -match 'appraiserres') 'IFEO: Hook script zeroes appraiserres.dll'
        Assert-True ($content -match '/Product Server') 'IFEO: Hook script uses /Product Server trick'
    }

    # Verify registry
    Assert-True (Test-Path $ifeoBase) 'IFEO: SetupHost.exe key exists'
    if (Test-Path $ifeoBase) {
        $useFilter = Get-RegValue $ifeoBase 'UseFilter'
        Assert-Equal 1 $useFilter 'IFEO: UseFilter is 1'

        $filterKey = Join-Path $ifeoBase '0'
        if (Test-Path $filterKey) {
            $debugger = Get-RegValue $filterKey 'Debugger'
            Assert-True ($debugger -match 'get11\.cmd') 'IFEO: Debugger points to get11.cmd'
            $filterPath = Get-RegValue $filterKey 'FilterFullPath'
            Assert-True ($filterPath -match 'WINDOWS\.~BT.*SetupHost\.exe') 'IFEO: FilterFullPath targets BT sources'
        }
    }

    # Remove
    Install-SetupHostBypassHook -Remove
    Assert-True (-not (Test-Path $ifeoBase)) 'IFEO: Registry key removed after uninstall'
    Assert-True (-not (Test-Path $hookScript)) 'IFEO: Hook script removed after uninstall'
}
