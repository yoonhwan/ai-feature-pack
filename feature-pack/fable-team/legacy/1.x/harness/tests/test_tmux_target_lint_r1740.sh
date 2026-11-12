#!/usr/bin/env bash
# test_tmux_target_lint_r1740.sh — r1740: ft-tmux-target-lint.sh — pane 명령 `-t "=<이름>"`(끝 «:» 없음)을 잡는 착지 게이트 검사
#   반례 ①~⑥(카드 동결) + 변이 M1~M4(각 변이 뒤 원본으로 같은 사례 1회 더 = 반대 결과 대조) · 임시 git 리포 · 실 tmux 0 · sleep 0
#   ④ 뒤 절반은 ft-merge-land 사본을 실제로 돌린다(임시 origin(bare)+clone · gh 스텁 · 실 원격·실 push 0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(merge-land 의 CROSS 판정이 실 리포를 안 보게)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
BIN="$REPO/harness/bin"; SUT="$BIN/ft-tmux-target-lint.sh"; LAND="$BIN/ft-merge-land.sh"
fail=0; OUT=""; RC=0; T0=$SECONDS; step() { echo "단계 초 $1: $((SECONDS - T0))s"; }
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$RC out=${OUT:0:400}"; fail=$((fail+1)); fi; }
run() { local s="$1"; shift; OUT="$(bash "$s" "$@" 2>&1)"; RC=$?; }
has() { case "$OUT" in *"$1"*) return 0;; *) return 1;; esac; }
[ -f "$SUT" ] || { echo "FAIL ft-tmux-target-lint.sh 없음"; echo "(1 failed)"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ===== 사전: 문법 · 줄 수(≤120) · bin=kit 같은 판 =====
bash -n "$SUT" && bash -n "$LAND"; ck "사전 bash -n (lint·merge-land)" $?
[ "$(grep -c '' "$SUT")" -le 120 ]; ck "사전 줄 수 $(grep -c '' "$SUT") ≤ 120" $?
cmp -s "$SUT" "$BIN/../kit/fable-team/bin/ft-tmux-target-lint.sh" && cmp -s "$LAND" "$BIN/../kit/fable-team/bin/ft-merge-land.sh"; ck "사전 bin = kit 같은 판(cmp0)" $?
step "사전"

# ===== ① 파이썬 scan.sh:146 꼴 → ERR 1 =====
mkdir -p "$T/c"
printf '%s\n' 'def f(seat):' '    run(["tmux", "display-message", "-p", "-t", "=" + seat, "#{pane_current_path}"])' > "$T/c/py1.py"
run "$SUT" "$T/c/py1.py"
{ [ "$RC" = 1 ] && has "ERR $T/c/py1.py:2 tmux display-message" && has "ERR tmux-target 1"; }; ck "① 파이썬 «\"=\" + seat» → ERR 1(파일:줄 · 끝 «:» 없음)" $?

# ===== ② 셸 «=이름» 은 ERR · «=이름:» 은 0 · 파이썬 «+ \":\"» 은 0 =====
printf '%s\n' 'tmux capture-pane -p -t "=$NAME" -S -20' > "$T/c/sh2bad.sh"
run "$SUT" "$T/c/sh2bad.sh"; { [ "$RC" = 1 ] && has "ERR $T/c/sh2bad.sh:1 tmux capture-pane"; }; ck "② 셸 -t \"=\$NAME\" → ERR" $?
printf '%s\n' 'tmux capture-pane -p -t "=${NAME}:" -S -20' > "$T/c/sh2ok.sh"
run "$SUT" "$T/c/sh2ok.sh"; { [ "$RC" = 0 ] && [ "$OUT" = "OK tmux-target 0" ]; }; ck "② 셸 -t \"=\${NAME}:\" → 0" $?
printf '%s\n' 'run(["tmux", "capture-pane", "-p", "-t", "=" + seat + ":", "-S", "-20"])' > "$T/c/py2ok.py"
run "$SUT" "$T/c/py2ok.py"; { [ "$RC" = 0 ] && [ "$OUT" = "OK tmux-target 0" ]; }; ck "② 파이썬 «\"=\" + seat + \":\"» → 0" $?
step "①②"

# ===== ③ has-session·kill-session 은 «=이름» 이 맞다 → 0 =====
printf '%s\n' 'tmux has-session -t "=$S" 2>/dev/null' 'tmux kill-session -t "=$S" 2>/dev/null' > "$T/c/sh3.sh"
run "$SUT" "$T/c/sh3.sh"; { [ "$RC" = 0 ] && [ "$OUT" = "OK tmux-target 0" ]; }; ck "③ has-session·kill-session -t \"=\$S\" → 0" $?

# ===== ⑤ 주석은 보지 않는다 → 0 =====
printf '%s\n' '# tmux display-message -p -t "=$NAME" 는 has-session 에만 통한다' 'echo hi   # tmux send-keys -t "=$S" Enter' > "$T/c/sh5.sh"
run "$SUT" "$T/c/sh5.sh"; { [ "$RC" = 0 ] && [ "$OUT" = "OK tmux-target 0" ]; }; ck "⑤ 주석 줄·줄 끝 주석 속 꼴 → 0" $?
step "③⑤"

# ===== ⑥ 폴더 재귀(.sh·.py) + 실코퍼스에 pane 명령 위반 0 =====
mkdir -p "$T/c/corpus/sub"
printf '%s\n' 'echo ok' > "$T/c/corpus/a.sh"
printf '%s\n' 'tmux send-keys -t "=${S}" Enter' > "$T/c/corpus/sub/deep.py"
printf '%s\n' 'echo note' > "$T/c/corpus/skip.txt"
run "$SUT" "$T/c/corpus"
{ [ "$RC" = 1 ] && has "ERR $T/c/corpus/sub/deep.py:1 tmux send-keys" && has "ERR tmux-target 1" && ! has "skip.txt"; }; ck "⑥ 폴더 = 하위 폴더 *.sh·*.py 재귀(.txt 제외)" $?
run "$SUT" "$BIN" "$REPO/design/harness/evidence"
{ [ "$RC" = 0 ] || { has "ERR tmux-target" && ! has "tmux display-message " && ! has "tmux capture-pane " && ! has "tmux send-keys "; }; }; ck "⑥ 실코퍼스(pack bin + design/harness/evidence) — pane 명령 위반 0 (남은 ERR = 세션 대상 명령 · 카드 ⑥ 기대값 0 과 어긋남은 보고)" $?
step "⑥"

# ===== ④ --range 는 «추가된 줄» 만 · ft-merge-land 사본이 그 PR 을 거절 =====
. "$HERE/_merge_fixture.sh"
export FT_AUTONOMY_LEVEL=each
mkdir -p "$T/state" "$T/.fable-team"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_MERGE_DENY_FILE="$T/deny.txt"
printf '# 시험 목록(빈)\n' > "$T/deny.txt"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
body=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done
echo "$* :: $body" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
put() { mkdir -p "$(dirname "$W/$1")"; printf '%s\n' "$2" > "$W/$1"; }
pushpr() {
  git -C "$W" push -q -f origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":"feat: PR "+sys.argv[3],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "$1" > "$STUB_JSON"
}
mkpr() { local n="$1" b="$2"; shift 2; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "$b" origin/main
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "pr $n"; pushpr "$n" "$b"; }
land() { local s="$1"; shift; apv "$@"; : > "$STUB_LOG"; OUT="$(bash "$s" "$@" --repo "$W" 2>&1)"; RC=$?; }
mkrepo "$T"
put "bin/mix.sh" 'tmux display-message -p -t "=$OLD"'; cm "$W" "main: 옛 줄에 함정"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
git -C "$W" checkout -q -B c41 origin/main; printf '%s\n' 'echo ok' >> "$W/bin/mix.sh"; cm "$W" "pr 41"; pushpr 41 c41
run "$SUT" --range "origin/main..c41" --repo "$W"
{ [ "$RC" = 0 ] && [ "$OUT" = "OK tmux-target 0" ]; }; ck "④ --range: 옛 줄(함정)은 범위 밖 · PR 이 더한 줄만 봄 → 0" $?
mkpr 42 c42 'bin/bad.sh=tmux capture-pane -p -t "=$NAME"'; run "$SUT" --range "origin/main..c42" --repo "$W"
{ [ "$RC" = 1 ] && has "ERR bin/bad.sh:1 tmux capture-pane" && has "ERR tmux-target 1"; }; ck "④ --range: PR 이 함정 줄을 더하면 ERR 1" $?
land "$LAND" 42 --approve-sha "$PRSHA"
{ [ "$RC" = 1 ] && has "REJECT " && has "ERR bin/bad.sh:1" && [ "$(git -C "$ORIGIN" rev-parse main)" = "$(sha "$W" c42^)" ]; }; ck "④ ft-merge-land rc1 — 사유에 ERR 줄 · main 불변" $?
run "$SUT" "$T/nope.sh"; [ "$RC" = 2 ]; ck "④ 없는 파일 rc2(판정 불가)" $?
step "④"

# ===== 변이 M1~M4 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더) =====
mutl() { local d="$T/m-$1"; mkdir -p "$d"; cp "$SUT" "$d/ft-tmux-target-lint.sh"
  python3 - "$d/ft-tmux-target-lint.sh" "$2" "$3" <<'PY' || { echo "FAIL 변이 $1 대상 없음"; exit 1; }
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
assert old in s, "변이 대상 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  printf '%s' "$d/ft-tmux-target-lint.sh"; }
M1="$(mutl M1 'SAFE = ("has-session", "kill-session")' 'SAFE = ()')"
run "$M1" "$T/c/sh3.sh"; { [ "$RC" = 1 ] && has "ERR tmux-target 2"; }; ck "변이 M1(세션 명령 예외 삭제) → ③ FAIL 재현" $?
run "$SUT" "$T/c/sh3.sh"; { [ "$RC" = 0 ] && [ "$OUT" = "OK tmux-target 0" ]; }; ck "M1 대조: 원본은 ③ 0" $?
M2="$(mutl M2 '    return added(dif)' '    return file_srcs([p for p in git("diff", "--name-only", "--diff-filter=AM", f"{a}...{b}", "--", "*.sh", "*.py").splitlines() if p], b)')"
run "$M2" --range "origin/main..c41" --repo "$W"; { [ "$RC" = 1 ] && has "ERR bin/mix.sh:1"; }; ck "변이 M2(«추가된 줄만» → 파일 전체) → ④ 앞 절반 FAIL 재현" $?
run "$SUT" --range "origin/main..c41" --repo "$W"; { [ "$RC" = 0 ] && [ "$OUT" = "OK tmux-target 0" ]; }; ck "M2 대조: 원본은 ④ 앞 절반 0" $?
M3="$T/m-M3"; mkdir -p "$M3"; for f in "$BIN"/*; do ln -s "$f" "$M3/$(basename "$f")"; done; rm -f "$M3/ft-merge-land.sh"
python3 - "$LAND" "$M3/ft-merge-land.sh" <<'PY' || { echo "FAIL 변이 M3 대상 없음"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
sn = [l for l in s.split("\n") if "ft-tmux-target-lint.sh" in l and "rej" in l]
assert len(sn) == 1, sn
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sn[0] + "\n", "", 1))
PY
land "$M3/ft-merge-land.sh" 42 --approve-sha "$PRSHA"
{ [ "$RC" = 0 ] && has "LANDED pr=42 "; }; ck "변이 M3(merge-land 호출 줄 삭제) → ④ 뒤 절반 FAIL 재현(함정 PR 이 착지)" $?
M4="$(mutl M4 '    r = hit(code(text))' '    r = hit(text)')"
run "$M4" "$T/c/sh5.sh"; { [ "$RC" = 1 ] && has "ERR tmux-target 2"; }; ck "변이 M4(주석 건너뛰기 삭제) → ⑤ FAIL 재현" $?
run "$SUT" "$T/c/sh5.sh"; { [ "$RC" = 0 ] && [ "$OUT" = "OK tmux-target 0" ]; }; ck "M4 대조: 원본은 ⑤ 0" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh·실 tmux 0)" $?
step "변이"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
