// ft-idle-nudge (r1530) — 팀장 pi 좌석이 «골 열림 ∧ 진행 카드 0 ∧ 대기 h 0 ∧ 미읽음 0» 으로 턴을 끝내면, 그 좌석의 agent_settled 에서 턴 1회.
//  · 사건 = pi.on("agent_settled") 하나 · 주기·타이머·크론·send-keys 0 · Escape 중단(event.aborted) = 0.
//  · 지문 = 진행 카드 수 · 대기 h 수 · 남이 이 좌석에 보낸 마지막 쪽지 seq(우편함 to=좌석 + receipts/<좌석>.jsonl · 자기 발신 행 제외 = r1153·r1529 와 같은 칸).
//    같은 지문 1회째 = 턴 1 · 2회째 = 턴 0 + planner 팀장(_master) [긴급] 1통(r1684 ①) · 3회째부터 0 · 지문이 바뀌면 다시 1회째. 상태 = <state>/pi-wake/<좌석키>.idle(JSON).
//  · 판정 입력 = <루트>/.fable-team/bin shim(ft-goal-table.sh teams · ft-card-flow.sh --team · ft-hil.sh --pending --each --team <팀>(r1538: 그 팀 h 만)) + mbox.sh peek · 호출마다 7초.
//    읽기 실패(rc≠0 · 꼴 불일치) = stderr «판정 불가» 1줄 · 턴 0 · [긴급] 0 · 지문 무변화(no_silent_fallback).
//  · 활성 = ft-mbox-wake.ts piMasterFile(seats*.json _master ∧ 같은 파일 agent=='pi' · _desk·나노·claude 팀장 = 0) · 팀 = 그 파일의 <팀>(seats.json = v65).
//  · 설치 = ~/.pi/agent/extensions/ 에 ft-mbox-wake.ts(r1530 판) 와 나란히 복사 · /reload · 시험 = tests/test_pi_idle_nudge_r1530.sh
import * as fs from "node:fs";
import * as path from "node:path";
import { execFile, execSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { piMasterFile } from "./ft-mbox-wake.ts";
import { appendLoadLine } from "./ft-load-line.ts"; // r1537 — 세션 기록 «로드 <카드> <판>» 1줄(턴 0)

type Got = { goal: boolean; prog: number; h: number; unread: number; last: number };
type Run = { rc: number; out: string };
const keyOf = (s: string) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
const log = (m: string) => console.error(`ft-idle-nudge: ${m}`);
const sh = (cmd: string): string => { try { return execSync(cmd, { encoding: "utf-8", timeout: 7000, stdio: ["ignore", "pipe", "ignore"] }).trim(); } catch { return ""; } };
const gitRoot = (): string => { const d = sh("git rev-parse --path-format=absolute --git-common-dir"); return d ? path.dirname(d) : ""; };
export const NUDGE = "다음 발주 또는 막힌 이유 1줄";

// 팀 = 팀장 판정 파일 이름의 <팀> · seats.json 은 v65 (카드 §구현 범위 ③)
export const teamOf = (file: string): string => (file === "seats.json" ? "v65" : file.replace(/^seats-/, "").replace(/\.json$/, ""));
// 골 열림 = ft-goal-table.sh teams 의 마커 블록 안에 «| <팀> |» 행 · 마커 없음 = 꼴 불일치(null)
export function goalOpen(out: string, team: string): boolean | null {
  const lines = out.split("\n"), a = lines.findIndex((l) => l.startsWith("★팀별 완성 진행 (")), b = lines.indexOf("★/팀별 완성 진행★");
  if (a < 0 || b < a) return null;
  return lines.slice(a + 1, b).some((l) => l.split("|").map((c) => c.trim())[1] === team);
}
// 진행 카드 = ft-card-flow.sh 기본 출력 «카드 대기 N · 진행 N(좌석 M)» 의 진행 N · 꼴 불일치 = null
export const progOf = (out: string): number | null => { const m = /^카드 대기 \d+ · 진행 (\d+)\(좌석 \d+\)/m.exec(out); return m ? Number(m[1]) : null; };
// 대기 h = ft-hil.sh --pending --each [--team <팀>] 의 `h<N> <분>` 줄 수 · 다른 꼴 줄 = null
export const hilOf = (out: string): number | null => { const ls = out.split("\n").filter((l) => l.trim()); return ls.every((l) => /^h\d+ \d+$/.test(l.trim())) ? ls.length : null; };
// 미읽음 = mbox.sh peek 의 pending=N(doorbell _db_pending 과 같은 칸)
export const unreadOf = (out: string): number | null => { const m = /^pending=(\d+)/m.exec(out); return m ? Number(m[1]) : null; };

export default function (pi: ExtensionAPI) {
  const root = process.env.FT_MBOX_ROOT || gitRoot() || process.cwd();
  const seat = process.env.FT_SEAT || sh('tmux display-message -p "#S"');
  const mbox = process.env.FT_MBOX_FILE ?? path.join(root, ".fable-team", "comm", "mailbox.jsonl");
  const mboxDir = path.dirname(mbox); // ft-mbox-wake 와 같은 «지정 우편함» 결속(FT_MBOX_FILE)
  const localSh = path.join(mboxDir, "mbox.sh"), borrowed = !fs.existsSync(localSh);
  const mboxSh = borrowed ? path.join(root, ".fable-team", "comm", "mbox.sh") : localSh;
  const mboxEnv = { FT_MBOX_DIR: mboxDir };
  const bin = (n: string) => path.join(root, ".fable-team", "bin", n);
  const state = process.env.FT_MBOX_STATE_DIR ?? path.join(root, ".fable-team", "state");
  const idleFile = path.join(state, "pi-wake", `${keyOf(seat)}.idle`);
  const receipts = path.join(mboxDir, "receipts", `${seat}.jsonl`);

  const run = (file: string, args: string[], env: Record<string, string> = {}): Promise<Run> => new Promise((res) => {
    try {
      execFile("bash", [file, ...args], { cwd: root, encoding: "utf-8", timeout: 7000, env: { ...process.env, ...env } },
        (e, out) => res({ rc: e ? (typeof (e as { code?: unknown }).code === "number" ? Number((e as { code: number }).code) : 124) : 0, out: String(out ?? "") }));
    } catch (e) { res({ rc: 127, out: String(e) }); }
  });
  // 남이 이 좌석에 보낸 마지막 쪽지 seq — 우편함 미읽음 행 + 받은 영수(receipts) · 자기 발신·표시(mark) 행 제외 · 읽기 실패 = null
  const others = (r: { from?: unknown }) => String(r.from ?? "") !== seat;
  function lastSeq(): number | null {
    let max = 0;
    const scan = (text: string, needTo: boolean) => { for (const line of text.split("\n")) { if (!line.trim()) continue; let r;
      try { r = JSON.parse(line); } catch { continue; } // 깨진 줄 1개가 판정을 막지 않는다(ft-mbox-wake parseRows 와 같은 꼴)
      if (typeof r?.seq !== "number" || "mark" in r || (needTo && r.to !== seat) || !others(r)) continue;
      max = Math.max(max, r.seq); } };
    try { scan(fs.readFileSync(mbox, "utf-8"), true); } catch (e) { log(`우편함 ${mbox} — ${e}`); return null; }
    try { scan(fs.readFileSync(receipts, "utf-8"), false); } catch (e) { if ((e as NodeJS.ErrnoException)?.code !== "ENOENT") { log(`영수 ${receipts} — ${e}`); return null; } } // 영수 없음 = 받은 쪽지 0
    return max;
  }
  // r1684 ② — 골 원장이 없는 루트(aifp 등) = 이 루트 design/TEAMS.md 에 planner 행이 없음. 그때 골 칸 = 열림 + 세션당 INFO 1줄.
  //   TEAMS.md 를 못 읽거나 planner 행이 있으면 지금처럼 null(=«판정 불가») — «없음» 과 «못 읽음» 을 가른다(하드 룰 20).
  let ledgerlessInfo = false;
  function ledgerlessRoot(): boolean {
    let md: string;
    try { md = fs.readFileSync(path.join(root, "design", "TEAMS.md"), "utf-8"); } catch { return false; }
    if (md.split("\n").some((l) => /^\|\s*planner\s*\|/.test(l))) return false;
    if (!ledgerlessInfo) { ledgerlessInfo = true; log("INFO 골 원장 없는 루트 — 골 칸 열림으로 봄 (design/TEAMS.md 에 planner 행 없음)"); }
    return true;
  }
  async function read(team: string): Promise<Got | string> {
    const [g, c, h, p] = await Promise.all([
      run(bin("ft-goal-table.sh"), ["teams"]), run(bin("ft-card-flow.sh"), ["--team", team, "--root", root]),
      run(bin("ft-hil.sh"), ["--pending", "--each", "--team", team]), run(mboxSh, ["peek", seat], mboxEnv)]);
    const goal = g.rc === 0 ? goalOpen(g.out, team) : (ledgerlessRoot() ? true : null), prog = c.rc === 0 ? progOf(c.out) : null;
    const hil = h.rc === 0 ? hilOf(h.out) : null, unread = p.rc === 0 ? unreadOf(p.out) : null;
    if (goal === null) return `골 표 rc=${g.rc}`;
    if (prog === null) return `카드판 rc=${c.rc}`;
    if (hil === null) return `대기 h rc=${h.rc}`;
    if (unread === null) return `미읽음 rc=${p.rc}`;
    const last = lastSeq();
    if (last === null) return "우편함·영수 읽기 실패";
    return { goal, prog, h: hil, unread, last };
  }
  function readIdle(): { fp: string; n: number } | null {
    try { const j = JSON.parse(fs.readFileSync(idleFile, "utf-8")); return typeof j?.fp === "string" && Number.isInteger(j?.n) ? j : null; }
    catch (e) { return (e as NodeJS.ErrnoException)?.code === "ENOENT" ? { fp: "", n: 0 } : null; }
  }
  const writeIdle = (fp: string, n: number) => { try { fs.mkdirSync(path.dirname(idleFile), { recursive: true }); fs.writeFileSync(idleFile, JSON.stringify({ fp, n }) + "\n"); } catch (e) { log(`지문 기록 실패 ${idleFile} — ${e}`); } };
  // r1684 ① — [긴급] 은 planner 팀장(_master) 앞으로. desk 는 planner 밖 수신자를 REJECT 하는 경로 규칙이 있다(feature#69 실사건 = rc3).
  const plannerMaster = (): string => { try { return String(JSON.parse(fs.readFileSync(path.join(root, ".fable-team", "seats-planner.json"), "utf-8"))._master ?? ""); } catch { return ""; } };

  async function urgent() { // planner 팀장 앞 [긴급] 1통 — 본문에 백틱·$( 0
    const to = plannerMaster();
    if (!to) return log(`[긴급] 못 보냄 — seats-planner.json _master 없음 (${seat})`);
    const r = await run(mboxSh, ["send", to, seat, `[긴급] ${seat} 쉼 지문 반복 · 진행 0 · h 0 · 다음 발주 없음 · 막힌 이유 확인 필요`], mboxEnv);
    if (r.rc !== 0) log(`[긴급] 발신 실패 rc=${r.rc} → ${to}`);
  }

  pi.on("session_start", async () => { ledgerlessInfo = false; appendLoadLine(pi, "r1530", "ft-idle-nudge.ts"); }); // r1537 — 실림 1줄 · r1684 INFO 는 세션당 1줄

  pi.on("agent_settled", async (event: { aborted?: boolean }) => {
    if (event?.aborted) return; // Escape 중단 = 0
    const file = seat ? piMasterFile(root, seat) : "";
    if (!file) return; // 팀장 pi 좌석만(나노·_desk·claude/codex 팀장 = 0)
    const team = teamOf(file), got = await read(team);
    if (typeof got === "string") return log(`판정 불가 — ${got} · ${seat} 턴 0`);
    if (!got.goal || got.prog > 0 || got.h > 0 || got.unread > 0) return; // 일이 남았다 = 턴 0 · 지문 무변화
    const fp = `${got.prog}|${got.h}|${got.last}`, prev = readIdle();
    if (prev === null) return log(`판정 불가 — 지문 파일 꼴 불일치 ${idleFile} · ${seat} 턴 0`);
    const n = prev.fp === fp ? prev.n + 1 : 1;
    if (n === 1) {
      const content = `[idle-nudge] ${team} 골 열림 · 진행 카드 0 · 대기 h 0 · 미읽음 0 — ${NUDGE}: 다음 발주를 1건 내거나, 막힌 이유를 1줄로 쓴다(오빠 결정이면 desk 앞 mbox 1통).`;
      try { pi.sendMessage({ customType: "ft-idle-nudge", content, display: true }, { triggerTurn: true, deliverAs: "followUp" }); }
      catch (e) { return log(`sendMessage 실패 — ${e}`); } // 실패 = 지문 무변화(다음 settled 재시도)
    } else if (n === 2) await urgent();
    if (n <= 3) writeIdle(fp, n); // 3회째에서 멈춘다 — 그 뒤 settled 는 파일도 안 바꾼다
  });
}
