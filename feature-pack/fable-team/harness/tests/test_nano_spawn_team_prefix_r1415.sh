#!/usr/bin/env bash
# test_nano_spawn_team_prefix_r1415.sh — r1415: ft-nano-spawn.sh 가 좌석 집합·master 정규식·상한 팀 이름을 «byz-<팀>» 글자로
#   박지 않고 FT_NANO_PREFIX 의 «<접두>-nano-» 앞부분(<프로젝트>-<팀>) 한 값에서 푼다 — aifp-airag 처럼 byz- 가 아닌
#   프로젝트 팀의 나노 개설이 «보고 대상 0» 으로 막히는 일 0 · BYZ 팀(byz-<팀>-nano-)은 지금과 같은 문자열.
# 전부 mktemp — 임시 저장소·가짜 tmm/tmux/tmuxc·가짜 센서·가짜 회수. 실 좌석·실 워크트리·실 tmux·실 명부 0.
# 카드 흐름 게이트는 FT_CARD_FLOW=0 로 끈다(이 카드 범위 밖 · 그 칸의 팀 이름은 «카드 폴더 팀» 이라 접두 마지막 칸이 아니다).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'tmux_isolate_end; rm -rf "$T"' EXIT
. "$HERE/lib/tmux_isolate.sh"
. "$HERE/lib/fake_resource_env.sh"
fake_resource_env "$T/res" ok
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
G1='내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고.'
G2='하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.'
G3='메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.'
CLOSE='정본 문구 닫는증거는스무자이상이어야합니다 가나다라마바사'

# ── 가짜 도구(PATH 앞) — 실 tmux·실 tmuxc·실 tmm 을 절대 부르지 않는다 ──
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
printf '#!/usr/bin/env bash\necho "TMUXC $*"; case " $* " in *" --dry-run "*) ;; *) : > "$FAKE_OPENED";; esac\nexit 0\n' > "$T/fake/tmuxc"
printf '#!/bin/sh\nexit 0\n' > "$T/fake/sleep"
# tmm ls 스텁 — 목록 파일(FAKE_TMM_LIST) 그대로 · 부른 인자를 FAKE_TMM_ARGS 에 남긴다(접두 확인용)
cat > "$T/fake/tmm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_TMM_ARGS:-/dev/null}"
if [ "${1:-}" = ls ] && [ "${2:-}" = --names ]; then awk '{print $3}' "$FAKE_TMM_LIST" 2>/dev/null; exit 0; fi
cat "$FAKE_TMM_LIST" 2>/dev/null
EOF
printf '#!/usr/bin/env bash\necho "{\\"number\\":1,\\"state\\":\\"OPEN\\",\\"url\\":\\"https://github.com/o/r/issues/1\\"}"\n' > "$T/fake/gh-open"
chmod +x "$T/fake/"*
printf '#!/bin/sh\necho "RECLAIMED 1"\n' > "$T/reclaim.sh"
cat > "$T/reclaim-rec.sh" <<EOF
#!/bin/sh
echo "\$*" >> "$T/reclaim.calls"
echo "RECLAIMED 0"
EOF
chmod 755 "$T/reclaim.sh" "$T/reclaim-rec.sh"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"

# ── 사본 bin(temp) + 스텁 — 실 키트를 그대로 복사하고 필요한 형제 도구만 대역으로 바꾼다 ──
BINX="$T/bin"; cp -R "$KIT" "$BINX"; rm -rf "$BINX/__pycache__"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/ft-send-verified.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/ft-agent-ready.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/ft-all-stop.sh"
chmod +x "$BINX/"*.sh

GX_TEAM="aifp"; GX_PREFIX="aifp-airag-nano-"; CARDX="design/aifp/indices/대기/x.md"
# tl <이름…> — tmm ls 출력 꼴(이름 = 3번째 칸)
tl() { : > "$T/tmm.lst"; local n; for n in "$@"; do printf 'harne ● %s IDLE  fabl5·hi 09~14  0m harness-ops\n' "$n" >> "$T/tmm.lst"; done; }
mkfix() {  # mkfix <디렉터리> <팀> <접두> — 카드·팀 env·명부. 접두가 빈 문자열이면 env 에 FT_NANO_PREFIX 를 안 적는다(P4).
  local d="$1" tm="$2" px="$3"
  GX_TEAM="$tm"; CARDX="design/$tm/indices/대기/x.md"
  rm -rf "$d"; mkdir -p "$d/.fable-team/state" "$d/.fable-team/comm" "$d/.fable-team/bin-$tm" \
    "$d/design/$tm/indices/대기" "$d/design/$tm/indices/진행" "$d/scripts"
  printf '#!/bin/sh\nexit 0\n' > "$d/scripts/real.sh"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$d/.fable-team/state/all-stop.log"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| %s | `design/%s/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' "$tm" "$tm" > "$d/design/TEAMS.md"
  mkdir -p "$d/design/v65"; echo x > "$d/design/v65/SEATBELT-README.md"
  printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > "$d/.fable-team/bin-$tm/goal-lines.txt"
  printf '# GOAL — %s 제목줄\n\n## 원문 1 머리줄\n> %s\n' "$tm" "$CLOSE" > "$d/design/$tm/GOAL-$tm.md"
  printf '# 인덱스: x\n- Issue: #1\n- 제안서: 없음 — 시험용 카드\n- 상태: 대기\n- 선행: 없음\n- 시험 입력: 없음\n- 기준값: 없음 → 대체 축 시험\n- 설치: 없음\n<!-- ledger: design/'"$tm"'/GOAL-'"$tm"'.md -->\n\n## 골 원문 (항상 이 3줄)\n%s\n%s\n%s\n\n## 골좌표\n닫는 증거: 「%s」\n\n## 배경\n시험.\n\n## 구현 범위\n1. `scripts/real.sh` 를 고친다.\n\n## 완료 조건\n- 시험 rc=0\n\n## 계약↔시험 대응표\n| 계약 | 시험 |\n|---|---|\n| ① 팀 접두 | ⓐ |\n\n## 상태\n- 대기\n' \
    "$G1" "$G2" "$G3" "$CLOSE" > "$d/$CARDX"
  printf '{"_version":"1.0.0","%smaster-claude#1":{"role":"master"}}\n' "$(printf '%s' "$px" | sed 's/-nano-$//;s/-airag$/-/')" > "$d/.fable-team/seats-$tm.json"
  printf '{"_version":"1.0.0"}\n' > "$d/.fable-team/seats.json"
  { printf "export FT_SEATS_JSON='%s/.fable-team/seats-%s.json'\n" "$d" "$tm"
    [ -z "$px" ] || printf "export FT_NANO_PREFIX=%s\n" "$px"
    printf "export FT_GOAL_LEDGER='design/%s/GOAL-%s.md'\nexport FT_GOAL_LINES_FILE='%s/.fable-team/bin-%s/goal-lines.txt'\n" "$tm" "$tm" "$d" "$tm"
  } > "$d/.fable-team/bin-$tm/$tm-env.sh"
  git init -q -b main "$d" && git -C "$d" -c user.name=t -c user.email=t@t add -A >/dev/null \
    && git -C "$d" -c user.name=t -c user.email=t@t commit -q -m init && git -C "$d" update-ref refs/remotes/origin/main HEAD
}
sp() {  # sp <픽스처> [인자…] — env -i 격리 · BINX(사본 키트) · ★env 뒤는 글자 대입만 + 고정 명령(판정기 ft_secret_judge — 환경 추가는 대입 줄에 직접 쓴다)★
  local d="$1"; shift
  rm -f "$T/opened" "$T/tmm.args"; printf 'aifp-airag-nano-x#0|%%1|1\n' > "$T/panes"
  ( cd "$d" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_CARD_FLOW=0 FT_RES_ROOT="$T/res" \
      FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$d" FT_RECLAIM_SH="$T/reclaim-rec.sh" \
      FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" FAKE_TMM_LIST="$T/tmm.lst" FAKE_TMM_ARGS="$T/tmm.args" \
      bash "$BINX/ft-nano-spawn.sh" "$CARDX" "$@" 2>&1 )
}
wts() { git -C "$1" worktree list | wc -l | tr -d ' '; }

# ── 정적: 두 사본 동일 · 문법 ──
bash -n "$BIN/ft-nano-spawn.sh" && ok "bash -n 추적본" || bad "bash -n 추적본"
cmp -s "$BIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" && ok "bin·kit cmp 0" || bad "bin·kit 불일치"

# ── P1 aifp 팀: tmm 에 aifp-airag-master-claude#10 → 보고 대상 = 그 이름 · rc0(개설 계획까지) ──
D="$T/p1"; mkfix "$D" aifp "aifp-airag-nano-"; tl aifp-airag-master-claude#10
o="$(sp "$D" --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"INFO 회신 대상 = aifp-airag-master-claude#10"* ]]; } \
  && ok "P1 aifp → 보고 대상 = aifp-airag-master-claude#10 rc0" || bad "P1 rc=$rc $o"
grep -qx -- "ls --names aifp-airag" "$T/tmm.args" 2>/dev/null && ok "P1 tmm 인자 = ls --names aifp-airag(byz-aifp 아님)" || bad "P1 tmm 인자: $(tr '\n' '|' < "$T/tmm.args" 2>/dev/null)"

# ── P2 두 프로젝트 좌석이 섞여 있어도 aifp 쪽만 고른다 ──
D="$T/p2"; mkfix "$D" aifp "aifp-airag-nano-"; tl aifp-airag-master-claude#10 byz-airag-master-claude#3
o="$(sp "$D" --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"INFO 회신 대상 = aifp-airag-master-claude#10"* ]] && ! [[ "$o" == *"INFO 회신 대상 = byz-airag"* ]]; } \
  && ok "P2 섞인 목록에서도 aifp 쪽 master 선택" || bad "P2 rc=$rc $o"

# ── P3 BYZ 팀(byz-<팀>-nano-): 지금과 같은 결과 ──
D="$T/p3"; mkfix "$D" harness "byz-harness-nano-"; tl byz-harness-master-claude#3 byz-harness-arch-claude#1
o="$(sp "$D" --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"INFO 회신 대상 = byz-harness-master-claude#3"* ]]; } \
  && ok "P3 BYZ 팀 → byz-harness-master-claude#3 rc0(불변)" || bad "P3 rc=$rc $o"
grep -qx -- "ls --names byz-harness" "$T/tmm.args" 2>/dev/null && ok "P3 tmm 인자 = ls --names byz-harness(불변)" || bad "P3 tmm 인자: $(tr '\n' '|' < "$T/tmm.args" 2>/dev/null)"

# ── P4 접두 없음(기본) → 지금과 같음(byz-<팀>) ──
D="$T/p4"; mkfix "$D" harness ""; tl byz-harness-master-claude#3
o="$(sp "$D" --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"INFO 회신 대상 = byz-harness-master-claude#3"* ]]; } \
  && ok "P4 접두 없음 → byz-<팀> 기본값(불변)" || bad "P4 rc=$rc $o"

# ── P5 상한 팀 이름 = 접두의 마지막 칸 (aifp → airag · byz → harness) ──
CAPX="$T/bin-cap"; cp -R "$BINX" "$CAPX"
printf '#!/usr/bin/env python3\nimport sys\nprint("REJECT 좌석 3/2")\nsys.exit(1)\n' > "$CAPX/ft_seat_cap.py"
run_cap() {  # run_cap <픽스처> — 회수 인자를 기록하고 즉시 끝난다
  local d="$1"; rm -f "$T/reclaim.calls"
  ( cd "$d" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_CARD_FLOW=0 FT_RES_ROOT="$T/res" \
      FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$d" FT_RECLAIM_SH="$T/reclaim-rec.sh" \
      FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" FAKE_TMM_LIST="$T/tmm.lst" FAKE_TMM_ARGS="$T/tmm.args" \
      FT_TEAM_SEAT_CAP=2 \
      bash "$CAPX/ft-nano-spawn.sh" "$CARDX" 2>&1 )
}
D="$T/p5a"; mkfix "$D" aifp "aifp-airag-nano-"; tl aifp-airag-master-claude#10
printf 'aifp-airag-nano-x#0|%%1|1\n' > "$T/panes"; o="$(run_cap "$D")"
grep -q -- "--team airag" "$T/reclaim.calls" 2>/dev/null && ok "P5 aifp 상한 팀 이름 = airag" || bad "P5 상한 팀 이름: $(cat "$T/reclaim.calls" 2>/dev/null) $o"
grep -q -- "--caller aifp-airag-master-claude#10" "$T/reclaim.calls" 2>/dev/null && ok "P5 회수 --caller = 접두로 고른 master" || bad "P5 caller: $(cat "$T/reclaim.calls" 2>/dev/null)"
D="$T/p5b"; mkfix "$D" harness "byz-harness-nano-"; tl byz-harness-master-claude#3
printf 'byz-harness-nano-x#0|%%1|1\n' > "$T/panes"; o="$(run_cap "$D")"
grep -q -- "--team harness" "$T/reclaim.calls" 2>/dev/null && ok "P5 BYZ 상한 팀 이름 = harness(불변)" || bad "P5 BYZ 상한: $(cat "$T/reclaim.calls" 2>/dev/null) $o"

# ── 변이 3종 — 계약 위반 검출(문구 아님 · 각 bash -n rc0 먼저) ──
mk_mut() { cp -R "$BINX" "$1"; python3 - "$1/ft-nano-spawn.sh" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old[:70]
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
# 변이 ① 접두 함수가 늘 byz-<팀> (수정 전 = 기준판) → P1·P2 FAIL
M1="$T/m1"; mk_mut "$M1" "  case \"\$p\" in *-nano-) full=\"\${p%-nano-}\"; [ -n \"\$full\" ] && { printf '%s\\n' \"\$full\"; return 0; };; esac" "  :   # 변이①: 접두 해석 제거(수정 전과 같은 byz-<팀>)"
bash -n "$M1/ft-nano-spawn.sh" && ok "변이① bash -n rc0" || bad "변이① bash -n 실패"
mut_sp() { local m="$1" d="$2"; shift 2; ( cd "$d" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_CARD_FLOW=0 FT_RES_ROOT="$T/res" \
      FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$d" FT_RECLAIM_SH="$T/reclaim-rec.sh" \
      FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" FAKE_TMM_LIST="$T/tmm.lst" FAKE_TMM_ARGS="$T/tmm.args" \
      bash "$m/ft-nano-spawn.sh" "$CARDX" "$@" 2>&1 ); }
D="$T/mm1"; mkfix "$D" aifp "aifp-airag-nano-"; tl aifp-airag-master-claude#10
o="$(mut_sp "$M1" "$D" --dry-run)"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"보고 대상을 못 풀었다"* ]] && ! [[ "$o" == *"INFO 회신 대상 = aifp-airag"* ]]; } \
  && ok "변이① byz- 고정 = P1·P2 위반 검출(기준판 FAIL)" || bad "변이① 계약을 안 깼다(rc=$rc): $o"
D="$T/mm2"; mkfix "$D" aifp "aifp-airag-nano-"; tl aifp-airag-master-claude#10 byz-airag-master-claude#3
o="$(mut_sp "$M1" "$D" --dry-run)"; rc=$?
{ [ "$rc" != 0 ] && ! [[ "$o" == *"INFO 회신 대상 = aifp-airag"* ]]; } \
  && ok "변이① P2 도 위반 검출" || bad "변이① P2 계약을 안 깼다(rc=$rc): $o"
# 변이 ② master 정규식만 byz- 고정 → P1 FAIL(좌석은 찾는데 master 0명)
M2="$T/m2"; mk_mut "$M2" 'mpat = re.compile("^" + re.escape(pfx) + r"-master-[^#\s]+#([0-9]+)$")' 'mpat = re.compile(r"^byz-[a-z0-9]+-master-[^#\s]+#([0-9]+)$")   # 변이②: 정규식만 byz 고정'
bash -n "$M2/ft-nano-spawn.sh" && ok "변이② bash -n rc0" || bad "변이② bash -n 실패"
D="$T/mm3"; mkfix "$D" aifp "aifp-airag-nano-"; tl aifp-airag-master-claude#10
o="$(mut_sp "$M2" "$D" --dry-run)"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"master 좌석이 집합에 없다"* ]]; } \
  && ok "변이② 정규식 byz 고정 = P1 위반 검출" || bad "변이② 계약을 안 깼다(rc=$rc): $o"
# 변이 ③ 상한 파싱만 옛 sed(byz-) → P5 FAIL(팀 이름이 빈 값)
M3="$T/m3"; mk_mut "$M3" '  _capt="$(_nano_prefix_team)"' "  _capt=\"\$(printf '%s' \"\${FT_NANO_PREFIX:-}\" | sed -n 's/^byz-\\([a-z0-9]*\\)-nano-\$/\\1/p')\"   # 변이③: 옛 sed"
bash -n "$M3/ft-nano-spawn.sh" && ok "변이③ bash -n rc0" || bad "변이③ bash -n 실패"
CAPM="$T/m3"; cp -R "$BINX" "$T/m3cap"; cp "$M3/ft-nano-spawn.sh" "$T/m3cap/ft-nano-spawn.sh"
printf '#!/usr/bin/env python3\nimport sys\nprint("REJECT 좌석 3/2")\nsys.exit(1)\n' > "$T/m3cap/ft_seat_cap.py"
D="$T/mm4"; mkfix "$D" aifp "aifp-airag-nano-"; tl aifp-airag-master-claude#10; rm -f "$T/reclaim.calls"
o="$( cd "$D" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_CARD_FLOW=0 FT_RES_ROOT="$T/res" \
      FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$D" FT_RECLAIM_SH="$T/reclaim-rec.sh" \
      FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" FAKE_TMM_LIST="$T/tmm.lst" FT_TEAM_SEAT_CAP=2 \
      bash "$T/m3cap/ft-nano-spawn.sh" "$CARDX" 2>&1 )"
{ ! grep -q -- "--team airag" "$T/reclaim.calls" 2>/dev/null; } \
  && ok "변이③ 옛 sed = P5 위반 검출(팀 이름 빈 값)" || bad "변이③ 계약을 안 깼다: $(cat "$T/reclaim.calls" 2>/dev/null) $o"

[ "$(git -C "$REPO" config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare != false"
tmux_isolate_leak_check || fail=$((fail+1))
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
