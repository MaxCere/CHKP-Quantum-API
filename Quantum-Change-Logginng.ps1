<#
.SYNOPSIS
    Check Point Quantum Access Rule Logging Configuration Tool

.DESCRIPTION
    This script allows you to configure logging settings (Track) for Check Point Quantum access rules via Management API.
    Supports: Log, Detailed Log, Extended Log, None, Accounting, per-Connection, per-Session options.
    Can be run interactively or fully automated via command-line parameters.

.PARAMETER MgmtServer
    Management server address (IP or hostname)

.PARAMETER User
    Management API username

.PARAMETER Password
    Management API password

.PARAMETER PackageName
    Policy package name

.PARAMETER LayerName
    Access layer name (optional if package has only one layer)

.PARAMETER RuleSelection
    Select rules: "all" for all rules, or leave empty for manual selection

.PARAMETER RuleNumbers
    Array of rule numbers to modify (e.g., @("1", "3", "5") or "all")

.PARAMETER RuleNames
    Array of rule names to modify (e.g., @("Rule1", "Rule2"))

.PARAMETER TrackType
    Track type: none, log, detailed-log (or "detailed log"), extended-log (or "extended log")
    Also accepts: detail, extended, extend as shortcuts

.PARAMETER Accounting
    Enable Accounting option

.PARAMETER PerConnection
    Enable per-Connection logging

.PARAMETER PerSession
    Enable per-Session logging

.PARAMETER Publish
    Publish changes (will prompt for confirmation)

.PARAMETER AutoPublish
    Automatically publish changes without confirmation

.PARAMETER Interactive
    Enable interactive mode (default: true)

.PARAMETER Quiet
    Suppress non-essential output

.EXAMPLE
    # Interactive mode (default)
    .\Quantum-Change-Logging.ps1 -MgmtServer 192.168.100.10

.EXAMPLE
    # Fully automated - modify all rules
    .\Quantum-Change-Logging.ps1 -MgmtServer 192.168.100.10 -User admin -Password "Pass" -PackageName "Standard" -RuleSelection all -TrackType log -Accounting -PerConnection -AutoPublish -Interactive:$false

.EXAMPLE
    # With spaces in TrackType
    .\Quantum-Change-Logging.ps1 -MgmtServer 192.168.100.10 -User admin -Password "Pass" -PackageName "Standard" -RuleNumbers @("1","3") -TrackType "extended log" -AutoPublish -Interactive:$false

.EXAMPLE
    # With dashes in TrackType
    .\Quantum-Change-Logging.ps1 -MgmtServer 192.168.100.10 -User admin -Password "Pass" -PackageName "Standard" -RuleSelection all -TrackType extended-log -AutoPublish -Interactive:$false

.EXAMPLE
    # Short form
    .\Quantum-Change-Logging.ps1 -MgmtServer 192.168.100.10 -User admin -Password "Pass" -PackageName "Standard" -RuleNames @("Grafana Access") -TrackType extended -AutoPublish -Interactive:$false -Quiet

.NOTES
    Author: MaxCere
    Version: 2.1
    
    IMPORTANT: Policy installation functionality is DISABLED by default.
    Automatic policy installation is considered too risky as it has not been tested 
    in all scenarios and could potentially install the wrong policy on the wrong 
    gateway, leading to service disruption or security issues.
    
    Users should manually install policies through SmartConsole after verifying
    the changes in the published policy package.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Management server address")]
    [string]$MgmtServer,
    
    [Parameter(Mandatory=$false)]
    [string]$User,
    
    [Parameter(Mandatory=$false)]
    [string]$Password,
    
    [Parameter(Mandatory=$false)]
    [string]$PackageName,
    
    [Parameter(Mandatory=$false)]
    [string]$LayerName,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("all", "")]
    [string]$RuleSelection = "",
    
    [Parameter(Mandatory=$false)]
    [string[]]$RuleNumbers,
    
    [Parameter(Mandatory=$false)]
    [string[]]$RuleNames,
    
    [Parameter(Mandatory=$false)]
    [string]$TrackType = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$Accounting,
    
    [Parameter(Mandatory=$false)]
    [switch]$PerConnection,
    
    [Parameter(Mandatory=$false)]
    [switch]$PerSession,
    
    [Parameter(Mandatory=$false)]
    [switch]$Publish,
    
    [Parameter(Mandatory=$false)]
    [switch]$AutoPublish,
    
    [Parameter(Mandatory=$false)]
    [switch]$Interactive = $true,
    
    [Parameter(Mandatory=$false)]
    [switch]$Quiet
)

# Color definitions
$script:Colors = @{
    Success = "Green"
    Error = "Red"
    Warning = "Yellow"
    Info = "Cyan"
    Highlight = "Magenta"
    Subtle = "Gray"
}

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White",
        [switch]$NoNewline
    )
    
    # Skip non-essential output in Quiet mode
    if ($Quiet -and $Color -notin @($Colors.Error, $Colors.Warning, $Colors.Success)) {
        return
    }
    
    if ($NoNewline) {
        Write-Host $Message -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Normalize-TrackType {
    param([string]$TrackType)
    
    if (-not $TrackType) {
        return ""
    }
    
    # Normalize track type to API format
    $normalizedType = switch -Regex ($TrackType.ToLower().Trim()) {
        "^none$" { "none" }
        "^log$" { "log" }
        "^(detailed-log|detail|detailed|detailed\s+log)$" { "detailed log" }
        "^(extended-log|extended|extend|extended\s+log)$" { "extended log" }
        default { 
            # Invalid track type
            $validOptions = "none, log, detailed-log (or 'detailed log'), extended-log (or 'extended log')"
            Write-ColorOutput "✗ Invalid TrackType: '$TrackType'" -Color $script:Colors.Error
            Write-ColorOutput "  Valid options: $validOptions" -Color $script:Colors.Subtle
            return $null
        }
    }
    
    return $normalizedType
}

function Authenticate {
    param($MgmtServer, $User, $Password)

    if (-not $User) { 
        if ($Interactive) {
            $User = Read-Host "Enter Management username"
        } else {
            Write-Error "Username is required in non-interactive mode"
            return $null
        }
    }
    
    if (-not $Password) {
        if ($Interactive) {
            $Password = Read-Host "Enter Management password" -AsSecureString
            $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
        } else {
            Write-Error "Password is required in non-interactive mode"
            return $null
        }
    }

    Write-ColorOutput "Authenticating to $MgmtServer..." -Color $Colors.Info

    $bodyObj = @{
        user = $User
        password = $Password
    }
    $body = $bodyObj | ConvertTo-Json -Depth 3

    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

    try {
        $url = if ($MgmtServer -notmatch "^https?://") { "https://$MgmtServer" } else { $MgmtServer }
        $resp = Invoke-RestMethod -Uri "$url/web_api/login" -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
        Write-ColorOutput "✓ Authentication successful" -Color $Colors.Success
        return $resp.sid
    }
    catch {
        Write-ColorOutput "✗ Authentication failed: $_" -Color $Colors.Error
        return $null
    }
}

function Logout {
    param($MgmtServer, $sid)
    try {
        $headers = @{ "X-chkp-sid" = $sid }
        $bodyObj = @{}
        $body = $bodyObj | ConvertTo-Json
        Invoke-RestMethod -Uri "$MgmtServer/web_api/logout" -Headers $headers -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
        Write-ColorOutput "✓ Logout completed" -Color $Colors.Success
    }
    catch {
        Write-ColorOutput "⚠ Logout failed or not necessary" -Color $Colors.Warning
    }
}

function DiscardChanges {
    param($MgmtServer, $sid)
    try {
        $headers = @{ "X-chkp-sid" = $sid }
        $bodyObj = @{}
        $body = $bodyObj | ConvertTo-Json
        Invoke-RestMethod -Uri "$MgmtServer/web_api/discard" -Headers $headers -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
        Write-ColorOutput "✓ Unpublished changes discarded" -Color $Colors.Warning
        return $true
    }
    catch {
        return $false
    }
}

function WaitForTask {
    param($MgmtServer, $sid, $taskId)
    
    Write-Host ""
    Write-ColorOutput "Waiting for task to complete..." -Color $Colors.Info
    
    $maxAttempts = 30
    $attempt = 0
    
    while ($attempt -lt $maxAttempts) {
        try {
            $headers = @{ "X-chkp-sid" = $sid }
            $bodyObj = @{ 
                "task-id" = $taskId
                "details-level" = "full"
            }
            $body = $bodyObj | ConvertTo-Json -Depth 3
            
            $taskStatus = Invoke-RestMethod -Uri "$MgmtServer/web_api/show-task" -Headers $headers -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
            
            if ($taskStatus.tasks -and $taskStatus.tasks.Count -gt 0) {
                $task = $taskStatus.tasks[0]
                $status = $task.status
                $progress = if ($task.'progress-percentage') { $task.'progress-percentage' } else { 0 }
                
                Write-ColorOutput "  Progress: $progress% - Status: $status" -Color $Colors.Subtle
                
                if ($status -eq "succeeded") {
                    Write-ColorOutput "✓ Task completed successfully" -Color $Colors.Success
                    return $true
                }
                elseif ($status -eq "failed") {
                    Write-ColorOutput "✗ Task failed" -Color $Colors.Error
                    if ($task.'task-details') {
                        Write-ColorOutput "  Error details:" -Color $Colors.Error
                        $task.'task-details' | ForEach-Object {
                            Write-ColorOutput "    $_" -Color $Colors.Error
                        }
                    }
                    return $false
                }
                elseif ($status -eq "partially succeeded") {
                    Write-ColorOutput "⚠ Task partially succeeded" -Color $Colors.Warning
                    if ($task.'task-details') {
                        Write-ColorOutput "  Details:" -Color $Colors.Warning
                        $task.'task-details' | ForEach-Object {
                            Write-ColorOutput "    $_" -Color $Colors.Warning
                        }
                    }
                    return $true
                }
            }
        }
        catch {
            Write-ColorOutput "⚠ Could not check task status: $_" -Color $Colors.Warning
            return $false
        }
        
        Start-Sleep -Seconds 2
        $attempt++
    }
    
    Write-ColorOutput "⚠ Task status check timed out after 60 seconds" -Color $Colors.Warning
    return $false
}

function GetPolicyPackages {
    param($MgmtServer, $sid)
    try {
        $headers = @{ "X-chkp-sid" = $sid }
        $bodyObj = @{ "details-level" = "full" }
        $body = $bodyObj | ConvertTo-Json -Depth 3
        
        $resp = Invoke-RestMethod -Uri "$MgmtServer/web_api/show-packages" -Headers $headers -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
        
        return $resp.packages
    }
    catch {
        Write-ColorOutput "✗ Error retrieving packages: $_" -Color $Colors.Error
        return @()
    }
}

function GetPackageDetails {
    param($MgmtServer, $sid, $packageName)
    try {
        $headers = @{ "X-chkp-sid" = $sid }
        $bodyObj = @{ 
            "name" = $packageName
            "details-level" = "full" 
        }
        $body = $bodyObj | ConvertTo-Json -Depth 3
        
        $resp = Invoke-RestMethod -Uri "$MgmtServer/web_api/show-package" -Headers $headers -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
        
        if ($resp.'access-layers') {
            return $resp.'access-layers'
        }
        else {
            return @()
        }
    }
    catch {
        Write-ColorOutput "✗ Error retrieving package details: $_" -Color $Colors.Error
        return @()
    }
}

function GetAccessRules {
    param($MgmtServer, $sid, $layerName)
    try {
        $headers = @{ "X-chkp-sid" = $sid }
        $bodyObj = @{
            name = $layerName
            "details-level" = "full"
            "use-object-dictionary" = $true
        }
        $body = $bodyObj | ConvertTo-Json -Depth 3
        
        $resp = Invoke-RestMethod -Uri "$MgmtServer/web_api/show-access-rulebase" -Headers $headers -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
        
        # Extract objects dictionary if present
        $objectDict = @{}
        if ($resp.'objects-dictionary') {
            foreach ($obj in $resp.'objects-dictionary') {
                $objectDict[$obj.uid] = $obj
            }
        }
        
        # Extract rules from response
        $rules = @()
        if ($resp.rulebase) {
            foreach ($item in $resp.rulebase) {
                if ($item.type -eq "access-rule") {
                    $rules += $item
                }
                elseif ($item.type -eq "access-section" -and $item.rulebase) {
                    foreach ($subItem in $item.rulebase) {
                        if ($subItem.type -eq "access-rule") {
                            $rules += $subItem
                        }
                    }
                }
            }
        }
        
        return @{
            rules = $rules
            objectDict = $objectDict
        }
    }
    catch {
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader ($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-ColorOutput "✗ Error retrieving rules: $responseBody" -Color $Colors.Error
        } else {
            Write-ColorOutput "✗ Error retrieving rules: $_" -Color $Colors.Error
        }
        return @{
            rules = @()
            objectDict = @{}
        }
    }
}

function SetAccessRuleLogging {
    param(
        $MgmtServer, 
        $sid, 
        $layerName, 
        $ruleUid, 
        $trackType,
        $accounting,
        $perConnection,
        $perSession
    )
    try {
        $headers = @{ "X-chkp-sid" = $sid }
        
        # Build track object - ALWAYS include all options
        $trackObj = @{
            type = $trackType
        }
        
        # ALWAYS set these options explicitly (true or false)
        # Don't use if conditions - always send the value
        $trackObj["accounting"] = [bool]$accounting
        $trackObj["per-connection"] = [bool]$perConnection
        $trackObj["per-session"] = [bool]$perSession
        
        $bodyObj = @{
            layer = $layerName
            uid = $ruleUid
            track = $trackObj
        }
        
              
        $body = $bodyObj | ConvertTo-Json -Depth 5

        $resp = Invoke-RestMethod -Uri "$MgmtServer/web_api/set-access-rule" -Headers $headers -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
               
        return @{ success = $true }
    }
    catch {
        $errorMessage = "Unknown error"
        
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader ($_.Exception.Response.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                $errorObj = $responseBody | ConvertFrom-Json
                
                if ($errorObj.errors -and $errorObj.errors.Count -gt 0) {
                    $errorMessage = $errorObj.errors[0].message
                } elseif ($errorObj.message) {
                    $errorMessage = $errorObj.message
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
            }
        } else {
            $errorMessage = $_.Exception.Message
        }
        
        return @{ success = $false; message = $errorMessage }
    }
}



function PublishPolicy {
    param($MgmtServer, $sid)
    try {
        $headers = @{ "X-chkp-sid" = $sid }
        $bodyObj = @{}
        $body = $bodyObj | ConvertTo-Json
        $resp = Invoke-RestMethod -Uri "$MgmtServer/web_api/publish" -Headers $headers -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
        
        if ($resp.'task-id') {
            Write-ColorOutput "✓ Publish request submitted" -Color $Colors.Success
            Write-ColorOutput "  Task ID: $($resp.'task-id')" -Color $Colors.Subtle
            
            $taskCompleted = WaitForTask -MgmtServer $MgmtServer -sid $sid -taskId $resp.'task-id'
            
            if ($taskCompleted) {
                Write-Host ""
                Write-ColorOutput "✓ Changes published successfully to database" -Color $Colors.Success
                return $true
            }
            else {
                Write-Host ""
                Write-ColorOutput "✗ Publish task failed or timed out" -Color $Colors.Error
                return $false
            }
        } 
        else {
            Write-ColorOutput "✓ Changes published successfully" -Color $Colors.Success
            return $true
        }
    }
    catch {
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader ($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-ColorOutput "✗ Publish error: $responseBody" -Color $Colors.Error
        } else {
            Write-ColorOutput "✗ Publish error: $_" -Color $Colors.Error
        }
        return $false
    }
}

function GetTrackValue {
    param($trackObj, $objectDict)
    
    if (-not $trackObj) {
        return "None"
    }
    
    $trackName = "None"
    
    if ($trackObj -is [string]) {
        if ($objectDict.ContainsKey($trackObj)) {
            $trackName = $objectDict[$trackObj].name
        } else {
            $trackName = $trackObj
        }
    }
    elseif ($trackObj.type) {
        if ($objectDict.ContainsKey($trackObj.type)) {
            $trackName = $objectDict[$trackObj.type].name
        } else {
            $trackName = $trackObj.type
        }
    }
    elseif ($trackObj.name) {
        $trackName = $trackObj.name
    }
    elseif ($trackObj.uid) {
        if ($objectDict.ContainsKey($trackObj.uid)) {
            $trackName = $objectDict[$trackObj.uid].name
        } else {
            $trackName = $trackObj.uid
        }
    }
    
    $details = @()
    if ($trackObj.accounting) {
        $details += "Accounting"
    }
    if ($trackObj.'per-connection') {
        $details += "per Connection"
    }
    if ($trackObj.'per-session') {
        $details += "per Session"
    }
    
    if ($details.Count -gt 0) {
        return "$trackName [$($details -join ', ')]"
    }
    
    return $trackName
}

function BuildTrackDescription {
    param($trackType, $accounting, $perConnection, $perSession)
    
    $trackName = switch ($trackType) {
        "none" { "None" }
        "log" { "Log" }
        "detailed log" { "Detailed Log" }
        "extended log" { "Extended Log" }
        default { $trackType }
    }
    
    $details = @()
    if ($accounting) {
        $details += "Accounting"
    }
    if ($perConnection) {
        $details += "per Connection"
    }
    if ($perSession) {
        $details += "per Session"
    }
    
    if ($details.Count -gt 0) {
        return "$trackName [$($details -join ', ')]"
    }
    
    return $trackName
}

# ============================================
# MAIN SCRIPT
# ============================================

# Normalize and validate TrackType parameter
if ($TrackType) {
    $normalizedTrackType = Normalize-TrackType -TrackType $TrackType
    if ($null -eq $normalizedTrackType) {
        exit 1
    }
    $TrackType = $normalizedTrackType
}

# Validate non-interactive mode parameters
if (-not $Interactive) {
    $missingParams = @()
    
    if (-not $User) { $missingParams += "User" }
    if (-not $Password) { $missingParams += "Password" }
    if (-not $PackageName) { $missingParams += "PackageName" }
    if (-not $TrackType) { $missingParams += "TrackType" }
    if (-not $RuleSelection -and -not $RuleNumbers -and -not $RuleNames) {
        $missingParams += "RuleSelection, RuleNumbers, or RuleNames"
    }
    
    if ($missingParams.Count -gt 0) {
        Write-Error "Non-interactive mode requires the following parameters: $($missingParams -join ', ')"
        exit 1
    }
}

if (-not $Quiet) {
    Write-Host ""
    Write-ColorOutput "═══════════════════════════════════════════════════════════" -Color $Colors.Highlight
    Write-ColorOutput "  Check Point Quantum - Access Rule Logging Configuration" -Color $Colors.Highlight
    Write-ColorOutput "═══════════════════════════════════════════════════════════" -Color $Colors.Highlight
    Write-Host ""
}

if ($MgmtServer -notmatch "^https?://") {
    $MgmtServer = "https://$MgmtServer"
}

$sid = Authenticate -MgmtServer $MgmtServer -User $User -Password $Password
if (-not $sid) {
    Write-ColorOutput "Unable to authenticate. Exiting." -Color $Colors.Error
    exit 1
}

$changesPublished = $false

try {
    # Discard any pending changes
    DiscardChanges -MgmtServer $MgmtServer -sid $sid | Out-Null

    # Retrieve policy packages
    Write-ColorOutput "`nRetrieving policy packages..." -Color $Colors.Info
    $packages = GetPolicyPackages -MgmtServer $MgmtServer -sid $sid

    if ($packages.Count -eq 0) {
        Write-ColorOutput "No packages found." -Color $Colors.Warning
        exit 1
    }

    # Select package
    if (-not $PackageName) {
        if ($Interactive) {
            Write-Host ""
            Write-ColorOutput "Available Policy Packages:" -Color $Colors.Highlight
            Write-Host ""
            for ($i=0; $i -lt $packages.Count; $i++) {
                Write-ColorOutput "  [$($i+1)]" -Color $Colors.Info -NoNewline
                Write-Host " $($packages[$i].name)"
            }
            Write-Host ""
            
            do {
                $scelta = Read-Host "Select package number"
            } while (-not ($scelta -match "^\d+$") -or [int]$scelta -lt 1 -or [int]$scelta -gt $packages.Count)
            
            $PackageName = $packages[[int]$scelta - 1].name
        } else {
            Write-Error "PackageName is required in non-interactive mode"
            exit 1
        }
    }
    
    # Validate package name
    $selectedPackage = $packages | Where-Object { $_.name -eq $PackageName }
    if (-not $selectedPackage) {
        Write-ColorOutput "✗ Package '$PackageName' not found" -Color $Colors.Error
        exit 1
    }
    
    Write-ColorOutput "`n→ Using package: " -Color $Colors.Subtle -NoNewline
    Write-ColorOutput $PackageName -Color $Colors.Highlight

    # Retrieve layers
    $packageLayers = GetPackageDetails -MgmtServer $MgmtServer -sid $sid -packageName $PackageName
    
    if (-not $packageLayers -or $packageLayers.Count -eq 0) {
        Write-ColorOutput "No access layers found for package '$PackageName'." -Color $Colors.Warning
        exit 1
    }

    if ($packageLayers -isnot [System.Array]) {
        $packageLayers = @($packageLayers)
    }

    # Select layer
    if ($packageLayers.Count -eq 1) {
        $layerSelezionato = $packageLayers[0].name
        Write-ColorOutput "→ Access layer: " -Color $Colors.Subtle -NoNewline
        Write-ColorOutput $layerSelezionato -Color $Colors.Highlight
    }
    elseif ($LayerName) {
        $selectedLayer = $packageLayers | Where-Object { $_.name -eq $LayerName }
        if ($selectedLayer) {
            $layerSelezionato = $LayerName
            Write-ColorOutput "→ Access layer: " -Color $Colors.Subtle -NoNewline
            Write-ColorOutput $layerSelezionato -Color $Colors.Highlight
        } else {
            Write-ColorOutput "✗ Layer '$LayerName' not found" -Color $Colors.Error
            exit 1
        }
    }
    else {
        if ($Interactive) {
            Write-Host ""
            Write-ColorOutput "Available Access Layers:" -Color $Colors.Highlight
            Write-Host ""
            for ($i=0; $i -lt $packageLayers.Count; $i++) {
                Write-ColorOutput "  [$($i+1)]" -Color $Colors.Info -NoNewline
                Write-Host " $($packageLayers[$i].name)"
            }
            Write-Host ""
            
            do {
                $sceltaLayer = Read-Host "Select access layer number"
            } while (-not ($sceltaLayer -match "^\d+$") -or [int]$sceltaLayer -lt 1 -or [int]$sceltaLayer -gt $packageLayers.Count)
            
            $layerSelezionato = $packageLayers[[int]$sceltaLayer - 1].name
        } else {
            Write-Error "LayerName is required when package has multiple layers in non-interactive mode"
            exit 1
        }
    }

    # Retrieve rules
    Write-ColorOutput "`nRetrieving rules from layer '$layerSelezionato'..." -Color $Colors.Info
    $response = GetAccessRules -MgmtServer $MgmtServer -sid $sid -layerName $layerSelezionato
    $rules = $response.rules
    $objectDict = $response.objectDict
    
    if ($rules.Count -eq 0) {
        Write-ColorOutput "No rules found in this layer." -Color $Colors.Warning
        exit 0
    }

    Write-ColorOutput "✓ Found $($rules.Count) rules" -Color $Colors.Success
    
    if (-not $Quiet) {
        Write-Host ""
        Write-ColorOutput "─────────────────────────────────────────────────────────" -Color $Colors.Subtle
    }

    # Display rules
    $i = 1
    $rules | ForEach-Object {
        $trackVal = GetTrackValue -trackObj $_.track -objectDict $objectDict
        
        if (-not $Quiet) {
            Write-ColorOutput "  [$i]" -Color $Colors.Info -NoNewline
            Write-Host " $($_.name) " -NoNewline
            Write-ColorOutput "→ " -Color $Colors.Subtle -NoNewline
            Write-ColorOutput $trackVal -Color $Colors.Highlight
        }
        
        $_ | Add-Member -MemberType NoteProperty -Name Index -Value $i -Force
        $_ | Add-Member -MemberType NoteProperty -Name TrackValue -Value $trackVal -Force
        $i++
    }
    
    if (-not $Quiet) {
        Write-ColorOutput "─────────────────────────────────────────────────────────" -Color $Colors.Subtle
    }

    # Select rules to modify
    $toModify = @()
    
    # Check if RuleSelection is "all" OR RuleNumbers contains "all"
    if ($RuleSelection -eq "all" -or ($RuleNumbers -and $RuleNumbers[0] -eq "all")) {
        $toModify = $rules
    }
    elseif ($RuleNumbers) {
        foreach ($num in $RuleNumbers) {
            # Skip if it's "all" (already handled above)
            if ($num -eq "all") { continue }
            
            # Try to parse as integer
            $numInt = 0
            if ([int]::TryParse($num, [ref]$numInt)) {
                $matchRule = $rules | Where-Object { $_.Index -eq $numInt }
                if ($matchRule) { 
                    $toModify += $matchRule 
                } else {
                    Write-ColorOutput "⚠ Rule number $num not found" -Color $Colors.Warning
                }
            } else {
                Write-ColorOutput "⚠ Invalid rule number: $num" -Color $Colors.Warning
            }
        }
    }
    elseif ($RuleNames) {
        foreach ($name in $RuleNames) {
            $matchRule = $rules | Where-Object { $_.name -eq $name }
            if ($matchRule) { 
                $toModify += $matchRule 
            } else {
                Write-ColorOutput "⚠ Rule '$name' not found" -Color $Colors.Warning
            }
        }
    }
    elseif ($Interactive) {
        Write-Host ""
        $inputRules = Read-Host "Enter rule numbers to modify (comma-separated, or 'all' for all)"
        
        if ($inputRules -eq "all") {
            $toModify = $rules
        }
        elseif ($inputRules) {
            $indexes = $inputRules -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
            foreach ($idx in $indexes) {
                $matchRule = $rules | Where-Object { $_.Index -eq [int]$idx }
                if ($matchRule) { $toModify += $matchRule }
            }
        }
    }

    if ($toModify.Count -eq 0) {
        Write-ColorOutput "No rules selected for modification." -Color $Colors.Warning
        exit 0
    }

    # Show selected rules
    Write-Host ""
    Write-ColorOutput "Selected Rules ($($toModify.Count)):" -Color $Colors.Highlight
    Write-Host ""
    $toModify | ForEach-Object {
        Write-ColorOutput "  • " -Color $Colors.Subtle -NoNewline
        Write-Host "$($_.name) " -NoNewline
        Write-ColorOutput "(current: " -Color $Colors.Subtle -NoNewline
        Write-ColorOutput "$($_.TrackValue)" -Color $Colors.Info -NoNewline
        Write-ColorOutput ")" -Color $Colors.Subtle
    }
    
    # Get track configuration
    $configurationDone = $false
    $newTrackDescription = ""
    $selectedTrackType = $TrackType
    $selectedAccounting = $Accounting.IsPresent
    $selectedPerConnection = $PerConnection.IsPresent
    $selectedPerSession = $PerSession.IsPresent
    
    while (-not $configurationDone) {
        if ($Interactive -and -not $TrackType) {
            Write-Host ""
            Write-ColorOutput "═══════════════════════════════════════════════════════════" -Color $Colors.Highlight
            Write-ColorOutput "  Track Configuration" -Color $Colors.Highlight
            Write-ColorOutput "═══════════════════════════════════════════════════════════" -Color $Colors.Highlight
            Write-Host ""
            Write-ColorOutput "  [1]" -Color $Colors.Info -NoNewline
            Write-Host " None - No logging"
            Write-ColorOutput "  [2]" -Color $Colors.Info -NoNewline
            Write-Host " Log - Standard logging"
            Write-ColorOutput "  [3]" -Color $Colors.Info -NoNewline
            Write-Host " Detailed Log - Detailed logging"
            Write-ColorOutput "  [4]" -Color $Colors.Info -NoNewline
            Write-Host " Extended Log - Extended logging"
            Write-Host ""
            
            do {
                $trackChoice = Read-Host "Select track type"
            } while ($trackChoice -notin @("1", "2", "3", "4"))
            
            $selectedTrackType = switch ($trackChoice) {
                "1" { "none" }
                "2" { "log" }
                "3" { "detailed log" }
                "4" { "extended log" }
            }
            
            if ($selectedTrackType -ne "none") {
                Write-Host ""
                $accountingInput = Read-Host "Enable Accounting? (y/n)"
                $selectedAccounting = $accountingInput -eq "y"
                
                $perConnectionInput = Read-Host "Log per Connection? (y/n)"
                $selectedPerConnection = $perConnectionInput -eq "y"
                
                $perSessionInput = Read-Host "Log per Session? (y/n)"
                $selectedPerSession = $perSessionInput -eq "y"
            }
        }
        
        $newTrackDescription = BuildTrackDescription -trackType $selectedTrackType -accounting $selectedAccounting -perConnection $selectedPerConnection -perSession $selectedPerSession
        
        # Test configuration on first rule
        Write-Host ""
        Write-ColorOutput "Testing configuration on first rule..." -Color $Colors.Info
        $testResult = SetAccessRuleLogging -MgmtServer $MgmtServer -sid $sid -layerName $layerSelezionato -ruleUid $toModify[0].uid -trackType $selectedTrackType -accounting $selectedAccounting -perConnection $selectedPerConnection -perSession $selectedPerSession
        
        if ($testResult.success) {
            Write-ColorOutput "✓ Configuration is valid!" -Color $Colors.Success
            $configurationDone = $true
            
            # Apply to other rules
            if ($toModify.Count -gt 1) {
                Write-Host ""
                Write-ColorOutput "Applying to remaining rules..." -Color $Colors.Info
                $successCount = 1
                for ($i = 1; $i -lt $toModify.Count; $i++) {
                    Write-ColorOutput "  → Modifying rule '$($toModify[$i].name)'..." -Color $Colors.Subtle
                    $result = SetAccessRuleLogging -MgmtServer $MgmtServer -sid $sid -layerName $layerSelezionato -ruleUid $toModify[$i].uid -trackType $selectedTrackType -accounting $selectedAccounting -perConnection $selectedPerConnection -perSession $selectedPerSession
                    if ($result.success) {
                        $successCount++
                    }
                }
                Write-Host ""
                Write-ColorOutput "✓ Modified $successCount of $($toModify.Count) rules" -Color $Colors.Success
            } else {
                Write-Host ""
                Write-ColorOutput "✓ Modified 1 rule" -Color $Colors.Success
            }
        }
        else {
            Write-Host ""
            Write-ColorOutput "✗ Error: $($testResult.message)" -Color $Colors.Error
            
            if ($Interactive) {
                Write-Host ""
                $retry = Read-Host "Do you want to choose a different configuration? (y/n)"
                if ($retry -ne "y") {
                    Write-ColorOutput "Operation cancelled." -Color $Colors.Warning
                    DiscardChanges -MgmtServer $MgmtServer -sid $sid | Out-Null
                    exit 0
                }
                # Reset TrackType to force re-prompting
                $selectedTrackType = ""
            } else {
                Write-ColorOutput "Operation failed in non-interactive mode." -Color $Colors.Error
                DiscardChanges -MgmtServer $MgmtServer -sid $sid | Out-Null
                exit 1
            }
        }
    }

    # Show summary
    if ($configurationDone -and -not $Quiet) {
        Write-Host ""
        Write-ColorOutput "═══════════════════════════════════════════════════════════" -Color $Colors.Highlight
        Write-ColorOutput "  Changes Summary" -Color $Colors.Highlight
        Write-ColorOutput "═══════════════════════════════════════════════════════════" -Color $Colors.Highlight
        Write-Host ""
        
        $toModify | ForEach-Object {
            Write-ColorOutput "  • " -Color $Colors.Subtle -NoNewline
            Write-Host "$($_.name)" -NoNewline
            Write-Host ""
            Write-ColorOutput "    Before: " -Color $Colors.Subtle -NoNewline
            Write-ColorOutput "$($_.TrackValue)" -Color $Colors.Info
            Write-ColorOutput "    After:  " -Color $Colors.Subtle -NoNewline
            Write-ColorOutput "$newTrackDescription" -Color $Colors.Success
            Write-Host ""
        }
        
        Write-ColorOutput "─────────────────────────────────────────────────────────" -Color $Colors.Subtle
    }

    # Publish changes
    if ($configurationDone) {
        $shouldPublish = $false
        
        if ($AutoPublish) {
            $shouldPublish = $true
        }
        elseif ($Publish -or $Interactive) {
            if ($Interactive) {
                Write-Host ""
                $publishChoice = Read-Host "Publish changes? (y/n)"
                $shouldPublish = $publishChoice -eq "y"
            } else {
                $shouldPublish = $Publish.IsPresent
            }
        }
        
        if ($shouldPublish) {
            $changesPublished = PublishPolicy -MgmtServer $MgmtServer -sid $sid
        }
        else {
            Write-Host ""
            Write-ColorOutput "Discarding unpublished changes..." -Color $Colors.Info
            DiscardChanges -MgmtServer $MgmtServer -sid $sid
        }
    }

    # Reminder
    if ($changesPublished) {
        Write-Host ""
        Write-ColorOutput "⚠ NEXT STEP: Install the policy manually through SmartConsole" -Color $Colors.Warning
        Write-ColorOutput "  to apply the changes to your gateways." -Color $Colors.Subtle
    }
    
    if (-not $Quiet) {
        Write-Host ""
        Write-ColorOutput "═══════════════════════════════════════════════════════════" -Color $Colors.Highlight
        if ($changesPublished) {
            Write-ColorOutput "  Operation Completed Successfully" -Color $Colors.Success
        }
        else {
            Write-ColorOutput "  Operation Completed (No Changes Published)" -Color $Colors.Warning
        }
        Write-ColorOutput "═══════════════════════════════════════════════════════════" -Color $Colors.Highlight
        Write-Host ""
    }
}
finally {
    Logout -MgmtServer $MgmtServer -sid $sid
}



