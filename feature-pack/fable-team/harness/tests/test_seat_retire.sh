#!/usr/bin/env bash
# test_seat_retire.sh — R43: 틱 정지 감시는 _master 아닌 옛 role=master 행을 건너뛴다 · ft-seat-retire.sh · ft-role-spawn.sh 옛 행 닫기.
# 모든 쓰기는 mktemp scratch 안 — 라이브 좌석표·stamp·tmux 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"
TICK="$BIN/ft-tick.sh"; RETIRE="$BIN/ft-seat-retire.sh"; SPAWN="$BIN/ft-role-spawn.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok   # R218: 자원 문지기 센서를 가짜로(실 머신 부하·압력 무관)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
J() { jq -r "$2" "$1"; }

for f in "$TICK" "$RETIRE" "$SPAWN"; do bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $f"; done
chk "ft-seat-retire.sh ≤ 200줄" "$([ "$(wc -l < "$RETIRE")" -le 200 ] && echo yes || echo no)" yes

# ①② 틱 stall 대상 (dry-run) · all_seats 는 함수 추출
stall_seats() { # <좌석표 json>
  printf '%s' "$1" > "$TMP/s.json"
  FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_HIL=0 FT_TICK_DRIFT=0 FT_TICK_SEATS="$TMP/s.json" FT_TICK_STAMP_PREFIX="$TMP/p-" FT_TICK_STATE_DIR="$TMP/st" \
    bash "$TICK" --once --dry-run 2>&1 | sed -n 's/^DRY kind=stall .* seats=//p' | xargs
}
all_seats() { printf '%s' "$1" > "$TMP/s.json"; bash -c "SEATS=$TMP/s.json; $(sed -n '/^all_seats() {/,/^}/p' "$TICK")"$'\n''all_seats' | cut -f1 | xargs; }
ROW='"role": "master", "tick": "ft-master-tick"'
WITH="{\"_master\": \"M#2\", \"M#1\": {$ROW}, \"M#2\": {\"role\": \"master\", \"tick\": null}, \"N#0\": {\"role\": \"nano\"}}"
chk "①stall: 옛 M#1 제외 · M#2·N#0 포함" "$(stall_seats "$WITH")" "M#2 N#0"
chk "①all_seats: 옛 M#1 제외" "$(all_seats "$WITH")" "M#2 N#0"
WITHOUT="{\"M#1\": {$ROW}, \"M#2\": {\"role\": \"master\"}, \"N#0\": {\"role\": \"nano\"}}"
chk "②_master 없음 → 무변경(M#1 M#2 N#0)" "$(stall_seats "$WITHOUT")" "M#1 M#2 N#0"
chk "②all_seats _master 없음 → 무변경" "$(all_seats "$WITHOUT")" "M#1 M#2 N#0"
chk "②_master 문자열 아님 → 무변경" "$(stall_seats "{\"_master\": 7, \"M#1\": {$ROW}, \"M#2\": {\"role\": \"master\"}}")" "M#1 M#2"

# ③ retire 정상
S="$TMP/seats-a.json"; printf '%s' "{\"_master\": \"M#1\", \"_hil_route\": \"M#1\", \"_version\": \"x\", \"M#1\": {\"role\": \"master\", \"agent\": \"claude\", \"model\": \"m1\", \"tick\": \"ft-master-tick\"}}" > "$S"
out="$(bash "$RETIRE" 'M#1' 'M#2' --seats "$S")"; rc=$?
chk "③rc" "$rc" 0
chk "③RETIRED 줄(첫 줄 · 부팅 보고 retire= 계약 불변)" "${out%%$'\n'*}" "RETIRED M#1 -> M#2 file=$S keys=['_master', '_hil_route']"
chk "③구 행 _replaced_by·role·_retired_role·tick" "$(J "$S" '[.["M#1"]._replaced_by, .["M#1"].role, .["M#1"]._retired_role, (.["M#1"].tick|tostring)]|join(",")')" "M#2,stop-ready,master,null"
chk "③후계 행 생성(role·agent·model·tick·_replaces)" "$(J "$S" '.["M#2"]|[.role,.agent,.model,.tick,(._replaces|join("+"))]|join(",")')" "master,claude,m1,ft-master-tick,M#1"
chk "③_master·_hil_route → M#2" "$(J "$S" '[._master,._hil_route,._version]|join(",")')" "M#2,M#2,x"
chk "③백업 1개" "$(ls "$S".bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" 1

# ⑤ 두 번째 호출 NOOP (바이트 불변)
cp "$S" "$TMP/after1.json"
out="$(bash "$RETIRE" 'M#1' 'M#2' --seats "$S")"; rc=$?
chk "⑤NOOP rc" "$rc" 0
chk "⑤NOOP 출력" "${out%% *}" NOOP
chk "⑤바이트 불변" "$(cmp -s "$S" "$TMP/after1.json" && echo same || echo changed)" same

# ④ 후계 은퇴 → rc 3 · 바이트 그대로
S="$TMP/seats-b.json"; printf '%s' '{"_master": "M#1", "M#1": {"role": "master", "tick": "t"}, "M#2": {"role": "stop-ready", "tick": null, "_replaced_by": "M#9"}}' > "$S"; cp "$S" "$TMP/b.orig"
bash "$RETIRE" 'M#1' 'M#2' --seats "$S" > /dev/null; rc=$?
chk "④rc 3" "$rc" 3
chk "④파일 바이트 그대로" "$(cmp -s "$S" "$TMP/b.orig" && echo same || echo changed)" same
chk "④백업 0" "$(ls "$S".bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" 0

# ⑥ 명부 2개에 같은 키 → rc 1 · 쓰기 0 (루트 탐색: git 리포 scratch)
R="$TMP/repo"; mkdir -p "$R/.fable-team"; git -C "$R" init -q
printf '%s' '{"M#1": {"role": "master"}}' > "$R/.fable-team/seats.json"; printf '%s' '{"M#1": {"role": "master"}}' > "$R/.fable-team/seats-x.json"
(cd "$R" && env -u FT_SEATS_JSON bash "$RETIRE" 'M#1' 'M#2' > "$TMP/six.out"); rc=$?
chk "⑥rc 1" "$rc" 1
chk "⑥쓰기 0(백업·후계 행 없음)" "$(ls "$R/.fable-team" | grep -c bak; jq 'has("M#2")' "$R/.fable-team/seats.json")" $'0\nfalse'
rm "$R/.fable-team/seats-x.json"
(cd "$R" && env -u FT_SEATS_JSON bash "$RETIRE" 'M#1' 'M#2' > /dev/null); rc=$?
chk "⑥b 후보 1개 → 자동 선택 rc 0" "$rc" 0
chk "⑥b 구 행 은퇴" "$(J "$R/.fable-team/seats.json" '.["M#1"]._replaced_by')" "M#2"

# ⑦ role-spawn 옛 행 닫기 — 스크립트의 두 번째 python 블록만 추출해 임시 명부에 돌린다(tmux 0)
sed -n '/^python3 - "\$SEATS" "\$NAME"/,/^PY$/p' "$SPAWN" | sed '1d;$d' > "$TMP/spawn_block.py"
chk "⑦블록 추출(비어 있지 않음)" "$([ -s "$TMP/spawn_block.py" ] && echo yes || echo no)" yes
S="$TMP/seats-c.json"; printf '%s' '{"_master": "B#1", "_hil_route": "B#1", "B#1": {"role": "master", "agent": "claude", "tick": "ft-master-tick"}, "B#0": {"role": "master", "_replaced_by": "B#1", "tick": null}}' > "$S"
N_BLOCK="$(sed -n "s/^python3 - \(.*\) <<'PY'\$/\1/p" "$SPAWN" | grep -o '"\$[A-Z_]*"' | wc -l | tr -d ' ')"
BLOCK_ARGS=("$S" 'B#2' master claude m2 design/inbox/master B B "" "" "")  # SEATS NAME ROLE AGENT MODEL INBOX NEW_BASE OLD_BASE RAISE RAISE_CARD FROM
chk "⑦블록 인자 수 = 시험 인자 수 (스크립트 호출 줄 기준)" "$N_BLOCK" "${#BLOCK_ARGS[@]}"
python3 "$TMP/spawn_block.py" "${BLOCK_ARGS[@]}"
chk "⑦옛 행 B#1 닫힘" "$(J "$S" '.["B#1"]|[._replaced_by,.role,._retired_role,(.tick|tostring)]|join(",")')" "B#2,stop-ready,master,null"
chk "⑦_master·_hil_route → B#2" "$(J "$S" '[._master,._hil_route]|join(",")')" "B#2,B#2"
chk "⑦새 행 tick 상속·_replaces" "$(J "$S" '.["B#2"]|[.tick,(._replaces|join("+"))]|join(",")')" "ft-master-tick,B#1"
chk "⑦이미 닫힌 B#0 불변" "$(J "$S" '.["B#0"]|[._replaced_by,.role]|join(",")')" "B#1,master"

# ⑨ 재개 기록 (판정 1344) — 가짜 tmux/pgrep(PATH 앞 스텁) · 임시 HOME 의 세션 파일·jsonl 픽스처 · 실 tmux 0
FK="$TMP/fake"; mkdir -p "$FK"
cat > "$FK/tmux" <<'EOF'
#!/usr/bin/env bash
[ "$1" = display ] && [ -n "${FAKE_PANE_PID:-}" ] && { echo "$FAKE_PANE_PID"; exit 0; }
exit 1
EOF
cat > "$FK/pgrep" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-P" ] && { for p in ${FAKE_CHILDREN:-}; do echo "$p"; done; exit 0; }
exit 1
EOF
chmod +x "$FK/tmux" "$FK/pgrep"
UU1=11111111-2222-3333-4444-555555555555; UU2=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee; WORK="$TMP/work"; mkdir -p "$WORK"
ENC="$(printf '%s' "$WORK" | sed 's/[^A-Za-z0-9]/-/g')"
rs_home() { # <case> → 정상 픽스처 HOME (자식 pid 7001 의 세션 파일 · UU2 = 같은 좌석의 다른 대화, mtime 더 최신)
  local h="$TMP/h-$1"; mkdir -p "$h/.claude/sessions" "$h/.claude/projects/$ENC"
  printf '{"pid":7001,"sessionId":"%s","cwd":"%s","name":"M#1"}' "$UU1" "$WORK" > "$h/.claude/sessions/7001.json"
  : > "$h/.claude/projects/$ENC/$UU1.jsonl"; : > "$h/.claude/projects/$ENC/$UU2.jsonl"; touch -t 203001010000 "$h/.claude/projects/$ENC/$UU2.jsonl"
  echo "$h"
}
rs_seats() { printf '{"M#1": {"role": "master", "agent": "claude", %s "tick": "t"}}' "${2-\"model\": \"m1\",}" > "$1"; } # <파일> [model 조각]
rs_run() { HOME="$1" PATH="$FK:$PATH" FAKE_PANE_PID="${FAKE_PANE_PID-100}" FAKE_CHILDREN="${FAKE_CHILDREN-7000 7001}" bash "$RETIRE" 'M#1' 'M#2' --seats "$2"; }
H="$(rs_home ok)"; S="$TMP/seats-r.json"; rs_seats "$S"; out="$(rs_run "$H" "$S")"; rc=$?; REC="$H/.claude/state/seat-resume/M#1.json"
chk "⑨정상 rc" "$rc" 0
chk "⑨RETIRED 첫 줄 불변" "${out%%$'\n'*}" "RETIRED M#1 -> M#2 file=$S keys=[]"
chk "⑨둘째 줄 = RESUME ok <기록 경로>" "$(sed -n 2p <<< "$out")" "RESUME ok $REC"
chk "⑨기록 파일 9칸" "$(jq 'keys|length' "$REC" 2>/dev/null)" 9
chk "⑨uuid = 세션 파일 sessionId (더 최신 다른 jsonl 무시)" "$(jq -r '[.uuid,.jsonl]|join(",")' "$REC" 2>/dev/null)" "$UU1,$H/.claude/projects/$ENC/$UU1.jsonl"
chk "⑨name·engine·pid·cwd·model·retired_by" "$(jq -r '[.name,.engine,(.pid|tostring),.cwd,.model,.retired_by]|join(",")' "$REC" 2>/dev/null)" "M#1,claude,7001,$WORK,m1,M#2"
chk "⑨명부 구 행 _resume_uuid" "$(J "$S" '.["M#1"]._resume_uuid')" "$UU1"
rs_norecord() { # <라벨> <home> <seats 인자 2 (선택)> — 은퇴는 되고 기록 0 · NORECORD 줄 (DA② H3)
  local s="$TMP/seats-$1.json"; rs_seats "$s" ${3+"$3"}; local o; o="$(rs_run "$2" "$s")"; local r=$?
  chk "⑨$1 rc 0(은퇴 결과와 분리)" "$r" 0
  chk "⑨$1 RETIRED 첫 줄" "${o%%' '*}" RETIRED
  chk "⑨$1 NORECORD 둘째 줄" "$(sed -n 2p <<< "$o" | cut -d' ' -f1-2)" "NORECORD M#1"
  chk "⑨$1 기록 파일 0" "$([ -e "$2/.claude/state/seat-resume/M#1.json" ] && echo yes || echo no)" no
  chk "⑨$1 명부 은퇴됨" "$(J "$s" '.["M#1"]._replaced_by')" "M#2"
}
H="$(rs_home nosess)"; rm "$H/.claude/sessions/7001.json"; rs_norecord 세션파일없음 "$H"
H="$(rs_home two)"; printf '{"pid":7002,"sessionId":"%s","cwd":"%s","name":"M#1"}' "$UU2" "$WORK" > "$H/.claude/sessions/7002.json"; FAKE_CHILDREN="7001 7002" rs_norecord 세션파일2개 "$H"
H="$(rs_home name)"; printf '{"pid":7001,"sessionId":"%s","cwd":"%s","name":"X#9"}' "$UU1" "$WORK" > "$H/.claude/sessions/7001.json"; rs_norecord 이름불일치 "$H"
H="$(rs_home pid)"; printf '{"pid":9999,"sessionId":"%s","cwd":"%s","name":"M#1"}' "$UU1" "$WORK" > "$H/.claude/sessions/7001.json"; rs_norecord pid불일치 "$H"
H="$(rs_home nojsonl)"; rm "$H/.claude/projects/$ENC/$UU1.jsonl"; rs_norecord jsonl없음 "$H"
H="$(rs_home nomodel)"; rs_norecord model없음 "$H" ''
H="$(rs_home notmux)"; FAKE_PANE_PID="" rs_norecord tmux세션없음 "$H"
# ⑨-H1 (DA⑥) — 옛 재개 기록이 있는 좌석이 이번엔 NORECORD → 옛 기록을 지우지 않고 stale 로 이름 바꿔 닫기 근거에서 뺀다
H="$(rs_home stale)"; rm "$H/.claude/sessions/7001.json"; RD="$H/.claude/state/seat-resume"; mkdir -p "$RD"
printf '{"name":"M#1","engine":"claude","uuid":"%s"}' "$UU2" > "$RD/M#1.json"
S="$TMP/seats-stale.json"; printf '{"M#1": {"role": "master", "agent": "claude", "model": "m1", "tick": "t", "_resume_uuid": "%s"}}' "$UU2" > "$S"
out="$(rs_run "$H" "$S")"; rc=$?
chk "⑨H1 rc 0" "$rc" 0
chk "⑨H1 둘째 줄 = NORECORD … · 이전 기록 무효화 <새 경로>" "$(sed -n 2p <<< "$out" | sed -E 's/^(NORECORD M#1 .* · 이전 기록 무효화 ).*(M#1\.json\.stale-[0-9]{14})$/\1\2/' | sed "s|$RD/||")" "$(sed -n 2p <<< "$out" | sed -E 's/ · 이전 기록 무효화 .*//') · 이전 기록 무효화 M#1.json.stale-$(ls "$RD" | sed -n 's/^M#1\.json\.stale-//p')"
chk "⑨H1 <구>.json 0 · stale 1" "$([ -e "$RD/M#1.json" ] && echo yes || echo no) $(ls "$RD" | grep -c '^M#1\.json\.stale-[0-9]\{14\}$')" "no 1"
chk "⑨H1 stale 내용 보존(uuid)" "$(jq -r .uuid "$RD"/M#1.json.stale-* 2>/dev/null)" "$UU2"
chk "⑨H1 명부 구 행 _resume_uuid 제거" "$(J "$S" '.["M#1"]|has("_resume_uuid")')" false

# ⑩ --record-only (R110 · 판정 1380) — 이미 은퇴한 «살아 있는» 옛 좌석에 재개 기록만 쓴다 · 명부 쓰기 0
rr_seats() { # <파일> [model 조각] [agent] [retired_by]  → 은퇴된 행(_replaced_by 있음)
  printf '{"M#1": {"role": "stop-ready", "agent": "%s", %s "tick": null, "_replaced_by": "%s", "_retired_role": "master"}}' "${3:-claude}" "${2-\"model\": \"m1\",}" "${4:-M#7}" > "$1"; }
rr_run() { HOME="$1" PATH="$FK:$PATH" FAKE_PANE_PID="${FAKE_PANE_PID-100}" FAKE_CHILDREN="${FAKE_CHILDREN-7000 7001}" bash "$RETIRE" 'M#1' --record-only --seats "$2"; }
H="$(rs_home rr)"; S="$TMP/seats-rr.json"; rr_seats "$S"; cp "$S" "$S.orig"; out="$(rr_run "$H" "$S")"; rc=$?; REC="$H/.claude/state/seat-resume/M#1.json"
chk "⑩ⓐ rc 0" "$rc" 0
chk "⑩ⓐ 출력 = RESUME ok <기록 경로> 한 줄(RETIRED 줄 없음)" "$out" "RESUME ok $REC"
chk "⑩ⓐ 기록 키 9개" "$(jq 'keys|sort|join(",")' "$REC" 2>/dev/null)" '"at,cwd,engine,jsonl,model,name,pid,retired_by,uuid"'
chk "⑩ⓐ uuid·name·engine·pid·model" "$(jq -r '[.uuid,.name,.engine,(.pid|tostring),.model]|join(",")' "$REC" 2>/dev/null)" "$UU1,M#1,claude,7001,m1"
chk "⑩ⓐ retired_by = 명부 _replaced_by(M#7)" "$(jq -r .retired_by "$REC" 2>/dev/null)" "M#7"
chk "⑩ⓑ 명부 바이트 불변" "$(cmp -s "$S" "$S.orig" && echo same || echo changed)" same
chk "⑩ⓑ .bak-retire-* 0" "$(ls "$S".bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" 0
# ⓒ 현역 행(_replaced_by 없음) → REJECT rc 1 · 기록 0 · 명부 불변
H="$(rs_home rrlive)"; S="$TMP/seats-rrlive.json"; rs_seats "$S"; cp "$S" "$S.orig"; out="$(rr_run "$H" "$S")"; rc=$?
chk "⑩ⓒ rc 1" "$rc" 1
chk "⑩ⓒ 출력 REJECT" "${out%% *}" REJECT
chk "⑩ⓒ 기록 파일 0" "$([ -e "$H/.claude/state/seat-resume/M#1.json" ] && echo yes || echo no)" no
chk "⑩ⓒ 명부 바이트 불변" "$(cmp -s "$S" "$S.orig" && echo same || echo changed)" same
# ⓓ 검증 실패 → NORECORD rc 0 · 기록 0 · 명부 불변
rr_norecord() { # <라벨> <home> [model 조각] [agent]
  local s="$TMP/seats-rr-$1.json" o r; if [ $# -ge 3 ]; then rr_seats "$s" "$3" "${4:-claude}"; else rr_seats "$s"; fi; cp "$s" "$s.orig"; o="$(rr_run "$2" "$s")"; r=$?
  chk "⑩ⓓ$1 rc 0" "$r" 0
  chk "⑩ⓓ$1 첫 줄 NORECORD M#1" "$(sed -n 1p <<< "$o" | cut -d' ' -f1-2)" "NORECORD M#1"
  chk "⑩ⓓ$1 기록 파일 0" "$([ -e "$2/.claude/state/seat-resume/M#1.json" ] && echo yes || echo no)" no
  chk "⑩ⓓ$1 명부 바이트 불변·bak 0" "$(cmp -s "$s" "$s.orig" && echo same || echo changed) $(ls "$s".bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" "same 0"
}
H="$(rs_home rrn1)"; rm "$H/.claude/sessions/7001.json"; rr_norecord 세션파일없음 "$H"
H="$(rs_home rrn2)"; printf '{"pid":7002,"sessionId":"%s","cwd":"%s","name":"M#1"}' "$UU2" "$WORK" > "$H/.claude/sessions/7002.json"; FAKE_CHILDREN="7001 7002" rr_norecord 세션파일2개 "$H"
H="$(rs_home rrn3)"; printf '{"pid":7001,"sessionId":"%s","cwd":"%s","name":"X#9"}' "$UU1" "$WORK" > "$H/.claude/sessions/7001.json"; rr_norecord 이름불일치 "$H"
H="$(rs_home rrn4)"; printf '{"pid":9999,"sessionId":"%s","cwd":"%s","name":"M#1"}' "$UU1" "$WORK" > "$H/.claude/sessions/7001.json"; rr_norecord pid불일치 "$H"
H="$(rs_home rrn5)"; rm "$H/.claude/projects/$ENC/$UU1.jsonl"; rr_norecord jsonl없음 "$H"
H="$(rs_home rrn6)"; rr_norecord model없음 "$H" ''
H="$(rs_home rrn7)"; FAKE_PANE_PID="" rr_norecord tmux세션없음 "$H"
H="$(rs_home rrn8)"; rm "$H/.claude/sessions/7001.json"; rr_norecord codex좌석 "$H" '"model": "gpt-6.1-sol",' codex
# ⓓ 이미 있던 <구>.json → .stale-<ts> 이름 바꿈(명부는 그대로)
H="$(rs_home rrstale)"; rm "$H/.claude/sessions/7001.json"; RD="$H/.claude/state/seat-resume"; mkdir -p "$RD"; printf '{"name":"M#1","uuid":"%s"}' "$UU2" > "$RD/M#1.json"
S="$TMP/seats-rrstale.json"; rr_seats "$S"; cp "$S" "$S.orig"; out="$(rr_run "$H" "$S")"; rc=$?
chk "⑩ⓓstale rc 0·NORECORD" "$rc $(cut -d' ' -f1-2 <<< "$out")" "0 NORECORD M#1"
chk "⑩ⓓstale <구>.json 0 · stale 1" "$([ -e "$RD/M#1.json" ] && echo yes || echo no) $(ls "$RD" | grep -c '^M#1\.json\.stale-[0-9]\{14\}$')" "no 1"
chk "⑩ⓓstale 명부 불변" "$(cmp -s "$S" "$S.orig" && echo same || echo changed)" same
# ⓕ --record-only + <후계> → usage rc 2 · 쓰기 0
H="$(rs_home rrf)"; S="$TMP/seats-rrf.json"; rr_seats "$S"; cp "$S" "$S.orig"
for a in "M#1 M#2 --record-only" "M#1 --record-only M#2"; do
  out="$(HOME="$H" PATH="$FK:$PATH" FAKE_PANE_PID=100 FAKE_CHILDREN="7000 7001" bash "$RETIRE" $a --seats "$S" 2>&1)"; rc=$?
  chk "⑩ⓕ [$a] rc 2" "$rc" 2
done
chk "⑩ⓕ 기록 0 · 명부 불변" "$([ -e "$H/.claude/state/seat-resume/M#1.json" ] && echo yes || echo no) $(cmp -s "$S" "$S.orig" && echo same || echo changed)" "no same"

# ⑧ 기존 시험
for t in test_ft_tick_master_seat.sh test_role_spawn_name.sh test_kit_bin_sync.sh; do
  bash "$HERE/$t" > "$TMP/$t.out" 2>&1; chk "⑧$t rc=0" "$?" 0
done

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
