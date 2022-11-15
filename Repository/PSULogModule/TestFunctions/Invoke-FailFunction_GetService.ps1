function Invoke-FailFunction_GetService {
    param(
        [string]$ServiceName = "FakeService",
        [string]$ExtraVariable
    )

    try {
        Write-PSULog -Severity Info -Message "Running Get-Service on [$ServiceName]"
        Get-Service -Name $ServiceName -ExtraVariable $ExtraVariable -ErrorAction Stop 
    } catch {
        Write-PSULog -Severity Error -Message "There was an error getting [$ServiceName]"
    }

}