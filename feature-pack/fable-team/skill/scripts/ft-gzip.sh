#!/bin/bash
# ft-gzip.sh — auto_gzip 강제부: 비활성 로그 무손실 압축 래퍼 (§1-3⑥)
# Usage: ft-gzip.sh <file> [--op-token <path>]
# Exit: 0 압축·검증 통과 / 1 대상 검증 위반(조치 없음) / 3 APPROVAL_REQUIRED
# 삭제는 절대 하지 않는다(무손실 압축만).
set +e
LIB="$(cd "$(dirname "$0")" && pwd)/ft-lib.sh"; . "$LIB"

FILE="" OP_TOKEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --op-token) OP_TOKEN="$2"; shift 2;;
    *) FILE="$1"; shift;;
  esac
done
[ -n "$FILE" ] || { echo "ft-gzip: <file> 필수" >&2; exit 1; }
ROOT="$(ft_resolve_root "")"

# ⓪ 승인 판정 (standing.auto_gzip 또는 op-token op=gzip·target 일치)
ft_check_approval "$ROOT" gzip "$FILE" "$OP_TOKEN"
[ $? -eq 0 ] || { echo "ft-gzip: APPROVAL_REQUIRED $FILE" >&2; exit 3; }

# ① 대상 검증: 프로젝트 내부 + 확장자 .log|.jsonl + lsof 무점유 + mtime>24h
abs_file="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd)/$(basename "$FILE")"
abs_root="$(cd "$ROOT" 2>/dev/null && pwd)"
case "$abs_file" in
  "$abs_root"/*) ;;
  *) echo "ft-gzip: 프로젝트 외부 경로 거부: $FILE" >&2; exit 1;;
esac
case "$FILE" in
  *.log|*.jsonl) ;;
  *) echo "ft-gzip: 허용 확장자(.log|.jsonl) 아님: $FILE" >&2; exit 1;;
esac
[ -f "$FILE" ] || { echo "ft-gzip: 파일 부재: $FILE" >&2; exit 1; }
if lsof -- "$FILE" >/dev/null 2>&1; then
  echo "ft-gzip: lsof 점유 중 — 거부: $FILE" >&2; exit 1
fi
# mtime > 24h
now="$(date +%s)"
mt="$(stat -f %m "$FILE" 2>/dev/null || stat -c %Y "$FILE" 2>/dev/null)"
if [ -z "$mt" ] || [ $((now - mt)) -lt 86400 ]; then
  echo "ft-gzip: mtime 24h 이내 — 거부: $FILE" >&2; exit 1
fi

# ② gzip 후 무결성 검증(gzip -t). 실패 시 원본 보존.
size_before="$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')"
gzip "$FILE" 2>/dev/null || { echo "ft-gzip: gzip 실패(원본 보존): $FILE" >&2; exit 1; }
if ! gzip -t "$FILE.gz" 2>/dev/null; then
  # 무결성 실패 → 복원 시도
  gunzip "$FILE.gz" 2>/dev/null
  echo "ft-gzip: 무결성 검증 실패(gzip -t) — 원본 복원: $FILE" >&2; exit 1
fi
size_after="$(wc -c < "$FILE.gz" 2>/dev/null | tr -d ' ')"

# ③ audit append
ft_append "$(ft_global_signals "$ROOT")/gzip-audit.log" "$now $FILE ${size_before:-?} ${size_after:-?}"
echo "GZIPPED $FILE.gz ($size_before -> $size_after)"
exit 0
