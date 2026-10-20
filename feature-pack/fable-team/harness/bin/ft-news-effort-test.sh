#!/usr/bin/env bash
# ft-news-effort-test.sh — 뉴스 HTML 모드(r478) effort(변형) 비교표: 같은 입력 묶음으로 변형마다 `ft_news_html.py run` 1회 → 표 1장.
#   ft-news-effort-test.sh --variants "<v1>,<v2>[,<v3>]" --input <input.json> [--table <표.md>]
#   변형 = opencode `--model <ID>#<변형>`(r563: 변형은 CLI 경로 전용 → 기본 FT_NEWS_VIA=opencode) · `base` = 변형 없음 · `depth:<문장>` = 변형 없이 프롬프트 «깊이» 문장(FT_NEWS_DEPTH · 변형이 안 먹을 때 대체)
#   표 열: 변형 · 걸린 초 · rc · 린트 · 중요한 일 수 · 요약 B · 사람 점수(빈 칸 — 오빠·desk 가 채움). 기본값 결정 줄도 사람 손(막는 장치 0).
#   산출 HTML·요약·로그 = <표 이름>-files/<순번>/ (사람이 열어 보고 점수) · 외부 호출 = 변형마다 opencode run 1회(70초 총 마감)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIANTS="" INPUT="" TABLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --variants) VARIANTS="${2:-}"; shift 2 ;;
    --input) INPUT="${2:-}"; shift 2 ;;
    --table) TABLE="${2:-}"; shift 2 ;;
    *) echo "usage: $0 --variants \"v1,v2[,v3]\" --input <input.json> [--table <표.md>]" >&2; exit 2 ;;
  esac
done
[ -n "$VARIANTS" ] && [ -f "$INPUT" ] || { echo "usage: $0 --variants \"v1,v2[,v3]\" --input <input.json> [--table <표.md>]" >&2; exit 2; }
TABLE="${TABLE:-./EFFORT-news-html-$(date +%Y%m%d).md}"
FILES="${TABLE%.md}-files"
mkdir -p "$FILES"
{
  echo "# 뉴스 HTML effort 비교 — $(date '+%Y-%m-%d %H:%M')"
  echo
  echo "- 입력: \`$INPUT\` ($(wc -c < "$INPUT" | tr -d ' ') B) · 모델: \`${FT_NEWS_MODEL:-opencode/deepseek-v4.1-flash-free}\` · 산출: \`$FILES/\`"
  echo
  echo "| 변형 | 걸린 초 | rc | 린트 | 중요한 일 수 | 요약 B | 사람 점수 |"
  echo "|---|---|---|---|---|---|---|"
} > "$TABLE"
i=0
IFS=',' read -r -a LIST <<< "$VARIANTS"
for v in "${LIST[@]}"; do
  i=$((i + 1)); dir="$FILES/$i"; mkdir -p "$dir"
  eff="$v" depth=""
  case "$v" in base) eff="" ;; depth:*) eff="" depth="${v#depth:}" ;; esac
  t0=$(python3 -c 'import time; print(time.time())')
  FT_NEWS_VIA="${FT_NEWS_VIA:-opencode}" FT_NEWS_EFFORT="$eff" FT_NEWS_DEPTH="$depth" python3 "$HERE/ft_news_html.py" run --input "$INPUT" --out "$dir" > "$dir/run.log" 2>&1
  rc=$?
  secs=$(python3 -c "import time; print(f'{time.time() - $t0:.1f}')")
  html=$(ls "$dir"/*.html 2>/dev/null | head -1) sum=$(ls "$dir"/*.summary.txt 2>/dev/null | head -1)
  lint="-" imp="-" bytes="-"
  if [ -n "$html" ] && [ -n "$sum" ]; then
    lint=$(python3 "$HERE/ft_news_html_lint.py" "$html" "$sum" | head -1)
    imp=$(python3 -c 'import re,sys; s=open(sys.argv[1],encoding="utf-8").read(); m=re.search(r"<section class=\"prio\">(.*?)</section>",s,re.S); print(len(re.findall(r"<li[ >]",m[1])) if m else 0)' "$html")
    bytes=$(wc -c < "$sum" | tr -d ' ')
  else
    lint="실패: $(tail -1 "$dir/run.log" | tr '|' '/' | cut -c1-120)"
  fi
  echo "| $v | $secs | $rc | $lint | $imp | $bytes |  |" >> "$TABLE"
  echo "ft-news-effort-test: $v secs=$secs rc=$rc lint=$lint"
done
{ echo; echo "- 기본값 결정(사람 1줄): "; } >> "$TABLE"
echo "ft-news-effort-test: 표 $TABLE"
