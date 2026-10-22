#!/usr/bin/env bash
# test_idle_slot_fill_r667.sh — 빈 석 자동 채우기 시험 (r667 · 원인 표 행 1-1~1-5 · DA⑥ r1 G1~G8)
#   ⓐ′ 계산기 팀 폴더 = FT_NANO_PREFIX 의 팀(v65 고정 아님) · ⓐ 지금 판(고치기 전) 쪽지 0·spawn 0 · ⓑ 1단계 쪽지 · ⓒ 2단계 자동 spawn(비동기)
#   ⓓ 0 조건(정지·동결·입력 중·팀 env 없음·FT_IDLE_SLOT_AUTO=0·후보 계산 실패) · ⓔ 상태 손상 = 0 + 보존
#   ⓗ 2단계는 기본 꺼짐(r667 범위 축소 · master 139846) — env 없음 = 쪽지 1통 · spawn 0 · 변이(기본값 1) = 그 칸 FAIL
#   G1 상태 소실 = 재시도 0 · 카드당 1회는 spawn «전» 선점(G1b) · G2 후보 A→B→A 30분 억제 · G3 쪽지 실패 → spawn 0(fail-closed)
#   G4 송신·spawn 직전 입력 재확인 · G5 부모 FT_INDEX_DIR 오염 0 · G6 팀장 = 명부 `_master`(둘째 행·라이브) · G7 spawn 75초여도 부모 ≤70초
# 격리: 임시 리포(FT_ROOT)·가짜 명부·가짜 tmux·가짜 mbox·가짜 spawn·가짜 seat-status·가짜 시계(FT_IDLE_WAKE_NOW). 실 좌석·실 명부·실 쪽지함 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${R667_SUT:-$HERE/../kit/fable-team/bin}"   # 기준 판(전/후 대조용) — 기본 = 지금 키트
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
ck()  { if [ "$2" = 0 ]; then ok "$1"; else bad "$1 :: $3"; fi; }

T="$(mktemp -d)"; trap '[ -n "${R667_KEEP:-}" ] && echo "KEPT=$T" || rm -rf "$T"' EXIT
BIN="$T/bin"; mkdir -p "$BIN" "$T/.fable-team/comm" "$T/.fable-team/state" "$T/design/teams/harness/indices/대기" "$T/design/teams/v65/indices/대기"
cp "$KIT/ft-idle-wake.sh" "$KIT/ft-nano-slots.sh" "$KIT/ft-team-lib.sh" "$BIN/" 2>/dev/null
cp "$KIT/ft_teamset.py" "$BIN/" 2>/dev/null
cp "$KIT/ft-idle-slot-fill.sh" "$BIN/" 2>/dev/null; chmod +x "$BIN"/*.sh 2>/dev/null

# ── 가짜 세계 ────────────────────────────────────────────────────────────────
cat > "$BIN/ft-seat-status.sh" <<'EOF'
#!/usr/bin/env bash
f="$STATUS_DIR/$2"; [ -f "$f" ] || { echo "turn: no jsonl" >&2; exit 3; }
cat "$f"
EOF
cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  ls) cat "$LIVE_TXT" 2>/dev/null; exit 0 ;;
  has-session) grep -qxF "${3#=}" "$LIVE_TXT" 2>/dev/null; exit $? ;;
  list-clients)   # ACT_FLIP=1 이면 «두 번째 호출부터» 입력 중 — G4 «직전 재확인» 시험용
    if [ -n "${ACT_FLIP:-}" ]; then
      n=$(( $(cat "$ACT_CALLS" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$ACT_CALLS"
      [ "$n" -ge 2 ] && cat "$ACTIVITY_TXT" 2>/dev/null
    else cat "$ACTIVITY_TXT" 2>/dev/null; fi
    exit 0 ;;
esac
exit 0
EOF
cat > "$BIN/mbox.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  send) [ "${SEND_FAIL:-0}" = 0 ] || { echo "REJECT mbox send 가짜 실패" >&2; exit 1; }
        python3 -c 'import json,sys;print(json.dumps({"to":sys.argv[1],"from":sys.argv[2],"body":sys.argv[3]},ensure_ascii=False))' "$2" "$3" "$4" >> "$MBOX_LOG"; echo "QUEUED seq=1 to=$2" ;;
  ring) echo "ring $2 $3" >> "$MBOX_LOG" ;;
esac
exit 0
EOF
cat > "$BIN/ft-all-stop.sh" <<'EOF'
#!/usr/bin/env bash
[ "${ALLSTOP_RC:-0}" = 0 ] || { echo "REJECT 전팀 정지 중(가짜)"; exit 1; }
exit 0
EOF
cat > "$BIN/ft-nano-spawn.sh" <<'EOF'
#!/usr/bin/env bash
{ printf 'ARGS\t%s\n' "$*"; printf 'PREFIX\t%s\n' "${FT_NANO_PREFIX:-<없음>}"; } >> "$SPAWN_LOG"
sleep "${SPAWN_SLEEP:-0}"
[ "${SPAWN_RC:-0}" = 0 ] || { echo "REJECT spawn 가짜 실패(rc=${SPAWN_RC})"; exit "${SPAWN_RC}"; }
echo "SPAWNED byz-harness-nano-fake#0 index=$1"
EOF
chmod +x "$BIN"/*
export STATUS_DIR="$T/status" LIVE_TXT="$T/live.txt" ACTIVITY_TXT="$T/activity.txt" ACT_CALLS="$T/calls.txt"
export MBOX_LOG="$T/mbox.log" SPAWN_LOG="$T/spawn.log"
mkdir -p "$STATUS_DIR" "$T/.fable-team/bin-harness"
: > "$ACTIVITY_TXT"; : > "$MBOX_LOG"; : > "$SPAWN_LOG"
echo 'export FT_NANO_PREFIX=byz-harness-nano-' > "$T/.fable-team/bin-harness/harness-env.sh"
SEAT='byz-harness-master-claude#95'
printf '%s\n' "$SEAT" > "$LIVE_TXT"

card() {  # card <팀> <파일>
  { echo "# 인덱스: $2"; echo "Issue: #7"; echo "상태: 대기"; echo "선행: 없음"; echo "시험 입력: 없음"; echo "## 구현 범위"; echo "x"; } > "$T/design/teams/$1/indices/대기/$2"
}
teams_md() { printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | x | 현역 |\n| v65 | `design/teams/v65/` | x | 현역 |\n'; }
teams_md > "$T/design/TEAMS.md"
card harness h1.md; card harness h2.md; card v65 v1.md
roster() {  # roster <팀> <_master> [이름=role …] — 팀 명부(v65 = seats.json · 그 밖 = seats-<팀>.json)
  local f="$T/.fable-team/seats-$1.json"; [ "$1" = v65 ] && f="$T/.fable-team/seats.json"
  python3 - "$f" "$2" "${@:3}" <<'EOF'
import json, sys
p, m, rows = sys.argv[1], sys.argv[2], sys.argv[3:]
d = {"_master": m}
for a in rows:
    n, _, r = a.partition("=")
    d[n] = {"role": r or "master", "tick": None}
json.dump(d, open(p, "w"), ensure_ascii=False)
EOF
}
roster_h() { roster harness "$@"; }
roster harness "$SEAT" "$SEAT=master"
gr() { git -C "$T" -c user.name=t -c user.email=t@t "$@"; }
commit_world() { gr add -A >/dev/null 2>&1; gr commit -qm "$1" >/dev/null 2>&1; gr update-ref refs/remotes/origin/main HEAD; }
gr init -q; commit_world base
NOW="$(date +%s)"
iso() { python3 -c 'import datetime as d,sys;print(d.datetime.fromtimestamp(int(sys.argv[1]),d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
set_state() { printf '%s %s\n' "$2" "$(iso "$3")" > "$STATUS_DIR/$1"; }   # set_state <좌석> <STATE> <턴 끝 epoch>
set_state "$SEAT" IDLE "$((NOW - 1200))"                                   # 팀장 IDLE 20분

run() {  # run [<가짜 now>] [env…] → ft-idle-wake 1회(그 안에서 빈 석 장치가 돈다)
  : > "$MBOX_LOG"
  local t0=$SECONDS n="${1:-$NOW}"; : > "$ACT_CALLS"   # ACT_FLIP 호출 수는 «회차마다» 1부터
  env FT_ROOT="$T" FT_MBOX="$BIN/mbox.sh" FT_SEAT_STATUS="$BIN/ft-seat-status.sh" \
    FT_TMUX="bash $BIN/tmux" FT_SEATS_JSON="$T/.fable-team/seats.json" FT_TEAMS_REF=origin/main \
    FT_IDLE_WAKE_NOW="$n" FT_IDLE_WAKE_LOG="$T/wake.log" FT_IDLE_SLOT_LOG="$T/slot.log" \
    PATH="$BIN:$PATH" "${@:2}" bash "${WAKESH:-$BIN/ft-idle-wake.sh}" >"$T/out" 2>"$T/err"
  rc=$?
  LAST_ELAPSED=$(( SECONDS - t0 ))
}
notes() { grep -c '"to"' "$MBOX_LOG" 2>/dev/null | tr -d ' '; }
note_has() { grep -qF -- "$1" "$MBOX_LOG"; }
spawns() { grep -c '^ARGS' "$SPAWN_LOG" 2>/dev/null | tr -d ' '; }
reset_all() { : > "$MBOX_LOG"; : > "$SPAWN_LOG"; : > "$T/slot.log"; rm -f "$T/.fable-team/state/idle-slot.json" "$T/.fable-team/state/idle-slot.seen" "$T/.fable-team/state"/idle-slot-spawn-*.log; }
wait_spawn() {  # wait_spawn <n> — 가짜 spawn 은 비동기(자식) — 로그가 찰 때까지 짧게 기다린다
  local i=0; while [ "$(spawns)" -lt "$1" ] && [ "$i" -lt 60 ]; do sleep 0.1; i=$((i+1)); done
}

bash -n "$KIT/ft-idle-wake.sh" && bash -n "$KIT/ft-idle-slot-fill.sh" && bash -n "$KIT/ft-nano-slots.sh"
ck "bash -n 3종" $? "$(bash -n "$KIT/ft-idle-wake.sh" 2>&1)"

# ── ⓐ′ 계산기 팀 폴더 = FT_NANO_PREFIX 의 팀 (v65 고정 아님) ────────────────────
slots() { ( cd "$T" && env FT_SEATS_JSON="$T/.fable-team/seats-harness.json" PATH="$BIN:$PATH" "$@" bash "$BIN/ft-nano-slots.sh" --json 2>"$T/serr" ); }
out="$(slots env FT_NANO_PREFIX=byz-harness-nano- FT_TEAMS_REF=origin/main)"
echo "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin);assert d["team"]=="harness",d["team"];assert [c.rsplit("/",1)[1] for c in d["candidates"]]==["h1.md","h2.md"],d["candidates"]' 2>/dev/null
ck "ⓐ′ 접두 byz-harness-nano- → 팀 harness · 후보 = harness 카드 2장" $? "$out $(cat "$T/serr")"
out="$(slots env FT_NANO_PREFIX=byz-v65-nano- FT_TEAMS_REF=origin/main)"
echo "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin);assert d["team"]=="v65",d["team"];assert [c.rsplit("/",1)[1] for c in d["candidates"]]==["v1.md"],d["candidates"]' 2>/dev/null
ck "ⓐ′ 접두 byz-v65-nano- → 팀 v65 · 후보 = v65 카드만" $? "$out"
out="$(slots env -u FT_NANO_PREFIX FT_TEAMS_REF=origin/main)"
echo "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin);assert d["team"]=="v65"' 2>/dev/null
ck "ⓐ′ 접두 미설정 → v65(기존 동작)" $? "$out"
out="$(slots env FT_NANO_PREFIX=nonsense- FT_TEAMS_REF=origin/main)"; rc2=$?
[ "$rc2" != 0 ] && grep -q 'ERROR FT_NANO_PREFIX' "$T/serr" && ! echo "$out" | grep -q 'SLOTS\|{'
ck "ⓐ′ 규칙 밖 접두 → ERROR rc≠0 · v65 후퇴 0 (rc=$rc2)" $? "$out $(cat "$T/serr")"

# ── ⓐ 지금 판(고치기 전 키트로 돌린 대조) = 쪽지 0 · spawn 0 — R667_SUT=base 일 때만 참 ──
if [ ! -f "$KIT/ft-idle-slot-fill.sh" ]; then
  reset_all; run "$NOW"
  [ "$(notes)" = 0 ] && [ "$(spawns)" = 0 ] && ok "ⓐ (고치기 전 판 $KIT) 쪽지 0 · spawn 0" || bad "ⓐ 고치기 전에도 움직임 notes=$(notes) spawns=$(spawns)"
else
  ok "ⓐ 건너뜀 — 지금 키트($KIT)에 빈 석 장치가 있다(전/후 대조는 R667_SUT=base 로)"
fi

# ── ⓑ 1단계 «빈 석 쪽지» ────────────────────────────────────────────────────
reset_all; run "$NOW"
[ "$(notes)" = 1 ] && note_has '[빈 석]' && note_has 'h1.md' && note_has 'h2.md' && note_has '착지 차례 대기 = 그 PR 만 대기' && note_has '900'
ck "ⓑ 팀장 IDLE 20분 · 후보 2 → «빈 석 쪽지» 1통(후보·900 포함)" $? "$(cat "$MBOX_LOG")"
[ "$(spawns)" = 0 ] && ok "ⓑ 쪽지 단계에서는 spawn 0" || bad "ⓑ 쪽지와 같이 spawn 됨"
run $((NOW + 60)); [ "$(notes)" = 0 ] && ok "ⓑ 같은 (팀, 후보 집합) 60초 뒤 → 쪽지 0(중복 억제)" || bad "ⓑ 중복 쪽지 $(cat "$MBOX_LOG")"
card harness h3.md; commit_world h3
run $((NOW + 1900)); { [ "$(notes)" = 1 ] && note_has 'h3.md'; } && ok "ⓑ 30분 지나고 후보 집합이 바뀌면 → 쪽지 1통" || bad "ⓑ 새 후보 집합 쪽지 없음"

# ── G2 후보 A→B→A — «집합별» 억제(마지막 sig 하나만 기억하면 30분 안 A 를 다시 보낸다) ─────────
rm -f "$T/design/teams/harness/indices/대기/h3.md"; commit_world h3-rm
reset_all; run "$NOW"                     # A,B 쪽지
card harness h3.md; commit_world h3-again
run $((NOW + 60))                         # A,B,h3 쪽지
rm -f "$T/design/teams/harness/indices/대기/h3.md"; commit_world h3-rm2
run $((NOW + 120))                        # 다시 A,B — 30분 안이므로 0
[ "$(notes)" = 0 ] && ok "G2 후보 A→B→A — 30분 안에 A 집합 재송신 0(집합별 시각 맵)" || bad "G2 A 집합 재송신 $(cat "$MBOX_LOG")"

# ── ⓗ 2단계는 «기본 꺼짐»(r667 범위 축소 · master 139846 · 2단계 재설계 = 새 카드 r721) ──────
reset_all; run "$NOW"; n_default="$(notes)"; note_ok=0
[ "$n_default" = 1 ] && note_has '[빈 석]' && note_has 'FT_IDLE_SLOT_AUTO=0' && [ "$(spawns)" = 0 ] && note_ok=1
run $((NOW + 901)); sleep 0.5
[ "$note_ok" = 1 ] && [ "$(spawns)" = 0 ] && ! grep -q '자동 spawn 기동' "$T/slot.log"
ck "ⓗa env 없음(기본) = 빈 석 쪽지 1통 · 900초 뒤에도 자동 spawn 0" $? "notes1=$n_default spawns=$(spawns) $(cat "$T/slot.log")"
reset_all; run "$NOW" FT_IDLE_SLOT_AUTO=1
grep -q '미검증' "$T/slot.log" && grep -q 'r721' "$T/slot.log"
ck "ⓗb 켜기 = 명시 FT_IDLE_SLOT_AUTO=1 이고 로그에 «r721 전까지 미검증» 1줄" $? "$(cat "$T/slot.log")"
# 변이: 기본값을 «1»(켜짐)로 되돌리면 ⓗa 가 FAIL 해야 한다 — 그 판을 여기서 실제로 돌린다
BINMUT="$T/bin-mut"; rm -rf "$BINMUT"; mkdir -p "$BINMUT"; cp "$BIN"/* "$BINMUT/" 2>/dev/null
python3 - "$KIT/ft-idle-slot-fill.sh" "$BINMUT/ft-idle-slot-fill.sh" <<'EOF'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = 'AUTO_ON = os.environ.get("FT_IDLE_SLOT_AUTO") == "1"'
new = 'AUTO_ON = (os.environ.get("FT_IDLE_SLOT_AUTO") or "1") != "0"'
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, new) if old in s else s)  # 기준 판(기본 켜짐)은 그대로 둔다
EOF
chmod +x "$BINMUT"/* 2>/dev/null
WAKESH="$BINMUT/ft-idle-wake.sh"
reset_all; run "$NOW"; run $((NOW + 901)); wait_spawn 1; sleep 0.3
unset WAKESH
[ "$(spawns)" -ge 1 ]
ck "ⓗc 변이(기본값 1 로 되돌림) → 자동 spawn 발생 = ⓗa 칸이 FAIL 하는 판(변별력)" $? "spawns=$(spawns) $(cat "$SPAWN_LOG")"

# ── ⓒ 2단계 «자동 spawn»(비동기 · 결과는 다음 틱 회수) ─────────────────────────
reset_all; run "$NOW"                     # 쪽지 → note 기록
run $((NOW + 901)) FT_IDLE_SLOT_AUTO=1; wait_spawn 1          # 900초 지나도 그대로 → 장치가 맨 위 1장(자식 프로세스)
[ "$(spawns)" = 1 ] && grep -q "h1.md" "$SPAWN_LOG" && grep -q -- "--from" "$SPAWN_LOG" && grep -q "byz-harness-nano-" "$SPAWN_LOG"
ck "ⓒ 900초 뒤 → 맨 위 카드 h1.md 1장 spawn · --from · 팀 env 서브셸(접두 주입)" $? "$(cat "$SPAWN_LOG")"
run $((NOW + 902)) FT_IDLE_SLOT_AUTO=1; note_has '[자동 spawn]' && note_has 'SPAWNED' && ok "ⓒ 다음 틱 회수 → 팀장에 «[자동 spawn] 카드·좌석» 쪽지" || bad "ⓒ 자동 spawn 쪽지 없음 :: $(cat "$MBOX_LOG") $(cat "$T/slot.log" | tail -3)"
run $((NOW + 1900)) FT_IDLE_SLOT_AUTO=1; wait_spawn 1; [ "$(spawns)" = 1 ] && ok "ⓒ 같은 카드 다시 spawn 0(카드당 1회)" || bad "ⓒ 같은 카드 재spawn $(cat "$SPAWN_LOG")"

# ── G1 상태 파일 소실 = 재시도 0(첫 실행 표식과 «사라짐» 구분) ──────────────────────
reset_all; run "$NOW"; run $((NOW + 901)) FT_IDLE_SLOT_AUTO=1; wait_spawn 1
[ -f "$T/.fable-team/state/idle-slot.seen" ] && ok "G1a 첫 실행 표식(idle-slot.seen) 생성" || bad "G1a 첫 실행 표식 없음"
rm -f "$T/.fable-team/state/idle-slot.json"; : > "$SPAWN_LOG"
run $((NOW + 1000)) FT_IDLE_SLOT_AUTO=1; wait_spawn 0; sleep 0.3
[ "$(spawns)" = 0 ] && [ "$(notes)" = 0 ] && grep -q '상태 파일 사라짐' "$T/slot.log"
ck "G1b 상태 파일 소실 → 그 틱 0 + 로그(«사라짐» ≠ 첫 실행) · 재spawn 0" $? "$(cat "$T/slot.log") spawns=$(cat "$SPAWN_LOG")"

# ── G1c 카드당 1회는 spawn «전» 선점 — spawn 이 실패해도 재spawn 0(재시도 = 사람) ─────────────
reset_all; run "$NOW"; run $((NOW + 901)) FT_IDLE_SLOT_AUTO=1 SPAWN_RC=3; wait_spawn 1
run $((NOW + 902)) FT_IDLE_SLOT_AUTO=1; note_has '[자동 spawn 실패]' && ok "G1c spawn 실패 원문이 팀장에 쪽지(조용한 실패 0)" || bad "G1c 실패 쪽지 없음 :: $(cat "$MBOX_LOG")"
: > "$SPAWN_LOG"; run $((NOW + 1900)) FT_IDLE_SLOT_AUTO=1; sleep 0.3
[ "$(spawns)" = 0 ] && ok "G1c 실패한 카드 재spawn 0(선점 기록이 먼저)" || bad "G1c 실패 카드 재spawn $(cat "$SPAWN_LOG")"

# ── G3 쪽지 실패 → 자동 spawn 0(fail-closed) · 다음 틱 재시도 ────────────────────────
reset_all; run "$NOW" SEND_FAIL=1
[ "$(notes)" = 0 ] && [ "$(spawns)" = 0 ] && grep -q '쪽지 실패' "$T/slot.log"
ck "G3a 쪽지 송신 실패 → note_at 저장 0 + 로그" $? "$(cat "$T/slot.log")"
run $((NOW + 901)) FT_IDLE_SLOT_AUTO=1 SEND_FAIL=1; sleep 0.3
[ "$(spawns)" = 0 ] && ok "G3b 쪽지가 한 번도 성공 안 했으면 900초 뒤에도 자동 spawn 0" || bad "G3b 쪽지 실패인데 spawn $(cat "$SPAWN_LOG")"
run $((NOW + 1900)) FT_IDLE_SLOT_AUTO=1; wait_spawn 0; sleep 0.3
[ "$(spawns)" = 0 ] && ok "G3c 여전히 실패면 spawn 0(fail-closed 유지)" || bad "G3c spawn 발생 $(cat "$SPAWN_LOG")"

# ── G4 송신·spawn 직전 입력(client_activity) 재확인 ────────────────────────────
reset_all; echo "$NOW" > "$ACTIVITY_TXT"; run "$NOW" ACT_FLIP=1; : > "$ACTIVITY_TXT"
[ "$(notes)" = 0 ] && grep -q '송신 직전 입력 감지' "$T/slot.log"
ck "G4a 첫 조회는 비었는데 송신 직전에 입력 → 쪽지 0 + 로그" $? "$(cat "$T/slot.log")"
reset_all; run "$NOW"; echo $((NOW + 901)) > "$ACTIVITY_TXT"; run $((NOW + 901)) FT_IDLE_SLOT_AUTO=1 ACT_FLIP=1; : > "$ACTIVITY_TXT"; sleep 0.3
[ "$(spawns)" = 0 ] && grep -q 'spawn 직전 입력 감지' "$T/slot.log"
ck "G4b spawn 직전에 입력 → spawn 0 + 로그(다음 틱)" $? "$(cat "$T/slot.log")"

# ── G5 부모 FT_INDEX_DIR(v65) 오염 0 — 후보 계산도 그 팀 env 서브셸 ───────────────────
reset_all; run "$NOW" FT_INDEX_DIR="$T/design/teams/v65/indices"
note_has 'h1.md' && ! note_has 'v1.md' && ok "G5 부모 FT_INDEX_DIR=v65 여도 harness 후보 = harness 카드만" || bad "G5 다른 팀 카드가 후보 :: $(cat "$MBOX_LOG")"
reset_all; run "$NOW" FT_INDEX_DIR="$T/nope-indices"
note_has 'h1.md' && ok "G5 부모 FT_INDEX_DIR 이 없는 폴더여도 그 팀 폴더로 센다" || bad "G5 후보 계산 실패 :: $(cat "$T/slot.log")"

# ── G6 팀장 = 명부 `_master` 대조(첫 행이 아니라 _master · 라이브 · 현역) ────────────────
FIRST='byz-harness-master-claude#7'
printf '%s\n' "$SEAT" "$FIRST" > "$LIVE_TXT"
set_state "$SEAT" IDLE "$((NOW - 1200))"; set_state "$FIRST" IDLE "$((NOW - 1200))"
roster_h "$SEAT" "$FIRST=master" "$SEAT=master"; commit_world master-2rows
reset_all; run "$NOW"
note_has "\"to\": \"$SEAT\"" && ! note_has "\"to\": \"$FIRST\"" && ok "G6a 팀장 = 명부 _master(둘째 행) — 첫 행에 쪽지 0" || bad "G6a 팀장 선택 오류 :: $(cat "$MBOX_LOG")"
roster_h 'byz-harness-master-claude#999' 'byz-harness-master-claude#999=master'; commit_world master-dead
printf '%s\n' "$SEAT" > "$LIVE_TXT"
reset_all; run "$NOW"
[ "$(notes)" = 0 ] && grep -q '라이브 아님' "$T/slot.log" && ok "G6b _master 가 라이브 아님 → 쪽지·spawn 0 + 로그" || bad "G6b 죽은 팀장에 쪽지 :: $(cat "$MBOX_LOG") $(cat "$T/slot.log")"
roster_h "$SEAT" "$SEAT=master"; commit_world master-back

# ── G7 spawn 이 오래 걸려도 부모 실행은 마감(70초) 안 — 비동기 ────────────────────────
reset_all; run "$NOW"; run $((NOW + 901)) FT_IDLE_SLOT_AUTO=1 SPAWN_SLEEP=75; wait_spawn 1
[ "$LAST_ELAPSED" -le 70 ] && ok "G7 가짜 spawn sleep 75 → 부모 실행 ${LAST_ELAPSED}초(≤70 · 비동기)" || bad "G7 부모가 spawn 을 기다렸다 ${LAST_ELAPSED}초"
[ "$(spawns)" = 1 ] && ok "G7 비동기로도 spawn 은 실제로 떴다" || bad "G7 spawn 안 뜸"

# ── G7c «한 틱 1장» — 두 팀이 동시에 준비돼도 폭주 0 ────────────────────────────
mkdir -p "$T/.fable-team/bin-loom"; echo 'export FT_NANO_PREFIX=byz-loom-nano-' > "$T/.fable-team/bin-loom/loom-env.sh"
roster loom 'byz-loom-master-claude#9' 'byz-loom-master-claude#9=master'
mkdir -p "$T/design/teams/loom/indices/대기"; card loom l2.md
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | x | 현역 |\n| loom | `design/teams/loom/` | x | 현역 |\n' > "$T/design/TEAMS.md"
commit_world loom-ready
printf '%s\n' "$SEAT" 'byz-loom-master-claude#9' > "$LIVE_TXT"; set_state 'byz-loom-master-claude#9' IDLE "$((NOW - 1200))"
reset_all; run "$NOW"; [ "$(notes)" = 2 ] && ok "G7c 두 팀 모두 «빈 석 쪽지» 1통씩" || bad "G7c 쪽지 $(cat "$MBOX_LOG")"
run $((NOW + 901)) FT_IDLE_SLOT_AUTO=1; wait_spawn 1; sleep 0.5
[ "$(spawns)" = 1 ] && ok "G7c 한 틱 spawn 1장(두 팀 준비돼도 폭주 0)" || bad "G7c 한 틱 다중 spawn $(cat "$SPAWN_LOG")"
rm -rf "$T/.fable-team/bin-loom" "$T/.fable-team/seats-loom.json"; rm -f "$T/design/teams/loom/indices/대기/l2.md"
printf '%s\n' "$SEAT" > "$LIVE_TXT"; commit_world loom-off

# ── ⓓ 0 조건 ────────────────────────────────────────────────────────────────
reset_all; run "$NOW" FT_IDLE_SLOT_AUTO=0; run $((NOW + 4000)) FT_IDLE_SLOT_AUTO=0
[ "$(spawns)" = 0 ] && [ "$(notes)" -ge 1 ] && note_has 'FT_IDLE_SLOT_AUTO=0'
ck "ⓓa FT_IDLE_SLOT_AUTO=0 → 쪽지는 가고 spawn 0" $? "spawns=$(spawns) notes=$(notes)"
reset_all; run "$NOW" ALLSTOP_RC=1
[ "$(notes)" = 0 ] && [ "$(spawns)" = 0 ] && grep -q '전팀 정지' "$T/slot.log"
ck "ⓓb 전팀 정지 → 쪽지 0 · spawn 0 + 로그 1줄" $? "$(cat "$T/slot.log")"
reset_all; : > "$T/.fable-team/state/RESOURCE_FREEZE"; run "$NOW"; rm -f "$T/.fable-team/state/RESOURCE_FREEZE"
[ "$(notes)" = 0 ] && [ "$(spawns)" = 0 ] && grep -q 'RESOURCE_FREEZE' "$T/slot.log"
ck "ⓓc 자원 동결 표식 → 0 + 로그" $? "$(cat "$T/slot.log")"
reset_all; echo "$NOW" > "$ACTIVITY_TXT"; run "$NOW"; : > "$ACTIVITY_TXT"
[ "$(notes)" = 0 ] && grep -q '오빠 입력 중' "$T/slot.log"
ck "ⓓd 팀장 화면에 오빠가 치는 중(client_activity) → 0 + 로그" $? "$(cat "$T/slot.log")"
reset_all; roster loom 'byz-loom-master-claude#9' 'byz-loom-master-claude#9=master'
printf '%s\n' 'byz-loom-master-claude#9' > "$LIVE_TXT"; set_state 'byz-loom-master-claude#9' IDLE "$((NOW - 1200))"
mkdir -p "$T/design/teams/loom/indices/대기"; card loom l1.md
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| loom | `design/teams/loom/` | x | 현역 |\n' > "$T/design/TEAMS.md"
commit_world loom
run "$NOW"
[ "$(notes)" = 0 ] && [ "$(spawns)" = 0 ] && grep -q '팀 env 없음' "$T/slot.log"
ck "ⓓe 팀 env 파일 없음(bin-loom/loom-env.sh) → 0 + 로그" $? "$(cat "$T/slot.log")"
printf '깨진' > "$T/.fable-team/seats-harness.json"; commit_world broken
reset_all; printf '%s\n' "$SEAT" > "$LIVE_TXT"; run "$NOW"
[ "$(notes)" = 0 ] && [ "$(spawns)" = 0 ] && grep -q '명부를 못 읽음' "$T/slot.log" && [ "$(cat "$T/.fable-team/seats-harness.json")" = '깨진' ]
ck "ⓕ 명부 못 읽음 → 0 + 로그 1줄(파일 보존)" $? "$(cat "$T/slot.log")"
roster_h "$SEAT" "$SEAT=master"; commit_world fixed

# ── ⓔ 상태 파일 손상 = 0(덮어쓰지 않는다) ────────────────────────────────────
reset_all; printf '{깨진' > "$T/.fable-team/state/idle-slot.json"; run "$NOW"
[ "$(notes)" = 0 ] && [ "$(spawns)" = 0 ] && [ "$(cat "$T/.fable-team/state/idle-slot.json")" = '{깨진' ] && grep -q '상태 파일 손상' "$T/slot.log"
ck "ⓔ 상태 파일 손상 → 0 · 로그 ERROR · 파일 보존" $? "$(cat "$T/slot.log")"

# ── ⓖ 기존 깨우기(ring) 동작 불변 — 같은 실행에서 mailbox 쪽지가 있으면 ring 은 그대로 ──────────
reset_all
python3 - "$T/.fable-team/comm/mailbox.jsonl" "$NOW" "$SEAT" <<'EOF'
import json,sys,time
p,now,seat=sys.argv[1:4]
open(p,"a",encoding="utf-8").write(json.dumps({"seq":77,"ts":time.strftime("%Y-%m-%dT%H:%M:%S",time.localtime(int(now)-400)),"to":seat,"from":"x","body":"b"})+"\n")
EOF
run "$NOW"; rm -f "$T/.fable-team/comm/mailbox.jsonl"
grep -q "ring $SEAT 77" "$MBOX_LOG" && ok "ⓖ 기존 ring 경로 불변(빈 석 장치가 깨우기를 막지 않는다)" || bad "ⓖ ring 사라짐 :: $(cat "$MBOX_LOG")"

echo; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL $fail"
exit "$fail"
