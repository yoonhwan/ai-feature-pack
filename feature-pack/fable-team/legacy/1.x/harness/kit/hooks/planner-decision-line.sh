#!/bin/bash
# fable-team planner-decision-line — Stop (planner _master 좌석 전용 · R214 · 오빠 판정 1804)
# 왜: planner 가 «오빠께 물을 결정 N건 · 오빠가 칠 스크립트 N건» 을 세지 않아 팀 회신(graphics #91963)이 4시간 밀렸다.
# 동작: 최종 답변 첫 비어 있지 않은 줄이 `결정 인터뷰 <n>건 · 스크립트 <m>건` 으로 시작하고 n·m 이 ft-decision-count.sh 값과 같아야 통과.
#   아니면 턴 키당 block 1회 — 사유 = 도구 출력 줄 그대로(«이 줄을 첫 줄로»). 술어 재구현 0 — 숫자는 도구 한 곳에서만 나온다.
# ★영구 루프 0★ (report-coverage.sh 와 같은 규약): 같은 턴 키 2회째 · stop_hook_active · 도구/기록 실패 = 통과 + state/hook-errors.log 1줄.
# planner 가 아닌 좌석(seats-planner.json 의 _master 계보 밖)·좌석표 없음 = 무출력 통과. 등록은 planner 좌석 settings 에만(전역 0 · master 설치).
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
if [ -z "${FT_ROOT:-}" ]; then
  COMMON="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$COMMON" ] || exit 0
  FT_ROOT="$(dirname "$COMMON")"
fi
ME="${FT_SEAT:-}"
[ -z "$ME" ] && [ -n "${TMUX_PANE:-}" ] && ME="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)"
[ -n "$ME" ] || exit 0
[ -f "$FT_ROOT/.fable-team/seats-planner.json" ] || exit 0
export FT_ROOT ME INPUT
export FT_DECISION_SH="${FT_DECISION_SH:-${FT_BIN:-$FT_ROOT/.fable-team/bin}/ft-decision-count.sh}"
python3 - <<'PYEOF'
import json, os, re, subprocess, sys, tempfile, time

ROOT, ME, TOOL = os.environ["FT_ROOT"], os.environ["ME"], os.environ["FT_DECISION_SH"]
STATE = f"{ROOT}/.fable-team/state/decision-line"
LOG = f"{ROOT}/.fable-team/state/hook-errors.log"  # ft_inbox_core.HOOK_ERRORS 와 같은 파일


def log(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + f" planner-decision-line {ME}: {msg}\n")
    except OSError:
        pass
    sys.exit(0)


def text_of(rec):
    c = (rec.get("message") or {}).get("content")
    if isinstance(c, str):
        return c
    return "".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text") if isinstance(c, list) else ""


def scan(path):
    """(마지막 사용자 레코드 uuid, 그 뒤 마지막 assistant 텍스트) — 훅 피드백 user 레코드·도구결과·메타는 사용자 턴이 아니다."""
    uuid, final = None, ""
    with open(path, encoding="utf-8") as f:
        for ln in f:
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            if r.get("isSidechain") or r.get("isMeta"):
                continue
            if r.get("type") == "user" and text_of(r).strip() and not text_of(r).lstrip().startswith("Stop hook feedback"):
                uuid, final = r.get("uuid"), ""
            elif r.get("type") == "assistant" and uuid and text_of(r).strip():
                final = text_of(r)
    return uuid, final


def numbers(s):
    m = re.match(r"결정 인터뷰 (\d+)건 · 스크립트 (\d+)건", s)
    return m.groups() if m else None


try:
    with open(f"{ROOT}/.fable-team/seats-planner.json", encoding="utf-8") as f:
        master = json.load(f)["_master"]
    if ME.split("#")[0] != master.split("#")[0]:
        sys.exit(0)
    d = json.loads(os.environ["INPUT"])
    sid = re.sub(r"[^A-Za-z0-9_.-]", "_", str(d.get("session_id") or ""))
    if not sid:
        log("session_id 없음 — 통과")
    uuid, final = scan(d.get("transcript_path") or "")
    final = d["last_assistant_message"] if isinstance(d.get("last_assistant_message"), str) else final
    if not uuid:
        log("transcript 에서 사용자 턴 uuid 를 못 읽음 — 통과")
    p = subprocess.run(["bash", TOOL], capture_output=True, text=True, timeout=30)
    want = (p.stdout.strip().splitlines() or [""])[0]
    if p.returncode != 0 or not numbers(want):
        log(f"ft-decision-count rc={p.returncode} {p.stderr.strip()[:120]} — 통과")
except SystemExit:
    raise
except Exception as e:
    log(f"{type(e).__name__} {e} — 통과")
first = next((ln.strip() for ln in final.splitlines() if ln.strip()), "")
if numbers(first) == numbers(want) or d.get("stop_hook_active"):
    sys.exit(0)
key, sf = f"{sid}:{uuid}", f"{STATE}/stop-{sid}.json"
try:
    os.makedirs(STATE, exist_ok=True)
    prev = json.load(open(sf, encoding="utf-8")) if os.path.exists(sf) else {}
    if prev.get("turn_key") == key:
        sys.exit(0)
    fd, tmp = tempfile.mkstemp(dir=STATE)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump({"turn_key": key, "blocked_at": time.strftime("%Y-%m-%dT%H:%M:%S")}, f)
    os.replace(tmp, sf)
except SystemExit:
    raise
except Exception as e:
    log(f"턴 키 저장 실패 {type(e).__name__} {e} — 통과")
print(json.dumps({"decision": "block", "reason": (
    f"[planner-decision-line] 오빠께 올리는 최종 답변의 첫 줄은 현재 결정 대기열 값이어야 한다(판정 1804). 이 줄을 첫 줄로: {want} "
    "— 이 안내는 이번 턴 1회뿐이다.")}, ensure_ascii=False))
PYEOF
exit 0
