#!/usr/bin/env bash
# test_hil_gate_r2078.sh — r2078: h 등록 공통 규칙 판정기(J1 pipefail · J2 timeout rc · J3 초 선언) + 진입 파일 sha 잠금 · 다시 등록 · 걸린 초
#   카드 반례 ①~⑥ · 변이 M1~M5(사본 · 변이마다 원본 같은 칸 PASS 대조) · bin·kit 같은 내용 · ft-hil.sh ≤200줄
# 격리: 임시 HIL_DIR · 임시 HOME · HIL_CLIP=0 · 가짜 mbox.sh · 리포 밖 계획(mktemp) — 실 /tmp/h* · 실 쪽지함 · 실 계획 0 · sleep 0(걸린 초 = 보조 도구 인자 · .ran 시작 줄 주입)
#   기준판: R2078_BIN=<origin/main bin 사본> 이면 ②a · ③a · ④b · ⑤d 가 FAIL(Red) · ⑥ 은 팩 커밋 450d5038(기준판)을 git archive 로 꺼내 견준다
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

C="$T/comm"; mkdir -p "$C" "$T/home"
printf '{"_master": "byz-planner-master-claude#1"}\n' > "$T/seats-planner.json"
printf '#!/bin/bash\nprintf "%%s\\t%%s\\t%%s\\n" "$2" "$3" "$4" >> "$(dirname "$0")/sent.log"\n' > "$C/mbox.sh"
hil()  { local b="$1"; shift; env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$C" bash "$b/ft-hil.sh" "$@"; }
runh() { ( cd /tmp && env -i HOME="$T/home" PATH="/usr/bin:/bin" bash "$1" ); }
plan() { local f="$T/$1.sh.hil"; shift; { echo '#!/usr/bin/env bash'; printf '%s\n' "$@"; } > "$f"; echo "$f"; }
fresh() { HD="$T/hd-$1"; rm -rf "$HD"; mkdir -p "$HD"; }
nh() { find "$HD" -maxdepth 1 -name 'h[0-9]*' ! -name '*.*' | wc -l | tr -d ' '; }
judge() { local f; f="$(plan "$2" "${@:3}")"; python3 "$1/ft_hil_gate_judge.py" --plan "$f" 2>/dev/null; }
jc() {  # <bin> <이름> <기대 글자|ok> <줄…> — 판정기 1칸
  local b="$1" k="$2" want="$3" o; shift 3; o="$(judge "$b" "j-$k" "$@")"
  if [ "$want" = ok ]; then [ "$o" = ok ] && ok "① $k = ok" || bad "① $k 기대 ok ← $o"; else has "$o" "$want" "① $k → $want"; fi
}
SETPF='set -euo pipefail'

c1() { local b="$1"
  jc "$b" pipe "J1 2줄" 'a | b'; jc "$b" pipe-pf ok "$SETPF" 'a | b'
  jc "$b" pipe-text ok '# a | b' 'echo "a | b"' "printf '%s' 'x|y'" 'x || y'
  jc "$b" j2-pipe "J2 2줄 시간 상한 건 명령의 rc 를 안 봄" 'n=$(timeout 7 git status --porcelain | wc -l)'
  jc "$b" j2-rc ok 'o=$(timeout 7 git status --porcelain); rc=$?'
  jc "$b" j2-or ok 'h=$(timeout 7 git rev-parse HEAD) || { echo SKIP; exit 3; }'
  jc "$b" j2-rcok ok 'n=$(timeout 7 x || echo 0) # rc-ok: 출력 글로 판정'
  jc "$b" j2-out ok 'timeout 25 rm -rf "$p"'
  jc "$b" j3-none "J3 2줄 반복이 있는데 «# ft-hil-budget: <초>» 줄이 0개" 'for i in 1 2; do :; done'
  jc "$b" j3-60 ok '# ft-hil-budget: 60' 'for i in 1 2; do :; done'
  jc "$b" j3-two "줄이 2개" '# ft-hil-budget: 60' '# ft-hil-budget: 60' 'while x; do :; done'
  jc "$b" j3-0 "선언 0초 — 1~70 밖" '# ft-hil-budget: 0' 'until x; do :; done'
  jc "$b" j3-71 "선언 71초 — 1~70 밖" '# ft-hil-budget: 71' 'for i in 1; do :; done'
  jc "$b" j3-noloop ok 'echo 반복 없음'; }
c1s() { jc "$1" j2-swallow "J2 2줄 시간 상한 건 명령의 rc 를 삼킴" 'n=$(timeout 7 x || echo 0)'; }

BAD3=('n=$(timeout 7 false | wc -l)' 'for i in 1 2; do rm -rf "/tmp/r2078-none-$i"; done' 'echo "n=$n"')
c2a() { local b="$1" o rc e; fresh 2a
  o="$(judge "$b" p2a "${BAD3[@]}")"; rc=$?
  [ "$rc" = 1 ] && [ "$(grep -c '^reject ' <<< "$o")" = 3 ] && has "$o" "reject J1 2줄 파이프가 있는데 그 앞에 set -o pipefail 없음 (지우는 줄 3줄)" "②a 판정기 rc1 · reject 3줄(규칙·줄·지우는 줄)" || bad "②a 판정기 rc=$rc ← $o"
  e="$(hil "$b" --add "$T/p2a.sh.hil" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = 1 ] && [ "$(nh)" = 0 ] && [ -z "$(ls -A "$HD")" ] && has "$e" "REJECT J1 2줄" "②a --add rc1 · h 0 · 표식 0" || bad "②a --add rc=$rc h=$(nh) ls=$(ls -A "$HD" | tr '\n' ' ') ← $e"; }
c2b() { local b="$1" o e rc f; fresh 2b; f="$(plan p2b 'n=$(timeout 7 false | wc -l)' 'for i in 1 2; do echo "rm -rf /x-$i"; done' '# rm -rf /y')"
  o="$(hil "$b" --add "$f" 2>"$T/e2b")"; rc=$?; e="$(cat "$T/e2b")"
  [ "$rc" = 0 ] && [ "$o" = "! bash $HD/h1" ] && [ "$(grep -c 'h 공통 규칙' <<< "$e")" = 1 ] && has "$e" "WARN h 공통 규칙 — J1 2줄" "②b 지우는 줄 없음(주석·echo 안 rm) = 경고 1줄 · stdout ! bash 1줄 · rc0" || bad "②b rc=$rc o=$o ← $e"
  fresh 2c; e="$(hil "$b" --add "$(plan p2c "$SETPF" 'echo ok')" 2>&1 >/dev/null)"
  hasnt "$e" "h 공통 규칙" "②c 위반 0 = stderr 에 «h 공통 규칙» 0"
  o="$(python3 "$b/ft_hil_gate_judge.py" --plan "$T/none.sh" 2>/dev/null)"; rc=$?
  [ "$rc" = 2 ] && [ -z "$o" ] && ok "②d 없는 파일 = rc2 · reject 글 0" || bad "②d rc=$rc o=$o"; }

P3=("$SETPF" ': > "$MARK"' 'echo 허락받은-판')
reg3() { fresh "$2"; MARK="$T/mark-$2"; rm -f "$MARK"; f3="$(plan "p$2" "MARK=$MARK" "${P3[@]}")"; h3="$(hil "$1" --add "$f3" 2>/dev/null)"; h3="${h3#! bash }"; }
c3a() { local o rc; reg3 "$1" 3a; sed -i.bak 's/허락받은-판/허락받은-팜/' "$f3"
  o="$(runh "$h3" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && [ ! -e "$MARK" ] && [ ! -e "$h3.ran" ] && [ ! -e "$h3.out" ] && has "$o" "REJECT 계획이 등록 뒤 바뀜 — 등록 " "③a 1글자 수정 → rc1 · 표시 파일·.ran·.out 0" || bad "③a rc=$rc mark=$([ -e "$MARK" ] && echo 1) ran=$([ -e "$h3.ran" ] && echo 1) ← $o"; }
c3b() { local o rc; reg3 "$1" 3b; o="$(runh "$h3" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ -e "$MARK" ] && has "$(cat "$h3.out")" "허락받은-판" "③b 수정 없음 = 실행 rc0" || bad "③b rc=$rc ← $o"
  reg3 "$1" 3c; sed -i.bak 's/허락받은-판/바뀐-판/' "$f3"; rm -f "$h3.sha"; o="$(runh "$h3" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ -e "$MARK" ] && ok "③c h<N>.sha 없는 h = 그대로 실행" || bad "③c rc=$rc ← $o"
  rm -rf "$T/nogate"; cp -R "$1" "$T/nogate"; reg3 "$T/nogate" 3d; rm -f "$T/nogate/ft-hil-gate.sh"; o="$(runh "$h3" 2>&1)"; rc=$?
  [ "$rc" = 3 ] && [ ! -e "$MARK" ] && has "$o" "판정 불가" "③d 보조 도구 치움 = rc3 · 계획 실행 0" || bad "③d rc=$rc ← $o"; }

c4a() { local o f s; fresh 4a; f="$(plan p4 "$SETPF" 'echo 판-1')"; hil "$1" --add "$f" >/dev/null 2>&1
  o="$(hil "$1" --add "$f" 2>/dev/null)"; [ "$o" = "! bash $HD/h1" ] && [ "$(nh)" = 1 ] && ok "④a 내용 같음 = 같은 h1 · h 수 그대로" || bad "④a o=$o h=$(nh)"
  rm -f "$HD/h1.sha"; o="$(hil "$1" --add "$f" 2>/dev/null)"; s="$(head -1 "$HD/h1.sha" 2>/dev/null)"
  [ "$o" = "! bash $HD/h1" ] && [ "${#s}" = 64 ] && ok "④d sha 없음 · 같은 경로 = 같은 h1 + h1.sha 생김" || bad "④d o=$o sha=$s"; }
c4b() { local o e rc f s0; fresh 4b; f="$(plan p4 "$SETPF" 'echo 판-1')"; hil "$1" --add "$f" >/dev/null 2>&1; s0="$(cat "$HD/h1.sha" 2>/dev/null)"
  plan p4 "$SETPF" 'echo 판-2' >/dev/null; o="$(hil "$1" --add "$f" 2>"$T/e4")"; rc=$?; e="$(cat "$T/e4")"
  [ "$rc" = 1 ] && [ -z "$o" ] && [ "$(nh)" = 1 ] && [ "$(cat "$HD/h1.sha" 2>/dev/null)" = "$s0" ] && has "$e" "REJECT 계획이 바뀜 — h1 등록 " "④b 내용 바뀜 · --supersedes 없음 = rc1 · 새 h 0 · sha 불변" || bad "④b rc=$rc o=$o h=$(nh) ← $e"; }
c4c() { local o f; fresh 4c; f="$(plan p4 "$SETPF" 'echo 판-1')"; hil "$1" --add "$f" >/dev/null 2>&1
  plan p4 "$SETPF" 'echo 판-2' >/dev/null; o="$(hil "$1" --add "$f" --supersedes h1 2>/dev/null)"
  [ "$o" = "! bash $HD/h2" ] && [ "$(cat "$HD/h1.superseded" 2>/dev/null)" = h2 ] && [ "$(cut -c1-64 "$HD/h2.sha")" = "$(shasum -a 256 < "$f" | cut -c1-64)" ] && ok "④c --supersedes h1 = 새 h2 · h1 대체됨 · h2.sha = 새 sha" || bad "④c o=$o"
  has "$(runh "$HD/h1" 2>&1)" "REJECT 대체됨 → h2" "④c bash h1 = REJECT 대체됨 → h2"; }

c5() { local b="$1" e f; fresh 5; : > "$HD/h1.out"; f="$(plan p5 '# ft-hil-budget: 60' 'echo x')"
  e="$(bash "$b/ft-hil-gate.sh" budget "$f" "$HD/h1" 1000 1061 2>&1)"
  [ "$e" = "[상한 초과] h1 61초 > 60초 — 묶음을 줄여 다시 등록" ] && [ "$(tail -n 1 "$HD/h1.out")" = "$e" ] && ok "⑤a 선언 60 · 61초 = stderr · .out 끝 1줄" || bad "⑤a ← $e"
  e="$(bash "$b/ft-hil-gate.sh" budget "$(plan p5n 'echo x')" "$HD/h1" 1000 1071 2>&1)"; has "$e" "71초 > 70초" "⑤b 선언 없음 · 71초 = «> 70초»"; }
c5c() { local e; fresh 5c; e="$(bash "$1/ft-hil-gate.sh" budget "$(plan p5c '# ft-hil-budget: 60' 'echo x')" "$HD/h1" 1000 1060 2>&1)"
  [ -z "$e" ] && [ ! -s "$HD/h1.out" ] && ok "⑤c 선언 60 · 60초 = 줄 0" || bad "⑤c ← $e"; }
c5d() { local o rc h; fresh 5d; h="$(hil "$1" --add "$(plan p5d '# ft-hil-budget: 60' "echo \$((\$(date +%s) - 100)) >> \"$HD/h1.ran\"" 'exit 7')" 2>/dev/null)"
  o="$(runh "${h#! bash }" 2>&1)"; rc=$?
  [ "$rc" = 7 ] && has "$o" "[상한 초과] h1 " "⑤d 진입 파일: 초과 줄 stderr · rc 7 그대로" && has "$(tail -n 1 "$HD/h1.out" 2>/dev/null)" "초 > 60초 — 묶음을 줄여 다시 등록" "⑤d h1.out 끝 줄" || bad "⑤d rc=$rc ← $o"; }

c6() { local B="$T/base" o0 o1 r0 r1 l0 l1 x; mkdir -p "$B"
  git -C "$(git -C "$HERE" rev-parse --show-toplevel)" archive "$BASE" -- "$(git -C "$HERE/../bin" rev-parse --show-prefix)" 2>/dev/null | tar -x -C "$B" 2>/dev/null; B="$(find "$B" -type d -name bin -path '*harness/bin' | head -1)"
  [ -f "$B/ft-hil.sh" ] || { bad "⑥ 기준판($BASE)을 못 꺼냄 — 판정 불가"; return; }
  for x in 0 1; do fresh "6-$x"; [ "$x" = 0 ] && b="$B" || b="$BIN0"
    o="$(hil "$b" --add "$(plan p6 "$SETPF" 'echo 위반-0')" 2>/dev/null)"; r=$?; eval "o$x=\"\${o//\$HD/HIL}\"; r$x=\$r; l$x=\"\$(ls \"\$HD\" | grep -v '\.sha\$' | tr '\n' ' ')\""
    o="$(hil "$b" --cmd 'echo x' 2>/dev/null)"; runh "${o#! bash }" >/dev/null 2>&1; eval "c$x=\"\${o//\$HD/HIL} rc=\$? \$(cat \"\$HD/h2.out\")\""; done
  [ "$o0" = "$o1" ] && [ "$r0" = "$r1" ] && [ "$l0" = "$l1" ] && ok "⑥ 위반 0 --add stdout·rc·파일(.sha 빼고) = 기준판 «$o1 rc=$r1 · ${l1}»" || bad "⑥ 기준판 «$o0 $r0 ${l0}» ≠ «$o1 $r1 ${l1}»"
  [ "$c0" = "$c1" ] && ok "⑥ --cmd 'echo x' 등록·실행 = 기준판 «${c1//$'\n'/|}»" || bad "⑥ --cmd 기준판 «${c0}» ≠ «${c1}»"; }

sec "① 판정기 규칙"; c1 "$BIN0"; c1s "$BIN0"
sec "② 거절과 경고"; c2a "$BIN0"; c2b "$BIN0"
sec "③ sha 잠금"; c3a "$BIN0"; c3b "$BIN0"
sec "④ 다시 등록"; c4a "$BIN0"; c4b "$BIN0"; c4c "$BIN0"
sec "⑤ 걸린 초"; c5 "$BIN0"; c5c "$BIN0"; c5d "$BIN0"
sec "⑥ 등록 출력 불변 · bin=kit · 줄 상한"; c6
for f in ft-hil.sh ft-hil-gate.sh ft_hil_gate_judge.py; do cmp -s "$BIN0/$f" "$KIT/$f" && ok "bin=kit $f" || bad "bin≠kit $f"; done
n="$(wc -l < "$BIN0/ft-hil.sh" | tr -d ' ')"; [ "$n" -le 200 ] && ok "ft-hil.sh ${n}줄 ≤200" || bad "ft-hil.sh ${n}줄 > 200"
c2a "$KIT"; c3a "$KIT"

sec "변이 M1~M5 — 사본에서 해당 칸 FAIL · 원본 같은 칸 PASS"
mutv() { local f0=$fail; "$@" > /dev/null 2>&1; local d=$((fail - f0)); fail=$f0; [ "$d" -gt 0 ]; }
mut() {  # <이름> <바꿀 파일> <perl 식> <칸> — 사본 고침 · 사본 ≠ 원본 · 사본 칸 FAIL + 원본 칸 PASS
  local m="$T/mut-$1"; rm -rf "$m"; cp -R "$BIN0" "$m" && perl -0pe "$3" "$BIN0/$2" > "$m/$2"
  cmp -s "$BIN0/$2" "$m/$2" && { bad "변이 $1 사본 = 원본"; return; }
  mutv "$4" "$m" && ! mutv "$4" "$BIN0" && ok "변이 $1 → $4 FAIL 검출 · 원본 PASS" || bad "변이 $1 을 $4 로 못 잡음(또는 원본 FAIL)"
}
mut M1-swallow ft_hil_gate_judge.py 's/swallow = any\(.*\n/swallow = False\n/' c1s
mut M2-destroy ft_hil_gate_judge.py 's/(def destroys\(w: list\[str\]\) -> bool:\n)/$1    return False\n/' c2a
mut M3-shacheck ft-hil.sh 's/bash "\$G" check "\$P" "\$M" \|\| exit \$\?; //' c3a
mut M4-reuse ft-hil-gate.sh 's/if \[ "\$s" = "\$o" \]; then/if true; then/' c4b
mut M5-ge ft-hil-gate.sh 's/\[ "\$e" -gt /[ "\$e" -ge /' c5c

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
