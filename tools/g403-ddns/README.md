# g403-ddns

Tiny dependency-free TypeScript service (runs directly on Node 24, no build step) that reads the WAN IP of a TP-Link Omada
gateway from the Omada controller's Open API and keeps one Cloudflare A record
pointed at it. Built because the gateway's own custom-DDNS client can only
reach targets on the WAN side, which rules out anything internal.

- Polls every `INTERVAL_SECONDS` (default 60).
- Writes to Cloudflare only when the record's content, TTL or proxied flag differ.
- Creates the record if it does not exist yet.
- `/` on `HEALTH_PORT` returns JSON and `200`/`503` for probes.
- Refuses to publish private or CGNAT addresses and tells you to switch to `IP_SOURCE=public`.

## Run

```
cp .env.example .env   # fill it in
node index.ts --once --dry-run   # prove the credentials, change nothing
node index.ts --once             # one update, exit 0/1
node index.ts                    # loop forever
```

Node 24 or newer (it strips the types itself). No `npm install` needed at runtime; `npm install && npm run typecheck` for development.

## Configuration

Everything is read from the environment. See `.env.example` for the full list.

### Cloudflare

| Key | Where it comes from |
| --- | --- |
| `CF_API_TOKEN` | dash.cloudflare.com, profile (top right), **API Tokens**, **Create Token**, template **Edit zone DNS**. Under Zone Resources pick only the zone that holds the record. Copy the token once; it is not shown again. |
| `CF_RECORD_NAME` | The full record you want updated, e.g. `vpn.example.com`. It is created if missing. |
| `CF_ZONE_NAME` | Optional. The zone (`example.com`). Derived from the record name when empty. |
| `CF_TTL` | Seconds, default 60. Cloudflare's minimum for unproxied records. |
| `CF_PROXIED` | `false` unless you want the orange cloud. Keep `false` for VPN endpoints. |

### Omada controller (`IP_SOURCE=omada`)

| Key | Where it comes from |
| --- | --- |
| `OMADA_URL` | The controller's URL as reachable from this host, e.g. `https://controller.lan:8043`. Set `OMADA_TLS_VERIFY=false` if it uses the built-in self-signed certificate. |
| `OMADA_CLIENT_ID`, `OMADA_CLIENT_SECRET` | Controller UI, **Global View**, **Settings**, **Platform Integration**, **Open API**, **Add New App**. Mode **Client Credentials**, role **Viewer** is enough. The client ID and secret are shown when the app is created. Needs controller 5.9 or newer. |
| `OMADA_OMADAC_ID` | Optional. Shown on the same Open API page; discovered automatically from `/api/info` when empty. |
| `OMADA_SITE` | Optional. Site name as shown in the site picker. Only needed when the controller has more than one site. |
| `OMADA_GATEWAY_MAC` | Optional. Pins one gateway when a site has several. |
| `OMADA_WAN_PORT` | Optional. Pins one WAN port by name (`WAN1`). Default is the first WAN port that reports internet connectivity. |

### Public echo (`IP_SOURCE=public`)

Uses `https://1.1.1.1/cdn-cgi/trace` with `api.ipify.org` as a fallback. No
Omada settings needed. Use this when the gateway sits behind another NAT and
its WAN port carries a private address.

## Endpoints used

- `POST {OMADA_URL}/openapi/authorize/token?grant_type=client_credentials`
- `GET  {OMADA_URL}/openapi/v1/{omadacId}/sites`
- `GET  {OMADA_URL}/openapi/v1/{omadacId}/sites/{siteId}/devices`
- `GET  {OMADA_URL}/openapi/v1/{omadacId}/sites/{siteId}/gateways/{mac}/wan-status`
- Cloudflare `zones`, `dns_records` (GET/POST/PATCH)

## Deploying as an LXC

`ct/g403-ddns.sh` in this branch installs it: prompts for every value above,
writes `/opt/g403-ddns/.env`, runs the dry-run check and installs a systemd
unit. The container fetches `index.ts` straight from this branch's raw URL
(`var_source_url`), and `update` re-fetches it and restarts when it changed.
