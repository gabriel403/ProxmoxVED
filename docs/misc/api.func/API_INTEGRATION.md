# api.func Integration Guide

## Overview

This document describes how `api.func` integrates with other components in the Proxmox Community Scripts project. The telemetry backend is **PocketBase** at `http://db.community-scripts.org`, using the `_dev_telemetry_data` collection.

## Architecture

```
Installation Scripts ──► api.func ──► PocketBase (db.community-scripts.org)
                                         │
                                         ├─ POST  → create record (status: "installing")
                                         ├─ PATCH → update record (status: "sucess"/"failed")
                                         └─ GET   → lookup record by random_id (fallback)
```

### Key Design Points
- **POST** creates a new telemetry record and returns a PocketBase `id`
- **PATCH** updates the existing record using that `id` (or a GET lookup by `random_id`)
- All communication is fire-and-forget — failures never block the installation
- `explain_exit_code()` is the canonical function for exit-code-to-description mapping

## Dependencies

### External Dependencies

#### Required Commands
- **`curl`**: HTTP client for PocketBase API communication

#### Optional Commands
- **`uuidgen`**: Generate unique identifiers (any UUID source works)
- **`pveversion`**: Retrieve Proxmox VE version (gracefully skipped if missing)

### Internal Dependencies

#### Environment Variables from Other Scripts
- **build.func**: Provides container creation variables (`CT_TYPE`, `DISK_SIZE`, etc.)
- **vm-core.func**: Provides VM creation variables
- **core.func**: Provides system information
- **Installation scripts**: Provide application-specific variables (`NSAPP`, `METHOD`)

## Integration Points

### With build.func

#### LXC Container Reporting
```bash
source core.func
source api.func
source build.func

export DIAGNOSTICS="yes"
export RANDOM_UUID="$(uuidgen)"

# Set container parameters
export CT_TYPE=1
export DISK_SIZE="$var_disk"
export CORE_COUNT="$var_cpu"
export RAM_SIZE="$var_ram"
export var_os="$var_os"
export var_version="$var_version"
export NSAPP="$APP"
export METHOD="install"

# POST → creates record in PocketBase, saves PB_RECORD_ID
post_to_api

# ... container creation via build.func ...

# PATCH → updates the record with final status
if [[ $? -eq 0 ]]; then
    post_update_to_api "done" 0
else
    post_update_to_api "failed" $?
fi
```

#### Error Reporting Integration
```bash
handle_container_error() {
    local exit_code=$1
    local error_msg=$(explain_exit_code $exit_code)

    echo "Container creation failed: $error_msg"
    post_update_to_api "failed" $exit_code
}
```

### With vm-core.func

#### VM Installation Reporting
```bash
source core.func
source api.func
source vm-core.func

# VM reads DIAGNOSTICS from file
mkdir -p /usr/local/community-scripts
echo "DIAGNOSTICS=yes" > /usr/local/community-scripts/diagnostics

export RANDOM_UUID="$(uuidgen)"

# Set VM parameters
export DISK_SIZE="${var_disk}G"
export CORE_COUNT="$var_cpu"
export RAM_SIZE="$var_ram"
export var_os="$var_os"
export var_version="$var_version"
export NSAPP="$APP"
export METHOD="install"

# POST → creates record in PocketBase (ct_type=2, type="vm")
post_to_api_vm

# ... VM creation via vm-core.func ...

# PATCH → finalizes record
post_update_to_api "done" 0
```

### With error_handler.func

#### Error Description Integration
```bash
source core.func
source error_handler.func
source api.func

enhanced_error_handler() {
    local exit_code=${1:-$?}
    local command=${2:-${BASH_COMMAND:-unknown}}

    # explain_exit_code() is the canonical error description function
    local error_msg=$(explain_exit_code $exit_code)

    echo "Error $exit_code: $error_msg"
    echo "Command: $command"

    # PATCH the telemetry record with failure details
    post_update_to_api "failed" $exit_code
}
```

### With install.func

#### Installation Process Reporting
```bash
source core.func
source api.func
source install.func

install_package_with_reporting() {
    local package="$1"

    export DIAGNOSTICS="yes"
    export RANDOM_UUID="$(uuidgen)"
    export NSAPP="$package"
    export METHOD="install"

    # POST → create telemetry record
    post_to_api

    if install_package "$package"; then
        echo "$package installed successfully"
        post_update_to_api "done" 0
        return 0
    else
        local exit_code=$?
        local error_msg=$(explain_exit_code $exit_code)
        echo "$package installation failed: $error_msg"
        post_update_to_api "failed" $exit_code
        return $exit_code
    fi
}
```

## Data Flow

### Input Data

#### Environment Variables
| Variable | Source | Description |
|----------|--------|-------------|
| `CT_TYPE` | build.func | Container type (1=LXC, 2=VM) |
| `DISK_SIZE` | build.func / vm-core.func | Disk size in GB (VMs may have `G` suffix) |
| `CORE_COUNT` | build.func / vm-core.func | CPU core count |
| `RAM_SIZE` | build.func / vm-core.func | RAM in MB |
| `var_os` | core.func | Operating system type |
| `var_version` | core.func | OS version |
| `NSAPP` | Installation scripts | Application name |
| `METHOD` | Installation scripts | Installation method |
| `DIAGNOSTICS` | User config / diagnostics file | Enable/disable telemetry |
| `RANDOM_UUID` | Caller | Session tracking UUID |

#### Function Parameters
- **Exit codes**: Passed to `explain_exit_code()` and `post_update_to_api()`
- **Status strings**: Passed to `post_update_to_api()` (`"done"`, `"failed"`)

#### System Information
- **PVE version**: Retrieved from `pveversion` command at runtime
- **Disk size**: VM disk size is stripped of `G` suffix before sending

### Processing

#### Record Creation (POST)
1. Validate prerequisites (curl, DIAGNOSTICS, RANDOM_UUID)
2. Gather PVE version
3. Build JSON payload with all telemetry fields
4. `POST` to `PB_API_URL`
5. Extract `PB_RECORD_ID` from PocketBase response (HTTP 200/201)

#### Record Update (PATCH)
1. Validate prerequisites + check `POST_UPDATE_DONE` flag
2. Map status string → PocketBase select value (`"done"` → `"sucess"`)
3. For failures: call `explain_exit_code()` to get error description
4. Resolve record ID: use `PB_RECORD_ID` or fall back to GET lookup
5. `PATCH` to `PB_API_URL/{record_id}` with status, error, exit_code
6. Set `POST_UPDATE_DONE=true`

### Output Data

#### PocketBase Records
- **POST response**: Returns record with `id` field → stored in `PB_RECORD_ID`
- **PATCH response**: Updates record fields (status, error, exit_code)
- **GET response**: Used for record ID lookup by `random_id` filter

#### Internal State
| Variable | Description |
|----------|-------------|
| `PB_RECORD_ID` | PocketBase record ID for PATCH calls |
| `POST_UPDATE_DONE` | Flag preventing duplicate updates |

## API Surface

### Public Functions

| Function | Purpose | HTTP Method |
|----------|---------|-------------|
| `explain_exit_code(code)` | Map exit code to description | — |
| `post_to_api()` | Create LXC telemetry record | POST |
| `post_to_api_vm()` | Create VM telemetry record | POST |
| `post_update_to_api(status, exit_code)` | Update record with final status | PATCH |

### PocketBase Collection Schema

Collection: `_dev_telemetry_data`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | text (auto) | yes | PocketBase record ID (15 chars) |
| `random_id` | text | yes | Session UUID (min 8 chars, unique) |
| `type` | select | yes | `"lxc"`, `"vm"`, `"addon"`, `"pve"` |
| `ct_type` | number | yes | 1 (LXC) or 2 (VM) |
| `nsapp` | text | yes | Application name |
| `status` | select | yes | `"installing"`, `"sucess"`, `"failed"`, `"unknown"` |
| `disk_size` | number | no | Disk size in GB |
| `core_count` | number | no | CPU cores |
| `ram_size` | number | no | RAM in MB |
| `os_type` | text | no | OS type |
| `os_version` | text | no | OS version |
| `pve_version` | text | no | Proxmox VE version |
| `method` | text | no | Installation method |
| `error` | text | no | Error description |
| `exit_code` | number | no | Numeric exit code |
| `created` | autodate | auto | Record creation timestamp |
| `updated` | autodate | auto | Last update timestamp |

> **Note**: The `status` field intentionally uses the spelling `"sucess"` (not `"success"`).

### Configuration Variables
| Variable | Value |
|----------|-------|
| `PB_URL` | `http://db.community-scripts.org` |
| `PB_COLLECTION` | `_dev_telemetry_data` |
| `PB_API_URL` | `${PB_URL}/api/collections/${PB_COLLECTION}/records` |

## Integration Patterns

### Standard Integration Pattern

```bash
#!/usr/bin/env bash

# 1. Source dependencies
source core.func
source api.func

# 2. Enable telemetry
export DIAGNOSTICS="yes"
export RANDOM_UUID="$(uuidgen)"

# 3. Set application parameters
export NSAPP="$APP"
export METHOD="install"

# 4. POST → create telemetry record in PocketBase
post_to_api

# 5. Perform installation
# ... installation logic ...

# 6. PATCH → update record with final status
post_update_to_api "done" 0
```

### Minimal Integration Pattern

```bash
#!/usr/bin/env bash
source api.func

export DIAGNOSTICS="yes"
export RANDOM_UUID="$(uuidgen)"

# Report failure (PATCH via record lookup)
post_update_to_api "failed" 127
```

### Advanced Integration Pattern

```bash
#!/usr/bin/env bash
source core.func
source api.func
source error_handler.func

export DIAGNOSTICS="yes"
export RANDOM_UUID="$(uuidgen)"
export CT_TYPE=1
export DISK_SIZE=8
export CORE_COUNT=2
export RAM_SIZE=2048
export var_os="debian"
export var_version="12"
export METHOD="install"

# Enhanced error handler with PocketBase reporting
enhanced_error_handler() {
    local exit_code=${1:-$?}
    local command=${2:-${BASH_COMMAND:-unknown}}

    local error_msg=$(explain_exit_code $exit_code)
    echo "Error $exit_code: $error_msg"

    post_update_to_api "failed" $exit_code
    error_handler $exit_code $command
}

trap 'enhanced_error_handler' ERR

# POST → create record
post_to_api

# ... operations ...

# PATCH → finalize
post_update_to_api "done" 0
```

## Error Handling Integration

### Automatic Error Reporting
- **Error Descriptions**: `explain_exit_code()` provides human-readable messages for all recognized exit codes
- **PocketBase Integration**: Errors are recorded via PATCH with `status`, `error`, and `exit_code` fields
- **Error Tracking**: Anonymous telemetry helps track common failure patterns
- **Diagnostic Data**: Contributes to project-wide analytics without PII

### API Communication Errors
- **Network Failures**: All API calls use `|| true` — failures are swallowed silently
- **Missing Prerequisites**: Functions return early if curl, DIAGNOSTICS, or UUID are missing
- **Duplicate Prevention**: `POST_UPDATE_DONE` flag ensures only one PATCH per session
- **Record Lookup Fallback**: If `PB_RECORD_ID` is unset, a GET filter query resolves the record

## Performance Considerations

### API Communication Overhead
- **Minimal Impact**: Only 2 HTTP calls per installation (1 POST + 1 PATCH)
- **Non-blocking**: API failures never block the installation process
- **Fire-and-forget**: curl stderr is suppressed (`2>/dev/null`)
- **Optional**: Telemetry is entirely opt-in via `DIAGNOSTICS` setting

### Security Considerations
- **Anonymous**: No personal data is transmitted — only system specs and app names
- **No Auth Required**: PocketBase collection rules allow anonymous create/update
- **User Control**: Users can disable telemetry by setting `DIAGNOSTICS=no`
- **HTTP**: API uses HTTP (not HTTPS) for compatibility with minimal containers
