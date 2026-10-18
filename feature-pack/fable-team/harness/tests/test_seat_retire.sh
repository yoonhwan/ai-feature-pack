#!/usr/bin/env bash
# test_seat_retire.sh — R43: 틱 정지 감시는 _master 아닌 옛 role=master 행을 건너뛴다 · ft-seat-retire.sh · ft-role-spawn.sh 옛 행 닫기.
# 모든 쓰기는 mktemp scratch 안 — 라이브 좌석표·stamp·tmux 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
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
[ "$1" = display ] && [ -n "${FAKE_PANE_PID:-}" ] && { n="${4#=}"; n="${n%:}"; printf '%s\t%s:@1.%%1\n' "$FAKE_PANE_PID" "$n"; exit 0; }   # R364: pane pid + 식별(<세션>:@window.%pane)
[ "$1" = has-session ] && { for a in ${FAKE_ALIVE:-}; do [ "=$a" = "$3" ] && exit 0; done; exit 1; }
exit 1
EOF
cat > "$FK/pgrep" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-P" ] && { for p in ${FAKE_CHILDREN:-}; do echo "$p"; done; exit 0; }
exit 1
EOF
cat > "$FK/ps" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = -o ]; then   # R364: 결속 판정기가 lstart·comm 을 묻는다 — 고정 값(옛 시각 · claude)
  case "$2" in lstart=) echo "Mon Jan  1 00:00:00 2001"; exit 0;; comm=) echo /u/.local/bin/claude; exit 0;; esac
  [ -n "${FAKE_ARGV:-}" ] && { echo "$FAKE_ARGV"; exit 0; }
fi
exit 1
EOF
chmod +x "$FK/tmux" "$FK/pgrep" "$FK/ps"
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
chk "⑨기록 파일 10칸(9 + binding · R364)" "$(jq 'keys|length' "$REC" 2>/dev/null)" 10
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
chk "⑩ⓐ 기록 키 10개(9 + binding · R364)" "$(jq 'keys|sort|join(",")' "$REC" 2>/dev/null)" '"at,binding,cwd,engine,jsonl,model,name,pid,retired_by,uuid"'
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

# ⑪ R282 ① jsonl model — 명부 model 없음 + jsonl 마지막 assistant model → 기록 model = jsonl 값 · 명부와 다르면 둘 다 + 출력 표시
jl() { printf '%s\n' '{"type":"assistant","message":{"model":"old-model"}}' '{"type":"user","message":{"content":"x"}}' '{"type":"assistant","message":{"model":"<synthetic>"}}' '{"type":"assistant","message":{"model":"'"$2"'"}}' '{"type":"system"}' > "$1/.claude/projects/$ENC/$UU1.jsonl"; }
H="$(rs_home jm1)"; jl "$H" real-model; S="$TMP/seats-jm1.json"; rs_seats "$S" ''; out="$(rs_run "$H" "$S")"; REC="$H/.claude/state/seat-resume/M#1.json"
chk "⑪명부 model 없음 + jsonl → RESUME ok(불일치 표시 없음)" "$(sed -n 2p <<< "$out")" "RESUME ok $REC"
chk "⑪기록 model = jsonl 마지막 assistant(synthetic 제외) · roster_model 없음" "$(jq -r '[.model,(has("roster_model")|tostring)]|join(",")' "$REC")" "real-model,false"
H="$(rs_home jm2)"; jl "$H" real-model; S="$TMP/seats-jm2.json"; rs_seats "$S"; out="$(rs_run "$H" "$S")"; REC="$H/.claude/state/seat-resume/M#1.json"
chk "⑪명부 m1 ≠ jsonl → 둘째 줄 끝 표시" "$(sed -n 2p <<< "$out")" "RESUME ok $REC (명부 model 다름: m1)"
chk "⑪기록 model=jsonl · roster_model=명부" "$(jq -r '[.model,.roster_model]|join(",")' "$REC")" "real-model,m1"
H="$(rs_home jm3)"; jl "$H" m1; S="$TMP/seats-jm3.json"; rs_seats "$S"; out="$(rs_run "$H" "$S")"
chk "⑪jsonl = 명부 → 표시 0 · roster_model 0" "$(sed -n 2p <<< "$out" | grep -c '명부 model 다름') $(jq 'has("roster_model")' "$H/.claude/state/seat-resume/M#1.json")" "0 false"
H="$(rs_home jm4)"; S="$TMP/seats-jm4.json"; rs_seats "$S" ''; out="$(rs_run "$H" "$S")"
chk "⑪jsonl·명부 둘 다 없음 → NORECORD(model 못 읽음) · 기록 0" "$(sed -n 2p <<< "$out") $([ -e "$H/.claude/state/seat-resume/M#1.json" ] && echo yes || echo no)" "NORECORD M#1 model 못 읽음(jsonl·명부) no"

# ⑪-r2 model 접미사 정규화 — zombie-clean resume 이 --model 로 그대로 쓴다: [1m] 이 빠지면 200k 창 회귀
H="$(rs_home sfx1)"; jl "$H" claude-x; S="$TMP/seats-sfx1.json"; rs_seats "$S" '"model": "claude-x[1m]",'; out="$(rs_run "$H" "$S")"; REC="$H/.claude/state/seat-resume/M#1.json"
chk "⑪r2 명부 claude-x[1m] · jsonl claude-x(바탕 같음) → 기록 model 에 [1m] 유지 · roster_model 0 · 표시 0" "$(jq -r '[.model,(has("roster_model")|tostring)]|join(",")' "$REC") $(sed -n 2p <<< "$out" | grep -c '명부 model 다름')" "claude-x[1m],false 0"
H="$(rs_home sfx2)"; jl "$H" claude-x; S="$TMP/seats-sfx2.json"; rs_seats "$S" ''; FAKE_ARGV="claude --resume u --model claude-y[1m] --effort high" rs_run "$H" "$S" > /dev/null
chk "⑪r2 argv --model(명부 없음) → 기록 model = argv 값(접미사 포함)" "$(jq -r .model "$H/.claude/state/seat-resume/M#1.json")" "claude-y[1m]"
H="$(rs_home sfx3)"; jl "$H" claude-x; S="$TMP/seats-sfx3.json"; rs_seats "$S" '"model": "claude-x[1m]",'; out="$(FAKE_ARGV="claude --model=claude-z[1m]" rs_run "$H" "$S")"; REC="$H/.claude/state/seat-resume/M#1.json"
chk "⑪r2 argv(--model=) 가 명부·jsonl 보다 먼저 · 명부와 바탕 다르면 roster_model + 표시" "$(jq -r '[.model,.roster_model]|join(",")' "$REC") $(sed -n 2p <<< "$out" | grep -c '명부 model 다름: claude-x\[1m\]')" "claude-z[1m],claude-x[1m] 1"

# ⑫ R282 ③ 후계 행 model — 도달 파일 model → 후계 행 · 없으면 옛 값
AD="$TMP/arrive"; mkdir -p "$AD"; printf '{"successor":"M#2","seq":1,"reached_at":"t","rc":0,"model":"arrived-model"}' > "$AD/M#1.json"
H="$(rs_home ad1)"; S="$TMP/seats-ad1.json"; rs_seats "$S"; FT_SUCCESSOR_DIR="$AD" rs_run "$H" "$S" > /dev/null
chk "⑫도달 파일 model → 후계 행 model" "$(J "$S" '.["M#2"].model')" arrived-model
H="$(rs_home ad2)"; S="$TMP/seats-ad2.json"; rs_seats "$S"; FT_SUCCESSOR_DIR="$TMP/noarrive" rs_run "$H" "$S" > /dev/null
chk "⑫도달 파일 없음 → 옛 행 값(m1)" "$(J "$S" '.["M#2"].model')" m1
H="$(rs_home ad3)"; jl "$H" jm-only; S="$TMP/seats-ad3.json"; rs_seats "$S" ''; FT_SUCCESSOR_DIR="$TMP/noarrive" rs_run "$H" "$S" > /dev/null
chk "⑫도달 파일·명부 둘 다 없음 → jsonl 값" "$(J "$S" '.["M#2"].model')" jm-only

# ⑬ R282 ② 옛 행 없음 → 팀 명부 은퇴 행 생성 (scratch 리포 · 가짜 tmux/pgrep · 임시 HOME)
SEATS_ROOM='{"_master": "byz-room-master-claude#1", "_hil_route": "P#1"}'
rr_repo() { # <라벨> <seats-room.json 내용> → scratch 리포 경로
  local r="$TMP/rp-$1"; mkdir -p "$r/.fable-team"; git -C "$r" init -q; [ -n "$2" ] && printf '%s' "$2" > "$r/.fable-team/seats-room.json"; echo "$r"; }
ro_run() { # <repo> <home> <old> <new> [args…] — 이름 byz-room-master-claude#N 용 세션 파일(name 일치) 필요
  local r="$1" h="$2" o="$3" n="$4"; shift 4; local na=(); [ -n "$n" ] && na=("$n")   # <후계> '' = --record-only 호출
  (cd "$r" && HOME="$h" PATH="$FK:$PATH" FAKE_PANE_PID=100 FAKE_CHILDREN="${FAKE_CHILDREN-7000 7001}" FAKE_ALIVE="${FAKE_ALIVE-}" env -u FT_SEATS_JSON bash "$RETIRE" "$o" ${na[@]+"${na[@]}"} "$@"); }
RN='byz-room-master-claude#1'; RN2='byz-room-master-claude#2'
rm_home() { local h; h="$(rs_home "$1")"; printf '{"pid":7001,"sessionId":"%s","cwd":"%s","name":"%s"}' "$UU1" "$WORK" "$RN" > "$h/.claude/sessions/7001.json"; jl "$h" real-model; echo "$h"; }
R="$(rr_repo a "$SEATS_ROOM")"; H="$(rm_home ra)"; out="$(ro_run "$R" "$H" "$RN" "$RN2")"; rc=$?; F="$R/.fable-team/seats-room.json"
chk "⑬행 없음+팀 명부 → rc 0 RETIRED" "$rc ${out%% *}" "0 RETIRED"
chk "⑬은퇴 행 생성(role·agent·model·_created_by·_replaced_by·_retired_role)" "$(J "$F" ".[\"$RN\"]|[.role,.agent,.model,._created_by,._replaced_by,._retired_role]|join(\",\")")" "stop-ready,claude,real-model,retire,$RN2,master"
chk "⑬_master → 후계 · 후계 행 model=옛 값" "$(J "$F" "[._master,.[\"$RN2\"].model]|join(\",\")")" "$RN2,real-model"
chk "⑬.bak 1개 · 재개 기록 RESUME ok" "$(ls "$F".bak-retire-* | wc -l | tr -d ' ') $(sed -n 2p <<< "$out" | cut -d' ' -f1-2)" "1 RESUME ok"
R="$(rr_repo b "")"; H="$(rm_home rb)"; out="$(ro_run "$R" "$H" "$RN" "$RN2")"; rc=$?
chk "⑬팀 명부 없음 → REJECT rc 1 · 파일 생성 0" "$rc ${out%% *} $(ls "$R/.fable-team" | wc -l | tr -d ' ')" "1 REJECT 0"
R="$(rr_repo c "$SEATS_ROOM")"; H="$(rm_home rc)"; out="$(ro_run "$R" "$H" 'M#1' 'M#2')"; rc=$?
chk "⑬이름 lint 실패 → REJECT rc 1 · 명부 불변" "$rc ${out%% *} $(cmp -s "$R/.fable-team/seats-room.json" <(printf '%s' "$SEATS_ROOM") && echo same || echo changed)" "1 REJECT same"
R="$(rr_repo d "$SEATS_ROOM")"; printf '{"_master": "%s"}' "$RN" > "$R/.fable-team/seats-other.json"; H="$(rm_home rd)"; out="$(ro_run "$R" "$H" "$RN" "$RN2")"; rc=$?
chk "⑬옛 이름이 다른 명부에서 현역(_master) → REJECT rc 1 · 행 생성 0" "$rc ${out%% *} $(jq -r 'has("'"$RN"'")' "$R/.fable-team/seats-room.json") $(ls "$R/.fable-team"/*.bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" "1 REJECT false 0"

# ⑭ R296 ④ --record-only + 행 없음 — ⓐ 현역 아님 ⓑ 더 큰 번호 현역 ⓒ 그 세션 생존
SEATS_R2="{\"_master\": \"$RN2\"}"
R="$(rr_repo e "$SEATS_R2")"; H="$(rm_home re)"; F="$R/.fable-team/seats-room.json"; cp "$F" "$F.orig"; FAKE_ALIVE="$RN2" out="$(ro_run "$R" "$H" "$RN" '' --record-only)"; rc=$?; REC="$H/.claude/state/seat-resume/$RN.json"
chk "⑭ⓐⓑⓒ 참 → rc 0 · 출력 RESUME ok 한 줄" "$rc $out" "0 RESUME ok $REC"
chk "⑭retired_by = 명부 _master 현역 · model=jsonl" "$(jq -r '[.retired_by,.model]|join(",")' "$REC")" "$RN2,real-model"
chk "⑭명부 바이트 불변 · .bak 0" "$(cmp -s "$F" "$F.orig" && echo same || echo changed) $(ls "$R/.fable-team"/*.bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" "same 0"
R="$(rr_repo f "{\"_master\": \"$RN\"}")"; H="$(rm_home rf)"; FAKE_ALIVE="$RN" out="$(ro_run "$R" "$H" "$RN" '' --record-only)"; rc=$?
chk "⑭옛 이름이 _master 현역 → REJECT rc 1 · 기록 0" "$rc ${out%% *} $([ -e "$H/.claude/state/seat-resume/$RN.json" ] && echo yes || echo no)" "1 REJECT no"
R="$(rr_repo g '{"_master": "byz-room-master-claude#1x", "_hil_route": "P#9"}')"; H="$(rm_home rg)"; FAKE_ALIVE="$RN2" out="$(ro_run "$R" "$H" "$RN" '' --record-only)"; rc=$?
chk "⑭더 큰 번호 현역 없음 → REJECT rc 1 · 기록 0" "$rc ${out%% *} $([ -e "$H/.claude/state/seat-resume/$RN.json" ] && echo yes || echo no)" "1 REJECT no"
R="$(rr_repo h "$SEATS_R2")"; H="$(rm_home rh)"; FAKE_ALIVE="" out="$(ro_run "$R" "$H" "$RN" '' --record-only)"; rc=$?
chk "⑭현역 세션 죽음 → REJECT rc 1 · 기록 0" "$rc ${out%% *} $([ -e "$H/.claude/state/seat-resume/$RN.json" ] && echo yes || echo no)" "1 REJECT no"

# ⑮ R400 --record-only --verdict <번호> (판정 2304) — 승계 아닌 «판정에 의한 닫기»의 재개 기록 · 명부 쓰기 0
# ⓖ 현역 행(_replaced_by 없음 · _master 값) → RESUME ok · retired_by = verdict N · 명부 바이트 불변 · .bak 0
H="$(rs_home vg)"; S="$TMP/seats-vg.json"; printf '{"_master": "M#1", "M#1": {"role": "master", "agent": "claude", "model": "m1", "tick": "t"}}' > "$S"; cp "$S" "$S.orig"
out="$(HOME="$H" PATH="$FK:$PATH" FAKE_PANE_PID=100 FAKE_CHILDREN="7000 7001" bash "$RETIRE" 'M#1' --record-only --verdict 2304 --seats "$S")"; rc=$?; REC="$H/.claude/state/seat-resume/M#1.json"
chk "⑮ⓖ rc 0 · RESUME ok 한 줄" "$rc $out" "0 RESUME ok $REC"
chk "⑮ⓖ retired_by = verdict 2304 · model = 명부 · uuid" "$(jq -r '[.retired_by,.model,.uuid]|join(",")' "$REC")" "verdict 2304,m1,$UU1"
chk "⑮ⓖ 명부 바이트 불변 · .bak 0" "$(cmp -s "$S" "$S.orig" && echo same || echo changed) $(ls "$S".bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" "same 0"
# ⓗ 행 없음(다른 리포 좌석) + 결속 ok → R296 ⓑⓒ 없이 RESUME ok · model = jsonl · 명부 쓰기 0
R="$(rr_repo vh '{"_master": "byz-room-master-claude#9x"}')"; H="$(rm_home vh)"; F="$R/.fable-team/seats-room.json"; cp "$F" "$F.orig"
FAKE_ALIVE="" out="$(ro_run "$R" "$H" "$RN" '' --record-only --verdict 2304)"; rc=$?; REC="$H/.claude/state/seat-resume/$RN.json"
chk "⑮ⓗ rc 0 · RESUME ok(더 큰 번호 현역·생존 없이)" "$rc $out" "0 RESUME ok $REC"
chk "⑮ⓗ retired_by = verdict 2304 · model = jsonl" "$(jq -r '[.retired_by,.model]|join(",")' "$REC")" "verdict 2304,real-model"
chk "⑮ⓗ 명부 바이트 불변 · .bak 0" "$(cmp -s "$F" "$F.orig" && echo same || echo changed) $(ls "$R/.fable-team"/*.bak-retire-* 2>/dev/null | wc -l | tr -d ' ')" "same 0"
# ⓗ' 행 없음인데 `_*` 칸 값 → REJECT rc 1 · 기록 0 (R296 ⓐ 유지) · 결속 실패 → NORECORD rc 0
R="$(rr_repo vh2 "{\"_arch\": \"$RN\"}")"; H="$(rm_home vh2)"; out="$(ro_run "$R" "$H" "$RN" '' --record-only --verdict 2304)"; rc=$?
chk "⑮ⓗ' 행 없음 + _ 칸 값 → REJECT rc 1 · 기록 0" "$rc ${out%% *} $([ -e "$H/.claude/state/seat-resume/$RN.json" ] && echo yes || echo no)" "1 REJECT no"
H="$(rs_home vg2)"; rm "$H/.claude/sessions/7001.json"; S="$TMP/seats-vg2.json"; rs_seats "$S"
out="$(HOME="$H" PATH="$FK:$PATH" FAKE_PANE_PID=100 FAKE_CHILDREN="7000 7001" bash "$RETIRE" 'M#1' --record-only --verdict 2304 --seats "$S")"; rc=$?
chk "⑮ 결속 실패 → rc 0 · NORECORD · 기록 0" "$rc $(cut -d' ' -f1-2 <<< "$out") $([ -e "$H/.claude/state/seat-resume/M#1.json" ] && echo yes || echo no)" "0 NORECORD M#1 no"
# usage — --verdict 는 --record-only 와만 · 값 형식
for a in "M#1 M#2 --verdict 2304" "M#1 --record-only --verdict" "M#1 --record-only --verdict x"; do
  bash "$RETIRE" $a --seats "$S" > /dev/null 2>&1; chk "⑮usage [$a] rc 2" "$?" 2
done

# ⑧ 기존 시험
for t in test_ft_tick_master_seat.sh test_role_spawn_name.sh test_kit_bin_sync.sh; do
  bash "$HERE/$t" > "$TMP/$t.out" 2>&1; chk "⑧$t rc=0" "$?" 0
done

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
