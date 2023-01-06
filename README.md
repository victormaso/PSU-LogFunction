# Building Standard structured log function for Universal for debugging and auditing

PowerShell universal has several methods to debug dashboards, jobs and endpoints. However when it comes to auditing user actions and debugging your code being invoked within dashboards endpoints benefit from adding your own logging. Even if there is no "error" to catch you may want to log information you need to recreate or diagnose an unexpected result a user reports using one of your dashboards, jobs, apis ect.
Having a standard log function you can use across PSU that will automatically PSU specific metadata such as the current logged in user using the services rather than the service account running PSU.

# Create a "Universal" Log function
When creating any new application log we want to have some sort of a structure and standards so we can easily parse the logs later. Lets start by adding a timestamp and severity to our log message in a pscustomobject.

```powershell
function Write-PSULog {
    param(
        [ValidateSet('Info', 'Warn', 'Error', 'Start', 'End', IgnoreCase = $false)]
        [string]$Severity = "Info",
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    $LogObject = [PSCustomObject]@{
        Timestamp = Get-Date
        Severity  = $Severity
        Message   = $Message
    }
    $LogObject
}
```
```powershell
Write-PSULog -Severity Info -Message "Hello World!"   

Timestamp             Severity Message     
---------             -------- -------     
11/14/2022 3:31:56 PM Info     Hello World!
```
While this does show us the output and will display in PSU Job log it will also output the object to the pipeline. 

Lets update it to write the output to the host and write a log as JSON to a log file. Writing to JSON preserves the PSobject structure in a text format.
```powershell
function Write-PSULog {
    param(
        [ValidateSet('Info', 'Warn', 'Error', 'Start', 'End', IgnoreCase = $false)]
        [string]$Severity = "Info",
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$logDirectory="C:\PSULogDir"
    )
    $LogObject = [PSCustomObject]@{
        Timestamp = Get-Date
        Severity  = $Severity
        Message   = $Message
    }

    $logFilePath = Join-Path "$logDirectory" "PSULogFile.json"
    $LogObject | ConvertTo-Json -Compress | Out-File -FilePath $logFilePath -Append
    
    Write-Host "$($LogObject.Timestamp) Severity=$($LogObject.Severity) Message=$($LogObject.Message)"
}
```
Powershell
```powershell
Write-PSULog -Severity Info -Message "Hello World!"
Write-PSULog -Severity Info -Message "Another Message"
```
Host Output
```
11/14/2022 15:25:58 Severity=Info Message=Hello World!
11/14/2022 15:27:25 Severity=Info Message=Another Message
```

PSULogFile.json
```json
{"Timestamp":"2022-11-14T15:25:58.8605891-05:00","Severity":"Info","Message":"Hello World!"}
{"Timestamp":"2022-11-14T15:27:25.5325547-05:00","Severity":"Info","Message":"Another Message"}
```

# Using JSON as a log format
Many CIM products like Splunk, Sumo and others support automatic parsing of JSON without any sort of definition being defined. Having a centralized log solution that can parse and categorize your logs can be very beneficial for searching but not required. It also allows for the flexibility of having your logs not all contain the same fields. 
By compressing the json (removing whitespace/formatting) and separating each JSON log/document into its own line this usually makes it more compatible, faster to write and smaller in file size to be parsed by a log solution supporting JSON.


# Capturing PSU metadata for audit
Powershell Universal creates some standard variables when running as a Dashboard, Job or API. 
https://docs.powershelluniversal.com/platform/variables#built-in-variables

By looking for these variables we can determine if this is a job, api or Dashboard and include relevant metadata with each log. We can then populate a new PSCustomObject with metadata relevant to each type including what user is invoking the process. 


```powershell
    if ($DashboardName) {
        #Dashboard
        $Metadata = [PSCustomObject]@{
            Invoking_User = $user
            Name          = $DashboardName
            PSU_Type      = "Dashboard"
            EndPointID    = $endpoint.Name
        }

    } elseif (($Method) -and ($Url)) {
        #Rest API Endpoint
        $Metadata = [PSCustomObject]@{
            Invoking_User = $Identity
            PSU_Type      = "Endpoint"
            Method        = $Method
            EndpointUrl   = $Url
            Body          = $Body
        }
    } elseif ($UAJob.id) {
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
    } else {
        #Not running in UA. Identify User run as account by Home directory
        $user = $HOME | Split-Path -Leaf

        $Metadata = [PSCustomObject]@{
            Invoking_User = $user
            PSU_Type      = "NA"
        }
    }

```
# Capturing a terminating Error and the exception
To our parameter block we want to add a way for our function to accept an exception object. We can specify $_ as the default for the -LastException parameter which will automatically 

```powershell
function Write-PSULog {
    param(
        [ValidateSet('Info', 'Warn', 'Error', 'Start', 'End', IgnoreCase = $false)]
        [string]$Severity = "Info",
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$logDirectory = "C:\PSULogDir",
        [System.Management.Automation.ErrorRecord]$LastException = $_
    )
    ...
    ...
```


To ensure a function when it errors is a terminating error (and error that stops the pipeline and does not continue) you usually can specify -ErrorAction Stop. Using this in a Try catch block will allow our log function to access the exception object. 

```powershell
    try {
        Write-PSULog -Severity Info -Message "Running Get-Service on [$ServiceName]"
        Get-Service -Name "Spooler" -BadParam "value" -ErrorAction Stop 
    } catch {
        Write-PSULog -Severity Error -Message "There was an error getting [$ServiceName]" 
    }
```

In our code we add a section that expands out some useful information about the exception into a psobject.

```powershell

  if ($Severity -eq "Error") {

        if ($LastException.ErrorRecord) {
            #PSCore Error
            $LastError = $LastException.ErrorRecord
        } else {
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
  }

```

The very last line of our write-psulog function can throw the very same exception it received at the beginning of the script. This allows you to retain the the same functionality of stopping the pipeline and outputting the same error after you logging is complete. If this were running in a PSU Dashboard the same error will be shown in a red udtoast just like the original terminating error would have.

```powershell
 if ($Severity -eq "Error") {throw $LastException}
```


# PSCallstack for debugging
Best practice when designing dashboards is to leverage Powershell functions stored in modules and/or PSU Jobs whenever possible. This is fantastic for keeping the code for the layout of a dashboard separate from the code executed by user button press for example. If the function or a nested function within the dashboard or Job has an error the output of the exception or log might not be clean on what file/script line error ocurred. When Dashboards when running have many runspaces and when looking at exception will show "scriptblock" as the calling function and the line number where the error occurred will likely not line up with the line number in your Dashboard script file as each. 

https://docs.powershelluniversal.com/config/best-practices#use-functions-in-dashboards

https://docs.powershelluniversal.com/config/best-practices#consider-leveraging-jobs

```powershell

    $CallStackDepth = 0
    $fullCallStack = Get-PSCallStack

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
            

```

# Completed Log function

<details>
<summary>Completed Log function</summary>

```powershell
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

    } elseif (($Method) -and ($Url)) {
        #Rest API Endpoint
        $Metadata = [PSCustomObject]@{
            Invoking_User = $Identity
            PSU_Type      = "Endpoint"
            Method        = $Method
            EndpointUrl   = $Url
            Body          = $Body
        }
    } elseif ($UAJob.id) {
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
    } else {
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
        } else {
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
            
        $WriteHostColor = @{foregroundColor = "Red"}
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
    $LogObject | ConvertTo-Json  -Depth 2 | Out-File -FilePath $logFilePath -Append -Encoding utf8
    
    Write-Host "$($LogObject.Timestamp) Sev=$($LogObject.Severity) CallingFunction=$($LogObject.CallingFunction) `n   $($LogObject.Message)" @WriteHostColor
    if ($Severity -eq "Error") {throw $LastException}
}
```

</details>

# Considerations
- A log function that takes long to run no matter the reason will affect performance of your scripts. Do performance testing of the log function using "measure-command" and only do verbose logging when needed like for Errors or end of scripts. Avoid dependencies that could cause you log function to fail if they are missing. Avoid unessasary logging where performance matters.
- When using log files if multiple scripts/dashboards/runspaces ect are writing to the same file, locking will occur and could cause other processes trying to write to the same file to error. Avoid this by having the log function create unique file names to avoid this condition and add retry logic to the log function. An alternative option may be to write the log instead to a Document database or restapi to a log aggregator service.
- If you want to include the object output of the results of another command into your log function be mindful of when that object gets converted to JSON. Try selecting only needed properties relevant before the log function converts to json. https://docs.powershelluniversal.com/config/best-practices#avoid-returning-highly-complex-objects
- Code defensively in your log function. You really want to avoid you log function being prone to errors that could prevent the original event from being logged.
- Make sure you log function does not add anything to the pipeline. Use Out-null or assign output to $null as necessary to avoid hard to diagnose issues due to unexpected output to the pipeline.
- When logging input from variables be aware of potential sensitive information like api keys being entered. You may want to put in logic to obfuscate or disable certain metadata from being captured where appropriate.

# Going further
- On important events like an Error you may want your log function to not only log the event but send an additional message to a chat platform or ticketing system. You can embed all the code to do so in a nested function in the log function or have it instead invoke a UA Job or Rest Endpoint to abstract the logic and access to the api key for those services.

# Sample Logs

<details>
<summary>Dashboard Info and Error Example (Formatted)</summary>

```json
{
    "Timestamp":  "11/14/2022 10:20:13 PM",
    "Severity":  "Info",
    "CallingFunction":  "Invoke-FailFunction_GetService",
    "Message":  "Running Get-Service on [FakeService]",
    "Metadata":  {
                     "Invoking_User":  "Domain\\Victor",
                     "Name":  "WPSU_Dashboard51",
                     "PSU_Type":  "Dashboard",
                     "EndPointID":  "LookupFakeServiceButtonID"
                 }
}
```

```json
{
    "Timestamp":  "11/14/2022 10:20:13 PM",
    "Severity":  "Error",
    "CallingFunction":  "Invoke-FailFunction_GetService",
    "Message":  "There was an error getting [FakeService]",
    "Metadata":  {
                     "Invoking_User":  "Domain\\Victor",
                     "Name":  "WPSU_Dashboard51",
                     "PSU_Type":  "Dashboard",
                     "EndPointID":  "LookupFakeServiceButtonID"
                 },
    "LastError":  {
                      "ScriptName":  "C:\\ProgramData\\UniversalAutomation\\Repository\\PSULogModule\\TestFunctions\\Invoke-FailFunction_GetService.ps1",
                      "ExceptionSource":  "System.Management.Automation",
                      "ExceptionStackTrace":  "   at System.Management.Automation.ExceptionHandlingOps.CheckActionPreference(FunctionContext funcContext, Exception exception)\r\n   at System.Management.Automation.Interpreter.ActionCallInstruction`2.Run(InterpretedFrame frame)\r\n   at System.Management.Automation.Interpreter.EnterTryCatchFinallyInstruction.Run(InterpretedFrame frame)\r\n   at System.Management.Automation.Interpreter.EnterTryCatchFinallyInstruction.Run(InterpretedFrame frame)",
                      "InvocationName":  "",
                      "ExceptionMessage":  "A parameter cannot be found that matches parameter name \u0027ExtraVariable\u0027.",
                      "MyCommandVersion":  "3.0.0.0",
                      "PositionMessage":  "At C:\\ProgramData\\UniversalAutomation\\Repository\\PSULogModule\\TestFunctions\\Invoke-FailFunction_GetService.ps1:9 char:40\r\n+         Get-Service -Name $ServiceName -ExtraVariable $ExtraVariable  ...\r\n+                                        ~~~~~~~~~~~~~~"
                  },
    "fullCallStackDump":  [
                              {
                                  "CallStackDepth":  1,
                                  "ScriptLineNumber":  11,
                                  "FunctionName":  "Invoke-FailFunction_GetService",
                                  "ScriptName":  "C:\\ProgramData\\UniversalAutomation\\Repository\\PSULogModule\\TestFunctions\\Invoke-FailFunction_GetService.ps1",
                                  "Location":  "Invoke-FailFunction_GetService.ps1: line 11",
                                  "Command":  "Invoke-FailFunction_GetService",
                                  "Arguments":  "{ServiceName=FakeService, ExtraVariable=ExtraVariableValue}"
                              },
                              {
                                  "CallStackDepth":  2,
                                  "ScriptLineNumber":  9,
                                  "FunctionName":  "Invoke-MainScript",
                                  "ScriptName":  "C:\\ProgramData\\UniversalAutomation\\Repository\\PSULogModule\\TestFunctions\\Invoke-MainScript.ps1",
                                  "Location":  "Invoke-MainScript.ps1: line 9",
                                  "Command":  "Invoke-MainScript",
                                  "Arguments":  "{ServiceNameToLookup=FakeService}"
                              },
                              {
                                  "CallStackDepth":  3,
                                  "ScriptLineNumber":  3,
                                  "FunctionName":  "\u003cScriptBlock\u003e",
                                  "ScriptName":  null,
                                  "Location":  "\u003cNo file\u003e",
                                  "Command":  "\u003cScriptBlock\u003e",
                                  "Arguments":  "{}"
                              }
                          ]
}
```

</details>

<details>
<summary>Endpoint Info and Error log Example (Formatted)</summary>

```json
{
  "Timestamp": "11/14/2022 10:26:51 PM",
  "Severity": "Info",
  "CallingFunction": "Invoke-FailFunction_GetService",
  "Message": "Running Get-Service on [FakeService]",
  "Metadata": {
    "Invoking_User": "Domain\\Victor",
    "PSU_Type":  "Endpoint",
    "Method": "GET",
    "EndpointUrl": "/WPSU_EndpointPS7/test",
    "Body": ""
  }
}
```

```json
{
  "Timestamp": "11/14/2022 10:26:51 PM",
  "Severity": "Error",
  "CallingFunction": "Invoke-FailFunction_GetService",
  "Message": "There was an error getting [FakeService]",
  "Metadata": {
    "Invoking_User": "Domain\\Victor",
    "PSU_Type":  "Endpoint",
    "Method": "GET",
    "EndpointUrl": "/WPSU_EndpointPS7/test",
    "Body": ""
  },
  "LastError": {
    "MyCommandVersion": "7.3.0.500",
    "ExceptionMessage": "A parameter cannot be found that matches parameter name 'ExtraVariable'.",
    "ScriptName": "C:\\ProgramData\\UniversalAutomation\\Repository\\PSULogModule\\TestFunctions\\Invoke-FailFunction_GetService.ps1",
    "PositionMessage": "At C:\\ProgramData\\UniversalAutomation\\Repository\\PSULogModule\\TestFunctions\\Invoke-FailFunction_GetService.ps1:9 char:40\r\n+         Get-Service -Name $ServiceName -ExtraVariable $ExtraVariable  …\r\n+                                        ~~~~~~~~~~~~~~",
    "ExceptionStackTrace": "   at System.Management.Automation.ExceptionHandlingOps.CheckActionPreference(FunctionContext funcContext, Exception exception)\r\n   at System.Management.Automation.Interpreter.ActionCallInstruction`2.Run(InterpretedFrame frame)\r\n   at System.Management.Automation.Interpreter.EnterTryCatchFinallyInstruction.Run(InterpretedFrame frame)\r\n   at System.Management.Automation.Interpreter.EnterTryCatchFinallyInstruction.Run(InterpretedFrame frame)",
    "ExceptionSource": "System.Management.Automation",
    "InvocationName": ""
  },
  "fullCallStackDump": [
    {
      "CallStackDepth": 1,
      "ScriptLineNumber": 11,
      "FunctionName": "Invoke-FailFunction_GetService",
      "ScriptName": "C:\\ProgramData\\UniversalAutomation\\Repository\\PSULogModule\\TestFunctions\\Invoke-FailFunction_GetService.ps1",
      "Location": "Invoke-FailFunction_GetService.ps1: line 11",
      "Command": "Invoke-FailFunction_GetService",
      "Arguments": "{ServiceName=FakeService, ExtraVariable=ExtraVariableValue}"
    },
    {
      "CallStackDepth": 2,
      "ScriptLineNumber": 9,
      "FunctionName": "Invoke-MainScript",
      "ScriptName": "C:\\ProgramData\\UniversalAutomation\\Repository\\PSULogModule\\TestFunctions\\Invoke-MainScript.ps1",
      "Location": "Invoke-MainScript.ps1: line 9",
      "Command": "Invoke-MainScript",
      "Arguments": "{ServiceNameToLookup=FakeService}"
    },
    {
      "CallStackDepth": 3,
      "ScriptLineNumber": 7,
      "FunctionName": "<ScriptBlock>",
      "ScriptName": null,
      "Location": "<No file>",
      "Command": "<ScriptBlock>",
      "Arguments": "{-TestVar, test}"
    },
    {
      "CallStackDepth": 4,
      "ScriptLineNumber": 1,
      "FunctionName": "<ScriptBlock>",
      "ScriptName": null,
      "Location": "<No file>",
      "Command": "<ScriptBlock>",
      "Arguments": "{}"
    }
  ]
}
```

</details>

<details>
<summary>Script Job Info and Error log Example (Formatted)</summary>

```json
{
    "Timestamp":  "11/14/2022 10:34:45 PM",
    "Severity":  "Info",
    "CallingFunction":  "Invoke-FailFunction_GetService",
    "Message":  "Running Get-Service on [FakeService]",
    "Metadata":  {
                     "Invoking_User":  "Domain\\Victor",
                     "PSU_Type":  "UAJob",
                     "UAJobParam":  {
                                        "Name":  "testJobParam",
                                        "Type":  "System.Object",
                                        "DisplayValue":  "FakeService"
                                    },
                     "UAJobScript":  "Jobs\\WPSU_Script.ps1",
                     "UAJobId":  4870
                 }
}
```

```json
{
    "Timestamp":  "11/14/2022 10:34:45 PM",
    "Severity":  "Error",
    "CallingFunction":  "Invoke-FailFunction_GetService",
    "Message":  "There was an error getting [FakeService]",
    "Metadata":  {
                     "Invoking_User":  "Domain\\Victor",
                     "PSU_Type":  "UAJob",
                     "UAJobParam":  {
                                        "Name":  "testJobParam",
                                        "Type":  "System.Object",
                                        "DisplayValue":  "FakeService"
                                    },
                     "UAJobScript":  "Jobs\\WPSU_Script.ps1",
                     "UAJobId":  4870
                 },
    "LastError":  {
                      "ScriptName":  "C:\\ProgramData\\UniversalAutomation\\Repository\\PSULogModule\\TestFunctions\\Invoke-FailFunction_GetService.ps1",
                      "ExceptionSource":  "System.Management.Automation",
                      "ExceptionStackTrace":  "   at System.Management.Automation.ExceptionHandlingOps.CheckActionPreference(FunctionContext funcContext, Exception exception)\r\n   at System.Management.Automation.Interpreter.ActionCallInstruction`2.Run(InterpretedFrame frame)\r\n   at System.Management.Automation.Interpreter.EnterTryCatchFinallyInstruction.Run(InterpretedFrame frame)\r\n   at System.Management.Automation.Interpreter.EnterTryCatchFinallyInstruction.Run(InterpretedFrame frame)",
                      "InvocationName":  "",
                      "ExceptionMessage":  "A parameter cannot be found that matches parameter name \u0027ExtraVariable\u0027.",
                      "MyCommandVersion":  "3.0.0.0",
                      "PositionMessage":  "At C:\\ProgramData\\UniversalAutomation\\Repository\\PSULogModule\\TestFunctions\\Invoke-FailFunction_GetService.ps1:9 char:40\r\n+         Get-Service -Name $ServiceName -ExtraVariable $ExtraVariable  ...\r\n+                                        ~~~~~~~~~~~~~~"
                  },
    "fullCallStackDump":  [
                              {
                                  "CallStackDepth":  1,
                                  "ScriptLineNumber":  11,
                                  "FunctionName":  "Invoke-FailFunction_GetService",
                                  "ScriptName":  "C:\\ProgramData\\UniversalAutomation\\Repository\\PSULogModule\\TestFunctions\\Invoke-FailFunction_GetService.ps1",
                                  "Location":  "Invoke-FailFunction_GetService.ps1: line 11",
                                  "Command":  "Invoke-FailFunction_GetService",
                                  "Arguments":  "{ServiceName=FakeService, ExtraVariable=ExtraVariableValue}"
                              },
                              {
                                  "CallStackDepth":  2,
                                  "ScriptLineNumber":  9,
                                  "FunctionName":  "Invoke-MainScript",
                                  "ScriptName":  "C:\\ProgramData\\UniversalAutomation\\Repository\\PSULogModule\\TestFunctions\\Invoke-MainScript.ps1",
                                  "Location":  "Invoke-MainScript.ps1: line 9",
                                  "Command":  "Invoke-MainScript",
                                  "Arguments":  "{ServiceNameToLookup=FakeService}"
                              },
                              {
                                  "CallStackDepth":  3,
                                  "ScriptLineNumber":  7,
                                  "FunctionName":  "\u003cScriptBlock\u003e",
                                  "ScriptName":  "C:\\ProgramData\\UniversalAutomation\\Repository\\Jobs\\WPSU_Script.ps1",
                                  "Location":  "WPSU_Script.ps1: line 7",
                                  "Command":  "WPSU_Script.ps1",
                                  "Arguments":  "{testJobParam=FakeService}"
                              },
                              {
                                  "CallStackDepth":  4,
                                  "ScriptLineNumber":  1,
                                  "FunctionName":  "\u003cScriptBlock\u003e",
                                  "ScriptName":  null,
                                  "Location":  "\u003cNo file\u003e",
                                  "Command":  "\u003cScriptBlock\u003e",
                                  "Arguments":  "{}"
                              }
                          ]
}
```

</details>

