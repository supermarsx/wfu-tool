function Import-WfuAutomationModule {
    if (-not (Get-Command Get-WfuDefaultOptions -ErrorAction SilentlyContinue)) {
        $projectRoot = Split-Path $PSScriptRoot -Parent
        . (Join-Path $projectRoot 'modules\Upgrade\Automation.ps1')
    }
}

Import-WfuAutomationModule

$projectRoot = Split-Path $PSScriptRoot -Parent
$mediaToolsPath = Join-Path $projectRoot 'modules\Upgrade\MediaTools.ps1'
if (Test-Path $mediaToolsPath) {
    . $mediaToolsPath
}

function Get-UsbPlanningCommand {
    $candidates = @(
        'New-WfuUsbDiskpartScript',
        'Resolve-WfuUsbMediaPlan',
        'Write-WfuUsbMedia',
        'Resolve-UsbDiskTarget',
        'Get-UsbDiskTarget',
        'New-UsbWritePlan',
        'Get-UsbWritePlan',
        'New-WfuUsbWritePlan',
        'Get-WfuUsbWritePlan',
        'New-UsbPartitionScript',
        'Get-UsbPartitionScript',
        'Start-UsbMediaCreation',
        'Invoke-UsbMediaCreation',
        'New-UsbMediaPlan',
        'Get-UsbMediaPlan'
    )

    foreach ($candidate in $candidates) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd }
    }

    return $null
}

$usbCmd = Get-UsbPlanningCommand
if (-not $usbCmd) {
    Skip-Test 'USB planning helpers' 'USB helper functions are not surfaced yet'
    return
}

$commandName = $usbCmd.Name
Assert-NotNull $usbCmd "USB planning: command located ($commandName)"

$commonArgs = @{}
$paramNames = @($usbCmd.Parameters.Keys)
if ($paramNames -contains 'Options') {
    $commonArgs['Options'] = [ordered]@{
        CreateUsb = $true
        KeepIso = $true
        UsbDiskNumber = 3
        UsbDiskId = 'USB-DISK-123'
        UsbPartitionStyle = 'gpt'
        Mode = if ((Get-Command Get-WfuNormalizedMode -ErrorAction SilentlyContinue) -and (Get-WfuNormalizedMode -Mode 'UsbFromIso') -eq 'UsbFromIso') { 'UsbFromIso' } else { 'CreateUsb' }
    }
}
if ($paramNames -contains 'UsbDiskNumber') { $commonArgs['UsbDiskNumber'] = 3 }
if ($paramNames -contains 'DiskNumber') { $commonArgs['DiskNumber'] = 3 }
if ($paramNames -contains 'UsbDiskId') { $commonArgs['UsbDiskId'] = 'USB-DISK-123' }
if ($paramNames -contains 'DiskId') { $commonArgs['DiskId'] = 'USB-DISK-123' }
if ($paramNames -contains 'IsoPath') { $commonArgs['IsoPath'] = Join-Path $env:TEMP 'wfu-tool-test.iso' }
if ($paramNames -contains 'ImagePath') { $commonArgs['ImagePath'] = Join-Path $env:TEMP 'wfu-tool-test.iso' }
if ($paramNames -contains 'PartitionStyle') { $commonArgs['PartitionStyle'] = 'gpt' }
if ($paramNames -contains 'UsbPartitionStyle') { $commonArgs['UsbPartitionStyle'] = 'gpt' }
if ($paramNames -contains 'KeepIso') { $commonArgs['KeepIso'] = $true }
if ($paramNames -contains 'Mode') {
    $commonArgs['Mode'] = if ((Get-Command Get-WfuNormalizedMode -ErrorAction SilentlyContinue) -and (Get-WfuNormalizedMode -Mode 'UsbFromIso') -eq 'UsbFromIso') { 'UsbFromIso' } else { 'CreateUsb' }
}
if ($paramNames -contains 'Headless') { $commonArgs['Headless'] = $true }
if ($paramNames -contains 'TargetDisk') { $commonArgs['TargetDisk'] = 'USB-DISK-123' }
if ($paramNames -contains 'Disk') { $commonArgs['Disk'] = 'USB-DISK-123' }
if ($paramNames -contains 'Volume') { $commonArgs['Volume'] = 'USB-DISK-123' }
if ($paramNames -contains 'Workspace') { $commonArgs['Workspace'] = Join-Path $env:TEMP 'WFU_USB_Workspace' }
if ($paramNames -contains 'OutputPath') { $commonArgs['OutputPath'] = Join-Path $env:TEMP 'WFU_USB_Output' }
if ($paramNames -contains 'SourcePath') { $commonArgs['SourcePath'] = Join-Path $env:TEMP 'wfu-tool-test.iso' }

$mandatoryMissing = @()
foreach ($parameter in $usbCmd.Parameters.Values) {
    $isMandatory = $false
    foreach ($attr in $parameter.Attributes) {
        if ($attr.PSObject.Properties.Name -contains 'Mandatory' -and $attr.Mandatory) {
            $isMandatory = $true
            break
        }
    }
    if ($isMandatory -and -not $commonArgs.ContainsKey($parameter.Name)) {
        $mandatoryMissing += $parameter.Name
    }
}

if ($mandatoryMissing.Count -gt 0) {
    Skip-Test 'USB planning helpers' "Command $commandName requires parameters not covered by the generic contract: $($mandatoryMissing -join ', ')"
    return
}

if ($usbCmd.CommandType -eq 'Function' -and $usbCmd.Parameters.Count -gt 0) {
    try {
        $result = & $usbCmd.Name @commonArgs
        Assert-NotNull $result "USB planning: helper returned a result ($commandName)"

        $resultText = if ($result -is [string]) { $result } else { ($result | Out-String) }
        if ($resultText) {
            Assert-True ($resultText -match 'USB|Disk|Iso|WIM|ESD|GPT|MBR') "USB planning: result looks like a USB plan ($commandName)"
        }
    } catch {
        Assert-True $false "USB planning: helper invocation failed ($commandName) -- $_"
    }
} else {
    Skip-Test 'USB planning helpers' "Command $commandName is not invokable with the current test harness"
}
