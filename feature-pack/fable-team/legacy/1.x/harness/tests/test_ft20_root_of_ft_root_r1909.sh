#!/usr/bin/env bash
# test_ft20_root_of_ft_root_r1909.sh — r1909 ft20_root_of 가 FT_ROOT(데이터 루트)를 보고, 루트를 못 정하면 1.x 쓰기 입구가 rc3 + 사유 1줄로 멈춘다.
#   반례 ①~⑨(DA 동결) + team-switch --root 는 helper 안 부름 + tick 은 return(셸 생존) · 변이 M1(호출자 옛 꼴) → ⑥ FAIL · M2(FT_ROOT 단계 삭제) → ② FAIL
#   격리: 임시 git 리포 G + 그 worktree D(kakao 꼴 데이터 루트) · 임시 kit 사본 · tmux/tmuxc = 실패 stub · HOME 임시 · 실 명부·pane·mbox·설치 쓰기 0 · sleep 0
#   tick 은 살아 있는 tmux 후계가 있어야 retarget_seat 에 닿는다 → 실제 파일에서 그 함수를 떼어 부른다 · role-spawn 앞단 게이트(자원·all-stop·명부 풀기)는 stub
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
H="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../bin" && pwd)"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
G="$T/g"; D="$T/d"; K="$T/kit"; OUT="$T/out"; S="$T/stub"; fail=0; n=0
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
now() { date +%s; }; secs() { echo "$(( $(now) - $1 ))초"; }
unset FT_FT20_ROOT FT_ROOT FT_TEAM FT_SEATS_JSON
export HOME="$T/home" FT_ACCT_ASSIGN=0 FT_RECLAIM=0 PATH="$S:$PATH"; mkdir -p "$HOME" "$OUT" "$S"
t0=$(now); for c in tmux tmuxc; do printf '#!/bin/sh\nexit 1\n' > "$S/$c"; chmod +x "$S/$c"; done
git init -q "$G" && git -C "$G" -c user.name=t -c user.email=t@t commit -q --allow-empty -m 0 && git -C "$G" worktree add -q --detach "$D" || { echo "FAIL 준비 — git"; exit 1; }
for r in "$G" "$D"; do mkdir -p "$r/.fable-team/state/ft20-switch" "$r/design/harness/indices/대기"; printf '{"byz-harness-master-pi#1":{"role":"master","tick":"m"},"_master":"byz-harness-master-pi#1"}\n' > "$r/.fable-team/seats-harness.json"; printf '# c\n## 상태\n' > "$r/design/harness/indices/대기/c.md"; done
ln -s "$G" "$T/glink"; printf 'body\n' > "$T/body.txt"; printf '# c\n' > "$OUT/c.md"
mk() { local d="$1" f; rm -rf "$d"; mkdir -p "$d"; for f in ft20-switch-lib ft-index-move ft-nano-spawn ft-role-spawn ft-seat-retire ft-successor-open ft-tick-team ft-team-switch ft-name-lint; do cp -p "$H/$f.sh" "$d/"; done
  printf '#!/bin/sh\nexit 0\n' > "$d/ft-resource-gate.sh"; printf 'ft_reclaim_capped() { :; }\n' > "$d/ft-reclaim-capped.sh"; printf '#!/bin/sh\nexit 0\n' > "$d/ft-all-stop.sh"
  printf 'import sys\nsys.exit(1)\n' > "$d/ft_raised.py"; printf 'import sys\nprint(sys.argv[2] + "/.fable-team/seats-harness.json")\n' > "$d/ft_team_lib.py"; }
mk "$K"; mark() { printf '{"team":"%s","switched_at":"t","h":"%s"}\n' "$2" "$3" > "$1/.fable-team/state/ft20-switch/$2.json"; }
clr() { rm -f "$G"/.fable-team/state/ft20-switch/*.json "$D"/.fable-team/state/ft20-switch/*.json; }
snap() { python3 -c 'import os,sys
for r in sys.argv[1:]:
  for b,ds,fs in os.walk(r):
    ds[:]=[x for x in ds if x!=".git"]
    for f in fs: p=os.path.join(b,f); s=os.lstat(p); print(p,s.st_mtime_ns,s.st_size)' "$G" "$D" | sort; }
lib() { ( . "$K/ft20-switch-lib.sh"; ft20_root_of "$1" ) 2>"$T/e"; }   # stdout = 루트 · stderr = $T/e
one() { [ "$(grep -c . "$T/e")" = 1 ] && grep -q '^REJECT 데이터 루트 판정 불가' "$T/e"; }
run() { shift; "$@" >"$T/o" 2>&1; RC=$?; }   # run <이름> <명령...> → $T/o · RC
t=$(now)
# ① BYZ 꼴(FT_ROOT = git 루트) · ⑤ FT_FT20_ROOT · ④ 심링크 · ⑨ git 밖
o="$(FT_ROOT="$G" lib "$G/design")"; ck "① FT_ROOT=git 루트 → 그 루트 rc0" "$([ "$o" = "$G" ] && [ ! -s "$T/e" ] && echo 0 || echo 1)"
o="$(FT_FT20_ROOT=/nowhere FT_ROOT="$D" lib "$G")"; ck "⑤ FT_FT20_ROOT 주입 → 그 값만" "$([ "$o" = /nowhere ] && echo 0 || echo 1)"
mark "$G" harness 1; mark "$D" harness 2
o="$(FT_ROOT="$T/glink" lib "$G")"; ck "④ 같은 실경로(심링크) → 후보 1개(표식 비교 0) rc0" "$([ "$o" = "$G" ] && echo 0 || echo 1)"
o="$(lib "$OUT/c.md")"; rc=$?; ck "⑨ git 밖 ∧ FT_ROOT 없음 → rc3 1줄" "$([ "$rc" = 3 ] && [ -z "$o" ] && one && echo 0 || echo 1)"
o="$(FT_ROOT="$T/no-dir" lib "$G")"; rc=$?; ck "⑨b FT_ROOT 폴더 아님 → rc3 1줄" "$([ "$rc" = 3 ] && [ -z "$o" ] && one && echo 0 || echo 1)"
# ③ 두 루트 다른 표식 · 같은 표식
o="$(FT_ROOT="$D" lib "$D")"; rc=$?; ck "③ 두 루트 다른 표식(내용) → rc3 1줄" "$([ "$rc" = 3 ] && [ -z "$o" ] && one && echo 0 || echo 1)"
clr; mark "$G" harness 1; mark "$D" aifp 1
o="$(FT_ROOT="$D" lib "$D")"; rc=$?; ck "③ 두 루트 다른 팀 집합 → rc3" "$([ "$rc" = 3 ] && one && echo 0 || echo 1)"
clr; mark "$G" harness 1; cp "$G/.fable-team/state/ft20-switch/harness.json" "$D/.fable-team/state/ft20-switch/"
o="$(FT_ROOT="$D" lib "$D")"; ck "③ 같은 이름·cmp0 → FT_ROOT" "$([ "$o" = "$D" ] && echo 0 || echo 1)"
echo "helper $(secs "$t")"; cases2() {  # $1 = kit · ② kakao 꼴(표식 데이터 루트만)
  local k="$1"; clr; mark "$D" harness 1
  ( cd "$D" && FT_ROOT="$D" bash "$k/ft-index-move.sh" "$D/design/harness/indices/대기/c.md" 진행 --seat x ) >"$T/o2" 2>&1; local rc=$?
  echo "② $([ "$rc" = 3 ] && grep -q '2.0 전환됨' "$T/o2" && [ -f "$D/design/harness/indices/대기/c.md" ] && echo 0 || echo 1)"
}
cases6() {  # $1 = kit · $2 = 입구 목록 · ⑥ 충돌 → rc3 · 쓰기 0 · 사유 1줄
  local k="$1" e b; clr; mark "$G" harness 1; mark "$D" harness 2
  for e in $2; do b="$(snap)"
    case "$e" in
      move) ( cd "$D" && FT_ROOT="$D" bash "$k/ft-index-move.sh" "$D/design/harness/indices/대기/c.md" 진행 --seat x ) >"$T/o" 2>&1;;
      roster) ( cd "$D" && FT_ROOT="$D" bash "$k/ft-role-spawn.sh" master --team harness --agent pi --model m ) >"$T/o" 2>&1;;
      retire) ( cd "$D" && FT_ROOT="$D" bash "$k/ft-seat-retire.sh" 'byz-harness-master-pi#1' 'byz-harness-da-pi#2' ) >"$T/o" 2>&1;;
      successor) ( cd "$D" && FT_ROOT="$D" bash "$k/ft-successor-open.sh" 'byz-harness-master-pi#1' "$D" --name 'byz-harness-master-pi#2' --agent pi --model m --body-file "$T/body.txt" ) >"$T/o" 2>&1;;
      tick) ( cd "$D" && HERE="$k" ROOT="$G" WT="$D" SEATS="$G/.fable-team/seats-harness.json" FT_ROOT="$D"
              eval "$(sed -n '/^retarget_seat() {/,/^}/p' "$k/ft-tick-team.sh")"; retarget_seat 'byz-harness-master-pi#1' 2; echo "ALIVE rc=$?" ) >"$T/o" 2>&1;;
    esac; local rc=$?; [ "$e" != tick ] || { grep -q '^ALIVE rc=3$' "$T/o" && rc=3; }
    echo "⑥$e $([ "$rc" = 3 ] && [ "$(grep -c '^REJECT 데이터 루트 판정 불가' "$T/o")" = 1 ] && [ "$(snap)" = "$b" ] && echo 0 || echo 1)"
  done
}
t=$(now); while read -r k v; do ck "$k kakao 꼴 표식 데이터 루트만 → move rc3 «2.0 전환됨» · 카드 그대로" "$v"; done < <(cases2 "$K"); echo "② $(secs "$t")"
t=$(now); while read -r k v; do ck "$k 충돌 → rc3 · 사유 1줄 · 명부·카드·도달 파일 mtime 무변(tick = return 뒤 셸 생존)" "$v"; done < <(cases6 "$K" "roster move retire successor tick"); echo "⑥ $(secs "$t")"
t=$(now); clr; mark "$G" harness 1   # ⑦ spawn rc3 보존(git 밖 카드 · 표식 팀 카드)
run spawn bash "$K/ft-nano-spawn.sh" "$OUT/c.md"; ck "⑦ spawn git 밖 카드 rc3 «데이터 루트 판정 불가»" "$([ "$RC" = 3 ] && grep -q '데이터 루트 판정 불가' "$T/o" && echo 0 || echo 1)"
run spawn bash "$K/ft-nano-spawn.sh" "$G/design/harness/indices/대기/c.md"; ck "⑦ spawn 전환 팀 카드 rc3 «2.0 전환됨»" "$([ "$RC" = 3 ] && grep -q '2.0 전환됨' "$T/o" && echo 0 || echo 1)"
# + team-switch: --root 면 helper 0(FT_ROOT 폴더 아님이어도 통과) · 없으면 helper(git 밖 rc3)
run ts bash -c "cd '$OUT' && FT_ROOT='$T/no-dir' bash '$K/ft-team-switch.sh' status harness --root '$G'"; ck "+ team-switch --root → helper 안 부름 rc0" "$([ "$RC" = 0 ] && ! grep -q '판정 불가' "$T/o" && echo 0 || echo 1)"
run ts bash -c "cd '$OUT' && bash '$K/ft-team-switch.sh' status harness"; ck "⑨ team-switch git 밖 · --root 없음 → rc3 1줄" "$([ "$RC" = 3 ] && [ "$(grep -c . "$T/o")" = 1 ] && echo 0 || echo 1)"
echo "⑦⑨ $(secs "$t")"; t=$(now)
# 옛 판(호출자 옛 꼴 + 옛 ft20_root_of) — ⑧ 대조와 변이 M1 이 같이 쓴다
OLDF='ft20_root_of() {
  if [ -n "${FT_FT20_ROOT:-}" ]; then printf "%s" "$FT_FT20_ROOT"; return 0; fi
  local p="${1:-.}" r
  [ -f "$p" ] && p="$(dirname -- "$p")"
  while [ ! -e "$p" ]; do p="$(dirname -- "$p")"; done
  r="$(git -C "$p" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  printf "%s" "${r%/.git}"
}'
oldify() {  # $1 = kit 폴더 · $2 = lib 도 옛 판(1)/새 판(0)
  python3 - "$1" "$2" "$OLDF" <<'PY'
import re, sys, glob
d, lib, oldf = sys.argv[1:]
for p in glob.glob(d + "/ft-*.sh"):
    s = open(p, encoding="utf-8").read()
    s = re.sub(r'_ft20_root="\$\(ft20_root_of (.+?)\)" \|\| (?:exit|return) \$\?; (ft20_guard_\w+) "\$_ft20_root"', r'\2 "$(ft20_root_of \1 2>/dev/null)"', s)
    s = s.replace('if [ -n "$ROOT_ARG" ]; then ROOT="$ROOT_ARG"; else ROOT="$(ft20_root_of .)" || exit $?; fi', 'ROOT="${ROOT_ARG:-$(ft20_root_of . 2>/dev/null)}"')
    open(p, "w", encoding="utf-8").write(s)
if lib == "1":
    p = d + "/ft20-switch-lib.sh"; s = open(p, encoding="utf-8").read()
    s2 = re.sub(r'(?s)# r1909 .*?\nft20_root_of\(\) \{.*?\n\}\n', lambda m: oldf + "\n", s, count=1)
    if s2 == s: sys.exit(1)
    open(p, "w", encoding="utf-8").write(s2)
PY
}
# ⑧ 정상 같은 루트(FT_ROOT 없음 · FT_ROOT=G) → 옛 판과 rc·stdout·stderr 동일
mk "$T/old"; oldify "$T/old" 1 || ck "⑧ 옛 판 만들기" 1
same() {  # $1 = 이름 · $2 = env · $3 = 입구와 인자(kit 자리 = @K@)
  local a b c; clr; mark "$G" harness 1
  a="$(cd "$G" && env $2 bash -c "${3//@K@/$K}" 2>&1; echo "rc=$?")"; clr; mark "$G" harness 1
  b="$(cd "$G" && env $2 bash -c "${3//@K@/$T/old}" 2>&1; echo "rc=$?")"; b="${b//$T\/old/$K}"
  ck "⑧ $1 새 판 = 옛 판 ($(tail -1 <<<"$a"))" "$([ "$a" = "$b" ] && echo 0 || echo 1)"
}
for e in "" "FT_ROOT=$G"; do
  same "move ${e:-FT_ROOT 없음}" "$e X=1" "bash @K@/ft-index-move.sh $G/design/harness/indices/대기/c.md 진행 --seat x"
  same "retire ${e:-FT_ROOT 없음}" "$e X=1" "bash @K@/ft-seat-retire.sh 'byz-harness-master-pi#1' 'byz-harness-da-pi#2'"
  same "team-switch status ${e:-FT_ROOT 없음}" "$e X=1" "bash @K@/ft-team-switch.sh status harness"
done
echo "⑧ $(secs "$t")"; t=$(now)
# 변이 M1(호출자 옛 꼴 · lib 새 판) → ⑥ FAIL · M2(FT_ROOT 단계 삭제) → ② FAIL · 변이는 쓰기가 임시 루트에만 닿는 입구만(move·tick)
mk "$T/m1"; oldify "$T/m1" 0; m="$(cases6 "$T/m1" "move tick" | grep -c ' 1$')"; o="$(cases6 "$K" "move tick" | grep -c ' 1$')"
ck "M1 호출자 옛 꼴 → ⑥ FAIL(변이 FAIL $m/2 · 원본 FAIL $o/2)" "$([ "$m" = 2 ] && [ "$o" = 0 ] && echo 0 || echo 1)"
mk "$T/m2"; sed -i.bak 's/ f="${FT_ROOT:-}" / f="" /' "$T/m2/ft20-switch-lib.sh"
m="$(cases2 "$T/m2")"; o="$(cases2 "$K")"
ck "M2 FT_ROOT 단계 삭제 → ② FAIL(변이 $m · 원본 $o)" "$(! cmp -s "$T/m2/ft20-switch-lib.sh" "$K/ft20-switch-lib.sh" && [ "$m" = '② 1' ] && [ "$o" = '② 0' ] && echo 0 || echo 1)"
echo "변이 $(secs "$t") · RUN 1회차 $(secs "$t0") · 사례 $n"
[ "$fail" = 0 ] || { echo "FAIL 합계 $fail"; exit 1; }; echo "PASS 합계 $n"
