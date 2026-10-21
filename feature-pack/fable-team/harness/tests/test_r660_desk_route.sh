#!/usr/bin/env bash
# test_r660_desk_route.sh — desk 창구 고정(r660 · 판정 1125 · DA⑥ r1 고침 반영): 쪽지 «모든 길»이 «판정기 하나»로 같은 표를 낸다.
#   길 3 = 키트 ft-mbox.sh(→ft-mbox.py send) · 우편함 comm/mbox.sh(→mbox_ops.send) · python 직접(comm/mbox.py send) · relay 두 길.
#   ⓐ 판정 전 FAIL 표 ⓑ desk → planner 만 통과 ⓒ 팀 → desk 거절 ⓓ 예외는 «방향 한정»(팀→desk [HIL]·h결과 1줄) ⓔ 판정 불변(planner↔팀·팀끼리·도구·slack·desk 계보)
#   ⓕ 명부 없음·깨짐·_desk 칸 없음 = 판정 0(WARN — 조용히 막기 0) ⓖ 세 길 결과 표 동일 ⓗ 판정기 고장 = 세 길 다 REJECT(fail-closed)
#   ⓘ DA⑥ r1 구멍 재현: desk→팀 [HIL] REJECT · planner 비-_master 발신 h 지정 REJECT · h7abc 경계 REJECT · `.2` 회전 로그 통과 · 여러 줄 전문 relay REJECT · 옛 desk 다른 베이스 인식
# 임시 루트에 우편함 코드 사본 + 명부 + 가짜 tmux 만 둔다 — 실 큐·실 좌석·실 tmux·홈·리포 상태 쓰기 0.
# base 판 대조(카드 ⓐ) = FT_R660_COMM·FT_R660_KIT 로 «고치기 전» 폴더를 가리켜 같은 표를 돌린다(제품 우회 플래그 0 · 시험 입력 주입점).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
COMM="${FT_R660_COMM:-$REPO/harness/comm}"; KIT="${FT_R660_KIT:-$REPO/harness/kit/fable-team/bin}"
GATE="$KIT/ft_desk_route_gate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"

# ── 격리 루트: 우편함 코드 사본(<루트>/.fable-team/comm) + 판정기 사본(<루트>/.fable-team/bin = LIVE_BIN 폴백 자리) + 명부 3팀
new_root() {
  R="$T/root.$1"; rm -rf "$R"; mkdir -p "$R/.fable-team/comm" "$R/.fable-team/bin" "$R/.fable-team/state"
  cp "$COMM"/mbox*.sh "$COMM"/mbox*.py "$R/.fable-team/comm/" 2>/dev/null
  [ -f "$COMM/queues.conf" ] && cp "$COMM/queues.conf" "$R/.fable-team/comm/"
  [ -f "$COMM/bang_command_check.py" ] && cp "$COMM/bang_command_check.py" "$R/.fable-team/comm/"
  [ -f "$GATE" ] && cp "$GATE" "$R/.fable-team/bin/"
  python3 - "$R" <<'PY'
import json, sys, time
r = sys.argv[1]; today = time.strftime("%Y-%m-%dT%H:%M:%S")
p = {"_master": "byz-planner-master-claude#94", "_desk": "byz-planner-desk-claude#38"}
p.update({k: {"role": "master"} for k in ("byz-planner-master-claude#94", "byz-planner-desk-claude#38", "byz-planner-desk-claude#37")})
json.dump(p, open(r + "/.fable-team/seats-planner.json", "w"))
h = {"_master": "byz-harness-master-claude#92"}
h.update({k: {"role": "master"} for k in ("byz-harness-master-claude#92", "byz-harness-nano-x#0")})
json.dump(h, open(r + "/.fable-team/seats-harness.json", "w"))
json.dump({"_master": "byz-other-master-claude#1", "byz-other-master-claude#1": {"role": "master"}},
          open(r + "/.fable-team/seats-other.json", "w"))
# 보낸 로그: _master 계보 → 하네스 팀에 h7 지정(오늘) · 옛 .2 회전본에 h9 지정 · planner arch 가 보낸 h5(계보 아님 = 무효)
rows = [
    ("mailbox.log.jsonl", "h7", "byz-planner-master-claude#94", "byz-harness-master-claude#92"),
    ("mailbox.log.jsonl.2", "h9", "byz-planner-master-claude#94", "byz-harness-master-claude#92"),
    ("mailbox.log.jsonl", "h5", "byz-planner-arch-claude#1", "byz-harness-master-claude#92"),
    ("mailbox.log.jsonl", "h7abc", "byz-planner-master-claude#94", "byz-harness-master-claude#92"),
]
with open(r + "/.fable-team/comm/mailbox.log.jsonl", "w") as f:
    for i, (_, h, frm, to) in enumerate(rows):
        if _ == "mailbox.log.jsonl":
            f.write(json.dumps({"seq": i + 1, "ts": today, "from": frm, "to": to, "body": "%s 실행해라" % h}, ensure_ascii=False) + "\n")
with open(r + "/.fable-team/comm/mailbox.log.jsonl.2", "w") as f:
    for i, (name, h, frm, to) in enumerate(rows):
        if name.endswith(".2"):
            f.write(json.dumps({"seq": 100 + i, "ts": today, "from": frm, "to": to, "body": "%s 실행해라" % h}, ensure_ascii=False) + "\n")
PY
  git -C "$R" init -q
  touch "$R/.fable-team/state/planner-watch-missing.byz-planner-master-claude#94"
}
_env() { env -u FT_PLANNER_HEAD_MODE -u FT_DESK_GATE PATH="$T/stub:$PATH" FT_SEATS_JSON="$R/.fable-team/seats-planner.json" FT_MBOX_DIR="$R/.fable-team/comm" \
             FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_MBOX_RESEND_COOLDOWN=0 "$@"; }
send_kit()  { OUT="$(_env bash "$KIT/ft-mbox.sh" send "$1" "$2" "$3" 2>&1)"; RC=$?; }
send_comm() { OUT="$(_env bash "$R/.fable-team/comm/mbox.sh" send "$1" "$2" "$3" 2>&1)"; RC=$?; }
send_py()   { OUT="$(_env python3 "$R/.fable-team/comm/mbox.py" send "$1" "$2" "$3" 2>&1)"; RC=$?; }
qrows() { python3 - "$R/.fable-team/comm/mailbox.jsonl" "$1" <<'PY'
import json, sys
n = 0
try:
    fh = open(sys.argv[1], encoding="utf-8")
except OSError:
    sys.exit(0)
with fh:
    for line in fh:
        if line.strip():
            try:
                r = json.loads(line)
            except Exception:
                continue
            n += r.get("to") == sys.argv[2]
print(n)
PY
}

D='byz-planner-desk-claude#38'; PM='byz-planner-master-claude#94'; HM='byz-harness-master-claude#92'
HN='byz-harness-nano-x#0'; OM='byz-other-master-claude#1'; DCODEX='byz-planner-desk-codex#3'
# 표 = <이름>|<to>|<from>|<본문(\n = 개행)>|<기대 pass|reject>|<REJECT 사유 조각>
TABLE=(
 "desk→팀장 보통|$HM|$D|[진행] r660 표 1 — 보고|reject|desk 는 planner 에게만 보내요"
 "desk→팀장 [HIL]|$HM|$D|[HIL] r660 표 2 — desk 사람 판정 요청\n①막힌 명령: x\n④선택지: a·b|reject|desk 는 planner 에게만 보내요"
 "desk→팀장 [긴급]|$HM|$D|[긴급] r660 표 3 — 급함|reject|desk 는 planner 에게만 보내요"
 "desk→팀 좌석|$HN|$D|[진행] r660 표 4 — 보고|reject|desk 는 planner 에게만 보내요"
 "옛 desk 다른 베이스→팀장|$HM|$DCODEX|[진행] r660 표 5 — codex desk|reject|desk 는 planner 에게만 보내요"
 "desk→planner master|$PM|$D|[진행] r660 표 6 — 보고|pass|"
 "desk→planner master [HIL]|$PM|$D|[HIL] r660 표 7 — desk 사람 판정 요청\n①막힌 명령: x\n④선택지: a·b|pass|"
 "팀장→desk 보통|$D|$HM|[진행] r660 표 8 — 보고|reject|desk 에는 planner 가 보내요"
 "팀장→desk [긴급]|$D|$HM|[긴급] r660 표 9 — 급함|reject|desk 에는 planner 가 보내요"
 "팀장→desk [HIL]|$D|$HM|[HIL] r660 표 10 — 오빠 판정 필요\n①막힌 명령: x\n④선택지: a·b|pass|"
 "팀장→desk [h7 결과] 지정 있음|$D|$HM|[h7 결과] r660 표 11 — 끝|pass|"
 "팀장→desk [h9 결과] .2 회전본 지정|$D|$HM|[h9 결과] r660 표 12 — 끝|pass|"
 "팀장→desk [h5 결과] planner arch 발신 = 지정 아님|$D|$HM|[h5 결과] r660 표 13 — 끝|reject|desk 에는 planner 가 보내요"
 "팀장→desk [h8 결과] 지정 없음|$D|$HM|[h8 결과] r660 표 14 — 끝|reject|desk 에는 planner 가 보내요"
 "팀장→desk [h7abc 결과] 경계|$D|$HM|[h7abc 결과] r660 표 15 — 끝|reject|desk 에는 planner 가 보내요"
 "팀장→desk [h7 결과] 2줄|$D|$HM|[h7 결과] r660 표 16 — 끝\n둘째 줄|reject|desk 에는 planner 가 보내요"
 "desk 계보 인계|$D|byz-planner-desk-claude#37|[진행] r660 표 18 — 인계|pass|"
 "planner→desk|$D|$PM|[진행] r660 표 19 — planner 답|pass|"
 "도구 발신→desk|$D|ft-tick|[진행] r660 표 20 — 틱|pass|"
 "slack→desk|$D|slack-oppa|r660 표 21 — 오빠 슬랙 글|pass|"
 "planner→팀|$HM|$PM|[발주] r660 표 22 — 발주|pass|"
 "팀끼리|$OM|$HM|[진행] r660 표 23 — 팀끼리|pass|"
)

tab=(); n=0
for row in "${TABLE[@]}"; do
  IFS='|' read -r name to from body want frag <<< "$row"
  body="$(printf '%b' "$body")"
  new_root "t$n"; n=$((n+1))
  for path in kit comm py; do
    b0="$(qrows "$to")"
    case "$path" in kit) send_kit "$to" "$from" "$body";; comm) send_comm "$to" "$from" "$body";; py) send_py "$to" "$from" "$body";; esac
    d=$(( $(qrows "$to") - b0 ))
    case "$want" in
      pass)   [ "$RC" -eq 0 ] && [ "$d" = 1 ] && r=PASS || r="FAIL(rc=$RC d=$d)";;
      reject) [ "$RC" -ne 0 ] && [ "$d" = 0 ] && case "$OUT" in *"$frag"*) r=PASS;; *) r="FAIL(사유 없음)";; esac || r="FAIL(rc=$RC d=$d)";;
    esac
    tab+=("$name|$path|rc=$RC|d=$d|$r")
    [ "$r" = PASS ] && ok "$name [${path}] rc=$RC 큐증감=$d" || bad "$name [${path}] $r :: ${OUT:0:200}"
  done
done

# ── ⓖ 세 길 결과 표 동일 · 판정기 1개를 셋이 부름(규칙 두 벌 0)
printf '%-44s %-12s %-12s %-12s %s\n' '케이스' 'kit(rc/큐)' 'comm(rc/큐)' 'python(rc/큐)' '같음'
sw=0
for ((i=0; i<${#tab[@]}; i+=3)); do
  a="${tab[$i]}"; b="${tab[$((i+1))]}"; c="${tab[$((i+2))]}"
  IFS='|' read -r nm _ ra da _ <<< "$a"; IFS='|' read -r _ _ rb db _ <<< "$b"; IFS='|' read -r _ _ rc2 dc _ <<< "$c"
  ka="${a#*|kit|}"; kb="${b#*|comm|}"; kc="${c#*|py|}"
  if [ "$ka" = "$kb" ] && [ "$ka" = "$kc" ]; then sm=O; else sm=X; sw=1; fi
  printf '%-44s %-12s %-12s %-12s %s\n' "$nm" "$ra/$da" "$rb/$db" "$rc2/$dc" "$sm"
done
[ "$sw" = 0 ] && ok "ⓖ 세 길 결과 표 동일(rc·큐 증감·판정 전부)" || bad "ⓖ 세 길 표가 다르다"
{ grep -q 'ft_desk_route_gate.py' "$COMM/mbox_desk_gate.py" && grep -q 'ft_desk_route_gate.py' "$KIT/ft-mbox.py" && [ -f "$GATE" ]; } \
  && ok "ⓖ 판정기 1개($(basename "$GATE"))를 키트·우편함 두 python 이 부름" || bad "ⓖ 판정기를 두 길이 안 부른다"
[ "$(grep -c 'desk 는 planner 에게만 보내요' "$COMM/mbox_desk_gate.py" "$KIT/ft-mbox.py" | awk -F: '{s+=$2} END{print s}')" = 0 ] \
  && grep -q 'desk 는 planner 에게만 보내요' "$GATE" \
  && ok "ⓖ 사람 말 사유 문구 = 판정기 1곳에만(호출부 0)" || bad "ⓖ 사유 문구가 두 벌"

# ── ⓘ 로그 쪽 경계: 지정 기록이 «h7abc» 뿐이면 h7 지정이 아니다(비단어 문자 경계)
new_root logbound
python3 - "$R" <<'PYLOG'
import json, sys, time
r = sys.argv[1]; today = time.strftime("%Y-%m-%dT%H:%M:%S")
with open(r + "/.fable-team/comm/mailbox.log.jsonl", "w") as f:
    f.write(json.dumps({"seq": 1, "ts": today, "from": "byz-planner-master-claude#94",
                        "to": "byz-harness-master-claude#92", "body": "h7abc 실행해라"}, ensure_ascii=False) + "\n")
PYLOG
send_comm "$D" "$HM" '[h7 결과] r660 로그 경계 — 끝'
{ [ "$RC" -ne 0 ] && case "$OUT" in *'desk 에는 planner 가 보내요'*) true;; *) false;; esac; } \
  && ok "ⓘ 지정 기록이 h7abc 뿐 → [h7 결과] REJECT(경계 = 비단어 문자)" || bad "ⓘ 로그 경계 rc=$RC :: ${OUT:0:200}"

# ── ⓘ multiple-line 전문 relay + h 결과 = REJECT(전문이 판정 재료) · 두 길 다
new_root relay; printf '[h7 결과] r660 relay 요약\n둘째 줄 전문\n셋째 줄 전문\n' > "$T/att.txt"
b0="$(qrows "$D")"; OUT="$(_env bash "$R/.fable-team/comm/mbox.sh" relay "$D" "$HM" "$T/att.txt" '[h7 결과] r660 relay 요약' 2>&1)"; RC=$?
{ [ "$RC" -ne 0 ] && [ "$(qrows "$D")" = "$b0" ] && case "$OUT" in *'desk 에는 planner 가 보내요'*) true;; *) false;; esac; } \
  && ok "ⓘ 여러 줄 전문 relay + [h7 결과] → comm REJECT · 큐 0" || bad "ⓘ comm relay rc=$RC :: ${OUT:0:200}"
OUT="$(_env bash "$KIT/ft-mbox.sh" relay "$D" "$HM" "$T/att.txt" '[h7 결과] r660 relay 요약' 2>&1)"; RC=$?
{ [ "$RC" -ne 0 ] && [ "$(qrows "$D")" = "$b0" ]; } && ok "ⓘ 여러 줄 전문 relay + [h7 결과] → kit REJECT · 큐 0" || bad "ⓘ kit relay rc=$RC :: ${OUT:0:200}"
printf '[h7 결과] r660 relay 1줄\n' > "$T/att1.txt"
OUT="$(_env bash "$R/.fable-team/comm/mbox.sh" relay "$D" "$HM" "$T/att1.txt" '[h7 결과] r660 relay 1줄' 2>&1)"; RC=$?
{ [ "$RC" -ne 0 ] && [ "$(qrows "$D")" = "$b0" ]; } \
  && ok "ⓘ relay 는 요약 1줄 + 전문 1줄 = 2줄 → h 예외 불가 REJECT(전문까지 «1줄» 이어야 통과 · DA⑥ r1 ⓑ③)" || bad "ⓘ relay 1줄 rc=$RC :: ${OUT:0:200}"
printf '[진행] r660 relay 직발\n' > "$T/att2.txt"
b0="$(qrows "$HM")"; OUT="$(_env bash "$R/.fable-team/comm/mbox.sh" relay "$HM" "$D" "$T/att2.txt" '[진행] r660 relay 직발' 2>&1)"; RC=$?
{ [ "$RC" -ne 0 ] && [ "$(qrows "$HM")" = "$b0" ]; } && ok "ⓘ relay desk→팀장 REJECT · 큐 0" || bad "ⓘ relay 직발 rc=$RC"

# ── ⓗ 판정기 고장 = 세 길 다 REJECT(fail-closed · 사유 1줄) · 없음 = desk 쪽지만 REJECT
new_root broken_gate; printf '#!/bin/sh\nexit 7\n' > "$T/badgate.sh"; chmod +x "$T/badgate.sh"
for path in kit comm py; do
  b0="$(qrows "$HM")"
  case "$path" in
    kit)  OUT="$(_env FT_DESK_GATE="$T/badgate.sh" bash "$KIT/ft-mbox.sh" send "$HM" "$D" '[진행] r660 게이트 고장' 2>&1)"; RC=$?;;
    comm) OUT="$(_env FT_DESK_GATE="$T/badgate.sh" bash "$R/.fable-team/comm/mbox.sh" send "$HM" "$D" '[진행] r660 게이트 고장' 2>&1)"; RC=$?;;
    py)   OUT="$(_env FT_DESK_GATE="$T/badgate.sh" python3 "$R/.fable-team/comm/mbox.py" send "$HM" "$D" '[진행] r660 게이트 고장' 2>&1)"; RC=$?;;
  esac
  { [ "$RC" -ne 0 ] && [ "$(qrows "$HM")" = "$b0" ] && case "$OUT" in *DESK_ROUTE_GATE_ERROR*) true;; *) false;; esac; } \
    && ok "ⓗ 판정기 예외 주입 → $path REJECT · 큐 0 · 사유 DESK_ROUTE_GATE_ERROR" || bad "ⓗ $path rc=$RC :: ${OUT:0:200}"
done
new_root nogate; rm -f "$R/.fable-team/bin/ft_desk_route_gate.py"
for path in comm py; do
  case "$path" in comm) send_comm "$HM" "$D" '[진행] r660 판정기 없음';; py) send_py "$HM" "$D" '[진행] r660 판정기 없음';; esac
  { [ "$RC" -ne 0 ] && case "$OUT" in *DESK_ROUTE_GATE_MISSING*) true;; *) false;; esac; } \
    && ok "ⓗ 판정기 파일 없음 → $path desk 쪽지 REJECT(설치 순서 · fail-closed)" || bad "ⓗ 게이트 없음[$path] rc=$RC :: ${OUT:0:200}"
done

# ── ⓕ 명부 이상 = 판정 0(통과 + WARN · 세 길 같은 문구)
new_root nofile; rm -f "$R/.fable-team/seats-planner.json"
for path in kit comm py; do
  b0="$(qrows "$HM")"
  case "$path" in kit) send_kit "$HM" "$D" "[진행] r660 명부 없음 $path";; comm) send_comm "$HM" "$D" "[진행] r660 명부 없음 $path";; py) send_py "$HM" "$D" "[진행] r660 명부 없음 $path";; esac
  { [ "$RC" = 0 ] && case "$OUT" in *'판정 0'*) true;; *) false;; esac && [ "$(( $(qrows "$HM") - b0 ))" = 1 ]; } \
    && ok "ⓕ seats-planner.json 없음 → $path 판정 0 · 통과 · WARN" || bad "ⓕ 없음[$path] rc=$RC :: ${OUT:0:160}"
done
new_root nodesk
python3 - "$R" <<'PY'
import json, sys
p = json.load(open(sys.argv[1] + "/.fable-team/seats-planner.json")); p.pop("_desk", None)
json.dump(p, open(sys.argv[1] + "/.fable-team/seats-planner.json", "w"))
PY
send_comm "$HM" "$D" '[진행] r660 _desk 칸 없음'
{ [ "$RC" = 0 ] && case "$OUT" in *'판정 0'*) true;; *) false;; esac; } \
  && ok "ⓕ _desk 칸 없음 → 판정 0 · 통과 · WARN" || bad "ⓕ _desk rc=$RC :: ${OUT:0:160}"
new_root broken; printf '{ 깨진 명부\n' > "$R/.fable-team/seats-planner.json"
for path in kit comm py; do
  case "$path" in kit) send_kit "$HM" "$D" "[진행] r660 명부 깨짐 $path";; comm) send_comm "$HM" "$D" "[진행] r660 명부 깨짐 $path";; py) send_py "$HM" "$D" "[진행] r660 명부 깨짐 $path";; esac
  line="$OUT"; plantxt=no; case "$line" in *'판정 0'*) plantxt=yes;; esac
  echo "깨진 명부[$path] rc=$RC 판정0=$plantxt — $(printf '%s' "$line" | head -1)" > "$T/broken.$path.txt"
  [ "$plantxt" = yes ] && ok "ⓕ 깨진 명부 → $path 판정기 WARN(판정 0 문구 확인 · 수신자 판정 D3 는 별개)" || bad "ⓕ 깨짐[$path] rc=$RC :: ${line:0:200}"
done
# 받는 쪽이 desk 인 경우 = comm 의 «수신자 판정 D3»(R97 · 이 카드 무변경)가 명부 깨짐을 먼저 거절한다 — desk 문 자체는 두 길 다 판정 0(위 3줄). 차이의 출처를 원문으로 못박는다.
send_kit "$D" "$HM" '[진행] r660 깨진 명부 · 받는 쪽 desk kit'
kitrc=$RC; kitout="$OUT"
send_comm "$D" "$HM" '[진행] r660 깨진 명부 · 받는 쪽 desk comm'
{ [ "$kitrc" = 0 ] && case "$kitout" in *'판정 0'*) true;; *) false;; esac; } \
  && ok "ⓕ 받는 쪽 desk + 깨진 명부 → kit = desk 문 판정 0 · 통과(카드 ⓕ 정책)" || bad "ⓕ desk-len kit rc=$kitrc :: ${kitout:0:160}"
case "$OUT" in *'명부 읽기 실패'*) ok "ⓕ 받는 쪽 desk + 깨진 명부 → comm = 수신자 판정 D3 가 거절(R97 · base 와 동일 동작 · 이 카드 무변경 — desk 문은 판정 0)";; *) bad "ⓕ D3 대조 rc=$RC :: ${OUT:0:200}";; esac
cat "$T"/broken.*.txt

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
