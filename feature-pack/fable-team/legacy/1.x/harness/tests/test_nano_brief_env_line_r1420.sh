#!/usr/bin/env bash
# test_nano_brief_env_line_r1420.sh — r1420: 나노 첫 발주문에 «env 뒤 첫 낱말 = 글자 명령» 고정 줄 1개(BODY+ 셋째 자리 · _NFX 뒤).
#   계기: 나노 PR 767·768 이 scope-approve secret 으로 반송(ft_secret_judge UNKNOWN_CMD — 시험 env -i 블록 안 배열 펼침) 2회.
#   E1 --dry-run 발주문(claude·pi 두 에이전트) → «env 뒤 명령을 글자로» 줄 1개씩 · _WFX(r1299)·_NFX(r1305) 줄 바로 다음 자리
#      · ^BODY= 줄(실제 송신)에서도 ${_EVX} 가 ${_NFX} 바로 뒤
#   E2 줄 글자가 판정기 문구 «env 뒤 명령을 글자로» 를 포함하고 판정기 UNKNOWN_CMD 에도 그 문구가 있다(판정기 문구가 바뀌면 FAIL)
#   변이: ①줄 삭제 → E1 FAIL ②pi 분기에서만 빠짐 → E1 FAIL
#   꼴 = test_nano_spawn_team_prefix_r1415.sh(mktemp 픽스처 · 가짜 tmm/tmux/tmuxc · 실 좌석·실 tmux·실 명부 0).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
JUDGE="$BIN/ft_secret_judge.py"
PHRASE='env 뒤 명령을 글자로'
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'tmux_isolate_end; rm -rf "$T"' EXIT
. "$HERE/lib/tmux_isolate.sh"
. "$HERE/lib/fake_resource_env.sh"
fake_resource_env "$T/res" ok
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
for f in "$BIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" "$JUDGE"; do
  [ -f "$f" ] || { echo "판정 불가: 입력 파일 없음 $f"; exit 1; }
done
G1='내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고.'
G2='하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.'
G3='메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.'
CLOSE='정본 문구 닫는증거는스무자이상이어야합니다 가나다라마바사'

# ── 가짜 도구(PATH 앞) ──
mkdir -p "$T/fake"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) [ -f "$FAKE_OPENED" ]; exit $?;;
  list-panes) [ -f "$FAKE_OPENED" ] || exit 1; cat "$FAKE_PANES"; exit 0;;
  show-option) echo 1;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\necho "TMUXC $*"\nexit 0\n' > "$T/fake/tmuxc"
printf '#!/bin/sh\nexit 0\n' > "$T/fake/sleep"
cat > "$T/fake/tmm" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = ls ] && [ "${2:-}" = --names ]; then awk '{print $3}' "$FAKE_TMM_LIST" 2>/dev/null; exit 0; fi
cat "$FAKE_TMM_LIST" 2>/dev/null
EOF
printf '#!/usr/bin/env bash\necho "{\\"number\\":1,\\"state\\":\\"OPEN\\",\\"url\\":\\"https://github.com/o/r/issues/1\\"}"\n' > "$T/fake/gh-open"
chmod +x "$T/fake/"*
printf 'harne ● byz-harness-master-claude#3 IDLE  fabl5·hi 09~14  0m harness-ops\n' > "$T/tmm.lst"
printf 'byz-harness-nano-x#0|%%1|1\n' > "$T/panes"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"

mkbin() {  # mkbin <디렉터리> [spawn 원본] — 키트 사본 + 송신·준비·정지 대역
  cp -R "$KIT" "$1"; rm -rf "$1/__pycache__"
  [ -z "${2:-}" ] || cp "$2" "$1/ft-nano-spawn.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/ft-send-verified.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/ft-agent-ready.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/ft-all-stop.sh"
  chmod +x "$1/"*.sh
}
TM=harness; CARDX="design/$TM/indices/대기/x.md"
mkfix() {  # mkfix <디렉터리> — harness 팀 카드·env·명부 · git main
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/.fable-team/state" "$d/.fable-team/comm" "$d/.fable-team/bin-$TM" \
    "$d/design/$TM/indices/대기" "$d/design/$TM/indices/진행" "$d/scripts" "$d/design/v65"
  printf '#!/bin/sh\nexit 0\n' > "$d/scripts/real.sh"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$d/.fable-team/state/all-stop.log"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| %s | `design/%s/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' "$TM" "$TM" > "$d/design/TEAMS.md"
  echo x > "$d/design/v65/SEATBELT-README.md"
  printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > "$d/.fable-team/bin-$TM/goal-lines.txt"
  printf '# GOAL — %s 제목줄\n\n## 원문 1 머리줄\n> %s\n' "$TM" "$CLOSE" > "$d/design/$TM/GOAL-$TM.md"
  printf '# 인덱스: x\n- Issue: #1\n- 제안서: 없음 — 시험용 카드\n- 상태: 대기\n- 선행: 없음\n- 시험 입력: 없음\n- 기준값: 없음 → 대체 축 시험\n- 설치: 없음\n<!-- ledger: design/'"$TM"'/GOAL-'"$TM"'.md -->\n\n## 골 원문 (항상 이 3줄)\n%s\n%s\n%s\n\n## 골좌표\n닫는 증거: 「%s」\n\n## 배경\n시험.\n\n## 구현 범위\n1. `scripts/real.sh` 를 고친다.\n\n## 완료 조건\n- 시험 rc=0\n\n## 계약↔시험 대응표\n| 계약 | 시험 |\n|---|---|\n| ① 고정 줄 | E1 |\n\n## 상태\n- 대기\n' \
    "$G1" "$G2" "$G3" "$CLOSE" > "$d/$CARDX"
  printf '{"_version":"1.0.0","byz-harness-master-claude#1":{"role":"master"}}\n' > "$d/.fable-team/seats-$TM.json"
  printf '{"_version":"1.0.0"}\n' > "$d/.fable-team/seats.json"
  { printf "export FT_SEATS_JSON='%s/.fable-team/seats-%s.json'\nexport FT_NANO_PREFIX=byz-%s-nano-\n" "$d" "$TM" "$TM"
    printf "export FT_GOAL_LEDGER='design/%s/GOAL-%s.md'\nexport FT_GOAL_LINES_FILE='%s/.fable-team/bin-%s/goal-lines.txt'\n" "$TM" "$TM" "$d" "$TM"
  } > "$d/.fable-team/bin-$TM/$TM-env.sh"
  git init -q -b main "$d" && git -C "$d" -c user.name=t -c user.email=t@t add -A >/dev/null \
    && git -C "$d" -c user.name=t -c user.email=t@t commit -q -m init && git -C "$d" update-ref refs/remotes/origin/main HEAD
}
sp() {  # sp <bin> <에이전트> — dry-run 1회 · ★env 뒤 = 글자 대입 + 고정 명령 bash(이 카드의 규칙)★
  local b="$1" ag="$2" d="$T/fx-$RANDOM" raise=()
  [ "$ag" = pi ] || raise=(--raise "r1420 시험 — claude 갈래 발주문 비교")   # r1385: pi 가 아닌 나노 = 사유 필수
  mkfix "$d"
  ( cd "$d" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_CARD_FLOW=0 FT_RES_ROOT="$T/res" \
      FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$d" FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" FAKE_TMM_LIST="$T/tmm.lst" \
      bash "$b/ft-nano-spawn.sh" "$CARDX" --agent "$ag" ${raise[@]+"${raise[@]}"} --dry-run 2>&1 )
}
# e1 <라벨> <bin> <에이전트> — BODY+ 줄 순서: …_WFX(코드 파일 수) → _NFX(새 파일 모드) → env 줄 · env 줄 정확히 1개
e1() {
  local lbl="$1" out rc lines n iw in ie
  out="$(sp "$2" "$3")"; rc=$?
  [ "$rc" = 0 ] || { bad "E1 $lbl dry-run rc=$rc: $(printf '%s' "$out" | tail -3 | tr '\n' '|')"; return 0; }
  lines="$(printf '%s\n' "$out" | grep '^BODY+')"
  n="$(printf '%s\n' "$lines" | grep -c -F "$PHRASE")"
  [ "$n" = 1 ] || { bad "E1 $lbl «${PHRASE}» BODY+ 줄 ${n}개 (기대 1)"; return 0; }
  iw="$(printf '%s\n' "$lines" | grep -n -F '코드 파일 수 한도 없음(r1295·r1299)' | head -1 | cut -d: -f1)"
  in="$(printf '%s\n' "$lines" | grep -n -F '새 파일 모드(r1305)' | head -1 | cut -d: -f1)"
  ie="$(printf '%s\n' "$lines" | grep -n -F "$PHRASE" | head -1 | cut -d: -f1)"
  if [ -n "$iw" ] && [ -n "$in" ] && [ "$in" = "$((iw + 1))" ] && [ "$ie" = "$((in + 1))" ]; then
    ok "E1 $lbl env 줄 1개 · r1299·r1305 줄 바로 다음(BODY+ ${ie}번째)"
  else bad "E1 $lbl 자리 어긋남 (r1299=$iw r1305=$in env=$ie)"; fi
}
e1_body() {  # 실제 송신 BODY= 줄에서 ${_NFX}${_EVX} 이웃
  grep -m1 '^BODY=' "$1" | grep -q -F '${_NFX}${_EVX}' && ok "E1 $2 ^BODY= 줄 \${_NFX} 바로 뒤 \${_EVX}" || bad "E1 $2 ^BODY= 줄에 \${_NFX}\${_EVX} 없음"
}

bash -n "$BIN/ft-nano-spawn.sh" && ok "bash -n 추적본" || bad "bash -n 추적본"
cmp -s "$BIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" && ok "bin·kit cmp 0" || bad "bin·kit 불일치"
[ -x "$0" ] && bad "시험 파일 실행 비트(100644 이어야)" || ok "시험 파일 실행 비트 0"

BINX="$T/bin"; mkbin "$BINX"
e1 claude "$BINX" claude
e1 pi "$BINX" pi
e1_body "$BIN/ft-nano-spawn.sh" 추적본
e1_body "$KIT/ft-nano-spawn.sh" 키트

# ── E2 판정기 문구와 같은 말 ──
grep -q "^UNKNOWN_CMD = \".*$PHRASE" "$JUDGE" && ok "E2 판정기 UNKNOWN_CMD 에 «${PHRASE}»" || bad "E2 판정기 UNKNOWN_CMD 문구가 바뀜 — 발주문 줄과 맞출 것"
grep -m1 '^_EVX="' "$BIN/ft-nano-spawn.sh" | grep -q -F "$PHRASE" && ok "E2 _EVX 줄에 «${PHRASE}»" || bad "E2 _EVX 줄에 «${PHRASE}» 없음"

# ── 변이 — E1 이 FAIL 을 내야 한다 ──
mutate() {  # mutate <출력> <python 치환식 old> <new>
  python3 - "$BIN/ft-nano-spawn.sh" "$1" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old[:60]
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
mexpect() {  # mexpect <이름> <bin> <에이전트>
  local before="$fail" out
  out="$(e1 "$1" "$2" "$3")"; fail="$before"
  case "$out" in *"FAIL E1"*) ok "변이 $1 → E1 FAIL(기대)";; *) bad "변이 $1 인데 E1 이 통과: $out";; esac
}
mutate "$T/m1.sh" 'echo "BODY+${_EVX}"'$'\n' ''
M1="$T/bm1"; mkbin "$M1" "$T/m1.sh"; mexpect "①줄 삭제(claude)" "$M1" claude
mutate "$T/m2.sh" 'echo "BODY+${_EVX}"' '[ "$AGENT" = pi ] || echo "BODY+${_EVX}"'
M2="$T/bm2"; mkbin "$M2" "$T/m2.sh"; mexpect "②pi 분기만 빠짐" "$M2" pi
b="$fail"; o="$(e1 "②claude 는 그대로" "$M2" claude)"; fail="$b"
case "$o" in *"PASS E1"*) ok "변이② claude 갈래는 통과(분기만 잡는다)";; *) bad "변이② claude 갈래도 FAIL: $o";; esac

tmux_isolate_leak_check || fail=$((fail+1))
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
