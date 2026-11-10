#!/usr/bin/env bash
# test_pi_bash_pending_r1540.sh — r1540: pi 확장이 «streaming 중 `!` 결과 대기 영역» 을 만들지 않는다.
#   ft-mbox-wake: h 끝을 모아 마지막 h 뒤 조용함 창(FT_H_DONE_QUIET_MS)이 지나고 좌석이 쉬면 턴 1회, 일하는 중이면 다음 정상 settled 1회.
#   ft-reload-request: reload 가 거절되면(일하는 중) 요청 파일을 되살리고 다음 settled 로 미룬다 — 요청 소실 0.
#  격리: 임시 루트 · 합성 seats-planner.json · 가짜 pi(sendMessage/sendUserMessage 기록 · ctx.isIdle 주입 · reload 스텁) ·
#        가짜 bash operations · 실 pi 창 0 · 실 우편함 0 · 실 /tmp h 0 · 주기 타이머 0.
#  사례: ⓐ h 1장 = 즉시 턴 0 · 창 뒤 1회 · ⓑ 창 안 h 3장 = 1회(3줄) · ⓒ 일하는 중이면 settled 1회(aborted 는 미룸)
#        ⓓ 같은 h 두 번 알림 0 · ⓔ 주기 타이머 0 · ⓕ h 아님/!!/비활성 = 훅 0 · ⓖ reload 거절 = 복원 + 1줄 + 다음 settled 1회
#        ⓗ 정상 쉼 = reload 1회 · 파일 0
#  변이: M1 즉시 턴(옛 동작) = ⓐ FAIL · M2 창을 다시 재지 않음 = ⓑ 턴 2회 이상 · M3 거절 때 복원 0 = ⓖ FAIL
#        M4 정상 settled 가 창을 무시하고 flush = ⓘ FAIL · M5 대기 목록 파일 저장 0 = ⓙ FAIL
#  경계(가짜 시계 · DA 277721 R1/R2): ⓘ 창 안 정상 settled = flush 0 · 창 뒤 연속 h 2장 = 최종 1회
#        ⓙ h 대기 중 reload(session_shutdown) → 새 확장 session_start 회수 = 옛/새 합 1회(유실 0 · 중복 0)
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
WAKE="${R1540_WAKE:-$HARNESS/pi/ft-mbox-wake.ts}"
RELOAD="${R1540_RELOAD:-$HARNESS/pi/ft-reload-request.ts}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$WAKE" ] || { echo "FAIL 확장 없음 $WAKE"; exit 1; }
[ -f "$RELOAD" ] || { echo "FAIL 확장 없음 $RELOAD"; exit 1; }

# ── 정적 계약 ─────────────────────────────────────────────────────────────────────────
eq "S1 ft-mbox-wake ≤200줄" "$([ "$(wc -l < "$WAKE" | tr -d ' ')" -le 200 ] && echo yes || echo no)" yes
eq "S2 ft-reload-request ≤200줄" "$([ "$(wc -l < "$RELOAD" | tr -d ' ')" -le 200 ] && echo yes || echo no)" yes
eq "S3 조용함 창 기본 20000ms" "$(grep -c 'FT_H_DONE_QUIET_MS ?? 20000' "$WAKE")" 1
eq "S4 주기 타이머 0(두 파일)" "$(cat "$WAKE" "$RELOAD" | grep -c 'setInterval')" 0
eq "S5 reload 핸들러가 reload 직전에 쉼을 재확인" "$(grep -c 'if (!guard(ctx as Ctx)) return;' "$RELOAD")" 1
eq "S6 거절 = 요청 복원(restore)" "$(grep -c 'restore(); pending = true;' "$RELOAD")" 1
bash -n "$0" && ok "S7 bash -n rc0" || bad "S7 bash -n rc0"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1540-bash.XXXXXX")"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
cp "$WAKE" "$T/ext-ft-mbox-wake.ts"; cp "$RELOAD" "$T/ext-ft-reload-request.ts"; cp "$(dirname "$WAKE")/ft-load-line.ts" "$T/"
mkdir -p "$T/node_modules/@earendil-works/pi-coding-agent"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
cat > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs" <<'SHIM'
export const createLocalBashOperations = () => globalThis.__r1540Bash ?? { exec: async () => ({ output: "", exitCode: 0, cancelled: false, truncated: false }) };
SHIM

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const TMP = process.env.R1540_TMP, WAKE = process.env.R1540_WAKE, RELOAD = process.env.R1540_RELOAD;
const SEAT = process.env.R1540_SEAT, RCMD = "/ft-reload-runtime", OTHER = "byz-harness-master-pi#171";
let wakePath = WAKE, modv = 0, fails = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const until = async (fn, ms = 600) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (fn()) return true; await wait(5); } return fn(); };
const ST = { idle: true, reloads: 0 };
const mkCtx = () => ({ isIdle: () => ST.idle, reload: () => { ST.reloads++; return new Promise(() => {}); } }); // reload = «끝»(실 pi)

function env(dir, quiet) {
  const base = path.join(dir, ".fable-team"), state = path.join(base, "state"), comm = path.join(base, "comm");
  fs.mkdirSync(comm, { recursive: true }); fs.mkdirSync(state, { recursive: true });
  fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify({ _master: SEAT, [SEAT]: { role: "master", agent: "pi" } }) + "\n");
  fs.writeFileSync(path.join(comm, "mbox.sh"), "#!/bin/bash\nexit 0\n");
  fs.writeFileSync(path.join(comm, "mailbox.jsonl"), "");
  Object.assign(process.env, { FT_MBOX_ROOT: dir, FT_MBOX_STATE_DIR: state, FT_MBOX_FILE: path.join(comm, "mailbox.jsonl"),
    FT_SEAT: SEAT, FT_MBOX_WAKE_DEBOUNCE_MS: "5", FT_RELOAD_REQUEST_DEBOUNCE_MS: "5", FT_H_DONE_QUIET_MS: String(quiet ?? 40) });
  return { dir, base, state, wake: path.join(state, "pi-wake") };
}
const setupWake = (name, opt = {}) => {
  const c = env(path.join(TMP, name), opt.quiet);
  if (opt.master) fs.writeFileSync(path.join(c.base, "seats-planner.json"), JSON.stringify({ _master: opt.master, [SEAT]: { role: "master", agent: "pi" } }) + "\n");
  return c;
};
const setupReload = (name) => {
  const c = env(path.join(TMP, name));
  c.req = path.join(c.wake, `${SEAT.replace(/[^A-Za-z0-9._#-]/g, "_")}.reload`);
  return c;
};
const errs = [];
const origErr = console.error;
console.error = (...a) => { errs.push(a.map(String).join(" ")); };

const live = [];
async function load(ext, opt = {}) {
  for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); }
  const pi = { calls: [], retired: false, h: {}, cmds: {},
    on(e, f) { (this.h[e] ??= []).push(f); },
    registerCommand(n, o) { this.cmds["/" + n.replace(/^\//, "")] = o; },
    async emit(e, ev = {}) { let out; for (const f of this.h[e] ?? []) { const r = await f(ev, mkCtx()); if (r !== undefined && out === undefined) out = r; } return out; },
    appendEntry() {},
    sendMessage(m, o) { if (!this.retired) pi.calls.push({ m, o }); },
    sendUserMessage(c, o) { if (this.retired) return; pi.calls.push({ c, o });
      if (o?.expandPromptTemplates && c === RCMD && pi.cmds[RCMD]) { if (opt.busyOnce !== undefined && (opt.busyOnce-- > 0)) ST.idle = false; void pi.cmds[RCMD].handler("", mkCtx()); } },
  };
  live.push(pi);
  const mod = await import(`${pathToFileURL(ext).href}?v=${++modv}`);
  mod.default(pi);
  await pi.emit("session_start", {});
  return pi;
}
const hBash = (rc = 0) => { globalThis.__r1540Bash = { exec: async () => ({ output: "out", exitCode: rc, cancelled: false, truncated: false }) }; };
const runH = async (pi, n, rc = 0) => { hBash(rc); const res = await pi.emit("user_bash", { command: `bash /tmp/h${n}`, cwd: "/tmp" }); return res.operations.exec(`bash /tmp/h${n}`, "/tmp", {}); };

// ── ⓐ h 1장 = 즉시 턴 0 · 조용함 창 뒤 1회 ───────────────────────────────────────────────
{
  const c = setupWake("a"); ST.idle = true;
  const pi = await load(wakePath);
  const before = pi.calls.length;
  const out = await runH(pi, 7);
  eq("ⓐ rc·출력 그대로", `${out.exitCode}/${out.output}`, "0/out");
  await wait(15);
  eq("ⓐ 즉시 턴 0", pi.calls.length, before);
  await until(() => pi.calls.length > before);
  eq("ⓐ 창 뒤 턴 1", pi.calls.length - before, 1);
  eq("ⓐ 본문 = h7 끝 rc=0 → recv 하고 [완료] 정리", pi.calls.at(-1)?.m?.content, "h7 끝 rc=0 → recv 하고 [완료] 정리");
  eq("ⓐ 오빠 말 아님(custom) + followUp", `${pi.calls.at(-1)?.m?.customType}/${pi.calls.at(-1)?.o?.deliverAs}/${pi.calls.at(-1)?.o?.triggerTurn}`, "ft-mbox/followUp/true");
  eq("ⓐ 요청 파일 없음(이 경로는 우편함 무관)", fs.existsSync(path.join(c.wake, "x")), false);
  delete globalThis.__r1540Bash;
}

// ── ⓑ 창 안 h 3장 = 턴 1회 · 본문 3줄(번호·rc 순서) ─────────────────────────────────────
{
  setupWake("b"); ST.idle = true;
  const pi = await load(wakePath);
  const before = pi.calls.length;
  await runH(pi, 1, 0); await wait(10);
  await runH(pi, 2, 0); await wait(10);
  await runH(pi, 3, 1);
  await until(() => pi.calls.length > before);
  await wait(80); // 창이 더 지나도 추가 턴 0
  eq("ⓑ 턴 1회", pi.calls.length - before, 1);
  eq("ⓑ 본문 = h 3줄", pi.calls.at(-1)?.m?.content, "h1 끝 rc=0\nh2 끝 rc=0\nh3 끝 rc=1 → recv 하고 [완료] 정리");
  delete globalThis.__r1540Bash;
}

// ── ⓒ 창이 끝났을 때 일하는 중 = 그 자리 0 · 다음 정상 settled 1회(aborted 는 미룸) ────────
{
  setupWake("c"); ST.idle = false;
  const pi = await load(wakePath);
  const before = pi.calls.length;
  await runH(pi, 11);
  await wait(90); // 창 + 기동 창 재확인까지 지나도 0
  eq("ⓒ 일하는 중 = 그 자리 0", pi.calls.length, before);
  ST.idle = true; await pi.emit("agent_settled", { aborted: true });
  eq("ⓒ aborted settled = 0", pi.calls.length, before);
  await pi.emit("agent_settled", {});
  eq("ⓒ 다음 정상 settled = 1", pi.calls.length - before, 1);
  delete globalThis.__r1540Bash;
}

// ── ⓓ 같은 h 결과 두 번 알림 0(보낸 목록은 비운다) ───────────────────────────────────────
{
  setupWake("d"); ST.idle = true;
  const pi = await load(wakePath);
  const before = pi.calls.length;
  await runH(pi, 21);
  await until(() => pi.calls.length > before);
  await pi.emit("agent_settled", {}); await pi.emit("agent_end", {});
  await wait(80);
  eq("ⓓ settled·end 뒤 추가 알림 0", pi.calls.length - before, 1);
  delete globalThis.__r1540Bash;
}

// ── ⓔ h 0 이면 타이머 0(턴 0) · 주기 타이머 0(S4 정적) ───────────────────────────────────
{
  setupWake("e"); ST.idle = true;
  const pi = await load(wakePath);
  const before = pi.calls.length;
  await wait(120);
  eq("ⓔ h 0 = 턴 0", pi.calls.length, before);
}

// ── ⓕ h 아닌 명령·`!!`·비활성 좌석 = 훅 0 ────────────────────────────────────────────────
{
  setupWake("f"); ST.idle = true;
  const pi = await load(wakePath);
  hBash();
  eq("ⓕ `bash /tmp/other.sh` = 훅 0", await pi.emit("user_bash", { command: "bash /tmp/other.sh" }), undefined);
  eq("ⓕ `bash /tmp/h7 extra` = 훅 0", await pi.emit("user_bash", { command: "bash /tmp/h7 extra" }), undefined);
  eq("ⓕ !! = 훅 0", await pi.emit("user_bash", { command: "bash /tmp/h7", excludeFromContext: true }), undefined);
  const before = pi.calls.length;
  setupWake("f2", { master: OTHER });
  const pi2 = await load(wakePath);
  eq("ⓕ 비활성 좌석 = 훅 0", await pi2.emit("user_bash", { command: "bash /tmp/h7" }), undefined);
  const passthrough = { command: "bash /tmp/h7" };
  eq("ⓕ 비활성 좌석 = 턴 0", pi2.calls.length, 0);
  delete globalThis.__r1540Bash;
}

// ── ⓖ reload 거절(일하는 중) = reload 0 · 요청 복원 · 1줄 · 다음 정상 settled 1회 ─────────
{
  const c = setupReload("g"); ST.idle = true; ST.reloads = 0;
  fs.mkdirSync(c.wake, { recursive: true }); fs.writeFileSync(c.req, "reload\n");
  const n0 = errs.length;
  const pi = await load(RELOAD, { busyOnce: 1 });
  await until(() => errs.slice(n0).some((l) => l.includes("reload 거절(일하는 중) — 요청 복원")));
  eq("ⓖ 거절 = reload 0", ST.reloads, 0);
  eq("ⓖ 요청 파일 복원", fs.existsSync(c.req), true);
  eq("ⓖ stderr 1줄", errs.slice(n0).filter((l) => l.includes("reload 거절(일하는 중) — 요청 복원")).length, 1);
  ST.idle = true; await pi.emit("agent_settled", {});
  await until(() => ST.reloads >= 1);
  eq("ⓖ 다음 정상 settled = reload 1", ST.reloads, 1);
  eq("ⓖ reload 뒤 요청 파일 0", fs.existsSync(c.req), false);
}

// ── ⓗ 정상 쉼 = reload 1회 · 요청 파일 0 ─────────────────────────────────────────────────
{
  const c = setupReload("h"); ST.idle = true; ST.reloads = 0;
  fs.mkdirSync(c.wake, { recursive: true }); fs.writeFileSync(c.req, "reload\n");
  await load(RELOAD);
  await until(() => ST.reloads >= 1);
  await wait(60);
  eq("ⓗ 정상 쉼 = reload 1", ST.reloads, 1);
  eq("ⓗ 요청 파일 0", fs.existsSync(c.req), false);
}

// ── 변이 ────────────────────────────────────────────────────────────────────────────────
function mutate(name, src, from, to) {
  const out = src.replace(from, to);
  if (out === src) { bad(`변이 ${name} 치환 미적용(줄 못 찾음)`); return null; }
  const p = path.join(TMP, `mut-${name}.ts`);
  fs.writeFileSync(p, out);
  return p;
}
// M1: 즉시 턴(옛 동작) — 조용함 창 없이 바로 보낸다 → ⓐ 즉시 턴 0 이 FAIL
{
  const src = fs.readFileSync(WAKE, "utf-8");
  const from = "    hTimer = setTimeout(() => { hTimer = null; hArmed = true; try { hFlush(); } catch (e) { fail(`h 끝 처리 실패 — ${e}`); } }, hQuiet);";
  const mut = mutate("M1", src, from, "    hArmed = true; try { hFlush(); } catch (e) { fail(`h 끝 처리 실패 — ${e}`); } // M1: 즉시");
  if (mut) {
    wakePath = mut;
    setupWake("m1"); ST.idle = true;
    const pi = await load(mut);
    const before = pi.calls.length;
    await runH(pi, 31); await wait(15);
    (pi.calls.length > before ? ok : bad)(`M1 → ⓐ 즉시 턴 0 FAIL 검출(즉시 ${pi.calls.length - before}회)`);
    wakePath = WAKE;
    delete globalThis.__r1540Bash;
  }
}
// M2: 창을 다시 재지 않음(clearTimeout 제거) — h 사이 간격 > 창 이면 턴이 쪼개진다 → ⓑ 2회 이상
{
  const src = fs.readFileSync(WAKE, "utf-8");
  const mut = mutate("M2", src, "    if (hTimer) clearTimeout(hTimer);\n", "    // M2: 창 다시 재지 않음\n");
  if (mut) {
    wakePath = mut;
    setupWake("m2", { quiet: 60 }); ST.idle = true;
    const pi = await load(mut);
    const before = pi.calls.length;
    await runH(pi, 41); await wait(35);
    await runH(pi, 42); await wait(35);
    await runH(pi, 43);
    await wait(160);
    (pi.calls.length - before >= 2 ? ok : bad)(`M2 → ⓑ 턴 1회 FAIL 검출(턴 ${pi.calls.length - before}회)`);
    wakePath = WAKE;
    delete globalThis.__r1540Bash;
  }
}
// M3: 거절 때 요청 복원 0 → ⓖ 요청 파일 복원 FAIL
{
  const src = fs.readFileSync(RELOAD, "utf-8");
  const mut = mutate("M3", src, "    restore(); pending = true;", "    pending = true; // M3: 복원 0");
  if (mut) {
    const c = setupReload("m3"); ST.idle = true; ST.reloads = 0;
    fs.mkdirSync(c.wake, { recursive: true }); fs.writeFileSync(c.req, "reload\n");
    await load(mut, { busyOnce: 1 });
    await wait(80);
    (ST.reloads === 0 && !fs.existsSync(c.req) ? ok : bad)(`M3 → ⓖ 요청 복원 FAIL 검출(파일=${fs.existsSync(c.req)} reload=${ST.reloads})`);
  }
}

console.error = origErr;
console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

cmp -s "$WAKE" "$T/ext-ft-mbox-wake.ts" && ok "S8 시험 사본 = 원본 바이트 일치(wake)" || bad "S8 시험 사본 = 원본 바이트 일치(wake)"
cmp -s "$RELOAD" "$T/ext-ft-reload-request.ts" && ok "S9 시험 사본 = 원본 바이트 일치(reload)" || bad "S9 시험 사본 = 원본 바이트 일치(reload)"

R1540_WAKE="$T/ext-ft-mbox-wake.ts" R1540_RELOAD="$T/ext-ft-reload-request.ts" R1540_SEAT="byz-harness-nano-r1540-pi-bash-pending-block-and-reload-r#0" R1540_TMP="$T" \
  timeout 70 node "$T/driver.mjs"; rc=$?

# ── 경계 드라이버(가짜 시계) — DA 277721 R1/ⓘ · R2/ⓙ ──────────────────────────────────────
cat > "$T/boundary.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
const TMP = process.env.R1540_TMP, WAKE = process.env.R1540_WAKE, RELOAD = process.env.R1540_RELOAD, SEAT = process.env.R1540_SEAT;
let fails = 0, wakePath = WAKE;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
// ★가짜 시계★ — 주기 탐색 0 · sleep 0. advance() 가 due 타이머를 «시각 순서로» 돌린다(HARD RULE 22).
let now = 0, next = 1, timers = new Map(), idle = true;
globalThis.setTimeout = (fn, ms) => { const id = next++; timers.set(id, { fn, due: now + Number(ms) }); return id; };
globalThis.clearTimeout = (id) => { timers.delete(id); };
function advance(ms) {
  const end = now + ms;
  for (;;) { const xs = [...timers].filter(([, v]) => v.due <= end).sort((a, b) => a[1].due - b[1].due); if (!xs.length) break; const [id, v] = xs[0]; timers.delete(id); now = v.due; v.fn(); }
  now = end;
}
const keyOf = (s) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
let modv = 0;
function setup(name) {
  timers.clear(); now = 0; idle = true;
  const root = path.join(TMP, name), base = path.join(root, ".fable-team"), comm = path.join(base, "comm"), state = path.join(base, "state");
  fs.mkdirSync(comm, { recursive: true }); fs.mkdirSync(state, { recursive: true });
  fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify({ _master: SEAT, [SEAT]: { agent: "pi" } }) + "\n");
  fs.writeFileSync(path.join(comm, "mailbox.jsonl"), ""); fs.writeFileSync(path.join(comm, "mbox.sh"), "#!/bin/bash\nexit 0\n");
  Object.assign(process.env, { FT_MBOX_ROOT: root, FT_MBOX_FILE: path.join(comm, "mailbox.jsonl"), FT_MBOX_STATE_DIR: state, FT_SEAT: SEAT,
    FT_MBOX_WAKE_DEBOUNCE_MS: "5", FT_RELOAD_REQUEST_DEBOUNCE_MS: "5", FT_H_DONE_QUIET_MS: "20000" });
  return { root, state, wake: path.join(state, "pi-wake"), req: path.join(state, "pi-wake", `${keyOf(SEAT)}.reload`) };
}
function piNew(withReload = false) {
  const pi = { h: {}, cmd: {}, calls: [], reloads: 0, on(e, f) { (this.h[e] ??= []).push(f); },
    appendEntry() {}, registerCommand(n, o) { this.cmd[n] = o; },
    sendMessage(m, o) { this.calls.push({ at: now, m, o }); },
    sendUserMessage(c) { if (this.cmd[c.slice(1)]) void this.cmd[c.slice(1)].handler("", this.ctx); },
    async emit(e, v = {}) { let r; for (const f of this.h[e] ?? []) { const x = await f(v, this.ctx); if (x !== undefined) r = x; } return r; } };
  pi.ctx = { isIdle: () => idle, reload: async () => { pi.reloads++; await pi.emit("session_shutdown"); } };
  return pi;
}
async function load(pi, withReload) {
  const ext = await import(`${pathToFileURL(wakePath).href}?b=${++modv}`);
  ext.default(pi);
  if (withReload) { const r = await import(`${pathToFileURL(RELOAD).href}?b=${++modv}`); r.default(pi); }
  await pi.emit("session_start");
  return pi;
}
const h = async (pi, n) => { const x = await pi.emit("user_bash", { command: `bash /tmp/h${n}` }); await x.operations.exec("", TMP, {}); await new Promise(setImmediate); };

// ⓘ DA 277721 R1 — 창(20000ms) «안» t=1000 에 정상 settled 가 와도 flush 0 · 창 뒤 연속 h 2장 = 최종 1회
{
  setup("b-early"); const pi = await load(piNew());
  idle = false; await h(pi, 1); advance(1000); idle = true; await pi.emit("agent_settled", {});
  eq("ⓘ 창 안 정상 settled = flush 0", pi.calls.length, 0);
  await h(pi, 2); advance(20001); await pi.emit("agent_settled", {});
  eq("ⓘ 창 뒤 연속 h 2장 = 최종 1회", pi.calls.length, 1);
  eq("ⓘ 본문 = h 2장 한 통", pi.calls[0]?.m?.content, "h1 끝 rc=0\nh2 끝 rc=0 → recv 하고 [완료] 정리");
  await pi.emit("session_shutdown");
}
// ⓙ DA 277721 R2 — h 대기 중 reload = session_shutdown → 새 확장 session_start 회수 · 유실 0 · 중복 0
{
  const c = setup("b-reload"); const pi = await load(piNew(), true);
  await h(pi, 3);
  fs.writeFileSync(c.req, "reload\n"); advance(1000); await new Promise(setImmediate);
  eq("ⓙ 옛 확장 reload 1", pi.reloads, 1);
  eq("ⓙ 옛 확장 = 요청 처리 뒤 h 알림 0", pi.calls.length, 0);
  const np = await load(piNew(), true);
  advance(20001); await np.emit("agent_settled", {});
  eq("ⓙ 새 확장 회수 = 1(유실 0)", np.calls.length, 1);
  eq("ⓙ 본문 = h3", np.calls[0]?.m?.content, "h3 끝 rc=0 → recv 하고 [완료] 정리");
  advance(40001); await np.emit("agent_settled", {});
  eq("ⓙ 중복 알림 0", np.calls.length, 1);
  await np.emit("session_shutdown");
}
// ⓚ DA 277737 R3 — t=0 h 완료 → t=1000 reload → 새 session_start 는 «남은 창» 을 존중(즉시 0 · 만료 뒤 1)
{
  const c = setup("b-r3"); const pi = await load(piNew(), true);
  await h(pi, 6);
  fs.writeFileSync(c.req, "reload\n"); advance(1000); await new Promise(setImmediate);
  eq("ⓚ 옛 확장 reload 1", pi.reloads, 1);
  const np = await load(piNew(), true);
  eq("ⓚ 새 시작 즉시 알림 0(남은 창 존중)", np.calls.length, 0);
  advance(20001); // t≈21001 — 완료 시각 + 20000 만료
  eq("ⓚ 남은 창 만료 뒤 1회", np.calls.length, 1);
  eq("ⓚ 본문 = h6", np.calls[0]?.m?.content, "h6 끝 rc=0 → recv 하고 [완료] 정리");
  advance(40001); await np.emit("agent_settled", {});
  eq("ⓚ 중복 알림 0", np.calls.length, 1);
  await np.emit("session_shutdown");
}
// M4 — 정상 settled 가 창을 무시하고 flush → ⓘ 창 안 flush 0 FAIL 검출
{
  const src = fs.readFileSync(WAKE, "utf-8");
  const out = src.replace("    if (hHeld) return;", "    if (hHeld) return; hArmed = true; // M4");
  if (out === src) bad("M4 치환 미적용");
  else {
    fs.writeFileSync(path.join(TMP, "mut-M4.ts"), out);
    const keep = wakePath; wakePath = path.join(TMP, "mut-M4.ts");
    setup("b-m4"); const pi = await load(piNew());
    idle = false; await h(pi, 1); advance(1000); idle = true; await pi.emit("agent_settled", {});
    (pi.calls.length > 0 ? ok : bad)(`M4 → ⓘ 창 안 flush 0 FAIL 검출(flush ${pi.calls.length}회)`);
    wakePath = keep; await pi.emit("session_shutdown");
  }
}
// M6 — hLoad 가 남은 창을 무시하고 즉시 armed → ⓚ 새 시작 즉시 알림 0 FAIL 검출
{
  const src = fs.readFileSync(WAKE, "utf-8");
  const out = src.replace("    if (left <= 0) { hArmed = true; hFlush(); return; }", "    hArmed = true; hFlush(); return; // M6: 남은 창 무시");
  if (out === src) bad("M6 치환 미적용");
  else {
    fs.writeFileSync(path.join(TMP, "mut-M6.ts"), out);
    const keep = wakePath; wakePath = path.join(TMP, "mut-M6.ts");
    const c = setup("b-m6"); const pi = await load(piNew(), true);
    await h(pi, 7); fs.writeFileSync(c.req, "reload\n"); advance(1000); await new Promise(setImmediate);
    const np = await load(piNew(), true);
    (np.calls.length > 0 ? ok : bad)(`M6 → ⓚ 새 시작 즉시 알림 0 FAIL 검출(${np.calls.length}회)`);
    wakePath = keep; await np.emit("session_shutdown");
  }
}
// M5 — 대기 목록 파일 저장 0 → ⓙ 유실 = FAIL 검출
{
  const src = fs.readFileSync(WAKE, "utf-8");
  const out = src.replace("    hDone.push({ n, rc, at: Date.now() }); // ★R3★", "    hDone.push({ n, rc, at: Date.now() }); hSave = () => {}; // ★R3★");
  if (out === src) bad("M5 치환 미적용");
  else {
    fs.writeFileSync(path.join(TMP, "mut-M5.ts"), out);
    wakePath = path.join(TMP, "mut-M5.ts");
    const c = setup("b-m5"); const pi = await load(piNew(), true);
    await h(pi, 5); fs.writeFileSync(c.req, "reload\n"); advance(1000); await new Promise(setImmediate);
    const np = await load(piNew(), true); advance(20001); await np.emit("agent_settled", {});
    (np.calls.length === 0 ? ok : bad)(`M5 → ⓙ 유실 FAIL 검출(회수 ${np.calls.length}회)`);
    await np.emit("session_shutdown");
  }
}
console.log("---");
if (fails === 0) { console.log("BOUNDARY ALL PASS"); process.exit(0); }
console.log(`BOUNDARY FAIL ${fails}`); process.exit(1);
NODE
R1540_WAKE="$T/ext-ft-mbox-wake.ts" R1540_RELOAD="$T/ext-ft-reload-request.ts" R1540_SEAT="byz-harness-nano-r1540-pi-bash-pending-block-and-reload-r#0" R1540_TMP="$T" \
  timeout 70 node "$T/boundary.mjs"; rc2=$?

echo "---"
if [ "$rc" = 0 ] && [ "$rc2" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc boundary_rc=$rc2)"; exit 1
