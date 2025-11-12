# Check Point Quantum - Access Rule Logging Configuration

PowerShell script to configure logging settings (Track) for Check Point Quantum access rules via Management API.

## ✨ Features

- **Interactive & Non-Interactive Modes** - Run interactively or fully automated via command-line parameters
- **Flexible Logging Options** - Supports Log, Detailed Log, Extended Log, and None
- **Advanced Options** - Accounting, per-Connection, and per-Session logging
- **Batch Processing** - Modify single or multiple rules at once (by number, name, or all)
- **Safe Operations** - Automatic session cleanup and validation with changes summary before publish
- **Configuration Validation** - Tests settings on first rule before applying to all
- **Color-coded Output** - Enhanced readability with visual feedback
- **Change Summary** - Review all modifications before publishing
- **Real-time Task Monitoring** - Live progress tracking for publish operations
- **Flexible TrackType Input** - Accepts multiple formats (spaces, dashes, abbreviations)
- **Quiet Mode** - Suppress non-essential output for automation

## 📋 Requirements

- PowerShell 5.1 or higher
- Check Point Management Server R80.10 or higher
- Valid Management API credentials
- Network access to Check Point Management API (HTTPS)

## 🚀 Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/MaxCere/CHKP-Quantum-API.git
   cd CHKP-Quantum-API
   ```

2. No additional dependencies required - uses built-in PowerShell modules

## 💻 Usage

### Interactive Mode (Default)

Run the script interactively with prompts:

```powershell
.\Quantum-Change-Logging.ps1 -MgmtServer 192.168.100.10
```

### Non-Interactive Mode (Automation)

Fully automated - modify all rules:

```powershell
.\Quantum-Change-Logging.ps1 `
    -MgmtServer 192.168.100.10 `
    -User admin `
    -Password "YourPassword" `
    -PackageName "Standard" `
    -RuleSelection all `
    -TrackType log `
    -Accounting `
    -PerConnection `
    -AutoPublish `
    -Interactive:$false
```

Modify specific rules by number:

```powershell
.\Quantum-Change-Logging.ps1 `
    -MgmtServer 192.168.100.10 `
    -User admin `
    -Password "YourPassword" `
    -PackageName "Standard" `
    -RuleNumbers @("1","3","5") `
    -TrackType "extended log" `
    -Accounting `
    -AutoPublish `
    -Interactive:$false
```

Modify rules by name:

```powershell
.\Quantum-Change-Logging.ps1 `
    -MgmtServer 192.168.100.10 `
    -User admin `
    -Password "YourPassword" `
    -PackageName "Standard" `
    -RuleNames @("Grafana Access","N8N Web Access") `
    -TrackType extended-log `
    -AutoPublish `
    -Interactive:$false `
    -Quiet
```

With environment variables:

```powershell
$env:CHKP_USER = "admin"
$env:CHKP_PASSWORD = "YourPassword"

.\Quantum-Change-Logging.ps1 `
    -MgmtServer 192.168.100.10 `
    -User $env:CHKP_USER `
    -Password $env:CHKP_PASSWORD `
    -PackageName "Standard" `
    -RuleSelection all `
    -TrackType log `
    -AutoPublish `
    -Interactive:$false
```

## 📝 Parameters

| Parameter       | Type     | Required | Description                                                  |
|-----------------|----------|----------|--------------------------------------------------------------|
| -MgmtServer     | String   | Yes      | Management server address (IP or hostname with https://)     |
| -User           | String   | No*      | Management API username (*required in non-interactive mode)  |
| -Password       | String   | No*      | Management API password (*required in non-interactive mode)  |
| -PackageName    | String   | No*      | Policy package name (*required in non-interactive mode)      |
| -LayerName      | String   | No       | Access layer name (auto-selected if only one)                |
| -RuleSelection  | String   | No       | Select rules: "all" for all rules                            |
| -RuleNumbers    | String[] | No       | Array of rule numbers (e.g., @("1","3","5") or "all")        |
| -RuleNames      | String[] | No       | Array of rule names (e.g., @("Rule1","Rule2"))               |
| -TrackType      | String   | No*      | Track type (see options below) (*required in non-interactive)|
| -Accounting     | Switch   | No       | Enable Accounting option                                     |
| -PerConnection  | Switch   | No       | Enable per-Connection logging                                |
| -PerSession     | Switch   | No       | Enable per-Session logging                                   |
| -Publish        | Switch   | No       | Publish changes (will prompt for confirmation)               |
| -AutoPublish    | Switch   | No       | Automatically publish changes without confirmation           |
| -Interactive    | Switch   | No       | Enable interactive mode (default: true)                      |
| -Quiet          | Switch   | No       | Suppress non-essential output                                |

## ⚙️ Configuration Options

### Track Types

The `-TrackType` parameter accepts multiple formats:

| Format          | Aliases                           | Result         |
|-----------------|-----------------------------------|----------------|
| none            | none                              | None           |
| log             | log                               | Log            |
| detailed-log    | detail, detailed, "detailed log"  | Detailed Log   |
| extended-log    | extended, extend, "extended log"  | Extended Log   |

**Examples:**
```powershell
-TrackType log
-TrackType "extended log"
-TrackType extended-log
-TrackType extended
```

All formats are case-insensitive and normalized automatically.

### Additional Options

- **Accounting** - Enable accounting logs
- **Per-Connection** - Log each connection separately
- **Per-Session** - Log each session separately

More details here: [R82 SmartConsole Help - Track Settings](https://sc1.checkpoint.com/documents/R82/SmartConsole_OLH/EN/Topics-OLH/Agb31EQtegrfJA5m6BGBOA2.htm?cshid=Agb31EQtegrfJA5m6BGBOA2)

## 🔄 Workflow

1. **Authentication** - Connect to Management Server
2. **Package Selection** - Choose policy package
3. **Layer Selection** - Choose access layer (auto-selected if only one)
4. **Rule Display** - View all rules with current logging status
5. **Rule Selection** - Select rules to modify (individual, multiple, or all)
6. **Configuration** - Choose logging type and options
7. **Validation** - Test configuration on first rule
8. **Apply Changes** - Apply to all selected rules
9. **Changes Summary** - Review all modifications (before/after)
10. **Publish** - Publish changes with real-time task monitoring
11. **Manual Install** - Install policy through SmartConsole

## 📊 Examples

### Example 1: Interactive Mode

```
PS> .\Quantum-Change-Logging.ps1 -MgmtServer 192.168.100.10

═══════════════════════════════════════════════════════════
  Check Point Quantum - Access Rule Logging Configuration
═══════════════════════════════════════════════════════════

Authenticating to https://192.168.100.10...
✓ Authentication successful

Available Policy Packages:
  [1] Standard
  [2] Standard_Clone

Select package number: 1

→ Using package: Standard
→ Access layer: Standard Network

Retrieving rules from layer 'Standard Network'...
✓ Found 29 rules

Enter rule numbers to modify: 1,3,5

Selected Rules (3):
  • Rule 1 (current: None)
  • Rule 3 (current: Log)
  • Rule 5 (current: None)

Track Configuration:
Select track type: 2
Enable Accounting? (y/n): y
Log per Connection? (y/n): y

✓ Configuration is valid!
✓ Modified 3 of 3 rules

Publish changes? (y/n): y
✓ Publish request submitted
  Progress: 100% - Status: succeeded
✓ Changes published successfully
```

### Example 2: Non-Interactive - All Rules

```powershell
.\Quantum-Change-Logging.ps1 `
    -MgmtServer 192.168.100.10 `
    -User admin `
    -Password "Pass123" `
    -PackageName "Standard" `
    -RuleSelection all `
    -TrackType extended-log `
    -Accounting `
    -PerConnection `
    -PerSession `
    -AutoPublish `
    -Interactive:$false
```

### Example 3: Non-Interactive - Specific Rules by Number

```powershell
.\Quantum-Change-Logging.ps1 `
    -MgmtServer 192.168.100.10 `
    -User admin `
    -Password "Pass123" `
    -PackageName "Standard" `
    -RuleNumbers @("10","11","12") `
    -TrackType log `
    -PerConnection `
    -AutoPublish `
    -Interactive:$false `
    -Quiet
```

### Example 4: Non-Interactive - Rules by Name

```powershell
.\Quantum-Change-Logging.ps1 `
    -MgmtServer 192.168.100.10 `
    -User admin `
    -Password "Pass123" `
    -PackageName "Standard" `
    -RuleNames @("Grafana Access","HA Web Access") `
    -TrackType none `
    -AutoPublish `
    -Interactive:$false
```

## ⚠️ Important Notes

### Policy Installation

**Policy installation functionality is DISABLED by default** for safety reasons:

- Could install policy on wrong gateway/cluster
- May cause service disruption if policy has errors
- No validation of target gateway readiness
- Potential for network connectivity loss
- Difficult to rollback if issues occur

**RECOMMENDATION**: Always install policies manually through SmartConsole after thorough review and verification of the changes.

### Session Management

- The script automatically discards pending changes at startup to avoid conflicts
- If you don't publish changes, the script automatically discards them to release locks
- Always wait for publish task completion before closing the script
- Publish operations are monitored in real-time with progress updates
- If a session remains locked, use SmartConsole Session Management to disconnect it

### Non-Interactive Mode Requirements

When running in non-interactive mode (`-Interactive:$false`), these parameters are required:
- `-User`
- `-Password`
- `-PackageName`
- `-TrackType`
- One of: `-RuleSelection`, `-RuleNumbers`, or `-RuleNames`

## 🐛 Troubleshooting

### Invalid TrackType Error

**Error**: `Invalid TrackType: 'extendend log'`

**Solution**:
- Use correct spelling: `extended` not `extendend`
- Accepted formats: `extended-log`, `extended`, `extend`, or `"extended log"`
- Case-insensitive: `EXTENDED`, `Extended`, `extended` all work

### Rule Selection with RuleNumbers

**Error**: `Cannot convert value "all" to type "System.Int32"`

**Solution**:
- Use `-RuleSelection all` instead of `-RuleNumbers "all"`
- OR use `-RuleNumbers @("all")` (both work in v2.1+)

### Authentication Errors

**Error**: `400 Bad Request` during authentication

**Solution**:
- Verify Management Server address and port (default: 443)
- Check username and password
- Ensure Web API is enabled on Management Server
- Verify network connectivity

### Session/Lock Conflicts

**Error**: Objects remain locked after script execution

**Solution**:
- Close all SmartConsole sessions
- Use SmartConsole Sessions view to disconnect active API sessions
- Run script with `-Interactive:$false` to avoid timeout issues
- Re-run the script

### Publish Task Timeout

**Error**: Task status check timed out after 60 seconds

**Solution**:
- Check Management Server performance
- Verify network connectivity
- Review task details in SmartConsole
- Script will show progress updates every 2 seconds

### Unsupported Track Types

**Error**: `Invalid parameter for [type]. The invalid value [Extended] should be replaced by one of the following values: [none, log, extended log, detailed log]`

**Solution**:
- Detailed Log and Extended Log require additional security blades (e.g., Application Control, IPS)
- Verify required blades are enabled in the access layer
- Use standard "Log" option if advanced logging is not available
- Check blade configuration in SmartConsole

## 🔧 API Endpoints Used

- `POST /web_api/login` - Authentication
- `POST /web_api/logout` - Session cleanup
- `POST /web_api/discard` - Discard pending changes
- `POST /web_api/show-packages` - List policy packages
- `POST /web_api/show-package` - Get package details
- `POST /web_api/show-access-rulebase` - Get access rules
- `POST /web_api/set-access-rule` - Modify rule logging
- `POST /web_api/publish` - Publish changes
- `POST /web_api/show-task` - Monitor task status

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## ⚠️ Disclaimer

This script is provided as-is without warranty. Always test in a non-production environment first.

**IMPORTANT**: This tool modifies firewall policy configurations. Ensure you have:
- Proper authorization to modify policies
- Recent backups of your configuration
- Tested changes in a lab environment
- Understanding of the impact on your security posture

## 📞 Support

For issues and questions:
- Open an issue on [GitHub](https://github.com/MaxCere/CHKP-Quantum-API/issues)
- Check Point Community: [https://community.checkpoint.com](https://community.checkpoint.com)

## 📝 Version History

### v2.1 (2025-11-12)
- **Non-Interactive Mode**: Full support for automation and CI/CD pipelines
- **Flexible Rule Selection**: By number, name, or all rules
- **TrackType Normalization**: Accepts multiple formats (spaces, dashes, abbreviations)
- **Quiet Mode**: Suppress non-essential output with `-Quiet` parameter
- **AutoPublish**: Automatic publishing without confirmation
- **Improved Error Handling**: Better validation and error messages
- **Bug Fixes**: Fixed RuleNumbers parsing and TrackType validation

### v1.3 (2025-11-12)
- Added real-time task monitoring for publish operations
- Improved error handling and messages
- Enhanced color-coded output
- Fixed session cleanup issues

### v1.2 (2025-11-12)
- Added support for Accounting, per-Connection, per-Session options
- Implemented configuration validation
- Added changes summary before publish
- Disabled automatic policy installation for safety

### v1.0 (2025-11-12)
- Initial release
- Interactive configuration
- Basic logging modification
