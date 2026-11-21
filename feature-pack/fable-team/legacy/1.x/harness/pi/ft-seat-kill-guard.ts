// ft-seat-kill-guard (r2412) — pi 좌석이 bash 로 «넓게 잡히는 pkill·killall» 또는 «광역 kill» 을 돌리려 하면 tool_call 문지기에서 거절하고 안전한 꼴(옵션은 패턴 앞 · pgrep 으로 먼저 세기 · PID 로 kill)을 알려 준다.
//  · 실사건(11-21 20:49:37): `pkill -TERM -f 'run_all.sh' -P 1` — macOS pkill 은 첫 패턴 낱말 뒤 낱말을 옵션으로 읽지 않고 패턴으로 읽는다 → «-P»·«1» 이 패턴이 되고 -f 는 명령줄 전체에 대조 → 명령줄에 1 이 든 사용자 프로세스 82개 + launchd 서비스 7개가 SIGTERM
//  · 거절 = 좌석 있음(FT_SEAT_NAME·FT_SEAT) ∧ bash ∧ 토막 하나라도 K2 꼴 4종(ⓐ 패턴 뒤 옵션 · ⓑ -f 짧은·빈·변수 패턴 · ⓒ 복수 패턴 · ⓓ kill 광역 대상 0·음수)
//  · 통과 = 좌석 미상 · bash 밖(read·write·grep) · pgrep(읽기 전용) · pkill/killall/kill 아닌 낱말 · 옵션이 패턴 앞에 온 정상 꼴 · kill -0 · PID 하나 · 판정 불가 = 통과 + NOTE 1줄(사유별 1회 · 하드 룰 20)
//  · 거절마다 <루트>/.fable-team/state/seat-kill-block.log 1줄(같은 좌석·같은 명령 1회 · 0644 · 하드 룰 19) · 쓰기 실패 = ERROR 1줄 · 거절은 그대로(K3)
//  · 설치 = ~/.pi/agent/extensions 복사 1개(arch h) · env = FT_SEAT_NAME · FT_SEAT · FT_LIVE_ROOT · 시험 = tests/test_seat_kill_guard_r2412.sh · 명령 나누기 = r2379 splitCmd 재사용
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendLoadLine, say } from "./ft-load-line.ts";            // r1537 로드 줄 · r1837 진단 1줄 출력 길
import { seatOf, rootOf } from "./ft-live-write-guard.ts";          // r1672 좌석·루트 판정 재사용(그 파일 손 0)
import { splitCmd, redir } from "./ft-nano-repo-grep-guard.ts";     // r2379 명령 나누기 export 재사용 · 사본 0

export const WHY = '[ft-seat-kill-guard] 넓게 잡히는 종료 명령 금지 — macOS pkill 은 첫 패턴 낱말 뒤 낱말을 옵션으로 읽지 않는다(«-P 1» 이 패턴 «-P»·«1» 이 된다) · 옵션은 패턴 앞: pkill -TERM -P 1 -f \'run_all.sh\' · 먼저 세기: pgrep -P 1 -f \'<글자>\' 로 확인 · 그다음 PID 로: kill <pid> · -f 패턴은 6자 이상';
// K2ⓑ 문턱 — 고른 값 6(카드 한계 4 · «node»·«python» 같은 짧고 흔한 이름을 막으려는 값 · 실측 분포 아님)
const MINP = 6;
const KILLS = /^(pkill|killall|kill)$/;
const SIG = /^-(?:\d+|(?:sig)?(?:hup|int|quit|ill|trap|abrt|bus|fpe|kill|usr1|segv|usr2|pipe|alrm|term|stkflt|chld|cont|stop|tstp|ttin|ttou|urg|xcpu|xfsz|vtalrm|prof|winch|io|pwr|sys))$/i;
const PKV = new Set(["g", "G", "P", "s", "t", "U", "u", "F", "d"]);   // pkill 값 받는 낱자 옵션
const KAV = new Set(["u", "t", "c"]);                                  // killall 값 받는 낱자 옵션
type Seg = { toks: string[]; sep: string };
type Verdict = { block: boolean; bad: string; why: string; target: string };
const NO: Verdict = { block: false, bad: "", why: "", target: "" };

// 앞머리 건너뛰기 — env 대입(A=b) · timeout/gtimeout N · nice [-n N] · command · env · sudo [-옵션 · -u/-g/-p 값] (r2379 headIndex 는 비공개라 여기 따로 둔다 · K1)
export function headIndex(toks: string[]): number {
  for (let k = 0; k < toks.length; ) {
    const t = toks[k];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t)) { k++; continue; }
    if (t === "timeout" || t === "gtimeout") { k += 2; continue; }
    if (t === "nice") { k += toks[k + 1] === "-n" ? 3 : 1; continue; }
    if (t === "command" || t === "env") { k++; continue; }
    if (t === "sudo") {
      k++;
      while ((toks[k] ?? "").startsWith("-")) k += ["-u", "-g", "-p", "-C", "-h", "-r", "-t", "-U"].includes(toks[k]) ? 2 : 1;
      continue;
    }
    return k;
  }
  return -1;
}

// 종료 명령 인자 — 옵션은 첫 패턴 앞까지만(BSD getopt) · 패턴(위치 낱말) · 신호 옵션 1개 · kill 광역 대상(0·음수)
export function parseKill(toks: string[], i0: number, tool: string): { pat: string[]; broad: string; lateOpt: string; full: boolean; bad: string } {
  const pat: string[] = []; let broad = "", lateOpt = "", full = false, sig = false, opt = true, i = i0;
  const V = tool === "killall" ? KAV : PKV;
  const val = (): string => { const v = toks[i] ?? ""; i++; return v; };
  while (i < toks.length) {
    const t = toks[i], r = redir(t); i++;
    if (r === "fd" || r === "attached") continue;                       // 2>&1 · 2>/dev/null = 인자 아님
    if (r === "pure") { i++; continue; }                                // 리다이렉트 대상 = 인자 아님
    if (opt && t === "--") { opt = false; continue; }
    if (opt && SIG.test(t)) { if (!sig) { sig = true; continue; } opt = false; }  // 둘째 -N = 신호가 아니라 대상(kill -9 -1)
    if (opt && t.startsWith("--")) {                                    // 긴 옵션
      const name = t.split("=")[0].slice(2), hasVal = t.includes("=");
      if (name === "full") full = true;
      if (name === "signal") sig = true;
      if (!hasVal && ["pgroup", "parent", "group", "uid", "euid", "terminal", "file", "delimiter", "session"].includes(name)) val();
      continue;
    }
    if (opt && t.startsWith("-") && t.length > 1) {                      // 낱자 옵션 묶음(-f · -P 1 · -P1 · -x)
      for (let j = 1; j < t.length; j++) {
        const c = t[j];
        if (V.has(c)) { if (!t.slice(j + 1)) val(); break; }
        if (c === "f") { full = true; continue; }
        break;                                                          // 그 밖 낱자 = 값 없는 옵션
      }
      continue;
    }
    opt = false;
    if (tool === "kill") { if (t === "0" || /^-\d+$/.test(t)) broad = broad || t; continue; }
    if (/^-[A-Za-z0-9]/.test(t)) { lateOpt = lateOpt || t; continue; }   // K2ⓐ 옵션이 패턴 뒤 = macOS 가 패턴으로 읽는다
    pat.push(t);
  }
  return { pat, broad, lateOpt, full, bad: "" };
}

// 한 명령 판정 — 토막마다 앞머리를 건너뛰고 종료 명령 꼴만 본다(pgrep·echo·grep·ps = 통과)
export function judgeKill(cmd: string): Verdict {
  const { segs, bad } = splitCmd(cmd);
  if (bad) return { ...NO, bad };
  for (const s of segs as Seg[]) {
    const k = headIndex(s.toks);
    if (k < 0) continue;
    const tool = path.basename(s.toks[k] ?? "");
    if (!KILLS.test(tool)) continue;
    const a = parseKill(s.toks, k + 1, tool);
    const line = s.toks.slice(k).join(" ");
    if (a.bad) return { ...NO, bad: a.bad };
    if (tool === "kill") { if (a.broad) return { block: true, bad: "", why: `광역 대상 «${a.broad}»`, target: line }; continue; }
    if (a.lateOpt) return { block: true, bad: "", why: `옵션 «${a.lateOpt}» 이 패턴 뒤`, target: line };
    if (a.pat.length > 1) return { block: true, bad: "", why: `패턴 ${a.pat.length}개`, target: line };
    if (a.full && a.pat.length === 1) {
      const p = a.pat[0];
      if (p.length < MINP) return { block: true, bad: "", why: `짧은·빈 패턴 «${p}»(${p.length}자 < ${MINP}자)`, target: line };
      if (p.includes("$")) return { block: true, bad: "", why: `값을 모르는 패턴 «${p}»`, target: line };
    }
  }
  return NO;
}

// 거절 기록 1줄 — 같은 좌석·같은 명령은 1회만 · 쓰기 실패 = ERROR 1줄(거절은 그대로)
export function logBlock(root: string, seat: string, cmd: string): void {
  const f = path.join(root, ".fable-team", "state", "seat-kill-block.log");
  try {
    const prev = fs.existsSync(f) ? fs.readFileSync(f, "utf-8") : "";
    if (prev.split("\n").some((l) => l.includes(` ${seat} `) && l.trimEnd().endsWith(` ${cmd}`))) return;
    fs.mkdirSync(path.dirname(f), { recursive: true }); fs.appendFileSync(f, `${new Date().toISOString()} ${seat} ${cmd}\n`, { mode: 0o644 });
  } catch (e) { say(`ERROR ft-seat-kill-guard: 감지 로그 실패 ${f} — ${e}`); }
}

export default function (pi: ExtensionAPI) {
  const noted = new Set<string>();
  pi.on("session_start", async () => { appendLoadLine(pi, "r2412", "ft-seat-kill-guard.ts"); });
  pi.on("tool_call", async (event) => {
    const seat = seatOf();
    if (!seat) return;                                                  // K1 좌석 미상 = 통과
    if (String(event.toolName ?? "") !== "bash") return;                // bash 밖(read·write·grep) = 통과
    const cmd = String((event.input as Record<string, unknown> | undefined)?.command ?? "");
    if (!cmd) return;
    let v: Verdict;
    try { v = judgeKill(cmd); } catch (e) { say(`ERROR ft-seat-kill-guard: 판정 실패 — ${e}`); return; }
    if (v.bad) {                                                        // 판정 불가 = 통과 + NOTE 1줄(사유별 1회)
      if (!noted.has(v.bad)) { noted.add(v.bad); say(`NOTE ft-seat-kill-guard: 판정 불가 ${v.bad}`); }
      return;
    }
    if (!v.block) return;
    logBlock(rootOf(), seat, cmd.slice(0, 120));
    return { block: true, reason: `${WHY} · 사유 ${v.why} · 대상 ${v.target}` };
  });
}
