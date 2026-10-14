#!/usr/bin/env bash
# ft-wt-sweep.sh [--dry-run | --finish <포인터>]  — 닫힌 나노의 워크트리 정리 계획(.fable-team/state/wt-clean/<seat>.sh)을 «세션이 사라진 뒤» 실행한다.
#   하네스 0.5 행 2 r2~r4 (DA r1 조건 1 · DA r2 조건 2 · DA r3 MAJOR N1): close 는 계획을 «생성만» 하고, 실행은 이 sweep(또는 close --kill 성공 뒤)에서만.
#   ★호출처(r3 배선)★: ft-tick.sh 의 pass() 가 매 루프(60s) `sweep_wt()` 로 이 스크립트를 부른다(FT_TICK_WT_SWEEP=0 으로 끔). 수동 호출도 같은 진입점.
#   계획 스크립트 자신이 가드(계보 세션 자기 포함 0 · cwd 보유 프로세스 0 · branch nano/* · HEAD=branch 도달성 · 실작업물 0 · ignored 보관 · 도구 실패=skipped)와 원장 표식을 담당한다.
#   결과: cleaned|none → <seat>.sh.done · skipped:좌석/cwd → WAIT(제자리 · 다음 sweep) · 그 외 skipped → ★<seat>.sh.hil 로 이동 + [HIL] 1줄 «1회»★(호출자가 mbox 로 올린다 ·
#   사람이 .hil 을 .sh 로 되돌리면 재시도). 계획 1건당 FT_WT_PLAN_TIMEOUT(기본 120s) — 초과는 skipped:timeout 으로 .hil(MINOR b).
#   ★r-wt-sweep-route-timeout★ ①초과는 rc 124 정직(perl 이 자기 TERM 을 무시) ②baton 머리줄이 로그에 있는 «삭제 단계» 초과는 WAIT + <계획>.tmo 연속 카운트(FT_WT_SWEEP_TMO_MAX=3 회면 HIL)
#   ③pass 1회에 계획 FT_WT_SWEEP_MAX(기본 1)건만(좌석·cwd WAIT 는 안 센다) ④[HIL] 줄은 «seat=<좌석>» 을 담는다(호출자가 팀 master 로 라우팅).
#   ★r166 2단 정리★ 생성기 계획은 «이름 바꾸기(즉시) → 분리 프로세스 정리» 로 끝난다(상한 TERM 이 삭제 도중 걸려도 원래 경로엔 껍데기 0).
#   ⓐ분리 정리 = `--finish <계획>.deleting`(포인터: 1행 이름 바뀐 경로 · 2행 리포 루트) — baton 보관+삭제 → prune. 끝나지 않은 포인터는 매 pass 가 이어서 다시 건다(⓶ 이어정리 · 실패 FT_WT_FINISH_MAX=3 회면 HIL).
#   ⓑ계획 머리 `# plan-ver:` ≠ 옆의 라이브 생성기(ft-nano-close.sh blob sha) = 실행 거부(.stale 로 이동 + STALE 1줄). 머리 표식이 없어도 생성기 계획(`# wt-clean 계획 — ft-nano-close.sh`)이면 옛 판으로 거부. 생성기 계획이 아닌 것(수동·스텁)은 대상 아님.
#   ⓒ껍데기 경보 = 반쯤 지워진 워크트리(tracked 최상위 항목 2개 이상 부재 · 포인터 없는 .deleting-*)의 목록을 «바뀐 때만» [HIL] 1줄(FT_WT_SHELL_SCAN_SEC 간격 · 기본 600s).
#   실행 위치 무관(원장·워크트리는 계획에 절대경로로 박혀 있다). FT_WT_AUTOCLEAN=0 이면 아무것도 실행하지 않는다.
set -uo pipefail
SELF="$(cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")"
BATON="${BATON_BIN:-$HOME/.baton/current/bin/baton}"

# has_tar <리포 루트> <워크트리 경로> — baton archive(<루트>/.baton/archive/INDEX.jsonl)에 이 경로의 행이 있고 그 tar.gz 가 실재·읽힐 때 0.
has_tar() {
  python3 - "$1/.baton/archive" "$2" <<'PY'
import json, os, sys, tarfile
d, wt = sys.argv[1:3]
try: lines = open(os.path.join(d, "INDEX.jsonl"), encoding="utf-8").read().splitlines()
except OSError: sys.exit(1)
for l in lines:
    try: r = json.loads(l)
    except ValueError: continue
    if r.get("worktree") != wt: continue
    p = os.path.join(d, r.get("id", "") + ".tar.gz")
    try:
        if os.path.getsize(p) > 0 and tarfile.is_tarfile(p):
            with tarfile.open(p) as t: t.getmembers()
            sys.exit(0)
    except (OSError, tarfile.TarError): pass
sys.exit(1)
PY
}
# --finish <포인터> — 이름 바뀐 워크트리(.deleting-<ts>)를 상한 밖에서 끝까지 정리. rc 0 = 끝 · 1 = 남음(포인터·실패 횟수 유지).
finish_one() {
  local ptr="$1" del root f rc
  del="$(sed -n 1p "$ptr" 2>/dev/null)"; root="$(sed -n 2p "$ptr" 2>/dev/null)"
  case "${del##*/}" in *.deleting-[0-9]*) ;; *) echo "REJECT 이름 안전장치 — .deleting-<ts> 아님: ${del:-<빈 값>}" >&2; return 1;; esac
  [ -n "$root" ] && [ -d "$root" ] || { echo "REJECT 리포 루트 없음: ${root:-<빈 값>}" >&2; return 1; }
  echo $$ > "$ptr.pid"
  if [ -d "$del" ]; then
    # ★잔여 삭제는 «검증된 보관 tar» 가 있을 때만★(marker 유무와 무관 — 흔적 없음 ≠ 이미 보관됨). 증거 = baton 이 쓰는 INDEX.jsonl 의 이 경로 행 + 실재하는 tar.gz.
    # 증거가 없으면 먼저 baton 으로 «보관+삭제» 를 시도하고, 그 뒤에도 워크트리가 남았는데 증거가 없으면(보관 실패) 지우지 않는다 — 남기고 다음 pass 재시도.
    if ! has_tar "$root" "$del"; then
      ( cd "$root" && BATON_TMUX_DISABLE=true "$BATON" wt-clean "$del" ); rc=$?
      if [ -d "$del" ] && { [ "$rc" -ne 0 ] || ! has_tar "$root" "$del"; }; then echo "보관 tar 확인 불가(baton rc=$rc) — 삭제 보류: $del" >&2
        f=$(( $(cat "$ptr.fail" 2>/dev/null || echo 0) + 1 )); echo "$f" > "$ptr.fail"; rm -f "$ptr.pid"; return 1; fi
    fi
    # 여기 도달 = 검증된 보관 있음(또는 baton 이 이미 지움). baton 이 남긴 잔여·반쯤 지워진 껍데기: git 이 알면 git 으로, 아니면 직접 마무리.
    [ ! -d "$del" ] || git -C "$root" worktree remove --force "$del" 2>/dev/null
    [ ! -d "$del" ] || rm -rf -- "$del"
  fi
  git -C "$root" worktree prune 2>/dev/null
  rm -f "$ptr.pid"
  if [ -d "$del" ]; then
    f=$(( $(cat "$ptr.fail" 2>/dev/null || echo 0) + 1 )); echo "$f" > "$ptr.fail"; echo "정리 후에도 남음: $del" >&2; return 1
  fi
  rm -f "$ptr" "$ptr.fail"; echo "FINISH OK ${del##*/}"
}
if [ "${1:-}" = "--finish" ]; then [ -n "${2:-}" ] && [ -f "$2" ] || { echo "usage: $0 --finish <포인터 파일>" >&2; exit 2; }; finish_one "$2"; exit $?; fi

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
[ "${FT_WT_AUTOCLEAN:-1}" != 0 ] || { echo "FT_WT_AUTOCLEAN=0 — sweep 실행 안 함"; exit 0; }
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
DIR="${FT_WT_CLEAN_DIR:-${ROOT:-$WT}/.fable-team/state/wt-clean}"
TMO="${FT_WT_PLAN_TIMEOUT:-120}"
MAX="${FT_WT_SWEEP_MAX:-1}"          # pass 1회에 실행하는 계획 수(좌석 WAIT 는 세지 않는다) — 틱 pass 를 계획 N×상한 동안 붙잡지 않는다
TMO_MAX="${FT_WT_SWEEP_TMO_MAX:-3}"  # 삭제 단계 초과가 «연속» 이 횟수가 되면 사람 판정(HIL)
FIN_MAX="${FT_WT_FINISH_MAX:-3}"     # 이름 바뀐 워크트리의 분리 정리가 «연속 실패» 한 횟수가 되면 사람 판정(HIL)
GRACE="${FT_WT_RESUME_GRACE:-20}"    # 막 만든 포인터는 이 초 동안 이어정리 대상이 아니다(계획이 방금 건 분리 정리와 겹치지 않게)
SCAN_SEC="${FT_WT_SHELL_SCAN_SEC:-600}"
SCAN_ROOT="${FT_WT_SCAN_ROOT:-$ROOT}"
GEN="$(dirname "$0")/ft-nano-close.sh"
BATON_HDR='워크트리 정리 — Archive'   # baton wt-clean 머리줄 — 이게 로그에 있으면 계획이 가드를 지나 «삭제 단계» 까지 갔다
# 계획 1건을 타임아웃 아래 실행 — perl alarm(macOS 기본엔 timeout(1) 이 없다). 새 프로세스 그룹으로 띄워 초과 시 «그룹 전체»(bash·tar·baton 자식) TERM. rc 는 계획의 것 · 초과 = 124.
#   perl 자신이 그 그룹의 리더라 TERM 을 무시해야 exit 124 까지 간다(안 그러면 자기도 죽어 rc 143 = «실행 실패» 오분류).
run_plan() { perl -e 'setpgrp(0,0); $SIG{ALRM}=sub{ local $SIG{TERM}="IGNORE"; kill "TERM", -$$; exit 124 }; alarm shift; my $r=system(@ARGV); exit(($r>>8) || (($r&127) ? 128+($r&127) : 0));' "$TMO" /bin/bash "$1"; }
HB="$(dirname "$0")/ft-hil.sh"  # R83: 사람 ! 실행 안내 = 짧은 링크(`! bash /tmp/h<N>`) — 옆의 ft-hil.sh 가 없거나 실패면 지금 문구 그대로 + WARN
hilmsg() { local m=""; command -v "$HB" >/dev/null 2>&1 && m="$("$HB" --add "$1" 2>/dev/null | tail -1)"; [ -n "$m" ] && echo "$m" || { echo "WARN ft-hil 실패 — 경로 안내로 후퇴" >&2; echo "스크립트 $1"; }; }
# 분리 정리 — 새 세션(setsid)으로 떼어 낸다: run_plan 의 그룹 TERM·틱 pass 의 종료와 무관하게 끝까지 돈다. 표준출력은 파일로 — 파이프를 쥐고 있으면 호출자가 안 돌아온다.
launch_finish() { ( cd "$2" && perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' /bin/bash "$SELF" --finish "$1" >> "$1.log" 2>&1 < /dev/null & ); }
# 계획 버전 대조 — 0 통과 · 1 거부(사유 stdout). 생성기 계획이 아닌 것(수동·스텁)은 대상 아님.
plan_ver_check() {
  local pv lv
  pv="$(sed -n 's/^# plan-ver: //p' "$1" | head -1)"
  if [ -z "$pv" ]; then grep -q '^# wt-clean 계획 — ft-nano-close.sh' "$1" || return 0; fi
  lv=""; [ -f "$GEN" ] && lv="$(git hash-object -- "$GEN" 2>/dev/null)"
  [ -n "$pv" ] && [ "$pv" = "$lv" ] && return 0
  echo "plan-ver=${pv:-없음} ≠ 라이브 생성기=${lv:-없음}"; return 1
}
n=0; c=0; w=0; h=0; d=0; ran=0; st=0; rs=0
for plan in "$DIR"/*.sh; do
  [ -f "$plan" ] || continue
  seat="$(basename "$plan" .sh)"
  if [ "$DRY" = 1 ]; then n=$((n+1)); echo "DRY $seat — $plan"; continue; fi
  why="$(plan_ver_check "$plan")" || { st=$((st+1)); mv "$plan" "$plan.stale"; echo "STALE $seat — 옛 생성기 계획 실행 거부($why) · 재생성: ft-nano-close.sh $seat 를 다시 돌려 새 계획을 만든다(옛 계획 $plan.stale)"; continue; }
  if [ "$ran" -ge "$MAX" ]; then d=$((d+1)); continue; fi
  n=$((n+1))
  run_plan "$plan" > "$plan.log" 2>&1; rc=$?; res="$(tail -1 "$plan.log")"   # 파일로 받는다 — 파이프 캡처는 고아 자식이 잡고 있으면 타임아웃 뒤에도 안 돌아온다
  [ "$rc" -ne 124 ] || res="skipped:timeout ${TMO}s"
  case "$res" in skipped:좌석*|skipped:cwd*) ;; *) ran=$((ran+1));; esac
  tmo="$plan.tmo"
  if [ "$rc" -eq 124 ] && grep -qF -- "$BATON_HDR" "$plan.log"; then
    # 삭제 단계 초과 = 사람 판정이 아니라 재시도(계획은 재실행 안전 — 반쯤 지워졌으면 baton 이 이어서 지운다). 연속 TMO_MAX 회면 HIL.
    t=$(( $(cat "$tmo" 2>/dev/null || echo 0) + 1 ))
    if [ "$t" -ge "$TMO_MAX" ]; then h=$((h+1)); rm -f "$tmo"; mv "$plan" "$plan.hil"; echo "[HIL] seat=$seat 삭제 단계 시간 초과 ${t}회 연속(${TMO}s) · $(hilmsg "$plan.hil") (로그 $plan.log)"
    else w=$((w+1)); echo "$t" > "$tmo"; echo "WAIT $seat 삭제 단계 시간 초과 ${t}/${TMO_MAX} — 다음 sweep 재시도"; fi
    continue
  fi
  rm -f "$tmo"   # 초과 외의 결과는 «연속» 을 끊는다
  case "$res" in
    cleaned*|none) c=$((c+1)); mv "$plan" "$plan.done"; echo "OK   $seat wt=$res";;
    skipped:좌석*|skipped:cwd*) w=$((w+1)); echo "WAIT $seat ${res#skipped:}";;
    skipped:*) h=$((h+1)); mv "$plan" "$plan.hil"; echo "[HIL] seat=$seat ${res#skipped:} · $(hilmsg "$plan.hil")";;
    *) h=$((h+1)); mv "$plan" "$plan.hil"; echo "[HIL] seat=$seat 실행 실패(rc=$rc: ${res:-출력 없음}) · $(hilmsg "$plan.hil") (로그 $plan.log)";;
  esac
done
# 이어정리 — 이름 바뀐 워크트리(.deleting-<ts>)의 분리 정리가 안 끝났으면(프로세스 없음) 다시 건다. 연속 실패가 FIN_MAX 회면 HIL.
for ptr in "$DIR"/*.deleting; do
  [ -f "$ptr" ] || continue
  seat="$(basename "$ptr")"; seat="${seat%.deleting}"; seat="${seat%.hil}"; seat="${seat%.sh}"
  if [ "$DRY" = 1 ]; then echo "DRY 이어정리 $seat — $ptr"; continue; fi
  pid="$(cat "$ptr.pid" 2>/dev/null)"; { [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; } && continue
  [ $(( $(date +%s) - $(stat -f %m "$ptr" 2>/dev/null || echo 0) )) -ge "$GRACE" ] || continue
  f="$(cat "$ptr.fail" 2>/dev/null || echo 0)"
  if [ "$f" -ge "$FIN_MAX" ]; then h=$((h+1)); mv "$ptr" "$ptr.hil"; echo "[HIL] seat=$seat 이름 바뀐 워크트리 정리 ${f}회 연속 실패 · $(sed -n 1p "$ptr.hil") (로그 $ptr.log)"; continue; fi
  rs=$((rs+1)); launch_finish "$ptr" "$(sed -n 2p "$ptr")"; echo "RESUME $seat $(sed -n 1p "$ptr")"
done
# 껍데기 경보 — 반쯤 지워진 워크트리 목록을 «바뀐 때만» 1줄. 부하 때문에 SCAN_SEC 간격으로만 훑는다.
shell_scan() {
  local stamp="$DIR/.shell-scan.stamp" sigf="$DIR/.shell-sig" now sig="" list="" p sha name missing cnt=0 live
  [ "$DRY" != 1 ] && [ -n "$SCAN_ROOT" ] && [ -d "$SCAN_ROOT" ] && [ -d "$DIR" ] || return 0
  now="$(date +%s)"; [ $(( now - $(cat "$stamp" 2>/dev/null || echo 0) )) -ge "$SCAN_SEC" ] || return 0
  echo "$now" > "$stamp"
  live="$(for f in "$DIR"/*.deleting; do [ -f "$f" ] && sed -n 1p "$f"; done)"
  while IFS=$'\t' read -r p sha; do
    case "$p" in "$SCAN_ROOT"/.worktrees/*) ;; *) continue;; esac
    [ -d "$p" ] || continue
    case "${p##*/}" in
      *.deleting-[0-9]*) printf '%s\n' "$live" | grep -qxF -- "$p" && continue; missing=9;;
      *) missing=0
         while IFS= read -r name; do [ -e "$p/$name" ] || missing=$((missing+1)); done < <(git -C "$SCAN_ROOT" ls-tree --name-only "$sha" 2>/dev/null);;
    esac
    [ "$missing" -ge 2 ] || continue
    list="$list${p##*/} "; cnt=$((cnt+1))
  done < <(git -C "$SCAN_ROOT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{p=substr($0,10)} /^HEAD /{print p "\t" substr($0,6)}')
  sig="$(printf '%s' "$list" | tr ' ' '\n' | sort | tr '\n' ' ')"
  if [ -z "$sig" ]; then rm -f "$sigf"; return 0; fi
  [ "$sig" = "$(cat "$sigf" 2>/dev/null)" ] && return 0
  printf '%s' "$sig" > "$sigf"
  echo "[HIL] 반쯤 지워진 워크트리 껍데기 ${cnt}곳: ${sig% } — 처리는 오빠 값(바뀐 때만 1줄)"
}
shell_scan
echo "sweep 계획 $n · cleaned/none $c · wait $w · hil $h$([ "$d" -gt 0 ] && echo " · 이월 $d")$([ "$st" -gt 0 ] && echo " · stale $st")$([ "$rs" -gt 0 ] && echo " · 이어정리 $rs")"
