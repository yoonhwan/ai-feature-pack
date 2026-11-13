#!/usr/bin/env bash
# test_nano_spawn_base_origin_main_r1390.sh — 카드 r1390: 나노 기본 base = fetch 한 origin/main(부른 워크트리 HEAD 아님).
#   --base 명시가 origin/main 조상이 아니면 --base-reason 없이는 REJECT · origin 은 있는데 fetch 실패 = «판정 불가» REJECT(옛 HEAD 로 열기 0).
# 계약↔시험: 기본 base = origin/main → B1·B2·B3·변이1 · 사유 필수 → B4·B5·변이2 · fetch 실패 = 열지 않음 → B6·변이3 · 범위 밖(origin 없음) = 옛 동작 → B7
# 임시 리포 D(뒤처진 main) + 가짜 원격 bare(main 이 1커밋 앞) + 작업 가지 워크트리(미착지 커밋 1) + 가짜 tmux/tmuxc/tmm(PATH 앞) · --dry-run 만(송신·좌석·워크트리 0)
#   실 리포·실 원격·실 명부·실 tmux 0 · 고정 sleep 0 · 자기 재호출 = real_state_guard 재진입 표지(RSG_ACTIVE)뿐. 꼴 = test_nano_detached_base_on_main_r1162.sh
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/fake_resource_env.sh"
fake_resource_env "$T/res" ok
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
G1='내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고.'
G2='하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.'
G3='메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.'
CLOSE='정본 문구 닫는증거는스무자이상이어야합니다 가나다라마바사'
CARDX="design/harness/indices/대기/x.md"
GIT() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

echo "== bin·kit 같은 내용"
bash -n "$BIN/ft-nano-spawn.sh" && ok "bash -n ft-nano-spawn.sh" || bad "bash -n ft-nano-spawn.sh"
cmp -s "$BIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" && ok "사본 cmp ft-nano-spawn.sh" || bad "사본 불일치 ft-nano-spawn.sh"

# ── 가짜 도구(PATH 앞) — 실 tmux·tmuxc·tmm 을 부르지 않는다
mkdir -p "$T/fake"
printf '#!/usr/bin/env bash\ncase "$1" in has-session|list-panes) exit 1;; show-option) echo 1;; esac\nexit 0\n' > "$T/fake/tmux"
printf '#!/usr/bin/env bash\necho "TMUXC $*"\nexit 0\n' > "$T/fake/tmuxc"
printf '#!/usr/bin/env bash\nprintf "harne ● byz-harness-master-claude#1 IDLE  fabl5·hi 09~14  0m harness-ops\\n"\n' > "$T/fake/tmm"
chmod +x "$T/fake/"*
printf '#!/bin/sh\nexit 0\n' > "$T/reclaim.sh"; chmod 755 "$T/reclaim.sh"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
BINX="$T/bin"; cp -R "$KIT" "$BINX"; rm -rf "$BINX/__pycache__"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/ft-all-stop.sh"; chmod +x "$BINX/ft-all-stop.sh"

# ── 픽스처: 리포 D(main M1 = 뒤처짐) · 원격 bare(main M2 = 1커밋 앞) · 작업 가지 워크트리 W(미착지 U)
D="$T/d"
mkdir -p "$D/.fable-team/state" "$D/.fable-team/comm" "$D/.fable-team/bin-harness" "$D/design/harness/indices/대기" "$D/design/v65" "$D/scripts"
printf '#!/bin/sh\nexit 0\n' > "$D/scripts/real.sh"
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$D/.fable-team/state/all-stop.log"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$D/design/TEAMS.md"
echo x > "$D/design/v65/SEATBELT-README.md"
printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > "$D/.fable-team/bin-harness/goal-lines.txt"
printf '# GOAL — harness 제목줄\n\n## 원문 1 머리줄\n> %s\n' "$CLOSE" > "$D/design/harness/GOAL-harness.md"
printf '# 인덱스: x\n- Issue: #1\n- 제안서: 없음 — 시험용 카드\n- 상태: 대기\n- 선행: 없음\n- 시험 입력: 없음\n- 기준값: 없음 → 대체 축 시험\n- 설치: 없음\n<!-- ledger: design/harness/GOAL-harness.md -->\n\n## 골 원문 (항상 이 3줄)\n%s\n%s\n%s\n\n## 골좌표\n닫는 증거: 「%s」\n\n## 배경\n시험.\n\n## 구현 범위\n1. `scripts/real.sh` 를 고친다.\n\n## 계약↔시험 대응표\n| 계약 | 시험 |\n|---|---|\n| ① real.sh | ⓐ rc0 |\n\n## 완료 조건\n- 시험 rc=0\n\n## 상태\n- 대기\n' \
  "$G1" "$G2" "$G3" "$CLOSE" > "$D/$CARDX"
printf '{"_version":"1.0.0","byz-harness-master-claude#1":{"role":"master"}}\n' > "$D/.fable-team/seats-harness.json"
printf '{"_version":"1.0.0"}\n' > "$D/.fable-team/seats.json"
printf "export FT_SEATS_JSON='%s/.fable-team/seats-harness.json'\nexport FT_NANO_PREFIX=byz-harness-nano-\nexport FT_NANO_WT_PREFIX=harness-\nexport FT_GOAL_LEDGER='design/harness/GOAL-harness.md'\nexport FT_GOAL_LINES_FILE='%s/.fable-team/bin-harness/goal-lines.txt'\n" "$D" "$D" > "$D/.fable-team/bin-harness/harness-env.sh"
git init -q -b main "$D"; GIT "$D" add -A >/dev/null; GIT "$D" commit -q -m init; M1="$(GIT "$D" rev-parse HEAD)"
# 범위 밖 B7 용 원격 없는 사본(지금 시점 · origin 0)
git clone -q "$D" "$T/noorigin"; git -C "$T/noorigin" remote remove origin
git clone -q --bare "$D" "$T/remote.git"; GIT "$D" remote add origin "$T/remote.git"; GIT "$D" fetch -q origin
# 원격 main 만 1커밋 앞으로(D 의 main·origin/main 은 M1 에 남는다 = 뒤처진 루트)
git clone -q "$T/remote.git" "$T/up"; echo two > "$T/up/two.txt"; GIT "$T/up" add two.txt; GIT "$T/up" commit -q -m two; GIT "$T/up" push -q origin main
M2="$(GIT "$T/up" rev-parse HEAD)"
# 작업 가지 워크트리 W(main 위 미착지 커밋 U)
git -C "$D" worktree add -q -b work/x "$T/w" main; echo u > "$T/w/u.txt"; GIT "$T/w" add u.txt; GIT "$T/w" commit -q -m unlanded
U="$(GIT "$T/w" rev-parse HEAD)"
# B6 용: origin 이 사라진 원격을 가리키는 사본
git clone -q "$T/remote.git" "$T/gone"; git -C "$T/gone" remote set-url origin "$T/gone-remote.git"
mkdir -p "$T/gone/.fable-team/comm" "$T/noorigin/.fable-team/comm"   # 빈 폴더는 clone 에 안 실린다(spawn-hold 가 comm 폴더를 본다)

sp() {  # sp <cwd> <FT_ROOT> <bindir> [인자…] — env -i 격리 · --dry-run 고정
  local w="$1" r="$2" bd="$3"; shift 3
  ( cd "$w" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_TEAMSET=0 FT_RES_ROOT="$T/res" FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$r" FT_RECLAIM_SH="$T/reclaim.sh" \
      bash "$bd/ft-nano-spawn.sh" "$CARDX" --dry-run "$@" 2>&1 )
}
b1() {  # 뒤처진 main 위 · --base 없음 → base=origin/main · origin/main = 원격 tip M2
  local out rc; out="$(sp "$D" "$D" "$1")"; rc=$?
  [ "$rc" = 0 ] && [[ "$out" == *"base=origin/main index="* ]] && [ "$(git -C "$D" rev-parse refs/remotes/origin/main)" = "$M2" ] \
    || { echo "  B1 rc=$rc ← ${out: -300}"; return 1; }
}
b2() {  # 미착지 커밋 얹은 작업 가지 위 · --base 없음 → base=origin/main(work/x 아님) · U 는 그 base 에 없다
  local out rc; out="$(sp "$T/w" "$D" "$1")"; rc=$?
  [ "$rc" = 0 ] && [[ "$out" == *"base=origin/main index="* ]] && ! git -C "$D" merge-base --is-ancestor "$U" refs/remotes/origin/main \
    || { echo "  B2 rc=$rc ← ${out: -300}"; return 1; }
}
b4() {  # --base U · 사유 없음 → REJECT 1줄 · rc1 · PLAN 0 · 카드·명부 바이트 그대로 · 워크트리 0
  local out rc n=0
  cp "$T/w/$CARDX" "$T/card.before"; cp "$D/.fable-team/seats-harness.json" "$T/seats.before"
  out="$(sp "$T/w" "$D" "$1" --base "$U")"; rc=$?
  [ "$rc" = 1 ] || { n=$((n+1)); echo "  B4 rc=$rc"; }
  case "$out" in *"REJECT 기준 ${U:0:10} 가 origin/main 위가 아니다 — --base origin/main 또는 --base-reason"*) ;; *) n=$((n+1)); echo "  B4 REJECT 줄 없음 ← ${out: -300}";; esac
  [ "$(printf '%s\n' "$out" | grep -c '^REJECT')" = 1 ] || { n=$((n+1)); echo "  B4 REJECT 줄 수 ≠ 1"; }
  case "$out" in *"PLAN seat="*) n=$((n+1)); echo "  B4 PLAN 줄이 나왔다";; esac
  cmp -s "$T/card.before" "$T/w/$CARDX" || { n=$((n+1)); echo "  B4 카드 바이트가 바뀜"; }
  cmp -s "$T/seats.before" "$D/.fable-team/seats-harness.json" || { n=$((n+1)); echo "  B4 명부 바이트가 바뀜"; }
  [ ! -e "$D/.worktrees" ] || { n=$((n+1)); echo "  B4 워크트리 폴더가 생김"; }
  return "$n"
}
b6() {  # origin 은 있는데 fetch 실패 → «판정 불가» REJECT 1줄 · rc1 · PLAN 0(옛 HEAD 로 열기 0)
  local out rc; out="$(sp "$T/gone" "$T/gone" "$1")"; rc=$?
  [ "$rc" = 1 ] && [[ "$out" == *"REJECT 기준 판정 불가 — origin main fetch 실패"* ]] && [[ "$out" != *"PLAN seat="* ]] \
    || { echo "  B6 rc=$rc ← ${out: -300}"; return 1; }
}

s=$SECONDS; echo "== B1 뒤처진 main 위 · --base 없음"
o="$(b1 "$BINX")" && ok "B1 base=origin/main · origin/main=${M2:0:10}(뒤처진 HEAD ${M1:0:10} 아님)" || bad "B1$(printf '\n%s' "$o")"
echo "== B2 미착지 커밋 얹은 작업 가지 위 · --base 없음"
o="$(b2 "$BINX")" && ok "B2 base=origin/main · 미착지 ${U:0:10} 는 base 에 없다" || bad "B2$(printf '\n%s' "$o")"
echo "== B3 --base origin/main 명시 → B1 과 같음"
out="$(sp "$D" "$D" "$BINX" --base origin/main)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$out" == *"base=origin/main index="* ]]; } && ok "B3 base=origin/main" || bad "B3 rc=$rc ← ${out: -300}"
echo "  (B1~B3 $((SECONDS-s))초)"

s=$SECONDS; echo "== B4 --base <미착지> · 사유 없음 → REJECT · 부작용 0"
o="$(b4 "$BINX")" && ok "B4 REJECT 1줄 · rc1 · 카드·명부 cmp 같음 · 워크트리 0" || bad "B4$(printf '\n%s' "$o")"
echo "== B5 --base <미착지> --base-reason → 열림 · BASE-REASON 1줄"
out="$(sp "$T/w" "$D" "$BINX" --base "$U" --base-reason "선행 카드 위에서")"; rc=$?
{ [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c "^BASE-REASON ${U:0:10} origin/main 위 아님 — 선행 카드 위에서$")" = 1 ] && [[ "$out" == *"base=$U index="* ]]; } \
  && ok "B5 rc0 · BASE-REASON 1줄 · base=$U" || bad "B5 rc=$rc ← ${out: -300}"
# B5 쓰기 자리(dry-run 은 쓰기 0 — 실제 쓰기는 test_nano_spawn_reopen_no_root_commit_r1409.sh E5·E6 이 본다): 명부 base_reason 칸 + 카드 «## 상태» card_note 1줄
grep -q 'd\[name\]\["base_reason"\] = base_reason.strip()' "$BINX/ft-nano-spawn.sh" && grep -q 'card_note "$IDX_WT/$NEW_IDX" "$_BR_LINE"' "$BINX/ft-nano-spawn.sh" \
  && ok "B5 쓰기 자리 2곳(명부 base_reason · 카드 상태 줄) 있음" || bad "B5 쓰기 자리 없음"
echo "== B5b --base-reason 이 공백뿐 → 사유 없음과 같다(REJECT)"
out="$(sp "$T/w" "$D" "$BINX" --base "$U" --base-reason "  ")"; rc=$?
{ [ "$rc" = 1 ] && [[ "$out" == *"가 origin/main 위가 아니다"* ]]; } && ok "B5b 공백 사유 REJECT" || bad "B5b rc=$rc ← ${out: -300}"
echo "== B5c --base <origin/main 조상 M1> · 사유 없음 → 열림(검사 통과)"
out="$(sp "$T/w" "$D" "$BINX" --base "$M1")"; rc=$?
{ [ "$rc" = 0 ] && [[ "$out" != *"BASE-REASON"* ]]; } && ok "B5c 조상 base 통과 · BASE-REASON 0" || bad "B5c rc=$rc ← ${out: -300}"
echo "  (B4·B5 $((SECONDS-s))초)"

s=$SECONDS; echo "== B6 fetch 실패(원격 사라짐) → 판정 불가 REJECT"
o="$(b6 "$BINX")" && ok "B6 REJECT «판정 불가» · PLAN 0" || bad "B6$(printf '\n%s' "$o")"
echo "== B7 범위 밖: origin 원격 없는 리포 → 옛 동작(base=main)"
out="$(sp "$T/noorigin" "$T/noorigin" "$BINX")"; rc=$?
{ [ "$rc" = 0 ] && [[ "$out" == *"base=main index="* ]]; } && ok "B7 base=main(옛 동작)" || bad "B7 rc=$rc ← ${out: -300}"
echo "  (B6·B7 $((SECONDS-s))초)"

mut() {  # mut <이름> <sed 식> <검사 함수> — 변이판에서 검사가 FAIL 이어야 한다
  local m="$T/mut-$1"; cp -R "$BINX" "$m"
  sed "$2" "$BINX/ft-nano-spawn.sh" > "$m/ft-nano-spawn.sh"
  if cmp -s "$m/ft-nano-spawn.sh" "$BINX/ft-nano-spawn.sh"; then bad "변이 $1 적용 0(패턴 없음)"; return; fi
  "$3" "$m" >/dev/null && bad "변이 $1 이 $3 을 통과 — 시험이 못 본다" || ok "변이 $1 → $3 FAIL(잡힘)"
}
s=$SECONDS; echo "== 변이"
GIT "$D" update-ref refs/remotes/origin/main "$M1"   # 변이1 B1 이 fetch 결과에 기대지 않게 되돌려 둔다
mut default-head 's/^    BASE_REF=origin\/main$/    :/' b1
mut default-head2 's/^    BASE_REF=origin\/main$/    :/' b2
mut no-ancestor 's/merge-base --is-ancestor "\$_bs" refs\/remotes\/origin\/main/cat-file -e "$_bs"/' b4
mut fetch-fallback 's/^if \[ -n "\$_bw" \] \&\& git -C "\$_bw" config --get remote.origin.url >\/dev\/null 2>&1; then$/if [ -n "$_bw" ] \&\& git -C "$_bw" fetch -q origin main >\/dev\/null 2>\&1; then/' b6
echo "  (변이 $((SECONDS-s))초)"

echo
echo "총 $((SECONDS-T0))초"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
