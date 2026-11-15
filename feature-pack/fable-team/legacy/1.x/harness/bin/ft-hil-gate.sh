#!/usr/bin/env bash
# ft-hil-gate.sh — h 진입 파일 sha 잠금 · 다시 등록 · 걸린 초 보조 (r2078 · 실사건 #309264 GO 뒤 계획 수정 · #309281 70초 넘김). ft-hil.sh 와 진입 파일이 부른다.
#   write <계획> <h 파일>             → <h>.sha 에 계획 sha256(64자) 1줄 · 못 구함 = «판정 불가» rc 3
#   check <계획> <h 파일>             → <h>.sha 없음 = rc 0(설치 전 h) · 같음 = rc 0 · 다름 = REJECT 1줄 rc 1 · 못 구함 = 판정 불가 rc 3
#   reuse <계획> <h 파일> [대체 번호]  → 같은 경로 다시 등록: stdout = 다시 쓸 번호(sha 없음 = 지금 적고 그 번호 · 같음 = 그 번호)
#                                       다름 + 대체 번호 = 그 h 번호 → 빈 줄(새 번호 발급) · 다름 + 대체 없음 = REJECT rc 1
#   budget <계획> <h 파일> [시작 끝]  → .ran 마지막 시작 줄 · rc 줄 시각 차(시험은 인자로 시각 주입)가 선언 초(`# ft-hil-budget: <초>` · 없으면 70)를 넘으면
#                                       `[상한 초과] …` 1줄을 stderr 와 <h>.out 끝에 · 늘 rc 0(계획 rc 는 진입 파일이 그대로 낸다)
set -uo pipefail
sha() {  # <파일> → sha256 64자(못 구하면 rc 3 · 판정 불가 1줄)
  local s
  if command -v shasum >/dev/null 2>&1; then s="$(shasum -a 256 < "$1" 2>/dev/null)"; else s="$(sha256sum < "$1" 2>/dev/null)"; fi
  s="${s%% *}"; [[ "$s" =~ ^[0-9a-f]{64}$ ]] || { echo "판정 불가 — 계획 sha256 을 못 구함: $1" >&2; return 3; }
  echo "$s"
}
old() { head -1 "$1.sha" 2>/dev/null; }
case "${1:-}" in
  write) s="$(sha "$2")" || exit 3; echo "$s" > "$3.sha" || { echo "판정 불가 — sha 표식을 못 씀: $3.sha" >&2; exit 3; } ;;
  check)
    [ -f "$3.sha" ] || exit 0
    s="$(sha "$2")" || exit 3; o="$(old "$3")"
    [ "$s" = "$o" ] || { echo "REJECT 계획이 등록 뒤 바뀜 — 등록 ${o:0:16} ≠ 지금 ${s:0:16} · 다시 등록(--add $2 --supersedes ${3##*/})" >&2; exit 1; } ;;
  reuse)
    n="${3##*/h}"
    [ -f "$3.sha" ] || { bash "$0" write "$2" "$3" || exit 3; echo "$n"; exit 0; }
    s="$(sha "$2")" || exit 3; o="$(old "$3")"
    if [ "$s" = "$o" ]; then echo "$n"
    elif [ "${4:-}" = "$n" ]; then echo ""
    else echo "REJECT 계획이 바뀜 — h$n 등록 ${o:0:16} ≠ 지금 ${s:0:16} · --supersedes h$n 을 붙여 다시 등록" >&2; exit 1; fi ;;
  budget)
    b="$(sed -n 's/^[[:space:]]*#[[:space:]]*ft-hil-budget:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p' "$2" 2>/dev/null | head -1)"; b="${b:-70}"
    st="${4:-$(sed -n '/^[0-9][0-9]*$/h; ${x;p;}' "$3.ran" 2>/dev/null)}"
    en="${5:-$(tail -n 1 "$3.ran" 2>/dev/null | sed -n 's/^rc=[0-9]* \([0-9][0-9]*\)$/\1/p')}"
    [[ "$st" =~ ^[0-9]+$ && "$en" =~ ^[0-9]+$ ]] || exit 0
    e=$((en - st)); [ "$e" -gt "$((10#$b))" ] || exit 0
    l="[상한 초과] ${3##*/} ${e}초 > $((10#$b))초 — 묶음을 줄여 다시 등록"
    echo "$l" >&2; echo "$l" >> "$3.out" ;;
  *) echo "usage: ft-hil-gate.sh write|check|reuse|budget <계획> <h 파일> [...]" >&2; exit 2 ;;
esac
