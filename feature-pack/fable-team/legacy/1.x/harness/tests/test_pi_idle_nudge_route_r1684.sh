#!/usr/bin/env bash
# test_pi_idle_nudge_route_r1684.sh — r1684: ①[긴급] 받는이 = planner 팀장(_master · desk 아님) ②골 원장 없는 루트 = 골 칸 열림 + 세션당 INFO 1줄
# 격리: 임시 루트(.fable-team/{bin,comm,state} · design/TEAMS.md · fake/{teams,indices,hil,sends.log}) · 스텁 shim 4개 · 가짜 pi · 실 루트·실 우편함 0 · sleep 0
# 사례 ⓐ 받는이 ⓑ 원장 없는 루트 ⓒ 원장 있는 루트 ⓓ 판정 불가 유지 · 회귀 2파일은 이 파일 밖(RUN 줄에 rc·초)
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R1684_EXT:-$HARNESS/pi/ft-idle-nudge.ts}"; WAKE="$(dirname "$EXT")/ft-mbox-wake.ts"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$EXT" ] && [ -f "$WAKE" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }
CODE="$(grep -v '^[[:space:]]*//' "$EXT")"   # 머리 주석 줄은 빼고 코드 줄만 본다
eq "S2 [긴급] 받는이 = plannerMaster(._desk 접근 0)" "$(grep -c '\._desk' <<<"$CODE")$(grep -c 'plannerMaster()' <<<"$CODE")" 01

T="$(mktemp -d "${TMPDIR:-/tmp}/r1684-route.XXXXXX")"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/stub"
printf '#!/bin/sh\nF="$(cd "$(dirname "$0")/../.." && pwd)/fake"; [ -e "$F/goal.fail" ] && { echo "ERROR planner 은 팀 명단에 없다" >&2; exit 1; }\necho "★팀별 완성 진행 (abcdef0123)★"\nwhile IFS= read -r t; do [ -n "$t" ] && echo "| $t | — |"; done < "$F/teams"\necho "★/팀별 완성 진행★"\n' > "$T/stub/ft-goal-table.sh"
cat > "$T/stub/ft-card-flow.sh" <<'SH'
D="$(cd "$(dirname "$0")/../.." && pwd)/fake"; echo "카드 대기 0 · 진행 $(ls "$D/indices/진행" 2>/dev/null | grep -c '\.md$')(좌석 0)"
SH
printf '#!/bin/sh\ncat "$(cd "$(dirname "$0")/../.." && pwd)/fake/hil" 2>/dev/null\nexit 0\n' > "$T/stub/ft-hil.sh"
cat > "$T/stub/mbox.sh" <<'SH'
D="$(cd "$(dirname "$0")/../.." && pwd)"
[ "$1" = peek ] && { echo "pending=0 scanned=1 lineage=0"; exit 0; }
[ "$1" = send ] || exit 2
printf '%s\t%s\n' "$2" "$4" >> "$D/fake/sends.log"; echo "QUEUED seq=1 to=$2"
SH
cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs"; import * as path from "node:path"; import { pathToFileURL } from "node:url";
const EXT = process.env.R1684_EXT, ROOT = process.env.R1684_TMP, STUB = process.env.R1684_STUB;
const SEAT = "byz-harness-master-pi#171", MASTER = "byz-planner-master-pi#244", DESK = "byz-planner-desk-pi#9";
const MD_PLANNER = "| 팀 | 폴더 |\n|---|---|\n| planner | `design/teams/planner/` |\n| harness | `design/harness/` |\n";
const MD_AIFP = "| 팀 | 폴더 |\n|---|---|\n| aifp | `design/aifp/` |\n";
let fails = 0, modv = 0;
const errs = [], origErr = console.error; console.error = (...a) => errs.push(a.join(" "));
const ok = (n) => console.log(`PASS ${n}`), bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, a, b) => (String(a) === String(b) ? ok(n) : bad(n, `기대 '${b}' 실제 '${a}'`));
const keyOf = (s) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
function setup(name, { teams = "planner\nharness\n", md = MD_PLANNER, goalFail = false, prog = 0 } = {}) {
  const dir = path.join(ROOT, name), b = path.join(dir, ".fable-team"), fake = path.join(dir, "fake");
  for (const [base, d] of [[b, "bin"], [b, "comm/receipts"], [b, "state"], [dir, "design"], [dir, "fake/indices/대기"], [dir, "fake/indices/진행"]]) fs.mkdirSync(path.join(base, d), { recursive: true });
  for (const n of ["ft-goal-table.sh", "ft-card-flow.sh", "ft-hil.sh"]) fs.copyFileSync(path.join(STUB, n), path.join(b, "bin", n));
  fs.copyFileSync(path.join(STUB, "mbox.sh"), path.join(b, "comm", "mbox.sh"));
  fs.writeFileSync(path.join(b, "seats-harness.json"), JSON.stringify({ _master: SEAT, [SEAT]: { role: "master", agent: "pi" } }) + "\n");
  fs.writeFileSync(path.join(b, "seats-planner.json"), JSON.stringify({ _master: MASTER, _desk: DESK, [MASTER]: { role: "master", agent: "pi" } }) + "\n");
  fs.writeFileSync(path.join(fake, "teams"), teams); fs.writeFileSync(path.join(fake, "hil"), ""); fs.writeFileSync(path.join(fake, "sends.log"), "");
  if (goalFail) fs.writeFileSync(path.join(fake, "goal.fail"), "1");
  if (md !== null) fs.writeFileSync(path.join(dir, "design", "TEAMS.md"), md);
  for (let i = 0; i < prog; i++) fs.writeFileSync(path.join(fake, "indices", "진행", `r${i}.md`), "x");
  const mbox = path.join(b, "comm", "mailbox.jsonl"); fs.writeFileSync(mbox, ""); Object.assign(process.env, { FT_MBOX_ROOT: dir, FT_MBOX_STATE_DIR: path.join(b, "state"), FT_MBOX_FILE: mbox, FT_SEAT: SEAT });
  return { sends: path.join(fake, "sends.log"), idle: path.join(b, "state", "pi-wake", `${keyOf(SEAT)}.idle`) };
}
async function load() {
  const pi = { calls: [], h: {}, on(e, f) { (this.h[e] ??= []).push(f); }, sendMessage(m, o) { this.calls.push({ m, o }); } };
  const mod = await import(`${pathToFileURL(EXT).href}?v=${++modv}`); mod.default(pi);
  pi.settle = async () => { for (const f of pi.h.agent_settled ?? []) await f({ aborted: false }); };
  return pi;
}
const sends = (c) => fs.readFileSync(c.sends, "utf-8").split("\n").filter(Boolean).map((l) => l.split("\t"));
const nInfo = () => errs.filter((e) => e.includes("INFO 골 원장 없는 루트")).length;
{ // ⓐ 2회째 [긴급] 받는이 = planner 팀장 · desk 앞 0
  const c = setup("a"), pi = await load(); await pi.settle(); await pi.settle();
  const g = sends(c).filter((r) => r[1].startsWith("[긴급]"));
  eq("ⓐ [긴급] 1통 · 받는이 = _master", `${g.length}/${g[0]?.[0]}`, `1/${MASTER}`);
  eq("ⓐ desk 앞 send 0 · 턴 1", `${sends(c).filter((r) => r[0] === DESK).length}/${pi.calls.length}`, "0/1");
}
{ // ⓑ planner 행 없는 루트 + 골 표 rc1 → 골 칸 열림 · 턴 1 · INFO 1줄 · 판정 불가 0
  const c = setup("b", { md: MD_AIFP, goalFail: true }); errs.length = 0;
  const pi = await load(); await pi.settle();
  eq("ⓑ 턴 1(1회째) · 판정 불가 0", `${pi.calls.length}/${errs.filter((e) => e.includes("판정 불가")).length}`, "1/0");
  await pi.settle();
  eq("ⓑ INFO 1줄(세션당)", nInfo(), 1);
}
{ // ⓒ planner 행 있는 루트 = 지금과 같다(골 표로 판정 · 열림/닫힘 둘 다)
  const c1 = setup("c1"), pi = await load(); errs.length = 0; await pi.settle();
  eq("ⓒ 열림 = 턴 1 · INFO 0", `${pi.calls.length}/${nInfo()}`, "1/0");
  const c2 = setup("c2", { teams: "planner\n" }), pi2 = await load(); await pi2.settle();
  eq("ⓒ 닫힘 = 턴 0 · 지문 파일 없음", `${pi2.calls.length}/${fs.existsSync(c2.idle)}`, "0/false");
  const c3 = setup("c3", { prog: 1 }), pi3 = await load(); await pi3.settle();
  eq("ⓒ 진행 1 = 턴 0 · 지문 없음", `${pi3.calls.length}/${fs.existsSync(c3.idle)}`, "0/false");
}
{ // ⓓ 판정 불가 유지: TEAMS.md 못 읽음 · planner 행 있는데 골 표 rc1
  const c = setup("d1", { md: null, goalFail: true }), pi = await load(); errs.length = 0; await pi.settle();
  eq("ⓓ TEAMS.md 없음 = 턴 0 · 판정 불가 1줄", `${pi.calls.length}/${errs.filter((e) => e.includes("판정 불가 — 골 표 rc=1")).length}`, "0/1");
  const c2 = setup("d2", { goalFail: true }), pi2 = await load(); errs.length = 0; await pi2.settle();
  eq("ⓓ planner 행 + 골 표 rc1 = 턴 0 · INFO 0 · 지문 없음", `${pi2.calls.length}/${nInfo()}/${fs.existsSync(c2.idle)}`, "0/0/false");
}
console.error = origErr;
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE
mkdir -p "$T/ext" "$T/node_modules/@earendil-works/pi-coding-agent" && cp "$EXT" "$T/ext/ft-idle-nudge.ts" && cp "$WAKE" "$T/ext/ft-mbox-wake.ts" && cp "$(dirname "$EXT")/ft-load-line.ts" "$T/ext/"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
echo 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0 }) });' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"
R1684_EXT="$T/ext/ft-idle-nudge.ts" R1684_TMP="$T" R1684_STUB="$T/stub" timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"; if [ "$rc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc)"; exit 1
