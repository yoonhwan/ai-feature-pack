#!/usr/bin/env bash
# test_tick_promote_line_r1467.sh — r1467: 팀 틱이 팀장에게 «승격/폐기 판단» 1줄을 묻고, resolve 가 그 판단을 파일로 남기고, 일일 평가가 그 파일로 기계 판정한다.
#   T1 후보 학습 2·폐기 1 · 오늘 resolved 0 → 팀 master 발사 줄 끝에 [승격/폐기 판단] 1줄(N·M·파일·resolve 꼴)
#   T2 후보 0 · 오늘 그 팀 판단 있음 · 메인 틱(FT_TICK_TEAM 없음) → 발사 줄 바이트 불변(다른 팀 줄은 막지 않는다)
#   T3 LATEST 없음·깨짐 → stderr «판정 불가» 1줄(같은 원인 연속은 0) · 줄 0 · 바퀴 계속
#   T4 ft-lessons resolve 1회 → resolved-<오늘>.jsonl 1줄(ts·team·seat·id·verdict·reason) · 기존 결과(keep=directive+pin · drop=아카이브) 불변
#   T5 ft_eval_daily 실측 = resolved promote ≥1·discard ≥1 → «통과» · 아니면 «고칠 것 후보»
# 쓰기는 mktemp 안만 — 실 틱·실 pane·실 lessons 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TICK="$HERE/../bin/ft-tick.sh"
KBIN="$HERE/../kit/fable-team/bin"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TODAY="$(date +%Y%m%d)"
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 (없음 [$3] in [$(printf '%s' "$2" | tr '\n' ' ' | cut -c1-160)])";; esac; }

# ── T1~T3: ft-tick.sh 의 r1467 블록 + fire_seats 를 떼어 돌린다(fire = 발사 줄 기록만 · 가짜 tmux 0 필요) ──
BLOCK="$(sed -n '/^# r1467 promote\/discard line/,/^# end r1467 promote\/discard line/p' "$TICK")"
FS="$(sed -n '/^fire_seats() {/,/^}/p' "$TICK")"
MSG='[cron-tick · 뉴스] fixture'
# run <케이스> [FT_TICK_TEAM] → $TMP/<케이스>.sent(발사 줄) · .err(stderr) · rc 출력
run() {
  local c="$1" team="${2:-}" st="$TMP/$c.state"
  mkdir -p "$st"
  printf '%s\n' "$BLOCK" "$FS" > "$TMP/$c.fns"
  env -u FT_TICK_TEAM ${team:+FT_TICK_TEAM="$team"} ROOT="$TMP/$c" STATE_DIR="$st" OUT="$TMP/$c.sent" MASTER_MSG="$MSG" FNS="$TMP/$c.fns" \
    bash -c 'set -uo pipefail
      DRY=0; MASTER_MIN_GAP=240; MASTER_INTERVAL=280; master=S#1; mok=0
      rows="$(printf "S#1\tft-master-tick\tmaster")"
      stamp_of(){ echo "$STATE_DIR/$1.$2"; }; stamp_gap(){ echo 1000000; }; write_stamp(){ :; }; log(){ :; }; goal(){ :; }
      fire(){ printf "%s" "$5" > "$OUT"; }
      . "$FNS"
      fire_seats; fire_seats' 2> "$TMP/$c.err"
  echo $?
}
evo() {   # evo <케이스> <학습 N> <폐기 M> — 합성 후보 파일 + LATEST
  local d="$TMP/$1/.fable-team/state/evolution"; mkdir -p "$d"
  { echo "# evolve 후보 — $TODAY (ft-evolve gate)"; echo; echo "## 학습 후보 ($2)"
    for ((i = 0; i < $2; i++)); do echo "- learn-$i.log 실패·판정불가 3회"; done; [ "$2" -gt 0 ] || echo "- 없음"
    echo; echo "## 폐기 후보 ($3)"
    for ((i = 0; i < $3; i++)); do echo "- old-$i.bak-x 31일"; done; [ "$3" -gt 0 ] || echo "- 없음"; } > "$d/candidates-$TODAY.md"
  echo "$TODAY candidates-$TODAY.md" > "$d/LATEST"
}
sent() { cat "$TMP/$1.sent" 2>/dev/null; }
errn() { grep -c '판정 불가' "$TMP/$1.err" 2>/dev/null || true; }

chk "블록 존재(r1467 표식)" "$([ -n "$BLOCK" ] && echo yes || echo no)" yes

c=t1; evo $c 2 1; rc="$(run $c fx)"
chk "T1 rc" "$rc" 0
has "T1 원문 앞부분 유지" "$(sent $c)" "$MSG [승격/폐기 판단] "
has "T1 후보 수" "$(sent $c)" "후보 학습 2 · 폐기 1"
has "T1 후보 파일" "$(sent $c)" "$TMP/$c/.fable-team/state/evolution/candidates-$TODAY.md"
has "T1 resolve 꼴" "$(sent $c)" 'ft-lessons.sh resolve team fx "검색어" --result keep|drop --reason "사유"'
has "T1 상한" "$(sent $c)" "승격(keep) 1·폐기(drop) 1 까지만"
chk "T1 한 줄(개행 0)" "$(sent $c | wc -l | tr -d ' ')" 0
chk "T1 stderr 0" "$(wc -l < "$TMP/$c.err" | tr -d ' ')" 0

c=t2a; evo $c 0 0; rc="$(run $c fx)"
chk "T2a 후보 0 rc" "$rc" 0
chk "T2a 후보 0 → 발사 줄 바이트 불변" "$(sent $c)" "$MSG"
chk "T2a stderr 0" "$(wc -l < "$TMP/$c.err" | tr -d ' ')" 0
c=t2b; evo $c 2 1; printf '%s\n' '{"ts": "x", "team": "fx", "seat": "fx-master#1", "id": "a", "verdict": "promote", "reason": "r"}' > "$TMP/$c/.fable-team/state/evolution/resolved-$TODAY.jsonl"
rc="$(run $c fx)"
chk "T2b 오늘 판단 있음 → 바이트 불변" "$(sent $c)" "$MSG"
c=t2c; evo $c 2 1; printf '%s\n' '{"ts": "x", "team": "other", "seat": "o#1", "id": "a", "verdict": "promote", "reason": "r"}' > "$TMP/$c/.fable-team/state/evolution/resolved-$TODAY.jsonl"
rc="$(run $c fx)"
has "T2c 다른 팀 판단만 있음 → 줄 붙음" "$(sent $c)" "후보 학습 2 · 폐기 1"
c=t2d; evo $c 2 1; rc="$(run $c)"
chk "T2d 메인 틱(FT_TICK_TEAM 없음) → 바이트 불변" "$(sent $c)" "$MSG"
chk "T2d stderr 0" "$(wc -l < "$TMP/$c.err" | tr -d ' ')" 0

c=t3a; mkdir -p "$TMP/$c/.fable-team/state/evolution"; rc="$(run $c fx)"
chk "T3a LATEST 없음 rc(틱 계속)" "$rc" 0
chk "T3a 줄 0" "$(sent $c)" "$MSG"
chk "T3a stderr 판정 불가 1줄(2바퀴)" "$(errn $c)" 1
c=t3b; evo $c 2 1; echo "$TODAY candidates-19990101.md" > "$TMP/$c/.fable-team/state/evolution/LATEST"; rc="$(run $c fx)"
chk "T3b 후보 파일 없음 rc" "$rc" 0
chk "T3b 줄 0" "$(sent $c)" "$MSG"
chk "T3b stderr 판정 불가 1줄" "$(errn $c)" 1
c=t3c; evo $c 2 1; sed -i '' 's/^## 폐기 후보.*/## 폐기/' "$TMP/$c/.fable-team/state/evolution/candidates-$TODAY.md"; rc="$(run $c fx)"
chk "T3c 후보 수 못 읽음 → 줄 0" "$(sent $c)" "$MSG"
chk "T3c stderr 판정 불가 1줄" "$(errn $c)" 1
echo "PHASE T1-T3 seconds=$((SECONDS - T0))"

# ── T4: ft-lessons resolve → resolved-<오늘>.jsonl ──
R4="$TMP/r4/.fable-team"; mkdir -p "$R4"
L() { FT_ROOT="$R4" FT_SEAT_NAME=fx-master#1 python3 -B "$KBIN/ft_lessons.py" "$@"; }
L add team fx "실험 교훈 alpha-keep" --kind experiment > /dev/null
L add team fx "실험 교훈 beta-drop" --kind experiment > /dev/null
RF="$R4/state/evolution/resolved-$TODAY.jsonl"
out="$(L resolve team fx alpha-keep --result keep --reason "세 번 반복 확인")"; rc=$?
chk "T4 keep rc" "$rc" 0
has "T4 keep 기존 출력" "$out" "RESOLVE keep 1건 → directive+pin"
chk "T4 keep 기존 결과(directive+pin)" "$(python3 -c 'import json,sys;r=[json.loads(l) for l in open(sys.argv[1])];a=[x for x in r if "alpha-keep" in x["text"]][0];print(a["kind"],a["pin"])' "$R4/state/lessons/team/fx.jsonl")" "directive True"
chk "T4 resolved 1줄" "$(wc -l < "$RF" 2>/dev/null | tr -d ' ')" 1
chk "T4 줄 내용" "$(python3 -c 'import json,sys;r=json.loads(open(sys.argv[1]).readline());print(sorted(r)==sorted(["ts","team","seat","id","verdict","reason"]),r["team"],r["seat"],r["id"],r["verdict"],r["reason"])' "$RF" 2>&1)" "True fx fx-master#1 alpha-keep promote 세 번 반복 확인"
out="$(L resolve team fx beta-drop --result drop)"; rc=$?
chk "T4 drop rc" "$rc" 0
has "T4 drop 기존 출력(아카이브)" "$out" "RESOLVE drop 1건 → 아카이브"
chk "T4 drop 뒤 2줄 · verdict discard · reason 빈 값" "$(wc -l < "$RF" | tr -d ' ') $(tail -1 "$RF" | python3 -c 'import json,sys;r=json.loads(sys.stdin.read());print(r["verdict"],repr(r["reason"]))')" "2 discard ''"
out="$(L resolve team fx 없는말 --result keep --reason x)"; rc=$?
chk "T4 일치 없음 rc1 · 줄 추가 0" "$rc $(wc -l < "$RF" | tr -d ' ')" "1 2"
echo "PHASE T4 seconds=$((SECONDS - T0))"

# ── T5: ft_eval_daily 기계 판정 ──
ev() { mkdir -p "$TMP/$1/.fable-team"; FT_ROOT="$TMP/$1/.fable-team" FT_EVAL_NO_SEND=1 FT_EVAL_DESK=none python3 -B "$KBIN/ft_eval_daily.py" > /dev/null 2>&1; cat "$TMP/$1/.fable-team/state/eval/daily-$TODAY.md" 2>/dev/null; }
out="$(ev r5a)"
has "T5 resolved 없음 → 고칠 것 후보" "$out" "승격/폐기 판단 = 오늘 resolved promote 0 · discard 0 → 고칠 것 후보"
has "T5 큐 확인 방법 = resolved 파일" "$(cat "$TMP/r5a/.fable-team/state/eval/queue.md" 2>/dev/null)" "팀장 틱이 승격/폐기를 하는가 :: state/evolution/resolved-<오늘>.jsonl 에 promote ≥1 · discard ≥1(팀 무관)"
mkdir -p "$TMP/r5b/.fable-team/state/evolution"
printf '%s\n' '{"team": "a", "verdict": "promote"}' '{"team": "b", "verdict": "discard"}' '{"team": "b", "verdict": "promote"}' > "$TMP/r5b/.fable-team/state/evolution/resolved-$TODAY.jsonl"
has "T5 promote 2·discard 1 → 통과" "$(ev r5b)" "승격/폐기 판단 = 오늘 resolved promote 2 · discard 1 → 통과"
mkdir -p "$TMP/r5c/.fable-team/state/evolution"
printf '%s\n' '{"team": "a", "verdict": "promote"}' > "$TMP/r5c/.fable-team/state/evolution/resolved-$TODAY.jsonl"
has "T5 promote 만 → 고칠 것 후보" "$(ev r5c)" "promote 1 · discard 0 → 고칠 것 후보"
mkdir -p "$TMP/r5d/.fable-team/state/evolution"; printf 'not json\n' > "$TMP/r5d/.fable-team/state/evolution/resolved-$TODAY.jsonl"
has "T5 깨진 줄 → 판정 불가" "$(ev r5d)" "승격/폐기 판단 = 판정 불가"
echo "PHASE T5 seconds=$((SECONDS - T0))"

# ── bin·kit 일치 ──
chk "ft-tick.sh bin=kit" "$(cmp -s "$TICK" "$KBIN/ft-tick.sh" && echo same || echo diff)" same
echo "fail=$fail seconds=$((SECONDS - T0))"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
