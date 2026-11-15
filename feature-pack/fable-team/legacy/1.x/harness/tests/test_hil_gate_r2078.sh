#!/usr/bin/env bash
# test_hil_gate_r2078.sh — r2078: h 등록 공통 규칙 판정기(J1 pipefail · J2 timeout rc · J3 초 선언 · J4 BASH_SOURCE) + 진입 파일 sha 잠금(검사한 바이트 실행) · 다시 등록 · 걸린 초
#   카드(ops/main-base dbdb9893) 반례 ①~⑥ · 고정 Red ⑧-1~⑧-4(입력 = design/harness/evidence/r2078-da/fixed-red/ 4파일과 같은 바이트 · sha 로 확인)
#   변이 M1~M10(사본 · 변이마다 원본 같은 칸 PASS 대조) · bin·kit 같은 내용 · ft-hil.sh ≤200줄
# 격리: 임시 HIL_DIR · 임시 HOME · HIL_CLIP=0 · 가짜 mbox.sh · 리포 밖 계획(mktemp) — 실 /tmp/h* · 실 쪽지함 · 실 계획 0 · sleep 0(걸린 초 = 보조 도구 인자 · .ran 시작 줄 주입)
#   기준판 = 팩 커밋 450d5038 bin(git archive) · R2078_BIN=<기준판 bin> 으로 돌리면 ②a · ③a · ④b · ⑤d 가 FAIL(Red)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="${R2078_BIN:-$HERE/../bin}"; KIT="$HERE/../kit/fable-team/bin"; BASE=450d5038d9e482a269d2362685571a984777132e
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:400}";; *) ok "$3";; esac; }
sec() { echo "== $1 (누적 $((SECONDS - T0))s)"; }

C="$T/comm"; mkdir -p "$C" "$T/home" "$T/base" "$T/gitstub"
printf '{"_master": "byz-planner-master-claude#1"}\n' > "$T/seats-planner.json"
printf '#!/bin/bash\nprintf "%%s\\t%%s\\t%%s\\n" "$2" "$3" "$4" >> "$(dirname "$0")/sent.log"\n' > "$C/mbox.sh"
git -C "$(git -C "$HERE" rev-parse --show-toplevel)" archive "$BASE" -- "$(git -C "$HERE/../bin" rev-parse --show-prefix)" 2>/dev/null | tar -x -C "$T/base" 2>/dev/null
BB="$(find "$T/base" -type d -path '*harness/bin' | head -1)"; [ -f "$BB/ft-hil.sh" ] || BB=""
hil()  { local b="$1" e=(); shift; while [ "${1:-}" = env ]; do e+=("$2"); shift 2; done
  ( for v in $(compgen -e); do unset "$v" 2>/dev/null; done; export HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$C" ${e[@]+"${e[@]}"}; bash "$b/ft-hil.sh" "$@" ); }
runh() { local p="/usr/bin:/bin"; [ "${1:-}" != --stub ] || { p="$T/gitstub:$p"; shift; }; ( cd /tmp && env -i HOME="$T/home" PATH="$p" bash "$@" ); }
plan() { local f="$T/$1.sh.hil"; shift; { echo '#!/usr/bin/env bash'; printf '%s\n' "$@"; } > "$f"; echo "$f"; }
fresh() { HD="$T/hd-$1"; rm -rf "$HD"; mkdir -p "$HD"; }
nh() { find "$HD" -maxdepth 1 -name 'h[0-9]*' ! -name '*.*' | wc -l | tr -d ' '; }
judge() { local f; f="$(plan "$2" "${@:3}")"; python3 "$1/ft_hil_gate_judge.py" --plan "$f" 2>/dev/null; }
jc() {  # <bin> <이름> <기대 글자|ok> <줄…> — 판정기 1칸(계획 줄 1 = shebang · 첫 줄 = 2줄)
  local b="$1" k="$2" want="$3" o; shift 3; o="$(judge "$b" "j-$k" "$@")"
  if [ "$want" = ok ]; then [ "$o" = ok ] && ok "① $k = ok" || bad "① $k 기대 ok ← $o"; else has "$o" "$want" "① $k → $want"; fi
}
SETPF='set -euo pipefail'; SW="J2 2줄 시간 상한 건 명령의 rc 를 삼킴"; NS="J2 2줄 시간 상한 건 명령의 rc 를 안 봄"

c1() { local b="$1"
  jc "$b" pipe "J1 2줄" 'a | b'; jc "$b" pipe-pf ok "$SETPF" 'a | b'
  jc "$b" pipe-text ok '# a | b' 'echo "a | b"' "printf '%s' 'x|y'" 'x || y'
  jc "$b" j2-pipe "$NS" 'n=$(timeout 7 git status --porcelain | wc -l)'
  jc "$b" j2-rc ok 'o=$(timeout 7 git status --porcelain); rc=$?'
  jc "$b" j2-or-block ok '# ft-hil-budget: 9' 'for i in 1; do h=$(timeout 7 git rev-parse HEAD) || { echo SKIP; continue; }; done'
  jc "$b" j2-swallow-in "J2 2줄 시간 상한 건 명령의 rc 를 삼킴(치환 안" 'n=$(timeout 7 x || echo 0)'
  jc "$b" j2-rcok ok 'n=$(timeout 7 x || echo 0) # rc-ok: 출력 글로 판정'
  jc "$b" j2-out ok 'timeout 25 rm -rf "$p"'
  jc "$b" r1-dq-semi "$SW" 'n="$(timeout 7 git status --porcelain || echo 0)"; rc=$?'
  jc "$b" r1-semi-in "$SW" 'n=$(timeout 7 x; echo 0); rc=$?'
  jc "$b" r1-or-assign "$SW" 'n=$(timeout 7 x) || n=0'; jc "$b" r1-or-func "$SW" 'n=$(timeout 7 x) || f "조회 실패"'
  jc "$b" r1-or-two "$SW" 'n=$(timeout 7 x) || { echo a; echo b; exit 1; }'
  jc "$b" r1-or-cond "$SW" 'n=$(timeout 7 x) || { n=0; [ "$n" -ge 0 ] || exit 3; }'
  jc "$b" r1-or-exit ok 'n=$(timeout 7 x) || exit 3'; jc "$b" r1-or-printf ok 'n=$(timeout 7 x) || { printf "%s\n" SKIP >&2; return 1; }'
  jc "$b" r1-local "$NS" 'local n=$(timeout 7 x); rc=$?'; jc "$b" r1-test "$NS" '[ "$(timeout 7 x)" = "" ] || exit 1'
  jc "$b" r1-late "$NS" 'n=$(timeout 7 x); echo hi; rc=$?'; jc "$b" r1-and "$NS" 'n=$(timeout 7 x) && echo ok'; jc "$b" r1-plain "$NS" 'n=$(timeout 7 x)'
  jc "$b" r1-if ok 'if ! o=$(timeout 7 x); then exit 3; fi'; jc "$b" r1-dq-rc ok 'n="$(timeout 7 x)"; [ "$?" -eq 0 ] || exit 3'
  jc "$b" r2-sq ok "printf '%s\\n' 'n=\$(timeout 7 git status)'"
  jc "$b" j4 "reject J4 2줄 BASH_SOURCE 는 잠금 실행에서 빈 값" 'd="$(dirname "${BASH_SOURCE[0]}")"'; jc "$b" j4-comment ok '# d="${BASH_SOURCE[0]}"'
  jc "$b" j3-none "J3 2줄 반복이 있는데 «# ft-hil-budget: <초>» 줄이 0개" 'for i in 1 2; do :; done'
  jc "$b" j3-indent "J3 3줄 반복이 있는데" 'f() {' '  while x; do :; done; }'
  jc "$b" j3-60 ok '# ft-hil-budget: 60' 'for i in 1 2; do :; done'
  jc "$b" j3-two "줄이 2개" '# ft-hil-budget: 60' '# ft-hil-budget: 60' 'while x; do :; done'
  jc "$b" j3-0 "선언 0초 — 1~70 밖" '# ft-hil-budget: 0' 'until x; do :; done'
  jc "$b" j3-71 "선언 71초 — 1~70 밖" '# ft-hil-budget: 71' 'for i in 1; do :; done'
  jc "$b" j3-noloop ok 'echo 반복 없음'; }
c1r1() { jc "$1" r1-or-brace "J2 2줄 시간 상한 건 명령의 rc 를 삼킴(치환 안" 'n=$(timeout 7 git status --porcelain || { echo 0; })'; }
c1m8() { jc "$1" r1-or-echo "$SW" 'n=$(timeout 7 x) || echo 0'; }

BAD3=('n=$(timeout 7 false | wc -l)' 'for i in 1 2; do rm -rf "/tmp/r2078-none-$i"; done' 'echo "n=$n"')
c2a() { local b="$1" o rc e; fresh 2a
  o="$(judge "$b" p2a "${BAD3[@]}")"; rc=$?
  [ "$rc" = 1 ] && [ "$(grep -c '^reject ' <<< "$o")" = 3 ] && has "$o" "reject J1 2줄 파이프가 있는데 그 앞에 set -o pipefail 없음 (지우는 줄 3줄)" "②a 판정기 rc1 · reject 3줄(규칙·줄·지우는 줄)" || bad "②a 판정기 rc=$rc ← $o"
  e="$(hil "$b" --add "$T/p2a.sh.hil" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = 1 ] && [ "$(nh)" = 0 ] && [ -z "$(ls -A "$HD")" ] && has "$e" "REJECT J1 2줄" "②a --add rc1 · h 0 · 표식 0" || bad "②a --add rc=$rc h=$(nh) ls=$(ls -A "$HD" | tr '\n' ' ') ← $e"; }
c2b() { local b="$1" o e rc f; fresh 2b; f="$(plan p2b 'n=$(timeout 7 false | wc -l)' 'for i in 1 2; do echo "rm -rf /x-$i"; done' '# rm -rf /y')"
  o="$(hil "$b" --add "$f" 2>"$T/e2b")"; rc=$?; e="$(cat "$T/e2b")"
  [ "$rc" = 0 ] && [ "$o" = "! bash $HD/h1" ] && [ "$(grep -c 'h 공통 규칙' <<< "$e")" = 1 ] && has "$e" "WARN h 공통 규칙 — J1 2줄" "②b 지우는 줄 없음(주석·echo 안 rm) = 경고 1줄 · stdout ! bash 1줄 · rc0" || bad "②b rc=$rc o=$o ← $e"
  o="$(judge "$b" p2r 'n=$(timeout 7 git status)' '  rm -rf "$p"')"; rc=$?
  [ "$rc" = 1 ] && has "$o" "reject J2 2줄 시간 상한 건 명령의 rc 를 안 봄" "②R2 들여쓴 rm 앞 J2 = reject" && has "$o" "(지우는 줄 3줄)" "②R2 지우는 줄 = 들여쓴 줄" || bad "②R2 rc=$rc ← $o"
  o="$(judge "$b" p2q "printf '%s\\n' 'n=\$(timeout 7 git status)'" 'rm -rf "$p"')"; rc=$?; [ "$rc" = 0 ] && [ "$o" = ok ] && ok "②R2 작은따옴표 안 치환 + rm = ok" || bad "②R2 sq rc=$rc ← $o"
  o="$(judge "$b" p2s 'o=$(timeout 7 git status); rc=$?' '[ "$rc" = 0 ] || exit "$rc"' 'rm -rf "$p"')"; rc=$?; [ "$rc" = 0 ] && [ "$o" = ok ] && ok "②R2 rc 본 뒤 rm 3줄 = ok" || bad "②R2 safe rc=$rc ← $o"
  fresh 2j; e="$(hil "$b" --add "$(plan p2j "$SETPF" 'cd "$(dirname "${BASH_SOURCE[0]}")"' 'echo hi')" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = 1 ] && [ "$(nh)" = 0 ] && has "$e" "REJECT J4 3줄" "②J4 지우는 줄 없음 · BASH_SOURCE = --add rc1 · h 0" || bad "②J4 rc=$rc h=$(nh) ← $e"
  fresh 2c; e="$(hil "$b" --add "$(plan p2c "$SETPF" 'echo ok')" 2>&1 >/dev/null)"
  hasnt "$e" "h 공통 규칙" "②c 위반 0 = stderr 에 «h 공통 규칙» 0"
  o="$(python3 "$b/ft_hil_gate_judge.py" --plan "$T/none.sh" 2>/dev/null)"; rc=$?
  [ "$rc" = 2 ] && [ -z "$o" ] && ok "②d 없는 파일 = rc2 · reject 글 0" || bad "②d rc=$rc o=$o"; }

P3=("$SETPF" ': > "$MARK"' 'echo 허락받은-판')
reg3() { fresh "$2"; MARK="$T/mark-$2"; rm -f "$MARK"; f3="$(plan "p$2" "MARK=$MARK" "${P3[@]}")"; h3="$(hil "$1" --add "$f3" 2>/dev/null)"; h3="${h3#! bash }"; }
c3a() { local o rc; reg3 "$1" 3a; sed -i.bak 's/허락받은-판/허락받은-팜/' "$f3"
  o="$(runh "$h3" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && [ ! -e "$MARK" ] && [ ! -e "$h3.ran" ] && [ ! -e "$h3.out" ] && has "$o" "REJECT 계획이 등록 뒤 바뀜 — 등록 " "③a 1글자 수정 → rc1 · 표시 파일·.ran·.out 0" || bad "③a rc=$rc mark=$([ -e "$MARK" ] && echo 1) ran=$([ -e "$h3.ran" ] && echo 1) ← $o"; }
PB=('echo "0=$0 args=$*"' 'echo "pwd=$(pwd)"' 'echo err >&2' 'exit 7')
c3b() { local o0 o1 r0 r1 x b; [ -n "$BB" ] || { bad "③b 기준판 없음 — 판정 불가"; return; }
  for x in 0 1; do fresh "3b-$x"; [ "$x" = 0 ] && b="$BB" || b="$1"
    h3="$(hil "$b" --add "$(plan p3b "${PB[@]}")" 2>/dev/null)"; runh "${h3#! bash }" a1 "b 2" >/dev/null 2>&1; eval "r$x=\$?"; eval "o$x=\"\$(cat \"\$HD/h1.out\")\""; done
  [ "$o0" = "$o1" ] && [ "$r0" = 7 ] && [ "$r1" = 7 ] && ok "③b 수정 없이 실행 = 기준판과 같은 \$0·인자·pwd·stderr 사본 · rc 7 «${o1//$'\n'/|}»" || bad "③b 기준판 «$o0» rc=$r0 ≠ «$o1» rc=$r1"; }
c3c() { local o rc; reg3 "$1" 3c; MARK2="$T/mark2-3c"; rm -f "$MARK2"
  printf '#!/bin/bash\nprintf '"'"'\\n: > "%s"\\necho 바뀐-판\\n'"'"' >> "%s"\nexec /usr/bin/git "$@"\n' "$MARK2" "$f3" > "$T/gitstub/git"; chmod +x "$T/gitstub/git"
  o="$(runh --stub "$h3" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ -e "$MARK" ] && [ ! -e "$MARK2" ] && grep -q '바뀐-판' "$f3" && has "$o" "허락받은-판" "③c 검사와 실행 사이 수정(git 대역) = 등록한 판 실행 · 표시 파일 0" && hasnt "$o" "바뀐-판" "③c 바뀐 판 출력 0" || bad "③c rc=$rc mark2=$([ -e "$MARK2" ] && echo 1) ← $o"; }
c3d() { local o rc; reg3 "$1" 3d; rm -f "$h3.sha"; o="$(runh "$h3" 2>&1)"; rc=$?
  [ "$rc" = 3 ] && [ ! -e "$MARK" ] && has "$o" "판정 불가" "③d 새 꼴 h 의 .sha 지움 = rc3 · 계획 실행 0" || bad "③d rc=$rc ← $o"
  rm -rf "$T/nogate"; cp -R "$1" "$T/nogate"; reg3 "$T/nogate" 3e; rm -f "$T/nogate/ft-hil-gate.sh"; o="$(runh "$h3" 2>&1)"; rc=$?
  [ "$rc" = 3 ] && [ ! -e "$MARK" ] && has "$o" "판정 불가" "③e 보조 도구 치움 = rc3 · 계획 실행 0" || bad "③e rc=$rc ← $o"
  if [ -n "$BB" ]; then reg3 "$BB" 3f; sed -i.bak 's/허락받은-판/옛-판/' "$f3"; o="$(runh "$h3" 2>&1)"; rc=$?
    [ "$rc" = 0 ] && [ -e "$MARK" ] && has "$o" "옛-판" "③f 옛 꼴 진입 파일(기준판 등록 · .sha 없음) = 지금처럼 실행" || bad "③f rc=$rc ← $o"; else bad "③f 기준판 없음"; fi
  fresh 3g; printf 'import sys\nopen(sys.argv[2], "a").write("#")\nprint("ok")\n' > "$T/mutjudge.py"
  o="$(hil "$1" env FT_MIX_JUDGE="$T/mutjudge.py" --add "$(plan p3g "$SETPF" 'echo x')" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && [ "$(nh)" = 0 ] && has "$o" "REJECT 등록 중 계획이 바뀜 — 판정 앞 " "③g 판정기 사슬 중 수정 = rc1 · h 0" || bad "③g rc=$rc h=$(nh) ← $o"
  fresh 3h; { echo '#!/usr/bin/env bash'; head -c 99980 /dev/zero | tr '\0' '#'; echo; } > "$T/p3h.sh.hil"; [ "$(wc -c < "$T/p3h.sh.hil" | tr -d ' ')" = 100001 ] || bad "③h 입력 크기"
  o="$(hil "$1" --add "$T/p3h.sh.hil" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && [ "$(nh)" = 0 ] && has "$o" "REJECT 계획이 너무 큼 — 100001 > 100000" "③h 100001바이트 = rc1 · h 0" || bad "③h rc=$rc ← $o"; }

c4a() { local o f; fresh 4a; f="$(plan p4 "$SETPF" 'echo 판-1')"; hil "$1" --add "$f" >/dev/null 2>&1
  o="$(hil "$1" --add "$f" 2>/dev/null)"; [ "$o" = "! bash $HD/h1" ] && [ "$(nh)" = 1 ] && ok "④a 내용 같음 = 같은 h1 · h 수 그대로" || bad "④a o=$o h=$(nh)"; }
c4b() { local o e rc f s0; fresh 4b; f="$(plan p4 "$SETPF" 'echo 판-1')"; hil "$1" --add "$f" >/dev/null 2>&1; s0="$(cat "$HD/h1.sha" 2>/dev/null)"
  plan p4 "$SETPF" 'echo 판-2' >/dev/null; o="$(hil "$1" --add "$f" 2>"$T/e4")"; rc=$?; e="$(cat "$T/e4")"
  [ "$rc" = 1 ] && [ -z "$o" ] && [ "$(nh)" = 1 ] && [ "$(cat "$HD/h1.sha" 2>/dev/null)" = "$s0" ] && has "$e" "REJECT 계획이 바뀜 — h1 등록 " "④b 내용 바뀜 · --supersedes 없음 = rc1 · 새 h 0 · sha 불변" || bad "④b rc=$rc o=$o h=$(nh) ← $e"; }
c4c() { local o f; fresh 4c; f="$(plan p4 "$SETPF" 'echo 판-1')"; hil "$1" --add "$f" >/dev/null 2>&1
  plan p4 "$SETPF" 'echo 판-2' >/dev/null; o="$(hil "$1" --add "$f" --supersedes h1 2>/dev/null)"
  [ "$o" = "! bash $HD/h2" ] && [ "$(cat "$HD/h1.superseded" 2>/dev/null)" = h2 ] && [ "$(cut -c1-64 "$HD/h2.sha")" = "$(shasum -a 256 < "$f" | cut -c1-64)" ] && ok "④c --supersedes h1 = 새 h2 · h1 대체됨 · h2.sha = 새 sha" || bad "④c o=$o"
  has "$(runh "$HD/h1" 2>&1)" "REJECT 대체됨 → h2" "④c bash h1 = REJECT 대체됨 → h2"; }
c4d() { local o rc f; [ -n "$BB" ] || { bad "④d 기준판 없음 — 판정 불가"; return; }; fresh 4d; f="$(plan p4d "$SETPF" 'echo 옛-등록')"
  hil "$BB" --add "$f" >/dev/null 2>&1; o="$(hil "$1" --add "$f" 2>/dev/null)"
  [ "$o" = "! bash $HD/h1" ] && [ "$(nh)" = 1 ] && [ "$(head -1 "$HD/h1.sha" 2>/dev/null)" = "$(shasum -a 256 < "$f" | cut -c1-64)" ] && grep -q 'ft-hil-gate.sh' "$HD/h1" && ok "④d 옛 꼴 h1 다시 등록 = 같은 h1 + h1.sha + 새 꼴 진입 파일" || bad "④d o=$o h=$(nh) sha=$(cat "$HD/h1.sha" 2>/dev/null)"
  sed -i.bak 's/옛-등록/옛-등록-바뀜/' "$f"; o="$(runh "$HD/h1" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && has "$o" "REJECT 계획이 등록 뒤 바뀜" "④d 그 뒤 1글자 수정 = bash h1 rc1" || bad "④d 수정 뒤 rc=$rc ← $o"; }

c5() { local b="$1" e f; fresh 5; : > "$HD/h1.out"; f="$(plan p5 '# ft-hil-budget: 60' 'echo x')"
  e="$(bash "$b/ft-hil-gate.sh" budget "$f" "$HD/h1" 1000 1061 2>&1)"
  [ "$e" = "[상한 초과] h1 61초 > 60초 — 묶음을 줄여 다시 등록" ] && [ "$(tail -n 1 "$HD/h1.out")" = "$e" ] && ok "⑤a 선언 60 · 61초 = stderr · .out 끝 1줄" || bad "⑤a ← $e"
  e="$(bash "$b/ft-hil-gate.sh" budget "$(plan p5n 'echo x')" "$HD/h1" 1000 1071 2>&1)"; has "$e" "71초 > 70초" "⑤b 선언 없음 · 71초 = «> 70초»"; }
c5c() { local e; fresh 5c; e="$(bash "$1/ft-hil-gate.sh" budget "$(plan p5c '# ft-hil-budget: 60' 'echo x')" "$HD/h1" 1000 1060 2>&1)"
  [ -z "$e" ] && [ ! -s "$HD/h1.out" ] && ok "⑤c 선언 60 · 60초 = 줄 0" || bad "⑤c ← $e"; }
c5d() { local o rc h; fresh 5d; h="$(hil "$1" --add "$(plan p5d '# ft-hil-budget: 60' "echo \$((\$(date +%s) - 100)) >> \"$HD/h1.ran\"" 'exit 7')" 2>/dev/null)"
  o="$(runh "${h#! bash }" 2>&1)"; rc=$?
  [ "$rc" = 7 ] && has "$o" "[상한 초과] h1 " "⑤d 진입 파일: 초과 줄 stderr · rc 7 그대로" && has "$(tail -n 1 "$HD/h1.out" 2>/dev/null)" "초 > 60초 — 묶음을 줄여 다시 등록" "⑤d h1.out 끝 줄" || bad "⑤d rc=$rc ← $o"; }

c6() { local o r x b; [ -n "$BB" ] || { bad "⑥ 기준판($BASE)을 못 꺼냄 — 판정 불가"; return; }
  for x in 0 1; do fresh "6-$x"; [ "$x" = 0 ] && b="$BB" || b="$BIN0"
    o="$(hil "$b" --add "$(plan p6 "$SETPF" 'echo 위반-0')" 2>/dev/null)"; r=$?; eval "o$x=\"\${o//\$HD/HIL}\"; r$x=\$r; l$x=\"\$(ls \"\$HD\" | grep -v '\.sha\$' | tr '\n' ' ')\""
    o="$(hil "$b" --cmd 'echo x' 2>/dev/null)"; runh "${o#! bash }" >/dev/null 2>&1; eval "c$x=\"\${o//\$HD/HIL} rc=\$? \$(cat \"\$HD/h2.out\")\""; done
  [ "$o0" = "$o1" ] && [ "$r0" = "$r1" ] && [ "$l0" = "$l1" ] && ok "⑥ 위반 0 --add stdout·rc·파일(.sha 빼고) = 기준판 «$o1 rc=$r1 · ${l1}»" || bad "⑥ 기준판 «$o0 $r0 ${l0}» ≠ «$o1 $r1 ${l1}»"
  [ "$c0" = "$c1" ] && ok "⑥ --cmd 'echo x' 등록·실행 = 기준판 «${c1//$'\n'/|}»" || bad "⑥ --cmd 기준판 «${c0}» ≠ «${c1}»"; }

# ⑧ 고정 Red — DA#11 #310488 입력 바이트 그대로(만든 뒤 sha 로 원본과 같은지 확인)
F="$T/fixed"; mkdir -p "$F"
cat > "$F/conditional-exit.sh" <<'EOF'
set -o pipefail
n=$(timeout 7 git status --porcelain) || { n=0; [ "$n" -ge 0 ] || exit 3; }
if [ "$n" = 0 ]; then
  rm -rf "$p"
fi
EOF
cat > "$F/conditional-exit-safe.sh" <<'EOF'
timeout() { printf "injected timeout rc=124\n" >&2; return 124; }
set -o pipefail
n=$(timeout 7 git status --porcelain) || { n=0; [ "$n" -ge 0 ] || exit 3; }
if [ "$n" = 0 ]; then
  printf "WOULD_DELETE n=%s\n" "$n"
fi
EOF
cat > "$F/trailing-newline.sh" <<'EOF'
printf '%s\n' foo\
EOF
cat > "$F/locked-safe.sh" <<'EOF'
body() {
python3 - "$1" "$2" <<'PYBODY'
import hashlib,sys
b=open(sys.argv[2],'rb').read()
if hashlib.sha256(b).hexdigest()!=sys.argv[1]: sys.exit(1)
sys.stdout.buffer.write(b)
PYBODY
}
B="$(body "$1" "$2")" || exit 9
bash -c "$B" "$2"
EOF
fsha() { shasum -a 256 < "$1" | cut -c1-64; }
c8in() { local k s; for k in conditional-exit:e02e25e50d74cf53 conditional-exit-safe:ca0213eba3b85f83 trailing-newline:e2a5f6c942e40e79 locked-safe:744b58680e87dc38; do
  s="$(fsha "$F/${k%%:*}.sh")"; [ "${s:0:16}" = "${k#*:}" ] && ok "⑧ 입력 ${k%%:*}.sh 바이트 = 고정 원본($(wc -c < "$F/${k%%:*}.sh" | tr -d ' ')바이트)" || bad "⑧ 입력 ${k%%:*}.sh sha ${s:0:16} ≠ ${k#*:}"; done; }
c81() { local o rc e; o="$(python3 "$1/ft_hil_gate_judge.py" --plan "$F/conditional-exit.sh" 2>/dev/null)"; rc=$?
  [ "$rc" = 1 ] && has "$o" "reject J2 2줄 " "⑧-1 conditional-exit 판정기 rc1 · reject J2 2줄" && has "$o" "(지우는 줄 4줄)" "⑧-1 지우는 줄 4줄" || bad "⑧-1 rc=$rc ← $o"
  fresh 81; e="$(hil "$1" --add "$F/conditional-exit.sh" 2>&1)"; rc=$?; [ "$rc" = 1 ] && [ "$(nh)" = 0 ] && ok "⑧-1 --add rc1 · h 0" || bad "⑧-1 --add rc=$rc h=$(nh) ← $e"; }
c82() { local o rc; o="$(python3 "$1/ft_hil_gate_judge.py" --plan "$F/conditional-exit-safe.sh" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && has "$o" "warn h 공통 규칙 — J2 3줄 " "⑧-2 conditional-exit-safe = warn J2 3줄 rc0" || bad "⑧-2 rc=$rc ← $o"
  o="$( (cd "$T" && env -i PATH=/usr/bin:/bin bash "$F/conditional-exit-safe.sh" 2>/dev/null) )"; rc=$?
  [ "$rc" = 0 ] && [ "$o" = "WOULD_DELETE n=0" ] && ok "⑧-2 대조: 그대로 실행 = WOULD_DELETE n=0 · rc0(실패가 정상 값이 되는 길)" || bad "⑧-2 대조 rc=$rc ← $o"; }
c83() { local o rc w; fresh 83; cp "$F/trailing-newline.sh" "$T/p83.sh"; h3="$(hil "$1" --add "$T/p83.sh" 2>/dev/null)"; h3="${h3#! bash }"
  ( cd /tmp && for v in $(compgen -e); do unset "$v" 2>/dev/null; done; export HOME="$T/home" PATH="${BASH%/*}:/usr/bin:/bin"; "$BASH" "$h3" ) >/dev/null 2>&1; rc=$?; cp "$h3.out" "$T/o83" 2>/dev/null; ( cd /tmp && "$BASH" "$T/p83.sh" ) > "$T/w83" 2>/dev/null   # 시험을 돌리는 bash(macOS /bin/bash 3.2 는 끝 backslash 를 버려 차이가 안 보임)   # 진입 파일 stdout 사본 = .out(뒤 «남은 미실행» 줄은 결과 쪽지 몫)
  [ "$rc" = 0 ] && cmp -s "$T/o83" "$T/w83" && printf 'foo\n' > "$T/x83" && cmp -s "$T/o83" "$T/x83" && ok "⑧-3 끝 개행 계획 = bash h 와 bash 계획 stdout 같음(foo+개행) · rc0" || bad "⑧-3 rc=$rc h=«$(od -An -c "$T/o83")» 계획=«$(od -An -c "$T/w83")»"; }
c84() { local s; s="$(fsha "$T/p83.sh")"; ( cd /tmp && PATH="${BASH%/*}:$PATH" "$BASH" "$F/locked-safe.sh" "$s" "$T/p83.sh" ) > "$T/l84" 2>/dev/null
  [ -s "$T/o83" ] && ! cmp -s "$T/l84" "$T/o83" && printf 'foo\\\n' > "$T/x84" && cmp -s "$T/l84" "$T/x84" && ok "⑧-4 끝 개행을 지우는 대조판(foo+\\+개행) ≠ 진입 파일 stdout" || bad "⑧-4 대조판=«$(od -An -c "$T/l84")» h=«$(od -An -c "$T/o83" 2>/dev/null)»"; }
c8() { c81 "$1"; c82 "$1"; c83 "$1"; c84 "$1"; }

sec "① 판정기 규칙"; c1 "$BIN0"; c1r1 "$BIN0"; c1m8 "$BIN0"
sec "② 거절과 경고"; c2a "$BIN0"; c2b "$BIN0"
sec "③ sha 잠금 · 검사한 바이트 실행"; c3a "$BIN0"; c3b "$BIN0"; c3c "$BIN0"; c3d "$BIN0"
sec "④ 다시 등록"; c4a "$BIN0"; c4b "$BIN0"; c4c "$BIN0"; c4d "$BIN0"
sec "⑤ 걸린 초"; c5 "$BIN0"; c5c "$BIN0"; c5d "$BIN0"
sec "⑥ 등록 출력 불변 · bin=kit · 줄 상한"; c6
for f in ft-hil.sh ft-hil-gate.sh ft_hil_gate_judge.py; do cmp -s "$BIN0/$f" "$KIT/$f" && ok "bin=kit $f" || bad "bin≠kit $f"; done
n="$(wc -l < "$BIN0/ft-hil.sh" | tr -d ' ')"; [ "$n" -le 200 ] && ok "ft-hil.sh ${n}줄 ≤200" || bad "ft-hil.sh ${n}줄 > 200"
c2a "$KIT"; c3a "$KIT"; c3c "$KIT"
sec "⑧ 고정 Red 4칸"; c8in; c8 "$BIN0"

sec "변이 M1~M10 — 사본에서 해당 칸 FAIL · 원본 같은 칸 PASS"
mutv() { local f0=$fail; "$@" > /dev/null 2>&1; local d=$((fail - f0)); fail=$f0; [ "$d" -gt 0 ]; }
mut() {  # <이름> <바꿀 파일> <perl 식> <칸> — 사본 고침 · 사본 ≠ 원본 · 사본 칸 FAIL + 원본 칸 PASS
  local m="$T/mut-$1"; rm -rf "$m"; cp -R "$BIN0" "$m" && perl -0pe "$3" "$BIN0/$2" > "$m/$2"
  cmp -s "$BIN0/$2" "$m/$2" && { bad "변이 $1 사본 = 원본"; return; }
  mutv "$4" "$m" && ! mutv "$4" "$BIN0" && ok "변이 $1 → $4 FAIL 검출 · 원본 PASS" || bad "변이 $1 을 $4 로 못 잡음(또는 원본 FAIL)"
}
mut M1-swallow-in ft_hil_gate_judge.py 's/if m and re\.search\(r"\\\|\\\|\|;", inner\[m\.end\(\):\]\):/if False:/' c1r1
mut M2-destroy ft_hil_gate_judge.py 's/(def destroys\(w: list\[str\]\) -> bool:\n)/$1    return False\n/' c2a
mut M3-shacheck ft-hil-gate.sh 's/\[ "\$s" = "\$o" \] \|\| \{ echo "REJECT 계획이 등록 뒤/true || { echo "REJECT 계획이 등록 뒤/' c3a
mut M4-reuse ft-hil-gate.sh 's/elif \[ "\$2" = "\$o" \]; then/elif true; then/' c4b
mut M5-ge ft-hil-gate.sh 's/\[ "\$e" -gt /[ "\$e" -ge /' c5c
mut M6-reread ft-hil.sh 's/bash -c "\$B" "\$P" "\$@"/bash "\$P" "\$@"/' c3c
mut M7-shaonly ft-hil.sh 's/entry_body "\$t" "\$D\/h\$n" "\$rc_c" "\$\{rq\[\*\]-\}" > "\$D\/h\$n" && bash/bash/' c4d
mut M8-or-pass ft_hil_gate_judge.py 's/if m and o and not h\.group\("cond"\) and not CLOSED\.match\(o\.group\(1\)\):/if False:/' c1m8
mut M9-leave-word ft_hil_gate_judge.py 's/not CLOSED\.match\(o\.group\(1\)\)/not re.search(LEAVE, o.group(1))/' c81
mut M10-no-marker ft-hil-gate.sh "s/printf '%s' \"\\\$b\" ;;/printf '%s' \"\\\${b%.}\" ;;/" c83

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
