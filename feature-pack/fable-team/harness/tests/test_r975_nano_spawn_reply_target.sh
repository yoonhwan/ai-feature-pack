#!/usr/bin/env bash
# test_r975_nano_spawn_reply_target.sh — r975 r4(오빠 결정 3): ft-nano-spawn.sh 의 발주문 «회신(보고) 대상» 은
#   ★명부 파일(seats.json · 팀 env · FT_SEATS_JSON) 해석이 아니라 «지금 살아 있는 좌석 목록»(tmm ls byz-<팀>)★ 에서 고른다.
#   r1~r3 반례(예: 은퇴 좌석 승계 추적 · 명부 미지정 시 루트 팀장 · 상위 폴더 000 명부 건너뛰기)는 «그 입력» 이 사라져 재현 자체가 없어진다.
# 전부 mktemp — 임시 저장소·가짜 tmm/tmux/tmuxc·가짜 센서·가짜 회수·가짜 mbox. 실 좌석·실 워크트리·실 우편함·실 tmux 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
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
# tmm ls 스텁 — 목록 파일(FAKE_TMM_LIST)을 그대로 낸다 · FAKE_TMM_DELAY 면 /bin/sleep(진짜 지연) · FAKE_TMM_RC 면 그 rc
cat > "$T/fake/tmm" <<'EOF'
#!/usr/bin/env bash
[ -z "${FAKE_TMM_DELAY:-}" ] || /bin/sleep "$FAKE_TMM_DELAY"
[ -z "${FAKE_TMM_RC:-}" ] || exit "$FAKE_TMM_RC"
cat "$FAKE_TMM_LIST" 2>/dev/null
EOF
printf '#!/usr/bin/env bash\necho "{\\"number\\":1,\\"state\\":\\"OPEN\\",\\"url\\":\\"https://github.com/o/r/issues/1\\"}"\n' > "$T/fake/gh-open"
chmod +x "$T/fake/"*
printf '#!/bin/sh\nexit 0\n' > "$T/reclaim.sh"; chmod 755 "$T/reclaim.sh"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"

# ── 사본 bin(temp) + 스텁 ──
#   BINX = 빠른 칸용(ft-send-verified 스텁 = 넘겨받은 FT_SEND_FROM 을 기록) · SENDX = 실 ft-send-verified + 기록 mbox(계약 ④)
BINX="$T/bin"; cp -R "$KIT" "$BINX"; rm -rf "$BINX/__pycache__"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$2" > "%s/body.txt"; printf "%%s\\n" "${FT_SEND_FROM:-}" > "%s/sent-from.txt"; exit 0\n' "$T" "$T" > "$BINX/ft-send-verified.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/ft-agent-ready.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/ft-all-stop.sh"
chmod +x "$BINX/"*.sh
SENDX="$T/sendbin"; cp -R "$KIT" "$SENDX"; rm -rf "$SENDX/__pycache__"
printf '#!/usr/bin/env bash\necho 0\n' > "$SENDX/ft-reach-check.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SENDX/ft-agent-ready.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SENDX/ft-all-stop.sh"
chmod +x "$SENDX/"*.sh
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$3" > "%s/mbox-from.txt"\nprintf "%%s\\n" "$2" >> "%s/mbox-to.txt"\nexit 1\n' "$T" "$T" > "$T/fake-mbox.sh"   # 발신자·수신자를 기록하고 즉시 실패(도달 대기 없음)
chmod +x "$T/fake-mbox.sh"

TEAMX="harness"; CARDX="design/harness/indices/대기/x.md"
setteam() { TEAMX="$1"; CARDX="design/$1/indices/대기/x.md"; }
# tl <파일> <이름…> — tmm ls 출력 꼴(이름 = 3번째 칸)로 목록 파일을 만든다
tl() { local f="$1"; shift; : > "$f"; local n; for n in "$@"; do printf 'harne ● %s IDLE  fabl5·hi 09~14  0m harness-ops\n' "$n" >> "$f"; done; }
mkfix() {  # mkfix <디렉터리> — 카드·팀 env·등록용 명부(보고 대상 해석에는 «쓰이지 않는다»)
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/.fable-team/state" "$d/.fable-team/comm" "$d/.fable-team/bin-$TEAMX" \
    "$d/design/$TEAMX/indices/대기" "$d/design/$TEAMX/indices/진행" "$d/scripts"
  printf '#!/bin/sh\nexit 0\n' > "$d/scripts/real.sh"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$d/.fable-team/state/all-stop.log"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| %s | `design/%s/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' "$TEAMX" "$TEAMX" > "$d/design/TEAMS.md"
  mkdir -p "$d/design/v65"; echo x > "$d/design/v65/SEATBELT-README.md"
  printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > "$d/.fable-team/bin-$TEAMX/goal-lines.txt"
  printf '# GOAL — harness 제목줄\n\n## 원문 1 머리줄\n> %s\n' "$CLOSE" > "$d/design/$TEAMX/GOAL-harness.md"
  printf '# 인덱스: x\n- Issue: #1\n- 제안서: 없음 — 시험용 카드\n- 상태: 대기\n- 선행: 없음\n- 시험 입력: 없음\n- 기준값: 없음 → 대체 축 시험\n- 설치: 없음\n<!-- ledger: design/'"$TEAMX"'/GOAL-harness.md -->\n\n## 골 원문 (항상 이 3줄)\n%s\n%s\n%s\n\n## 골좌표\n닫는 증거: 「%s」\n\n## 배경\n시험.\n\n## 구현 범위\n1. `scripts/real.sh` 를 고친다.\n\n## 완료 조건\n- 시험 rc=0\n\n## 상태\n- 대기\n' \
    "$G1" "$G2" "$G3" "$CLOSE" > "$d/design/$TEAMX/indices/대기/x.md"
  printf '{"_version":"1.0.0","byz-harness-master-claude#1":{"role":"master"}}\n' > "$d/.fable-team/seats-$TEAMX.json"
  printf '{"_version":"1.0.0"}\n' > "$d/.fable-team/seats.json"
  printf "export FT_SEATS_JSON='%s/.fable-team/seats-%s.json'\nexport FT_NANO_PREFIX=byz-harness-nano-\nexport FT_NANO_WT_PREFIX=harness-\nexport FT_GOAL_LEDGER='design/harness/GOAL-harness.md'\nexport FT_GOAL_LINES_FILE='%s/.fable-team/bin-%s/goal-lines.txt'\n" "$d" "$TEAMX" "$d" "$TEAMX" > "$d/.fable-team/bin-$TEAMX/$TEAMX-env.sh"
  git init -q -b main "$d" && git -C "$d" -c user.name=t -c user.email=t@t add -A >/dev/null \
    && git -C "$d" -c user.name=t -c user.email=t@t commit -q -m init && git -C "$d" update-ref refs/remotes/origin/main HEAD
}
wts() { git -C "$1" worktree list | wc -l | tr -d ' '; }
EXTRA_ENV=()
sp() {  # sp <픽스처> <bindir> [인자…] — env -i 격리 · 카드 = CARDX
  #   ★매 spawn 마다 «열린 세션 없음» 상태로 되돌린다★ — 가짜 tmux 의 has-session 은 FAKE_OPENED 파일 존재로 참이 되고,
  #   그 상태로 남으면 spawn 의 «좌석 번호 찾기(while has-session)» 가 영원히 돈다(시험 자체의 함정 · 실 tmux 무관).
  local d="$1" bd="$2"; shift 2
  rm -f "$T/opened"
  ( cd "$d" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_RES_ROOT="$T/res" FT_SHEET_ROOT="$FT_SHEET_ROOT" \
      FT_ROOT="$d" FT_RECLAIM_SH="$T/reclaim.sh" FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" \
      FAKE_TMM_LIST="$T/tmm.lst" FAKE_TMM_RC="${FAKE_TMM_RC:-}" FAKE_TMM_DELAY="${FAKE_TMM_DELAY:-}" \
      ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} \
      bash "$bd/ft-nano-spawn.sh" "$CARDX" "$@" 2>&1 )
}
run1() { local d="$1"; shift; rm -f "$T/opened" "$T/body.txt" "$T/sent-from.txt"; mkpanes; sp "$d" "$BINX" "$@"; }
mkpanes() { printf 'byz-harness-nano-x#0|%%1|1\n' > "$T/panes"; }
one_line() { [ "$(printf '%s\n' "$1" | grep -c '^REJECT')" = 1 ] && [ "$(printf '%s\n' "$1" | grep -cE '^REJECT|^[[:space:]]+[^[:space:]]')" = 1 ]; }

for f in ft-nano-spawn.sh; do
  bash -n "$BIN/$f" && ok "bash -n 추적본 $f" || bad "bash -n 추적본 $f"
  cmp -s "$BIN/$f" "$KIT/$f" && ok "두 사본 cmp 0 $f" || bad "두 사본 불일치 $f"
done
[ "$(grep -c 'dispatch' "$BIN/ft-nano-spawn.sh")" = 0 ] && ok "«dispatch» 글자 0(추적본)" || bad "«dispatch» 글자가 남아 있다"
grep -q 'FT_SEND_FROM="\$FROM" bash "\$HERE/ft-send-verified.sh"' "$KIT/ft-nano-spawn.sh" && ok "발주문 송신 from = 선택된 \$FROM" || bad "발주문 송신이 \$FROM 을 안 쓴다"
# 계약 ① 방향: spawn 이 명부 파일을 «읽어» 보고 대상을 고르지 않는다(읽기 코드 0)
nroster="$(grep -nE '"_master"|_replaced_by' "$KIT/ft-nano-spawn.sh" | grep -vE '^[0-9]+:[[:space:]]*#' | wc -l | tr -d ' ')"
[ "$nroster" = 0 ] && ok "명부 파일 해석 코드 0(보고 대상은 tmm 목록)" || bad "명부 파일을 아직 읽는다(${nroster}줄)"

# ── ⓐ 목록에 현역 master 1명 → 그 이름이 보고 대상·발주문 머리·송신 from ──
D="$T/a"; mkfix "$D"; tl "$T/tmm.lst" byz-harness-master-claude#3 byz-harness-arch-claude#1 byz-harness-nano-x#0
o="$(run1 "$D")"; rc=$?
[[ "$o" == *"INFO 회신 대상 = byz-harness-master-claude#3"* ]] && ok "ⓐ 목록의 현역 master = 보고 대상" || bad "ⓐ $o"
[[ "$o" == *"[byz-harness-master-claude#3->"* ]] && ok "ⓐ 발주문 머리 = 선택 이름" || bad "ⓐ 머리 $o"
[ "$(cat "$T/sent-from.txt" 2>/dev/null)" = "byz-harness-master-claude#3" ] && ok "ⓐ 송신 from = 선택 이름(계약 ④)" || bad "ⓐ 송신 from = '$(cat "$T/sent-from.txt" 2>/dev/null)'"
{ [ "$rc" = 0 ] && [[ "$o" == *"SPAWNED"* ]]; } && ok "ⓐ 개설 rc=0" || bad "ⓐ rc=$rc $o"
# ⓐ-2 이름은 같은데 «옛 번호» 도 살아 있고 새 번호도 살아 있으면 = 2명(ⓑ) · 목록에 master 가 하나면 그 하나
tl "$T/tmm.lst" byz-harness-master-claude#7
o="$(run1 "$D")"
[[ "$o" == *"INFO 회신 대상 = byz-harness-master-claude#7"* ]] && ok "ⓐ-2 목록이 바뀌면 대상도 바뀐다(번호 하드코딩 0)" || bad "ⓐ-2 $o"

# ── ⓑ 현역 master 2명 → REJECT 1줄 + 목록 · 개설 0 ──
D="$T/b"; mkfix "$D"; tl "$T/tmm.lst" byz-harness-master-claude#3 byz-harness-master-claude#4
o="$(run1 "$D")"; rc=$?
{ [ "$rc" != 0 ] && one_line "$o" && [[ "$o" == *"#3"* ]] && [[ "$o" == *"#4"* ]] && [ "$(wts "$D")" = 1 ] && [ ! -f "$T/opened" ]; } \
  && ok "ⓑ 현역 master 2명 → REJECT 1줄 + 목록 · 개설 0" || bad "ⓑ rc=$rc $o"

# ── ⓒ 0명 · 빈 출력 · rc≠0 · 7초 초과 → REJECT · 개설 0 ──
D="$T/c"; mkfix "$D"
: > "$T/tmm.lst"; o="$(run1 "$D")"; rc=$?
{ [ "$rc" != 0 ] && one_line "$o" && [ ! -f "$T/opened" ]; } && ok "ⓒ 빈 출력 → REJECT 1줄 · 개설 0" || bad "ⓒ 빈 rc=$rc $o"
tl "$T/tmm.lst" byz-harness-arch-claude#1 byz-harness-nano-x#0; o="$(run1 "$D")"; rc=$?
{ [ "$rc" != 0 ] && one_line "$o" && [ "$(wts "$D")" = 1 ]; } && ok "ⓒ 목록에 master 0명 → REJECT 1줄" || bad "ⓒ 0명 rc=$rc $o"
o="$(FAKE_TMM_RC=7 run1 "$D")"; rc=$?
{ [ "$rc" != 0 ] && one_line "$o" && [ ! -f "$T/opened" ]; } && ok "ⓒ tmm rc≠0 → REJECT 1줄 · 개설 0" || bad "ⓒ rc≠0 rc=$rc $o"
t0="$(date +%s)"; o="$(FAKE_TMM_DELAY=20 run1 "$D")"; rc=$?; dt=$(( $(date +%s) - t0 ))
{ [ "$rc" != 0 ] && one_line "$o" && [ "$dt" -le 12 ] && [ ! -f "$T/opened" ]; } \
  && ok "ⓒ tmm 20초 지연 → 7초 상한에 끊고 REJECT(${dt}s)" || bad "ⓒ 지연 rc=$rc ${dt}s $o"

# ── ⓓ --from 이 목록 밖(은퇴 이름) → REJECT(승계 추적 0) ──
D="$T/d"; mkfix "$D"; tl "$T/tmm.lst" byz-harness-master-claude#4 byz-harness-arch-claude#1
o="$(run1 "$D" --from byz-harness-master-claude#3)"; rc=$?
{ [ "$rc" != 0 ] && one_line "$o" && [[ "$o" == *"목록에 없다"* ]] && [ ! -f "$T/opened" ]; } \
  && ok "ⓓ --from 은퇴 이름 → REJECT 1줄(후계로 바꾸지 않는다)" || bad "ⓓ rc=$rc $o"

# ── ⓔ --from 이 목록 안 → 그대로 ──
D="$T/e"; mkfix "$D"; tl "$T/tmm.lst" byz-harness-master-claude#4 byz-harness-arch-claude#1
o="$(run1 "$D" --from byz-harness-arch-claude#1)"
{ [[ "$o" == *"INFO 회신 대상 = byz-harness-arch-claude#1"* ]] && [ "$(cat "$T/sent-from.txt" 2>/dev/null)" = "byz-harness-arch-claude#1" ] && [[ "$o" == *"SPAWNED"* ]]; } \
  && ok "ⓔ --from 목록 안 → 그대로(송신 기록 일치)" || bad "ⓔ $o"
# ⓔ-2 다른 팀 좌석은 목록에 없다
o="$(run1 "$D" --from byz-v65-master-claude#2)"; rc=$?
{ [ "$rc" != 0 ] && one_line "$o"; } && ok "ⓔ-2 다른 팀 좌석 → REJECT 1줄" || bad "ⓔ-2 rc=$rc $o"

# ── ⓕ 팀 폴더 이름에 공백·한글 → 그 팀 접두로 tmm 목록을 읽는다 ──
setteam '하네스'; D="$T/f-1"; mkfix "$D"
tl "$T/tmm.lst" "byz-하네스-master-claude#3" "byz-하네스-arch-claude#1"
o="$(run1 "$D")"
{ [[ "$o" == *"INFO 회신 대상 = byz-하네스-master-claude#3"* ]] && [[ "$o" == *"SPAWNED"* ]]; } \
  && ok "ⓕ 한글 팀 → tmm ls byz-하네스 목록에서 고른다" || bad "ⓕ 한글 팀 $o"
# [범위 밖] 팀·좌석 이름에 «공백» 은 우리 도구가 만들지 않는다(하드 룰 18 결 · arch 161 판단 ⒝) —
#   목록 토큰은 공백으로 갈리므로 «공백 팀 접두» 는 매치될 수 없다. 그래도 조용히 다른 좌석을 고르지 않고 REJECT 1줄인지만 본다.
setteam 'harness team'; D="$T/f-2"; mkfix "$D"
tl "$T/tmm.lst" "byz-harness-master-claude#3"
o="$(run1 "$D")"; rc=$?
{ [ "$rc" != 0 ] && one_line "$o" && [ ! -f "$T/opened" ]; } \
  && ok "ⓕ 공백 팀 접두 → REJECT 1줄 · 개설 0([범위 밖] 이름에 공백 없음)" || bad "ⓕ 공백 팀 rc=$rc $o"
setteam harness

# ── 계약 ④ 실제 송신 도구 경유: 선택 이름 = mbox from/to ──
D="$T/g"; mkfix "$D"; tl "$T/tmm.lst" byz-harness-master-claude#3
rm -f "$T/mbox-from.txt" "$T/mbox-to.txt"; mkpanes
o="$(EXTRA_ENV=(FT_MBOX_SH="$T/fake-mbox.sh"); sp "$D" "$SENDX")"
[ "$(cat "$T/mbox-from.txt" 2>/dev/null)" = "byz-harness-master-claude#3" ] && ok "계약④ 실 ft-send-verified → mbox from = 선택 이름" || bad "계약④ from='$(cat "$T/mbox-from.txt" 2>/dev/null)' $o"
[ "$(cat "$T/mbox-to.txt" 2>/dev/null)" = "byz-harness-nano-x#0" ] && ok "계약④ mbox to = 이번 좌석" || bad "계약④ to='$(cat "$T/mbox-to.txt" 2>/dev/null)'"

# ── 변이 2종(계약 위반 단언 · 각 bash -n rc0 먼저) ──
mk_mut() { cp -R "$BINX" "$1"; python3 - "$1/ft-nano-spawn.sh" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old[:60]
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
# 변이 ① «목록 밖 이름을 고른다»(명부/하드코딩 값으로 대체 = r4 이전 방식) → 계약 위반: 목록에 없는 이름
M1="$T/mut1"; mk_mut "$M1" 'print(masters[0][1])' 'print("byz-harness-master-claude#1")   # 변이: 고정값(옛 방식)'
bash -n "$M1/ft-nano-spawn.sh" && ok "변이① bash -n rc0(실행 가능)" || bad "변이① bash -n 실패"
D="$T/m1"; mkfix "$D"; tl "$T/tmm.lst" byz-harness-master-claude#3
rm -f "$T/opened"; mkpanes
TO="$(command -v timeout || command -v gtimeout || true)"
o="$( cd "$D" && "$TO" 20 env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_RES_ROOT="$T/res" FT_SHEET_ROOT="$FT_SHEET_ROOT" \
      FT_ROOT="$D" FT_RECLAIM_SH="$T/reclaim.sh" FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" \
      FAKE_TMM_LIST="$T/tmm.lst" bash "$M1/ft-nano-spawn.sh" "$CARDX" --dry-run 2>&1 )"; rc=$?
if [ "$rc" = 124 ]; then ok "변이① 20초 안에 안 끝남(상한 소실) → 변이 검출(arch 161 ⒜)"
elif [[ "$o" == *"INFO 회신 대상 = byz-harness-master-claude#1"* ]]; then ok "변이① 목록 밖 이름을 골랐다 → 계약 위반 검출"
else bad "변이① 계약을 안 깼다(rc=$rc): $o"; fi

# 변이 ② «master 가 없으면 루트 팀장으로 대체»(조용한 대체 = 계약 ② 위반) → 목록에 없는 이름으로 개설
M2="$T/mut2"; mk_mut "$M2" 'if not masters:
    reject("목록에 byz-%s-master-* 좌석이 없다%s (목록: %s)" % (team, " — master 이름이 잘려 읽혔다" if cut_master else "", " ".join(sorted(names)) or "0명"))' 'if not masters:
    print("byz-v65-master-claude#2"); sys.exit(0)'
bash -n "$M2/ft-nano-spawn.sh" && ok "변이② bash -n rc0(실행 가능)" || bad "변이② bash -n 실패"
D="$T/m2"; mkfix "$D"; tl "$T/tmm.lst" byz-harness-arch-claude#1   # 살아 있는 좌석은 있지만 master 없음
rm -f "$T/opened"; mkpanes
# 변이 빌드는 «일부러 계약을 깬» 판이라 흐름이 무너져 끝나지 않을 수 있다 → 시험이 timeout 20 으로 감싸고
#   rc124 = 변이 검출로 센다(arch 161 ⒜ 와 같은 규칙). 계약 위반 자체는 위 ⓑ·ⓒ 칸이 이미 잰다.
o="$( cd "$D" && "$TO" 20 env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_RES_ROOT="$T/res" FT_SHEET_ROOT="$FT_SHEET_ROOT" \
      FT_ROOT="$D" FT_RECLAIM_SH="$T/reclaim.sh" FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" \
      FAKE_TMM_LIST="$T/tmm.lst" bash "$M2/ft-nano-spawn.sh" "$CARDX" --dry-run 2>&1 )"; rc=$?
if [ "$rc" = 124 ]; then ok "변이② 20초 안에 안 끝남 → 변이 검출(arch 161 ⒜)"
elif [ "$rc" = 0 ] && [[ "$o" == *"INFO 회신 대상 = byz-v65-master-claude#2"* ]]; then ok "변이② master 없음 → 루트 팀장 대체 = 계약② 위반 검출"
else bad "변이② 계약을 안 깼다(rc=$rc): $o"; fi

# ── /bin/bash 3.2.57 1회 ──
if /bin/bash --version | head -1 | grep -q '3\.2'; then
  D="$T/b32"; mkfix "$D"; tl "$T/tmm.lst" byz-harness-master-claude#3
  rm -f "$T/opened"; mkpanes
  o="$( cd "$D" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r \
        FT_TEAMSET=0 FT_RES_ROOT="$T/res" FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$D" FT_RECLAIM_SH="$T/reclaim.sh" \
        FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" FAKE_TMM_LIST="$T/tmm.lst" \
        /bin/bash "$BINX/ft-nano-spawn.sh" "$CARDX" --dry-run 2>&1 )"
  [[ "$o" == *"INFO 회신 대상 = byz-harness-master-claude#3"* ]] && ok "/bin/bash 3.2: 목록에서 고른다" || bad "/bin/bash 3.2: $o"
else echo "SKIP /bin/bash 3.2 칸 — 이 머신의 /bin/bash 가 3.2 가 아니다"; fi

[ "$(git -C "$REPO" config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare != false"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
