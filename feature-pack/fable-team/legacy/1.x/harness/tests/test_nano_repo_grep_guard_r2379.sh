#!/usr/bin/env bash
# test_nano_repo_grep_guard_r2379.sh — r2379: 나노 좌석(pi)의 bash «리포 루트 재귀 grep» 을 tool_call 문지기에서 거절하고 ci·범위 경로를 안내한다.
#   반례 ①~⑳ 동결 · 통과(⑬~⑯) · 판정 불가 = 통과 + NOTE(⑰⑱⑲) · 거절 기록(⑳) · 기준판 Red(확장 없음 ① = 통과)
#   변이 M1~M17(사본에서만 · 변이마다 원본 대조 1회) · 회귀 = test_nano_live_write_block_r1672.sh · 단계별 초
#  격리: tmp HOME·tmp 루트(git init)·tmp 워크트리 사본·가짜 git(PATH 앞) · 실 grep·실 확장 쓰기 0 · sleep 0(가짜 git 만 sleep 8 · 7초 상한 시험)
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$(cd -- "$HERE/.." && pwd)"
GUARD="$H/pi/ft-nano-repo-grep-guard.ts"; LIVE="$H/pi/ft-live-write-guard.ts"; LOAD="$H/pi/ft-load-line.ts"; REG="$H/tests/test_nano_live_write_block_r1672.sh"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq(){ [ "$2" = "$3" ] && ok "$1" || bad "$1" "기대 '$3' 실제 '$2'"; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1" "«$3» 없음";; esac; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
for f in "$GUARD" "$LIVE" "$LOAD" "$REG"; do [ -f "$f" ] || { echo "FAIL 없음 $f"; exit 1; }; done
T0=$SECONDS; st(){ echo "STEP $1 $((SECONDS-T0))s"; }

# ── 정적 계약 ──
[ "$(stat -f %Lp "$0")" = 644 ] && ok "S1 시험 파일 100644" || bad "S1 시험 파일 모드"
eq "S2 NANO 정규식 = r1672 와 같은 글자" "$(grep -m1 -o 'NANO = /[^,]*/' "$GUARD")" "$(grep -m1 -o 'NANO = /[^,]*/' "$LIVE")"
has "S3 seatOf·realish = r1672 export 재사용" "$(grep -m1 'from "./ft-live-write-guard.ts"' "$GUARD")" "seatOf, realish"
eq "S4 rootOf 직접 안 씀(git 실패를 cwd 로 안 돌림)" "$(grep -c 'rootOf' "$GUARD")" 0
has "S5 거절 문구 = ci search" "$(cat "$GUARD")" "ci search"
has "S6 거절 문구 = code-intel(ci sym·refs·outline)" "$(cat "$GUARD")" "ci outline"
eq "S7 ft-live-write-guard.ts 손 0" "$(git -C "$H" status --porcelain -- "$LIVE")" ""
eq "S8 ft-load-line.ts 손 0" "$(git -C "$H" status --porcelain -- "$LOAD")" ""
st "정적"

# ── 격리 환경 ──
T="$(mktemp -d "${TMPDIR:-/tmp}/r2379.XXXXXX")"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export R="$HOME/root"; export SUB="$R/sub"; export WT="$R/.worktrees/x"; export LINK="$T/link"; export X="$T/ext"
mkdir -p "$R/.fable-team" "$SUB/inner" "$R/feature-pack/fable-team" "$HOME/.pi/agent/extensions" "$X" "$T/gr" "$T/gs"
git init -q "$R"; git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git init -q "$WT"; git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m wt
ln -s "$R" "$LINK"
printf '#!/bin/sh\nexit 1\n' > "$T/gr/git"; printf '#!/bin/sh\nexec sleep 8\n' > "$T/gs/git"; chmod +x "$T/gr/git" "$T/gs/git"
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
const R = process.env.R, SUB = process.env.SUB, WT = process.env.WT, LINK = process.env.LINK;
const B = (s) => ({ toolName: "bash", input: { command: s } });
const N = "byz-harness-nano-r2379-x#0", A = "byz-harness-arch-pi#9";
const cases = [
  ["c01", R, N, B("grep -rn foo --include=*.py .")],
  ["c02a", R, N, B("grep -r foo")], ["c02b", R, N, B('grep -Rni foo "$PWD"')], ["c02c", R, N, B(`cd ${R} && grep -rl x ~/root`)],
  ["c03a", WT, N, B("grep -rn foo .")], ["c03b", WT, N, B("timeout 7 grep -r foo .")], ["c03c", WT, N, B("LC_ALL=C grep -r foo .")],
  ["c04a", R, N, B("grep -rn foo $HOME")], ["c04b", R, N, B("grep -r foo ~")],
  ["c05", R, N, B(`grep -r foo ${LINK}`)],
  ["c06", R, N, B("git log | grep -r x")],
  ["c07a", R, N, B("echo hi\ngrep -rn foo .")], ["c07b", R, N, B("sleep 1 & grep -r foo .")], ["c07c", R, N, B("x=$(grep -rl foo .)")],
  ["c08", SUB, N, B(`cd ${R} && grep -rn foo .`)],
  ["c09", R, N, B("(cd sub); grep -r foo .")],
  ["c10a", R, N, B("grep -d recurse foo")], ["c10b", R, N, B("grep --directories=recurse foo")], ["c10c", R, N, B("grep -r -e foo --include '*.py'")],
  ["c11a", R, N, B("grep -rn foo 2>/dev/null")], ["c11b", R, N, B("grep -rn foo >/tmp/o.txt")],
  ["c12a", R, N, B("grep -rn foo 2>&1 | head")], ["c12b", R, N, B("grep -r foo &>/tmp/o")], ["c12c", R, N, B("grep -r foo >&2")],
  ["c13", R, N, B("grep -rn foo feature-pack/fable-team/legacy/1.x/harness/pi")],
  ["c14a", R, N, B("grep -n foo README.md")], ["c14b", R, N, B("git log | grep x")], ["c14c", R, N, B("rg -n foo .")],
  ["c14d", R, N, { toolName: "grep", input: { pattern: "foo", path: "." } }],
  ["c15a", R, N, B("cd feature-pack/fable-team && grep -rn foo .")], ["c15b", R, N, B("( cd sub; grep -r foo . )")], ["c15c", R, N, B("grep -r -e foo sub")],
  ["c16a", R, A, B("grep -rn foo .")], ["c16b", R, "", B("grep -rn foo .")],
  ["c17", SUB, N, B("grep -rn foo")],
  ["c18", R, N, B('grep -r "foo .')], ["c19a", R, N, B("cd - && grep -r foo .")], ["c19b", R, N, B('cd "$X" && grep -r foo .')],
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
expect(){ local o g; o="$(one "$1" "$2")"; [ "$o" = "$3" ] && ok "$2 $3" || bad "$2 기대 $3" "실제 '$o'"; }
pairs(){ local o="$1"; shift; for p in "$@"; do expect "$o" "${p% *}" "${p#* }"; done; }

# ── ①~⑳ ──
out="$(drive "$X/guard.ts" "$R")"
eq "L1 로드 줄 r2379" "$(one "$out" loadline)" OK
pairs "$out" "c01 BLOCK" "c02a BLOCK" "c02b BLOCK" "c02c BLOCK" "c03a BLOCK" "c03b BLOCK" "c03c BLOCK" "c04a BLOCK" "c04b BLOCK" \
  "c05 BLOCK" "c06 BLOCK" "c07a BLOCK" "c07b BLOCK" "c07c BLOCK" "c08 BLOCK" "c09 BLOCK" "c10a BLOCK" "c10b BLOCK" "c10c BLOCK" \
  "c11a BLOCK" "c11b BLOCK" "c12a BLOCK" "c12b BLOCK" "c12c BLOCK" \
  "c13 PASS" "c14a PASS" "c14b PASS" "c14c PASS" "c14d PASS" "c15a PASS" "c15b PASS" "c15c PASS" "c16a PASS" "c16b PASS" \
  "c18 PASS" "c19a PASS" "c19b PASS"
has "K1 거절 이유 = ci search·좁히기" "$out" "ci search"
has "R1 ⑱ 따옴표 = NOTE" "$(cat "$T/err")" "판정 불가 따옴표 안 닫힘"
has "R2 ⑲ cd - = NOTE" "$(cat "$T/err")" "풀 수 없는 cd(cd -)"
has "R3 ⑲ cd \$X = NOTE" "$(cat "$T/err")" '풀 수 없는 cd($X)'
LOG="$R/.fable-team/state/nano-grep-block.log"
eq "R4 ⑳ 거절 기록 1줄(c01)" "$(grep -c 'grep -rn foo --include=\*\.py \.' "$LOG")" 1
eq "R5 기록 = 일반 파일 644" "$(stat -f %Lp "$LOG")" 644
drive "$X/guard.ts" "$R" >/dev/null; eq "R6 같은 좌석·같은 명령 두 번째 = 줄 0" "$(grep -c 'grep -rn foo --include=\*\.py \.' "$LOG")" 1

st "①~⑳"

# ── 기준판 Red — 확장 없음 = ① 통과(시험이 잡나) ──
printf 'export default function (pi){ pi.on("session_start", async () => {}); pi.on("tool_call", async () => {}); }\n' > "$X/base.ts"
eq "B1 기준판(확장 없음) = ① PASS" "$(one "$(drive "$X/base.ts" "$R" c01)" c01)" PASS
eq "B2 기준판 = 로드 줄 없음" "$(one "$(drive "$X/base.ts" "$R")" loadline)" NO

st "기준판"

# ── ⑰ 판정 불가(git rc≠0 · 7초 · 사유별 NOTE 1회) ──
o="$(PATH="$T/gr:$PATH" drive "$X/guard.ts" "" "c17")"
eq "G1 ⑰ git rc≠0 = 통과" "$(one "$o" c17)" PASS
has "G2 ⑰ NOTE = rc≠0" "$(cat "$T/err")" "rc≠0"
o="$(PATH="$T/gr:$PATH" FT_LIVE_ROOT="$R" drive "$X/guard.ts" "$R" "c17 c17")"
eq "G3 ⑰ 같은 사유 두 번째도 통과" "$(printf '%s\n' "$o" | grep -c 'CASE c17 PASS')" 2
eq "G4 ⑰ 같은 사유 NOTE 1줄" "$(grep -c 'NOTE ft-nano-repo-grep-guard' "$T/err")" 1
o="$(PATH="$T/gs:$PATH" drive "$X/guard.ts" "$R" "c17")"
eq "G5 ⑰ git 8초 = 통과(7초 상한)" "$(one "$o" c17)" PASS
has "G6 ⑰ NOTE = 7초 넘김" "$(cat "$T/err")" "7초 넘김"

st "⑰"

# ── ⑳ 기록 쓰기 실패 = 거절 그대로 + ERROR 1줄 ──
mv "$R/.fable-team/state" "$T/state.bak"; : > "$R/.fable-team/state"
o="$(drive "$X/guard.ts" "$R" "c01 c01")"
eq "X1 ⑳ 로그 실패에도 거절" "$(printf '%s\n' "$o" | grep -c 'CASE c01 BLOCK')" 2
eq "X2 ⑳ ERROR 2줄(거절 2회)" "$(grep -c 'ERROR ft-nano-repo-grep-guard' "$T/err")" 2
eq "X3 ⑳ 기록 줄 0" "$(find "$R/.fable-team" -name 'nano-grep-block.log' | wc -l | tr -d ' ')" 0
rm -f "$R/.fable-team/state"; mv "$T/state.bak" "$R/.fable-team/state"

st "⑳"

# ── 변이 M1~M17 (사본에서만 · 되돌리면 RED) ──
mut(){ python3 -c 'import sys;s=open(sys.argv[1]).read();a,b=sys.argv[3],sys.argv[4]
assert a in s, "패턴 없음: "+a
open(sys.argv[2],"w").write(s.replace(a,b,1))' "$1" "$2" "$3" "$4"; }
hit(){ local o; o="$(drive "$1" "${4:-$R}" "$2")"; [ "$(one "$o" "$2")" = "$3" ]; }
mut "$X/guard.ts" "$X/m.ts" 'if (c === "r" || c === "R") { rec = true; continue; }' 'if (t === "-r" || t === "-R") { rec = true; continue; }'
hit "$X/m.ts" c01 PASS && ok "M1 묶음 플래그(-rn) = ① 통과" || bad "M1 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'const ps = paths.length ? paths : ["."];' 'const ps = paths;'
hit "$X/l.ts" c02a PASS && ok "M2 경로 0 = 통과" || bad "M2 미탐지"
mut "$X/guard.ts" "$X/l.ts" '  roots.push(t.out);' ''
hit "$X/l.ts" c03a PASS && ok "M3 워크트리 맨 위 뺌 = ③ 통과" || bad "M3 미탐지"
mut "$X/guard.ts" "$X/l.ts" '    if (t === "timeout" || t === "gtimeout") { k += 2; continue; }' ''
hit "$X/l.ts" c03b PASS && ok "M4 앞 낱말 건너뛰기 지움 = ③b 통과" || bad "M4 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'realish(w) : realish(path.join(base, w))' 'w : path.join(base, w)'
hit "$X/l.ts" c05 PASS && ok "M5 realpath 대신 글자 = ⑤ 통과" || bad "M5 미탐지"
mut "$X/guard.ts" "$X/l.ts" '  for (const s of segs) {' '  for (const s of segs.slice(0, 1)) {'
hit "$X/l.ts" c06 PASS && ok "M6 파이프 뒤 건너뜀 = ⑥ 통과" || bad "M6 미탐지"
mut "$X/guard.ts" "$X/l.ts" '    if (SEPC.has(c)) { out(c); i++; continue; }' ''
hit "$X/l.ts" c07a PASS && ok "M7 줄바꿈·&·\$( 나누기 지움 = ⑦ 통과" || bad "M7 미탐지"
mut "$X/guard.ts" "$X/l.ts" '      base = r.base ?? base;' ''
hit "$X/l.ts" c08 PASS && ok "M8 cd 무시 = ⑧ 통과" || bad "M8 미탐지"
mut "$X/guard.ts" "$X/l.ts" '    if (s.sep === ")") base = stack.pop() ?? base0;' ''
hit "$X/l.ts" c09 PASS && ok "M9 괄호 되돌리기 지움 = ⑨ 통과" || bad "M9 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'if (!val) val = take();' 'if (!val) val = "";'
hit "$X/l.ts" c10a PASS && ok "M10 옵션 값을 경로로 셈 = ⑩a 통과" || bad "M10 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'if (r === "fd" || r === "attached") continue;' 'if (r === "fd") continue;'
hit "$X/l.ts" c11a PASS && ok "M11 리다이렉트 대상을 경로로 셈 = ⑪a 통과" || bad "M11 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'if (c === "&" && nx === ">") { buf += "&>"; i += 2; continue; }' ''
mut "$X/m.ts" "$X/l.ts" 'if (c === ">" && nx === "&") { buf += ">&"; i += 2; continue; }' ''
hit "$X/l.ts" c12c PASS && ok "M12 리다이렉트 안 & 를 나누기로 = ⑫c 통과" || bad "M12 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'return ps.some((w) => roots.includes(abs(w, base)));' 'return true;'
hit "$X/l.ts" c13 BLOCK && ok "M13 하위 폴더도 거절 = ⑬ 거절" || bad "M13 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'if (!seat || !NANO.test(seat)) return;' 'if (!seat) return;'
hit "$X/l.ts" c16a BLOCK && ok "M14 NANO 판정 지움 = ⑯a 거절" || bad "M14 미탐지"
mut "$X/guard.ts" "$X/l.ts" 'if (t.bad || !t.out) return { roots, bad: t.bad || "git rev-parse --show-toplevel 빈 출력" };' 'if (t.bad || !t.out) return { roots: [base], bad: "" };'
o="$(PATH="$T/gr:$PATH" FT_LIVE_ROOT="$R" drive "$X/l.ts" "$R" "c17")"
eq "M15 rootOf 꼴(git 실패 = cwd) = ⑰ 거절" "$(one "$o" c17)" BLOCK
mut "$X/guard.ts" "$X/l.ts" 'if (rr.bad) return { ...NO, bad: rr.bad };' 'if (rr.bad) return { block: true, bad: "", root: f.base, target: f.base };'
o="$(PATH="$T/gr:$PATH" FT_LIVE_ROOT="$R" drive "$X/l.ts" "$R" "c17")"
eq "M16 git 실패 = 거절로 = ⑰ 거절" "$(one "$o" c17)" BLOCK
mut "$X/guard.ts" "$X/l.ts" 'if (r.bad) return { ...NO, bad: r.bad };' 'if (r.bad) return { block: true, bad: "", root: base0, target: base0 };'
hit "$X/l.ts" c19b BLOCK && ok "M17 풀 수 없는 cd = 거절로 = ⑲b 거절" || bad "M17 미탐지"

st "변이"

# ── 회귀 ──
bash "$REG" >"$T/reg" 2>&1; eq "Z1 회귀 r1672 rc" "$?" 0
eq "Z2 회귀 r1672 합계 fail 0" "$(grep -c '합계 fail :: ' "$T/reg")" 0
st "회귀"
eq "합계 fail" "$fail" 0; exit $((fail > 0))
