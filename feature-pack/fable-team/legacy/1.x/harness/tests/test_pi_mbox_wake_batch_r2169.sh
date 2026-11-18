#!/usr/bin/env bash
# test_pi_mbox_wake_batch_r2169.sh — r2169 W4 · W5 · W6: ft-mbox-wake 가 큐 행의 wake_at(정수 epoch 초)을 본다.
#   «아직 묶음»(wake_at > 지금) 행과 QUIET 머리 행뿐 = 깨움 0 · 예산 0 · held 0 · seq 불변 · 가장 이른 wake_at 에 check 1회 타이머(좌석당 1개 · 주기 0)
#   시각이 지난 wake_at 행 = 깨움 사유(예산 예약 · [긴급] 이어도 loud 아님) · 칸 없는 행 = 지금 그대로 · 미읽음 8행 이상 = 묶음 행도 시각이 지난 행
#   wake_at 이 정수가 아님 · 음수 · 지금+3600초 초과 = 칸 없는 행 · 턴 도중 = 깨움 0 → agent_end 1 · session_shutdown 이 타이머를 끈다
#  사례 ⑫~⑲(카드 r2169 반례 집합) · 격리: 임시 루트 · 합성 seats-planner.json · 가짜 pi(sendMessage 기록) · 가짜 시계(setTimeout 교체 · sleep 0) · 예산 CLI 대역 · 실 우편함 · 실 tmux · 실 pi 창 0.
#  env: R2169_WAKE = 다른 확장 파일(기준판 Red · 변이) · R2169_CASES = "12 13" 처럼 일부만.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
WAKE="${R2169_WAKE:-$HARNESS/pi/ft-mbox-wake.ts}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$WAKE" ] || { echo "FAIL 확장 없음 $WAKE"; exit 1; }
eq "S1 ft-mbox-wake ≤240줄" "$([ "$(wc -l < "$WAKE" | tr -d ' ')" -le 240 ] && echo yes || echo no)" yes
eq "S2 주기 타이머 0(setInterval)" "$(grep -c 'setInterval' "$WAKE")" 0

T="$(mktemp -d "${TMPDIR:-/tmp}/r2169-batch.XXXXXX")"
trap 'rm -rf "$T"' EXIT
cp "$WAKE" "$T/ext-ft-mbox-wake.ts"; cp "$HARNESS/pi/ft-load-line.ts" "$T/"
mkdir -p "$T/node_modules/@earendil-works/pi-coding-agent"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
printf 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0 }) });\n' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
const TMP = process.env.R2169_TMP, WAKE = process.env.R2169_WAKE, SEAT = "byz-hrd-master-pi#1", N0 = 1763340000;
const CASES = (process.env.R2169_CASES || "12 13 14 15 16 17 18 19").split(/\s+/);
const want = (n) => CASES.includes(String(n));
const keyOf = (s) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
let fails = 0, modv = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
// ★가짜 시계★ — ms 단위(FT_MBOX_NOW = 소수 초 · 실 시계와 같은 꼴) · 확장의 nowS(FT_MBOX_NOW)도 같이 옮긴다 · sleep 0 · due 타이머를 시각 순서로
const OTHER_MS = new Set([5, 255, 86400000]); // 바운스 · 기동 창 · 재무장(아주 김) = 묶음 타이머 아님
let now = 0, next = 1, timers = new Map(), maxBatch = 0;
const setNow = (ms) => { now = ms; process.env.FT_MBOX_NOW = String(N0 + ms / 1000); };
const batch = () => [...timers.values()].filter((v) => !OTHER_MS.has(v.ms));
globalThis.setTimeout = (fn, ms) => { const id = next++; timers.set(id, { fn, due: now + Number(ms), ms: Number(ms) }); maxBatch = Math.max(maxBatch, batch().length); return id; };
globalThis.clearTimeout = (id) => { timers.delete(id); };
function advance(ms) {
  const end = now + ms;
  for (;;) { const xs = [...timers].filter(([, v]) => v.due <= end).sort((a, b) => a[1].due - b[1].due); if (!xs.length) break; const [id, v] = xs[0]; timers.delete(id); setNow(v.due); v.fn(); }
  setNow(end);
}
console.error = () => {};
let cur = null;
function setup(name) {
  timers.clear(); setNow(0); maxBatch = 0;
  const root = path.join(TMP, name), base = path.join(root, ".fable-team"), comm = path.join(base, "comm"), state = path.join(base, "state");
  fs.mkdirSync(comm, { recursive: true }); fs.mkdirSync(state, { recursive: true });
  fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify({ _master: SEAT, [SEAT]: { agent: "pi" } }) + "\n");
  const mbox = path.join(comm, "mailbox.jsonl"), budget = path.join(root, "budget.log");
  fs.writeFileSync(mbox, "");
  fs.writeFileSync(path.join(comm, "mbox.sh"), `#!/bin/bash\necho "$*" >> ${budget}\nexit 0\n`);
  Object.assign(process.env, { FT_MBOX_ROOT: root, FT_MBOX_FILE: mbox, FT_MBOX_STATE_DIR: state, FT_SEAT: SEAT, FT_MBOX_WAKE_DEBOUNCE_MS: "5", FT_MBOX_WAKE_REARM_MS: "86400000" });
  const k = keyOf(SEAT);
  cur = { mbox, budget, seqf: path.join(state, "pi-wake", `${k}.seq`), heldf: path.join(state, "doorbell-held", k), seq: 100 };
  return cur;
}
// row(c, {wake, body, from}) — 내 좌석 앞 1행 추가 · wake === undefined = 칸 없음
const row = (c, o = {}) => { const r = { seq: ++c.seq, ts: "2026-11-17T10:00:00", to: SEAT, from: o.from ?? "ft-stall-scan", body: o.body ?? "[멈춤] 팀장 심박 없음" }; if ("wake" in o) r.wake_at = o.wake; fs.appendFileSync(c.mbox, JSON.stringify(r) + "\n"); return r.seq; };
const held = (c, s) => row(c, { wake: N0 + s }); // s 초 뒤 «아직 묶음»
const drain = (c) => fs.writeFileSync(c.mbox, "");
const budget = (c) => { try { return fs.readFileSync(c.budget, "utf-8").split("\n").filter(Boolean).length; } catch { return 0; } };
const sends = (pi) => pi.calls.filter((x) => String(x.m?.content ?? "").startsWith("[발주 #"));
const live = [];
async function load() {
  for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); }
  const pi = { calls: [], retired: false, h: {}, on(e, f) { (this.h[e] ??= []).push(f); }, registerCommand() {}, appendEntry() {},
    async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); },
    sendMessage(m, o) { if (!this.retired) pi.calls.push({ m, o }); }, sendUserMessage() {} };
  live.push(pi);
  (await import(`${pathToFileURL(WAKE).href}?v=${++modv}`)).default(pi);
  await pi.emit("session_start", {});
  advance(1000); // 기동 창 1회 재확인(fallback)까지 흘린다 — 묶음 타이머는 그 check 에서 다시 잰다(시각은 같은 wake_at)
  return pi;
}
const poke = (pi) => pi.emit("agent_settled", {}); // 정상 settled = check 1회(감시 사건 대신 · 실 I/O 대기 0)
const turnEnd = async (pi) => { await pi.emit("agent_start", {}); await pi.emit("agent_end", {}); }; // 깨움 배달 → 턴 끝 = 다음 check

if (want(12) || want(13)) {
  const c = setup("p12"); const s = held(c, 900); const pi = await load();
  eq("⑫ wake_at(NOW+900) 행 1개 → sendMessage 0", sends(pi).length, 0);
  eq("⑫ 예산 CLI 호출 0", budget(c), 0);
  eq("⑫ held 파일 0 · seq 파일 불변(없음)", `${fs.existsSync(c.heldf)} ${fs.existsSync(c.seqf)}`, "false false");
  eq("⑫ 묶음 타이머 1개 = 900초 시각(NOW+900)", batch().map((v) => v.due).join(","), "900000");
  if (want(13)) {
    advance(-1000 + 900000);
    eq("⑬ 시계 NOW+900 · 타이머 실행 → 깨움 1회", sends(pi).length, 1);
    eq("⑬ 본문의 seq = 그 행", sends(pi)[0]?.m?.content.includes(`#${s}]`), true);
    eq("⑬ 예산 예약 1회", budget(c), 1);
  }
}
if (want(14)) {
  const c = setup("p14"); held(c, 900); const pi = await load();
  row(c, { from: "byz-hrd-arch-pi#4", body: "회신 부탁" }); await poke(pi);
  eq("⑭ 칸 없는 좌석 쪽지 도착 → 즉시 깨움 1", sends(pi).length, 1);
  drain(c); await turnEnd(pi); advance(-1000 + 900000);
  eq("⑭ 큐 비운 뒤 타이머 시각 → 깨움 0(합 1)", sends(pi).length, 1);
}
if (want(15)) {
  const c = setup("p15"); held(c, 300); held(c, 600); held(c, 900); const pi = await load();
  eq("⑮ wake_at 3개 → 걸린 묶음 타이머 1개 = 300초 시각", batch().map((v) => v.due).join(","), "300000");
  advance(-1000 + 300000);
  eq("⑮ 실행 → 깨움 1회", sends(pi).length, 1);
  drain(c); await turnEnd(pi);
  eq("⑮ 큐 비운 뒤 남은 묶음 타이머 0", batch().length, 0);
  const d = setup("p15b"); row(d, { body: "[정리] 끝난 일 1줄" }); held(d, 900); const pj = await load();
  eq("⑮ QUIET 머리 행 + «아직 묶음» 행만 → 깨움 0", sends(pj).length, 0);
}
if (want(16)) {
  const c = setup("p16"); row(c, { body: "[긴급] 배정 막힘", from: "ft-idle-scan", wake: N0 + 900 }); const pi = await load();
  eq("⑯ [긴급] + 미래 wake_at 행만 → 깨움 0", sends(pi).length, 0);
  advance(-1000 + 900000);
  eq("⑯ 시각이 지난 뒤 → 깨움 1 · 예산 예약 1(면제 아님)", `${sends(pi).length} ${budget(c)}`, "1 1");
  const d = setup("p16b"); row(d, { body: "[긴급] 배정 막힘", from: "ft-idle-scan" }); const pj = await load();
  eq("⑯ [긴급] 칸 없는 행 → 즉시 깨움 · 예산 0(기준판과 같음)", `${sends(pj).length} ${budget(d)}`, "1 0");
}
if (want(17)) {
  for (const [n, v] of [["\"x\"", "x"], ["-1", -1], ["1.5", 1.5], ["null", null], ["NOW+3601", N0 + 3601]]) {
    const c = setup(`p17-${n.replace(/\W/g, "_")}`); row(c, { wake: v }); const pi = await load();
    eq(`⑰ wake_at=${n} → 즉시 깨움 · 묶음 타이머 0`, `${sends(pi).length} ${batch().length}`, "1 0");
  }
}
if (want(18)) {
  const c = setup("p18"); held(c, 900); const pi = await load();
  await pi.emit("agent_start", {}); advance(-1000 + 900000);
  eq("⑱ 턴 도중 타이머 실행 → 깨움 0", sends(pi).length, 0);
  await pi.emit("agent_end", {});
  eq("⑱ agent_end 뒤 → 깨움 1", sends(pi).length, 1);
  const d = setup("p18b"); held(d, 900); const pj = await load();
  await pj.emit("session_shutdown", {}); advance(-1000 + 900000);
  eq("⑱ session_shutdown 뒤 타이머 실행 → 깨움 0 · 남은 묶음 타이머 0", `${sends(pj).length} ${batch().length}`, "0 0");
  eq("⑱ 어느 사례에서도 걸린 묶음 타이머 ≤ 1", maxBatch <= 1, true);
}
if (want(19)) {
  const c = setup("p19"); for (let i = 1; i <= 7; i++) held(c, 900 + i); const pi = await load();
  eq("⑲ «아직 묶음» 7행 → 깨움 0", sends(pi).length, 0);
  held(c, 950); await poke(pi);
  eq("⑲ 8번째 «아직 묶음» 행 도착 → 깨움 1 · 예산 예약 1", `${sends(pi).length} ${budget(c)}`, "1 1");
  const d = setup("p19b"); for (let i = 0; i < 5; i++) held(d, 900); for (let i = 0; i < 3; i++) row(d, { body: "[회신] ok" }); const pj = await load();
  eq("⑲ «아직 묶음» 5 + QUIET 머리 3 → 깨움 1", sends(pj).length, 1);
  const e = setup("p19c"); for (let i = 0; i < 4; i++) held(e, 900); for (let i = 0; i < 3; i++) row(e, { body: "[회신] ok" }); const pk = await load();
  eq("⑲ «아직 묶음» 4 + QUIET 머리 3 → 깨움 0", sends(pk).length, 0);
}
for (const p of live.splice(0)) await p.emit("session_shutdown", {});
console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

R2169_WAKE="$T/ext-ft-mbox-wake.ts" R2169_TMP="$T" timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
if [ "$rc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc)"; exit 1
