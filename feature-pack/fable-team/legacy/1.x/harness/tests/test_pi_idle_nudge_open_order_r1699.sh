#!/usr/bin/env bash
# test_pi_idle_nudge_open_order_r1699.sh — r1699: ft-idle-nudge 가 «보내 놓고 회신을 기다리는 발주» 를 일로 센다.
#   ⓐ 발주 1분 전·회신 없음·받는 좌석 살아 있음 → settled 2회 = 턴 0 · [긴급] 0 (지금 = 2회째 [긴급])
#   ⓑ 회신 옴 → 열린 발주 0 → 지금 판정(1회째 턴 1) ⓒ 31분 전·회신 없음 → 지금 판정 + [긴급] «회신 없는 발주 1(#seq)»
#   ⓓ 받는 좌석 죽음(tmux 없음) → 안 셈 ⓔ 닫는 머리([레디]·[받음]·[긴급]·[정리])만 → 0 ⓕ 발신 기록 못 읽음 → 판정 불가·턴 0·[긴급] 0
#   ⓖ FT_IDLE_OPEN_MIN=abc → 30분 ⓗ 회귀 test_pi_idle_nudge_r1530.sh·_route_r1684.sh FAIL 줄이 앞 판과 같다
# 임시 루트·가짜 tmux(PATH)·가짜 bin shim 만 · 실 우편함·실 tmux 0 · sleep 0(시각은 ts 값) · 새 파일 100644
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R1699_EXT:-$HARNESS/pi/ft-idle-nudge.ts}"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$EXT" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/r1699-open.XXXXXX")"; trap 'rm -rf "$T"' EXIT; printf '{"type":"module"}\n' > "$T/package.json"
mkdir -p "$T/stub" "$T/fake/indices/대기" "$T/fake/indices/진행" "$T/bin"
# ── shim(판정 입력) — r1530 과 같은 꼴 ────────────────────────────────────────────────
printf '#!/bin/bash\nF="$(cd "$(dirname "$0")/../.." && pwd)/fake"\necho "★팀별 완성 진행 (abcdef0123)★"\necho "| 팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것 |"\nprintf "| harness | — | 1 | 일 |\\n"\necho "★/팀별 완성 진행★"\n' > "$T/bin/ft-goal-table.sh"
printf '#!/bin/bash\nF="$(cd "$(dirname "$0")/../.." && pwd)/fake"\np=$(ls "$F/indices/진행" 2>/dev/null | grep -c "\\.md$")\necho "카드 대기 0 · 진행 $p(좌석 0) · 착지됐는데 진행 0"\n' > "$T/bin/ft-card-flow.sh"
printf '#!/bin/bash\nF="$(cd "$(dirname "$0")/../.." && pwd)/fake"\ncat "$F/hil" 2>/dev/null; exit 0\n' > "$T/bin/ft-hil.sh"
cat > "$T/bin/mbox.sh" <<'SH'
D="${FT_MBOX_DIR:-$(cd "$(dirname "$0")" && pwd)}"
case "$1" in
  peek) python3 - "$D/mailbox.jsonl" "$2" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print("pending=%d scanned=1 lineage=0" % len([r for r in rows if r.get("to") == sys.argv[2] and r.get("from") != sys.argv[2]]))
PY
  ;;
  send) python3 - "$D/mailbox.jsonl" "$2" "$3" "$4" <<'PY'
import json, sys
f, to, frm, body = sys.argv[1:5]
rows = [json.loads(l) for l in open(f) if l.strip()]
seq = max([r["seq"] for r in rows] + [1000]) + 1
open(f, "a").write(json.dumps({"seq": seq, "ts": "2026-11-11T00:00:00", "to": to, "from": frm, "body": body}, ensure_ascii=False) + "\n")
print("QUEUED seq=%d to=%s" % (seq, to))
PY
  ;;
  *) exit 2;;
esac
SH
chmod +x "$T/bin"/*.sh
# 가짜 tmux — 세션 목록은 $T/sess 파일(없으면 «no server running» rc1)
mkdir -p "$T/path"; printf '#!/bin/sh\nD="$(cd "$(dirname "$0")/.." && pwd)"\nM="$(cat "$D/tmux.mode" 2>/dev/null)"\n[ "$M" = fail ] && { echo "weird failure" >&2; exit 2; }\n[ "$M" = nosession ] && { echo "can\x27t find session" >&2; exit 1; }\n[ -f "$D/sess" ] || { echo "no server running on /tmp/x" >&2; exit 1; }\nshift; cat "$D/sess"\n' > "$T/path/tmux"; chmod +x "$T/path/tmux"
printf 'planner\nharness\n' > "$T/fake/teams"; : > "$T/fake/hil"
cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
const EXT = process.env.R1699_EXT, ROOT = process.env.R1699_TMP;
const SEAT = "byz-harness-master-pi#71", NANO = "byz-harness-nano-r1#0", ARCH = "byz-harness-arch-pi#301", SEAT_OF = (x) => x;
let fails = 0, modv = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const lts = (minAgo) => { const d = new Date(Date.now() - minAgo * 60000), p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`; };
const row = (seq, to, from, body, agoMin) => JSON.stringify({ seq, ts: lts(agoMin), to, from, body });
let CASE = 0;
function setup(name, { log = "", mbox = "", sess = "", env = {} } = {}) {
  const SEATN = SEAT.replace(/#71$/, "#" + (71 + ++CASE));
  const LOG = typeof log === "function" ? log(SEATN) : log;
  const dir = path.join(ROOT, name), base = path.join(dir, ".fable-team"), comm = path.join(base, "comm");
  for (const d of [path.join(base, "bin"), comm, path.join(comm, "receipts"), path.join(base, "state"),
                   path.join(dir, "fake", "indices", "대기"), path.join(dir, "fake", "indices", "진행")]) fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(dir, "fake", "teams"), "planner\nharness\n"); fs.writeFileSync(path.join(dir, "fake", "hil"), "");
  for (const n of ["ft-goal-table.sh", "ft-card-flow.sh", "ft-hil.sh"]) fs.copyFileSync(path.join(ROOT, "bin", n), path.join(base, "bin", n));
  fs.copyFileSync(path.join(ROOT, "bin", "mbox.sh"), path.join(comm, "mbox.sh"));
  fs.writeFileSync(path.join(base, "seats-harness.json"), JSON.stringify({ _master: SEATN, [SEATN]: { role: "master", agent: "pi" } }) + "\n");
  fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify({ _master: "byz-planner-master-pi#244" }) + "\n");
  const mb = path.join(comm, "mailbox.jsonl"); fs.writeFileSync(mb, mbox);
  if (log !== null) fs.writeFileSync(path.join(comm, "mailbox.log.jsonl"), LOG);
  fs.writeFileSync(path.join(ROOT, "sess"), sess);
  Object.assign(process.env, { FT_MBOX_ROOT: dir, FT_MBOX_STATE_DIR: path.join(base, "state"), FT_MBOX_FILE: mb, FT_SEAT: SEATN, ...env });
  return { dir, comm, mb };
}
async function load() {
  const pi = { calls: [], h: {}, on(e, f) { (this.h[e] ??= []).push(f); },
    async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); },
    sendMessage(m, o) { this.calls.push({ m, o }); } };
  const mod = await import(`${pathToFileURL(EXT).href}?v=${++modv}`);
  mod.default(pi); pi.settle = () => pi.emit("agent_settled", { aborted: false });
  return pi;
}
const urgents = (c) => fs.readFileSync(c.mb, "utf-8").split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l)).filter((r) => String(r.body).startsWith("[긴급]"));
const ONLY = process.argv[2] || "";   // 케이스 하나만 — 실행마다 프로세스가 새로 서서 지문 파일이 안 겹친다
const errs = []; const oe = console.error; console.error = (...a) => { errs.push(a.join(" ")); };
// ⓐ 발주 1분 전 · 회신 없음 · 받는 좌석 살아 있음 → 2회 settled = 턴 0 · [긴급] 0
if (!ONLY || ONLY === "a") {
  const c = setup("a", { log: (S) => row(2001, NANO, S, "[발주] 일 하라", 1) + "\n", sess: NANO + "\n" });
  const pi = await load(); errs.length = 0;
  await pi.settle(); await pi.settle();
  eq("ⓐ 열린 발주 = 턴 0(sendMessage 0)", pi.calls.length, 0);
}
// ⓐ-대조 — 같은 픽스처인데 발주 기록만 없으면 1회째 턴 1(«열린 발주가 막았다» 를 이 대조로 증명한다)
if (!ONLY || ONLY === "a0") {
  const c = setup("a0", { log: "", sess: NANO + "\n" });
  const pi = await load(); errs.length = 0;
  await pi.settle();
  eq("ⓐ-대조 발주 기록 0 이면 1회째 턴 1", pi.calls.length, 1);
  eq("ⓐ [긴급] 0", urgents(c).length, 0);
}
// ⓑ 회신 옴 → 열린 발주 0 → 지금 판정(1회째 턴 1)
if (!ONLY || ONLY === "b") {
  const c = setup("b", { log: (S) => row(2001, NANO, S, "[발주] 일 하라", 1) + "\n" + row(2002, S, NANO, "[보고] 끝", 0) + "\n", sess: NANO + "\n" });
  const pi = await load(); errs.length = 0;
  const rd = () => { try { return fs.readFileSync(path.join(c.dir, ".fable-team/state/pi-wake", (process.env.FT_SEAT || "").replace(/[^A-Za-z0-9._#-]/g, "_") + ".idle"), "utf-8").trim(); } catch { return "<없음>"; } };
  await pi.settle();
  if (process.env.R1699_DEBUG) console.log("DBG-B calls=" + pi.calls.length + " nh=" + (pi.h.agent_settled || []).length + " errs=" + JSON.stringify(errs) + " idle=" + (() => { try { return fs.readFileSync(path.join(c.dir, ".fable-team/state/pi-wake", (process.env.FT_SEAT || "").replace(/[^A-Za-z0-9._#-]/g, "_") + ".idle"), "utf-8").trim(); } catch { return "<없음>"; } })());
  eq("ⓑ 회신 오면 지금 판정(1회째 턴 1)", pi.calls.length, 1);
}
// ⓒ 31분 전 · 회신 없음 → 지금 판정 + [긴급] 문구에 «회신 없는 발주 1(2001)»
if (!ONLY || ONLY === "c") {
  const c = setup("c", { log: (S) => row(2001, NANO, S, "[발주] 일 하라", 31) + "\n", sess: NANO + "\n" });
  const pi = await load();
  await pi.settle(); await pi.settle();
  const u = urgents(c);
  eq("ⓒ 31분 = 지금 판정(2회째 [긴급] 1)", u.length, 1);
  eq("ⓒ [긴급] 문구 «회신 없는 발주 1(2001)»", u[0]?.body.includes("회신 없는 발주 1(2001)") ? true : `BODY=${u[0]?.body ?? "<없음>"}`, true);
}
// ⓓ 받는 좌석 죽음(tmux 없음) → 안 셈 → 지금 판정
if (!ONLY || ONLY === "d") {
  const c = setup("d", { log: (S) => row(2001, NANO, S, "[발주] 일 하라", 1) + "\n", sess: "byz-harness-nano-other#0\n" });
  const pi = await load();
  await pi.settle(); await pi.settle();
  eq("ⓓ 받는 좌석 죽음 → 열린 발주 0(2회째 [긴급] 1)", urgents(c).length, 1);
}
// ⓔ 닫는 머리만 → 0
if (!ONLY || ONLY === "e") {
  const lines = (S) => ["[레디]", "[받음]", "[긴급]", "[정리]"].map((h, i) => row(2010 + i, NANO, S, h + " 처리", 1)).join("\n") + "\n";
  const c = setup("e", { log: lines, sess: NANO + "\n" });
  const pi = await load();
  await pi.settle(); await pi.settle();
  eq("ⓔ 닫는 머리 4종 = 열린 발주 0(2회째 [긴급] 1)", urgents(c).length, 1);
}
// ⓕ 발신 기록 못 읽음 → 판정 불가 1줄 · 턴 0 · [긴급] 0
if (!ONLY || ONLY === "f") {
  const c = setup("f", { log: null, sess: NANO + "\n" });
  fs.mkdirSync(path.join(c.comm, "mailbox.log.jsonl"), { recursive: true });   // 폴더 = 읽기 실패(EISDIR)
  const pi = await load(); errs.length = 0;
  await pi.settle(); await pi.settle();
  eq("ⓕ 판정 불가 = 턴 0", pi.calls.length, 0);
  eq("ⓕ [긴급] 0", urgents(c).length, 0);
  eq("ⓕ «판정 불가» 1줄 이상", errs.some((e) => e.includes("판정 불가")), true);
}
// ⓖ FT_IDLE_OPEN_MIN=abc → 30분(31분 발주는 창 밖)
if (!ONLY || ONLY === "g") {
  const c = setup("g", { log: (S) => row(2001, NANO, S, "[발주] 일 하라", 31) + "\n", sess: NANO + "\n", env: { FT_IDLE_OPEN_MIN: "abc" } });
  const pi = await load();
  await pi.settle(); await pi.settle();
  eq("ⓖ abc = 30분 → 31분 발주는 창 밖([긴급] 1)", urgents(c).length, 1);
}
// ── 단위: openOrdersOf 순수 함수(회신·생존·창·닫는 머리) — 변이 M2·M4 가 여기서 걸린다 ────────────
if (!ONLY || ONLY === "u") {
  const m = await import(pathToFileURL(EXT).href + "?u=" + (++modv));
  const now = Date.now(), ago = (min) => lts(min);
  const S = "byz-u-seat#0", L = new Set([NANO]);
  const ord = (over = {}) => ({ seq: 1, ts: ago(1), to: NANO, from: S, body: "[발주] 일", ...over });
  eq("단위 열린 발주 1(회신 없음·살아 있음·창 안)", m.openOrdersOf([ord()], S, L, 30, now).open, 1);
  eq("단위 회신 오면 0", m.openOrdersOf([ord(), { seq: 2, ts: ago(0), to: S, from: NANO, body: "[보고]" }], S, L, 30, now).open, 0);
  eq("단위 받는 좌석 죽음 → 0", m.openOrdersOf([ord()], S, new Set(), 30, now).open, 0);
  eq("단위 31분 → 창 밖 stale 1(가장 오래된 seq)", m.openOrdersOf([ord({ ts: ago(31) })], S, L, 30, now).stale, 1);
  eq("단위 닫는 머리 → 0", m.openOrdersOf([ord({ body: "[레디] 처리" })], S, L, 30, now).open, 0);
}
// ⓘ R1 — 보내는 접두어 [발신->수신] 뒤의 닫는 머리는 닫는 보고로 본다 · 접두어가 없으면 지금 그대로
if (!ONLY || ONLY === "i") {
  const m = await import(pathToFileURL(EXT).href + "?i=" + (++modv));
  const now = Date.now(), S = "byz-i-seat#0", L = new Set([NANO]);
  const r = (body) => ({ seq: 1, ts: lts(1), to: NANO, from: S, body });
  eq("ⓘ 접두어 뒤 [레디] = 닫는 보고(open 0)", m.openOrdersOf([r("[byz-i-seat#0->byz-nano#1] [레디] 정리 완료")], S, L, 30, now).open, 0);
  eq("ⓘ 접두어 뒤 [긴급] = 닫는 보고(open 0)", m.openOrdersOf([r("[a->b] [긴급] 확인 부탁")], S, L, 30, now).open, 0);
  eq("ⓘ 접두어만 있고 닫는 머리 없음 = 열린 발주 1", m.openOrdersOf([r("[a->b] 작업 하라")], S, L, 30, now).open, 1);
}
// ⓙ R2 — tmux «can't find session/noserver» 만 세션 0 · 그 밖 실패(rc2 등) = 판정 불가(턴 0 · [긴급] 0)
if (!ONLY || ONLY === "j") {
  const c1 = setup("j1", { log: "", sess: "", env: {} }); fs.writeFileSync(path.join(path.dirname(c1.dir), "tmux.mode"), "fail");
  const p1 = await load(); errs.length = 0;
  await p1.settle(); await p1.settle();
  eq("ⓙ tmux 그 밖 실패 = 턴 0", p1.calls.length, 0);
  eq("ⓙ tmux 그 밖 실패 = [긴급] 0", urgents(c1).length, 0);
  eq("ⓙ «판정 불가» 1줄", errs.some((e) => e.includes("판정 불가")), true);
}
// ⓚ R3(planner #286260) — 남의 팀 카드를 relay 로 받은 팀장: 자기 팀 진행 카드 0 이어도 arch 에 발주해 회신 대기 중이면 일 있음
if (!ONLY || ONLY === "k") {
  const c = setup("k", { log: (S) => row(3001, SEAT_OF(S), "byz-planner-master-pi#264", "[relay] harness 카드 인계", 3) + "\n"
                                    + row(3002, ARCH, S, "[발주] 설계 1건 — harness 카드", 2) + "\n", sess: ARCH + "\n" });
  const pi = await load(); errs.length = 0;
  await pi.settle(); await pi.settle();
  eq("ⓚ R3 relay 받은 팀장 · arch 발주 회신 대기 = 턴 0", pi.calls.length, 0);
  eq("ⓚ R3 [긴급] 0", urgents(c).length, 0);
}
console.error = oe;
if (process.env.R1699_DEBUG) console.log("ERRS " + JSON.stringify(errs.slice(-6)));
console.log(`FAILED ${fails}`);
process.exit(fails ? 1 : 0);
NODE
# 확장 사본(ft-mbox-wake·ft-load-line 형제) + pi 패키지 스텁 — node 가 $T/node_modules 를 찾는다(cwd=$T)
mkdir -p "$T/ext" "$T/node_modules/@earendil-works/pi-coding-agent"
cp "$(dirname "$EXT")/ft-mbox-wake.ts" "$(dirname "$EXT")/ft-load-line.ts" "$T/ext/"; printf '{"type":"module"}\n' > "$T/ext/package.json"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
echo 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0 }) });' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"
EXTC="$T/ext/ft-idle-nudge.ts"
RUNN=0
drv() { local r c="${1:-}"; RUNN=$((RUNN+1)); r="$T/run$RUNN"; mkdir -p "$r"; cp -R "$T/bin" "$T/path" "$r/"; ( cd "$r" && R1699_EXT="$EXTC" R1699_TMP="$r" PATH="$r/path:$PATH" node "$T/driver.mjs" ${c:+"$c"} 2>&1 ); }
drv_all() { local c o; for c in a0 a b c d e f g i j k; do o="$(drv "$c")"; echo "$o" | grep -E '^(PASS|FAIL) ' ; done; }
# ── Red 먼저 — 고침 전(HEAD 판) 으로 돌리면 ⓐ 가 턴 2·[긴급] 으로 실패해야 한다 ─────────────
# Red 판 = r1699 이전(origin/main) — 이 가지에 커밋이 쌓여도 «고침 전» 은 origin/main 이다
RBASE="$(git -C "$HARNESS" merge-base HEAD origin/main 2>/dev/null)"   # 고침 직전 판 = 이 가지가 갈라진 고정 커밋(떠다니는 이름 아님)
[ -n "$RBASE" ] && git -C "$HARNESS" show "$RBASE:feature-pack/fable-team/legacy/1.x/harness/pi/ft-idle-nudge.ts" > "$EXTC" 2>/dev/null || cp "$EXT" "$EXTC"
r="$(drv a)"; grep -qE '^FAIL ⓐ' <<<"$r" && ok "Red — 고침 전 판은 ⓐ 에서 실패(턴·[긴급] 발생)" || bad "Red 확인 실패" "$(grep -E '^FAIL ' <<<"$r" | head -1)"
r="$(drv k)"; grep -qE '^FAIL ⓚ' <<<"$r" && ok "Red R3 — 고침 전 판은 ⓚ(relay 받은 팀장)에서 실패" || bad "Red R3 확인 실패"
cp "$EXT" "$EXTC"
echo "--- 기본(고침 후) ---"
r="$(drv_all)"; echo "$r" | sed 's/^/  /'
grep -qE '^FAIL ' <<<"$r" && { echo "$r" | grep -E '^FAIL ' | sed 's/^/  /'; fail=$((fail+$(grep -cE '^FAIL ' <<<"$r"))); } || ok "사례 ⓐ~ⓖ ALL PASS"
# ── 변이 4종(사본에서만 · 변이마다 형제 파일까지 새 ext 폴더 = 고립 실행과 같은 꼴) ──────────
mkx() {  # mkx <이름> <old> <new> → ext 폴더 경로
  local d="$T/mx-$1"; mkdir -p "$d"; cp "$(dirname "$EXT")/ft-mbox-wake.ts" "$(dirname "$EXT")/ft-load-line.ts" "$d/"; printf '{"type":"module"}\n' > "$d/package.json"
  python3 - "$EXT" "$d/ft-idle-nudge.ts" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old[:60]
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  printf '%s\n' "$d"; }
drvx() { local d="$1" c="$2" r; RUNN=$((RUNN+1)); r="$T/iso$RUNN"; mkdir -p "$r"; cp -R "$T/bin" "$T/path" "$r/"; cp "$T/driver.mjs" "$r/"; cp -R "$T/node_modules" "$r/"; ( cd "$r" && R1699_EXT="$d/ft-idle-nudge.ts" R1699_TMP="$r" PATH="$r/path:$PATH" node "$r/driver.mjs" "$c" 2>&1 ); }
X="$(mkx m1 'const ord = openOrders(live);' 'const ord = { open: 0, stale: 0, oldest: 0 };')"
X="$(mkx m2 'const replied = rows.some(' 'const replied = false && rows.some(')"
X="$(mkx m3 'now - ts <= win' 'true')"
r="$(drvx "$X" c)"; grep -qE '^FAIL ⓒ' <<<"$r" && ok "M3 시간 창 삭제 → ⓒ FAIL(검출됨)" || bad "M3 검출 실패"
X="$(mkx m4 'if (replied || !live.has(to)) continue;' 'if (replied) continue;')"
# ── ⓗ 회귀 — 기존 idle-nudge 시험 2파일 새 FAIL 0 ────────────────────────────────────────
n=0; for t in test_pi_idle_nudge_r1530.sh test_pi_idle_nudge_route_r1684.sh; do m="$(timeout 70 bash "$HERE/$t" 2>&1 | grep -cE '^FAIL ')"; n=$((n+m)); done
[ "$n" = 0 ] && ok "ⓗ 회귀 idle-nudge 2파일 FAIL 0(앞 판과 같다)" || bad "ⓗ 회귀 FAIL $n 줄"
mkx_line() {  # mkx_line <이름> <줄에_든_조각> <새_줄> — 줄 단위 변이(따옴표 문제 회피)
  local d="$T/mx-$1"; mkdir -p "$d"; cp "$(dirname "$EXT")/ft-mbox-wake.ts" "$(dirname "$EXT")/ft-load-line.ts" "$d/"
  printf '{"type":"module"}\n' > "$d/package.json"
  python3 - "$EXT" "$d/ft-idle-nudge.ts" "$2" "$3" <<'PY'
import sys
src, dst, needle, new = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if needle in l]
assert hit, "변이 대상 줄 없음: " + needle
lines[hit[0]] = new
open(dst, "w", encoding="utf-8").write("\n".join(lines))
PY
  printf '%s\n' "$d"; }
X="$(mkx_line m5 'head = bodyHead(r.body)' '    const to = String(r.to ?? ""), head = String(r.body ?? "").trim().slice(0, 4);')"
r="$(drvx "$X" i)"; grep -qE '^FAIL ⓘ' <<<"$r" && ok "M5 접두어 벗기기 삭제 → ⓘ FAIL(검출됨)" || bad "M5 검출 실패"
X="$(mkx_line m6 'no server running' '      return new Set();')"
r="$(drvx "$X" j)"; grep -qE '^FAIL ⓙ' <<<"$r" && ok "M6 tmux 실패 구분 삭제 → ⓙ FAIL(검출됨)" || bad "M6 검출 실패"
echo "FAILED $fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit $([ "$fail" = 0 ] && echo 0 || echo 1)
