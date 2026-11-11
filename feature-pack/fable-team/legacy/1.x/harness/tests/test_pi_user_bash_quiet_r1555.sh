#!/usr/bin/env bash
# test_pi_user_bash_quiet_r1555.sh — r1555: 오빠 `!`(user_bash) 뒤 «조용함 창» 동안 쪽지 깨움 턴을 미룬다.
#   ft-mbox-wake: `!` 아무 명령이나 창(FT_USER_BASH_QUIET_MS · 기본 = FT_H_DONE_QUIET_MS 값)을 열고, 마지막 `!` 기준으로 다시 잰다.
#   창 안 = check() 첫 줄 return(우편함 읽기·seq·예산·held 0) · 창 끝 1회짜리 타이머가 run() 1회 → 쉼이면 깨움 1회(우편함 파일이 정본 · 손실 0).
#   오빠 일반 메시지(pi input source="interactive") = 창 즉시 닫기 · "extension"·"rpc" = 창 불변 · `!!`·비활성 좌석 = 창 0.
#  격리: 임시 루트 · 합성 seats-planner.json · 가짜 pi(sendMessage 기록) · 가짜 시계(globalThis.setTimeout 교체 · sleep 0) ·
#        예산 CLI 대역(budget.log) · 실 pi 창 0 · 실 우편함 0 · 실 /tmp h 0 · 주기 타이머 0.
#  사례: ⓐ 창 안 쪽지 = 턴 0 · seq 0 · 예산 0 · held 0 · ⓑ 창 끝 = run() 1회 · 깨움 1회(seq 일치 = 손실 0)
#        ⓒ 창 안 `!` 재장전 = 마지막 `!` 기준(중간 창 끝 0 · 최종 1회) · ⓓ interactive = 즉시 닫힘(그 턴 끝 뒤 1회) · extension/rpc = 불변
#        ⓔ `!!` = 창 0(즉시 깨움) · 비활성 좌석 = 창 0 · ⓕ 창 없음 = 지금과 같음 · ⓖ 창 타이머 = 1회짜리(주기 0 · shutdown 이 끔)
#        ⓗ h 끝 모음(r1540) 불변 · 같은 창 끝에 h 알림과 쪽지 깨움이 겹쳐도 각 1회
#  변이: M1 창 판정 0 = ⓐ 턴 0 FAIL · M2 `!` 마다 창을 다시 재지 않음 = ⓒ FAIL · M3 interactive 에 창을 안 닫음 = ⓓ FAIL
#        M4 창 안에서도 예산 reserve 호출 = ⓐ 예산 0 FAIL
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
WAKE="${R1555_WAKE:-$HARNESS/pi/ft-mbox-wake.ts}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$WAKE" ] || { echo "FAIL 확장 없음 $WAKE"; exit 1; }

# ── 정적 계약 ─────────────────────────────────────────────────────────────────────────
eq "S1 ft-mbox-wake ≤240줄" "$([ "$(wc -l < "$WAKE" | tr -d ' ')" -le 240 ] && echo yes || echo no)" yes # r1669 recv-gate +25줄(200→240)
eq "S2 창 기본값 = r1540 창 값(FT_H_DONE_QUIET_MS)" "$(grep -c 'FT_USER_BASH_QUIET_MS ?? hQuiet' "$WAKE")" 1
eq "S3 check 첫 줄이 창 판정" "$(grep -c 'if (uUntil > Date.now()) return;' "$WAKE")" 1
eq "S4 input 핸들러 1개" "$(grep -c 'pi.on("input"' "$WAKE")" 1
eq "S4b interactive 만 닫음" "$(grep -c 'event.source !== "interactive"' "$WAKE")" 1
eq "S5 주기 타이머 0(setInterval)" "$(grep -c 'setInterval' "$WAKE")" 0
eq "S6 모듈 분리 0(r1540 변이 문자열 보존)" "$(grep -c 'ft-h-done' "$WAKE")$(grep -c 'hArmed = true; try { hFlush(); }' "$WAKE")" "02"
bash -n "$0" && ok "S7 bash -n rc0" || bad "S7 bash -n rc0"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1555-quiet.XXXXXX")"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
cp "$WAKE" "$T/ext-ft-mbox-wake.ts"; cp "$(dirname "$WAKE")/ft-load-line.ts" "$T/"
mkdir -p "$T/node_modules/@earendil-works/pi-coding-agent"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
cat > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs" <<'SHIM'
export const createLocalBashOperations = () => globalThis.__r1555Bash ?? { exec: async () => ({ output: "", exitCode: 0, cancelled: false, truncated: false }) };
SHIM

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const TMP = process.env.R1555_TMP, WAKE = process.env.R1555_WAKE, SEAT = process.env.R1555_SEAT;
const OTHER = "byz-harness-master-pi#172"; // 사람 발신 판정(_master)은 안 쓰는 좌석으로 둔다 — 예산 경로를 재야 한다
const MAIL = "본문 · 창 안 도착"; // 머리 없는 본문 = quietOnly 아님 · loud 아님 = 예산 경로
const keyOf = (s) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
let fails = 0, wakePath = WAKE, modv = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));

// ★가짜 시계★ — 주기 탐색 0 · sleep 0 · advance() 가 due 타이머를 «시각 순서로» 돌린다(하드 룰 22).
let now = 0, next = 1, timers = new Map(), created = [];
globalThis.setTimeout = (fn, ms) => { const id = next++; const due = now + Number(ms); timers.set(id, { fn, due }); created.push({ ms: Number(ms), at: now }); return id; };
globalThis.clearTimeout = (id) => { timers.delete(id); };
function advance(ms) {
  const end = now + ms;
  for (;;) { const xs = [...timers].filter(([, v]) => v.due <= end).sort((a, b) => a[1].due - b[1].due); if (!xs.length) break; const [id, v] = xs[0]; timers.delete(id); now = v.due; v.fn(); }
  now = end;
}
const errs = [];
const origErr = console.error;
console.error = (...a) => { errs.push(a.map(String).join(" ")); };

let cur = null;
function setup(name, opt = {}) {
  timers.clear(); created = []; now = 0;
  const root = path.join(TMP, name), base = path.join(root, ".fable-team"), comm = path.join(base, "comm"), state = path.join(base, "state");
  fs.mkdirSync(comm, { recursive: true }); fs.mkdirSync(state, { recursive: true });
  const seats = opt.inactive ? { _master: OTHER, [SEAT]: { agent: "pi" } } : { _master: SEAT, [SEAT]: { agent: "pi" } };
  fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify(seats) + "\n");
  const mbox = path.join(comm, "mailbox.jsonl"), budget = path.join(root, "budget.log");
  fs.writeFileSync(mbox, "");
  fs.writeFileSync(path.join(comm, "mbox.sh"), `#!/bin/bash\necho "$*" >> ${budget}\nexit 0\n`);
  Object.assign(process.env, { FT_MBOX_ROOT: root, FT_MBOX_FILE: mbox, FT_MBOX_STATE_DIR: state, FT_SEAT: SEAT,
    FT_MBOX_WAKE_DEBOUNCE_MS: "5", FT_USER_BASH_QUIET_MS: String(opt.quiet ?? 20000) });
  const wake = path.join(state, "pi-wake"), k = keyOf(SEAT);
  cur = { name, root, mbox, budget, wake, seqf: path.join(wake, `${k}.seq`), heldf: path.join(state, "doorbell-held", k) };
  return cur;
}
const mail = (c, seq) => fs.writeFileSync(c.mbox, JSON.stringify({ seq, to: SEAT, from: "byz-other-seat#1", body: MAIL }) + "\n");
const budgetLines = (c) => { try { return fs.readFileSync(c.budget, "utf-8").trim().split("\n").filter(Boolean); } catch { return []; } };
const sends = (pi) => pi.calls.filter((x) => String(x.m?.content ?? "").startsWith("[발주 #"));
const hSends = (pi) => pi.calls.filter((x) => String(x.m?.content ?? "").includes("→ recv 하고 [완료] 정리"));
const sleepReal = () => new Promise(setImmediate); // 폴더 감시 콜백이 돌 기회(가짜 시계 아님 · 실 I/O 1틱)

const live = [];
async function load(opt = {}) {
  for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); }
  const pi = { calls: [], retired: false, h: {},
    on(e, f) { (this.h[e] ??= []).push(f); }, registerCommand() {}, appendEntry() {},
    async emit(e, ev = {}) { let out; for (const f of this.h[e] ?? []) { const r = await f(ev, { isIdle: () => true }); if (r !== undefined && out === undefined) out = r; } return out; },
    sendMessage(m, o) { if (!this.retired) pi.calls.push({ m, o }); }, sendUserMessage() {},
  };
  live.push(pi);
  const mod = await import(`${pathToFileURL(wakePath).href}?v=${++modv}`);
  mod.default(pi);
  await pi.emit("session_start", {});
  await sleepReal();
  return pi;
}
const hBash = (rc = 0) => { globalThis.__r1555Bash = { exec: async () => ({ output: "out", exitCode: rc, cancelled: false, truncated: false }) }; };
const runH = async (pi, n) => { hBash(0); const res = await pi.emit("user_bash", { command: `bash /tmp/h${n}` }); return res.operations.exec("", TMP, {}); };

// ── ⓐ 창 안 쪽지 = 턴 0 · seq 0 · 예산 0 · held 0 → 창 끝 = 1회 ───────────────────────────
{
  const c = setup("a"); const pi = await load();
  const before = pi.calls.length;
  eq("ⓐ h 아닌 `!` = 훅 0(창만)", await pi.emit("user_bash", { command: "git status --short" }), undefined);
  mail(c, 101); advance(5000); await sleepReal();
  await pi.emit("agent_end", {}); // 창 안 재확인 경로
  advance(4000); await sleepReal();
  eq("ⓐ 창 안 = 턴 0", sends(pi).length, 0);
  eq("ⓐ 창 안 = 예산 0", budgetLines(c).length, 0);
  eq("ⓐ 창 안 = seq 파일 0", fs.existsSync(c.seqf), false);
  eq("ⓐ 창 안 = held 0", fs.existsSync(c.heldf), false);
  advance(12000); // 창 끝(t=21000)
  await sleepReal();
  eq("ⓑ 창 끝 = 깨움 1회", sends(pi).length - 0, 1);
  eq("ⓑ 본문 = 그 seq(손실 0)", sends(pi)[0]?.m?.content.includes("#101"), true);
  eq("ⓑ 창 끝 = 예산 1회", budgetLines(c).length, 1);
  eq("ⓑ seq 파일 = 101", fs.readFileSync(c.seqf, "utf-8").trim(), "101");
  advance(40000); await sleepReal();
  eq("ⓑ 더 지나도 중복 깨움 0", sends(pi).length, 1);
  eq("ⓑ 창 타이머 = 1회짜리(주기 0)", created.filter((x) => x.ms === 20000).length, 1);
}

// ── ⓒ 창 안 `!` 재장전 = 마지막 `!` 기준(중간 창 끝 0 · 최종 1회) ─────────────────────────
{
  const c = setup("c"); const pi = await load();
  await pi.emit("user_bash", { command: "git status" }); // t=0 창 → t=20000
  mail(c, 102); advance(1000); await sleepReal();
  await pi.emit("user_bash", { command: "ls" }); // t=1000 창 → t=21000 (재장전)
  advance(19000); await sleepReal(); // t=20000 — 첫 창이었다면 여기서 깨웠다
  eq("ⓒ 첫 창 끝 = 턴 0(재장전)", sends(pi).length, 0);
  advance(1500); await sleepReal(); // t=21500 — 마지막 창 끝
  eq("ⓒ 마지막 창 끝 = 1회", sends(pi).length, 1);
  eq("ⓒ 창 타이머 = 재장전 2회", created.filter((x) => x.ms === 20000).length, 2);
  advance(40000); await sleepReal();
  eq("ⓒ 중복 0", sends(pi).length, 1);
}

// ── ⓓ interactive = 즉시 닫힘(그 턴 끝 뒤 1회) · extension/rpc = 창 불변 ─────────────────
{
  const c = setup("d"); const pi = await load();
  await pi.emit("user_bash", { command: "git status" }); // 창 → t=20000
  mail(c, 103); advance(2000); await sleepReal();
  await pi.emit("input", { source: "extension", text: "[발주]" }); // 창 불변
  advance(1000); await sleepReal();
  eq("ⓓ extension = 창 불변(턴 0)", sends(pi).length, 0);
  await pi.emit("input", { source: "rpc", text: "x" }); // 창 불변
  await pi.emit("input", { source: "interactive", text: "오빠 메시지" }); // 창 닫힘
  await pi.emit("agent_end", {}); // 그 턴이 끝나면 우편함 재확인
  await sleepReal();
  eq("ⓓ interactive = 즉시 닫힘 → 그 턴 끝 1회", sends(pi).length, 1);
  advance(40000); await sleepReal();
  eq("ⓓ 닫힌 창이 다시 울리지 않음", sends(pi).length, 1);
}

// ── ⓔ `!!` = 창 0(즉시 깨움) · 비활성 좌석 = 창 0 ────────────────────────────────────────
{
  const c = setup("e"); const pi = await load();
  eq("ⓔ !! = 훅 0", await pi.emit("user_bash", { command: "bash /tmp/h1", excludeFromContext: true }), undefined);
  mail(c, 104); await pi.emit("agent_end", {}); await sleepReal();
  eq("ⓔ !! 는 창을 안 연다(즉시 1회)", sends(pi).length, 1);
}
{
  const c = setup("e2", { inactive: true }); const pi = await load();
  eq("ⓔ 비활성 좌석 = 훅 0", await pi.emit("user_bash", { command: "git status" }), undefined);
  mail(c, 105); await pi.emit("agent_end", {}); await sleepReal(); advance(100); await sleepReal();
  eq("ⓔ 비활성 좌석 = 턴 0", sends(pi).length, 0);
}

// ── ⓕ 창 없음 = 지금과 같음(쪽지 = 턴 1회) ───────────────────────────────────────────────
{
  const c = setup("f"); const pi = await load();
  mail(c, 106); await pi.emit("agent_end", {}); await sleepReal();
  eq("ⓕ 창 없음 = 지금과 같음 1회", sends(pi).length, 1);
  eq("ⓕ seq 파일 기록", fs.readFileSync(c.seqf, "utf-8").trim(), "106");
}

// ── ⓖ 창 타이머 = 1회짜리 · shutdown 이 끈다 ─────────────────────────────────────────────
{
  const c = setup("g"); const pi = await load();
  await pi.emit("user_bash", { command: "git status" });
  const n = timers.size;
  eq("ⓖ 창 타이머 = 1개", created.filter((x) => x.ms === 20000).length, 1);
  await pi.emit("session_shutdown", {}); await sleepReal();
  const left = [...timers.values()].filter((v) => v.due >= now + 20000).length;
  eq("ⓖ shutdown 뒤 남은 창 타이머 0", left, 0);
  mail(c, 107); advance(40000); await sleepReal();
  eq("ⓖ shutdown 뒤 깨움 0", sends(pi).length, 0);
}

// ── ⓗ h 끝 모음(r1540) 불변 · 같은 창 끝에 겹쳐도 각 1회 ─────────────────────────────────
{
  const c = setup("h"); const pi = await load();
  await runH(pi, 9); // h1장 = 실행 중 창 + 완료 뒤 h 창(같은 값)
  mail(c, 108); advance(500); await sleepReal();
  eq("ⓗ h 직후 = 알림 0(r1540 그대로)", pi.calls.length, 0);
  advance(21000); await sleepReal(); // 마지막 h 기준 창 끝
  eq("ⓗ h 끝 알림 1회", hSends(pi).length, 1);
  eq("ⓗ 같은 창 끝 쪽지 깨움 1회", sends(pi).length, 1);
  advance(40000); await sleepReal();
  eq("ⓗ 두 번 알림 0", `${hSends(pi).length}/${sends(pi).length}`, "1/1");
}

// ── 변이 ────────────────────────────────────────────────────────────────────────────────
function mutate(name, from, to) {
  const src = fs.readFileSync(WAKE, "utf-8"), out = src.replace(from, to);
  if (out === src) { bad(`변이 ${name} 치환 미적용(줄 못 찾음)`); return null; }
  const p = path.join(TMP, `mut-${name}.ts`);
  fs.writeFileSync(p, out);
  return p;
}
// M1: 창 판정 0(옛 동작) → ⓐ 창 안 턴 0 FAIL
{
  const keep = wakePath;
  const mut = mutate("M1", "    if (uUntil > Date.now()) return; // ★r1555★ 창 안 = 아무것도 하지 않는다(우편함 읽기·seq·예산·held 0) — 창 끝 타이머가 run() 을 1회 부른다\n", "");
  if (mut) {
    wakePath = mut;
    const c = setup("m1"); const pi = await load();
    await pi.emit("user_bash", { command: "git status" }); mail(c, 201);
    await pi.emit("agent_end", {}); await sleepReal();
    (sends(pi).length > 0 ? ok : bad)(`M1 → ⓐ 창 안 턴 0 FAIL 검출(턴 ${sends(pi).length}회)`);
    wakePath = keep;
  }
}
// M2: `!` 마다 창을 다시 재지 않음 → ⓒ 첫 창 끝에서 깨움 FAIL
{
  const keep = wakePath;
  const mut = mutate("M2", "uUntil = Date.now() + userQuiet; if (uTimer) clearTimeout(uTimer); uTimer = setTimeout(", "uUntil = Date.now() + userQuiet; uTimer = setTimeout(");
  if (mut) {
    wakePath = mut;
    const c = setup("m2"); const pi = await load();
    await pi.emit("user_bash", { command: "git status" }); mail(c, 202); advance(1000);
    await pi.emit("user_bash", { command: "ls" });
    advance(19500); await sleepReal();
    (sends(pi).length > 0 ? ok : bad)(`M2 → ⓒ 재장전 FAIL 검출(첫 창 끝에서 ${sends(pi).length}회)`);
    wakePath = keep;
  }
}
// M3: interactive 에 창을 안 닫음 → ⓓ 즉시 닫힘 FAIL
{
  const keep = wakePath;
  const mut = mutate("M3", 'if (event.source !== "interactive") return; uUntil = 0;', 'if (event.source !== "interactive") return;');
  if (mut) {
    wakePath = mut;
    const c = setup("m3"); const pi = await load();
    await pi.emit("user_bash", { command: "git status" }); mail(c, 203); advance(2000);
    await pi.emit("input", { source: "interactive", text: "오빠 메시지" });
    await pi.emit("agent_end", {}); await sleepReal();
    (sends(pi).length === 0 ? ok : bad)(`M3 → ⓓ 창 닫힘 FAIL 검출(턴 ${sends(pi).length}회)`);
    wakePath = keep;
  }
}
// M4: 창 판정을 reserve «뒤» 로 옮김 = 창 안에서도 예산 차감 → ⓐ 예산 0 FAIL
{
  const keep = wakePath;
  const src = fs.readFileSync(WAKE, "utf-8")
    .replace("    if (uUntil > Date.now()) return; // ★r1555★ 창 안 = 아무것도 하지 않는다(우편함 읽기·seq·예산·held 0) — 창 끝 타이머가 run() 을 1회 부른다\n", "")
    .replace("    wakeNow(seq, viaNudge);", "    if (uUntil > Date.now()) return; // M4\n    wakeNow(seq, viaNudge);");
  if (src === fs.readFileSync(WAKE, "utf-8")) bad("M4 치환 미적용");
  else {
    const p = path.join(TMP, "mut-M4.ts"); fs.writeFileSync(p, src);
    wakePath = p;
    const c = setup("m4"); const pi = await load();
    await pi.emit("user_bash", { command: "git status" }); mail(c, 204);
    await pi.emit("agent_end", {}); await sleepReal();
    (budgetLines(c).length > 0 ? ok : bad)(`M4 → ⓐ 창 안 예산 0 FAIL 검출(예산 ${budgetLines(c).length}회)`);
    wakePath = keep;
  }
}

console.error = origErr;
console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

R1555_WAKE="$T/ext-ft-mbox-wake.ts" R1555_SEAT="byz-harness-nano-r1555-pi-user-bash-quiet-defers-mail-wak#0" R1555_TMP="$T" \
  timeout 70 node "$T/driver.mjs"; rc=$?

echo "---"
if [ "$rc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc)"; exit 1
