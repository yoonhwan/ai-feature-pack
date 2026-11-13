// ft2 pi 증류 게이트 (r1553) — claude 훅과 같은 축을 pi 좌석에 건다(REC arch273 cb5f7c01d2 (a)). WARN = 매 턴 경고 1줄(막기 0) · BLOCK = 허용 목록 밖 tool_call 막음 · RECV = mbox recv 막음. 문턱은 파일에서만 읽는다(extension 안 숫자 0) — env FT_DISTILL_{WARN,BLOCK,RECV} > <루트>/.fable-team/thresholds.env > ~/.claude/fable-team/thresholds.env. 판정 불가(모델 불명·usage 없음·문턱 못 읽음·좌석 불명) = 막고 팀장 1줄(같은 좌석·같은 이유 세션당 1통).
// r1565: 판정 불가 중 «ctx usage 없음» 만 r1554 와 같은 3갈래 — ⓐ 세션 첫 판정 = 통과+기록(알림 0) · ⓑ 같은 세션 연속 N(FT_DISTILL_FAILOPEN_MAX 기본 3) = 허용 목록 모드(밖 도구만 막음) + 팀장 1줄(세션당 1통) · ⓗ 턴 시작(before_agent_start) usage 없음 = 주입 0 · 알림 0 · 연속 횟수 불변. ⓔ 읽은 뒤의 null 은 «첫 판정» 이 아니고(연속 횟수에 더한다) 표식을 지우지 않는다 · ⓘ 읽음 = 양수(>0)만 · ⓙ 초기 예외 = 새 대화(startup|new ∧ assistant 0 ∧ compaction 0 ∧ 표식 0)뿐 · ⓛ 그 «표식 0» = 이 좌석 전체 이름(#N)이 적힌 표식 없음(같은 베이스 직전 세대 #N-1 표식은 막지 않는다 · 이름 없는 옛 표식·읽기 실패는 지금처럼 초기 예외 0) · ⓜ 승계 첫 턴 = 주입 0·알림 0·연속 횟수 불변. 모델·문턱·좌석 불명은 지금처럼 즉시 막는다(ⓕ).
// r1634 = ft 좌석이 아니면 아무것도 하지 않는다 — 첫 갈래 = allow(rule not-seat) · 도구 차단 0 · 팀장 알림 0 · 표식 쓰기 0 · misses 증가 0. 좌석 판정 = FT_SEAT ∨ (tmux 세션명 == <루트>/.fable-team/seats*.json 키 «#N 뺀 이름») · 좌석 안의 판정 불가·fail-closed 는 그대로.
// 대상 = model 이 claude 계열인 pi 좌석만(gpt·gemini·deepseek = 판정 0). 알림 = FT_MBOX 명령 + seats*.json 현역 master 행. 허용 목록은 claude 훅보다 넓다(mbox handover·ready·close-check) — 증류 마무리가 막히지 않게. 증류 미완 표식 = <루트>/.fable-team/state/pi-distill-pending/<좌석 베이스> 1개 · 덮어쓰기 0 · 닫는 사건 = 후계 좌석(같은 베이스 · 다른 #N)의 첫 판정 1개 · 같은 좌석은 압축으로 ctx 가 줄어도 유지(arch 확인 · DA R3).
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { execFileSync } from "node:child_process";

export type Action = "allow" | "warn" | "block";
export interface Lines { warn: number; block: number; recv: number }
export interface Verdict { action: Action; rule: string; reason: string }
export interface GateInput { // 한 tool_call 입력 · session = pi 세션 신원(닫는 사건·새 대화 판정용)
  tool: string; command?: string; path?: string; tokens?: number | null; model?: string; cwd?: string; seat?: string; env?: Record<string, string | undefined>; notify?: (to: string, body: string) => boolean;
  session?: { reason?: string; entries?: unknown[]; fresh?: boolean }; // reason = session_start reason · entries = getEntries() · fresh = 턴 시작에 잰 «새 대화" (ⓙ)
}
const K = { warn: "FT_DISTILL_WARN", block: "FT_DISTILL_BLOCK", recv: "FT_DISTILL_RECV" };
const SUBS = ["send", "relay", "recv", "peek", "ring", "handover", "ready", "mark", "unmarked", "close-check"];
const SCRIPTS = ["ft-tmux-distill.sh", "ft-tmux-spawn.sh", "ft-role-spawn.sh", "ft-nano-spawn.sh", "ft-version.sh", "ft-successor-open.sh", "ft-reach-check.sh", "ft-send-verified.sh"];
const MBOX = ["mbox.sh", "ft-mbox.sh"], EXT = [".md", ".json", ".jsonl", ".txt"], NEW = new Set(["startup", "new"]); // NEW = ⓙ 초기 예외가 허용되는 session_start reason
/** thresholds.env 한 줄들 = KEY=VALUE(따옴표 벗김) · 파일 없음·읽기 실패 = null · 우선순위 = env > <루트>/.fable-team > ~/.claude/fable-team > 설치본 thresholds.env.sample(r1860 · <루트>/.fable-team/LIVE_BIN 의 부모/templates · claude 도구와 같은 순서) */
const read = (file: string | null | undefined): Record<string, string> | null => { try { return Object.fromEntries([...fs.readFileSync(file ?? "", "utf8").matchAll(/^\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)=(.*)$/gm)].map((m) => [m[1], m[2].trim().replace(/^(['"])(.*)\1$/, "$2")])); } catch { return null; } };
const envFiles = (env: Record<string, string | undefined>, root: string | null): Array<Record<string, string> | null> => [env.FT_DISTILL_THRESHOLDS, root && path.join(root, ".fable-team", "thresholds.env"), path.join(os.homedir(), ".claude", "fable-team", "thresholds.env"), sample(root)].map(read);
const sample = (root: string | null): string | null => { try { const bin = root ? fs.readFileSync(path.join(root, ".fable-team", "LIVE_BIN"), "utf8").trim() : ""; return bin ? path.join(path.dirname(bin), "templates", "thresholds.env.sample") : null; } catch { return null; } };
/** 문턱 = 파일에서만 읽는다(extension 안 숫자 0) · 키 하나라도 없으면 null = 판정 불가. */
export function thresholds(env: Record<string, string | undefined>, root: string | null): Lines | null {
  const files = envFiles(env, root);
  const pick = (key: string): number | null => { const s = String(env[key] ?? files.map((f) => f?.[key]).find((v) => v !== undefined) ?? "").trim(); return /^\d+$/.test(s) ? Number(s) : null; };
  const warn = pick(K.warn), block = pick(K.block), recv = pick(K.recv);
  return warn && block && recv ? { warn, block, recv } : null;
}
export const newConversation = (reason: string | undefined, entries: unknown[] | undefined): boolean => !!(reason && NEW.has(reason) && Array.isArray(entries) && !entries.some((e: any) => (e?.type === "message" && e?.message?.role === "assistant") || e?.type === "compaction")); // ⓙ «새 대화» = reason ∈ {startup,new} ∧ assistant 메시지 0 ∧ compaction 0 — 못 읽으면 false(초기 예외 0)
/** 리포 루트 = .git 이 «폴더» 인 조상(워크트리의 .git 파일은 건너뛴다 — claude 훅과 같은 규칙). */
export function repoRoot(cwd: string): string | null {
  for (let dir = path.resolve(cwd); ; dir = path.dirname(dir)) {
    try { if (fs.statSync(path.join(dir, ".git")).isDirectory()) return dir; } catch { /* 위로 */ } if (path.dirname(dir) === dir) return null;
  }
}
/** 따옴표 안을 "_" 로 덮은 같은 길이 사본 — 구분자·리다이렉트·주석을 따옴표 밖에서만 본다. */
const mask = (s: string): string => s.replace(/"(?:[^"\\]|\\.)*"|'[^']*'/g, (q) => "_".repeat(q.length));
function splitTop(s: string): string[] {
  const m = mask(s), out: string[] = [];
  let start = 0;
  for (let i = 0; i < s.length; i++) {
    const d = ["||", "&&", ";", "|", "\n", "&"].find((t) => m.startsWith(t, i) && !(t === "&" && (/[<>]/.test(m[i - 1] ?? "") || m[i + 1] === ">")));
    if (d) { out.push(s.slice(start, i), d); start = i += d.length; }
  }
  return [...out, s.slice(start)];
}
/** shlex 꼴 토큰 — 닫히지 않은 따옴표는 null(=차단). */
const words = (s: string): string[] | null => (/["']/.test(s.replace(/"[^"]*"|'[^']*'/g, "")) ? null : [...s.matchAll(/"([^"]*)"|'([^']*)'|(\S+)/g)].map((m) => (m[1] ?? m[2] ?? m[3]) as string));
const PUSH_OPT = new Set(["-u", "--set-upstream", "-q", "--quiet", "-v", "--verbose", "--dry-run", "-n", "--follow-tags", "--tags", "--all", "--porcelain"]);
function gitAllowed(frag: string): boolean {
  if (!/^\s*git\b/.test(frag)) return true; // 공통 분기(:83~84)는 cd·baton·tmux·tmuxc·sleep·pgrep 도 넣는다 — git 판정은 git 조각에만(DA R5 직접 회귀)
  const sub = (frag.match(/^\s*git\s+(?:-C\s+\S+\s+)?(add|commit|status|diff|log|push)\b/) ?? [])[1];
  if (!sub) return false; // 허용 6개 밖 git = 막음(DA R5 · claude 훅과 같다)
  const toks = sub === "push" && /[$\\{]/.test(frag) ? null : words(frag); if (!toks || toks.some((t) => /^--output(?:=.*)?$/.test(t) || (t === "-o" && sub !== "commit"))) return false;
  if (sub !== "push") return true;
  return toks.slice(toks.lastIndexOf("push") + 1).every((t) => t.startsWith("-") ? PUSH_OPT.has(t) : !/^(?:\+.*|:.*|.*:)$/.test(t));
}
function relTo(root: string | null, p: string): string | null {
  if (!root || !p || /(^|\/)\.\.(\/|$)/.test(p)) return null;
  const rel = path.relative(root, path.resolve(root, p)).replace(/\\/g, "/"); return rel && !rel.startsWith("../") ? rel : null;
}
function scriptAllowed(frag: string, root: string | null): boolean {
  const m = frag.match(/^(?:bash\s+)?(\S+)(?:\s+([\s\S]*))?$/);
  if (!m) return false; m[1] = m[1].replace(/^["']|["']$/g, ""); // 경로 따옴표는 벗겨서 본다(DA R4)
  if (/\.\.(\/|$)/.test(m[1]) || !relTo(root, m[1])) return false;
  const parts = m[1].split("/").filter(Boolean), name = parts[parts.length - 1];
  if (!/^(?:\.worktrees\/[^/]+\/)?\.fable-team\/(?:bin|comm)\/[^/]+$/.test(parts.slice(-3).join("/")) && !/^\.claude\/fable-team\/bin\/[^/]+$/.test(parts.slice(-4).join("/"))) return false;
  return MBOX.includes(name) ? SUBS.includes((m[2] ?? "").trim().split(/\s+/)[0]) : SCRIPTS.includes(name);
}
/** claude 훅 hard_allowed 의 Bash 판정 이식 — 명령 조각 단위 · allowlist 밖은 전부 막는다. */
export function bashAllowed(command: string | undefined, root: string | null): boolean {
  const cmd = String(command ?? "");
  if (!cmd.trim()) return true;
  if (cmd.includes("$(") || cmd.includes("`")) return false; // 명령치환·백틱은 따옴표 안이어도 막는다(claude 훅과 같다)
  let prev = "";
  for (const piece of splitTop(cmd)) {
    if (["||", "&&", ";", "|", "&", "\n"].includes(piece)) { prev = piece; continue; }
    const masked = mask(piece);
    if (/(^|\s)#/.test(masked) || /<<|<\(/.test(masked)) return false;
    if (/[<>]/.test(masked.replace(/(?:2>&1|2>\/dev\/null|>\/dev\/null)(?=\s|$)/g, " ").replace(/</g, " "))) return false;
    const frag = piece.trim();
    if (!frag) { prev = ""; continue; }
    const wrap = frag.match(/^(?:zsh|bash)\s+-l?c\s+(['"])([\s\S]*)\1$/);
    if (wrap) { if (!bashAllowed(wrap[2], root)) return false; }
    else if (prev === "|" && /^(?:cat\b|tail\s+-\d+|head\s+-\d+|grep\b|wc\b)/.test(frag)) { /* 읽기만 */ }
    else if (/^(?:cd\s+\S+|(?:[^\s]*\/)?baton\s+(?:save|finish)\b|git\s|tmuxc\s+(?:open|save|list|distill)\b|tmux\s+(?:capture-pane|list-\S*)\b|sleep\b|pgrep\b)/.test(frag)) {
      if (!gitAllowed(frag)) return false;
    } else if (!scriptAllowed(frag, root)) return false;
    prev = "";
  }
  return true;
}
/** claude 훅 path_allowed 이식 — 인계서·state·design inbox 만 쓰기 허용. */
export function pathAllowed(p: string | undefined, root: string | null): boolean {
  const rel = relTo(root, String(p ?? "")); if (!rel) return false;
  if (/^(?:\.worktrees\/[^/]+\/)?(?:\.fable-team\/(?:state|comm)\/|\.baton\/)/.test(rel)) {
    if (!EXT.some((e) => rel.toLowerCase().endsWith(e))) return false;
    let real = rel; try { real = relTo(root, fs.realpathSync.native(path.join(root as string, rel))) ?? ".claude/"; } catch { /* 신규 파일 = 있는 그대로(Python realpath 와 같다) */ }
    return !real.startsWith(".claude/") && !/(^|\/)bin\//.test(real);
  }
  return [/(^|\/)design\/[^/]+\/(?:IMPL|HANDOFF|VERDICT|PROGRESS)-[^/]*\.md$/, /(^|\/)HANDOFF-[^/]*\.md$/, /(^|\/)design\/(?:[^/]+\/)*inbox\/(?:[^/]+\/)*[^/]+\.md$/, /(^|\/)\d+-HANDOFF-[^/]*\.md$/].some((rx) => rx.test(rel));
}
/** r1634 좌석 판정 — true = ft 좌석 · false = 좌석 아님(no-op) · null = 판정 불가(지금처럼 막는다 · 하드 룰 20: 이름 못 읽음 ≠ 좌석 아님). declared = 호출자가 이미 좌석 이름을 확정해 넘김(그 이름이 명부에 없으면 판정 불가). 루트를 못 찾으면 명부 대조는 거짓 · 명부 파일이 깨졌으면 판정 불가. */
export function seatVerdict(env: Record<string, string | undefined>, root: string | null, seat: string, declared = false): boolean | null {
  if (String(env.FT_SEAT ?? "").trim()) return true;
  if (!seat) return env.TMUX_PANE || declared ? null : false;
  const base = seat.replace(/#\d+$/, ""), dir = root ? path.join(root, ".fable-team") : "";
  let broken = false;
  try {
    for (const f of fs.readdirSync(dir).filter((n) => /^seats.*\.json$/.test(n))) {
      try { const j = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")); if (Object.keys(j).some((row) => !row.startsWith("_") && (row === seat || row.replace(/#\d+$/, "") === base))) return true; } catch { broken = true; } // 깨진 명부 = 판정 불가(하드 룰 20)
    }
  } catch { /* .fable-team 없음 = 명부 없음 */ }
  return broken || declared ? null : false; // 명부 조회 실패를 «좌석 아님» 으로 단정하지 않는다
}
function seatOf(env: Record<string, string | undefined>): string {
  if (env.FT_SEAT || !env.TMUX_PANE) return env.FT_SEAT ?? ""; try { return execFileSync("tmux", ["display", "-p", "-t", env.TMUX_PANE, "#S"], { timeout: 3000 }).toString().trim(); } catch { return ""; }
}
const notified = new Set<string>(), seenUsage = new Map<string, boolean>(), misses = new Map<string, number>(); // ⓘ 양수 usage 를 한 번이라도 읽었나 · ⓑ 세션 안 연속 판정 불가 횟수(extension 하나 = 한 세션)
/** mbox recv 인가 — 따옴표를 벗긴 토큰으로 본다(`bash "…/mbox.sh" recv` 포함 · DA R4). */
const isRecv = (cmd: string | undefined): boolean => { const t = words(String(cmd ?? "")); return !!t && t.some((w, i) => MBOX.includes(path.basename(w)) && t[i + 1] === "recv"); };
const mboxScript = (env: Record<string, string | undefined>, root: string | null): string => { // 팀장 알림 명령 = FT_MBOX > <루트>/.fable-team/comm/mbox.sh(파일이 있을 때) · 둘 다 없으면 ""
  const builtin = root ? path.join(root, ".fable-team", "comm", "mbox.sh") : "";
  return env.FT_MBOX || (builtin && fs.existsSync(builtin) ? builtin : "");
};
/** 표식 본문의 좌석 전체 이름(#N 포함) — 옛 파일처럼 없으면 ""(= 자동으로 닫지 않는다). */
const seatIn = (state: string | null): string => { try { return (fs.readFileSync(state ?? "", "utf8").match(/seat=(\S+)/) ?? [])[1] ?? ""; } catch { return ""; } };
/** 이 좌석의 팀장 = 그 좌석 행이 있는 seats 파일의 _master. 찾는 곳 = FT_MBOX 의 .fable-team → 리포 루트. 다른 팀 명부의 master 를 고르지 않는다(arch#274 동작 반례 1). */
function teamMaster(env: Record<string, string | undefined>, root: string | null, seat: string): string {
  const mbox = mboxScript(env, root); let dir = mbox ? path.dirname(path.resolve(mbox)) : "";
  while (dir && path.basename(dir) !== ".fable-team" && path.dirname(dir) !== dir) dir = path.dirname(dir);
  if (path.basename(dir) !== ".fable-team") dir = path.join(root ?? "/nonexistent", ".fable-team");
  const base = seat.replace(/#\d+$/, "");
  try {
    for (const f of fs.readdirSync(dir).filter((n) => /^seats.*\.json$/.test(n))) {
      const data = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
      if (Object.keys(data).some((k) => k === seat || k.replace(/#\d+$/, "") === base)) return String(data._master ?? "");
    }
  } catch { /* 명부 없음 = 팀장 불명 */ }
  return "";
}
function notifyTeam(input: GateInput, env: Record<string, string | undefined>, seat: string, root: string | null, why: string): string {
  const key = `${seat}|${why}`; if (notified.has(key)) return ""; notified.add(key);
  const master = teamMaster(env, root, seat), body = `[긴급] 증류 판정 불가 ${seat} ${why}`;
  if (!master) return "팀장 불명 — seats 명부에 이 좌석 행이나 _master 없음(send 0)";
  if (input.notify) { input.notify(master, body); return ""; }
  const mbox = mboxScript(env, root); if (!mbox) return `우편함 없음 ${path.join(root ?? "<리포 루트 못 찾음>", ".fable-team", "comm", "mbox.sh")} — 팀장 알림 0`; // 조용한 0 금지
  try { execFileSync("bash", [mbox, "send", master, seat, body], { timeout: 7000 }); return ""; }
  catch (e) { return `팀장 알림 실패(${master}): ${e}`; }
}
const pendingFile = (root: string | null, seat: string): string | null => root ? path.join(root, ".fable-team", "state", "pi-distill-pending", seat.replace(/#\d+$/, "")) : null;
/** 증류 미완 표식 1개 — 이미 있으면 덮어쓰지 않는다(DA 반례 4). 실패는 reason 에 실어 조용한 0 을 만들지 않는다. */
function markPending(root: string | null, seat: string, tokens: number): string {
  const p = pendingFile(root, seat), body = `${new Date().toISOString()} seat=${seat} ctx=${tokens} 증류 미완\n`;
  if (!p) return "상태 파일 경로 없음(리포 루트 못 찾음)";
  try { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, body, { flag: "wx" }); return ""; }
  catch (e) { return (e as any)?.code === "EEXIST" ? "" : `상태 파일 쓰기 실패: ${e}`; }
}
const toolAllowed = (input: GateInput, root: string | null): boolean => input.tool === "read" || input.tool === "ask_user" || (input.tool === "bash" ? bashAllowed(input.command, root) : (input.tool === "write" || input.tool === "edit") && pathAllowed(input.path, root)); // 허용 목록 = 판정 불가 허용 목록 모드(ⓑ)와 ctx ≥ 차단선이 «같은» 함수를 쓴다
/** 한 tool_call 판정 — claude 훅의 warn·block·recv 세 축 + 판정 불가 fail-closed. */
export function judge(input: GateInput): Verdict {
  const env = input.env ?? process.env, root = repoRoot(input.cwd ?? process.env.FT_CWD ?? process.cwd());
  const seat = input.seat ?? seatOf(env), th = thresholds(env, root), state = pendingFile(root, seat), model = String(input.model ?? "");
  if (seatVerdict(env, root, seat, input.seat !== undefined) === false) return { action: "allow", rule: "not-seat", reason: `ft 좌석 아님 — 증류 게이트 무동작(${seat ? `세션 ${seat} 명부 행 없음` : "FT_SEAT·TMUX_PANE 없음"} · 도구 차단 0 · 팀장 알림 0 · 표식 0)`};
  const k = typeof input.tokens === "number" && input.tokens > 0 ? input.tokens : 0, stored = seatIn(state);
  const key = seat || "unknown", own = fs.existsSync(state ?? "/nonexistent") && (stored === seat || !stored), fresh = (input.session?.fresh ?? newConversation(input.session?.reason, input.session?.entries)) && !own; if (k > 0) { seenUsage.set(key, true); misses.delete(key); } // ⓙ 초기 예외 = 새 대화 ∧ 표식 없음 · ⓛ «표식 있음» = 이 좌석(#N) 몫이거나 이름 없는 옛 표식(직전 세대 #N-1 표식은 승계 첫 턴을 막지 않는다) · ⓓⓘ 읽음 = 양수만 · 읽으면 연속 0
  const why = !model ? "모델 불명" : !/claude/i.test(model) ? "" : !th ? `문턱 못 읽음(${K.warn}/${K.block}/${K.recv})` : !seat ? "좌석 이름 못 읽음(TMUX_PANE·FT_SEAT)" : !k ? "ctx usage 없음" : ""; // ⓕ 좌석 불명을 usage 초기 예외(ⓐⓗ)보다 먼저 — 좌석이 없으면 팀장 알림·표식 경로가 전부 불명이다(DA R1)
  const missBlock = (): Verdict => { const bad = notifyTeam(input, env, seat || "unknown", root, why); return { action: "block", rule: "undecidable", reason: `증류 판정 불가 = 막음 — ${why}${bad ? ` · ${bad}` : ""}` }; };
  if (why === "ctx usage 없음") { // r1565 — 세 갈래: 첫 판정 통과(ⓐ) · 연속 N 허용 목록 모드(ⓑ) · 턴 시작 무주입(ⓗ)
    const seen = seenUsage.get(key) === true, n = (misses.get(key) ?? 0) + 1, turn = input.tool === "turn", max = Number(env.FT_DISTILL_FAILOPEN_MAX ?? envFiles(env, root).map((f) => f?.FT_DISTILL_FAILOPEN_MAX).find((v) => v !== undefined) ?? 3) || 3; // r1554 와 같은 키(env > 파일) · 기본 3
    if (turn && !seen && fresh) return { action: "allow", rule: "undecidable-turn", reason: `턴 시작 ${why} — 메시지 주입 0 · 팀장 알림 0 · 연속 횟수 불변` }; // ⓗⓚ
    misses.set(key, n);
    if (turn || (!seen && !fresh)) return missBlock(); // ⓙ 초기 예외 0(새 대화 아님) = 지금 동작 · ⓔ 읽은 뒤의 null 은 «첫 판정» 이 아니다
    if (seen && input.tool === "bash" && isRecv(input.command) && fs.existsSync(state ?? "/nonexistent")) return { action: "block", rule: "recv-gate", reason: `ctx usage 없음(읽은 뒤) · 증류 미완 표식 있음 — 새 일 수락 0: peek 은 허용, 승계(ft-successor-open.sh·mbox handover/ready)부터` }; // ⓔ 표식 있으면 읽은 뒤의 null 도 «새 일» 을 받지 않는다
    if (!seen && n < max) return { action: "allow", rule: n === 1 ? "undecidable-first" : "undecidable-pass", reason: `증류 판정 불가 = 통과 — ${why} · 연속 ${n}/${max}` }; // ⓐ 첫 판정(n=1) · ⓑ N 전까지
    const bad = notifyTeam(input, env, key, root, why), ok = toolAllowed(input, root), tail = bad ? ` · ${bad}` : ""; // ⓔ 읽은 뒤의 null · 연속 N 도달 = «통과 0» 허용 목록 모드(ⓑⓒ)
    return ok ? { action: "allow", rule: "undecidable-allowlist", reason: `증류 판정 불가 ${n}/${max} 연속 = 허용 목록 모드 — 증류 도구라 통과${tail}` } : { action: "block", rule: "undecidable-allowlist", reason: `증류 판정 불가 ${n}/${max} 연속 = 허용 목록 모드 — 도구 «${input.tool}» 는 허용 목록 밖${tail}` };
  }
  if (why) return missBlock(); // ⓕ 모델·문턱·좌석 불명 = 지금처럼 즉시 막음(이번 변경 밖)
  if (!/claude/i.test(model)) return { action: "allow", rule: "model-out-of-scope", reason: `${model} = 증류 게이트 대상 아님(gpt·gemini·deepseek 통과)` };
  const lines = th as Lines;
  const legacy = fs.existsSync(state ?? "/nonexistent") && !stored ? "표식에 좌석 이름 없음(옛 파일) — 자동으로 닫지 않는다" : ""; // 손 0 · 사람이 확인
  if (k < lines.warn && stored && stored !== seat && stored.replace(/#\d+$/, "") === seat.replace(/#\d+$/, "")) { try { fs.rmSync(state ?? "/nonexistent", { force: true }); } catch { /* 다음 턴이 다시 시도 */ } } // 닫는 사건(ⓙ) = 후계 좌석의 첫 판정
  if (input.tool === "bash" && isRecv(input.command) && (k >= lines.recv || fs.existsSync(state ?? "/nonexistent"))) {
    const bad = markPending(root, seat, k);
    return { action: "block", rule: "recv-gate", reason: `ctx ${k} ≥ recv ${lines.recv} — 새 일 수락 0: peek 은 허용, 승계(ft-successor-open.sh·mbox handover/ready)부터${bad ? ` · ${bad}` : ""}${legacy ? ` · ${legacy}` : ""}` };
  }
  const tool = input.tool, allowed = toolAllowed(input, root);
  const bad = k >= lines.block ? markPending(root, seat, k) : ""; // ⓖ: 허용 통과여도 차단선 이상이면 표식을 먼저 남긴다(DA R6)
  if (k >= lines.block && !allowed) {
    return { action: "block", rule: "block-gate", reason: `ctx ${k} ≥ 차단선 ${lines.block} — 도구 «${tool}» 는 허용 목록 밖. 허용 = read·ask_user·인계서/state/design inbox 쓰기·mbox send/relay·handover·ready·close-check·ft-successor-open.sh·git add/commit/push.${bad ? ` · ${bad}` : ""}${legacy ? ` · ${legacy}` : ""}` };
  }
  if (k >= lines.block) return { action: "allow", rule: "block-allowlist", reason: `ctx ${k} ≥ 차단선 ${lines.block} 이지만 증류 도구라 통과${bad ? ` · ${bad}` : ""}` };
  if (k < lines.warn) return { action: "allow", rule: "below-warn", reason: `ctx ${k} < 경고선 ${lines.warn}` };
  return { action: "warn", rule: "warn-line", reason: `⚠️ [ft2 distill-gate] ctx ${k} ≥ 경고선 ${lines.warn} — 새 일 수락 중지 · 지금 증류(스냅샷 → handover → ft-successor-open). ${lines.block} 에서 허용 목록 밖 도구가 막힌다.` };
}
const usageOf = (ctx: any): number | null => { try { const u = ctx?.getContextUsage?.(); return typeof u?.tokens === "number" ? u.tokens : null; } catch { return null; } };
const modelOf = (ctx: any): string => String(ctx?.model?.id ?? ctx?.model?.model ?? ctx?.model?.name ?? "");
const entriesOf = (ctx: any): unknown[] | undefined => { try { const e = ctx?.sessionManager?.getEntries?.(); return Array.isArray(e) ? e : undefined; } catch { return undefined; } };
export default function distillGate(pi: any): void {
  let reason = "", fresh = false; // ⓙ session_start reason · 이번 턴이 «새 대화» 인가(tool_call 때는 assistant 메시지가 이미 있어 턴 시작에 잰다)
  pi.on("session_start", (event: any) => { reason = String(event?.reason ?? ""); });
  pi.on("tool_call", (event: any, ctx: any) => {
    const v = judge({ tool: String(event?.toolName ?? ""), command: event?.input?.command, path: event?.input?.path, tokens: usageOf(ctx), model: modelOf(ctx), cwd: ctx?.cwd, session: { reason, fresh } });
    if (v.action !== "block") { if (/^undecidable/.test(v.rule)) console.error(`ft2 distill-gate: ${v.rule} ${v.reason}`); return undefined; } // ⓐ 판정 불가 통과도 기록 1줄(no_silent_fallback · 채널 = 차단과 같은 stderr)
    console.error(`ft2 distill-gate: ${v.rule} ${v.reason}`); return { block: true, reason: v.reason };
  });
  pi.on("before_agent_start", (_event: any, ctx: any) => {
    fresh = newConversation(reason, entriesOf(ctx)); // ⓗⓙ 턴 시작 = 이 순간에만 «assistant 0» 을 볼 수 있다
    const v = judge({ tool: "turn", tokens: usageOf(ctx), model: modelOf(ctx), cwd: ctx?.cwd, session: { reason, fresh } });
    return v.action === "allow" ? undefined : { message: { customType: "ft2-distill-gate", content: v.reason, display: true } };
  });
}
