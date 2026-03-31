<#
.SYNOPSIS
    Validates legacy Windows 10 source staging metadata and download bookkeeping.
#>

$tempRoot = Join-Path $env:TEMP ("WFU_TOOL_LegacyStage_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

$script:LegacyInvokeWebRequestCount = 0
function Invoke-WebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [string]$OutFile,

        [switch]$UseBasicParsing
    )

    $script:LegacyInvokeWebRequestCount++
    if ($OutFile) {
        $payload = "downloaded from $Uri"
        Set-Content -Path $OutFile -Value $payload -Encoding ASCII -Force
    }

    [pscustomobject]@{
        StatusCode = 200
        Headers    = @{ 'Content-Length' = if ($OutFile -and (Test-Path $OutFile)) { (Get-Item $OutFile).Length } else { 0 } }
    }
}

try {
    $firstPass = @(Invoke-LegacyMediaDownload -Version 'W10_1507' -TargetDirectory $tempRoot -Architecture 'x64')
    $stage = $firstPass | Where-Object {
        $_.PSObject.Properties.Name -contains 'Items' -and $_.PSObject.Properties.Name -contains 'TargetDirectory'
    } | Select-Object -Last 1

    Assert-NotNull $stage 'Legacy staging: stage result exists'
    if ($stage) {
        Assert-Equal 'W10_1507' $stage.Version 'Legacy staging: version matches'
        Assert-Equal '1507' $stage.DisplayVersion 'Legacy staging: display version matches'
        Assert-Equal 10240 $stage.Build 'Legacy staging: build matches'
        Assert-Equal 'Windows 10' $stage.OS 'Legacy staging: OS matches'
        Assert-Equal 'x64' $stage.Architecture 'Legacy staging: architecture matches'
        Assert-True ($stage.Items.Count -ge 1) 'Legacy staging: staged at least one item'
        $downloadedItems = @($stage.Items | Where-Object { $_.Downloaded })
        Assert-True ($downloadedItems.Count -ge 1) 'Legacy staging: download helper was invoked'

        foreach ($item in $stage.Items) {
            Assert-NotNull $item.FilePath "Legacy staging: item file path exists for $($item.Kind)"
            Assert-True (Test-Path $item.FilePath) "Legacy staging: file exists for $($item.Kind)"
            Assert-True ($item.Downloaded -eq $true) "Legacy staging: item marked downloaded for $($item.Kind)"
            Assert-True ($item.Skipped -eq $false) "Legacy staging: item not skipped on first pass for $($item.Kind)"
            Assert-NotNull $item.SourceUrl "Legacy staging: item has source URL for $($item.Kind)"
        }

        $stagedFiles = @($stage.Items | ForEach-Object { Split-Path $_.FilePath -Leaf })
        Assert-True ($stagedFiles.Count -ge 1) 'Legacy staging: staged file list populated'
        if ($stagedFiles -contains 'Products09232015_2.xml') {
            Assert-True $true 'Legacy staging: XML catalog staged when selected'
        }
        else {
            Assert-True ($stage.Items[0].Kind -eq 'MCTEXE') 'Legacy staging: live MCT source staged when XML catalog is dead'
        }
    }

    $script:LegacyInvokeWebRequestCount = 0
    $secondPass = @(Invoke-LegacyMediaDownload -Version 'W10_1507' -TargetDirectory $tempRoot -Architecture 'x64')
    $stageAgain = $secondPass | Where-Object {
        $_.PSObject.Properties.Name -contains 'Items' -and $_.PSObject.Properties.Name -contains 'TargetDirectory'
    } | Select-Object -Last 1

    Assert-NotNull $stageAgain 'Legacy staging: second stage result exists'
    if ($stageAgain) {
        Assert-True ($script:LegacyInvokeWebRequestCount -eq 0) 'Legacy staging: existing files are reused without re-download'
        $skippedItems = @($stageAgain.Items | Where-Object { $_.Skipped })
        Assert-True ($skippedItems.Count -ge 1) 'Legacy staging: second pass marks items skipped'
    }
}
finally {
    Remove-Item function:Invoke-WebRequest -Force -ErrorAction SilentlyContinue
    Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
