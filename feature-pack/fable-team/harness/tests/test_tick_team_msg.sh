#!/usr/bin/env bash
# test_tick_team_msg.sh — R150: 팀 틱 4개가 라이브 ft-tick.sh 를 같이 돌려도 안전한가.
#   ⓐ두 변수 미설정 → master/pm 문구가 지금 판과 바이트 동일  ⓑFT_TICK_MASTER_MSG → 그대로 발사
#   ⓒFT_TICK_PM_MSG → 확장·치환 0 그대로  ⓓFT_TICK_WT_SWEEP=0 → sweep 실행 0 (=1 은 양성 대조)
#   ⓔ메인 1 + 팀 4 동시 --once → drift 알림 정확히 1통 · drift.sig 는 메인 STATE_DIR 에만 · .turn 은 자기 좌석만 · api-outage 상태 경로 = 좌석표 이름별
#   ⓕ키트 두 사본 동일.  변이: R150_TICK=<변이 사본> · R150_MUTANT=team-drift(팀 틱이 drift 를 켠 설치 꼴) · team-raised(팀 틱이 raised 경보를 켠 설치 꼴)
#   ⓔ 에는 raised 경보(R149)도 포함: 가짜 ft_raised(양성 1행) → 정확히 1통 · 수신 = 메인 틱 master · raised.sig 는 메인 STATE_DIR 에만
# 모든 쓰기는 mktemp scratch 안 — 실 /tmp 기본 경로·라이브 좌석표 0. tmux·mbox 는 가짜.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
KIT="$REPO/scripts/harness-install/fable-team/bin/ft-tick.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }

# 라이브 bin 꼴: drift_watch 는 */.fable-team/bin 에서 돌 때만 켜진다. cwd 는 git 이 아닌 scratch → ROOT=cwd.
mkdir -p "$TMP/repo/.fable-team/bin"; LIVE="$TMP/repo/.fable-team/bin/ft-tick.sh"
cp "${R150_TICK:-$KIT}" "$LIVE"
chk "ⓕ 키트 두 사본 동일" "$(cmp -s "$KIT" "$REPO/scripts/fable-team-bin/ft-tick.sh" && echo same || echo differ)" same
bash -n "$LIVE" && ok "bash -n" || bad "bash -n"

# 가짜 tmux: list-panes = FAKE_PANES · send-keys -l 본문을 FAKE_SENT_DIR/p<pane> 에 저장 (PATH 스텁은 틱의 PATH 앞붙임에 지므로 export -f)
tmux() { case "$1" in list-panes) printf '%s\n' "$FAKE_PANES";; send-keys) [ "${4:-}" = -l ] && printf '%s' "$5" > "$FAKE_SENT_DIR/p${3#%}";; esac; return 0; }
export -f tmux
export FAKE_PANES=$'M#1 %1\nP#1 %2\nmain-M#1 %3\nmain-N#1 %4\nops-M#1 %5\nops-N#1 %6\ncfo-M#1 %7\ncfo-N#1 %8\nfeature-M#1 %9\nfeature-N#1 %10\nloom-M#1 %11\nloom-N#1 %12'
printf '#!/bin/bash\necho "$*" >> "$MBOX_LOG"\n' > "$TMP/mbox-stub.sh"
printf '#!/bin/bash\ntouch "$SWEEP_MARK"; echo ran\n' > "$TMP/sweep-stub.sh"; chmod +x "$TMP/sweep-stub.sh"
printf '#!/bin/bash\nprintf "DRIFT 1 file\\nDIFF scripts/x\\n"; exit 1\n' > "$TMP/drift-stub.sh"
printf 'import sys\nif sys.argv[1] == "check": print("ft-raised-stub-seat model=x card=gone")\n' > "$TMP/raised-stub.py"
printf '#!/bin/bash\ncase "$1" in turn) echo "WORKING 2026-10-14T00:00:00 0 no jsonl";; esac\n' > "$TMP/seatstatus-stub.sh"
BASE_ENV=(FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_IDLE_ENABLED=0FT_TICK_API_OUTAGE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_DRIFT=0 FT_TICK_WT_SWEEP=0 FT_TICK_RAISED=0 "FT_TICK_RAISED_BIN=$TMP/raised-stub.py"
  "FT_TICK_GOAL_TICK=$TMP/none" "FT_TICK_SEAT_STATUS=$TMP/none" "FT_TICK_MBOX=$TMP/mbox-stub.sh" "MBOX_LOG=$TMP/mbox.log")

# run <이름> <좌석표> <틱 인자> [KEY=VAL ...] → $TMP/<이름>/out · sent/p<pane> (뒤쪽 KEY=VAL 이 BASE_ENV 를 덮는다)
run() {
  local n="$1" seats="$2" flags="$3"; shift 3; mkdir -p "$TMP/$n/sent" "$TMP/$n/state"
  ( cd "$TMP/repo" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
      "${BASE_ENV[@]}" FT_TICK_SEATS="$seats" FT_TICK_STAMP_PREFIX="$TMP/$n/p-" FT_TICK_PIDFILE="$TMP/$n/pid" \
      FT_TICK_STATE_DIR="$TMP/$n/state" FAKE_SENT_DIR="$TMP/$n/sent" "$@" bash "$LIVE" $flags > "$TMP/$n/out" 2>&1 )
}
sent() { cat "$TMP/$1/sent/p$2" 2>/dev/null; }
seats_pm() { printf '{"_master":"M#1","M#1":{"role":"master","tick":"ft-master-tick"},"P#1":{"role":"pm","tick":"ft-pm-tick"}}' > "$TMP/seats-pm.json"; }
seats_pm

# 지금 판 문구 (바이트 기준선 · pm 의 $1 = report_to = M#1)
EXP_MASTER='[cron-tick · 뉴스] 형식은 SEATBELT-README §6-1 master 항 그대로(★⓪ 완성 상태 트리 = ft-news-tick ⑥ 출력 그대로 맨 위★ · 뉴스 4칸 ≤6불릿 · 빈 줄 · 세션 상태 트리 · 같은 턴에 1건 착수). 변화 없으면 "변화 없음 — <증상 한 줄>" 만. 총 ≤900자.'
EXP_PM='[cron-tick] pm 틱 — ①골 대조 1줄(M?/G?) ②원장 미등재 ③활성 나노 @zc_v65_active 전수(0 이면 즉시 set-option) ④사람 확인 필요분 → M#1. 변화 없으면 "변화 없음" 1줄. 정본·형식: SEATBELT-README §6-1.'

run a "$TMP/seats-pm.json" --once
chk "ⓐ master 문구 바이트 동일" "$(sent a 1)" "$EXP_MASTER"
chk "ⓐ pm 문구 바이트 동일" "$(sent a 2)" "$EXP_PM"

MV='팀 뉴스 $HOME `x` "q" \n {y}'
run b "$TMP/seats-pm.json" --once "FT_TICK_MASTER_MSG=$MV"
chk "ⓑ FT_TICK_MASTER_MSG 그대로 발사" "$(sent b 1)" "$MV"
chk "ⓑ pm 문구는 불변" "$(sent b 2)" "$EXP_PM"

PV='팀 문구 $1 {x}'
run c "$TMP/seats-pm.json" --once "FT_TICK_PM_MSG=$PV"
chk "ⓒ FT_TICK_PM_MSG 확장·치환 0" "$(sent c 2)" "$PV"
chk "ⓒ master 문구는 불변" "$(sent c 1)" "$EXP_MASTER"

run d0 "$TMP/seats-pm.json" --once "FT_TICK_WT_SWEEP=0" "FT_TICK_WT_SWEEP_BIN=$TMP/sweep-stub.sh" "SWEEP_MARK=$TMP/d0/mark"
chk "ⓓ FT_TICK_WT_SWEEP=0 → sweep 실행 0" "$([ -e "$TMP/d0/mark" ] && echo ran || echo none)" none
run d1 "$TMP/seats-pm.json" --once "FT_TICK_WT_SWEEP=1" "FT_TICK_WT_SWEEP_BIN=$TMP/sweep-stub.sh" "SWEEP_MARK=$TMP/d1/mark"
chk "ⓓ 양성 대조: =1 → sweep 실행" "$([ -e "$TMP/d1/mark" ] && echo ran || echo none)" ran

# ⓔ 메인 1 + 팀 4 동시 --once (drift 켜진 쪽은 메인뿐 · 팀은 STATE_DIR 분리)
mkdir -p "$TMP/repo/.fable-team"
for t in main ops cfo feature loom; do
  s="$TMP/repo/.fable-team/seats-$t.json"; [ "$t" = main ] && s="$TMP/repo/.fable-team/seats.json"
  printf '{"_master":"%s-M#1","%s-M#1":{"role":"master","tick":"ft-master-tick"},"%s-N#1":{"role":"nano","tick":null}}' "$t" "$t" "$t" > "$s"
done
EOPT=(FT_TICK_IDLE_ENABLED=1 "FT_TICK_SEAT_STATUS=$TMP/seatstatus-stub.sh" "FT_TICK_DRIFT_BIN=$TMP/drift-stub.sh")
run e-main "$TMP/repo/.fable-team/seats.json" --once "${EOPT[@]}" FT_TICK_DRIFT=1 FT_TICK_RAISED=1 &
for t in ops cfo feature loom; do
  dr=0; [ "${R150_MUTANT:-}" = team-drift ] && dr=1
  rr=0; [ "${R150_MUTANT:-}" = team-raised ] && rr=1
  run "e-$t" "$TMP/repo/.fable-team/seats-$t.json" --once "${EOPT[@]}" "FT_TICK_DRIFT=$dr" "FT_TICK_RAISED=$rr" FT_TICK_WT_SWEEP=0 &
done
wait
chk "ⓔ drift 알림 정확히 1통" "$(grep -c '\[drift\]' "$TMP/mbox.log" 2>/dev/null || true)" 1
chk "ⓔ drift.sig = 메인 STATE_DIR 에만" "$(ls "$TMP"/e-*/state/drift.sig 2>/dev/null | sed "s|$TMP/||" | tr '\n' ' ')" "e-main/state/drift.sig "
chk "ⓔ raised 경보 정확히 1통" "$(grep -c '내릴 것' "$TMP/mbox.log" 2>/dev/null || true)" 1
chk "ⓔ raised 수신 = 메인 틱 master" "$(grep '내릴 것' "$TMP/mbox.log" | awk '{print $2}' | tr '\n' ' ')" "main-M#1 "
chk "ⓔ raised.sig = 메인 STATE_DIR 에만" "$(ls "$TMP"/e-*/state/raised.sig 2>/dev/null | sed "s|$TMP/||" | tr '\n' ' ')" "e-main/state/raised.sig "
for t in main ops cfo feature loom; do
  chk "ⓔ $t STATE_DIR 의 .turn = 자기 좌석만" "$(ls "$TMP/e-$t/state" | grep '\.turn$' | tr '\n' ' ')" "$t-N#1.turn "
  chk "ⓔ $t master 문구 발사" "$(sent e-$t "$(echo "$FAKE_PANES" | grep -F "$t-M#1 " | sed 's/.*%//')")" "$EXP_MASTER"
done
# api-outage 상태 경로 = <ROOT>/.fable-team/state/api-outage/<좌석표 이름> (팀 STATE_DIR 로 옮기지 않음) — --dry-run 이 경로를 찍는다
for t in main ops cfo feature loom; do
  s="seats-$t.json"; [ "$t" = main ] && s=seats.json
  run "o-$t" "$TMP/repo/.fable-team/$s" "--once --dry-run" FT_TICK_API_OUTAGE=1
  chk "ⓔ $t api-outage 상태 경로" "$(grep -o 'state=.*' "$TMP/o-$t/out" | grep api-outage)" "state=$TMP/repo/.fable-team/state/api-outage/$s"
done

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
