#!/usr/bin/env bash
# ft-resume-gate.sh <jsonl|세션uuid> [--max N]   (r1426)
#   리줌해도 되는 크기인가 판정한다. 큰 대화를 리줌하면 첫 요청이 통째로 «캐시 재작성»(2배)이 되어
#   소모의 40%를 태운다(r1422 실측). 넘으면 리줌하지 말고 증류(후계)로 이어간다.
#   기본 상한 = FT_RESUME_MAX(ft-thresholds.sh → 파일 없으면 thresholds.env.sample · r1860 숫자 0 · 못 읽으면 UNKNOWN rc3). 판정 대상 ctx = 마지막 usage 의 read+write+input.
#   출력 = `RESUME_OK ctx=N` rc0 · `DISTILL ctx=N max=M` rc1 · `UNKNOWN <사유>` rc3 · `REJECT` rc2(인자)
#   쓰기 0 · 네트워크 0 · 읽기만.
set -uo pipefail
for _t in "$(dirname -- "$0")/ft-thresholds.sh" "${OMC_FT_BIN:-}/ft-thresholds.sh" "$HOME/.claude/fable-team/thresholds.env"; do
  [ -f "$_t" ] || continue
  case "$_t" in *.env) set -a; . "$_t"; set +a;; *) eval "$(bash "$_t" --export 2>/dev/null)" || true;; esac
  break
done
MAX="${FT_RESUME_MAX:-}"; ARG=""
while [ $# -gt 0 ]; do case "$1" in
  --max) MAX="$2"; shift 2;; -*) echo "REJECT unknown $1" >&2; exit 2;; *) ARG="$1"; shift;; esac; done
[ -n "$ARG" ] || { echo "usage: $0 <jsonl|session-uuid> [--max N]" >&2; exit 2; }
case "$MAX" in ''|*[!0-9]*) echo "UNKNOWN 리줌 상한 못 읽음(FT_RESUME_MAX · thresholds.env.sample 없음)"; exit 3;; esac
F="$ARG"
if [ ! -f "$F" ]; then
  F="$(ls -1 "$HOME"/.claude/projects/*/"$ARG".jsonl 2>/dev/null | head -1)"
  [ -n "$F" ] && [ -f "$F" ] || { echo "UNKNOWN 대화 파일 없음: $ARG"; exit 3; }
fi
python3 - "$F" "$MAX" <<'PY'
import json, sys
path, mx = sys.argv[1], int(sys.argv[2])
best = None
try:
    fh = open(path, encoding="utf-8", errors="ignore")
except OSError as e:
    print("UNKNOWN 읽기 실패: %s" % e); sys.exit(3)
for line in fh:
    if '"usage"' not in line: continue
    try: d = json.loads(line)
    except ValueError: continue
    u = (d.get("message") or {}).get("usage") or {}
    if not u: continue
    cc = u.get("cache_creation") or {}
    c = (u.get("cache_read_input_tokens") or 0) + (cc.get("ephemeral_1h_input_tokens") or 0) \
        + (cc.get("ephemeral_5m_input_tokens") or 0) + (u.get("input_tokens") or 0)
    if c: best = c
fh.close()
if best is None:
    print("UNKNOWN usage 기록 없음"); sys.exit(3)
if best > mx:
    print("DISTILL ctx=%s max=%s" % (format(best, ","), format(mx, ","))); sys.exit(1)
print("RESUME_OK ctx=%s" % format(best, ",")); sys.exit(0)
PY
