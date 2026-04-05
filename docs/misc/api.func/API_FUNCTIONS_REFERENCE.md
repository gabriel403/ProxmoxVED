# api.func Functions Reference

## Overview

This document provides a comprehensive reference of all functions in `api.func`, including parameters, dependencies, usage examples, and error handling. The backend is **PocketBase** hosted at `http://db.community-scripts.org`.

## Configuration Variables

| Variable | Value | Description |
|----------|-------|-------------|
| `PB_URL` | `http://db.community-scripts.org` | PocketBase server URL |
| `PB_COLLECTION` | `_dev_telemetry_data` | PocketBase collection name |
| `PB_API_URL` | `${PB_URL}/api/collections/${PB_COLLECTION}/records` | Full API endpoint |
| `PB_RECORD_ID` | *(runtime)* | Stores the PocketBase record ID returned by POST for later PATCH calls |

## Function Categories

### Error Description Functions

#### `explain_exit_code()`

**Purpose**: Convert numeric exit codes to human-readable explanations
**Parameters**:
- `$1` — Exit code to explain
**Returns**: Human-readable error explanation string
**Side Effects**: None
**Dependencies**: None
**Environment Variables Used**: None

> **Note**: `explain_exit_code()` is the **canonical** function for exit-code mapping. It is used by both `api.func` (telemetry) and `error_handler.func` (error display).

**Supported Exit Code Ranges** (non-overlapping):

| Range | Category |
|-------|----------|
| 1–2 | Generic / Shell |
| 6–35 | curl / wget |
| 100–102 | APT / Package manager |
| 124–143 | System / Signals |
| 150–154 | Systemd / Service |
| 160–162 | Python / pip / uv |
| 170–173 | PostgreSQL |
| 180–183 | MySQL / MariaDB |
| 190–193 | MongoDB |
| 200–231 | Proxmox custom codes |
| 243–249 | Node.js / npm |
| 255 | DPKG fatal |

**Usage Example**:
```bash
error_msg=$(explain_exit_code 127)
echo "Error 127: $error_msg"
# Output: Error 127: Command not found
```

**Error Code Examples**:
```bash
explain_exit_code 1     # "General error / Operation not permitted"
explain_exit_code 22    # "curl: HTTP error returned (404, 429, 500+)"
explain_exit_code 127   # "Command not found"
explain_exit_code 200   # "Proxmox: Failed to create lock file"
explain_exit_code 255   # "DPKG: Fatal internal error"
explain_exit_code 999   # "Unknown error"
```

### API Communication Functions

#### `post_to_api()`

**Purpose**: Create an LXC container telemetry record in PocketBase
**Parameters**: None (uses environment variables)
**Returns**: None
**Side Effects**:
- Sends HTTP **POST** to `PB_API_URL`
- Stores the returned PocketBase record `id` in `PB_RECORD_ID` for later PATCH updates
**Dependencies**: `curl` command
**Environment Variables Used**: `DIAGNOSTICS`, `RANDOM_UUID`, `CT_TYPE`, `DISK_SIZE`, `CORE_COUNT`, `RAM_SIZE`, `var_os`, `var_version`, `NSAPP`, `METHOD`

**Prerequisites**:
- `curl` must be available
- `DIAGNOSTICS` must be `"yes"`
- `RANDOM_UUID` must be set and not empty

**API Endpoint**: `POST http://db.community-scripts.org/api/collections/_dev_telemetry_data/records`

**JSON Payload**:
```json
{
    "ct_type": 1,
    "type": "lxc",
    "disk_size": 8,
    "core_count": 2,
    "ram_size": 2048,
    "os_type": "debian",
    "os_version": "12",
    "nsapp": "plex",
    "method": "install",
    "pve_version": "8.0",
    "status": "installing",
    "random_id": "uuid-string"
}
```

**Response Handling**:
- On HTTP 200/201, `PB_RECORD_ID` is extracted from the response JSON (`"id"` field)
- On failure, the function returns silently without blocking the installation

**Usage Example**:
```bash
export DIAGNOSTICS="yes"
export RANDOM_UUID="$(uuidgen)"
export CT_TYPE=1
export DISK_SIZE=8
export CORE_COUNT=2
export RAM_SIZE=2048
export var_os="debian"
export var_version="12"
export NSAPP="plex"
export METHOD="install"

post_to_api
# PB_RECORD_ID is now set (e.g. "abc123def456789")
```

#### `post_to_api_vm()`

**Purpose**: Create a VM telemetry record in PocketBase
**Parameters**: None (uses environment variables)
**Returns**: None
**Side Effects**:
- Sends HTTP **POST** to `PB_API_URL`
- Stores the returned PocketBase record `id` in `PB_RECORD_ID`
**Dependencies**: `curl` command, diagnostics file
**Environment Variables Used**: `RANDOM_UUID`, `DISK_SIZE`, `CORE_COUNT`, `RAM_SIZE`, `var_os`, `var_version`, `NSAPP`, `METHOD`

**Prerequisites**:
- `/usr/local/community-scripts/diagnostics` file must exist
- `DIAGNOSTICS` must be `"yes"` in that file (read at runtime)
- `curl` must be available
- `RANDOM_UUID` must be set and not empty

**API Endpoint**: `POST http://db.community-scripts.org/api/collections/_dev_telemetry_data/records`

**JSON Payload**:
```json
{
    "ct_type": 2,
    "type": "vm",
    "disk_size": 20,
    "core_count": 4,
    "ram_size": 4096,
    "os_type": "ubuntu",
    "os_version": "22.04",
    "nsapp": "nextcloud",
    "method": "install",
    "pve_version": "8.0",
    "status": "installing",
    "random_id": "uuid-string"
}
```

> **Note**: `DISK_SIZE` is stripped of its `G` suffix before sending (e.g. `"20G"` → `20`).

**Usage Example**:
```bash
# Create diagnostics file
mkdir -p /usr/local/community-scripts
echo "DIAGNOSTICS=yes" > /usr/local/community-scripts/diagnostics

export RANDOM_UUID="$(uuidgen)"
export DISK_SIZE="20G"
export CORE_COUNT=4
export RAM_SIZE=4096
export var_os="ubuntu"
export var_version="22.04"
export NSAPP="nextcloud"
export METHOD="install"

post_to_api_vm
# PB_RECORD_ID is now set
```

#### `post_update_to_api()`

**Purpose**: Update an existing PocketBase record with installation completion status via PATCH
**Parameters**:
- `$1` — Status (`"done"`, `"success"`, or `"failed"`; default: `"failed"`)
- `$2` — Exit code (numeric, default: `1`)
**Returns**: None
**Side Effects**:
- Sends HTTP **PATCH** to `PB_API_URL/{record_id}`
- Sets `POST_UPDATE_DONE=true` to prevent duplicate calls
**Dependencies**: `curl`, `explain_exit_code()`
**Environment Variables Used**: `DIAGNOSTICS`, `RANDOM_UUID`, `PB_RECORD_ID`

**Prerequisites**:
- `curl` must be available
- `DIAGNOSTICS` must be `"yes"`
- `RANDOM_UUID` must be set and not empty
- `POST_UPDATE_DONE` must not be `"true"` (prevents duplicate updates)

**Record Lookup**:
1. If `PB_RECORD_ID` is already set (from a prior `post_to_api` / `post_to_api_vm` call), it is used directly.
2. Otherwise, the function performs a **GET** lookup:
   ```
   GET PB_API_URL?filter=(random_id='<RANDOM_UUID>')&fields=id&perPage=1
   ```
3. If no record is found, the function sets `POST_UPDATE_DONE=true` and returns.

**Status Mapping** (PocketBase select field values: `installing`, `sucess`, `failed`, `unknown`):

| Input Status | PocketBase `status` | `exit_code` | `error` |
|---|---|---|---|
| `"done"` / `"success"` / `"sucess"` | `"sucess"` | `0` | `""` |
| `"failed"` | `"failed"` | *from $2* | *from `explain_exit_code()`* |
| anything else | `"unknown"` | *from $2* | *from `explain_exit_code()`* |

> **Note**: The PocketBase schema intentionally spells success as `"sucess"`.

**API Endpoint**: `PATCH http://db.community-scripts.org/api/collections/_dev_telemetry_data/records/{record_id}`

**JSON Payload**:
```json
{
    "status": "sucess",
    "error": "",
    "exit_code": 0
}
```

or for failures:
```json
{
    "status": "failed",
    "error": "Command not found",
    "exit_code": 127
}
```

**Usage Example**:
```bash
export DIAGNOSTICS="yes"
export RANDOM_UUID="$(uuidgen)"

# After a successful installation
post_update_to_api "done" 0

# After a failed installation
post_update_to_api "failed" 127
```

## Function Call Hierarchy

### API Communication Flow
```
post_to_api()
├── Check curl availability
├── Check DIAGNOSTICS == "yes"
├── Check RANDOM_UUID is set
├── Get PVE version
├── Create JSON payload (ct_type=1, type="lxc", status="installing")
├── POST to PB_API_URL
└── Extract PB_RECORD_ID from response

post_to_api_vm()
├── Read DIAGNOSTICS from /usr/local/community-scripts/diagnostics
├── Check curl availability
├── Check DIAGNOSTICS == "yes"
├── Check RANDOM_UUID is set
├── Strip 'G' suffix from DISK_SIZE
├── Get PVE version
├── Create JSON payload (ct_type=2, type="vm", status="installing")
├── POST to PB_API_URL
└── Extract PB_RECORD_ID from response

post_update_to_api(status, exit_code)
├── Check curl availability
├── Check POST_UPDATE_DONE flag
├── Check DIAGNOSTICS == "yes"
├── Check RANDOM_UUID is set
├── Map status → pb_status ("done"→"sucess", "failed"→"failed", *→"unknown")
├── For failed/unknown: call explain_exit_code(exit_code)
├── Resolve record_id (PB_RECORD_ID or GET lookup by random_id)
├── PATCH to PB_API_URL/{record_id}
└── Set POST_UPDATE_DONE=true
```

### Error Description Flow
```
explain_exit_code(code)
├── Match code against case statement (non-overlapping ranges)
├── Return description string
└── Default: "Unknown error"
```

## Error Code Reference

### Generic / Shell (1–2)
| Code | Description |
|------|-------------|
| 1 | General error / Operation not permitted |
| 2 | Misuse of shell builtins (e.g. syntax error) |

### curl / wget (6–35)
| Code | Description |
|------|-------------|
| 6 | curl: DNS resolution failed (could not resolve host) |
| 7 | curl: Failed to connect (network unreachable / host down) |
| 22 | curl: HTTP error returned (404, 429, 500+) |
| 28 | curl: Operation timeout (network slow or server not responding) |
| 35 | curl: SSL/TLS handshake failed (certificate error) |

### APT / Package Manager (100–102)
| Code | Description |
|------|-------------|
| 100 | APT: Package manager error (broken packages / dependency problems) |
| 101 | APT: Configuration error (bad sources.list, malformed config) |
| 102 | APT: Lock held by another process (dpkg/apt still running) |

### System / Signals (124–143)
| Code | Description |
|------|-------------|
| 124 | Command timed out (timeout command) |
| 126 | Command invoked cannot execute (permission problem?) |
| 127 | Command not found |
| 128 | Invalid argument to exit |
| 130 | Terminated by Ctrl+C (SIGINT) |
| 134 | Process aborted (SIGABRT — possibly Node.js heap overflow) |
| 137 | Killed (SIGKILL / Out of memory?) |
| 139 | Segmentation fault (core dumped) |
| 141 | Broken pipe (SIGPIPE — output closed prematurely) |
| 143 | Terminated (SIGTERM) |

### Systemd / Service (150–154)
| Code | Description |
|------|-------------|
| 150 | Systemd: Service failed to start |
| 151 | Systemd: Service unit not found |
| 152 | Permission denied (EACCES) |
| 153 | Build/compile failed (make/gcc/cmake) |
| 154 | Node.js: Native addon build failed (node-gyp) |

### Python / pip / uv (160–162)
| Code | Description |
|------|-------------|
| 160 | Python: Virtualenv / uv environment missing or broken |
| 161 | Python: Dependency resolution failed |
| 162 | Python: Installation aborted (permissions or EXTERNALLY-MANAGED) |

### PostgreSQL (170–173)
| Code | Description |
|------|-------------|
| 170 | PostgreSQL: Connection failed (server not running / wrong socket) |
| 171 | PostgreSQL: Authentication failed (bad user/password) |
| 172 | PostgreSQL: Database does not exist |
| 173 | PostgreSQL: Fatal error in query / syntax |

### MySQL / MariaDB (180–183)
| Code | Description |
|------|-------------|
| 180 | MySQL/MariaDB: Connection failed (server not running / wrong socket) |
| 181 | MySQL/MariaDB: Authentication failed (bad user/password) |
| 182 | MySQL/MariaDB: Database does not exist |
| 183 | MySQL/MariaDB: Fatal error in query / syntax |

### MongoDB (190–193)
| Code | Description |
|------|-------------|
| 190 | MongoDB: Connection failed (server not running) |
| 191 | MongoDB: Authentication failed (bad user/password) |
| 192 | MongoDB: Database not found |
| 193 | MongoDB: Fatal query error |

### Proxmox Custom Codes (200–231)
| Code | Description |
|------|-------------|
| 200 | Proxmox: Failed to create lock file |
| 203 | Proxmox: Missing CTID variable |
| 204 | Proxmox: Missing PCT_OSTYPE variable |
| 205 | Proxmox: Invalid CTID (<100) |
| 206 | Proxmox: CTID already in use |
| 207 | Proxmox: Password contains unescaped special characters |
| 208 | Proxmox: Invalid configuration (DNS/MAC/Network format) |
| 209 | Proxmox: Container creation failed |
| 210 | Proxmox: Cluster not quorate |
| 211 | Proxmox: Timeout waiting for template lock |
| 212 | Proxmox: Storage type 'iscsidirect' does not support containers (VMs only) |
| 213 | Proxmox: Storage type does not support 'rootdir' content |
| 214 | Proxmox: Not enough storage space |
| 215 | Proxmox: Container created but not listed (ghost state) |
| 216 | Proxmox: RootFS entry missing in config |
| 217 | Proxmox: Storage not accessible |
| 218 | Proxmox: Template file corrupted or incomplete |
| 219 | Proxmox: CephFS does not support containers — use RBD |
| 220 | Proxmox: Unable to resolve template path |
| 221 | Proxmox: Template file not readable |
| 222 | Proxmox: Template download failed |
| 223 | Proxmox: Template not available after download |
| 224 | Proxmox: PBS storage is for backups only |
| 225 | Proxmox: No template available for OS/Version |
| 231 | Proxmox: LXC stack upgrade failed |

### Node.js / npm (243–249)
| Code | Description |
|------|-------------|
| 243 | Node.js: Out of memory (JavaScript heap out of memory) |
| 245 | Node.js: Invalid command-line option |
| 246 | Node.js: Internal JavaScript Parse Error |
| 247 | Node.js: Fatal internal error |
| 248 | Node.js: Invalid C++ addon / N-API failure |
| 249 | npm/pnpm/yarn: Unknown fatal error |

### DPKG (255)
| Code | Description |
|------|-------------|
| 255 | DPKG: Fatal internal error |

### Default
| Code | Description |
|------|-------------|
| * | Unknown error |

## Environment Variable Dependencies

### Required Variables
- **`DIAGNOSTICS`**: Enable/disable diagnostic reporting (`"yes"` / `"no"`)
- **`RANDOM_UUID`**: Unique identifier for session tracking

### Container / VM Variables
- **`CT_TYPE`**: Container type (`1` for LXC, `2` for VM)
- **`DISK_SIZE`**: Disk size in GB (VMs may include `G` suffix)
- **`CORE_COUNT`**: Number of CPU cores
- **`RAM_SIZE`**: RAM size in MB
- **`var_os`**: Operating system type
- **`var_version`**: OS version
- **`NSAPP`**: Application name
- **`METHOD`**: Installation method

### Internal Variables
- **`PB_URL`**: PocketBase server URL
- **`PB_COLLECTION`**: PocketBase collection name
- **`PB_API_URL`**: Full PocketBase API endpoint
- **`PB_RECORD_ID`**: PocketBase record ID (set after POST, used for PATCH)
- **`POST_UPDATE_DONE`**: Flag to prevent duplicate status updates
- **`JSON_PAYLOAD`**: API request payload (local to each function)
- **`RESPONSE`**: API response (local to each function)

## Error Handling Patterns

### API Communication Errors
- All API functions return silently on failure — network errors never block installation
- Missing prerequisites (no curl, diagnostics disabled, no UUID) cause early return
- `POST_UPDATE_DONE` flag prevents duplicate PATCH updates
- PocketBase record lookup falls back to `GET ?filter=(random_id='...')` if `PB_RECORD_ID` is unset

### Error Description Errors
- Unknown error codes return `"Unknown error"`
- All recognized codes are handled via a `case` statement with non-overlapping ranges
- The fallback message is generic (no error code is embedded)

## Integration Examples

### With build.func (LXC)
```bash
#!/usr/bin/env bash
source core.func
source api.func
source build.func

export DIAGNOSTICS="yes"
export RANDOM_UUID="$(uuidgen)"

# Report LXC installation start → POST creates record
post_to_api

# ... container creation via build.func ...

# Report completion → PATCH updates record
if [[ $? -eq 0 ]]; then
    post_update_to_api "done" 0
else
    post_update_to_api "failed" $?
fi
```

### With vm-core.func (VM)
```bash
#!/usr/bin/env bash
source core.func
source api.func
source vm-core.func

export RANDOM_UUID="$(uuidgen)"

# Report VM installation start → POST creates record
post_to_api_vm

# ... VM creation via vm-core.func ...

# Report completion → PATCH updates record
post_update_to_api "done" 0
```

### With error_handler.func
```bash
#!/usr/bin/env bash
source core.func
source error_handler.func
source api.func

error_code=127
error_msg=$(explain_exit_code $error_code)
echo "Error $error_code: $error_msg"

# Report error to PocketBase
post_update_to_api "failed" $error_code
```

## Best Practices

### API Usage
1. Always check prerequisites before API calls (handled internally by each function)
2. Call `post_to_api` / `post_to_api_vm` **once** at installation start to get a `PB_RECORD_ID`
3. Call `post_update_to_api` **once** at the end to finalize the record via PATCH
4. Never block the installation on API failures

### Error Reporting
1. Use `explain_exit_code()` for human-readable error messages
2. Pass the actual numeric exit code to `post_update_to_api`
3. Report both success (`"done"`) and failure (`"failed"`) cases
4. The `POST_UPDATE_DONE` flag automatically prevents duplicate updates

### Diagnostic Reporting
1. Respect user privacy — only send data when `DIAGNOSTICS="yes"`
2. Use anonymous random UUIDs for session tracking (no personal data)
3. Include relevant system information (PVE version, OS, app name)
4. The diagnostics file at `/usr/local/community-scripts/diagnostics` controls VM reporting
