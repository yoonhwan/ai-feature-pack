#!/usr/bin/env bash
# test_heavy_slot_bash32_r1338.sh — r1338 ft-heavy-slot-lib.sh 가 macOS /bin/bash 3.2 에서도 돈다(고정 fd: 쥔 자리 8 · 탐침 7)
#   해석기 2개(OLD=/bin/bash 3.2 · NEW=homebrew bash)로 같은 케이스를 돈다.
#   B1 lib source → hs_count_held = «0» rc0 / B2 hs_acquire t 0 → rc0·HS_SLOT=slot-1·뒤 줄 실행 · 다른 셸 hs_count_held = «1»
#   B3 자리 둘 쥔 채 셋째 hs_acquire t 0 → rc3 «판정 불가 — … 대기 0초 초과» · 셸 계속 / B4 hs_release 뒤 다른 셸 hs_count_held = «0» · 같은 셸 재획득 rc0
#   B5 ft-resource-sample.sh(FT_RES_ROOT 임시) → heavy.tsv 새 줄 둘째 칸 = 숫자 / B6 ft-scratch-repo.sh --sweep(임시 사본 2개) → 삭제 · swept= 끝 줄 · rc0
#   변이 1(hs_try 를 exec {HS_FD} 로) → OLD 의 B2 FAIL / 변이 2(hs_count_held 를 exec {fd} 로) → OLD 의 B1·B5 FAIL / 변이 3(hs_release 가 fd 8 을 안 닫음) → B4 FAIL
#   env: FT_R1338_LIB = 시험할 lib 경로(기본 ../bin/ft-heavy-slot-lib.sh · 기준판 확인용) · FT_R1338_OLD · FT_R1338_NEW = 해석기 경로
#   실 tmux·네트워크·Redis 0 · 자기 재호출 0 · 고정 sleep 0(표식 폴링) · 시험 1개 상한 70초
set -uo pipefail
[ -z "${FT_R1338_REENTRY:-}" ] || { echo "FAIL 재진입"; exit 1; }
export FT_R1338_REENTRY=1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; LIB0="${FT_R1338_LIB:-$BIN/ft-heavy-slot-lib.sh}"
OLD="${FT_R1338_OLD:-/bin/bash}"; NEW="${FT_R1338_NEW:-/opt/homebrew/bin/bash}"
[ -x "$OLD" ] && [ -x "$NEW" ] || { echo "FAIL 해석기 없음 OLD=$OLD NEW=$NEW"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/r1338.XXXXXX")"; fail=0; BAD=""; BG=(); T0=$SECONDS
clean(){ local p; for p in ${BG[@]+"${BG[@]}"}; do kill -9 "$p" 2>/dev/null || true; done; rm -rf "$T"; }
trap clean EXIT
bad(){ echo "FAIL $1" >&2; fail=$((fail+1)); BAD="$BAD $1"; }
waitfor(){ local i; for i in $(seq 1 200); do [ -e "$1" ] && return 0; command sleep 0.05; done; return 1; }
mkbin(){ # <이름> <lib> → bin 전체를 링크한 폴더 · lib 만 바꿔 끼움
  local d="$T/bin-$1" f; mkdir -p "$d"
  for f in "$BIN"/*; do ln -sf "$f" "$d/${f##*/}"; done
  rm -f "$d/ft-heavy-slot-lib.sh"; cp "$2" "$d/ft-heavy-slot-lib.sh"; printf '%s' "$d"; }
hold(){ # <해석기> <lib> <자리폴더> <이름> → 자리를 쥐고 뒤 줄(표식·HS_SLOT 기록)을 실행한 뒤 stop.<이름> 을 기다림
  local bi="$1" lib="$2" d="$3" n="$4"
  cat > "$T/h-$n.sh" <<EOF
export FT_HEAVY_DIR="$d"
. "$lib"
hs_acquire "$n" 0 >/dev/null || exit 1
printf '%s' "\$HS_SLOT" > "$T/slot.$n"
touch "$T/held.$n"
while [ ! -f "$T/stop.$n" ]; do command sleep 0.05; done
EOF
  rm -f "$T/held.$n" "$T/stop.$n" "$T/slot.$n"; "$bi" "$T/h-$n.sh" 2>/dev/null & BG+=($!); waitfor "$T/held.$n"; }
count(){ FT_HEAVY_DIR="$2" "$1" -c '. "$0"; hs_count_held; echo " rc=$?"' "$3" 2>&1; }
B1(){ local out; out="$(count "$1" "$T/$2/s1" "$3")"; [ "$out" = "0 rc=0" ] || { echo "  B1[$2] out=[$out]" >&2; return 1; }; }
B2(){ local d="$T/$2/s2" out; hold "$1" "$3" "$d" b2 || { echo "  B2[$2] 표식 없음(셸 종료?)" >&2; return 1; }
  [ "$(cat "$T/slot.b2")" = "slot-1" ] || { echo "  B2[$2] HS_SLOT=[$(cat "$T/slot.b2")]" >&2; touch "$T/stop.b2"; return 1; }
  out="$(count "$1" "$d" "$3")"; touch "$T/stop.b2"; [ "$out" = "1 rc=0" ] || { echo "  B2[$2] count=[$out]" >&2; return 1; }; }
B3(){ local d="$T/$2/s3" out; hold "$1" "$3" "$d" c1 && hold "$1" "$3" "$d" c2 || { touch "$T/stop.c1" "$T/stop.c2"; echo "  B3[$2] holder 실패" >&2; return 1; }
  out="$(FT_HEAVY_DIR="$d" FT_HEAVY_POLL_SEC=0.1 "$1" -c '. "$0"; hs_acquire t 0; echo "rc=$? cont"' "$3" 2>&1)"; touch "$T/stop.c1" "$T/stop.c2"
  printf '%s' "$out" | grep -q '판정 불가 — 무거운 git 자리 대기 [0-9]*초 초과' && printf '%s' "$out" | grep -q 'rc=3 cont' || { echo "  B3[$2] out=[$out]" >&2; return 1; }; }
B4(){ local d="$T/$2/s4" out
  out="$(FT_HEAVY_DIR="$d" B="$1" "$1" -c '. "$0"; hs_acquire a 0 >/dev/null; hs_release; c="$("$B" -c ". \"\$0\"; hs_count_held" "$0")"; hs_acquire b 0 >/dev/null; echo "after=$c re=$? fd=${HS_FD:-}"' "$3" 2>&1)"
  [ "$out" = "after=0 re=0 fd=8" ] || { echo "  B4[$2] out=[$out]" >&2; return 1; }; }
B5(){ local r="$T/$2/r5" out hv; mkdir -p "$r/.fable-team/state/heavy-slots"
  out="$(FT_RES_ROOT="$r" "$1" "$4/ft-resource-sample.sh" 2>&1)"; local rc=$?
  [ "$rc" = 0 ] || { echo "  B5[$2] sample rc=$rc out=[$out]" >&2; return 1; }
  hv="$(tail -n 1 "$r/.fable-team/state/heavy.tsv" 2>/dev/null | awk -F'\t' '$1~/^[0-9]+$/ && $2~/^[0-9]+$/ && $3~/^[0-9]+$/{print "ok"}')"
  [ "$hv" = ok ] || { echo "  B5[$2] heavy.tsv=[$(tail -n 1 "$r/.fable-team/state/heavy.tsv" 2>/dev/null | tr '\t' '|')]" >&2; return 1; }; }
B6(){ local S="$T/$2/s6" i out rc P ps=() sc="$4/ft-scratch-repo.sh" TSV
  mkdir -p "$S/src" "$S/R/.fable-team/state" "$S/scr" "$S/tmpd" "$S/bin"; TSV="$S/R/.fable-team/state/scratch-repos.tsv"
  git -C "$S/src" init -q; echo a > "$S/src/a.txt"; git -C "$S/src" add a.txt; git -C "$S/src" -c user.name=t -c user.email=t@t commit -q -m c1
  local SHA; SHA="$(git -C "$S/src" rev-parse HEAD)"
  printf '#!/bin/sh\n[ "$1" = list-sessions ] && printf "live-owner\\n"\nexit 0\n' > "$S/bin/tmux"; chmod 755 "$S/bin/tmux"
  date +%s > "$S/R/.fable-team/state/scratch-sweep.armed"
  for i in 1 2; do   # 사본 만들기는 NEW 로(기준판에서도 만들어져야 sweep 만 가름)
    P="$(env PATH="$S/bin:$PATH" FT_RES_ROOT="$S/R" FT_SCRATCH_DIR="$S/scr" TMPDIR="$S/tmpd" FT_SCRATCH_OWNER="gone-$i" FT_HEAVY_DIR="$S/R/.fable-team/state/heavy-slots" FT_HEAVY_WAIT_S=5 "$NEW" "$sc" "$SHA" --repo "$S/src" 2>&1)" || { echo "  B6[$2] 사본 만들기 실패 [$P]" >&2; return 1; }
    [ -d "$P" ] || { echo "  B6[$2] 사본 경로 아님 [$P]" >&2; return 1; }; ps+=("$P")
    awk -F'\t' -v p="$P" -v t="$(( $(date +%s) - 90000 ))" 'BEGIN{OFS="\t"} $1==p{$3=t} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
  done
  out="$(env PATH="$S/bin:$PATH" FT_RES_ROOT="$S/R" FT_SCRATCH_DIR="$S/scr" TMPDIR="$S/tmpd" FT_SCRATCH_OWNER=live-owner FT_HEAVY_DIR="$S/R/.fable-team/state/heavy-slots" FT_HEAVY_WAIT_S=5 "$1" "$sc" --sweep 2>&1)"; rc=$?
  printf '%s\n' "$out" > "$S/sweep.out"   # 출력은 파일로 남기고 화면엔 경로만(비밀 변수 환경 명령 출력 화면 금지 · 분류기 r1338)
  [ "$rc" = 0 ] || { echo "  B6[$2] sweep rc=$rc 출력=$S/sweep.out" >&2; return 1; }
  [ ! -d "${ps[0]}" ] && [ ! -d "${ps[1]}" ] || { echo "  B6[$2] 사본 남음" >&2; return 1; }
  grep -q '^swept=' "$S/sweep.out" || { echo "  B6[$2] 끝 줄 없음 출력=$S/sweep.out" >&2; return 1; }; }
# B 함수 인자: $1 해석기 $2 폴더이름 $3 lib $4 bin 폴더
STAGE(){ echo "단계 $1: $((SECONDS-T0))초"; }
LB="$(mkbin base "$LIB0")"
for tag in old new; do for c in B1 B2 B3 B4 B5 B6; do
  mkdir -p "$T/$tag-$c"; bi="$OLD"; [ "$tag" = new ] && bi="$NEW"
  "$c" "$bi" "$tag-$c" "$LB/ft-heavy-slot-lib.sh" "$LB" || bad "$c($tag)"
done; STAGE "$tag B1~B6"; done
mkvar(){ # <이름> <python 치환> → 변이 lib 의 bin 폴더
  local out="$T/lib-$1.sh"; python3 -I - "$LIB0" "$out" "$2" <<'PY' || return 1
import sys
s = open(sys.argv[1], encoding="utf-8").read()
ns = {"s": s}; exec(sys.argv[3], ns)
assert ns["s"] != s
open(sys.argv[2], "w", encoding="utf-8").write(ns["s"])
PY
  mkbin "$1" "$out" > /dev/null; }
runv(){ # <변이 이름> <bin 폴더> <케이스들> — OLD 로 돌려 «전부 FAIL» 이어야 정상
  local n="$1" bd="$2" c; shift 2
  for c in "$@"; do mkdir -p "$T/v-$n-$c"; if "$c" "$OLD" "v-$n-$c" "$bd/ft-heavy-slot-lib.sh" "$bd" 2>/dev/null; then bad "변이 $n — $c 통과"; else echo "변이 $n → $c FAIL(정상)"; fi; done; }
mkvar v1 's = s.replace("""  { exec 8>>"$f"; } 2>/dev/null || { unset HS_FD; return 3; }
  HS_FD=8""", """  { exec {HS_FD}>>"$f"; } 2>/dev/null || { unset HS_FD; return 3; }""")' && runv 1 "$T/bin-v1" B2
mkvar v2 's = s.replace("""    { exec 7>>"$f"; } 2>/dev/null || continue""", """    { exec {fd}>>"$f"; } 2>/dev/null || continue""")' && runv 2 "$T/bin-v2" B1 B5
mkvar v3 's = s.replace("""  exec 8>&-
  unset HS_FD HS_SLOT""", """  unset HS_FD HS_SLOT""")' && runv 3 "$T/bin-v3" B4
STAGE "변이"
[ -z "$BAD" ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail$BAD"; exit 1
