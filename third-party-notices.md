# Third-Party Notices

This repository includes or is informed by third-party work.

## Windows Update SOAP client

File:
- `wfu-tool-windows-update.ps1`

Notice:
- Parts of the Windows Update SOAP client implementation were derived from the `uup-dump/api` project.
- Original upstream project: `uup-dump/api`
- Upstream site: `https://git.uupdump.net/uup-dump/api`
- Original PHP code copyright: 2019-2021 whatever127 and contributors
- License: Apache License 2.0

## Media and setup compatibility techniques

Files:
- `wfu-tool.ps1`
- `modules/Upgrade/UpgradePreparation.ps1`
- `modules/Upgrade/Assistant.ps1`
- `modules/Upgrade/DownloadSources.ps1`

Notice:
- Some setup-compatibility, media-selection, and download-flow behavior was informed by established community approaches and tooling around Windows installation media and upgrade bypass techniques, including prior public work associated with MediaCreationTool.bat and Fido.
- This notice centralizes provenance that is not repeated throughout the runtime scripts.
