// ft-live-write-guard (r1672) — 나노 좌석(pi)이 «라이브 설치 자리» 에 직접 쓰지 못하게 tool_call 문지기에서 거절한다.
//  · 라이브 자리 = <루트>/.fable-team/LIVE_BIN 첫 줄의 부모 live/ 아래 전부(판 폴더 포함) · <루트>/.fable-team/bin*(bin·bin-<팀>) · <루트>/.fable-team/comm 원장 «직접 쓰기»(mailbox*.jsonl · bodies/ · drops/) · ~/.pi/agent/extensions
//  · 나노 꼴 = FT_SEAT_NAME(없으면 FT_SEAT) 에 팀 나노 접두(예 byz-harness-nano-) · 그 밖 좌석·좌석 미상 = 통과(ⓔ) · 판정 = realpath(심링크·`..`·`~`·$VAR 우회 0)
//  · 거절마다 <루트>/.fable-team/state/live-write-block.log 1줄(시각·좌석·도구·대상 · 같은 좌석·같은 대상 1회 · 일반 파일 · 하드 룰 19) · LIVE_BIN 못 읽음 = 그 칸 없이 판정 + NOTE 1줄(하드 룰 20)
//  · 설치 = ~/.pi/agent/extensions 복사 1개 + pi 재시작(master h) · env = FT_SEAT_NAME · FT_LIVE_ROOT · 시험 = tests/test_nano_live_write_block_r1672.sh
import * as fs from "node:fs";
import * as path from "node:path";
import { execSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendLoadLine, say } from "./ft-load-line.ts"; // r1537 로드 줄 · r1837 진단 1줄 출력 길(TUI = 파일 로그)

export const WHY = "라이브 설치는 master h — 팩 가지에 커밋하고 산출 보고에 «설치 h 필요» 1줄";
const NANO = /(^|[-_/.])nano([-_#./]|$)/, WRITE_CMDS = /^(cp|mv|install|rsync|tee|ln|dd)$/, OPS = /^(;|&&|\|\||\||>|>>)$/;
const note = (m: string) => say(`NOTE ft-live-write-guard: ${m}`), under = (p: string, b: string) => p === b || p.startsWith(b.endsWith(path.sep) ? b : b + path.sep);
export const seatOf = (): string => process.env.FT_SEAT_NAME || process.env.FT_SEAT || "";
// 루트 = git 공용 루트(워크트리에서도 같은 자리) · FT_LIVE_ROOT 가 이긴다(시험 손잡이)
export function rootOf(): string {
  if (process.env.FT_LIVE_ROOT) return path.resolve(process.env.FT_LIVE_ROOT);
  try {
    const d = execSync("git rev-parse --path-format=absolute --git-common-dir", { encoding: "utf-8", timeout: 7000, stdio: ["ignore", "pipe", "ignore"] }).trim();
    if (d) return path.dirname(d);
  } catch { /* git 밖 = cwd */ }
  return process.cwd();
}
// realpath — 「성분별로 풀고 `..` 는 «푼 부모» 에서 올라간다(심링크+.. 합성 우회 차단 · $VAR·~ 확장)
export function realish(p: string): string {
  let s = String(p || "").trim().replace(/^["']|["']$/g, "").replace(/\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/g, (_, k) => process.env[k] ?? "");
  if (!s) return "";
  if (s === "~" || s.startsWith("~/")) s = (process.env.HOME ?? "") + s.slice(1);
  let cur = s.startsWith("/") ? path.sep : process.cwd();
  for (const c of s.split("/")) {
    if (!c || c === ".") continue;
    if (c === "..") { cur = path.dirname(cur); continue; }
    const nx = path.join(cur, c);
    try { cur = fs.realpathSync.native(nx); } catch { cur = nx; }
  }
  return cur;
}
// 라이브 자리 칸 — LIVE_BIN 못 읽음 = note 1줄(그 칸 없이 판정 · 조용한 통과 0)
export function liveRoots(root: string): { roots: string[]; note: string } {
  const roots: string[] = [], ft = path.join(root, ".fable-team"), ptr = path.join(ft, "LIVE_BIN"); let n = "";
  try {
    const line = (fs.readFileSync(ptr, "utf-8").split("\n")[0] ?? "").trim();
    if (line) roots.push(realish(path.dirname(path.dirname(line)))); // 판 폴더의 부모 = live/
    else n = `LIVE_BIN 첫 줄이 비었다(판 폴더 칸 판정 불가) ${ptr}`;
  } catch { n = `LIVE_BIN 못 읽음(판 폴더 칸 판정 불가) ${ptr}`; }
  try { for (const e of fs.readdirSync(ft)) if (/^bin(-|$)/.test(e)) roots.push(realish(path.join(ft, e))); } catch { /* .fable-team 없음 = 이 칸 0 */ }
  if (process.env.HOME) roots.push(realish(path.join(process.env.HOME, ".pi", "agent", "extensions")));
  return { roots, note: n };
}
// comm 은 «직접 쓰기» 만 — mbox.sh send|recv|ready 호출은 명령 글자에 원장 경로가 없어 통과한다(ⓑ)
export function blockedBy(p: string, root: string, roots: string[]): string {
  for (const b of roots) if (b && under(p, b)) return b;
  const d = realish(path.join(root, ".fable-team", "comm")), rel = under(p, d) ? path.relative(d, p).split(path.sep).join("/") : "";
  return /^mailbox[^/]*\.jsonl$/.test(rel) || /^(bodies|drops)(\/|$)/.test(rel) ? d : "";
}
// 한 명령의 인자 = 다음 shell 연산자 앞까지(;·&&·|·리다이렉션 에서 끊는다)
const argsOf = (toks: string[], i: number): string[] => { const a: string[] = [];
  for (let j = i + 1; j < toks.length; j++) { const t = toks[j]; if (OPS.test(t) || t.includes(">") || t.startsWith("&")) break; if (!t.startsWith("-")) a.push(t); }
  return a; };
// bash 쓰기 대상 — cp·mv·install·rsync·tee·ln·dd · `>`/`>>` · `of=` · sed -i (대표 패턴 · 읽기는 대상 0)
export function bashTargets(cmd: string): string[] {
  const out: string[] = [], toks = (cmd.match(/"[^"]*"|'[^']*'|[^\s"']+/g) ?? []).map((t) => t.replace(/^["']|["']$/g, ""));
  for (let i = 0; i < toks.length; i++) {
    const t = toks[i], base = path.basename(t), gt = t.lastIndexOf(">");
    if ((t === ">" || t === ">>") && toks[i + 1]) out.push(toks[i + 1]);              // `> 파일`
    else if (gt >= 0) { const tgt = t.slice(gt + 1); if (tgt && !tgt.startsWith("&")) out.push(tgt); }   // `>파일`·`text>파일`(R1)
    if (t.startsWith("of=") && t.length > 3) out.push(t.slice(3));                     // dd of=파일
    if (!WRITE_CMDS.test(base)) continue;
    const args = argsOf(toks, i);
    if (base === "mv") out.push(args[args.length - 1], args[0]);                       // 원본(사라짐)·대상
    else if (base === "tee" || base === "dd") out.push(...args);
    else if (args.length) out.push(args[args.length - 1]);                             // cp·install·rsync·ln = 대상
  }
  for (let i = 0; i < toks.length; i++) if (path.basename(toks[i]) === "sed") {          // sed -i <script> <파일들>
    const rest = toks.slice(i + 1);
    if (rest.some((a) => /^-[a-zA-Z]*i/.test(a))) out.push(...rest.filter((a) => !a.startsWith("-")).slice(1));
  }
  return out.filter(Boolean);
}
// 감지 1줄 — 같은 좌석·같은 대상은 1회만 · 실패는 ERROR 1줄(확장은 계속)
export function logBlock(root: string, seat: string, tool: string, target: string): void {
  const f = path.join(root, ".fable-team", "state", "live-write-block.log");
  try {
    const prev = fs.existsSync(f) ? fs.readFileSync(f, "utf-8") : "";
    if (prev.split("\n").some((l) => l.includes(` ${seat} `) && l.trimEnd().endsWith(` ${target}`))) return;
    fs.mkdirSync(path.dirname(f), { recursive: true }); fs.appendFileSync(f, `${new Date().toISOString()} ${seat} ${tool} ${target}\n`, { mode: 0o644 });
  } catch (e) { say(`ERROR ft-live-write-guard: 감지 로그 실패 ${f} — ${e}`); }
}

export default function (pi: ExtensionAPI) {
  let noted = false;
  pi.on("session_start", async () => { appendLoadLine(pi, "r1672", "ft-live-write-guard.ts"); });
  pi.on("tool_call", async (event) => {
    const seat = seatOf();
    if (!seat || !NANO.test(seat)) return;                                   // 나노 아님 = 통과(ⓔ)
    const tool = String(event.toolName ?? ""), input = (event.input ?? {}) as Record<string, unknown>;
    const targets = tool === "write" || tool === "edit" ? [String(input.path ?? "")]
      : tool === "bash" ? bashTargets(String(input.command ?? "")) : [];
    if (!targets.length) return;
    const root = rootOf(), lv = liveRoots(root);
    if (lv.note && !noted) { noted = true; note(lv.note + " — 나머지 칸(comm·bin*·확장)으로만 판정"); }
    for (const t of targets) {
      const p = realish(t), hit = p ? blockedBy(p, root, lv.roots) : "";
      if (!hit) continue;
      logBlock(root, seat, tool, p);
      return { block: true, reason: `[ft-live-write-guard] ${WHY} — 라이브 자리 ${hit} · 대상 ${p}` };
    }
  });
}
