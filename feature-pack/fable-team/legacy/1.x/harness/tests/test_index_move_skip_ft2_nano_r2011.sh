#!/usr/bin/env bash
# test_index_move_skip_ft2_nano_r2011.sh — r2011: 완성 이동의 나노 닫기 고리가 2.0 나노(명부 행 source=ft2-launch 또는
#   worktree 에 «/.fable-team/teams/»)는 1.x ft-nano-close 를 부르지 않고 «NANO-CLOSE <좌석> skip ft2 → keeper» 1줄만 남긴다.
#   T1 ft2(source+worktree) = 호출 0 · h 0 · skip 1줄 · rc0 · T1b source 없음 + worktree 만 = T1 과 같음 ·
#   T2 1.x 행 = 호출 1 · 지금 출력 그대로 · T3 ft2 1석 + 1.x 1석 = 호출 1(1.x 만) · skip 1줄.
#   변이: M1 ① 갈래 삭제 → T1 FAIL · M2 worktree 조건 삭제 → T1b FAIL.
#   임시 리포·가짜 판정문·가짜 명부(FT_SEATS_JSON)·가짜 ft-nano-close·가짜 ft-hil 만 — 실 명부·실 우편함 0 · sleep 0.
set -uo pipefail
export LC_ALL=C
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:600}";; *) ok "$3";; esac; }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got=[$1] want=[$2])"; fi; }

echo "== 짝 cmp · bash -n"
cmp -s "$SRCDIR/ft-index-move.sh" "$KIT/ft-index-move.sh" && ok "cmp bin == kit ft-index-move.sh" || bad "cmp 다름 ft-index-move.sh"
bash -n "$SRCDIR/ft-index-move.sh" && ok "bash -n ft-index-move.sh" || bad "bash -n ft-index-move.sh"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BIN="$T/bin"; mkdir -p "$BIN"
cp "$SRCDIR/ft-index-move.sh" "$SRCDIR/ft-index-move-canon.sh" "$SRCDIR/ft-index-move-install.sh" "$SRCDIR/ft_da_hold_gate.py" "$SRCDIR/ft_git_capped.py" "$SRCDIR/ft-team-lib.sh" "$BIN/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-index-lint.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "$MBOX_LOG"\nexit 0\n' > "$T/fake-mbox.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$CLOSE_LOG"\nexit 0\n' > "$T/fake-close.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$HIL_LOG"\necho "! bash /tmp/h7"\nexit 0\n' > "$T/fake-hil.sh"
chmod +x "$T/fake-mbox.sh" "$T/fake-close.sh" "$T/fake-hil.sh"
mkdir -p "$T/state" "$T/comm"
export FT_MBOX="$T/fake-mbox.sh" MBOX_LOG="$T/mbox.log" FT_INDEX_STATE_DIR="$T/state" FT_LAND_REF=main
export FT_MBOX_DIR="$T/comm" FT_NANO_CLOSE_BIN="$T/fake-close.sh" FT_HIL_BIN="$T/fake-hil.sh"
export CLOSE_LOG="$T/close.log" HIL_LOG="$T/hil.log"

REPO="$T/repo"; IDX="$REPO/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성}
G() { git -C "$REPO" "$@"; }
G init -q -b main . && G config user.email t@t && G config user.name t
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$REPO/design/TEAMS.md"
echo base > "$REPO/code.txt"; G add -A; G commit -qm base

card() {
  local f="$IDX/진행/$1.md"
  printf '# 인덱스: %s\n## 상태\n- 정본 영향 없음: 하네스 도구만 변경 — 제품 정본 없음\n- 규칙: 없음 — 시험 fixture 카드(규칙 무관)\n- 설치: 없음\n- 남은 범위: 없음\n' "$1" > "$f"
  echo "$f"
}
da() { local f="$REPO/design/harness/$1.md"; shift; printf '# 판정문\n' > "$f"; printf '%s\n' "$@" >> "$f"; echo "$f"; }
mv_() { bash "$BIN/ft-index-move.sh" "$@" 2>&1; }
seats() { printf '%s\n' "$1" > "$T/seats.json"; export FT_SEATS_JSON="$T/seats.json"; }
mbox_row() { printf '{"seq":%s,"from":"%s","to":"byz-harness-master-pi#193","body":"산출"}\n' "$2" "$1" >> "$T/comm/mailbox.jsonl"; }
reset_logs() { : > "$CLOSE_LOG"; : > "$HIL_LOG"; }
WT="/r/.fable-team/teams/t1/worktrees/x@a1"

# ══ T1 — ft2 행(source=ft2-launch · worktree …/.fable-team/teams/…) = 호출 0 · h 0 · skip 1줄 ═════════
c="$(card k1)"; d="$(da da1 "## §1 닫힘: k1")"
seats '{"byz-nano-f#0":{"role":"nano","index":"design/harness/indices/진행/k1.md","source":"ft2-launch","agent":"pi","worktree":"'"$WT"'"}}'
mbox_row byz-nano-f#0 11; reset_logs
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s)"; rc=$?
has "$out" "NANO-CLOSE byz-nano-f#0 skip ft2 → keeper" "T1a ft2 행 → skip 1줄"
eq "$(grep -c '^NANO-CLOSE' <<< "$out")" "1" "T1b NANO-CLOSE 줄 1개"
[ ! -s "$CLOSE_LOG" ] && ok "T1c ft-nano-close 호출 0" || bad "T1c 닫기가 불렸다: $(cat "$CLOSE_LOG")"
[ ! -s "$HIL_LOG" ] && ok "T1d h 0" || bad "T1d h 가 불렸다: $(cat "$HIL_LOG")"
eq "$rc" "0" "T1e 이동 rc0"
has "$out" "MOVED 진행→완성" "T1f 이동 그대로"

# ══ T1b — source 칸 없음 + worktree 만 …/.fable-team/teams/… = T1 과 같음 ═══════════════════════
c="$(card k1b)"; d="$(da da1b "## §1 닫힘: k1b")"
seats '{"byz-nano-g#0":{"role":"nano","index":"design/harness/indices/진행/k1b.md","worktree":"'"$WT"'"}}'
mbox_row byz-nano-g#0 12; reset_logs
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s)"; rc=$?
has "$out" "NANO-CLOSE byz-nano-g#0 skip ft2 → keeper" "T1b-a worktree 만 → skip 1줄"
[ ! -s "$CLOSE_LOG" ] && ok "T1b-b ft-nano-close 호출 0" || bad "T1b-b 닫기가 불렸다: $(cat "$CLOSE_LOG")"
[ ! -s "$HIL_LOG" ] && ok "T1b-c h 0" || bad "T1b-c h 가 불렸다: $(cat "$HIL_LOG")"
eq "$rc" "0" "T1b-d 이동 rc0"

# ══ T2 — 1.x 행(source·worktree 없음) = 지금 그대로(호출 1 · NANO-CLOSE rc=0) ═══════════════════
c="$(card k2)"; d="$(da da2 "## §1 닫힘: k2")"
seats '{"byz-nano-h#0":{"role":"nano","index":"design/harness/indices/진행/k2.md"}}'
mbox_row byz-nano-h#0 13; reset_logs
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s)"
has "$out" "NANO-CLOSE byz-nano-h#0 rc=0" "T2a 1.x 행 → 지금 출력 그대로"
hasnt "$out" "skip ft2" "T2b 1.x 행은 skip 0"
eq "$(cat "$CLOSE_LOG")" "byz-nano-h#0 --result $IDX/완성/k2.md --recv 13" "T2c 닫기 호출 1회(인자 그대로)"

# ══ T3 — 같은 카드에 ft2 1석 + 1.x 1석 = 호출 1(1.x 만) · skip 1줄 ═══════════════════════════════
c="$(card k3)"; d="$(da da3 "## §1 닫힘: k3")"
seats '{"byz-nano-i#0":{"role":"nano","index":"design/harness/indices/진행/k3.md","source":"ft2-launch","worktree":"'"$WT"'"},"byz-nano-j#0":{"role":"nano","index":"design/harness/indices/진행/k3.md"}}'
mbox_row byz-nano-i#0 14; mbox_row byz-nano-j#0 15; reset_logs
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s)"
eq "$(cat "$CLOSE_LOG")" "byz-nano-j#0 --result $IDX/완성/k3.md --recv 15" "T3a 호출 1회 = 1.x 좌석만"
eq "$(grep -c 'skip ft2 → keeper' <<< "$out")" "1" "T3b skip 1줄"
has "$out" "NANO-CLOSE byz-nano-i#0 skip ft2 → keeper" "T3c skip 줄 = ft2 좌석"
has "$out" "NANO-CLOSE byz-nano-j#0 rc=0" "T3d 1.x 좌석 rc=0 줄"

echo "== 결과: FAIL=$fail"
exit $(( fail > 0 ? 1 : 0 ))
