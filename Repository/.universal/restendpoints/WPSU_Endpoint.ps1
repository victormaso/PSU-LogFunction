Import-Module c:\ProgramData\UniversalAutomation\Repository\PSULogModule\PSULogModule.psm1 -Force

Write-PSULog -Severity Info -Message "PSU Endpoint Example"
invoke-mainscript -ServiceNameToLookup "FakeService"