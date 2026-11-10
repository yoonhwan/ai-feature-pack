#!/usr/bin/env bash
# test_proxy_decide_queue_card_resolve.sh — r515: 오빠 큐 자리 = 리졸버 ft_planner_queue 1개(대리·자율 상태·결정 셈이 같이 씀) · card-start 카드 상대경로 = cwd → ref 순.
#   ⓐ 옛 꼴 체크아웃(데이터 루트 · 이동 전 가지) QUEUE → 공용 루트 state/planner 큐 1행 · 옛 자리 쓰기 0  ⓑ ft-autonomy·ft_decision_count 가 같은 파일(경로 글자 같음)
#   ⓒ FT_PLANNER_DIR 덮어쓰기 = 그 폴더  ⓓ cwd 에 없고 ref 에 있는 카드 → 읽음 · 판정 줄 검사로 진행  ⓔ 둘 다 없음 → QUEUE 사유에 두 자리  ⓕ 절대경로 = 그 파일만  ⓖ path-lint 키트 5파일
# 격리: 임시 리포 R(main = 새 꼴 · origin/main ref) + 워크트리 W(옛 꼴 가지 = 데이터 루트) + 임시 상태 — 실 상태·실 mbox·외부 호출 0 · GIT_* env 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_PLANNER_DIR FT_TEAMS_REF FT_TEAMS_MD FT_REPO_ROOT FT_DECISION_AUTONOMY_QUEUE
export FT_AUTONOMY_LEVEL=each   # r466: 레벨 밖 시험 — 실 슬랙 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
R="$T/repo"; W="$R/.worktrees/live"; S="$T/state"
G() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
git init -q -b main "$R"; mkdir -p "$R/design/planner" "$R/design/loom/indices/대기" "$S" "$T/gb"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `%s` | x | 현역 |\n| loom | `%s` | x | 현역 |\n' design/planner/ design/loom/ > "$R/design/TEAMS.md"
printf '%s\n' '- **100** (오빠) loom-x 착수 승인' > "$R/design/planner/VERDICTS-planner-1-20261020.md"
echo keep > "$R/design/loom/indices/대기/.keep"
G "$R" add -A; G "$R" commit -qm old; G "$R" branch old
mkdir -p "$R/design/teams"; G "$R" mv design/planner design/teams/planner; G "$R" mv design/loom design/teams/loom
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `%s` | x | 현역 |\n| loom | `%s` | x | 현역 |\n' design/teams/planner/ design/teams/loom/ > "$R/design/TEAMS.md"
CREL="design/teams/loom/indices/대기/loom-x.md"
printf '# 인덱스: loom-x\n## 구현 범위\n1. 도구 하나.\n' > "$R/$CREL"
G "$R" add -A; G "$R" commit -qm move; G "$R" update-ref refs/remotes/origin/main main
G "$R" worktree add -q "$W" old
NEWQ="$R/.fable-team/state/planner/AUTONOMY-QUEUE.md"; OLDQ="$W/design/planner/AUTONOMY-QUEUE.md"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/gb/gcloud"; chmod +x "$T/gb/gcloud"
export FT_ROOT="$W" FT_AUTONOMY_STATE_DIR="$S" FT_AUTONOMY_HOOK_LOG="$T/hook.log" PATH="$T/gb:$PATH"
"$BASH" "$BIN/ft-autonomy.sh" on >/dev/null 2>&1; [ "$("$BASH" "$BIN/ft-autonomy.sh" mode)" = on ]; ck "준비: 자율 ON" $?
for f in ft-team-lib.sh ft-proxy-decide.sh ft-autonomy.sh ft_decision_count.py ft_team_lib.py; do cmp -s "$BIN/$f" "$KIT/$f"; ck "키트 미러 cmp 0: $f" $?; done

n=0
D() { n=$((n+1)); out="$(cd "${CWD:-$W}" && "$BASH" "$BIN/ft-proxy-decide.sh" --q "질문 $n" --choice 추천 --why 근거 --undo 되돌림 "$@" 2>&1)"; rc=$?; }
led() { grep -c '\[대리 · 자율 ON' "$W/design/planner/VERDICTS-planner-1-20261020.md"; }

# ===== ⓐ 옛 꼴 데이터 루트 QUEUE → 리졸버 자리(공용 루트 state) 1행 · 옛 자리 0 =====
D --kind card-start --card "$T/none.md" --verdict 100
[ "$rc" = 2 ] && [ "$(grep -c '| card-start |' "$NEWQ" 2>/dev/null)" = 1 ]; ck "ⓐ card-start QUEUE → $NEWQ 에 1행" $?
[ ! -e "$OLDQ" ]; ck "ⓐ 옛 자리($OLDQ) 쓰기 0" $?
grep -qF "큐 파일 $NEWQ" <<<"$out"; ck "ⓐ QUEUE 출력의 큐 파일 = 리졸버 자리" $?

# ===== ⓑ 자율 상태·결정 셈이 같은 파일 =====
sq="$(cd "$W" && FT_ROOT="$W" "$BASH" -c ". '$BIN/ft-team-lib.sh' && ft_planner_queue '$W'")"
pq="$(cd "$W" && python3 -c "import sys;sys.path.insert(0,'$BIN');from ft_team_lib import planner_queue;print(planner_queue('$W'))")"
[ "$sq" = "$NEWQ" ] && [ "$pq" = "$NEWQ" ]; ck "ⓑ 셸·파이썬 리졸버 경로 글자 같음 ($sq | $pq)" $?
out="$("$BASH" "$BIN/ft-autonomy.sh" status 2>&1)"; grep -qF '큐 1' <<<"$out"; ck "ⓑ ft-autonomy status 큐 1 (리졸버 자리에서 셈)" $?
mkdir -p "$W/.fable-team/state/inbox" "$T/hil"; : > "$W/.fable-team/state/inbox/p.jsonl"; printf '{"_master":"p#1","_cards_wt":"none"}\n' > "$W/.fable-team/seats-planner.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/stub.sh"; chmod +x "$T/stub.sh"; git init -q "$T/flag"; G "$T/flag" commit -q --allow-empty -m e
out="$(cd "$W" && FT_DECISION_NOW=2026-10-20T07:00:00 HIL_DIR="$T/hil" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_DECISION_MBOX="$T/stub.sh" FT_DECISION_TMUX="$T/stub.sh" \
  FT_DECISION_MERGE_QUEUE="$T/MQ.md" FT_FLAG_OFF_REPO="$T/flag" FT_FLAG_OFF_REF=HEAD bash "$BIN/ft-decision-count.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -qF '결정 인터뷰 1건' <<<"$out" && ! grep -qF 'AUTONOMY-QUEUE 파일 없음' <<<"$out"; ck "ⓑ ft-decision-count 가 같은 큐 행 1 을 셈" $?
rm -f "$W/.fable-team/seats-planner.json"
# 운영 꼴(FT_ROOT 없음): 데이터 루트 = 공용 루트 .fable-team/LIVE_ROOT 1행 — 대리 도구·결정 셈이 같은 자리
mkdir -p "$R/.fable-team/state/inbox"; echo "$W" > "$R/.fable-team/LIVE_ROOT"; : > "$R/.fable-team/state/inbox/p.jsonl"; printf '{"_master":"p#1","_cards_wt":"none"}\n' > "$R/.fable-team/seats-planner.json"
out="$(cd "$R" && env -u FT_ROOT "$BASH" "$BIN/ft-proxy-decide.sh" --kind card-start --card "$T/none2.md" --verdict 100 --q "live 질문" --choice c --why w --undo u 2>&1)"; rc=$?
[ "$rc" = 2 ] && grep -qF "큐 파일 $NEWQ" <<<"$out" && [ "$(grep -c '| card-start |' "$NEWQ")" = 2 ]; ck "ⓑ FT_ROOT 없음(LIVE_ROOT) proxy-decide 큐 = 같은 자리 2행" $?
out="$(cd "$R" && env -u FT_ROOT FT_DECISION_NOW=2026-10-20T07:00:00 HIL_DIR="$T/hil" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_DECISION_MBOX="$T/stub.sh" FT_DECISION_TMUX="$T/stub.sh" \
  FT_DECISION_MERGE_QUEUE="$T/MQ.md" FT_FLAG_OFF_REPO="$T/flag" FT_FLAG_OFF_REF=HEAD bash "$BIN/ft-decision-count.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -qF '결정 인터뷰 2건' <<<"$out"; ck "ⓑ FT_ROOT 없음(LIVE_ROOT) ft-decision-count 가 같은 자리 2행을 셈" $?
echo "relative" > "$R/.fable-team/LIVE_ROOT"; out="$(cd "$R" && env -u FT_ROOT python3 -c "import sys;sys.path.insert(0,'$BIN');from ft_team_lib import data_root;data_root('$R')" 2>&1)"; rc=$?
[ "$rc" != 0 ] && grep -qF 'LIVE_ROOT 가 절대경로 폴더가 아님' <<<"$out"; ck "ⓑ 파이썬 data_root: LIVE_ROOT 상대경로 = ERROR(조용한 대체 0)" $?
rm -f "$R/.fable-team/LIVE_ROOT" "$R/.fable-team/seats-planner.json"

# ===== ⓒ FT_PLANNER_DIR 덮어쓰기 유지 =====
out="$(FT_PLANNER_DIR="$T/pd" "$BASH" -c ". '$BIN/ft-team-lib.sh' && ft_planner_queue '$W'")"; [ "$out" = "$T/pd/AUTONOMY-QUEUE.md" ]; ck "ⓒ 셸 FT_PLANNER_DIR = 그 폴더" $?
out="$(FT_PLANNER_DIR="$T/pd" python3 -c "import sys;sys.path.insert(0,'$BIN');from ft_team_lib import planner_queue;print(planner_queue('$W'))")"; [ "$out" = "$T/pd/AUTONOMY-QUEUE.md" ]; ck "ⓒ 파이썬 FT_PLANNER_DIR = 그 폴더" $?
mkdir -p "$T/pd"; cp "$W/design/planner/VERDICTS-planner-1-20261020.md" "$T/pd/"
FT_PLANNER_DIR="$T/pd" D --kind card-start --card "$T/none.md" --verdict 100; [ "$rc" = 2 ] && [ -f "$T/pd/AUTONOMY-QUEUE.md" ]; ck "ⓒ proxy-decide FT_PLANNER_DIR 큐 = 그 폴더" $?
out="$(cd "$R" && FT_ROOT="$R" "$BASH" -c ". '$BIN/ft-team-lib.sh' && ft_planner_queue '$R'")"; [ "$out" = "$R/design/teams/planner/AUTONOMY-QUEUE.md" ]; ck "ⓒ 새 꼴 체크아웃 루트 = 명단 꼴 폴더" $?

# ===== ⓓ cwd 에 없고 ref 에 있는 카드 → 읽음 =====
[ ! -e "$W/$CREL" ]; ck "ⓓ 전제: 카드가 cwd(W) 에 없음" $?
n0="$(led)"; D --kind card-start --card "$CREL" --verdict 100
[ "$rc" = 0 ] && grep -q '^PROXY' <<<"$out" && [ "$(led)" = "$((n0+1))" ]; ck "ⓓ ref 카드 읽음 → 판정 줄 검사 통과 PROXY" $?
D --kind card-start --card "$CREL" --verdict 999; [ "$rc" = 2 ] && grep -qF '원장에 판정 999 줄 없음' <<<"$out"; ck "ⓓ ref 카드 읽은 뒤 판정 줄 검사가 계속 돈다(없는 판정 → QUEUE)" $?

# ===== ⓔ cwd·ref 둘 다 없음 → QUEUE 두 자리 =====
D --kind card-start --card design/teams/loom/indices/대기/ghost.md --verdict 100
[ "$rc" = 2 ] && grep -qF "카드를 못 읽음: $W/design/teams/loom/indices/대기/ghost.md · origin/main:design/teams/loom/indices/대기/ghost.md" <<<"$out"; ck "ⓔ 못 읽음 사유에 cwd 경로 · ref 경로 둘 다" $?

# ===== ⓕ 절대경로 = 그 파일만 =====
D --kind card-start --card "$W/$CREL" --verdict 100; [ "$rc" = 2 ] && grep -qF "카드를 못 읽음: $W/$CREL" <<<"$out" && ! grep -qF 'origin/main:' <<<"$out"; ck "ⓕ 절대경로 없는 파일 → ref 로 안 감" $?
mkdir -p "$T/abs"; printf '# 인덱스: loom-x\n## 구현 범위\n1. 도구.\n' > "$T/abs/loom-x.md"
D --kind card-start --card "$T/abs/loom-x.md" --verdict 100; [ "$rc" = 0 ]; ck "ⓕ 절대경로 실재 파일 → 그 파일로 PROXY" $?

# ===== ⓖ path-lint =====
out="$(cd "$HERE" && "$BASH" "$BIN/ft-team-path-lint.sh" "$KIT" 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -qF 'OK 하드코딩 0' <<<"$out"; ck "ⓖ ft-team-path-lint 키트 폴더(5파일 포함) OK 하드코딩 0" $?
for f in ft-team-lib.sh ft-proxy-decide.sh ft-autonomy.sh; do bash -n "$KIT/$f"; ck "bash -n $f" $?; done
python3 -m py_compile "$KIT/ft_decision_count.py" "$KIT/ft_team_lib.py"; ck "py_compile" $?
[ "$(wc -l < "$KIT/ft-proxy-decide.sh")" -le 200 ]; ck "ft-proxy-decide 200줄 이하" $?

echo "== $([ "$fail" = 0 ] && echo ALL PASS || echo "FAIL $fail")"
[ "$fail" = 0 ]
