# Tests for Test-FileHash

$testFile = Join-Path $env:TEMP 'WFU_TOOL_HashTest.txt'
Set-Content $testFile -Value 'Hello World' -Encoding ASCII

# Get actual hashes
$sha1 = (Get-FileHash $testFile -Algorithm SHA1).Hash
$sha256 = (Get-FileHash $testFile -Algorithm SHA256).Hash

# -- Correct hash passes --
$result = Test-FileHash -FilePath $testFile -ExpectedHash $sha1 -Algorithm SHA1
Assert-True ($result -eq $true) 'FileHash: Correct SHA1 passes'

$result = Test-FileHash -FilePath $testFile -ExpectedHash $sha256 -Algorithm SHA256
Assert-True ($result -eq $true) 'FileHash: Correct SHA256 passes'

# -- Wrong hash fails --
$result = Test-FileHash -FilePath $testFile -ExpectedHash 'DEADBEEF00000000000000000000000000000000' -Algorithm SHA1
Assert-True ($result -eq $false) 'FileHash: Wrong SHA1 fails'

# -- Empty hash skips (returns true) --
$result = Test-FileHash -FilePath $testFile -ExpectedHash '' -Algorithm SHA1
Assert-True ($result -eq $true) 'FileHash: Empty hash skips verification'

# -- Missing file returns false --
$result = Test-FileHash -FilePath 'C:\NoSuchFile_12345.txt' -ExpectedHash $sha1 -Algorithm SHA1
Assert-True ($result -eq $false) 'FileHash: Missing file returns false'

# -- Case insensitive --
$result = Test-FileHash -FilePath $testFile -ExpectedHash $sha1.ToLower() -Algorithm SHA1
Assert-True ($result -eq $true) 'FileHash: Case insensitive comparison'

# Cleanup
Remove-Item $testFile -Force -ErrorAction SilentlyContinue
