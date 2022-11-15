Get-ChildItem (Join-Path $PSScriptRoot 'TestFunctions') -File -Recurse | Where-Object {$_.name -match '.ps1'} | ForEach-Object {
    . $_.FullName
}

$modulesToExport = @(
    'Invoke-FailFunction_GetService',
    'Invoke-MainScript',
    'Write-PSULog'
)
$modulesToExport | ForEach-Object {Export-ModuleMember -Function "$_"}