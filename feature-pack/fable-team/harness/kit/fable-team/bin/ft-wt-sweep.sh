#!/usr/bin/env bash
# ft-wt-sweep.sh [--dry-run | --finish <포인터> | --launchd]  — 닫힌 나노의 워크트리 정리 계획(.fable-team/state/wt-clean/<seat>.sh)을 «세션이 사라진 뒤» 실행한다.
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
#     ★r832★ 후보마다 «tmux pane 0 ∧ 미커밋 0» 일 때만 목록에(아니면 SKIP 1줄 · 경보 아님) · pane 목록을 못 읽은 회차 = 경보 0(NOTE) · git status 상한 FT_WT_SHELL_GIT_SEC(기본 7).
#     ★r844 r5★ 판정이 «안 된» 것은 경보도 «아님» 도 아니다 — worktree list·ls-tree 실패(rc≠0·시간 초과·SHA 0) = 판정 못 함(이전 판정 이어받기 · 후보 제외 0 · NOTE 1줄). 물려받은 GIT_DIR·GIT_WORK_TREE·GIT_INDEX_FILE·GIT_COMMON_DIR 는 스크립트 시작(자동 스캔 루트 결정 전)에서 지운다.
#   실행 위치 무관(원장·워크트리는 계획에 절대경로로 박혀 있다). FT_WT_AUTOCLEAN=0 이면 아무것도 실행하지 않는다.
#   ★r444 --launchd★(com.byz.ft-wt-sweep · 일 1회 — 사람 h 0): FT_ROOT 필수 · 그 루트에서 sweep 1회(FT_WT_SWEEP_MAX 기본 20) → [HIL] 줄을 팀 master 우편함으로(ft-tick sweep_wt 와 같은 규칙)
#     → 끝난 가지 재확인(refs/heads/nano/* 최신순 FT_WT_ARCHIVE_MAX 기본 200 · ft-branch-archive.sh · FINISHED 만 refs/archive 로) → 로그 <FT_ROOT>/.fable-team/state/wt-sweep.log 1줄 `cleaned=N wait=N hil=N … archived=N`.
#   ★r444 4b★ 껍데기 경보 [HIL] 은 폴더 주인 팀마다 1줄 `seat=byz-<팀>-wt-shell`(팀 = .worktree-info.json purpose 의 카드 경로 · 명단에 있는 팀만 · 못 정하면 harness) — 호출자가 그 팀 master 로 보낸다.
set -uo pipefail
SELF="$(cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")"
BATON="${BATON_BIN:-$HOME/.baton/current/bin/baton}"

# r844 GIT_CLEAN — 물려받은 저장소 env 지움(git rev-parse --local-env-vars 목록 그대로 · 다른 저장소 상태를 읽지 않게) · LC_ALL=C(SKIP 사유의 git 원문 고정)
GIT_CLEAN=(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES
  -u GIT_CONFIG -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT -u GIT_IMPLICIT_WORK_TREE -u GIT_GRAFT_FILE -u GIT_NO_REPLACE_OBJECTS -u GIT_REPLACE_REF_BASE
  -u GIT_PREFIX -u GIT_SHALLOW_FILE LC_ALL=C)
# cap <초> <명령…> — run_plan 과 같은 꼴의 상한(그룹째 TERM) · 초과 = rc 124
cap() { perl -e 'setpgrp(0,0); $SIG{ALRM}=sub{ local $SIG{TERM}="IGNORE"; kill "TERM", -$$; exit 124 }; alarm shift; my $r=system(@ARGV); exit(($r>>8) || (($r&127) ? 128+($r&127) : 0));' "$@"; }
# ★r845★ 이 스크립트의 «모든» git 호출은 git7(또는 r844 의 sgit = cap+GIT_CLEAN+ceiling) 하나를 지난다 — 머리 rev-parse · shell_scan 4자리+sparse-checkout list · orphan_scan · --finish · --launchd · plan 검사.
#   7초 상한(FT_WT_GIT_SEC) · 물려받은 GIT_* 지움(GIT_CLEAN) · LC_ALL=C · rc≠0 은 호출부가 «판정 불가» 로 올린다.
git7() { perl -e 'setpgrp(0,0); $SIG{ALRM}=sub{ local $SIG{TERM}="IGNORE"; kill "TERM", -$$; exit 124 }; alarm shift; my $r=system(@ARGV); exit(($r>>8) || (($r&127) ? 128+($r&127) : 0));' "${FT_WT_GIT_SEC:-7}" "${GIT_CLEAN[@]}" git -C "$1" "${@:2}"; }
SCAN_U=0   # shell_scan·orphan_scan 이 낸 «판정 불가» 수 — 요약 줄 u= 로 나간다(결정 4 ② · r8: 한 카운터로 모은다)

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
    [ ! -d "$del" ] || git7 "$root" worktree remove --force "$del" 2>/dev/null   # r845: git7 경유(넘으면 아래 rm -rf 가 마무리)
    [ ! -d "$del" ] || rm -rf -- "$del"
  fi
  git7 "$root" worktree prune 2>/dev/null
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
    else rfail=$((rfail+1)); echo "ERROR [HIL] 라우팅 실패(to=${to:-없음} mbox=${MB:-없음}): ${ln:0:120}" >&2; fi
  done < <(printf '%s\n' "$out" | grep '^\[HIL\]')
  # 끝난 가지 재확인 — FINISHED 만 refs/archive 로(삭제 0). 최신 가지부터(새로 끝난 것이 먼저 잡히게)
  AR="$(dirname "$SELF")/ft-branch-archive.sh"; ar=0; ask=0
  if [ -f "$AR" ] && [ "${FT_WT_ARCHIVE:-1}" = 1 ]; then
    while IFS= read -r b; do [ -n "$b" ] || continue
      if bash "$AR" "$b" --repo "$FT_ROOT" >/dev/null 2>&1; then ar=$((ar+1)); else ask=$((ask+1)); fi
    done < <(git7 "$FT_ROOT" for-each-ref --sort=-committerdate --count="${FT_WT_ARCHIVE_MAX:-200}" --format='%(refname:short)' 'refs/heads/nano/')
  fi
  printf '%s rc=%s cleaned=%s wait=%s hil=%s stale=%s carry=%s resume=%s routed=%s route_fail=%s archived=%s archive_skip=%s replanned=%s hil_files=%s orphans=%s freed_kb=%s\n' "$(date '+%F %T')" "$rc" \
    "$(num 'cleaned/none')" "$(num wait)" "$(num hil)" "$(num stale)" "$(num 이월)" "$(num 이어정리)" "$routed" "$rfail" "$ar" "$ask" \
    "$(num replanned)" "$(num hil_files)" "$(num orphans)" "$(num freed_kb)" >> "$LST/wt-sweep.log"
  tail -1 "$LST/wt-sweep.log"; exit "$rc"
fi

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
[ "${FT_WT_AUTOCLEAN:-1}" != 0 ] || { echo "FT_WT_AUTOCLEAN=0 — sweep 실행 안 함"; exit 0; }
# ★r844 r5 ⓐ★ 물려받은 저장소 env(GIT_DIR·GIT_WORK_TREE·GIT_INDEX_FILE·GIT_COMMON_DIR)는 «자동 스캔 루트 결정 전» 에 지운다
#   — 밖에서 물려받은 값이 있으면 아래 WT·ROOT 결정이 다른 리포를 가리켜 남의 저장소 상태를 판정한다(외부 DA r3 반례 2) · LC_ALL=C 로 git 원문 고정
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
LC_ALL=C; export LC_ALL
# ★r8★ 초기 조회 실패를 «삼키지 않는다» — `|| pwd` 폴백 0 · 조용한 return 0. 실패 = «판정 불가 <cwd>:init» 1줄 + SCAN_U 1(요약 u= 로 나간다) · rc 는 줄에 그대로 적는다.
INIT_RC=0
WT="$(git7 "$PWD" rev-parse --show-toplevel 2>/dev/null)"; INIT_RC=$?
if [ "$INIT_RC" -eq 0 ] && [ -n "$WT" ]; then
  ROOT="$(git7 "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
else
  WT=""; ROOT=""
  echo "판정 불가 $PWD:init — 워크트리/리포 조회 실패(rc=$INIT_RC · 오빠 판정 0 · 삭제 0)"
  SCAN_U=$((SCAN_U+1))
fi
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
HB="$(dirname "$0")/ft-hil.sh"  # R83: 사람 ! 실행 안내 = 짧은 링크(`! bash /tmp/h<N>`) — 옆의 ft-hil.sh 가 없거나 실패면 지금 문구 그대로 + WARN
hilmsg() { local m=""; command -v "$HB" >/dev/null 2>&1 && m="$("$HB" --add "$1" 2>/dev/null | tail -1)"; [ -n "$m" ] && echo "$m" || { echo "WARN ft-hil 실패 — 경로 안내로 후퇴" >&2; echo "스크립트 $1"; }; }
# 분리 정리 — 새 세션(setsid)으로 떼어 낸다: run_plan 의 그룹 TERM·틱 pass 의 종료와 무관하게 끝까지 돈다. 표준출력은 파일로 — 파이프를 쥐고 있으면 호출자가 안 돌아온다.
launch_finish() { ( cd "$2" && perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' /bin/bash "$SELF" --finish "$1" >> "$1.log" 2>&1 < /dev/null & ); }
# 계획 버전 대조 — 0 통과 · 1 거부(사유 stdout). 생성기 계획이 아닌 것(수동·스텁)은 대상 아님.
plan_ver_check() {
  local pv lv
  pv="$(sed -n 's/^# plan-ver: //p' "$1" | head -1)"
  if [ -z "$pv" ]; then grep -q '^# wt-clean 계획 — ft-nano-close.sh' "$1" || return 0; fi
  lv=""; [ -f "$GEN" ] && lv="$(git7 "$PWD" hash-object -- "$GEN" 2>/dev/null)"
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
# git 호출 실패의 «공용» 처리 — shell_scan 의 지역 변수 und·ucnt 에 «판정 불가 <경로:단계>» 를 더한다(bash 동적 스코프).
gitfail() { und="$und$1:$2 "; ucnt=$((ucnt+1)); }
# ★r945 r5★ sparse 워크트리 판정 — 문서·카드 작업 공간은 `--no-checkout + sparse-checkout` 으로 만들어져 최상위 항목 대부분이 «원래» 디스크에 없다.
#   옛 셈(HEAD 트리 최상위 중 2개 이상 부재 = 껍데기)은 그 정상 상태를 «반쯤 지워진 껍데기» 로 올려 오빠 HIL 목록을 오염시켰다(진행 중 PR 작업 공간 삭제 위험).
#   ★git 규칙을 «흉내 내지 않는다»★ — r1~r4 반례 4회가 전부 흉내 자리에서 났다(sparse 패턴 손 해석 · 따옴표 · 종류 · 제어문자 · `!` 제외 취소).
#     대신 «있어야 하는데 없는 추적 파일» 을 git 에게 그대로 묻는다: `git ls-files -d -z` 1회(sparse 로 안 받은 파일은 git 이 skip-worktree 로 들고 있어 애초에 안 나온다).
#   ★r8·결정 4★ 삭제 파일을 «최상위 이름» 으로 접고, 그 최상위가 디스크에 없을 때만 껍데기다(하위 파일 1개 부재 = 껍데기 아님).
#   ★r6·r8★ git7 실패 = «판정 불가 <경로:단계>» 1줄 + SCAN_U(조용한 0 · 일반 워크트리 후퇴 = 구조로 사라짐).
#   ★알려진 값(r5 실측)★ 실 스캔루트 sparse 325석 중 41석이 «추적된 .serena 삭제» 로 1 이상(현재 39석) — 새 카드 r1007 범위.
# sparse 워크트리의 «껍데기» — $1 = 워크트리 · $2 = 접두("$2.raw"). stdout = 사라진 최상위 이름 수(0 = 껍데기 아님) · rc 0 정상 · 2 판정 불가.
sparse_deleted() {
  local p="$1" raw="$2.raw" rc n=0 item top
  git7 "$p" ls-files -d -z > "$raw" 2>/dev/null; rc=$?
  if [ "$rc" -ne 0 ]; then rm -f "$raw"; return 2; fi   # rc≠0(124 = 7초 초과 포함) = 판정 불가
  while IFS= read -r -d '' item; do
    top="${item%%/*}"
    [ -n "$top" ] || continue
    [ -e "$p/$top" ] || [ -L "$p/$top" ] && continue   # 최상위가 디스크에 있으면 그 안 하위 파일 부재는 껍데기가 아니다
    n=$((n+1))
  done < "$raw"
  rm -f "$raw"
  echo "$n"
  return 0
}
# sparse 패턴 파일을 «읽을 수 있는가» — rc≠0 또는 경고(stderr) = 판정 불가(동결 기대: 패턴 파일이 폴더면 git 은 rc0 + 경고만 낸다).
sparse_patterns_ok() {
  local p="$1" err rc
  err="$(git7 "$p" sparse-checkout list 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] && [ -z "$err" ]
}
# r832 살아 있는 좌석 가드 — rc 0 = 껍데기로 올리지 않음(사유 stdout) · 1 = 세션 0 ∧ 미커밋 0 · 2 = 판정 못 함(이전 판정 이어받음)
#   · 3 = 세션 0 ∧ git 연결 끊김(.git 없음 · gitdir 경로 자체 없음 — 미커밋을 셀 수 없지만 껍데기로 셈 · 정리는 오빠 값).
#   · r844 r3: gitdir 이 있는데 rev-parse·status 가 실패 = 무엇이든 2(판정 못 함 · 오류 문구로 «없음»·«못 읽음» 을 가르지 않음) · git 호출은 sgit(물려받은 GIT_* 지움 · LC_ALL=C).
#   세션 = tmux pane 경로(글자 그대로 + 실제 경로 — pane_paths)가 그 폴더 자신 또는 하위(경로 앞부분만 같은 형제 A-r2 는 아님).
#   미커밋 = status 줄 중 «지워짐만»(' D'·'D ' — 껍데기 자체 · 내용은 HEAD 에 있음 · r166 과 같은 판정)을 뺀 수.
#   git 은 그 폴더 밖으로 올라가지 않는다(부모 리포 상태를 읽는 일 0) · 실패·상한 초과 = 판정 못 함.
# sgit <폴더> <git 인자…> — GIT_CLEAN · 그 폴더 밖으로 안 올라감 · 상한 SHELL_GIT_SEC
sgit() { local p="$1"; shift; cap "$SHELL_GIT_SEC" "${GIT_CLEAN[@]}" GIT_CEILING_DIRECTORIES="$(dirname "$p")" git -C "$p" "$@"; }
# r844 r2 pstat <경로> — stat(심링크 따라감) rc: 0 = 있음 · 1 = 없음(ENOENT·ENOTDIR — 앞 폴더를 다 지나 이름이 없음) · 2 = 접근 불가 등(EACCES·ELOOP… — 있는지 모름)
#   ★-e 는 접근 불가도 «없음» 으로 답한다(외부 DA r844 r1) — 없음 판정은 이것만 쓴다★
pstat() { perl -e 'exit(stat($ARGV[0]) ? 0 : ($!{ENOENT} || $!{ENOTDIR}) ? 1 : 2)' -- "$1"; }
# r844 r3 gitdir_gone <폴더> — rc0(사유 stdout) = 끊김: «.git 이 가리키는 gitdir 경로 자체가 없음» 하나뿐 · rc1 = 끊김 아님(rev-parse·status 로 판정)
#   gitdir = .git 이 폴더면 그 폴더 · 파일이면 «gitdir: » 뒤(git read_gitfile 과 같게 — 파일 머리가 «gitdir: » · 끝 \r\n 만 뗌 · 상대 경로는 .git 이 있는 폴더 기준)
#   .git 대상 없음(깨진 심링크) = 끊김 · .git·gitdir 접근 불가 · gitdir: 줄 못 읽음/꼴 틀림 = rc1(판정은 git 에게 · 실패하면 판정 못 함)
gitdir_gone() {
  local g="$1/.git" t s
  pstat "$g"; s=$?
  [ "$s" -ne 1 ] || { echo ".git 대상 없음"; return 0; }
  [ "$s" -eq 0 ] && [ ! -d "$g" ] || return 1
  t="$(perl -e 'open(my $f, "<", $ARGV[0]) or exit 1; local $/; my $b = <$f>; $b =~ s/[\r\n]+\z//; $b =~ s/\Agitdir: // or exit 1; print $b' -- "$g")" || return 1
  case "$t" in /*) ;; *) t="$1/$t";; esac
  pstat "$t"; [ "$?" -eq 1 ] || return 1
  echo "gitdir 없음: $t"
}
seat_busy() {
  local p="$1" rp q out rc n err
  rp="$(CDPATH= cd -P -- "$p" 2>/dev/null && pwd -P)"
  while IFS= read -r q; do
    [ -n "$q" ] || continue
    case "$q" in "$p"|"$p"/*|"${rp:-$p}"|"${rp:-$p}"/*) echo "세션 있음(pane $q)"; return 0;; esac
  done <<<"$2"
  [ -r "$p" ] && [ -x "$p" ] || { echo "판정 못 함(폴더 못 읽음)"; return 2; }
  # r844 r2: .git 은 «있음» 만 본다(-e 거짓 = 심링크 대상 접근 불가일 수 있음 → -L · 폴더 r·x 라 이름 확인은 정확)
  [ -e "$p/.git" ] || [ -L "$p/.git" ] || { echo "git 연결 끊김(.git 없음)"; return 3; }
  # r844 r3: 끊김 = gitdir 경로 자체 없음 하나 · 그 밖은 git 에게 묻고 실패하면 무엇이든 판정 못 함(이어받음)
  q="$(gitdir_gone "$p")" && { echo "git 연결 끊김($q)"; return 3; }
  err="$(sgit "$p" rev-parse --git-dir 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -ne 124 ] || { echo "판정 못 함(git rev-parse ${SHELL_GIT_SEC}s 초과)"; return 2; }
  [ "$rc" -eq 0 ] || { echo "판정 못 함(git rev-parse rc=$rc · $(printf '%s\n' "$err" | head -1 | cut -c1-160))"; return 2; }
  out="$(sgit "$p" status --porcelain --untracked-files=normal 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || { echo "판정 못 함(git status rc=$rc$([ "$rc" -eq 124 ] && echo " · ${SHELL_GIT_SEC}s 초과"))"; return 2; }
  n="$(printf '%s\n' "$out" | grep -cvE '^( D|D ) |^$')"
  [ "$n" -eq 0 ] || { echo "미커밋 $n"; return 0; }
  return 1
}
# pane_paths <목록> — 줄마다 글자 그대로 + 실제 경로(심링크·/var→/private/var 풀림 · 다를 때만) · 없는 경로는 글자만
pane_paths() {
  local q r
  while IFS= read -r q; do
    [ -n "$q" ] || continue
    printf '%s\n' "$q"
    r="$(CDPATH= cd -P -- "$q" 2>/dev/null && pwd -P)" && [ "$r" != "$q" ] && printf '%s\n' "$r"
  done <<<"$1"
  return 0
}
shell_scan() {
  local stamp="$DIR/.shell-scan.stamp" sigf="$DIR/.shell-sig" now sig="" list="" p sha name missing cnt=0 unk=0 unkl="" unkls=0 dis="" live tm chk why brc panes k names wl wrc tree trc
  local und="" ucnt=0 s1 s2 spx spcfg crc
  local tb="${FT_TMUX_BIN:-$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)}" SHELL_GIT_SEC="${FT_WT_SHELL_GIT_SEC:-7}"
  [ "$DRY" != 1 ] && [ -n "$SCAN_ROOT" ] && [ -d "$SCAN_ROOT" ] && [ -d "$DIR" ] || return 0
  now="$(date +%s)"; [ $(( now - $(cat "$stamp" 2>/dev/null || echo 0) )) -ge "$SCAN_SEC" ] || return 0
  echo "$now" > "$stamp"
  # r832: 살아 있는지 모르면 올리지 않는다 — pane 목록을 못 읽은 회차는 경보 0 · 서명 그대로
  panes="$(cap 7 "$tb" list-panes -a -F '#{pane_current_path}' 2>/dev/null)" || { echo "NOTE 껍데기 판정 생략 — tmux 목록 못 읽음($tb)"; return 0; }
  panes="$(pane_paths "$panes")"
  # ★r844 r5 ⓑ★ worktree list 실패(rc≠0 · 시간 초과) = 이번 회차는 껍데기를 판정하지 않는다 — 경보 0 · 서명 그대로
  wl="$(cap "$SHELL_GIT_SEC" "${GIT_CLEAN[@]}" git -C "$SCAN_ROOT" worktree list --porcelain 2>/dev/null)"; wrc=$?
  # ★r8★ 그 실패는 «판정 불가 <루트>:worktree-list» 1줄 + u= 로도 남긴다(위 조기 return 은 r844 계약 그대로)
  [ "$wrc" -eq 0 ] || { gitfail "$SCAN_ROOT" worktree-list; SCAN_U=$((SCAN_U+ucnt)); }
  [ "$wrc" -eq 0 ] || { echo "NOTE 껍데기 판정 생략 — worktree list 실패(rc=$wrc · 서명 그대로)"; return 0; }
  live="$(for f in "$DIR"/*.deleting; do [ -f "$f" ] && sed -n 1p "$f"; done)"
  while IFS=$'\t' read -r p sha; do
    case "$p" in "$SCAN_ROOT"/.worktrees/*) ;; *) continue;; esac
    [ -d "$p" ] || continue
    chk=1
    # ★r945★ sparse 표식이면 «git 에게 직접 묻기» — 삭제된 추적 파일을 최상위로 접어 ≥1 = 껍데기(아래 r844 case 는 일반 워크트리 몫 · sparse 는 여기서 판정 끝)
    sp_hit=0
    spcfg="$(git7 "$p" config --bool --get core.sparseCheckout 2>/dev/null)"; crc=$?
    if [ "$crc" -gt 1 ]; then
      # ★r8★ 설정 조회 실패 = «판정 불가 <경로>:config» 1줄 + u=(일반 규칙으로 «조용히» 후퇴해 껍데기 1 로 세는 길 0) · r844 자리(seat_busy)는 그대로 본다
      gitfail "$p" config; spcfg=""; crc=1
    fi
    if [ "$crc" -eq 0 ] && [ "$spcfg" = true ]; then
      if ! sparse_patterns_ok "$p"; then gitfail "$p" sparse-list; continue; fi
      spx="$DIR/.sparse-$$"
      if ! missing="$(sparse_deleted "$p" "$spx")"; then gitfail "$p" ls-files; continue; fi
      [ "$missing" -ge 1 ] || continue
      sp_hit=1
    fi
    [ "$sp_hit" = 1 ] && : || {
    case "${p##*/}" in
      *.deleting-[0-9]*) printf '%s\n' "$live" | grep -qxF -- "$p" && continue; missing=9; chk=0;;
      *)
         # ★r844 r5 ⓑ★ ls-tree 실패(rc≠0 · 시간 초과 · SHA 0/빈 값) = 그 폴더 «판정 못 함»(이전 서명 이어받기 · 후보에서 빼지 않음)
         #   — 지금까지는 실패를 «부재 0» 으로 읽어 후보에서 빼고 서명을 지웠다(외부 DA r3 반례 1: 같은 경보 반복)
         #   ★r8★ 그 실패는 «판정 불가 <경로>:ls-tree» 1줄 + u= 로도 남긴다(두 계약을 같이 지킨다)
         tree=""; trc=0
         if [ -n "$sha" ] && ! printf '%s' "$sha" | grep -q '^0*$'; then
           tree="$(cap "$SHELL_GIT_SEC" "${GIT_CLEAN[@]}" git -C "$SCAN_ROOT" ls-tree --name-only "$sha" 2>/dev/null)"; trc=$?
         else
           trc=1
         fi
         if [ "$trc" -ne 0 ]; then
           echo "SKIP 껍데기 후보 ${p##*/} — 판정 못 함(ls-tree 실패 · sha=${sha:-빈값} rc=$trc)"
           gitfail "$p" ls-tree
           unk=$((unk+1)); unkls=$((unkls+1)); unkl="$unkl$(owner_team "$p"):${p##*/} "; continue
         fi
         while IFS= read -r name; do [ -n "$name" ] || continue; [ -e "$p/$name" ] || missing=$((missing+1)); done <<<"$tree";;
    esac
    }
    brc=1
    if [ "$chk" = 1 ]; then
      why="$(seat_busy "$p" "$panes")"; brc=$?
      case "$brc" in
        0) echo "SKIP 껍데기 후보 ${p##*/} — $why"; continue;;
        2) echo "SKIP 껍데기 후보 ${p##*/} — $why"; unk=$((unk+1)); unkl="$unkl$(owner_team "$p"):${p##*/} "; continue;;
      esac
    fi
    tm="$(owner_team "$p")"; list="$list$tm:${p##*/} "; cnt=$((cnt+1))
    [ "$brc" -eq 3 ] && dis="$dis$tm:${p##*/} "
  done < <(printf '%s\n' "$wl" | awk '/^worktree /{p=substr($0,10)} /^HEAD /{print p "\t" substr($0,6)}')
  # r832 r2b: 판정 못 한 폴더는 그 폴더만 이전 서명을 이어받는다(지우면 다음 회차에 같은 경보가 다시 나감) — 회차 전체 보류 0
  if [ "$unk" -gt 0 ]; then
    why="이전 판정 이어받음"; [ "$unkls" -eq 0 ] || why="ls-tree 실패 ${unkls}곳 · 이전 판정 이어받음"; [ "$unkls" -ne "$unk" ] || why="ls-tree 실패 ${unkls}곳"
    echo "NOTE 껍데기 판정 못 함 ${unk}곳(${why})"
    for k in $unkl; do tr ' ' '\n' 2>/dev/null < "$sigf" | grep -qxF -- "$k" && { list="$list$k "; cnt=$((cnt+1)); }; done
  fi
  SCAN_U=$((SCAN_U+ucnt))   # 요약 줄 u= (r8: init·orphan 이 먼저 올린 수에 «더한다»)
  s2="$(printf '%s' "$und" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ')"
  # 판정 불가 — 사람 판정 0 · 삭제 대상 0 · master 1줄(«경로:단계» · 아래 조기 return 들보다 «먼저» 낸다) · «바뀐 때만»(HIL 서명과 분리한 파일로 dedup)
  undf="$DIR/.shell-und"
  if [ "$ucnt" -eq 0 ]; then rm -f "$undf"; else
    if [ "$s2" != "$(cat "$undf" 2>/dev/null)" ]; then
      printf '%s' "$s2" > "$undf"
      echo "판정 불가 ${ucnt}곳 — git 호출 실패로 껍데기 판정 보류(오빠 판정 0 · 삭제 0): $(printf '%s' "$s2" | tr ' ' '\n' | sed '/^$/d' | tr '\n' ' ')"
    fi
  fi
  sig="$(printf '%s' "$list" | tr ' ' '\n' | sort | tr '\n' ' ')"
  if [ -z "$sig" ]; then [ "$unk" -gt 0 ] && return 0; rm -f "$sigf"; return 0; fi
  [ "$sig" = "$(cat "$sigf" 2>/dev/null)" ] && return 0
  printf '%s' "$sig" > "$sigf"
  for tm in $(printf '%s' "$sig" | tr ' ' '\n' | cut -d: -f1 | sort -u); do
    names=""; for k in $(printf '%s' "$sig" | tr ' ' '\n' | grep "^$tm:"); do
      names="$names${k#*:}"; case " $dis " in *" $k "*) names="$names (git 연결 끊김)";; esac; names="$names "
    done
    echo "[HIL] seat=byz-$tm-wt-shell 반쯤 지워진 워크트리 껍데기 $(printf '%s' "$sig" | tr ' ' '\n' | grep -c "^$tm:")곳(전체 ${cnt}곳): ${names}— 처리는 오빠 값(바뀐 때만 1줄) (세션 0 · 미커밋 0)"
  done
}
# r535 등록 없는 폴더 목록 — <SCAN_ROOT>/.worktrees/* 중 git worktree list 에 없는 실폴더(링크 제외) → TSV(이름·mtime·KB). 읽기·목록만(삭제 0) · 간격 ORPH_SEC · du 폴더당 DU_SEC · 합계 60s 넘으면 나머지 크기 ?
orphan_scan() {
  local stamp="$DIR/.orphan-scan.stamp" now
  [ "$DRY" != 1 ] && [ -n "$SCAN_ROOT" ] && [ -d "$SCAN_ROOT/.worktrees" ] && [ -d "$DIR" ] || return 0
  now="$(date +%s)"; [ $(( now - $(cat "$stamp" 2>/dev/null || echo 0) )) -ge "${FT_WT_ORPHAN_SCAN_SEC:-3600}" ] || return 0
  echo "$now" > "$stamp"
  local wlp
  if ! wlp="$(git7 "$SCAN_ROOT" worktree list --porcelain 2>/dev/null)"; then   # r845: git7 경유 · python 은 git 을 부르지 않는다
    echo "판정 불가 $SCAN_ROOT:orphan-list — 등록 없는 폴더 목록 갱신 0(오빠 판정 0 · 삭제 0)" >&2
    SCAN_U=$((SCAN_U+1))   # ★r8★ 판정 불가 셈은 한 카운터(SCAN_U) 하나로 모은다
    return 0
  fi
  printf '%s\n' "$wlp" > "$ORPH.wl"   # git7 이 받은 목록을 파일로 넘긴다(python 은 git 을 부르지 않는다)
  python3 - "$SCAN_ROOT" "$ORPH" "$DU" "$DU_SEC" "$ORPH.wl" <<'PY' || echo "ERROR 등록 없는 폴더 목록 실패(목록 갱신 0)" >&2
import os, subprocess, sys, time
root, out, du, dusec, wlf = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), sys.argv[5]
wl = open(wlf, encoding="utf-8", errors="replace").read()
reg = {os.path.realpath(l[9:]) for l in wl.splitlines() if l.startswith("worktree ")}
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
try: os.unlink(wlf)
except OSError: pass
PY
}
orphan_scan
shell_scan
no=0; [ -f "$ORPH" ] && no=$(( $(wc -l < "$ORPH") - 1 )); [ "$no" -ge 0 ] || no=0
nh="$(ls "$DIR"/*.sh.hil 2>/dev/null | wc -l | tr -d ' ')"
[ "$DRY" = 1 ] || [ $((c + rp)) -eq 0 ] || echo "$(date '+%F %T') pass cleaned=$c replanned=$rp stale=$st wait=$w carry=$d freed_kb=$freed" >> "$SLOG" 2>/dev/null
echo "sweep 계획 $n · cleaned/none $c · wait $w · hil $h$([ "${SCAN_U:-0}" -gt 0 ] && echo " · u=$SCAN_U")$([ "$c" -gt 0 ] && echo " · freed_kb $freed")$([ "$d" -gt 0 ] && echo " · 이월 $d")$([ "$st" -gt 0 ] && echo " · stale $st")$([ "$rp" -gt 0 ] && echo " · replanned $rp")$([ "$rs" -gt 0 ] && echo " · 이어정리 $rs")$([ "$nh" -gt 0 ] && echo " · hil_files $nh")$([ "$no" -gt 0 ] && echo " · orphans $no(목록 $ORPH)")"
