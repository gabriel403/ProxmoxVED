#!/usr/bin/env node
// g403-ddns: read the gateway's WAN IP from the Omada controller (or a public
// echo service) and keep one Cloudflare A record pointed at it.
//
// No runtime dependencies. Runs directly under Node 24 (type stripping), so
// only erasable TypeScript syntax is used: no enums, namespaces or parameter
// properties. `tsconfig.json` enforces that with `erasableSyntaxOnly`.
// Configuration comes from the environment; see .env.example and the README.

import http from "node:http";
import https from "node:https";
import { URL } from "node:url";

const args = new Set(process.argv.slice(2));
const ONCE = args.has("--once");
const DRY_RUN = args.has("--dry-run");

const env = (k: string, d = ""): string => {
  const v = process.env[k];
  return v === undefined || v === "" ? d : v;
};
const bool = (k: string, d: boolean): boolean => /^(1|true|yes|on)$/i.test(env(k, d ? "true" : "false"));

type IpSource = "omada" | "public";

const cfg = {
  ipSource: env("IP_SOURCE", "omada").toLowerCase() as IpSource,
  interval: Number(env("INTERVAL_SECONDS", "60")),
  healthPort: Number(env("HEALTH_PORT", "8080")),
  omada: {
    url: env("OMADA_URL").replace(/\/+$/, ""),
    clientId: env("OMADA_CLIENT_ID"),
    clientSecret: env("OMADA_CLIENT_SECRET"),
    omadacId: env("OMADA_OMADAC_ID"),
    site: env("OMADA_SITE"),
    gatewayMac: env("OMADA_GATEWAY_MAC").toUpperCase().replace(/:/g, "-"),
    wanPort: env("OMADA_WAN_PORT"),
    tlsVerify: bool("OMADA_TLS_VERIFY", true),
  },
  cf: {
    token: env("CF_API_TOKEN"),
    record: env("CF_RECORD_NAME").toLowerCase(),
    zone: env("CF_ZONE_NAME").toLowerCase(),
    ttl: Number(env("CF_TTL", "60")),
    proxied: bool("CF_PROXIED", false),
  },
};

type Level = "info" | "warn" | "error";
const log = (level: Level, msg: string, extra?: Record<string, unknown>): void => {
  const line = `${new Date().toISOString()} ${level.toUpperCase()} ${msg}`;
  (level === "error" ? console.error : console.log)(extra ? `${line} ${JSON.stringify(extra)}` : line);
};

const errMsg = (e: unknown): string => (e instanceof Error ? e.message : String(e));

// ---------------------------------------------------------------------------
// HTTP helper (node:https so the Omada controller's self-signed cert can be
// tolerated per-request without disabling TLS verification globally).
// ---------------------------------------------------------------------------
interface RequestOptions {
  headers?: Record<string, string>;
  body?: unknown;
  insecure?: boolean;
  timeout?: number;
}
interface Response<T> {
  status: number;
  json: T | null;
  text: string;
}

function request<T = unknown>(method: string, url: string, opts: RequestOptions = {}): Promise<Response<T>> {
  const { headers = {}, body, insecure = false, timeout = 15_000 } = opts;
  const u = new URL(url);
  const payload = body === undefined ? undefined : JSON.stringify(body);
  const reqOpts: https.RequestOptions = {
    method,
    hostname: u.hostname,
    port: u.port || (u.protocol === "https:" ? 443 : 80),
    path: u.pathname + u.search,
    headers: {
      Accept: "application/json",
      "User-Agent": "g403-ddns",
      ...(payload ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) } : {}),
      ...headers,
    },
    rejectUnauthorized: !insecure,
    timeout,
  };
  const mod = u.protocol === "https:" ? https : http;
  return new Promise((resolve, reject) => {
    const req = mod.request(reqOpts, (res) => {
      let data = "";
      res.setEncoding("utf8");
      res.on("data", (c: string) => (data += c));
      res.on("end", () => {
        let json: T | null = null;
        try {
          json = data ? (JSON.parse(data) as T) : null;
        } catch {
          json = null;
        }
        resolve({ status: res.statusCode ?? 0, json, text: data });
      });
    });
    req.on("timeout", () => req.destroy(new Error(`timeout after ${timeout}ms: ${method} ${url}`)));
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

const isPrivateIp = (ip: string): boolean =>
  /^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.)/.test(ip);
const isIpv4 = (ip: string): boolean => /^(\d{1,3}\.){3}\d{1,3}$/.test(ip);

interface IpResult {
  ip: string;
  detail: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Omada Open API (client_credentials). Discovery of controller id, site and
// gateway is cached and re-done from scratch if a later call fails.
// ---------------------------------------------------------------------------
interface OmadaEnvelope<T> {
  errorCode: number;
  msg?: string;
  result: T;
}
interface OmadaInfo {
  omadacId: string;
  controllerVer?: string;
}
interface OmadaToken {
  accessToken: string;
  expiresIn?: number;
}
interface OmadaPage<T> {
  data?: T[];
}
interface OmadaSite {
  siteId: string;
  name: string;
}
interface OmadaDevice {
  mac: string;
  name?: string;
  type?: string;
  modelName?: string;
}
interface OmadaWanPort {
  name?: string;
  portDesc?: string;
  mode?: number; // 0 = WAN, 1 = LAN
  status?: number; // 1 = connected
  internetState?: number; // 1 = online
  ip?: string;
  proto?: string;
  wanPortIpv4Config?: { ip?: string };
}

const omada = {
  token: null as string | null,
  tokenExpiresAt: 0,
  omadacId: cfg.omada.omadacId,
  siteId: null as string | null,
  siteName: null as string | null,
  gatewayMac: cfg.omada.gatewayMac,

  async call<T>(method: string, path: string, body?: unknown, retry = true): Promise<T> {
    await this.ensureToken();
    const res = await request<OmadaEnvelope<T>>(method, `${cfg.omada.url}${path}`, {
      body,
      insecure: !cfg.omada.tlsVerify,
      headers: { Authorization: `AccessToken=${this.token}` },
    });
    const code = res.json?.errorCode;
    if (res.status === 401 || (code !== undefined && code !== 0 && retry && /token/i.test(res.json?.msg ?? ""))) {
      this.token = null;
      return this.call<T>(method, path, body, false);
    }
    if (res.status !== 200 || code !== 0 || !res.json) {
      throw new Error(`omada ${method} ${path} -> HTTP ${res.status} errorCode=${code} ${res.json?.msg ?? res.text.slice(0, 200)}`);
    }
    return res.json.result;
  },

  async ensureOmadacId(): Promise<void> {
    if (this.omadacId) return;
    const res = await request<OmadaEnvelope<OmadaInfo>>("GET", `${cfg.omada.url}/api/info`, { insecure: !cfg.omada.tlsVerify });
    const id = res.json?.result?.omadacId;
    if (!id) throw new Error(`could not discover omadacId from ${cfg.omada.url}/api/info (HTTP ${res.status}); set OMADA_OMADAC_ID`);
    this.omadacId = id;
    log("info", "discovered controller id", { omadacId: id, version: res.json?.result.controllerVer });
  },

  async ensureToken(): Promise<void> {
    if (this.token && Date.now() < this.tokenExpiresAt - 60_000) return;
    await this.ensureOmadacId();
    const res = await request<OmadaEnvelope<OmadaToken>>("POST", `${cfg.omada.url}/openapi/authorize/token?grant_type=client_credentials`, {
      insecure: !cfg.omada.tlsVerify,
      body: { omadacId: this.omadacId, client_id: cfg.omada.clientId, client_secret: cfg.omada.clientSecret },
    });
    if (res.status !== 200 || res.json?.errorCode !== 0) {
      throw new Error(`omada token request failed: HTTP ${res.status} errorCode=${res.json?.errorCode} ${res.json?.msg ?? res.text.slice(0, 200)}`);
    }
    this.token = res.json.result.accessToken;
    this.tokenExpiresAt = Date.now() + Number(res.json.result.expiresIn ?? 3600) * 1000;
  },

  async ensureSite(): Promise<void> {
    if (this.siteId) return;
    const r = await this.call<OmadaPage<OmadaSite>>("GET", `/openapi/v1/${this.omadacId}/sites?page=1&pageSize=100`);
    const sites = r.data ?? [];
    let site: OmadaSite | undefined;
    if (cfg.omada.site) {
      site = sites.find((s) => s.name.toLowerCase() === cfg.omada.site.toLowerCase());
    } else if (sites.length === 1) {
      site = sites[0];
    }
    if (!site) {
      throw new Error(`site "${cfg.omada.site || "(unset)"}" not found; controller has: ${sites.map((s) => s.name).join(", ") || "none"}`);
    }
    this.siteId = site.siteId;
    this.siteName = site.name;
    log("info", "using site", { site: site.name, siteId: site.siteId });
  },

  async ensureGateway(): Promise<void> {
    if (this.gatewayMac) return;
    const r = await this.call<OmadaPage<OmadaDevice>>("GET", `/openapi/v1/${this.omadacId}/sites/${this.siteId}/devices?page=1&pageSize=100`);
    const gws = (r.data ?? []).filter((d) => String(d.type).toLowerCase() === "gateway");
    const first = gws[0];
    if (!first) throw new Error(`no gateway adopted in site "${this.siteName}"`);
    if (gws.length > 1) {
      log("warn", "multiple gateways found, using the first; set OMADA_GATEWAY_MAC to pin one", { gateways: gws.map((g) => `${g.name} ${g.mac}`) });
    }
    this.gatewayMac = first.mac;
    log("info", "using gateway", { name: first.name, mac: first.mac, model: first.modelName });
  },

  async wanIp(): Promise<IpResult> {
    try {
      await this.ensureSite();
      await this.ensureGateway();
      return await this.readWan();
    } catch (err) {
      // Drop cached discovery so a renamed site / replaced gateway heals itself.
      this.siteId = null;
      this.gatewayMac = cfg.omada.gatewayMac;
      throw err;
    }
  },

  async readWan(): Promise<IpResult> {
    const ports = await this.call<OmadaWanPort[]>("GET", `/openapi/v1/${this.omadacId}/sites/${this.siteId}/gateways/${this.gatewayMac}/wan-status`);
    const wans = (ports ?? []).filter((p) => p.mode === 0);
    let pick: OmadaWanPort | undefined;
    if (cfg.omada.wanPort) {
      const want = cfg.omada.wanPort.toLowerCase();
      pick = wans.find((p) => [p.name, p.portDesc].some((n) => String(n ?? "").toLowerCase() === want));
      if (!pick) throw new Error(`WAN port "${cfg.omada.wanPort}" not found; gateway has: ${wans.map((p) => p.name).join(", ")}`);
    } else {
      pick =
        wans.find((p) => p.status === 1 && p.internetState === 1 && (p.ip || p.wanPortIpv4Config?.ip)) ??
        wans.find((p) => p.status === 1);
      if (!pick) throw new Error(`no connected WAN port on gateway ${this.gatewayMac}`);
    }
    const ip = pick.ip || pick.wanPortIpv4Config?.ip;
    if (!ip || !isIpv4(ip)) {
      throw new Error(`WAN port "${pick.name}" has no IPv4 address (status=${pick.status} internetState=${pick.internetState})`);
    }
    return { ip, detail: { port: pick.name, proto: pick.proto, internetState: pick.internetState } };
  },
};

// ---------------------------------------------------------------------------
// Public echo fallback (for double-NAT setups where the gateway's WAN address
// is not the internet-facing one).
// ---------------------------------------------------------------------------
async function publicIp(): Promise<IpResult> {
  const r = await request("GET", "https://1.1.1.1/cdn-cgi/trace", { headers: { Accept: "text/plain" } });
  const m = /^ip=(.+)$/m.exec(r.text);
  const traced = m?.[1]?.trim();
  if (r.status === 200 && traced && isIpv4(traced)) return { ip: traced, detail: { via: "1.1.1.1/cdn-cgi/trace" } };
  const r2 = await request<{ ip?: string }>("GET", "https://api.ipify.org?format=json");
  const ip2 = r2.json?.ip;
  if (r2.status === 200 && ip2 && isIpv4(ip2)) return { ip: ip2, detail: { via: "api.ipify.org" } };
  throw new Error(`public IP lookup failed (HTTP ${r.status} / ${r2.status})`);
}

// ---------------------------------------------------------------------------
// Cloudflare DNS
// ---------------------------------------------------------------------------
interface CfEnvelope<T> {
  success: boolean;
  errors?: { code: number; message: string }[];
  result: T;
}
interface CfZone {
  id: string;
  name: string;
}
interface CfRecord {
  id: string;
  name: string;
  content: string;
  ttl: number;
  proxied: boolean;
}

const cf = {
  base: "https://api.cloudflare.com/client/v4",
  zoneId: null as string | null,
  zoneName: null as string | null,

  async call<T>(method: string, path: string, body?: unknown): Promise<T> {
    const res = await request<CfEnvelope<T>>(method, `${this.base}${path}`, { body, headers: { Authorization: `Bearer ${cfg.cf.token}` } });
    if (!res.json?.success) {
      const errs = (res.json?.errors ?? []).map((e) => `${e.code}: ${e.message}`).join("; ");
      throw new Error(`cloudflare ${method} ${path} -> HTTP ${res.status} ${errs || res.text.slice(0, 200)}`);
    }
    return res.json.result;
  },

  async ensureZone(): Promise<void> {
    if (this.zoneId) return;
    const labels = cfg.cf.record.split(".");
    const candidates = cfg.cf.zone ? [cfg.cf.zone] : labels.map((_, i) => labels.slice(i).join(".")).filter((c) => c.includes("."));
    for (const name of candidates) {
      const zones = await this.call<CfZone[]>("GET", `/zones?name=${encodeURIComponent(name)}&status=active`);
      const zone = zones[0];
      if (zone) {
        this.zoneId = zone.id;
        this.zoneName = zone.name;
        log("info", "using zone", { zone: zone.name, zoneId: zone.id });
        return;
      }
    }
    throw new Error(`no Cloudflare zone found for ${cfg.cf.record} (tried ${candidates.join(", ")}); check the token's zone scope or set CF_ZONE_NAME`);
  },

  async current(): Promise<CfRecord | null> {
    await this.ensureZone();
    const recs = await this.call<CfRecord[]>("GET", `/zones/${this.zoneId}/dns_records?type=A&name=${encodeURIComponent(cfg.cf.record)}`);
    return recs[0] ?? null;
  },

  async upsert(ip: string, existing: CfRecord | null): Promise<CfRecord> {
    const body = { type: "A", name: cfg.cf.record, content: ip, ttl: cfg.cf.ttl, proxied: cfg.cf.proxied, comment: "managed by g403-ddns" };
    if (existing) return this.call<CfRecord>("PATCH", `/zones/${this.zoneId}/dns_records/${existing.id}`, body);
    return this.call<CfRecord>("POST", `/zones/${this.zoneId}/dns_records`, body);
  },
};

// ---------------------------------------------------------------------------
// Main loop + health endpoint
// ---------------------------------------------------------------------------
interface State {
  ok: boolean;
  ip: string | null;
  recordIp: string | null;
  lastSuccess: string | null;
  lastError: string | null;
  lastRun: string | null;
  updates: number;
}
const state: State = { ok: false, ip: null, recordIp: null, lastSuccess: null, lastError: null, lastRun: null, updates: 0 };

async function cycle(): Promise<boolean> {
  state.lastRun = new Date().toISOString();
  try {
    const { ip, detail } = cfg.ipSource === "public" ? await publicIp() : await omada.wanIp();
    if (isPrivateIp(ip)) {
      throw new Error(`WAN IP ${ip} is a private/CGNAT address; DNS would be useless. If you are behind another NAT set IP_SOURCE=public`);
    }
    const rec = await cf.current();
    state.recordIp = rec?.content ?? null;
    if (rec && rec.content === ip && rec.ttl === cfg.cf.ttl && rec.proxied === cfg.cf.proxied) {
      if (state.ip !== ip) log("info", "record already current", { record: cfg.cf.record, ip, ...detail });
    } else if (DRY_RUN) {
      log("info", "dry-run: would update record", { record: cfg.cf.record, from: rec?.content ?? "(none)", to: ip, ...detail });
    } else {
      const r = await cf.upsert(ip, rec);
      state.updates += 1;
      state.recordIp = r.content;
      log("info", rec ? "updated record" : "created record", { record: cfg.cf.record, from: rec?.content ?? "(none)", to: ip, ...detail });
    }
    state.ip = ip;
    state.ok = true;
    state.lastSuccess = new Date().toISOString();
    state.lastError = null;
    return true;
  } catch (err) {
    state.ok = false;
    state.lastError = `${new Date().toISOString()} ${errMsg(err)}`;
    log("error", errMsg(err));
    return false;
  }
}

function validate(): void {
  const missing: string[] = [];
  if (!cfg.cf.token) missing.push("CF_API_TOKEN");
  if (!cfg.cf.record) missing.push("CF_RECORD_NAME");
  if (cfg.ipSource === "omada") {
    if (!cfg.omada.url) missing.push("OMADA_URL");
    if (!cfg.omada.clientId) missing.push("OMADA_CLIENT_ID");
    if (!cfg.omada.clientSecret) missing.push("OMADA_CLIENT_SECRET");
  } else if (cfg.ipSource !== "public") {
    log("error", `IP_SOURCE must be "omada" or "public", got "${String(cfg.ipSource)}"`);
    process.exit(2);
  }
  if (missing.length) {
    log("error", `missing required configuration: ${missing.join(", ")}`);
    process.exit(2);
  }
  if (!Number.isFinite(cfg.interval) || cfg.interval < 10) {
    log("error", "INTERVAL_SECONDS must be a number >= 10");
    process.exit(2);
  }
}

function startHealth(): void {
  if (!cfg.healthPort) return;
  http
    .createServer((_req, res) => {
      const body = JSON.stringify({ ...state, source: cfg.ipSource, record: cfg.cf.record, interval: cfg.interval }, null, 2);
      res.writeHead(state.ok ? 200 : 503, { "Content-Type": "application/json" });
      res.end(body);
    })
    .listen(cfg.healthPort, () => log("info", "health endpoint listening", { port: cfg.healthPort }));
}

validate();
log("info", "starting", { source: cfg.ipSource, record: cfg.cf.record, interval: cfg.interval, once: ONCE, dryRun: DRY_RUN });

if (ONCE) {
  process.exit((await cycle()) ? 0 : 1);
}

startHealth();
let stopping = false;
for (const sig of ["SIGINT", "SIGTERM"] as const) {
  process.on(sig, () => {
    stopping = true;
    log("info", `received ${sig}, exiting`);
    process.exit(0);
  });
}
// A failed cycle (resolver not up yet at boot, controller restarting) is
// retried with a short backoff instead of waiting out the whole interval.
let failures = 0;
while (!stopping) {
  const ok = await cycle();
  failures = ok ? 0 : failures + 1;
  const delay = ok ? cfg.interval : Math.min(cfg.interval, 15 * 2 ** Math.min(failures - 1, 5));
  if (!ok) log("warn", `retrying in ${delay}s`, { failures });
  await new Promise((r) => setTimeout(r, delay * 1000));
}
