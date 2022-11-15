param(
    $testJobParam="FakeService"
)
Import-Module c:\ProgramData\UniversalAutomation\Repository\PSULogModule\PSULogModule.psm1 -Force

Write-PSULog -Severity Info -Message "PSU Script Example"
invoke-mainscript -ServiceNameToLookup $testJobParam