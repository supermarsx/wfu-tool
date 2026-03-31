$batPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'launch-wfu-tool.bat'
Assert-True (Test-Path $batPath) 'BatchPassthrough: launcher batch file exists'

$content = Get-Content -Path $batPath -Raw
Assert-Match '%\*' $content 'BatchPassthrough: batch file preserves raw argument passthrough'
Assert-Match 'launch-wfu-tool\.ps1' $content 'BatchPassthrough: batch file still invokes PowerShell launcher'
Assert-Match 'ShellExecute|runas|elevat' $content 'BatchPassthrough: batch file still supports elevation relay'
