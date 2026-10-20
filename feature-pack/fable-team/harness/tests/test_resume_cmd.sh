#!/usr/bin/env bash
# test_resume_cmd.sh — ft-resume-cmd.sh (이어가기 블록 «재개» 칸 · 설계 §2 · DA HOLD-I3). 가짜 tmux(PATH 맨 앞 스텁) · 가짜 jsonl · 가짜 좌석표 — 실제 tmux/claude 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
CMD="$HERE/../../harness/bin/ft-resume-cmd.sh"
NONE='없음(좌석 종료 · 확인된 세션 매핑 없음 — 카드 정본으로 새로 연다)'
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub" "$T/root/.fable-team" "$T/projects"
cat > "$T/stub/tmux" <<'S'
#!/bin/sh
# has-session -t =NAME → FAKE_TMUX_LIVE(공백 구분)에 NAME 이 «정확히» 있을 때만 성공
[ "$1" = has-session ] || exit 1
name="${3#=}"
for s in $FAKE_TMUX_LIVE; do [ "$s" = "$name" ] && exit 0; done
exit 1
S
chmod +x "$T/stub/tmux"
export PATH="$T/stub:$PATH" FT_ROOT="$T/root" CLAUDE_PROJECTS_DIR="$T/projects" FAKE_TMUX_LIVE=""

enc() { printf '%s' "$1" | sed 's/[^A-Za-z0-9-]/-/g'; }
# jsonl <cwd> <uuid> <본문에 쓸 sessionId> <본문 cwd> [추가 본문]
jsonl() {
  local d
  d="$T/projects/$(enc "$1")"; mkdir -p "$d"
  printf '{"type":"user","message":"%s"}\n{"sessionId":"%s","cwd":"%s"}\n' "${5:-hi}" "$3" "$4" > "$d/$2.jsonl"
}
seats() { printf '%s' "$1" > "$T/root/.fable-team/${2:-seats.json}"; }
run() { OUT="$(bash "$CMD" "$@" 2>/dev/null)"; RC=$?; }
expect_none() { run "$1"; [ "$RC" = 3 ] && [ "$OUT" = "$NONE" ] && ok "$2" || bad "$2 (rc=$RC out=$OUT)"; }

A='byz-x-nano-a#0'; B='byz-x-nano-b#0'; U='11111111-2222-3333-4444-555555555555'
CWD="$T/work tree/wt a"

# ① 살아 있는 세션 → ring (정확 일치: 접두만 같은 세션은 살아 있는 것이 아니다)
FAKE_TMUX_LIVE="$A"; run "$A"
[ "$RC" = 0 ] && [ "$OUT" = "bash $T/root/.fable-team/comm/mbox.sh ring byz-x-nano-a#0" ] || [ "$OUT" = "bash $T/root/.fable-team/comm/mbox.sh ring byz-x-nano-a\\#0" ] && ok "live tmux → mbox ring" || bad "live tmux (rc=$RC out=$OUT)"
FAKE_TMUX_LIVE="${A}9"; seats '{}'; expect_none "$A" "prefix-only tmux session is not live"
FAKE_TMUX_LIVE=""

# ② 행 매핑 정확 1건 + jsonl 일치 + claude → cd … && ~/.headroom/claude-hr.sh --resume … (공백 경로 인용 · R524 헤드룸 래퍼)
seats "{\"$A\":{\"agent\":\"claude\",\"session_uuid\":\"$U\",\"cwd\":\"$CWD\"}}"
jsonl "$CWD" "$U" "$U" "$CWD"
run "$A"
want="$(printf 'cd %q && ~/.headroom/claude-hr.sh --resume %q' "$CWD" "$U")"
[ "$RC" = 0 ] && [ "$OUT" = "$want" ] && ok "exact mapping → cd && ~/.headroom/claude-hr.sh --resume (quoted)" || bad "mapping (rc=$RC out=$OUT want=$want)"
case "$OUT" in *"&& claude "*) bad "R524 날 claude 직결 명령이 남음";; *) ok "R524 날 claude 직결 명령 0";; esac
[ "$(bash -c "set -- ${OUT#cd }; echo \"\$1\"" 2>/dev/null)" = "$CWD" ] && ok "quoted cwd round-trips through the shell" || bad "quoting round-trip"

# ③ 전부 «없음» 으로 떨어지는 경우들
seats "{\"$A\":{\"agent\":\"claude\",\"session_uuid\":\"$U\",\"cwd\":\"$CWD\"}}"
rm -rf "$T/projects"/*; jsonl "$CWD" "$U" "other-uuid" "$CWD"; expect_none "$A" "jsonl sessionId differs from row"
rm -rf "$T/projects"/*; jsonl "$CWD" "$U" "$U" "/elsewhere"; expect_none "$A" "jsonl cwd differs from row"
rm -rf "$T/projects"/*; expect_none "$A" "row has mapping but jsonl missing"
seats "{\"$A\":{\"agent\":\"codex\",\"session_uuid\":\"$U\",\"cwd\":\"$CWD\"}}"; jsonl "$CWD" "$U" "$U" "$CWD"; expect_none "$A" "backend mismatch (agent=codex)"
seats "{\"$A\":{\"agent\":\"claude\"}}"; expect_none "$A" "row without session_uuid/cwd"
seats '{}'; expect_none "$A" "seat not in any roster"

# ③-b 이름 언급 ≠ 소유권: A 의 jsonl 본문이 B 를 언급해도 B 는 매핑이 없다 / 행이 2군데면 모호 → 없음
seats "{\"$A\":{\"agent\":\"claude\",\"session_uuid\":\"$U\",\"cwd\":\"$CWD\"}}"
rm -rf "$T/projects"/*; jsonl "$CWD" "$U" "$U" "$CWD" "나는 $B 에게 보낸다"
expect_none "$B" "name mentioned in someone else's jsonl is not ownership"
row="{\"$A\":{\"agent\":\"claude\",\"session_uuid\":\"$U\",\"cwd\":\"$CWD\"}}"; seats "$row" seats.json; seats "$row" seats-other.json
expect_none "$A" "same seat in two rosters is ambiguous"

# 인자 없음 → rc 2
bash "$CMD" >/dev/null 2>&1; [ "$?" = 2 ] && ok "no argument → rc 2" || bad "no argument rc"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
