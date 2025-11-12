<#
.SYNOPSIS
    Check Point Quantum Access Rule Logging Configuration Tool

.DESCRIPTION
    This script allows you to configure logging settings (Track) for Check Point Quantum access rules via Management API.
    Supports: Log, Detailed Log, Extended Log, None, Accounting, per-Connection, per-Session options.

.PARAMETER MgmtServer
    Management server address (IP or hostname)

.PARAMETER User
    Management API username

.PARAMETER Password
    Management API password

.PARAMETER PackageName
    Policy package name (optional, will be prompted if not provided)

.PARAMETER LayerName
    Access layer name (optional, will be prompted if not provided)

.PARAMETER Publish
    Automatically publish changes after modification

.PARAMETER Interactive
    Enable interactive mode (default: true)

.EXAMPLE
    .\Quantum-Change-Logging.ps1 -MgmtServer 192.168.100.10 -User admin -Password Passw0rd

.NOTES
    Author: Check Point
    Version: 1.3
    
    IMPORTANT: Policy installation functionality is DISABLED by default.
    Automatic policy installation is considered too risky as it has not been tested 
    in all scenarios and could potentially install the wrong policy on the wrong 
    gateway, leading to service disruption or security issues.
    
    Users should manually install policies through SmartConsole after verifying
    the changes in the published policy package.
#>

param(
    [string]$MgmtServer,
    [string]$User,
    [string]$Password,
    [string]$PackageName,
    [string]$LayerName,
    [switch]$Publish,
    [switch]$Interactive = $true
    # [switch]$Install  # DISABLED: Policy installation disabled for safety reasons
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
    
    if ($NoNewline) {
        Write-Host $Message -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Authenticate {
    param($MgmtServer, $User, $Password)

    if (-not $User) { 
        $User = Read-Host "Enter Management username" 
    }
    if (-not $Password) {
        $Password = Read-Host "Enter Management password" -AsSecureString
        $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
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
                # else: still in progress, continue loop
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
            # Rulebase can contain both direct rules and sections
            foreach ($item in $resp.rulebase) {
                if ($item.type -eq "access-rule") {
                    $rules += $item
                }
                elseif ($item.type -eq "access-section" -and $item.rulebase) {
                    # Section with nested rules
                    foreach ($subItem in $item.rulebase) {
                        if ($subItem.type -eq "access-rule") {
                            $rules += $subItem
                        }
                    }
                }
            }
        }
        
        # Return both rules and dictionary
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
        
        # Build track object
        $trackObj = @{
            type = $trackType
        }
        
        # Add options if specified
        if ($accounting) {
            $trackObj["accounting"] = $true
        }
        if ($perConnection) {
            $trackObj["per-connection"] = $true
        }
        if ($perSession) {
            $trackObj["per-session"] = $true
        }
        
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
                
                # Extract only error message
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
        
        # Check if publish returned a task ID
        if ($resp.'task-id') {
            Write-ColorOutput "✓ Publish request submitted" -Color $Colors.Success
            Write-ColorOutput "  Task ID: $($resp.'task-id')" -Color $Colors.Subtle
            
            # Wait for task completion
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

<#
.SYNOPSIS
    Installs a policy package on its target gateways

.DESCRIPTION
    This function is DISABLED for safety reasons. Automatic policy installation
    has not been tested in all scenarios and poses significant risks:
    
    - Could install policy on wrong gateway/cluster
    - May cause service disruption if policy has errors
    - No validation of target gateway readiness
    - Potential for network connectivity loss
    - Difficult to rollback if issues occur
    
    RECOMMENDATION: Always install policies manually through SmartConsole after 
    thorough review and verification of the changes.

.PARAMETER MgmtServer
    Management server address

.PARAMETER sid
    Session ID from authentication

.PARAMETER packageName
    Name of the policy package to install

.NOTES
    To enable this function, uncomment the code below and the -Install parameter
    in the script parameters section. Use at your own risk.
#>
function InstallPolicy {
    param($MgmtServer, $sid, $packageName)
    
    # DISABLED: Policy installation is disabled for safety reasons
    Write-ColorOutput "⚠ Policy installation is disabled for safety" -Color $Colors.Warning
    Write-ColorOutput "  Please install the policy manually through SmartConsole" -Color $Colors.Subtle
    return $false
}

function GetTrackValue {
    param($trackObj, $objectDict)
    
    if (-not $trackObj) {
        return "None"
    }
    
    $trackName = "None"
    
    # If it's a string (UID), look it up in dictionary
    if ($trackObj -is [string]) {
        if ($objectDict.ContainsKey($trackObj)) {
            $trackName = $objectDict[$trackObj].name
        } else {
            $trackName = $trackObj
        }
    }
    # If it's an object with 'type' field
    elseif ($trackObj.type) {
        # The type field may contain a UID, look it up in dictionary
        if ($objectDict.ContainsKey($trackObj.type)) {
            $trackName = $objectDict[$trackObj.type].name
        } else {
            $trackName = $trackObj.type
        }
    }
    # If it's an object with 'name' field
    elseif ($trackObj.name) {
        $trackName = $trackObj.name
    }
    # If it's an object with 'uid' field
    elseif ($trackObj.uid) {
        if ($objectDict.ContainsKey($trackObj.uid)) {
            $trackName = $objectDict[$trackObj.uid].name
        } else {
            $trackName = $trackObj.uid
        }
    }
    
    # Add information about accounting, per-connection, per-session
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
    
    # Convert track type to display name
    $trackName = switch ($trackType) {
        "none" { "None" }
        "log" { "Log" }
        "detailed log" { "Detailed Log" }
        "extended log" { "Extended Log" }
        default { $trackType }
    }
    
    # Build details list
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

Write-Host ""
Write-ColorOutput "═══════════════════════════════════════════════════════════" -Color $Colors.Highlight
Write-ColorOutput "  Check Point Quantum - Access Rule Logging Configuration" -Color $Colors.Highlight
Write-ColorOutput "═══════════════════════════════════════════════════════════" -Color $Colors.Highlight
Write-Host ""

if (-not $MgmtServer) {
    $MgmtServer = Read-Host "Enter Management Server address (with https://)"
}
if ($MgmtServer -notmatch "^https?://") {
    $MgmtServer = "https://$MgmtServer"
}

$sid = Authenticate -MgmtServer $MgmtServer -User $User -Password $Password
if (-not $sid) {
    Write-ColorOutput "Unable to authenticate. Exiting." -Color $Colors.Error
    exit 1
}

# Track if changes were published
$changesPublished = $false

try {
    # Discard any pending changes from previous sessions
    DiscardChanges -MgmtServer $MgmtServer -sid $sid | Out-Null

    # Retrieve policy packages
    Write-ColorOutput "`nRetrieving policy packages..." -Color $Colors.Info
    $packages = GetPolicyPackages -MgmtServer $MgmtServer -sid $sid

    if ($packages.Count -eq 0) {
        Write-ColorOutput "No packages found." -Color $Colors.Warning
        exit 1
    }

    if (-not $PackageName) {
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
    }
    
    Write-ColorOutput "`n→ Using package: " -Color $Colors.Subtle -NoNewline
    Write-ColorOutput $PackageName -Color $Colors.Highlight

    # Retrieve layers associated with selected package
    $packageLayers = GetPackageDetails -MgmtServer $MgmtServer -sid $sid -packageName $PackageName
    
    if (-not $packageLayers -or $packageLayers.Count -eq 0) {
        Write-ColorOutput "No access layers found for package '$PackageName'." -Color $Colors.Warning
        exit 1
    }

    # Convert to array if single object
    if ($packageLayers -isnot [System.Array]) {
        $packageLayers = @($packageLayers)
    }

    # If there's only one layer, select it automatically
    if ($packageLayers.Count -eq 1) {
        $layerSelezionato = $packageLayers[0].name
        Write-ColorOutput "→ Access layer: " -Color $Colors.Subtle -NoNewline
        Write-ColorOutput $layerSelezionato -Color $Colors.Highlight
    }
    else {
        Write-Host ""
        Write-ColorOutput "Available Access Layers in package '$PackageName':" -Color $Colors.Highlight
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
    }

    # Retrieve access rules from selected layer
    Write-ColorOutput "`nRetrieving rules from layer '$layerSelezionato'..." -Color $Colors.Info
    $response = GetAccessRules -MgmtServer $MgmtServer -sid $sid -layerName $layerSelezionato
    $rules = $response.rules
    $objectDict = $response.objectDict
    
    if ($rules.Count -eq 0) {
        Write-ColorOutput "No rules found in this layer." -Color $Colors.Warning
        exit 0
    }

    Write-ColorOutput "✓ Found $($rules.Count) rules" -Color $Colors.Success
    Write-Host ""
    Write-ColorOutput "─────────────────────────────────────────────────────────" -Color $Colors.Subtle

    # Display rules with logging status
    $i = 1
    $rules | ForEach-Object {
        $trackVal = GetTrackValue -trackObj $_.track -objectDict $objectDict
        
        Write-ColorOutput "  [$i]" -Color $Colors.Info -NoNewline
        Write-Host " $($_.name) " -NoNewline
        Write-ColorOutput "→ " -Color $Colors.Subtle -NoNewline
        Write-ColorOutput $trackVal -Color $Colors.Highlight
        
        $_ | Add-Member -MemberType NoteProperty -Name Index -Value $i -Force
        $_ | Add-Member -MemberType NoteProperty -Name TrackValue -Value $trackVal -Force
        $i++
    }
    
    Write-ColorOutput "─────────────────────────────────────────────────────────" -Color $Colors.Subtle

    # Select rules to modify
    $toModify = @()
    if ($Interactive) {
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
    
    # Logging configuration loop with retry
    $configurationDone = $false
    $newTrackDescription = ""
    
    while (-not $configurationDone) {
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
        
        $trackType = switch ($trackChoice) {
            "1" { "none" }
            "2" { "log" }
            "3" { "detailed log" }
            "4" { "extended log" }
        }
        
        # Additional options (only if not "none")
        $accounting = $false
        $perConnection = $false
        $perSession = $false
        
        if ($trackType -ne "none") {
            Write-Host ""
            $accountingInput = Read-Host "Enable Accounting? (y/n)"
            $accounting = $accountingInput -eq "y"
            
            $perConnectionInput = Read-Host "Log per Connection? (y/n)"
            $perConnection = $perConnectionInput -eq "y"
            
            $perSessionInput = Read-Host "Log per Session? (y/n)"
            $perSession = $perSessionInput -eq "y"
        }
        
        # Build new track description
        $newTrackDescription = BuildTrackDescription -trackType $trackType -accounting $accounting -perConnection $perConnection -perSession $perSession
        
        # Test configuration on first rule
        Write-Host ""
        Write-ColorOutput "Testing configuration on first rule..." -Color $Colors.Info
        $testResult = SetAccessRuleLogging -MgmtServer $MgmtServer -sid $sid -layerName $layerSelezionato -ruleUid $toModify[0].uid -trackType $trackType -accounting $accounting -perConnection $perConnection -perSession $perSession
        
        if ($testResult.success) {
            Write-ColorOutput "✓ Configuration is valid!" -Color $Colors.Success
            $configurationDone = $true
            
            # Apply to other rules if there are any
            if ($toModify.Count -gt 1) {
                Write-Host ""
                Write-ColorOutput "Applying to remaining rules..." -Color $Colors.Info
                $successCount = 1
                for ($i = 1; $i -lt $toModify.Count; $i++) {
                    Write-ColorOutput "  → Modifying rule '$($toModify[$i].name)'..." -Color $Colors.Subtle
                    $result = SetAccessRuleLogging -MgmtServer $MgmtServer -sid $sid -layerName $layerSelezionato -ruleUid $toModify[$i].uid -trackType $trackType -accounting $accounting -perConnection $perConnection -perSession $perSession
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
            Write-Host ""
            $retry = Read-Host "Do you want to choose a different configuration? (y/n)"
            if ($retry -ne "y") {
                Write-ColorOutput "Operation cancelled." -Color $Colors.Warning
                # Discard changes before exit
                Write-ColorOutput "Discarding unpublished changes..." -Color $Colors.Info
                DiscardChanges -MgmtServer $MgmtServer -sid $sid | Out-Null
                exit 0
            }
        }
    }

    # Show summary before publish
    if ($configurationDone) {
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
    if ($configurationDone -and ($Publish -or $Interactive)) {
        Write-Host ""
        $publishChoice = Read-Host "Publish changes? (y/n)"
        if ($publishChoice -eq "y") {
            $changesPublished = PublishPolicy -MgmtServer $MgmtServer -sid $sid
            # After successful publish, locks are automatically released by Check Point API
            # DO NOT discard after publish - it would undo the published changes!
        }
        else {
            # User chose not to publish, discard changes to release locks
            Write-Host ""
            Write-ColorOutput "Discarding unpublished changes..." -Color $Colors.Info
            DiscardChanges -MgmtServer $MgmtServer -sid $sid
        }
    }

    <#
    # POLICY INSTALLATION - DISABLED FOR SAFETY
    # 
    # Automatic policy installation is disabled because:
    # - Not tested in all deployment scenarios
    # - Risk of installing on wrong gateway/cluster
    # - Could cause service disruption
    # - Difficult to rollback automatically
    # 
    # To enable, uncomment this section and add -Install parameter above
    
    # Install policy (only if published)
    if ($changesPublished -and ($Install -or $Interactive)) {
        Write-Host ""
        $installChoice = Read-Host "Install policy now? (y/n)"
        if ($installChoice -eq "y") {
            InstallPolicy -MgmtServer $MgmtServer -sid $sid -packageName $PackageName | Out-Null
        }
    }
    #>
    
    # Reminder to install policy manually
    if ($changesPublished) {
        Write-Host ""
        Write-ColorOutput "⚠ NEXT STEP: Install the policy manually through SmartConsole" -Color $Colors.Warning
        Write-ColorOutput "  to apply the changes to your gateways." -Color $Colors.Subtle
    }
    
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
finally {
    Logout -MgmtServer $MgmtServer -sid $sid
}
