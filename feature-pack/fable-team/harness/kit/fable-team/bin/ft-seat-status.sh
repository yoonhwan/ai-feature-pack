#!/bin/bash
# 좌석 busy/IDLE/정지 판정 — 눈대중 금지, 이 스크립트가 정본.
# 추적 사본: scripts/fable-team-bin/ft-seat-status.sh · 런타임 자리: <워크트리>/.fable-team/bin/ (gitignore)
#
# 2026-09-01 신설 (오빠: "또 안멈춰있게 체크루프 모니터링 확실히")
# 배경: master 가 pane 캡처에서 'esc to interrupt' 같은 문자열을 잡아
#   IDLE 좌석을 "작업중"으로 두 번 오판했고, 그때마다 좌석이 놀았다.
#
# 2026-09-14 Seatbelt 0.4 — pane 층의 역할을 낮춘다 (삭제 아님).
#   pane 스피너는 ghost `❯` 텍스트·재렌더·단어 변경에 오판한다(ft-reach-check.sh 헤더 A/B/C 실측표).
#   «기록» 층은 세션 jsonl(~/.claude/projects/<cwd 인코딩>/<uuid>.jsonl, 좌석명은 agentName/customTitle 레코드).
#   ★한 좌석에 jsonl 이 여러 개(resume 계보)★ — `grep -l | head -1` 은 가장 오래된 파일을 잡는다
#   (ft-v65-arch-fable#40: 250463s 로 나왔는데 오늘 활동). 반드시 mtime 최신 파일의 age 를 쓴다.
#
# 판정식(고정):
#   PANE BUSY = pane 에 진행 스피너 토큰이 있다 (Claude Code 는 작업 중에만 찍는다) / IDLE = 없다
#   JSONL_AGE = 좌석명 매칭 jsonl 중 mtime 최신 파일의 age(초). 매칭 0 = `-` (claude 가 아닌 agent 등)
#   정지(stalled) = JSONL_AGE ≥ N분 «이고» PANE 에 스피너 없음 — 이 AND 로만. 한 축으로 판정하지 않는다.
#   seats.json 의 `_replaced_by` 행은 list 에 (replaced) 표시, stalled 에서 제외.
#
# usage: ft-seat-status.sh list [regex] [--json]
#        ft-seat-status.sh stalled [--min N] [regex] [--json]     (기본 20분)
#        ft-seat-status.sh one <seat> [--json]
#        ft-seat-status.sh idle [regex]                            (IDLE 좌석만 — 깨울 대상, pane 층만)
#        ft-seat-status.sh turn <seat> [--json]                    (Seatbelt 1.1 · 턴 경계 판정 — 아래 turn_of_file 주석)
#        ft-seat-status.sh turn --file <jsonl> [--json] [--bytes] [--no-reported]  (픽스처·경로 캐시 · 좌석 해석 생략)
#        ft-seat-status.sh jsonl <seat>                            (좌석 → 최신 jsonl 경로 1줄 · 없으면 rc 1 — ft-tick-line 의 경로 캐시용)
# 출력 4열: 좌석  PANE(BUSY|IDLE|NOSEAT)  JSONL_AGE(초|-)  AGENT   /  turn 은 1줄 5열: STATE TURN_END_ISO DURATION_MS REPORTED SOURCE
#   turn 읽은 바이트(F5): --json 은 read_bytes 키 · 텍스트는 --bytes 일 때만 6열째(기본 5열 — ft-tick.sh `read -r st end dur rep src` 보호)
#   끝 읽기는 64KB 부터 시작해 «턴 끝 레코드 2개»(REPORTED 의 직전 턴 경계)를 찾을 때까지 2배씩(최대 1MB). --no-reported 는 REPORTED 를 건너뛰어(`-`)
#   «1개»만 찾으면 멈춘다 — 긴 턴(수백 KB)이 흔한 실 좌석에서 상태만 필요한 틱이 1MB 를 읽지 않게 한다.
# 스피너 토큰은 버전마다 늘어난다. 목록을 여기 한 곳에서만 고친다.

set -uo pipefail
SPIN='thinking|Sublimating|Cogitat|Gusting|Crunch|Sock-hopping|Brewed|Elucidat|Worked for|Percolat|Simmer|Mulling|Pondering|Noodling|Ruminat|Deliberat|Herding|Puzzl|Wrangl|Baking|Steeping|Whirring|Forging|Honing|Distilling|Musing'

# seats.json — 리포 루트(<git-common-dir 의 부모>)/.fable-team/seats.json. FT_SEATS_JSON 으로 덮어쓴다.
SEATS_JSON="${FT_SEATS_JSON:-}"
if [ -z "$SEATS_JSON" ]; then
  common="$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$common" ] && SEATS_JSON="$(dirname "$common")/.fable-team/seats.json"
fi
# 좌석명\tagent\treplaced(0|1) — 파일이 없으면 빈 표 + stderr 한 줄 (조용히 넘기지 않는다)
SEATS_TSV=""
if [ -f "$SEATS_JSON" ]; then
  SEATS_TSV="$(python3 - "$SEATS_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for k, v in d.items():
    if k.startswith("_") or not isinstance(v, dict):
        continue
    print("%s\t%s\t%d" % (k, v.get("agent") or "-", 1 if v.get("_replaced_by") else 0))
PY
)"
else
  echo "warn: seats.json 없음($SEATS_JSON) — AGENT 열은 '-', (replaced) 판정 없음" >&2
fi

seat_field() {  # $1=seat $2=열번호(2 agent · 3 replaced)
  printf '%s\n' "$SEATS_TSV" | awk -F'\t' -v s="$1" -v c="$2" '$1==s{print $c; exit}'
}

seats() {
  tmux list-sessions -F '#{session_name}' 2>/dev/null \
    | grep -E "${1:-^ft-}" | sort
}

pane_of() {
  tmux list-panes -a -F '#{session_name}|#{pane_id}' 2>/dev/null \
    | awk -F'|' -v s="$1" '$1==s{print $2; exit}'
}

status_of() {
  local p; p="$(pane_of "$1")"
  [ -n "$p" ] || { echo "NOSEAT"; return; }
  local cap; cap="$(tmux capture-pane -p -J -S -12 -t "$p" 2>/dev/null)"
  if echo "$cap" | grep -qE "$SPIN"; then echo "BUSY"; else echo "IDLE"; fi
}

# pane cwd → ~/.claude/projects/<비영숫자 전부 '-'> (ft-reach-check.sh seat_projects_dir 와 같은 규칙)
seat_projects_dir() {
  local cwd enc
  cwd="$(tmux display-message -p -t "$1" '#{pane_current_path}' 2>/dev/null)"
  [ -n "$cwd" ] || return 1
  enc="$(printf '%s' "$cwd" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"
  printf '%s/.claude/projects/%s' "$HOME" "$enc"
}

# 좌석명 매칭 jsonl 중 ★mtime 최신★ 파일의 «경로». 매칭 0 → 빈 출력
# ★전문 grep 금지★ — 한 cwd 의 jsonl 이 392개·2.2GB 라 `grep -l … *.jsonl` 은 좌석당 20초(실측 2026-09-14).
# 좌석명 레코드(agent-name/custom-title)는 파일 «앞»에 쓰인다(339파일 전수: 첫 출현 최대 482KB).
# 그래서 각 파일 앞 FT_SEAT_HEAD_BYTES(기본 1MB)만 읽는다. 그 밖에 있으면 못 보고 빈 값이 된다 — 상한을 늘려라.
newest_jsonl_of() {
  local dir
  dir="$(seat_projects_dir "$1")" || return 0
  SEAT="$1" DIR="$dir" HEAD_BYTES="${FT_SEAT_HEAD_BYTES:-1048576}" python3 -c '
import glob, os
seat = os.environ["SEAT"].encode(); d = os.environ["DIR"]; cap = int(os.environ["HEAD_BYTES"])
needles = (b"\"agentName\":\"" + seat + b"\"", b"\"customTitle\":\"" + seat + b"\"")
newest = (0, "")
for p in glob.glob(os.path.join(d, "*.jsonl")):
    try:
        with open(p, "rb") as fh:
            head = fh.read(cap)
    except OSError:
        continue
    if any(n in head for n in needles):
        m = int(os.stat(p).st_mtime)
        if m > newest[0]: newest = (m, p)
print(newest[1])
'
}

# 그 파일의 age(초). 매칭 0 → '-'
jsonl_age_of() {
  local p; p="$(newest_jsonl_of "$1")"
  [ -n "$p" ] || { echo "-"; return; }
  echo $(( $(date +%s) - $(stat -f %m "$p") ))
}

# ★Seatbelt 1.1 — 턴 경계 판정 (DRAFT-harness-upgrade-v65.md §7-2)★
#   Claude Code jsonl 은 턴이 끝날 때 항상 system/stop_hook_summary → system/turn_duration 을 찍고 다음 턴은 user 로 연다.
#   STATE = 마지막 turn_duration 뒤에 user/assistant 있으면 WORKING · 없으면 IDLE
#           · turn_duration 뒤 queue-operation enqueue 만 있으면(dequeue/remove 로 닫히지 않음) PENDING
#           · tail 창(FT_SEAT_TAIL_BYTES, 기본 1MB)에 turn_duration 이 없으면 UNKNOWN
#   REPORTED = «그 턴»(직전 turn_duration ~ 마지막 turn_duration) 의 assistant tool_use 입력에
#              `mbox.sh send <master>` 문자열 실재(yes/no) — «보고가 옳았다»가 아니라 «문자열이 있다»다. master 미상이면 '-'.
#   mtime·pane 을 쓰지 않는다 — idle 중 away_summary 가 mtime 을 갱신하고 완료요약행이 pane 을 BUSY 로 보이게 한다.
# 출력 1줄: STATE TURN_END_ISO DURATION_MS REPORTED SOURCE   (SOURCE=jsonl · 파일이 없으면 pane 스피너로 `STATE - - - pane`)
master_seat_of_json() {  # seats.json 현역 master 1명 (FT_MASTER_SEAT 로 덮어쓴다 — 픽스처용)
  [ -n "${FT_MASTER_SEAT:-}" ] && { printf '%s' "$FT_MASTER_SEAT"; return; }
  [ -f "$SEATS_JSON" ] || return 0
  python3 - "$SEATS_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for k, v in d.items():
    if k.startswith("_") or not isinstance(v, dict): continue
    if v.get("role") == "master" and not v.get("_replaced_by"):
        print(k); break
PY
}

turn_of_file() {  # $1=jsonl → "STATE\tTURN_END_ISO\tDURATION_MS\tREPORTED\tREAD_BYTES"
  FILE="$1" TAIL_BYTES="${FT_SEAT_TAIL_BYTES:-1048576}" TAIL_START="${FT_SEAT_TAIL_START:-65536}" MASTER="$([ "$NOREP" = 1 ] || master_seat_of_json)" NEED_ENDS="$([ "$NOREP" = 1 ] && echo 1 || echo 2)" python3 - <<'PY'
import json, os
path = os.environ["FILE"]; cap = int(os.environ["TAIL_BYTES"]); master = os.environ.get("MASTER", "")
win, raw, got = min(int(os.environ["TAIL_START"]), cap), b"", 0
size = os.path.getsize(path)
need_ends = int(os.environ["NEED_ENDS"]); status_only = os.environ["NEED_ENDS"] == "1"
while True:  # 끝 64KB 부터 — 턴 끝 레코드 «need_ends»개를 찾을 때까지 앞쪽으로 2배씩(최대 cap). 앞서 읽은 꼬리는 다시 읽지 않는다.
    want = min(win, size)
    with open(path, "rb") as fh:
        fh.seek(size - want); raw = fh.read(want - got) + raw
    got = want
    data = raw.split(b"\n", 1)[1] if size > want and b"\n" in raw else (b"" if size > want else raw)   # 잘린 첫 줄 버림
    recs = []
    for line in data.split(b"\n"):
        if not line.strip(): continue
        try: recs.append(json.loads(line))
        except ValueError: continue                   # 손상 행은 건너뛴다 (마지막 미완 행 포함)
    ends = [i for i, r in enumerate(recs) if r.get("type") == "system" and r.get("subtype") == "turn_duration"]
    if len(ends) >= need_ends or want >= size or want >= cap: break
    # 상태 전용: 끝 레코드가 창 밖이어도 창 안에 user/assistant 가 있으면 «그 끝 뒤» 기록이므로 열린 턴 = WORKING (턴 끝 시각은 불요)
    if status_only and not ends and any(r.get("type") in ("user", "assistant") for r in recs):
        print("WORKING\t-\t-\t-\t%d" % got); raise SystemExit
    win = min(win * 2, cap)
read_total = got
if not ends:
    print("UNKNOWN\t-\t-\t-\t%d" % read_total); raise SystemExit
last = ends[-1]; prev = ends[-2] if len(ends) > 1 else -1
end = recs[last]
state, pending = "IDLE", False
for r in recs[last + 1:]:
    t = r.get("type")
    if t in ("user", "assistant"): state = "WORKING"; break
    if t == "queue-operation":
        pending = r.get("operation") == "enqueue"
if state == "IDLE" and pending: state = "PENDING"
reported = "-"
if master:
    needle = "mbox.sh send " + master
    reported = "no"
    for r in recs[prev + 1:last]:
        if r.get("type") != "assistant": continue
        content = (r.get("message") or {}).get("content")
        if not isinstance(content, list): continue
        for b in content:
            if isinstance(b, dict) and b.get("type") == "tool_use" and needle in json.dumps(b.get("input", {}), ensure_ascii=False):
                reported = "yes"; break
        if reported == "yes": break
print("%s\t%s\t%s\t%s\t%d" % (state, end.get("timestamp", "-"), end.get("durationMs", "-"), reported, read_total))
PY
}

turn_row_of_file() {  # $1=jsonl → "STATE\tTURN_END\tMS\tREPORTED\tjsonl\tREAD_BYTES" (6열 · SOURCE 는 5열째)
  turn_of_file "$1" | awk -F'\t' '{ print $1 "\t" $2 "\t" $3 "\t" $4 "\tjsonl\t" $5 }'
}

turn_of_seat() {  # $1=seat → 6열 탭 행. jsonl 없으면 pane 스피너(BUSY→WORKING · IDLE→IDLE · NOSEAT→UNKNOWN), source=pane
  local f row rc
  if [ -n "$SEATS_JSON" ]; then  # 명부 agent=codex 좌석만 rollout 턴 기록으로(R132a · 8열 · source=codex) — rc 3 = codex 아님 → 아래 기존 경로
    row="$(python3 "$(dirname "$0")/ft_seat_codex.py" --if-codex "$(dirname "$SEATS_JSON")" "$1")"; rc=$?
    [ "$rc" = 0 ] && { printf '%s\n' "$row"; return; }
    [ "$rc" = 3 ] || return "$rc"
  fi
  f="$(newest_jsonl_of "$1")"
  if [ -n "$f" ]; then turn_row_of_file "$f"; return; fi
  case "$(status_of "$1")" in BUSY) printf 'WORKING';; IDLE) printf 'IDLE';; *) printf 'UNKNOWN';; esac
  printf '\t-\t-\t-\tpane\t-\n'
}

emit_turn() {  # stdin = 5열 탭 1행
  if [ "$JSON" = 1 ]; then
    python3 -c '
import json, sys
s, e, d, r, src, b, *codex = sys.stdin.readline().rstrip("\n").split("\t")
row = {"state": s, "turn_end": None if e == "-" else e, "duration_ms": None if d == "-" else int(d),
       "reported": None if r == "-" else r, "source": src, "read_bytes": None if b == "-" else int(b)}
if codex and codex[0] == "aborted": row["aborted"] = True  # codex 행(8열)만 — jsonl·pane 행(6열)은 키가 늘지 않는다
if codex and codex[1] != "-": row["reason"] = codex[1]
print(json.dumps(row, ensure_ascii=False))'
  elif [ "$BYTES" = 1 ]; then
    tr '\t' ' '
  else
    cut -f1-5 | tr '\t' ' '
  fi
}

# 한 좌석의 4열 값 → "seat\tpane\tage\tagent\treplaced"
row_of() {
  local agent rep
  agent="$(seat_field "$1" 2)"; rep="$(seat_field "$1" 3)"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$(status_of "$1")" "$(jsonl_age_of "$1")" "${agent:--}" "${rep:-0}"
}

emit() {  # stdin = row_of 행들 → 텍스트 4열 또는 JSON 배열
  if [ "$JSON" = 1 ]; then
    python3 -c '
import json, sys
rows = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    s, p, a, g, r = line.split("\t")
    rows.append({"seat": s, "pane": p, "jsonl_age": None if a == "-" else int(a),
                 "agent": g, "replaced": r == "1"})
print(json.dumps(rows, ensure_ascii=False))'
  else
    awk -F'\t' '{ printf "%-40s %-7s %-10s %s%s\n", $1, $2, $3, $4, ($5=="1" ? " (replaced)" : "") }'
  fi
}

# ─ 인자 파싱: 서브커맨드 · --json · --min N · 나머지 1개 = regex/seat ─
CMD="${1:-list}"; shift || true
JSON=0; MIN=20; ARG=""; FILE=""; BYTES=0; NOREP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --bytes) BYTES=1 ;;
    --no-reported) NOREP=1 ;;
    --min)  MIN="${2:?--min N}"; shift ;;
    --min=*) MIN="${1#--min=}" ;;
    --file) FILE="${2:?--file <jsonl>}"; shift ;;
    --file=*) FILE="${1#--file=}" ;;
    *) ARG="$1" ;;
  esac
  shift
done

case "$CMD" in
  list)
    for s in $(seats "${ARG:-^ft-}"); do row_of "$s"; done | emit ;;
  stalled)   # 정지 = JSONL_AGE ≥ MIN분 AND pane 스피너 없음. replaced 제외. age 측정 불가는 stderr 로 드러낸다.
    for s in $(seats "${ARG:-^ft-}"); do row_of "$s"; done \
      | awk -F'\t' -v lim=$(( MIN * 60 )) '
          $5=="1" { next }
          $3=="-" { printf "warn: %s JSONL_AGE 측정 불가(agent=%s) — stalled 판정 제외\n", $1, $4 > "/dev/stderr"; next }
          $2!="BUSY" && $3+0 >= lim { print }' \
      | emit ;;
  one)    row_of "${ARG:?seat}" | emit ;;
  idle)   # IDLE 좌석만 — 깨울 대상 (pane 층만 · 정지 판정은 stalled 를 쓴다)
    for s in $(seats "${ARG:-^ft-}"); do [ "$(status_of "$s")" = "IDLE" ] && echo "$s"; done ;;
  turn)   # 턴 경계 판정 — `--file <jsonl>` 이면 좌석 해석 생략(픽스처용)
    if [ -n "$FILE" ]; then
      [ -f "$FILE" ] || { echo "turn: no such file $FILE" >&2; exit 2; }
      turn_row_of_file "$FILE" | emit_turn
    else
      turn_of_seat "${ARG:?seat}" | emit_turn
    fi ;;
  jsonl)  # 좌석 → 최신 jsonl 경로 (경로 캐시용) — 없으면 rc 1
    f="$(newest_jsonl_of "${ARG:?seat}")"; [ -n "$f" ] || exit 1; printf '%s\n' "$f" ;;
  *) echo "usage: $0 {list [regex]|stalled [--min N] [regex]|one <seat>|idle [regex]|turn <seat>|turn --file <jsonl>|jsonl <seat>} [--json] [--bytes]" >&2; exit 2 ;;
esac
