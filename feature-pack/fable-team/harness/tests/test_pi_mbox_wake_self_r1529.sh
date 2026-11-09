#!/usr/bin/env bash
# test_pi_mbox_wake_self_r1529.sh — r1529: pi 확장 ft-mbox-wake
#  ① 내 행 판정 = recv 가 소비할 행(r1153: to === seat ∧ from !== seat) — 자기 발신 행은 턴 0
#  ② (판 2) 턴 도중(agent_start~agent_end) 깨움 쌓기 0 · 배달 안 된 깨움 1개 상한
#  격리: 임시 루트(<케이스>/.fable-team/{comm,state}) · 합성 mailbox.jsonl · 가짜 pi(sendMessage 기록) ·
#        스텁 mbox.sh(budget reserve rc 고정 · 호출 기록). 실 우편함·실 pi 세션·실 Redis 0. sleep 0(폴링).
#  사례: ⓐⓑⓕⓖⓘ 자기 발신 행만 = 턴 0 · ⓒ 다른 좌석 행이 섞이면 그 행 seq 로 턴 1 · ⓓⓔ 기존 동작 회귀
#        ⓗ 턴 도중 도착 3 = 턴 0 · 턴 끝 재확인 1(남은 행 seq) · ⓙ 유휴 즉시 1 · 배달 전 1통 더 = 추가 0
#        ⓚ 시작 회수(force) 깨움도 배달 대기 1개 — 시작회수 501 뒤 agent_start 전 502 = 총 1(DA HOLD R1)
#  변이: 1 = 거르개 끔 → ⓐ FAIL · ⓒ seq 틀림 · 2 = 턴 표지 끔 → ⓗ 턴 도중 3 = FAIL · 2b = 대기 상한 끔 → ⓙ 추가 1
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R1529_EXT:-$HARNESS/pi/ft-mbox-wake.ts}"
COMM="$HARNESS/comm/mbox.sh"
SEAT="${R1529_SEAT:-byz-harness-master-pi#171}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

[ -f "$COMM" ] || { echo "FAIL 선행 없음 — r1476 착지본 $COMM"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$EXT" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }

# ── 정적 계약 ─────────────────────────────────────────────────────────────────────────
eq "S1 확장 $(wc -l < "$EXT" | tr -d ' ')줄 ≤200" "$([ "$(wc -l < "$EXT" | tr -d ' ')" -le 200 ] && echo yes || echo no)" yes # r1537 로드 줄 +2
eq "S2 내 행 = to ∧ from !== seat(한 줄)" "$(grep -c 'r.to === seat && r.from !== seat' "$EXT")" 1
eq "S3 턴 도중 표지 = pi.on(agent_start) 1 + check 거르개 1" "$(grep -c 'pi.on("agent_start"' "$EXT")$(grep -c 'inTurn || wakePending' "$EXT")" "11"
eq "S4 setInterval 0" "$(grep -c 'setInterval' "$EXT")" 0
bash -n "$0" && ok "S5 bash -n rc0" || bad "S5 bash -n rc0"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1529-self.XXXXXX")"
trap 'rm -rf "$T"' EXIT

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const EXT = process.env.R1529_EXT, SEAT = process.env.R1529_SEAT, ROOT = process.env.R1529_TMP;
let EXTv = EXT, modv = 0, fails = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
// 사건 경로는 비동기 — «깨움이 일어났는가» 를 상한 안에서 확인한다(유실이면 FAIL 그대로).
const until = async (fn, ms = 600) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (fn()) return true; await wait(10); } return fn(); };
const settle = (ms = 150) => wait(ms); // «턴 0» 을 재는 창(사건이 늦게 와도 0 이어야 한다)
const keyOf = (s) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
const OTHER = "byz-harness-nano-other#7";
const row = (seq, to, from, body) => JSON.stringify({ seq, ts: "2026-11-09T00:00:00", to, from, body });
const append = (f, ...rows) => fs.appendFileSync(f, rows.map((r) => r + "\n").join(""));
const replace = (f, ...rows) => { const t = `${f}.tmp`; fs.writeFileSync(t, rows.map((r) => r + "\n").join("")); fs.renameSync(t, f); };
const lines = (f) => { try { return fs.readFileSync(f, "utf-8").split("\n").filter((l) => l.trim()).length; } catch { return 0; } };

function setup(name) {
  const dir = path.join(ROOT, name), base = path.join(dir, ".fable-team");
  const comm = path.join(base, "comm"), state = path.join(base, "state");
  fs.mkdirSync(comm, { recursive: true });
  fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify({ _master: SEAT, [SEAT]: { role: "master", agent: "pi" } }) + "\n");
  const stubLog = path.join(dir, "stub.log");
  fs.writeFileSync(path.join(comm, "mbox.sh"), ["#!/bin/bash", `echo "$*" >> ${JSON.stringify(stubLog)}`, "exit 0", ""].join("\n"));
  Object.assign(process.env, {
    FT_MBOX_ROOT: dir, FT_MBOX_STATE_DIR: state, FT_MBOX_FILE: path.join(comm, "mailbox.jsonl"),
    FT_SEAT: SEAT, FT_MBOX_WAKE_DEBOUNCE_MS: "5",
  });
  return { dir, mbox: path.join(comm, "mailbox.jsonl"), stubLog,
    seqFile: path.join(state, "pi-wake", `${keyOf(SEAT)}.seq`),
    nudge: path.join(state, "pi-wake", `${keyOf(SEAT)}.nudge`) };
}
const selfRows = [row(301, SEAT, SEAT, "[카드 이동] r1529 a"), row(302, SEAT, SEAT, "[카드 이동] r1529 b"), row(303, SEAT, SEAT, "[착지] 설치 PENDING")];

const live = [];
async function load() {
  for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); }
  const pi = { calls: [], retired: false, h: {}, on(e, f) { (this.h[e] ??= []).push(f); },
    async emit(e, ev = {}) { let out; for (const f of this.h[e] ?? []) { const r = await f(ev, { isIdle: () => true }); if (r !== undefined && out === undefined) out = r; } return out; },
    appendEntry(t, d) { this.entries = this.entries ?? []; this.entries.push({ t, d }); }, // r1537 로드 줄(실 pi 와 같은 칸)
    sendMessage(m, o) { if (!this.retired) this.calls.push({ m, o }); } };
  live.push(pi);
  const mod = await import(`${pathToFileURL(EXTv).href}?v=${++modv}`);
  mod.default(pi);
  await pi.emit("session_start", {});
  return pi;
}
const bodyOf = (pi, i) => pi.calls[i ?? pi.calls.length - 1]?.m?.content ?? ""; // i 생략 = 마지막 깨움
const seqOf = (pi, i) => Number((bodyOf(pi, i).match(/^\[발주 #(\d+)\]/) ?? [])[1] ?? -1);

// ── ⓐ 자기 발신 행만(session_start check(true)) = 턴 0 · seq 파일 무변화 ─────────────────────
{
  const c = setup("a");
  replace(c.mbox, ...selfRows);
  fs.mkdirSync(path.dirname(c.seqFile), { recursive: true });
  fs.writeFileSync(c.seqFile, "777\n");
  const pi = await load();
  await settle();
  eq("ⓐ 자기 발신 3행 = 턴 0", pi.calls.length, 0);
  eq("ⓐ seq 파일 무변화(777)", fs.readFileSync(c.seqFile, "utf-8").trim(), "777");
  eq("ⓐ 예산 0", lines(c.stubLog), 0);
  // ── ⓑ ⓐ 상태에서 agent_end(writeSeq(null) + run) = 턴 0 ─────────────────────────────
  await pi.emit("agent_end", {});
  await settle();
  eq("ⓑ agent_end 재확인 = 턴 0", pi.calls.length, 0);
  eq("ⓑ seq 파일 그대로 없음", fs.existsSync(c.seqFile), false);
}

// ── ⓒ 자기 행 + 다른 좌석 [긴급] 1행(더 작은 seq) → 턴 1 · 발주 seq = 그 행 ─────────────────
{
  const c = setup("c");
  replace(c.mbox, ...selfRows, row(300, SEAT, OTHER, "[긴급] 다른 좌석"));
  const pi = await load();
  await until(() => pi.calls.length >= 1);
  eq("ⓒ 다른 좌석 행 = 턴 1", pi.calls.length, 1);
  eq("ⓒ 발주 seq = 다른 좌석 행(300)", seqOf(pi), 300);
  eq("ⓒ [긴급] = 예산 0", lines(c.stubLog), 0);
}

// ── ⓓ 다른 좌석 일반 1행 = 턴 1(회귀) · ⓔ from 칸 없는 옛 행 = 내 행으로 셈 ─────────────────
{
  const c = setup("d");
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  append(c.mbox, row(310, SEAT, OTHER, "[발주 #310] 일반"));
  await until(() => pi.calls.length >= 1);
  eq("ⓓ 다른 좌석 일반 = 턴 1", pi.calls.length, 1);
  eq("ⓓ 예산 1", lines(c.stubLog), 1);
  const c2 = setup("e");
  replace(c2.mbox, JSON.stringify({ seq: 320, ts: "2026-11-09T00:00:00", to: SEAT, body: "[발주 #320] from 없음" })); // 옛 행 = from 칸 0
  const pi2 = await load();
  eq("ⓔ from 칸 없는 행 = 턴 1", pi2.calls.length, 1);
  eq("ⓔ 발주 seq = 320", seqOf(pi2), 320);
}

// ── ⓕ 자기 발신 행 3개를 하나씩 덧붙임(감시 사건 3회 · master #277066 꼴) = 턴 0 ─────────────
{
  const c = setup("f");
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  for (const r of selfRows) { append(c.mbox, r); await settle(120); }
  eq("ⓕ 자기 행 3회 덧붙임 = 턴 0", pi.calls.length, 0);
  eq("ⓕ seq 파일 없음", fs.existsSync(c.seqFile), false);
  eq("ⓕ 예산 0", lines(c.stubLog), 0);
}

// ── ⓖ 자기 발신 행만 + sweep nudge 파일 있음 = 턴 0(nudge 는 남아도 된다) ──────────────────
{
  const c = setup("g");
  replace(c.mbox, ...selfRows);
  fs.mkdirSync(path.dirname(c.nudge), { recursive: true });
  fs.writeFileSync(c.nudge, "sweep\n");
  const pi = await load();
  await settle();
  eq("ⓖ nudge + 자기 행만 = 턴 0", pi.calls.length, 0);
  eq("ⓖ nudge 남음", fs.existsSync(c.nudge), true);
}

// ── ⓗ 턴 도중 3통 = 턴 0 · 턴 끝 재확인 1(남은 행 seq) · ⓘ 턴 안 전부 소비 = 턴 끝 0 ────────
{
  const c = setup("h");
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  await pi.emit("agent_start", {});
  for (const s of [411, 412, 413]) { append(c.mbox, row(s, SEAT, OTHER, `[발주 #${s}] 턴 도중`)); await settle(80); }
  eq("ⓗ 턴 도중 도착 3 = 깨움 0", pi.calls.length, 0);
  eq("ⓗ 턴 도중 예산 0", lines(c.stubLog), 0);
  replace(c.mbox, row(413, SEAT, OTHER, "[발주 #413] 턴 도중")); // 411·412 만 recv 로 소비
  await pi.emit("agent_end", {});
  eq("ⓗ 턴 끝 재확인 = 턴 1", pi.calls.length, 1);
  eq("ⓗ 발주 seq = 남은 행(413)", seqOf(pi), 413);
  const c2 = setup("i");
  fs.writeFileSync(c2.mbox, "");
  const pi2 = await load();
  await pi2.emit("agent_start", {});
  for (const s of [421, 422, 423]) { append(c2.mbox, row(s, SEAT, OTHER, `[발주 #${s}] 턴 도중`)); await settle(80); }
  eq("ⓘ 턴 도중 3 = 깨움 0", pi2.calls.length, 0);
  replace(c2.mbox); // 3통 다 소비(우편함 비움)
  await pi2.emit("agent_end", {});
  eq("ⓘ 전부 소비한 턴 끝 = 깨움 0", pi2.calls.length, 0);
}

// ── ⓙ 유휴 쪽지 1통 = 즉시 턴 1 · 배달 전 1통 더 = 추가 0 ──────────────────────────────────
{
  const c = setup("j");
  fs.writeFileSync(c.mbox, "");
  const pi = await load();
  append(c.mbox, row(431, SEAT, OTHER, "[발주 #431] 유휴"));
  await until(() => pi.calls.length >= 1);
  eq("ⓙ 유휴 즉시 = 턴 1", pi.calls.length, 1);
  append(c.mbox, row(432, SEAT, OTHER, "[발주 #432] 배달 전"));
  await settle(200);
  eq("ⓙ 배달 전 1통 더 = 추가 0", pi.calls.length, 1);
  eq("ⓙ 예산 1회", lines(c.stubLog), 1);
  await pi.emit("agent_start", {}); // 턴 시작 = 배달된 깨움 소비
  replace(c.mbox, row(432, SEAT, OTHER, "[발주 #432] 배달 전"));
  await pi.emit("agent_end", {});
  eq("ⓙ 다음 턴 끝 재확인 = 턴 2(남은 432)", pi.calls.length, 2);
  eq("ⓙ 두 번째 발주 seq = 432", seqOf(pi, 1), 432);
}

// ── ⓚ R1 회귀(DA HOLD R1): 세션 시작 회수 깨움도 배달 대기 1개 — 시작회수 [인계]501 뒤
//     agent_start 전 [레디]502 도착 = 추가 깨움 0(총 1) · 턴 안에서 소비하고 턴 끝 = 추가 0 ──────────
{
  const c = setup("k");
  replace(c.mbox, row(501, SEAT, OTHER, "[인계] r1529 인계"));
  const pi = await load();
  eq("ⓚ 시작 회수 [인계] = 턴 1", pi.calls.length, 1);
  eq("ⓚ 시작 회수 발주 seq = 501", seqOf(pi), 501);
  append(c.mbox, row(502, SEAT, OTHER, "[레디] r1529 레디")); // agent_start 전 도착(카드 «배달 안 된 깨움 1개» 꼴)
  await settle(200);
  eq("ⓚ 배달 대기 중 도착 = 총 1(추가 0)", pi.calls.length, 1);
  await pi.emit("agent_start", {}); // 턴 시작 = 배달된 깨움 소비
  replace(c.mbox); // 턴 안에서 501·502 다 소비(recv)
  await pi.emit("agent_end", {});
  eq("ⓚ 턴 끝(미읽음 0) = 추가 0", pi.calls.length, 1);
}

// ── 변이 1: 거르개 끔(from 조건 삭제) → ⓐ 가 FAIL 이어야 한다 · ⓒ seq 도 틀려야 ──────────────
function mutate(name, from, to) {
  const src = fs.readFileSync(EXT, "utf-8"), out = src.replace(from, to);
  if (out === src) { bad(`변이 ${name} 치환 미적용(줄 못 찾음)`); return null; }
  const p = path.join(path.dirname(EXT), `mut-${name}.ts`);
  fs.writeFileSync(p, out);
  return p;
}
{
  const mut = mutate("1", "r.to === seat && r.from !== seat", "r.to === seat");
  if (mut) {
    EXTv = mut;
    const c = setup("m1");
    replace(c.mbox, ...selfRows);
    const pi = await load();
    await until(() => pi.calls.length >= 1);
    (pi.calls.length >= 1 ? ok : bad)("변이 1 → ⓐ FAIL 확인(거르개 없으면 자기 행으로 턴)");
    const c2 = setup("m2");
    replace(c2.mbox, ...selfRows, row(300, SEAT, OTHER, "[긴급] 다른 좌석"));
    const pi2 = await load();
    await until(() => pi2.calls.length >= 1);
    eq("변이 1 → ⓒ seq 틀림(자기 행 max 303)", seqOf(pi2), 303);
    EXTv = EXT;
  }
}
// ── 변이 2: 턴 표지·대기 상한 끔 → ⓗ 턴 도중 3 = FAIL · 변이 2b: 대기 상한만 끔 → ⓙ 추가 1 ────
{
  const mut = mutate("2", "if (!activeSeat(false) || inTurn || wakePending) return;", "if (!activeSeat(false)) return;");
  if (mut) {
    EXTv = mut;
    const c = setup("m3");
    fs.writeFileSync(c.mbox, "");
    const pi = await load();
    await pi.emit("agent_start", {});
    for (const s of [411, 412, 413]) { append(c.mbox, row(s, SEAT, OTHER, `[발주 #${s}] 턴 도중`)); await settle(80); }
    eq("변이 2 → ⓗ 턴 도중 3 = FAIL 확인", pi.calls.length, 3);
    EXTv = EXT;
  }
  const mut2 = mutate("2b", "if (!activeSeat(false) || inTurn || wakePending) return;", "if (!activeSeat(false) || inTurn) return;");
  if (mut2) {
    EXTv = mut2;
    const c = setup("m4");
    fs.writeFileSync(c.mbox, "");
    const pi = await load();
    append(c.mbox, row(431, SEAT, OTHER, "[발주 #431] 유휴"));
    await until(() => pi.calls.length >= 1);
    append(c.mbox, row(432, SEAT, OTHER, "[발주 #432] 배달 전"));
    await settle(200);
    eq("변이 2b → ⓙ 추가 1 = FAIL 확인", pi.calls.length, 2);
    EXTv = EXT;
  }
}

console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

# 확장은 pi 패키지에서 createLocalBashOperations 를 import 한다 — node 시험용 사본 + 스텁(pi 패키지 대체).
mkdir -p "$T/ext" "$T/node_modules/@earendil-works/pi-coding-agent"
cp "$EXT" "$T/ext/ft-mbox-wake.ts"; cp "$(dirname "$EXT")/ft-load-line.ts" "$T/ext/" # r1537 공용 헬퍼(확장이 import)
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
cat > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs" <<'SHIM'
export const createLocalBashOperations = () => globalThis.__r1529Bash ?? { exec: async () => ({ output: "", exitCode: 0, cancelled: false, truncated: false }) };
SHIM
cmp -s "$EXT" "$T/ext/ft-mbox-wake.ts" && ok "S6 시험 사본 = 원본 바이트 일치" || bad "S6 시험 사본 = 원본 바이트 일치"

R1529_EXT="$T/ext/ft-mbox-wake.ts" R1529_SEAT="$SEAT" R1529_TMP="$T" \
  timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
if [ "$rc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc)"; exit 1
