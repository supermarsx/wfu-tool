# Tests for Get-EsdDownloadFromCatalog

# -- 25H2 should return null (no public catalog) --
$esd25 = Get-EsdDownloadFromCatalog -Version '25H2' -Language 'en-us' -Arch 'x64'
Assert-Null $esd25 'EsdCatalog: 25H2 returns null (no public catalog)'

# -- 24H2 should return null (no public catalog) --
$esd24 = Get-EsdDownloadFromCatalog -Version '24H2' -Language 'en-us' -Arch 'x64'
Assert-Null $esd24 'EsdCatalog: 24H2 returns null (no public catalog)'

# -- 23H2 should return valid ESD info (if internet available) --
Write-Host '    (Testing 23H2 ESD catalog download -- needs internet)' -ForegroundColor DarkGray
$esd23 = Get-EsdDownloadFromCatalog -Version '23H2' -Language 'en-us' -Arch 'x64'
if ($esd23) {
    Assert-NotNull $esd23.Url 'EsdCatalog: 23H2 has URL'
    Assert-NotNull $esd23.Sha1 'EsdCatalog: 23H2 has SHA1'
    Assert-True ($esd23.Size -gt 1GB) 'EsdCatalog: 23H2 size > 1 GB'
    Assert-Match '\.esd' $esd23.Url 'EsdCatalog: 23H2 URL ends with .esd'
    Assert-Match 'dl\.delivery\.mp\.microsoft\.com' $esd23.Url 'EsdCatalog: 23H2 URL is Microsoft CDN'
    Assert-Match '^[0-9a-f]{40}$' $esd23.Sha1 'EsdCatalog: 23H2 SHA1 is 40 hex chars'
    Assert-NotNull $esd23.FileName 'EsdCatalog: 23H2 has FileName'
    Assert-Match 'en-us' $esd23.FileName 'EsdCatalog: 23H2 FileName contains en-us'
}
else {
    Skip-Test 'EsdCatalog: 23H2 details' 'No internet or catalog download failed'
}
