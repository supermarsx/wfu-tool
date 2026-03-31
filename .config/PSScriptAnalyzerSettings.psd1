@{
    Severity = @('Error')
    IncludeRules = @(
        'PSAvoidUsingCmdletAliases',
        'PSUseApprovedVerbs',
        'PSUseDeclaredVarsMoreThanAssignments'
    )
    ExcludeRules = @(
        'PSAvoidUsingPositionalParameters'
    )
}
