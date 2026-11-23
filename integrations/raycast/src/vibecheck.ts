import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { promisify } from "node:util";

const run = promisify(execFile);

export const BUNDLE_ID = "io.github.saroj-shahi.vibecheck";

export type Vibe = "vibing" | "mid" | "cooked";

export interface Limit {
  key?: string;
  agent?: string;
  name?: string;
  label?: string;
  /** 0...1 or 0...100, normalised by leftPercent(). */
  left?: number;
  leftPercent?: number;
  usedPercent?: number;
  resetsAt?: string;
  resetsInMinutes?: number;
  /** ISO date when the limit runs out at the current pace; absent when it lasts until the reset. */
  runsOutAt?: string;
  forecast?: string | { text?: string; summary?: string };
}

export interface Status {
  schema?: number;
  updatedAt?: string;
  vibe: string;
  verdict: string;
  culprit?: string | null;
  cpu?: number;
  memoryPressure?: string;
  swapUsedBytes?: number;
  thermalState?: string;
  battery?: { percent: number; onAC: boolean; minutesLeft?: number | null } | null;
  topMemory?: { name: string; bytes: number; processes?: number; growthBytes?: number; growthMinutes?: number }[];
  topCPU?: { name: string; cpu: number; processes?: number }[];
  topCPUAt?: string;
  stale?: boolean;
  // Possible later additions: every field is optional and only rendered when present.
  agentLimits?: Limit[];
  limits?: Limit[];
  devServers?: { name?: string; port?: number; url?: string; pid?: number; command?: string }[];
  /** Top apps by estimated energy since local midnight (share is 0...1). */
  energyToday?: { name: string; wattHours: number; share: number }[];
}

const CANDIDATES = [
  "/Applications/VibeCheck.app/Contents/Helpers/vibecheck",
  `${homedir()}/Applications/VibeCheck.app/Contents/Helpers/vibecheck`,
];

/** The bundled helper if present, else `vibecheck` on PATH. */
export function findBinary(): string {
  return CANDIDATES.find((p) => existsSync(p)) ?? "vibecheck";
}

export type Reason = "missing" | "unreadable";
export type Loaded = { ok: true; status: Status } | { ok: false; reason: Reason };

export async function loadStatus(): Promise<Loaded> {
  const env = { ...process.env, PATH: `${process.env.PATH ?? ""}:/usr/local/bin:/opt/homebrew/bin` };
  try {
    const { stdout } = await run(findBinary(), ["status", "--json"], { env, timeout: 10_000 });
    const parsed = JSON.parse(stdout) as Status;
    if (!parsed || typeof parsed.vibe !== "string") return { ok: false, reason: "unreadable" };
    return { ok: true, status: parsed };
  } catch (error) {
    const code = (error as { code?: string | number }).code;
    // ENOENT: no binary. Exit 3: the CLI found no status file (the app has never run).
    if (code === "ENOENT" || code === 3) return { ok: false, reason: "missing" };
    return { ok: false, reason: "unreadable" };
  }
}

export function culpritRows(s: Status, by: "memory" | "cpu" = "memory"): { name: string; detail: string }[] {
  if (by === "cpu" && s.topCPU?.length) {
    return s.topCPU.map((c) => ({ name: c.name, detail: `${Math.round(c.cpu)}% CPU${plural(c.processes)}` }));
  }
  return (s.topMemory ?? []).map((m) => {
    let detail = `${bytesText(m.bytes)}${plural(m.processes)}`;
    if (m.growthBytes && m.growthBytes >= 100_000_000 && m.growthMinutes) {
      detail += `, +${bytesText(m.growthBytes)} in ${m.growthMinutes} min`;
    }
    return { name: m.name, detail };
  });
}

function plural(n?: number): string {
  return n && n > 1 ? ` (${n} processes)` : "";
}

export function bytesText(value: number): string {
  const gb = value / 1_000_000_000;
  return gb >= 1 ? `${gb.toFixed(1)} GB` : `${Math.round(value / 1_000_000)} MB`;
}

export function vibeWord(s: Status): Vibe {
  return s.vibe === "mid" || s.vibe === "cooked" ? s.vibe : "vibing";
}

export function limitsOf(s: Status): Limit[] {
  return s.agentLimits ?? s.limits ?? [];
}

export function limitTitle(l: Limit): string {
  return [l.agent, l.name ?? l.label ?? l.key].filter(Boolean).join(" ") || "Limit";
}

export function leftPercent(l: Limit): number | undefined {
  if (typeof l.leftPercent === "number") return Math.round(l.leftPercent);
  if (typeof l.usedPercent === "number") return Math.round(100 - l.usedPercent);
  if (typeof l.left === "number") return Math.round(l.left <= 1 ? l.left * 100 : l.left);
  return undefined;
}

export function resetsIn(l: Limit, now = Date.now()): string | undefined {
  let minutes = l.resetsInMinutes;
  if (minutes === undefined && l.resetsAt) {
    const t = Date.parse(l.resetsAt);
    if (!Number.isNaN(t)) minutes = Math.max(0, Math.round((t - now) / 60_000));
  }
  if (minutes === undefined) return undefined;
  if (minutes < 60) return `${minutes} min`;
  if (minutes < 48 * 60) return `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
  return `${Math.round(minutes / 1440)} days`;
}

export function forecastText(l: Limit): string | undefined {
  const f = l.forecast;
  if (f) return typeof f === "string" ? f : (f.text ?? f.summary);
  if (l.runsOutAt) {
    const t = new Date(l.runsOutAt);
    if (!Number.isNaN(t.getTime())) {
      const time = t.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" }).toLowerCase();
      return `runs out ~${time}`;
    }
  }
  return l.resetsAt || l.resetsInMinutes !== undefined ? "on pace to last until reset" : undefined;
}

export interface Reading {
  title: string;
  value: string;
}

export function readings(s: Status): Reading[] {
  const out: Reading[] = [];
  if (typeof s.cpu === "number") out.push({ title: "CPU", value: `${Math.round(s.cpu * 100)}%` });
  if (s.memoryPressure) out.push({ title: "Memory pressure", value: cap(s.memoryPressure) });
  if (typeof s.swapUsedBytes === "number") out.push({ title: "Swap used", value: bytesText(s.swapUsedBytes) });
  if (s.thermalState) out.push({ title: "Thermal state", value: cap(s.thermalState) });
  if (s.battery) {
    const b = s.battery;
    const left = b.minutesLeft ? `, ${Math.floor(b.minutesLeft / 60)} h ${b.minutesLeft % 60} min left` : "";
    out.push({ title: "Battery", value: `${Math.round(b.percent * 100)}%${b.onAC ? ", on charger" : left}` });
  }
  for (const e of s.energyToday ?? []) {
    const wh = e.wattHours < 0.05 ? "<0.1 Wh" : `${e.wattHours.toFixed(1)} Wh`;
    out.push({ title: `Energy today: ${e.name}`, value: `${wh} · ${Math.round(e.share * 100)}%` });
  }
  return out;
}

export function cap(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1);
}

export function statusText(s: Status): string {
  const lines = [s.verdict];
  for (const r of readings(s)) lines.push(`${r.title}: ${r.value}`);
  const c = culpritRows(s);
  if (c.length) lines.push("", "Culprits", ...c.map((r, i) => `${i + 1}. ${r.name}  ${r.detail}`));
  for (const l of limitsOf(s)) {
    const left = leftPercent(l);
    const reset = resetsIn(l);
    lines.push(`${limitTitle(l)}: ${left === undefined ? "" : left + "% left"}${reset ? ", resets in " + reset : ""}`);
  }
  return lines.join("\n");
}

export function emptyMessage(reason: Reason): { title: string; description: string } {
  return reason === "unreadable"
    ? { title: "Couldn't read VibeCheck's status", description: "Open VibeCheck once, then try again." }
    : {
        title: "VibeCheck isn't installed or hasn't run yet",
        description: "Install VibeCheck and open it once. This command reads its status.",
      };
}
