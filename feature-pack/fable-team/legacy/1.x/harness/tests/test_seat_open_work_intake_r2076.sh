#!/usr/bin/env bash
# test_seat_open_work_intake_r2076.sh — r2076 E5·E6: 팀장 빈 2.0 팀의 사슬 끝 팀장 좌석은 ft2 접수 남은 일을 «받을 일» 로 센다.
#   반례 ⑥ ⑦(카드 그대로) + 변이 M6~M8(사본에서만 · 변이마다 원본으로 같은 사례 1회 = 반대 결과 대조)
#   임시 루트 · 가짜 tmux·tmuxc·pgrep · fake_resource_env · ft2 cli 스텁(FT2_CLI = JSON 1줄 + 불린 횟수) — 실 ft2·실 우편함·실 명부 쓰기 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
TOOL="$REPO/bin/ft-seat-open-work.py"; KITTOOL="$REPO/kit/fable-team/bin/ft-seat-open-work.py"; KB="$REPO/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0; t0="$(date +%s)"
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
RT="$(command -v tmux || true)"; tls() { [ -z "$RT" ] || "$RT" ls -F '#S' 2>/dev/null | sort; }; tl0="$(tls)"   # 실 tmux 세션 목록(스텁 PATH 앞에서 잡은 실 tmux)
I57='byz-issues-master-claude#57'; I60='byz-issues-master-sol#60'; I61='byz-issues-master-pi#61'
ROSTER='{"_master": "", "byz-issues-master-claude#57": {"role": "stop-ready", "agent": "claude", "_replaced_by": "byz-issues-master-sol#58"}, "byz-issues-master-sol#58": {"role": "stop-ready", "agent": "codex", "_replaces": ["byz-issues-master-claude#57"], "_replaced_by": "byz-issues-master-sol#59"}, "byz-issues-master-sol#59": {"role": "stop-ready", "agent": "codex", "_replaces": ["byz-issues-master-sol#58"], "_replaced_by": "byz-issues-master-sol#60"}, "byz-issues-master-sol#60": {"role": "stop-ready", "agent": "codex", "_replaces": ["byz-issues-master-sol#59"], "_closed": {"by": "x", "at": "2026-11-13T12:47:55"}}}'
BASE0='OPEN-WORK 0 이유=쪽지0(일 아님 0)·배정0·진행0'
FAKE="$T/fakebin"; W="$T/wt"; LOG="$T/calls.log"; BODY="$T/body.txt"; CNT="$T/cli.count"; mkdir -p "$FAKE" "$W" "$T/home"; git -C "$W" init -q
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n열린 칸 감시: 없음\n본문\n' > "$BODY"; : > "$FAKE/mbox_doorbell.sh"
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux 'case "$1" in has-session) exit 1;; list-panes) echo 4242;; display-message) echo "$WT";; esac; exit 0'
mkstub tmuxc 'echo "tmuxc $*" >> "$LOG"; exit 0'; mkstub pgrep 'echo 5555; exit 0'
mkstub send 'echo "send $*" >> "$LOG"; echo "QUEUED seq=777"; exit 0'; mkstub reach 'exit 0'
mkstub mbox 'echo "mbox $1 $2" >> "$LOG"; echo "QUEUED seq=901 doorbell=sent"; exit 0'
cat > "$T/ft2cli.py" <<'PY'
import json, os, sys
open(os.environ["CLI_COUNT"], "a").write(" ".join(sys.argv[1:]) + "\n")
if os.environ.get("FAKE_MODE") == "notjson":
    print("not json")
else:
    rem = os.environ.get("FAKE_REMAINING", "8")
    print(json.dumps({"result": os.environ.get("FAKE_RESULT", "접수 성공"), "team": "issues", "remaining": rem if os.environ.get("FAKE_STR") else int(rem), "capacity": 8}))
sys.exit(int(os.environ.get("FAKE_RC", "0")))
PY
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok; RES="$FT_RES_ROOT"
world() {   # 실사건 꼴 명부(사슬 claude#57 → sol#58 → sol#59 → sol#60 · _master 빈 글) · issues 표식 · 쪽지·배정·진행 0
  for r in "$RES" "$W"; do
    rm -rf "$r/design" "$r/.fable-team"; mkdir -p "$r/design/teams/issues/indices" "$r/.fable-team/comm/receipts" "$r/.fable-team/state/card-assign" "$r/.fable-team/state/ft20-switch"
    printf '%s\n' "$ROSTER" > "$r/.fable-team/seats-issues.json"; : > "$r/.fable-team/comm/mailbox.jsonl"
    printf '{"team":"issues","switched_at":"2026-11-12T00:00:00+0900","h":"1794494025.738289","by":"fx"}\n' > "$r/.fable-team/state/ft20-switch/issues.json"
    printf '2026-11-10T00:00:00\toff\tinstall\tinit\n' > "$r/.fable-team/state/all-stop.log"
    printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| issues | `design/teams/issues/` | byz-issues-master-pi | 현역 |\n' > "$r/design/TEAMS.md"
  done
  printf '| 팀 | 오케 | arch 상시 |\n|---|---|---|\n| issues | byz-issues-master-pi | — |\n' > "$T/teamset.md"
  printf '<!-- S17-BOOT-BEGIN -->\n목적 0 = 진행 카드를 완성하고 닫는다.\n<!-- S17-BOOT-END -->\n' > "$T/gov.md"
  : > "$CNT"
}
roster_edit() { python3 - "$RES/.fable-team/seats-issues.json" "$1" <<'PY'
import json, sys
p, op = sys.argv[1:]; d = json.load(open(p))
if op == "pi61": d["_master"] = "byz-issues-master-pi#61"
if op == "nomaster": d.pop("_master")
json.dump(d, open(p, "w"))
PY
}
ow() {   # ow [env…] — 판정 도구 단독(좌석 = $SEAT 또는 sol#60)
  ( for kv in "$@"; do export "$kv"; done; env HOME="$T/home" CLI_COUNT="$CNT" FT2_CLI="${CLI-$T/ft2cli.py}" python3 "${TD:-$TOOL}" "${SEAT:-$I60}" --root "$RES" ) > "$T/ow.out" 2> "$T/ow.err"
  RC=$?; OUT="$(cat "$T/ow.out")"; ERR="$(cat "$T/ow.err")"; CALLS="$(grep -c . "$CNT")"
}
so() {   # so <구> <후계> <agent> — ft-successor-open(가짜 tmuxc 열기까지)
  : > "$LOG"
  env HOME="$T/home" PATH="$FAKE:$PATH" WT="$W" LOG="$LOG" CLI_COUNT="$CNT" FT_ROOT="$RES" FT_RES_ROOT="$RES" FT_FT20_ROOT="$RES" FT2_CLI="$T/ft2cli.py" \
      SENSORS="$T/sensors/fake-sensors" FT_TEAMSET_MD="$T/teamset.md" FT_GOV_MD="$T/gov.md" FT_SO_POLL=0 FT_SO_WAIT_MAX=2 \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" \
      bash "$KB/ft-successor-open.sh" "$1" "$W" --name "$2" --agent "$3" --model claude-sonnet-5-5 --ctx 1m --body-file "$BODY" > "$T/so.out" 2>&1
  RC=$?; OPEN="$(grep -c '^tmuxc open' "$LOG")"; OW0="$(grep -c '^OPEN-WORK-0' "$T/so.out")"
}
is() { [ "$RC" = "$1" ] && [ "$OUT" = "$2" ]; }

# ⑥ 접수 남은 일
world; ow;                    ck "⑥ remaining 8 → rc=$RC(1) «접수 남은 일 8» · cli ${CALLS}회" "$(is 1 'OPEN-WORK 있음 이유=접수 남은 일 8' && [ "$CALLS" = 1 ] && grep -q "^project --root $RES --team issues$" "$CNT" && echo 0 || echo 1)"
world; ow FAKE_REMAINING=0;   ck "⑥ remaining 0 → rc=$RC(0) · 기준판 출력" "$(is 0 "$BASE0"$'\n''LEADER -' && echo 0 || echo 1)"
world; rm -f "$RES/.fable-team/state/ft20-switch/issues.json"; ow
ck "⑥ 표식 없음 → rc=$RC(0) · cli ${CALLS}회" "$(is 0 "$BASE0"$'\n''LEADER -' && [ "$CALLS" = 0 ] && echo 0 || echo 1)"
world; roster_edit pi61; ow;  ck "⑥ _master = pi#61 → rc=$RC(0) · LEADER 그대로" "$(is 0 "$BASE0"$'\n'"LEADER $I61" && echo 0 || echo 1)"
world; roster_edit nomaster; ow; ck "⑥ _master 칸 없음 → rc=$RC(0)" "$(is 0 "$BASE0"$'\n''LEADER -' && echo 0 || echo 1)"
world; SEAT="$I57" ow;        ck "⑥ 사슬 중간 claude#57 → rc=$RC(0)" "$(is 0 "$BASE0"$'\n''LEADER -' && echo 0 || echo 1)"
world; SEAT='byz-issues-master-sol#61' ow; ck "⑥ 명부에 행 없음 sol#61 → rc=$RC(0)" "$(is 0 "$BASE0"$'\n''LEADER -' && echo 0 || echo 1)"
world; SEAT='byz-issues-arch-pi#3' ow;     ck "⑥ 역할 arch → rc=$RC(0)" "$(is 0 "$BASE0"$'\n''LEADER -' && echo 0 || echo 1)"
world; SEAT='byz-issues-desk-pi#3' ow;     ck "⑥ 역할 desk → rc=$RC(0)" "$(is 0 "$BASE0"$'\n''LEADER -' && echo 0 || echo 1)"
world; printf '{"seq": 1, "ts": "2026-11-16T00:00:00", "to": "%s", "from": "byz-planner-master-pi#322", "body": "[발주] issues 접수 1건"}\n' "$I60" > "$RES/.fable-team/comm/mailbox.jsonl"; ow
ck "⑥ remaining 8 + 미처리 [발주] 1 → rc=$RC(1) «쪽지 일 1» · cli ${CALLS}회(0)" "$(is 1 'OPEN-WORK 있음 이유=쪽지 일 1' && [ "$CALLS" = 0 ] && echo 0 || echo 1)"
world; so "$I60" "$I61" pi
ck "⑥ successor-open sol#60 → pi#61 rc=$RC · OPEN-WORK-0 ${OW0}줄(0) · tmuxc open ${OPEN}회(1)" "$([ "$OW0" = 0 ] && [ "$OPEN" = 1 ] && ! grep -q '2.0 전환됨' "$T/so.out" && echo 0 || echo 1)"
world; so "$I57" 'byz-issues-master-claude#61' claude
ck "⑥ successor-open claude#57 → claude#61 rc=$RC(6) · OPEN-WORK-0 ${OW0}줄(1)" "$([ "$RC" = 6 ] && [ "$OW0" = 1 ] && echo 0 || echo 1)"

# ⑦ 판독 실패 = rc 3(rc 0 으로 새는 길 0)
R7='OPEN-WORK 불가 이유=접수 판독'; R7M='OPEN-WORK 불가 이유=2.0 표식·명부 판독'
world; ow FAKE_RC=1
ck "⑦ cli rc 1 → rc=$RC(3) · stderr 1줄" "$(is 3 "$R7" && [ "$ERR" = '받을 일 판정 불가 접수 판독 — 기존 승계' ] && echo 0 || echo 1)"
world; ow FAKE_RESULT=손상;    ck "⑦ result 손상 → rc=$RC(3)" "$(is 3 "$R7" && echo 0 || echo 1)"
world; ow FAKE_MODE=notjson;   ck "⑦ stdout JSON 아님 → rc=$RC(3)" "$(is 3 "$R7" && echo 0 || echo 1)"
world; ow FAKE_STR=1;          ck "⑦ remaining 글자 «8» → rc=$RC(3)" "$(is 3 "$R7" && echo 0 || echo 1)"
world; CLI=/nonexistent ow;    ck "⑦ FT2_CLI 없는 경로 → rc=$RC(3)" "$(is 3 "$R7" && echo 0 || echo 1)"
world; printf '{"team":' > "$RES/.fable-team/state/ft20-switch/issues.json"; ow
ck "⑦ 표식 깨짐 → rc=$RC(3) · 표식·명부 판독" "$(is 3 "$R7M" && [ "$ERR" = '받을 일 판정 불가 2.0 표식·명부 판독 — 기존 승계' ] && echo 0 || echo 1)"
world; printf '{"h":""}\n' > "$RES/.fable-team/state/ft20-switch/issues.json"; ow; ck "⑦ 표식 h 빈 글 → rc=$RC(3)" "$(is 3 "$R7M" && echo 0 || echo 1)"
world; printf '{"_master": ' > "$RES/.fable-team/seats-issues.json"; ow;      ck "⑦ seats-issues.json 깨짐 → rc=$RC(3)" "$(is 3 "$R7M" && echo 0 || echo 1)"

ck "kit 사본 ft-seat-open-work.py cmp 0" "$(cmp -s "$TOOL" "$KITTOOL" && echo 0 || echo 1)"

# ── 변이(사본에서만) — 변이 사본은 틀리고, 원본은 같은 사례에서 맞다 ──
mut() {  # mut <이름> <원문> <바꿀 글>
  TD="$T/mut-$1.py"; cp -p "$TOOL" "$TD"
  python3 - "$TD" "$2" "$3" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
mcase() {  # mcase <변이> <사례> <원본 기대 rc> <prep 함수> [env…] — 변이 rc ≠ 원본 rc · 원본 = 기대 rc
  local nm="$1" cs="$2" want="$3" prep="$4" m; shift 4
  world; $prep; ow "$@"; m="$RC"; TD=""; world; $prep; ow "$@"
  ck "$nm $cs → 변이 rc=$m · 원본 rc=$RC($want)" "$([ "$RC" = "$want" ] && [ "$m" != "$want" ] && echo 0 || echo 1)"
}
p_pi61() { roster_edit pi61; }; p_none() { :; }; p_mid() { SEAT="$I57"; export SEAT; }
mut M6 'ros.get("_master") != "" or ' '';            mcase M6 "⑥ _master = pi#61" 0 p_pi61
mut M7 ' or row.get("_replaced_by")' '';             mcase M7 "⑥ 사슬 중간 claude#57" 0 p_mid; unset SEAT
mut M8 'return 3, "접수 판독", ""' 'return None';     mcase M8 "⑦ cli rc 1" 3 p_none FAKE_RC=1
TD=""

tl1="$(tls)"; TN="$T/tnames"; for x in $I61 byz-issues-master-claude#61; do printf '%s\n' "$x"; done > "$TN"
nt="$(comm -13 <(printf '%s\n' "$tl0") <(printf '%s\n' "$tl1") | grep -cFx -f "$TN")"
ck "실 tmux 새 세션 중 시험 이름 ${nt}개(0) · 전체 $(printf '%s' "$tl0" | grep -c .) → $(printf '%s' "$tl1" | grep -c .)" "$([ "$nt" = 0 ] && echo 0 || echo 1)"
echo "RUN 1회차 $(( $(date +%s) - t0 ))초 · 사례 $n"
[ "$fail" = 0 ] || { echo "FAIL 합계 $fail"; exit 1; }
echo "PASS 합계 $n"
