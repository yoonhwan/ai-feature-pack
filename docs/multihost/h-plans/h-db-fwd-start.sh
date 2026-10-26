#!/usr/bin/env bash
# h-db-fwd-start.sh — h1b: 14시간 격리 관찰이 끝난 뒤 포워더 VM byz-db-fwd 를 1회 켜서 길을 복구한다 (카드 하나 §6 h1b)
#   (2026-10-26 · aifp-multihost-arch-claude#2 초안 r2 · 발주 #3313/#3315 · DA 델타 r1 #1·#5 반영 · 실행은 오빠 `! bash /tmp/h<N>` · DRY=1 기본 = 읽기만)
#   하는 일: ① 상태가 TERMINATED 인지(= Google 이 스스로 꺼 줬는지) · 꺼진 시각이 «마지막 기동 + 14시간 ±10분» 안인지 판정(관찰 합격)
#              ★기동·정지 시각 중 하나라도 없으면 합격이 아니다(rc 3 · 켜지 않는다) — TERMINATED 만으로는 조기 정지와 정상 만료를 못 가른다★
#           ② DRY=0 이면 instances start --async → RUNNING 폴링(마감 40초) → 새 lastStartTimestamp · 다음 만료 예상 출력
#   바꾸지 않는 것: IAM · 방화벽 · 주소 · 다른 VM. 비밀 0.
# rc: 0 성공 · 2 사전점검 · 3 관찰 불합격(RUNNING 그대로 = 만료가 강제되지 않았다 → ★도입 중단★ · 시각 누락도 3 · 켜지 않는다) · 4 기동 실패
set -uo pipefail
P="${P:-byz-agents-484214}"; A="${A:-developer.ts@byourz.com}"; Z="${Z:-asia-northeast3-a}"
VM="${VM:-byz-db-fwd}"; MAXRUN_SEC="${MAXRUN_SEC:-50400}"; TOL_SEC="${TOL_SEC:-600}"
DRY="${DRY:-1}"
say() { printf '[h1b-db-fwd-start] %s\n' "$*"; }
die() { printf '[h1b-db-fwd-start] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
GT="${GT:-11}"; G() { timeout "$GT" gcloud --account="$A" --project="$P" --quiet "$@"; }
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

say "1/3 상태 조회 (DRY=$DRY)"
command -v gcloud >/dev/null || die 2 "gcloud 없음"
ROW="$(G compute instances describe "$VM" --zone="$Z" --format='value(status,lastStartTimestamp,lastStopTimestamp,scheduling.maxRunDuration.seconds,scheduling.instanceTerminationAction)' 2>/dev/null)" || die 2 "$VM 조회 실패(h1 이 아직 안 돌았나)"
ST="$(printf '%s' "$ROW" | cut -f1)"; LST="$(printf '%s' "$ROW" | cut -f2)"; LSP="$(printf '%s' "$ROW" | cut -f3)"; MR="$(printf '%s' "$ROW" | cut -f4)"; TA="$(printf '%s' "$ROW" | cut -f5)"
say "        status=$ST lastStart=$LST lastStop=$LSP maxRun=$MR action=$TA"
[ "$MR" = "$MAXRUN_SEC" ] && [ "$TA" = STOP ] || die 2 "만료 설정이 기대와 다르다(maxRun=$MR action=$TA)"

say "2/3 관찰 판정: 꺼진 시각 − 마지막 기동 = 14시간 ±$((TOL_SEC/60))분 인가"
case "$ST" in
  TERMINATED|STOPPED) ;;
  RUNNING) die 3 "★도입 중단★ VM 이 아직 RUNNING — Google 만료가 강제되지 않았다(관찰 시작 뒤 14시간이 안 지났으면 기다렸다 다시 · 지났으면 설계 재검토 · 되돌림은 h1 끝 줄)" ;;
  *) die 2 "예상 밖 상태 $ST(STOPPING·STAGING 이면 1~2분 뒤 다시)" ;;
esac
[ -n "$LST" ] && [ -n "$LSP" ] || die 3 "관찰 증거 부족 — 기동/정지 시각이 비어 있다(lastStart='$LST' lastStop='$LSP') · TERMINATED 만으로는 합격이 아니다 · 켜지 않는다"
VERDICT="$(python3 -I - "$LST" "$LSP" "$MAXRUN_SEC" "$TOL_SEC" <<'PY'
import sys, datetime as d
st, sp, mr, tol = sys.argv[1:5]
p = lambda s: d.datetime.fromisoformat(s.replace("Z","+00:00"))
dur = (p(sp)-p(st)).total_seconds(); dev = dur-int(mr)
print(("PASS" if abs(dev) <= int(tol) else "FAIL") + f" 가동 {dur/3600:.2f}h 편차 {dev/60:+.1f}분")
PY
)" || die 3 "시각 해석 실패('$LST' / '$LSP')"
say "        관찰 = $VERDICT"
case "$VERDICT" in PASS*) ;; *) die 3 "관찰 불합격 — 손으로 꺼졌거나(h1 뒤 누가 stop 했나) 만료 시계가 기대와 다르다. 켜지 않는다";; esac

say "3/3 기동"
if [ "$DRY" = 1 ]; then say "DRY — 할 예정: gcloud compute instances start $VM --zone=$Z --async → RUNNING 마감 50초(회차 = sleep 5 + 조회 ≤ 11 · 남은 시간이 16초 미만이면 더 돌지 않음) → 새 lastStart·다음 만료 출력"; exit 0; fi
G compute instances start "$VM" --zone="$Z" --async --format=json >"$HOME/.byz-db-fwd-start-op.json" 2>/dev/null || die 4 "start 요청 실패"
say "        반환 객체 → ~/.byz-db-fwd-start-op.json (작업 이름 해석은 추정 · 오류 추적용)"
# 마감 루프(DA 델타 r2 #3): 남은 시간 < sleep+조회 상한 이면 더 돌지 않는다 → 마감을 넘기는 회차 0
poll() { local lim="$1" s="$2" per="$3"; shift 3; local T=$SECONDS left
  while :; do left=$((lim-(SECONDS-T))); [ "$left" -ge $((s+per)) ] || return 1; sleep "$s"; "$@" && return 0; done; }
vm_running() { ST2="$(G compute instances describe "$VM" --zone="$Z" --format='value(status)' 2>/dev/null)"; [ "$ST2" = RUNNING ]; }
ST2=""; poll 50 5 "$GT" vm_running || die 4 "마감 50초 안에 RUNNING 이 아니다(status=${ST2:-?} · 반환 객체 ~/.byz-db-fwd-start-op.json)"
LST2="$(G compute instances describe "$VM" --zone="$Z" --format='value(lastStartTimestamp)' 2>/dev/null)"
EXP="$(python3 -I -c 'import sys,datetime as d; t=d.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")); print((t+d.timedelta(seconds=int(sys.argv[2]))).astimezone().strftime("%Y-%m-%d %H:%M %Z"))' "$LST2" "$MAXRUN_SEC" 2>/dev/null || echo '?')"
say "        RUNNING · lastStart=$LST2 · 다음 자동 만료 예상 $EXP"
say "닫는 증거 2줄: 관찰 $VERDICT · 재기동 OK(lastStart $LST2). 다음 = h2(mini 터널·역방향 포워딩 제거·fail-closed 시험)"
exit 0
