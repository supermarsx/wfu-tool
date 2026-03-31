@{
    PackageIdentifier   = 'supermarsx.wfu-tool'
    PackageName         = 'wfu-tool'
    Publisher           = 'supermarsx'
    PublisherUrl        = 'https://github.com/supermarsx'
    PublisherSupportUrl = 'https://github.com/supermarsx/wfu-tool/issues'
    PackageUrl          = 'https://github.com/supermarsx/wfu-tool'
    License             = 'MIT'
    LicenseUrl          = 'https://github.com/supermarsx/wfu-tool/blob/main/license.md'
    ShortDescription    = 'Windows feature upgrade helper for Windows 10 and Windows 11.'
    Description         = 'Acquires Windows feature update media, prepares bootable USB media, and automates in-place upgrade workflows for supported Windows 10 and Windows 11 releases.'
    Moniker             = 'wfu-tool'
    Tags                = @(
        'windows'
        'windows-10'
        'windows-11'
        'windows-update'
        'upgrade'
        'powershell'
    )
    ManifestVersion     = '1.6.0'
    InstallerType       = 'zip'
    NestedInstallerType = 'portable'
    NestedInstallerFiles = @(
        @{
            RelativeFilePath     = 'launch-wfu-tool.bat'
            PortableCommandAlias = 'wfu-tool'
        }
    )
    ReleaseNotesUrl     = 'https://github.com/supermarsx/wfu-tool/releases'
}
