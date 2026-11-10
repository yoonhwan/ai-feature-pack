#!/usr/bin/env bash
# test_zc_resume_headroom.sh — R524: zombie-clean resume·restore 가 claude 를 헤드룸 래퍼(claude-hr.sh)로 연다 + resume 뒤 env 확인 1줄.
# 가짜 tmux/pgrep/ps(PATH 앞 스텁) + 임시 HOME(가짜 래퍼) + 임시 재개 기록 — 실 claude·tmux·프록시 0 · GIT_* env 0.
#   ⓐ resume --dry-run `[dry] cmd=` = 래퍼 명령 ⓑ 실제 경로 send-keys -l = ⓐ 명령 ⓒ 래퍼 없음/비실행 = ❌ rc1 · 호출 0
#   ⓓ resume 뒤 env 확인: HEADROOM ok / WARN HEADROOM_BYPASS / WARN HEADROOM 확인 불가(7s) — kill 0 · rc0
#   ⓔ restore: argv 첫 낱말 claude(·…/claude) 만 래퍼로 · 래퍼·codex 등은 그대로
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ZC="${ZC_SCRIPT:-$HERE/../../harness/kit/zombie-clean/zombie-clean.sh}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }

bash -n "$ZC" && ok "bash -n zombie-clean.sh" || bad "bash -n zombie-clean.sh"

T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
F="$T/fake"; H="$T/home"; REC="$T/rec"; CALLS="$T/calls"; CWD="$T/cwd"
mkdir -p "$F" "$H/.headroom" "$H/.claude/logs" "$REC" "$CWD" "$T/proj"
HR="$H/.headroom/claude-hr.sh"
printf '#!/bin/bash\nexit 0\n' > "$HR"; chmod +x "$HR"

# 가짜 tmux — has-session 은 ALIVE 일 때만 0 · list-panes 는 pane pid 7000 · 그 밖 호출은 기록
cat > "$F/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) [ -n "${ALIVE:-}" ] && exit 0; exit 1 ;;
  list-panes) echo 7000 ;;
  *) echo "$*" >> "$CALLS" ;;
esac
exit 0
EOF
# 가짜 pgrep — pane 7000 의 자식 = FAKE_KID(비면 0건)
printf '#!/usr/bin/env bash\n[ "$1" = -P ] && [ "$2" = 7000 ] && [ -n "${FAKE_KID:-}" ] && { echo "$FAKE_KID"; exit 0; }\nexit 1\n' > "$F/pgrep"
# 가짜 ps — `-o comm= -p <pid>` = FAKE_COMM · `eww <pid>` = env 줄(FAKE_URL 있으면 ANTHROPIC_BASE_URL 포함)
cat > "$F/ps" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = -o ] && [ "$2" = comm= ]; then echo "${FAKE_COMM:-/x/.local/bin/claude}"; exit 0; fi
if [ "$1" = eww ]; then
  e="HOME=/x TERM=xterm"; [ -n "${FAKE_URL:-}" ] && e="$e ANTHROPIC_BASE_URL=$FAKE_URL"
  printf '  PID   TT  STAT      TIME COMMAND\n%s s001 S+ 0:00.10 /x/.local/bin/claude --resume u-1 %s\n' "$2" "$e"; exit 0
fi
exit 1
EOF
chmod +x "$F"/*

S="byz-t-master-claude#1"; M="claude-sonnet-5-5[1m]"
mkrec() {   # 검증 통과하는 재개 기록 1장
  printf '{}\n' > "$T/proj/u-1.jsonl"
  python3 - "$REC/$S.json" "$S" "$T/proj/u-1.jsonl" "$CWD" "$M" <<'PY'
import json, sys
f, name, jl, cwd, model = sys.argv[1:6]
json.dump({"name": name, "engine": "claude", "uuid": "u-1", "jsonl": jl, "cwd": cwd, "model": model}, open(f, "w"))
PY
}
ZCR() { : > "$CALLS"; env HOME="$H" PATH="$F:$PATH" CALLS="$CALLS" ZC_RESUME_DIR="$REC" "$@" 2>&1; }
WANT="$HR --dangerously-skip-permissions --resume u-1 --model '$M'"
mkrec

# ⓐ dry-run 출력 = 래퍼 명령
o="$(ZCR bash "$ZC" resume "$S" --dry-run)"; rc=$?
eq "$rc" 0 "ⓐ dry-run rc0"
has "$o" "[dry] cmd=$WANT" "ⓐ [dry] cmd= 래퍼 명령"
hasnt "$o" "] claude --resume" "ⓐ 날 claude 명령 0"
eq "$(wc -l < "$CALLS" | tr -d ' ')" 0 "ⓐ dry-run tmux 호출 0"

# ⓑ 실제 경로 — send-keys -l 문자열 = ⓐ 명령 · Enter 별도 · ⓓ HEADROOM ok
o="$(ZCR FAKE_KID=4242 FAKE_URL=http://127.0.0.1:8317 bash "$ZC" resume "$S")"; rc=$?
eq "$rc" 0 "ⓑ resume rc0"
eq "$(sed -n 1p "$CALLS")" "new-session -d -s $S -c $CWD" "ⓑ new-session cwd"
eq "$(sed -n 2p "$CALLS")" "send-keys -t =$S: -l $WANT" "ⓑ send-keys -l = 래퍼 명령"
eq "$(sed -n 3p "$CALLS")" "send-keys -t =$S: Enter" "ⓑ Enter 별도"
has "$o" "HEADROOM ok $S pid=4242 ANTHROPIC_BASE_URL=http://127.0.0.1:8317" "ⓓ 프록시 경유 = HEADROOM ok 줄"
hasnt "$o" "WARN" "ⓓ ok 일 때 WARN 0"

# ⓓ env 에 ANTHROPIC_BASE_URL 없음 → WARN HEADROOM_BYPASS · kill 0 · rc0
o="$(ZCR FAKE_KID=4242 bash "$ZC" resume "$S")"; rc=$?
eq "$rc" 0 "ⓓ 직결이어도 rc0(래퍼 fail-open)"
has "$o" "WARN HEADROOM_BYPASS $S pid=4242" "ⓓ 직결 = WARN HEADROOM_BYPASS 줄"
hasnt "$(cat "$CALLS")" "kill" "ⓓ kill 0"

# ⓓ 래퍼(bash) 단계 pid 는 본체로 세지 않는다 — 대기 상한 안에 claude 가 안 보이면 확인 불가
o="$(ZCR FAKE_KID=4242 FAKE_COMM=/bin/bash ZC_HR_WAIT_S=1 bash "$ZC" resume "$S")"; rc=$?
eq "$rc" 0 "ⓓ 래퍼 단계만 보임 rc0"
has "$o" "WARN HEADROOM 확인 불가(1s)" "ⓓ 래퍼(bash) pid 는 본체 아님 → 확인 불가"

# ⓓ pid 못 찾음(기본 7초) → WARN HEADROOM 확인 불가(7s)
o="$(ZCR bash "$ZC" resume "$S")"; rc=$?
eq "$rc" 0 "ⓓ pid 없음 rc0"
has "$o" "WARN HEADROOM 확인 불가(7s)" "ⓓ 7초 안에 pid 없음 = 확인 불가 줄"

# ⓒ 래퍼 없음 / 비실행 → ❌ rc1 · 세션 생성 0 · 직결 대체 0
chmod -x "$HR"
o="$(ZCR bash "$ZC" resume "$S")"; rc=$?
eq "$rc $(wc -l < "$CALLS" | tr -d ' ')" "1 0" "ⓒ 비실행 래퍼 rc1 · tmux 호출 0"
has "$o" "❌ 헤드룸 래퍼 없음: $HR" "ⓒ 비실행 래퍼 안내"
rm -f "$HR"
o="$(ZCR bash "$ZC" resume "$S")"; rc=$?
eq "$rc $(wc -l < "$CALLS" | tr -d ' ')" "1 0" "ⓒ 래퍼 없음 rc1 · tmux 호출 0"
has "$o" "❌ 헤드룸 래퍼 없음: $HR" "ⓒ 래퍼 없음 안내"
hasnt "$o" "✅" "ⓒ 성공 표기 0"
o="$(ZCR bash "$ZC" resume "$S" --dry-run)"; rc=$?
eq "$rc" 1 "ⓒ 래퍼 없음이면 dry-run 도 rc1"
o="$(ZCR ZC_CLAUDE_HR="$T/other-hr.sh" bash "$ZC" resume "$S")"; rc=$?
has "$o" "❌ 헤드룸 래퍼 없음: $T/other-hr.sh" "ⓒ 경로는 ZC_CLAUDE_HR 한 곳"
printf '#!/bin/bash\nexit 0\n' > "$HR"; chmod +x "$HR"

# ⓔ restore — 대장 argv 첫 낱말이 claude 면 그 낱말만 래퍼로
LED="$H/.claude/logs/zc-reclaim-test.tsv"
row() { printf 'ts\t%s\tx\tx\tx\t%s\trestore\t%s\n' "$1" "$CWD" "$2"; }
{ printf 'ts\tname\ta\tb\tc\tcwd\trestore\targv\n'
  row R1 "/x/.local/bin/claude --dangerously-skip-permissions --resume u9 --model m"
  row R2 "claude --resume u9"
  row R3 "$HR --resume u9"
  row R4 "codex --model gpt -c x"
  row R5 "claudex --a"
  row R6 "claude"; } > "$LED"
rs() { ZCR bash "$ZC" restore "$1" "$LED" --dry-run | sed -n 's/^\[dry\] argv=//p'; }
eq "$(rs R1)" "$HR --dangerously-skip-permissions --resume u9 --model m" "ⓔ …/claude → 래퍼(나머지 인자 그대로)"
eq "$(rs R2)" "$HR --resume u9" "ⓔ claude → 래퍼"
eq "$(rs R3)" "$HR --resume u9" "ⓔ 이미 래퍼면 그대로"
eq "$(rs R4)" "codex --model gpt -c x" "ⓔ codex argv 그대로"
eq "$(rs R5)" "claudex --a" "ⓔ claude 가 아닌 낱말(claudex) 그대로"
eq "$(rs R6)" "$HR" "ⓔ 인자 없는 claude → 래퍼"
o="$(ZCR bash "$ZC" restore R2 "$LED")"; rc=$?
eq "$rc" 0 "ⓔ restore 실제 rc0"
eq "$(sed -n 2p "$CALLS")" "send-keys -t =R2: -l $HR --resume u9" "ⓔ restore send-keys -l = 래퍼 argv"
rm -f "$HR"
o="$(ZCR bash "$ZC" restore R2 "$LED")"; rc=$?
eq "$rc $(wc -l < "$CALLS" | tr -d ' ')" "1 0" "ⓔ 래퍼 없음 + claude argv → rc1 · 호출 0"
has "$o" "❌ 헤드룸 래퍼 없음" "ⓔ 래퍼 없음 안내"
o="$(ZCR bash "$ZC" restore R4 "$LED" --dry-run)"; rc=$?
eq "$rc" 0 "ⓔ 래퍼 없어도 codex argv 는 그대로 복원"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
