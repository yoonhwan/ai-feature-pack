#!/usr/bin/env bash
# test_r660_desk_route.sh — desk 창구 고정(r660 · 판정 1125): 쪽지 두 길이 «같은 판정기»(ft_desk_route_gate.py)로 같은 표를 낸다.
#   ⓐ 판정 전 FAIL 표(기대표는 카드 §시험 ⓑ~ⓕ) ⓑ desk → planner 만 통과 ⓒ 팀 → desk 거절 ⓓ 예외 4 ⓔ 판정 불변 ⓕ 명부 이상 = 판정 0(WARN) ⓖ 두 길 결과 표 동일.
# 임시 루트 명부(seats-planner.json `_master`·`_desk` + 팀 명부) + 임시 우편함 + 가짜 tmux 만 쓴다 — 실 큐·실 좌석·실 tmux·홈 쓰기 0.
# base 판 대조(카드 ⓐ) = FT_R660_COMM·FT_R660_KIT 로 «고치기 전» 폴더를 가리켜 같은 표를 돌린다(제품 우회 플래그 0 · 시험 입력 주입점).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
COMM="${FT_R660_COMM:-$REPO/harness/comm}"; KIT="${FT_R660_KIT:-$REPO/harness/kit/fable-team/bin}"
GATE="$KIT/ft_desk_route_gate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
# 우편함 사본(CSRC) — mbox.sh 의 가드 로그 자리($DIR/../state)가 «리포» 로 새지 않게 사본 폴더에서만 돌린다(실 상태 쓰기 0)
CSRC="$T/csrc"; mkdir -p "$CSRC"; cp "$COMM"/mbox*.sh "$COMM"/mbox*.py "$CSRC"/ 2>/dev/null; [ -f "$COMM/queues.conf" ] && cp "$COMM/queues.conf" "$CSRC"/; [ -f "$COMM/bang_command_check.py" ] && cp "$COMM/bang_command_check.py" "$CSRC"/
printf '#!/bin/sh\nexit 1\n' > "$T/stub/pgrep"; chmod +x "$T/stub/pgrep"

# ── 격리 루트: 명부 3팀(planner = _master·_desk) + 임시 우편함 + planner watch 표식(알람 재발신 차단)
new_root() {
  R="$T/root.$1"; rm -rf "$R"; mkdir -p "$R/.fable-team/comm" "$R/.fable-team/state"
  python3 - "$R" <<'PY'
import json, sys
r = sys.argv[1]
p = {"_master": "byz-planner-master-claude#94", "_desk": "byz-planner-desk-claude#38"}
p.update({k: {"role": "master"} for k in ("byz-planner-master-claude#94", "byz-planner-desk-claude#38", "byz-planner-desk-claude#37")})
json.dump(p, open(r + "/.fable-team/seats-planner.json", "w"))
h = {"_master": "byz-harness-master-claude#92"}
h.update({k: {"role": "master"} for k in ("byz-harness-master-claude#92", "byz-harness-nano-x#0")})
json.dump(h, open(r + "/.fable-team/seats-harness.json", "w"))
json.dump({"_master": "byz-other-master-claude#1", "byz-other-master-claude#1": {"role": "master"}},
          open(r + "/.fable-team/seats-other.json", "w"))
PY
  git -C "$R" init -q
  touch "$R/.fable-team/state/planner-watch-missing.byz-planner-master-claude#94"
  : > "$R/.fable-team/comm/mailbox.log.jsonl"
  printf '{"seq":1,"from":"byz-planner-master-claude#94","to":"byz-harness-master-claude#92","body":"h7 실행해라"}\n' >> "$R/.fable-team/comm/mailbox.log.jsonl"
}
# send_kit / send_comm <to> <from> <body> — 출력 = OUT · rc = RC (두 길이 같은 env 경계를 쓴다)
_env() { env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$R/.fable-team/seats-planner.json" FT_MBOX_DIR="$R/.fable-team/comm" \
             FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_MBOX_RESEND_COOLDOWN=0 "$@"; }
send_kit()  { OUT="$(_env bash "$KIT/ft-mbox.sh" send "$1" "$2" "$3" 2>&1)"; RC=$?; }
send_comm() { OUT="$(_env FT_BIN="$KIT" bash "$CSRC/mbox.sh" send "$1" "$2" "$3" 2>&1)"; RC=$?; }
qrows() { python3 - "$R/.fable-team/comm/mailbox.jsonl" "$1" <<'PY'
import json, sys
n = 0
try:
    fh = open(sys.argv[1], encoding="utf-8")
except OSError:
    sys.exit(0)
with fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("to") == sys.argv[2]:
            n += 1
print(n)
PY
}

D='byz-planner-desk-claude#38'; PM='byz-planner-master-claude#94'; HM='byz-harness-master-claude#92'
HN='byz-harness-nano-x#0'; OM='byz-other-master-claude#1'
# 표 = <이름>|<to>|<from>|<본문>|<기대 pass|reject>|<REJECT 사유 조각>
TABLE=(
 "desk→팀장 보통|$HM|$D|[진행] r660 표 1 — 보고|reject|desk 는 planner 에게만 보내요"
 "desk→팀 좌석|$HN|$D|[진행] r660 표 2 — 보고|reject|desk 는 planner 에게만 보내요"
 "desk→planner master|$PM|$D|[진행] r660 표 3 — 보고|pass|"
 "desk→[HIL] 팀장|$HM|$D|[HIL] r660 표 4 — 막힘\n①막힌 명령: x\n②막은 훅: y\n④선택지: a·b|pass|"
 "팀장→desk 보통|$D|$HM|[진행] r660 표 5 — 보고|reject|desk 에는 planner 가 보내요"
 "팀장→desk [HIL]|$D|$HM|[HIL] r660 표 6 — 오빠 판정 필요\n①막힌 명령: x\n②막은 훅: y\n④선택지: a·b|pass|"
 "팀장→desk [h7 결과] 기록 있음|$D|$HM|[h7 결과] r660 표 7 — 끝|pass|"
 "팀장→desk [h8 결과] 기록 없음|$D|$HM|[h8 결과] r660 표 8 — 끝|reject|desk 에는 planner 가 보내요"
 "팀장→desk [h7 결과] 2줄|$D|$HM|[h7 결과] r660 표 9 — 끝\n둘째 줄|reject|desk 에는 planner 가 보내요"
 "팀장→desk [긴급]|$D|$HM|[긴급] r660 표 10 — 급함|reject|desk 에는 planner 가 보내요"
 "desk 계보 인계|$D|byz-planner-desk-claude#37|[진행] r660 표 11 — 인계|pass|"
 "도구 발신→desk|$D|ft-tick|[진행] r660 표 12 — 틱|pass|"
 "slack→desk|$D|slack-oppa|r660 표 13 — 오빠 슬랙 글|pass|"
 "planner→팀|$HM|$PM|[발주] r660 표 14 — 발주|pass|"
 "팀끼리|$OM|$HM|[진행] r660 표 15 — 팀끼리|pass|"
)

# ── 1. 표를 «두 길»로 돌려 rc·큐 증감·사유를 비교(ⓑ~ⓔ·ⓖ)
tab=(); n=0
for row in "${TABLE[@]}"; do
  IFS='|' read -r name to from body want frag <<< "$row"
  body="$(printf '%b' "$body")"   # 표 안 개행은 «\n» 두 글자로 적는다(read 는 한 줄만 읽는다)
  new_root "t$n"; n=$((n+1))
  for path in kit comm; do
    b0="$(qrows "$to")"
    if [ "$path" = kit ]; then send_kit "$to" "$from" "$body"; else send_comm "$to" "$from" "$body"; fi
    d=$(( $(qrows "$to") - b0 ))
    case "$want" in
      pass)   [ "$RC" -eq 0 ] && [ "$d" = 1 ] && r=PASS || r="FAIL(rc=$RC d=$d)" ;;
      reject) [ "$RC" -ne 0 ] && [ "$d" = 0 ] && case "$OUT" in *"$frag"*) r=PASS;; *) r="FAIL(사유 없음)";; esac || r="FAIL(rc=$RC d=$d)";;
    esac
    tab+=("$name|$path|rc=$RC|d=$d|$r")
    [ "$r" = PASS ] && ok "$name [$path] rc=$RC 큐증감=$d" || bad "$name [$path] $r :: $OUT"
  done
done

# ── 2. ⓖ 두 길 «같은 표» · 판정기 1개를 둘이 부름(규칙 두 벌 0)
printf '%-38s %-12s %-12s %s\n' '케이스' 'kit(rc/큐)' 'comm(rc/큐)' '같음'
for ((i=0; i<${#tab[@]}; i+=2)); do
  a="${tab[$i]}"; b="${tab[$((i+1))]}"
  IFS='|' read -r nm _ ra da _ <<< "$a"; IFS='|' read -r _ _ rb db _ <<< "$b"
  [ "${a#*|kit|}" = "${b#*|comm|}" ] && sm=O || sm=X
  printf '%-38s %-12s %-12s %s\n' "$nm" "$ra/$da" "$rb/$db" "$sm"
done
sw=0
for ((i=0; i<${#tab[@]}; i+=2)); do
  a="${tab[$i]}"; b="${tab[$((i+1))]}"
  [ "${a#*|kit|}" = "${b#*|comm|}" ] || { sw=1; echo "  표 차이: $a vs $b"; }
done
[ "$sw" = 0 ] && ok "ⓖ 두 길 결과 표 동일(rc·큐 증감·판정 전부)" || bad "ⓖ 두 길 표가 다르다"
{ grep -q 'ft_desk_route_gate.py' "$COMM/mbox_guard_desk.sh" && grep -q 'ft_desk_route_gate.py' "$KIT/ft-mbox.py" && [ -f "$GATE" ]; } \
  && ok "ⓖ 판정기 1개($(basename "$GATE"))를 두 길이 부름" || bad "ⓖ 판정기를 두 길이 안 부른다"
{ [ "$(grep -c 'desk 는 planner 에게만 보내요' "$COMM/mbox_guard_desk.sh" "$KIT/ft-mbox.py" | awk -F: '{s+=$2} END{print s}')" = 0 ] && grep -q 'desk 는 planner 에게만 보내요' "$GATE"; } \
  && ok "ⓖ 사람 말 사유 문구 = 판정기 1곳에만(호출부 0)" || bad "ⓖ 사유 문구가 두 벌"

# ── 3. relay 도 같은 판정(카드 ⓖ) · 첨부 본문이 판정 재료
new_root relay; printf '[진행] r660 relay — 첨부\n둘째 줄\n' > "$T/att.txt"
b0="$(qrows "$HM")"; OUT="$(_env FT_BIN="$KIT" bash "$CSRC/mbox.sh" relay "$HM" "$D" "$T/att.txt" '[진행] r660 relay 요약' 2>&1)"; RC=$?
{ [ "$RC" -ne 0 ] && [ "$(qrows "$HM")" = "$b0" ] && case "$OUT" in *'desk 는 planner 에게만 보내요'*) true;; *) false;; esac; } \
  && ok "relay desk→팀장 REJECT · 큐 적재 0" || bad "relay rc=$RC :: $OUT"
new_root relay2
b0="$(qrows "$D")"; OUT="$(_env FT_BIN="$KIT" bash "$CSRC/mbox.sh" relay "$D" "$HM" "$T/att.txt" '[h7 결과] r660 relay 요약' 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && [ "$(qrows "$D")" = $((b0+1)) ]; } && ok "relay 팀장→desk [h7 결과] 기록 있음 = 통과" || bad "relay 예외 rc=$RC :: $OUT"

# ── 4. ⓕ 명부 이상 = 판정 0(통과 + WARN 1줄 · 조용히 막기 0)
new_root nofile; rm -f "$R/.fable-team/seats-planner.json"
send_comm "$D" "$HM" '[진행] r660 명부 없음'
{ [ "$RC" = 0 ] && case "$OUT" in *'판정 0'*) true;; *) false;; esac && [ "$(qrows "$D")" = 1 ]; } \
  && ok "ⓕ seats-planner.json 없음 → 판정 0 · 통과 · WARN" || bad "ⓕ rc=$RC :: $OUT"
new_root nodesk
python3 - "$R" <<'PY'
import json, sys
p = json.load(open(sys.argv[1] + "/.fable-team/seats-planner.json")); p.pop("_desk", None)
json.dump(p, open(sys.argv[1] + "/.fable-team/seats-planner.json", "w"))
PY
send_comm "$D" "$HM" '[진행] r660 _desk 칸 없음'
{ [ "$RC" = 0 ] && case "$OUT" in *'판정 0'*) true;; *) false;; esac; } \
  && ok "ⓕ _desk 칸 없음 → 판정 0 · 통과 · WARN" || bad "ⓕ _desk rc=$RC :: $OUT"
new_root broken; printf '{ 깨진 명부\n' > "$R/.fable-team/seats-planner.json"
printf '[진행] r660 명부 깨짐' > "$T/bb.txt"
OUT="$("$GATE" --to "$HM" --from "$D" --body-file "$T/bb.txt" --seats-dir "$R/.fable-team" --comm "$R/.fable-team/comm" 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && case "$OUT" in *'판정 0'*) true;; *) false;; esac; } \
  && ok "ⓕ 깨진 명부 → 판정기 rc0 · 판정 0 WARN(막지 않음)" || bad "ⓕ 깨짐 rc=$RC :: $OUT"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
