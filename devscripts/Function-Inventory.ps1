<#
.SYNOPSIS
    Lists all functions across all script files with line numbers and sizes.
#>
$projectRoot = Split-Path $PSScriptRoot -Parent

Write-Host ''
Write-Host '  FUNCTION INVENTORY' -ForegroundColor Cyan
Write-Host '  ==================' -ForegroundColor Cyan
Write-Host ''

$scripts = Get-ChildItem $projectRoot -Filter '*.ps1' -Recurse
$allFunctions = @()

foreach ($script in $scripts) {
    $content = Get-Content $script.FullName
    $rel = $script.FullName.Replace($projectRoot, '').TrimStart('\')

    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match '^function\s+(\S+)') {
            $funcName = $matches[1]
            $startLine = $i + 1

            # Find the end of the function (matching closing brace at same indent)
            $braceCount = 0
            $endLine = $startLine
            for ($j = $i; $j -lt $content.Count; $j++) {
                $braceCount += ([regex]::Matches($content[$j], '\{')).Count
                $braceCount -= ([regex]::Matches($content[$j], '\}')).Count
                if ($braceCount -eq 0 -and $j -gt $i) {
                    $endLine = $j + 1
                    break
                }
            }
            $size = $endLine - $startLine + 1

            $allFunctions += [PSCustomObject]@{
                File     = $rel
                Function = $funcName
                Line     = $startLine
                Size     = $size
            }
        }
    }
}

# Display grouped by file
$grouped = $allFunctions | Group-Object File
foreach ($group in $grouped) {
    Write-Host "  $($group.Name)" -ForegroundColor Yellow
    foreach ($func in $group.Group) {
        $sizeColor = if ($func.Size -gt 100) { 'Cyan' } elseif ($func.Size -gt 50) { 'White' } else { 'DarkGray' }
        Write-Host "    L$("$($func.Line)".PadRight(6))$($func.Function.PadRight(40))$($func.Size) lines" -ForegroundColor $sizeColor
    }
    Write-Host ''
}

Write-Host "  Total: $($allFunctions.Count) functions across $($grouped.Count) files" -ForegroundColor Green
Write-Host ''
