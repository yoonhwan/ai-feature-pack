#!/usr/bin/env bash
# test_pi_reload_request_r1531.sh — r1531: pi 확장 ft-reload-request
#   요청 파일(<state>/pi-wake/<좌표키>.reload) 1개 = reload 1회 · 파일은 reload 전에 지운다 · 좌석이 쉬면 바로 · 일하면 agent_settled.
#  격리: 임시 루트(<케이스>/.fable-team/state) · 합성 seats-planner.json · 가짜 pi(registerCommand·sendUserMessage 기록 · isIdle 주입 ·
#        ctx.reload 스텁 — 핸들러가 부르면 «끝나지 않는» 약속 = 실 pi 의 «reload 뒤 코드는 옛 판본» 을 흉내) · 실 pi·실 /reload·실 Redis 0 · sleep 0.
#  사례: ⓐ 쉼 = 즉시 1 · ⓑ 일하는 중 = 그 자리 0 · settled 1 · ⓒ 쓰기 3번 = 1 · ⓓ 다른 좌석키 = 0
#        ⓔ 비활성 좌석 = 0(파일 그대로) · ⓕ 지우기 실패 = 0 + ERROR 1줄 · ⓖ 핸들러 = reload 1회가 끝 · ⓗ 중단 settled = 미룸 · ⓘ 시작 회수 = 1
#  변이: M1 지우기를 reload 뒤로 = ⓘ 에서 reload 반복 FAIL · M2 isIdle 검사 끔 = ⓑ 그 자리 1 FAIL
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R1531_EXT:-$HARNESS/pi/ft-reload-request.ts}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$EXT" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }

# ── 정적 계약 ─────────────────────────────────────────────────────────────────────────
eq "S1 확장 $(wc -l < "$EXT" | tr -d ' ')줄 ≤200" "$([ "$(wc -l < "$EXT" | tr -d ' ')" -le 200 ] && echo yes || echo no)" yes
eq "S2 요청 파일 = <state>/pi-wake/<좌표키>.reload" "$(grep -c 'const req = path.join(wakeDir, `${keyOf(seat)}.reload`);' "$EXT")" 1
eq "S3 지우기가 요청보다 앞(check 안 take < fire)" "$(awk '/if \(!take\(\)\) return;/{t=NR} /^ *fire\(\);/{if(!f)f=NR} END{print (t&&f&&t<f)?"yes":"no"}' "$EXT")" yes
eq "S4 setInterval 0" "$(grep -c 'setInterval' "$EXT")" 0
bash -n "$0" && ok "S5 bash -n rc0" || bad "S5 bash -n rc0"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1531-reload.XXXXXX")"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const EXT = process.env.R1531_EXT, SEAT = process.env.R1531_SEAT, ROOT = process.env.R1531_TMP;
let EXTv = EXT, modv = 0, fails = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const keyOf = (s) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
const OTHER = "byz-harness-nano-other#7";
const CMD = "/ft-reload-runtime";
const ST = { idle: true, reloads: 0, sent: [], errs: [] };
const mkCtx = () => ({
  isIdle: () => ST.idle,
  // 실 pi: ctx.reload() 는 «끝» — 그 뒤 코드는 옛 판본으로 돈다(docs/extensions.md:1512). 시험은 끝나지 않는 약속으로 흉내 낸다.
  reload: () => { ST.reloads++; return new Promise(() => {}); },
});

function setup(name, seats) {
  const dir = path.join(ROOT, name), base = path.join(dir, ".fable-team"), state = path.join(base, "state");
  fs.mkdirSync(state, { recursive: true });
  fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify(seats) + "\n");
  Object.assign(process.env, { FT_MBOX_ROOT: dir, FT_MBOX_STATE_DIR: state, FT_SEAT: SEAT, FT_RELOAD_REQUEST_DEBOUNCE_MS: "5" });
  ST.idle = true; ST.reloads = 0; ST.sent = []; ST.errs = [];
  return { dir, wake: path.join(state, "pi-wake"), req: path.join(state, "pi-wake", `${keyOf(SEAT)}.reload`) };
}
const MINE = { _master: SEAT, [SEAT]: { role: "master", agent: "pi" } };
const NANO = { _master: OTHER, [OTHER]: { role: "master", agent: "pi" }, [SEAT]: { role: "nano", agent: "pi" } };

const live = [];
async function load() {
  for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); }
  const pi = { calls: [], cmds: {}, h: {}, retired: false,
    on(e, f) { (this.h[e] ??= []).push(f); },
    registerCommand(n, o) { this.cmds["/" + n.replace(/^\//, "")] = o; }, // 실 pi 처럼 이름은 슬래시 없이 등록 · 호출은 /이름
    async emit(e, ev = {}) { let out; for (const f of this.h[e] ?? []) { const r = await f(ev, mkCtx()); if (r !== undefined && out === undefined) out = r; } return out; },
    // 실 pi 와 같은 길: expandPromptTemplates = 명령 디스패치(모델 입력 0)
    sendUserMessage(c, o) { if (this.retired) return; this.calls.push({ c, o }); if (o?.expandPromptTemplates && c === CMD && this.cmds[CMD]) void this.cmds[CMD].handler("", mkCtx()); },
  };
  live.push(pi);
  const mod = await import(`${pathToFileURL(EXTv).href}?v=${++modv}`);
  mod.default(pi);
  await pi.emit("session_start", {});
  return pi;
}
const errN = () => ST.errs.filter((l) => l.startsWith("ERROR ft-reload-request")).length;
const origErr = console.error;
console.error = (...a) => { ST.errs.push(a.join(" ")); };

// ── ⓐ 쉼 = 요청 파일 생김 → 지움 → 명령 1회(expandPromptTemplates) ─────────────────────────────
{
  const c = setup("a", MINE);
  fs.mkdirSync(c.wake, { recursive: true }); fs.writeFileSync(c.req, "reload\n");
  const pi = await load();
  eq("ⓐ 쉼 = 명령 1회", pi.calls.length, 1);
  eq("ⓐ 명령 = /ft-reload-runtime ∧ expandPromptTemplates", `${pi.calls[0]?.c}|${pi.calls[0]?.o?.expandPromptTemplates}`, `${CMD}|true`);
  eq("ⓐ reload 1회", ST.reloads, 1);
  eq("ⓐ 요청 파일 지움", fs.existsSync(c.req), false);
}

// ── ⓑ 일하는 중(isIdle false) 요청 = 그 자리 0 · 다음 agent_settled 에서 1 ────────────────────────
{
  const c = setup("b", MINE);
  ST.idle = false;
  const pi = await load();
  fs.mkdirSync(c.wake, { recursive: true }); fs.writeFileSync(c.req, "reload\n");
  await wait(320); // 사건 폴링 + 기동 창 재확인까지 지나도 0
  eq("ⓑ 일하는 중 = 그 자리 0", ST.reloads, 0);
  eq("ⓑ 요청 파일 남음", fs.existsSync(c.req), true);
  ST.idle = true; await pi.emit("agent_settled", {});
  eq("ⓑ settled 에서 1", ST.reloads, 1);
  eq("ⓑ settled 뒤 파일 지움", fs.existsSync(c.req), false);
}

// ── ⓒ 같은 요청 파일에 쓰기 3번(사건 3회) = 1 ────────────────────────────────────────────────
{
  const c = setup("c", MINE);
  const pi = await load();
  fs.mkdirSync(c.wake, { recursive: true });
  for (let i = 0; i < 3; i++) fs.writeFileSync(c.req, `reload ${i}\n`);
  await wait(200);
  eq("ⓒ 쓰기 3번 = 1", ST.reloads, 1);
  eq("ⓒ 파일 지움", fs.existsSync(c.req), false);
}

// ── ⓓ 다른 좌석키 파일 = 0 ────────────────────────────────────────────────────────────────
{
  const c = setup("d", MINE);
  const pi = await load();
  fs.mkdirSync(c.wake, { recursive: true });
  fs.writeFileSync(path.join(c.wake, `${keyOf(OTHER)}.reload`), "reload\n");
  await wait(320);
  eq("ⓓ 다른 좌석키 = 0", ST.reloads, 0);
  eq("ⓓ 내 파일 없음", fs.existsSync(c.req), false);
}

// ── ⓔ 비활성 좌석(나노) = 0 · 파일 그대로 ──────────────────────────────────────────────────
{
  const c = setup("e", NANO);
  fs.mkdirSync(c.wake, { recursive: true }); fs.writeFileSync(c.req, "reload\n");
  const pi = await load();
  await wait(320);
  eq("ⓔ 비활성 좌석 = 0", ST.reloads, 0);
  eq("ⓔ 파일 그대로", fs.existsSync(c.req), true);
}

// ── ⓕ 지우기 실패(읽기 전용 폴더) = reload 0 + ERROR 1줄 · 파일 그대로 ───────────────────────────
{
  const c = setup("f", MINE);
  fs.mkdirSync(c.wake, { recursive: true }); fs.writeFileSync(c.req, "reload\n");
  fs.chmodSync(c.wake, 0o500);
  const pi = await load();
  await wait(400); // 기동 창 재확인까지 = 같은 실패 1회 더 → ERROR 는 여전히 1줄
  eq("ⓕ 지우기 실패 = reload 0", ST.reloads, 0);
  eq("ⓕ ERROR 1줄", errN(), 1);
  eq("ⓕ 파일 그대로", fs.existsSync(c.req), true);
  fs.chmodSync(c.wake, 0o700);
}

// ── ⓖ 명령 핸들러 = ctx.reload() 1회가 끝(그 뒤 pi 호출 0) ────────────────────────────────
{
  const c = setup("g", MINE);
  const pi = await load();
  let n = 0;
  const ctx = { isIdle: () => true, reload: async () => { n++; return; } }; // 끝나는 reload = 핸들러가 return 까지 간다
  const before = pi.calls.length;
  const out = await pi.cmds[CMD].handler("", ctx);
  eq("ⓖ reload 1회", n, 1);
  eq("ⓖ 핸들러 return(undefined)", out, undefined);
  eq("ⓖ 핸들러가 다른 pi 호출 0", pi.calls.length, before);
}

// ── ⓗ 중단(aborted) settled = 0 · 다음 settled 로 미룸 ───────────────────────────────────────
{
  const c = setup("h", MINE);
  ST.idle = false;
  const pi = await load();
  fs.mkdirSync(c.wake, { recursive: true }); fs.writeFileSync(c.req, "reload\n");
  await wait(120);
  ST.idle = true; await pi.emit("agent_settled", { aborted: true });
  eq("ⓗ aborted settled = 0", ST.reloads, 0);
  eq("ⓗ 파일 남음", fs.existsSync(c.req), true);
  await pi.emit("agent_settled", {});
  eq("ⓗ 다음 settled = 1", ST.reloads, 1);
}

// ── ⓘ 세션 시작 때 이미 있는 요청 파일 = 1(기동 창 재확인 1회) ────────────────────────────────
{
  const c = setup("i", MINE);
  fs.mkdirSync(c.wake, { recursive: true }); fs.writeFileSync(c.req, "reload\n");
  const pi = await load();
  await wait(400); // 재확인 지나도 1 — 지웠으므로 두 번째 0
  eq("ⓘ 시작 회수 = 1", ST.reloads, 1);
  eq("ⓘ 재확인 뒤에도 파일 없음", fs.existsSync(c.req), false);
}

// ── 변이 M1: 지우기를 reload 뒤로(= take 제거) → ⓘ 에서 reload 반복 = FAIL 검출 ──────────────────
function mutate(name, from, to) {
  const src = fs.readFileSync(EXT, "utf-8"), out = src.replace(from, to);
  if (out === src) { bad(`변이 ${name} 치환 미적용(줄 못 찾음)`); return null; }
  const p = path.join(path.dirname(EXT), `mut-${name}.ts`);
  fs.writeFileSync(p, out);
  return p;
}
{
  const mut = mutate("M1", "    if (!take()) return; // 지우기 실패 = reload 0", "    // M1: 지우기를 reload 뒤로(지움 0)");
  if (mut) {
    EXTv = mut;
    const c = setup("m1", MINE);
    fs.mkdirSync(c.wake, { recursive: true }); fs.writeFileSync(c.req, "reload\n");
    await load();
    await wait(400);
    (ST.reloads >= 2 ? ok : bad)(`M1 → ⓘ reload 반복 FAIL 검출(reload ${ST.reloads}회)`);
    EXTv = EXT;
  }
}
// ── 변이 M2: isIdle 검사 끔 → ⓑ 그 자리 1 = FAIL 검출 ─────────────────────────────────────
{
  const mut = mutate("M2", "    if (!idle()) { pending = true; return; } // 일하는 중 = 그 자리 0 · 다음 agent_settled 에서 1", "    // M2: isIdle 검사 끔");
  if (mut) {
    EXTv = mut;
    const c = setup("m2", MINE);
    ST.idle = false;
    await load();
    fs.mkdirSync(c.wake, { recursive: true }); fs.writeFileSync(c.req, "reload\n");
    await wait(200);
    (ST.reloads >= 1 ? ok : bad)(`M2 → ⓑ 그 자리 reload FAIL 검출(reload ${ST.reloads}회)`);
    EXTv = EXT;
  }
}

console.error = origErr;
console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

cp "$EXT" "$T/ext-ft-reload-request.ts"
cmp -s "$EXT" "$T/ext-ft-reload-request.ts" && ok "S6 시험 사본 = 원본 바이트 일치" || bad "S6 시험 사본 = 원본 바이트 일치"

R1531_EXT="$T/ext-ft-reload-request.ts" R1531_SEAT="byz-harness-master-pi#171" R1531_TMP="$T" \
  timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
if [ "$rc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc)"; exit 1
