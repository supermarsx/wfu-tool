$ErrorActionPreference = 'Stop'

function Get-WfuChocolateyPackageUrl {
    $params = Get-PackageParameters
    if ($params.ContainsKey('PackageUrl') -and $params.PackageUrl) {
        return $params.PackageUrl
    }

    if ($env:WFU_TOOL_PACKAGE_URL) {
        return $env:WFU_TOOL_PACKAGE_URL
    }

    throw 'wfu-tool requires PackageUrl or WFU_TOOL_PACKAGE_URL to be supplied.'
}

function Get-WfuChocolateyInstallDir {
    $params = Get-PackageParameters
    if ($params.ContainsKey('InstallDir') -and $params.InstallDir) {
        return $params.InstallDir
    }

    if ($env:WFU_TOOL_INSTALL_DIR) {
        return $env:WFU_TOOL_INSTALL_DIR
    }

    return Join-Path $env:ProgramFiles 'wfu-tool'
}

$packageUrl = Get-WfuChocolateyPackageUrl
$installDir = Get-WfuChocolateyInstallDir
$tempDir = Join-Path $env:TEMP "wfu-tool.$([guid]::NewGuid().ToString('N'))"
$archivePath = Join-Path $tempDir 'wfu-tool.zip'

New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
try {
    Get-ChocolateyWebFile -PackageName 'wfu-tool' -FileFullPath $archivePath -Url $packageUrl
    if (Test-Path $installDir) {
        Remove-Item -LiteralPath $installDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Expand-Archive -Path $archivePath -DestinationPath $installDir -Force
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

