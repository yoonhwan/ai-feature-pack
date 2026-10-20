#!/usr/bin/env bash
# test_planner_nano_path.sh — P2 r-planner-nano-path: planner 임시 나노 경로
#   ⓐ골 3줄 txt(FT_GOAL_LINES_FILE) 로 판정 1151 꼴 카드 lint OK · 옛 env(GOAL-planner.md 전체)는 REJECT
#   ⓑspawn --dry-run: 접두·명부·카드 경로·골 3줄 lint OK  ⓒ빈 카드 템플릿(planner 한정) + 변이 2종  ⓓ발주 BODY 팀 구조 1문장(전 팀)  ⓔ기존 시험 rc=0
# 임시 git 리포 + 가짜 tmux/tmuxc/sleep(PATH 앞) + 스크립트 사본만 쓴다 — 실 리포·seats·tmux·Redis 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../harness/kit/fable-team"; SRC="$KIT/bin"; TXT="$KIT/bin-planner/goal-lines-planner.txt"; ENVSRC="$KIT/bin-planner/planner-env.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok   # R218: 자원 문지기 센서를 가짜로(실 머신 부하·압력 무관)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

for f in ft-nano-spawn.sh ft-index-lint.sh; do bash -n "$SRC/$f" || bad "bash -n $f"; done
[ "$(wc -l < "$TXT" 2>/dev/null | tr -d ' ')" = 3 ] && ok "goal-lines-planner.txt 3줄" || bad "goal-lines-planner.txt 가 3줄이 아니다: $TXT"
[ -f "$ENVSRC" ] && ok "planner-env.sh 추적 사본 실재" || bad "planner-env.sh 추적 사본 없음: $ENVSRC"
G1="$(sed -n 1p "$TXT")"; G2="$(sed -n 2p "$TXT")"; G3="$(sed -n 3p "$TXT")"

# ── 임시 리포 · 사본 bin · 가짜 도구
BIN="$T/bin"; BIN2="$T/bin-stublint"; mkdir -p "$BIN" "$T/fake" "$T/comm/bodies"
for f in ft-nano-spawn.sh ft-index-lint.sh ft-index-lint-install.sh ft-proposal-gate.sh ft-index-move.sh ft-sheet-events.sh ft_sheet_events.py ft_sheet_confirm.py ft_sheet_key.py ft_board_env.py ft_board_mail.py ft-nano-cherry-gate.sh ft-nano-spawn-undo.sh ft-resource-gate.sh ft_raised.py ft_teamset.py ft_spawn_queue.py ft-team-lib.sh; do cp "$SRC/$f" "$BIN/" 2>/dev/null; done
printf '#!/usr/bin/env bash\necho "$2" > "%s/body.txt"; exit 0\n' "$T" > "$BIN/ft-send-verified.sh"   # 발주 BODY 를 잡는다
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-agent-ready.sh"   # R251 필수 형제 — 기동 확인 자체는 test_spawn_agent_ready.sh 가 본다
cp -R "$BIN" "$BIN2"; printf '#!/usr/bin/env bash\necho "OK stub-lint $1"; exit 0\n' > "$BIN2/ft-index-lint.sh"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) [ -f "$FAKE_OPENED" ]; exit $?;;
  list-panes) [ -f "$FAKE_OPENED" ] || exit 1; cat "$FAKE_PANES"; exit 0;;
  show-option) echo 1;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\necho "TMUXC $*"; case " $* " in *" --dry-run "*) ;; *) : > "$FAKE_OPENED";; esac\n' > "$T/fake/tmuxc"
printf '#!/bin/sh\nexit 0\n' > "$T/fake/sleep"; chmod +x "$BIN/"* "$BIN2/"* "$T/fake/"*

REPO="$T/repo"; mkdir -p "$REPO"
mkdir -p "$REPO/design"; printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| planner | `design/planner/` | p | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$REPO/design/TEAMS.md"   # R383: spawn·설치 게이트가 팀 폴더 명단을 읽는다
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$REPO/.fable-team/bin-planner" "$REPO/design/planner/indices/대기" "$REPO/design/planner/indices/진행" "$REPO/design/v65/indices/대기" "$REPO/scripts"
cp "$TXT" "$REPO/.fable-team/bin-planner/goal-lines-planner.txt"
sed "s#/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents#$REPO#g" "$ENVSRC" > "$REPO/.fable-team/bin-planner/planner-env.sh"
mkdir -p "$REPO/.fable-team/bin-harness"   # 하네스 팀 env — 골 줄·원장은 planner 시험 카드와 같은 값(⑤ 가 «유일한» REJECT 사유가 되도록)
printf 'export FT_SEATS_JSON=%s/.fable-team/seats-harness.json\nexport FT_NANO_PREFIX=byz-harness-nano-\nexport FT_NANO_WT_PREFIX=harness-\nexport FT_GOAL_LEDGER=design/planner/GOAL-planner.md\nexport FT_GOAL_LINES_FILE=%s/.fable-team/bin-planner/goal-lines-planner.txt\n' "$REPO" "$REPO" > "$REPO/.fable-team/bin-harness/harness-env.sh"; echo '{}' > "$REPO/.fable-team/seats-harness.json"
echo '{}' > "$REPO/.fable-team/seats-planner.json"; echo '{}' > "$REPO/.fable-team/seats.json"; echo x > "$REPO/scripts/real.sh"
# 정본(GOAL-planner.md) — 제목줄·빈 줄·머리줄이 1~3행(옛 env 가 파일 전체를 골 3줄로 읽던 꼴) + 골좌표 닫는 증거 문구
printf '# GOAL — planner 제목줄\n\n## 원문 1 머리줄\n> 정본 문구 닫는증거는스무자이상이어야합니다 가나다라마바사\n' > "$REPO/design/planner/GOAL-planner.md"
CLOSE='정본 문구 닫는증거는스무자이상이어야합니다 가나다라마바사'
card() {  # card <경로> <머리 추가줄> <구현 범위 본문> <완료 조건 본문>
  printf '# 인덱스: x\n- Issue: 없음\n- 제안서: 없음 — 시험용 카드\n- 상태: 대기\n- 선행: 없음\n- 시험 입력: 없음\n- 기준값: 없음 → 대체 축 시험\n%s\n\n## 골 원문 (항상 이 3줄)\n%s\n%s\n%s\n\n## 골좌표\n닫는 증거: 「%s」\n\n## 배경\n시험.\n\n## 구현 범위\n%s\n\n## 완료 조건\n%s\n\n## 상태\n- 대기\n' "$2" "$G1" "$G2" "$G3" "$CLOSE" "$3" "$4" > "$1"
}
FULL_IMPL='1. `scripts/real.sh` 를 고친다.'; FULL_DONE='- 시험 rc=0'
card "$REPO/design/planner/indices/대기/full.md" '<!-- ledger: design/planner/GOAL-planner.md -->' "$FULL_IMPL" "$FULL_DONE"
card "$REPO/design/planner/indices/대기/tpl.md" '<!-- ledger: design/planner/GOAL-planner.md -->
- 템플릿: 빈 카드(나노가 채움)' '' ''
card "$REPO/design/planner/indices/대기/empty.md" '<!-- ledger: design/planner/GOAL-planner.md -->' '' ''
card "$REPO/design/planner/indices/대기/bodyp.md" '<!-- ledger: design/planner/GOAL-planner.md -->' "$FULL_IMPL" "$FULL_DONE"   # ⓓ 전용(ⓒ 가 쓴 카드는 진행/ 으로 이동했다)
card "$REPO/design/v65/indices/대기/v65card.md" '' "$FULL_IMPL" "$FULL_DONE"
echo x > "$REPO/design/v65/SEATBELT-README.md"   # R406: 발주 본문 README = 명단 ref 의 v65 폴더에 실재 1개
mkdir -p "$REPO/design/harness/indices/대기"; cp "$REPO/design/planner/indices/대기/tpl.md" "$REPO/design/harness/indices/대기/tpl.md"
GIT add -A >/dev/null; GIT commit -q -m cards
GIT update-ref refs/remotes/origin/main HEAD

run()  { ( cd "$REPO" && env -i FT_TEAMSET=0 FT_RES_ROOT="$FT_RES_ROOT" HOME="$HOME" LC_ALL=en_US.UTF-8 FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" "$@" 2>&1 ); }
lint() { ( cd "$REPO" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$PATH" "$@" 2>&1 ); }
LINT="$BIN/ft-index-lint.sh"
spawn() { local bindir="$1"; shift; rm -f "$T/opened" "$T/body.txt"; run bash "$bindir/ft-nano-spawn.sh" "$@"; }
real() {  # real <bindir> <카드> — 실 spawn(가짜 도구) · 좌석 이름은 카드 slug 에서
  local slug; slug="$(basename "$2" .md)"; printf 'byz-planner-nano-%s#0|%%1|1\nft-v65-temp-%s#0|%%2|1\n' "$slug" "$slug" > "$T/panes"
  spawn "$1" "$2" --base HEAD
}

echo "== ⓐ 골 3줄 파일 · 판정 1151 꼴 카드 lint"
out="$(lint FT_GOAL_LEDGER=design/planner/GOAL-planner.md FT_GOAL_LINES_FILE="$REPO/.fable-team/bin-planner/goal-lines-planner.txt" bash "$LINT" "$REPO/design/planner/indices/대기/full.md")"
has "$out" "OK " "골 3줄 txt 로 lint OK"
out="$(lint FT_GOAL_LEDGER=design/planner/GOAL-planner.md FT_GOAL_LINES_FILE="$REPO/design/planner/GOAL-planner.md" bash "$LINT" "$REPO/design/planner/indices/대기/full.md")"
has "$out" "REJECT" "옛 env(GOAL-planner.md 전체) 는 REJECT(재현)"
has "$out" "골 1줄 불일치" "  └ 사유 = 제목줄이 골 1줄로 읽힘"
grep -q "FT_GOAL_LINES_FILE=.*bin-planner/goal-lines-planner.txt" "$ENVSRC" && ok "planner-env.sh 의 FT_GOAL_LINES_FILE = goal-lines-planner.txt" || bad "planner-env.sh 의 FT_GOAL_LINES_FILE 이 txt 가 아니다"
V6GOAL="/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/design/planner/GOAL-planner.md"
if [ -f "$V6GOAL" ]; then n=0; for g in "$G1" "$G2" "$G3"; do grep -qxF -- "> $g" "$V6GOAL" && n=$((n+1)); done; [ "$n" = 3 ] && ok "txt 3줄 = GOAL-planner.md 원문 줄(\"> \" 제거) 바이트 일치" || bad "txt 3줄 중 $n 줄만 GOAL-planner.md 원문과 일치"; else echo "SKIP 골 정본 대조 — $V6GOAL 없음"; fi

echo "== ⓑ spawn --dry-run 4값"
out="$(spawn "$BIN" design/planner/indices/대기/full.md --dry-run)"
has "$out" "ENV team=planner prefix=byz-planner-nano- seats=$REPO/.fable-team/seats-planner.json" "접두 byz-planner-nano- · 명부 seats-planner.json"
has "$out" "OK design/planner/indices/대기/full.md" "골 3줄 txt 로 lint OK(카드 경로 design/planner/indices/대기/)"
has "$out" "PLAN seat=byz-planner-nano-full#0" "PLAN 좌석 접두"

echo "== ⓒ 빈 카드 템플릿"
out="$(spawn "$BIN" design/planner/indices/대기/tpl.md --dry-run)"
has "$out" "(empty-body allowed)" "템플릿 줄 + planner → lint OK (empty-body allowed)"
has "$out" "PLAN seat=byz-planner-nano-tpl#0" "  └ PLAN 까지 도달"
out="$(real "$BIN" design/planner/indices/대기/tpl.md)"; has "$out" "SPAWNED" "템플릿 카드 실 spawn(가짜 도구) 통과"
body="$(cat "$T/body.txt" 2>/dev/null)"; has "$body" "카드 구현 범위·완료 조건 절을 네가 먼저 채우고 arch 1줄 확인 뒤 착수" "발주 BODY 에 「먼저 채우고 arch 확인」 문장"
out="$(spawn "$BIN" design/harness/indices/대기/tpl.md --dry-run)"; has "$out" "절 비어 있음" "같은 카드를 하네스 팀 경로로 → REJECT(⑤ 그대로)"; hasnt "$out" "(empty-body allowed)" "  └ 하네스 팀은 empty-body 허용 표시 0"
out="$(spawn "$BIN" design/planner/indices/대기/empty.md --dry-run)"; has "$out" "REJECT" "템플릿 줄 없이 빈 본문 → planner 도 REJECT"; has "$out" "절 비어 있음" "  └ 사유 = 구현 범위·완료 조건 비어 있음"
# DA⑥ H1 회귀 — 상속된 FT_INDEX_ALLOW_EMPTY_BODY=1 이 다른 팀·템플릿 줄 없는 카드의 ⑤⑥ 을 우회하면 안 된다
out="$(run FT_INDEX_ALLOW_EMPTY_BODY=1 bash "$BIN/ft-nano-spawn.sh" design/harness/indices/대기/tpl.md --dry-run)"; has "$out" "절 비어 있음" "상속 env=1 + 하네스 팀 빈 카드 → ⑤ REJECT(spawn 이 명시 초기화)"; hasnt "$out" "(empty-body allowed)" "  └ 하네스 팀 empty-body 허용 표시 0"
out="$(run FT_INDEX_ALLOW_EMPTY_BODY=1 bash "$BIN/ft-nano-spawn.sh" design/planner/indices/대기/empty.md --dry-run)"; has "$out" "절 비어 있음" "상속 env=1 + 템플릿 줄 없는 planner 빈 카드 → REJECT(lint 독립 확인)"
out="$(lint FT_GOAL_LEDGER=design/planner/GOAL-planner.md FT_GOAL_LINES_FILE="$REPO/.fable-team/bin-planner/goal-lines-planner.txt" FT_INDEX_ALLOW_EMPTY_BODY=1 bash "$LINT" "$REPO/design/planner/indices/대기/empty.md")"; has "$out" "REJECT" "lint 단독: env=1 이어도 템플릿 줄 없으면 REJECT"
out="$(real "$BIN" design/planner/indices/대기/full.md)"; body="$(cat "$T/body.txt" 2>/dev/null)"
hasnt "$body" "카드 구현 범위·완료 조건 절을 네가 먼저 채우고" "일반(채워진) 카드 BODY 에는 템플릿 문장 0"
# 변이 대조 2종 — 변이한 사본으로 같은 확인을 돌리면 «잡혀야» 한다(= 본 시험이 빨강이 된다)
M1="$T/bin-m1"; cp -R "$BIN" "$M1"; sed -i.bak 's/FT_INDEX_ALLOW_EMPTY_BODY/FT_INDEX_NEVER_SET_ZZ/g' "$M1/ft-index-lint.sh"
out="$(spawn "$M1" design/planner/indices/대기/tpl.md --dry-run)"; case "$out" in *"(empty-body allowed)"*) bad "변이1(lint 분기 제거) 가 안 잡힘";; *) ok "변이1 FAIL 확인 — lint 의 FT_INDEX_ALLOW_EMPTY_BODY 분기 제거 → 템플릿 시험 빨강";; esac
M2="$T/bin-m2"; cp -R "$BIN" "$M2"; sed -i.bak -E "s/awk '[^']*'[^|]*\| grep -q '[^']*'/true/" "$M2/ft-nano-spawn.sh"; sed -i.bak -E "s/ && awk '[^']*'[^|]*\| grep -q '[^']*' && allow_empty=1/ \&\& allow_empty=1/" "$M2/ft-index-lint.sh"   # 이중 방어(spawn+lint 독립 확인) 둘 다 제거해야 변이가 성립
out="$(spawn "$M2" design/planner/indices/대기/empty.md --dry-run)"; case "$out" in *REJECT*) bad "변이2(템플릿 줄 검사 제거) 가 안 잡힘 — 줄 없는 빈 본문도 통과해야 변이가 성립";; *) ok "변이2 FAIL 확인 — 템플릿 줄 검사 제거(env 무조건) → «줄 없이 빈 본문 REJECT» 시험 빨강";; esac
M3="$T/bin-m3"; cp -R "$BIN" "$M3"; sed -i.bak 's/else unset FT_INDEX_ALLOW_EMPTY_BODY;//' "$M3/ft-nano-spawn.sh"
out="$(run FT_INDEX_ALLOW_EMPTY_BODY=1 bash "$M3/ft-nano-spawn.sh" design/harness/indices/대기/tpl.md --dry-run)"; case "$out" in *"절 비어 있음"*) bad "변이3(unset 제거) 가 안 잡힘";; *) ok "변이3 FAIL 확인 — spawn 의 unset 제거 → 상속 env 회귀 시험 빨강";; esac
cmp -s "$M3/ft-nano-spawn.sh" "$BIN/ft-nano-spawn.sh" && bad "변이3 가 사본을 안 바꿨다"
cmp -s "$M2/ft-nano-spawn.sh" "$BIN/ft-nano-spawn.sh" && bad "변이2 가 spawn 사본을 안 바꿨다(sed 패턴이 구현과 안 맞음)"; cmp -s "$M2/ft-index-lint.sh" "$BIN/ft-index-lint.sh" && bad "변이2 가 lint 사본을 안 바꿨다"

echo "== ⓓ 발주 BODY 팀 구조 1문장 (전 팀)"
SENT="각 팀 = master(집행) + arch(설계·발주·DA 소환) + DA(반박 게이트) 상시 · 실제 작업은 전부 나노(카드 1장 = 나노 1석) · master·arch·DA 는 코드·시안·카드 증거 줄을 쓰지 않는다"
out="$(real "$BIN" design/planner/indices/대기/bodyp.md)"; has "$(cat "$T/body.txt" 2>/dev/null)" "$SENT" "planner 팀 BODY 에 팀 구조 1문장"
out="$(real "$BIN2" design/v65/indices/대기/v65card.md)"; has "$(cat "$T/body.txt" 2>/dev/null)" "$SENT" "v65(default) 팀 BODY 에도 팀 구조 1문장"
has "$(cat "$T/body.txt" 2>/dev/null)" "[Seatbelt 발주] 네 인덱스:" "  └ 기존 BODY 첫 문장 그대로"

echo "== ⓔ 기존 시험 rc=0"
for t in test_nano_team_env.sh test_nano_spawn_body_press.sh test_role_spawn_name.sh; do
  if [ -f "$HERE/$t" ]; then bash "$HERE/$t" >"$T/$t.out" 2>&1 && ok "기존 $t rc=0" || bad "기존 $t rc≠0 ← $(tail -3 "$T/$t.out" | tr '\n' ' ' | cut -c1-200)"; else bad "기존 시험 없음: $t"; fi
done

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
