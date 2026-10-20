#!/usr/bin/env bash
# ★런타임 사본은 git 추적 밖이다(작동 원리 — README 참조). 추적 백업: harness/comm/ · 드리프트 확인: harness/comm/check-drift.sh
# 좌석에 보낸 텍스트가 ★실제로 제출됐는지★를 세션 jsonl 층에서 판정한다.
#
# ─ 왜 화면(capture-pane)으로는 안 되는가 ────────────────────────────────────
# 2026-09-03 실증. 전용 좌석(PROBE_REACH#0)에 3가지 상태를 각각 만들고 두 층의
# 값을 비교했다.
#
#   케이스                      capture-pane        jsonl user 레코드
#   A 미도달 (Enter 안 침)       DIRTY               0
#   B 도달   (제출됨)            DIRTY               +1
#   C 재렌더 (입력 없음 30초)     DIRTY               +0
#
# ★capture-pane 은 셋을 전부 DIRTY 로 찍는다★ = 세 상태를 못 가른다. 원인은
# 화면에 남는 것이 입력줄만이 아니기 때문이다 — ★이미 제출된 메시지가 대화
# 이력으로 `❯ <본문>` 형태로 계속 렌더된다★. 실물(7행):
#     ❯ PROBE-MARKER-ALPHA-not-submitted / PROBE-MARKER-BETA-submitted-ok
# 그래서 `^❯ 텍스트` 정규식은 «제출 성공» 직후에도 참이 되고, 그 위에 선
# 재전송 로직이 ★같은 발주를 두 번 투입★한다. 반대로 진짜 미도달(A)도 같은
# 값이라 사람은 「잔여:0」을 도달로 읽게 된다.
#
# jsonl 층은 다르다. 입력이 «제출»돼야만 `type=="user"` 레코드가 쓰인다.
# 화면 재렌더는 파일을 건드리지 않는다(케이스 C 증분 0).
#
# ─ 판정 대상을 어떻게 찾나 ──────────────────────────────────────────────────
# pane 의 cwd → `~/.claude/projects/<cwd 의 비영숫자를 전부 '-' 로 치환>`.
# ★치환 대상은 '/' 만이 아니다★ — `.worktrees` 의 점도 '-' 가 되어 `--worktrees`
# 가 된다. '/' 만 바꾸면 존재하지 않는 경로가 나온다(2026-09-03 실측).
# 전수 검증: tmux 좌석 59개 중 57개가 이 규칙으로 매핑됐다. 나머지 2개
# (FB_VECIDX#0/#1)는 ★비-ASCII 경로★(산업안전DB)라 규칙이 다르다 — 그 경우는
# 조용히 통과시키지 않고 UNVERIFIABLE 로 표시한다.
#
# ─ 좌석 특정: agentName 레코드로 «한다» (2026-09-03 개정) ───────────────────
# 개정 전에는 좌석을 특정하지 않고 디렉터리 전체를 마커로 훑었다. pane PID 로는
# 못 가르는 게 맞다(claude 는 jsonl 을 열어두지 않아 lsof 에 안 잡힌다). 그러나
# ★jsonl 안에 좌석명이 구조 필드로 박혀 있다★:
#     {"type":"agent-name",  "agentName":"<좌석>",  "sessionId":"<uuid>"}
#     {"type":"custom-title","customTitle":"<좌석>","sessionId":"<uuid>"}
# 표본 4좌석 전수에서 정확히 1파일씩 매칭됐다(2026-09-03 실측).
#
# ★왜 고쳐야 했나 — 디렉터리 전수 판정은 브로드캐스트를 통과시킨다★
# 실측: 한 cwd 의 jsonl 291개 중 ★20개★가 같은 브로드캐스트 본문을 담고 있었다.
# 마커를 디렉터리 전체에서 세면 «다른 좌석이 받은 것»이 내 좌석의 도달로 계산된다
# ⇒ 좌석 A 에 안 갔는데도 REACHED. 판정기가 «잡으려던 그 사고»를 통과시킨다.
# (인계 목록 ⑥ 「브로드캐스트가 SENT 를 찍고 한 좌석에도 안 갔다」가 이 경로다.)
#
# 특정에 실패하면 ★조용히 전수로 되돌아가지 않는다★ — 되돌아가되 그 사실을
# stderr 에 찍어 판정의 «폭»이 넓어졌음을 드러낸다(#0 RULE — 조용한 폴백 금지).
#
# usage: ft-reach-check.sh <session> <marker> [timeout_sec] [baseline_count]
#   exit 0 = REACHED / 4 = NOT_REACHED / 5 = UNVERIFIABLE(판정 불가, 사람 확인)
#
# ★판정기를 만들지 않는다★ — 이 스크립트는 «제출됐나» 하나만 답하고 점수·임계·
# 예외목록을 두지 않는다. 판정 불가는 통과가 아니라 별도 종료코드로 드러낸다.
set -uo pipefail

SESSION="${1:?session required}"
MARKER="${2:?marker required}"
TIMEOUT="${3:-20}"
BASELINE="${4:-}"

# ─ 좌석의 jsonl 디렉터리 ────────────────────────────────────────────────────
seat_projects_dir() {
    local cwd enc
    [ "${PI:-0}" = 1 ] && { pi_seat_dir; return; }
    cwd="$(tmux display-message -p -t "$SESSION" '#{pane_current_path}' 2>/dev/null)"
    [ -n "$cwd" ] || return 1
    # LC_ALL=C 로 고정한다. 로케일에 따라 [^A-Za-z0-9] 가 비-ASCII 를 포함/제외해
    # 같은 경로가 다른 이름으로 인코딩되면 «없는 디렉터리»를 조용히 가리킨다.
    enc="$(printf '%s' "$cwd" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"
    printf '%s/.claude/projects/%s' "$HOME" "$enc"
}

# 마커를 담은 ★제출된★ 레코드 수. type=="user" 로 한정한다 — 같은 파일에
# last-prompt·attachment 등 «입력 중»에도 쓰이는 레코드가 섞여 있어서, 그것까지
# 세면 미도달을 도달로 읽는다.
# 좌석의 jsonl 만 골라낸다. 못 고르면 빈 값(=호출자가 전수로 되돌아간다).
# 이어달리기(resume)로 uuid 가 갈리면 여러 개일 수 있으므로 목록으로 돌려준다.
seat_files() {
    local dir="$1"
    grep -lE "\"(agentName|customTitle)\":\"$(printf '%s' "$SESSION" \
        | sed 's/[][\.*^$/]/\\&/g')\"" "$dir"/*.jsonl 2>/dev/null
}

count_submitted() {
    local dir="$1"
    local cands
    [ "${PI:-0}" = 1 ] && { pi_count_submitted "$dir"; return; }
    # 1단계: 후보 좁히기. ★좌석 파일이 특정되면 거기서만 센다★ — 안 그러면 다른
    #        좌석이 받은 브로드캐스트가 내 도달로 계산된다(위 헤더 실측 20/291).
    local mine
    mine="$(seat_files "$dir")"
    if [ -n "$mine" ]; then
        cands="$(printf '%s\n' "$mine" | xargs grep -lF -- "$MARKER" 2>/dev/null)"
    else
        # 폴백은 하되 «넓어졌다»고 말한다. 조용히 넓히면 REACHED 의 뜻이 바뀐다.
        echo "  warn: 좌석 파일 특정 실패($SESSION) — 디렉터리 전수로 판정한다(다른 좌석 수신이 섞일 수 있다)" >&2
        cands="$(find "$dir" -maxdepth 1 -name '*.jsonl' -mmin -120 -print0 2>/dev/null \
                 | xargs -0 grep -lF -- "$MARKER" 2>/dev/null)"
    fi
    [ -n "$cands" ] || { echo 0; return 0; }
    # 2단계: 후보만 파싱해 user 레코드인지 본다.
    printf '%s\n' "$cands" | MARKER="$MARKER" python3 -c '
import json, os, sys
marker = os.environ["MARKER"]
n = 0
hits = []
for path in sys.stdin.read().split("\n"):
    if not path:
        continue
    try:
        fh = open(path, encoding="utf-8")
    except OSError:
        continue
    with fh:
        for line in fh:
            if marker not in line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            # ★큐잉된 제출도 «제출»이다★ (2026-09-14 실측, Seatbelt 첫 spawn):
            #   좌석이 작업 중일 때 들어간 doorbell 은 Claude Code 입력 큐로 가고, jsonl 에는
            #   `type=="user"` 가 아니라 `{"type":"queue-operation","operation":"enqueue","content":…}`
            #   (소비되면 `"remove"`) 로만 남는다. user 만 세면 «접수돼 처리 중인» 발주를 NOT_REACHED
            #   로 읽고 ring 을 또 울린다 — 실측: 같은 발주가 enqueue 2회(1차 + 재발주). 그 중복이
            #   이 스크립트가 없애려던 병이다. enqueue = UI 가 받았다 = 제출. 그래서 함께 센다.
            t = rec.get("type")
            if t == "queue-operation":
                if rec.get("operation") == "enqueue" and marker in (rec.get("content") or ""):
                    n += 1
                    hits.append(os.path.basename(path) + "(queued)")
                continue
            if t != "user":
                continue
            content = rec.get("message", {}).get("content")
            if isinstance(content, list):
                content = " ".join(
                    p.get("text", "") for p in content if isinstance(p, dict)
                )
            if isinstance(content, str) and marker in content:
                n += 1
                hits.append(os.path.basename(path))
if hits:
    sys.stderr.write("  hit: %s\n" % " ".join(sorted(set(hits))))
print(n)
'
}

# ─ pi 좌석 (r540) ─────────────────────────────────────────────────────────────
# pi 는 대화 기록을 `~/.pi/agent/sessions/--<cwd 앞 '/' 하나 빼고 '/'·'\'·':' → '-'>--/*.jsonl` 에 쓴다
# (pi session-manager 의 폴더 규칙 그대로 · 2026-10-20 실측 폴더 5개 일치). 좌석 특정 = `{"type":"session_info","name":"<좌석>"}` ·
# 제출 = `{"type":"message","message":{"role":"user","content":[{"type":"text","text":…}]}}`.
# ★첫 user 입력 전엔 파일 자체가 없다★(pi _persist: 대화가 생겨야 쓴다) — 좌석 폴더·파일이 없으면 «0 건 + 사유» 로 세고
# 뿌리 폴더가 없을 때만 UNVERIFIABLE. 좌석 파일을 못 고르면 전수로 넓히지 않는다(남의 좌석 수신을 내 도달로 세지 않는다).
# pi 판정 = FT_REACH_AGENT(호출자가 아는 에이전트)가 있으면 그 값 · 없으면 pane 자식 본체 이름이 pi.
seat_is_pi() {
    [ -n "${FT_REACH_AGENT:-}" ] && { [ "$FT_REACH_AGENT" = pi ]; return; }
    local pid
    pid="$(tmux display-message -p -t "$SESSION" '#{pane_pid}' 2>/dev/null)"
    [ -n "$pid" ] && pgrep -P "$pid" -x pi >/dev/null 2>&1
}
pi_root() { printf '%s' "${FT_PI_SESSIONS_DIR:-$HOME/.pi/agent/sessions}"; }
pi_seat_dir() {
    local cwd
    cwd="$(tmux display-message -p -t "$SESSION" '#{pane_current_path}' 2>/dev/null)"
    [ -n "$cwd" ] || return 1
    printf '%s/--%s--' "$(pi_root)" "$(printf '%s' "$cwd" | sed -e 's|^[/\\]||' -e 's|[/\\:]|-|g')"
}
pi_count_submitted() {
    local dir="$1" mine
    [ -d "$dir" ] || { echo "  pi: 좌석 대화 기록 아직 없음: $dir (pi 는 첫 제출 뒤에 파일을 만든다)" >&2; echo 0; return 0; }
    mine="$(grep -lF -- "\"name\":\"$SESSION\"" "$dir"/*.jsonl 2>/dev/null)"
    [ -n "$mine" ] || { echo "  pi: 좌석 파일 없음($SESSION) — session_info.name 일치 0 · 전수로 넓히지 않는다" >&2; echo 0; return 0; }
    printf '%s\n' "$mine" | SEAT="$SESSION" MARKER="$MARKER" python3 -c '
import json, os, sys
seat, marker = os.environ["SEAT"], os.environ["MARKER"]
n = 0
for path in sys.stdin.read().split("\n"):
    if not path:
        continue
    try:
        fh = open(path, encoding="utf-8")
    except OSError:
        continue
    named, hits = False, 0
    with fh:
        for line in fh:
            if "\"session_info\"" not in line and marker not in line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("type") == "session_info":
                named = named or rec.get("name") == seat
                continue
            msg = rec.get("message") or {}
            if rec.get("type") != "message" or msg.get("role") != "user":
                continue
            content = msg.get("content")
            if isinstance(content, list):
                content = " ".join(p.get("text", "") for p in content if isinstance(p, dict))
            if isinstance(content, str) and marker in content:
                hits += 1
    if named:
        n += hits
print(n)
'
}
PI=0; seat_is_pi && PI=1
if [ "$PI" = 1 ] && [ ! -d "$(pi_root)" ]; then
    echo "UNVERIFIABLE session=$SESSION — pi 대화 기록 뿌리 없음: $(pi_root)" >&2
    exit 5
fi
# ─ pi 좌석 끝 ─────────────────────────────────────────────────────────────────

DIR="$(seat_projects_dir)" || {
    echo "UNVERIFIABLE session=$SESSION — pane cwd 를 못 읽었다(세션 없음?)" >&2
    exit 5
}
if [ "$PI" = 0 ] && [ ! -d "$DIR" ]; then
    echo "UNVERIFIABLE session=$SESSION — jsonl 디렉터리 없음: $DIR" >&2
    echo "  (비-ASCII 경로이거나 아직 첫 프롬프트 전이다. 화면으로 폴백하지 않는다.)" >&2
    exit 5
fi

# 보내기 «전» 기준값을 재는 모드. 같은 텍스트를 두 번 보내면 이전 것과 구분이
# 안 되므로, 호출자는 send 전에 이걸로 기준을 잡고 send 후 그 값을 넘겨야 한다.
if [ -n "${FT_REACH_COUNT_ONLY:-}" ]; then
    count_submitted "$DIR" 2>/dev/null
    exit 0
fi

if [ -z "$BASELINE" ]; then
    BASELINE="$(count_submitted "$DIR" 2>/dev/null)"
fi

# jsonl 쓰기에는 지연이 있다(실측 4초 내 기록). 한 번만 보면 «아직 안 쓰임»을
# 미도달로 읽는다.
DEADLINE=$(( $(date +%s) + TIMEOUT ))
while :; do
    NOW="$(count_submitted "$DIR")"
    if [ "${NOW:-0}" -gt "${BASELINE:-0}" ]; then
        echo "REACHED session=$SESSION submitted=$NOW (baseline=$BASELINE) dir=${DIR##*/}"
        exit 0
    fi
    [ "$(date +%s)" -ge "$DEADLINE" ] && break
    sleep 2
done

echo "NOT_REACHED session=$SESSION submitted=$NOW (baseline=$BASELINE) after ${TIMEOUT}s" >&2
exit 4
