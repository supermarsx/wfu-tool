# Tests that all script files parse without errors (syntax validation)

$projectRoot = Split-Path $PSScriptRoot -Parent
$scripts = @(
    'wfu-tool.ps1',
    'launch-wfu-tool.ps1',
    'resume-wfu-tool.ps1',
    'modules\Upgrade\LegacyMedia.ps1',
    'tests\Test-LegacyMediaAcquisition.ps1'
)

foreach ($script in $scripts) {
    $path = Join-Path $projectRoot $script
    if (-not (Test-Path $path)) {
        Assert-True $false "Parse[$script]: File exists"
        continue
    }

    $errors = $null
    $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)

    Assert-Equal 0 $errors.Count "Parse[$script]: Zero parse errors"

    if ($errors.Count -gt 0) {
        foreach ($err in $errors) {
            Write-Host "      Line $($err.Extent.StartLineNumber): $($err.Message)" -ForegroundColor Red
        }
    }

    # Check no non-ASCII characters (encoding safety)
    $content = Get-Content $path -Raw
    $nonAscii = [regex]::Matches($content, '[^\x00-\x7F]')
    Assert-Equal 0 $nonAscii.Count "Parse[$script]: No non-ASCII characters (found $($nonAscii.Count))"

    # Check line count is reasonable
    $lineCount = (Get-Content $path).Count
    Assert-True ($lineCount -gt 50) "Parse[$script]: Has $lineCount lines (> 50)"
}

# Check bat file exists and has content
$batPath = Join-Path $projectRoot 'launch-wfu-tool.bat'
Assert-True (Test-Path $batPath) 'Parse[launch-wfu-tool.bat]: File exists'
$batLines = (Get-Content $batPath).Count
Assert-True ($batLines -gt 10) "Parse[launch-wfu-tool.bat]: Has $batLines lines"
