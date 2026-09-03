#!/usr/bin/env bash
# ★이 파일은 git 추적 밖이다(작동 원리 — README 참조). 추적 백업: tools/comm-canonical/ · 드리프트 확인: tools/comm-canonical/check-drift.sh
# 여러 좌석에 같은 본문을 보내고 ★좌석별 도달 결과를 집계★한다.
#
# ─ 왜 스크립트여야 하나 (zsh 단어분할 재발 방지) ────────────────────────────
# 2026-09-03 첫 브로드캐스트가 ★한 좌석에도 안 갔다★. 원인은 사람이 zsh
# 프롬프트에서 직접 돌린 루프였다. 실측(같은 코드, 셸만 교체):
#
#   LIST=$(printf 'ft-a\nft-b\nft-c\n')
#   for s in $LIST      → bash 3회 / ★zsh 1회★   ← 여기가 갈린다
#   for s in $(cmd)     → bash 3회 /  zsh 3회     (안전)
#   while read <<<VAR   → bash 3회 /  zsh 3회     (안전)
#
# zsh 는 ★변수 확장★을 단어분할하지 않는다(명령치환은 한다 — 흔한 오해라
# 확인해 두었다). 그래서 `$LIST` 세 줄이 «한 좌석 이름»이 되고, 그 이름의
# 좌석은 없으므로 tmux 가 조용히 실패한다.
#
# ★리포의 .sh 파일들에는 이 형태가 없다★(전수 0줄, 양성대조로 for 문 5줄은
# 잡혔다). 즉 고칠 대상은 파일이 아니라 «사람이 손으로 치는 루프» 였다.
# 그래서 그 루프를 여기 bash 스크립트 안에 넣어 손으로 칠 이유를 없앤다.
# 아래 루프는 `while IFS= read -r` 이라 셸이 무엇이든 줄 단위로 돈다.
#
# ─ 도달 판정 ────────────────────────────────────────────────────────────────
# ft-send-verified.sh 에 위임한다(세션 jsonl 층 — 화면 판정은 미도달과 재렌더를
# 구분 못 한다. 근거는 그쪽 헤더).
#
# usage:
#   ft-broadcast.sh <regex> <text>          # 좌석 이름 정규식으로 고른다
#   ft-broadcast.sh --seats <file> <text>   # 한 줄에 한 좌석씩 적힌 파일
#   ft-broadcast.sh --dry-run <regex>       # 대상만 나열하고 보내지 않는다
set -uo pipefail

# ★`${BASH_SOURCE[0]}` 를 그대로 쓰지 않는다★ — zsh 로 실행하면 그 배열이 없어
# `parameter not set` 으로 죽는다(2026-09-03 실증). 더 나쁜 건 --dry-run 은
# 이 값을 안 써서 «통과»한다는 것 — 검증이 초록인데 실발주만 죽는다.
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SENDER="$HERE/ft-send-verified.sh"

# ★플래그는 «여러 개» 올 수 있다★ (2026-09-03 실측 결함)
#   이전엔 case 가 한 번만 돌아 `--seats <file> --dry-run` 이 이렇게 갈렸다:
#       MODE=file / SEL=<file> / ★TEXT="--dry-run"★
#   즉 «미리보기만 하겠다»는 호출이 ★플래그 문자열을 본문으로 전 좌석에 실발송★했다.
#   드라이런이 실발송이 되는 것은 이 도구에서 가장 나쁜 실패다 — 확인하려던 사람이
#   확인 대신 사고를 친다. 그래서 (a) 플래그를 루프로 걷어내고 (b) 본문 자리에
#   플래그가 오면 ★보내지 않고 죽는다★.
#   ★위치가 아니라 «값»으로 걷어낸다★ — 앞에서만 걷으면 `--seats <file> --dry-run`
#   처럼 «뒤에 붙은» 플래그가 여전히 본문 자리로 흘러든다. 사람은 플래그를 뒤에도 붙인다.
MODE=regex
DRY=0
_ARGS=()
for _a in "$@"; do
    case "$_a" in
        --seats)   MODE=file ;;
        --dry-run) DRY=1 ;;
        *)         _ARGS+=("$_a") ;;
    esac
done
set -- ${_ARGS[@]+"${_ARGS[@]}"}
SEL="${1:?regex 또는 좌석파일이 필요하다}"
TEXT="${2-}"
case "$TEXT" in
    --*) echo "BAD_TEXT '$TEXT' — 본문 자리에 플래그가 왔다. 발송하지 않는다." >&2; exit 2 ;;
esac
[ "$DRY" = 1 ] || [ -n "$TEXT" ] || { echo "text required" >&2; exit 2; }

list_seats() {
    if [ "$MODE" = file ]; then
        cat -- "$SEL"
    else
        tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -E -- "$SEL" | sort
    fi
}

SEATS="$(list_seats)"
if [ -z "$SEATS" ]; then
    # ★0건은 «대상이 없다»와 «셀렉터가 틀렸다»를 둘 다 뜻한다★. 조용히 성공하지
    # 않고, 전체 좌석 수를 양성대조로 함께 찍어 어느 쪽인지 보이게 한다.
    ALL="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | wc -l | tr -d ' ')"
    echo "NO_TARGET selector='$SEL' — 매칭 0건 (전체 좌석 ${ALL}개)" >&2
    exit 3
fi

if [ "$DRY" = 1 ]; then
    printf '%s\n' "$SEATS" | sed 's/^/  /'
    printf '총 %s 좌석\n' "$(printf '%s\n' "$SEATS" | wc -l | tr -d ' ')"
    exit 0
fi

OK=0; FAIL=0; UNV=0
FAILED=""
while IFS= read -r seat; do
    [ -n "$seat" ] || continue
    printf '── %s\n' "$seat"
    bash "$SENDER" "$seat" "$TEXT"
    rc=$?
    case "$rc" in
        0) OK=$((OK+1)) ;;
        5) UNV=$((UNV+1)); FAILED="$FAILED $seat(UNVERIFIED)" ;;
        *) FAIL=$((FAIL+1)); FAILED="$FAILED $seat(rc=$rc)" ;;
    esac
done <<EOF
$SEATS
EOF

echo
echo "도달 $OK / 미도달 $FAIL / 판정불가 $UNV"
# ★「잔여:0」을 도달로 읽지 않게★ — 실패·판정불가는 이름을 그대로 남긴다.
[ -n "$FAILED" ] && echo "확인 필요:$FAILED" >&2
[ "$FAIL" -eq 0 ] && [ "$UNV" -eq 0 ]
