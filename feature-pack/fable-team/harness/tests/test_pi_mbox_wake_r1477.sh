#!/usr/bin/env bash
# test_pi_mbox_wake_r1477.sh — r1477: pi 확장 ft-mbox-wake 단위 시험(T1~T11)
#  격리: 임시 루트(<케이스>/.fable-team/{comm,state}) · 합성 mailbox.jsonl · 가짜 pi 객체(sendMessage 기록) ·
#        스텁 mbox.sh(budget reserve rc 제어 · 호출 기록) · FT_MBOX_NOW 로 가짜 시계. 실 우편함·실 pi 세션 0.
#  T7 만 실 r1476 `mbox.sh sweep` 를 부른다(발행 주체 실제 · 확장이 touch 하지 않는다).
#  T1 시작 회수(잔존 2행 = 턴 1) · T2 실시간 도착 1턴 · T3 to 필터 · T4 중복 0 + agent_end 재확인
#  T5 2행 도착 = 큐 1 + ACK 1 · T6 우편함 없음 = ERROR 1줄 + 폴링 0 · T7 예산 rc3 → held → sweep nudge → 1턴(재예약 0)
#  T8 보고 전용 무음 / [긴급] 예산 밖 · T9 원자 교체 2회 모두 감지 · T10 recv 전 재시작도 회수 · T11 활성 결속
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="$HARNESS/pi/ft-mbox-wake.ts"
COMM="$HARNESS/comm/mbox.sh"
SEAT="${R1477_SEAT:-byz-planner-master-pi#244}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

[ -f "$COMM" ] || { echo "FAIL 선행 없음 — r1476 착지본 $COMM"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
if [ ! -f "$EXT" ]; then echo "FAIL 확장 없음 $EXT"; exit 1; fi

# ── 정적 계약(완료 조건) ──────────────────────────────────────────────────────────────
eq "S1 확장 ≤120줄" "$([ "$(wc -l < "$EXT" | tr -d ' ')" -le 120 ] && echo yes || echo no)" yes
eq "S2 setInterval 0" "$(grep -c 'setInterval' "$EXT")" 0
eq "S3 send-keys 0(타이핑 주입)" "$(grep -c 'send-keys' "$EXT")" 0
bash -n "$0" && ok "S4 bash -n rc0" || bad "S4 bash -n rc0"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1477-wake.XXXXXX")"
trap 'rm -rf "$T"' EXIT

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const EXT = process.env.R1477_EXT, COMM = process.env.R1477_COMM;
const SEAT = process.env.R1477_SEAT, ROOT = process.env.R1477_TMP;
let fails = 0, modv = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const keyOf = (s) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
const row = (seq, to, body) => JSON.stringify({ seq, ts: "2026-11-09T00:00:00", to, from: "test-sender", body });
const append = (f, ...rows) => fs.appendFileSync(f, rows.map((r) => r + "\n").join(""));
const replace = (f, ...rows) => { const t = `${f}.tmp`; fs.writeFileSync(t, rows.map((r) => r + "\n").join("")); fs.renameSync(t, f); };
const lines = (f) => { try { return fs.readFileSync(f, "utf-8").split("\n").filter((l) => l.trim()).length; } catch { return 0; } };

function setup(name, { master = SEAT, seat = SEAT } = {}) {
  const dir = path.join(ROOT, name);
  const base = path.join(dir, ".fable-team");
  const comm = path.join(base, "comm"), state = path.join(base, "state");
  fs.mkdirSync(comm, { recursive: true });
  fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify({ _master: master }) + "\n");
  fs.writeFileSync(path.join(base, "seats.json"), JSON.stringify({ [SEAT]: { team: "planner", tick: 0 } }) + "\n");
  const stubLog = path.join(dir, "stub.log");
  const stub = ["#!/bin/bash", `echo "$*" >> ${JSON.stringify(stubLog)}`,
    'case "$*" in *"budget reserve"*) exit "${STUB_RC:-0}" ;; esac', "exit 0", ""].join("\n");
  fs.writeFileSync(path.join(comm, "mbox.sh"), stub);
  Object.assign(process.env, {
    FT_MBOX_ROOT: dir, FT_MBOX_STATE_DIR: state, FT_MBOX_FILE: path.join(comm, "mailbox.jsonl"),
    FT_SEAT: seat, FT_MBOX_WAKE_DEBOUNCE_MS: "5",
  });
  delete process.env.STUB_RC;
  return { dir, comm, state, mbox: path.join(comm, "mailbox.jsonl"), stubLog,
    seqFile: path.join(state, "pi-wake", `${keyOf(seat)}.seq`),
    nudge: path.join(state, "pi-wake", `${keyOf(seat)}.nudge`),
    held: path.join(state, "doorbell-held", keyOf(seat)),
    seats: path.join(base, "seats.json") };
}

function capture() { const buf = []; const orig = console.error; console.error = (...a) => buf.push(a.map(String).join(" ")); return { buf, stop: () => { console.error = orig; } }; }

async function load() {
  const pi = { calls: [], retired: false, h: {}, on(e, f) { (this.h[e] ??= []).push(f); },
    async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); },
    sendMessage(m, o) { if (!this.retired) this.calls.push({ m, o }); } };
  const mod = await import(`${pathToFileURL(EXT).href}?v=${++modv}`);
  mod.default(pi);
  await pi.emit("session_start", {});
  return pi;
}

// ── T1 시작 회수: 잔존 2행(seq 5·6) · seq 파일 7 → 턴 1회 · seq 파일 6 ────────────────────────
{
  const c = setup("t1");
  append(c.mbox, row(5, SEAT, "[발주 #5] a"), row(6, SEAT, "[발주 #6] b"), row(7, "byz-planner-da#0", "남"));
  fs.mkdirSync(path.dirname(c.seqFile), { recursive: true });
  fs.writeFileSync(c.seqFile, "7\n");
  const pi = await load();
  eq("T1 잔존 2행 = 턴 1", pi.calls.length, 1);
  eq("T1 본문 최대 seq", /^\[발주 #6\] bash .*mbox\.sh recv byz-planner-master-pi#244 /.test(pi.calls[0]?.m?.content ?? ""), true);
  eq("T1 triggerTurn/followUp", `${pi.calls[0]?.o?.triggerTurn}/${pi.calls[0]?.o?.deliverAs}`, "true/followUp");
  eq("T1 예산 1회", lines(c.stubLog), 1);
  eq("T1 seq 파일 = 6", fs.readFileSync(c.seqFile, "utf-8").trim(), "6");
}
// ── T2 실행 중 도착: append 1행 → 1턴 · 본문 꼴 ─────────────────────────────────────────────
{
  const c = setup("t2");
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  eq("T2 시작 시 턴 0", pi.calls.length, 0);
  append(c.mbox, row(8, SEAT, "[발주 #8] 실행 중"));
  await wait(120);
  eq("T2 도착 = 턴 1", pi.calls.length, 1);
  eq("T2 본문 꼴", /^\[발주 #8\] bash .*\/comm\/mbox\.sh recv byz-planner-master-pi#244 — 실행하고 그 안의 지시를 즉시 착수하라$/.test(pi.calls[0]?.m?.content ?? ""), true);
  eq("T2 customType/display", `${pi.calls[0]?.m?.customType}/${pi.calls[0]?.m?.display}`, "ft-mbox/true");
}
// ── T3 to 필터: 남의 좌석 행 = 턴 0 · seq 파일 불변 ─────────────────────────────────────────
{
  const c = setup("t3");
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  append(c.mbox, row(9, "byz-planner-da#0", "[발주 #9] 남"));
  await wait(120);
  eq("T3 남 좌석 = 턴 0", pi.calls.length, 0);
  eq("T3 seq 파일 없음", fs.existsSync(c.seqFile), false);
  eq("T3 예산 0", lines(c.stubLog), 0);
}
// ── T4 중복 0: 같은 행 재기록 → 0 · agent_end 뒤 잔존 → 1회 더 ──────────────────────────────
{
  const c = setup("t4");
  append(c.mbox, row(10, SEAT, "[발주 #10] 미소비"));
  const pi = await load();
  eq("T4 최초 1턴", pi.calls.length, 1);
  replace(c.mbox, row(10, SEAT, "[발주 #10] 미소비"));
  await wait(120);
  eq("T4 같은 seq 재기록 = 턴 0", pi.calls.length, 1);
  await pi.emit("agent_end", {});
  eq("T4 agent_end 재확인 = +1", pi.calls.length, 2);
}
// ── T5 2행 도착 = 큐 1 · agent_end ACK = +1 ───────────────────────────────────────────────
{
  const c = setup("t5");
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  append(c.mbox, row(11, SEAT, "[발주 #11] x"), row(12, SEAT, "[발주 #12] y"));
  await wait(120);
  eq("T5 2행 = 턴 1", pi.calls.length, 1);
  eq("T5 최대 seq 로 깨움", /^\[발주 #12\] /.test(pi.calls[0]?.m?.content ?? ""), true);
  await pi.emit("agent_end", {});
  eq("T5 ACK 재확인 = +1", pi.calls.length, 2);
}
// ── T6 우편함 없음: ERROR 1줄 · 폴링 0(watch 없음) ────────────────────────────────────────
{
  const c = setup("t6");
  const cap = capture();
  const pi = await load();
  cap.stop();
  eq("T6 ERROR 1줄", cap.buf.filter((l) => l.startsWith("ERROR ft-mbox-wake:")).length, 1);
  eq("T6 턴 0", pi.calls.length, 0);
  append(c.mbox, row(13, SEAT, "[발주 #13] 뒤늦게 생긴 우편함"));
  await wait(120);
  eq("T6 watch 없음 = 이후 턴 0", pi.calls.length, 0);
  eq("T6 예산 0", lines(c.stubLog), 0);
}
// ── T7 예산 rc3 → held → 실 r1476 sweep → nudge → 1턴(재예약 0) ───────────────────────────
{
  const c = setup("t7");
  append(c.mbox, row(20, SEAT, "[발주 #20] 예산 소진"));
  process.env.STUB_RC = "3";
  const pi = await load();
  eq("T7 소진 = 턴 0", pi.calls.length, 0);
  const held = fs.existsSync(c.held) ? fs.readFileSync(c.held, "utf-8") : "";
  eq("T7 held reason=budget", /reason=budget/.test(held), true);
  eq("T7 held seq=20", /(^|\n)seq=20(\n|$)/.test(held), true);
  eq("T7 예산 스텁 1회", lines(c.stubLog), 1);
  delete process.env.STUB_RC;
  const ts = Number((held.match(/ts=(\d+)/) ?? [])[1] ?? 0);
  const out = execFileSync("bash", [COMM, "sweep"], { encoding: "utf-8", env: {
    ...process.env, FT_MBOX_NOW: String(ts + 3700), FT_SEATS_JSON: c.seats, FT_MBOX_STATE_DIR: c.state } });
  eq("T7 sweep followup=... via=nudge", out.includes(`followup=${SEAT} via=nudge`), true);
  eq("T7 nudge 생성", fs.existsSync(c.nudge), true);
  await wait(200);
  eq("T7 nudge 수신 = 턴 1", pi.calls.length, 1);
  eq("T7 nudge 안 seq 로 깨움", /^\[발주 #20\] /.test(pi.calls[0]?.m?.content ?? ""), true);
  eq("T7 예약 재호출 0(이중 차감 0)", lines(c.stubLog), 1);
  eq("T7 nudge 삭제", fs.existsSync(c.nudge), false);
}
// ── T8 보고 전용 무음 · [긴급] 예산 밖 ───────────────────────────────────────────────────
{
  const c = setup("t8a");
  append(c.mbox, row(30, SEAT, "[정리] 심박"));
  const pi = await load();
  eq("T8a [정리] = 턴 0", pi.calls.length, 0);
  eq("T8a [정리] = 예산 0", lines(c.stubLog), 0);
  append(c.mbox, row(31, SEAT, "[발주 #31] 일반"));
  await wait(120);
  eq("T8a 일반 1행 = 턴 1", pi.calls.length, 1);
  eq("T8a 일반 = 예산 1", lines(c.stubLog), 1);
  const c2 = setup("t8b");
  append(c2.mbox, row(40, SEAT, "[긴급] 지금"));
  const pi2 = await load();
  eq("T8b [긴급] = 턴 1", pi2.calls.length, 1);
  eq("T8b [긴급] = 예산 0", lines(c2.stubLog), 0);
}
// ── T9 원자 교체 2회 모두 감지(os.replace · inode 변화) ──────────────────────────────────
{
  const c = setup("t9");
  replace(c.mbox, row(50, SEAT, "[발주 #50] a"));
  const pi = await load();
  eq("T9 첫 교체 = 턴 1", pi.calls.length, 1);
  replace(c.mbox, row(50, SEAT, "[발주 #50] a"), row(51, SEAT, "[발주 #51] b"));
  await wait(150);
  eq("T9 inode 교체 뒤 두 번째 = 턴 2", pi.calls.length, 2);
  eq("T9 두 번째 본문 seq 51", /^\[발주 #51\] /.test(pi.calls[1]?.m?.content ?? ""), true);
}
// ── T10 recv 전 재시작: 같은 행으로 회수 1회 더 ──────────────────────────────────────────
{
  const c = setup("t10");
  append(c.mbox, row(60, SEAT, "[발주 #60] recv 전"));
  const pi1 = await load();
  eq("T10 첫 프로세스 = 턴 1", pi1.calls.length, 1);
  pi1.retired = true;
  const pi2 = await load();
  eq("T10 재시작 회수 = 턴 1(seq 파일 무관)", pi2.calls.length, 1);
}
// ── T11 활성 결속: FT_SEAT != _master = inactive · watch 0 ───────────────────────────────
{
  const c = setup("t11", { master: "byz-other-pi#1" });
  fs.writeFileSync(c.mbox, "");
  const cap = capture();
  const pi = await load();
  cap.stop();
  eq("T11 inactive 1줄", cap.buf.filter((l) => l.includes("inactive")).length, 1);
  append(c.mbox, row(70, SEAT, "[발주 #70] 무시"));
  await wait(120);
  eq("T11 비활성 = 턴 0", pi.calls.length, 0);
  eq("T11 비활성 = 예산 0", lines(c.stubLog), 0);
  const c2 = setup("t11b");
  append(c2.mbox, row(71, SEAT, "[발주 #71] 활성"));
  const pi2 = await load();
  eq("T11 _master 일치 = 활성 1턴", pi2.calls.length, 1);
}

console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

R1477_EXT="$EXT" R1477_COMM="$COMM" R1477_SEAT="$SEAT" R1477_TMP="$T" \
  timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
if [ "$rc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc)"; exit 1
