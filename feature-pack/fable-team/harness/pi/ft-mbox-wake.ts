// ft-mbox-wake (r1477) — planner 대면 pi 좌석을 «쪽지 도착 = 턴 1회» 로 깨운다.
//  · 주기 타이머 0 · 입력 주입 0 · 예산은 r1476 `mbox.sh budget reserve` CLI 로만 차감.
//  · 활성 = FT_SEAT(없으면 tmux 세션명) == <루트>/.fable-team/seats-planner.json `_master` 정확 일치.
//  · 설치 = `~/.pi/agent/extensions/ft-mbox-wake.ts` 로 복사 1개(자동 발견 · settings 등록 0 · pi 재시작 1회).
//  · env: FT_SEAT · FT_MBOX_ROOT · FT_MBOX_FILE · FT_MBOX_STATE_DIR · FT_MBOX_WAKE_DEBOUNCE_MS
//  · 시험 = harness/tests/test_pi_mbox_wake_r1477.sh (T1~T11 · 가짜 pi 객체 · 실 우편함 0)
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync, execSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
type Row = { seq: number; to: string; body: string };
const QUIET = ["[정리]", "[회신]", "[완료 보고]"]; // r1476 종류 표와 같은 값 — 큐만
const LOUD = ["[긴급]", "[인계]", "[레디]"]; // 예산 밖 즉시

export const headOf = (body: string): string => [...QUIET, ...LOUD].find((h) => body.trimStart().startsWith(h)) ?? "";

export function parseRows(text: string): Row[] {
  const rows: Row[] = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    try {
      const r = JSON.parse(line);
      if (typeof r?.seq === "number" && typeof r?.to === "string") rows.push({ seq: r.seq, to: r.to, body: String(r.body ?? "") });
    } catch { continue; } // 깨진 줄 1개가 우편함 전체를 막지 않는다
  }
  return rows;
}

export const quietOnly = (rows: Row[]) => rows.length > 0 && rows.every((r) => QUIET.includes(headOf(r.body)));
export const loud = (rows: Row[]) => rows.some((r) => LOUD.includes(headOf(r.body)));

const keyOf = (s: string) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
const log = (m: string) => console.error(`ft-mbox-wake: ${m}`);
const fail = (m: string) => console.error(`ERROR ft-mbox-wake: ${m}`);

function seatName(): string {
  if (process.env.FT_SEAT) return process.env.FT_SEAT;
  try { return execSync('tmux display-message -p "#S"', { encoding: "utf-8", timeout: 7000 }).trim(); } catch { return ""; }
}

export default function (pi: ExtensionAPI) {
  const root = process.env.FT_MBOX_ROOT ?? process.cwd();
  const seat = seatName();
  const comm = path.join(root, ".fable-team", "comm");
  const mbox = process.env.FT_MBOX_FILE ?? path.join(comm, "mailbox.jsonl");
  const mboxSh = path.join(comm, "mbox.sh");
  const state = process.env.FT_MBOX_STATE_DIR ?? path.join(root, ".fable-team", "state");
  const wakeDir = path.join(state, "pi-wake");
  const seqFile = path.join(wakeDir, `${keyOf(seat)}.seq`);
  const nudge = path.join(wakeDir, `${keyOf(seat)}.nudge`);
  const debounce = Number(process.env.FT_MBOX_WAKE_DEBOUNCE_MS ?? 300);
  let timer: ReturnType<typeof setTimeout> | null = null;

  let master = "";
  try { master = String(JSON.parse(fs.readFileSync(path.join(root, ".fable-team", "seats-planner.json"), "utf-8"))._master ?? ""); } catch { master = ""; }
  if (!seat || master !== seat) return log(`inactive seat=${seat || "?"} master=${master || "?"}`); // 다른 pi 좌석 자동 활성화 0

  const mine = (): Row[] => { try { return parseRows(fs.readFileSync(mbox, "utf-8")).filter((r) => r.to === seat); } catch (e) { fail(`우편함 읽기 실패 ${mbox} — ${e}`); return []; } };
  const readSeq = (): number => { try { const n = Number(fs.readFileSync(seqFile, "utf-8").trim()); return Number.isFinite(n) ? n : -1; } catch { return -1; } };
  const writeSeq = (n: number | null) => {
    try {
      if (n === null) fs.rmSync(seqFile, { force: true });
      else fs.writeFileSync(seqFile, `${n}\n`);
    } catch { /* 폴더 없음 = 다음 회수에서 다시 쓴다 */ }
  };
  const reserve = () => spawnSync("bash", [mboxSh, "budget", "reserve", seat, "pi"], { encoding: "utf-8", timeout: 7000 }).status ?? 1;

  // r1476 doorbell_record_held 와 같은 꼴 — 닫는 사건은 sweep(예산 창이 바뀐 뒤 nudge)이다.
  function recordHeld(seq: number) {
    const now = Math.floor(Number(process.env.FT_MBOX_NOW ?? Date.now() / 1000));
    const f = path.join(state, "doorbell-held", keyOf(seat));
    try {
      fs.mkdirSync(path.dirname(f), { recursive: true });
      if (!fs.existsSync(f)) fs.writeFileSync(f, `held ts=${now} reason=budget window=${Math.floor(now / 3600)} seat=${seat}\n`);
      fs.appendFileSync(f, `seq=${seq}\n`);
    } catch (e) { fail(`held 기록 실패 ${f} — ${e}`); }
  }

  function wakeNow(seq: number, viaNudge: boolean) {
    const content = `[발주 #${seq}] bash ${mboxSh} recv ${seat} — 실행하고 그 안의 지시를 즉시 착수하라`;
    try { pi.sendMessage({ customType: "ft-mbox", content, display: true }, { triggerTurn: true, deliverAs: "followUp" }); } catch (e) { return fail(`sendMessage 실패 — ${e}`); }
    writeSeq(seq);
    if (viaNudge) fs.rmSync(nudge, { force: true }); // nudge 삭제 = 깨운 뒤
  }

  function check(force: boolean) {
    const rows = mine();
    if (rows.length === 0 || quietOnly(rows)) return; // 보고 전용 머리만 = 큐만 · 예산 0
    const seq = Math.max(...rows.map((r) => r.seq));
    const viaNudge = fs.existsSync(nudge); // r1476 sweep 이 이미 예약했다 — 재예약 0(이중 차감 0)
    if (!force && !viaNudge && readSeq() >= seq) return; // 턴 진행 중 중복 억제
    if (!viaNudge && !loud(rows)) {
      const rc = reserve();
      if (rc !== 0) {
        recordHeld(seq);
        if (rc !== 3) fail(`예산 CLI 실패 rc=${rc} — 턴 0(${seat} #${seq})`);
        return;
      }
    }
    wakeNow(seq, viaNudge);
  }
  const run = () => { try { check(false); } catch (e) { fail(`감시 처리 실패 — ${e}`); } };
  const schedule = () => {
    if (timer) return;
    timer = setTimeout(() => { timer = null; run(); }, debounce);
  };

  pi.on("session_start", async () => {
    if (!fs.existsSync(mbox)) return fail(`우편함 없음 ${mbox} — 확장 비활성(폴링 폴백 0)`);
    try { fs.mkdirSync(wakeDir, { recursive: true }); } catch { /* 이미 있음 */ }
    try {
      // ★부모 폴더 감시★ — os.replace 로 inode 가 바뀌어도 폴더 감시는 유지된다(파일 직접 watch 0).
      fs.watch(comm, (_e, fn) => { if (!fn || fn === path.basename(mbox)) schedule(); });
      fs.watch(wakeDir, (_e, fn) => { if (fn === path.basename(nudge)) schedule(); });
    } catch (e) { return fail(`watch 실패 ${comm} / ${wakeDir} — ${e}`); }
    check(true); // 시작 회수 = 우편함에 «남아 있는» to=내 좌석 행(소비 ACK 기준 · seq 파일 무관)
  });

  pi.on("agent_end", async () => { writeSeq(null); run(); }); // 표지 해제 + 우편함 재확인 1회(소비 안 됐으면 다시 깨운다)
}
