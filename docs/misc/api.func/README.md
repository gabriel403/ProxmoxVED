# api.func Documentation

## Overview

The `api.func` file provides PocketBase API integration and diagnostic reporting for the Community Scripts project. It handles telemetry communication, error reporting, and status updates to the PocketBase backend at `db.community-scripts.org`.

## Purpose and Use Cases

- **API Communication**: Send installation and status data to PocketBase
- **Diagnostic Reporting**: Report installation progress and errors for analytics
- **Error Description**: Provide detailed error code explanations (canonical source of truth)
- **Status Updates**: Track installation success/failure status
- **Analytics**: Contribute anonymous usage data for project improvement

## Quick Reference

### Key Function Groups
- **Error Handling**: `explain_exit_code()` - Convert exit codes to human-readable messages
- **API Communication**: `post_to_api()`, `post_to_api_vm()` - Send installation data to PocketBase
- **Status Updates**: `post_update_to_api()` - Report installation completion status via PATCH

### PocketBase Configuration
- **URL**: `http://db.community-scripts.org`
- **Collection**: `_dev_telemetry_data`
- **API Endpoint**: `/api/collections/_dev_telemetry_data/records`

### Dependencies
- **External**: `curl` command for HTTP requests
- **Internal**: Uses environment variables from other scripts

### Integration Points
- Used by: All installation scripts for diagnostic reporting
- Uses: Environment variables from build.func and other scripts
- Provides: API communication, error reporting, and exit code descriptions

## Documentation Files

### 📊 [API_FLOWCHART.md](./API_FLOWCHART.md)
Visual execution flows showing API communication processes and error handling.

### 📚 [API_FUNCTIONS_REFERENCE.md](./API_FUNCTIONS_REFERENCE.md)
Complete alphabetical reference of all functions with parameters, dependencies, and usage details.

### 💡 [API_USAGE_EXAMPLES.md](./API_USAGE_EXAMPLES.md)
Practical examples showing how to use API functions and common patterns.

### 🔗 [API_INTEGRATION.md](./API_INTEGRATION.md)
How api.func integrates with other components and provides API services.

## Key Features

### Exit Code Descriptions
- **Canonical source**: Single authoritative `explain_exit_code()` for the entire project
- **Non-overlapping ranges**: Clean separation between error categories
- **Comprehensive Coverage**: 60+ error codes with detailed explanations
- **System Errors**: General system, curl, and network errors
- **Signal Errors**: Process termination and signal errors

### PocketBase Integration
- **Record Creation**: POST to create telemetry records with status `installing`
- **Record Updates**: PATCH to update with final status, exit code, and error
- **ID Tracking**: Stores `PB_RECORD_ID` for efficient updates
- **Fallback Lookup**: Searches by `random_id` filter if record ID is lost

### Diagnostic Integration
- **Optional Reporting**: Only sends data when diagnostics enabled
- **Privacy Respect**: Respects user privacy settings
- **Error Tracking**: Tracks installation errors for improvement
- **Usage Analytics**: Contributes to project statistics

## Common Usage Patterns

### Basic API Setup
```bash
#!/usr/bin/env bash
source api.func

# Set up diagnostic reporting
export DIAGNOSTICS="yes"
export RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"

# Report installation start (creates PocketBase record)
post_to_api
```

### Error Reporting
```bash
#!/usr/bin/env bash
source api.func

# Get error description
error_msg=$(explain_exit_code 137)
echo "Error 137: $error_msg"
# Output: Error 137: Killed (SIGKILL / Out of memory?)
```

### Status Updates
```bash
#!/usr/bin/env bash
source api.func

# Report successful installation
post_update_to_api "done" 0

# Report failed installation with exit code
post_update_to_api "failed" 127
```

## Environment Variables

### Required Variables
- `DIAGNOSTICS`: Enable/disable diagnostic reporting ("yes"/"no")
- `RANDOM_UUID`: Unique identifier for session tracking

### Optional Variables
- `CT_TYPE`: Container type (1 for LXC, 2 for VM)
- `DISK_SIZE`: Disk size in GB
- `CORE_COUNT`: Number of CPU cores
- `RAM_SIZE`: RAM size in MB
- `var_os`: Operating system type
- `var_version`: OS version
- `NSAPP`: Application name
- `METHOD`: Installation method

### Internal Variables
- `POST_UPDATE_DONE`: Prevents duplicate status updates
- `PB_URL`: PocketBase base URL
- `PB_API_URL`: Full API endpoint URL
- `PB_RECORD_ID`: Stored PocketBase record ID for updates

## Error Code Categories (Non-Overlapping Ranges)

| Range | Category |
|-------|----------|
| 1-2 | Generic shell errors |
| 6-35 | curl/wget network errors |
| 100-102 | APT/DPKG package errors |
| 124-143 | Command execution & signal errors |
| 150-154 | Systemd/service errors |
| 160-162 | Python/pip/uv errors |
| 170-173 | PostgreSQL errors |
| 180-183 | MySQL/MariaDB errors |
| 190-193 | MongoDB errors |
| 200-231 | Proxmox custom codes |
| 243-249 | Node.js/npm errors |
| 255 | DPKG fatal error |

## Best Practices

### Diagnostic Reporting
1. Always check if diagnostics are enabled
2. Respect user privacy settings
3. Use unique identifiers for tracking
4. Report both success and failure cases

### Error Handling
1. Use the correct non-overlapping exit code ranges
2. Use `explain_exit_code()` from api.func (canonical source)
3. Handle API communication failures gracefully
4. Don't block installation on API failures

### API Usage
1. Check for curl availability before API calls
2. Handle network failures gracefully (all calls use `|| true`)
3. Store and reuse PB_RECORD_ID for updates
4. Use proper PocketBase REST methods (POST for create, PATCH for update)

## Troubleshooting

### Common Issues
1. **API Communication Fails**: Check network connectivity and curl availability
2. **Diagnostics Not Working**: Verify `DIAGNOSTICS=yes` in `/usr/local/community-scripts/diagnostics`
3. **Status Update Fails**: Check that `PB_RECORD_ID` was captured or `random_id` filter works
4. **Duplicate Updates**: `POST_UPDATE_DONE` flag prevents duplicates

### Debug Mode
Enable diagnostic reporting for debugging:
```bash
export DIAGNOSTICS="yes"
export RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
```

### API Testing
Test PocketBase connectivity:
```bash
curl -s http://db.community-scripts.org/api/health
```

Test record creation:
```bash
source api.func
export DIAGNOSTICS="yes"
export RANDOM_UUID="test-$(date +%s)"
export NSAPP="test"
export CT_TYPE=1
post_to_api
echo "Record ID: $PB_RECORD_ID"
```

## Related Documentation

- [core.func](../core.func/) - Core utilities
- [error_handler.func](../error_handler.func/) - Error handling (fallback `explain_exit_code`)
- [build.func](../build.func/) - Container creation with API integration
- [tools.func](../tools.func/) - Extended utilities

---

*This documentation covers the api.func file which provides PocketBase communication and diagnostic reporting for all Proxmox Community Scripts.*
