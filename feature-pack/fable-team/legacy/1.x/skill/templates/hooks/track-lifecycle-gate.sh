#!/bin/bash
# fable-team track-lifecycle-gate — PreToolUse 강제 게이트 (트랙 개설 dedup + close 라이브증거)
# 운영규율 #1·#4의 물리화 (BYZ v6 retro §4.1 — DUP 6회·부정반전 4트랙 재정의, 유닛PASS 라이브반증 5회).
#
# [규율 #1 — 개설 dedup, fingerprint-first]
#   새 `.fable-team/state/<track>/` 디렉토리에 대한 첫 Write는 반드시 `fingerprint.md`
#   (1행=유저 가시 증상 한 줄, 2행=재현 커맨드)여야 한다. 다른 파일 먼저 → deny(+기존 지문 목록 안내).
#   fingerprint.md Write 시 기존 트랙 지문과 대조 — 증상 1행이 동일하거나 토큰 겹침 ≥60% → deny
#   ("새 트랙 금지, 기존 트랙에 라운드 append"). 같은 증상을 새 트랙명으로 재정의하는 포크를 물리 차단.
#
# [규율 #4 — close = 라이브 JSONL 필수]
#   트랙 파일에 status: done/closed 를 쓰는 Edit/Write는 그 트랙 디렉토리에 라이브 증거(*.jsonl)가
#   존재해야 통과. 없으면 deny → status: live-pending 안내. 유닛/DA PASS만으로 트랙을 닫는 완료오판 차단.
#
# 대상 도구: Write | Edit  (settings.json matcher). 판정: exit 0 허용 / exit 2 deny.
# ★ FAIL-OPEN: 파싱 오류·상태 불명은 허용. deny는 규율 위반 확신 케이스만. 훅이 세션을 brick하지 않는다.

set +e

INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

python3 - "$INPUT" <<'PYEOF'
import json, sys, os, re, glob

def allow():
    sys.exit(0)

def deny(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(2)

try:
    data = json.loads(sys.argv[1])
except Exception:
    allow()

tool = data.get("tool_name", "")
if tool not in ("Write", "Edit"):
    allow()

tin = data.get("tool_input", {}) or {}
path = tin.get("file_path") or ""
m = re.search(r'(.*?/\.fable-team/state)/([^/]+)/(.+)$', path)
if not m:
    allow()
state_dir, track, rel = m.group(1), m.group(2), m.group(3)
track_dir = os.path.join(state_dir, track)

def track_fingerprints():
    fps = {}
    try:
        for d in glob.glob(os.path.join(state_dir, "*")):
            if not os.path.isdir(d) or os.path.basename(d) == track:
                continue
            fp = os.path.join(d, "fingerprint.md")
            if os.path.isfile(fp):
                try:
                    lines = [l.strip() for l in open(fp, encoding="utf-8", errors="ignore").read().split("\n") if l.strip()]
                    if lines:
                        fps[os.path.basename(d)] = lines[0]
                except Exception:
                    pass
    except Exception:
        pass
    return fps

def toks(s):
    return set(re.findall(r'[a-z0-9가-힣]{2,}', s.lower()))

# ── 규율 #1: 새 트랙 개설 dedup (fingerprint-first) ──
try:
    is_new_track = not os.path.isdir(track_dir)
except Exception:
    is_new_track = False

if is_new_track and tool == "Write":
    fps = track_fingerprints()
    if os.path.basename(rel) != "fingerprint.md" or "/" in rel:
        listing = "\n".join("   - %s: %s" % (t, s) for t, s in sorted(fps.items())[:12]) or "   (기존 지문 없음)"
        deny(
            "🚫 [track-lifecycle-gate] 새 트랙 '%s' 개설의 첫 Write는 fingerprint.md여야 합니다(운영규율 #1 — fingerprint-first).\n"
            "   1행=유저 가시 증상 한 줄, 2행=재현 커맨드. 먼저 아래 기존 트랙 지문과 대조해 같은 대증상이면 새 트랙 금지 — 기존 트랙에 라운드 append.\n%s"
            % (track, listing)
        )
    # fingerprint.md 자체 — 내용 dedup 대조
    content = tin.get("content") or ""
    lines = [l.strip() for l in content.split("\n") if l.strip()]
    new_sym = lines[0] if lines else ""
    if new_sym:
        nt = toks(new_sym)
        for t, sym in track_fingerprints().items():
            et = toks(sym)
            if not nt or not et:
                continue
            overlap = len(nt & et) / max(1, min(len(nt), len(et)))
            if new_sym == sym or overlap >= 0.6:
                deny(
                    "🚫 [track-lifecycle-gate] 새 트랙 '%s'의 증상 지문이 기존 트랙 '%s'와 중복입니다(겹침 %.0f%%).\n"
                    "   같은 근본증상의 새 트랙명 재정의는 금지(운영규율 #1 — BYZ 실측: 부정반전 1증상이 4트랙 DA 15R로 분열).\n"
                    "→ 기존 트랙 '%s'에 라운드/서브태스크로 append하세요. 정말 다른 증상이면 지문 1행을 구체화해 재시도."
                    % (track, t, overlap * 100, t)
                )
    allow()

# ── 규율 #4: close = 라이브 JSONL 필수 ──
newtext = ""
if tool == "Write":
    newtext = tin.get("content") or ""
else:
    newtext = tin.get("new_string") or ""
if not re.search(r'status\s*[:=]\s*["\']?(done|closed|complete[d]?)\b', newtext, re.I):
    allow()

try:
    jsonls = glob.glob(os.path.join(track_dir, "**", "*.jsonl"), recursive=True)
except Exception:
    jsonls = []
if jsonls:
    allow()

deny(
    "🚫 [track-lifecycle-gate] 트랙 '%s'를 done/closed로 전환하려면 라이브 증거(*.jsonl)가 트랙 디렉토리에 있어야 합니다(운영규율 #4 — unit-PASS ≠ 완료).\n"
    "   유닛/회귀 GREEN + DA APPROVE는 중간 마일스톤일 뿐(BYZ 실측: PASS 후 라이브 반증 5회).\n"
    "→ 라이브 스팟(trusted 클릭/실발화) 통과 JSONL을 남긴 뒤 close하거나, 지금은 status: live-pending으로 기록하세요."
    % track
)
PYEOF
GATE_RC=$?
[ "$GATE_RC" = "2" ] && exit 2
exit 0
