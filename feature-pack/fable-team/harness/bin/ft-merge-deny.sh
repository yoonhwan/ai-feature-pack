#!/usr/bin/env bash
# ft-merge-deny.sh <head-sha> --branch <가지 이름> [--repo <dir>] [--deny-file <path>]   (r755)
#   «착지 금지 가지» 목록 검사 — ft-merge-land.sh 가 착지 후보(commit-tree)를 만들기 «전»에 부른다.
#   목록 = 같은 폴더 ft-merge-deny.txt (FT_MERGE_DENY_FILE·--deny-file 이 있으면 그 값)
#   한 줄 = <가지 이름 정규식><TAB><끝 sha 40hex | ->   · '#' 주석·빈 줄 허용 · 정규식은 이름 «전체» 와 일치(목록이 ^…$ 로 감싸도 그대로)
#   ⓐ PR head 가지 이름이 정규식에 걸림 → REJECT(사유에 목록 파일:줄) ⓑ 줄의 끝 sha 가 head 의 조상 → REJECT(그 가지 커밋을 품음)
#   목록 파일 없음·못 읽음·꼴 오류 = REJECT(fail-closed — 설치 누락을 조용히 통과시키지 않는다) · 주석만(빈 목록) = 통과
#   exit 0 = 통과(목록 밖) · 1 = REJECT(사유 stdout 1줄) · 2 = usage
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H=""; BR=""; REPO=""; DF="${FT_MERGE_DENY_FILE:-$HERE/ft-merge-deny.txt}"; BRGIVEN=0
usage() { echo "usage: $0 <head-sha> --branch <name> [--repo <dir>] [--deny-file <path>]" >&2; exit 2; }
while [ $# -gt 0 ]; do case "$1" in
  --branch) [ $# -ge 2 ] || usage; BR="$2"; BRGIVEN=1; shift 2;;
  --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2;;
  --deny-file) [ $# -ge 2 ] || usage; DF="$2"; shift 2;;
  -*) usage;; *) [ -z "$H" ] || usage; H="$1"; shift;; esac; done
printf '%s' "$H" | grep -Eq '^[0-9a-f]{40}$' || usage
[ "$BRGIVEN" = 1 ] || usage   # 가지 이름을 못 받으면 이름 검사가 통째로 꺼진다 — 부른 쪽 실수를 조용히 넘기지 않는다
rej() { echo "$*"; exit 1; }
[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || rej "repo 를 찾을 수 없음(가지 ${BR:-?})"
[ -f "$DF" ] && [ -r "$DF" ] || rej "착지 금지 목록을 읽을 수 없음($DF) — 목록 없이 착지 0(fail-closed)"
brhit() { case "$1" in ^*'$'*) printf '%s' "$BR" | grep -Eq -- "$1";; *) printf '%s' "$BR" | grep -Eq -- "^($1)\$";; esac; }   # R249 ft-head-skip 과 같은 꼴: 줄 1개 = 이름 전체 정규식
LN=0
while IFS= read -r raw || [ -n "$raw" ]; do
  LN=$((LN + 1)); t="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//')"
  case "$t" in ''|'#'*) continue;; esac
  pat="${t%%$'\t'*}"; [ "$pat" = "$t" ] && rej "착지 금지 목록 꼴 오류($DF:$LN — TAB 둘째 칸이 없다 · <정규식><TAB><40hex|->)"; end="${t#*$'\t'}"
  pat="$(printf '%s' "$pat" | sed 's/[[:space:]]*$//')"; end="$(printf '%s' "$end" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$pat" ] || rej "착지 금지 목록 꼴 오류($DF:$LN — 정규식 칸이 비었다 · <정규식><TAB><40hex|->)"
  case "$end" in -) ;; *) printf '%s' "$end" | grep -Eq '^[0-9a-f]{40}$' || rej "착지 금지 목록 꼴 오류($DF:$LN — 둘째 칸은 40hex 또는 '-' : $end)";; esac
  [ -z "$BR" ] || ! brhit "$pat" || rej "착지 금지 가지($BR · 목록 $DF:$LN)"
  case "$end" in -) continue;; esac
  git -C "$REPO" merge-base --is-ancestor "$end" "$H" 2>/dev/null; arc=$?
  [ "$arc" -eq 1 ] && continue
  [ "$arc" -eq 0 ] && rej "착지 금지 가지의 커밋 ${end:0:10} 을 품음(가지 ${BR:-?} · 목록 $DF:$LN)"
  rej "착지 금지 목록의 끝 sha ${end:0:10} 를 이 리포에서 확인 못 함(가지 ${BR:-?} · 목록 $DF:$LN · 그 가지를 fetch 했나)"
done < "$DF"
exit 0
