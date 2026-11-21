#!/usr/bin/env bash
# test_seat_pkill_guard_r2412.sh — r2412: pi 좌석(FT_SEAT_NAME)의 bash «넓게 잡히는 pkill·killall·kill» 을 tool_call 문지기에서 거절하고 안전한 꼴(옵션은 패턴 앞 · pgrep -fl · PID kill)을 알려 준다.
#   카드 반례 ①~⑨ 동결 · 변이 M1~M6 원본 대조 · 기준판 Red(①) · 단계별 초 · 실제 pkill·pgrep·killall·kill 실행 0(가짜 명령 기록 0줄)
#   격리: tmp HOME·tmp 리포 루트 · 판정 함수(tool_call)만 부른다.
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$(cd -- "$HERE/.." && pwd)"
GUARD="$H/pi/ft-seat-pkill-guard.ts"; GREP_GUARD="$H/pi/ft-nano-repo-grep-guard.ts"; LIVE="$H/pi/ft-live-write-guard.ts"; LOAD="$H/pi/ft-load-line.ts"
R2379="$H/tests/test_nano_repo_grep_guard_r2379.sh"; R1672="$H/tests/test_nano_live_write_block_r1672.sh"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq(){ [ "$2" = "$3" ] && ok "$1" || bad "$1" "기대 '$3' 실제 '$2'"; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1" "«$3» 없음";; esac; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
for f in "$GUARD" "$GREP_GUARD" "$LIVE" "$LOAD" "$R2379" "$R1672"; do [ -f "$f" ] || { echo "FAIL 없음 $f"; exit 1; }; done
T0=$SECONDS; st(){ echo "STEP $1 $((SECONDS-T0))s"; }

# ── 정적 계약 ──
[ "$(stat -f %Lp "$0")" = 644 ] && ok "S1 시험 파일 100644" || bad "S1 시험 파일 모드"
has "S2 판정 함수 export(judgeKill)" "$(cat "$GUARD")" "export function judgeKill"
has "S3 거절 글자 = [ft-seat-pkill-guard] 넓게 잡히는 kill 금지" "$(cat "$GUARD")" "[ft-seat-pkill-guard] 넓게 잡히는 kill 금지("
has "S4 안내 3구 = 옵션은 패턴 앞에" "$(cat "$GUARD")" "옵션은 패턴 앞에(pkill -TERM -P <부모> -f '<긴 패턴>')"
has "S5 안내 3구 = pgrep -fl" "$(cat "$GUARD")" "먼저 pgrep -fl 로 대상 수 확인"
has "S6 안내 3구 = PID 로 kill" "$(cat "$GUARD")" "가능하면 PID 로 kill"
has "S7 기록 파일 = seat-kill-block.log" "$(cat "$GUARD")" "seat-kill-block.log"
eq "S8 판정 = FT_SEAT_NAME 만(K1)" "$(grep -c 'process.env.FT_SEAT_NAME ??' "$GUARD")" 1
eq "S9 FT_SEAT(다른 env) 미사용" "$(grep -c 'FT_SEAT[^_]' "$GUARD")" 0
has "S10 splitCmd 재사용(r2379 export)" "$(cat "$GUARD")" 'from "./ft-nano-repo-grep-guard.ts"'
eq "S11 splitCmd 사본 0" "$(grep -c 'function splitCmd' "$GUARD")" 0
eq "S12 ft-nano-repo-grep-guard.ts 손 0" "$(git -C "$H" status --porcelain -- "$GREP_GUARD")" ""
eq "S13 ft-live-write-guard.ts 손 0" "$(git -C "$H" status --porcelain -- "$LIVE")" ""
eq "S14 ft-load-line.ts 손 0" "$(git -C "$H" status --porcelain -- "$LOAD")" ""
eq "S15 r2379 거절 글자 그대로" "$(grep -m1 'export const WHY = ' "$GREP_GUARD")" "$(git -C "$H" show "HEAD:./${GREP_GUARD#$H/}" | grep -m1 'export const WHY = ')"
st "정적"

# ── 격리 환경 ──
T="$(mktemp -d "${TMPDIR:-/tmp}/r2412.XXXXXX")"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export R="$T/repo"; export X="$T/ext"; export FAKE="$T/fakecmd.log"
mkdir -p "$R/.fable-team" "$HOME/.pi/agent/extensions" "$X" "$T/bin"
# 가짜 명령 — 시험이 진짜 pkill·pgrep·killall·kill 을 부르면 여기에 기록된다(0줄이어야 한다)
for c in pkill pgrep killall kill; do printf '#!/bin/sh\necho "%s $*" >> "$FAKE"\nexit 0\n' "$c" > "$T/bin/$c"; chmod 755 "$T/bin/$c"; done
export PATH="$T/bin:$PATH"
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
const N = "byz-room-tester#58", A = "byz-harness-nano-r2412#0";     // N = 실사건 좌석(나노 아님) · A = 나노
const INC = "pkill -TERM -f 'run_all.sh' -P 1";                     // 11-21 20:49:37 실사건 그 줄
const cases = [
  ["c01", N, B(INC)],
  ["c01b", A, B(INC)],
  ["c02a", N, B("cd x && timeout 5 pkill -f 'abcdefg' -P 1")],
  ["c02b", N, B("echo hi; sudo /usr/bin/pkill -f abcdefg -u root")],
  ["c02c", N, B("X=1 killall node -u me")],
  ["c02d", N, B("nice pkill -f 'abcdefg' -P 1")],
  ["c02e", N, B("command pkill -f 'abcdefg' -P 1")],
  ["c03a", "", B(INC)],
  ["c03b", A, { toolName: "read", input: { path: "notes.md" } }],
  ["c04a", N, B("pkill -TERM -P 1 -f 'run_all.sh'")],
  ["c04b", N, B("pkill -TERM -f 't58-L135/r4/'")],
  ["c04c", N, B("kill -TERM 12345 67890")],
  ["c05a", N, B("pkill -f run_all.sh set_run.sh")],
  ["c05b", N, B("pkill -f 'pi'")],
  ["c05c", N, B("pkill -f '.*'")],
  ["c05d", N, B('pkill -f "$PAT"')],
  ["c05e", N, B("pkill -f ''")],
  ["c05f", N, B("pkill -f 'ab.cd'")],
  ["c06a", N, B("kill -TERM -1")],
  ["c06b", N, B("kill -9 -- -1")],
  ["c06c", N, B("kill 0")],
  ["c05g", N, B("pkill -xf pi")],
  ["c05h", N, B("pkill -x -f pi")],
  ["c06d", N, B("kill -0 12345")],
  ["c06e", N, B("kill -TERM 12345 > 0")],
  ["c06f", N, B("kill -TERM 12345 > -1")],
  ["c06g", N, B("kill -TERM 12345 2>/dev/null")],
  ["c07", N, B("pkill -f 'abc")],
  ["c08a", N, B('echo "pkill -f a -P 1"')],
  ["c08b", N, B("grep -n 'pkill -f' notes.md")],
  ["c08c", N, B("pgrep -f 'run_all.sh' -P 1")],
  ["c08d", N, B("ps aux | grep pkill")],
];
const only = (process.env.ONLY ?? "").split(/\s+/).filter(Boolean);
for (const name of (only.length ? only : cases.map((c) => c[0]))) {
  const c = cases.find((x) => x[0] === name);
  if (!c) { console.log(`CASE ${name} MISSING`); continue; }
  process.chdir(R); process.env.PWD = R;
  delete process.env.FT_SEAT_NAME;
  if (c[1]) process.env.FT_SEAT_NAME = c[1];
  const r = await h.tool_call(c[2]);
  console.log(`CASE ${c[0]} ${r?.block ? "BLOCK" : "PASS"}${r?.reason ? ` :: ${r.reason}` : ""}`);
}
NODE
drive(){ EXT="$1" FT_LIVE_ROOT="$R" ONLY="${2:-}" node "$T/driver.mjs" 2>>"$T/err"; }
one(){ printf '%s\n' "$1" | awk -v c="$2" '$1=="CASE"&&$2==c{print $3}'; }
reason(){ printf '%s\n' "$1" | grep "CASE $2 " | sed 's/^[^:]*:: //'; }
expect(){ local o; o="$(one "$1" "$2")"; [ "$o" = "$3" ] && ok "$2 $3" || bad "$2 기대 $3" "실제 '$o'"; }
pairs(){ local o="$1"; shift; for p in "$@"; do expect "$o" "${p% *}" "${p#* }"; done; }
LOG="$R/.fable-team/state/seat-kill-block.log"; : > "$T/err"

# ── ① 차단 + ⑦ 기록 ──
o="$(drive "$X/guard.ts" c01)"; eq "L1 로드 줄 r2412" "$(one "$o" loadline)" OK
eq "① 거절" "$(one "$o" c01)" BLOCK
has "① reason 에 갈래 ⓐ" "$(reason "$o" c01)" "ⓐ"
has "① reason 안내 3구" "$(reason "$o" c01)" "가능하면 PID 로 kill"
eq "⑦ ① 기록 1줄" "$(grep -c 'run_all.sh' "$LOG")" 1
eq "⑦ 기록 = 일반 파일 644" "$(stat -f %Lp "$LOG")" 644
eq "⑦ 기록 칸 = 시각·좌석·갈래" "$(awk '{print $2, $3}' "$LOG" | head -1)" "byz-room-tester#58 ⓐ"
drive "$X/guard.ts" c01 >/dev/null; eq "⑦ 같은 좌석·같은 명령 두 번째 = 줄 0" "$(grep -c 'run_all.sh' "$LOG")" 1
drive "$X/guard.ts" c01b >/dev/null; eq "① 나노 좌석도 같은 명령 = 줄 2" "$(grep -c 'run_all.sh' "$LOG")" 2
st "①⑦"

# ── ②~⑥·⑧ ──
out="$(drive "$X/guard.ts")"
pairs "$out" "c02a BLOCK" "c02b BLOCK" "c02c BLOCK" "c02d BLOCK" "c02e BLOCK" \
  "c03a PASS" "c03b PASS" \
  "c04a PASS" "c04b PASS" "c04c PASS" \
  "c05a BLOCK" "c05b BLOCK" "c05c BLOCK" "c05d BLOCK" "c05e BLOCK" "c05f BLOCK" "c05g BLOCK" "c05h BLOCK" \
  "c06a BLOCK" "c06b BLOCK" "c06c BLOCK" "c06d PASS" "c06e PASS" "c06f PASS" "c06g PASS" \
  "c08a PASS" "c08b PASS" "c08c PASS" "c08d PASS"
has "②a 갈래 ⓐ" "$(reason "$out" c02a)" "ⓐ"
has "②b 갈래 ⓐ" "$(reason "$out" c02b)" "ⓐ"
has "②c 갈래 ⓐ" "$(reason "$out" c02c)" "ⓐ"
has "⑤a 갈래 ⓑ" "$(reason "$out" c05a)" "ⓑ"
has "⑤b 갈래 ⓒ" "$(reason "$out" c05b)" "ⓒ"
has "⑤c 갈래 ⓒ" "$(reason "$out" c05c)" "ⓒ"
has "⑤d 갈래 ⓒ 변수" "$(reason "$out" c05d)" "변수 하나"
has "⑤e 갈래 ⓒ 빈 따옴표" "$(reason "$out" c05e)" "빈 따옴표"
has "⑤g H1 묶은 옵션 -xf 도 -f 로 읽음(갈래 ⓒ)" "$(reason "$out" c05g)" "ⓒ"
has "⑥a 갈래 ⓓ" "$(reason "$out" c06a)" "ⓓ"
has "⑥b 갈래 ⓓ" "$(reason "$out" c06b)" "ⓓ"
eq "③ 좌석 env 없음 = 기록 0줄" "$(grep -c '^[^ ]*  ' "$LOG")" 0
st "②~⑥⑧"

# ── 기준판 Red — 확장 없음 = ① 통과 ──
printf 'export default function (pi){ pi.on("session_start", async () => {}); pi.on("tool_call", async () => {}); }\n' > "$X/base.ts"
eq "B1 기준판(확장 없음) = ① PASS" "$(one "$(drive "$X/base.ts" c01)" c01)" PASS
st "기준판"

# ── ⑦ 못 나눔 = 통과 + 기록 1줄 «판정 불가» / 기록 실패 = 거절 그대로 + ERROR 1줄 ──
o="$(drive "$X/guard.ts" c07)"
eq "⑦ 못 나눈 명령 = 통과" "$(one "$o" c07)" PASS
eq "⑦ 못 나눔 기록 1줄 «판정 불가»" "$(grep -c '판정 불가' "$LOG")" 1
mv "$R/.fable-team/state" "$T/state.bak"; : > "$R/.fable-team/state"
eq "⑦ 기록 폴더 막혀도 ① 거절 그대로" "$(one "$(drive "$X/guard.ts" c01)" c01)" BLOCK
eq "⑦ ERROR 1줄" "$(grep -c 'ERROR ft-seat-pkill-guard' "$T/err")" 1
rm -f "$R/.fable-team/state"; mv "$T/state.bak" "$R/.fable-team/state"
st "⑦"

# ── 변이 M1~M6 (사본에서만 · 되돌리면 RED) ──
mut(){ python3 -c 'import sys;s=open(sys.argv[1]).read();a,b=sys.argv[3],sys.argv[4]
assert a in s, "패턴 없음: "+a
open(sys.argv[2],"w").write(s.replace(a,b,1))' "$1" "$2" "$3" "$4"; }
hit(){ [ "$(one "$(drive "$1" "$2")" "$2")" = "$3" ]; }
mut "$X/guard.ts" "$X/m1.ts" 'if (!seat) return;' 'if (!seat && false) return;'
hit "$X/m1.ts" c03a BLOCK && ok "M1 K1 좌석 env 검사 뺌 = ③ 거절" || bad "M1 미탐지"
mut "$X/guard.ts" "$X/m2.ts" 'if (a.late) return' 'if (false) return'
hit "$X/m2.ts" c01 PASS && ok "M2 K2ⓐ 검사 뺌 = ① 통과(실사건 재현)" || bad "M2 미탐지"
mut "$X/guard.ts" "$X/m3.ts" 'const VAL = new Set(["F", "G", "P",' 'const VAL = new Set(["F", "G",'
hit "$X/m3.ts" c04a BLOCK && ok "M3 값 받는 옵션 표에서 -P 뺌 = ④ 첫 구 거절" || bad "M3 미탐지"
mut "$X/guard.ts" "$X/m4.ts" 'const MINP = 6;' 'const MINP = 1;'
hit "$X/m4.ts" c05b PASS && ok "M4 ⓒ 길이 문턱 6 → 1 = ⑤ 둘째 구 통과" || bad "M4 미탐지"
mut "$X/guard.ts" "$X/m5.ts" 'const b = a.pat.find((v) => v === "-1" || v === "0");' 'const b = [...a.pat, ...a.sig].find((v) => v === "-1" || v === "0" || v.startsWith("-"));'
hit "$X/m5.ts" c06d BLOCK && ok "M5 kill -0 <pid> 를 거절로 = ⑥ 넷째 구 거절" || bad "M5 미탐지"
mut "$X/guard.ts" "$X/m6.ts" 'try { v = judgeKill(cmd); }' 'try { const i = cmd.search(/\b(kill\w*|pkill)\b/); v = judgeKill(i < 0 ? cmd : cmd.slice(i).replace(/["'"'"']/g, "")); }'
hit "$X/m6.ts" c08a BLOCK && ok "M6 따옴표 안 글자도 판정 = ⑧ 첫 구 거절" || bad "M6 미탐지"
st "변이"

# ── ⑨ 회귀 (r2379 · r1672) ──
bash "$R2379" >"$T/r2379" 2>&1; eq "⑨ 회귀 r2379 rc" "$?" 0
eq "⑨ 회귀 r2379 FAIL 0" "$(grep -c '^FAIL' "$T/r2379")" 0
bash "$R1672" >"$T/r1672" 2>&1; eq "⑨ 회귀 r1672 rc" "$?" 0
eq "⑨ 회귀 r1672 FAIL 0" "$(grep -c '^FAIL' "$T/r1672")" 0
st "⑨ 회귀"

eq "Z1 가짜 pkill·pgrep·killall·kill 기록 0줄" "$(grep -c . "$FAKE")" 0
st "실행 0"
eq "합계 fail" "$fail" 0; exit $((fail > 0))
