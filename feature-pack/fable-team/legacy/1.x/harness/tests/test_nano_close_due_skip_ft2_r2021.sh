#!/usr/bin/env bash
# test_nano_close_due_skip_ft2_r2021.sh — r2021: ft-nano-close-due.sh 는 2.0 나노(명부 행 source=ft2-launch 또는 worktree 가 «/.fable-team/teams/» 아래)를
#   «닫기 차례» 에 넣지 않고 «제외 <좌석> ft2 나노 → keeper» 로만 남긴다(git·tmux 호출 전) · --approve-gate <ft2 좌석> = 같은 사유 rc 1 · 1.x 나노는 그대로.
#   임시 루트(TEAMS.md·명부·카드) + 좌석마다 임시 bare remote·clone + 가짜 tmux·ft-seat-status·git 래퍼(호출 기록) — 실 명부·우편함·tmux 0 · sleep 0.
#   T1 ft2(source+worktree) · T1b worktree 만 · T2 1.x = 기준판(① 갈래 뺀 사본) 같은 바이트 · T3 섞임 · T4 --approve-gate · 변이 M1(① 삭제) M2(worktree 조건 삭제).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
TOOL="${FT_CLOSE_DUE_UNDER_TEST:-$BIN/ft-nano-close-due.sh}"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
REALGIT="$(command -v git)"; S0=$(date +%s)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:500}";; *) ok "$3";; esac; }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got=[$1] want=[$2])"; fi; }
cmp -s "$BIN/ft-nano-close-due.sh" "$KIT/ft-nano-close-due.sh" && ok "cmp bin == kit" || bad "cmp bin != kit"

# ── 가짜 도구(호출 기록 = $T/calls) ──────────────────────────────────────────────────────────────
FK="$T/fake"; mkdir -p "$FK"
cat > "$FK/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "$FAKE_CALLS"
case "$1" in
  list-sessions) cat "$FAKE_SESS";;
  display-message) s="${4#=}"; s="${s%:}"; cat "$FAKE_CWD_DIR/$s";;
  *) exit 9;;
esac
EOF
cat > "$FK/git" <<EOF
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >> "\$FAKE_CALLS"
exec "$REALGIT" "\$@"
EOF
cat > "$FK/ft-seat-status.sh" <<'EOF'
#!/usr/bin/env bash
printf 'seat-status %s\n' "$*" >> "$FAKE_CALLS"
[ "${1:-}" = turn ] && { echo "IDLE - - - jsonl"; exit 0; }
exit 1
EOF
chmod +x "$FK/tmux" "$FK/git" "$FK/ft-seat-status.sh"
export FT_CLOSE_DUE_SEAT_STATUS="$FK/ft-seat-status.sh" FAKE_SESS="$T/sess" FAKE_CWD_DIR="$T/cwd" FAKE_CALLS="$T/calls"

# ── 픽스처 ─────────────────────────────────────────────────────────────────────────────────────────
ROOT=""
new_root() { ROOT="$T/root-$RANDOM"; rm -rf "$T/rem" "$T/wt" "$T/cwd"; mkdir -p "$ROOT/.fable-team/state" "$ROOT/design" "$T/rem" "$T/wt" "$T/cwd"
  : > "$T/sess"; : > "$T/rows.tsv"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| t1 | `design/teams/t1/` | byz-t1-master-claude | 현역 |\n' > "$ROOT/design/TEAMS.md"; }
mk() {   # <좌석> <slug> <source|-> <worktree 칸|-> — ff 착지·깨끗·IDLE·세트 = HEAD(착지 근거 다 섬)
  local seat="$1" slug="$2" rem="$T/rem/$2.git" wt="$T/wt/$2" m0 h
  git init -q --bare -b main "$rem"; git clone -q "$rem" "$wt" 2>/dev/null; git -C "$wt" checkout -q -b main
  git -C "$wt" commit -q --allow-empty -m M0; git -C "$wt" push -q origin main 2>/dev/null; m0="$(git -C "$wt" rev-parse HEAD)"
  git -C "$wt" checkout -q -b "nano/$slug"; git -C "$wt" commit -q --allow-empty -m work; h="$(git -C "$wt" rev-parse HEAD)"
  git -C "$wt" push -q origin "nano/$slug:main" 2>/dev/null; git -C "$wt" update-ref refs/remotes/origin/main "$m0"
  printf '%s\n' "$seat" >> "$T/sess"; printf '%s\n' "$wt" > "$T/cwd/$seat"
  mkdir -p "$ROOT/design/teams/t1/indices/진행"
  printf '# 인덱스: %s\n## 상태\n- 세트: %s · 시험: x rc=0\n' "$slug" "$h" > "$ROOT/design/teams/t1/indices/진행/$slug.md"
  printf '%s\t%s\t%s\t%s\n' "$seat" "design/teams/t1/indices/진행/$slug.md" "$3" "$4" >> "$T/rows.tsv"; }
fin() { python3 - "$ROOT" "$T/rows.tsv" <<'PY'
import json, sys
root, rows = sys.argv[1:3]
d = {"_master": "byz-t1-master-claude#1", "_cards": "design/teams/t1/indices"}
for ln in open(rows, encoding="utf-8"):
    s, idx, src, wt = ln.rstrip("\n").split("\t")
    d[s] = {"role": "nano", "agent": "pi", "index": idx, **({"source": src} if src != "-" else {}), **({"worktree": wt} if wt != "-" else {})}
json.dump(d, open(root + "/.fable-team/seats-t1.json", "w", encoding="utf-8"), ensure_ascii=False)
PY
}
run() { local tool="$1"; shift; : > "$T/calls"; OUT="$(PATH="$FK:$PATH" FT_ROOT="$ROOT" bash "$tool" "$@" 2>&1)"; RC=$?; }
seat_calls() { grep -v '^tmux list-sessions ' "$T/calls" | grep -c .; }
TW="$T/x/.fable-team/teams/t1/worktrees/x@a1"
FT2="byz-t1-nano-x#0"; ONE="byz-t1-nano-y#0"

# ── 기준판·변이 사본(같은 폴더에 import 짝) ─────────────────────────────────────────────────────────
mutdir() { local M="$T/m-$1"; rm -rf "$M"; mkdir -p "$M"; cp "$TOOL" "$M/ft-nano-close-due.sh"; cp "$BIN/ft_team_lib.py" "$BIN"/ft_nano_record*.py "$M/"
  python3 - "$M/ft-nano-close-due.sh" "$2" "$3" <<'PY' || bad "변이 자리 못 찾음 $1"
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
if s.count(old) != 1: sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
FT2LINE="$(grep -n 'r2021-mut:ft2' "$TOOL" | head -1 | cut -d: -f2-)"
mutdir M1 "$FT2LINE" ""
mutdir M2 ' or "/.fable-team/teams/" in str(row.get("worktree") or "")' ""

case_t1()  { new_root; mk "$FT2" x ft2-launch "$TW"; fin; }
case_t1b() { new_root; mk "$FT2" x - "$TW"; fin; }
case_t2()  { new_root; mk "$ONE" y - -; fin; }
case_t3()  { new_root; mk "$FT2" x ft2-launch "$TW"; mk "$ONE" y - -; fin; }
want_t1() {   # <tool> <이름>
  run "$1" --all --why
  eq "$(printf '%s\n' "$OUT" | grep -c '^닫기 차례 ')" "0" "$2 목록 0줄"
  eq "$(printf '%s\n' "$OUT" | grep -cxF "제외 $FT2 ft2 나노 → keeper")" "1" "$2 --why «제외 $FT2 ft2 나노 → keeper» 1줄"
  eq "$RC" "0" "$2 rc0(판정 불가 아님)"; eq "$(seat_calls)" "0" "$2 좌석 git·tmux·seat-status 호출 0"; }

echo "== T1 ft2 픽스처(source=ft2-launch · teams worktree)"; case_t1; want_t1 "$TOOL" T1
echo "== T1b source 없음 + teams worktree"; case_t1b; want_t1 "$TOOL" T1b
echo "== T2 1.x 픽스처 = 기준판 같은 바이트"
case_t2; run "$TOOL" --all --why; O2="$OUT"; R2=$RC; run "$T/m-M1/ft-nano-close-due.sh" --all --why
eq "$(printf '%s\n' "$O2" | grep -c "^닫기 차례 $ONE ")" "1" "T2 «닫기 차례 $ONE …» 1줄"
eq "$O2" "$OUT" "T2 출력 = 기준판(① 갈래 뺀 사본) 같은 바이트"; eq "$R2" "0" "T2 rc0"
echo "== T3 ft2 1석 + 1.x 1석"
case_t3; run "$TOOL" --all --why
eq "$(printf '%s\n' "$OUT" | grep -c '^닫기 차례 ')" "1" "T3 목록 1줄"; has "$OUT" "닫기 차례 $ONE " "T3 1.x 만"
eq "$(printf '%s\n' "$OUT" | grep -cxF "제외 $FT2 ft2 나노 → keeper")" "1" "T3 제외 1줄"
hasnt "$(cat "$T/calls")" "$FT2" "T3 ft2 좌석 이름으로 부른 바깥 호출 0"
echo "== T4 --approve-gate <ft2 좌석>"
case_t1; run "$TOOL" --approve-gate "$FT2"
eq "$RC" "1" "T4 rc1"; eq "$OUT" "제외 $FT2 ft2 나노 → keeper" "T4 제외 사유 1줄(APPROVE-REJECT 대신)"; eq "$(seat_calls)" "0" "T4 좌석 호출 0"

echo "== 변이"
m_fail() {   # <이름> <case> <검사> — 변이 사본에서 그 사례가 FAIL 이어야 시험이 잡는다
  local f0=$fail; "$2"; ( fail=0; TOOL="$T/m-$1/ft-nano-close-due.sh"; "$3" "$TOOL" "$1/$2" >/dev/null; exit $fail ); local r=$?
  fail=$f0; [ "$r" -gt 0 ] && ok "$1 변이 → $2 FAIL($r) = 시험이 잡는다" || bad "$1 변이 안 잡힘($2)"; }
t3_chk() { run "$1" --all --why; [ "$(printf '%s\n' "$OUT" | grep -c '^닫기 차례 ')" = 1 ] && ok x || bad "$2 목록 ≠ 1"; }
m_fail M1 case_t1 want_t1; m_fail M1 case_t3 t3_chk; m_fail M2 case_t1b want_t1
case_t1; want_t1 "$T/m-M2/ft-nano-close-due.sh" "M2 사본 T1(source 조건은 남음)"

echo "단계별 초: 전체=$(( $(date +%s) - S0 ))s"
echo "== 결과: FAIL=$fail"
exit $(( fail > 0 ? 1 : 0 ))
