# Legacy Windows 10 media manifest and source helpers.

function New-LegacyMediaSourceDescriptor {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('CAB','XML','MCTEXE')]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$DisplayVersion,

        [Parameter(Mandatory)]
        [int]$Build,

        [Parameter(Mandatory)]
        [string]$OS,

        [string]$Architecture = 'neutral',
        [string]$FileName = '',
        [string]$Notes = '',
        [string]$Confidence = 'Known'
    )

    [pscustomobject]@{
        Kind           = $Kind
        Url            = $Url
        FileName       = $FileName
        Version        = $Version
        DisplayVersion = $DisplayVersion
        Build          = $Build
        OS             = $OS
        Architecture   = $Architecture
        Notes          = $Notes
        Confidence     = $Confidence
    }
}

function Get-LegacyMediaManifest {
    <#
    .SYNOPSIS
        Returns the built-in legacy Windows 10 media manifest.
    #>
    [CmdletBinding()]
    param()

    $mctGeneric = 'https://download.microsoft.com/download/C/F/9/CF9862F9-3D22-4811-99E7-68CE3327DAE6/MediaCreationTool.exe'
    $mct1507X64 = 'https://download.microsoft.com/download/1/C/8/1C8BAF5C-9B7E-44FB-A90A-F58590B5DF7B/v2.0/MediaCreationToolx64.exe'
    $mct1507X86 = 'https://download.microsoft.com/download/1/C/8/1C8BAF5C-9B7E-44FB-A90A-F58590B5DF7B/v2.0/MediaCreationTool.exe'
    $mct1703    = 'https://download.microsoft.com/download/1/F/E/1FE453BE-89E0-4B6D-8FF8-35B8FA35EC3F/MediaCreationTool.exe'
    $mct1709    = 'https://download.microsoft.com/download/A/B/E/ABEE70FE-7DE8-472A-8893-5F69947DE0B1/MediaCreationTool.exe'
    $mct1803    = 'https://software-download.microsoft.com/download/pr/MediaCreationTool1803.exe'
    $mct1809    = 'https://software-download.microsoft.com/download/pr/MediaCreationTool1809.exe'
    $mct1903    = 'https://software-download.microsoft.com/download/pr/MediaCreationTool1903.exe'
    $mct1909    = 'https://download.microsoft.com/download/c/0/b/c0b2b254-54f1-42de-bfe5-82effe499ee0/MediaCreationTool1909.exe'
    $mct2004    = 'https://software-download.microsoft.com/download/pr/MediaCreationTool2004.exe'
    $mct20H2    = 'https://download.microsoft.com/download/4/c/c/4cc6c15c-75a5-4d1b-a3fe-140a5e09c9ff/MediaCreationTool20H2.exe'
    $mct21H1    = 'https://download.microsoft.com/download/d/5/2/d528a4e0-03f3-452d-a98e-3e479226d166/MediaCreationTool21H1.exe'
    $mct21H2    = 'https://download.microsoft.com/download/b/0/5/b053c6bc-fc07-4785-a66a-63c5aeb715a9/MediaCreationTool21H2.exe'
    $mct22H2    = 'https://download.microsoft.com/download/9/e/a/9eac306f-d134-4609-9c58-35d1638c2363/MediaCreationTool22H2.exe'

    @(
        [pscustomobject]@{
            Version                 = 'W10_1507'
            DisplayVersion          = '1507'
            Build                   = 10240
            OS                      = 'Windows 10'
            ReleaseLine             = 'Threshold 1'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $false
            SupportsBusinessEdition = $false
            CatalogKind             = 'XML'
            CatalogUrl              = 'https://wscont.apps.microsoft.com/winstore/OSUpgradeNotification/MediaCreationTool/prod/Products09232015_2.xml'
            CatalogFileName         = 'Products09232015_2.xml'
            MctUrl                  = $mct1507X64
            MctUrl32                = $mct1507X86
            PreferredMctUrl         = $mct1507X64
            Notes                   = 'Initial Windows 10 release catalog.'
        }
        [pscustomobject]@{
            Version                 = 'W10_1511'
            DisplayVersion          = '1511'
            Build                   = 10586
            OS                      = 'Windows 10'
            ReleaseLine             = 'Threshold 2'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $false
            SupportsBusinessEdition = $false
            CatalogKind             = 'XML'
            CatalogUrl              = 'https://wscont.apps.microsoft.com/winstore/OSUpgradeNotification/MediaCreationTool/prod/Products05242016.xml'
            CatalogFileName         = 'Products05242016.xml'
            MctUrl                  = $mctGeneric
            MctUrl32                = $mctGeneric
            PreferredMctUrl         = $mctGeneric
            Notes                   = 'Threshold 2 release catalog.'
        }
        [pscustomobject]@{
            Version                 = 'W10_1607'
            DisplayVersion          = '1607'
            Build                   = 14393
            OS                      = 'Windows 10'
            ReleaseLine             = 'Redstone 1'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $false
            SupportsBusinessEdition = $true
            CatalogKind             = 'CAB'
            CatalogUrl              = 'https://wscont.apps.microsoft.com/winstore/OSUpgradeNotification/MediaCreationTool/prod/Products_20170116.cab'
            CatalogFileName         = 'Products_20170116.cab'
            MctUrl                  = $mctGeneric
            MctUrl32                = $mctGeneric
            PreferredMctUrl         = $mctGeneric
            Notes                   = 'First unified catalog format used for legacy edition generation.'
        }
        [pscustomobject]@{
            Version                 = 'W10_1703'
            DisplayVersion          = '1703'
            Build                   = 15063
            OS                      = 'Windows 10'
            ReleaseLine             = 'Redstone 2'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $false
            SupportsBusinessEdition = $true
            CatalogKind             = 'CAB'
            CatalogUrl              = 'https://download.microsoft.com/download/954415FD-D9D7-4E1F-8161-41B3A4E03D5E/products_20170317.cab'
            CatalogFileName         = 'products_20170317.cab'
            MctUrl                  = $mct1703
            MctUrl32                = $mct1703
            PreferredMctUrl         = $mct1703
            Notes                   = 'Redstone 2 catalog family.'
        }
        [pscustomobject]@{
            Version                 = 'W10_1709'
            DisplayVersion          = '1709'
            Build                   = 16299
            OS                      = 'Windows 10'
            ReleaseLine             = 'Redstone 3'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $true
            SupportsBusinessEdition = $true
            CatalogKind             = 'CAB'
            CatalogUrl              = 'https://download.microsoft.com/download/323D0F94-95D2-47DE-BB83-1D4AC3331190/products_20180105.cab'
            CatalogFileName         = 'products_20180105.cab'
            MctUrl                  = $mct1709
            MctUrl32                = $mct1709
            PreferredMctUrl         = $mct1709
            Notes                   = 'Catalog family used for the newer Redstone releases.'
        }
        [pscustomobject]@{
            Version                 = 'W10_1803'
            DisplayVersion          = '1803'
            Build                   = 17134
            OS                      = 'Windows 10'
            ReleaseLine             = 'Redstone 4'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $true
            SupportsBusinessEdition = $true
            CatalogKind             = 'CAB'
            CatalogUrl              = 'https://download.microsoft.com/download/5/C/B/5CB83D2A-2D7E-4129-9AFE-353F8459AA8B/products_20180705.cab'
            CatalogFileName         = 'products_20180705.cab'
            MctUrl                  = $mct1803
            MctUrl32                = $mct1803
            PreferredMctUrl         = $mct1803
            Notes                   = 'Shares the post-Redstone catalog family.'
        }
        [pscustomobject]@{
            Version                 = 'W10_1809'
            DisplayVersion          = '1809'
            Build                   = 17763
            OS                      = 'Windows 10'
            ReleaseLine             = 'Redstone 5'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $true
            SupportsBusinessEdition = $true
            CatalogKind             = 'CAB'
            CatalogUrl              = 'https://download.microsoft.com/download/8/E/8/8E852CBF-0BCC-454E-BDF5-60443569617C/products_20190314.cab'
            CatalogFileName         = 'products_20190314.cab'
            MctUrl                  = $mct1809
            MctUrl32                = $mct1809
            PreferredMctUrl         = $mct1809
            Notes                   = 'RS5 release catalog and matching MCT.'
        }
        [pscustomobject]@{
            Version                 = 'W10_1903'
            DisplayVersion          = '1903'
            Build                   = 18362
            OS                      = 'Windows 10'
            ReleaseLine             = '19H1'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $true
            SupportsBusinessEdition = $true
            CatalogKind             = 'CAB'
            CatalogUrl              = 'https://download.microsoft.com/download/8/E/8/8E852CBF-0BCC-454E-BDF5-60443569617C/products_20190314.cab'
            CatalogFileName         = 'products_20190314.cab'
            MctUrl                  = $mct1903
            MctUrl32                = $mct1903
            PreferredMctUrl         = $mct1903
            Notes                   = '19H1 release catalog.'
        }
        [pscustomobject]@{
            Version                 = 'W10_1909'
            DisplayVersion          = '1909'
            Build                   = 18363
            OS                      = 'Windows 10'
            ReleaseLine             = '19H2'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $true
            SupportsBusinessEdition = $true
            CatalogKind             = 'CAB'
            CatalogUrl              = 'https://download.microsoft.com/download/8/E/8/8E852CBF-0BCC-454E-BDF5-60443569617C/products_20190314.cab'
            CatalogFileName         = 'products_20190314.cab'
            MctUrl                  = $mct1909
            MctUrl32                = $mct1909
            PreferredMctUrl         = $mct1909
            Notes                   = '19H2 release refresh catalog.'
        }
        [pscustomobject]@{
            Version                 = 'W10_2004'
            DisplayVersion          = '2004'
            Build                   = 19041
            OS                      = 'Windows 10'
            ReleaseLine             = '20H1'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $true
            SupportsBusinessEdition = $true
            CatalogKind             = 'MCT'
            CatalogUrl              = $null
            CatalogFileName         = ''
            MctUrl                  = $mct2004
            MctUrl32                = $mct2004
            PreferredMctUrl         = $mct2004
            Notes                   = 'Pinned 20H1 media tool family.'
        }
        [pscustomobject]@{
            Version                 = 'W10_20H2'
            DisplayVersion          = '20H2'
            Build                   = 19042
            OS                      = 'Windows 10'
            ReleaseLine             = '20H2'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $true
            SupportsBusinessEdition = $true
            CatalogKind             = 'MCT'
            CatalogUrl              = $null
            CatalogFileName         = ''
            MctUrl                  = $mct20H2
            MctUrl32                = $mct20H2
            PreferredMctUrl         = $mct20H2
            Notes                   = 'Pinned MCT family for the 20H2 release.'
        }
        [pscustomobject]@{
            Version                 = 'W10_21H1'
            DisplayVersion          = '21H1'
            Build                   = 19043
            OS                      = 'Windows 10'
            ReleaseLine             = '21H1'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $true
            SupportsBusinessEdition = $true
            CatalogKind             = 'MCT'
            CatalogUrl              = $null
            CatalogFileName         = ''
            MctUrl                  = $mct21H1
            MctUrl32                = $mct21H1
            PreferredMctUrl         = $mct21H1
            Notes                   = 'Pinned MCT family for the 21H1 release.'
        }
        [pscustomobject]@{
            Version                 = 'W10_21H2'
            DisplayVersion          = '21H2'
            Build                   = 19044
            OS                      = 'Windows 10'
            ReleaseLine             = '21H2'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $true
            SupportsBusinessEdition = $true
            CatalogKind             = 'MCT'
            CatalogUrl              = $null
            CatalogFileName         = ''
            MctUrl                  = $mct21H2
            MctUrl32                = $mct21H2
            PreferredMctUrl         = $mct21H2
            Notes                   = 'Pinned Windows 10 21H2 media tool.'
        }
        [pscustomobject]@{
            Version                 = 'W10_22H2'
            DisplayVersion          = '22H2'
            Build                   = 19045
            OS                      = 'Windows 10'
            ReleaseLine             = '22H2'
            SupportsArchSelection   = $true
            SupportsMediaEditionArg = $true
            SupportsBusinessEdition = $true
            CatalogKind             = 'MCT'
            CatalogUrl              = $null
            CatalogFileName         = ''
            MctUrl                  = $mct22H2
            MctUrl32                = $mct22H2
            PreferredMctUrl         = $mct22H2
            Notes                   = 'Final Windows 10 feature release.'
        }
    )
}

function Get-LegacyMediaVersions {
    <#
    .SYNOPSIS
        Returns the supported legacy Windows 10 version ids.
    #>
    [CmdletBinding()]
    param()

    @(Get-LegacyMediaManifest | ForEach-Object { $_.Version })
}

function Get-LegacyMediaSpec {
    <#
    .SYNOPSIS
        Returns the manifest entry for a legacy Windows 10 version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )

    Get-LegacyMediaManifest | Where-Object { $_.Version -ieq $Version } | Select-Object -First 1
}

function Get-LegacyMediaSourceDescriptors {
    <#
    .SYNOPSIS
        Returns normalized source descriptors for the requested legacy version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )

    $spec = Get-LegacyMediaSpec -Version $Version
    if (-not $spec) {
        return $null
    }

    $sources = @()
    if ($spec.CatalogKind -and $spec.CatalogUrl) {
        $sources += New-LegacyMediaSourceDescriptor `
            -Kind $spec.CatalogKind `
            -Url $spec.CatalogUrl `
            -FileName $spec.CatalogFileName `
            -Version $spec.Version `
            -DisplayVersion $spec.DisplayVersion `
            -Build $spec.Build `
            -OS $spec.OS `
            -Architecture 'neutral' `
            -Notes $spec.Notes
    }

    if ($spec.MctUrl) {
        $sources += New-LegacyMediaSourceDescriptor `
            -Kind 'MCTEXE' `
            -Url $spec.MctUrl `
            -FileName (Split-Path $spec.MctUrl -Leaf) `
            -Version $spec.Version `
            -DisplayVersion $spec.DisplayVersion `
            -Build $spec.Build `
            -OS $spec.OS `
            -Architecture 'x64' `
            -Notes 'Preferred launcher' `
            -Confidence 'Heuristic'
    }

    if ($spec.MctUrl32 -and $spec.MctUrl32 -ne $spec.MctUrl) {
        $sources += New-LegacyMediaSourceDescriptor `
            -Kind 'MCTEXE' `
            -Url $spec.MctUrl32 `
            -FileName (Split-Path $spec.MctUrl32 -Leaf) `
            -Version $spec.Version `
            -DisplayVersion $spec.DisplayVersion `
            -Build $spec.Build `
            -OS $spec.OS `
            -Architecture 'x86' `
            -Notes '32-bit launcher' `
            -Confidence 'Heuristic'
    }

    $sources
}

function Get-LegacyMediaCatalogSources {
    <#
    .SYNOPSIS
        Returns the source descriptors for a legacy Windows 10 version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )

    Get-LegacyMediaSourceDescriptors -Version $Version
}

function Get-LegacyMediaPreferredSources {
    <#
    .SYNOPSIS
        Returns legacy media sources in preferred download order for a version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [ValidateSet('x64','x86','neutral')]
        [string]$Architecture = 'x64'
    )

    $sources = @(Get-LegacyMediaSourceDescriptors -Version $Version)
    if (-not $sources -or $sources.Count -eq 0) {
        return @()
    }

    $arch = $Architecture.ToLowerInvariant()
    $filtered = foreach ($source in $sources) {
        if (-not $source) { continue }
        $srcArch = if ($source.PSObject.Properties.Name -contains 'Architecture' -and $source.Architecture) {
            [string]$source.Architecture
        } else {
            'neutral'
        }

        if ($arch -eq 'neutral' -or $srcArch -eq 'neutral' -or $srcArch -ieq $arch) {
            $priority = switch ($source.Kind) {
                'CAB'   { 0 }
                'XML'   { 1 }
                'MCTEXE' { if ($arch -eq 'x86') { 1 } else { 2 } }
                default { 3 }
            }

            [pscustomobject]@{
                Priority       = $priority
                Source         = $source
                Version        = $source.Version
                DisplayVersion = $source.DisplayVersion
                Build          = $source.Build
                OS             = $source.OS
                Kind           = $source.Kind
                Url            = $source.Url
                FileName       = $source.FileName
                Architecture   = $srcArch
                Notes          = $source.Notes
                Confidence     = $source.Confidence
            }
        }
    }

    @($filtered | Sort-Object -Property Priority, Kind, FileName)
}

function Resolve-LegacyMediaSource {
    <#
    .SYNOPSIS
        Resolves a legacy media source to a concrete descriptor.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [ValidateSet('x64','x86','neutral')]
        [string]$Architecture = 'x64',

        [ValidateSet('Preferred','All')]
        [string]$Mode = 'Preferred'
    )

    $sources = if ($Mode -eq 'All') {
        @(Get-LegacyMediaSourceDescriptors -Version $Version)
    } else {
        @(Get-LegacyMediaPreferredSources -Version $Version -Architecture $Architecture | ForEach-Object { $_.Source })
    }

    if ($Mode -eq 'Preferred') {
        $preferred = Get-LegacyMediaPreferredSources -Version $Version -Architecture $Architecture
        if ($preferred.Count -gt 0) {
            return $preferred[0].Source
        }
        return $null
    }

    return @($sources)
}

function Get-LegacyMediaDownloadPlan {
    <#
    .SYNOPSIS
        Builds a normalized download plan for a legacy Windows 10 version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [ValidateSet('x64','x86','neutral')]
        [string]$Architecture = 'x64'
    )

    $spec = Get-LegacyMediaSpec -Version $Version
    if (-not $spec) {
        return $null
    }

    $preferred = Get-LegacyMediaPreferredSources -Version $Version -Architecture $Architecture
    if (-not $preferred -or $preferred.Count -eq 0) {
        return $null
    }

    [pscustomobject]@{
        Version        = $spec.Version
        DisplayVersion = $spec.DisplayVersion
        Build          = $spec.Build
        OS             = $spec.OS
        Architecture   = $Architecture
        Sources        = @($preferred)
    }
}

function Invoke-LegacyMediaDownload {
    <#
    .SYNOPSIS
        Downloads a legacy media source into a target directory.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetDirectory,

        [ValidateSet('x64','x86','neutral')]
        [string]$Architecture = 'x64',

        [switch]$Force
    )

    $plan = Get-LegacyMediaDownloadPlan -Version $Version -Architecture $Architecture
    if (-not $plan) {
        return $null
    }

    if (-not (Test-Path $TargetDirectory)) {
        New-Item -ItemType Directory -Path $TargetDirectory -Force -ErrorAction Stop | Out-Null
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $plan.Sources) {
        $source = $entry.Source
        if (-not $source -or -not $source.Url) {
            continue
        }

        $fileName = if ($source.FileName) { $source.FileName } else { Split-Path $source.Url -Leaf }
        if (-not $fileName) {
            $fileName = "$($source.Version).$($source.Kind.ToLowerInvariant())"
        }

        $destination = Join-Path $TargetDirectory $fileName
        if ((Test-Path $destination) -and -not $Force) {
            [void]$results.Add([pscustomobject]@{
                Version    = $source.Version
                Kind       = $source.Kind
                SourceUrl  = $source.Url
                FilePath   = $destination
                Downloaded = $false
                Skipped    = $true
            })
            continue
        }

        if ($PSCmdlet.ShouldProcess($destination, "Download $($source.Kind) source")) {
            try {
                Invoke-WebRequest -Uri $source.Url -OutFile $destination -UseBasicParsing -ErrorAction Stop
                [void]$results.Add([pscustomobject]@{
                    Version    = $source.Version
                    Kind       = $source.Kind
                    SourceUrl  = $source.Url
                    FilePath   = $destination
                    Downloaded = $true
                    Skipped    = $false
                })
            } catch {
                [void]$results.Add([pscustomobject]@{
                    Version    = $source.Version
                    Kind       = $source.Kind
                    SourceUrl  = $source.Url
                    FilePath   = $destination
                    Downloaded = $false
                    Skipped    = $false
                    Error      = [string]$_
                })
            }
        }
    }

    [pscustomobject]([ordered]@{
        Version         = $plan.Version
        DisplayVersion   = $plan.DisplayVersion
        Build           = $plan.Build
        OS              = $plan.OS
        Architecture    = $plan.Architecture
        TargetDirectory = $TargetDirectory
        Items           = @($results | ForEach-Object { $_ })
    })
}

function Stage-LegacyMediaSources {
    <#
    .SYNOPSIS
        Ensures legacy media sources are present on disk and returns their paths.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetDirectory,

        [ValidateSet('x64','x86','neutral')]
        [string]$Architecture = 'x64'
    )

    $download = Invoke-LegacyMediaDownload -Version $Version -TargetDirectory $TargetDirectory -Architecture $Architecture
    if (-not $download) {
        return $null
    }

    [pscustomobject]([ordered]@{
        Version         = $download.Version
        DisplayVersion  = $download.DisplayVersion
        Build           = $download.Build
        OS              = $download.OS
        Architecture    = $download.Architecture
        TargetDirectory = $download.TargetDirectory
        Items           = $download.Items
        Files           = @($download.Items | Where-Object { $_.FilePath } | ForEach-Object { $_.FilePath })
    })
}
