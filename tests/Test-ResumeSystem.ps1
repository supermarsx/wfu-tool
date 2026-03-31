# Tests for Set-ResumeAfterReboot and Clear-ResumeAfterReboot

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Skip-Test 'Resume: Set resume state' 'Requires admin privileges'
    Skip-Test 'Resume: Registry state saved' 'Requires admin privileges'
    Skip-Test 'Resume: Clear resume state' 'Requires admin privileges'
} else {
    $regKey = 'HKLM:\SOFTWARE\wfu-tool'
    $taskName = 'wfu-tool-resume'

    # Clean any leftover
    Clear-ResumeAfterReboot

    # Set resume
    Set-ResumeAfterReboot -NextTarget '25H2'

    # Verify registry state
    Assert-True (Test-Path $regKey) 'Resume: Registry key created'
    if (Test-Path $regKey) {
        $tv = Get-RegValue $regKey 'TargetVersion'
        Assert-NotNull $tv 'Resume: TargetVersion saved'
        $sr = Get-RegValue $regKey 'ScriptRoot'
        Assert-NotNull $sr 'Resume: ScriptRoot saved'
    }

    # Check scheduled task or RunOnce was registered
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $runOnce = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'wfu-tool'
    Assert-True ($task -or $runOnce) 'Resume: Scheduled task or RunOnce registered'

    # Clear
    Clear-ResumeAfterReboot
    Assert-True (-not (Test-Path $regKey)) 'Resume: Registry key removed after clear'

    $taskAfter = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $runOnceAfter = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'wfu-tool'
    Assert-True (-not $taskAfter -and -not $runOnceAfter) 'Resume: Task and RunOnce removed after clear'
}
