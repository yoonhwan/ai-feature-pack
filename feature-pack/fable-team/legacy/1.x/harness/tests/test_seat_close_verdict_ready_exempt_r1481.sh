#!/usr/bin/env bash
# test_seat_close_verdict_ready_exempt_r1481.sh — r1481: `ft-seat-close.sh <좌석> --verdict <번호>` 가 ①판정 번호를 planner 판정 원장에서 «실재» 확인하고
#   ②실재할 때만 mbox.py close-check 의 r1116 ②③(미표시 영수·[인계] 뒤 후계 [레디])을 면제한다. 판정 없음·원장 확인 불가 = REJECT(쓰기 0 · kill 0).
# 모든 쓰기는 mktemp scratch · 우편함은 정본 mbox* 복사본(격리 큐) · 가짜 tmux/retire/reap/ft-hil/git 래퍼 · 실 좌석·실 명부·실 원장 0.
# T1 미표시 영수 있어도 --verdict 면제(③) · T2 원장 실재 → CLOSED-ROLE(끝까지) · T3 --verdict 없음 = 지금 그대로 REJECT · T4 원장에 번호 없음(경계 포함) · T5 원장 확인 불가 · T6 후계 없음·--reopen 불변
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."; BIN="$REPO/harness/bin"; SRC="$REPO/harness/comm"
CLOSE="${FT_SEAT_CLOSE_BIN:-$BIN/ft-seat-close.sh}"; RB="$(command -v git)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
J() { jq -r "$2" "$1"; }
O="byz-feature-master-codex#169"; N="byz-feature-master-codex#170"   # O = 은퇴(_replaced_by→N) 꼴 = codex#169
export FT_ROOT="$T/root" RETIRE_LOG="$T/retire.log" GIT_LOG="$T/git.log" TMUX_LOG="$T/tmux.log" ZC_RESUME_DIR="$T/resume"
mkdir -p "$FT_ROOT/.fable-team/state" "$ZC_RESUME_DIR" "$T/bin" "$T/resume"
VLOG="$FT_ROOT/.fable-team/state/seat-close-verdict.log"; TREF="${TREF:-main}"   # 원장 ref = 임시 리포의 로컬 main(fetch 0)

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$GIT_LOG"\nexec %s "$@"\n' "$RB" > "$T/bin/git"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/reap-stub.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "$RETIRE_LOG"\necho "RESUME ok $FT_ROOT/resume/$1.json"\n' > "$T/bin/retire-stub.sh"
printf '#!/bin/sh\n[ "$1 $2" = "--pending --each" ] && { echo "h62 3"; exit 0; }\necho usage >&2; exit 2\n' > "$T/bin/ft-hil.sh"
cat > "$T/bin/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  has-session) n=""; for a in "$@"; do case "$a" in =*) n="${a#=}";; esac; done; [ "${FAKE_SESSION:-1}" = 1 ] && ! { [ -n "$TMUX_LOG" ] && [ -n "$n" ] && grep -qE "=$n(\$| )" <<<"$(grep '^kill-session' "$TMUX_LOG")"; } || exit 1;;   # r1568: «그 세션» kill-session 뒤엔 세션 없음(앞 사례 kill 이 뒤 사례를 가리지 않는다)
  show-options) [ "${FAKE_TAG:-1}" = 1 ] && echo 1; exit 0;;
  list-sessions) for x in ${FAKE_LIVE:-}; do echo "$x"; done;;
  list-panes) exit 0;;
  display-message) case "$*" in *session_attached*) echo 0;; *) echo caller#0;; esac;;   # r1839 사람 화면 0 = 지금 동작 그대로
esac
exit 0
EOF
cat > "$T/bin/mbox-stub.py" <<'EOF'
import os, sys
open(os.environ["MBOX_STUB_LOG"], "a").write(" ".join(sys.argv[1:]) + "\n")
print("CLOSE-OK stub 면제")
EOF
chmod 0755 "$T/bin/git" "$T/bin/reap-stub.sh" "$T/bin/retire-stub.sh" "$T/bin/ft-hil.sh" "$T/bin/tmux"; chmod 0644 "$T/bin/mbox-stub.py"

xenv() { env -u FT_PLANNER_HEAD_MODE -u FT_SEATS_JSON PATH="$T/bin:$PATH" TMUX_LOG="$TMUX_LOG" GIT_LOG="$GIT_LOG" \
  FT_SEATS_JSON="${FT_SEATS_JSON:-$E/seats/seats-feature.json}" FT_MBOX_DIR="$C" FT_HIL_BIN="$T/bin/ft-hil.sh" \
  FT_MBOX_PY="${FT_MBOX_PY:-$C/mbox.py}" MBOX_STUB_LOG="${MBOX_STUB_LOG:-$T/mboxstub.log}" RETIRE_LOG="$RETIRE_LOG" FT_TEAMS_REF="$TREF" \
  FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$BIN/ft-name-lint.sh" FT_SEAT_REAP_BIN="$T/bin/reap-stub.sh" \
  FT_SEAT_RETIRE_BIN="${FT_SEAT_RETIRE_BIN:-$T/bin/retire-stub.sh}" "$@"; }
sh_() { OUT="$(cd "$E" && xenv bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
py() { OUT="$(cd "$E" && xenv python3 "$C/mbox.py" "$@" 2>&1)"; RC=$?; }
close_() { OUT="$(cd "$E" && xenv bash "$CLOSE" "$@" 2>&1)"; RC=$?; }
ledger() { mkdir -p "$E/design/teams/planner"; printf '| 팀 | 폴더 |\n|---|---|\n| planner | design/teams/planner/ | x | 현역 |\n' > "$E/design/TEAMS.md"
  printf '%s\n' "${@:-| 4138 | 11-08 21:3x | 은퇴 좌석 3석 세션 닫기 |}" > "$E/design/teams/planner/VERDICTS-planner-1.md"; }
roster() {   # roster <retired 0|1> — 1 = O 은퇴(_replaced_by→N) 꼴(codex#169) · X#1 = 닫힌 행(--reopen 용)
  python3 - "$E/seats/seats-feature.json" "$1" "$O" "$N" <<'PY'
import json, sys
p, r, o, n = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4]
d = {"_master": n if r else o, o: {"role": "stop-ready" if r else "master", "agent": "codex", "model": "m", "tick": None},
     n: {"role": "master", "agent": "codex", "model": "m", "tick": None},
     "X#1": {"role": "stop-ready", "agent": "codex", "model": "m", "tick": None, "_closed_role": "nano",
             "_closed": {"by": "caller#0", "at": "2026-11-08T00:00:00", "reason": "r1481 시험"}}}
if r: d[o]["_replaced_by"] = n
json.dump(d, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env — 격리 리포(로컬 main 원장)·우편함 복사본·명부
  E="$(mktemp -d "$T/e.XXXXXX")"; C="$E/.fable-team/comm"; mkdir -p "$C" "$E/.fable-team/state" "$E/seats"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C"/; : > "$C/mailbox.jsonl"
  "$RB" -C "$E" init -q -b main; roster 1; printf '{}\n' > "$E/seats/seats.json"; ledger
  "$RB" -C "$E" add -A; "$RB" -C "$E" -c user.name=t -c user.email=t@t commit -qm base; : > "$GIT_LOG"
}
hando() { roster 0; sh_ handover "$O" "$N"; }   # 기계 [인계] 1통 — 현역일 때만 보낼 수 있어 먼저 은퇴 전 상태로 되돌린다
row() { printf '{"seq": %s, "ts": "2026-11-09T00:00:00", "to": "%s", "from": "slack-oppa", "body": "%s"}\n' "$1" "$2" "$3" >> "$C/mailbox.jsonl"; }
grepc() { grep -c "$1" "$GIT_LOG" 2>/dev/null || true; }
kills() { grep -c '^kill-session' "$TMUX_LOG" 2>/dev/null || true; }

# ── T1: 미표시 영수 1 이 있어도 `--verdict` = ②③ 면제 (python close_check 조기 반환) · 없으면 지금처럼 REJECT
new_env; hando; row 2 "$O" "[HIL] 두 번째 질문"; sh_ recv "$O"; roster 1   # [인계] 뒤에 받은 쪽지 = 미표시 영수 1 · 그 뒤 은퇴
py unmarked "$O"; chk "T1 준비 — O 미표시 영수 1(unmarked 는 있으면 rc1)" "$RC $OUT" "1 UNMARKED 1 #2"
py close-check "$O"; chk "T1 --verdict 없으면 미표시로 REJECT rc3" "$RC $([[ "$OUT" == *"미표시 쪽지"* ]] && echo 미표시거절)" "3 미표시거절"
py close-check "$O" --verdict; chk "T1 --verdict → CLOSE-OK ②③ 면제 rc0" "$RC $([[ "$OUT" == "CLOSE-OK $O 판정 닫기(②③ 면제 · 사람 판정 1건)" ]] && echo out-ok)" "0 out-ok"

# ── T2: 원장 실재 + 끝까지 → close-check 통과 → R400 ①②③ → CLOSED-ROLE · 명부 _closed.verdict · 원장 로그 1행
S="$E/seats/seats-feature.json"; : > "$RETIRE_LOG"; : > "$TMUX_LOG"; : > "$VLOG"
close_ "$O" --reason "판정 4138 은퇴 좌석 닫기" --seats "$S" --verdict 4138
chk "T2 rc0 · CLOSED-ROLE verdict=4138 kill=ok" "$RC $([[ "$OUT" == *"CLOSED-ROLE $O verdict=4138"*"kill=ok"* ]] && echo closed-role)" "0 closed-role"
chk "T2 명부 _closed.verdict=4138 · role stop-ready" "$(J "$S" "[.[\"$O\"]._closed.verdict,.[\"$O\"].role]|join(\",\")")" "4138,stop-ready"
chk "T2 원장 로그 1행 verdict=4138" "$(wc -l < "$VLOG" | tr -d ' ') $(cut -f2 "$VLOG")" "1 verdict=4138"
chk "T2 kill 1 · retire 스텁 1회(--record-only --verdict 4138)" "$(kills) $(grep -c -- '--record-only --verdict 4138' "$RETIRE_LOG")" "1 1"

# ── T3: `--verdict` 없는 호출 = 지금 동작 그대로 (close-check rc3 · ft-seat-close rc1 · 쓰기 0 · kill 0)
new_env; hando; roster 1; S="$E/seats/seats-feature.json"; cp "$S" "$T/roster3.orig"; : > "$TMUX_LOG"
py close-check "$O"; chk "T3 close-check rc3 · [레디] 없음" "$RC $([[ "$OUT" == *'후계 [레디] 없음'* ]] && echo ready-none)" "3 ready-none"
close_ "$O" --reason r --seats "$S"; chk "T3 ft-seat-close rc1 · 승계 마무리 전 거절 · 명부 바이트 동일 · kill 0" \
  "$RC $([[ "$OUT" == *"승계 마무리 전 닫기 거절(r1116 ②③"* ]] && echo rejected) $(cmp -s "$S" "$T/roster3.orig" && echo same) $(kills)" "1 rejected same 0"

# ── T4: 원장에 번호 없음 → REJECT rc1 · close-check 호출 0 · retire 0 · 명부 바이트 동일 · kill 0 (번호 경계 = fv_row_re)
export FT_MBOX_PY="$T/bin/mbox-stub.py" MBOX_STUB_LOG="$T/mboxstub.log"
export FT_CRITICAL_OFF=1   # r1718 A9: T4 는 거절 출력을 «줄 전체» 로 대조한다(2>&1) — 이 시험 환경에는 desk 명부가 없어 [크리티컬] 알림이 WARN 1줄을 덧붙인다 · 알림은 이 시험 대상이 아니다(test_reject_critical_r1718*)
new_env; hando; roster 1; S="$E/seats/seats-feature.json"; cp "$S" "$T/roster4.orig"; : > "$MBOX_STUB_LOG"; : > "$RETIRE_LOG"; : > "$TMUX_LOG"
close_ "$O" --reason r --seats "$S" --verdict 99999
chk "T4a 판정 99999 없음 → REJECT rc1 · 원장 문구" "$RC $([[ "$OUT" == "REJECT $O 판정 99999 이 main 원장(VERDICTS-planner-*.md)에 없음 — 쓰기 0 · kill 0" ]] && echo msg)" "1 msg"
chk "T4a close-check 0 · retire 0 · 명부 동일 · kill 0" "$(wc -l < "$MBOX_STUB_LOG" | tr -d ' ') $(wc -l < "$RETIRE_LOG" | tr -d ' ') $(cmp -s "$S" "$T/roster4.orig" && echo same) $(kills)" "0 0 same 0"
new_env; hando; roster 1; ledger "| 41380 | t | 시험 |" "- **4138a** 시험 줄"; "$RB" -C "$E" add -A; "$RB" -C "$E" -c user.name=t -c user.email=t@t commit -qm ledger2; cp "$E/seats/seats-feature.json" "$T/roster4b.orig"
close_ "$O" --reason r --seats "$E/seats/seats-feature.json" --verdict 4138
chk "T4b 이웃 번호(41380·4138a)만 있으면 «없음» rc1 · 쓰기 0" "$RC $([[ "$OUT" == *"판정 4138 이 main 원장"*"에 없음"* ]] && echo none) $(cmp -s "$E/seats/seats-feature.json" "$T/roster4b.orig" && echo same)" "1 none same"

# ── T5: 원장 확인 불가(ref 없음 · design/TEAMS.md 없는 ref) → REJECT rc1 · fetch 0 · 쓰기 0 · kill 0
new_env; hando; roster 1; cp "$E/seats/seats-feature.json" "$T/roster5.orig"; : > "$GIT_LOG"; : > "$TMUX_LOG"
TREF=nope; close_ "$O" --reason r --seats "$E/seats/seats-feature.json" --verdict 4138
chk "T5a ref 없음 → REJECT rc1 · «판정 원장 확인 불가»" "$RC $([[ "$OUT" == *"판정 원장 확인 불가(nope:design/TEAMS.md)"* ]] && echo unreadable)" "1 unreadable"
chk "T5a fetch 0 · 명부 동일 · kill 0" "$(grepc 'fetch') $(cmp -s "$E/seats/seats-feature.json" "$T/roster5.orig" && echo same) $(kills)" "0 same 0"
TREF=main; new_env; hando; roster 1; "$RB" -C "$E" rm -q design/TEAMS.md; "$RB" -C "$E" -c user.name=t -c user.email=t@t commit -qm rm-teams
cp "$E/seats/seats-feature.json" "$T/roster5b.orig"
close_ "$O" --reason r --seats "$E/seats/seats-feature.json" --verdict 4138
chk "T5b ref 에 design/TEAMS.md 없음 → «확인 불가» rc1 · 쓰기 0" "$RC $([[ "$OUT" == *"판정 원장 확인 불가(main:design/TEAMS.md)"* ]] && echo unreadable) $(cmp -s "$E/seats/seats-feature.json" "$T/roster5b.orig" && echo same)" "1 unreadable same"
unset FT_MBOX_PY

# ── T6: 후계 없는 좌석(C7 갈래) + --verdict = 지금 그대로 · `--reopen` 에는 원장 관문 0
new_env; roster 0
py close-check "$O" --verdict; chk "T6 후계 없음 + --verdict = CLOSE-OK 후계 없음(승계 검사 대상 아님) rc0" "$RC $([[ "$OUT" == "CLOSE-OK $O 후계 없음(승계 검사 대상 아님)" ]] && echo c7)" "0 c7"
: > "$GIT_LOG"; : > "$TMUX_LOG"; S="$E/seats/seats-feature.json"
close_ --reopen 'X#1' --seats "$S"; chk "T6 --reopen rc0 · REOPENED · git grep 0(원장 관문 없음)" \
  "$RC $([[ "$OUT" == *"REOPENED X#1"* ]] && echo reopened) $(grepc ' grep ')" "0 reopened 0"

# ── T7(DA 반례 1 · r1481 r2): 원장 꼴이 아닌 번호(--verdict 4138a) · 깨진 정규식 도우미(fv_row_re rc2 = 빈 정규식) — 어느 쪽도 닫기로 가면 안 된다
export FT_MBOX_PY="$T/bin/mbox-stub.py" MBOX_STUB_LOG="$T/mboxstub7.log"
new_env; hando; roster 1; S="$E/seats/seats-feature.json"; cp "$S" "$T/roster7.orig"; : > "$MBOX_STUB_LOG"; : > "$RETIRE_LOG"; : > "$TMUX_LOG"
close_ "$O" --reason r --seats "$S" --verdict 4138a
chk "T7a --verdict 4138a(원장 꼴 아님) → rc2 usage" "$RC $([[ "$OUT" == *"--verdict <번호>"* ]] && echo usage)" "2 usage"
chk "T7a 쓰기 0 · close-check 0 · retire 0 · kill 0" "$(cmp -s "$S" "$T/roster7.orig" && echo same) $(wc -l < "$MBOX_STUB_LOG" | tr -d ' ') $(wc -l < "$RETIRE_LOG" | tr -d ' ') $(kills)" "same 0 0 0"
close_ "$O" --reason r --seats "$S" --verdict
chk "T7c --verdict 값 없음 → rc2 usage · 쓰기 0 · kill 0" "$RC $([[ "$OUT" == *"--verdict <번호>"* ]] && echo usage) $(cmp -s "$S" "$T/roster7.orig" && echo same) $(kills)" "2 usage same 0"
TB="$T/brokenbin"; mkdir -p "$TB"; cp "$BIN/ft-seat-close.sh" "$BIN/ft_roster_lib.py" "$BIN/ft-harness-root.sh" "$BIN/ft_seat_bind.py" "$BIN/ft-team-lib.sh" "$TB/"
printf '#!/usr/bin/env bash\nfv_row_re() { return 2; }\n' > "$TB/ft-verdict-row.sh"; : > "$MBOX_STUB_LOG"; : > "$RETIRE_LOG"; : > "$TMUX_LOG"
OUT="$(cd "$E" && xenv bash "$TB/ft-seat-close.sh" "$O" --reason r --seats "$S" --verdict 4138 2>&1)"; RC=$?
chk "T7b fv_row_re rc2(빈 정규식) → REJECT rc1 · 안내" "$RC $([[ "$OUT" == *"꼴이 원장 꼴(숫자)이 아님(fv_row_re rc=2)"* ]] && echo reject)" "1 reject"
chk "T7b 쓰기 0 · close-check 0 · retire 0 · kill 0" "$(cmp -s "$S" "$T/roster7.orig" && echo same) $(wc -l < "$MBOX_STUB_LOG" | tr -d ' ') $(wc -l < "$RETIRE_LOG" | tr -d ' ') $(kills)" "same 0 0 0"
unset FT_MBOX_PY

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
