# Tests for Write-Log function

$testLog = Join-Path $env:TEMP 'WFU_TOOL_LogTest.log'
Remove-Item $testLog -Force -ErrorAction SilentlyContinue

# Override LogPath for testing
$Script:LogPath = $testLog

# -- Basic logging --
Write-Log 'Test message INFO'
Write-Log 'Test message WARN' -Level WARN
Write-Log 'Test message ERROR' -Level ERROR
Write-Log 'Test message SUCCESS' -Level SUCCESS
Write-Log 'Test message DEBUG' -Level DEBUG

Assert-True (Test-Path $testLog) 'WriteLog: Log file created'

$logContent = Get-Content $testLog -Raw
Assert-True ($logContent -match '\[INFO\] Test message INFO') 'WriteLog: INFO message logged'
Assert-True ($logContent -match '\[WARN\] Test message WARN') 'WriteLog: WARN message logged'
Assert-True ($logContent -match '\[ERROR\] Test message ERROR') 'WriteLog: ERROR message logged'
Assert-True ($logContent -match '\[SUCCESS\] Test message SUCCESS') 'WriteLog: SUCCESS message logged'
Assert-True ($logContent -match '\[DEBUG\] Test message DEBUG') 'WriteLog: DEBUG message logged'

# -- Timestamp format --
Assert-Match '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]' $logContent 'WriteLog: Timestamp format correct'

# -- Error tracking --
$errCountBefore = $Script:ErrorLog.Count
Write-Log 'Error for tracking' -Level ERROR
Assert-True ($Script:ErrorLog.Count -gt $errCountBefore) 'WriteLog: ERROR level adds to ErrorLog'

# Cleanup
Remove-Item $testLog -Force -ErrorAction SilentlyContinue
