#!/usr/bin/env bash
# test_nano_repo_find_guard_r2413.sh — r2413: pi 좌석 전부(FT_SEAT_NAME)의 bash «리포 루트 find» 를 tool_call 문지기에서 거절하고 갈 길(git ls-files·ci·폴더를 좁힌 find)을 알려 준다.
#   반례 ①~⑧ 동결 · 변이 M1~M8 · 회귀 = test_nano_repo_grep_guard_r2379.sh(r2379 grep 뜻·글자 유지) · 단계별 초
#   격리: tmp HOME·tmp 리포 루트(git init)·tmp 워크트리·tmp 사본 · 실제 find 실행 0 — 판정 함수(tool_call)만 부른다
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$(cd -- "$HERE/.." && pwd)"
GUARD="$H/pi/ft-nano-repo-grep-guard.ts"; LIVE="$H/pi/ft-live-write-guard.ts"; LOAD="$H/pi/ft-load-line.ts"; REG="$H/tests/test_nano_repo_grep_guard_r2379.sh"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq(){ [ "$2" = "$3" ] && ok "$1" || bad "$1" "기대 '$3' 실제 '$2'"; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1" "«$3» 없음";; esac; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
for f in "$GUARD" "$LIVE" "$LOAD" "$REG"; do [ -f "$f" ] || { echo "FAIL 없음 $f"; exit 1; }; done
T0=$SECONDS; st(){ echo "STEP $1 $((SECONDS-T0))s"; }

# ── 정적 계약 ──
[ "$(stat -f %Lp "$0")" = 644 ] && ok "S1 시험 파일 100644" || bad "S1 시험 파일 모드"
has "S2 find 갈래 판정 함수 따로" "$(cat "$GUARD")" "export function judgeFind"
has "S3 거절 문구 = git ls-files" "$(cat "$GUARD")" "git ls-files"
has "S4 거절 문구 = ci search" "$(cat "$GUARD")" "ci search"
has "S5 거절 문구 = find . -maxdepth 3" "$(cat "$GUARD")" "find . -maxdepth 3"
eq "S6 rootOf 직접 안 씀(git 실패를 cwd 로 안 돌림)" "$(grep -c 'rootOf' "$GUARD")" 0
has "S7 grep 거절 글자 = r2379 그대로" "$(grep -m1 'export const WHY = ' "$GUARD")" "리포 루트 재귀 grep 금지(하드 룰 16)"
eq "S8 ft-live-write-guard.ts 손 0" "$(git -C "$H" status --porcelain -- "$LIVE")" ""
eq "S9 ft-load-line.ts 손 0" "$(git -C "$H" status --porcelain -- "$LOAD")" ""
st "정적"

# ── 격리 환경 ──
T="$(mktemp -d "${TMPDIR:-/tmp}/r2413.XXXXXX")"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export R="$T/repo"; export WT="$R/wt"; export SUB="$R/sub"; export OUT="$T/out"; export X="$T/ext"
mkdir -p "$R/.fable-team" "$SUB/inner" "$R/design/harness" "$OUT" "$HOME/.pi/agent/extensions" "$X"
git init -q "$R"; git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git init -q "$WT"; git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m wt
cp "$GUARD" "$X/guard.ts"; cp "$LIVE" "$X/ft-live-write-guard.ts"; cp "$LOAD" "$X/ft-load-line.ts"
mkdir -p "$T/node_modules/@earendil-works/pi-coding-agent"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
printf 'export default function(){}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"
cat > "$T/driver.mjs" <<'NODE'
import { pathToFileURL } from "node:url";
const m = await import(pathToFileURL(process.env.EXT).href), h = {};
m.default({ on: (n, f) => { h[n] = f; }, appendEntry: (t, d) => { globalThis.__e = d; } });
await h.session_start();
console.log(`CASE loadline ${globalThis.__e?.card === "r2379" && globalThis.__e?.line ? "OK" : "NO"}`);
const R = process.env.R, WT = process.env.WT, OUT = process.env.OUT;
const B = (s) => ({ toolName: "bash", input: { command: s } });
const N = "byz-harness-nano-r2413#0", A = "byz-harness-tester-r2413#0";
const cases = [
  ["c01", R, A, B("find . -name 'DA-pre-r2403*'")],
  ["c02a", WT, N, B("find -name x")],
  ["c02b", WT, N, B("cd .. && find . -type f")],
  ["c02c", WT, N, B('find "$PWD" -name x')],
  ["c03", R, "", B("find . -name 'DA-pre-r2403*'")],
  ["c04a", R, N, B("find . -maxdepth 2 -name x")],
  ["c04b", R, N, B("find . -maxdepth 4 -name x")],
  ["c04c", R, N, B("find . -path ./.worktrees -prune -o -name x -print")],
  ["c04d", R, N, B("find .. -name x")],
  ["c04e", R, N, B("find ../other -name x")],
  ["c05a", R, N, B("find design/harness -name 'r24*'")],
  ["c05b", R, N, B("find /tmp/a515 -name '*.md'")],
  ["c05c", R, N, B("find -L . -name x")],
  ["c06a", R, N, B("ls; timeout 20 find . -name x | head")],
  ["c06b", R, N, B('echo "find . -name x"')],
  ["c06c", R, N, B("git ls-files | grep find")],
  ["c07a", R, N, B("grep -rn foo .")],
  ["c07b", R, A, B("grep -rn foo .")],
  ["c07c", R, N, B("grep -rn foo ..")],
];
const only = (process.env.ONLY ?? "").split(/\s+/).filter(Boolean);
for (const name of (only.length ? only : cases.map((c) => c[0]))) {
  const c = cases.find((x) => x[0] === name);
  if (!c) { console.log(`CASE ${name} MISSING`); continue; }
  process.chdir(c[1]); process.env.PWD = c[1]; process.env.FT_SEAT_NAME = c[2];
  const r = await h.tool_call(c[3]);
  console.log(`CASE ${c[0]} ${r?.block ? "BLOCK" : "PASS"}${r?.reason ? ` :: ${r.reason}` : ""}`);
}
NODE
drive(){ EXT="$1" FT_LIVE_ROOT="${2:-}" ONLY="${3:-}" node "$T/driver.mjs" 2>"$T/err"; }
one(){ printf '%s\n' "$1" | awk -v c="$2" '$1=="CASE"&&$2==c{print $3}'; }
expect(){ local o; o="$(one "$1" "$2")"; [ "$o" = "$3" ] && ok "$2 $3" || bad "$2 기대 $3" "실제 '$o'"; }
pairs(){ local o="$1"; shift; for p in "$@"; do expect "$o" "${p% *}" "${p#* }"; done; }

# ── ①~⑧ ──
out="$(drive "$X/guard.ts" "$R")"
eq "L1 로드 줄 r2379 그대로(파일 이름·경로 유지)" "$(one "$out" loadline)" OK
pairs "$out" "c01 BLOCK" "c02a BLOCK" "c02b BLOCK" "c02c PASS" "c03 PASS" \
  "c04a PASS" "c04b BLOCK" "c04c PASS" "c04d BLOCK" "c04e PASS" \
  "c05a PASS" "c05b PASS" "c05c BLOCK" "c06a BLOCK" "c06b PASS" "c06c PASS" \
  "c07a BLOCK" "c07b PASS" "c07c PASS"
has "K1 ① 거절 이유 = 리포 루트 find 금지" "$(printf '%s\n' "$out" | grep 'CASE c01')" "리포 루트 find 금지"
has "K1 ① 거절 이유 = git ls-files·ci search" "$out" "ci search"
has "R1 ②c 변수 경로 = NOTE 판정 불가" "$(cat "$T/err")" "판정 불가 풀 수 없는 find 경로"
has "R2 ⑦a 나노 재귀 grep 거절 글자 = r2379 그대로" "$(printf '%s\n' "$out" | grep 'CASE c07a')" "리포 루트 재귀 grep 금지(하드 룰 16)"
LOG="$R/.fable-team/state/nano-grep-block.log"
eq "R3 ⑧ ① 거절 기록 1줄" "$(grep -c 'DA-pre-r2403' "$LOG")" 1
eq "R4 ⑧ 기록 = 일반 파일 644" "$(stat -f %Lp "$LOG")" 644
eq "R5 ⑧ ③ 좌석 env 없음 = 빈 좌석 기록 0줄" "$(grep -c '^[^ ]*  ' "$LOG")" 0
drive "$X/guard.ts" "$R" "c01" >/dev/null; eq "R6 ⑧ 같은 좌석·같은 명령 두 번째 = 줄 0" "$(grep -c 'DA-pre-r2403' "$LOG")" 1
st "①~⑧"

# ── 기준판 Red — find 갈래 없음 = ① 통과(시험이 잡나) ──
printf 'export default function (pi){ pi.on("session_start", async () => {}); pi.on("tool_call", async () => {}); }\n' > "$X/base.ts"
eq "B1 기준판(확장 없음) = ① PASS" "$(one "$(drive "$X/base.ts" "$R" c01)" c01)" PASS

st "기준판"

# ── ⑧ 기록 쓰기 실패 = 거절 그대로 + ERROR 1줄 ──
mv "$R/.fable-team/state" "$T/state.bak"; : > "$R/.fable-team/state"
o="$(drive "$X/guard.ts" "$R" "c01")"
eq "X1 ⑧ 로그 실패에도 거절" "$(one "$o" c01)" BLOCK
eq "X2 ⑧ ERROR 1줄" "$(grep -c 'ERROR ft-nano-repo-grep-guard' "$T/err")" 1
rm -f "$R/.fable-team/state"; mv "$T/state.bak" "$R/.fable-team/state"

st "⑧ 기록"

# ── 변이 M1~M8 (사본에서만 · 되돌리면 RED) ──
mut(){ python3 -c 'import sys;s=open(sys.argv[1]).read();a,b=sys.argv[3],sys.argv[4]
assert a in s, "패턴 없음: "+a
open(sys.argv[2],"w").write(s.replace(a,b,1))' "$1" "$2" "$3" "$4"; }
hit(){ local o; o="$(drive "$1" "${4:-$R}" "$2")"; [ "$(one "$o" "$2")" = "$3" ]; }
mut "$X/guard.ts" "$X/m.ts" 'const isNano = NANO.test(seat);' 'const isNano = NANO.test(seat); if (!isNano) return;'
hit "$X/m.ts" c01 PASS && ok "M1 K1 대상을 나노만으로 = ① 통과" || bad "M1 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'const ps = paths.length > 0 ? paths : ["."];' 'const ps = paths;'
hit "$X/l.ts" c02a PASS && ok "M2 경로 낱말 0개 = 루트 아님 = ② 첫 구 통과" || bad "M2 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'if (!seat) return;' ''
hit "$X/l.ts" c03 BLOCK && ok "M3 좌석 env 검사 뺌 = ③ 거절" || bad "M3 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'a.depth <= 3' 'a.depth <= 99'
hit "$X/l.ts" c04b PASS && ok "M4 깊이 문턱 99 = ④b 통과" || bad "M4 미탐지"
mut "$X/guard.ts" "$X/l.ts" '!a.prune && ' ''
hit "$X/l.ts" c04c BLOCK && ok "M5 가지치기 검사 뺌 = ④c 거절" || bad "M5 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'return roots.some((r) => r === p || r.startsWith(pre));' 'return roots.includes(p);'
hit "$X/l.ts" c04d PASS && ok "M6 조상 판정 뺌 = ④d 통과" || bad "M6 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'if (isNano) {' 'if (seat) {'
hit "$X/l.ts" c07b BLOCK && ok "M7 grep 갈래를 좌석 전부로 = ⑦b 거절" || bad "M7 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'return ps.some((w) => roots.includes(abs(w, base)));' 'return ps.some((w) => { const p = abs(w, base); return roots.some((r) => r === p || r.startsWith(p + "/")); });'
hit "$X/l.ts" c07c BLOCK && ok "M8 grep atRoot 에 조상 판정 = ⑦c 거절" || bad "M8 미탐지"

st "변이"

# ── 회귀 r2379 (grep 뜻·글자 유지) ──
bash "$REG" >"$T/reg" 2>&1; eq "Z1 회귀 r2379 rc" "$?" 0
eq "Z2 회귀 r2379 합계 fail 0" "$(grep -c '합계 fail :: ' "$T/reg")" 0
st "회귀"
eq "합계 fail" "$fail" 0; exit $((fail > 0))
