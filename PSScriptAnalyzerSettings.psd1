@{
    Severity     = @('Error', 'Warning')
    IncludeRules = @()
    ExcludeRules = @()
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $false
            TargetVersions = @('7.4')
        }
    }
}
