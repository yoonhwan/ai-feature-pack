#!/usr/bin/env bash
# test_teamset_roster_column_r1907.sh — r1907: ft_teamset.roster_path 가 TEAMS.md «명부» 칸을 따른다(ft_team_lib.roster_name 재사용).
#   ① 칸 = seats.json 인 팀 kk → arch-live 가 seats.json 을 읽어 OK ② 칸 빈 팀 → seats-<팀>.json ③ v65 → seats.json
#   ④ TEAMS.md 깨짐 → «판정 불가» rc≠0 · 명부 쓰기 0 · M1 옛 고정식 → ① FAIL. 전부 mktemp 안 · 가짜 tmux · 실 명부 0 · sleep 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_TEAMS_MD
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
R="$T/root"; F="$T/fake"; MD="$T/TEAMSET.md"; mkdir -p "$R/.fable-team" "$R/design" "$F"
printf '## 표 1\n| 역할 | 수 | 모델 | effort | 명부 키 |\n|---|---|---|---|---|\n| arch | 1 | `m` | high | `_arch` |\n- 나노 상한 기본: 3\n## 표 2\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| kk | 3 | 0 | 상시 |\n| solo | 3 | 0 | 상시 |\n| v65 | 3 | 0 | 상시 |\n' > "$MD"
printf '#!/bin/sh\nprintf "byz-kk-arch-claude#1\\nbyz-solo-arch-claude#1\\n"\n' > "$F/tmux"; chmod 755 "$F/tmux"
teams_ok() { printf '| 팀 | 폴더 | 상태 | 명부 |\n|---|---|---|---|\n| kk | `design/kk/` | 현역 | seats.json |\n| solo | `design/solo/` | 현역 | |\n| v65 | `design/v65/` | 현역 | |\n' > "$R/design/TEAMS.md"; }
seat() { printf '{"_arch":"%s"}\n' "$2" > "$R/.fable-team/$1"; }
run() { PATH="$F:$PATH" python3 "$1/ft_teamset.py" arch-live --root "$R" --md "$MD" --team "$2" 2>&1; }
cases() {  # cases <bin 폴더> — 칸마다 «이름 P|F 원문»
  local b="$1" o rc; rm -f "$R/.fable-team/"*; teams_ok
  seat seats.json "byz-kk-arch-claude#1"; o="$(run "$b" kk)"; rc=$?
  { [ $rc = 0 ] && [ "$o" = "OK kk" ]; } && echo "①a P $o" || echo "①a F rc=$rc $o"
  o="$(cd "$b" && python3 -c 'import ft_teamset as t, sys; print(t.roster_path(sys.argv[1], "kk"), t.read_roster(sys.argv[1], "kk")["_arch"])' "$R" 2>&1)"
  [ "$o" = "$R/.fable-team/seats.json byz-kk-arch-claude#1" ] && echo "①b P $o" || echo "①b F $o"
  seat seats-solo.json "byz-solo-arch-claude#1"; o="$(run "$b" solo)"; rc=$?
  { [ $rc = 0 ] && [ "$o" = "OK solo" ]; } && echo "② P $o" || echo "② F rc=$rc $o"
  seat seats.json "byz-v65-arch-claude#9"; o="$(run "$b" v65)"; rc=$?
  { [ $rc = 3 ] && [[ "$o" == "NO v65 arch 없음 — 명부 _arch byz-v65-arch-claude#9 라이브 아님"* ]]; } && echo "③ P" || echo "③ F rc=$rc $o"
  printf '| 팀 | 폴더 | 상태 | 명부 |\n|---|---|---|---|\n| kk | `design/kk/` | 현역 | a/b.json |\n' > "$R/design/TEAMS.md"
  local before; before="$(ls -l "$R/.fable-team" | md5)"; o="$(run "$b" kk)"; rc=$?
  { [ $rc != 0 ] && [[ "$o" == *"판정 불가 명부 이름"* ]] && [ "$before" = "$(ls -l "$R/.fable-team" | md5)" ]; } && echo "④ P $o" || echo "④ F rc=$rc $o"
}
python3 -m py_compile "$BIN/ft_teamset.py" && ok py_compile || bad py_compile
while read -r n st rest; do [ "$st" = P ] && ok "$n $rest" || bad "$n $rest"; done <<<"$(cases "$BIN")"
M="$T/mut"; mkdir -p "$M"; cp "$BIN"/*.py "$M/"   # M1 — 옛 고정식으로 되돌린 사본 → ① 이 FAIL 해야 한다
python3 - "$M/ft_teamset.py" <<'PY'
import sys; p = sys.argv[1]; s = open(p, encoding="utf-8").read(); old = 'Path(root) / ".fable-team" / roster_name(team, Path(root))'
assert old in s; open(p, "w", encoding="utf-8").write(s.replace(old, 'Path(root) / ".fable-team" / ("seats.json" if team == "v65" else f"seats-{team}.json")', 1))
PY
[ $? = 0 ] && grep -q "^①a F" <<<"$(cases "$M")" && ok "M1 옛 고정식 → ①a FAIL" || bad "M1 이 ① 을 못 잡는다(또는 대상 문자열 없음)"
cmp -s "$BIN/ft_teamset.py" "$KIT/ft_teamset.py" && ok "bin·kit cmp0" || bad "bin·kit 불일치"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"; exit $fail
