#!/usr/bin/env bash
# test_pi_mbox_wake_why_history_r2322.sh — r2322: 좌석이 안 깨웠을 때 «어느 갈래로 돌아섰는지» 가 <state>/pi-wake/<키>.why 에 1줄씩 남는다
#  H1 이력 1줄 = ①③⑤ · H2 중복 0 = ② · H3 상한 = ④ · H4 불변 = ⑥(.beat 꼴 · 쓰기 실패 = 깨움 영향 0 · 회귀 시험 8종)
#  기준판(.why 없음) = ① Red. 격리 = r2321 꼴(임시 루트 · 합성 mailbox.jsonl · 가짜 pi · 스텁 mbox.sh · pi 패키지 스텁 · 실 우편함·실 pi 0).
#  시계 = FT_MBOX_NOW(정수 초) 고정 · sleep 0(⑤ 의 창은 기본 20000ms 안이라 즉시) · 네트워크 0.
#  R2322_EXT = 다른 확장 파일(기준판·변이)을 볼 때만 · R2322_CASES = 돌릴 시험 번호(기본 1 2 3 4 5 6) · R2322_SKIP_REGRESS=1 = ⑥ 회귀 생략.
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R2322_EXT:-$HARNESS/pi/ft-mbox-wake.ts}"
SEAT="byz-harness-master-pi#2322"
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$EXT" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/r2322-why.XXXXXX")"
trap 'rm -rf "$T"' EXIT

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const EXT = process.env.R2322_EXT, SEAT = process.env.R2322_SEAT, ROOT = process.env.R2322_TMP;
const CASES = (process.env.R2322_CASES || "1 2 3 4 5 6").split(/\s+/);
const want = (n) => CASES.includes(String(n));
const T0 = 1795000000; // 고정 «지금»(초) — ts 칸이 FT_MBOX_NOW 를 따르는지 재는 값
let modv = 0, fails = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const keyOf = (s) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
const row = (seq, o = {}) => ({ seq, to: SEAT, from: o.from ?? "issues-master-pi#66", body: o.body ?? "[Issue 접수] r2322 시험" }); // non-quiet 머리(QUIET 3종 아님)

let cur = null;
function setup(name, rows) {
  const dir = path.join(ROOT, name), base = path.join(dir, ".fable-team"), comm = path.join(base, "comm"), state = path.join(base, "state");
  fs.mkdirSync(comm, { recursive: true }); fs.mkdirSync(state, { recursive: true });
  fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify({ _master: SEAT, [SEAT]: { role: "master", agent: "pi" } }) + "\n");
  const budgetLog = path.join(dir, "budget.log");
  fs.writeFileSync(path.join(comm, "mbox.sh"), `#!/bin/bash\necho "$*" >> ${budgetLog}\nexit 0\n`); // 예산 CLI 스텁 = 항상 승인
  const mbox = path.join(comm, "mailbox.jsonl");
  fs.writeFileSync(mbox, rows.map((r) => JSON.stringify(r) + "\n").join(""));
  Object.assign(process.env, { FT_MBOX_ROOT: dir, FT_MBOX_STATE_DIR: state, FT_MBOX_FILE: mbox, FT_SEAT: SEAT,
    FT_MBOX_WAKE_DEBOUNCE_MS: "5", FT_MBOX_WAKE_REARM_MS: "86400000", FT_MBOX_NOW: String(T0) });
  cur = { dir, mbox, budgetLog, state, k: keyOf(SEAT) };
  return cur;
}
const whyFile = (c) => path.join(c.state, "pi-wake", `${c.k}.why`);
const whyLines = (c) => { try { return fs.readFileSync(whyFile(c), "utf-8").split("\n").filter((l) => l.trim()); } catch { return []; } };
const beatFile = (c) => path.join(c.state, "pi-wake", `${c.k}.beat`);

const live = [];
async function load() {
  for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); }
  const pi = { calls: [], retired: false, h: {}, on(e, f) { (this.h[e] ??= []).push(f); },
    async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); },
    appendEntry() {}, sendMessage(m) { if (this.retired) return; this.calls.push(m); } };
  live.push(pi);
  (await import(`${pathToFileURL(EXT).href}?v=${++modv}`)).default(pi);
  await pi.emit("session_start", {});
  return pi;
}
const poke = (pi) => pi.emit("agent_settled", {}); // 정상 settled = 재무장 + run() 1회
const turnStart = (pi) => pi.emit("agent_start", {}); // inTurn = 1
const turnEnd = (pi) => pi.emit("agent_end", {}); // inTurn = 0 · seq 표지 지움 · run() 1회
const shutdown = async () => { for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); } };
const cols = (line) => Object.fromEntries((line ?? "").trim().split(/\s+/).map((kv) => { const i = kv.indexOf("="); return [kv.slice(0, i), kv.slice(i + 1)]; }));

// ── ① H1 in-turn 갈래 = 1줄(기준판 = 파일 없음 → Red) ────────────────────────────────
if (want(1)) {
  const c = setup("h1", [row(901)]);
  const pi = await load(); // session_start check(true) = 깨움 1(예산 스텁 승인)
  await turnStart(pi); // 턴 도중 = 갈래 in-turn
  await poke(pi); // run() 1회
  const ls = whyLines(c);
  eq("① .why 1줄", ls.length, 1);
  const k = cols(ls[0]);
  eq("① why=in-turn", k.why, "in-turn");
  eq("① seq = 그 미읽음 seq", k.seq, "901");
  eq("① n = 미읽음 1", k.n, "1");
  eq("① inTurn=1", k.inTurn, "1");
  eq("① uwin=0(창 밖)", k.uwin, "0");
  eq("① ts = FT_MBOX_NOW", k.ts, String(T0));
  eq("① 깨움 판단 불변(세션 시작 1회만)", pi.calls.length, 1);
  await shutdown();
}
// ── ② H2 중복 0 = 같은 상태 3회 = 여전히 1줄 ─────────────────────────────────────
if (want(2)) {
  const c = setup("h2", [row(911)]);
  const pi = await load();
  await turnStart(pi);
  await poke(pi); await poke(pi); await poke(pi); // 같은 why·seq·n·inTurn·wakePending·uwin 3회
  eq("② 같은 상태 check 3회 = .why 1줄", whyLines(c).length, 1);
  await shutdown();
}
// ── ③ H1 갈래가 바뀌면 1줄 더 = in-turn → woke ──────────────────────────────────
if (want(3)) {
  const c = setup("h3", [row(921)]);
  const pi = await load();
  await turnStart(pi); await poke(pi);
  eq("③ (앞) in-turn 1줄", whyLines(c).length, 1);
  await turnEnd(pi); // 턴 끝 = seq 표지 지움 → 우편함 재확인 = 깨움(woke)
  const ls = whyLines(c), k = cols(ls.at(-1));
  eq("③ 갈래가 바뀌면 2줄", ls.length, 2);
  eq("③ 첫 줄 = in-turn", cols(ls[0]).why, "in-turn");
  eq("③ 둘째 줄 = woke", k.why, "woke");
  eq("③ 둘째 줄 seq = 921", k.seq, "921");
  eq("③ 둘째 줄 inTurn=0", k.inTurn, "0");
  eq("③ 둘째 줄 wakePending=1", k.wakePending, "1");
  eq("③ 깨움은 그대로 2회(세션 시작 + 턴 끝)", pi.calls.length, 2);
  await shutdown();
}
// ── ④ H3 상한 = 120줄 위에 1회 쓰면 50~100줄 · 마지막 줄 = 이번 상태 ───────────────
if (want(4)) {
  const c = setup("h4", [row(931)]);
  const wd = path.join(c.state, "pi-wake");
  fs.mkdirSync(wd, { recursive: true });
  fs.writeFileSync(whyFile(c), Array.from({ length: 120 }, (_, i) => `ts=${T0 - 200 + i} why=old seq=${i} n=1 inTurn=0 wakePending=0 uwin=0\n`).join(""));
  const pi = await load();
  await turnStart(pi); await poke(pi);
  const ls = whyLines(c), last = cols(ls.at(-1));
  eq("④ 줄 수 > 100 이면 마지막 50줄로", ls.length >= 50 && ls.length <= 100, true);
  eq("④ 마지막 줄 = 이번 상태(why)", last.why, "in-turn");
  eq("④ 마지막 줄 = 이번 상태(seq)", last.seq, "931");
  eq("④ 옛 줄이 남아 있음(전부 지움 0)", ls.length > 1 && /why=old/.test(ls[0]), true);
  await shutdown();
}
// ── ⑤ H1 uquiet 갈래 = 우편함을 안 읽으므로 seq=- n=- · uwin=1 ─────────────────────
if (want(5)) {
  const c = setup("h5", [row(941)]);
  const pi = await load();
  await pi.emit("user_bash", { command: "ls" }); // 오빠 `!` = 조용함 창 열림(기본 20000ms)
  await poke(pi); // 창 안 run() 1회
  const ls = whyLines(c), k = cols(ls.at(-1));
  eq("⑤ 창 안 = 1줄", ls.length, 1);
  eq("⑤ why=uquiet", k.why, "uquiet");
  eq("⑤ seq=- (우편함 읽기 전에 돌아섬)", k.seq, "-");
  eq("⑤ n=- (우편함 읽기 전에 돌아섬)", k.n, "-");
  eq("⑤ uwin=1", k.uwin, "1");
  eq("⑤ 창 안 = 깨움 0(r1555 불변)", pi.calls.length, 1); // 세션 시작 1회만
  await shutdown();
}
// ── ⑥ H4 불변 = .beat 1줄 꼴 그대로 · .why 쓰기 실패 = 깨움 영향 0 ──────────────────
if (want(6)) {
  const c = setup("h6", [row(951)]);
  fs.mkdirSync(path.join(c.state, "pi-wake", `${c.k}.why`), { recursive: true }); // .why 자리를 폴더로 = 쓰기 실패
  const pi = await load(); // 예외가 새어 나오면 여기서 죽는다
  await turnEnd(pi); // run() = .beat + .why(실패) — 깨움은 그대로
  eq("⑥ .why 쓰기 실패해도 깨움 1(턴 끝)", pi.calls.length, 2);
  const beat = fs.readFileSync(beatFile(c), "utf-8");
  eq("⑥ .beat = 1줄(덮어쓰기)", beat.split("\n").filter((l) => l.trim()).length, 1);
  eq("⑥ .beat 칸 꼴 그대로", /^event=\d+ check=\d+ why=\S+ inTurn=[01] wakePending=[01] watchers=\d+ rearm=\d+ woke=\d+\n$/.test(beat), true);
  eq("⑥ .beat 에 새 칸 없음(why 이력은 .why 몫)", /seq=|uwin=|\.why/.test(beat), false);
  await shutdown();
}
console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

mkdir -p "$T/ext" "$T/node_modules/@earendil-works/pi-coding-agent"
cp "$EXT" "$T/ext/ft-mbox-wake.ts"; cp "$HARNESS/pi/ft-load-line.ts" "$T/ext/"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
cat > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs" <<'SHIM'
export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0, cancelled: false, truncated: false }) });
SHIM
R2322_EXT="$T/ext/ft-mbox-wake.ts" R2322_SEAT="$SEAT" R2322_TMP="$T" timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
# ── ⑥ H4 회귀 = 기존 시험 8종 무회귀(기준판과 실패 이름 diff 0 = 실패 이름 0) ──────────────
if [ "${R2322_SKIP_REGRESS:-0}" != 1 ]; then
  for t in test_pi_mbox_wake_r1477.sh test_pi_mbox_wake_batch_r2169.sh test_pi_mbox_wake_recv_gate_r1669.sh \
           test_pi_mbox_wake_seat_only_r1634.sh test_pi_mbox_wake_self_r1529.sh test_pi_mbox_wake_self_wake_r2259.sh \
           test_pi_idle_nudge_r1530.sh test_pi_mbox_wake_quiet_aged_r2321.sh; do
    out="$(timeout 70 bash "$HERE/$t" 2>&1)"; brc=$?
    names="$(printf '%s\n' "$out" | grep -c '^FAIL')"
    if [ "$brc" != 0 ] || [ "$names" != 0 ]; then # 기존 시험의 타이밍 흐들림(r1529 변이 2 = 기준판도 1/8 실패 측정) = 딱 1회만 다시 돌려 가려낸다(숨김 0 · 기록 남김)
      out="$(timeout 70 bash "$HERE/$t" 2>&1)"; brc=$?; names="$(printf '%s\n' "$out" | grep -c '^FAIL')"
      [ "$brc" = 0 ] && [ "$names" = 0 ] && echo "NOTE ⑥ $t = 1회차 실패 · 2회차 통과(기존 시험 타이밍 흐들림 · 새 판과 무관)"
    fi
    if [ "$brc" = 0 ] && [ "$names" = 0 ]; then echo "PASS ⑥ 회귀 $t"; else echo "FAIL ⑥ 회귀 $t :: rc=$brc 실패이름=$names"; printf '%s\n' "$out" | grep '^FAIL' | head -3; rc=1; fi
  done
fi
echo "---"
if [ "$rc" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (rc=$rc)"; exit 1
