#!/usr/bin/env bash
# test_nano_spawn_lint_map_once_r1398.sh — r1398: 카드 이력 사전(FT_CARD_ADDED_MAP_FILE)을 spawn ① «앞» 에서 1회 만들고 끝까지 넘긴다.
#   왜: ⑥(대기→진행)의 ft-index-move 안 lint 가 git log 를 다시 부르고, 부하가 크면 상한을 넘겨 «좌석은 떴는데 카드는 대기» 로 남았다(실사건 3번 · 재시도 = 같은 워크트리에 #1).
#   계약(카드 계약↔시험 대응표 그대로):
#   S1 ① 앞 사전 1회 · ⑥ 은 git 0        ⓐ --dry-run 1회 → 가짜 map_lint --map-only 정확히 1회 · ① lint 가 그 사전을 물려받는다
#   S2 ⑥ 갈래 lint 는 사전만 읽는다        ⓑ spawn ① 앞 블록을 그대로 떼어 사전을 만들고 같은 셸에서 진짜 ft-index-move 로 잇는다 → 8초 지연 git log 를 ⑥ 이 다시 부르지 않는다(총 1회 = ① 몫) · 이동 rc0
#   S3 사전 판정 불가 = 재시도 1          ⓒ 1차 rc3 · 2차 rc0 → rc0 · 호출 2
#   S4 판정 불가 = 부작용 0 REJECT        ⓓ 1·2차 모두 rc3 → rc1 + «좌석·워크트리·명부 0» · ① lint 진입 0 · 명부 바이트 불변
#   S5 이 실행의 사전만 지운다             ⓔ 성공·REJECT 둘 다 임시 폴더에 ft-r1398-cardmap.* 남음 0
#   S6 바깥이 준 사전은 안 건드린다        ⓕ 밖에서 준 파일 → 생성 0 · 호출 0 · 내용 불변 · 지우기 0
#   S7 카드 이력 git 상한 = 25초           ⓖ 12초 지연 → rc0(상한 안) / 26초 → rc3 «git log 25초 상한 초과»
#   S7b 창 밖 카드 갈래(rev-list)도 상한    ⓗ 상한 3초(env)에서 rev-list 2초 → rc0 · 4초 → rc3 · 사전이 있으면 rev-list 호출 0
#   변이: ① 앞 사전 블록 삭제 → S1 FAIL · 재시도 0 → S3 FAIL · 실패를 WARN 으로 넘김 → S4 FAIL · 정리 줄 삭제 → S5 FAIL
#         · git log 상한을 7 로 되돌림 → S7(g 12초) FAIL · :175(rev-list)만 7 로 남김 → S7b(h) FAIL
# 꼴 = 블록 추출 + 임시 bin 사본(진짜 spawn --dry-run) — 실 tmux·실 워크트리·실 명부 0 · 자기 재호출 0 · 임시 폴더만 쓴다.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"; MOD="$BIN/ft_card_map_lint.py"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — 없음 «$3» ← $(printf '%s' "${2:0:400}" | tr '\n' ';')";; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — 있으면 안 됨 «$3» ← $(printf '%s' "${2:0:400}" | tr '\n' ';')";; *) ok "$1";; esac; }

# ── 0. 짝·구문 — bin/kit cmp0 · bash 3.2 구문 ──
for f in ft-nano-spawn.sh ft_card_map_lint.py; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "kit 짝 cmp0 ($f)" || bad "kit 짝 다름 ($f)"
done
bash -n "$BIN/ft-nano-spawn.sh" && ok "bash -n ft-nano-spawn.sh" || bad "bash -n ft-nano-spawn.sh"
/bin/bash -n "$BIN/ft-nano-spawn.sh" && ok "/bin/bash 3.2 -n ft-nano-spawn.sh" || bad "/bin/bash 3.2 -n ft-nano-spawn.sh"

# ── 공통 대역: 임시 bin 사본(키트 통째) + 가짜 map_lint(호출 기록) + 가짜 ① lint(사전 물려받음 기록) + 가짜 tmux ──
SB="$T/bin"; bash "$HERE/lib/kit_bin_copy.sh" "$SB" >/dev/null || { echo "FAIL 임시 bin 사본 실패"; exit 1; }
MAPLOG="$T/maplog"; TMUXLOG="$T/tmuxlog"; : > "$MAPLOG"; : > "$TMUXLOG"
cat > "$SB/ft_card_map_lint.py" <<'PY'
#!/usr/bin/env python3
"""r1398 시험 대역 — 호출을 기록하고 env 로 rc·지연을 흉내낸다(진짜 판정기는 S7·S7b 가 쓴다)."""
import os
import sys
import time

log = os.environ["FT_TEST_MAPPLOG"]
n = len(open(log, encoding="utf-8").read().splitlines()) if os.path.exists(log) else 0
with open(log, "a", encoding="utf-8") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
n += 1
rcs = (os.environ.get("FT_TEST_MAP_RC") or "0").split(",")
delays = (os.environ.get("FT_TEST_MAP_DELAY") or "").split(",")
rc = int(rcs[min(n - 1, len(rcs) - 1)])
delay = delays[min(n - 1, len(delays) - 1)] if delays and delays[0] else "0"
if float(delay or 0):
    time.sleep(float(delay))
mp = os.environ.get("FT_CARD_ADDED_MAP_FILE", "")
if rc == 0 and mp and "--map-only" in sys.argv:
    open(mp, "w", encoding="utf-8").write("x.md\t2026-11-05\n")
sys.exit(rc)
PY
printf '#!/bin/sh\necho "LINT-OK mapfile=${FT_CARD_ADDED_MAP_FILE:-none}"\nexit 0\n' > "$SB/ft-index-lint.sh"
printf '#!/bin/sh\necho gate-ok\nexit 0\n' > "$SB/ft-proposal-gate.sh"
printf '#!/bin/sh\necho "$*" >> "%s"\ncase "$1" in new-session|new-window|split-window|list-sessions) exit 0;; *) exit 1;; esac\n' "$TMUXLOG" > "$T/fake/tmux"; chmod 755 "$T/fake/tmux"
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T" ok
. "$HERE/lib/fake_tmm.sh"; fake_tmm "$T/fake" byz-alpha-master-claude#1   # 살아 있는 좌석 1명 — 실 좌석 목록이 새어 들어오지 않게
R1="$T/repo"; mkdir -p "$R1/design/alpha/indices/대기" "$R1/.fable-team/comm" "$R1/.fable-team/state" "$T/tmp"
env -u GIT_DIR -u GIT_WORK_TREE git init -q "$R1"; git -C "$R1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
echo '{"_name":"alpha"}' > "$R1/.fable-team/seats-alpha.json"
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$R1/.fable-team/state/all-stop.log"
printf '# 인덱스: x\n## 상태\n' > "$R1/design/alpha/indices/대기/x.md"
SEATS_MD5="$(md5 -q "$R1/.fable-team/seats-alpha.json" 2>/dev/null || md5sum "$R1/.fable-team/seats-alpha.json" | cut -d' ' -f1)"
GOODLINES="$T/goal3.txt"; printf '목표는 AAAA 이다.\n목표는 BBBB 이다.\n목표는 CCCC 이다.\n' > "$GOODLINES"
spr()  { ( cd "$R1" && FT_ROOT="$R1" FT_NANO_PREFIX="byz-alpha-nano-" FT_SEATS_JSON="$R1/.fable-team/seats-alpha.json" \
           FT_TEAMSET=0 FT_CARD_FLOW=0 FT_ACCT_ASSIGN=0 FT_TEST_MAPPLOG="$MAPLOG" FT_GOAL_LINES_FILE="$GOODLINES" \
           TMPDIR="$T/tmp" PATH="$T/fake:$PATH" bash "$SB/ft-nano-spawn.sh" design/alpha/indices/대기/x.md --from byz-alpha-master-claude#1 "$@" 2>&1 ); }
leftover() { ls "$T/tmp"/*ft-r1398-cardmap* 2>/dev/null | wc -l | tr -d ' '; }

# ── S1 · S5(성공 갈래) — 지연 0 · rc0: --map-only 정확히 1회 · ① lint 가 그 사전을 물려받는다 · 임시 사전 남음 0 ──
: > "$MAPLOG"; : > "$TMUXLOG"
OUT="$(FT_TEST_MAP_RC=0 spr --dry-run)"; RC=$?
[ "$RC" = 0 ] && ok "S1 spawn --dry-run rc0" || bad "S1 rc=$RC ← $(printf '%s' "$OUT" | tr '\n' ';')"
[ "$(wc -l < "$MAPLOG" | tr -d ' ')" = 1 ] && ok "S1 가짜 map_lint 호출 정확히 1회" || bad "S1 map_lint 호출 $(wc -l < "$MAPLOG" | tr -d ' ')"
has "S1 호출이 --map-only + 카드 경로" "$(cat "$MAPLOG")" "--map-only design/alpha/indices/대기/x.md"
has "S1 ① lint 는 export 된 사전을 물려받는다(빈 값 아님)" "$OUT" "LINT-OK mapfile=$T/tmp/ft-r1398-cardmap."
hasnt "S1 ① 앞에서 멈추지 않았다(lint 진입)" "$OUT" "REJECT 카드 이력 사전"
[ "$(leftover)" = 0 ] && ok "S5 성공 뒤 임시 사전 남음 0" || bad "S5 성공 뒤 임시 사전 $(leftover)개 남음"

# ── S3 — 1차 rc3 · 2차 rc0: 재시도 1회로 통과 · 호출 2 ──
: > "$MAPLOG"
OUT="$(FT_TEST_MAP_RC=3,0 spr --dry-run)"; RC=$?
[ "$RC" = 0 ] && ok "S3 1차 rc3 → 재시도 1회 뒤 rc0" || bad "S3 rc=$RC ← $(printf '%s' "$OUT" | tr '\n' ';')"
[ "$(wc -l < "$MAPLOG" | tr -d ' ')" = 2 ] && ok "S3 map_lint 호출 2회(재시도 1)" || bad "S3 호출 $(wc -l < "$MAPLOG" | tr -d ' ')"
[ "$(leftover)" = 0 ] && ok "S5 S3 뒤 임시 사전 남음 0" || bad "S5 S3 뒤 임시 사전 $(leftover)개"

# ── S4 · S5(REJECT 갈래) — 1·2차 모두 rc3: rc1 REJECT · ① 진입 0 · 명부·tmux 불변 ──
: > "$MAPLOG"; : > "$TMUXLOG"
OUT="$(FT_TEST_MAP_RC=3 spr --dry-run)"; RC=$?
[ "$RC" = 1 ] && ok "S4 두 번 다 rc3 → rc1" || bad "S4 rc=$RC ← $(printf '%s' "$OUT" | tr '\n' ';')"
has "S4 REJECT 문구(좌석·워크트리·명부 0)" "$OUT" "REJECT 카드 이력 사전 판정 불가 — 좌석·워크트리·명부 0"
[ "$(wc -l < "$MAPLOG" | tr -d ' ')" = 2 ] && ok "S4 재시도 1회(호출 2)" || bad "S4 호출 $(wc -l < "$MAPLOG" | tr -d ' ')"
hasnt "S4 ① lint 진입 0(부작용 0)" "$OUT" "LINT-OK"
grep -q 'new-session' "$TMUXLOG" && bad "S4 tmux new-session 호출됨" || ok "S4 tmux new-session 0"
[ ! -d "$R1/.worktrees" ] && ok "S4 워크트리 0" || bad "S4 워크트리 생김"
NOW_MD5="$(md5 -q "$R1/.fable-team/seats-alpha.json" 2>/dev/null || md5sum "$R1/.fable-team/seats-alpha.json" | cut -d' ' -f1)"
[ "$SEATS_MD5" = "$NOW_MD5" ] && ok "S4 명부 바이트 불변" || bad "S4 명부가 바뀌었다"
[ "$(leftover)" = 0 ] && ok "S5 REJECT 뒤 임시 사전 남음 0" || bad "S5 REJECT 뒤 임시 사전 $(leftover)개"

# ── S6 — 바깥이 준 사전: 새 생성 0 · 호출 0 · 내용 불변 · 지우기 0 ──
: > "$MAPLOG"
EXT="$T/outside-map.txt"; printf 'given.md\t2026-11-01\n' > "$EXT"; EXT_MD5="$(md5 -q "$EXT")"
OUT="$(FT_CARD_ADDED_MAP_FILE="$EXT" FT_TEST_MAP_RC=0 spr --dry-run)"; RC=$?
[ "$RC" = 0 ] && ok "S6 바깥 사전으로 rc0" || bad "S6 rc=$RC ← $(printf '%s' "$OUT" | tr '\n' ';')"
[ "$(wc -l < "$MAPLOG" | tr -d ' ')" = 0 ] && ok "S6 map_lint 호출 0(새 생성 0)" || bad "S6 map_lint 호출 $(wc -l < "$MAPLOG" | tr -d ' ')"
has "S6 ① lint 가 바깥 사전을 그대로 쓴다" "$OUT" "LINT-OK mapfile=$EXT"
[ -f "$EXT" ] && [ "$(md5 -q "$EXT")" = "$EXT_MD5" ] && ok "S6 바깥 사전 지우기 0 · 내용 불변" || bad "S6 바깥 사전이 지워졌거나 바뀌었다"
[ "$(leftover)" = 0 ] && ok "S6 임시 사전 새로 안 만듦" || bad "S6 임시 사전 $(leftover)개 생김"

# ── S2 — 진짜 ⑥(ft-index-move) 갈래: 사전이 있으면 git log 0 · 이동 rc0 / 대조군은 호출 ≥ 1 ──
R2="$T/repo2"; mkdir -p "$R2/design/harness/indices/대기" "$R2/design/harness"
env -u GIT_DIR -u GIT_WORK_TREE git init -q "$R2"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| planner | `design/planner/` | p | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$R2/design/TEAMS.md"
printf '닫는 증거 문장 하나는 여기에 길게 적혀 있다 스물자 넘게.\n' > "$R2/design/harness/GOAL.md"
printf 'x\n' > "$R2/design/harness/x.txt"
mkcard() {  # <파일> — 진짜 ft-index-lint 를 통과하는 최소 카드(사전 생성·이동 갈래를 실제로 태운다)
  cat > "$1" <<EOF
# 인덱스: $(basename "$1" .md) — 시험 카드
<!-- ledger: design/harness/GOAL.md -->
- Issue: #1
- 지시: r1398 시험
- 제안서: 없음 — 시험용
- 배정: 없음
- 설치: 있음
- 상태: 대기
- 선행: 없음
- 시험 입력: 없음
- 기준값: 없음 → 대체 축 없음
- 대상: $(cd "$(dirname "$1")" && pwd)/x.txt

## 골 원문 (항상 이 3줄)
목표는 AAAA 이다.
목표는 BBBB 이다.
목표는 CCCC 이다.

## 골좌표
닫는 증거: 「닫는 증거 문장 하나는 여기에 길게 적혀 있다 스물자 넘게.」

## 배경
r1398 시험 배경 한 단락.

## 구현 범위
- design/harness/x.txt 한 줄

## 완료 조건
- rc0

## 계약↔시험 대응표
| 계약 | 입력 | 기대 | 시험 |
|---|---|---|---|
| C1 | a | b | ① |

## 상태
- 대기
EOF
}
mkcard "$R2/design/harness/indices/대기/c1.md"; mkcard "$R2/design/harness/indices/대기/c2.md"
git -C "$R2" add -A && git -C "$R2" -c user.name=t -c user.email=t@t commit -qm init
RG="$(command -v git)"
GW="$T/gwcount"; mkdir -p "$GW"
printf '#!/bin/bash\ncase " $* " in *" log "*) echo "$*" >> "%s/logcnt";; esac\nexec "%s" "$@"\n' "$GW" "$RG" > "$GW/git"; chmod 755 "$GW/git"
GS="$T/gwslow"; mkdir -p "$GS"
printf '#!/bin/bash\ncase " $* " in *" log "*) echo "$*" >> "%s/logcnt"; sleep 8;; esac\nexec "%s" "$@"\n' "$GS" "$RG" > "$GS/git"; chmod 755 "$GS/git"
# 기준선: ⑥ 갈래(사전 없음) — lint 가 스스로 사전을 만든다 = git log 1회 · 8초 > spawn 기본 상한(7초 옛 판) → 이동 REJECT
: > "$GW/logcnt"
OUT0="$( cd "$R2" && PATH="$GW:$PATH" FT_GOAL_LINES_FILE="$GOODLINES" bash "$KIT/ft-index-move.sh" design/harness/indices/대기/c2.md 진행 --seat byz-harness-nano-x#0 2>&1 )"; RC0=$?
has "S2 대조군(사전 없음): lint 가 git log 를 부른다" "$(wc -l < "$GW/logcnt" | tr -d ' ')" "1"
git -C "$R2" checkout -q -- . 2>/dev/null; git -C "$R2" clean -qfd design/harness/indices 2>/dev/null
# S2 본판: spawn ① 앞 블록을 «그대로 떼어» 사전을 만들고, 같은 셸에서 ⑥(ft-index-move)로 잇는다 — 사전을 손으로 만들지 않는다.
BLK="$(awk '/^# r1398: 카드 이력 사전/{f=1} f{print} f&&/^fi$/{exit}' "$BIN/ft-nano-spawn.sh")"
{ [ -n "$BLK" ] && ok "S2 ① 앞 사전 블록 추출(spawn 원문)"; } || bad "S2 사전 블록 추출 0 — ft-nano-spawn.sh 에 r1398 블록이 없다"
CH="$T/chain.sh"
{ echo '_ON_EXIT=(); _on_exit() { local f; for f in ${_ON_EXIT[@]+"${_ON_EXIT[@]}"}; do "$f" || true; done; }; trap _on_exit EXIT'
  echo 'HERE="'"$BIN"'"; IDX="'"$R2"'/design/harness/indices/대기/c1.md"'
  printf '%s\n' "$BLK"
  echo 'echo "CHAIN-MAPFILE=${FT_CARD_ADDED_MAP_FILE:-none}"'
  echo 'bash "'"$KIT"'/ft-index-move.sh" "$IDX" 진행 --seat byz-harness-nano-x#0; echo "CHAIN-MOVE-RC=$?"'; } > "$CH"
: > "$GS/logcnt"
OUT="$( cd "$R2" && TMPDIR="$T/tmp" PATH="$GS:$PATH" FT_GOAL_LINES_FILE="$GOODLINES" bash "$CH" 2>&1 )"; RC=$?
has "S2 ① 앞 블록이 사전을 만든다" "$OUT" "CHAIN-MAPFILE=$T/tmp/ft-r1398-cardmap."
has "S2 ⑥ 이동 rc0(8초 지연 git log 를 안 탄다)" "$OUT" "CHAIN-MOVE-RC=0"
has "S2 이동 출력 MOVED" "$OUT" "MOVED 대기→진행"
[ "$(wc -l < "$GS/logcnt" | tr -d ' ')" = 1 ] && ok "S2 ⑥ 갈래 git log 이미 지나간 뒤 추가 호출 0(전체 1 = ① 사전 생성 몫)" || bad "S2 git log 총 $(wc -l < "$GS/logcnt" | tr -d ' ')회(1 이어야 한다)"
[ -f "$R2/design/harness/indices/진행/c1.md" ] && ok "S2 카드가 진행/ 으로 옮겨졌다" || bad "S2 카드 이동 0"
[ "$(leftover)" = 0 ] && ok "S5 블록 사전은 EXIT 에 지워진다(chain)" || bad "S5 chain 사전 $(leftover)개 남음"

# ── S7 — 진짜 판정기: 카드 이력 git 상한 25초(기본) · 문구 — 12초/26초 두 갈래는 서로 독립이라 같이 돌린다(같은 파일 안 2개 동시) ──
GP12="$T/gp12"; GP26="$T/gp26"; mkdir -p "$GP12" "$GP26"
printf '#!/bin/bash\ncase " $* " in *" log "*) sleep 12;; esac\nexec "%s" "$@"\n' "$RG" > "$GP12/git"; chmod 755 "$GP12/git"
printf '#!/bin/bash\ncase " $* " in *" log "*) sleep 26;; esac\nexec "%s" "$@"\n' "$RG" > "$GP26/git"; chmod 755 "$GP26/git"
( cd "$R2" && PATH="$GP12:$PATH" python3 "$MOD" --map-only design/harness/indices/대기/c2.md > "$T/s7a.out" 2>&1; echo $? > "$T/s7a.rc" ) &   # bg-ok: 12초 갈래 — 바로 아래 26초 갈래와 독립이라 같이 돌리고 wait 로 회수한다
( cd "$R2" && PATH="$GP26:$PATH" python3 "$MOD" --map-only design/harness/indices/대기/c2.md > "$T/s7b.out" 2>&1; echo $? > "$T/s7b.rc" ) &   # bg-ok: 26초 갈래 — 위와 같이 돌리고 wait 로 회수한다
wait
OUT="$(cat "$T/s7a.out")"; RC="$(cat "$T/s7a.rc")"
[ "$RC" = 0 ] && hasnt "S7 12초 지연은 25초 상한 안(rc0)" "$OUT" "판정 불가" || bad "S7 12초 rc=$RC $(printf '%s' "$OUT" | tr '\n' ';')"
OUT="$(cat "$T/s7b.out")"; RC="$(cat "$T/s7b.rc")"
[ "$RC" = 3 ] && ok "S7 26초 지연 → rc3(상한 넘음)" || bad "S7 26초 rc=$RC ← $(printf '%s' "$OUT" | tr '\n' ';')"
has "S7 문구 = git log 25초 상한 초과" "$OUT" "git log 25초 상한 초과"
grep -q 'git_sec' "$MOD" && ok "S7 상한 = 한 함수(git_sec) — 세 호출이 같은 값을 쓴다" || bad "S7 상한 함수 없음"

# ── S7b — 창 밖 카드 갈래(old_names: rev-list)도 같은 상한 · 사전이 있으면 그 갈래도 git 0 ──
GR="$T/grv"; mkdir -p "$GR"
printf '#!/bin/bash\ncase " $* " in *" rev-list "*) echo "$*" >> "%s/rvcnt"; sleep 2;; esac\nexec "%s" "$@"\n' "$GR" "$RG" > "$GR/git"; chmod 755 "$GR/git"
OUT="$( cd "$R2" && PATH="$GR:$PATH" FT_CARD_MAP_GIT_SEC=6 python3 "$MOD" --map-only design/harness/indices/대기/c2.md 2>&1 )"; RC=$?
[ "$RC" = 0 ] && ok "S7b rev-list 2초(상한 6초) → rc0" || bad "S7b rev-list 2초 rc=$RC ← $(printf '%s' "$OUT" | tr '\n' ';')"
printf '#!/bin/bash\ncase " $* " in *" rev-list "*) echo "$*" >> "%s/rvcnt"; sleep 3;; esac\nexec "%s" "$@"\n' "$GR" "$RG" > "$GR/git"; chmod 755 "$GR/git"
OUT="$( cd "$R2" && PATH="$GR:$PATH" FT_CARD_MAP_GIT_SEC=2 python3 "$MOD" --map-only design/harness/indices/대기/c2.md 2>&1 )"; RC=$?
[ "$RC" = 3 ] && has "S7b rev-list 3초(상한 2초) → rc3" "$OUT" "git log 2초 상한 초과" || bad "S7b rev-list 3초 rc=$RC ← $(printf '%s' "$OUT" | tr '\n' ';')"
: > "$GR/rvcnt"
( cd "$R2" && PATH="$GR:$PATH" FT_CARD_ADDED_MAP_FILE="$MAP2" FT_GOAL_LINES_FILE="$GOODLINES" python3 "$MOD" --map-only design/harness/indices/대기/c1.md ) >/dev/null 2>&1
[ "$(wc -l < "$GR/rvcnt" 2>/dev/null | tr -d ' ')" = 0 ] && ok "S7b 사전이 있으면 rev-list 호출 0" || bad "S7b 사전이 있는데 rev-list 호출 $(wc -l < "$GR/rvcnt" | tr -d ' ')"

# ── 정적: 기본 상한 25 · 세 곳 모두 같은 상한 함수를 쓴다(한 곳만 옛 값으로 남기 0) ──
grep -q '^GIT_SEC_DEFAULT = 25$' "$MOD" && ok "S7 기본 상한 = 25(상수)" || bad "S7 기본 상한 상수 없음/다름"
n7="$(grep -c 'timeout=7\|, timeout=7' "$MOD")"
[ "$n7" = 0 ] && ok "S7 timeout=7 잔재 0" || bad "S7 timeout=7 잔재 $n7곳"
nsec="$(( $(grep -c 'timeout=git_sec()' "$MOD") + $(grep -c 'timeout or git_sec()' "$MOD") ))"
[ "$nsec" = 3 ] && ok "S7 세 곳(log · rev-list · ls-tree/ls-files)이 같은 상한 함수" || bad "S7 상한 함수 쓰는 곳 $nsec (3 이어야 한다)"

echo "fail=$fail"; [ "$fail" = 0 ]
