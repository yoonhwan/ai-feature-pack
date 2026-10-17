#!/usr/bin/env bash
# ft-spawn-hold.sh set|clear|status — 새 좌석 spawn «정지» 는 기한과 해제 조건이 있는 파일 하나로만 건다 (R320 · 판정 2166 계기).
#   set --verdict <판정 번호> --until <ISO8601 · 지금+4시간 이하> --release "<조건>" --reason "<10자 이상>"
#        조건 문법 = `swap<N` · `memfree>=N` · `agents<N` · `level<=N` (swap|memfree|agents|level × < <= > >=)을 `&` 로 잇기만 — 그 밖 글자 REJECT.
#        한 번에 1개 — 파일이 이미 있으면 REJECT(status 로 정리하거나 clear).
#   clear   정지 파일 삭제.
#   status  판정기. 정지 없음 `hold=none` rc0 · 기한 지남 → 파일 삭제 + planner 쪽지 «정지 기한 만료» `EXPIRED …` rc0 · 해제 조건 참 → 파일 삭제 + 쪽지 «정지 자동 해제» `RELEASED …` rc0
#           · 기한 안 & 해제 조건 거짓 `REJECT hold <판정> until=… release=…` rc3 · 파일 손상·문지기 측정 실패 `ERROR hold …` rc4(정지 유지 — 통과시키지 않는다).
#   status --check <판정 번호>  같은 판정기를 «부작용 0»(삭제·쪽지 0)으로 돌려, 그 번호의 정지가 지금 유효할 때만 rc0 `OK hold=<번호> …` · 아니면 rc3 + 사유 (쪽지 가드가 쓴다).
#   파일 = <리포 루트>/.fable-team/state/SPAWN_HOLD (json 1개) · 리포 루트 = git common-dir 역산(ft-resource-gate.sh 와 같은 방식 — 워크트리 어디서 불러도 같은 파일).
#   값 출처 = `ft-resource-gate.sh status` 칸 이름 그대로. 외부 호출 0(로컬 파일·sysctl·mbox).
#   env(시험): FT_RES_ROOT FT_HOLD_GATE FT_HOLD_NOW FT_HOLD_PLANNER_SEATS FT_MBOX_SH
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_RES_ROOT:-$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"
[ -n "$ROOT" ] || ROOT="$(cd -- "$HERE/../.." && pwd)"
FILE="$ROOT/.fable-team/state/SPAWN_HOLD"
GATE="${FT_HOLD_GATE:-$HERE/ft-resource-gate.sh}"
MBOX="${FT_MBOX_SH:-$HERE/../comm/mbox.sh}"
PSEATS="${FT_HOLD_PLANNER_SEATS:-$ROOT/.fable-team/seats-planner.json}"
NOW="${FT_HOLD_NOW:-$(date +%s)}"
GRAMMAR='^(swap|memfree|agents|level)(<=|>=|<|>)[0-9]+(&(swap|memfree|agents|level)(<=|>=|<|>)[0-9]+)*$'
usage() { echo "usage: $0 set --verdict <N> --until <ISO8601> --release \"<조건>\" --reason \"<10자+>\" | clear | status [--check <판정 번호>]" >&2; exit 2; }
jget() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$FILE" "$1" 2>/dev/null; }

# 해제 조건 평가 — rc0 참 · 1 거짓 · 2 측정 실패
release_true() {
  local st; st="$(bash "$GATE" status 2>&1)" || return 2
  python3 - "$1" "$st" <<'PY'
import re, sys
vals = dict(re.findall(r'(\w+)=(-?\d+)', sys.argv[2]))
ops = {'<': lambda a, b: a < b, '<=': lambda a, b: a <= b, '>': lambda a, b: a > b, '>=': lambda a, b: a >= b}
for term in sys.argv[1].split('&'):
    m = re.fullmatch(r'(swap|memfree|agents|level)(<=|>=|<|>)(\d+)', term)
    if not m or m.group(1) not in vals: sys.exit(2)
    if not ops[m.group(2)](int(vals[m.group(1)]), int(m.group(3))): sys.exit(1)
PY
}

note() {   # $1=머리 $2=본문 → planner(_hil_route). 실패는 stderr WARN(정지 판정은 이미 끝난 뒤)
  local to; to="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("_hil_route",""))' "$PSEATS" 2>/dev/null)"
  [ -n "$to" ] || { echo "WARN hold 쪽지 수신자 없음($PSEATS _hil_route)" >&2; return 0; }
  bash "$MBOX" send "$to" ft-spawn-hold "$1 $2" >/dev/null 2>&1 || echo "WARN hold 쪽지 발신 실패 to=$to" >&2
}

# 판정기 — 출력·rc 는 status 설명 그대로. $1=1 이면 부작용 0(--check)
evaluate() {
  local dry="${1:-0}" v until_ep until_iso rel rc
  [ -f "$FILE" ] || { echo "hold=none"; return 0; }
  v="$(jget verdict)"; until_ep="$(jget until_epoch)"; until_iso="$(jget until)"; rel="$(jget release)"
  case "$v:$until_ep" in *[!0-9:]*|:*|*:) echo "ERROR hold 파일 손상 — $FILE (verdict/until_epoch 읽기 실패) · 정지 유지"; return 4;; esac
  if [ "$NOW" -ge "$until_ep" ]; then
    [ "$dry" = 1 ] && { echo "REJECT hold $v 기한 지남(until=$until_iso) — status 가 정리한다"; return 3; }
    rm -f "$FILE"; note "[정지 기한 만료]" "판정 $v · until=$until_iso — SPAWN_HOLD 삭제"; echo "EXPIRED hold=$v until=$until_iso"; return 0
  fi
  release_true "$rel"; rc=$?
  case "$rc" in
    0) [ "$dry" = 1 ] && { echo "REJECT hold $v 해제 조건 참(release=$rel) — status 가 정리한다"; return 3; }
       rm -f "$FILE"; note "[정지 자동 해제]" "판정 $v · 조건 참 release=$rel — SPAWN_HOLD 삭제"; echo "RELEASED hold=$v release=$rel"; return 0;;
    1) echo "REJECT hold $v until=$until_iso release=$rel"; return 3;;
    *) echo "ERROR hold 해제 조건 측정 실패($GATE status) · 정지 유지 — release=$rel"; return 4;;
  esac
}

CMD="${1:-}"; shift || usage
case "$CMD" in
  status)
    if [ "${1:-}" = --check ]; then
      N="${2:-}"; case "$N" in ''|*[!0-9]*) usage;; esac
      out="$(evaluate 1)"; rc=$?
      if [ "$rc" = 3 ] && [ "$(jget verdict)" = "$N" ] && ! printf '%s' "$out" | grep -Eq '기한 지남|해제 조건 참'; then
        echo "OK hold=$N until=$(jget until) release=$(jget release)"; exit 0
      fi
      echo "REJECT hold 번호 $N 의 유효한 정지 없음 — ${out}"; exit 3
    fi
    [ $# -eq 0 ] || usage; evaluate 0; exit $?;;
  clear) [ $# -eq 0 ] || usage; if [ -f "$FILE" ]; then rm -f "$FILE" && echo "CLEARED"; else echo "hold=none"; fi; exit 0;;
  set)
    V=""; U=""; R=""; W=""
    while [ $# -gt 0 ]; do case "$1" in
      --verdict) V="${2:-}"; shift 2 2>/dev/null || shift;; --until) U="${2:-}"; shift 2 2>/dev/null || shift;;
      --release) R="${2:-}"; shift 2 2>/dev/null || shift;; --reason) W="${2:-}"; shift 2 2>/dev/null || shift;; *) usage;; esac; done
    rej() { echo "REJECT hold set — $1"; exit 1; }
    case "$V" in ''|*[!0-9]*) rej "--verdict 는 판정 번호(숫자)";; esac
    printf '%s' "$R" | grep -Eq "$GRAMMAR" || rej "--release 문법 위반(허용: swap|memfree|agents|level × < <= > >= 숫자, & 로 연결) — «${R}»"
    [ "$(python3 -c 'import sys;print(len(sys.argv[1].strip()))' "$W")" -ge 10 ] || rej "--reason 은 10자 이상"
    [ ! -f "$FILE" ] || rej "정지 파일이 이미 있다(판정 $(jget verdict)) — status 로 정리하거나 clear 먼저(한 번에 1개)"
    UE="$(python3 - "$U" <<'PY'
import sys, datetime
try:
    d = datetime.datetime.fromisoformat(sys.argv[1].replace('Z', '+00:00'))
    if d.tzinfo is None: d = d.astimezone()
    print(int(d.timestamp()))
except ValueError:
    print('')
PY
)"
    [ -n "$UE" ] || rej "--until 은 ISO8601 (예: 2026-10-17T18:00:00+09:00)"
    [ "$UE" -gt "$NOW" ] || rej "--until 이 이미 지났다"
    [ "$UE" -le $((NOW + 14400)) ] || rej "--until 은 지금+4시간 이하(기한 없는 정지 금지)"
    mkdir -p "$(dirname "$FILE")" || rej "상태 폴더 생성 실패"
    python3 - "$FILE" "$V" "$U" "$UE" "$R" "$W" "$NOW" <<'PY' || rej "파일 쓰기 실패"
import json, os, sys
f, v, u, ue, r, w, now = sys.argv[1:8]
tmp = f + '.tmp.%d' % os.getpid()
json.dump({'verdict': int(v), 'until': u, 'until_epoch': int(ue), 'release': r, 'reason': w, 'set_at': int(now)}, open(tmp, 'w'), ensure_ascii=False)
os.replace(tmp, f)
PY
    echo "SET hold=$V until=$U release=$R"; exit 0;;
  *) usage;;
esac
