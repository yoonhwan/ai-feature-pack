#!/usr/bin/env bash
# test_seat_kill_guard_r2412.sh — r2412: pi 좌석 전부(FT_SEAT_NAME)의 bash «넓게 잡히는 pkill·killall · 광역 kill» 을 tool_call 문지기에서 거절하고 안전한 꼴(옵션은 패턴 앞 · pgrep 으로 먼저 세기 · PID 로 kill)을 알려 준다.
#   반례 ①~⑨ 동결 · 변이 M1~M6 · 단계별 초 · 실제 pkill·pgrep·killall·kill 실행 0(가짜 명령 기록 0줄로 확인)
#   격리: tmp HOME·tmp 리포 루트 · 판정 함수(tool_call)만 부른다.
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$(cd -- "$HERE/.." && pwd)"
GUARD="$H/pi/ft-seat-kill-guard.ts"; GREP_GUARD="$H/pi/ft-nano-repo-grep-guard.ts"; LIVE="$H/pi/ft-live-write-guard.ts"; LOAD="$H/pi/ft-load-line.ts"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq(){ [ "$2" = "$3" ] && ok "$1" || bad "$1" "기대 '$3' 실제 '$2'"; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1" "«$3» 없음";; esac; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
for f in "$GUARD" "$GREP_GUARD" "$LIVE" "$LOAD"; do [ -f "$f" ] || { echo "FAIL 없음 $f"; exit 1; }; done
T0=$SECONDS; st(){ echo "STEP $1 $((SECONDS-T0))s"; }

# ── 정적 계약 ──
[ "$(stat -f %Lp "$0")" = 644 ] && ok "S1 시험 파일 100644" || bad "S1 시험 파일 모드"
has "S2 판정 함수 따로(judgeKill)" "$(cat "$GUARD")" "export function judgeKill"
has "S3 안내 = 옵션은 패턴 앞" "$(grep -m1 'export const WHY = ' "$GUARD")" "옵션은 패턴 앞"
has "S4 안내 = pgrep 으로 먼저 세기" "$(grep -m1 'export const WHY = ' "$GUARD")" "pgrep"
has "S5 안내 = PID 로 kill" "$(grep -m1 'export const WHY = ' "$GUARD")" "kill <pid>"
has "S6 기록 파일 = seat-kill-block.log" "$(cat "$GUARD")" "seat-kill-block.log"
has "S7 splitCmd 재사용(r2379 export)" "$(cat "$GUARD")" 'from "./ft-nano-repo-grep-guard.ts"'
eq "S8 splitCmd 사본 0(다시 안 만듦)" "$(grep -c 'function splitCmd' "$GUARD")" 0
eq "S9 ft-nano-repo-grep-guard.ts 손 0" "$(git -C "$H" status --porcelain -- "$GREP_GUARD")" ""
eq "S10 ft-live-write-guard.ts 손 0" "$(git -C "$H" status --porcelain -- "$LIVE")" ""
eq "S11 ft-load-line.ts 손 0" "$(git -C "$H" status --porcelain -- "$LOAD")" ""
st "정적"

# ── 격리 환경 ──
T="$(mktemp -d "${TMPDIR:-/tmp}/r2412.XXXXXX")"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export R="$T/repo"; export OUT="$T/out"; export X="$T/ext"; export FAKE="$T/fakecmd.log"
mkdir -p "$R/.fable-team" "$OUT" "$HOME/.pi/agent/extensions" "$X" "$T/bin"
: > "$FAKE"
# 가짜 명령 — 시험이 진짜 pkill·pgrep·killall·kill 을 부르면 여기에 기록된다(0줄이어야 한다)
for c in pkill pgrep killall kill; do printf '#!/bin/sh\necho "%s $*" >> "$FAKE"\nexit 0\n' "$c" > "$T/bin/$c"; chmod 755 "$T/bin/$c"; done
export FAKE; export PATH="$T/bin:$PATH"
: > "$FAKE"
cp "$GUARD" "$X/guard.ts"; cp "$GREP_GUARD" "$X/ft-nano-repo-grep-guard.ts"; cp "$LIVE" "$X/ft-live-write-guard.ts"; cp "$LOAD" "$X/ft-load-line.ts"
mkdir -p "$T/node_modules/@earendil-works/pi-coding-agent"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
printf 'export default function(){}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"
cat > "$T/driver.mjs" <<'NODE'
import { pathToFileURL } from "node:url";
const m = await import(pathToFileURL(process.env.EXT).href), h = {};
m.default({ on: (n, f) => { h[n] = f; }, appendEntry: (t, d) => { globalThis.__e = d; } });
await h.session_start();
console.log(`CASE loadline ${globalThis.__e?.card === "r2412" && globalThis.__e?.line ? "OK" : "NO"}`);
const R = process.env.R;
const B = (s) => ({ toolName: "bash", input: { command: s } });
const N = "byz-room-tester#58", A = "byz-harness-nano-r2412#0";   // N = 실사건 좌석(나노 아님)
const INC = "pkill -TERM -f 'run_all.sh' -P 1";                   // 11-21 20:49:37 실사건 그 줄
const cases = [
  ["c01", N, B(INC)],
  ["c01b", A, B(INC)],
  ["c02a", N, B("pkill -f 'run_all.sh' -P 1")],
  ["c02b", N, B("ls; timeout 20 pkill -f 'run_all.sh' -P 1 | head -3")],
  ["c02c", N, B("sudo -E pkill -f 'run_all.sh' -P 1")],
  ["c02d", N, B("killall -TERM run_all.sh -u me")],
  ["c02e", N, B("cd /tmp && pkill -f 'run_all.sh' -P 1")],
  ["c03a", "", B(INC)],
  ["c03b", A, { toolName: "read", input: { path: "notes.md" } }],
  ["c03c", N, B("pgrep -f 'run_all.sh' -P 1")],
  ["c03d", N, B("ps aux | grep pkill")],
  ["c04a", N, B("pkill -f 'node'")],
  ["c04b", N, B("pkill -f ''")],
  ["c04c", N, B('pkill -f "$R"')],
  ["c04d", N, B("pkill -f 'abcdef'")],
  ["c05a", N, B("pkill -f 'run_all.sh' 'other_long.sh'")],
  ["c05b", N, B("killall run_all.sh other_long.sh")],
  ["c06a", N, B("kill -9 -1")],
  ["c06b", N, B("kill 0")],
  ["c06c", N, B("kill -- -1")],
  ["c06d", N, B("kill -TERM 4321")],
  ["c06e", N, B("kill -0 4321")],
  ["c08a", N, B("pkill -TERM -P 1 -f 'run_all.sh'")],
  ["c08b", N, B("kill 4321")],
  ["c08c", N, B("pkill -P 1 -f 'run_all.sh'")],
  ["c08d", N, B('echo "pkill -f x -P 1"')],
  ["c08e", N, B("grep -n 'pkill' notes.md")],
  ["c08f", N, B("man pkill")],
  ["c08g", N, B("command -v pkill")],
  ["c08h", N, B("killall -l")],
  ["c09a", N, B("pkill -f 'run_all.sh")],
  ["c09b", N, B("pkill")],
];
const only = (process.env.ONLY ?? "").split(/\s+/).filter(Boolean);
for (const name of (only.length ? only : cases.map((c) => c[0]))) {
  const c = cases.find((x) => x[0] === name);
  if (!c) { console.log(`CASE ${name} MISSING`); continue; }
  process.chdir(R); process.env.PWD = R;
  delete process.env.FT_SEAT_NAME; delete process.env.FT_SEAT;
  if (c[1]) process.env.FT_SEAT_NAME = c[1];
  const r = await h.tool_call(c[2]);
  console.log(`CASE ${c[0]} ${r?.block ? "BLOCK" : "PASS"}${r?.reason ? ` :: ${r.reason}` : ""}`);
}
NODE
drive(){ EXT="$1" FT_LIVE_ROOT="$R" ONLY="${2:-}" node "$T/driver.mjs" 2>>"$T/err"; }
one(){ printf '%s\n' "$1" | awk -v c="$2" '$1=="CASE"&&$2==c{print $3}'; }
expect(){ local o; o="$(one "$1" "$2")"; [ "$o" = "$3" ] && ok "$2 $3" || bad "$2 기대 $3" "실제 '$o'"; }
pairs(){ local o="$1"; shift; for p in "$@"; do expect "$o" "${p% *}" "${p#* }"; done; }
LOG="$R/.fable-team/state/seat-kill-block.log"; : > "$T/err"

# ── ⑦ 기록(K3) — 같은 좌석·같은 명령 1회 · 일반 파일 644 ──
o="$(drive "$X/guard.ts" c01)"; eq "L1 로드 줄 r2412" "$(one "$o" loadline)" OK
eq "R1 ⑦ ① 거절 기록 1줄" "$(grep -c 'run_all.sh' "$LOG")" 1
eq "R2 ⑦ 기록 = 일반 파일 644" "$(stat -f %Lp "$LOG")" 644
eq "R3 ⑦ 기록 첫 칸 = 좌석 이름" "$(awk '{print $2}' "$LOG" | head -1)" "byz-room-tester#58"
has "R4 ⑦ 거절 사유 = 옵션이 패턴 뒤" "$(printf '%s\n' "$o" | grep 'CASE c01')" "패턴 뒤"
drive "$X/guard.ts" c01 >/dev/null; eq "R5 ⑦ 같은 좌석·같은 명령 두 번째 = 줄 0" "$(grep -c 'run_all.sh' "$LOG")" 1
drive "$X/guard.ts" c01b >/dev/null; eq "R6 ① 나노 좌석도 같은 명령 = 줄 1 늘어 2" "$(grep -c 'run_all.sh' "$LOG")" 2
st "⑦ 기록"

# ── ①~⑥·⑧·⑨ ──
out="$(drive "$X/guard.ts")"
pairs "$out" "c01 BLOCK" "c01b BLOCK" "c02a BLOCK" "c02b BLOCK" "c02c BLOCK" "c02d BLOCK" "c02e BLOCK" \
  "c03a PASS" "c03b PASS" "c03c PASS" "c03d PASS" \
  "c04a BLOCK" "c04b BLOCK" "c04c BLOCK" "c04d PASS" \
  "c05a BLOCK" "c05b BLOCK" \
  "c06a BLOCK" "c06b BLOCK" "c06c BLOCK" "c06d PASS" "c06e PASS" \
  "c08a PASS" "c08b PASS" "c08c PASS" "c08d PASS" "c08e PASS" "c08f PASS" "c08g PASS" "c08h PASS" \
  "c09a PASS" "c09b PASS"
has "K1 ① 거절 이유 = 넓게 잡히는 종료 명령 금지" "$(printf '%s\n' "$out" | grep 'CASE c01')" "넓게 잡히는 종료 명령 금지"
has "K3 ① 안내 = 옵션은 패턴 앞" "$(printf '%s\n' "$out" | grep 'CASE c01')" "옵션은 패턴 앞"
has "K3 ① 안내 = pgrep" "$(printf '%s\n' "$out" | grep 'CASE c01')" "pgrep"
has "K3 ① 안내 = kill <pid>" "$(printf '%s\n' "$out" | grep 'CASE c01')" "kill <pid>"
has "K2 ⑤ 사유 = 패턴 개수" "$(printf '%s\n' "$out" | grep 'CASE c05a')" "패턴 2개"
has "K2 ⑥ 사유 = 광역 대상" "$(printf '%s\n' "$out" | grep 'CASE c06a')" "광역 대상"
has "K2 ④b 사유 = 빈 패턴" "$(printf '%s\n' "$out" | grep 'CASE c04b')" "패턴"
has "K4 ⑨a 판정 불가 = NOTE 1줄" "$(cat "$T/err")" "NOTE ft-seat-kill-guard: 판정 불가"
eq "K1 ③b 좌석 env 없음 = 기록 0줄" "$(grep -c '^[^ ]*  ' "$LOG")" 0
st "①~⑨"

# ── 기준판 Red — 확장 없음 = ① 통과(시험이 잡나) ──
printf 'export default function (pi){ pi.on("session_start", async () => {}); pi.on("tool_call", async () => {}); }\n' > "$X/base.ts"
eq "B1 기준판(확장 없음) = ① PASS" "$(one "$(drive "$X/base.ts" c01)" c01)" PASS
st "기준판"

# ── ⑦ 기록 쓰기 실패 = 거절 그대로 + ERROR 1줄 ──
mv "$R/.fable-team/state" "$T/state.bak"; : > "$R/.fable-team/state"
o="$(drive "$X/guard.ts" c01)"
eq "X1 ⑦ 로그 실패에도 거절" "$(one "$o" c01)" BLOCK
eq "X2 ⑦ ERROR 1줄" "$(grep -c 'ERROR ft-seat-kill-guard' "$T/err")" 1
rm -f "$R/.fable-team/state"; mv "$T/state.bak" "$R/.fable-team/state"
st "⑦ 기록 실패"

# ── 변이 M1~M6 (사본에서만 · 되돌리면 RED) ──
mut(){ python3 -c 'import sys;s=open(sys.argv[1]).read();a,b=sys.argv[3],sys.argv[4]
assert a in s, "패턴 없음: "+a
open(sys.argv[2],"w").write(s.replace(a,b,1))' "$1" "$2" "$3" "$4"; }
hit(){ local o; o="$(drive "$1" "$2")"; [ "$(one "$o" "$2")" = "$3" ]; }
mut "$X/guard.ts" "$X/m1.ts" 'const seat = seatOf();
    if (!seat) return;' 'const seat = seatOf();
    if (!seat || !/nano/.test(seat)) return;'
hit "$X/m1.ts" c01 PASS && ok "M1 K1 대상을 나노만으로 = ① 통과" || bad "M1 미탐지" "$(one "$(drive "$X/m1.ts" c01)" c01)"
mut "$X/guard.ts" "$X/m2.ts" 'if (a.lateOpt) return' 'if (false) return'
m2="$(drive "$X/m2.ts" c01)"; eq "M2 K2ⓐ 검사 뺀 판 = 사유가 «패턴 뒤» 가 아님" "$(printf '%s\n' "$m2" | grep -c '패턴 뒤')" 0
hit "$X/m2.ts" c01 BLOCK && ok "M2 K2ⓐ 를 빼도 ⓒ 복수 패턴이 겹쳐 잡음(사유로 구분)" || bad "M2 미탐지"
mut "$X/guard.ts" "$X/m3.ts" 'const MINP = 6;' 'const MINP = 0;'
hit "$X/m3.ts" c04a PASS && ok "M3 K2ⓑ 짧은 패턴 문턱 뺌 = ④a 통과" || bad "M3 미탐지"
mut "$X/guard.ts" "$X/m4.ts" 'if (a.pat.length > 1)' 'if (false)'
hit "$X/m4.ts" c05a PASS && ok "M4 K2ⓒ 복수 패턴 검사 뺌 = ⑤a 통과" || bad "M4 미탐지"
mut "$X/guard.ts" "$X/m5.ts" 'if (a.broad)' 'if (false)'
hit "$X/m5.ts" c06a PASS && ok "M5 K2ⓓ 광역 대상 검사 뺌 = ⑥a 통과" || bad "M5 미탐지"
mut "$X/guard.ts" "$X/m6.ts" 'if (a.pat.length > 1)' 'if (a.pat.length >= 1)'
hit "$X/m6.ts" c08a BLOCK && ok "M6 K4 정상 pkill 까지 거절 = ⑧a 거절" || bad "M6 미탐지"
st "변이"

# ── 실제 종료 명령 호출 0 ──
eq "Z1 가짜 pkill·pgrep·killall·kill 기록 0줄" "$(grep -c . "$FAKE")" 0
st "실행 0"
eq "합계 fail" "$fail" 0; exit $((fail > 0))
