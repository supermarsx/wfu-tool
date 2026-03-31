# Tests for Invoke-WithRetry

# -- Succeeds on first try --
$result = Invoke-WithRetry -Description 'instant success' -MaxAttempts 3 -BaseDelaySec 0 -Action { return 'ok' }
Assert-Equal 'ok' $result 'Retry: Returns value on first success'

# -- Succeeds on second try --
$Script:retryCounter = 0
$result = Invoke-WithRetry -Description 'second try' -MaxAttempts 3 -BaseDelaySec 0 -Action {
    $Script:retryCounter++
    if ($Script:retryCounter -lt 2) { throw 'not yet' }
    return 'recovered'
}
Assert-Equal 'recovered' $result 'Retry: Recovers on second attempt'
Assert-Equal 2 $Script:retryCounter 'Retry: Ran exactly 2 times'

# -- Exhausts all retries --
$Script:retryCounter = 0
$result = Invoke-WithRetry -Description 'always fails' -MaxAttempts 2 -BaseDelaySec 0 -Action {
    $Script:retryCounter++
    throw 'permanent error'
}
Assert-Null $result 'Retry: Returns null after exhausting retries'
Assert-Equal 2 $Script:retryCounter 'Retry: Ran MaxAttempts times'

# -- Returns $false correctly (not confused with failure) --
$result = Invoke-WithRetry -Description 'returns false' -MaxAttempts 2 -BaseDelaySec 0 -Action { return $false }
Assert-True ($result -eq $false) 'Retry: Returns $false without retrying'

# -- Returns $true correctly --
$result = Invoke-WithRetry -Description 'returns true' -MaxAttempts 2 -BaseDelaySec 0 -Action { return $true }
Assert-True ($result -eq $true) 'Retry: Returns $true correctly'
