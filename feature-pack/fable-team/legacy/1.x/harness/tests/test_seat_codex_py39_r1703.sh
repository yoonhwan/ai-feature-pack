#!/usr/bin/env bash
# test_seat_codex_py39_r1703.sh — r1703: ft_seat_codex.py 가 python 3.9 로 잡히는 셸에서도 import·판정된다(좌석 상태 판정이 «판정 불가» 로 빠지지 않게).
#   ① 3.9 `import ft_seat_codex` rc0 (기준판 = TypeError rc1)  ② 3.9 `--if-codex <명부 agent=pi>` rc3 · 출력 0 (기준판 = TypeError rc1)
#   ③ 가짜 rollout(task_started → task_complete 같은 turn_id) 3.9 판 출력 1행 = 3.14 판 출력 1행 (기준판 3.9 = TypeError)
#   ④ 3.14 로 ①~③ 같은 입력 → 기준판과 같은 rc·출력
#   변이(사본에서만 · 변이마다 원본 BIN 으로 같은 사례를 다시 돌려 반대 결과 대조): W1 future 줄 삭제 → ①·② FAIL · W2 future 줄을 함수 안으로 → ① FAIL
# 3.9 = /usr/bin/python3(3.9.6) · 없으면 SKIP rc0 · 가짜 tmux·명부·rollout 주입(FT_SEAT_CODEX_*) · 실 tmux·실 명부 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
PY39=/usr/bin/python3
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:200}"; fail=$((fail+1)); }
[ -x "$PY39" ] && "$PY39" -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 9) else 1)' 2>/dev/null \
  || { echo "SKIP python 3.9 없음(/usr/bin/python3) — ①~③ 판정 불가"; [ "$fail" = 0 ] && echo "ALL PASS"; exit 0; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
SEAT="byz-t-codex#0"; SID="0199aaaa-bbbb-cccc-dddd-eeeeffff0000"; CWD="$T/cwd"; mkdir -p "$CWD"
# 가짜 rollout — task_started 와 같은 turn_id 의 task_complete
R="$T/root/sessions/2026/11/11"; mkdir -p "$R"
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_started","turn_id":"T1","ts":"2026-11-11T23:00:00"}}' \
  '{"type":"event_msg","payload":{"type":"task_complete","turn_id":"T1","ts":"2026-11-11T23:00:07"}}' > "$R/rollout-2026-11-11T23-00-00-abc.jsonl"
# 가짜 명부(codex 좌석 / pi 좌석)
mkdir -p "$T/seats-codex/.fable-team" "$T/seats-pi/.fable-team"
printf '{"%s":{"agent":"codex"}}\n' "$SEAT" > "$T/seats-codex/.fable-team/seats-t.json"
printf '{"%s":{"agent":"pi"}}\n' "$SEAT" > "$T/seats-pi/.fable-team/seats-t.json"
cat > "$T/ps.sh" <<EOF
#!/bin/sh
printf '%s\n' "100 1 /bin/zsh" "200 100 /opt/homebrew/bin/codex"
EOF
cat > "$T/lsof.sh" <<EOF
#!/bin/sh
echo "p200"
echo "n$R/rollout-2026-11-11T23-00-00-abc.jsonl"
EOF
chmod +x "$T/ps.sh" "$T/lsof.sh"
run39() {  # run39 <도구경로> <인자…> — 3.9 로 실행(가짜 주입)
  OUT="$("$PY39" "$@" 2>&1)"; RC=$?
}
run39env() {  # run39env <도구경로> <cmd…>
  OUT="$(FT_SEAT_CODEX_PANE_PID=100 FT_SEAT_CODEX_PS="$T/ps.sh" FT_SEAT_CODEX_LSOF="$T/lsof.sh" FT_SEAT_CODEX_ROOT="$T/root/sessions" "$@" 2>&1)"; RC=$?
}
BASE="$T/base"; cp "$BIN/ft_seat_codex.py" "$BASE.py"   # 기준판 = 팩 origin/main 판(픽스처 사본)
git -C "$HERE/../../../../.." show 20b2beff4f8ea48c9e2082fe9a7eb63a3a0d6496:feature-pack/fable-team/legacy/1.x/harness/bin/ft_seat_codex.py > "$BASE.py" 2>/dev/null   # 기준판 = 고정 sha(고치기 직전 origin/main) && ok "기준판 사본 origin/main 판" || bad "기준판 사본" "git show 실패"
imp39() {  # imp39 <py 파일> — 3.9 import 1회
  OUT="$("$PY39" -c "import importlib.util,sys;spec=importlib.util.spec_from_file_location('c',sys.argv[1]);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)" "$1" 2>&1)"; RC=$?
}
# ── 기준판 대조(①~③ 이 빨강이어야 한다)
imp39 "$BASE.py"; [ "$RC" != 0 ] && ok "기준판 ① 3.9 import 실패(rc=$RC)" || bad "기준판 ①" "rc=$RC"
run39env "$PY39" "$BASE.py" --if-codex "$T/seats-pi" "$SEAT"; [ "$RC" != 3 ] && ok "기준판 ② 3.9 비codex 판정 실패(rc=$RC)" || bad "기준판 ②" "rc=$RC out=$OUT"
run39env "$PY39" "$BASE.py" "$SEAT"; B39="$OUT"; B39RC="$RC"
run39env python3 "$BASE.py" "$SEAT"; B14="$OUT"; [ "$B39" != "$B14" ] && ok "기준판 ③ 3.9·3.14 출력 다름" || bad "기준판 ③" "$B39"
# ── 고친 판
imp39 "$BIN/ft_seat_codex.py"; [ "$RC" = 0 ] && ok "① 3.9 import rc0" || bad "①" "rc=$RC $OUT"
run39env "$PY39" "$BIN/ft_seat_codex.py" --if-codex "$T/seats-pi" "$SEAT"
{ [ "$RC" = 3 ] && [ -z "$OUT" ]; } && ok "② 3.9 비codex 좌석 → rc3 · 출력 0" || bad "②" "rc=$RC out=$OUT"
run39env "$PY39" "$BIN/ft_seat_codex.py" "$SEAT"; G39="$OUT"; G39RC="$RC"
run39env python3 "$BIN/ft_seat_codex.py" "$SEAT"; G14="$OUT"; G14RC="$RC"
{ [ "$G39RC" = "$G14RC" ] && [ "$G39" = "$G14" ] && [ -n "$G39" ]; } && ok "③ 3.9 판 출력 = 3.14 판 출력($(printf '%s' "$G39" | cut -f1))" || bad "③" "39=[$G39] 14=[$G14]"
run39env python3 "$BASE.py" "$SEAT"; { [ "$RC" = "$G14RC" ] && [ "$OUT" = "$G14" ]; } && ok "④ 3.14 판 = 기준판과 같은 rc·출력" || bad "④" "base=[$OUT] new=[$G14]"
# ── 변이 W1·W2 (사본에서만 · 되돌림 후 원본 대조)
mut() {  # mut <이름> — 사본에 변이 적용
  R2="$T/m-$1"; mkdir -p "$R2"; cp "$BIN/ft_seat_codex.py" "$R2/c.py"
  python3 - "$R2/c.py" "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text(); k = sys.argv[2]
line = "from __future__ import annotations   # r1703: 3.9 에서도 import 되게(주석 평가 지연) — 동작 변화 0\n"
assert s.count(line) == 1, "변이 미적용: future 줄"
if k == "W1":
    s = s.replace(line, "")
else:   # W2 — 함수 안으로 옮긴다(문법상 import 는 def 안에서 SyntaxError)
    s = s.replace(line, "").replace("\ndef pane_pid(seat: str) -> str | None:\n", "\ndef pane_pid(seat: str) -> str | None:\n    " + line.strip() + "\n")
p.write_text(s)
PY
}
for w in W1 W2; do
  mut "$w"; imp39 "$T/m-$w/c.py"
  { [ "$RC" != 0 ] && case "$OUT" in *Error*) true;; *) false;; esac; } && ok "$w 변이 → ① 3.9 import 실패(변이 잡힘)" || bad "$w 변이" "rc=$RC out=$OUT"
  imp39 "$BIN/ft_seat_codex.py"; [ "$RC" = 0 ] && ok "$w 원본 대조: 원본은 3.9 import rc0" || bad "$w 원본 대조" "rc=$RC"
done
mut W1; run39env "$PY39" "$T/m-W1/c.py" --if-codex "$T/seats-pi" "$SEAT"
[ "$RC" != 3 ] && ok "W1 변이 → ② 3.9 비codex 판정 실패(변이 잡힘)" || bad "W1 ②" "rc=$RC"
cmp -s "$BIN/ft_seat_codex.py" "$BIN/../kit/fable-team/bin/ft_seat_codex.py" && ok "bin·kit cmp0" || bad "bin·kit 다름" ""
echo "단계 합계 ${SECONDS}s"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
