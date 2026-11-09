// ft-mbox-wake (r1477) — planner 대면 pi 좌석을 «쪽지 도착 = 턴 1회» 로 깨운다. 주기 타이머 0 · 입력 주입 0 · 예산은 r1476 `mbox.sh budget reserve` CLI 로만 차감.
//  · 활성 = FT_SEAT(없으면 tmux 세션명) == <루트>/.fable-team/seats-planner.json `_master` «매 이벤트 재확인» · 루트 = FT_MBOX_ROOT ?? git 공용 루트 ?? cwd.
//  · 설치 = `~/.pi/agent/extensions/ft-mbox-wake.ts` 복사 1개(pi 재시작 1회) · env: FT_MBOX_FILE(다른 데이터 루트) · FT_MBOX_STATE_DIR · FT_MBOX_WAKE_DEBOUNCE_MS · 시험 = harness/tests/test_pi_mbox_wake_r1477.sh
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync, execSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
type Row = { seq: number; to: string; body: string; from: string };
const QUIET = ["[정리]", "[회신]", "[완료 보고]"]; // r1476 종류 표와 같은 값 — 큐만
const LOUD = ["[긴급]", "[인계]", "[레디]"]; // 예산 밖 즉시

export const headOf = (body: string): string => [...QUIET, ...LOUD].find((h) => body.trimStart().startsWith(h)) ?? "";

export function parseRows(text: string): Row[] {
  const rows: Row[] = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    try {
      const r = JSON.parse(line);
      if (typeof r?.seq === "number" && typeof r?.to === "string") rows.push({ seq: r.seq, to: r.to, body: String(r.body ?? ""), from: String(r.from ?? "") });
    } catch { continue; } // 깨진 줄 1개가 우편함 전체를 막지 않는다
  }
  return rows;
}

export const quietOnly = (rows: Row[]) => rows.length > 0 && rows.every((r) => QUIET.includes(headOf(r.body)));
export const loud = (rows: Row[]) => rows.some((r) => LOUD.includes(headOf(r.body)));
// mbox_wakegate.sh:12~18 «사람 발신» 경계 — planner 표식(slack-*·*-oppa·oppa) + 좌석 _master. 미등록 좌석은 사람이 아니다.
export const humanSender = (from: string, master: string) => from === master || from === "oppa" || from.startsWith("slack-") || from.endsWith("-oppa");

const keyOf = (s: string) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
const log = (m: string) => console.error(`ft-mbox-wake: ${m}`);
const fail = (m: string) => console.error(`ERROR ft-mbox-wake: ${m}`);

const sh = (cmd: string): string => { try { return execSync(cmd, { encoding: "utf-8", timeout: 7000, stdio: ["ignore", "pipe", "ignore"] }).trim(); } catch { return ""; } };
const seatName = (): string => process.env.FT_SEAT || sh('tmux display-message -p "#S"');
// ★root = «git 공용 루트»★ — pi pane 의 cwd 는 워크트리일 수 있다(실측 11-09 18:20 planner pi#245). 다른 ft 도구와 같은 식.
const gitRoot = (): string => { const d = sh("git rev-parse --path-format=absolute --git-common-dir"); return d ? path.dirname(d) : ""; };

export default function (pi: ExtensionAPI) {
  const root = process.env.FT_MBOX_ROOT || gitRoot() || process.cwd();
  const seat = seatName();
  const mbox = process.env.FT_MBOX_FILE ?? path.join(root, ".fable-team", "comm", "mailbox.jsonl");
  const mboxDir = path.dirname(mbox); // ★입력·감시·recv 는 «같은 지정 우편함» 에 결속한다(FT_MBOX_FILE 지원)
  const localSh = path.join(mboxDir, "mbox.sh");
  const borrowed = !fs.existsSync(localSh), mboxSh = borrowed ? path.join(root, ".fable-team", "comm", "mbox.sh") : localSh; // CLI 없으면 루트 것을 빌린다
  const state = process.env.FT_MBOX_STATE_DIR ?? path.join(root, ".fable-team", "state");
  const wakeDir = path.join(state, "pi-wake");
  const seqFile = path.join(wakeDir, `${keyOf(seat)}.seq`);
  const nudge = path.join(wakeDir, `${keyOf(seat)}.nudge`);
  const debounce = Number(process.env.FT_MBOX_WAKE_DEBOUNCE_MS ?? 300);
  let timer: ReturnType<typeof setTimeout> | null = null;
  let watchers: fs.FSWatcher[] = [];

  // ★활성 = 이벤트마다 재확인★ — 승계(retire) 전에 새 세션이 뜨면 _master 는 아직 옛 좌석이다. 한 번만 읽고 굳으면 영영 꺼진다.
  let announced = "";
  const activeSeat = (say: boolean): string => {
    let m = "";
    try { m = String(JSON.parse(fs.readFileSync(path.join(root, ".fable-team", "seats-planner.json"), "utf-8"))._master ?? ""); } catch { m = ""; }
    if (seat && m === seat) { announced = ""; return m; } // 내가 planner _master = 활성(사람 발신 판정에도 이 값을 쓴다)
    const why = `inactive seat=${seat || "?"} master=${m || "?"}`;
    if (say && announced !== why) { log(why); announced = why; } // 다른 pi 좌석 자동 활성화 0
    return "";
  };

  const mine = (): Row[] => { try { return parseRows(fs.readFileSync(mbox, "utf-8")).filter((r) => r.to === seat); } catch (e) { fail(`우편함 읽기 실패 ${mbox} — ${e}`); return []; } };
  const readSeq = (): number => { try { const n = Number(fs.readFileSync(seqFile, "utf-8").trim()); return Number.isFinite(n) ? n : -1; } catch { return -1; } };
  const writeSeq = (n: number | null) => { try { if (n === null) fs.rmSync(seqFile, { force: true }); else fs.writeFileSync(seqFile, `${n}\n`); } catch { /* 폴더 없음 = 다음 회수 */ } };
  // recv·예산이 «지정 우편함» 을 보게 한다(FT_MBOX_DIR).
  const reserve = () => spawnSync("bash", [mboxSh, "budget", "reserve", seat, "pi"], { encoding: "utf-8", timeout: 7000, env: { ...process.env, FT_MBOX_DIR: mboxDir } }).status ?? 1;
  function recordHeld(seq: number) { // r1476 doorbell_record_held 와 같은 꼴 — 닫는 사건은 sweep(창이 바뀐 뒤 nudge)이다.
    const now = Math.floor(Number(process.env.FT_MBOX_NOW ?? Date.now() / 1000)), f = path.join(state, "doorbell-held", keyOf(seat));
    try {
      fs.mkdirSync(path.dirname(f), { recursive: true });
      if (!fs.existsSync(f)) fs.writeFileSync(f, `held ts=${now} reason=budget window=${Math.floor(now / 3600)} seat=${seat}\n`);
      fs.appendFileSync(f, `seq=${seq}\n`);
    } catch (e) { fail(`held 기록 실패 ${f} — ${e}`); }
  }
  function wakeNow(seq: number, viaNudge: boolean) { // 빌린 CLI 일 때만 FT_MBOX_DIR 로 «recv 대상 우편함» 을 밝힌다.
    const content = `[발주 #${seq}] ${borrowed ? `FT_MBOX_DIR="${mboxDir}" ` : ""}bash ${mboxSh} recv ${seat} — 실행하고 그 안의 지시를 즉시 착수하라`;
    try { pi.sendMessage({ customType: "ft-mbox", content, display: true }, { triggerTurn: true, deliverAs: "followUp" }); } catch (e) { return fail(`sendMessage 실패 — ${e}`); }
    writeSeq(seq);
    if (viaNudge) fs.rmSync(nudge, { force: true }); // nudge 삭제 = 깨운 뒤
  }
  function check(force: boolean) {
    const rows = mine();
    if (rows.length === 0 || quietOnly(rows)) return; // 보고 전용 머리만 = 큐만 · 예산 0
    const master = activeSeat(false); // ★매 이벤트 재확인★
    if (!master) return;
    const seq = Math.max(...rows.map((r) => r.seq));
    const viaNudge = fs.existsSync(nudge); // r1476 sweep 이 이미 예약했다 — 재예약 0(이중 차감 0)
    if (!force && !viaNudge && readSeq() >= seq) return; // 턴 진행 중 중복 억제
    const exempt = loud(rows) || rows.some((r) => humanSender(r.from, master)); // 예산 밖(카드 ④)
    if (!viaNudge && !exempt) {
      const rc = reserve();
      if (rc !== 0) { recordHeld(seq); if (rc !== 3) fail(`예산 CLI 실패 rc=${rc} — 턴 0(${seat} #${seq})`); return; } // fail-closed = 턴 0
    }
    wakeNow(seq, viaNudge);
  }
  const run = () => { try { check(false); } catch (e) { fail(`감시 처리 실패 — ${e}`); } };
  const schedule = () => { if (!timer) timer = setTimeout(() => { timer = null; run(); }, debounce); };
  pi.on("session_start", async () => {
    if (!fs.existsSync(mbox)) return fail(`우편함 없음 ${mbox} — 확장 비활성(폴링 폴백 0)`);
    try { fs.mkdirSync(wakeDir, { recursive: true }); } catch { /* 이미 있음 */ }
    try {
      // ★부모 폴더 감시★ — os.replace 로 inode 가 바뀌어도 폴더 감시는 유지된다(파일 직접 watch 0).
      watchers = [
        fs.watch(mboxDir, (_e, fn) => { if (!fn || fn === path.basename(mbox)) schedule(); }),
        fs.watch(wakeDir, (_e, fn) => { if (fn === path.basename(nudge)) schedule(); }),
      ];
    } catch (e) { return fail(`watch 실패 ${mboxDir} / ${wakeDir} — ${e}`); }
    activeSeat(true); // 시작 로그 = 활성/비활성 1줄
    check(true); // 시작 회수 = 우편함에 «남아 있는» to=내 좌석 행(소비 ACK 기준 · seq 파일 무관)
    // ★감시 기동 창★ — fs.watch 등록 직후 사건은 유실될 수 있다(FSEvents startup). 주기 0 · 시작 1회 재확인만.
    if (!timer) timer = setTimeout(() => { timer = null; run(); }, debounce + 250);
  });
  pi.on("agent_end", async () => { writeSeq(null); run(); }); // 표지 해제 + 우편함 재확인 1회(소비 안 됐으면 다시 깨운다)
  // 세션 교체(reload/resume)·종료 = 감시 해제. 안 닫으면 옛 인스턴스가 같은 우편함에 2중으로 깨운다.
  pi.on("session_shutdown", async () => { for (const w of watchers) w.close(); watchers = []; if (timer) clearTimeout(timer); timer = null; });
}
