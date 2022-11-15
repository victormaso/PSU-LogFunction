New-UDDashboard -Title "Lookup FakeService" -Content {
    Import-Module c:\ProgramData\UniversalAutomation\Repository\PSULogModule\PSULogModule.psm1 -Force

    New-UDButton -ID "LookupFakeServiceButtonID" "Lookup FakeService" -OnClick {
        Write-PSULog -Severity Info -Message "PSU Dashboard Example"
        invoke-MainScript -ServiceNameToLookup "FakeService"
    }
}