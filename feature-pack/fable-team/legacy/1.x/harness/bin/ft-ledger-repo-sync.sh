#!/usr/bin/env bash
# ft-ledger-repo-sync.sh <사본 경로>   (r503 · 뉴스·매거진이 읽는 오빠 원장 «사본 체크아웃» 을 매 회 origin/main 으로 전진)
#   사본 = 읽기 전용 detached 체크아웃(예 <루트>/.worktrees/news-ledger-main). 뉴스(ft_news_ledger·ft_news_html)·매거진(magazine_from_news.sh)이 시작에서 부른다.
#   · 가지 위(symbolic-ref 성공) = 누군가의 작업 공간 → 전진 0 + ERROR rc3
#   · 추적 파일 미커밋 수정(status --porcelain -uno) → 전진 0 + ERROR rc3 (미추적 파일 = 뉴스 html 등은 «깨끗함»)
#   · r847: ls-remote(7초) 원격 main(+ r851 r3 원장 사본 브랜치) == 원격 추적 ref → fetch 0 · 아니면 fetch(이 스크립트만 시도당 30초 · 재시도 1 = 첫 시도 출력 0바이트만 · 총 70초 안) · 실패 → ERROR rc4
#   · HEAD == origin/main → `SYNC up-to-date` · 아니면 checkout --detach origin/main → `SYNC <옛 10자>..<새 10자>` rc0
#   출력 1줄(stdout) · 삭제 0 · 되돌림 = git -C <사본> checkout --detach <옛 sha> · exit 0 정상 · 2 usage · 3 전진 거절 · 4 fetch 실패 · 1 그 밖
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-merge-lib.sh"
[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: $0 <사본 경로>" >&2; exit 2; }
REPO="$1"
# r851 r3 ①③: 원장 사본 브랜치(FT_LEDGER_FILL_BRANCH · 기본 ledger/auto · ledger/ 로 시작하는 이름만 — 그 밖 = rc1 입구 거절) — main 과 «둘 다» 묻고 받는다(뉴스 ft_news_ledger.fetch_if_stale 와 같은 두 ref)
LBR="${FT_LEDGER_FILL_BRANCH:-ledger/auto}"
case "$LBR" in ledger/?*) git check-ref-format "refs/heads/$LBR" || { echo "ERROR 원장 사본 브랜치 이름 형식 틀림: $LBR"; exit 1; } ;;
  *) echo "ERROR 원장 사본 브랜치는 ledger/ 로 시작해야 함: $LBR (main·HEAD 등 거절)"; exit 1 ;; esac
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR ledger 사본이 git 체크아웃이 아니다: $REPO"; exit 1; }
if BR="$(git -C "$REPO" symbolic-ref -q --short HEAD)"; then
  echo "ERROR ledger 사본이 가지 $BR 위 — 전진 0 ($REPO)"; exit 3
fi
DIRTY="$(git -C "$REPO" status --porcelain -uno 2>&1)" || { echo "ERROR ledger 사본 status 실패: ${DIRTY%%$'\n'*}"; exit 1; }
if [ -n "$DIRTY" ]; then
  N="$(printf '%s\n' "$DIRTY" | grep -c .)"
  FIRST="$(printf '%s\n' "$DIRTY" | head -1 | cut -c4-)"
  echo "ERROR ledger 사본 미커밋 추적 변경 $N — 전진 0 ($FIRST)"; exit 3
fi
# r847 — 원격 main sha(ls-remote 7초)가 사본 origin/main 과 같으면 fetch 0 · 묻기 실패는 fetch 로 진행(stderr 1줄)
#   fetch 는 이 스크립트만 시도당 30초(오빠 «뉴스는 30초로 상향») · TERM→1초 KILL(묶음) · 공용 fm_fetch 7초는 그대로
#   r847 r2: 단계 상한 = min(단계 상한, 남은 시간 − 유예) — SECONDS 는 정수(최대 1초 덜 셈) + TERM→KILL 유예 1 + 기동 여유 1 → «67 − SECONDS» · 0 이하 = 시작 0
#            재시도 1 = 첫 시도 stdout·stderr «둘 다 0바이트» 일 때만(파일 크기로 판정) · 출력이 있으면 그 첫 줄이 오류
TB="$(fm_timeout_bin)" || { echo "ERROR timeout/gtimeout 없음 — 상한을 걸 수 없어 fetch 거절"; exit 4; }
cap() { local c=$(( 67 - SECONDS )); [ "$c" -gt "$1" ] && c="$1"; echo "$c"; }
C="$(cap 7)"
RAW="$([ "$C" -gt 0 ] && "$TB" -k 1 "$C" git -C "$REPO" ls-remote origin refs/heads/main "refs/heads/$LBR" 2>/dev/null)" || RAW=""
LS="$(printf '%s\n' "$RAW" | awk -F'\t' '$2=="refs/heads/main"{print $1; exit}')"
LSB="$(printf '%s\n' "$RAW" | awk -F'\t' -v r="refs/heads/$LBR" '$2==r{print $1; exit}')"
[ -n "$LS" ] || echo "WARN ls-remote 실패 — fetch 로 진행 ($REPO)" >&2
C="$(cap 7)"
LOCAL="$([ "$C" -gt 0 ] && "$TB" -k 1 "$C" git -C "$REPO" rev-parse --verify -q refs/remotes/origin/main 2>/dev/null)" || LOCAL=""
C="$(cap 7)"
LOCALB="$([ "$C" -gt 0 ] && "$TB" -k 1 "$C" git -C "$REPO" rev-parse --verify -q "refs/remotes/origin/$LBR" 2>/dev/null)" || LOCALB=""
if [ -z "$LS" ] || [ "$LS" != "$LOCAL" ] || [ "$LSB" != "$LOCALB" ]; then
  FO="$(mktemp)" FE="$(mktemp)" || { echo "ERROR ledger 사본 fetch 출력 임시 파일 못 만듦"; exit 4; }
  trap 'rm -f "$FO" "$FE"' EXIT
  ERR="fetch 시도 0"
  for TRY in 1 2; do
    CAP="$(cap 30)"
    [ "$CAP" -gt 0 ] || { ERR="총 마감 70초 안에 시도 못 함"; break; }
    "$TB" -k 1 "$CAP" git -c gc.auto=0 -C "$REPO" fetch --quiet origin main '+refs/heads/ledger/*:refs/remotes/origin/ledger/*' > "$FO" 2> "$FE" && { ERR=""; break; }
    RC=$?
    FIRST="$(head -n 1 "$FE")"; [ -n "$FIRST" ] || FIRST="$(head -n 1 "$FO")"
    case "$RC" in 124|137) ERR="시도 상한 ${CAP}초 초과${FIRST:+ · $FIRST}";; *) ERR="${FIRST:-rc=$RC 출력 없음}";; esac
    if [ -s "$FO" ] || [ -s "$FE" ]; then break; fi  # 출력이 있는 실패 = 확정 실패 · 재시도 0(첫 출력 전 실패만 재시도)
  done
  [ -z "$ERR" ] || { echo "ERROR ledger 사본 fetch 실패: $ERR"; exit 4; }
fi
OLD="$(git -C "$REPO" rev-parse HEAD)" || exit 1
NEW="$(git -C "$REPO" rev-parse --verify -q 'origin/main^{commit}')" || { echo "ERROR ledger 사본에 origin/main 없음 ($REPO)"; exit 1; }
# 판 = 사본 브랜치가 main 을 품으면(앞섬) 그 브랜치 · 없거나 뒤처짐 = origin/main (뉴스 ft_ledger_fill_src.read_ref 와 같은 규칙)
if BRS="$(git -C "$REPO" rev-parse --verify -q "refs/remotes/origin/$LBR^{commit}")" && git -C "$REPO" merge-base --is-ancestor "$NEW" "$BRS"; then NEW="$BRS"; fi
[ "$OLD" = "$NEW" ] && { echo "SYNC up-to-date ${NEW:0:10}"; exit 0; }
OUT="$(git -C "$REPO" checkout -q --detach "$NEW" 2>&1)" || { echo "ERROR ledger 사본 checkout 실패: ${OUT%%$'\n'*}"; exit 1; }
echo "SYNC ${OLD:0:10}..${NEW:0:10}"
