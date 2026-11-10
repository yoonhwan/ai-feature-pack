#!/usr/bin/env bash
# ft-waste-check.sh [--alert] [--hours N] [--json]   (r1431)
#   ctx-waste 를 «느슨하게» 불러 컨텍스트 낭비를 점검한다. 없으면 skip (하드 의존 0).
#   판정 = 재작성 비중 · 평균 ctx · 요청당 가중. CRITICAL 이면 --alert 로 planner 에 [긴급] 1통(desk 중계).
#   출력 1줄 = `WASTE ok|warn|critical rewrite=8% avg=120k per=41k` · rc 0(ok/warn/skip) · 1(critical) · 2(인자)
#   기본 임계: rewrite ≥35% 또는 avg ≥250k 또는 per ≥60k = critical · rewrite ≥20% 또는 avg ≥180k = warn
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOURS=6; ALERT=0; JSON=0
while [ $# -gt 0 ]; do case "$1" in
  --alert) ALERT=1; shift;; --json) JSON=1; shift;; --hours) HOURS="$2"; shift 2;; -*) shift;; *) shift;; esac; done
CW="$(command -v ft-burn 2>/dev/null || command -v ctx-waste 2>/dev/null || true)"
for c in "$HOME/.local/bin/ft-burn" "$HOME/.local/bin/ctx-waste" \
         "$HOME/Project/ai-feature-pack/feature-pack/ft-burn/bin/ft-burn"; do
  [ -n "$CW" ] && break; [ -x "$c" ] && CW="$c"
done
[ -n "$CW" ] || { echo "WASTE skip (ctx-waste 없음 — 느슨한 연결이라 실패 아님)"; exit 0; }
OUT="$("$CW" --hours "$HOURS" --json 2>/dev/null)" || { echo "WASTE skip (ctx-waste 실행 실패)"; exit 0; }
[ "$JSON" = 1 ] && { printf '%s\n' "$OUT"; exit 0; }
python3 - "$OUT" "$ALERT" <<'PY'
import json, os, subprocess, sys, time
try:
    d = json.loads(sys.argv[1]); alert = sys.argv[2] == "1"
except ValueError:
    print("WASTE skip (JSON 파싱 실패)"); sys.exit(0)
best = None
for k, v in (d.get("runtimes") or {}).items():
    s, b = v.get("stats"), v.get("burn")
    if not s or not b: continue
    tot = b.get("total") or 0
    rw = 100.0 * (b.get("rewrite") or 0) / tot if tot else 0
    per = int(tot / s["requests"]) if s.get("requests") else 0
    if best is None or rw > best[1]: best = (k, rw, s.get("avg_ctx") or 0, per, s.get("rewrites") or 0)
if not best:
    print("WASTE skip (usage 데이터 없음)"); sys.exit(0)
rt, rw, avg, per, nrew = best
crit = rw >= 35 or avg >= 250_000 or per >= 60_000
warn = rw >= 20 or avg >= 180_000
state = "critical" if crit else ("warn" if warn else "ok")
print("WASTE %s rewrite=%.0f%% avg=%dk per=%dk rewrites=%d (%s)" % (state, rw, avg / 1000, per / 1000, nrew, rt))
if crit and alert:
    seat = os.environ.get("FT_SEAT") or "ft-waste-check"
    body = ("[긴급] 컨텍스트 낭비 임계 초과 — %s\n"
            "rewrite %.0f%% · avg %dk · 요청당 %dk · 재작성 %d건 (최근 %s시간)\n"
            "조치: 리줌 상한(ft-thresholds --get FT_RESUME_MAX) 확인 · 캐시 유지 · 증류선 준수\n"
            "점검 = bash ~/.claude/fable-team/live/current/bin/ft-waste-check.sh --hours 6" % (rt, rw, avg / 1000, per / 1000, nrew, os.environ.get("FT_WASTE_HOURS", "6")))
    for mb in (os.path.join(os.environ.get("FT_ROOT", "."), ".fable-team", "comm", "mbox.sh"),):
        if os.path.isfile(mb):
            try:
                subprocess.run(["bash", mb, "send", "byz-planner-master-claude#241", seat, body], timeout=20)
                print("ALERT sent → byz-planner-master-claude#241")
            except Exception as e:
                print("ALERT 실패: %s" % e)
sys.exit(1 if crit else 0)
PY
