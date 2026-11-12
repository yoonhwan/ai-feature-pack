#!/usr/bin/env bash
# test_index_move_done_closes_nano_r1649.sh — r1649 ⓐⓑⓓ: 완성 이동이 그 카드 나노 좌석을 «같은 실행»에서 ft-nano-close 표준 경로로 닫는다.
#   사례1 나노 1석 닫기 rc0 → NANO-CLOSE rc=0 · h 0 · 사례2 가짜 닫기 rc1 → h 1장 · 이동 rc0 · 사례3 _replaced_by·다른 카드 행 = 호출 0 ·
#   사례4 완성 아닌 이동(대기→진행) = 호출 0. 사례2b 우편함 발신 0 = 닫기 0 → h 1장(ⓑ).
#   사례1b 발신이 «로그(mailbox.log.jsonl)에만» 있어도 그 seq 로 닫는다(r2 ⓐ) · 사례2c 닫기 실패의 첫 REJECT 줄이 h 주석·NANO-CLOSE 줄에 남는다(r2 ⓑ).
#   r1718 A10: 닫기가 rc 1 + REJECT(거절)이면 h 계획을 만들지 않는다(사례2c ⓐ) — h 주석에 첫 REJECT 줄이 남는 것은 rc 1 이 아닌 실패(사례2c ⓑ).
#   임시 리포·가짜 판정문·가짜 명부(FT_SEATS_JSON)·가짜 ft-nano-close(FT_NANO_CLOSE_BIN)·가짜 ft-hil(FT_HIL_BIN)만 — 실 tmux·실 우편함·실 명부 0 · sleep 0.
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

echo "== 짝 cmp · bash -n · 실행 비트"
for f in ft-index-move.sh; do cmp -s "$SRCDIR/$f" "$KIT/$f" && ok "cmp bin == kit $f" || bad "cmp 다름 $f"; done
bash -n "$SRCDIR/ft-index-move.sh" && ok "bash -n ft-index-move.sh" || bad "bash -n ft-index-move.sh"
[ ! -x "$HERE/test_index_move_done_closes_nano_r1649.sh" ] && ok "새 시험 100644(실행 비트 0)" || ok "새 시험 실행 비트 있음(무관)"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BIN="$T/bin"; mkdir -p "$BIN"
cp "$SRCDIR/ft-index-move.sh" "$SRCDIR/ft-index-move-canon.sh" "$SRCDIR/ft-index-move-install.sh" "$SRCDIR/ft_da_hold_gate.py" "$SRCDIR/ft_git_capped.py" "$SRCDIR/ft-team-lib.sh" "$BIN/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-index-lint.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "$MBOX_LOG"\nexit 0\n' > "$T/fake-mbox.sh"
# 가짜 닫기·가짜 h — 인자·rc 를 그대로 기록한다(실 ft-nano-close·실 ft-hil 0)
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$CLOSE_LOG"\n[ ! -f "$CLOSE_OUT" ] || cat "$CLOSE_OUT"\nexit "$(cat "$CLOSE_RC" 2>/dev/null || echo 0)"\n' > "$T/fake-close.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$HIL_LOG"\necho "! bash /tmp/h7"\nexit 0\n' > "$T/fake-hil.sh"
chmod +x "$T/fake-mbox.sh" "$T/fake-close.sh" "$T/fake-hil.sh"
mkdir -p "$T/state" "$T/comm"
export FT_MBOX="$T/fake-mbox.sh" MBOX_LOG="$T/mbox.log" FT_INDEX_STATE_DIR="$T/state" FT_LAND_REF=main
export FT_MBOX_DIR="$T/comm" FT_NANO_CLOSE_BIN="$T/fake-close.sh" FT_HIL_BIN="$T/fake-hil.sh"
export CLOSE_LOG="$T/close.log" HIL_LOG="$T/hil.log" CLOSE_RC="$T/close.rc" CLOSE_OUT="$T/close.out"
: > "$CLOSE_LOG"; : > "$HIL_LOG"; : > "$T/close.out"; echo 0 > "$CLOSE_RC"

REPO="$T/repo"; IDX="$REPO/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성}
G() { git -C "$REPO" "$@"; }
G init -q -b main . && G config user.email t@t && G config user.name t
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$REPO/design/TEAMS.md"
echo base > "$REPO/code.txt"; G add -A; G commit -qm base

card() {   # <이름> — 진행/ 에 카드 생성, 경로 출력
  local f="$IDX/진행/$1.md"
  printf '# 인덱스: %s\n## 상태\n- 정본 영향 없음: 하네스 도구만 변경 — 제품 정본 없음\n- 규칙: 없음 — 시험 fixture 카드(규칙 무관)\n- 설치: 없음\n' "$1" > "$f"
  echo "$f"
}
da() { local f="$REPO/design/harness/$1.md"; shift; printf '# 판정문\n' > "$f"; printf '%s\n' "$@" >> "$f"; echo "$f"; }
mv_() { bash "$BIN/ft-index-move.sh" "$@" 2>&1; }
seats() {   # <json 본문> — 가짜 명부
  printf '%s\n' "$1" > "$T/seats.json"; export FT_SEATS_JSON="$T/seats.json"
}
mbox_row() { printf '{"seq":%s,"from":"%s","to":"byz-harness-master-pi#193","body":"산출"}\n' "$2" "$1" >> "$T/comm/mailbox.jsonl"; }

# ══ 사례1 — 완성 이동 = 같은 실행 닫기(rc0) · h 0 ══════════════════════════════════════════════
c1="$(card k1)"; d1="$(da da1 "## §1 닫힘: k1")"
seats '{"_arch":"byz-harness-arch-pi#9","byz-nano-a#0":{"role":"nano","index":"design/harness/indices/진행/k1.md"}}'
mbox_row byz-nano-a#0 12
out="$(mv_ "$c1" 완성 --da "$d1#§1" --seat s)"
has "$out" "NANO-CLOSE byz-nano-a#0 rc=0" "1a rc0 → NANO-CLOSE rc=0 1줄"
has "$out" "MOVED 진행→완성" "1b 이동도 그대로(닫기가 이동을 되돌리지 않는다)"
eq "$(cat "$CLOSE_LOG")" "byz-nano-a#0 --result $IDX/완성/k1.md --recv 12" "1c 닫기 인자 = 좌석 · 완성 카드 경로 · 그 좌석 마지막 seq"
[ ! -s "$HIL_LOG" ] && ok "1d 성공 좌석 h 0" || bad "1d h 가 불렸다: $(cat "$HIL_LOG")"

# ══ 사례1b — 발신이 «로그에만» 있어도 그 seq 로 닫는다(큐는 recv 가 소비해 비어 있다) ═══════════════
c1b="$(card k1b)"; d1b="$(da da1b "## §1 닫힘: k1b")"
seats '{"byz-nano-a2#0":{"role":"nano","index":"design/harness/indices/진행/k1b.md"}}'
: > "$T/comm/mailbox.jsonl"; printf '{"seq":33,"ts":"2026-11-11T13:00:00","from":"byz-nano-a2#0","to":"byz-harness-master-pi#193","body":"산출"}\n' > "$T/comm/mailbox.log.jsonl"
: > "$CLOSE_LOG"
out="$(mv_ "$c1b" 완성 --da "$d1b#§1" --seat s)"
has "$out" "NANO-CLOSE byz-nano-a2#0 rc=0" "1e 로그에만 있는 발신 → 닫기 rc0(«발신 0 → h» 로 새지 않는다)"
eq "$(cat "$CLOSE_LOG")" "byz-nano-a2#0 --result $IDX/완성/k1b.md --recv 33" "1f 로그에서 읽은 seq 를 --recv 로 넘긴다"
: > "$T/comm/mailbox.log.jsonl"

# ══ 사례2 — 닫기 rc≠0 = 그 좌석만 h 1장 · 이동 rc 불변 ════════════════════════════════════════
c2="$(card k2)"; d2="$(da da2 "## §1 닫힘: k2 k2b")"
seats '{"_arch":"","byz-nano-b#0":{"role":"nano","index":"design/harness/indices/진행/k2.md"}}'
mbox_row byz-nano-b#0 21; echo 1 > "$CLOSE_RC"; : > "$CLOSE_LOG"; : > "$HIL_LOG"
out="$(mv_ "$c2" 완성 --da "$d2#§1" --seat s)"; rc2=$?
has "$out" "NANO-CLOSE byz-nano-b#0 rc=1 → h7" "2a 닫기 실패 → rc + h 번호 1줄"
eq "$rc2" "0" "2b 이동 rc 불변(닫기 실패가 완성을 되돌리지 않는다)"
[ -f "$IDX/완성/k2.md" ] && ok "2c 카드는 완성/ 에 있다" || bad "2c 카드가 안 옮겨졌다: $out"
eq "$(wc -l < "$HIL_LOG" | tr -d ' ')" "1" "2d h 등록 1장(성공 좌석 0)"
case "$(cat "$HIL_LOG")" in *"--add "*/plan.sh) ok "2e h 에 계획 파일 경로가 넘어간다";; *) bad "2e h 인자: $(cat "$HIL_LOG")";; esac

# ══ 사례2c — ⓐ rc 1 + REJECT = 계획 0(r1718 A10) · ⓑ rc 1 아닌 실패의 첫 REJECT 줄이 h 주석·NANO-CLOSE 줄에 남는다 ════════
c2c="$(card k2c)"; d2c="$(da da2c "## §1 닫힘: k2c")"
seats '{"_arch":"","byz-nano-e#0":{"role":"nano","index":"design/harness/indices/진행/k2c.md"}}'
printf '{"seq":41,"from":"byz-nano-e#0","to":"byz-harness-master-pi#193","body":"산출"}\n' >> "$T/comm/mailbox.jsonl"
printf 'REJECT 테스트 실패 — ⑥ 증거 줄 없음\n  - 세부 줄\n' > "$T/close.out"; echo 1 > "$CLOSE_RC"; : > "$HIL_LOG"
out="$(mv_ "$c2c" 완성 --da "$d2c#§1" --seat s)"; rc2c=$?
has "$out" "NANO-CLOSE byz-nano-e#0 rc=1 계획 0 — REJECT 테스트 실패 — ⑥ 증거 줄 없음 · 세부 줄" "2h rc 1 + REJECT → «계획 0» 줄(머리 줄 + 첫 사유 줄)"
[ ! -s "$HIL_LOG" ] && ok "2h2 거절 판 h 계획 0(같은 입력으로 다시 돌려도 거절)" || bad "2h2 h 가 불렸다: $(cat "$HIL_LOG")"
eq "$rc2c" "0" "2h3 이동 rc 불변"
c2d="$(card k2d)"; d2d="$(da da2d "## §1 닫힘: k2d")"
seats '{"_arch":"","byz-nano-e#0":{"role":"nano","index":"design/harness/indices/진행/k2d.md"}}'
echo 3 > "$CLOSE_RC"; : > "$HIL_LOG"
out="$(mv_ "$c2d" 완성 --da "$d2d#§1" --seat s)"
has "$out" "NANO-CLOSE byz-nano-e#0 rc=3 → h7 — ft-nano-close rc=3 — REJECT 테스트 실패" "2h4 rc 1 아닌 실패 → NANO-CLOSE 줄 끝에 실패 첫 REJECT 줄(지금 그대로)"
plan="$(sed -n 's/^--add //p' "$HIL_LOG" | head -1)"
[ -f "$plan" ] && grep -q '^# .*REJECT 테스트 실패' "$plan" && ok "2i h 계획 주석에 실패 첫 줄" || bad "2i h 계획 주석: $(cat "$plan" 2>/dev/null | head -3)"
grep -q -- '--recv 41' "$plan" 2>/dev/null && ok "2j h 계획 = 같은 ft-nano-close 한 줄(seq 보존)" || bad "2j h 계획: $(cat "$plan" 2>/dev/null)"
: > "$T/close.out"; echo 0 > "$CLOSE_RC"

# ══ 사례2b — 우편함 발신 0 = 닫기 0 → h 1장 ═════════════════════════════════════════════════
c2b="$(card k2b)"; echo 0 > "$CLOSE_RC"; : > "$CLOSE_LOG"; : > "$HIL_LOG"
seats '{"byz-nano-c#0":{"role":"nano","index":"design/harness/indices/진행/k2b.md"}}'
out="$(mv_ "$c2b" 완성 --da "$d2#§1" --seat s)"
has "$out" "NANO-CLOSE byz-nano-c#0 rc=- → h7" "2f seq 없음 → 닫기 0 · h 1장"
[ ! -s "$CLOSE_LOG" ] && ok "2g seq 없으면 ft-nano-close 를 부르지 않는다" || bad "2g 닫기가 불렸다: $(cat "$CLOSE_LOG")"

# ══ 사례3 — 남의 행(_replaced_by · 다른 카드) = 호출 0 ═════════════════════════════════════════
c3="$(card k3)"; d3="$(da da3 "## §1 닫힘: k3")"
seats '{"byz-nano-old#0":{"role":"nano","index":"design/harness/indices/진행/k3.md","_replaced_by":"byz-nano-old#1"},"byz-nano-other#0":{"role":"nano","index":"design/harness/indices/진행/다른카드.md"},"byz-nano-notnano#0":{"role":"tester","index":"design/harness/indices/진행/k3.md"}}'
: > "$CLOSE_LOG"; : > "$HIL_LOG"
out="$(mv_ "$c3" 완성 --da "$d3#§1" --seat s)"
has "$out" "NANO-CLOSE 0석" "3a 맞는 좌석 0 = NANO-CLOSE 0석 1줄"
[ ! -s "$CLOSE_LOG" ] && [ ! -s "$HIL_LOG" ] && ok "3b 옛 행·다른 카드·다른 역할 = 호출 0" || bad "3b 호출됨: $(cat "$CLOSE_LOG" "$HIL_LOG")"

# ══ 사례4 — 완성 아닌 이동(대기→진행) = 호출 0 ═══════════════════════════════════════════════
printf '# 인덱스: k4\n## 상태\n- 정본 영향 없음: x\n- 규칙: 없음 — 시험 fixture 카드\n- 설치: 없음\n' > "$IDX/대기/k4.md"
seats '{"byz-nano-d#0":{"role":"nano","index":"design/harness/indices/대기/k4.md"}}'
: > "$CLOSE_LOG"; : > "$HIL_LOG"; : > "$MBOX_LOG"
out="$(mv_ "$IDX/대기/k4.md" 진행 --seat byz-nano-d#0)"
has "$out" "MOVED 대기→진행" "4a 대기→진행 은 그대로"
hasnt "$out" "NANO-CLOSE" "4b 완성 아닌 이동은 닫기 0"
[ ! -s "$CLOSE_LOG" ] && ok "4c 닫기 호출 0" || bad "4c 닫기가 불렸다: $(cat "$CLOSE_LOG")"

echo "== 결과: FAIL=$fail"
exit $(( fail > 0 ? 1 : 0 ))
