function Invoke-MainScript {
param(
    [string]$ServiceNameToLookup="FakeService"
)


Write-PSULog -Severity "Start" -Message "Starting Invoke-MainScript"

Invoke-FailFunction_GetService -service $ServiceNameToLookup -ExtraVariable "ExtraVariableValue"

Write-PSULog -Severity "End" -Message "Ending Invoke-MainScript script"
}