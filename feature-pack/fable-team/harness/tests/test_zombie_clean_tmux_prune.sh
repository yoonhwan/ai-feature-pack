#!/usr/bin/env bash
# test_zombie_clean_tmux_prune.sh — zombie-clean.sh tmux_prune() 의 keep-last-2 순번·하한·세대 정렬 시험 (R75 · 판정 807).
# 가짜 tmux/pgrep/ps(PATH 앞 스텁) + 임시 HOME 만 쓴다 — 실 tmux 세션은 건드리지 않는다(tmux-prune --dry-run 의 `[dry] tmux kill` 줄 집합만 본다).
# 시험 대상은 ZC_SCRIPT 로 바꿀 수 있다(RED 확인용 · 기본 = 리포 추적본).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ZC="${ZC_SCRIPT:-$HERE/../../harness/kit/zombie-clean/zombie-clean.sh}"
fail=0; pass=0
# FT_TEST_ONLY=<부분문자열> 이면 그 칸(CASE)만 돈다 — 변이 회차·재확인용(한 칸 ≈ 2초 · 하드 룰 22 «그 칸만»).
CASE="old"
in_case() { [ -z "${FT_TEST_ONLY:-}" ] && return 0; case "$CASE" in *"$FT_TEST_ONLY"*) return 0 ;; esac; return 1; }
ok()  { in_case || return 0; echo "PASS $1"; pass=$((pass+1)); }
bad() { in_case || return 0; echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$ZC" || { echo "FAIL bash -n $ZC"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAKE="$TMP/fakebin"; FIX="$TMP/fixture"; RECD="$TMP/rec"; mkdir -p "$FAKE" "$TMP/home" "$RECD" "$TMP/cwd"
ROSTR="$TMP/roster"; mkdir -p "$ROSTR/.fable-team"; printf '{}\n' > "$ROSTR/.fable-team/seats.json"   # 기본 = 현역 0 인 깨끗한 명부(시험 격리 · 실 명부를 읽지 않는다)

# 스텁 tmux — fixture 한 줄 = `이름 idle분(입력) attached(0|1) [preserve] [server] [out=출력유휴분]` (out= 없으면 window_activity 출력 0)
cat > "$FAKE/tmux" <<'EOF'
#!/usr/bin/env bash
now=$(date +%s)
case "$1" in
  list-sessions)
    while read -r n idle att _; do [ -z "$n" ] && continue; echo "$n|$((now - idle*60))|$att"; done < "$FIXTURE" ;;
  show-options)
    n="${@: -2:1}"; n="${n#=}"; n="${n%:}"
    grep -E "^$n " "$FIXTURE" | grep -qw preserve && echo 1 ;;
  list-windows)
    n="${3#=}"; o=$(grep -E "^$n " "$FIXTURE" | grep -oE 'out=[0-9]+' | head -1); o="${o#out=}"
    [ -n "$o" ] && echo "$((now - o*60))" ;;
  list-panes)
    n="${@: -3:1}"
    if grep -E "^$n " "$FIXTURE" | grep -qw server; then echo 9001; else echo 8000; fi ;;   # 8000 = 평범한 pane (자식 = 에이전트 pid 4242)
  display)   # R364: 결속 재비교(ft_seat_bind.py --expect)가 묻는 pane pid + 식별(<세션>:@window.%pane) · r1014 r2: jsonl 판정이 묻는 pane_current_path
    case "${5:-}" in
      '#{pane_current_path}'*) printf '%s\n' "${FIXCWD:-}" ;;
      '#{pane_pid}'*) n="${4#=}"; n="${n%:}"; if grep -E "^$n " "$FIXTURE" | grep -qw server; then pp=9001; else pp=8000; fi
                      printf '%s\t%s:@1.%%1\n' "$pp" "$n" ;;
    esac ;;
  kill-session) echo "kill $*" >> "$TMP_KILLLOG" ;;
  has-session) n="${3#=}"; grep -qE "^$n " "$FIXTURE" && exit 0; exit 1 ;;   # fixture 에 줄이 있으면 «살아 있는 세션»
  new-session|send-keys) echo "$*" >> "${TMP_CALLLOG:-/dev/null}"
    [ "$1" = send-keys ] && [ -n "${FAIL_SEND:-}" ] && case " $* " in *" $FAIL_SEND "*) exit 1 ;; esac ;;   # FAIL_SEND=-l|Enter → 그 send-keys 만 rc 1
esac
exit 0
EOF
cat > "$FAKE/pgrep" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-P" ]; then case "$2" in 9001) echo 9002; echo 4242; exit 0 ;; 8000) echo 4242; exit 0 ;; esac; fi
exec /usr/bin/pgrep "$@"
EOF
printf '#!/usr/bin/env bash\n[ "$2" = "lstart=" ] && { echo "Mon Jan  1 00:00:00 2001"; exit 0; }\n[ "$2" = "comm=" ] && { echo /u/.local/bin/claude; exit 0; }\n[ "$4" = "9002" ] && { echo "uvicorn app:app"; exit 0; }\n[ "$4" = "4242" ] && { echo "claude"; exit 0; }\nexec /bin/ps "$@"\n' > "$FAKE/ps"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE/tmuxc"   # reclaim_init 의 tmuxc save — 실 tmuxc 호출 0
chmod +x "$FAKE/tmux" "$FAKE/pgrep" "$FAKE/ps" "$FAKE/tmuxc"

# r1014 r2: jsonl 활동 판정용 가짜 projects 폴더 — fixture 줄에 `jsonl=<분>` 이 있으면 그 나이, 없으면 999분, `jsonl=none` 이면 파일 없음.
PROJ="$TMP/projects"; FIXCWD="$TMP/cwd"; SLUG="$(printf '%s' "$FIXCWD" | tr '/.' '--')"
mkjsonl() {   # <fixture 본문> — 이 시험의 슬러그 폴더를 새로 만들고 좌석별 jsonl 을 만든다
  rm -rf "$PROJ"; mkdir -p "$PROJ/$SLUG"
  local n rest jm i=0
  while read -r n rest; do
    [ -z "$n" ] && continue
    i=$((i+1)); case "$rest" in *jsonl=none*) continue ;; esac
    jm="$(printf '%s' "$rest" | grep -oE 'jsonl=[0-9]+' | head -1)"; jm="${jm#jsonl=}"; [ -n "$jm" ] || jm=999
    printf '{"type":"summary","agentName":"%s"}\n' "$n" > "$PROJ/$SLUG/s$i.jsonl"
    touch -t "$(date -v-${jm}M '+%Y%m%d%H%M')" "$PROJ/$SLUG/s$i.jsonl"   # macOS date: M=분(分) · m=월
  done <<< "$1"
}

# run <YELLOW|RED> <fixture 본문> [env 추가…] → `[dry] tmux kill` 이름 집합(정렬·공백구분) + 전체 출력은 $TMP/out
run() {
  in_case || { echo ""; return 0; }        # FT_TEST_ONLY 밖 칸은 본체를 부르지도 않는다(부하 0)
  local tier="$1" body="$2"; shift 2
  printf '%s\n' "$body" > "$FIX"
  mkjsonl "$body"
  local -a envs=(ZC_JETS_CMD=true ZC_P_SWAP_RED=999999 ZC_P_JETS_RED=999999 ZC_P_COMP_RED=999999 ZC_P_SWAP_YEL=0)
  [ "$tier" = RED ] && envs=(ZC_JETS_CMD=true ZC_P_SWAP_RED=0)
  env HOME="$TMP/home" PATH="$FAKE:$PATH" FIXTURE="$FIX" FIXCWD="$FIXCWD" ZC_CLAUDE_PROJECTS="$PROJ" TMP_KILLLOG="$TMP/kill.log" \
      ZC_TMUX_IDLE_MIN=30 ZC_RESUME_DIR="$RECD" ZC_ROSTER_ROOT="$ROSTR" "${envs[@]}" "$@" bash "$ZC" tmux-prune --dry-run > "$TMP/out" 2>&1
  sed -n 's/^.*\[dry\] tmux kill \([^ ]*\) .*$/\1/p' "$TMP/out" | sort | tr '\n' ' ' | sed 's/ $//'
}
expect() { # expect <label> <기대 집합(공백구분·정렬)> <실제>
  in_case || return 0
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

# T11 — ⓐ keep 밖 세대: 입력 idle ≥ 임계 ∧ 출력 idle 작음(옛 좌석 크론 출력) → kill 후보
expect "T11 keep 밖 출력 무시(입력만)" "L#1" "$(run YELLOW 'L#3 10 0
L#2 20 0
L#1 500 0 out=10')"
# T12 — ⓑ active V65 task(preserve): 출력 포함 idle < ABANDON(360) → 지금처럼 보존
expect "T12 preserve 는 출력 포함 idle 유지" "" "$(run YELLOW 'M#3 10 0
M#2 20 0
M#1 500 0 preserve out=10')"
# T12b — preserve 라도 출력까지 ABANDON 넘게 조용하면 해제 → keep 밖이라 입력 idle 로 회수
expect "T12b preserve ABANDON 넘으면 회수" "N#1" "$(run YELLOW 'N#3 10 0
N#2 20 0
N#1 500 0 preserve out=400')"
# T13 — ⓒ keep 안 세대(출력만 조용해도 idle 안 봄)·attached·라이브 서버 보호 불변
expect "T13 keep 안 보호 불변" "" "$(run YELLOW 'O#3 500 0 out=5
O#2 600 0 out=5
O#1 700 0 server out=10')"
expect "T13b attached 보호 불변" "" "$(run YELLOW 'P#3 10 0
P#2 20 0
P#1 500 1 out=10')"
# T14 — 입력 idle 이 임계 미만이면 출력이 오래돼도 활성 보호(출력이 더 최근일 때만 덮던 기존 방향성 보존)
expect "T14 입력 최근이면 보호" "" "$(run YELLOW 'S#3 10 0
S#2 20 0
S#1 10 0 out=500')"

# ── 판정 1344 — 직전 세대(순번 2)는 «검증된 재개 기록»이 있을 때만 닫는다 ─────────────────────────
mkrec() { # <세션명> [name|engine|jsonl|jsonlname|cwd|model|pid: 그 칸만 어긋나게] — pid 기본 4242 = 스텁 pane 8000 의 자식
  local n="$1" bad="${2:-}" u nm="$1" en=claude cw="$TMP/cwd" md="m1" jl pd=4242
  u="u-$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"; jl="$TMP/cwd/$u.jsonl"; : > "$jl"; : > "$TMP/cwd/other.jsonl"
  case "$bad" in name) nm=other ;; engine) en=codex ;; jsonl) jl="$TMP/cwd/none.jsonl" ;; jsonlname) jl="$TMP/cwd/other.jsonl" ;; cwd) cw="$TMP/nodir" ;; model) md="" ;; pid) pd=7777 ;; esac
  printf '{"name":"%s","engine":"%s","pid":%s,"uuid":"%s","jsonl":"%s","cwd":"%s","model":"%s","retired_by":"x","at":"t","binding":{"session":"%s","window":"@1","pane":"%%1","pid":%s,"lstart":"Mon Jan  1 00:00:00 2001","source":"tmux-col"}}' "$nm" "$en" "$pd" "$u" "$jl" "$cw" "$md" "$n" "$pd" > "$RECD/$n.json"
}
# T15 — ① 멤버 2개 계보(J#2 현역·J#1 직전 세대) · 직전 세대에 검증된 기록 · idle 충분 → 직전 세대만 kill (DA② H1 반례)
rm -f "$RECD"/*; mkrec 'RA#1'
expect "T15 두 멤버 계보 · 기록 있는 직전 세대 kill" "RA#1" "$(run YELLOW 'RA#2 500 0
RA#1 600 0')"
# T16 — ② 같은데 기록 없음 → 둘 다 보존 + 출력
rm -f "$RECD"/*
expect "T16 기록 없으면 둘 다 보존" "" "$(run YELLOW 'RB#2 500 0
RB#1 600 0')"
grep -q "tmux keep RB#1 (재개 기록 없음 — 직전 세대 보존)" "$TMP/out" && ok "T16b 기록 없음 출력(#0 RULE)" || bad "T16b 출력에 '재개 기록 없음 — 직전 세대 보존' 없음"
# T17 — ③ 3세대 · 순번 2 기록 있음 → 순번 2·3 kill, 순번 1 보존
rm -f "$RECD"/*; mkrec 'RC#2'
expect "T17 순번 2 기록 → 2·3 kill" "RC#1 RC#2" "$(run YELLOW 'RC#3 500 0
RC#2 600 0
RC#1 700 0')"
# T18 — ④ 기록 불일치(칸마다) → 보존 + 사유 출력
for bad in name engine jsonl jsonlname cwd model; do
  rm -f "$RECD"/*; mkrec 'RD#1' "$bad"; want="$bad"; [ "$bad" = jsonlname ] && want=jsonl
  expect "T18 불일치($bad) 보존" "" "$(run YELLOW 'RD#2 500 0
RD#1 600 0')"
  grep -q "tmux keep RD#1 (재개 기록 불일치: $want)" "$TMP/out" && ok "T18 불일치($bad) 사유 출력" || bad "T18 불일치($bad) 사유 출력 없음: $(grep 'RD#1' "$TMP/out")"
done
# T19 — ⑤ 기록이 있어도 보호선은 순번 2 에서 그대로: attached · 라이브 서버 · active V65 task · idle 미달
rm -f "$RECD"/*; mkrec 'RE#1'
expect "T19a attached 보호" "" "$(run YELLOW 'RE#2 500 0
RE#1 600 1')"
expect "T19b 라이브 서버 보호" "" "$(run YELLOW 'RE#2 500 0
RE#1 600 0 server')"
expect "T19c active V65 task 보호" "" "$(run YELLOW 'RE#2 500 0
RE#1 300 0 preserve')"
expect "T19d idle 미달 보호" "" "$(run YELLOW 'RE#2 500 0
RE#1 10 0')"
# T20 — ⑥ KEEP=4 · 5세대 전부 기록 · 보호 없음 → 순번 2(RF#4)·순번 5(RF#1) kill · 순번 1·3·4 보존
rm -f "$RECD"/*; for g in 5 4 3 2 1; do mkrec "RF#$g"; done
expect "T20 KEEP=4 순번 2·5 만 kill" "RF#1 RF#4" "$(run YELLOW 'RF#5 500 0
RF#4 600 0
RF#3 600 0
RF#2 600 0
RF#1 700 0' ZC_TMUX_KEEP=4)"
# T21 — ⑦ 멤버 1개 계보는 기록이 있어도 불변
rm -f "$RECD"/*; mkrec 'RG#1'
expect "T21 멤버 1개 계보 불변" "" "$(run YELLOW 'RG#1 700 0')"
# T22 — ⑧ ZC_TMUX_KEEP=1 은 2 로 올리고(T9) 순번 2 기록 규칙을 그대로 탄다
rm -f "$RECD"/*; mkrec 'RH#2'
expect "T22 KEEP=1 → 하한 2 · 순번 2 기록 → 2·3 kill" "RH#1 RH#2" "$(run YELLOW 'RH#3 500 0
RH#2 600 0
RH#1 700 0' ZC_TMUX_KEEP=1)"

# T23 — 대장 restore 열: 검증된 기록이 있는 행은 `resume`, 없는 행은 기존 `restore` (실 kill 경로 = 스텁 tmux · tmuxc 스텁)
rm -f "$RECD"/*; mkrec 'RI#2'; mkdir -p "$TMP/home/.claude/logs"; rm -f "$TMP/home/.claude/logs"/zc-reclaim-*.tsv
printf '%s\n' 'RI#3 500 0
RI#2 600 0
RI#1 700 0' > "$FIX"
mkjsonl "$(cat "$FIX")"   # r1014 r2: jsonl 판정도 같은 가짜 세계(기본 999분 = 활동 없음 → 기존 kill 그대로)
env HOME="$TMP/home" PATH="$FAKE:$PATH" FIXTURE="$FIX" FIXCWD="$FIXCWD" ZC_CLAUDE_PROJECTS="$PROJ" ZC_ROSTER_ROOT="$ROSTR" TMP_KILLLOG="$TMP/kill.log" ZC_TMUX_IDLE_MIN=30 ZC_RESUME_DIR="$RECD" \
    ZC_JETS_CMD=true ZC_P_SWAP_RED=999999 ZC_P_JETS_RED=999999 ZC_P_COMP_RED=999999 ZC_P_SWAP_YEL=0 bash "$ZC" tmux-prune > "$TMP/out" 2>&1
LED="$(ls "$TMP/home/.claude/logs"/zc-reclaim-*.tsv 2>/dev/null | head -1)"
expect "T23a 대장 RI#2 restore 열 = resume" "zombie-clean.sh resume 'RI#2'" "$(awk -F'\t' '$2=="RI#2"{print $7}' "$LED" 2>/dev/null)"
expect "T23b 대장 RI#1 restore 열 = 기존 restore" "zombie-clean.sh restore RI#1" "$(awk -F'\t' '$2=="RI#1"{print $7}' "$LED" 2>/dev/null)"

# T24 — resume 명령: 검증 통과 → new-session cwd + 헤드룸 래퍼 --resume <uuid> --model (send-keys -l 와 Enter 별도 · R524) · 실패·살아 있음 rc 1 · 호출 0
mkdir -p "$TMP/home/.headroom"; printf '#!/bin/bash\nexit 0\n' > "$TMP/home/.headroom/claude-hr.sh"; chmod +x "$TMP/home/.headroom/claude-hr.sh"
resume() { local fx="$1"; shift; : > "$TMP/calls"; printf '%s\n' "$fx" > "$FIX"
  env HOME="$TMP/home" PATH="$FAKE:$PATH" FIXTURE="$FIX" TMP_CALLLOG="$TMP/calls" TMP_KILLLOG="$TMP/kill.log" ZC_RESUME_DIR="$RECD" bash "$ZC" resume "$@" > "$TMP/rout" 2>&1; }
rm -f "$RECD"/*; mkrec 'RJ#1'
resume '' 'RJ#1'; rc=$?
expect "T24a resume 검증 통과 rc 0" "0" "$rc"
expect "T24b new-session -d -s 이름 -c cwd (첫 호출)" "new-session -d -s RJ#1 -c $TMP/cwd" "$(sed -n 1p "$TMP/calls")"
expect "T24c 래퍼 --resume <uuid> --model (send-keys -l)" "send-keys -t =RJ#1: -l $TMP/home/.headroom/claude-hr.sh --dangerously-skip-permissions --resume u-RJ-1 --model 'm1'" "$(sed -n 2p "$TMP/calls")"
expect "T24d Enter 는 별도 호출" "send-keys -t =RJ#1: Enter" "$(sed -n 3p "$TMP/calls")"
resume '' 'RJ#1' --dry-run; rc=$?
expect "T24e --dry-run rc 0 · 호출 0" "0 0" "$rc $(wc -l < "$TMP/calls" | tr -d ' ')"
grep -q '^\[dry\]' "$TMP/rout" && ok "T24e2 --dry-run 출력" || bad "T24e2 [dry] 출력 없음"
resume 'RJ#1 500 0' 'RJ#1'; rc=$?
expect "T24f 이미 살아 있음 rc 1 · 호출 0" "1 0" "$rc $(wc -l < "$TMP/calls" | tr -d ' ')"
resume '' 'RK#1'; rc=$?
expect "T24g 기록 없음 rc 1 · 호출 0" "1 0" "$rc $(wc -l < "$TMP/calls" | tr -d ' ')"
for bad in name engine jsonl cwd model; do
  rm -f "$RECD"/*; mkrec 'RL#1' "$bad"; resume '' 'RL#1'; rc=$?
  expect "T24h 불일치($bad) rc 1 · 호출 0" "1 0" "$rc $(wc -l < "$TMP/calls" | tr -d ' ')"
done
resume ''; rc=$?
expect "T24i 인자 없음 rc 1" "1" "$rc"

# T25 — H1(DA⑥): 무효화된 옛 기록(<이름>.json.stale-*)은 닫기 근거가 아니다 — 후보 0 + «재개 기록 없음» 출력
rm -f "$RECD"/*; mkrec 'RM#1'; mv "$RECD/RM#1.json" "$RECD/RM#1.json.stale-20261013000000"
expect "T25 stale 기록은 근거 아님" "" "$(run YELLOW 'RM#2 500 0
RM#1 600 0')"
grep -q "tmux keep RM#1 (재개 기록 없음" "$TMP/out" && ok "T25b 재개 기록 없음 출력" || bad "T25b 출력 없음"
# T26 — H2(DA⑥): send-keys 실패는 성공으로 보고하지 않는다 · -l 실패면 Enter 0 · 열린 세션은 자동 kill 0 + 안내
rm -f "$RECD"/*; mkrec 'RN#1'; : > "$TMP/kill.log"
FAIL_SEND=-l resume '' 'RN#1'; rc=$?
expect "T26a -l 실패 rc 1 · new-session·send-keys -l 2호출(Enter 0)" "1 2" "$rc $(wc -l < "$TMP/calls" | tr -d ' ')"
grep -q '✅' "$TMP/rout" && bad "T26a ✅ 가 출력됨" || ok "T26a ✅ 0"
grep -q "세션 RN#1 열린 채 — 확인 뒤 닫기" "$TMP/rout" && ok "T26a 열린 세션 안내" || bad "T26a 안내 없음: $(cat "$TMP/rout")"
FAIL_SEND=Enter resume '' 'RN#1'; rc=$?
expect "T26b Enter 실패 rc 1 · 3호출" "1 3" "$rc $(wc -l < "$TMP/calls" | tr -d ' ')"
grep -q '✅' "$TMP/rout" && bad "T26b ✅ 가 출력됨" || ok "T26b ✅ 0"
grep -q "세션 RN#1 열린 채 — 확인 뒤 닫기" "$TMP/rout" && ok "T26b 열린 세션 안내" || bad "T26b 안내 없음"
grep -q '^kill' "$TMP/kill.log" 2>/dev/null && bad "T26 자동 kill 발생" || ok "T26 자동 kill 0"

# T27 — 잔여 H1(DA⑥ r2): 무효화 I/O 실패로 옛 기록이 남은 경우(기록 pid ≠ 지금 pane 자식 pid) → 보존 + «불일치: pid». pid 일치(T15)는 기존대로 후보.
rm -f "$RECD"/*; mkrec 'RO#1' pid
expect "T27a 기록 pid ≠ pane 자식 pid → 후보 0" "" "$(run YELLOW 'RO#2 500 0
RO#1 600 0')"
grep -q "tmux keep RO#1 (재개 기록 불일치: pid)" "$TMP/out" && ok "T27a 사유 출력(pid)" || bad "T27a 사유 출력 없음: $(grep 'RO#1' "$TMP/out")"
rm -f "$RECD"/*; mkrec 'RO#1'
expect "T27b 기록 pid 일치 → 후보(기존대로)" "RO#1" "$(run YELLOW 'RO#2 500 0
RO#1 600 0')"
# T27c — resume 경로(세션이 죽은 뒤)는 pid 검사 없음: pid 가 어긋난 기록도 재개는 통과
rm -f "$RECD"/*; mkrec 'RP#1' pid; resume '' 'RP#1'; rc=$?
expect "T27c resume 은 pid 검사 0" "0" "$rc"

# ── r1014 · 명부 현역 역할 좌석 보호 (2026-10-27 · 실사건 10-27 13:39 arch 3석 kill) ──────────────────
# 가짜 명부(ZC_ROSTER_ROOT = $ROSTR · mktemp) + 가짜 tmux 만 쓴다 — 실 명부·실 세션은 읽지도 건드리지도 않는다.
mkroster() { # <디렉토리 이름> <seats 파일에 쓸 JSON 본문> [추가 파일 이름:본문 …] — .fable-team/ 아래에 쓴다
  local d="$TMP/$1"; shift; mkdir -p "$d/.fable-team"
  printf '%s\n' "$1" > "$d/.fable-team/seats.json"; shift
  local f; for f in "$@"; do printf '%s\n' "${f#*:}" > "$d/.fable-team/${f%%:*}"; done
  echo "$d"
}
CASE="ⓐ"
# ⓐ 계보 3세대 · 현역(_arch) = 순번 3 · idle 999 → keep 1줄 · kill 0 (순번·idle 무관)
RA="$(mkroster ra '{"_arch": "ZA#1"}')"
rm -f "$RECD"/*
expect "ⓐ 현역 순번 3 · idle 999 → kill 0" "" "$(run YELLOW 'ZA#3 10 0
ZA#2 20 0
ZA#1 999 0' ZC_ROSTER_ROOT="$RA")"
grep -q 'tmux keep ZA#1 (명부 현역 역할)' "$TMP/out" && ok "ⓐ «명부 현역 역할» keep 줄 1" || bad "ⓐ keep 줄 없음: $(grep 'ZA#1' "$TMP/out")"
CASE="ⓑ"
# ⓑ 현역 = 순번 2 · 재개 기록 검증됨(기존엔 여기서 kill) → 현역 우선 keep
RB="$(mkroster rb '{"_sets": {"set1": {"arch": "ZB#1", "da": "ZB-da#9"}}}')"
rm -f "$RECD"/*; mkrec 'ZB#1'
expect "ⓑ 현역 순번 2 · 재개 기록 검증됨 → 현역 우선 keep" "" "$(run YELLOW 'ZB#2 500 0
ZB#1 600 0' ZC_ROSTER_ROOT="$RB")"
grep -q 'tmux keep ZB#1 (명부 현역 역할)' "$TMP/out" && ok "ⓑ 현역 우선 keep 줄" || bad "ⓑ keep 줄 없음: $(grep 'ZB#1' "$TMP/out")"
CASE="ⓒ"
# ⓒ 은퇴(_closed) 순번 3 · idle 999 → 기존 규칙대로 kill (회귀 0)
RC1="$(mkroster rc '{"_sets": {"set1": {"arch": "ZC#1", "_closed": "2026-10-27 13:5x 은퇴"}}}')"
rm -f "$RECD"/*
expect "ⓒ 은퇴(_closed) 는 보호 안 함" "ZC#1" "$(run YELLOW 'ZC#3 10 0
ZC#2 20 0
ZC#1 999 0' ZC_ROSTER_ROOT="$RC1")"
grep -q 'tmux keep ZC#1' "$TMP/out" && bad "ⓒ 은퇴 좌석에 keep 줄" || ok "ⓒ 은퇴 좌석 keep 줄 0"
CASE="ⓓ"
# ⓓ 명부 JSON 깨짐 → 판정 불가 1줄 · 그 계보 kill 0 · 다른 계보(무관 명부) 영향 0
RD="$(mkroster rd '{}' 'seats-harness.json:{"_arch": byz-harness-arch-claude#1,,,')"
rm -f "$RECD"/*
expect "ⓓ 깨진 명부 계보 kill 0 · 무관 계보는 기존대로" "byz-ops-nano-x#1" "$(run YELLOW 'byz-harness-arch-claude#3 10 0
byz-harness-arch-claude#2 20 0
byz-harness-arch-claude#1 999 0
byz-ops-nano-x#3 10 0
byz-ops-nano-x#2 20 0
byz-ops-nano-x#1 999 0' ZC_ROSTER_ROOT="$RD")"
grep -q '명부 판정 불가: seats-harness.json' "$TMP/out" && ok "ⓓ 판정 불가 1줄" || bad "ⓓ 판정 불가 줄 없음: $(cat "$TMP/out")"
expect "ⓓ 판정 불가 줄 1개(계보당 1줄)" "1" "$(grep -c '명부 판정 불가' "$TMP/out")"
CASE="ⓔ"
# ⓔ 두 경로 한 집합 — 같은 명부 좌석을 memory reclaim 표는 HIL, tmux-prune 은 keep
#    (reclaim 은 명부 행 role 로 이미 보호 · 코드 수정 0 · 여기서 «같은 명부» 로 두 경로를 한 묶음에 본다)
RE="$(mkroster re '{}' 'seats-t.json:{"_arch": "byz-t-arch-claude#1", "byz-t-arch-claude#1": {"role": "arch", "agent": "claude"}, "_sets": {"s": {"arch": "byz-t-nano-s#1"}}}')"
rm -f "$RECD"/*
expect "ⓔ tmux-prune: 같은 명부 현역 keep" "" "$(run YELLOW 'byz-t-arch-claude#3 10 0
byz-t-arch-claude#2 20 0
byz-t-arch-claude#1 999 0' ZC_ROSTER_ROOT="$RE")"
expect "ⓔ R5 tmux-prune: _sets 현역 keep" "" "$(run YELLOW 'byz-t-nano-s#3 10 0
byz-t-nano-s#2 200 0
byz-t-nano-s#1 999 0' ZC_ROSTER_ROOT="$RE")"
CASE="ⓕ"
# ⓕ keep 밖 · 비현역 · jsonl 활동 → keep + 「jsonl 활동」 줄 / jsonl 999분 전 → 기존대로 kill / jsonl 없음 → 판정 불가 1줄 · kill 0
rm -f "$RECD"/*
expect "ⓕ jsonl 1분 전 = 일하는 좌석 keep" "" "$(run YELLOW 'ZF#3 10 0
ZF#2 200 0
ZF#1 300 0 jsonl=1')"
grep -qE 'tmux keep ZF#1 \(jsonl 활동 [12]분 전\)' "$TMP/out" && ok "ⓕ 「jsonl 활동 n분 전」 줄(1~2분 — date 분 단위 절삭)" || bad "ⓕ jsonl 활동 줄 없음: $(grep 'ZF#1' "$TMP/out")"
expect "ⓕ jsonl 999분 전 = 기존대로 kill" "ZF#1" "$(run YELLOW 'ZF#3 10 0
ZF#2 200 0
ZF#1 300 0 jsonl=999')"
expect "ⓕ jsonl 없음 = 판정 불가 · kill 0" "" "$(run YELLOW 'ZF#3 10 0
ZF#2 200 0
ZF#1 300 0 jsonl=none')"
grep -q 'tmux keep ZF#1 (판정 불가' "$TMP/out" && ok "ⓕ 판정 불가 1줄" || bad "ⓕ 판정 불가 줄 없음: $(grep 'ZF#1' "$TMP/out")"
CASE="ⓖ"
# ⓖ 명부 행 role=stop-ready (또는 _closed) → jsonl 판정 건너뜀 · 입력 idle 규칙 그대로 kill
RG="$(mkroster rg '{"ZG#1": {"role": "stop-ready"}}')"
expect "ⓖ stop-ready 는 jsonl 판정 건너뜀 → kill" "ZG#1" "$(run YELLOW 'ZG#3 10 0
ZG#2 200 0
ZG#1 300 0 jsonl=1' ZC_ROSTER_ROOT="$RG")"
RG2="$(mkroster rg2 '{"ZG9#1": {"role": "arch", "_closed": "2026-10-27 02:38 은퇴"}}')"
expect "ⓖ_closed 좌석도 jsonl 판정 건너뜀 → kill" "ZG9#1" "$(run YELLOW 'ZG9#3 10 0
ZG9#2 200 0
ZG9#1 300 0 jsonl=1' ZC_ROSTER_ROOT="$RG2")"

# ── r3 고침 4 (DA⑥ r1 HOLD 동작 4) — R3 명부 루트 없음 · R4 은퇴 행을 가리키는 역할 칸 · R7 닫힌 세트 좌석 ──
CASE="R3"
# R3: 루트(ZC_ROSTER_ROOT·FT_RES_ROOT·cwd·$HOME 기본값)가 전부 없는 세계 → 판정 불가 1줄 · 그 sweep kill 0
NOROOT="$TMP/noroot"; mkdir -p "$NOROOT"
printf '%s\n' 'ZR#3 10 0
ZR#2 200 0
ZR#1 999 0' > "$FIX"
mkjsonl "$(cat "$FIX")"
( cd "$NOROOT" && env -u ZC_ROSTER_ROOT -u FT_RES_ROOT HOME="$TMP/home" PATH="$FAKE:$PATH" FIXTURE="$FIX" FIXCWD="$FIXCWD" \
    ZC_CLAUDE_PROJECTS="$PROJ" TMP_KILLLOG="$TMP/kill.log" ZC_TMUX_IDLE_MIN=30 ZC_RESUME_DIR="$RECD" \
    ZC_JETS_CMD=true ZC_P_SWAP_RED=999999 ZC_P_JETS_RED=999999 ZC_P_COMP_RED=999999 ZC_P_SWAP_YEL=0 bash "$ZC" tmux-prune --dry-run > "$TMP/out3" 2>&1 )
expect "R3 명부 루트 없음 → kill 0" "" "$(sed -n 's/^.*\[dry\] tmux kill \([^ ]*\) .*$/\1/p' "$TMP/out3" | sort | tr '\n' ' ' | sed 's/ $//')"
grep -q '명부 판정 불가: 명부 루트 없음' "$TMP/out3" && ok "R3 판정 불가 1줄(루트 없음)" || bad "R3 판정 불가 줄 없음: $(cat "$TMP/out3")"
CASE="R4"
# R4: `_arch` 가 은퇴(_closed) 행을 가리킨다 → 현역 아님 · 기존 회수 규칙
RR4="$(mkroster rr4 '{"_arch": "CL#1", "CL#1": {"role": "arch", "_closed": "2026-10-27 02:38 은퇴"}}')"
rm -f "$RECD"/*
expect "R4 은퇴 행을 가리키는 역할 칸 = 현역 아님" "CL#1" "$(run YELLOW 'CL#3 10 0
CL#2 200 0
CL#1 999 0' ZC_ROSTER_ROOT="$RR4")"
grep -q 'tmux keep CL#1 (명부 현역 역할)' "$TMP/out" && bad "R4 은퇴 좌석에 현역 keep 줄" || ok "R4 현역 keep 줄 0"
CASE="R7"
# R7: 닫힌 세트(_closed) 안 좌석은 jsonl 판정을 건너뛴다 → 입력 idle 규칙 그대로 kill
RR7="$(mkroster rr7 '{"_sets": {"s": {"arch": "CS#1", "_closed": "retired"}}}')"
expect "R7 닫힌 세트 좌석은 jsonl 건너뜀 → kill" "CS#1" "$(run YELLOW 'CS#3 10 0
CS#2 200 0
CS#1 300 0 jsonl=1' ZC_ROSTER_ROOT="$RR7")"

RPATH="$HERE/../bin/ft-resource-reclaim.sh"
if [ -f "$HERE/lib/fake_reclaim_world.sh" ] && [ -f "$RPATH" ]; then
  T="$TMP/rw"; BIN="$HERE/../bin"; mkdir -p "$T"; . "$HERE/lib/fake_reclaim_world.sh"
  setup
  mkseat "byz-t-arch-claude#1" 999 0 95001
  mkseat "byz-t-nano-s#1" 999 0 95002          # r3 R5: _sets 안에서만 현역인 좌석(최상위 문자열 값 아님)
  python3 - "$ST/seats.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["byz-t-arch-claude#1"] = {"role": "arch", "agent": "claude"}
d["_arch"] = "byz-t-arch-claude#1"
d["_sets"] = {"s": {"arch": "byz-t-nano-s#1", "note": "세트 1"}}
json.dump(d, open(p, "w"), ensure_ascii=False)
PY
  export FT_ALLOW_TRACKED_BIN=1; unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY   # 추적 사본을 직접 부른다(real test_resource_reclaim.sh 와 같은 규율)
  rout="$(run "$RPATH" --dry-run --caller byz-t-master-claude#1 --need 1)"
  if printf '%s\n' "$rout" | grep -qF -- 'byz-t-arch-claude#1 |'; then
    # 표에 올랐다면 반드시 «승인 범위 밖»(HIL)이다 — 닫는 후보(WOULD-CLOSE/kill)로는 절대 안 나온다
    if printf '%s\n' "$rout" | grep -F -- 'byz-t-arch-claude#1 |' | grep -qF 'HIL(승인 범위 밖'; then
      ok "ⓔ reclaim 표 = 현역 HIL(한 집합)"
    else
      bad "ⓔ reclaim 표에 현역이 HIL 아닌 행: $(printf '%s\n' "$rout" | grep -F 'byz-t-arch' | head -2)"
    fi
  else
    ok "ⓔ reclaim 은 현역을 후보표에 안 올림(_* 상위 오케 보호 — 한 집합)"
  fi
  expect "ⓔ reclaim 은 그 좌석 kill 0" "" "$(cat "$ST/kill.log" 2>/dev/null | tr '\n' ' ')"
  if printf '%s\n' "$rout" | grep -F -- 'byz-t-nano-s#1 |' | grep -q 'WOULD-CLOSE'; then
    bad "ⓔ R5 _sets 현역을 reclaim 이 닫으려 함: $(printf '%s\n' "$rout" | grep -F 'byz-t-nano-s#1')"
  else
    ok "ⓔ R5 _sets 현역 = reclaim 도 보호(한 집합)"
  fi
else
  bad "ⓔ reclaim 시험 재료 없음($HERE/lib/fake_reclaim_world.sh)"
fi

total=$((pass+fail))
echo "$pass/$total PASS"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
