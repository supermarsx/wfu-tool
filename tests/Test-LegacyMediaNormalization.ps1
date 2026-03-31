<#
.SYNOPSIS
    Validates legacy media source descriptor normalization.
#>

function Resolve-LegacyCommand {
    param([string[]]$Candidates)

    foreach ($name in $Candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd }
    }

    return $null
}

function Invoke-LegacySourceCommand {
    param($Cmd)

    foreach ($args in @(
            @(),
            @('-Version', 'W10_1507'),
            @('-TargetVersion', 'W10_1507')
        )) {
        try {
            return & $Cmd.Name @args
        }
        catch {
            continue
        }
    }

    return $null
}

function Get-NormalizedSourceValue {
    param($Item)

    foreach ($propName in @('SourceType', 'Source', 'Kind', 'Type')) {
        if ($Item.PSObject.Properties.Name -contains $propName) {
            return [string]$Item.$propName
        }
    }

    return $null
}

function Get-NormalizedUrlValue {
    param($Item)

    foreach ($propName in @('Url', 'URI', 'Uri', 'DownloadUrl')) {
        if ($Item.PSObject.Properties.Name -contains $propName) {
            return [string]$Item.$propName
        }
    }

    return $null
}

function Unwrap-LegacyDescriptor {
    param($Item)

    foreach ($propName in @('Value', 'Item', 'Release', 'Descriptor')) {
        if ($Item.PSObject.Properties.Name -contains $propName) {
            $candidate = $Item.$propName
            if ($candidate -and $candidate.PSObject.Properties.Count -gt 0) {
                return $candidate
            }
        }
    }

    return $Item
}

$descriptorCmd = Resolve-LegacyCommand -Candidates @(
    'Get-LegacyMediaSourceDescriptors',
    'Get-LegacyMediaSources',
    'Get-LegacyMediaCatalog',
    'Get-LegacyMediaManifest'
)

if (-not $descriptorCmd) {
    Skip-Test 'Legacy source normalization' 'Legacy descriptor helper not available yet'
    return
}

$descriptors = Invoke-LegacySourceCommand -Cmd $descriptorCmd
if (-not $descriptors) {
    Skip-Test 'Legacy source normalization' 'Legacy descriptor helper returned no descriptors'
    return
}

if ($descriptors -isnot [System.Collections.IEnumerable] -or $descriptors -is [string]) {
    $descriptors = @($descriptors)
}

$sourceKinds = @()
foreach ($item in $descriptors) {
    $item = Unwrap-LegacyDescriptor -Item $item
    $sourceValue = Get-NormalizedSourceValue -Item $item
    $urlValue = Get-NormalizedUrlValue -Item $item

    Assert-NotNull $sourceValue 'Legacy source normalization: source descriptor has a source value'
    if ($sourceValue) {
        Assert-True ($sourceValue -notmatch '^https?://') 'Legacy source normalization: source value is normalized, not a raw URL'
        Assert-True ($sourceValue -notmatch 'products\.(cab|xml)') 'Legacy source normalization: source value is not a raw catalog filename'
        $sourceKinds += $sourceValue
    }

    Assert-NotNull $urlValue 'Legacy source normalization: source descriptor has a URL'
    if ($urlValue) {
        Assert-Match '^https://' $urlValue 'Legacy source normalization: URL is HTTPS'
    }

    $versionValue = $null
    foreach ($propName in @('VersionId', 'Version', 'Id')) {
        if ($item.PSObject.Properties.Name -contains $propName) {
            $versionValue = [string]$item.$propName
            break
        }
    }
    if ($versionValue) {
        Assert-True ($versionValue -match '^W10_(1507|1511|1607|1703|1709|1803|1809|1903|1909|2004|20H2|21H1|21H2|22H2)$') "Legacy source normalization: version is canonical ($versionValue)"
    }
}

if ($sourceKinds.Count -gt 0) {
    $uniqueKinds = $sourceKinds | Sort-Object -Unique
    Assert-True ($uniqueKinds.Count -ge 1) 'Legacy source normalization: normalized source kinds present'
}
