#!/usr/bin/env bash
# test_r756_desk_planner_worktree_gate.sh — ft-successor-open.sh r756: desk·planner 후계는 «origin/main 을 품은» 워크트리에서만 열린다 + 하네스 데이터 루트(LIVE_ROOT) 갈라짐 금지.
#   ⓐ 옛 판(base = origin/main 사본)은 W1(뒤진 가지)에서 그대로 «연다» — 빨강 재현 ⓑ 지금 판 W1 = REJECT(뒤처짐 수 · 열기·송신·도달 파일 0) ⓒ W2(main 품음) = 통과
#   ⓓ desk·planner 아닌 좌석 = 검사 0 ⓔ origin/main 못 읽음 = REJECT(fail-closed) ⓕ LIVE_ROOT 갈라짐 = REJECT / 없음 = REJECT
#   ⓖ 기존 test_successor_open.sh 그대로 ALL PASS ⓗ 변이 2종(① main 포함 검사 삭제 → W1 통과 ② LIVE_ROOT 대조 삭제 → 갈라짐 통과 = 변이를 잡는다)
#   ⓘ 격리 = 임시 리포+워크트리 · PATH 스텁 · 임시 HOME 만. 실 세션·실 tmux·실 명부·실제품 키 쓰기 0 · press 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; PACK="$(cd -- "$HERE/../../../.." && pwd)"   # 워크트리 루트(REL 이 feature-pack/ 로 시작한다)
REL="feature-pack/fable-team/harness/kit/fable-team/bin/ft-successor-open.sh"
SO="${FT_SO_PATH:-$PACK/$REL}"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }

[ -f "$SO" ] && bash -n "$SO" && ok "bash -n" || { bad "ft-successor-open.sh 없음·구문 오류: $SO"; echo "FAILED $fail"; exit 1; }
cmp -s "$PACK/$REL" "$PACK/feature-pack/fable-team/harness/bin/ft-successor-open.sh" && ok "짝 사본(harness/bin ↔ kit) cmp=0" || bad "짝 사본이 다르다(harness/bin ↔ kit)"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; CNT="$TMP/pgrep.cnt"; OPENED="$TMP/opened"; BODY="$TMP/body.txt"
mkdir -p "$FAKE"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n' > "$BODY"

mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux   'case "$1" in
  has-session) [ -n "${EXISTS:-}" ] && case "$*" in *"=$EXISTS"*) exit 0;; esac; [ -f "$OPENED" ] && exit 0; exit 1;;
  list-panes) echo 4242;;
  display-message) echo "${PANE_CWD:-}";;
esac; exit 0'
mkstub tmuxc  'echo "tmuxc $*" >> "$LOG"; : > "$OPENED"; exit 0'
mkstub pgrep  'echo pgrep >> "$LOG"; n=$(cat "$CNT" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$CNT"; [ "$n" -ge 3 ] && { echo 5555; exit 0; }; exit 1'
mkstub send   'echo send >> "$LOG"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit 0'
mkstub mbox   'echo "mbox $1" >> "$LOG"; echo "RING seq=$3 doorbell=sent"; exit 0'
mkstub reach  'echo reach >> "$LOG"; exit 0'
: > "$FAKE/mbox_doorbell.sh"
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"

# ── 픽스처: 임시 리포(공용 루트) + 워크트리 W1(main 1커밋 뒤 = 옛 가지 꼴) · W2(main 품음) · LIVE_ROOT 3자리
R="$TMP/repo"; mkdir -p "$R"; git -C "$R" init -q
git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m c1
git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m c2
git -C "$R" update-ref refs/remotes/origin/main HEAD
git -C "$R" worktree add -q "$TMP/w1" -b old HEAD~1 2>/dev/null     # 뒤진 가지(옛 v6-realtime-live 꼴)
git -C "$R" worktree add -q "$TMP/w2" -b new HEAD 2>/dev/null       # main 을 품은 새 자리
W1="$TMP/w1"; W2="$TMP/w2"; LIVE="$TMP/live-root"
mkdir -p "$R/.fable-team/comm"
printf '#!/usr/bin/env bash\necho "mbox $1" >> "%s"; echo "RING seq=$3 doorbell=sent"\n' "$LOG" > "$R/.fable-team/comm/mbox.sh"
: > "$R/.fable-team/comm/mbox_doorbell.sh"
mkdir -p "$R/.fable-team" "$W1/.fable-team" "$W2/.fable-team"
printf '%s\n' "$LIVE" > "$R/.fable-team/LIVE_ROOT"
printf '%s\n' "$LIVE" > "$W1/.fable-team/LIVE_ROOT"
printf '%s\n' "$LIVE" > "$W2/.fable-team/LIVE_ROOT"

OLD='byz-planner-master-claude#94'; NEW='byz-planner-master-claude#95'
run() { # run <스크립트 경로> <워크트리> <환경 KEY=VAL…>
  local so="$1" wt="$2"; shift 2
  rm -f "$LOG" "$CNT" "$OPENED"; : > "$LOG"
  env HOME="$TMP/home" PATH="$FAKE:$PATH" LOG="$LOG" CNT="$CNT" OPENED="$OPENED" PANE_CWD="$wt" \
      FT_SO_POLL=0 FT_SO_WAIT_MAX=5 FT_RES_ROOT="$RES" SENSORS="$SENSORS" \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$R/.fable-team/comm/mbox.sh" FT_REACH_CHECK="$FAKE/reach" "$@" \
      bash "$so" "$OLD" "$wt" --name "$NEW" --agent claude --model 'claude-opus-5-5[1m]' --ctx 1m --effort high --body-file "$BODY" > "$TMP/out" 2>&1
  RC=$?
}
count() { grep -c "^$1" "$LOG" 2>/dev/null || true; }
withbin() { # withbin <폴더이름> <ft-successor-open.sh 대체본> → 그 폴더 사본의 경로를 $WITHSO 로
  mkdir -p "$TMP/$1"; cp -R "$(dirname -- "$SO")/." "$TMP/$1/"; cp "$2" "$TMP/$1/ft-successor-open.sh"; WITHSO="$TMP/$1/ft-successor-open.sh"
}
clean() { [ ! -e "$R/.fable-team/state/successor/$OLD.json" ]; }   # 도달 파일(부작용) 0

# ⓐ 빨강 — 옛 판(base 판)은 W1 에서 그대로 연다: 승계 도구가 자리를 보지 않았다
BASE_SO="$TMP/base.successor-open.sh"
if git -C "$PACK" show "${FT_SO_BASE_REF:-origin/main}:$REL" > "$BASE_SO" 2>/dev/null; then
  withbin basebin "$BASE_SO"; run "$WITHSO" "$W1"
  { [ "$RC" -eq 0 ] && [ "$(count tmuxc)" = 1 ] && [ "$(count send)" = 1 ]; } \
    && ok "ⓐ 옛 판(base) = W1(뒤진 가지)에서 연다 rc=0 · open 1 · 송신 1(빨강 재현)" || bad "ⓐ 옛 판이 W1 을 거절했다 rc=$RC :: $(head -2 "$TMP/out")"
  rm -rf "$R/.fable-team/state"   # ⓐ 가 남긴 도달 파일(부작용) — ⓑ 의 «도달 파일 0» 단언은 이 자리부터 센다
else
  bad "ⓐ base 판을 못 읽음(${FT_SO_BASE_REF:-origin/main}:$REL) — 빨강 재현 0"
fi

# ⓑ 지금 판 W1 = REJECT(열기 «전») · 뒤처짐 수 표시 · open·송신·도달 파일 0
run "$SO" "$W1"
{ [ "$RC" -eq 1 ] && grep -q 'desk·planner 후계는 origin/main 을 품은 워크트리에서만' "$TMP/out" && grep -q '보다 1 뒤' "$TMP/out" \
  && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ] && clean; } \
  && ok "ⓑ 지금 판 W1 → REJECT rc=1 · 뒤처짐 1 · open·송신·도달 파일 0" || bad "ⓑ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓑ-2 desk 이름도 같은 문(이름 표식 = *-desk-*) · 이 검사가 r660 본문 검사보다 «먼저» 문다
OLD='byz-planner-desk-claude#38'; NEW='byz-planner-desk-claude#39'; run "$SO" "$W1"
{ [ "$RC" -eq 1 ] && grep -q 'desk·planner 후계는 origin/main 을 품은 워크트리에서만' "$TMP/out" && [ "$(count tmuxc)" = 0 ] && clean; } \
  && ok "ⓑ-2 desk 이름 W1 → 같은 REJECT(자리 문이 본문 문보다 먼저)" || bad "ⓑ-2 rc=$RC out=$(cat "$TMP/out")"
OLD='byz-planner-master-claude#94'; NEW='byz-planner-master-claude#95'

# ⓒ W2(main 품음 · 같은 LIVE_ROOT) = 통과 → open 1 · 송신 1 · 도달 파일
run "$SO" "$W2"
{ [ "$RC" -eq 0 ] && [ "$(count tmuxc)" = 1 ] && [ "$(count send)" = 1 ] && [ -f "$R/.fable-team/state/successor/$OLD.json" ] && grep -q "$NEW" "$R/.fable-team/state/successor/$OLD.json"; } \
  && ok "ⓒ W2(main 품음) → 통과 · open 1 · 송신 1 · 도달 파일" || bad "ⓒ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"
rm -rf "$R/.fable-team/state"

# ⓓ desk·planner 아닌 좌석 = 검사 0 (W1 이어도 그대로 연다)
OLD='byz-harness-nano-x#0'; NEW='byz-harness-nano-x#1'; run "$SO" "$W1"
{ [ "$RC" -eq 0 ] && [ "$(count tmuxc)" = 1 ] && [ "$(count send)" = 1 ]; } \
  && ok "ⓓ nano 좌석 → 검사 0 · W1 이어도 통과" || bad "ⓓ rc=$RC out=$(cat "$TMP/out")"
OLD='byz-planner-master-claude#94'; NEW='byz-planner-master-claude#95'; rm -rf "$R/.fable-team/state"

# ⓔ origin/main 을 못 읽는 리포 = REJECT(fail-closed) · open·송신 0
R2="$TMP/repo2"; mkdir -p "$R2"; git -C "$R2" init -q
git -C "$R2" -c user.name=t -c user.email=t@t commit -q --allow-empty -m only
mkdir -p "$R2/.fable-team/comm" "$R2/.fable-team"; : > "$R2/.fable-team/comm/mbox_doorbell.sh"
cp "$R/.fable-team/comm/mbox.sh" "$R2/.fable-team/comm/mbox.sh"; printf '%s\n' "$LIVE" > "$R2/.fable-team/LIVE_ROOT"
run "$SO" "$R2"
{ [ "$RC" -eq 1 ] && grep -q 'origin/main 을 읽지 못했다(못 읽으면 열지 않는다 · fail-closed)' "$TMP/out" && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "ⓔ origin/main 없음 → REJECT rc=1 · open·송신 0(fail-closed)" || bad "ⓔ rc=$RC out=$(cat "$TMP/out")"

# ⓕ LIVE_ROOT 갈라짐 → REJECT(두 값 표시) · 같으면 통과 · 없으면 REJECT(fail-closed)
printf '%s\n' "$TMP/other-live-root" > "$W2/.fable-team/LIVE_ROOT"; run "$SO" "$W2"
{ [ "$RC" -eq 1 ] && grep -q '하네스 데이터 루트 갈라짐' "$TMP/out" && grep -qF "워크트리 LIVE_ROOT=$TMP/other-live-root" "$TMP/out" && grep -qF "공용 루트 LIVE_ROOT=$LIVE" "$TMP/out" \
  && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ] && clean; } \
  && ok "ⓕ LIVE_ROOT 갈라짐 → REJECT rc=1 · 두 값 표시 · open·송신 0" || bad "ⓕ rc=$RC out=$(cat "$TMP/out")"
rm -f "$W2/.fable-team/LIVE_ROOT"; run "$SO" "$W2"
{ [ "$RC" -eq 1 ] && grep -q 'LIVE_ROOT)를 읽지 못했다' "$TMP/out" && [ "$(count tmuxc)" = 0 ]; } \
  && ok "ⓕ 워크트리 LIVE_ROOT 없음 → REJECT rc=1(fail-closed)" || bad "ⓕ 없음 rc=$RC out=$(cat "$TMP/out")"
printf '%s\n' "$LIVE" > "$W2/.fable-team/LIVE_ROOT"; run "$SO" "$W2"
{ [ "$RC" -eq 0 ] && [ "$(count send)" = 1 ]; } \
  && ok "ⓕ LIVE_ROOT 같으면 통과(정상 흐름 그대로)" || bad "ⓕ 같음 rc=$RC out=$(cat "$TMP/out")"
rm -rf "$R/.fable-team/state"

# ⓗ 변이 2종 — 검사를 지우면 이 시험이 잡는다(변이 판 = REJECT 사라짐)
MUT1="$TMP/mut1.sh"; sed 's|if ! git -C "\$WT" merge-base --is-ancestor|if false \&\& git -C "$WT" merge-base --is-ancestor|' "$SO" > "$MUT1"
[ "$(grep -c 'if false && git -C "$WT" merge-base --is-ancestor' "$MUT1")" = 1 ] || bad "ⓗ 변이① 주입 실패(치환 0)"
withbin mut1bin "$MUT1"; run "$WITHSO" "$W1"
{ [ "$RC" -eq 0 ] && [ "$(count tmuxc)" = 1 ]; } \
  && ok "ⓗ① main 포함 검사 삭제 변이 → W1 통과(= 시험 ⓑ 가 잡는다)" || bad "ⓗ① 변이가 잡히지 않음 rc=$RC out=$(cat "$TMP/out")"
rm -rf "$R/.fable-team/state"
MUT2="$TMP/mut2.sh"; sed 's|\[ "\$_lr_wt" = "\$_lr_rt" \]|[ 1 = 1 ]|' "$SO" > "$MUT2"
[ "$(grep -c '\[ 1 = 1 \]' "$MUT2")" = 1 ] || bad "ⓗ 변이② 주입 실패(치환 0)"
printf '%s\n' "$TMP/other-live-root" > "$W2/.fable-team/LIVE_ROOT"; withbin mut2bin "$MUT2"; run "$WITHSO" "$W2"
{ [ "$RC" -eq 0 ] && [ "$(count tmuxc)" = 1 ]; } \
  && ok "ⓗ② LIVE_ROOT 대조 삭제 변이 → 갈라짐 통과(= 시험 ⓕ 가 잡는다)" || bad "ⓗ② 변이가 잡히지 않음 rc=$RC out=$(cat "$TMP/out")"
printf '%s\n' "$LIVE" > "$W2/.fable-team/LIVE_ROOT"; rm -rf "$R/.fable-team/state"

# ⓖ 기존 승계 시험 = 이 변경 뒤에도 전부 PASS
if [ -f "$HERE/test_successor_open.sh" ]; then
  OUT="$(bash "$HERE/test_successor_open.sh" 2>&1)"; GRC=$?
  { [ "$GRC" -eq 0 ] && case "$OUT" in *"ALL PASS"*) true;; *) false;; esac; } \
    && ok "ⓖ test_successor_open.sh ALL PASS" || bad "ⓖ test_successor_open.sh rc=$GRC :: $(printf '%s' "$OUT" | grep -m3 '^FAIL')"
else
  bad "ⓖ test_successor_open.sh 없음"
fi

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
