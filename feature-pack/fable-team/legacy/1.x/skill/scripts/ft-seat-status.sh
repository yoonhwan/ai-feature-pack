#!/bin/bash
# ★런타임 사본은 git 추적 밖이다 — 실전은 <워크트리>/.fable-team/bin/ 의 사본으로 돌린다. 이 파일이 팩 SSOT(Seatbelt 1.0.0).★
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
# 출력 4열: 좌석  PANE(BUSY|IDLE|NOSEAT)  JSONL_AGE(초|-)  AGENT
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

# 좌석명 매칭 jsonl 중 ★mtime 최신★ 파일의 age(초). 매칭 0 → '-'
# ★전문 grep 금지★ — 한 cwd 의 jsonl 이 392개·2.2GB 라 `grep -l … *.jsonl` 은 좌석당 20초(실측 2026-09-14).
# 좌석명 레코드(agent-name/custom-title)는 파일 «앞»에 쓰인다(339파일 전수: 첫 출현 최대 482KB).
# 그래서 각 파일 앞 FT_SEAT_HEAD_BYTES(기본 1MB)만 읽는다. 그 밖에 있으면 못 보고 '-' 가 된다 — 상한을 늘려라.
jsonl_age_of() {
  local dir
  dir="$(seat_projects_dir "$1")" || { echo "-"; return; }
  SEAT="$1" DIR="$dir" HEAD_BYTES="${FT_SEAT_HEAD_BYTES:-1048576}" python3 -c '
import glob, os, time
seat = os.environ["SEAT"].encode(); d = os.environ["DIR"]; cap = int(os.environ["HEAD_BYTES"])
needles = (b"\"agentName\":\"" + seat + b"\"", b"\"customTitle\":\"" + seat + b"\"")
newest = 0
for p in glob.glob(os.path.join(d, "*.jsonl")):
    try:
        with open(p, "rb") as fh:
            head = fh.read(cap)
    except OSError:
        continue
    if any(n in head for n in needles):
        newest = max(newest, int(os.stat(p).st_mtime))
print("-" if newest == 0 else int(time.time()) - newest)
'
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
JSON=0; MIN=20; ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --min)  MIN="${2:?--min N}"; shift ;;
    --min=*) MIN="${1#--min=}" ;;
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
  *) echo "usage: $0 {list [regex]|stalled [--min N] [regex]|one <seat>|idle [regex]} [--json]" >&2; exit 2 ;;
esac
