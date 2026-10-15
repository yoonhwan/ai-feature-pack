#!/usr/bin/env bash
# ft-merge-gate.sh <sha> [--base-head-file <경로>] [--repo <dir>] [--remote origin] [--target main]   (R230 · 판정 1860·1862·1875)
#   병합·main push 게이트 — «후보 sha 가 현재 main 을 이미 포함하고 main 이 더한 줄을 지우지 않는가». 자율 ON/OFF 무관 · 읽기 전용(fetch 1회만).
#   ① 검사 시각에 fetch(7 s + 재시도 1 · 실패 = deny) ② 기준 헤드 파일(.fable-team/state/base-head · 1줄 40hex) 있으면 «손상 아님 + 후보의 조상» · 없음 = 이 검사만 생략
#   ③ is-ancestor <main> <sha> 거짓 = deny(ft-head-sync 로 최신화) ④ 줄 계약(ft_merge_lines.py: main 이 더한 줄이 후보에서 사라지면 deny)
#   exit 0 = ALLOW · 1 = DENY(사유 stdout) · 2 = usage. 명령 실패는 «거짓» 과 사유를 가른다(DENY … 판정 불가).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-merge-lib.sh"
SHA=""; BHF=""; REPO=""; REMOTE="origin"; TARGET="main"
usage() { echo "usage: $0 <sha> [--base-head-file <경로>] [--repo <dir>] [--remote origin] [--target main]" >&2; exit 2; }
while [ $# -gt 0 ]; do case "$1" in
  --base-head-file) [ $# -ge 2 ] || usage; BHF="$2"; shift 2;;
  --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2;;
  --remote) [ $# -ge 2 ] || usage; REMOTE="$2"; shift 2;;
  --target) [ $# -ge 2 ] || usage; TARGET="$2"; shift 2;;
  -*) usage;; *) [ -z "$SHA" ] || usage; SHA="$1"; shift;; esac; done
[ -n "$SHA" ] || usage
[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "DENY repo 를 찾을 수 없음"; exit 1; }
G() { git -C "$REPO" "$@"; }
deny() { echo "DENY $*"; exit 1; }

if [ -z "$BHF" ]; then
  COMMON="$(G rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && BHF="${FT_ROOT:-$(dirname "$COMMON")}/.fable-team/state/base-head"
fi
fm_fetch "$REPO" "$REMOTE" "$TARGET" || deny "fetch $REMOTE $TARGET 실패(7 s + 재시도 1) — main 을 못 봐서 판정 불가"
M="$(G rev-parse --verify -q "refs/remotes/$REMOTE/$TARGET^{commit}")" || deny "main(refs/remotes/$REMOTE/$TARGET) 확인 실패"
S="$(G rev-parse --verify -q "$SHA^{commit}")" || deny "후보 $SHA 가 commit 이 아니거나 없음"
SHALLOW="$(G rev-parse --is-shallow-repository 2>/dev/null)"

anc() {  # anc <a> <b> → 0 조상 · 1 아님 · 2 판정 불가(명령 실패·shallow)
  G merge-base --is-ancestor "$1" "$2" 2>/dev/null; local rc=$?
  [ "$rc" -eq 128 ] && return 2; [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ] && return 2
  [ "$rc" -eq 1 ] && [ "$SHALLOW" = true ] && return 2
  return "$rc"
}

if [ -e "$BHF" ] || [ -L "$BHF" ]; then   # ⓐ «없음» 만 생략 — 있으면 손상 구분 deny
  [ -f "$BHF" ] && [ -r "$BHF" ] || deny "기준 헤드 파일 읽기 불가: $BHF"
  [ "$(wc -l < "$BHF" | tr -d ' ')" -le 1 ] && [ "$(grep -c . "$BHF")" -eq 1 ] || deny "기준 헤드 파일 손상(빈 값 또는 2줄 이상): $BHF"
  BH="$(head -n1 "$BHF" | tr -d '[:space:]')"
  printf '%s' "$BH" | grep -Eq '^[0-9a-f]{40}$' || deny "기준 헤드 파일 손상(40hex 아님): $BHF"
  [ "$(G cat-file -t "$BH" 2>/dev/null)" = commit ] || deny "기준 헤드 $BH 가 이 저장소에 commit 으로 없음(객체 없음·commit 아님)"
  anc "$BH" "$S"; case $? in 0) ;; 1) deny "기준 헤드 ${BH:0:10} 가 후보 ${S:0:10} 의 조상이 아님 — 옛 이력 위의 세트(ft-head-sync 로 최신화 먼저)";; *) deny "기준 헤드 조상 판정 불가(명령 실패 또는 shallow) — 거짓과 다름";; esac
fi

anc "$M" "$S"; case $? in 0) ;; 1) deny "후보 ${S:0:10} 가 현재 main ${M:0:10} 을 포함하지 않음 — ft-head-sync.sh 로 최신화 먼저";; *) deny "main 포함 판정 불가(명령 실패 또는 shallow)";; esac

OUT="$(python3 -I "$HERE/ft_merge_lines.py" "$REPO" "$M" "$S")"; rc=$?
[ "$rc" -eq 0 ] || deny "${OUT#DENY }$([ "$rc" -eq 2 ] && echo ' (판정 불가 — 명령 실패)')"
echo "ALLOW sha=$S main=$M tree=$(G rev-parse "$S^{tree}") · $OUT"
