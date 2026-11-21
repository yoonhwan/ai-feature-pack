// ft-seat-pkill-guard (r2412) — pi 좌석이 bash 로 «넓게 잡히는 pkill·killall·kill» 을 돌리려 하면 tool_call 문지기에서 거절하고 안전한 꼴(옵션은 패턴 앞 · pgrep -fl 로 먼저 세기 · PID 로 kill)을 알려 준다.
//  · 실사건(11-21 20:49:37): `pkill -TERM -f 'run_all.sh' -P 1` — macOS pkill 은 첫 패턴 낱말 뒤 낱말을 옵션으로 읽지 않고 패턴으로 읽는다 → «-P»·«1» 이 패턴이 되고 -f 는 명령줄 전체에 대조 → 명령줄에 1 이 든 사용자 프로세스 82개 + launchd 서비스 7개가 SIGTERM
//  · K1 = env FT_SEAT_NAME 있는 pi 좌석 전부(나노·tester·팀장·arch·desk)의 bash · r2379 splitCmd 로 나눈 토막마다 · 앞머리(env 대입 · timeout N · nice · command · sudo) 건너뛴 첫 낱말 basename 이 pkill·killall·kill 일 때만 · FT_SEAT_NAME 없음 = 판정 0 · pgrep = 통과
//  · K2 = ⓐ 옵션이 첫 패턴 뒤 · ⓑ pkill 패턴 2개 이상 · ⓒ pkill -f 인데 정규식 기호를 뺀 글자 6자 미만·빈 따옴표·변수 하나 · ⓓ kill 대상에 -1·0 → {block:true, reason}
//  · K3 = reason 1줄(갈래·사유 + 안내 3구) · 거절마다 <루트>/.fable-team/state/seat-kill-block.log 1줄(시각 · 좌석 · 갈래 · 명령 앞 200자 · 0644) · 기록 실패 = ERROR 1줄 · 거절은 그대로
//  · K4 = 통과 그대로(옵션 앞 + 패턴 1개 + 6자 이상 pkill · kill 숫자 PID · kill -0 <pid> · 따옴표 안 글자 · 못 나눔 = 통과 + 기록 1줄 «판정 불가»)
//  · 설치 = ~/.pi/agent/extensions 복사 1개(arch h) · env = FT_SEAT_NAME · FT_LIVE_ROOT · 시험 = tests/test_seat_pkill_guard_r2412.sh
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendLoadLine, say } from "./ft-load-line.ts";            // r1537 로드 줄 · r1837 진단 1줄 출력 길
import { rootOf } from "./ft-live-write-guard.ts";                  // r1672 루트 판정 재사용(그 파일 손 0)
import { splitCmd, redir } from "./ft-nano-repo-grep-guard.ts";     // r2379 명령 나누기 export 재사용 · 사본 0

const KILLS = /^(pkill|killall|kill)$/;
const VAL = new Set(["F", "G", "P", "U", "d", "g", "s", "t", "u", "c", "j", "M", "N"]);   // 값을 받는 옵션(띄어 쓴 다음 낱말 = 값)
const SIG = /^-(?:\d+|(?:sig)?(?:hup|int|quit|ill|trap|abrt|bus|fpe|kill|usr1|segv|usr2|pipe|alrm|term|stkflt|chld|cont|stop|tstp|ttin|ttou|urg|xcpu|xfsz|vtalrm|prof|winch|io|pwr|sys))$/i;
const REGEXCH = /[.*^$[\]()|?+\\]/g;                                // K2ⓒ 정규식 기호
const VARONLY = /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$/;                 // K2ⓒ 패턴 낱말 전체가 변수 하나
const MINP = 6;                                                     // K2ⓒ 길이 문턱(카드 고른 값)
const LOGNAME = "seat-kill-block.log";
type Seg = { toks: string[]; sep: string };
type Verdict = { block: boolean; bad: string; kind: string; why: string; target: string };
const NO: Verdict = { block: false, bad: "", kind: "", why: "", target: "" };

// reason 1줄 — 갈래(ⓐ~ⓓ·판정 불가)와 사유 + 안내 3구(K3)
export const whyOf = (kind: string, why: string): string =>
  `[ft-seat-pkill-guard] 넓게 잡히는 kill 금지(${kind} ${why}) — 옵션은 패턴 앞에(pkill -TERM -P <부모> -f '<긴 패턴>') · 먼저 pgrep -fl 로 대상 수 확인 · 가능하면 PID 로 kill`;

// 앞머리 건너뛰기 — env 대입(A=b) · timeout N · nice · command · sudo (경로 앞머리는 basename 으로 뗀다 · K1)
export function headIndex(toks: string[]): number {
  for (let k = 0; k < toks.length; ) {
    const t = toks[k];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t)) { k++; continue; }
    if (t === "timeout") { k += 2; continue; }
    if (t === "nice" || t === "command" || t === "sudo") { k++; continue; }
    return k;
  }
  return -1;
}

// 인자 — 옵션은 어디에나 올 수 있다고 읽되 패턴 뒤에 온 «-» 낱말은 late 로 표시(BSD 는 그 자리를 패턴으로 읽는다 · K2ⓐ)
//   값 받는 옵션(-P 1 · -u root)의 값은 패턴이 아니다 · 신호 꼴(-TERM·-15)은 옵션 · -- 뒤는 전부 대상(kill -9 -- -1)
export function parseArgs(toks: string[], i0: number): { pat: string[]; late: string; full: boolean } {
  const pat: string[] = []; let late = "", full = false, sig = false, opt = true, i = i0;
  while (i < toks.length) {
    const t = toks[i], r = redir(t); i++;
    if (r === "fd" || r === "attached") continue;                     // 2>&1 · 2>/dev/null = 인자 아님
    if (r === "pure") { i++; continue; }                              // 리다이렉트 대상 = 인자 아님
    if (opt && t === "--") { opt = false; continue; }
    const isOpt = opt && t.startsWith("-") && t.length > 1;
    if (isOpt && SIG.test(t) && !sig) { if (pat.length) late = late || t; sig = true; continue; }
    if (isOpt && !SIG.test(t)) {                                      // 낱자 옵션 묶음(-f · -P 1 · -P1 · -x)
      if (pat.length) late = late || t;
      for (let j = 1; j < t.length; j++) {
        const c = t[j];
        if (VAL.has(c)) { if (!t.slice(j + 1)) i++; break; }           // 값은 띄어 쓴 다음 낱말
        if (c === "f") full = true;
        break;
      }
      continue;
    }
    pat.push(t);                                                      // 패턴(신호 꼴 둘째 낱말 = 대상)
  }
  return { pat, late, full };
}

// 한 명령 판정 — 토막마다 앞머리를 건너뛰고 종료 명령 꼴만 본다(pgrep·echo·grep·ps = 통과 · K4)
export function judgeKill(cmd: string): Verdict {
  const { segs, bad } = splitCmd(cmd);
  if (bad) return { ...NO, bad };                                     // K4 못 나눔 = 통과 + 기록 «판정 불가»
  for (const s of segs as Seg[]) {
    const k = headIndex(s.toks);
    if (k < 0) continue;
    const tool = path.basename(s.toks[k] ?? "");
    if (!KILLS.test(tool)) continue;                                  // 따옴표 안 글자(echo·grep)·pgrep = 통과
    const line = s.toks.slice(k).join(" ");
    const a = parseArgs(s.toks, k + 1);
    if (tool === "kill") {                                            // K2ⓓ
      const b = s.toks.slice(k + 1).find((v) => v === "-1" || v === "0");
      if (b) return { block: true, bad: "", kind: "ⓓ", why: `대상 «${b}»`, target: line };
      continue;
    }
    if (a.late) return { block: true, bad: "", kind: "ⓐ", why: `옵션 «${a.late}» 이 패턴 뒤`, target: line };   // K2ⓐ
    if (tool === "pkill" && a.pat.length > 1) return { block: true, bad: "", kind: "ⓑ", why: `패턴 ${a.pat.length}개`, target: line };
    if (tool === "pkill" && a.full && a.pat.length === 1) {           // K2ⓒ
      const p = a.pat[0], plain = p.replace(REGEXCH, "");
      if (p === "") return { block: true, bad: "", kind: "ⓒ", why: "빈 따옴표 패턴", target: line };
      if (VARONLY.test(p)) return { block: true, bad: "", kind: "ⓒ", why: `변수 하나 «${p}»`, target: line };
      if (plain.length < MINP) return { block: true, bad: "", kind: "ⓒ", why: `«${p}» 정규식 기호 뺀 글자 ${plain.length}자`, target: line };
    }
  }
  return NO;
}

// 기록 1줄 — 시각 · 좌석 · 갈래 · 명령 앞 200자 · 0644 · 같은 좌석·같은 명령 1회 · 쓰기 실패 = ERROR 1줄(거절은 그대로)
export function logBlock(root: string, seat: string, kind: string, cmd: string): void {
  const f = path.join(root, ".fable-team", "state", LOGNAME), line = `${new Date().toISOString()} ${seat} ${kind} ${cmd}`;
  try {
    const prev = fs.existsSync(f) ? fs.readFileSync(f, "utf-8") : "";
    const key = ` ${seat} ${kind} ${cmd}`;
    if (prev.split("\n").some((l) => l.endsWith(key))) return;
    fs.mkdirSync(path.dirname(f), { recursive: true }); fs.appendFileSync(f, `${line}\n`, { mode: 0o644 });
  } catch (e) { say(`ERROR ft-seat-pkill-guard: 감지 로그 실패 ${f} — ${e}`); }
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async () => { appendLoadLine(pi, "r2412", "ft-seat-pkill-guard.ts"); });
  pi.on("tool_call", async (event) => {
    const seat = process.env.FT_SEAT_NAME ?? "";                      // K1 좌석 경계
    if (!seat) return;
    if (String(event.toolName ?? "") !== "bash") return;
    const cmd = String((event.input as Record<string, unknown> | undefined)?.command ?? "");
    if (!cmd) return;
    let v: Verdict;
    try { v = judgeKill(cmd); } catch (e) { say(`ERROR ft-seat-pkill-guard: 판정 실패 — ${e}`); return; }
    const root = rootOf();
    if (v.bad) { logBlock(root, seat, "판정 불가", `${v.bad} :: ${cmd.slice(0, 160)}`); return; }   // K4 조용한 통과 아님
    if (!v.block) return;
    logBlock(root, seat, v.kind, cmd.slice(0, 200));
    return { block: true, reason: whyOf(v.kind, v.why) };
  });
}
