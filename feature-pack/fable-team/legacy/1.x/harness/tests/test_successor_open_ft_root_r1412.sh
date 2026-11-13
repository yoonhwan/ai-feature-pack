#!/usr/bin/env bash
# test_successor_open_ft_root_r1412.sh — r1412: ft-successor-open 의 «데이터 루트» = env FT_ROOT 먼저(r1404 ft-role-spawn 과 같은 규칙)
#   K1 kakao 꼴(데이터 루트 = 깃 최상위 아래 하위 폴더) + FT_ROOT=<데이터 루트> → rc0 · arch 게이트·명부·mbox·도달 파일 = 데이터 루트
#   K2 BYZ 꼴 · FT_ROOT 없음 → 지금과 같음(공용 루트)
#   K3 FT_ROOT 에 .fable-team 없음 → REJECT rc1 · 부작용 0
#   K4 FT_RES_ROOT 와 FT_ROOT 둘 다 → 자원 게이트 손잡이(arch 게이트 루트) = FT_RES_ROOT · 명부·도달 파일 루트 = FT_ROOT
#   K5 kakao 꼴 · 데이터 루트 TEAMSET 에 kakao «arch 상시» + _arch 죽음 → 지금 규칙대로 REJECT(게이트가 열리기만 하는 게 아님)
# FT_SO_PATH=<경로> 로 «다른 판»(기준판·변이)을 같은 시험으로 돌린다 — 기본 = 팩 harness/bin/ft-successor-open.sh(옆 도구는 그 폴더 것).
# 전부 mktemp 안 — 가짜 tmux·tmuxc·pgrep·송신·mbox·reach·받을 일 판정·retire(PATH·env). 실 tmux·실 명부·실 쪽지 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROOT FT_MBOX_SH FT_MBOX_DIR FT_FT20_ROOT FT_SEAT_OPEN_WORK FT_SEAT_RETIRE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SO="${FT_SO_PATH:-$HERE/../bin/ft-successor-open.sh}"
[ -f "$SO" ] || { echo "REJECT 시험 대상 없음: $SO"; exit 2; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
FK="$T/fake"; LOG="$T/calls.log"; CNT="$T/pgrep.cnt"; OPENED="$T/opened"; mkdir -p "$FK"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$SO" && ok "bash -n 시험 대상($SO)" || bad "bash -n 시험 대상($SO)"
cmp -s "$HERE/../bin/ft-successor-open.sh" "$HERE/../kit/fable-team/bin/ft-successor-open.sh" \
  && ok "bin·kit 두 벌 같은 파일" || bad "bin·kit 두 벌이 다르다"

. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok; SENSORS="$T/sensors/fake-sensors"; RES="$FT_RES_ROOT"; unset FT_RES_ROOT
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FK/$1"; chmod +x "$FK/$1"; }
mkstub tmux  'case "$1" in has-session) [ -f "$OPENED" ] && exit 0; exit 1;; list-panes) echo 4242;; list-sessions) exit 0;; display-message) echo "$PANE_CWD";; esac; exit 0'
mkstub tmuxc 'echo "tmuxc $*" >> "$LOG"; : > "$OPENED"; exit 0'
mkstub pgrep 'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo 5555; exit 0'
mkstub send  'echo "send mbox=$FT_MBOX_SH" >> "$LOG"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit 0'
mkstub reach 'exit 0'
printf 'import os, sys\nopen(os.environ["LOG"], "a").write("openwork " + " ".join(sys.argv[1:]) + "\\n")\nsys.exit(1)\n' > "$FK/openwork"   # python3 로 불린다 · rc1 = 받을 일 있음(기존 승계 · 주제 밖)
mkstub retire 'exit 0'
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n' > "$T/body.txt"
printf '<!-- S17-BOOT-BEGIN -->\n목적 0 = 진행 카드를 완성하고 닫는다.\n<!-- S17-BOOT-END -->\n<!-- S11-DESK-BEGIN -->\n6. d\n<!-- S11-DESK-END -->\n' > "$T/gov.md"
teamset() { # teamset <파일> <kakao arch 칸> — ft_teamset.load 꼴(표 1 역할 · 나노 상한 · 표 2 팀)
  printf '## 표 1 — 역할\n| 역할 | 수 | 모델 | effort | 명부 키 |\n|---|---|---|---|---|\n| master | 1 | `m` | high | `_master` |\n| arch | 1 | `m` | high | `_arch` |\n- 나노 상한 기본: 3\n## 표 2 — 팀\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| kakao | 3 | 0 | %s |\n' "$2" > "$1"
}
teamset "$T/teamset-none.md" 없음; teamset "$T/teamset-arch.md" 상시
OLD='byz-kakao-master-claude#25'; NEW='byz-kakao-master-claude#26'

# data_root <폴더> — .fable-team(comm mbox·짝 파일 · state 원장·압력 표본) + design/TEAMS.md + 명부 seats-kakao.json(_master=OLD)
#   명부 이름 = 기본 규칙(seats-<팀>.json) — ft_teamset.roster_path 는 «명부» 칸을 읽지 않는다(이 카드 범위 밖 · 보고함). 시험 주제 = 루트 고르기.
data_root() {
  local d="$1"; mkdir -p "$d/.fable-team/comm" "$d/.fable-team/state" "$d/design"
  printf '#!/usr/bin/env bash\necho "mbox $1" >> "$LOG"; echo "RING seq=$3"\n' > "$d/.fable-team/comm/mbox.sh"; : > "$d/.fable-team/comm/mbox_doorbell.sh"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$d/.fable-team/state/all-stop.log"
  cp -p "$RES/.fable-team/state/pressure.tsv" "$d/.fable-team/state/"
  printf '| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n| kakao | `design/kakao/` | byz-kakao-master-claude | 현역 |\n' > "$d/design/TEAMS.md"
  printf '{"_master":"%s","_arch":"byz-kakao-arch-claude#3","%s":{"role":"master","agent":"claude","model":"m"}}\n' "$OLD" "$OLD" > "$d/.fable-team/seats-kakao.json"
}
# run <cwd> <wt> [KEY=VAL…] — 출력 $T/out · rc $RC · 호출마다 로그·표식 초기화
#   추가 대입(FT_ROOT·FT_RES_ROOT·FT_TEAMSET_MD)은 서브셸 export 로 env 줄 밖에서 — env 줄 = 글자 대입 + 글자 bash(비밀 분류기 env_strip)
run() {
  local cwd="$1" wt="$2"; shift 2; rm -f "$LOG" "$CNT" "$OPENED"; : > "$LOG"
  (cd "$cwd" || exit 1; export FT_TEAMSET_MD="$T/teamset-none.md"; for a in "$@"; do export "$a"; done
   env HOME="$T/home" PATH="$FK:$SENSORS:$PATH" LOG="$LOG" CNT="$CNT" OPENED="$OPENED" SENSORS="$SENSORS" PANE_CWD="$wt" \
     FT_SO_POLL=0 FT_SO_WAIT_MAX=2 FT_GOV_MD="$T/gov.md" FT_SEND_VERIFIED="$FK/send" \
     FT_REACH_CHECK="$FK/reach" FT_SEAT_OPEN_WORK="$FK/openwork" FT_SEAT_RETIRE="$FK/retire" FT_RECLAIM=0 \
     bash "$SO" "$OLD" "$wt" --name "$NEW" --agent claude --model m --body-file "$T/body.txt") > "$T/out" 2>&1
  RC=$?
}
cnt() { grep -c "^$1" "$LOG"; }
why() { echo "rc=$RC out=$(tail -n 3 "$T/out" | tr '\n' ' ') log=$(tr '\n' ' ' < "$LOG")"; }

# ── 픽스처 A: kakao 꼴 — 공용 루트 KA(.fable-team/state 만 · TEAMS.md 0) + 워크트리 WT + 데이터 루트 DR=<WT>/kakao ──
KA="$T/kakaobot"; WT="$KA/.worktrees/bootstrap"; DR="$WT/kakao"
mkdir -p "$KA/.fable-team/state"; cp -p "$RES/.fable-team/state/pressure.tsv" "$KA/.fable-team/state/"
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$KA/.fable-team/state/all-stop.log"
git init -q "$KA"; : > "$KA/README"; git -C "$KA" add README; git -C "$KA" -c user.email=t@t -c user.name=t commit -qm init
git -C "$KA" worktree add -q "$WT" -b bootstrap >/dev/null 2>&1
data_root "$DR"

# K1: FT_ROOT=<데이터 루트> → rc0 · 받을 일 판정·mbox·명부 선등록·도달 파일 = 데이터 루트 · 공용 루트 쓰기 0
run "$DR" "$WT" FT_ROOT="$DR/"
{ [ "$RC" = 0 ] && [ -f "$DR/.fable-team/state/successor/$OLD.json" ] && [ ! -e "$KA/.fable-team/state/successor" ] \
  && grep -q "^openwork $OLD --root $DR\$" "$LOG" && grep -q "^send mbox=$DR/.fable-team/comm/mbox.sh\$" "$LOG" \
  && grep -q "\"$NEW\"" "$DR/.fable-team/seats-kakao.json" && grep -q "mbox=$DR/.fable-team/comm/mbox.sh" "$T/out"; } \
  && ok "K1 kakao 꼴 + FT_ROOT=<데이터 루트>/ → rc0 · arch 게이트·명부·mbox·도달 파일 = 데이터 루트" || bad "K1 $(why)"

# K5: 같은 꼴 · 데이터 루트 TEAMSET 에 kakao «arch 상시» + _arch 죽음 → REJECT rc1 · 열기·송신 0
cp -p "$DR/.fable-team/seats-kakao.json" "$T/seats.k5.before"
run "$DR" "$WT" FT_ROOT="$DR" FT_TEAMSET_MD="$T/teamset-arch.md"
{ [ "$RC" = 1 ] && grep -q 'REJECT 그 팀 arch 좌석 없음' "$T/out" && grep -q 'byz-kakao-arch-claude#3 라이브 아님' "$T/out" \
  && [ "$(cnt tmuxc)" = 0 ] && [ "$(cnt send)" = 0 ] && cmp -s "$DR/.fable-team/seats-kakao.json" "$T/seats.k5.before"; } \
  && ok "K5 데이터 루트 «arch 상시» + _arch 죽음 → 지금 규칙대로 REJECT · 열기·송신·명부 쓰기 0" || bad "K5 $(why)"

# K3: FT_ROOT 에 .fable-team 없음 → REJECT rc1 · 부작용 0
mkdir -p "$T/nofable"; rm -rf "$DR/.fable-team/state/successor"; cp -p "$DR/.fable-team/seats-kakao.json" "$T/seats.k3.before"
run "$DR" "$WT" FT_ROOT="$T/nofable"
{ [ "$RC" = 1 ] && grep -q "REJECT FT_ROOT 에 .fable-team 없음: $T/nofable" "$T/out" && [ "$(cnt tmuxc)" = 0 ] && [ "$(cnt send)" = 0 ] \
  && [ "$(cnt openwork)" = 0 ] && [ ! -e "$DR/.fable-team/state/successor" ] && [ ! -e "$T/nofable/.fable-team" ] \
  && cmp -s "$DR/.fable-team/seats-kakao.json" "$T/seats.k3.before"; } \
  && ok "K3 FT_ROOT 에 .fable-team 없음 → REJECT rc1 · 열기·송신·판정·명부·도달 파일 0" || bad "K3 $(why)"

# K4: FT_RES_ROOT + FT_ROOT → arch 게이트 루트 = FT_RES_ROOT(명단 있음 → 통과) · 명부·도달 파일 = FT_ROOT
mkdir -p "$RES/design"; printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| t | `design/t/` | x | 현역 |\n' > "$RES/design/TEAMS.md"; printf '{}\n' > "$RES/.fable-team/seats-t.json"
rm -rf "$DR/.fable-team/state/successor"
run "$DR" "$WT" FT_ROOT="$DR" FT_RES_ROOT="$RES" FT_TEAMSET_MD="$T/teamset-arch.md"
{ [ "$RC" = 0 ] && [ -f "$DR/.fable-team/state/successor/$OLD.json" ] && [ ! -e "$RES/.fable-team/state/successor" ] \
  && grep -q "^send mbox=$DR/.fable-team/comm/mbox.sh\$" "$LOG"; } \
  && ok "K4 FT_RES_ROOT 이김(arch 게이트 = 자원 루트 명단 · kakao 상시 행 안 봄) · 도달 파일·mbox = FT_ROOT" || bad "K4 $(why)"
# K4': 자원 루트에 명단 없음 → arch 판정 실패가 «자원 루트» 경로를 말한다(데이터 루트 아님)
NR="$T/res-nomd"; mkdir -p "$NR/.fable-team/state"; cp -p "$RES/.fable-team/state/pressure.tsv" "$NR/.fable-team/state/"
run "$DR" "$WT" FT_ROOT="$DR" FT_RES_ROOT="$NR"
{ [ "$RC" = 1 ] && grep -q 'REJECT arch 판정 실패' "$T/out" && grep -q "$NR/design/TEAMS.md" "$T/out" && [ "$(cnt tmuxc)" = 0 ]; } \
  && ok "K4' 자원 루트 명단 없음 → arch 판정 실패 = 자원 루트 경로 · 열기 0" || bad "K4' $(why)"

# ── 픽스처 B: BYZ 꼴 — 한 리포 = 공용 루트 = 데이터 루트 · FT_ROOT 없음 ──
R="$T/byz"; data_root "$R"; git init -q "$R"
run "$R" "$R"
{ [ "$RC" = 0 ] && [ -f "$R/.fable-team/state/successor/$OLD.json" ] && grep -q "^openwork $OLD --root $R\$" "$LOG" \
  && grep -q "^send mbox=$R/.fable-team/comm/mbox.sh\$" "$LOG"; } \
  && ok "K2 BYZ 꼴 · FT_ROOT 없음 → 공용 루트(지금과 같음) · rc0" || bad "K2 $(why)"
run "$R" "$R" FT_TEAMSET_MD="$T/teamset-arch.md"
{ [ "$RC" = 1 ] && grep -q 'REJECT 그 팀 arch 좌석 없음' "$T/out" && [ "$(cnt tmuxc)" = 0 ]; } \
  && ok "K2' BYZ 꼴 · arch 게이트 = 공용 루트 명단(상시 + 죽음 → REJECT · 지금과 같음)" || bad "K2' $(why)"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
