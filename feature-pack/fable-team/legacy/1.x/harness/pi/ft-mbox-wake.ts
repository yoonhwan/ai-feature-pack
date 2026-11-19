// ft-mbox-wake (r1477) — planner 대면 pi 좌석을 «쪽지 도착 = 턴 1회» 로 깨운다. 주기 타이머 0 · 입력 주입 0 · 예산은 r1476 `mbox.sh budget reserve` CLI 로만 차감.
//  · 활성 = FT_SEAT(없으면 tmux 세션명) == <루트>/.fable-team/seats-planner.json `_master` «매 이벤트 재확인» · 루트 = FT_MBOX_ROOT ?? git 공용 루트 ?? cwd.
//  · 설치 = `~/.pi/agent/extensions/ft-mbox-wake.ts` 복사 1개(pi 재시작 1회) · env: FT_MBOX_FILE(다른 데이터 루트) · FT_MBOX_STATE_DIR · FT_MBOX_WAKE_DEBOUNCE_MS · FT_H_DONE_QUIET_MS(r1540) · FT_USER_BASH_QUIET_MS(r1555) · 시험 = tests/test_pi_mbox_wake_{r1477,self_r1529}.sh · tests/test_pi_bash_pending_r1540.sh · tests/test_pi_user_bash_quiet_r1555.sh · tests/test_pi_mbox_wake_recv_gate_r1669.sh(r1669 = 증류 게이트 좌석은 같은 미읽음에 깨움 1회 + 팀장 1통 · .gated·.gatedmark)
//  · r1529 = 내 행 판정을 recv 와 같은 칸으로(from !== seat) + 판 2 턴 도중 깨움 쌓기 0(agent_start~agent_end 표지 · 배달 안 된 깨움 1개 상한).
//  · r2321 = ★큐만(quiet) 늙음 1회★ — quiet 미읽음만 있는 좌석은 늘 «다음 깨움 때 같이 읽힘» 을 전제로 큐만 했는데, 유휴 좌석에는 그 다음 깨움이 오지 않아 영원히 남았다(실사건 room-tester-pi#45 → room-master-pi#64 17~84분 3회). 이제 «아직 안 깨운» quiet 행(seq > .aged)의 가장 오래된 ts + FT_MBOX_QUIET_AGE_S(초·기본 900)가 지나고 쉬는 좌석이면 1회 깨운다(이미 깨운 옛 행은 안 셈 — 새 행마다 바로 깨움 0). 1회 표지 = <state>/pi-wake/<키>.aged 일반 파일 1줄(seq · agent_end·check(true) 가 안 지운다 · seq 표지와 별개) · 늙음 타이머 aT 1개(bT 와 다른 변수 · 주기 0) · Row 에 ts 1칸 · 종류 표·예산·loud·사람 발신·증류 게이트·묶음(wake_at) 은 그대로 · 시험 = tests/test_pi_mbox_wake_quiet_aged_r2321.sh
//  · r1540 = h 끝 알림을 «모은다» — h 마다 즉시 턴을 만들면 오빠의 다음 `!` 이 거의 늘 streaming 중이고, pi 는 그 결과를 대화로 옮기지 않는다(interactive-mode.js:5960·5982 · flush 는 :2781 한 곳). 마지막 h 뒤 조용함 창(FT_H_DONE_QUIET_MS · 기본 20000)이 지나고 좌석이 쉬면 한 통, 일하는 중이면 다음 정상 settled 에서 1회. 창이 안 끝난 settled 는 0(R1) · 대기 목록은 파일(<state>/pi-wake/<키>.hdone)이 정본이라 reload·shutdown 에서 유실 0(R2 · 새 session_start 회수 · ★R3★ 창은 «h 완료 시각» 에서 재므로 새 인스턴스는 남은 창을 존중한다).
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync, execSync } from "node:child_process";
import { createLocalBashOperations, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendLoadLine } from "./ft-load-line.ts"; // r1537 — 세션 기록 «로드 <카드> <판>» 1줄(턴 0)
import { say } from "./ft-load-line.ts"; // r1837 — 진단 1줄 출력 길(TUI = 파일 로그)
type Row = { seq: number; to: string; body: string; from: string; ts?: unknown; wake?: unknown };
const QUIET = ["[정리]", "[회신]", "[완료 보고]"]; // r1476 종류 표와 같은 값 — 큐만
const LOUD = ["[긴급]", "[인계]", "[레디]"]; // 예산 밖 즉시

export const headOf = (body: string): string => [...QUIET, ...LOUD].find((h) => body.trimStart().startsWith(h)) ?? "";
export function parseRows(text: string): Row[] {
  const rows: Row[] = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    try {
      const r = JSON.parse(line);
      if (typeof r?.seq === "number" && typeof r?.to === "string") rows.push({ seq: r.seq, to: r.to, body: String(r.body ?? ""), from: String(r.from ?? ""), ts: r.ts, wake: r.wake_at });
    } catch { continue; } // 깨진 줄 1개가 우편함 전체를 막지 않는다
  }
  return rows;
}
export const quietOnly = (rows: Row[]) => rows.length > 0 && rows.every((r) => QUIET.includes(headOf(r.body)));
export const loud = (rows: Row[]) => rows.some((r) => LOUD.includes(headOf(r.body)));
export const wakeOk = (r: Row, now: number) => Number.isInteger(r.wake) && (r.wake as number) >= 0 && (r.wake as number) <= now + 3600; // ★r2169 W6★ wake_at 칸 = 정수 · 0 이상 · 지금+3600초 이하 · 그 밖(글자·음수·소수·null·먼 미래) = 칸 없는 행
export const oldestTsMs = (rows: Row[]): number => Math.min(...rows.map((r) => (typeof r.ts === "number" && Number.isFinite(r.ts) ? (r.ts < 1e12 ? r.ts * 1000 : r.ts) : typeof r.ts === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(r.ts.trim()) ? Date.parse(r.ts.trim()) : NaN)).filter((n) => Number.isFinite(n))); // ★r2321 Q4★ ts 판독 = ISO 초 글자 · Z·±hh:mm 없는 글자 = 지역 시각(ECMAScript) · 그 밖(칸 없음·글자 꼴 아님) = 못 읽음 = 늙음 판정에서 뺀다 · 전부 못 읽음 = Infinity(안 늙는다)
// mbox_wakegate.sh:12~18 «사람 발신» 경계 — planner 표식(slack-*·*-oppa·oppa) + 좌석 _master. 미등록 좌석은 사람이 아니다.
export const humanSender = (from: string, master: string) => from === master || from === "oppa" || from.startsWith("slack-") || from.endsWith("-oppa");
const keyOf = (s: string) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
const log = (m: string) => say(`ft-mbox-wake: ${m}`);
const fail = (m: string) => say(`ERROR ft-mbox-wake: ${m}`);
const sh = (cmd: string): string => { try { return execSync(cmd, { encoding: "utf-8", timeout: 7000, stdio: ["ignore", "pipe", "ignore"] }).trim(); } catch { return ""; } };
const seatName = (): string => process.env.FT_SEAT || sh('tmux display-message -p "#S"');
// ★root = «git 공용 루트»★ — pi pane 의 cwd 는 워크트리일 수 있다(실측 11-09 18:20 planner pi#245). 다른 ft 도구와 같은 식.
const gitRoot = (): string => { const d = sh("git rev-parse --path-format=absolute --git-common-dir"); return d ? path.dirname(d) : ""; };
// ★팀장 pi 판정(r1530 공유 · ft-idle-nudge 가 import)★ = seats*.json 하나의 _master 이고 «같은 파일» 그 행 agent=='pi' → 그 파일 이름(없으면 "") · 깨진 파일 = 그 파일 거짓
export function piMasterFile(root: string, seat: string): string { const d = path.join(root, ".fable-team"); let names: string[] = []; try { names = fs.readdirSync(d).filter((f) => /^seats.*\.json$/.test(f)).sort(); } catch { return ""; }
  for (const f of names) { try { const j = JSON.parse(fs.readFileSync(path.join(d, f), "utf-8")), r = j?.[seat]; if ((r?.agent === "pi" && j._master === seat)) return f; } catch { continue; } }
  return ""; }

// ★r1669★ 이 좌석의 팀장 = «내 행이 있는» seats 파일의 _master — distill-gate teamMaster 와 같은 칸(다른 팀 명부의 master 를 고르지 않는다).
export function teamMasterOf(root: string, seat: string): string { const d = path.join(root, ".fable-team"), b = seat.replace(/#\d+$/, ""); let names: string[] = []; try { names = fs.readdirSync(d).filter((f) => /^seats.*\.json$/.test(f)).sort(); } catch { return ""; } for (const f of names) { try { const j = JSON.parse(fs.readFileSync(path.join(d, f), "utf-8")); if (Object.keys(j).some((k) => k === seat || k.replace(/#\d+$/, "") === b)) return String(j._master ?? ""); } catch { continue; } } return ""; }

export default function (pi: ExtensionAPI) {
  const seat = seatName(), nano = !!seat && process.env.FT2_HOLDER === seat; // ★r2110 A1★ ft2 나노 pi 좌석(명부 밖) = 세션 env FT2_HOLDER 가 내 좌석 이름과 글자 그대로 같음
  const ft2Root = (() => { const r = process.env.FT2_ROOT ?? ""; try { return nano && r && fs.statSync(r).isDirectory() ? r : ""; } catch { return ""; } })(); // ★r2110 A2 · DA R1★ 나노 = 팀 루트(cwd 가 다른 리포 worktree 여도 팀 우편함) · 없는 폴더 = 지금 순서
  const root = process.env.FT_MBOX_ROOT || ft2Root || gitRoot() || process.cwd(); // 명시 값 먼저
  const seatKnown = (): boolean | null => { if (process.env.FT_SEAT || nano) return true; if (!process.env.TMUX_PANE) return false; if (!seat) return null; const b = seat.replace(/#\d+$/, ""), d = path.join(root, ".fable-team"); let files: string[] = [], bad = false; try { files = fs.readdirSync(d).filter((f) => /^seats.*\.json$/.test(f)); } catch { return false; } const hit = files.some((f) => { try { const j = JSON.parse(fs.readFileSync(path.join(d, f), "utf-8")); return Object.keys(j).some((k) => !k.startsWith("_") && (k === seat || k.replace(/#\d+$/, "") === b)); } catch { bad = true; return false; } }); return hit ? true : bad ? null : false; }; // ★r1634★ ft 좌석인가 = distill-gate 와 같은 규칙(FT_SEAT ∨ 명부 행) · false = no-op · null = 판정 불가(tmux 안인데 이름 못 읽음·명부 깨짐 = 지금처럼)
  const mbox = process.env.FT_MBOX_FILE ?? path.join(root, ".fable-team", "comm", "mailbox.jsonl");
  const mboxDir = path.dirname(mbox); // ★입력·감시·recv 는 «같은 지정 우편함» 에 결속한다(FT_MBOX_FILE 지원)
  const localSh = path.join(mboxDir, "mbox.sh");
  const borrowed = !fs.existsSync(localSh), mboxSh = borrowed ? path.join(root, ".fable-team", "comm", "mbox.sh") : localSh; // CLI 없으면 루트 것을 빌린다
  const state = process.env.FT_MBOX_STATE_DIR ?? path.join(root, ".fable-team", "state");
  const wakeDir = path.join(state, "pi-wake");
  const seqFile = path.join(wakeDir, `${keyOf(seat)}.seq`), agedFile = path.join(wakeDir, `${keyOf(seat)}.aged`), agedMs = Number(process.env.FT_MBOX_QUIET_AGE_S ?? 900) * 1000; // ★r2321★ 늙음 창 = FT_MBOX_QUIET_AGE_S 초(기본 900 = 15분 · 카드 글자와 같음) · .aged = 늙어 깨운 최대 seq 1줄(일반 파일 · 못 읽음 = 표지 없음 · agent_end 의 writeSeq(null)·check(true) 가 안 지운다 · seq 표지와 별개)
  const nudge = path.join(wakeDir, `${keyOf(seat)}.nudge`);
  // ★r1669★ 증류 게이트에 걸린 좌석 = recv 가 막혀 미읽음을 못 비운다 → 같은 미읽음에는 깨움 1회 뒤 억제(agent_end 가 지우지 않는다) + 팀장 1통.
  const gated = path.join(wakeDir, `${keyOf(seat)}.gated`), gatedMark = path.join(wakeDir, `${keyOf(seat)}.gatedmark`), markerFile = path.join(state, "pi-distill-pending", seat.replace(/#\d+$/, "")); // .gated = 억제한 최대 seq · .gatedmark = 팀장에 알린 표식 본문(같은 표식 두 번 알림 0)
  const debounce = Number(process.env.FT_MBOX_WAKE_DEBOUNCE_MS ?? 300);
  let timer: ReturnType<typeof setTimeout> | null = null, aT: ReturnType<typeof setTimeout> | null = null; // aT = ★r2321 Q3★ 늙음 타이머(가장 오래된 ts + agedMs 1회 · bT 와 다른 변수 · 주기 0)
  let watchers: fs.FSWatcher[] = [], fallback: ReturnType<typeof setTimeout> | null = null, inTurn = false, wakePending = false; // fallback = 기동 창 1회 재확인 · 판 2(r1529) = 턴 도중 표지 · 배달 안 된 깨움 1개
  // ★r2128 W1★ 감시 진단 1줄 = <state>/pi-wake/<키>.beat(일반 파일 · 덮어쓰기 · 시각 = epoch 초 · 0 = 아직 없음) — 칸: event(마지막 감시 사건) check why inTurn wakePending watchers rearm woke(마지막 깨움 = ft-idle-wake W3 이 읽음). 쓰기 자체는 감시 사건이 아니다(wakeDir 감시 = .nudge 이름만).
  const beatF = path.join(wakeDir, `${keyOf(seat)}.beat`), rearmMs = Number(process.env.FT_MBOX_WAKE_REARM_MS ?? 600000), nowS = () => Math.floor(Number(process.env.FT_MBOX_NOW ?? Date.now() / 1000)), B = { event: 0, check: 0, why: "-", rearm: 0, woke: 0 }, said = new Set<string>(), closed = new WeakSet<fs.FSWatcher>();
  let rearmT: ReturnType<typeof setTimeout> | null = null, live = false, down = false; // rearmT = 유휴 1회 재무장 타이머(W2 · 주기 0) · live = session_start 가 감시를 건 좌석 · down = session_shutdown 뒤(재무장 0)
  const once = (k: string, m: string) => { if (!said.has(k)) { said.add(k); fail(m); } }, beat = () => { if (!live) return; try { fs.writeFileSync(beatF, `event=${B.event} check=${B.check} why=${B.why} inTurn=${+inTurn} wakePending=${+wakePending} watchers=${watchers.length} rearm=${B.rearm} woke=${B.woke}\n`); said.delete("beat"); } catch (e) { if (!said.has("beat")) { said.add("beat"); log(`.beat 쓰기 실패 ${beatF} — ${e} · 깨움 동작 불변`); } } };
  // ★r1540 h 끝 모음 상태★ — 목록은 보낸 뒤 비우고(같은 h 두 번 알림 0), 타이머는 h 1건마다 «다시 거는» 1회짜리뿐이다(주기 타이머 0).
  //  ★R1(DA 277721)★ = 창이 열려 있는 동안(타이머 안 끝) 정상 settled 가 와도 보내지 않는다 → hArmed 가 「창이 끝났다」 한 표시.
  //  ★R2(DA 277721)★ = 대기 목록의 정본은 «파일»(<state>/pi-wake/<키>.hdone) — reload·shutdown 으로 확장 인스턴스가 갈리어도 새 session_start 가 회수한다(유실 0).
  const hQuiet = Number(process.env.FT_H_DONE_QUIET_MS ?? 20000);
  const hFile = path.join(wakeDir, `${keyOf(seat)}.hdone`);
  let hDone: { n: string; rc: string; at: number }[] = [], hTimer: ReturnType<typeof setTimeout> | null = null, hHeld = false, hArmed = false, hSaveFail = "", ctxNow: { isIdle(): boolean } | null = null;
  const idle = (): boolean => { try { return ctxNow ? ctxNow.isIdle() : false; } catch { return false; } }; // ctx 없음 = 모른다 → 다음 settled 로 미룬다
  function hSave(): void { // 목록이 비면 파일을 지운다 — 다음 세션이 이미 보낸 알림을 다시 보내지 않는다(중복 0)
    try {
      if (hDone.length === 0) fs.rmSync(hFile, { force: true });
      else { fs.mkdirSync(wakeDir, { recursive: true }); fs.writeFileSync(hFile, `${JSON.stringify(hDone)}\n`); }
      hSaveFail = "";
    } catch (e) { const m = String(e); if (m !== hSaveFail) { hSaveFail = m; fail(`h 대기 목록 저장 실패 ${hFile} — ${m}`); } } // 같은 실패 반복 = 1줄
  }
  function hLoad(): void { // R2 — 옛 확장의 대기 목록 회수. ★R3★ 창은 «h 완료 시각» 에서 재므로 남은 창을 그대로 존중한다
    try {
      const a: unknown = JSON.parse(fs.readFileSync(hFile, "utf-8"));
      if (Array.isArray(a)) hDone = a.filter((it) => it && typeof (it as { n?: unknown }).n === "string")
        .map((it) => ({ n: String(it.n), rc: String(it.rc ?? "?"), at: Number.isFinite(Number((it as { at?: unknown }).at)) ? Number((it as { at?: unknown }).at) : Date.now() }));
    } catch { /* 파일 없음 = 회수 0 */ }
    if (hDone.length === 0) return;
    const left = Math.max(...hDone.map((it) => it.at)) + hQuiet - Date.now(); // 마지막 h 기준 — 확장이 꺼져 있던 시간도 센다
    if (left <= 0) { hArmed = true; hFlush(); return; } // 창이 이미 지났다 = 쉼이면 지금 1회
    if (hTimer) clearTimeout(hTimer); // 남은 창만큼 1회짜리 타이머(주기 0) — 만료 뒤 쉼에서 1회
    hTimer = setTimeout(() => { hTimer = null; hArmed = true; try { hFlush(); } catch (e) { fail(`h 끝 처리 실패 — ${e}`); } }, left);
  }
  function hFlush(): void { // 창이 끝난 자리 판정 — 일하는 중이면 목록 그대로 두고 다음 정상 settled 가 부른다(ⓒ)
    if (hHeld) return; // 중단(aborted) settled = 다음 정상 settled 로 미룬다
    if (!hArmed || hDone.length === 0 || !idle()) return; // ★R1★ 창이 아직 안 끝났으면 0 — settled 만으로는 보내지 않는다
    const items = hDone; hDone = []; hArmed = false; // ★보낸 목록은 즉시 비운다★ — 같은 h 결과 두 번 알림 0(ⓓ)
    hSave();
    const body = `${items.map((it) => `h${it.n} 끝 rc=${it.rc}`).join("\n")} → recv 하고 [완료] 정리`;
    try { pi.sendMessage({ customType: "ft-mbox", content: body, display: true }, { triggerTurn: true, deliverAs: "followUp" }); } catch (e) { fail(`user_bash 알림 실패 — ${e}`); }
  }
  function hQueue(n: string, rc: string): void { // h 1장 끝마다 «창을 다시 잰다»(ⓑ) · h 0 이면 타이머 0(ⓔ)
    hDone.push({ n, rc, at: Date.now() }); // ★R3★ 완료 시각을 같이 남긴다 — 새 인스턴스가 «남은 창» 을 재는 근거
    hSave();
    hArmed = false; // 창을 다시 열었다 — settled 가 와도 아직 보내지 않는다(R1)
    if (hTimer) clearTimeout(hTimer);
    hTimer = setTimeout(() => { hTimer = null; hArmed = true; try { hFlush(); } catch (e) { fail(`h 끝 처리 실패 — ${e}`); } }, hQuiet);
  }
  const userQuiet = Number(process.env.FT_USER_BASH_QUIET_MS ?? hQuiet); // ★r1555★ 오빠 `!`(user_bash) 뒤 «조용함 창» — 기본 = r1540 창 값 · 창 안에서는 쪽지 깨움 턴 0 · seq 0 · 예산 0 · held 기록 0
  let uTimer: ReturnType<typeof setTimeout> | null = null, uUntil = 0, bT: ReturnType<typeof setTimeout> | null = null; // 창 끝 1회짜리 타이머가 run() 1회(우편함 파일이 정본이라 손실 0) · `!` 가 또 오면 «마지막 `!` 기준» 으로 다시 잰다(주기 타이머 0) · bT = r2169 묶음 끝 시각 1회 타이머(좌석당 1개)
  const openUserQuiet = () => { if (userQuiet <= 0) return; uUntil = Date.now() + userQuiet; if (uTimer) clearTimeout(uTimer); uTimer = setTimeout(() => { uTimer = null; uUntil = 0; run(); }, userQuiet); };

  // ★활성 = 이벤트마다 재확인★ — 승계(retire) 전에 새 세션이 뜨면 _master 는 아직 옛 좌석이다. 한 번만 읽고 굳으면 영영 꺼진다.
  let announced = "";
  const seats = (): { master: string; desk: string } => {
    try { const d = JSON.parse(fs.readFileSync(path.join(root, ".fable-team", "seats-planner.json"), "utf-8")); return { master: String(d._master ?? ""), desk: String(d._desk ?? "") }; } catch { return { master: "", desk: "" }; }
  };
  // ★판 2 활성 판정(arch#267 · 카드 954fe550)★ = 「seats*.json 하나의 _master 이고 «같은 파일» 그 행 agent=='pi'」 ∨ 「seats-planner.json _desk」 — 셸 comm/mbox.sh ext_wake_seat 와 «같은 칸»(두 벌이 다른 말을 하면 좌석이 두 길로 깨운다).
  const activeFlag = (): boolean => nano || !!piMasterFile(root, seat) || (!!seat && seats().desk === seat); // r2110 나노 pi ∨ _master ∧ 같은 파일 agent=='pi' ∨ planner _desk
  const activeSeat = (say: boolean): boolean => { // 다른 pi 좌석 자동 활성화 0 — _master/_desk · r2110 ft2 나노(A1)만
    const mine = !!seat && activeFlag(), s = seats();
    if (mine) { announced = ""; return true; }
    const why = `inactive seat=${seat || "?"} master=${s.master || "?"} desk=${s.desk || "?"}`;
    if (say && announced !== why) { log(why); announced = why; }
    return false;
  };

  // ★내 행 = «recv 가 소비할 행» 과 같은 칸(r1153: to === seat ∧ from !== seat · r2259: ∨ to === seat ∧ 머리 [깨움] = mbox_lineage.self_wake)★ — 그 밖의 자기 발신 행(ft-index-move·ft-merge-land 알림)은 recv 가 안 소비해 우편함에 남는다.
  const mine = (): Row[] => { try { return parseRows(fs.readFileSync(mbox, "utf-8")).filter((r) => r.to === seat && r.from !== seat || r.to === seat && r.body.trimStart().startsWith("[깨움]")); } catch (e) { fail(`우편함 읽기 실패 ${mbox} — ${e}`); return []; } };
  const nowMs = () => Number(process.env.FT_MBOX_NOW ?? Date.now() / 1000) * 1000, readAged = (): number => { try { return Number(fs.readFileSync(agedFile, "utf-8").trim()) || -1; } catch { return -1; } }, writeAged = (n: number) => { try { fs.mkdirSync(wakeDir, { recursive: true }); fs.writeFileSync(agedFile, `${n}\n`); } catch (e) { fail(`늙음 표지 쓰기 실패 ${agedFile} — ${e}`); } }; // ★r2321 Q2★ 얼린 시계와 같은 칸 · 못 읽음 = -1(표지 없음)
  const readSeq = (): number => { try { const n = Number(fs.readFileSync(seqFile, "utf-8").trim()); return Number.isFinite(n) ? n : -1; } catch { return -1; } };
  const writeSeq = (n: number | null) => { try { if (n === null) fs.rmSync(seqFile, { force: true }); else fs.writeFileSync(seqFile, `${n}\n`); } catch { /* 폴더 없음 = 다음 회수 */ } };
  const reserve = () => spawnSync("bash", [mboxSh, "budget", "reserve", seat, "pi"], { encoding: "utf-8", timeout: 7000, env: { ...process.env, FT_MBOX_DIR: mboxDir } }).status ?? 1; // recv·예산이 «지정 우편함» 을 보게 한다(FT_MBOX_DIR).
  function recordHeld(seq: number) { // r1476 doorbell_record_held 와 같은 꼴 — 닫는 사건은 sweep(창이 바뀐 뒤 nudge)이다.
    const now = Math.floor(Number(process.env.FT_MBOX_NOW ?? Date.now() / 1000)), f = path.join(state, "doorbell-held", keyOf(seat));
    try {
      fs.mkdirSync(path.dirname(f), { recursive: true });
      if (!fs.existsSync(f)) fs.writeFileSync(f, `held ts=${now} reason=budget window=${Math.floor(now / 3600)} seat=${seat}\n`);
      fs.appendFileSync(f, `seq=${seq}\n`);
    } catch (e) { fail(`held 기록 실패 ${f} — ${e}`); }
  }

  function wakeNow(seq: number, viaNudge: boolean): boolean { // 빌린 CLI 일 때만 FT_MBOX_DIR 로 «recv 대상 우편함» 을 밝힌다. · 반환 = 배달 성공(send-fail 이면 false — 늙음 표지 0)
    const content = `[발주 #${seq}] ${borrowed ? `FT_MBOX_DIR="${mboxDir}" ` : ""}bash ${mboxSh} recv ${seat} — 실행하고 그 안의 지시를 즉시 착수하라`;
    try { pi.sendMessage({ customType: "ft-mbox", content, display: true }, { triggerTurn: true, deliverAs: "followUp" }); } catch (e) { B.why = "send-fail"; fail(`sendMessage 실패 — ${e}`); return false; }
    writeSeq(seq); wakePending = true; B.woke = nowS(); B.why = "woke"; // 성공한 깨움 = 배달 대기 1개(세션 시작 회수 포함 · DA HOLD R1) — agent_start 에서 소비
    if (viaNudge) fs.rmSync(nudge, { force: true }); return true; // nudge 삭제 = 깨운 뒤
  }
  // ★r1669★ true = 이번 깨움 억제 · false = 지금 동작 그대로(표식 없음 ⓔ · 후계·직전 세대 표식 ⓓ · 첫 억제 1회 · 새 쪽지 1회 더 ⓒ) · scheduled = r1476 sweep 이 미리 예약한 nudge 자리(재차감 0 · 기록은 하되 이미 억제한 seq 면 깨우지 않는다 · DA R1·R2)
  function recvGate(rows: Row[], seq: number, scheduled: boolean): boolean {
    let body = "";
    try { body = fs.readFileSync(markerFile, "utf-8"); } catch { try { fs.rmSync(gated, { force: true }); fs.rmSync(gatedMark, { force: true }); } catch { /* 표식 없음 */ } return false; } // ⓔ 표식이 사라짐 = 억제 기록 무시
    const owner = (body.match(/(?:^|\s)seat=(\S+)/) ?? [])[1] ?? ""; // 표식 본문의 좌석(#N 포함 · 옛 파일 = "")
    if (owner !== seat) return false; // ⓓ 후계(같은 베이스 · 다른 #N)·직전 세대 표식 = 이 카드 억제 0
    let last = -1;
    try { const n = Number(fs.readFileSync(gated, "utf-8").trim()); if (Number.isFinite(n)) last = n; } catch { /* 첫 억제 */ }
    if (last >= seq) { if (scheduled) fs.rmSync(nudge, { force: true }); return true; } // ⓐⓖⓗ 이미 억제한 같은 seq = 깨움·팀장 알림 0 · 늦은 예약(nudge)도 0 — 표지만 소비(재차감 0 · DA R2)
    try { fs.mkdirSync(wakeDir, { recursive: true }); fs.writeFileSync(gated, `${seq}\n`); } catch (e) { fail(`억제 기록 실패 ${gated} — ${e}`); } // ⓒ 새 쪽지 = 1회 더(.gated 갱신)
    let told = "";
    try { told = fs.readFileSync(gatedMark, "utf-8"); } catch { /* 아직 안 알림 */ }
    if (told === body) return false; // 같은 표식 = 팀장 알림 0
    const master = teamMasterOf(root, seat), alert = `[멈춤] ${seat} recv 막힘(증류 게이트) · 미읽음 ${rows.length}(최대 #${seq}) · 후계 필요 — 깨움 억제`;
    const r = master ? spawnSync("bash", [mboxSh, "send", master, seat, alert], { encoding: "utf-8", timeout: 7000, env: { ...process.env, FT_MBOX_DIR: mboxDir } }) : null; // 하드 룰 12 = 7초 1회
    if (!master) fail(`팀장 알림 0 — ${seat} 명부 행·_master 없음`); else if ((r?.status ?? 1) !== 0) fail(`팀장 알림 실패(${master}) rc=${r?.status ?? "?"} — 깨움 억제는 그대로`); // 조용한 0 금지
    try { fs.writeFileSync(gatedMark, body); } catch (e) { fail(`알림 기록 실패 ${gatedMark} — ${e}`); }
    return false;
  }
  function armAged(pend: Row[]) { const oldest = oldestTsMs(pend), left = Number.isFinite(oldest) ? oldest + agedMs - nowMs() : -1; if (aT) { clearTimeout(aT); aT = null; } if (down || left <= 0) return; aT = setTimeout(() => { aT = null; run(); }, left); } // ★r2321 Q3★ 늙음 타이머 = «아직 안 깨운» 큐만 행의 가장 오래된 ts + agedMs 시각에 check 1회(check 마다 다시 잼 · 주기 0 · 못 읽는 ts 뿐이면 0)
  function check(force: boolean) { B.check = nowS(); B.why = "uquiet"; // ★r2128 W1★ 반환 이유는 갈래마다 B.why 에 남는다(run 이 .beat 1줄)
    if (uUntil > Date.now()) return; // ★r1555★ 창 안 = 아무것도 하지 않는다(우편함 읽기·seq·예산·held 0) — 창 끝 타이머가 run() 을 1회 부른다
    const rows = mine(), now = nowS(), held = rows.filter((r) => wakeOk(r, now) && (r.wake as number) > now), act = rows.length >= 8 ? rows : rows.filter((r) => !held.includes(r)); // ★r2169 W4★ «아직 묶음» = wake_at 미래 · ⓔ 미읽음 8행 이상 = 시각이 지난 행으로 본다
    if (bT) clearTimeout(bT); bT = held.length && !down ? setTimeout(() => { bT = null; run(); }, Math.min(...held.map((r) => r.wake as number)) * 1000 - Number(process.env.FT_MBOX_NOW ?? Date.now() / 1000) * 1000) : null; // ⓑ 가장 이른 wake_at 에 check 1회 · check 마다 다시 잼 · 주기 0
    const quiet = act.length > 0 && quietOnly(act), pend = act.filter((r) => r.seq > readAged()), aged = quiet && pend.length > 0 && oldestTsMs(pend) + agedMs <= nowMs(); if (quiet && !aged) armAged(pend); else if (aT) { clearTimeout(aT); aT = null; } // ★r2321★ 큐만 = «아직 안 깨운 행만» 세어 늙었으면 1회 깨운다 — 이미 깨운 옛 행이 남아도 새 행마다 바로 깨움 0 · 그 전엔 지금처럼 큐만 · 늙는 시각에 타이머 1회
    if (act.length === 0 || (quiet && !aged)) { B.why = rows.length === 0 ? "empty" : act.length ? "quiet-only" : "batched"; if (rows.length === 0) wakePending = false; return; } // 보고 전용 머리만 · 미읽음 0 = recv 가 소비했다(배달 대기 해제) · 예산 0
    B.why = inTurn ? "in-turn" : wakePending ? "wake-pending" : "inactive"; if (!activeSeat(false) || inTurn || wakePending) return; // ★매 이벤트 재확인★ · 판 2(r1529) = 턴 도중 쌓기 0 · 배달 안 된 깨움 1개 상한(ⓗⓘⓙ)
    const master = seats().master; // 사람 발신 판정 = _master(desk 로 활성돼도 같다)
    const seq = Math.max(...rows.map((r) => r.seq));
    const viaNudge = fs.existsSync(nudge); // r1476 sweep 이 이미 예약했다 — 재예약 0(이중 차감 0)
    B.why = quiet ? "quiet-aged" : "seq-dup"; if (!force && !viaNudge && readSeq() >= seq) return; // 턴 진행 중 중복 억제
    B.why = "gated"; if (recvGate(rows, seq, viaNudge)) return; // ★r1669★ 증류 게이트 좌석 = 같은 미읽음에 깨움 1회(예산·턴 0) — nudge 예약분도 같은 칸(첫 예약은 기록하고 깨우고 · 이미 억제한 seq 면 깨움 0 · DA R1·R2)
    const exempt = loud(rows.filter((r) => !wakeOk(r, now))) || rows.some((r) => humanSender(r.from, master)); // 예산 밖(카드 ④)
    if (!viaNudge && !exempt) {
      const rc = reserve();
      if (rc !== 0) { B.why = "budget-held"; recordHeld(seq); if (rc !== 3) fail(`예산 CLI 실패 rc=${rc} — 턴 0(${seat} #${seq})`); return; } // fail-closed = 턴 0
    }
    const woke = wakeNow(seq, viaNudge); if (quiet && woke) writeAged(seq); // ★r2321★ 깨운 뒤에만 표지(배달 실패면 표지 0) — 같은 seq 로 다시 0 · 새 seq 는 1회 더
  }
  const run = () => { try { check(false); } catch (e) { fail(`감시 처리 실패 — ${e}`); } beat(); }, schedule = () => { if (!timer) timer = setTimeout(() => { timer = null; run(); }, debounce); }; // ★r2128★ run 끝 = .beat 1줄 · schedule = 폴더 사건 → 바운스 1회, run = 이벤트 처리
  pi.on("session_start", async (_event, ctx) => {
    ctxNow = ctx as { isIdle(): boolean }; // r1540 — h 끝 판정은 ctx.isIdle 로만 한다(r1531 과 같은 칸)
    appendLoadLine(pi, "r1529", "ft-mbox-wake.ts"); // 조기 return 앞 — 기록은 확장이 실렸다는 사실만 말한다
    if (seatKnown() === false) return; if (!fs.existsSync(mbox)) return fail(`우편함 없음 ${mbox} — 확장 비활성(폴링 폴백 0)`); // ★r1634★ 좌석 아님 = 조용히(session_start 만 보고 끝 — ERROR 0 · watch 0 · sendMessage 0)
    try { fs.mkdirSync(wakeDir, { recursive: true }); } catch { /* 이미 있음 */ }
    live = true; if (!arm()) { live = false; return; } // ★부모 폴더 감시★(os.replace 로 inode 가 바뀌어도 유지 · 파일 직접 watch 0) · 등록 = arm() 한 곳(r2128 재무장과 같은 길)
    activeSeat(true); inTurn = wakePending = false; // 시작 로그 = 활성/비활성 1줄 · 표지 초기화(승계·/reload)
    hLoad(); // ★R2★ 옛 확장의 h 대기 목록 회수 — 남은 창이 있으면 그만큼 기다렸다가 1회(즉시 발사 0 · R3)
    check(true); beat(); idleArm(); // 시작 회수 = 우편함에 «남아 있는» to=내 좌석 행(소비 ACK 기준 · seq 파일 무관)
    // ★감시 기동 창★ — fs.watch 등록 직후 사건은 유실될 수 있다(FSEvents startup). 주기 0 · 시작 1회 재확인만.
    fallback = setTimeout(() => { fallback = null; run(); }, debounce + 250); // 사건 타이머를 막지 않는다(사건이 오면 즉시 처리)
  });
  // ★r2128 W2★ 재무장 = 옛 watcher 를 «일부러 닫음» 표시 뒤 닫고 새로 건다(교체 길 · 그 close 는 재무장 0) · 'error'·'close' 사건 = ERROR 1줄(같은 이유 1회) + 그 자리 재무장(사건 길) · shutdown 뒤 0.
  function arm(): boolean { for (const w of watchers) { closed.add(w); try { w.close(); } catch { /* 이미 닫힘 */ } } watchers = []; if (down) return false; const ws: fs.FSWatcher[] = [];
    try { ws.push(fs.watch(mboxDir, (_e, fn) => { if (!fn || fn === path.basename(mbox)) hit(); })); ws.push(fs.watch(wakeDir, (_e, fn) => { if (fn === path.basename(nudge)) hit(); })); } catch (e) { for (const w of ws) { closed.add(w); w.close(); } once(`watch ${e}`, `watch 실패 ${mboxDir} / ${wakeDir} — ${e}`); beat(); return false; }
    for (const w of ws) { w.on("error", (e) => lost(w, `error ${(e as NodeJS.ErrnoException)?.code ?? e}`)); w.on("close", () => lost(w, "close")); }
    watchers = ws; B.rearm = nowS(); beat(); return true; }
  function lost(w: fs.FSWatcher, why: string) { if (closed.has(w) || down) return; closed.add(w); once(`lost ${why}`, `감시 ${why} — 그 자리 재무장(${seat})`); arm(); }
  const hit = () => { B.event = nowS(); if (rearmT) { clearTimeout(rearmT); rearmT = null; } schedule(); }; // 감시 사건 = 진단 시각 + 유휴 1회 타이머 지움
  const idleArm = () => { if (rearmT) clearTimeout(rearmT); rearmT = down || !live ? null : setTimeout(() => { rearmT = null; if (!down) { arm(); run(); } }, rearmMs); }; // 유휴 진입 = 1회짜리(주기 0 · 유휴 1번에 최대 1회) — 그 사이 감시 사건 0 이면 재무장 + check 1회
  pi.on("agent_start", async () => { inTurn = true; wakePending = false; if (rearmT) { clearTimeout(rearmT); rearmT = null; } }); // 판 2 = 턴 시작(배달된 깨움 소비) · 도중 도착은 쌓지 않는다
  pi.on("agent_end", async () => { inTurn = false; wakePending = false; writeSeq(null); if (seatKnown() !== false) { if (live) arm(); idleArm(); run(); } }); // ★r2128 W2★ 턴 끝 = 재무장 + 유휴 타이머 + check // 표지 해제 + 우편함 재확인 1회(소비 안 됐으면 다시 깨운다) · r1634 좌석 밖에서는 우편함을 읽지 않는다(ERROR 0)
  // ★r1540 = 창이 끝났을 때 일하던 중이던 h 결과를 여기서 1회 알린다★ — 중단(Escape) settled 는 미룬다(r1531 꼴).
  pi.on("agent_settled", async (event, ctx) => {
    ctxNow = ctx as { isIdle(): boolean };
    if ((event as { aborted?: boolean })?.aborted) { hHeld = true; return; }
    hHeld = false; if (live) { arm(); idleArm(); run(); } // ★r2128 W2★ 정상 settled = 재무장 + check 1회
    hFlush();
  });
  // ④ 오빠가 `! bash /tmp/hN` 을 돌리면 «끝난 뒤» 턴 1회 — 결과(rc·출력)는 건드리지 않는다(desk 결함 11-09 18:5x).
  pi.on("user_bash", (event: { command: string; excludeFromContext?: boolean }) => {
    if (event.excludeFromContext || !activeSeat(false)) return; // !! 제외 · 활성 좌석(_master·_desk)만 — 다른 pi 좌석 0
    openUserQuiet(); // ★r1555★ `!` 는 «아무 명령» 이나 창을 열고, 창은 마지막 `!` 기준으로 다시 잰다 — 오빠 연타 중 쪽지가 오면 블록이 대기 영역에 남는다
    const m = /^bash \/tmp\/h([0-9]+)$/.exec(event.command);
    if (!m) return; // h 아닌 `!` = 창만 열고 훅 0
    let local;
    try { local = createLocalBashOperations(); } catch (e) { return fail(`user_bash 훅 비활성 — ${e}`); } // 훅 실패 = bash 결과 불변
    return { operations: { exec: async (cmd: string, cwd: string, o: unknown) => {
      const r = await local.exec(event.command, cwd, o); // ★원래 명령 그대로 실행★
      // ★결과 기록 «뒤» 모은다★ — exec 반환 뒤(pi 가 BashExecution 을 세션에 넣은 뒤) 목록에 넣고 조용함 창을 «다시» 건다. 폴링 0(단일 setImmediate) · 턴 0.
      setImmediate(() => { try { hQueue(m[1], String(r?.exitCode ?? "?")); } catch (e) { fail(`user_bash 알림 실패 — ${e}`); } });
      return r; // ★알림이 실패해도 bash 결과 그대로★
    } } };
  });
  pi.on("input", (event: { source?: string }) => { if (event.source !== "interactive") return; uUntil = 0; if (uTimer) { clearTimeout(uTimer); uTimer = null; } }); // ★r1555★ 오빠 일반 메시지(source="interactive") = 창 즉시 닫기 — 대기 영역이 비었고 그 턴이 끝나면 agent_end 가 우편함을 다시 본다 · "extension"·"rpc" 는 창 불변
  // 세션 교체(reload/resume)·종료 = 감시 해제. 안 닫으면 옛 인스턴스가 같은 우편함에 2중으로 깨운다.
  pi.on("session_shutdown", async () => { down = true; for (const w of watchers) { closed.add(w); w.close(); } watchers = []; if (rearmT) clearTimeout(rearmT); rearmT = null; if (timer) clearTimeout(timer); if (fallback) clearTimeout(fallback); if (hTimer) clearTimeout(hTimer); if (uTimer) clearTimeout(uTimer); if (bT) clearTimeout(bT); if (aT) clearTimeout(aT); timer = fallback = hTimer = uTimer = bT = aT = null; });
}
