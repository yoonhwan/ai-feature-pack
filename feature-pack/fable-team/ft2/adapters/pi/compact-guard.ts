// ft2 pi 압축 관문 (r1552) — 요청 직전에 ctx 를 다시 재고, 임계 C 를 넘으면 요청 0회 · 거절 1줄 · «증류 미완» 상태 파일. 압축이 실패하거나 모자라도 다음 초과 요청을 그대로 보내지 않는다.
// 차단 = ctx.abort(). before_provider_request 의 throw 는 pi 가 삼킨다(ExtensionRunner.emitBeforeProviderRequest try/catch) — 시험 2 가 실물 runner 로 그 사실을 고정한다. abort 만이 실제 요청을 0 으로 만든다(시험 3 = 가짜 provider fetch 계수).
// 압축 = ctx.compact() 1회(직렬). session_compact 성공 이벤트만으로 통과하지 않는다 — 매 요청이 재추산으로 판정한다(M1).
// 상태 파일 = <루트>/.fable-team/state/pi-compact-pending/<좌석 베이스> 1개 · wx(덮어쓰기 0) · 닫는 사건 = 재추산 ≤ C. r1553 표식(pi-distill-pending)은 읽기만 하고 쓰기·지우기 0.
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

export type Action = "allow" | "compact" | "block";
export interface Row { w: number; o: number; g: number; c?: number }
export type Table = Record<string, Row>;
export interface Budget { w: number; o: number; g: number; c: number }
export interface Decision { action: Action; rule: string; reason: string; budget?: Budget }

/** 예산 표를 파일에서 읽는다 — 읽기·파싱 실패 = null(판정 불가 = 요청 거절). */
export function loadBudget(file: string): Table | null {
  try { const models = JSON.parse(fs.readFileSync(file, "utf8"))?.models; return models && typeof models === "object" ? models : null; } catch { return null; }
}
/** 모델 id → 예산. 표에 적힌 c 와 w-o-g 가 다르면 어긋난 표라 판정 불가(null). 추정·기본값 0. */
export function limitFor(table: Table | null, model: string): Budget | null {
  if (!table || !model) return null;
  const row = table[model] ?? table[model.slice(model.lastIndexOf("/") + 1)];
  if (!row) return null;
  const w = Number(row.w), o = Number(row.o), g = Number(row.g), c = w - o - g;
  if (![w, o, g].every((n) => Number.isFinite(n) && n > 0) || c <= 0) return null;
  if (row.c !== undefined && Number(row.c) !== c) return null;
  return { w, o, g, c };
}
/** 리포 루트 = .git 이 «폴더» 인 조상(워크트리의 .git 파일은 건너뛴다 — r1553 과 같은 규칙). */
export function repoRoot(cwd: string): string | null {
  for (let dir = path.resolve(cwd); ; dir = path.dirname(dir)) {
    try { if (fs.statSync(path.join(dir, ".git")).isDirectory()) return dir; } catch { /* 위로 */ }
    if (path.dirname(dir) === dir) return null;
  }
}
/** 좌석 이름 = FT_SEAT(없으면 tmux 세션명). 못 읽으면 "" — 그때는 상태 파일 경로가 없다. */
export function seatOf(env: Record<string, string | undefined>): string {
  if (env.FT_SEAT || !env.TMUX_PANE) return env.FT_SEAT ?? "";
  try { return execFileSync("tmux", ["display", "-p", "-t", env.TMUX_PANE, "#S"], { timeout: 3000 }).toString().trim(); } catch { return ""; }
}
/** 한 요청의 판정 — 순수 함수(부작용 0). allow 이외는 요청 0. */
export function decide(table: Table | null, input: { tokens: number | null; model: string; payload?: unknown; summary: boolean; mark: boolean; tried: boolean }): Decision {
  const tokens = input.tokens ?? estimatePayload(input.payload); // ctx 추산이 없으면 payload 바이트 ÷ 3(arch#275 보정 1) — null 이면 판정하지 않고 막는다
  if (tokens === null) return { action: "block", rule: "no-usage", reason: "ctx 추산 없음 · payload 도 없음 — 추산 0 · 요청 거절(막기 0 으로 열지 않는다)" };
  const budget = limitFor(table, input.model);
  if (!budget) return { action: "block", rule: "no-budget", reason: `모델 예산 없음: ${input.model || "(모델 불명)"} — compact_guard_budget.json 에 없다(추정 0)` };
  if (input.summary) return tokens > budget.w
    ? { action: "block", rule: "summary-window", budget, reason: `요약 요청 ${tokens} > 요약 모델 창 ${budget.w} — 요약 요청도 보내지 않는다` }
    : { action: "allow", rule: "summary-within", budget, reason: `요약 요청 ${tokens} ≤ 창 ${budget.w}` };
  if (tokens <= budget.c) return { action: "allow", rule: "below-limit", budget, reason: `ctx ${tokens} ≤ C ${budget.c}` };
  if (!input.tried) return { action: "compact", rule: "over-limit-compact", budget, reason: `ctx ${tokens} > C ${budget.c} — 상태 파일 먼저 · 압축 1회 · 재추산 전 요청 0` };
  return { action: "block", rule: "over-limit", budget, reason: `ctx ${tokens} > C ${budget.c} — 압축 뒤에도 임계 초과: 요청 0 · 증류 미완 상태 파일(사람 인계 필요)` };
}
/** payload 를 토큰으로 어림한다 — JSON UTF-8 바이트 ÷ 3(보수적 · 반올림 올림). payload 없음·직렬화 불가 = null(판정 불가). */
export function estimatePayload(payload: unknown): number | null {
  if (payload === undefined || payload === null) return null;
  try { const bytes = Buffer.byteLength(JSON.stringify(payload) ?? "", "utf8"); return bytes > 0 ? Math.ceil(bytes / 3) : null; } catch { return null; }
}
export interface Guard {
  request(input: { tokens: number | null; model: string; payload?: unknown }): Decision;
  beforeCompact(): void;
  compactDone(): void;
  file(): string | null;
}
/** 관문 상태(압축 중 표지 · 압축 시도 1회)와 상태 파일. 압축 시도 표지는 «재추산 ≤ C» 닫는 사건에서만 풀린다(직렬 1회). */
export function createGuard(opts: { table: Table | null; root: string | null; seat: string }): Guard {
  const base = opts.seat.replace(/#\d+$/, "");
  const file = opts.root && base ? path.join(opts.root, ".fable-team", "state", "pi-compact-pending", base) : null;
  let summary = false, tried = false;
  const exists = (): boolean => { try { return !!file && fs.existsSync(file); } catch { return false; } };
  const write = (tokens: number, model: string): string => {
    if (!file) return opts.seat ? "상태 파일 경로 없음(리포 루트 못 찾음)" : "좌석 이름 못 읽음(TMUX_PANE·FT_SEAT) — 상태 파일 0";
    try {
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, `${new Date().toISOString()} seat=${opts.seat} ctx=${tokens} model=${model} 증류 미완\n`, { flag: "wx" });
      return "";
    } catch (e) { return (e as { code?: string })?.code === "EEXIST" ? "" : `상태 파일 쓰기 실패: ${e}`; }
  };
  return {
    file: () => file,
    beforeCompact() { summary = true; },
    compactDone() { summary = false; },
    request(input) {
      const mark = exists(), tokens = input.tokens ?? estimatePayload(input.payload);
      const d = decide(opts.table, { ...input, summary, mark, tried: tried || mark }); // 압축 시도 표지는 상태 파일이 있으면 참(새 인스턴스도 압축 재시도 0)
      if (d.rule === "below-limit" && exists()) { try { fs.rmSync(file as string, { force: true }); } catch { /* 다음 요청이 다시 닫는다 */ } tried = false; } // 숫자 재추산 ≤ C 일 때만 닫는다(요약 통과·추산 불가로 닫지 않는다)
      if (d.action === "allow") return d;
      const bad = write(tokens as number, input.model);
      if (d.action === "compact") tried = true;
      return bad ? { ...d, reason: `${d.reason} · ${bad}` } : d;
    },
  };
}
const modelOf = (ctx: any): string => String(ctx?.model?.id ?? "");
const tokensOf = (ctx: any): number | null => {
  try { const t = ctx?.getContextUsage?.()?.tokens; return typeof t === "number" ? t : null; } catch { return null; }
};
function budgetFile(): string {
  if (process.env.FT_COMPACT_GUARD_BUDGET) return process.env.FT_COMPACT_GUARD_BUDGET;
  try { return path.join(path.dirname(fileURLToPath(import.meta.url)), "compact_guard_budget.json"); } catch { /* jiti 밖 */ }
  return path.join(process.env.HOME ?? "~", ".pi", "agent", "extensions", "compact_guard_budget.json");
}
export default function compactGuard(pi: any): void {
  const table = loadBudget(budgetFile());
  const env = process.env;
  let guard: Guard | null = null;
  const build = (ctx: any): Guard => createGuard({ table, root: repoRoot(String(ctx?.cwd ?? process.cwd())), seat: seatOf(env) });
  const g = (ctx: any): Guard => (guard ??= build(ctx));
  pi.on("session_start", (_e: any, ctx: any) => { guard = build(ctx); });
  pi.on("session_before_compact", (_e: any, ctx: any) => { g(ctx).beforeCompact(); });
  pi.on("session_compact", (_e: any, ctx: any) => { g(ctx).compactDone(); });
  pi.on("session_compact_failed", (_e: any, ctx: any) => { g(ctx).compactDone(); });
  pi.on("before_provider_request", (event: any, ctx: any) => {
    const d = g(ctx).request({ tokens: tokensOf(ctx), model: modelOf(ctx), payload: event?.payload });
    if (d.action === "allow") return undefined;
    const line = `ft2 compact-guard: ${d.reason}`;
    try { ctx?.ui?.notify?.(line, "warning"); } catch { /* ui 없는 모드 */ }
    console.error(line);
    if (d.action === "compact") { try { ctx?.compact?.({ onComplete: () => undefined, onError: () => undefined }); } catch (e) { console.error(`ft2 compact-guard: 압축 호출 실패 ${e}`); } }
    ctx?.abort?.();
    return undefined;
  });
}
