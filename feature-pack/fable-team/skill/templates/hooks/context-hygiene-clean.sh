#!/bin/bash
# fable-team context-hygiene-clean — 증류 경계 도달 시 오버플로 유발 transient 파일 정리
# context-distill-gate가 60% 경계에서 백그라운드로 호출. 컨텍스트 폭탄(대용량 로그·raw·산물)을
# **압축(gzip)**한다 — 삭제 아님(context-management 하이진 규범: zcat 열람 유지·되돌릴 수 있게).
# ★ 안전: transient 패턴만·활성(최근 수정) 제외·유저 코드/문서/.git/node_modules 불가침. FAIL-SAFE.
set +e
PROJ="${1:-$(pwd)}"
if G=$(git -C "$PROJ" rev-parse --show-toplevel 2>/dev/null); then PROJ="$G"; fi
MIN_SIZE="${OMC_HYGIENE_MIN_MB:-5}"      # MB 이상만
MIN_AGE="${OMC_HYGIENE_MIN_AGE_SEC:-300}" # 초 이상 묵힌 것만(활성 쓰기 회피)
MAX_FILES="${OMC_HYGIENE_MAX_FILES:-50}"  # 한 번에 최대 파일 수(폭주 방지)
NOW=$(date +%s 2>/dev/null || echo 0)
freed=0; n=0

# transient 후보만 (오버플로 상습범): 로그·raw·workflow journal/agent 산물.
# 경로 한정: .fable-team/state, .omc/**/logs, scratch. 유저 코드/문서/설정은 제외.
while IFS= read -r f; do
  [ "$n" -ge "$MAX_FILES" ] && break
  [ -f "$f" ] || continue
  case "$f" in
    *.gz) continue;;                                  # 이미 압축
    */.git/*|*/node_modules/*) continue;;
  esac
  # 크기
  sz=$(stat -f %z "$f" 2>/dev/null || stat -c %s "$f" 2>/dev/null || echo 0)
  [ "$sz" -lt $(( MIN_SIZE * 1024 * 1024 )) ] && continue
  # 활성(최근 수정) 제외
  mt=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo "$NOW")
  [ $(( NOW - mt )) -lt "$MIN_AGE" ] && continue
  # lsof로 열려있으면(쓰는 중) 제외
  command -v lsof >/dev/null 2>&1 && lsof -- "$f" >/dev/null 2>&1 && continue
  gzip "$f" 2>/dev/null && { freed=$(( freed + sz )); n=$(( n + 1 )); }
done < <(
  find "$PROJ/.fable-team/state" "$PROJ/.omc" 2>/dev/null \
       \( -name '*-raw.txt' -o -name '*.log' -o -name '*.jsonl' -o -name '*.output' \) -type f
)

MB=$(( freed / 1024 / 1024 ))
echo "[context-hygiene-clean] 압축 ${n}개 파일, ~${MB}MB 회수 (gzip — zcat 열람 가능). 대상=$PROJ/.fable-team/state·.omc"
exit 0
