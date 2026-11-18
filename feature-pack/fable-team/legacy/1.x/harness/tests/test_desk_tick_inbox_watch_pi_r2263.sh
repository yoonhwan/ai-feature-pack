#!/usr/bin/env bash
# test_desk_tick_inbox_watch_pi_r2263.sh — ft-desk-tick.sh ④ 감시 칸은 seats 장부 agent=pi 좌석이면 «해당 없음» · 결정 필요에 안 든다(r2263 · 반례 ①~⑦)
#   C1 agent 값 = pi(모든 seats-*.json 에서 이 좌석 행 값이 pi 하나) → ps 판독 0 · «INBOX-WATCH 해당 없음(pi · doorbell 깨움)» · DEC 그대로
#   C2 agent 다름 · 행 없음 · JSON 깨짐 · 두 파일 값 다름 = 지금 ④ 그대로(감시 0 이면 DEC+1 · fail-closed)
#   C3 [완료] 3줄 꼴 그대로 · 둘째 줄 «감시 해당 없음»
# 전부 합성(임시 루트 · 가짜 mbox·hil·launchctl·ps) · 실 우편함 · 실 Slack · 외부 호출 0 · sleep 0.
# 변이 시험용: FT_R2263_SCRIPT = 시험할 ft-desk-tick.sh 경로(기본 = 이 팩 bin).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
S="${FT_R2263_SCRIPT:-$HERE/../bin/ft-desk-tick.sh}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
[ -f "$S" ] || { echo "FAIL ft-desk-tick.sh 없음: $S"; echo "FAILED 1"; exit 1; }

NOW=1794103664
DESK='byz-planner-desk-pi#210'; PLANNER='byz-planner-master-pi#335'
R="$T/root/.fable-team"; M="$R/comm/mbox.sh"
mkdir -p "$R/comm" "$T/fakebin" "$T/hil"

# seats 장부 — planner 파일 = 결속(_master·_desk) + 좌석 행(있으면) · 다른 파일 = seats-x.json
planner() {  # planner <agent|-> — «-» = 좌석 행 없음
  if [ "$1" = - ]; then printf '{"_master":"%s","_desk":"%s"}\n' "$PLANNER" "$DESK"
  else printf '{"_master":"%s","_desk":"%s","%s":{"agent":"%s","role":"desk"}}\n' "$PLANNER" "$DESK" "$DESK" "$1"; fi > "$R/seats-planner.json"
  rm -f "$R/seats-x.json"
}

# 가짜 mbox: peek = 0통 · send = $FAKE_SENT 에 JSON 1줄
cat > "$M" <<'EOS'
#!/usr/bin/env bash
case "${1:-}" in
  peek) echo "pending=0 scanned=1 lineage=fake"; exit 0;;
  send) python3 - "$FAKE_SENT" "$2" "$3" "$4" <<'PY'
import json, sys
open(sys.argv[1], "a").write(json.dumps({"to": sys.argv[2], "from": sys.argv[3], "body": sys.argv[4]}, ensure_ascii=False) + "\n")
PY
        exit 0;;
esac
exit 2
EOS
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/hil/ft-hil.sh"
cat > "$T/fakebin/launchctl" <<'EOS'
#!/usr/bin/env bash
echo "$2"; echo "	state = not running"
case "$2" in *ft-tick) echo "	last exit code = (never exited)";; *) echo "	last exit code = 0";; esac
EOS
# 가짜 ps — 부를 때마다 $FAKE_PS_CALLS 에 1줄 · FAKE_WATCH=1 이면 실 watcher argv 꼴 1줄
cat > "$T/fakebin/ps" <<'EOS'
#!/usr/bin/env bash
echo ps >> "$FAKE_PS_CALLS"
echo "  111 /usr/bin/login -fp yoonhwan"
[ "${FAKE_WATCH:-0}" = 1 ] && echo " 4242 /opt/homebrew/bin/python3 -u - /x/bin $FAKE_DESK"
exit 0
EOS
chmod +x "$T/fakebin/launchctl" "$T/fakebin/ps"   # 시험 픽스처만 실행 비트
# ①②③⑤ 정상 픽스처(r2187 과 같음) — ④ 말고는 결정 필요 0
printf 'ts=%s stall=0 a=0 b=0 c=0 d=0 seats=1\n' "$NOW" > "$T/stall.log"
printf '{"ts":"2026-11-08T11:02:44Z","from":"%s","to":"x","body":"y"}\n' "$PLANNER" > "$R/comm/mailbox.log.jsonl"
( cd "$T/root" && git init -q && mkdir -p design/teams/planner && printf '## 골 진행\n\n| 1 | a |\n\n## 끝\n' > design/teams/planner/PLAN-oppa-ledger.md && git add design && git -c user.email=t@t -c user.name=t commit -qm t && git update-ref refs/remotes/origin/main HEAD && git update-ref refs/remotes/origin/ops/main-base HEAD )

run() {  # run [FAKE_WATCH] — 결과 = $out · $rc
  : > "$T/pscalls"; rm -f "$T/sent.jsonl"
  out="$(env FT_ROOT="$T/root" FT_HIL_DIR="$T/hil" FT_DESK_TICK_MBOX="$M" FT_DESK_TICK_HIL="$T/hil/ft-hil.sh" \
      FT_DESK_TICK_LAUNCHCTL="$T/fakebin/launchctl" FT_DESK_TICK_PS="$T/fakebin/ps" \
      FT_DESK_TICK_STALL_LOG="$T/stall.log" FT_DESK_TICK_LOG="$R/comm/mailbox.log.jsonl" \
      FT_DESK_TICK_NOW="$NOW" FT_DESK_TICK_UID=501 \
      FAKE_SENT="$T/sent.jsonl" FAKE_PS_CALLS="$T/pscalls" FAKE_WATCH="${1:-0}" FAKE_DESK="$DESK" bash "$S" "$DESK" 2>&1)"; rc=$?
}
watch_line() { printf '%s\n' "$out" | grep '^INBOX-WATCH' | head -1; }
last() { printf '%s\n' "$out" | tail -1; }
NA='INBOX-WATCH 해당 없음(pi · doorbell 깨움)'; NONE='INBOX-WATCH 없음(desk 감시 프로세스 0)'
expect() {  # expect <사례> <감시 줄> <결정 필요>
  if [ "$(watch_line)" = "$2" ] && [ "$(last)" = "결정 필요: $3" ]; then ok "$1 «$2» · 결정 필요 $3"
  else bad "$1 감시 줄 = «$(watch_line)» · $(last) (기대 «$2» · $3)"; fi
}

# ① agent pi · 감시 0 → 해당 없음 · 결정 필요 0 · ps 판독 0
planner pi; run 0
expect ① "$NA" 0
[ "$(grep -c . "$T/pscalls")" = 0 ] && ok "① ps 판독 0" || bad "① ps 를 $(grep -c . "$T/pscalls")회 불렀다"
[ "$rc" = 0 ] && ok "① rc0" || bad "① rc=$rc"

# ⑦ ① 세계의 [완료] 3줄 — 첫 줄 [완료] · 둘째 줄 «감시 해당 없음» · 3줄
body="$(python3 -c 'import json,sys; print(json.loads(open(sys.argv[1]).readline())["body"])' "$T/sent.jsonl" 2>/dev/null)"
l2="$(printf '%s\n' "$body" | sed -n 2p)"
if [ "$(printf '%s\n' "$body" | grep -c .)" = 3 ] && printf '%s\n' "$body" | head -1 | grep -q '^\[완료\] desk 틱 — ' \
   && printf '%s\n' "$l2" | grep -qE '^남은 일: 결정 필요 0 · 팀장 정체 0건 · 감시 해당 없음$'; then ok "⑦ [완료] 3줄 · «감시 해당 없음»"
else bad "⑦ [완료] 본문 = $(printf '%s' "$body" | tr '\n' '/')"; fi

# ② agent claude(이름은 -pi#) · 감시 0 → 없음 · 1
planner claude; run 0; expect ② "$NONE" 1

# ③ agent claude · 감시 argv « -u - <bin> <desk>» 있음 → 감시 중 · 0
planner claude; run 1
if printf '%s\n' "$(watch_line)" | grep -qxF "INBOX-WATCH 4242 ${DESK%%#*} 감시 중" && [ "$(last)" = '결정 필요: 0' ]; then ok "③ 감시 중 · 결정 필요 0"
else bad "③ 감시 줄 = «$(watch_line)» · $(last)"; fi

# ④ 좌석 행 없음 · 감시 0 → 없음 · 1
planner -; run 0; expect ④ "$NONE" 1

# ⑤ JSON 깨짐 — ⑤a 좌석 행 agent pi + 다른 seats 파일 깨짐 ⑤b 좌석 행이 깨진 파일에만 있음 → 둘 다 없음 · 1
planner pi; printf '{"%s":{"agent":"pi"' "$DESK" > "$R/seats-x.json"; run 0; expect ⑤a "$NONE" 1
planner -; printf '{"%s":{"agent":"pi","role":"desk"}' "$DESK" > "$R/seats-x.json"; run 0; expect ⑤b "$NONE" 1

# ⑥ 두 seats 파일에 같은 좌석 · agent pi 와 claude → 없음 · 1
planner pi; printf '{"%s":{"agent":"claude"}}\n' "$DESK" > "$R/seats-x.json"; run 0; expect ⑥ "$NONE" 1

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
