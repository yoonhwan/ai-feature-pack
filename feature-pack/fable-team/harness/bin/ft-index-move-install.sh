#!/usr/bin/env bash
# ft-index-move-install.sh <카드> [--landed <A..B|sha>]   (R245 · ft-index-move.sh 진행→완성 «전»에 호출 — ft-index-move-canon.sh 처럼 분리)
#   병합 ≠ 끝: 하네스 키트 단위는 «라이브 설치 cmp0 + 실사건 1회 실측» 까지가 완료다.
#   design/harness/indices/ 카드: `- 설치: 있음|없음` 줄 필수. 없음 = 통과. 있음 = --landed 필수 → ft-live-install-check.sh --range 가 OK 이고
#   `- 실사건: <무엇> · <증거: mbox #N | 경로:줄 | ledger 키>` 줄에 증거 토큰이 있어야 통과. 통과하면 그 범위 sha 의 install-pending 파일을 지운다.
#   대조는 origin/main tip — --landed 는 «대상 파일»만 정한다(뒤 커밋이 같은 파일을 또 고쳐도 라이브=tip 이면 OK · R367).
#   r937: 착지 리포 판정 = ft_landed_repo(ft-team-lib.sh) — 팩 리포에 sha 가 있으면 범위 대조(그대로) ·
#     카드 리포에만 있으면 «설치 파일 = 라이브» 전수 대조(--all) — 그 sha 를 팩에서 찾지 않는다(표식 = env FT_LANDED_MARKER).
#   다른 팀 indices(design/<팀>/indices) 는 범위 밖 = 통과.   exit 0 = 통과 · 1 = REJECT(이동 0) · 2 = usage   env: FT_INSTALL_CHECK = 검사 도구(시험 주입)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
CARD="${1:-}"; LANDED=""; shift 2>/dev/null || { echo "usage: $0 <카드> [--landed <A..B|sha>]" >&2; exit 2; }
[ "${1:-}" = --landed ] && LANDED="${2:-}"
[ -f "$CARD" ] || { echo "REJECT 카드 없음: $CARD"; exit 1; }
. "$HERE/ft-team-lib.sh" || { echo "REJECT ft-team-lib.sh 를 못 읽었다: $HERE (이동 0)"; exit 1; }
# R383: 하네스 팀 카드 판정 = 팀 폴더 명단(ft_team_has · 쌍둥이 둘 다) · 명단은 카드가 있는 워크트리의 것 · 못 읽으면 «통과» 로 후퇴하지 않고 REJECT
# r937 r3: 카드 리포 루트 조회도 ft_git_capped — 실패(rc≠0 · 시간 초과 포함)면 빈 값·카드 폴더로 넘어가지 않고 REJECT
WT="$(ft_git_capped 7 "$(dirname "$CARD")" rev-parse --show-toplevel)" || { _rc=$?; echo "REJECT 카드 리포($(dirname "$CARD")) 루트 조회 실패(rc=$_rc) — 통과 0 (이동 0)"; exit 1; }
FT_REPO_ROOT="$WT" ft_team_has harness "$(cd "$(dirname "$CARD")" && pwd)/$(basename "$CARD")" indices/; _hrc=$?
case "$_hrc" in 0) ;; 1) exit 0;; *) echo "REJECT 하네스 팀 폴더를 못 풀었다(design/TEAMS.md) — 카드 종류를 못 정한다 (이동 0)"; exit 1;; esac
rej() { echo "REJECT $* (이동 0)"; exit 1; }
USE="쓰는 법: 카드에 「- 설치: 있음|없음」 줄 (하네스 키트·도구·훅·데몬을 바꾸면 있음)"
LINE="$(grep -m1 -E '^[[:space:]]*-[[:space:]]*설치:' "$CARD")"
[ -n "$LINE" ] || rej "카드에 「- 설치:」 줄 없음 — $USE"
case "$LINE" in *"설치: 없음"*) echo "INFO 설치: 없음 — 라이브 대조 0"; exit 0;; *"설치: 있음"*) ;; *) rej "「- 설치:」 값은 있음|없음 — $USE";; esac
[ -n "$LANDED" ] || rej "설치: 있음 카드는 --landed <A..B|sha> 필수 — 병합 범위를 라이브와 대조한다"
case "$LANDED" in *..*) RANGE="$LANDED";; *) RANGE="${LANDED}^..$LANDED";; esac
CHK="${FT_INSTALL_CHECK:-$HERE/ft-live-install-check.sh}"
# r581: 하네스 파일 대조는 하네스 루트 리포 — 카드 워크트리 아님(도구 기본값 · 카드 리포에 팩 객체가 있으면 outside_repo 가 막는다)
# r937: 착지 리포가 카드 리포면 대조 대상을 범위로 못 정한다(그 sha 가 팩에 없다) → 라이브 전수(--all)로 «설치 파일 = 라이브»만 본다
PACKH=""; [ -f "$HERE/ft-harness-root.sh" ] && PACKH="$(. "$HERE/ft-harness-root.sh" && ft_harness_root "$HERE" 2>/dev/null)"
PACK=""; [ -n "$PACKH" ] && { PACK="$(ft_git_capped 7 "$PACKH" rev-parse --show-toplevel)" || rej "팩 리포($PACKH) 루트 조회 실패(rc=$?) — 통과 0"; }
[ -n "$PACK" ] || rej "하네스 루트를 못 풂 — 설치 대조 리포를 못 정한다(FT_HARNESS_ROOT · ../HARNESS_ROOT)"
LR="$(ft_landed_repo "${LANDED##*..}" "$WT" "$PACK" "${FT_LANDED_MARKER:-}")" || { printf '%s\n' "$LR"; exit 1; }   # r959: 표식 오기(팩 착지) 보정은 ft_landed_repo 기본 — 정본·보류 가드·close-landed 와 같은 판정
LRREPO="${LR%%$'\t'*}"
# r948 + r959: --all 은 «어느 프로젝트의 라이브» 인지 같이 넘긴다 = 카드 리포의 공용 루트(워크트리 안 카드도 루트) — 안 넘기면 검사기가 팩 리포를 프로젝트로 본다(LIVE_BIN 없음 ERROR).
# r959 ④(r426 rc3): 같은 값을 --range 갈래(팩 착지 sha)에도 넘긴다 — plist-env 렌더도 프로젝트 루트가 필요한데,--all 만 넘기면 팩 착지 카드는 rc3 로 막했다.
CROOT="$(ft_git_capped 7 "$WT" rev-parse --path-format=absolute --git-common-dir)" || rej "카드 리포($WT) 공용 루트 조회 실패(rc=$?) — 통과 0"
CROOT="$(dirname "$CROOT")"
if [ "$LRREPO" = "$PACK" ]; then CARG=(--range "$RANGE" --project "$CROOT")
else
  CARG=(--all --project "$CROOT")
  printf 'INFO 착지 리포 = 카드 리포(%s) — 설치 대조 = 라이브 전수(--all --project %s)\n' "$LRREPO" "$CROOT"
fi
# r964: FT_BIN 은 부른 쪽(close-landed → index-move 사슬)이 넣지 않는다 — 비면 «게이트가 있는 라이브 폴더»(shim 이 exec 한 판 폴더)를 넘긴다.
#   안 넘기면 대조기가 «FT_BIN 없음» rc=3 으로 끝나고, 설치가 맞아도 «라이브 설치 어긋남» 으로 오표기됐다.
COUT="$(FT_BIN="${FT_BIN:-$HERE}" bash "$CHK" "${CARG[@]}" 2>&1)"; crc=$?
case "$crc" in
  0) ;;
  # r964: rc=3 = 대조기가 대조 자체를 못 한 것(지도·ref·FT_BIN 못 풂) — «설치 어긋남» 과 다른 사유로 거절한다
  3) printf '%s\n' "$COUT"; rej "설치 대조 불가(rc=3) — $(printf '%s\n' "$COUT" | grep -m1 -E '^ERROR' || echo '대조기 ERROR 줄 없음')";;
  *) printf '%s\n' "$COUT"; rej "라이브 설치 어긋남(rc=$crc) — master 설치 뒤 다시 이동";;
esac
EV="$(grep -m1 -E '^[[:space:]]*-[[:space:]]*실사건:' "$CARD")"
[ -n "$EV" ] || rej "카드에 「- 실사건: <무엇> · <증거>」 줄 없음 — 설치 뒤 실사건 1회 실측 증거(mbox #N | 경로:줄 | ledger 키)"
printf '%s' "$EV" | grep -qE '#[0-9]+|[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+|ledger[:=][^[:space:]]+' || rej "「- 실사건:」 줄에 증거 토큰 없음(mbox #N · 경로:줄 · ledger 키)"
ROOT="${CROOT:-$WT}"   # r959: 같은 공용 루트 — 위에서 7초 상한으로 이미 풀었다(중복 git 호출 0)
PD="${FT_INSTALL_PENDING_DIR:-${ROOT:-$WT}/.fable-team/state/install-pending}"
for s in $(ft_git_capped 7 "$WT" rev-list "$RANGE"); do rm -f "$PD/$s.txt"; done
echo "OK 설치 확인 — $COUT"
