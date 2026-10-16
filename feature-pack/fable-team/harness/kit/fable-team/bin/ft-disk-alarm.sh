#!/usr/bin/env bash
# ft-disk-alarm.sh — 디스크 여유가 모자라면 planner 에 쪽지로 알린다 (R246 · ft-resource-watch tick 끝에서 호출).
#   단계: ok → 경고(<FT_DISK_WARN_GIB 50) → 긴급(<FT_DISK_URGENT_GIB 30). 올라갈 땐 +5Gi(FT_DISK_RECOVER_ADD) 넘어야 내려간다.
#   15분(FT_DISK_PERIOD_SEC)에 한 번만 측정 · 같은 단계 반복: 경고 60분 · 긴급 15분 · 측정 실패 60분. 단계가 바뀌면 즉시.
#   수신자 = planner 명부(seats-planner.json) `_hil_route`(없으면 ERROR rc3 — 경보를 옛 이름·다른 좌석으로 대신 보내지 않는다).
#   그때 고장 신호만 하네스 master(seats-harness.json `_master`)에 1시간 1통. 삭제·정리 0 — 알리기만.
#   env(시험용): FT_RES_ROOT · FT_DISK_FREE_GIB(숫자|fail) · FT_DISK_NOW · FT_MBOX_SH · FT_SEATS_JSON · FT_HARNESS_SEATS_JSON · FT_RES_WATCH_SH · FT_SCRATCH_REPO_SH
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_RES_ROOT:-$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"
[ -n "$ROOT" ] || ROOT="$(cd -- "$HERE/../.." && pwd)"
STATE="$ROOT/.fable-team/state"; ST="$STATE/disk-alarm.state"; LOG="$STATE/disk-alarm.log"
MBOX="${FT_MBOX_SH:-$HERE/../comm/mbox.sh}"
WATCH="${FT_RES_WATCH_SH:-$HERE/ft-resource-watch.sh}"
SCRATCH="${FT_SCRATCH_REPO_SH:-$HERE/ft-scratch-repo.sh}"
WARN="${FT_DISK_WARN_GIB:-50}"; URG="${FT_DISK_URGENT_GIB:-30}"; ADD="${FT_DISK_RECOVER_ADD:-5}"; PERIOD="${FT_DISK_PERIOD_SEC:-900}"
NOW="${FT_DISK_NOW:-$(date +%s)}"
mkdir -p "$STATE" 2>/dev/null || { echo "ERROR 상태 폴더 생성 실패: $STATE" >&2; exit 4; }
logline() { printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOG"; }
stget() { sed -n "s/^$1=//p" "$ST" 2>/dev/null | tail -1; }
num() { case "$1" in ''|*[!0-9]*) echo 0;; *) echo "$1";; esac; }

last=$(num "$(stget last)"); stage="$(stget stage)"; [ -n "$stage" ] || stage=ok; sent=$(num "$(stget sent)"); rf=$(num "$(stget routefail)"); swept=$(num "$(stget swept)")
[ $((NOW-last)) -ge "$PERIOD" ] || [ "$last" = 0 ] || exit 0
save() { printf 'last=%s\nstage=%s\nsent=%s\nswept=%s\nroutefail=%s\n' "${2:-$NOW}" "$1" "$sent" "$swept" "$rf" > "$ST"; }
jget() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2" 2>/dev/null; }

free="${FT_DISK_FREE_GIB:-$(df -Pk /System/Volumes/Data 2>/dev/null | awk 'NR==2 && $4+0>0{print int($4/1048576)}')}"
SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats-planner.json}"; ROUTE="$(jget "$SEATS" _hil_route)"
if [ -z "$ROUTE" ]; then # 경보 대신 고장 신호만 하네스 master 에 — 명부가 고쳐지면 다음 틱에 바로 정상 경로(last 유지)
  logline "ERROR _hil_route 없음 — 쪽지 수신자 불명 ($SEATS)"; echo "ERROR disk-alarm: 명부에 _hil_route 없음 ($SEATS)" >&2
  HM="$(jget "${FT_HARNESS_SEATS_JSON:-$ROOT/.fable-team/seats-harness.json}" _master)"
  if [ -z "$HM" ]; then logline "ERROR 하네스 명부 _master 없음 — 고장 신호도 못 보냄"
  elif [ $((NOW-rf)) -ge 3600 ]; then
    case "$free" in ''|*[!0-9]*) fv=미상;; *) fv="${free}Gi";; esac
    if bash "$MBOX" send "$HM" ft-disk-alarm "[디스크 경보 수신자 없음] $SEATS 에 _hil_route 없음 — 디스크 경보가 planner 에 못 감 · 여유 $fv" >/dev/null 2>>"$LOG"; then rf=$NOW
    else logline "ERROR 고장 쪽지 발신 실패 to=$HM"; fi
  fi
  save "$stage" "$last"; exit 3
fi

case "$free" in ''|*[!0-9]*) new=fail;;
  *) if [ "$free" -lt "$URG" ]; then new=urgent
     elif [ "$stage" = urgent ] && [ "$free" -lt $((URG+ADD)) ]; then new=urgent
     elif [ "$free" -lt "$WARN" ]; then new=warn
     elif [ "$stage" = warn ] && [ "$free" -lt $((WARN+ADD)) ]; then new=warn
     else new=ok; fi;; esac

causes() { # 증가 상위 3 — watch scan 의 «직전 스냅샷 대비» 절
  local c; c="$(bash "$WATCH" scan 2>/dev/null | awk '/^== /{s=($0 ~ /직전/); next} s && NF>=2 && $2 ~ /^\+/ && n<3 {printf "%s%s %s", (n?", ":""), $1, $2; n++}')"
  printf '%s' "${c:-원인 미상}"
}
orphans() { local o; o="$(bash "$SCRATCH" --report --summary 2>/dev/null)"; [ -z "$o" ] || printf ' · %s' "$o"; }
post() { # 본문 → planner. 실패면 상태를 안 바꾼다(다음 틱 재시도)
  bash "$MBOX" send "$ROUTE" ft-disk-alarm "$1" >/dev/null 2>>"$LOG" && { sent=$NOW; return 0; }
  logline "ERROR 쪽지 발신 실패 to=$ROUTE"; return 1
}
sweep() { # 하루 1회 주인 없는 사본 정리(판정 1920 · 첫 1회는 목록 보고만) — 결과 1줄을 planner 로. 디스크 단계 반복 타이머(sent)와 무관
  [ $((NOW-swept)) -ge 86400 ] || return 0; local s; s="$(bash "$SCRATCH" --sweep 2>>"$LOG")"; swept=$NOW
  [ -z "$s" ] || bash "$MBOX" send "$ROUTE" ft-disk-alarm "$s" >/dev/null 2>>"$LOG" || logline "ERROR 사본 정리 쪽지 발신 실패"
}

gap=$((NOW-sent)); body=""
case "$new" in
  ok)     [ "$stage" = ok ] || { [ "$stage" = fail ] || body="[디스크 회복] 여유 ${free}Gi — 경보 해제"; };;
  warn)   if [ "$stage" != warn ] || [ "$gap" -ge 3600 ]; then body="[디스크 경고] 여유 ${free}Gi · 상위 3: $(causes)$(orphans)"; fi;;
  urgent) if [ "$stage" != urgent ] || [ "$gap" -ge "$PERIOD" ]; then body="[디스크 긴급] 여유 ${free}Gi · 상위 3: $(causes)$(orphans)"; fi;;
  fail)   logline "ERROR df 측정 실패 free='${free}'"
          if [ "$stage" != fail ] || [ "$gap" -ge 3600 ]; then body="[디스크 측정 실패] df 값을 못 읽음 — 여유 미상(충분하다는 뜻 아님)"; fi;;
esac
if [ -n "$body" ]; then post "$body" || exit 3; fi
sweep
save "$new"
exit 0
