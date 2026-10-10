#!/usr/bin/env bash
# test_zombie_clean_tmux_prune.sh — zombie-clean.sh tmux_prune() 의 keep-last-2 순번·하한·세대 정렬 시험 (R75 · 판정 807).
# 가짜 tmux/pgrep/ps(PATH 앞 스텁) + 임시 HOME 만 쓴다 — 실 tmux 세션은 건드리지 않는다(tmux-prune --dry-run 의 `[dry] tmux kill` 줄 집합만 본다).
# 시험 대상은 ZC_SCRIPT 로 바꿀 수 있다(RED 확인용 · 기본 = 리포 추적본).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ZC="${ZC_SCRIPT:-$HERE/../../scripts/harness-install/zombie-clean/zombie-clean.sh}"
fail=0; pass=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$ZC" || { echo "FAIL bash -n $ZC"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAKE="$TMP/fakebin"; FIX="$TMP/fixture"; mkdir -p "$FAKE" "$TMP/home"

# 스텁 tmux — fixture 한 줄 = `이름 idle분 attached(0|1) [preserve] [server]`
cat > "$FAKE/tmux" <<'EOF'
#!/usr/bin/env bash
now=$(date +%s)
case "$1" in
  list-sessions)
    while read -r n idle att _; do [ -z "$n" ] && continue; echo "$n|$((now - idle*60))|$att"; done < "$FIXTURE" ;;
  show-options)
    n="${@: -2:1}"; n="${n#=}"; n="${n%:}"
    grep -E "^$n " "$FIXTURE" | grep -qw preserve && echo 1 ;;
  list-windows) : ;;
  list-panes)
    n="${@: -3:1}"
    grep -E "^$n " "$FIXTURE" | grep -qw server && echo 9001 ;;
  kill-session) echo "kill $*" >> "$TMP_KILLLOG" ;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\n[ "$1" = "-P" ] && [ "$2" = "9001" ] && { echo 9002; exit 0; }\nexec /usr/bin/pgrep "$@"\n' > "$FAKE/pgrep"
printf '#!/usr/bin/env bash\n[ "$4" = "9002" ] && { echo "uvicorn app:app"; exit 0; }\nexec /bin/ps "$@"\n' > "$FAKE/ps"
chmod +x "$FAKE/tmux" "$FAKE/pgrep" "$FAKE/ps"

# run <YELLOW|RED> <fixture 본문> [env 추가…] → `[dry] tmux kill` 이름 집합(정렬·공백구분) + 전체 출력은 $TMP/out
run() {
  local tier="$1" body="$2"; shift 2
  printf '%s\n' "$body" > "$FIX"
  local -a envs=(ZC_P_SWAP_RED=999999 ZC_P_JETS_RED=999999 ZC_P_COMP_RED=999999 ZC_P_SWAP_YEL=0)
  [ "$tier" = RED ] && envs=(ZC_P_SWAP_RED=0)
  env HOME="$TMP/home" PATH="$FAKE:$PATH" FIXTURE="$FIX" TMP_KILLLOG="$TMP/kill.log" \
      ZC_TMUX_IDLE_MIN=30 "${envs[@]}" "$@" bash "$ZC" tmux-prune --dry-run > "$TMP/out" 2>&1
  sed -n 's/^.*\[dry\] tmux kill \([^ ]*\) .*$/\1/p' "$TMP/out" | sort | tr '\n' ' ' | sed 's/ $//'
}
expect() { # expect <label> <기대 집합(공백구분·정렬)> <실제>
  [ "$3" = "$2" ] && ok "$1" || bad "$1 → 기대 [$2] · 실제 [$3]"
}

# T1 — attached 두 세대가 순번 1·2 를 차지 → 3번째 A#1 정리
expect "T1 attached 가 순번을 차지" "A#1" "$(run YELLOW 'A#3 10 1
A#2 20 1
A#1 500 0')"
# T2 — preserve 가 순번 1 → B#1 만 정리
expect "T2 preserve 가 순번을 차지" "B#1" "$(run YELLOW 'B#3 10 0 preserve
B#2 500 0
B#1 600 0')"
# T3 — 멤버 2 = keep → 유일 세대 보호
expect "T3 멤버=keep 보호" "" "$(run YELLOW 'C#2 500 0
C#1 600 0')"
# T4 — idle 가드
expect "T4 idle 가드" "" "$(run YELLOW 'D#3 10 1
D#2 20 1
D#1 10 0')"
# T5 — attached 가 3번째 → E#1 만 (현행·패치 같음)
expect "T5 attached 3번째" "E#1" "$(run YELLOW 'E#4 500 0
E#3 600 0
E#2 10 1
E#1 700 0')"
# T6 — 라이브 서버 pane 가드
expect "T6 라이브 서버 가드" "" "$(run YELLOW 'F#3 500 0
F#2 600 0
F#1 700 0 server')"
# T7 — RED 에서도 최신 keep 세대 보존 (유일 세대 보호 + ABANDON 회수 제거)
expect "T7 RED 최신 2세대 보존" "" "$(run RED 'G#2 400 0
G#1 500 0')"
# T7b — RED 에서 keep 밖은 회수 그대로 (keep 안 H#3·H#2 는 idle 100 < ABANDON)
expect "T7b RED keep 밖 회수" "H#1" "$(run RED 'H#3 100 0
H#2 200 0
H#1 400 0')"
# T8 — 세대 번호 정렬: 입력 시각은 I#1 이 최신(idle 500)이어도 최신 세대는 I#3
expect "T8 #N 내림차순 정렬" "I#1" "$(run YELLOW 'I#3 700 0
I#2 600 0
I#1 500 0')"
# T9 — ZC_TMUX_KEEP=1 은 2 로 올리고 그 사실을 출력
got="$(run YELLOW 'J#3 500 0
J#2 600 0
J#1 700 0' ZC_TMUX_KEEP=1)"
grep -q "keep 하한 2 적용" "$TMP/out" && shown=" (하한 적용 출력 있음)" || shown=" (출력에 'keep 하한 2 적용' 없음)"
case "$shown" in *없음*) bad "T9 KEEP=1 → 하한 2$shown · kill [$got]" ;; *) expect "T9 KEEP=1 → 하한 2" "J#1" "$got" ;; esac
# T10 — RED 에서 유일 세대(멤버 2) 보호
expect "T10 RED 유일 세대 보호" "" "$(run RED 'K#2 500 0
K#1 500 0')"

total=$((pass+fail))
echo "$pass/$total PASS"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
