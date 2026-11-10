#!/usr/bin/env bash
# r1282 단계 2 — 판정 불가(기한 D 초과)로 끝난 실행도 «좌석 → jsonl 경로 캐시»(stall-scan.json 의 seats 칸) 만 저장한다.
#   반례·계약 정본: design/harness/indices/진행/r1282-stall-scan-judge-phase-cap-child-group-kill.md 「단계 2」 (S1~S7 · 변이 V1~V5)
#   handled·prev·a_card_nudged·처리(깨우기·쪽지·페널티)는 그대로 0. 시험은 전부 스텁 세계(실 tmux·실 쪽지·실 state 0) · press 0 · 네트워크 0 · 자기 재호출 0.
# 사용: bash test_stall_scan_seats_save_r1282b.sh [s1|s2|s3|mut1|mut2|mut3|stages]   (기본 s1 · 단계마다 70초 안)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
BINDIR="${BINDIR:-$(cd "$HERE/../../kit/fable-team/bin" && pwd)}"
NOW=1800000000
STAGE_FAIL=0
W=""

say() { printf '%s\n' "$*"; }
bad() { printf '  · 실패: %s\n' "$*" >&2; STAGE_FAIL=1; CASE_FAIL=1; }
have() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
now_s() { python3 -c 'import time;print(f"{time.time():.2f}")'; }
el() { python3 -c "print(round($2-$1,2))"; }
iso() { python3 -c "import time;print(time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime($NOW-$1*60)))"; }
iso_local() { python3 -c "import time;print(time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime($NOW-$1*60)))"; }
jf() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print($1)" "$R/.fable-team/state/stall-scan.json"; }   # stall-scan.json 한 값

new_world() {   # 좌석 31(팀장 1 + nano 30) · 모두 방금 일한 IDLE(나이 0.5분 < 문턱 = 후보 0) · seat-status jsonl 호출마다 지연(파일)
  W=$(mktemp -d "${TMPDIR:-/tmp}/r1282b.XXXXXX")
  S="$W/stub"; R="$W/repo"
  mkdir -p "$S/turn" "$S/jsonl" "$R/.fable-team/state" "$R/.fable-team/comm" "$R/design" \
    "$R/.worktrees/wt-t1/design/t1/indices/대기" "$R/.worktrees/wt-t1/design/t1/indices/진행"
  printf '# 팀 명단(시험)\n\n| 팀 | 폴더 | 상태 |\n|---|---|---|\n| t1 | `design/t1/` | 현역 |\n' > "$R/design/TEAMS.md"
  cat > "$S/seat-status.sh" <<'STUB'
#!/bin/sh
case "$1" in
  turn)
    s="$2"
    [ "$2" = --file ] && s=$(basename "$3" .jsonl)
    cat "$FT_STUB/turn/$s" 2>/dev/null || echo "UNKNOWN - - - pane"
    ;;
  jsonl)
    [ -f "$FT_STUB/jsonl/$2.jsonl" ] || exit 1
    d=$(cat "$FT_STUB/jsondelay" 2>/dev/null || echo 0)
    [ "$d" = 0 ] || sleep "$d"
    echo "$FT_STUB/jsonl/$2.jsonl"
    ;;
esac
STUB
  printf '#!/bin/sh\ncase "$1" in\n  list-sessions) cat "$FT_STUB/tmux" 2>/dev/null ;;\n  list-panes) awk %s "$FT_STUB/tmux" 2>/dev/null ;;\nesac\n' "'{print \$1\"|%\"NR}'" > "$S/tmux.sh"
  printf '#!/bin/sh\ncase "$1" in\n  send) echo "send|$2|$3" >> "$FT_STUB/mbox.log" ;;\n  ring) echo "ring|$2|" >> "$FT_STUB/mbox.log" ;;\nesac\n' > "$S/mbox.sh"
  printf '#!/bin/sh\nexit 0\n' > "$S/lint.sh"
  printf '#!/bin/sh\ncat "$FT_STUB/ps" 2>/dev/null\n' > "$S/ps.sh"
  printf '#!/bin/sh\nexit 1\n' > "$S/bad.sh"
  printf '#!/bin/sh\necho 50\n' > "$S/ctx.sh"
  : > "$S/ps"; : > "$S/tmux"
  local rows='{"_master":"t1-master#1","_label":"t1","_cards":"design/t1/indices","_cards_wt":"wt-t1","t1-master#1":{"role":"master"}' i s
  printf 'IDLE %s 1000 no jsonl\n' "$(iso 0.5)" > "$S/turn/t1-master#1"
  printf 't1-master#1 0\n' >> "$S/tmux"
  printf '{"type":"system","subtype":"turn_duration"}\n' > "$S/jsonl/t1-master#1.jsonl"
  for i in $(seq -w 1 30); do
    s="t1-n$i#0"
    rows="$rows,\"$s\":{\"role\":\"nano\"}"
    printf 'IDLE %s 1000 no jsonl\n' "$(iso 0.5)" > "$S/turn/$s"
    printf '%s 0\n' "$s" >> "$S/tmux"
    printf '{"type":"system","subtype":"turn_duration"}\n' > "$S/jsonl/$s.jsonl"
  done
  printf '%s}' "$rows" > "$R/.fable-team/seats-t1.json"
  printf '{"seq":1,"ts":"%s","to":"t1-master#1","from":"t1-master#1","body":"[정리] 한 일 3줄"}\n' "$(iso_local 2)" > "$R/.fable-team/comm/mailbox.jsonl"
  export FT_ROOT="$R" FT_STUB="$S" FT_NOW="$NOW"
  export FT_SEAT_STATUS="$S/seat-status.sh" FT_TMUX="$S/tmux.sh" FT_MBOX_SH="$S/mbox.sh"
  export FT_INDEX_LINT="$S/lint.sh" FT_MBOX_DIR="$R/.fable-team/comm"
  export FT_STALL_STATE_DIR="$R/.fable-team/state" FT_PS="$S/ps.sh" FT_CTX_CMD="$S/ctx.sh"
  export FT_SEAT_QUIESCE_BIN="$S/bad.sh" FT_ROOTS_TSV="$S/no-roots.tsv"
  unset FT_STALL_SCAN_TOTAL_S FT_STALL_PENALTY_TIMEOUT
}
rm_world() { [ -n "${W:-}" ] && rm -rf "$W"; W=""; }
run_scan() { timeout 70 bash "$BINDIR/ft-stall-scan.sh" "$@"; }
slow_jsonl() { printf '%s\n' "$1" > "$S/jsondelay"; export FT_STALL_SCAN_TOTAL_S=10; }   # jsonl 풀기 호출마다 지연 · D=10
seed_state() {   # 기존 stall-scan.json — 처리 기록 3칸(+ 좌석 캐시 1행)
  printf '%s' '{"handled": {"t1-n01#0": 1799999000.0, "t1-n02#0": 1799999100.5}, "prev": ["d:t1-n03#0"], "seats": {"t1-n09#0": {"path": "/x", "mtime": 1.0, "resolved": 1799990000.0, "state": "IDLE", "end": 1.0, "rest": false, "future": false, "err": null}}, "a_card_nudged": {"card-1": 1799999500.0}}' > "$R/.fable-team/state/stall-scan.json"
}
others() { jf '[d.get("handled"), d.get("prev"), d.get("a_card_nudged")]'; }
inproc() {   # inproc <S4|S7> — main() 을 같은 프로세스에서 부르되 저장 갈래만 고장낸다(rc·출력 → stdout)
  python3 -I - "$BINDIR" "$1" <<'PY'
import contextlib, io, os, sys
sys.path.insert(0, sys.argv[1])
import ft_stall_scan as sc
def boom(*_a, **_k):
    raise OSError("주입")
if sys.argv[2] == "S4":
    sc.stm.save_seats = boom
else:
    os.replace = boom
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = sc.main([])
print(f"rc={rc}")
print(buf.getvalue())
PY
}

c_S1() {   # 캐시 0 · 지연 0.5초 · D=10 → 1회차 판정 불가 + seats ≥1 저장 → N(≤4)회차 안에 요약 줄
  new_world; slow_jsonl 0.5; CASE_FAIL=0
  local out rc n i got=0
  out=$(run_scan); rc=$?
  have "$out" '판정 불가' && [ "$rc" = 3 ] || bad "S1 1회차 판정 불가·rc3 아님 rc=$rc"
  n=$(jf 'len(d.get("seats", {}))' 2>/dev/null || echo 0)
  [ "$n" -ge 1 ] 2>/dev/null || { bad "S1 1회차 seats 저장 0 (n=$n)"; rm_world; return "$CASE_FAIL"; }
  for i in 2 3 4; do
    out=$(run_scan); rc=$?
    if have "$out" 'stall=' && [ "$rc" = 0 ]; then got=$i; break; fi
  done
  [ "$got" != 0 ] || bad "S1 4회차 안에 요약 줄 없음"
  say "  S1 1회차 저장 ${n}석 · 요약 줄 ${got}회차"
  rm_world; return "$CASE_FAIL"
}
c_S2() {   # 기존 처리 기록 + 판정 불가 → handled·prev·a_card_nudged 같음 · seats 늘어남
  new_world; slow_jsonl 0.5; CASE_FAIL=0; seed_state
  local before after out rc n
  before=$(others)
  out=$(run_scan); rc=$?
  have "$out" '판정 불가' && [ "$rc" = 3 ] || bad "S2 판정 불가 아님 rc=$rc"
  after=$(others); n=$(jf 'len(d["seats"])')
  [ "$before" = "$after" ] || bad "S2 다른 칸이 바뀜: $before → $after"
  [ "$n" -gt 1 ] || bad "S2 seats 안 늘어남 (n=$n)"
  [ ! -s "$S/mbox.log" ] || bad "S2 처리 쪽지가 나감"
  rm_world; return "$CASE_FAIL"
}
c_S3() {   # 기한 안 정상 실행 → 정상 저장 경로(칸 4개 · 판정 불가 줄 0 · tmp 잔재 0)
  new_world; CASE_FAIL=0; seed_state
  local out rc keys
  out=$(run_scan); rc=$?
  [ "$rc" = 0 ] && have "$out" 'stall=' && ! have "$out" '판정 기한' || bad "S3 정상 실행 아님 rc=$rc"
  keys=$(jf 'sorted(d)')
  [ "$keys" = "['a_card_nudged', 'handled', 'prev', 'seats']" ] || bad "S3 칸이 기준판과 다름: $keys"
  [ -z "$(ls "$R/.fable-team/state" | grep 'stall-scan.json.tmp')" ] || bad "S3 tmp 잔재"
  rm_world; return "$CASE_FAIL"
}
c_S4() {   # 저장 함수 raise OSError → 출력 줄에 «좌석 캐시 저장 실패(OSError)» · rc 3
  new_world; slow_jsonl 0.5; CASE_FAIL=0
  local out
  out=$(inproc S4)
  have "$out" 'rc=3' && have "$out" '좌석 캐시 저장 실패(OSError)' || bad "S4 실패 꼬리 없음: $out"
  rm_world; return "$CASE_FAIL"
}
c_S5() {   # stall-scan.json 깨짐 + 판정 불가 → {"seats": …} 만 · 예외 0
  new_world; slow_jsonl 0.5; CASE_FAIL=0
  printf '{깨진 파일' > "$R/.fable-team/state/stall-scan.json"
  local out rc keys
  out=$(run_scan 2>&1); rc=$?
  [ "$rc" = 3 ] && have "$out" '판정 불가' && ! have "$out" 'Traceback' || bad "S5 rc=$rc 또는 예외: $out"
  keys=$(jf 'sorted(d)' 2>/dev/null || echo 깨짐)
  [ "$keys" = "['seats']" ] || bad "S5 seats 만이 아님: $keys"
  rm_world; return "$CASE_FAIL"
}
c_S6() {   # --dry-run + 판정 불가 → stall-scan.json 바이트 같음
  new_world; slow_jsonl 0.5; CASE_FAIL=0; seed_state
  local a b out rc
  a=$(shasum "$R/.fable-team/state/stall-scan.json")
  out=$(run_scan --dry-run); rc=$?
  b=$(shasum "$R/.fable-team/state/stall-scan.json")
  [ "$rc" = 3 ] && have "$out" '판정 불가' || bad "S6 판정 불가 rc3 아님 rc=$rc"
  [ "$a" = "$b" ] || bad "S6 dry-run 이 파일을 바꿈"
  rm_world; return "$CASE_FAIL"
}
c_S7() {   # os.replace 전 실패 → 옛 파일 바이트 같음 · tmp 잔재 0
  new_world; slow_jsonl 0.5; CASE_FAIL=0; seed_state
  local a b out
  a=$(shasum "$R/.fable-team/state/stall-scan.json")
  out=$(inproc S7)
  b=$(shasum "$R/.fable-team/state/stall-scan.json")
  have "$out" 'rc=3' && have "$out" '좌석 캐시 저장 실패(OSError)' || bad "S7 실패 꼬리 없음: $out"
  [ "$a" = "$b" ] || bad "S7 옛 파일이 바뀜"
  [ -z "$(ls "$R/.fable-team/state" | grep 'stall-scan.json.tmp')" ] || bad "S7 tmp 잔재"
  rm_world; return "$CASE_FAIL"
}

run_case() { local t0 rc; t0=$(now_s); "$1"; rc=$?; say "  ─ $1 rc=$rc ($(el "$t0" "$(now_s)")초)"; [ "$rc" = 0 ] || STAGE_FAIL=1; }

mutant() {   # mutant <이름> <케이스> <파일> <옛 글자> <새 글자> — 변이 적용 실패·생존은 단계 rc 1
  local name=$1 case=$2 file=$3 old=$4 new=$5 base=$BINDIR rc t0
  t0=$(now_s)
  local M; M=$(mktemp -d "${TMPDIR:-/tmp}/r1282bm.XXXXXX")
  cp -R "$base" "$M/bin"
  if ! python3 -I - "$M/bin/$file" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if old not in s:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  then say "  ✗ 변이 $name 적용 실패($file)"; STAGE_FAIL=1; rm -rf "$M"; return 0; fi
  local saved=$STAGE_FAIL
  BINDIR="$M/bin"; STAGE_FAIL=0
  "$case" >/dev/null 2>&1; rc=$?
  BINDIR="$base"; STAGE_FAIL=$saved
  rm -rf "$M"
  if [ "$rc" = 0 ]; then say "  ✗ 변이 $name 살아남음($case 통과)"; STAGE_FAIL=1
  else say "  ✓ 변이 $name → $case FAIL(죽음) ($(el "$t0" "$(now_s)")초)"; fi
}

stage_s1() { run_case c_S1; }
stage_s2() { run_case c_S2; run_case c_S3; run_case c_S5; }
stage_s3() { run_case c_S4; run_case c_S6; run_case c_S7; }
stage_mut1() { mutant 'V1_on_timeout저장삭제' c_S1 ft_stall_state.py $'                on_timeout()\n' $'                pass\n'; }
stage_mut2() {
  mutant 'V2_문서전체새로씀' c_S2 ft_stall_state.py 'doc = dict(doc) if isinstance(doc, dict) else {}' 'doc = {}'
  mutant 'V3_dry에서도저장' c_S6 ft_stall_scan.py 'keep = None if dry else (' 'keep = ('
}
stage_mut3() {
  mutant 'V4_저장실패삼킴' c_S4 ft_stall_state.py 'extra += f" · 좌석 캐시 저장 실패({e.__class__.__name__})"' 'pass'
  mutant 'V5_tmp없이직접씀' c_S7 ft_stall_state.py '_ = tmp.write_text(json.dumps(doc), encoding="utf-8")' '_ = path.write_text(json.dumps(doc), encoding="utf-8")'
}

main() {
  local stage=${1:-s1} one t0
  say "r1282 단계 2 시험 — bin=$BINDIR stage=$stage"
  case "$stage" in
  s1) stage_s1 ;; s2) stage_s2 ;; s3) stage_s3 ;;
  mut1) stage_mut1 ;; mut2) stage_mut2 ;; mut3) stage_mut3 ;;
  stages) for one in s1 s2 s3 mut1 mut2 mut3; do t0=$(now_s); "stage_$one"; say "  ─ 단계 $one $(el "$t0" "$(now_s)")초"; done ;;
  *) say "usage: bash $(basename "$0") [s1|s2|s3|mut1|mut2|mut3|stages]"; return 2 ;;
  esac
  if [ "$STAGE_FAIL" = 0 ]; then say "OK (rc 0)"; else say "FAIL (rc 1)"; fi
  return "$STAGE_FAIL"
}

trap 'rm_world >/dev/null 2>&1' EXIT
main "$@"
