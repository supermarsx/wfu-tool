# Tests for Get-RegValue, Set-RegValue, Remove-RegValue

$testKey = 'HKCU:\\SOFTWARE\\wfu-tool-Test_Temp'

# Setup
New-Item -Path $testKey -Force -ErrorAction SilentlyContinue | Out-Null

# -- Get-RegValue --
Set-ItemProperty $testKey -Name 'TestVal' -Value 42 -Type DWord -Force
Assert-Equal 42 (Get-RegValue $testKey 'TestVal') 'Get-RegValue reads existing DWORD'
Assert-Null (Get-RegValue $testKey 'NonExistent') 'Get-RegValue returns null for missing property'
Assert-Null (Get-RegValue 'HKCU:\\SOFTWARE\\wfu-tool-NoSuchKey_12345' 'Foo') 'Get-RegValue returns null for missing key'

# -- Set-RegValue --
$result = Set-RegValue $testKey 'NewVal' 99 'Test'
Assert-True ($result -eq $true) 'Set-RegValue returns true on success'
Assert-Equal 99 (Get-RegValue $testKey 'NewVal') 'Set-RegValue writes correct value'

# Set-RegValue on non-existent key (should create it)
$subKey = "$testKey\SubTest"
$result = Set-RegValue $subKey 'Deep' 1 'Test'
Assert-True ($result -eq $true) 'Set-RegValue creates new key + value'
Assert-Equal 1 (Get-RegValue $subKey 'Deep') 'Set-RegValue value readable after creation'

# -- Remove-RegValue --
Set-ItemProperty $testKey -Name 'ToRemove' -Value 'hello' -Force
Remove-RegValue $testKey 'ToRemove'
Assert-Null (Get-RegValue $testKey 'ToRemove') 'Remove-RegValue deletes property'

# Remove non-existent -- should not throw
Remove-RegValue $testKey 'AlreadyGone'
Assert-True $true 'Remove-RegValue silent on missing property'

# Cleanup
Remove-Item $testKey -Recurse -Force -ErrorAction SilentlyContinue
