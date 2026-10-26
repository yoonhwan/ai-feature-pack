#!/usr/bin/env bash
# test_r928_watch_rearm_grace.sh — r928 r3: planner 감시 «다시 걸기 틈» 유예 = 60초 표본기가 본 «처음 없음» + 긴급 근거 줄.
#   R1 감시(ft-inbox-watch.sh)는 쓰기 0 · R2 표본 파일(state/planner-watch-absent-since.<좌석> = «<표본 epoch>\t<처음 없음|0>»)의
#   쓰는 쪽 = `ft-mbox.sh watch-sample`(ft-tick 60초) 하나 · 송신 쪽은 읽기만 · R3 이상은 모두 긴급 쪽.
#   ⓐ 감시 없음 첫 송신 → 긴급 0 · 근거 «처음 없음» · 표본 = 정수 두 칸   ⓑ 300초 안 두 번째 송신 → 긴급 0   ⓒ 300초 뒤 → 긴급 1
#   ⓓ 감시 살아남 → 처음 없음 지워짐(0) · 긴급 0   ⓔ 표본 이상 7종 → 긴급 1 + WATCH-ABSENT 1줄   ⓕ 표본 쓰기 실패 → 긴급 1
#   ⓖ 지우기 실패 뒤 감시 없음 → 긴급 1(옛 값 믿지 않음)   ⓗ 감시가 state 에 쓰는 파일 0   ⓙ 감시 살아 있던 동안 송신 0 → 첫 공백 송신 긴급 0(H2)
#   ⓚ 표본 200초 전(표본기 멈춤) → 긴급 1 · 표본 멈춤 줄   + 10분 1회 제한 회귀 0 · 사본 4곳 같은 함수 · ft-tick 표본 배선
#   격리 FT_ROOT · 가짜 pgrep(FT_PGREP) · 가짜 tmux · 실 tmux·홈·BYZ 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
WATCH="$REPO/harness/bin/ft-inbox-watch.sh"
KIT="$REPO/harness/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }
has() { grep -qF -- "$2" "$3" && ok "$1" || bad "$1 (없음 «$2» · $(tr '\n' ' ' < "$3" | cut -c1-240))"; }
hasnt() { grep -qF -- "$2" "$3" && bad "$1 (있음 «$2»)" || ok "$1"; }

# ── ① 짝 사본 · 같은 함수 본문 (설치 cmp0 · 판정이 한 갈래)
cmp -s "$REPO/harness/bin/ft-inbox-watch.sh" "$KIT/ft-inbox-watch.sh" && ok "① 짝 cmp0 ft-inbox-watch.sh(bin ↔ kit)" || bad "① 짝 불일치 ft-inbox-watch.sh"
cmp -s "$KIT/ft-mbox.sh" "$REPO/skill/scripts/ft-mbox.sh" && ok "① 짝 cmp0 ft-mbox.sh(kit ↔ skill/scripts)" || bad "① 짝 불일치 ft-mbox.sh"
cmp -s "$REPO/harness/bin/ft-tick.sh" "$KIT/ft-tick.sh" && ok "① 짝 cmp0 ft-tick.sh(bin ↔ kit)" || bad "① 짝 불일치 ft-tick.sh"
fbody() { awk -v n="$2" '$0 ~ "^"n"\\(\\) \\{" {p=1} p {print} p && /^}/ {exit}' "$1"; }
for fn in _absent_grace _ep_hhmm; do
  a="$(fbody "$REPO/harness/comm/mbox.sh" "$fn")"; b="$(fbody "$KIT/ft-mbox.sh" "$fn")"
  [ -n "$a" ] && [ "$a" = "$b" ] && ok "① $fn 본문 같음(comm/mbox.sh ↔ kit ft-mbox.sh)" || bad "① $fn 본문 다름/없음"
done

# ── ⓗ R1 감시는 state 에 아무것도 쓰지 않는다 (TERM · INT 전후 목록 같음)
for sig in TERM INT; do
  W="$T/w-$sig"; mkdir -p "$W/.fable-team/state/inbox"; : > "$W/.fable-team/state/inbox/planner-h.jsonl"
  before="$(cd "$W/.fable-team/state" && find . | sort)"
  FT_ROOT="$W" FT_INBOX_WATCH_POLL=0.1 bash "$WATCH" 'planner-h#7' >/dev/null 2>"$T/werr" & WP=$!
  sleep 0.8; mid="$(cd "$W/.fable-team/state" && find . | sort)"
  kill -"$sig" "$WP" 2>/dev/null; sleep 0.5
  kill -TERM "$WP" 2>/dev/null; wait "$WP" 2>/dev/null   # 비대화 셸의 백그라운드 작업은 SIGINT 무시 상속 — 남아 있으면 TERM 으로 거둔다(대기 무한 0)
  after="$(cd "$W/.fable-team/state" && find . | sort)"
  eq "ⓗ[$sig] 감시 중 state 목록 = 시작 전" "$mid" "$before"
  eq "ⓗ[$sig] 감시 끝난 뒤 state 목록 = 시작 전" "$after" "$before"
done
grep -q 'planner-watch' "$WATCH" && bad "ⓗ ft-inbox-watch.sh 에 planner-watch 표식 코드가 남음" || ok "ⓗ ft-inbox-watch.sh 표식 코드 0"

# ── ② 격리 루트 · 대역
R="$T/r928"; C="$R/.fable-team/comm"; ST="$R/.fable-team/state"; mkdir -p "$C" "$R/.fable-team/bin" "$ST"
cp "$REPO/harness/comm/"mbox*.sh "$REPO/harness/comm/"mbox*.py "$C/"
cp "$REPO/harness/bin/ft-inbox.sh" "$REPO/harness/bin/ft-inbox.py" "$REPO/harness/bin/ft_inbox_core.py" "$R/.fable-team/bin/"
P='byz-planner-master-claude#72'; H='byz-harness-master-claude#9'
echo '{}' > "$R/.fable-team/seats.json"
printf '{"_master":"%s"}\n' "$P" > "$R/.fable-team/seats-planner.json"
printf '{"_master":"%s"}\n' "$H" > "$R/.fable-team/seats-harness.json"
PROCS="$T/procs.txt"; printf '#!/bin/sh\ncat %s\n' "$PROCS" > "$T/fake-pgrep"; chmod +x "$T/fake-pgrep"
printf '#!/bin/sh\nexit 1\n' > "$T/fake-haiku"; chmod +x "$T/fake-haiku"
mkdir -p "$T/fakebin"; printf '#!/bin/sh\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
procs_live() { { echo "60861 /opt/x/Python -u - $KIT $P"
                  echo "60863 bash $C/mbox.sh send $P x [결정] 시작: bash $KIT/ft-inbox-watch.sh $P"; } > "$PROCS"; }
procs_none() { : > "$PROCS"; }
SF="$ST/planner-watch-absent-since.$P"; MK="$ST/planner-watch-missing.$P"
env928() { env PATH="$T/fakebin:$PATH" FT_ROOT="$R" FT_MBOX_DIR="$C" FT_SEATS_JSON="$R/.fable-team/seats.json" FT_INBOX_HAIKU="$T/fake-haiku" FT_PGREP="$T/fake-pgrep" FT_BIN="$KIT" "$@"; }
sample() { env928 bash "$KIT/ft-mbox.sh" watch-sample "$P" "$C" >"$T/sout" 2>"$T/serr"; }
putsf() { local n; n="$(date +%s)"; printf '%s\t%s\n' "$((n - $1))" "$([ "$2" = 0 ] && echo 0 || echo $((n - $2)))" > "$SF"; }  # <표본 몇 초 전> <처음 없음 몇 초 전|0>
sfcol() { cut -f"$1" "$SF" 2>/dev/null; }
since_age() { local v; v="$(sfcol 2)"; case "$v" in ''|*[!0-9]*) echo 999999 ;; *) echo $(( $(date +%s) - v )) ;; esac; }  # 처음 없음 몇 초 전(값 없음 = 큰 수 · 산술 오류로 시험이 끊기지 않게)
abodies() { python3 - "$C/mailbox.jsonl" "$H" <<'PY'
import json, sys
try:
    f = open(sys.argv[1], encoding="utf-8")
except OSError:
    sys.exit(0)
for l in f:
    r = json.loads(l) if l.strip() else {}
    if r.get("to") == sys.argv[2] and r.get("from") == "ft-watch-alarm":
        print(r.get("body", "").replace("\n", " "))
PY
}
alarms() { abodies | grep -c 'planner watch 없음' || true; }
dbv() { sed -n 's/.*doorbell=\(.*\)$/\1/p' <<<"$1" | tail -1; }
ELD() { touch -t "$(date -v-11M +%Y%m%d%H%M 2>/dev/null || date -d '-11 min' +%Y%m%d%H%M)" "$1"; }
fresh() { chmod 755 "$ST" 2>/dev/null; rm -f "$C/mailbox.jsonl" "$MK"; rm -rf "$SF"; procs_none; }   # 우편함 포화(ring=10 DROPPED)로 건마다 결과가 흔들리지 않게

for S in comm kit; do
  if [ "$S" = comm ]; then snd() { env928 bash "$C/mbox.sh" send "$P" "t$1#1" "[결정] r928 r3 시험 $S $1" 2>"$T/err928"; }
  else snd() { env928 bash "$KIT/ft-mbox.sh" send "$P" "t$1#1" "[결정] r928 r3 시험 $S $1" 2>"$T/err928"; }; fi
  # ⓐ 감시 있음 표본 → 감시 죽음 → 표본(처음 없음 = 지금) → 첫 송신 긴급 0 · 근거 «처음 없음»
  fresh; procs_live; sample; procs_none; sample; rc=$?
  eq "ⓐ[$S] 감시 없음 표본 rc0" "$rc" 0
  [ -n "$(sfcol 1 | grep -E '^[0-9]{9,12}$')" ] && [ -n "$(sfcol 2 | grep -E '^[0-9]{9,12}$')" ] && ok "ⓐ[$S] 표본 = 정수 두 칸" || bad "ⓐ[$S] 표본 본문: $(cat "$SF" 2>/dev/null)"
  [ "$(since_age)" -le 5 ] && ok "ⓐ[$S] 처음 없음 = 지금(표본기가 처음 본 시각)" || bad "ⓐ[$S] 처음 없음 값 $(sfcol 2)"
  o="$(snd 1)"
  eq "ⓐ[$S] 첫 송신 → 긴급 0통" "$(alarms)" 0
  has "ⓐ[$S] stderr «WATCH-REARM 대기 0분 · 처음 없음»" "WATCH-REARM 대기 0분 · 처음 없음 " "$T/err928"
  eq "ⓐ[$S] 유예 중에도 db 꼬리 (WATCH 없음)" "$(dbv "$o")" "quiet(WATCH 없음)"
  [ ! -f "$MK" ] && ok "ⓐ[$S] 유예는 10분 제한 표식 0" || bad "ⓐ[$S] 유예 중 표식 생성됨"
  # ⓐ' 감시가 표본 사이에 죽음(표본은 아직 감시 있음) → 긴급 0 · «표본 전»
  fresh; procs_live; sample; procs_none; snd 2 >/dev/null
  eq "ⓐ'[$S] 표본 전 공백 → 긴급 0통" "$(alarms)" 0
  has "ⓐ'[$S] 근거 «처음 없음 표본 전»" "처음 없음 표본 전" "$T/err928"
  # ⓑ 처음 없음 290초 전 · 표본 10초 전 → 긴급 0
  fresh; putsf 10 290; snd 3 >/dev/null
  eq "ⓑ[$S] 300초 안 송신 → 긴급 0통" "$(alarms)" 0
  has "ⓑ[$S] stderr «WATCH-REARM 대기 4분»" "WATCH-REARM 대기 4분" "$T/err928"
  # ⓒ 처음 없음 310초 전 → 긴급 1 · 근거 줄
  fresh; putsf 10 310; HH="$(date -r "$(sfcol 2)" +%H:%M)"; snd 4 >/dev/null
  eq "ⓒ[$S] 300초 뒤 송신 → 긴급 1통" "$(alarms)" 1
  abodies | grep -qF "감시 프로세스 0(pgrep) · 처음 없음 $HH(5분)" && ok "ⓒ[$S] 근거 줄 «프로세스 0 · 처음 없음 $HH(5분)»" || bad "ⓒ[$S] 근거 줄: $(abodies | tail -1)"
  hasnt "ⓒ[$S] 유예 문구 없음" "WATCH-REARM" "$T/err928"
  # ⓓ 감시 살아남 → 표본이 처음 없음을 지움(0) · 송신 quiet · 긴급 0
  fresh; putsf 10 400; procs_live; sample
  eq "ⓓ[$S] 감시 있음 표본 → 처음 없음 칸 0" "$(sfcol 2)" 0
  o="$(snd 5)"
  eq "ⓓ[$S] 감시 있음 → doorbell=quiet" "$(dbv "$o")" "quiet"
  eq "ⓓ[$S] 감시 있음 → 긴급 0통" "$(alarms)" 0
  # 10분 1회 제한 회귀 0
  fresh; putsf 10 400; snd 6 >/dev/null; snd 7 >/dev/null
  eq "ⓓ'[$S] 10분 안 두 번 → 긴급 1통" "$(alarms)" 1
  ELD "$MK"; snd 8 >/dev/null
  eq "ⓓ'[$S] 표식 11분 경과 → 다시 1통" "$(alarms)" 2

  # ⓔ 표본 이상 7종 → 긴급 1 + WATCH-ABSENT 1줄 · 유예 0
  n="$(date +%s)"
  for k in not-epoch empty future-since future-sample dir symlink perm0; do
    fresh
    case "$k" in
      not-epoch)     printf '%s\tnot-epoch\n' "$n" > "$SF"; why="이상(본문 깨짐)" ;;
      empty)         : > "$SF"; why="이상(본문 깨짐)" ;;
      future-since)  printf '%s\t%s\n' "$n" "$((n + 600))" > "$SF"; why="이상(미래 처음 없음)" ;;
      future-sample) printf '%s\t%s\n' "$((n + 600))" "$((n + 600))" > "$SF"; why="이상(미래 표본)" ;;
      dir)           mkdir -p "$SF"; why="이상(일반 파일 아님)" ;;
      symlink)       printf '%s\t%s\n' "$n" "$n" > "$T/real-sf"; ln -s "$T/real-sf" "$SF"; why="이상(심링크)" ;;
      perm0)         printf '%s\t%s\n' "$n" "$n" > "$SF"; chmod 000 "$SF"; why="이상(읽기 실패)" ;;
    esac
    snd "e$k" >/dev/null
    eq "ⓔ[$S/$k] 표본 이상 → 긴급 1통" "$(alarms)" 1
    has "ⓔ[$S/$k] stderr WATCH-ABSENT $why" "WATCH-ABSENT $why" "$T/err928"
    hasnt "ⓔ[$S/$k] 유예 문구 없음" "WATCH-REARM" "$T/err928"
    [ "$S" = kit ] && [ "$k" = not-epoch ] && { sample; rc=$?; eq "ⓔ[$k] 감시 없음 표본은 이상 파일에 안 씀(rc1)" "$rc" 1; eq "ⓔ[$k] 이상 본문 그대로" "$(sfcol 2)" not-epoch; }
    chmod 644 "$SF" 2>/dev/null
  done

  # ⓕ 표본 쓰기 실패(state 0555) → 표본 rc1 + 쓰기 실패 줄 · 송신 긴급 1
  fresh; chmod 555 "$ST"; sample; rc=$?
  eq "ⓕ[$S] 쓰기 실패 → 표본 rc1" "$rc" 1
  has "ⓕ[$S] 표본 stderr «WATCH-ABSENT 이상(쓰기 실패)»" "WATCH-ABSENT 이상(쓰기 실패)" "$T/serr"
  snd f1 >/dev/null
  eq "ⓕ[$S] 표본 없음 + 쓰기 불가 → 긴급 1통" "$(alarms)" 1
  # ⓕ' 직전 표본 «감시 있음»(신선) 위에서 쓰기 불가가 되고 감시가 죽음 → 그 표본을 믿지 않음
  fresh; procs_live; sample; procs_none; chmod 555 "$ST"; sample; rc=$?
  eq "ⓕ'[$S] 감시 없음 표본 쓰기 실패 rc1" "$rc" 1
  snd f2 >/dev/null
  eq "ⓕ'[$S] 옛 «감시 있음» 표본 + 쓰기 불가 → 긴급 1통" "$(alarms)" 1
  has "ⓕ'[$S] stderr «WATCH-ABSENT 이상(state 쓰기 불가)»" "WATCH-ABSENT 이상(state 쓰기 불가)" "$T/err928"
  chmod 755 "$ST"

  # ⓖ 지우기 실패(state 0555): 처음 없음 100초 전(유예 안) · 감시 살아남 → 지우기 실패 rc1 → 감시 다시 죽음 → 긴급 1
  fresh; putsf 10 100; chmod 555 "$ST"; procs_live; sample; rc=$?
  eq "ⓖ[$S] 지우기 실패 → 표본 rc1" "$rc" 1
  has "ⓖ[$S] 표본 stderr «WATCH-ABSENT 이상(지우기 실패)»" "WATCH-ABSENT 이상(지우기 실패)" "$T/serr"
  procs_none; snd g1 >/dev/null
  eq "ⓖ[$S] 지우기 실패 뒤 감시 없음 → 긴급 1통(옛 처음 없음 안 믿음)" "$(alarms)" 1
  chmod 755 "$ST"
  # ⓖ' 표본 파일 0444 → 지우기(0 으로 덮기) 성공 · 옛 값 사라짐
  fresh; putsf 10 100; chmod 444 "$SF"; procs_live; sample; rc=$?
  eq "ⓖ'[$S] 0444 표본 → 덮기 rc0" "$rc" 0
  eq "ⓖ'[$S] 0444 표본 → 처음 없음 칸 0(옛 값 0)" "$(sfcol 2)" 0

  # ⓙ H2: 옛 공백 기록(1000초 전) → 감시 살아 있는 동안 송신 0 · 표본만 → 감시 죽음 → 첫 송신 긴급 0
  fresh; putsf 1000 1000; procs_live; sample; procs_none; sample; snd j1 >/dev/null
  eq "ⓙ[$S] 감시 살아 있던 동안 송신 0 → 첫 공백 송신 긴급 0통" "$(alarms)" 0
  [ "$(since_age)" -le 5 ] && ok "ⓙ[$S] 처음 없음 = 새 공백 시작(옛 1000초 아님)" || bad "ⓙ[$S] 처음 없음 $(sfcol 2)"
  # ⓙ' 계속 없음이면 처음 없음 유지(다음 표본이 시각을 당기지 않음)
  fresh; putsf 70 200; old="$(sfcol 2)"; sample
  eq "ⓙ'[$S] 계속 없음 표본 → 처음 없음 그대로" "$(sfcol 2)" "$old"

  # ⓚ 표본 200초 전(표본기 멈춤) → 긴급 1 + 표본 멈춤 줄 · 표본 파일 없음도 같음
  fresh; putsf 200 100; snd k1 >/dev/null
  eq "ⓚ[$S] 표본 200초 전 → 긴급 1통" "$(alarms)" 1
  has "ⓚ[$S] stderr «WATCH-ABSENT 표본 멈춤»" "WATCH-ABSENT 표본 멈춤(표본 멈춤 " "$T/err928"
  fresh; snd k2 >/dev/null
  eq "ⓚ'[$S] 표본 없음 → 긴급 1통" "$(alarms)" 1
  has "ⓚ'[$S] stderr «WATCH-ABSENT 표본 멈춤(표본 없음)»" "WATCH-ABSENT 표본 멈춤(표본 없음)" "$T/err928"
  abodies | grep -qF '감시 프로세스 0(pgrep) · 표본 이상(표본 없음)' && ok "ⓚ'[$S] 근거 줄 «표본 이상(표본 없음)»" || bad "ⓚ'[$S] 근거 줄: $(abodies | tail -1)"
done

# 유예 폭 환경값(FT_WATCH_REARM_GRACE_SEC) — 0 이면 유예 없음 · 600 이면 400초도 유예
fresh; putsf 10 5; env928 env FT_WATCH_REARM_GRACE_SEC=0 bash "$KIT/ft-mbox.sh" send "$P" tg0#1 "[결정] r928 유예 0" >/dev/null 2>&1
eq "유예 0초 → 처음 없음 5초 전이어도 긴급 1통" "$(alarms)" 1
fresh; putsf 10 400; env928 env FT_WATCH_REARM_GRACE_SEC=600 bash "$KIT/ft-mbox.sh" send "$P" tg6#1 "[결정] r928 유예 600" >/dev/null 2>&1
eq "유예 600초 → 처음 없음 400초 전도 긴급 0통" "$(alarms)" 0

# ── ③ ft-tick 배선 — 매 루프 planner _master 로 watch-sample (dry-run 대상 줄 · 끄는 스위치)
ENVX="FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_HIL=0 FT_TICK_DRIFT=0 FT_TICK_RESUME=0"
for tk in "$REPO/harness/bin/ft-tick.sh" "$KIT/ft-tick.sh"; do
  case "$tk" in "$KIT"/*) tl=kit ;; *) tl=bin ;; esac
  env $ENVX FT_MBOX_DIR="$C" FT_TICK_SEATS="$R/.fable-team/seats.json" FT_TICK_STAMP_PREFIX="$T/tk-" FT_TICK_STATE_DIR="$T/tk-state" FT_TICK_FTMBOX="$KIT/ft-mbox.sh" \
    bash "$tk" --once --dry-run > "$T/tick.out" 2>&1
  has "③[$tl] dry-run «DRY kind=watch-sample seat=${P}»" "DRY kind=watch-sample seat=$P bin=$KIT/ft-mbox.sh" "$T/tick.out"
  env $ENVX FT_TICK_WATCH_SAMPLE=0 FT_MBOX_DIR="$C" FT_TICK_SEATS="$R/.fable-team/seats.json" FT_TICK_STAMP_PREFIX="$T/tk-" FT_TICK_STATE_DIR="$T/tk-state" FT_TICK_FTMBOX="$KIT/ft-mbox.sh" \
    bash "$tk" --once --dry-run > "$T/tick0.out" 2>&1
  hasnt "③[$tl] FT_TICK_WATCH_SAMPLE=0 → 표본 줄 0" "kind=watch-sample" "$T/tick0.out"
done
[ -f "$KIT/ft-mbox.sh" ] && [ -f "$KIT/ft-tick.sh" ] && ok "③ 키트 bin 에 ft-tick.sh 옆 ft-mbox.sh 실재(기본 경로 \$HERE/ft-mbox.sh)" || bad "③ 키트 bin 짝 없음"

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
