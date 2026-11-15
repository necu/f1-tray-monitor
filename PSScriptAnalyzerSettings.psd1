@{
    # Reglas que no aportan valor en un proyecto de escritorio con WinForms.
    # El objetivo es detectar errores reales, no forzar un estilo concreto.
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingEmptyCatchBlock',
        'PSUseApprovedVerbs',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns',
        'PSAvoidUsingPositionalParameters',
        'PSReviewUnusedParameter',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSAvoidGlobalVars',
        'PSUseOutputTypeCorrectly',
        'PSAvoidUsingCmdletAliases',
        'PSUseConsistentWhitespace',
        'PSUseCorrectCasing',
        'PSAvoidTrailingWhitespace',
        # $sender es el nombre que exige la firma de los manejadores de eventos .NET.
        'PSAvoidAssignmentToAutomaticVariable'
    )
}
