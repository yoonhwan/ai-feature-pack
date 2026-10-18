#!/usr/bin/env bash
# test_distill_recv_gate.sh — context-distill-gate.sh hard 모드 «후계 도달 전 recv 차단» (R107).
# 셔뱅 /bin/bash(macOS 3.2) 로 훅을 실행한다(r6 사고: PATH bash5 시험은 3.2 파서 결함을 못 잡는다).
# transcript fixture 로 토큰 값을 주고, 가짜 tmux(PATH 앞)로 좌석명을 준다 — 실 세션·홈·명부 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOOK="$HERE/../../scripts/harness-install/fable-team/templates/hooks/context-distill-gate.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

/bin/bash -n "$HOOK" && ok "/bin/bash -n 훅" || bad "/bin/bash -n 훅"
[ "$(grep -c '`' "$HOOK")" = 0 ] && ok "훅 리터럴 백틱 0" || bad "훅 리터럴 백틱 $(grep -c '`' "$HOOK")"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; HOMED="$TMP/home"; SEAT="byz-t-old-claude#1"
mkdir -p "$REPO" "$FAKE" "$HOMED"; git -C "$REPO" init -q
STATE="$REPO/.fable-team/state/successor"
MBOX="$REPO/.fable-team/comm/mbox.sh"; SO="$REPO/.fable-team/bin/ft-successor-open.sh"
printf '#!/usr/bin/env bash\n[ "${TMUX_FAIL:-0}" = 1 ] && exit 1\ncase "$1" in display) echo "%s";; esac; exit 0\n' "$SEAT" > "$FAKE/tmux"; chmod +x "$FAKE/tmux"

transcript() { # transcript <토큰> → 마지막 실 usage 가 그 값인 jsonl
  printf '{"type":"assistant","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$1" > "$TMP/t.jsonl"
}
hook() { # hook <명령> [env KEY=VAL…] → rc 는 $RC, stderr 는 $TMP/err
  local cmd="$1"; shift
  local json; json="$(python3 -c 'import json,sys;print(json.dumps({"transcript_path":sys.argv[1],"cwd":sys.argv[2],"tool_name":"Bash","tool_input":{"command":sys.argv[3]}}))' "$TMP/t.jsonl" "$REPO" "$cmd")"
  printf '%s' "$json" | env HOME="$HOMED" PATH="$FAKE:$PATH" TMUX_PANE=%1 "$@" /bin/bash "$HOOK" hard --recv-gate-at 400000 --block-at 450000 >/dev/null 2>"$TMP/err"
  RC=$?
}
RECV="bash $MBOX recv $SEAT"; PEEK="bash $MBOX peek $SEAT"

transcript 410000; rm -rf "$STATE"; hook "$RECV"
{ [ "$RC" -eq 2 ] && grep -q 'R107' "$TMP/err"; } && ok "410k + recv + 도달 파일 없음 → exit 2 (R107 안내)" || bad "410k recv 파일 없음 rc=$RC err=$(cat "$TMP/err")"

mkdir -p "$STATE"; printf '{"successor":"x","seq":1,"reached_at":"t","rc":0}\n' > "$STATE/$SEAT.json"; hook "$RECV"
[ "$RC" -eq 0 ] && ok "410k + recv + 도달 파일 있음 → 0" || bad "410k recv 파일 있음 rc=$RC err=$(cat "$TMP/err")"

rm -rf "$STATE"; transcript 390000; hook "$RECV"
[ "$RC" -eq 0 ] && ok "390k + recv → 0" || bad "390k recv rc=$RC err=$(cat "$TMP/err")"

transcript 410000; hook "$PEEK"
[ "$RC" -eq 0 ] && ok "410k + peek → 0" || bad "410k peek rc=$RC err=$(cat "$TMP/err")"

rm -f "$HOMED/.claude/logs/context-distill-gate.log"; hook "$RECV" TMUX_PANE=
{ [ "$RC" -eq 0 ] && grep -q 'recv-gate' "$HOMED/.claude/logs/context-distill-gate.log"; } \
  && ok "TMUX_PANE 없음 → 0 + 로그 1줄" || bad "TMUX_PANE 없음 rc=$RC log=$(cat "$HOMED/.claude/logs/context-distill-gate.log" 2>&1)"

rm -f "$HOMED/.claude/logs/context-distill-gate.log"; hook "$RECV" TMUX_FAIL=1
{ [ "$RC" -eq 0 ] && grep -q 'recv-gate' "$HOMED/.claude/logs/context-distill-gate.log"; } \
  && ok "tmux 실패 → 0 + 로그 1줄(fail-open)" || bad "tmux 실패 rc=$RC log=$(cat "$HOMED/.claude/logs/context-distill-gate.log" 2>&1)"

# 460k(강제선 위) — 확인 수단은 증류 allowlist 를 통과한다(카드 설계 보정 2): 후계 개설·도달 확인·검증 송신·pane 읽기·pgrep
transcript 460000
for c in "bash $SO $SEAT $REPO --name x --agent claude --model m --body-file b" \
         "bash $REPO/.fable-team/bin/ft-reach-check.sh x marker 20 0" \
         "bash $REPO/.fable-team/bin/ft-send-verified.sh x text" \
         "tmux capture-pane -p -t x" "pgrep -P 123"; do
  hook "$c"
  [ "$RC" -eq 0 ] && ok "460k + 확인 수단 → 0: $(echo "$c" | cut -c1-60)" || bad "460k 확인 수단 차단: $c rc=$RC"
done
hook "ls /tmp"
[ "$RC" -eq 2 ] && ok "460k + allowlist 밖 명령(ls) → 여전히 차단" || bad "460k ls 가 통과 rc=$RC"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
