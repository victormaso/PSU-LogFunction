﻿New-PSUEndpoint -Url "/WPSU_EndpointPS7/:TestVar" -Method @('GET') -Path "restendpoints\WPSU_Endpoint.ps1" -Environment "PS7CoreLatest" -Authentication
New-PSUEndpoint -Url "/WPSU_EndpointPS51/:TestVar" -Method @('GET') -Path "restendpoints\WPSU_Endpoint.ps1" -Environment "Windows PowerShell 5.1" -Authentication