#!/usr/bin/env bash
# ft-thresholds.sh — 증류·리줌 문턱 «한 곳» (r1427)
#   증류 게이트(context-distill-gate) · 리줌 게이트(ft-resume-gate) · 좌석 복구(ft-reboot-restore) 가 모두 이 파일 하나를 본다.
#   해석 순서(먼저 있는 것 하나): ①$FT_THRESHOLDS ②<루트>/.fable-team/thresholds.env ③~/.claude/fable-team/thresholds.env ④설치본 ../templates/thresholds.env.sample(r1860 · 숫자 기본값 0 · 샘플도 없음 = rc3 판정 불가)
#   쓰기: --set KEY=V (기본 = ~/.claude/fable-team/thresholds.env · --file F 로 대상 변경) · --show 표 · --export `eval` 용 · --get KEY
#   검증: 정수만 · BLOCK > WARN · RECV ≤ BLOCK · RESUME_MAX > 0. 위반 = REJECT rc2 · 쓰기 0.
#   키: FT_DISTILL_WARN(경고) · FT_DISTILL_BLOCK(차단) · FT_DISTILL_RECV(승계 recv 차단) · FT_RESUME_MAX(리줌 상한)
set -uo pipefail
DEF_NEWWORK=0   # 0 = 경고선과 같은 값(문턱 숫자 아님)
SAMPLE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)/templates/thresholds.env.sample"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../.." && pwd 2>/dev/null || echo "$PWD")"
USERFILE="$HOME/.claude/fable-team/thresholds.env"
file=""
for c in "${FT_THRESHOLDS:-}" "$ROOT/.fable-team/thresholds.env" "$USERFILE"; do
  [ -n "$c" ] && [ -f "$c" ] && { file="$c"; break; }
done
get() { # get KEY DEFAULT [FILE] — 우선순위: 명시 env > 파일 > 기본값 (시험·임시 override 가 파일을 이긴다)
  local k="$1" d="$2" f="${3:-$file}" v="" e=""
  eval "e=\${$k:-}"
  if [ -n "$e" ]; then printf '%s' "$e"; return; fi
  [ -n "$f" ] && [ -f "$f" ] && v="$(sed -n "s/^[[:space:]]*$k[[:space:]]*=[[:space:]]*//p" "$f" | tail -1 | tr -d '"'"'"' \r')"
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$d"
}
sget() { get "$1" "$(FT_DISTILL_WARN= FT_DISTILL_BLOCK= FT_DISTILL_RECV= FT_RESUME_MAX= get "$1" "" "$SAMPLE")"; }   # 파일 값 없으면 샘플 값
WARN="$(sget FT_DISTILL_WARN)"; BLOCK="$(sget FT_DISTILL_BLOCK)"
RECV="$(sget FT_DISTILL_RECV)";  RESUME="$(sget FT_RESUME_MAX)"
NEWWORK="$(get FT_DISTILL_NEWWORK "$DEF_NEWWORK")"; [ "$NEWWORK" = 0 ] && NEWWORK="$WARN"   # 기본 = 경고선과 같은 값
valid() {
  for v in "$WARN" "$BLOCK" "$RECV" "$RESUME" "$NEWWORK"; do case "$v" in ''|*[!0-9]*) echo "REJECT 정수 아님: $v" >&2; return 2;; esac; done
  [ "$BLOCK" -gt "$WARN" ] || { echo "REJECT BLOCK($BLOCK) <= WARN($WARN)" >&2; return 2; }
  [ "$RECV" -le "$BLOCK" ] || { echo "REJECT RECV($RECV) > BLOCK($BLOCK)" >&2; return 2; }
  [ "$RESUME" -gt 0 ] || { echo "REJECT RESUME_MAX($RESUME) <= 0" >&2; return 2; }
  return 0
}
cmd="${1:---show}"; shift || true
if [ "$cmd" != --set ] && { [ -z "$WARN" ] || [ -z "$BLOCK" ] || [ -z "$RECV" ] || [ -z "$RESUME" ]; }; then
  echo "UNKNOWN 문턱 못 읽음(파일·샘플 없음: $SAMPLE)" >&2; exit 3; fi
TARGET="$USERFILE"; KEYV=""; POS=()
while [ $# -gt 0 ]; do case "$1" in
  --file) TARGET="$2"; shift 2;; --file=*) TARGET="${1#--file=}"; shift;;
  *=*) KEYV="$1"; shift;; *) POS+=("$1"); shift;; esac; done
case "$cmd" in
  --export)
    valid || exit 2
    printf 'export FT_DISTILL_WARN=%s FT_DISTILL_BLOCK=%s FT_DISTILL_RECV=%s FT_DISTILL_NEWWORK=%s FT_RESUME_MAX=%s\n' "$WARN" "$BLOCK" "$RECV" "$NEWWORK" "$RESUME";;
  --get) valid >/dev/null 2>&1; key="${POS[0]:-}"; case "$key" in
      FT_DISTILL_WARN) echo "$WARN";; FT_DISTILL_BLOCK) echo "$BLOCK";; FT_DISTILL_RECV) echo "$RECV";; FT_DISTILL_NEWWORK) echo "$NEWWORK";; FT_RESUME_MAX) echo "$RESUME";;
      *) echo "REJECT unknown key: $key" >&2; exit 2;; esac;;
  --set)
    [ -n "$KEYV" ] || { echo "usage: $0 --set KEY=VALUE [--file F]" >&2; exit 2; }
    k="${KEYV%%=*}"; v="${KEYV#*=}"
    case "$k" in FT_DISTILL_WARN|FT_DISTILL_BLOCK|FT_DISTILL_RECV|FT_DISTILL_NEWWORK|FT_RESUME_MAX) ;; *) echo "REJECT unknown key: $k" >&2; exit 2;; esac
    case "$v" in ''|*[!0-9]*) echo "REJECT 정수 아님: $v" >&2; exit 2;; esac
    mkdir -p "$(dirname "$TARGET")"; touch "$TARGET"
    if grep -q "^[[:space:]]*$k[[:space:]]*=" "$TARGET"; then
      tmp="$(mktemp)"; sed "s#^[[:space:]]*$k[[:space:]]*=.*#$k=$v#" "$TARGET" > "$tmp" && mv "$tmp" "$TARGET"
    else printf '%s=%s\n' "$k" "$v" >> "$TARGET"; fi
    echo "SET $k=$v file=$TARGET";;
  --show|--table)
    valid || exit 2
    echo "thresholds source = ${file:-$SAMPLE} (user default = $USERFILE)"
    printf '  %-18s %10s   %s\n' KEY VALUE NOTE
    printf '  %-18s %10s   %s\n' FT_DISTILL_WARN "$WARN" "이상이면 매 턴 증류 경고"
    printf '  %-18s %10s   %s\n' FT_DISTILL_BLOCK "$BLOCK" "이상이면 증류 allowlist 밖 도구 차단"
    printf '  %-18s %10s   %s\n' FT_DISTILL_RECV "$RECV" "승계 도달 전 recv 차단선"
    printf '  %-18s %10s   %s\n' FT_DISTILL_NEWWORK "$NEWWORK" "이상이면 새 일(스폰) 금지 = 즉시 증류"
    printf '  %-18s %10s   %s\n' FT_RESUME_MAX "$RESUME" "넘으면 리줌 대신 증류(r1426)";;
  *) echo "usage: $0 [--show|--export|--get KEY|--set KEY=VAL [--file F]]" >&2; exit 2;;
esac
