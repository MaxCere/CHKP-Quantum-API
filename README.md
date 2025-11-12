# Check Point Quantum - Access Rule Logging Configuration

PowerShell script to configure logging settings (Track) for Check Point Quantum access rules via Management API.

## ✨ Features

- **Interactive Configuration** - User-friendly prompts for selecting packages, layers, and rules
- **Flexible Logging Options** - Supports Log, Detailed Log, Extended Log, and None
- **Advanced Options** - Accounting, per-Connection, and per-Session logging
- **Batch Processing** - Modify single or multiple rules at once
- **Safe Operations** - Automatic session cleanup and validation with changes summary before publish
- **Configuration Validation** - Tests settings on first rule before applying to all
- **Color-coded Output** - Enhanced readability with visual feedback
- **Change Summary** - Review all modifications before publishing
- **Real-time Task Monitoring** - Live progress tracking for publish operations

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

### Basic Usage

Run the script interactively:

```powershell
.\Quantum-Change-Logging.ps1
```

### Advanced Usage

With parameters:

```powershell
.\Quantum-Change-Logging.ps1 -MgmtServer 192.168.100.10 -User admin -PackageName "Standard"
```

Auto-publish changes:

```powershell
.\Quantum-Change-Logging.ps1 -MgmtServer 192.168.100.10 -Publish
```

## 📝 Parameters

| Parameter      | Type   | Required | Description                                    |
|----------------|--------|----------|------------------------------------------------|
| -MgmtServer    | String | No       | Management server address (IP or hostname)     |
| -User          | String | No       | Management API username                         |
| -Password      | String | No       | Management API password                         |
| -PackageName   | String | No       | Policy package name                             |
| -LayerName     | String | No       | Access layer name                               |
| -Publish       | Switch | No       | Automatically publish changes after modification|
| -Interactive   | Switch | No       | Enable interactive mode (default: true)         |

## ⚙️ Configuration Options

### Track Types

1. **None** - No logging
2. **Log** - Standard logging
3. **Detailed Log** - Detailed logging (requires additional blades enabled)
4. **Extended Log** - Extended logging (requires additional blades enabled)

### Additional Options

- **Accounting** - Enable accounting logs
- **Per-Connection** - Log each connection separately
- **Per-Session** - Log each session separately

## 🔄 Workflow

1. **Authentication** - Connect to Management Server
2. **Package Selection** - Choose policy package
3. **Layer Selection** - Choose access layer (auto-selected if only one)
4. **Rule Display** - View all rules with current logging status
5. **Rule Selection** - Select rules to modify (individual or all)
6. **Configuration** - Choose logging type and options
7. **Validation** - Test configuration on first rule
8. **Apply Changes** - Apply to all selected rules
9. **Changes Summary** - Review all modifications
10. **Publish** - Optionally publish changes
11. **Manual Install** - Install policy through SmartConsole

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

- If you don't publish changes, the script automatically discards them to prevent locked objects
- Always wait for publish task completion before closing the script
- If a session remains locked, use SmartConsole Session Management to disconnect it

## 🐛 Troubleshooting

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
- Re-run the script

### Publish Task Timeout

**Error**: Task status check timed out after 60 seconds

**Solution**:
- Check Management Server performance
- Verify network connectivity
- Review task details in SmartConsole

### Unsupported Track Types

**Error**: Configuration validation fails with unsupported track type

**Solution**:
- Detailed Log and Extended Log require additional security blades (e.g., Threat Prevention)
- Verify required blades are enabled on gateways
- Use standard "Log" option if advanced logging is not available

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## ⚠️ Disclaimer

This script is provided as-is without warranty. Always test in a non-production environment first.

**IMPORTANT**: This tool modifies firewall policy configurations. Ensure you have:
- Proper authorization to modify policies
- Recent backups of your configuration
- Tested changes in a lab environment
- Understanding of the impact on your security posture

## 📄 License

This project is licensed under the MIT License.

## 👤 Author

Created by Massimiliano Cere ([@MaxCere](https://github.com/MaxCere))

## 📞 Support

For issues and questions:
- Open an issue on [GitHub](https://github.com/MaxCere/CHKP-Quantum-API/issues)
- Check Point Community: [https://community.checkpoint.com](https://community.checkpoint.com)

## 📚 Version History

### v1.3 (2025-11-12)
- Added real-time task monitoring for publish operations
- Improved error handling and messages
- Enhanced color-coded output
- Fixed session cleanup issues
- Added automatic discard of unpublished changes

### v1.2 (2025-11-12)
- Added support for Accounting, per-Connection, per-Session options
- Implemented configuration validation before applying to all rules
- Added changes summary before publish
- Disabled automatic policy installation for safety

### v1.1 (2025-11-12)
- Added color-coded output for better readability
- Improved user interface
- Enhanced error messages
- Better handling of access layers

### v1.0 (2025-11-12)
- Initial release
- Basic logging configuration functionality
- Support for standard track types (None, Log, Detailed Log, Extended Log)
