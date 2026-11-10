#!/usr/bin/env bash
# test_seat_retire_keep.sh — r427: ft-seat-retire.sh 재개 기록 보존 — --keep-existing(기존 기록 있으면 새 시도 0) · 죽은 좌석 대화 기록 탐색 ·
#   ⓔ 새 기록 실패 때 옛 기록 보존(무효화 0) · 새 기록 성공 때만 옛 것을 .prev-<ts> 로. 모든 쓰기는 mktemp scratch — 가짜 tmux/pgrep/ps · 임시 HOME · 실 세션 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
RETIRE="$HERE/../../harness/bin/ft-seat-retire.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unset FT_SEATS_JSON ZC_RESUME_DIR
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }

FK="$TMP/fake"; mkdir -p "$FK"
cat > "$FK/tmux" <<'EOF'
#!/usr/bin/env bash
[ "$1" = display ] && [ -n "${FAKE_PANE_PID:-}" ] && { n="${4#=}"; n="${n%:}"; printf '%s\t%s:@1.%%1\n' "$FAKE_PANE_PID" "$n"; exit 0; }
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
[ "$1" = -o ] && case "$2" in lstart=) echo "Mon Jan  1 00:00:00 2001"; exit 0;; comm=) echo /u/.local/bin/claude; exit 0;; esac
exit 1
EOF
chmod +x "$FK/tmux" "$FK/pgrep" "$FK/ps"
UU1=11111111-2222-3333-4444-555555555555; UU2=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee; WORK="$TMP/work"; mkdir -p "$WORK"
ENC="$(printf '%s' "$WORK" | sed 's/[^A-Za-z0-9]/-/g')"
mkhome() { # <case> → HOME · 살아 있는 pane 결속용 세션 파일(7001 → UU1) · 대화 기록 폴더
  local h="$TMP/h-$1"; mkdir -p "$h/.claude/sessions" "$h/.claude/projects/$ENC" "$h/.claude/state/seat-resume"
  printf '{"pid":7001,"sessionId":"%s","cwd":"%s","name":"M#1"}' "$UU1" "$WORK" > "$h/.claude/sessions/7001.json"; : > "$h/.claude/projects/$ENC/$UU1.jsonl"
  echo "$h"
}
hist() { printf '{"display":"[발주 #1] recv M#1","project":"%s","sessionId":"%s"}\n' "$WORK" "$2" >> "$1/.claude/history.jsonl"; }   # <home> <uuid>
agent() { printf '{"type":"agent-name","agentName":"M#1","sessionId":"%s"}\n' "$2" >> "$1/.claude/projects/$ENC/$2.jsonl"; }   # <home> <uuid>
S="$TMP/seats.json"; printf '{"M#1": {"role": "arch", "agent": "claude", "model": "m1[1m]", "tick": "t"}}' > "$S"
rk() { HOME="$1" PATH="$FK:$PATH" FAKE_PANE_PID="${FAKE_PANE_PID-100}" FAKE_CHILDREN="7000 7001" FAKE_ALIVE="${FAKE_ALIVE-}" bash "$RETIRE" 'M#1' --record-only --verdict 2344 "${@:2}" --seats "$S"; }
files() { ls "$1/.claude/state/seat-resume" | xargs; }

bash -n "$RETIRE" && ok "bash -n ft-seat-retire.sh" || bad "bash -n"
# ① --keep-existing + 기존 기록 → RESUME kept · 새 시도 0(살아 있는 결속이 있어도) · 바이트 불변
H="$(mkhome k1)"; RD="$H/.claude/state/seat-resume"; printf '{"name":"M#1","uuid":"%s"}' "$UU2" > "$RD/M#1.json"; cp "$RD/M#1.json" "$TMP/k1.orig"
out="$(FAKE_ALIVE="M#1" rk "$H" --keep-existing)"; rc=$?
chk "①rc 0 · RESUME kept <경로>" "$rc $out" "0 RESUME kept $RD/M#1.json"
chk "①바이트 불변 · 파일 1" "$(cmp -s "$RD/M#1.json" "$TMP/k1.orig" && echo same || echo changed) $(files "$H")" "same M#1.json"
# ② 죽은 좌석 + 기록 없음 + agent-name 대화 기록 1개 → RESUME ok · 기록 칸(zombie-clean resume 이 읽는 uuid·jsonl·cwd·model·engine)
H="$(mkhome k2)"; hist "$H" "$UU2"; agent "$H" "$UU2"
out="$(FAKE_PANE_PID="" rk "$H" --keep-existing)"; rc=$?; REC="$H/.claude/state/seat-resume/M#1.json"
chk "②rc 0 · RESUME ok" "$rc $out" "0 RESUME ok $REC"
chk "②기록 칸" "$(jq -r '[.name,.engine,.uuid,.jsonl,.cwd,.model,.retired_by,.binding.source,(.pid|tostring)]|join(",")' "$REC")" "M#1,claude,$UU2,$H/.claude/projects/$ENC/$UU2.jsonl,$WORK,m1[1m],verdict 2344,dead-agent-name,null"
# ③ 대화 기록에 좌석 이름은 있지만 jsonl 에 agent-name 줄 0 (입력 글자만) → NORECORD 0개 · 파일 0
H="$(mkhome k3)"; hist "$H" "$UU2"; : > "$H/.claude/projects/$ENC/$UU2.jsonl"
out="$(FAKE_PANE_PID="" rk "$H" --keep-existing)"; rc=$?
chk "③rc 0 · NORECORD … 0개 · 파일 0" "$rc $out [$(files "$H")]" "0 NORECORD M#1 죽은 좌석 · agent-name 대화 기록 0개 []"
# ④ agent-name 대화 기록 2개 → NORECORD 2개(하나 고르기 0)
H="$(mkhome k4)"; for u in "$UU1" "$UU2"; do hist "$H" "$u"; agent "$H" "$u"; done
out="$(FAKE_PANE_PID="" rk "$H" --keep-existing)"; chk "④NORECORD 2개 · 파일 0" "$out [$(files "$H")]" "NORECORD M#1 죽은 좌석 · agent-name 대화 기록 2개 []"
# ⑤ --keep-existing 이어도 세션이 «살아 있으면» pane 결속 경로 그대로(대화 기록 탐색 0)
H="$(mkhome k5)"; out="$(FAKE_ALIVE="M#1" rk "$H" --keep-existing)"
chk "⑤살아 있는 좌석 → pane 결속(binding=tmux 칸 아님 legacy-name · pid 7001)" "$out $(jq -r '[.uuid,(.pid|tostring),.binding.source]|join(",")' "$H/.claude/state/seat-resume/M#1.json")" "RESUME ok $H/.claude/state/seat-resume/M#1.json $UU1,7001,legacy-name"
# ⑥ ⓔ 새 기록 실패(세션 파일 0) + 옛 기록 → NORECORD · 옛 기록 바이트 불변 · stale·prev 0 (--keep-existing 없이도)
H="$(mkhome k6)"; RD="$H/.claude/state/seat-resume"; rm "$H/.claude/sessions/7001.json"; printf '{"name":"M#1","uuid":"%s"}' "$UU2" > "$RD/M#1.json"; cp "$RD/M#1.json" "$TMP/k6.orig"
out="$(FAKE_ALIVE="M#1" rk "$H")"; rc=$?
chk "⑥rc 0 · NORECORD · 기존 기록 보존 안내" "$rc ${out%% *} ${out##* · }" "0 NORECORD 기존 기록 보존 $RD/M#1.json"
chk "⑥옛 기록 바이트 불변 · 파일 1" "$(cmp -s "$RD/M#1.json" "$TMP/k6.orig" && echo same || echo changed) $(files "$H")" "same M#1.json"
# ⑦ ⓔ 새 기록 성공 + 옛 기록 → 새 기록 · 옛 것은 .prev-<ts> (내용 보존)
H="$(mkhome k7)"; RD="$H/.claude/state/seat-resume"; printf '{"name":"M#1","uuid":"%s"}' "$UU2" > "$RD/M#1.json"
out="$(FAKE_ALIVE="M#1" rk "$H")"; rc=$?
chk "⑦rc 0 · RESUME ok · 이전 기록 <prev>" "$rc $(sed -E 's/\.prev-[0-9]{14}$/.prev-TS/' <<< "$out")" "0 RESUME ok $RD/M#1.json · 이전 기록 $RD/M#1.json.prev-TS"
chk "⑦새 uuid · prev 내용 = 옛 uuid" "$(jq -r .uuid "$RD/M#1.json") $(jq -r .uuid "$RD"/M#1.json.prev-*)" "$UU1 $UU2"
# ⑧ usage — --keep-existing 은 --record-only 와만
HOME="$TMP" bash "$RETIRE" 'M#1' 'M#2' --keep-existing --seats "$S" > /dev/null 2>&1; chk "⑧승계 경로 + --keep-existing rc 2" "$?" 2

echo "fail=$fail"; [ "$fail" = 0 ]
