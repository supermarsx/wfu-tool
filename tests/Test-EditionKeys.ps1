# Tests for Get-WindowsEditionKeys

$keys = Get-WindowsEditionKeys

Assert-True ($keys -is [hashtable]) 'EditionKeys: Returns a hashtable'
Assert-True ($keys.Count -ge 15) 'EditionKeys: Has at least 15 editions'

# Check key format (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX)
foreach ($entry in $keys.GetEnumerator()) {
    Assert-Match '^\w{5}-\w{5}-\w{5}-\w{5}-\w{5}$' $entry.Value "EditionKeys: $($entry.Key) key format valid"
}

# Check specific well-known keys exist
Assert-NotNull $keys['Professional'] 'EditionKeys: Professional key exists'
Assert-NotNull $keys['Enterprise'] 'EditionKeys: Enterprise key exists'
Assert-NotNull $keys['Education'] 'EditionKeys: Education key exists'
Assert-NotNull $keys['Core'] 'EditionKeys: Core (Home) key exists'

# Pro key should match the known value
Assert-Equal 'VK7JG-NPHTM-C97JM-9MPGT-3V66T' $keys['Professional'] 'EditionKeys: Professional key matches known value'
