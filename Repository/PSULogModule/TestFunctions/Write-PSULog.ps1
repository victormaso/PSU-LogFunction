function Write-PSULog {
    param(
        [ValidateSet('Info', 'Warn', 'Error', 'Start', 'End', IgnoreCase = $false)]
        [string]$Severity = "Info",
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$logDirectory = "C:\PSULogDir",
        [System.Management.Automation.ErrorRecord]$LastException = $_
    )

    
    if ($DashboardName) {
        #Dashboard
        $Metadata = [PSCustomObject]@{
            Invoking_User = $user
            Name          = $DashboardName
            PSU_Type      = "Dashboard"
            EndPointID    = $endpoint.Name
        }

    }
    elseif (($Method) -and ($Url)) {
        #Rest API Endpoint
        $Metadata = [PSCustomObject]@{
            Invoking_User = $Identity
            PSU_Type      = "Endpoint"
            Method        = $Method
            EndpointUrl   = $Url
            Body          = $Body
        }
    }
    elseif ($UAJob.id) {
        #UA Job
        $UAJobParamObjects = $UAJob.Parameters | ForEach-Object {
            [PSCustomObject]@{
                Name         = $_.name
                Type         = $_.type
                DisplayValue = $_.DisplayValue
            }
        }
        $Metadata = [PSCustomObject]@{
            Invoking_User = $UAJob.Identity.name
            PSU_Type      = "UAJob"
            UAJobParam    = $UAJobParamObjects
            UAJobScript   = $UAJob.ScriptFullPath
            UAJobId       = $UAJob.Id
        }
    }
    else {
        #Identify User run as account by Home directory
        $user = $HOME | Split-Path -Leaf

        $Metadata = [PSCustomObject]@{
            Invoking_User = $user
            PSU_Type      = "NA"
        }
    }


    $CallStackDepth = 0
    $fullCallStack = Get-PSCallStack
    $CallingFunction = $fullCallStack[1].FunctionName


    $LogObject = [PSCustomObject]@{
        Timestamp       = (Get-Date).ToString()
        Severity        = $Severity
        CallingFunction = $CallingFunction
        Message         = $Message
        Metadata        = $Metadata
    }

    if ($Severity -eq "Error") {

        if ($LastException.ErrorRecord) {
            #PSCore Error
            $LastError = $LastException.ErrorRecord
        }
        else {
            #PS 5.1 Error
            $LastError = $LastException
        }
    

        if ($LastException.InvocationInfo.MyCommand.Version) {
            $version = $LastError.InvocationInfo.MyCommand.Version.ToString()
        }
        $LastErrorObject = @{
            'ExceptionMessage'    = $LastError.Exception.Message
            'ExceptionSource'     = $LastError.Exception.Source
            'ExceptionStackTrace' = $LastError.Exception.StackTrace
            'PositionMessage'     = $LastError.InvocationInfo.PositionMessage
            'InvocationName'      = $LastError.InvocationInfo.InvocationName
            'MyCommandVersion'    = $version
            'ScriptName'          = $LastError.InvocationInfo.ScriptName
        }

        $LogObject | Add-Member -MemberType NoteProperty -Name LastError -Value $LastErrorObject

        $FullCallStackWithoutLogFunction = $fullCallStack | ForEach-Object {
            #loop through all the objects in the callstack result.
            #excluding the 0 position of the call stack which would represent this write-psulog function.
            if ($CallStackDepth -gt 0) {
                [PSCustomObject]@{
                    CallStackDepth   = $CallStackDepth
                    ScriptLineNumber = $_.ScriptLineNumber
                    FunctionName     = $_.FunctionName
                    ScriptName       = $_.ScriptName
                    Location         = $_.Location
                    Command          = $_.Command
                    Arguments        = $_.Arguments
                }
            }
            $CallStackDepth++
        }
    
        $LogObject | Add-Member -MemberType NoteProperty -Name fullCallStackDump -Value $FullCallStackWithoutLogFunction
            
        $WriteHostColor = @{foregroundColor = "Red" }
    }

    if (-NOT (Test-Path $logDirectory -PathType Container)) {
        try {
            New-Item -Path $logDirectory -ItemType Directory -ErrorAction Stop
        }
        catch {
            throw "Could not access or create the log directory [$logDirectory] path $_"
        }
    }

    $logFilePath = Join-Path "$logDirectory" "PSULogFile.json"
    $LogObject | ConvertTo-Json -Compress -Depth 2 | Out-File -FilePath $logFilePath -Append -Encoding utf8
    
    Write-Host "$($LogObject.Timestamp) Sev=$($LogObject.Severity) CallingFunction=$($LogObject.CallingFunction) `n   $($LogObject.Message)" @WriteHostColor
    if ($Severity -eq "Error") { throw $LastException }
}