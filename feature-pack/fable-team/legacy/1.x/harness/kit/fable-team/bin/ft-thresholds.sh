#!/usr/bin/env bash
# ft-thresholds.sh — 증류·리줌 문턱 «한 곳» (r1427)
#   증류 게이트(context-distill-gate) · 리줌 게이트(ft-resume-gate) · 좌석 복구(ft-reboot-restore) 가 모두 이 파일 하나를 본다.
#   해석 순서(문턱 네 키 = 키마다 그 키가 있는 첫 곳 · R1 · NEWWORK 는 첫 파일 하나): ①$FT_THRESHOLDS ②<루트>/.fable-team/thresholds.env ③~/.claude/fable-team/thresholds.env ④설치본 ../templates/thresholds.env.sample(r1860 · 숫자 기본값 0 · 샘플도 없음 = rc3 판정 불가)
#   쓰기: --set KEY=V (기본 = ~/.claude/fable-team/thresholds.env · --file F 로 대상 변경) · --show 표 · --export `eval` 용 · --get KEY
#   검증: 정수만 · BLOCK > WARN · RECV ≤ BLOCK · RESUME_MAX > 0. 위반 = REJECT rc2 · 쓰기 0.
#   키: FT_DISTILL_WARN(경고) · FT_DISTILL_BLOCK(차단) · FT_DISTILL_RECV(승계 recv 차단) · FT_RESUME_MAX(리줌 상한)
#   r2051 티어: FT_DISTILL_TIER_<T>_MATCH=부분문자열[,…] · FT_DISTILL_{WARN,BLOCK,RECV}_<T>=정수(<T> = 대문자·숫자).
#     세트 = MATCH 가 있는 첫 파일(해석 순서) 한 곳에서 3값을 읽는다(env 만 키마다 우선 · 빠진 값을 다른 파일·샘플로 채우지 않음).
#     --model M = 모델 이름(소문자)에 MATCH 가 든 첫 티어(파일 순서 → env) 3값 · 매칭 0 = 지금 키 · 티어 값 빠짐·순서 위반 = 지금 키 + «티어 <T> 불완전 — 기본 세트» 1줄
#     env 로 지금 키(FT_DISTILL_RECV 등)를 명시하면 그 키는 티어보다 우선. claude 훅·pi distill-gate.ts 가 같은 규칙.
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
sget() { # R1: 키마다 env > $FT_THRESHOLDS > 루트 > 홈 > 샘플(pi distill-gate 와 같은 순서 · 빠진 키는 다음 파일에서)
  local c v=""
  for c in "${FT_THRESHOLDS:-}" "$ROOT/.fable-team/thresholds.env" "$USERFILE" "$SAMPLE"; do
    [ -n "$c" ] && [ -f "$c" ] || continue
    v="$(FT_DISTILL_WARN= FT_DISTILL_BLOCK= FT_DISTILL_RECV= FT_RESUME_MAX= get "$1" "" "$c")"; [ -n "$v" ] && break
  done
  get "$1" "$v" /dev/null; }
WARN="$(sget FT_DISTILL_WARN)"; BLOCK="$(sget FT_DISTILL_BLOCK)"
RECV="$(sget FT_DISTILL_RECV)";  RESUME="$(sget FT_RESUME_MAX)"
NEWWORK="$(get FT_DISTILL_NEWWORK "$DEF_NEWWORK")"   # 0 = 경고선(티어 고른 뒤 정한다)
tiers() { # 티어 이름 = MATCH 키가 나온 순서(파일 해석 순서 → env) · 중복 0
  { for c in "${FT_THRESHOLDS:-}" "$ROOT/.fable-team/thresholds.env" "$USERFILE" "$SAMPLE"; do
      [ -n "$c" ] && [ -f "$c" ] && sed -n 's/^[[:space:]]*FT_DISTILL_TIER_\([A-Z0-9]*\)_MATCH[[:space:]]*=.*/\1/p' "$c"; done
    compgen -v | sed -n 's/^FT_DISTILL_TIER_\([A-Z0-9]*\)_MATCH$/\1/p'; } | awk 'NF && !s[$0]++'; }
tier_ok() { # tier_ok WARN BLOCK RECV — 셋 다 정수 · BLOCK > WARN · RECV ≤ BLOCK
  local v; for v in "$@"; do case "$v" in ''|*[!0-9]*) return 1;; esac; done; [ "$2" -gt "$1" ] && [ "$3" -le "$2" ]; }
tget() { # tget KEY T — env > 티어 T 의 MATCH 가 있는 첫 파일(세트 한 곳)
  local c src=""
  for c in "${FT_THRESHOLDS:-}" "$ROOT/.fable-team/thresholds.env" "$USERFILE" "$SAMPLE"; do
    [ -n "$c" ] && [ -f "$c" ] && grep -q "^[[:space:]]*FT_DISTILL_TIER_${2}_MATCH[[:space:]]*=" "$c" && { src="$c"; break; }; done
  get "$1" "" "$src"; }
tier_pick() { # tier_pick 모델 → 첫 매칭 티어 이름(없으면 빈 출력)
  local m t s subs; m="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"; [ -n "$m" ] || return 0
  while read -r t; do
    IFS=', ' read -r -a subs <<<"$(sget "FT_DISTILL_TIER_${t}_MATCH" | tr 'A-Z' 'a-z')"
    for s in "${subs[@]:-}"; do [ -n "$s" ] && case "$m" in *"$s"*) echo "$t"; return 0;; esac; done
  done < <(tiers); }
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
TARGET="$USERFILE"; KEYV=""; POS=(); MODEL=""; TIER=""
while [ $# -gt 0 ]; do case "$1" in
  --file) TARGET="$2"; shift 2;; --file=*) TARGET="${1#--file=}"; shift;;
  --model) MODEL="${2:-}"; shift 2 || shift;; --model=*) MODEL="${1#--model=}"; shift;;
  *=*) KEYV="$1"; shift;; *) POS+=("$1"); shift;; esac; done
if [ "$cmd" != --set ] && [ -n "$MODEL" ]; then TIER="$(tier_pick "$MODEL")"; fi
if [ -n "$TIER" ]; then
  tw="$(tget "FT_DISTILL_WARN_$TIER" "$TIER")"; tb="$(tget "FT_DISTILL_BLOCK_$TIER" "$TIER")"; tr_="$(tget "FT_DISTILL_RECV_$TIER" "$TIER")"
  if tier_ok "$tw" "$tb" "$tr_"; then   # env 로 명시한 지금 키는 티어보다 우선(A4)
    [ -n "${FT_DISTILL_WARN:-}" ] || WARN="$tw"; [ -n "${FT_DISTILL_BLOCK:-}" ] || BLOCK="$tb"; [ -n "${FT_DISTILL_RECV:-}" ] || RECV="$tr_"
  else echo "티어 $TIER 불완전 — 기본 세트" >&2; TIER=""; fi
fi
[ "$NEWWORK" = 0 ] && NEWWORK="$WARN"   # 기본 = 경고선과 같은 값
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
    t=""; case "$k" in FT_DISTILL_WARN|FT_DISTILL_BLOCK|FT_DISTILL_RECV|FT_DISTILL_NEWWORK|FT_RESUME_MAX) t=-;;
      FT_DISTILL_TIER_*_MATCH) t="${k#FT_DISTILL_TIER_}"; t="${t%_MATCH}";;
      FT_DISTILL_WARN_*|FT_DISTILL_BLOCK_*|FT_DISTILL_RECV_*) t="${k##*_}";;
      *) echo "REJECT unknown key: $k" >&2; exit 2;; esac
    case "$t" in -) t="";; ''|*[!A-Z0-9]*) echo "REJECT unknown key: $k" >&2; exit 2;; esac
    case "$k" in
      *_MATCH) case "$v" in ''|*[!A-Za-z0-9._,-]*) echo "REJECT MATCH 값 = 영문·숫자·._,- 만: $v" >&2; exit 2;; esac;;
      *) case "$v" in ''|*[!0-9]*) echo "REJECT 정수 아님: $v" >&2; exit 2;; esac
         if [ -n "$t" ]; then   # 티어 값 = 쓴 뒤 대상 파일의 세 값이 다 있으면 순서 검사(BLOCK > WARN · RECV ≤ BLOCK) · 위반 = 쓰기 0
           tv() { if [ "$1" = "$k" ]; then echo "$v"; else get "$1" "" "$TARGET"; fi; }
           tw="$(tv "FT_DISTILL_WARN_$t")"; tb="$(tv "FT_DISTILL_BLOCK_$t")"; tr_="$(tv "FT_DISTILL_RECV_$t")"
           if [ -n "$tw" ] && [ -n "$tb" ] && [ -n "$tr_" ] && ! tier_ok "$tw" "$tb" "$tr_"; then
             echo "REJECT 티어 $t WARN=$tw BLOCK=$tb RECV=$tr_ (BLOCK > WARN · RECV ≤ BLOCK)" >&2; exit 2; fi
         fi;;
    esac
    mkdir -p "$(dirname "$TARGET")"; touch "$TARGET"
    if grep -q "^[[:space:]]*$k[[:space:]]*=" "$TARGET"; then
      tmp="$(mktemp)"; sed "s#^[[:space:]]*$k[[:space:]]*=.*#$k=$v#" "$TARGET" > "$tmp" && mv "$tmp" "$TARGET"
    else printf '%s=%s\n' "$k" "$v" >> "$TARGET"; fi
    echo "SET $k=$v file=$TARGET";;
  --show|--table)
    valid || exit 2
    echo "thresholds source = ${file:-$SAMPLE} (user default = $USERFILE)"
    [ -n "$MODEL" ] && echo "model = $MODEL → 세트 = ${TIER:-기본}"
    printf '  %-18s %10s   %s\n' KEY VALUE NOTE
    printf '  %-18s %10s   %s\n' FT_DISTILL_WARN "$WARN" "이상이면 매 턴 증류 경고"
    printf '  %-18s %10s   %s\n' FT_DISTILL_BLOCK "$BLOCK" "이상이면 증류 allowlist 밖 도구 차단"
    printf '  %-18s %10s   %s\n' FT_DISTILL_RECV "$RECV" "승계 도달 전 recv 차단선"
    printf '  %-18s %10s   %s\n' FT_DISTILL_NEWWORK "$NEWWORK" "이상이면 새 일(스폰) 금지 = 즉시 증류"
    printf '  %-18s %10s   %s\n' FT_RESUME_MAX "$RESUME" "넘으면 리줌 대신 증류(r1426)"
    tiers | while read -r t; do   # r2051 티어 행 = 티어마다 1행
      tw="$(tget "FT_DISTILL_WARN_$t" "$t")"; tb="$(tget "FT_DISTILL_BLOCK_$t" "$t")"; tr_="$(tget "FT_DISTILL_RECV_$t" "$t")"
      tier_ok "$tw" "$tb" "$tr_" && n="모델 이름에 MATCH 가 들면 이 세트" || n="불완전 — 기본 세트"
      printf '  %-18s %10s   %s\n' "TIER_$t" "-" "MATCH=$(sget "FT_DISTILL_TIER_${t}_MATCH") RECV=${tr_:-?} WARN=${tw:-?} BLOCK=${tb:-?} · $n"
    done;;
  *) echo "usage: $0 [--show|--export|--get KEY] [--model M] | --set KEY=VAL [--file F]" >&2; exit 2;;
esac
