#!/usr/bin/env bash
# test_pi_mbox_wake_r1477.sh — r1477: pi 확장 ft-mbox-wake 단위 시험(T1~T11)
#  격리: 임시 루트(<케이스>/.fable-team/{comm,state}) · 합성 mailbox.jsonl · 가짜 pi 객체(sendMessage 기록) ·
#        스텁 mbox.sh(budget reserve rc 제어 · 호출 기록) · FT_MBOX_NOW 로 가짜 시계. 실 우편함·실 pi 세션 0.
#  T7 만 실 r1476 `mbox.sh sweep` 를 부른다(발행 주체 실제 · 확장이 touch 하지 않는다).
#  T1 시작 회수(잔존 2행 = 턴 1) · T2 실시간 도착 1턴 · T3 to 필터 · T4 중복 0 + agent_end 재확인
#  T5 2행 도착 = 큐 1 + ACK 1 · T6 우편함 없음 = ERROR 1줄 + 폴링 0 · T7 예산 rc3 → held → sweep nudge → 1턴(재예약 0)
#  T8 보고 전용 무음 / [긴급] 예산 밖 · T9 원자 교체 2회 모두 감지 · T10 recv 전 재시작도 회수 · T11 활성 결속
#  T12 사람 발신(slack-*/_master) = 예산 밖 즉시(DA HOLD R2) · T13 지원 우편함(FT_MBOX_FILE 다른 루트) = 입력·감시·recv 결속(DA HOLD R1)
#  T14 지정 우편함에 CLI 가 없으면 루트 것을 빌리고 recv 대상을 FT_MBOX_DIR 로 밝힌다(DA HOLD R1 두 번째 꼴)
#  T15 session_shutdown = 감시 해제(옛 인스턴스가 같은 우편함을 2중으로 깨우지 않는다)
#  T17 _master 승계: 로드 뒤 좌석 표식이 바뀌면 다음 쪽지에 활성(매 이벤트 재확인 · 18:24 desk #276401)
#  T18 시작 직후(기동 창) 사건은 «사건» 으로 바로 깨운다(1회 재확인에 기대지 않는다)
#  T19 user_bash 훅: `! bash /tmp/hN` 이 끝나면 custom 턴 1회(rc·출력 그대로) · T20 그 밖의 명령 = 훅 0
#  T21 훅 알림 실패 = bash 결과 불변(ERROR 1줄) · T22 활성 = _master + _desk(desk 좌석도 planner 대면)
#  T23 비활성 좌석 = user_bash 훅 0 · T24 !! (excludeFromContext) = 훅 0 · T25 알림은 «결과 기록 뒤»(exec 반환 뒤 1회)
#  T16 FT_MBOX_ROOT 미지정 + cwd = git 워크트리 → root = git 공용 루트(실측 FAIL 보정 · 18:20 planner pi#245)
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R1477_EXT:-$HARNESS/pi/ft-mbox-wake.ts}"
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
# 상한 = 140줄(카드 «고칠 안» 값) — master #276564 가 ③_desk 활성 + ④user_bash 훅을 같은 보정에 합치며 120 초과를 허용(1줄 보고 의무).
eq "S1 확장 $(wc -l < "$EXT" | tr -d ' ')줄 ≤140" "$([ "$(wc -l < "$EXT" | tr -d ' ')" -le 140 ] && echo yes || echo no)" yes
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
// 사건 전달은 비동기 — «깨움이 일어났는가» 를 상한 600ms 안에서 확인한다(사건 유실이면 FAIL 그대로).
const until = async (fn, ms = 600) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (fn()) return true; await wait(10); } return fn(); };
const keyOf = (s) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
const row = (seq, to, body) => JSON.stringify({ seq, ts: "2026-11-09T00:00:00", to, from: "test-sender", body });
const append = (f, ...rows) => fs.appendFileSync(f, rows.map((r) => r + "\n").join(""));
const replace = (f, ...rows) => { const t = `${f}.tmp`; fs.writeFileSync(t, rows.map((r) => r + "\n").join("")); fs.renameSync(t, f); };
const lines = (f) => { try { return fs.readFileSync(f, "utf-8").split("\n").filter((l) => l.trim()).length; } catch { return 0; } };

function setup(name, { master = SEAT, seat = SEAT, mboxRoot = null } = {}) {
  const dir = path.join(ROOT, name);
  const base = path.join(dir, ".fable-team");
  // mboxRoot = 우편함이 «다른 데이터 루트» 에 있는 경우(FT_MBOX_FILE 지원 경로 · DA HOLD R1)
  const comm = path.join(mboxRoot ? path.join(dir, mboxRoot) : dir, ".fable-team", "comm");
  const state = path.join(base, "state");
  fs.mkdirSync(base, { recursive: true });
  fs.mkdirSync(comm, { recursive: true });
  fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify({ _master: master }) + "\n");
  fs.writeFileSync(path.join(base, "seats.json"), JSON.stringify({ [SEAT]: { team: "planner", tick: 0 } }) + "\n");
  const stubLog = path.join(dir, "stub.log");
  const stub = ["#!/bin/bash", `echo "$*" >> ${JSON.stringify(stubLog)}`,
    'case "$*" in *"budget reserve"*) exit "${STUB_RC:-0}" ;; esac', "exit 0", ""].join("\n");
  fs.writeFileSync(path.join(comm, "mbox.sh"), stub);
  if (mboxRoot) { fs.mkdirSync(path.join(base, "comm"), { recursive: true }); fs.writeFileSync(path.join(base, "comm", "mbox.sh"), stub); }
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

const live = [];
async function load() {
  for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); } // 앞 케이스 감시 해제
  const pi = { calls: [], retired: false, h: {}, on(e, f) { (this.h[e] ??= []).push(f); },
    async emit(e, ev = {}) { let out; for (const f of this.h[e] ?? []) { const r = await f(ev, { isIdle: () => true }); if (r !== undefined && out === undefined) out = r; } return out; }, // 핸들러 반환값(user_bash = operations) 전달
    throwOnSend: false,
    sendMessage(m, o) { if (this.throwOnSend) throw new Error("boom"); if (!this.retired) this.calls.push({ m, o }); } };
  live.push(pi);
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
  await until(() => pi.calls.length >= 1);
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
  await until(() => pi.calls.length >= 1);
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
  await until(() => pi.calls.length >= 1);
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
  await until(() => pi.calls.length >= 2);
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

// ── T12 사람 발신 = 예산 밖 즉시(DA HOLD R2) ─────────────────────────────────────────────
{
  const c = setup("t12");
  append(c.mbox, JSON.stringify({ seq: 80, ts: "2026-11-09T00:00:00", to: SEAT, from: "slack-yoonhwan", body: "이거 좀 봐줘" }));
  process.env.STUB_RC = "3"; // 예산이 소진돼 있어도 사람 글은 지나가야 한다
  const pi = await load();
  eq("T12 사람 글 = 턴 1(예산 소진 무관)", pi.calls.length, 1);
  eq("T12 사람 글 = 예약 0", lines(c.stubLog), 0);
  eq("T12 사람 글 = held 0", fs.existsSync(c.held), false);
  delete process.env.STUB_RC;
  const c2 = setup("t12b");
  append(c2.mbox, JSON.stringify({ seq: 81, ts: "2026-11-09T00:00:00", to: SEAT, from: "byz-unknown-seat#9", body: "미등록 좌석 글" }));
  process.env.STUB_RC = "3";
  const pi2 = await load();
  eq("T12b 미등록 발신 = 사람 아님(턴 0)", pi2.calls.length, 0);
  eq("T12b 미등록 발신 = 예약 1", lines(c2.stubLog), 1);
  delete process.env.STUB_RC;
}
// ── T13 지원 우편함 경로 분리: 입력·감시·recv 가 같은 지정 우편함(DA HOLD R1) ─────────────
{
  const c = setup("t13", { mboxRoot: "data-root-b" });
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  eq("T13 시작 시 턴 0", pi.calls.length, 0);
  append(c.mbox, row(90, SEAT, "[발주 #90] 다른 루트 우편함"));
  await until(() => pi.calls.length >= 1);
  eq("T13 다른 루트 우편함 도착 = 턴 1", pi.calls.length, 1);
  eq("T13 recv 가 그 우편함의 mbox.sh", (pi.calls[0]?.m?.content ?? "").includes(`bash ${c.comm}/mbox.sh recv ${SEAT}`), true);
  eq("T13 예산도 그 우편함 CLI", lines(c.stubLog), 1);
  eq("T13 seq 파일 = 90", fs.readFileSync(c.seqFile, "utf-8").trim(), "90");
}

// ── T14 지정 우편함에 CLI 없음 = 루트 CLI 빌림 + FT_MBOX_DIR 표식(DA HOLD R1) ─────────────
{
  const c = setup("t14", { mboxRoot: "data-root-c" });
  fs.rmSync(path.join(c.comm, "mbox.sh")); // 지정 우편함에 CLI 0
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  append(c.mbox, row(95, SEAT, "[발주 #95] CLI 없는 우편함"));
  await until(() => pi.calls.length >= 1);
  eq("T14 턴 1", pi.calls.length, 1);
  const content = pi.calls[0]?.m?.content ?? "";
  eq("T14 빌린 CLI = 루트 mbox.sh", content.includes(`bash ${c.dir}/.fable-team/comm/mbox.sh recv ${SEAT}`), true);
  eq("T14 recv 대상 우편함 표식", content.includes(`FT_MBOX_DIR="${c.comm}"`), true);
  eq("T14 예산 = 빌린 CLI 1회", lines(c.stubLog), 1);
}

// ── T15 session_shutdown = 감시 해제(2중 깨움 0) ─────────────────────────────────────────
{
  const c = setup("t15");
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  append(c.mbox, row(100, SEAT, "[발주 #100] 첫 프로세스"));
  await until(() => pi.calls.length >= 1);
  eq("T15 첫 프로세스 = 턴 1", pi.calls.length, 1);
  pi.retired = true;
  await pi.emit("session_shutdown", {});
  append(c.mbox, row(101, SEAT, "[발주 #101] 감시 해제 뒤"));
  await wait(150);
  eq("T15 shutdown 뒤 옛 인스턴스 = 턴 0", pi.calls.length, 1);
  eq("T15 예산도 1회뿐", lines(c.stubLog), 1);
  const pi2 = await load();
  eq("T15 후계는 회수로 2행 처리 = 턴 1", pi2.calls.length, 1);
}

// ── T17 _master 승계: 로드 뒤 표식이 바뀌면 다음 쪽지에 활성 ─────────────────────────────
{
  const c = setup("t17", { master: "byz-other-pi#1" }); // 승계 전 = 옛 좌석
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  eq("T17 승계 전 = 턴 0", pi.calls.length, 0);
  fs.writeFileSync(path.join(c.dir, ".fable-team", "seats-planner.json"), JSON.stringify({ _master: SEAT }) + "\n"); // 승계
  append(c.mbox, row(120, SEAT, "[발주 #120] 승계 뒤"));
  await until(() => pi.calls.length >= 1);
  eq("T17 승계 뒤 = 턴 1(재시작 0)", pi.calls.length, 1);
  eq("T17 seq 파일 = 120", fs.readFileSync(c.seqFile, "utf-8").trim(), "120");
}
// ── T19 user_bash 훅: `! bash /tmp/hN` 이 끝나면 custom 턴 1회 ──────────────────────────
{
  const c = setup("t19");
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  const ran = [];
  globalThis.__r1477Bash = { exec: async (cmd) => { ran.push(cmd); return { output: "h7 out", exitCode: 0, cancelled: false, truncated: false }; } };
  const res = await pi.emit("user_bash", { command: "bash /tmp/h7", cwd: "/tmp" });
  eq("T19 훅이 operations 를 준다", typeof res?.operations?.exec, "function");
  const out = await res.operations.exec("bash /tmp/h7", "/tmp", {});
  eq("T19 원래 명령 그대로 실행", ran[0], "bash /tmp/h7");
  eq("T19 rc·출력 그대로", `${out.exitCode}/${out.output}`, "0/h7 out");
  await wait(30);
  eq("T19 끝난 뒤 턴 1", pi.calls.length, 1);
  eq("T19 본문 = h7 끝 rc=0 → recv 하고 [완료] 정리", pi.calls[0]?.m?.content, "h7 끝 rc=0 → recv 하고 [완료] 정리");
  eq("T19 오빠 말 아님(custom) + followUp", `${pi.calls[0]?.m?.customType}/${pi.calls[0]?.o?.deliverAs}/${pi.calls[0]?.o?.triggerTurn}`, "ft-mbox/followUp/true");
  delete globalThis.__r1477Bash;
}
// ── T20 그 밖의 명령 = 훅 0 · T21 알림 실패 = bash 결과 불변 ────────────────────────────
{
  const c = setup("t20");
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  globalThis.__r1477Bash = { exec: async () => ({ output: "x", exitCode: 0, cancelled: false, truncated: false }) };
  eq("T20 `bash /tmp/other.sh` = 훅 0", await pi.emit("user_bash", { command: "bash /tmp/other.sh" }), undefined);
  eq("T20 `bash /tmp/h7 extra` = 훅 0", await pi.emit("user_bash", { command: "bash /tmp/h7 extra" }), undefined);
  pi.throwOnSend = true;
  const cap = capture();
  const res = await pi.emit("user_bash", { command: "bash /tmp/h9" });
  const out = await res.operations.exec("bash /tmp/h9", "/tmp", {});
  await until(() => cap.buf.some((l) => l.startsWith("ERROR ft-mbox-wake:"))); // 알림은 exec 반환 «뒤»(setImmediate)
  cap.stop();
  eq("T21 알림 실패해도 rc·출력 그대로", `${out.exitCode}/${out.output}`, "0/x");
  eq("T21 ERROR 1줄", cap.buf.filter((l) => l.startsWith("ERROR ft-mbox-wake:")).length, 1);
  delete globalThis.__r1477Bash;
}
// ── T23 비활성 좌석 = user_bash 훅 0 · T24 !! = 훅 0 · T25 알림은 결과 기록 뒤 ───────────────
{
  const c = setup("t23", { master: "byz-other-pi#1" });
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  globalThis.__r1477Bash = { exec: async () => ({ output: "x", exitCode: 0, cancelled: false, truncated: false }) };
  eq("T23 비활성 좌석 = 훅 0", await pi.emit("user_bash", { command: "bash /tmp/h5" }), undefined);
  const c2 = setup("t24");
  fs.writeFileSync(c2.mbox, "");
  const pi2 = await load();
  eq("T24 !! 제외 = 훅 0", await pi2.emit("user_bash", { command: "bash /tmp/h5", excludeFromContext: true }), undefined);
  eq("T24 !! 제외 = 턴 0", pi2.calls.length, 0);
  const c3 = setup("t25");
  fs.writeFileSync(c3.mbox, "");
  const pi3 = await load();
  let recorded = false;
  const order = [];
  pi3.sendMessage = function (m, o) { order.push(recorded); pi3.calls.push({ m, o }); };
  globalThis.__r1477Bash = { exec: async () => ({ output: "ok", exitCode: 0, cancelled: false, truncated: false }) };
  const res = await pi3.emit("user_bash", { command: "bash /tmp/h12" });
  const out = await res.operations.exec("bash /tmp/h12", "/tmp", {});
  recorded = true; // ← pi 가 BashExecution 을 세션에 넣은 시점(반환 직후)을 대신한다
  await until(() => pi3.calls.length >= 1);
  eq("T25 알림 1회", pi3.calls.length, 1);
  eq("T25 알림은 결과 기록 «뒤»(exec 반환 뒤)", order[0], true);
  eq("T25 rc 그대로", out.exitCode, 0);
  delete globalThis.__r1477Bash;
}
// ── T22 활성 = _master + _desk ─────────────────────────────────────────────────────────
{
  const c = setup("t22", { master: "byz-other-pi#1" });
  fs.writeFileSync(path.join(c.dir, ".fable-team", "seats-planner.json"), JSON.stringify({ _master: "byz-other-pi#1", _desk: SEAT }) + "\n");
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  append(c.mbox, row(140, SEAT, "[발주 #140] desk 좌석"));
  await until(() => pi.calls.length >= 1);
  eq("T22 _desk 로 활성 = 턴 1", pi.calls.length, 1);
  eq("T22 예산 1회", lines(c.stubLog), 1);
}
// ── T18 기동 창: 시작 직후 사건 = 즉시 깨움(재확인 타이머가 사건을 막지 않는다) ────────────
{
  const c = setup("t18");
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  append(c.mbox, row(130, SEAT, "[발주 #130] 시작 직후"));
  await wait(150); // 250ms 재확인보다 짧은 창 — 사건 경로가 살아 있어야만 통과
  eq("T18 시작 직후 사건 = 150ms 안 턴 1", pi.calls.length, 1);
  eq("T18 예산 1회", lines(c.stubLog), 1);
}
// ── T16 root 결속: FT_MBOX_ROOT 없이 cwd 가 git 워크트리여도 «공용 루트» 를 본다 ─────────────
{
  const base = path.join(ROOT, "t16-repo");
  fs.mkdirSync(base, { recursive: true });
  const git = (...args) => execFileSync("git", args, { encoding: "utf-8", cwd: base, stdio: ["ignore", "pipe", "ignore"] });
  git("init", "-q");
  git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init");
  const wt = path.join(base, "wt-planner");
  git("worktree", "add", "-q", wt);
  const c = setup("t16-src"); // 공용 루트 모양만 빌려 쓴다(seats-planner.json·스텁 mbox.sh 가 있는 .fable-team)
  const rootComm = path.join(base, ".fable-team", "comm"), rootState = path.join(base, ".fable-team", "state");
  fs.mkdirSync(rootComm, { recursive: true });
  fs.copyFileSync(path.join(c.dir, ".fable-team", "comm", "mbox.sh"), path.join(rootComm, "mbox.sh"));
  fs.writeFileSync(path.join(base, ".fable-team", "seats-planner.json"), JSON.stringify({ _master: SEAT }) + "\n");
  const mbox = path.join(rootComm, "mailbox.jsonl");
  fs.writeFileSync(mbox, "");
  delete process.env.FT_MBOX_ROOT;
  Object.assign(process.env, { FT_MBOX_FILE: mbox, FT_MBOX_STATE_DIR: rootState, FT_SEAT: SEAT });
  process.chdir(wt); // 확장이 보는 cwd = 워크트리
  const pi = await load();
  append(mbox, row(110, SEAT, "[발주 #110] 워크트리 cwd"));
  await until(() => pi.calls.length >= 1);
  eq("T16 워크트리 cwd = 턴 1", pi.calls.length, 1);
  eq("T16 recv = 공용 루트 CLI", (pi.calls[0]?.m?.content ?? "").includes(`bash ${rootComm}/mbox.sh recv ${SEAT}`), true);
  eq("T16 예산도 공용 루트 CLI", lines(c.stubLog), 1);
}

console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

# 확장은 문서(docs/extensions.md:1081)대로 pi 패키지에서 createLocalBashOperations 를 import 한다 — node 시험용 사본+스텁.
mkdir -p "$T/ext" "$T/node_modules/@earendil-works/pi-coding-agent"
cp "$EXT" "$T/ext/ft-mbox-wake.ts"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
cat > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs" <<'SHIM'
export const createLocalBashOperations = () => globalThis.__r1477Bash ?? { exec: async () => ({ output: "", exitCode: 0, cancelled: false, truncated: false }) };
SHIM
cmp -s "$EXT" "$T/ext/ft-mbox-wake.ts" && ok "S5 시험 사본 = 원본 바이트 일치" || bad "S5 시험 사본 = 원본 바이트 일치"

R1477_EXT="$T/ext/ft-mbox-wake.ts" R1477_COMM="$COMM" R1477_SEAT="$SEAT" R1477_TMP="$T" \
  timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
if [ "$rc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc)"; exit 1
