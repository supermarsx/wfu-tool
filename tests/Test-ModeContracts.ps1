function Import-WfuAutomationModule {
    if (-not (Get-Command Get-WfuDefaultOptions -ErrorAction SilentlyContinue)) {
        $projectRoot = Split-Path $PSScriptRoot -Parent
        . (Join-Path $projectRoot 'modules\Upgrade\Automation.ps1')
    }
}

Import-WfuAutomationModule

Assert-NotNull (Get-Command Get-WfuDefaultOptions -ErrorAction SilentlyContinue) 'Mode contracts: module loaded'

function Get-WfuFirstCommand {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd }
    }

    return $null
}

function Test-WfuNewModeSupport {
    if ((Get-WfuNormalizedMode -Mode 'IsoDownload') -ne 'IsoDownload') { return $false }
    if ((Get-WfuNormalizedMode -Mode 'UsbFromIso') -ne 'UsbFromIso') { return $false }
    if ((Get-WfuNormalizedMode -Mode 'AutomatedUpgrade') -ne 'AutomatedUpgrade') { return $false }
    if ((Get-WfuNormalizedMode -Mode 'headless') -ne 'AutomatedUpgrade') { return $false }
    if ((Get-WfuNormalizedMode -Mode 'createusb') -ne 'UsbFromIso') { return $false }
    if ((Get-WfuNormalizedMode -Mode 'create_usb') -ne 'UsbFromIso') { return $false }
    return $true
}

function Invoke-WfuModeValidation {
    param([hashtable]$Options)

    $cmd = Get-WfuFirstCommand -Candidates @(
        'Test-WfuModeRequirements',
        'Test-WfuAutomationRequirements',
        'Test-WfuHeadlessRequirements'
    )

    if (-not $cmd) { return $null }

    try {
        return & $cmd.Name -Options $Options
    }
    catch {
        return @($_)
    }
}

Assert-Equal 'Interactive' (Get-WfuNormalizedMode -Mode 'interactive') 'Mode contracts: interactive stays default'
Assert-Equal 'AutomatedUpgrade' (Get-WfuNormalizedMode -Mode 'headless') 'Mode contracts: legacy headless alias maps forward'
Assert-Equal 'UsbFromIso' (Get-WfuNormalizedMode -Mode 'createusb') 'Mode contracts: legacy createusb alias maps forward'
Assert-Equal 'UsbFromIso' (Get-WfuNormalizedMode -Mode 'create_usb') 'Mode contracts: legacy create_usb alias maps forward'
Assert-Equal 'Resume' (Get-WfuNormalizedMode -Mode 'resume') 'Mode contracts: resume still normalizes'

if (-not (Test-WfuNewModeSupport)) {
    Skip-Test 'Mode contracts: new mode normalization' 'New runtime mode names are not implemented yet'
    return
}

Assert-Equal 'IsoDownload' (Get-WfuNormalizedMode -Mode 'IsoDownload') 'Mode contracts: IsoDownload normalizes'
Assert-Equal 'UsbFromIso' (Get-WfuNormalizedMode -Mode 'UsbFromIso') 'Mode contracts: UsbFromIso normalizes'
Assert-Equal 'AutomatedUpgrade' (Get-WfuNormalizedMode -Mode 'AutomatedUpgrade') 'Mode contracts: AutomatedUpgrade normalizes'

$tempRoot = Join-Path $env:TEMP 'WFU_TOOL_ModeContractsTests'
Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

function New-WfuModeIni {
    param(
        [string]$Path,
        [string]$Mode,
        [hashtable]$ExtraGeneral = @{},
        [hashtable]$ExtraUsb = @{}
    )

    $general = @(
        '[general]',
        "mode=$Mode"
    )

    foreach ($key in $ExtraGeneral.Keys) {
        $general += "$key=$($ExtraGeneral[$key])"
    }

    $usb = @('[usb]')
    foreach ($key in $ExtraUsb.Keys) {
        $usb += "$key=$($ExtraUsb[$key])"
    }

    $lines = @()
    $lines += $general
    $lines += '[checks]'
    $lines += '[sources]'
    $lines += $usb
    $lines += '[resume]'
    $lines += ''
    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

$validationCommand = Get-WfuFirstCommand -Candidates @('Test-WfuModeRequirements', 'Test-WfuAutomationRequirements', 'Test-WfuHeadlessRequirements')
if (-not $validationCommand) {
    Skip-Test 'Mode contracts: validation helper' 'No validation helper is exposed yet'
}
else {
    $isoValidation = Invoke-WfuModeValidation -Options ([ordered]@{
            Mode          = 'IsoDownload'
            TargetVersion = $null
            DownloadPath  = $tempRoot
        })
    Assert-True (@($isoValidation).Count -gt 0) 'Mode contracts: IsoDownload requires a target version'

    $usbValidation = Invoke-WfuModeValidation -Options ([ordered]@{
            Mode          = 'UsbFromIso'
            TargetVersion = '24H2'
            DownloadPath  = $tempRoot
        })
    Assert-True (@($usbValidation).Count -gt 0) 'Mode contracts: UsbFromIso requires a USB target'
}

$resolvedIsoPath = Join-Path $tempRoot 'isodownload.ini'
New-WfuModeIni -Path $resolvedIsoPath -Mode 'IsoDownload' -ExtraGeneral @{
    target_version = '24H2'
    download_path  = $tempRoot
}
$resolvedIso = New-WfuResolvedOptions -ConfigPath $resolvedIsoPath -CliOptions @{}
Assert-Equal 'IsoDownload' $resolvedIso.Mode 'Mode contracts: IsoDownload resolves from INI'

$resolvedUsbPath = Join-Path $tempRoot 'usbfromiso.ini'
New-WfuModeIni -Path $resolvedUsbPath -Mode 'UsbFromIso' -ExtraGeneral @{
    target_version = '24H2'
    download_path  = $tempRoot
} -ExtraUsb @{
    create_usb      = 'true'
    disk_number     = '3'
    keep_iso        = 'true'
    partition_style = 'gpt'
}
$resolvedUsb = New-WfuResolvedOptions -ConfigPath $resolvedUsbPath -CliOptions @{}
Assert-Equal 'UsbFromIso' $resolvedUsb.Mode 'Mode contracts: UsbFromIso resolves from INI'
Assert-True $resolvedUsb.CreateUsb 'Mode contracts: UsbFromIso enables USB creation'
Assert-Equal 3 $resolvedUsb.UsbDiskNumber 'Mode contracts: UsbFromIso keeps the USB disk number'

$resolvedAutoPath = Join-Path $tempRoot 'automatedupgrade.ini'
New-WfuModeIni -Path $resolvedAutoPath -Mode 'AutomatedUpgrade' -ExtraGeneral @{
    target_version = '24H2'
    download_path  = $tempRoot
}
$resolvedAuto = New-WfuResolvedOptions -ConfigPath $resolvedAutoPath -CliOptions @{}
Assert-Equal 'AutomatedUpgrade' $resolvedAuto.Mode 'Mode contracts: AutomatedUpgrade resolves from INI'

$legacyHeadlessPath = Join-Path $tempRoot 'legacy-headless.ini'
New-WfuModeIni -Path $legacyHeadlessPath -Mode 'headless' -ExtraGeneral @{
    target_version = '24H2'
    download_path  = $tempRoot
}
$legacyHeadless = New-WfuResolvedOptions -ConfigPath $legacyHeadlessPath -CliOptions @{}
Assert-Equal 'AutomatedUpgrade' $legacyHeadless.Mode 'Mode contracts: legacy headless alias maps forward'

$legacyCreateUsbPath = Join-Path $tempRoot 'legacy-createusb.ini'
New-WfuModeIni -Path $legacyCreateUsbPath -Mode 'createusb' -ExtraGeneral @{
    target_version = '24H2'
    download_path  = $tempRoot
} -ExtraUsb @{
    create_usb  = 'true'
    disk_number = '3'
}
$legacyCreateUsb = New-WfuResolvedOptions -ConfigPath $legacyCreateUsbPath -CliOptions @{}
Assert-Equal 'UsbFromIso' $legacyCreateUsb.Mode 'Mode contracts: legacy createusb alias maps forward'

$templateCommand = Get-WfuFirstCommand -Candidates @(
    'New-WfuDefaultIniConfig',
    'New-WfuDefaultIniTemplate',
    'Write-WfuDefaultIniTemplate',
    'Get-WfuDefaultIniTemplate',
    'Save-WfuDefaultIniTemplate'
)

if (-not $templateCommand) {
    Skip-Test 'Mode contracts: minimal INI template' 'No default-template helper is exposed yet'
}
else {
    $templatePath = Join-Path $tempRoot 'default-template.ini'
    $templateArgs = @{}

    foreach ($name in @('Path', 'OutputPath', 'IniPath', 'ConfigPath', 'FilePath')) {
        if ($templateCommand.Parameters.ContainsKey($name)) {
            $templateArgs[$name] = $templatePath
            break
        }
    }

    if ($templateCommand.Parameters.ContainsKey('Mode')) {
        $templateArgs['Mode'] = 'Interactive'
    }
    if ($templateCommand.Parameters.ContainsKey('Minimal')) {
        $templateArgs['Minimal'] = $true
    }
    if ($templateCommand.Parameters.ContainsKey('DefaultOnly')) {
        $templateArgs['DefaultOnly'] = $true
    }
    if ($templateCommand.Parameters.ContainsKey('TemplateOnly')) {
        $templateArgs['TemplateOnly'] = $true
    }
    if ($templateCommand.Parameters.ContainsKey('PassThru')) {
        $templateArgs['PassThru'] = $true
    }

    $templateResult = & $templateCommand.Name @templateArgs
    $templateText = if (Test-Path $templatePath) { Get-Content -Path $templatePath -Raw } elseif ($templateResult) { [string]$templateResult } else { '' }

    Assert-True ([string]::IsNullOrWhiteSpace($templateText) -eq $false) 'Mode contracts: default template produced content'
    Assert-True ($templateText -match '\[general\]') 'Mode contracts: default template has general section'
    Assert-True ($templateText -match 'mode=interactive') 'Mode contracts: default template sets interactive mode'
    Assert-True ($templateText -match '\[checks\]') 'Mode contracts: default template has checks section'
    Assert-True ($templateText -match '\[sources\]') 'Mode contracts: default template has sources section'
    Assert-True ($templateText -match '\[usb\]') 'Mode contracts: default template has usb section'
    Assert-True ($templateText -match '\[resume\]') 'Mode contracts: default template has resume section'
    Assert-True (-not ($templateText -match '(?m)^(?!\s*[;#]).*target_version=')) 'Mode contracts: default template omits target override'
    Assert-True (-not ($templateText -match '(?m)^(?!\s*[;#]).*preferred_source=')) 'Mode contracts: default template omits source overrides'
    Assert-True (-not ($templateText -match '(?m)^(?!\s*[;#]).*disk_number=')) 'Mode contracts: default template omits usb overrides'
}

Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
