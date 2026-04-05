# api.func Execution Flowchart

## Overview

This document illustrates the execution flow of `api.func` functions. The backend is **PocketBase** at `http://db.community-scripts.org`, collection `_dev_telemetry_data`.

## Main API Communication Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        API Communication Initialization                        │
│  Entry point when api.func functions are called by installation scripts        │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        Prerequisites Check                                     │
│                                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    Prerequisites Validation                            │    │
│  │                                                                       │    │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────────┐   │    │
│  │  │   Check curl    │    │   Check         │    │   Check          │   │    │
│  │  │   Availability  │    │   DIAGNOSTICS   │    │   RANDOM_UUID    │   │    │
│  │  │                 │    │                 │    │                  │   │    │
│  │  │ • command -v    │    │ • Must be "yes" │    │ • Must not be    │   │    │
│  │  │   curl          │    │ • Return if     │    │   empty          │   │    │
│  │  │ • Return if     │    │   "no" or unset │    │ • Return if      │   │    │
│  │  │   not found     │    │                 │    │   not set        │   │    │
│  │  └─────────────────┘    └─────────────────┘    └──────────────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        Data Collection                                         │
│                                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    System Information Gathering                        │    │
│  │                                                                       │    │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────────┐   │    │
│  │  │   Get PVE       │    │   Collect Env   │    │   Build JSON     │   │    │
│  │  │   Version       │    │   Variables     │    │   Payload        │   │    │
│  │  │                 │    │                 │    │                  │   │    │
│  │  │ • pveversion    │    │ • CT_TYPE       │    │ • Heredoc JSON   │   │    │
│  │  │   command       │    │ • DISK_SIZE     │    │ • Include all    │   │    │
│  │  │ • Parse version │    │ • CORE_COUNT    │    │   fields         │   │    │
│  │  │ • Fallback:     │    │ • RAM_SIZE      │    │ • status =       │   │    │
│  │  │   "not found"   │    │ • var_os        │    │   "installing"   │   │    │
│  │  │                 │    │ • NSAPP, METHOD │    │                  │   │    │
│  │  └─────────────────┘    └─────────────────┘    └──────────────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        PocketBase API Request                                  │
│                                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    HTTP Request Processing                             │    │
│  │                                                                       │    │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────────┐   │    │
│  │  │   Prepare       │    │   Execute       │    │   Handle         │   │    │
│  │  │   Request       │    │   HTTP POST     │    │   Response       │   │    │
│  │  │                 │    │                 │    │                  │   │    │
│  │  │ • URL:          │    │ • curl -s -w    │    │ • Check HTTP     │   │    │
│  │  │   PB_API_URL    │    │   "%{http_code}"│    │   200/201        │   │    │
│  │  │ • Method: POST  │    │ • -X POST       │    │ • Extract "id"   │   │    │
│  │  │ • Content-Type: │    │ • -L (follow    │    │   from response  │   │    │
│  │  │   application/  │    │   redirects)    │    │ • Store in       │   │    │
│  │  │   json          │    │ • JSON body     │    │   PB_RECORD_ID   │   │    │
│  │  └─────────────────┘    └─────────────────┘    └──────────────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## LXC API Reporting Flow — `post_to_api()`

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        post_to_api() Flow                                      │
│  POST → Create LXC telemetry record in PocketBase                             │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  Prerequisites: curl? ──► DIAGNOSTICS="yes"? ──► RANDOM_UUID set?             │
│  (return silently on any failure)                                              │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        LXC Data Preparation                                    │
│                                                                                │
│  ┌─────────────────┐    ┌─────────────────────┐    ┌───────────────────┐       │
│  │  Set LXC type   │    │  Collect variables  │    │  Set initial      │       │
│  │                 │    │                     │    │  status           │       │
│  │ • ct_type: 1    │    │ • DISK_SIZE         │    │                   │       │
│  │ • type: "lxc"   │    │ • CORE_COUNT        │    │ • status:         │       │
│  │                 │    │ • RAM_SIZE           │    │   "installing"    │       │
│  │                 │    │ • var_os, var_version│    │ • random_id:      │       │
│  │                 │    │ • NSAPP, METHOD      │    │   RANDOM_UUID     │       │
│  │                 │    │ • pve_version        │    │                   │       │
│  └─────────────────┘    └─────────────────────┘    └───────────────────┘       │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  POST → PB_API_URL                                                             │
│  http://db.community-scripts.org/api/collections/_dev_telemetry_data/records   │
│                                                                                │
│  Response (HTTP 200/201):                                                      │
│    { "id": "abc123def456789", ... }                                            │
│              │                                                                 │
│              └──► PB_RECORD_ID = "abc123def456789"                             │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## VM API Reporting Flow — `post_to_api_vm()`

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        post_to_api_vm() Flow                                   │
│  POST → Create VM telemetry record in PocketBase                              │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  Read /usr/local/community-scripts/diagnostics                                 │
│  Extract DIAGNOSTICS=yes/no from file                                          │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  Prerequisites: curl? ──► DIAGNOSTICS="yes"? ──► RANDOM_UUID set?             │
│  (return silently on any failure)                                              │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        VM Data Preparation                                     │
│                                                                                │
│  ┌─────────────────┐    ┌─────────────────────┐    ┌───────────────────┐       │
│  │  Set VM type    │    │  Process disk size  │    │  Set initial      │       │
│  │                 │    │                     │    │  status           │       │
│  │ • ct_type: 2    │    │ • Strip 'G' suffix  │    │                   │       │
│  │ • type: "vm"    │    │   "20G" → 20        │    │ • status:         │       │
│  │                 │    │ • Store in           │    │   "installing"    │       │
│  │                 │    │   DISK_SIZE_API      │    │ • random_id:      │       │
│  │                 │    │                     │    │   RANDOM_UUID     │       │
│  └─────────────────┘    └─────────────────────┘    └───────────────────┘       │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  POST → PB_API_URL                                                             │
│  http://db.community-scripts.org/api/collections/_dev_telemetry_data/records   │
│                                                                                │
│  Response (HTTP 200/201):                                                      │
│    { "id": "xyz789abc012345", ... }                                            │
│              │                                                                 │
│              └──► PB_RECORD_ID = "xyz789abc012345"                             │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Status Update Flow — `post_update_to_api()`

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        post_update_to_api(status, exit_code) Flow              │
│  PATCH → Update existing PocketBase record with final status                  │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        Duplicate Prevention Check                              │
│                                                                                │
│  ┌─────────────────┐    ┌──────────────────────────────────────────────┐        │
│  │  Check           │    │  POST_UPDATE_DONE == "true"?               │        │
│  │  POST_UPDATE_    │───►│                                            │        │
│  │  DONE flag       │    │  YES → return 0 (skip PATCH)               │        │
│  │                 │    │  NO  → continue                             │        │
│  └─────────────────┘    └──────────────────────────────────────────────┘        │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │ (first call only)
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  Prerequisites: curl? ──► DIAGNOSTICS="yes"? ──► RANDOM_UUID set?             │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        Status Mapping                                          │
│                                                                                │
│  Input $1         │  PocketBase status  │  exit_code   │  error                │
│  ─────────────────┼─────────────────────┼──────────────┼────────────────────── │
│  "done"/"success" │  "sucess"           │  0           │  ""                   │
│  "failed"         │  "failed"           │  from $2     │  explain_exit_code()  │
│  anything else    │  "unknown"          │  from $2     │  explain_exit_code()  │
│                                                                                │
│  Note: PocketBase schema spells it "sucess" intentionally                      │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        Record ID Resolution                                    │
│                                                                                │
│  ┌──────────────────────────┐    ┌──────────────────────────────────────┐       │
│  │  PB_RECORD_ID set?       │    │  Fallback: GET lookup               │       │
│  │                          │    │                                      │       │
│  │  YES → use PB_RECORD_ID  │    │  GET PB_API_URL                     │       │
│  │                          │    │    ?filter=(random_id='UUID')        │       │
│  │  NO  → try GET lookup ───┼───►│    &fields=id                       │       │
│  │                          │    │    &perPage=1                        │       │
│  │                          │    │                                      │       │
│  │                          │    │  Extract "id" from response          │       │
│  │                          │    │  If not found → set flag, return     │       │
│  └──────────────────────────┘    └──────────────────────────────────────┘       │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        PATCH Request                                           │
│                                                                                │
│  PATCH → PB_API_URL/{record_id}                                                │
│  http://db.community-scripts.org/api/collections/_dev_telemetry_data/          │
│           records/{record_id}                                                  │
│                                                                                │
│  Payload:                                                                      │
│  {                                                                             │
│      "status": "sucess" | "failed" | "unknown",                               │
│      "error": "..." | "",                                                      │
│      "exit_code": 0 | <numeric>                                               │
│  }                                                                             │
│                                                                                │
│  ──► POST_UPDATE_DONE = true (prevents future calls)                           │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Error Description Flow — `explain_exit_code()`

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        explain_exit_code(code) Flow                            │
│  Convert numeric exit codes to human-readable descriptions                    │
│  Canonical function — used by api.func AND error_handler.func                 │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        Exit Code Classification (non-overlapping ranges)       │
│                                                                                │
│  ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐       │
│  │  Generic/Shell  │  │  curl/wget       │  │  APT/DPKG               │       │
│  │  1–2            │  │  6, 7, 22, 28, 35│  │  100–102, 255           │       │
│  └─────────────────┘  └──────────────────┘  └──────────────────────────┘       │
│                                                                                │
│  ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐       │
│  │  System/Signals │  │  Systemd/Service │  │  Python/pip/uv          │       │
│  │  124–143        │  │  150–154         │  │  160–162                │       │
│  └─────────────────┘  └──────────────────┘  └──────────────────────────┘       │
│                                                                                │
│  ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐       │
│  │  PostgreSQL     │  │  MySQL/MariaDB   │  │  MongoDB                │       │
│  │  170–173        │  │  180–183         │  │  190–193                │       │
│  └─────────────────┘  └──────────────────┘  └──────────────────────────┘       │
│                                                                                │
│  ┌─────────────────┐  ┌──────────────────┐                                     │
│  │  Proxmox        │  │  Node.js/npm     │                                     │
│  │  200–231        │  │  243–249         │                                     │
│  └─────────────────┘  └──────────────────┘                                     │
└─────────────────────┬───────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  case "$code" in                                                               │
│      <matched>)  echo "<description>" ;;                                       │
│      *)          echo "Unknown error" ;;                                       │
│  esac                                                                          │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Complete Installation Lifecycle

```
┌──────────────────────────────────────────────────────────────┐
│  Installation Script (e.g. build.func / vm-core.func)       │
└────────┬─────────────────────────────────────────────────────┘
         │
         │  1. source api.func
         │  2. Set DIAGNOSTICS, RANDOM_UUID, NSAPP, etc.
         │
         ▼
┌──────────────────────────────────────────────────────────────┐
│  post_to_api() / post_to_api_vm()                           │
│                                                              │
│  POST → PB_API_URL                                           │
│  Body: { ..., "status": "installing", "random_id": "..." }  │
│                                                              │
│  Response → PB_RECORD_ID = "abc123def456789"                 │
└────────┬─────────────────────────────────────────────────────┘
         │
         │  3. Installation proceeds...
         │     (container/VM creation, package install, etc.)
         │
         ▼
┌──────────────────────────────────────────────────────────────┐
│  post_update_to_api("done", 0)                              │
│          or                                                  │
│  post_update_to_api("failed", $exit_code)                   │
│                                                              │
│  PATCH → PB_API_URL/{PB_RECORD_ID}                           │
│  Body: { "status": "sucess", "error": "", "exit_code": 0 }  │
│    or  { "status": "failed", "error": "...", "exit_code": N }│
│                                                              │
│  POST_UPDATE_DONE = true                                     │
└──────────────────────────────────────────────────────────────┘
```

## Integration Points

### With Installation Scripts
- **build.func**: Calls `post_to_api()` for LXC creation, then `post_update_to_api()` on completion
- **vm-core.func**: Calls `post_to_api_vm()` for VM creation, then `post_update_to_api()` on completion
- **install.func / alpine-install.func**: Reports installation status via `post_update_to_api()`

### With Error Handling
- **error_handler.func**: Uses `explain_exit_code()` for human-readable error messages
- **Diagnostic reporting**: PocketBase records track error patterns anonymously

### External Dependencies
- **curl**: HTTP client for PocketBase API communication
- **PocketBase**: Backend at `http://db.community-scripts.org`
- **Network connectivity**: Required for API communication (failures are silently ignored)
