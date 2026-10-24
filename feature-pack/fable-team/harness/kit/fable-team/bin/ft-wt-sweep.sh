#!/usr/bin/env bash
# ft-wt-sweep.sh [--dry-run | --finish <포인터> | --launchd | --land-plan]  — 닫힌 나노의 워크트리 정리 계획(.fable-team/state/wt-clean/<seat>.sh)을 «세션이 사라진 뒤» 실행한다.
#   하네스 0.5 행 2 r2~r4 (DA r1 조건 1 · DA r2 조건 2 · DA r3 MAJOR N1): close 는 계획을 «생성만» 하고, 실행은 이 sweep(또는 close --kill 성공 뒤)에서만.
#   ★호출처(r3 배선)★: ft-tick.sh 의 pass() 가 매 루프(60s) `sweep_wt()` 로 이 스크립트를 부른다(FT_TICK_WT_SWEEP=0 으로 끔). 수동 호출도 같은 진입점.
#   계획 스크립트 자신이 가드(계보 세션 자기 포함 0 · cwd 보유 프로세스 0 · branch nano/* · HEAD=branch 도달성 · 실작업물 0 · ignored 보관 · 도구 실패=skipped)와 원장 표식을 담당한다.
#   결과: cleaned|none → <seat>.sh.done · skipped:좌석/cwd → WAIT(제자리 · 다음 sweep) · 그 외 skipped → ★<seat>.sh.hil 로 이동 + [HIL] 1줄 «1회»★(호출자가 mbox 로 올린다 ·
#   사람이 .hil 을 .sh 로 되돌리면 재시도). 계획 1건당 FT_WT_PLAN_TIMEOUT(기본 120s) — 초과는 skipped:timeout 으로 .hil(MINOR b).
#   ★r-wt-sweep-route-timeout★ ①초과는 rc 124 정직(perl 이 자기 TERM 을 무시) ②baton 머리줄이 로그에 있는 «삭제 단계» 초과는 WAIT + <계획>.tmo 연속 카운트(FT_WT_SWEEP_TMO_MAX=3 회면 HIL)
#   ③(r535 개정) pass 1회 = 시간 상한 FT_WT_SWEEP_BUDGET_SEC(기본 90 · 계획 1건 상한은 그대로) 안에서 막히지 않은 계획을 차례로 · FT_WT_SWEEP_MAX 는 명시할 때만 건수 상한(기본 0 = 없음 · 좌석·cwd WAIT 는 안 센다)
#   ④[HIL] 줄은 «seat=<좌석>» 을 담는다(호출자가 팀 master 로 라우팅).
#   ★r535★ ⓐ옛 판 계획 = 거부 전에 옆 생성기 `--replan` 으로 같은 좌석·같은 WT 계획 재생성(옛 파일 .replanned · REPLAN 1줄) → 같은 pass 에 실행 · 계보 세션 살아 있음 = WAIT(제자리) · 불가 = 지금처럼 .stale + 사유
#     ⓑ실행 직전 WT 크기 `du -sk`(FT_WT_DU_SEC 기본 5 상한 · 넘으면 ? · <계획>.kb 캐시) → cleaned 면 .done 끝 `# freed_kb=` · <state>/wt-sweep.log 폴더별 `freed seat= kb=` + pass 줄 끝 `freed_kb=<합>`
#     ⓒ등록 없는 폴더(<SCAN_ROOT>/.worktrees/* 인데 git worktree list 에 없음) → <state>/wt-orphans.tsv(이름·mtime·크기) 목록만(FT_WT_ORPHAN_SCAN_SEC 기본 3600 간격 · 삭제 0) ⓓ.sh.hil 수 → 요약 `hil_files N`(처리 0).
#   ★r166 2단 정리★ 생성기 계획은 «이름 바꾸기(즉시) → 분리 프로세스 정리» 로 끝난다(상한 TERM 이 삭제 도중 걸려도 원래 경로엔 껍데기 0).
#   ⓐ분리 정리 = `--finish <계획>.deleting`(포인터: 1행 이름 바뀐 경로 · 2행 리포 루트) — baton 보관+삭제 → prune. 끝나지 않은 포인터는 매 pass 가 이어서 다시 건다(⓶ 이어정리 · 실패 FT_WT_FINISH_MAX=3 회면 HIL).
#   ⓑ계획 머리 `# plan-ver:` ≠ 옆의 라이브 생성기(ft-nano-close.sh blob sha) = 실행 거부(.stale 로 이동 + STALE 1줄). 머리 표식이 없어도 생성기 계획(`# wt-clean 계획 — ft-nano-close.sh`)이면 옛 판으로 거부. 생성기 계획이 아닌 것(수동·스텁)은 대상 아님.
#   ⓒ껍데기 경보 = 반쯤 지워진 워크트리(tracked 최상위 항목 2개 이상 부재 · 포인터 없는 .deleting-*)의 목록을 «바뀐 때만» [HIL] 1줄(FT_WT_SHELL_SCAN_SEC 간격 · 기본 600s).
#   실행 위치 무관(원장·워크트리는 계획에 절대경로로 박혀 있다). FT_WT_AUTOCLEAN=0 이면 아무것도 실행하지 않는다.
#   ★r444 --launchd★(com.byz.ft-wt-sweep · 일 1회 — 사람 h 0): FT_ROOT 필수 · 그 루트에서 sweep 1회(FT_WT_SWEEP_MAX 기본 20) → [HIL] 줄을 팀 master 우편함으로(ft-tick sweep_wt 와 같은 규칙)
#     → 끝난 가지 재확인(refs/heads/nano/* 최신순 FT_WT_ARCHIVE_MAX 기본 200 · ft-branch-archive.sh · FINISHED 만 refs/archive 로) → 로그 <FT_ROOT>/.fable-team/state/wt-sweep.log 1줄 `cleaned=N wait=N hil=N … archived=N`.
#   ★r444 4b★ 껍데기 경보 [HIL] 은 폴더 주인 팀마다 1줄 `seat=byz-<팀>-wt-shell`(팀 = .worktree-info.json purpose 의 카드 경로 · 명단에 있는 팀만 · 못 정하면 harness) — 호출자가 그 팀 master 로 보낸다.
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
# --launchd — 일 1회 진입. 본체는 같은 스크립트 1회(출력 캡처) · 이 블록은 라우팅·보관 재확인·로그만.
if [ "${1:-}" = "--launchd" ]; then
  [ -n "${FT_ROOT:-}" ] && [ -d "$FT_ROOT" ] || { echo "ERROR --launchd 는 FT_ROOT(리포 루트) 필수: ${FT_ROOT:-<없음>}" >&2; exit 2; }
  cd "$FT_ROOT" || exit 2
  LST="$FT_ROOT/.fable-team/state"; mkdir -p "$LST"
  out="$(FT_WT_SWEEP_BUDGET_SEC="${FT_WT_SWEEP_BUDGET_SEC:-300}" bash "$SELF" 2>&1)"; rc=$?
  [ "${FT_WT_LAND_PLAN:-1}" = 0 ] || out="$out"$'\n'"$(bash "$SELF" --land-plan 2>&1)"   # r880: 착지 끝난 land 사본 정리 계획(삭제 0) · [HIL] 은 목록 바뀐 때만
  printf '%s\n' "$out"
  sm="$(printf '%s\n' "$out" | grep '^sweep 계획 ' | tail -1)"
  num() { local v; v="$(printf '%s' "$sm" | sed -nE "s#.*$1 ([0-9]+).*#\\1#p")"; echo "${v:-0}"; }
  # [HIL] → 팀 master(seat=byz-<팀>- → seats-<팀>.json _master · v65·표기 없음 = seats.json _master · 못 찾음 = harness master + [라우팅 실패])
  MB="${FT_MBOX_SH:-}"; [ -n "$MB" ] || { . "$(dirname "$SELF")/ft-harness-root.sh" 2>/dev/null && MB="$(ft_comm_dir "$(dirname "$SELF")")/mbox.sh"; }
  mjson() { python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1])); m=d.get("_master"); v=d.get(m) if isinstance(m,str) else None
except (OSError,ValueError): sys.exit(0)
print(m if isinstance(v,dict) and not v.get("_replaced_by") else "")' "$1" 2>/dev/null; }
  routed=0; rfail=0
  while IFS= read -r ln; do
    s="$(printf '%s' "$ln" | grep -oE 'seat=[^ ]+' | head -1)"; s="${s#seat=}"; tm=""; hdr=""
    case "$s" in byz-v65-*|ft-v65-*|'') tm=v65;; byz-*) tm="$(printf '%s' "$s" | cut -d- -f2)";; *) tm='?';; esac
    case "$tm" in v65) to="$(mjson "$FT_ROOT/.fable-team/seats.json")";; *) to="$(mjson "$FT_ROOT/.fable-team/seats-$tm.json")";; esac
    [ -n "$to" ] || { hdr="[라우팅 실패 $tm] "; to="$(mjson "$FT_ROOT/.fable-team/seats-harness.json")"; }
    if [ -n "$to" ] && [ -n "$MB" ] && bash "$MB" send "$to" ft-wt-sweep "[HIL] ${hdr}워크트리 정리 사람 판정 — $(printf '%s' "$ln" | cut -c7-200)" --urgent >/dev/null 2>&1; then routed=$((routed+1))
      # ★r880 고침 4★ land 계획 알림이 «실제로 나간 뒤에만» 보냄 표지(.sent ← .sig). 실패면 표지 0 → 다음 pass 재발송.
      case "$ln" in *land-copies.sh.hil*)
        sfl="$(printf '%s' "$ln" | sed -nE 's#.*계획 ([^ ]*land-copies\.sh\.hil).*#\1#p')"
        [ -n "$sfl" ] && [ -f "$sfl.sig" ] && cp "$sfl.sig" "$sfl.sent" 2>/dev/null ;;
      esac
    else rfail=$((rfail+1)); echo "ERROR [HIL] 라우팅 실패(to=${to:-없음} mbox=${MB:-없음}): ${ln:0:120}" >&2; fi
  done < <(printf '%s\n' "$out" | grep '^\[HIL\]')
  # 끝난 가지 재확인 — FINISHED 만 refs/archive 로(삭제 0). 최신 가지부터(새로 끝난 것이 먼저 잡히게)
  AR="$(dirname "$SELF")/ft-branch-archive.sh"; ar=0; ask=0
  if [ -f "$AR" ] && [ "${FT_WT_ARCHIVE:-1}" = 1 ]; then
    while IFS= read -r b; do [ -n "$b" ] || continue
      if bash "$AR" "$b" --repo "$FT_ROOT" >/dev/null 2>&1; then ar=$((ar+1)); else ask=$((ask+1)); fi
    done < <(git -C "$FT_ROOT" for-each-ref --sort=-committerdate --count="${FT_WT_ARCHIVE_MAX:-200}" --format='%(refname:short)' 'refs/heads/nano/')
  fi
  printf '%s rc=%s cleaned=%s wait=%s hil=%s stale=%s carry=%s resume=%s routed=%s route_fail=%s archived=%s archive_skip=%s replanned=%s hil_files=%s orphans=%s freed_kb=%s\n' "$(date '+%F %T')" "$rc" \
    "$(num 'cleaned/none')" "$(num wait)" "$(num hil)" "$(num stale)" "$(num 이월)" "$(num 이어정리)" "$routed" "$rfail" "$ar" "$ask" \
    "$(num replanned)" "$(num hil_files)" "$(num orphans)" "$(num freed_kb)" >> "$LST/wt-sweep.log"
  tail -1 "$LST/wt-sweep.log"; exit "$rc"
fi

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
[ "${FT_WT_AUTOCLEAN:-1}" != 0 ] || { echo "FT_WT_AUTOCLEAN=0 — sweep 실행 안 함"; exit 0; }
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
DIR="${FT_WT_CLEAN_DIR:-${ROOT:-$WT}/.fable-team/state/wt-clean}"
TMO="${FT_WT_PLAN_TIMEOUT:-120}"
MAX="${FT_WT_SWEEP_MAX:-0}"          # 명시할 때만 pass 1회 계획 수 상한(0 = 없음 · 좌석 WAIT 는 세지 않는다)
BUDGET="${FT_WT_SWEEP_BUDGET_SEC:-90}"  # r535: pass 1회 시간 상한 — 넘으면 남은 계획은 이월(계획 1건 상한 TMO 는 그대로) · 틱 pass 를 계획 N×상한 동안 붙잡지 않는다
DU="${FT_DU_BIN:-du}"; DU_SEC="${FT_WT_DU_SEC:-5}"
SLOG="${FT_WT_SWEEP_LOG:-$(dirname "$DIR")/wt-sweep.log}"; ORPH="${FT_WT_ORPHANS_TSV:-$(dirname "$DIR")/wt-orphans.tsv}"
TMO_MAX="${FT_WT_SWEEP_TMO_MAX:-3}"  # 삭제 단계 초과가 «연속» 이 횟수가 되면 사람 판정(HIL)
FIN_MAX="${FT_WT_FINISH_MAX:-3}"     # 이름 바뀐 워크트리의 분리 정리가 «연속 실패» 한 횟수가 되면 사람 판정(HIL)
GRACE="${FT_WT_RESUME_GRACE:-20}"    # 막 만든 포인터는 이 초 동안 이어정리 대상이 아니다(계획이 방금 건 분리 정리와 겹치지 않게)
SCAN_SEC="${FT_WT_SHELL_SCAN_SEC:-600}"
SCAN_ROOT="${FT_WT_SCAN_ROOT:-$ROOT}"
GEN="$(dirname "$0")/ft-nano-close.sh"
BATON_HDR='워크트리 정리 — Archive'   # baton wt-clean 머리줄 — 이게 로그에 있으면 계획이 가드를 지나 «삭제 단계» 까지 갔다
# 계획 1건을 타임아웃 아래 실행 — perl alarm(macOS 기본엔 timeout(1) 이 없다). 새 프로세스 그룹으로 띄워 초과 시 «그룹 전체»(bash·tar·baton 자식) TERM. rc 는 계획의 것 · 초과 = 124.
#   perl 자신이 그 그룹의 리더라 TERM 을 무시해야 exit 124 까지 간다(안 그러면 자기도 죽어 rc 143 = «실행 실패» 오분류).
# ★r608★ 계획 실행 잠금 — 계획 1개(<plan>.run.lock 디렉터리 · 안에 pid)를 «한 실행자만» 잡는다.
#   잡음 = 0 · 다른 실행자가 살아서 돌리는 중 = 1 · 잡고 있던 pid 가 죽었으면(낡은 잠금) mv 로 원자적으로 걷어내고 잡는다(사유 1줄).
#   닫기(ft-nano-close)와 이 주기 정리(sweep)가 같은 계획을 동시에 돌려 같은 .log 를 잘라 쓰던 사건(r608)의 고침 — 판정 꼴·계획 본문 불변.
plan_lock() {
  local lock="$1.run.lock" pid
  if mkdir "$lock" 2>/dev/null; then printf '%s\n' $$ > "$lock/pid"; return 0; fi
  pid="$(cat "$lock/pid" 2>/dev/null)"
  if [ -n "$pid" ] && [ "$pid" != "$$" ] && kill -0 "$pid" 2>/dev/null; then return 1; fi
  mv "$lock" "$lock.stale.$$" 2>/dev/null || return 1   # 원자 이동 — 동시에 걷어내는 쪽이 둘이면 한 쪽만 성공한다
  rm -rf "$lock.stale.$$"
  mkdir "$lock" 2>/dev/null || return 1
  printf '%s\n' $$ > "$lock/pid"
  echo "낡은 잠금 걷음(pid=${pid:-없음} · 살아 있는 실행자 없음): $1"
  return 0
}
plan_unlock() { rm -rf "$1.run.lock"; }
run_plan() { perl -e 'setpgrp(0,0); $SIG{ALRM}=sub{ local $SIG{TERM}="IGNORE"; kill "TERM", -$$; exit 124 }; alarm shift; my $r=system(@ARGV); exit(($r>>8) || (($r&127) ? 128+($r&127) : 0));' "$TMO" /bin/bash "$1"; }
HB="${FT_HIL_BIN:-$(dirname "$0")/ft-hil.sh}"  # R83: 사람 ! 실행 안내 = 짧은 링크(`! bash /tmp/h<N>`) — 옆의 ft-hil.sh 가 없거나 실패면 지금 문구 그대로 + WARN
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
# r535 옛 판 재생성 — 옛 계획을 .replanned 로 비켜 두고 옆 생성기 --replan 으로 같은 자리(<seat>.sh)에 새 계획. rc 0 = 새 계획 · 4 = WAIT(옛 계획 제자리) · 그 밖 = 실패(옛 계획 제자리 · 호출자가 .stale).
replan_one() {
  local out rc
  [ -f "$GEN" ] || { echo "생성기 없음($GEN)"; return 1; }
  mv "$1" "$1.replanned" || { echo "옛 계획 비키기 실패"; return 1; }
  out="$(FT_WT_CLEAN_DIR="$DIR" bash "$GEN" "$2" --replan "$1.replanned" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ -f "$1" ] && plan_ver_check "$1" >/dev/null; then return 0; fi
  rm -f "$1"; mv "$1.replanned" "$1"
  echo "$(printf '%s\n' "$out" | grep -E '^(REJECT|WAIT|ERROR|usage)' | tail -1 | cut -c1-200)"; [ "$rc" -eq 4 ] && return 4; return 1
}
# 실행 직전 WT 크기(KB) — du 상한(DU_SEC · perl alarm) · 넘김·실패 = ? · <계획>.kb 캐시(WAIT 로 매 pass 다시 재지 않게)
size_kb() {
  local wt v
  [ -f "$1.kb" ] && { cat "$1.kb"; return; }
  wt="$( (eval "$(grep -m1 '^SEAT=' "$1")" 2>/dev/null; printf '%s' "${WT:-}") 2>/dev/null)"   # 굽힌 값 줄만 서브셸에서 읽는다(신뢰 경계 = 실행할 계획 파일 자체)
  [ -n "$wt" ] && [ -d "$wt" ] || return 0
  # 그룹째 TERM(run_plan 과 같은 꼴) — 자식이 출력 파이프를 쥔 채 남아 $(…) 가 안 돌아오는 일 0
  v="$(perl -e 'setpgrp(0,0); $SIG{ALRM}=sub{ local $SIG{TERM}="IGNORE"; kill "TERM", -$$; exit 124 }; alarm shift; exit(system(@ARGV)>>8)' "$DU_SEC" "$DU" -sk "$wt" 2>/dev/null | awk 'NR==1{print $1}')"
  case "$v" in ''|*[!0-9]*) v='?';; esac
  echo "$v" > "$1.kb"; echo "$v"
}
# ★r880 --land-plan★ 착지용 사본(<SCAN_ROOT>/.worktrees/land-*)이 착지 뒤 영원히 남던 것의 «닫는 사건». 지우지 않는다 — 지워도 되는 사본 목록 → 계획 1개(<DIR>/land-copies.sh.hil) · 실행 = 오빠 h.
#   대상 = ①HEAD 가 FT_WT_LAND_REF(기본 origin/main) 조상 ②미커밋 0(추적 밖 파일 포함) ③그 폴더 안에 cwd 를 둔 프로세스·tmux pane 0 — 셋 다. 잠김·나머지 = KEEP + 이유 1줄.
#   계획은 같은 검사 함수(declare -f)를 품고 지우기 직전 다시 잰다(HEAD = 만든 때 sha 여야 · 낡은 목록으로 지우는 길 0) · 지우기 = git worktree remove(--force 0).
LAND_REF="${FT_WT_LAND_REF:-origin/main}"; LAND_GLOB="${FT_WT_LAND_GLOB:-land-*}"
LSOFB="${FT_LSOF_BIN:-/usr/sbin/lsof}"; TMUXB="${FT_TMUX_BIN:-$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)}"
# land_live — 살아 있는 cwd·pane 경로 → LIVE. 못 읽으면 1(비어 있음 ≠ 못 읽음 — 호출자는 목록 전체를 건너뛴다)
land_live() {
  local lo lrc tp trc
  [ -x "$LSOFB" ] || { echo "lsof 실행 불가($LSOFB)"; return 1; }
  lo="$(cd / && "$LSOFB" -Fn -d cwd 2>/dev/null)"; lrc=$?
  [ -n "$lo" ] || [ "$lrc" -eq 0 ] || { echo "lsof 실패(rc=$lrc)"; return 1; }
  tp="$("$TMUXB" list-panes -a -F '#{pane_current_path}' 2>&1)"; trc=$?
  # ★r880 고침 2(DA r1 반례 2)★ rc≠0 에서 «좌석 0» 으로 읽는 것은 «no server running» 하나뿐 — 권한·연결 오류는 «모르는 상태» 라 호출자가 계획 생성을 중단한다(모르면 안 지움). 오류 글자는 stderr 로 그대로 남긴다.
  if [ "$trc" -ne 0 ]; then case "$tp" in *'no server running'*) tp="";; *) printf '%s\n' "$tp" >&2; echo "tmux 목록 실패(rc=$trc)"; return 1;; esac; fi
  LIVE="$( { printf '%s\n' "$lo" | sed -n 's/^n//p'; printf '%s\n' "$tp"; } | sort -u)"
}
# land_check <리포> <사본> <만든 때 sha|빈 값> — 0 = 지워도 됨(stdout HEAD sha) · 1 = 남김(stdout 이유 1줄). LIVE·LAND_REF 를 쓴다.
land_check() {
  local root="$1" p="$2" want="$3" h m st rp
  h="$(git -C "$p" rev-parse --verify HEAD 2>/dev/null)" || { echo "HEAD 읽기 실패"; return 1; }
  [ -z "$want" ] || [ "$h" = "$want" ] || { echo "HEAD 바뀜(${h:0:12} ≠ 계획 ${want:0:12})"; return 1; }
  m="$(git -C "$root" rev-parse --verify "$LAND_REF^{commit}" 2>/dev/null)" || { echo "$LAND_REF 없음"; return 1; }
  git -C "$root" merge-base --is-ancestor "$h" "$m" || { echo "미착지 — HEAD ${h:0:12} 가 $LAND_REF 조상 아님"; return 1; }
  st="$(git -C "$p" status --porcelain 2>/dev/null)" || { echo "상태 읽기 실패"; return 1; }
  [ -z "$st" ] || { echo "미커밋 $(printf '%s\n' "$st" | wc -l | tr -d ' ')줄"; return 1; }
  rp="$(cd "$p" && pwd -P)"
  if printf '%s\n' "$LIVE" | awk -v a="$p" -v b="$rp" '$0==a||$0==b||index($0,a"/")==1||index($0,b"/")==1{f=1} END{exit !f}'; then echo "좌석·프로세스 살아 있음(cwd/pane 이 안에)"; return 1; fi
  echo "$h"
}
land_plan() {
  local out="$DIR/land-copies.sh.hil" tmp wl p lk h kb n=0 tk=0 new sig w
  [ -n "$SCAN_ROOT" ] && [ -d "$SCAN_ROOT" ] || { echo "ERROR --land-plan 리포 루트 없음: ${SCAN_ROOT:-<빈 값>}" >&2; return 2; }
  h="$(land_live)" || { echo "ERROR land 목록 건너뜀 — $h(살아 있는 좌석을 못 읽으면 목록 0)" >&2; return 1; }
  land_live >/dev/null   # $(…) 서브셸이 아닌 여기서 LIVE 를 채운다
  wl="$(git -C "$SCAN_ROOT" worktree list --porcelain 2>/dev/null)" || { echo "ERROR git worktree list 실패" >&2; return 1; }
  mkdir -p "$DIR"; tmp="$out.tmp.$$"
  { echo '#!/usr/bin/env bash'
    echo "# land 사본 정리 계획 — ft-wt-sweep.sh --land-plan (r880) · 만든 때 $(date '+%F %T') · 실행 = 오빠 h · 지우기 직전 같은 검사를 다시 잰다"
    echo 'set -uo pipefail'
    printf 'LAND_REF=%q; LSOFB=%q; TMUXB=%q; ROOT=%q\n' "$LAND_REF" "$LSOFB" "$TMUXB" "$SCAN_ROOT"
    declare -f land_live land_check
    echo 'w="$(land_live)" || { echo "중단 — $w(지우기 0)"; exit 1; }; land_live >/dev/null'
    # ★r880 고침 1(DA r1 반례 1)★ 지우기 직전마다 좌석 목록을 «그 사본 직전에» 새로 읽는다 — 실행 중 새로 열린 좌석을 놓친 목록으로 지우는 길 0. 못 읽으면 그 사본만 남긴다.
    echo 'land_rm() { local why w; if [ ! -d "$1" ]; then echo "skip $1 — 이미 없음"; return 0; fi
  w="$(land_live)" || { echo "skip $1 — 좌석 목록 못 읽음($w)"; return 0; }; land_live >/dev/null
  if why="$(land_check "$ROOT" "$1" "$2")"; then git -C "$ROOT" worktree remove "$1" && echo "removed $1" || echo "skip $1 — worktree remove 실패"; else echo "skip $1 — $why"; fi; }'
  } > "$tmp"
  while IFS=$'\t' read -r p lk; do
    case "$p" in "$SCAN_ROOT"/.worktrees/*) ;; *) continue;; esac
    case "${p##*/}" in $LAND_GLOB) ;; *) continue;; esac
    [ -d "$p" ] || continue
    [ -z "$lk" ] || { echo "KEEP ${p##*/} — 잠김(locked)"; continue; }
    # ★r880 고침 1(DA r1 반례 1)★ 사본마다 «직전에» 좌석 목록을 새로 읽는다 — 앞 사본을 처리하는 사이 열린 좌석을 시작 때 목록으로 통과시키지 않는다. 못 읽으면 계획 생성 중단(모르면 안 지움).
    w="$(land_live)" || { echo "ERROR land 목록 중단 — $w(계획 생성 중단 · 모르면 안 지움)" >&2; rm -f "$tmp"; return 1; }
    land_live >/dev/null
    h="$(land_check "$SCAN_ROOT" "$p" "")" || { echo "KEEP ${p##*/} — $h"; continue; }
    kb="$(perl -e 'setpgrp(0,0); $SIG{ALRM}=sub{ local $SIG{TERM}="IGNORE"; kill "TERM", -$$; exit 124 }; alarm shift; exit(system(@ARGV)>>8)' "$DU_SEC" "$DU" -sk "$p" 2>/dev/null | awk 'NR==1{print $1}')"
    case "$kb" in ''|*[!0-9]*) kb='?';; *) tk=$((tk+kb));; esac
    printf 'land_rm %q %q  # %s KB\n' "$p" "$h" "$kb" >> "$tmp"; n=$((n+1)); echo "LAND ${p##*/} sha=${h:0:12} kb=$kb"
  done < <(printf '%s\n' "$wl" | awk '/^worktree /{if(p!="")print p"\t"l; p=substr($0,10); l=""} /^locked/{l="y"} END{if(p!="")print p"\t"l}')
  new="$(grep '^land_rm ' "$tmp" | sed 's/  #.*//' | sort)"; sig="$(printf '%s' "$new" | cksum | awk '{print $1"-"$2}')"
  if [ "$n" -eq 0 ]; then rm -f "$tmp" "$out" "$out.sig" "$out.sent"; echo "LAND-PLAN 0곳"; return 0; fi
  mv "$tmp" "$out"; printf '%s\n' "$sig" > "$out.sig"; echo "LAND-PLAN ${n}곳 ${tk}KB → $out"
  # ★r880 고침 4(DA r1 반례 4)★ «보냄» 판정은 목록 비교가 아니라 표지(.sent = 실제로 나간 목록 해시)다 — 첫 알림이 실패했으면 목록이 그대로여도 다시 알린다.
  if [ -f "$out.sent" ] && [ "$(cat "$out.sent" 2>/dev/null)" = "$sig" ]; then
    echo "LAND-NOTIFY 보냄 표지 있음(목록 ${sig}) — 재발송 0"; return 0
  fi
  # ★r880 고침 3(DA r1 반례 3)★ 계획을 사람 승인 진입점(ft-hil --add → /tmp/h<N>)에 등록하고 그 «! bash /tmp/h<N>» 한 줄을 알림에 싣는다(하드 룰 13).
  echo "[HIL] seat=byz-harness-wt-land 착지 끝난 land 사본 ${n}곳(${tk}KB) · $(hilmsg "$out") · 계획 $out — 지우기는 오빠 h(목록 바뀐 때만 1줄)"
}
if [ "${1:-}" = "--land-plan" ]; then land_plan; exit $?; fi
n=0; c=0; w=0; h=0; d=0; ran=0; st=0; rs=0; rp=0; freed=0; T0="$(date +%s)"
for plan in "$DIR"/*.sh; do
  [ -f "$plan" ] || continue
  seat="$(basename "$plan" .sh)"
  if [ "$DRY" = 1 ]; then n=$((n+1)); echo "DRY $seat — $plan"; continue; fi
  if [ $(( $(date +%s) - T0 )) -ge "$BUDGET" ] || { [ "$MAX" -gt 0 ] && [ "$ran" -ge "$MAX" ]; }; then d=$((d+1)); continue; fi
  if ! why="$(plan_ver_check "$plan")"; then
    rwhy="$(replan_one "$plan" "$seat")"; rrc=$?
    case "$rrc" in
      0) rp=$((rp+1)); echo "REPLAN $seat — $why → 같은 좌석·같은 WT 새 계획(옛 계획 $plan.replanned)";;
      4) w=$((w+1)); echo "WAIT $seat 옛 판 계획 — 재생성 보류(${rwhy#WAIT --replan: })"; continue;;
      *) st=$((st+1)); mv "$plan" "$plan.stale"; echo "STALE $seat — 옛 생성기 계획 실행 거부($why) · 재생성 불가: ${rwhy:-사유 없음} (옛 계획 $plan.stale)"; continue;;
    esac
  fi
  n=$((n+1))
  # r608: 같은 계획을 다른 실행자(닫기 경로)가 돌리는 중이면 실행 0 — 로그·계획을 건드리지 않고 다음 계획으로(사람 판정 0).
  if ! plan_lock "$plan"; then w=$((w+1)); echo "WAIT $seat 다른 실행자가 돌리는 중"; continue; fi
  kb="$(size_kb "$plan")"
  run_plan "$plan" > "$plan.log" 2>&1; rc=$?; res="$(tail -1 "$plan.log")"   # 파일로 받는다 — 파이프 캡처는 고아 자식이 잡고 있으면 타임아웃 뒤에도 안 돌아온다
  plan_unlock "$plan"
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
    cleaned*|none) c=$((c+1)); mv "$plan" "$plan.done"; rm -f "$plan.kb"; echo "OK   $seat wt=$res"
      if [ -n "$kb" ] && [ "$res" != none ]; then   # r535 지운 폴더 크기 — .done 끝 1줄 + 폴더별 로그 1줄
        echo "# freed_kb=$kb" >> "$plan.done"; case "$kb" in *[!0-9]*) ;; *) freed=$((freed+kb));; esac
        echo "$(date '+%F %T') freed seat=$seat kb=$kb wt=$(sed -n 's/^SEAT=.*; WT=\([^;]*\).*/\1/p' "$plan.done" | head -1)" >> "$SLOG" 2>/dev/null
      fi;;
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
# 폴더 주인 팀(4b) — .worktree-info.json purpose 의 카드 경로 design/(teams/)<팀>/indices · 명단(ft-team-lib)에 있는 팀만 · 못 정하면 harness
owner_team() {
  local t; t="$(sed -nE 's#.*design/(teams/)?([a-z0-9][a-z0-9_-]*)/indices/.*#\2#p' "$1/.worktree-info.json" 2>/dev/null | head -1)"
  if [ -n "$t" ] && [ -f "$(dirname "$SELF")/ft-team-lib.sh" ] && ( . "$(dirname "$SELF")/ft-team-lib.sh"; FT_REPO_ROOT="$SCAN_ROOT" ft_team_names 2>/dev/null ) | grep -qxF -- "$t"; then echo "$t"; else echo harness; fi
}
shell_scan() {
  local stamp="$DIR/.shell-scan.stamp" sigf="$DIR/.shell-sig" now sig="" list="" p sha name missing cnt=0 live tm
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
    tm="$(owner_team "$p")"; list="$list$tm:${p##*/} "; cnt=$((cnt+1))
  done < <(git -C "$SCAN_ROOT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{p=substr($0,10)} /^HEAD /{print p "\t" substr($0,6)}')
  sig="$(printf '%s' "$list" | tr ' ' '\n' | sort | tr '\n' ' ')"
  if [ -z "$sig" ]; then rm -f "$sigf"; return 0; fi
  [ "$sig" = "$(cat "$sigf" 2>/dev/null)" ] && return 0
  printf '%s' "$sig" > "$sigf"
  for tm in $(printf '%s' "$sig" | tr ' ' '\n' | cut -d: -f1 | sort -u); do
    echo "[HIL] seat=byz-$tm-wt-shell 반쯤 지워진 워크트리 껍데기 $(printf '%s' "$sig" | tr ' ' '\n' | grep -c "^$tm:")곳(전체 ${cnt}곳): $(printf '%s' "$sig" | tr ' ' '\n' | sed -n "s/^$tm://p" | tr '\n' ' ')— 처리는 오빠 값(바뀐 때만 1줄)"
  done
}
shell_scan
# r535 등록 없는 폴더 목록 — <SCAN_ROOT>/.worktrees/* 중 git worktree list 에 없는 실폴더(링크 제외) → TSV(이름·mtime·KB). 읽기·목록만(삭제 0) · 간격 ORPH_SEC · du 폴더당 DU_SEC · 합계 60s 넘으면 나머지 크기 ?
orphan_scan() {
  local stamp="$DIR/.orphan-scan.stamp" now
  [ "$DRY" != 1 ] && [ -n "$SCAN_ROOT" ] && [ -d "$SCAN_ROOT/.worktrees" ] && [ -d "$DIR" ] || return 0
  now="$(date +%s)"; [ $(( now - $(cat "$stamp" 2>/dev/null || echo 0) )) -ge "${FT_WT_ORPHAN_SCAN_SEC:-3600}" ] || return 0
  echo "$now" > "$stamp"
  python3 - "$SCAN_ROOT" "$ORPH" "$DU" "$DU_SEC" <<'PY' || echo "ERROR 등록 없는 폴더 목록 실패(목록 갱신 0)" >&2
import os, subprocess, sys, time
root, out, du, dusec = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
wl = subprocess.run(["git", "-C", root, "worktree", "list", "--porcelain"], capture_output=True, text=True, timeout=30)
if wl.returncode != 0: raise SystemExit("git worktree list rc=%d" % wl.returncode)
reg = {os.path.realpath(l[9:]) for l in wl.stdout.splitlines() if l.startswith("worktree ")}
base = os.path.join(root, ".worktrees"); rows = []; t0 = time.time()
for n in sorted(os.listdir(base)):
    p = os.path.join(base, n)
    if os.path.islink(p) or not os.path.isdir(p) or os.path.realpath(p) in reg: continue
    kb = "?"
    if time.time() - t0 < 60:
        try:
            r = subprocess.run([du, "-sk", p], capture_output=True, text=True, timeout=dusec)
            v = (r.stdout.split() or ["?"])[0]; kb = v if v.isdigit() else "?"
        except subprocess.TimeoutExpired: pass
    rows.append("%s\t%s\t%s" % (n, time.strftime("%Y-%m-%d %H:%M", time.localtime(os.path.getmtime(p))), kb))
tmp = out + ".tmp.%d" % os.getpid()
with open(tmp, "w", encoding="utf-8") as f: f.write("name\tmtime\tsize_kb\n" + "".join(r + "\n" for r in rows))
os.replace(tmp, out)
PY
}
orphan_scan
no=0; [ -f "$ORPH" ] && no=$(( $(wc -l < "$ORPH") - 1 )); [ "$no" -ge 0 ] || no=0
nh="$(ls "$DIR"/*.sh.hil 2>/dev/null | wc -l | tr -d ' ')"
[ "$DRY" = 1 ] || [ $((c + rp)) -eq 0 ] || echo "$(date '+%F %T') pass cleaned=$c replanned=$rp stale=$st wait=$w carry=$d freed_kb=$freed" >> "$SLOG" 2>/dev/null
echo "sweep 계획 $n · cleaned/none $c · wait $w · hil $h$([ "$c" -gt 0 ] && echo " · freed_kb $freed")$([ "$d" -gt 0 ] && echo " · 이월 $d")$([ "$st" -gt 0 ] && echo " · stale $st")$([ "$rp" -gt 0 ] && echo " · replanned $rp")$([ "$rs" -gt 0 ] && echo " · 이어정리 $rs")$([ "$nh" -gt 0 ] && echo " · hil_files $nh")$([ "$no" -gt 0 ] && echo " · orphans $no(목록 $ORPH)")"
