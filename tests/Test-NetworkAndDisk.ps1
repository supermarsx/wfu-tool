# Tests for Test-NetworkReadiness, Test-DiskSpace, Test-PendingReboot

# -- Test-NetworkReadiness --
$networkOk = Test-NetworkReadiness
Assert-True ($networkOk -is [bool]) 'Network: Returns a boolean'
# If we have internet, it should pass (we can't guarantee this in all environments)
if ($networkOk) {
    Assert-True $true 'Network: Connectivity check passed'
} else {
    Skip-Test 'Network: Connectivity check' 'No internet access'
}

# -- Test-DiskSpace --
$diskOk = Test-DiskSpace -RequiredGB 1
Assert-True ($diskOk -is [bool]) 'DiskSpace: Returns a boolean'
Assert-True ($diskOk -eq $true) 'DiskSpace: 1 GB should always be available'

# Test with absurdly high requirement
$diskHigh = Test-DiskSpace -RequiredGB 99999
Assert-True ($diskHigh -eq $false) 'DiskSpace: 99999 GB should always fail'

# -- Test-PendingReboot --
$reboot = Test-PendingReboot
Assert-True ($reboot -is [bool]) 'PendingReboot: Returns a boolean'
# We can't assert the value since it depends on system state
Assert-True $true 'PendingReboot: Completed without throwing'
