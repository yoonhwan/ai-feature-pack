#!/usr/bin/env bash
# test_pi_mbox_wake_quiet_aged_r2321.sh — r2321: 큐만(quiet) 미읽음이 «늙어» 유휴 좌석에 남으면 ft-mbox-wake 가 1회 깨운다
#  Q1 늙음 깨움 = ①⑥⑦ · Q2 1회 = ③④⑩ · Q3 늙음 타이머 = ②④ · Q4 ts 판독 = ⑤ · Q5 불변 = ⑧⑨ · 이미 깨운 옛 행은 안 셈(DA#38 ⓐ) = ④ M7
#  기준판(늙음 갈래 없음) = ① ⑦ Red. 격리 = r1529/r2259 꼴(임시 루트 · 합성 mailbox.jsonl · 가짜 pi · 스텁 mbox.sh · pi 패키지 스텁 · 실 우편함·실 pi 0).
#  시계 = FT_MBOX_NOW(소수 초) 고정 + 늙음 창(FT_MBOX_WAKE_QUIET_AGED_MS 밀리초) 짧게 — sleep 은 ② 의 실제 타이머 대기 1곳뿐(폴링).
#  ★TZ = Asia/Seoul 고정★ — ⑤ 는 «Z 없는 ts = 지역 시각» 을 재는 시험이라 실행기 TZ 에 흔들리면 안 된다.
#  R2321_EXT = 다른 확장 파일(기준판·변이)을 볼 때만 · R2321_CASES = 돌릴 시험 번호(기본 전부).
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R2321_EXT:-$HARNESS/pi/ft-mbox-wake.ts}"
SEAT="byz-harness-master-pi#2321"
export TZ="${R2321_TZ:-Asia/Seoul}"
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$EXT" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/r2321-aged.XXXXXX")"
trap 'rm -rf "$T"' EXIT

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const EXT = process.env.R2321_EXT, SEAT = process.env.R2321_SEAT, ROOT = process.env.R2321_TMP;
const CASES = (process.env.R2321_CASES || "1 2 3 4 5 6 7 8 9 10 11").split(/\s+/);
const want = (n) => CASES.includes(String(n));
const T0 = 1795000000; // 고정 «지금»(초) — 늙음 판정은 FT_MBOX_NOW 로 얼린다
const MIN = 60;
const isoT = (sec) => new Date(sec * 1000).toISOString(); // Z 붙은 글자 = 절대 시각
const localT = (sec) => { // Z 없는 «지역 시각» 글자 — ⑤ 가 이 꼴을 지역으로 읽는지 잰다
  const d = new Date(sec * 1000), p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
};
let modv = 0, fails = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const until = async (fn, ms = 2000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (fn()) return true; await wait(10); } return fn(); };
const keyOf = (s) => s.replace(/[^A-Za-z0-9._#-]/g, "_");

// row(seq, {ts, body, from, wake}) — ts 를 안 주면 칸 없음(⑥)
const row = (seq, o = {}) => { const r = { seq, to: SEAT, from: o.from ?? "room-tester-pi#45", body: o.body ?? "[정리] 심박" };
  if ("ts" in o) r.ts = o.ts; if ("wake" in o) r.wake_at = o.wake; return r; };

let cur = null;
function setup(name, rows, o = {}) {
  const dir = path.join(ROOT, name), base = path.join(dir, ".fable-team"), comm = path.join(base, "comm"), state = path.join(base, "state");
  fs.mkdirSync(comm, { recursive: true }); fs.mkdirSync(state, { recursive: true });
  fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify({ _master: SEAT, [SEAT]: { role: "master", agent: "pi" } }) + "\n");
  const budgetLog = path.join(dir, "budget.log");
  fs.writeFileSync(path.join(comm, "mbox.sh"), `#!/bin/bash\necho "$*" >> ${budgetLog}\n[ "${o.budgetRc ?? 0}" = 0 ] || exit ${o.budgetRc ?? 0}\nexit 0\n`);
  const mbox = path.join(comm, "mailbox.jsonl");
  fs.writeFileSync(mbox, rows.map((r) => JSON.stringify(r) + "\n").join(""));
  Object.assign(process.env, { FT_MBOX_ROOT: dir, FT_MBOX_STATE_DIR: state, FT_MBOX_FILE: mbox, FT_SEAT: SEAT,
    FT_MBOX_WAKE_DEBOUNCE_MS: "5", FT_MBOX_WAKE_REARM_MS: "86400000", FT_MBOX_NOW: String(T0) });
  if (o.agedMs !== undefined) process.env.FT_MBOX_WAKE_QUIET_AGED_MS = String(o.agedMs); else delete process.env.FT_MBOX_WAKE_QUIET_AGED_MS;
  if (o.realClock) delete process.env.FT_MBOX_NOW;
  cur = { dir, mbox, budgetLog, state, k: keyOf(SEAT) };
  return cur;
}
const appendRow = (c, r) => fs.appendFileSync(c.mbox, JSON.stringify(r) + "\n");
const budgetCalls = (c) => { try { return fs.readFileSync(c.budgetLog, "utf-8").split("\n").filter(Boolean).length; } catch { return 0; } };
const agedFile = (c) => path.join(c.state, "pi-wake", `${c.k}.aged`);
const seqOf = (pi) => Number((String(pi.calls.at(-1)?.content ?? "").match(/^\[발주 #(\d+)\]/) ?? [])[1] ?? -1);

const live = [];
async function load(o = {}) { // o.throwFirst = 첮 n회 sendMessage 를 던짐(배달 실패 쪽 검사)
  for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); }
  const pi = { calls: [], retired: false, h: {}, on(e, f) { (this.h[e] ??= []).push(f); },
    async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); },
    appendEntry() {}, sendMessage(m) { if (this.retired) return; if (o.throwFirst > 0) { o.throwFirst--; throw new Error("배달 실패(시험)"); } this.calls.push(m); } };
  live.push(pi);
  (await import(`${pathToFileURL(EXT).href}?v=${++modv}`)).default(pi);
  await pi.emit("session_start", {});
  return pi;
}
const poke = (pi) => pi.emit("agent_settled", {}); // 정상 settled = 재무장 + check 1회
const turnEnd = async (pi) => { await pi.emit("agent_start", {}); await pi.emit("agent_end", {}); }; // 깨움 소비 → 턴 끝(seq 표지 지움)
const shutdown = async () => { for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); } };

// ── ① Q1 늙은 큐만 1행 = 유휴 좌석 1회 깨움 ──────────────────────────────────────────
if (want(1)) {
  const c = setup("q1", [row(701, { ts: isoT(T0 - 16 * MIN) })]);
  const pi = await load();
  eq("① 늙은 [정리] 1행 = 깨움 1", pi.calls.length, 1);
  eq("① 발주 seq = 701(그 행)", seqOf(pi), 701);
  eq("① 예산 예약 1(늙음도 보통 깨움과 같은 길)", budgetCalls(c), 1);
  await shutdown();
}
// ── ② Q3 아직 안 늙음 = 0 · 늙는 시각에 타이머 1회 ───────────────────────────────────
if (want(2)) {
  const c = setup("q2", [row(711, { ts: isoT(Math.floor(Date.now() / 1000)) })], { agedMs: 2000, realClock: true }); // ts = 초 단위 글자(최대 999ms 과거) — 창 2000ms 면 «즉시 늙음» 이 아니다
  const pi = await load();
  eq("② 지금 온 [정리] = 즉시 깨움 0", pi.calls.length, 0);
  const woke = await until(() => pi.calls.length >= 1, 5000);
  eq("② 늙는 시각(2초) 타이머 = 깨움 1", woke && pi.calls.length, 1);
  eq("② 발주 seq = 711", seqOf(pi), 711);
  await wait(300); // 표지 뒤 한 번 더 흘린다(같은 seq 재깨움 0)
  eq("② 같은 seq 다시 0", pi.calls.length, 1);
  await shutdown();
}
// ── ③④⑩ Q2 1회(같은 seq 0) · 새 seq 1회 더 · agent_end·check(true) 가 표지를 안 지운다 ─
if (want(3) || want(4) || want(10)) {
  const c = setup("q3", [row(721, { ts: isoT(T0 - 30 * MIN) })]);
  const pi = await load();
  if (want(3)) {
    eq("③ 늙은 1행 = 깨움 1", pi.calls.length, 1);
    await poke(pi);
    eq("③ 같은 seq 재확인(seq 표지 있음) = 깨움 0", pi.calls.length, 1);
    await turnEnd(pi); // agent_end = writeSeq(null) — seq 표지를 버려도 늙음 표지(.aged)가 막는다
    eq("③ seq 표지 빈 뒤에도 같은 seq = 깨움 0(늙음 표지)", pi.calls.length, 1);
  }
  let p = pi;
  if (want(10)) {
    const f = agedFile(c), got = fs.existsSync(f) ? fs.readFileSync(f, "utf-8").trim() : "없음";
    eq("⑩ .aged = 일반 파일 1줄(seq)", got, "721");
    await poke(pi);
    eq("⑩ 표지 살아 있음(seq 파일 비었어도) = 깨움 0", pi.calls.length, 1);
    p = await load(); // 새 인스턴스 = session_start check(true)
    eq("⑩ check(true) 뒤에도 = 깨움 0", p.calls.length, 0);
  }
  await shutdown();
}
// ── ④ Q2·Q3 이미 깨운 옛 행은 안 셈 = 새 quiet 행(«지금»)은 바로 0 · 그 행 기준 900초 뒤 1 ─────
if (want(4)) {
  const c = setup("q4", [row(721, { ts: isoT(T0 - 30 * MIN) })]); // ① 꼴 = 늙은 1행을 먼저 깨운다
  const pi = await load();
  eq("④ (앞) 늙은 1행 = 깨움 1", pi.calls.length, 1);
  await turnEnd(pi); // 깨움 소비 + seq 표지 비움 — 표지(.aged)만으로 막히는 자리
  eq("④ 깨움 소비 뒤 추가 깨움 0(옛 행은 안 셈)", pi.calls.length, 1);
  appendRow(c, row(722, { ts: isoT(T0) })); // 카드 ④ = «지금» 온 새 quiet 행
  await poke(pi);
  eq("④ 새 quiet 행(지금 온) = 바로 깨움 0", pi.calls.length, 1);
  process.env.FT_MBOX_NOW = String(T0 + 901); // 새 행 ts + 900초
  await poke(pi);
  eq("④ 새 행 ts+900초 뒤 = 깨움 1", pi.calls.length, 2);
  eq("④ 발주 seq = 722(새 행)", seqOf(pi), 722);
  await poke(pi);
  eq("④ 그 seq 재확인 = 0", pi.calls.length, 2);
  await shutdown();
}
// ── ⑤ Q4 ts 판독 = Z 없는 글자 = «지역 시각»(UTC 로 읽으면 9시간 어긋난다) · 글자 꼴 아님 = 못 읽음 ─
if (want(5)) {
  const off = -new Date(T0 * 1000).getTimezoneOffset();
  eq(`⑤ 실행기 TZ = +${off / 60}시간 고정`, off, 540); // +09:00 이어야 아래 판별이 성립한다
  setup("q5a", [row(731, { ts: localT(T0 - 20 * MIN) })]); // 20분 전(지역 시각 글자) = 늙음
  const pa = await load();
  eq("⑤ Z 없는 ts 20분 전 = 지역 시각으로 읽어 깨움 1(UTC 로 읽으면 미래 = 0)", pa.calls.length, 1);
  eq("⑤ 발주 seq = 731", seqOf(pa), 731);
  await shutdown();
  setup("q5b", [row(732, { ts: "2026-11-20 07:00" })]); // ISO 꼴 아님 = 못 읽음
  const pb = await load();
  eq("⑤ 글자 ts(못 읽음) = 늙음 0", pb.calls.length, 0);
  await shutdown();
}
// ── ⑥ Q1 ts 칸 없음 = 늙음 판정 0(못 읽음은 안 늙는다) ─────────────────────────────
if (want(6)) {
  setup("q6", [row(741)]);
  const pi = await load();
  eq("⑥ ts 칸 없음 = 깨움 0", pi.calls.length, 0);
  await shutdown();
}
// ── ⑦ Q1 판정 기준 = «가장 오래된» quiet 행 · 깨움 seq = 최대 seq ────────────────────
if (want(7)) {
  setup("q7", [row(751, { ts: isoT(T0 - 60 * MIN) }), row(752, { ts: isoT(T0 - 1 * MIN) })]);
  const pi = await load();
  eq("⑦ 가장 오래된 1행이 늙음 = 깨움 1", pi.calls.length, 1);
  eq("⑦ 발주 seq = 752(최대 seq)", seqOf(pi), 752);
  await shutdown();
}
// ── ⑧ Q5 묶음(wake_at) 불변 = 아직 묶음인 행만 남으면 늙어도 0 ──────────────────────
if (want(8)) {
  const c = setup("q8", [row(761, { ts: isoT(T0 - 60 * MIN), wake: T0 + 900 })]);
  const pi = await load();
  eq("⑧ 묶음 중 늙은 quiet = 깨움 0", pi.calls.length, 0);
  eq("⑧ 예산 0(묶음 규칙 그대로)", budgetCalls(c), 0);
  await shutdown();
}
// ── ⑨ Q5 예산 규칙 불변 = 늙음도 예산 CLI 를 거친다(rc≠0 = 턴 0 + held 기록) ─────────
if (want(9)) {
  const c = setup("q9", [row(771, { ts: isoT(T0 - 60 * MIN) })], { budgetRc: 3 });
  const pi = await load();
  eq("⑨ 예산 막힘 = 늙어도 깨움 0", pi.calls.length, 0);
  eq("⑨ 예산 CLI 1회(불변)", budgetCalls(c), 1);
  const held = path.join(c.state, "doorbell-held", c.k);
  eq("⑨ held 기록(reason=budget)", fs.existsSync(held) && /reason=budget/.test(fs.readFileSync(held, "utf-8")), true);
  await shutdown();
}
// ── ⑪ 메모2 Q2 배달 실패 = 늙음 표지 0(다음 check 에서 다시 시도) ──────────────
if (want(11)) {
  const c = setup("q11", [row(781, { ts: isoT(T0 - 60 * MIN) })]);
  const pi = await load({ throwFirst: 1 });
  eq("⑪ 배달 실패 = 깨움 0", pi.calls.length, 0);
  eq("⑪ 배달 실패 = 늙음 표지 0", fs.existsSync(agedFile(c)), false);
  await poke(pi);
  eq("⑪ 다시 check = 깨움 1", pi.calls.length, 1);
  eq("⑪ 이번에 표지 기록 = 781", fs.existsSync(agedFile(c)) ? fs.readFileSync(agedFile(c), "utf-8").trim() : "없음", "781");
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
R2321_EXT="$T/ext/ft-mbox-wake.ts" R2321_SEAT="$SEAT" R2321_TMP="$T" timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
if [ "$rc" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (node_rc=$rc)"; exit 1
