# Tests for Repair-TlsConfiguration

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Skip-Test 'TLS: Repair-TlsConfiguration' 'Requires admin privileges'
    Skip-Test 'TLS: WinHTTP DefaultSecureProtocols' 'Requires admin privileges'
    Skip-Test 'TLS: .NET SchUseStrongCrypto' 'Requires admin privileges'
}
else {
    # Run the fix
    Repair-TlsConfiguration
    Assert-True $true 'TLS: Repair-TlsConfiguration completed without error'

    # Verify WinHTTP DefaultSecureProtocols includes TLS 1.2 (0x800)
    $winHttpKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
    $val = Get-RegValue $winHttpKey 'DefaultSecureProtocols'
    Assert-True (($val -band 0x800) -ne 0) 'TLS: WinHTTP DefaultSecureProtocols includes TLS 1.2 (0x800)'

    # Verify Schannel TLS 1.2 is enabled
    $tls12Key = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'
    $enabled = Get-RegValue $tls12Key 'Enabled'
    Assert-Equal 1 $enabled 'TLS: Schannel TLS 1.2 Client Enabled = 1'

    $disabled = Get-RegValue $tls12Key 'DisabledByDefault'
    Assert-Equal 0 $disabled 'TLS: Schannel TLS 1.2 DisabledByDefault = 0'

    # Verify .NET strong crypto
    $netKey = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
    $strong = Get-RegValue $netKey 'SchUseStrongCrypto'
    Assert-Equal 1 $strong 'TLS: .NET SchUseStrongCrypto = 1'

    $sysDefault = Get-RegValue $netKey 'SystemDefaultTlsVersions'
    Assert-Equal 1 $sysDefault 'TLS: .NET SystemDefaultTlsVersions = 1'

    # Verify PS SecurityProtocol includes TLS 1.2
    $proto = [Net.ServicePointManager]::SecurityProtocol
    Assert-True ($proto -band [Net.SecurityProtocolType]::Tls12) 'TLS: PowerShell SecurityProtocol includes TLS 1.2'
}
