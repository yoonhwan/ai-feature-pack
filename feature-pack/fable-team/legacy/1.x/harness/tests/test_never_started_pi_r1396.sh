#!/usr/bin/env bash
# test_never_started_pi_r1396.sh — r1396: ft-nano-never-started-check.sh --agent pi 가 pi 기록(~/.pi/agent/sessions)을 읽어 assistant 턴을 센다
#   계기: «한 일 0» 검사가 claude(jsonl)·opencode(db) 갈래만 있어 pi 나노는 늘 «확인 못 함 대화 기록(agent=pi)» REJECT(r1392#0 · r1371#0).
#   값: 첫 줄 type=session 의 cwd == 워크트리 실경로 ∧ session_info.name == 좌석 이름 인 파일의 type=message ∧ message.role=assistant 줄 수
#       · 이름 줄 없는 옛 파일 = cwd 같고 첫 줄 timestamp ≥ .worktree-info.json created_at 인 것만 · 파일 0개 = 턴 0 · 못 읽음/시간 초과 = 확인 못 함
#   시험 입력은 전부 임시 폴더다 — 실 ~/.pi·실 명부·실 우편함은 건드리지 않는다(FT_PI_SESSIONS 로 주입). 자기 파일 재호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

echo "== 키트 2곳 같은 바이트 + bash -n"
cmp -s "$BIN/ft-nano-never-started-check.sh" "$SRC/ft-nano-never-started-check.sh" && ok "cmp (bin == kit)" || bad "cmp 다름"
bash -n "$SRC/ft-nano-never-started-check.sh" && ok "bash -n" || bad "bash -n"

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
BASE="$(git -C "$REPO" rev-parse HEAD)"
SEAT='byz-planner-nano-ns#0'; SUC='byz-planner-nano-ns#1'; BR='nano/ns'; NW="$REPO/.worktrees/ns"; PI="$T/pi"; COMM="$T/comm"
mkdir -p "$COMM"; git -C "$REPO" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t

setup() {  # «한 일 0» 로 리셋: 커밋 0 · 미커밋 0(노이즈 제외) · 발신 0 · pi 기록 0 · 좌석 created_at
  git -C "$NW" reset -q --hard "$BASE"; git -C "$NW" clean -qfd; git -C "$REPO" branch -q -f "$BR" "$BASE" 2>/dev/null
  printf '{"branch":"%s","base_sha":"%s","created_at":"2026-11-11 07:00:00"}\n' "$BR" "${BASE:0:10}" > "$NW/.worktree-info.json"
  printf '{"seq": 1, "from": "byz-planner-master-claude#1", "to": "%s", "body": "[발주]"}\n' "$SEAT" > "$COMM/mailbox.log.jsonl"
  rm -rf "$PI"; mkdir -p "$PI/--repo-.worktrees-ns--"
}
pifile() {  # pifile <경로> <cwd|-> <이름|-> <assistant 수> [첫 줄 timestamp]
  python3 - "$1" "$2" "$3" "$4" "${5:-2026-11-11T07:09:50.448Z}" <<'PY'
import json, sys
p, cwd, name, n, ts = sys.argv[1:6]
rows = [{"type": "session", "version": 3, "id": "x", "timestamp": ts, "cwd": cwd}]
if name != "-": rows.append({"type": "session_info", "id": "y", "timestamp": ts, "name": name})
rows.append({"type": "message", "timestamp": ts, "message": {"role": "user", "content": "발주"}})
for i in range(int(n)):
    rows.append({"type": "message", "timestamp": ts, "message": {"role": "assistant", "content": "일", "model": "m"}})
rows.append({"type": "message", "timestamp": ts, "message": {"role": "toolResult", "content": "결과"}})
open(p, "w", encoding="utf-8").write("\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n")
PY
}
CHK() { ( cd "$T" && env -i HOME="$T/home" FT_PI_SESSIONS="$PI_ROOT" PATH="$PATH" bash "$SRC/ft-nano-never-started-check.sh" "$SEAT" --wt "$NW" --branch "$BR" --comm "$COMM" --agent pi "$@" 2>&1 ); }
PI_ROOT=""
chk() { PI_ROOT="$PI"; CHK "$@"; }

echo "== P1 pi 기록 0(폴더 없음·파일 0·그 좌석 파일에 assistant 0) → NEVER-STARTED ok turns=0"
setup; out="$(chk)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "NEVER-STARTED ok turns=0" "  └ 기록 0 → 통과" || bad "P1 rc=$rc ← ${out:0:400}"
PI_ROOT="$T/no-such-pi-root"; out="$(CHK)"; rc=$?
[ "$rc" -eq 0 ] && ok "P1' 기록 뿌리 없음 → 턴 0 통과" || bad "P1' rc=$rc ← ${out:0:400}"
setup; pifile "$PI/--repo-.worktrees-ns--/a.jsonl" "$NW" "$SEAT" 0; out="$(chk)"; rc=$?
[ "$rc" -eq 0 ] && ok "P1'' 그 좌석 파일 assistant 0(user·toolResult 만) → 통과" || bad "P1'' rc=$rc ← ${out:0:400}"

echo "== P2 같은 워크트리 · name = 좌석 · assistant 3 → REJECT «pi 턴 3»"
setup; pifile "$PI/--repo-.worktrees-ns--/a.jsonl" "$NW" "$SEAT" 3; out="$(chk)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "never-started: pi 턴 3" "P2" || bad "P2 rc=$rc ← ${out:0:400}"
hasnt "$out" "확인 못 함" "  └ 확인 못 함 아님(실제로 셈)"

echo "== P3 같은 워크트리 · name = 다른 좌석(후계 #1) · assistant 5 → 이 좌석 턴 0"
setup; pifile "$PI/--repo-.worktrees-ns--/b.jsonl" "$NW" "$SUC" 5; out="$(chk)"; rc=$?
[ "$rc" -eq 0 ] && ok "P3 남의 좌석 기록은 세지 않는다" || bad "P3 rc=$rc ← ${out:0:400}"

echo "== P4 다른 워크트리 cwd · name = 좌석 → 셈 0"
setup; mkdir -p "$T/other-wt" "$PI/other"; pifile "$PI/other/a.jsonl" "$T/other-wt" "$SEAT" 2; out="$(chk)"; rc=$?
[ "$rc" -eq 0 ] && ok "P4 다른 cwd 기록은 세지 않는다" || bad "P4 rc=$rc ← ${out:0:400}"

echo "== P5 JSON 깨짐 → 확인 못 함 pi 기록 · rc 1"
setup; pifile "$PI/--repo-.worktrees-ns--/ok.jsonl" "$NW" "$SEAT" 0; printf '{"type":"session","cwd":"%s"}\n{깨진 줄\n' "$NW" > "$PI/--repo-.worktrees-ns--/bad.jsonl"
out="$(chk)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "확인 못 함 pi 기록" "P5 깨진 파일은 건너뛰지 않고 확인 못 함" || bad "P5 rc=$rc ← ${out:0:400}"
has "$out" "bad.jsonl" "  └ 어느 파일인지 이름을 남긴다"

echo "== P6 이름 줄 없는 옛 파일 — 좌석 생성 전 timestamp = 셈 0 / 생성 뒤 = 셈"
setup; pifile "$PI/--repo-.worktrees-ns--/old.jsonl" "$NW" "-" 4 "2026-11-10T00:00:00.000Z"; out="$(chk)"; rc=$?
[ "$rc" -eq 0 ] && ok "P6' 생성 전 옛 파일 → 셈 0" || bad "P6' rc=$rc ← ${out:0:400}"
setup; pifile "$PI/--repo-.worktrees-ns--/new.jsonl" "$NW" "-" 2 "2026-11-11T08:00:00.000Z"; out="$(chk)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "never-started: pi 턴 2" "P6'' 생성 뒤 이름 없는 파일 → 센다" || bad "P6'' rc=$rc ← ${out:0:400}"

echo "== 시간 상한 — 넘기면 확인 못 함(셈 0 통과 금지)"
setup; pifile "$PI/--repo-.worktrees-ns--/a.jsonl" "$NW" "$SEAT" 0
out="$( cd "$T" && env -i HOME="$T/home" FT_PI_SESSIONS="$PI" FT_PI_TIMEOUT=-1 PATH="$PATH" bash "$SRC/ft-nano-never-started-check.sh" "$SEAT" --wt "$NW" --branch "$BR" --comm "$COMM" --agent pi 2>&1 )"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "확인 못 함 pi 기록" "상한 초과 → 확인 못 함" || bad "상한 rc=$rc ← ${out:0:400}"

echo "== 다른 값(커밋·미커밋·발신)은 그대로 — pi 갈래만 더한다"
setup; pifile "$PI/--repo-.worktrees-ns--/a.jsonl" "$NW" "$SEAT" 0; echo x > "$NW/w.txt"; out="$(chk)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "미커밋 1파일" "미커밋 검사 그대로" || bad "미커밋 rc=$rc ← ${out:0:400}"
setup; printf '{"seq": 2, "from": "%s", "to": "m", "body": "x"}\n' "$SEAT" >> "$COMM/mailbox.log.jsonl"; out="$(chk)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "보낸 쪽지 1" "발신 검사 그대로" || bad "발신 rc=$rc ← ${out:0:400}"
setup; out="$( cd "$T" && env -i HOME="$T/home" FT_PI_SESSIONS="$PI" PATH="$PATH" bash "$SRC/ft-nano-never-started-check.sh" "$SEAT" --wt "$NW" --branch "$BR" --comm "$COMM" --agent codex 2>&1 )"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "확인 못 함 대화 기록(agent=codex)" "그 밖 에이전트 갈래 그대로" || bad "codex rc=$rc ← ${out:0:400}"

echo "== 실 기록 무접촉 — FT_PI_SESSIONS 밖(~/.pi)을 읽지 않는다"
setup; out="$(chk)"; rc=$?
[ "$rc" -eq 0 ] && ok "임시 뿌리 0개 → 통과(실 ~/.pi 안 봄)" || bad "실무접촉 rc=$rc ← ${out:0:400}"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
