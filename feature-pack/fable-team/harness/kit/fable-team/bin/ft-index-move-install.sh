#!/usr/bin/env bash
# ft-index-move-install.sh <카드> [--landed <A..B|sha>]   (R245 · ft-index-move.sh 진행→완성 «전»에 호출 — ft-index-move-canon.sh 처럼 분리)
#   병합 ≠ 끝: 하네스 키트 단위는 «라이브 설치 cmp0 + 실사건 1회 실측» 까지가 완료다.
#   design/harness/indices/ 카드: `- 설치: 있음|없음` 줄 필수. 없음 = 통과. 있음 = --landed 필수 → ft-live-install-check.sh --range 가 OK 이고
#   `- 실사건: <무엇> · <증거: mbox #N | 경로:줄 | ledger 키>` 줄에 증거 토큰이 있어야 통과. 통과하면 그 범위 sha 의 install-pending 파일을 지운다.
#   대조는 origin/main tip — --landed 는 «대상 파일»만 정한다(뒤 커밋이 같은 파일을 또 고쳐도 라이브=tip 이면 OK · R367).
#   다른 팀 indices(design/<팀>/indices) 는 범위 밖 = 통과.   exit 0 = 통과 · 1 = REJECT(이동 0) · 2 = usage   env: FT_INSTALL_CHECK = 검사 도구(시험 주입)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
CARD="${1:-}"; LANDED=""; shift 2>/dev/null || { echo "usage: $0 <카드> [--landed <A..B|sha>]" >&2; exit 2; }
[ "${1:-}" = --landed ] && LANDED="${2:-}"
[ -f "$CARD" ] || { echo "REJECT 카드 없음: $CARD"; exit 1; }
case "$CARD" in */design/harness/indices/*) ;; *) exit 0;; esac
rej() { echo "REJECT $* (이동 0)"; exit 1; }
USE="쓰는 법: 카드에 「- 설치: 있음|없음」 줄 (하네스 키트·도구·훅·데몬을 바꾸면 있음)"
LINE="$(grep -m1 -E '^[[:space:]]*-[[:space:]]*설치:' "$CARD")"
[ -n "$LINE" ] || rej "카드에 「- 설치:」 줄 없음 — $USE"
case "$LINE" in *"설치: 없음"*) echo "INFO 설치: 없음 — 라이브 대조 0"; exit 0;; *"설치: 있음"*) ;; *) rej "「- 설치:」 값은 있음|없음 — $USE";; esac
[ -n "$LANDED" ] || rej "설치: 있음 카드는 --landed <A..B|sha> 필수 — 병합 범위를 라이브와 대조한다"
WT="$(git -C "$(dirname "$CARD")" rev-parse --show-toplevel 2>/dev/null || dirname "$CARD")"
case "$LANDED" in *..*) RANGE="$LANDED";; *) RANGE="${LANDED}^..$LANDED";; esac
CHK="${FT_INSTALL_CHECK:-$HERE/ft-live-install-check.sh}"
COUT="$(bash "$CHK" --range "$RANGE" --repo "$WT" 2>&1)"; crc=$?
[ "$crc" -eq 0 ] || { printf '%s\n' "$COUT"; rej "라이브 설치 어긋남(rc=$crc) — master 설치 뒤 다시 이동"; }
EV="$(grep -m1 -E '^[[:space:]]*-[[:space:]]*실사건:' "$CARD")"
[ -n "$EV" ] || rej "카드에 「- 실사건: <무엇> · <증거>」 줄 없음 — 설치 뒤 실사건 1회 실측 증거(mbox #N | 경로:줄 | ledger 키)"
printf '%s' "$EV" | grep -qE '#[0-9]+|[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+|ledger[:=][^[:space:]]+' || rej "「- 실사건:」 줄에 증거 토큰 없음(mbox #N · 경로:줄 · ledger 키)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
PD="${FT_INSTALL_PENDING_DIR:-${ROOT:-$WT}/.fable-team/state/install-pending}"
for s in $(git -C "$WT" rev-list "$RANGE" 2>/dev/null); do rm -f "$PD/$s.txt"; done
echo "OK 설치 확인 — $COUT"
