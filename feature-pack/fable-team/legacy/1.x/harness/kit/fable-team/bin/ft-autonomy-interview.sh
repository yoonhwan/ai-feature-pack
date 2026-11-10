#!/usr/bin/env bash
# ft-autonomy-interview.sh — 자율 인터뷰 답 → 오빠 `!` 한 줄 (r466 · desk 가 슬랙 질문 카드 답을 받아 부른다 · 판정 1675: ON 은 오빠 `!` 만)
#   ft-autonomy-interview.sh (--for <N>h|<N>m | --until HH:MM) --level full|mid|each [--max <n> --daily <n> --code-max <n>]
#   → 검사 = ft-autonomy.sh on-check(on 과 같은 판정기 · 상태 쓰기 0) → 계획 파일 <state>/autonomy-on-<시각>-<레벨>.sh.hil
#     (`bash <bin>/ft-autonomy.sh on …` 1줄) → ft-hil.sh --add → stdout `! bash /tmp/h<N>` 1줄(60자 넘으면 REJECT · R106)
#   틀린 값 = REJECT rc 2(계획 파일 0) · 기간 없음 = REJECT(끝 시각은 인터뷰에서 정한다) · 이 도구는 on 을 부르지 않는다(좌석 경로 0 · R164)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
AUT="$HERE/ft-autonomy.sh"
die() { echo "REJECT $1" >&2; exit "${2:-2}"; }

args=() end="" lvl=""
while [ $# -gt 0 ]; do
  case "$1" in
    --for|--until) [ $# -ge 2 ] || die "$1 값 없음"; end="$1"; args+=("$1" "$2"); shift 2 ;;
    --level) [ $# -ge 2 ] || die "--level 값 없음"; lvl="$2"; args+=("$1" "$2"); shift 2 ;;
    --max|--daily|--code-max) [ $# -ge 2 ] || die "$1 값 없음"; args+=("$1" "$2"); shift 2 ;;
    *) die "알 수 없는 인자: $1 (usage: --for <N>h|--until HH:MM --level full|mid|each [--max --daily --code-max])" ;;
  esac
done
[ -n "$end" ] || die "기간 없음 — --for <N>h 또는 --until HH:MM (끝 시각은 인터뷰에서 정한다)"
[ -n "$lvl" ] || die "--level 없음 — full|mid|each (인터뷰 답 그대로)"
out="$(bash "$AUT" on-check "${args[@]}" 2>&1)" || die "값 검사 실패: ${out##*$'\n'}"
st="$(bash "$AUT" state-dir)" || die "상태 폴더를 못 풂" 1
mkdir -p "$st" || die "상태 폴더를 못 만듦: $st" 1
plan="$st/autonomy-on-$(date +%Y%m%d-%H%M%S)-$lvl.sh.hil"
{ printf '#!/usr/bin/env bash\n# r466 자율 인터뷰 답 → 오빠 `!` 한 줄(ft-autonomy-interview.sh 가 썼다 · 범위 승인까지 같이 걸린다)\n'
  printf 'bash %q on' "$AUT"; printf ' %q' "${args[@]}"; printf '\n'; } > "$plan" || die "계획 파일 쓰기 실패: $plan" 1
line="$(bash "$HERE/ft-hil.sh" --add "$plan")" || die "ft-hil.sh --add 실패" 1
line="${line##*$'\n'}"
[[ "$line" =~ ^!\ bash\ [^[:space:]]+/h[0-9]+$ ]] && [ "${#line}" -le 60 ] || die "오빠 한 줄 꼴 아님(60자 · R106): $line" 1
printf '%s\n' "$line"
