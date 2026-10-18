#!/bin/bash
# fable-team report-coverage — Stop (planner 좌석 전용 · 판정 423 ①⑤ · 설계 §2-4)
# 왜: planner 가 쪽지를 읽고도 오빠께 안 올리는 것이 26%(AUDIT-r34). 인박스 ①~④ 는 «mark + 최종 답변의 #seq» 둘 다 될 때까지 턴마다 대상이다.
# 동작: ①최종 답변의 `쪽지 #<seq>`(접두 없는 `#숫자`·PR #·Issue # = 0 · 인용 `>` 줄 제외)를 `ft-inbox.sh report` 로 보고 처리 ②`ft-inbox.sh show <me>` 에 ①~④ 미닫힘이 남으면 턴 키당 block 1회.
#   술어 재구현 0 — show 의 «미닫힘» 열만 읽는다. 턴 키 = 세션 id + 마지막 사용자 레코드 uuid(본문 파싱 0).
# ★영구 루프 0★: 같은 턴 키 2회째 · stop_hook_active · 조회/기록 실패 = 통과 + state/hook-errors.log 1줄(줄 상태는 그대로).
# 인박스 큐 파일이 없으면(팀 밖·planner 아님) 무출력 통과. 등록은 planner 좌석 settings 에만(전역 0 · master 집행).
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
STATE="$FT_ROOT/.fable-team/state/inbox"
[ -f "$STATE/${ME%%#*}.jsonl" ] || exit 0
export FT_ROOT ME STATE INPUT
export FT_INBOX_SH="${FT_INBOX_SH:-${FT_BIN:-$FT_ROOT/.fable-team/bin}/ft-inbox.sh}"
python3 - <<'PYEOF'
import json, os, re, subprocess, sys, tempfile, time

STATE, ME, INBOX = os.environ["STATE"], os.environ["ME"], os.environ["FT_INBOX_SH"]
LOG = os.path.join(os.path.dirname(STATE), "hook-errors.log")  # state/hook-errors.log = ft_inbox_core.HOOK_ERRORS 와 같은 파일
CAP = 40


def log(msg):
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + f" report-coverage {ME}: {msg}\n")
    except OSError:
        pass
    sys.exit(0)


def inbox(*args):
    p = subprocess.run([INBOX, *args], capture_output=True, text=True, timeout=30)
    if p.returncode != 0:
        raise RuntimeError(f"ft-inbox {args[0]} rc={p.returncode} {p.stderr.strip()[:120]}")
    return p.stdout


def text_of(rec):
    c = (rec.get("message") or {}).get("content")
    if isinstance(c, str):
        return c
    return "".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text") if isinstance(c, list) else ""


def scan(path):
    """(마지막 사용자 레코드 uuid, 그 뒤 마지막 assistant 텍스트). 훅 피드백 user 레코드·도구결과·메타는 사용자 턴이 아니다."""
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


def cited(text):
    body = "\n".join(l for l in text.split("\n") if not l.lstrip().startswith(">"))
    found = set()
    for m in re.finditer(r"쪽지 ?(#[0-9]{4,}(?:[·,] ?#[0-9]{4,})*)", body):  # 「쪽지 #65754·#65755」 — 접두 뒤 목록까지 한 묶음
        found.update(re.findall(r"#([0-9]{4,})", m.group(1)))
    return found


def open_seqs(out):
    got = []
    for ln in out.splitlines():
        m = re.match(r"^\[[①②③④]\] \S+ seq=(\S+) 미닫힘=(\S*) ", ln)
        if m:
            got.append((set(m.group(1).split(",")), [s for s in m.group(2).split(",") if s]))
    return got


try:
    d = json.loads(os.environ["INPUT"])
    sid = re.sub(r"[^A-Za-z0-9_.-]", "_", str(d.get("session_id") or ""))
    if not sid:
        log("session_id 없음 — 통과")
    uuid, final = scan(d.get("transcript_path") or "")
    final = d["last_assistant_message"] if isinstance(d.get("last_assistant_message"), str) else final
    if not uuid:
        log("transcript 에서 사용자 턴 uuid 를 못 읽음 — 통과")
    out = inbox("show", ME)
    listed = set().union(*[s for s, _ in open_seqs(out)], set())
    hit = sorted(cited(final) & listed, key=int)
    if hit:
        inbox("report", *hit, "--seat", ME)
        out = inbox("show", ME)
    left = sorted({s for _, o in open_seqs(out) for s in o}, key=int)
except Exception as e:
    log(f"{type(e).__name__} {e} — 통과")
if not left or d.get("stop_hook_active"):
    sys.exit(0)
key, sf = f"{sid}:{uuid}", f"{STATE}/stop-{sid}.json"
try:
    prev = json.load(open(sf, encoding="utf-8")) if os.path.exists(sf) else {}
    if prev.get("turn_key") == key:
        sys.exit(0)
    fd, tmp = tempfile.mkstemp(dir=STATE)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump({"turn_key": key, "blocked_at": time.strftime("%Y-%m-%dT%H:%M:%S")}, f)
    os.replace(tmp, sf)
except Exception as e:
    log(f"턴 키 저장 실패 {type(e).__name__} {e} — 통과")
shown = " · ".join("#" + s for s in left[:CAP]) + (f" 외 {len(left) - CAP}건" if len(left) > CAP else "")
print(json.dumps({"decision": "block", "reason": (
    f"[report-coverage] 인박스 ①~④ 미닫힘 {len(left)}건: {shown}. "
    "각 줄을 ft-inbox.sh mark <seq> 처리|위임|보류 \"1줄\" --seat <내 좌석> 으로 처리하고, 오빠께 올리는 최종 답변에 `쪽지 #seq` 로 적어라(인용 > 줄 제외). 이 안내는 이번 턴 1회뿐이다.")}, ensure_ascii=False))
PYEOF
exit 0
