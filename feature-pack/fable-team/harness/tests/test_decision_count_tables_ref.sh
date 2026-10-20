#!/usr/bin/env bash
# test_decision_count_tables_ref.sh — r517: ft-decision-count 의 planner 표(MERGE-QUEUE·FLAG-DECISIONS) = ref origin/main 명단으로 푼 경로의 ref 본문(공용 루트 체크아웃에 명단이 없어도 읽힌다).
#   ⓐ 체크아웃 명단 없음 → MERGE-QUEUE 를 ref 에서 읽어 rc0 · 대기 행 셈 반영(+ ⓐ2 카드 워크트리 디스크 표가 먼저)  ⓑ FLAG-DECISIONS 같은 꼴
#   ⓒ ref 에도 표 없음 → «(MERGE-QUEUE 파일 없음)» 메모 + rc0  ⓓ ref 명단 못 읽음(origin 없음) → rc4 + 사유  ⓔ FT_DECISION_MERGE_QUEUE 지정 = 그 파일
# 격리: 임시 리포 R(체크아웃 = 옛 커밋 · TEAMS.md 없음 · origin/main = 새 꼴 명단 + design/teams/planner 표) + 임시 인박스·대역 — 실 상태·실 mbox·외부 호출 0 · GIT_* env 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_TEAMS_REF FT_TEAMS_MD FT_REPO_ROOT FT_PLANNER_DIR \
  FT_DECISION_MERGE_QUEUE FT_DECISION_FLAG_DECISIONS FT_DECISION_AUTONOMY_QUEUE FT_DECISION_BUDGET_S
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
R="$T/repo"; P="design/teams/planner"
G() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
git init -q -b main "$R"; echo old > "$R/old.txt"; G "$R" add -A; G "$R" commit -qm old; G "$R" branch old   # 체크아웃 = 옛 main(명단 없음 · 공용 루트 2026-09-23 꼴)
mkdir -p "$R/$P"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `%s/` | x | 현역 |\n' "$P" > "$R/design/TEAMS.md"
G "$R" add design/TEAMS.md; G "$R" commit -qm teams; NOTAB="$(G "$R" rev-parse HEAD)"   # 명단만 · 표 0 (ⓒ)
printf '| 접수 | 상태 |\n|---|---|\n| a | 대기 |\n| b | ✅ 완료 |\n' > "$R/$P/MERGE-QUEUE.md"
printf '| 플래그 | 결정(켬/끔) | 판정 | 날짜 |\n|---|---|---|---|\n| NEXT_PUBLIC_FOO | 끔 | 판정 1 | 10-20 |\n' > "$R/$P/FLAG-DECISIONS.md"
G "$R" add -A; G "$R" commit -qm tables; TAB="$(G "$R" rev-parse HEAD)"
G "$R" update-ref refs/remotes/origin/main "$TAB"; G "$R" checkout -q old
[ ! -e "$R/design/TEAMS.md" ] && [ ! -e "$R/$P" ]; ck "준비: 체크아웃에 명단·planner 폴더 없음" $?

mkdir -p "$R/.fable-team/state/inbox"; : > "$R/.fable-team/state/inbox/byz-planner-master-claude.jsonl"
printf '{"_master":"byz-planner-master-claude#82","_cards_wt":"cards"}\n' > "$R/.fable-team/seats-planner.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/hil-stub.sh"
for f in ft_decision_count.py ft_team_lib.py; do cmp -s "$BIN/$f" "$KIT/$f"; ck "키트 미러 cmp 0: $f" $?; done

C() { out="$(cd "${CWD:-$R}" && env FT_ROOT="$R" FT_DECISION_AUTONOMY_QUEUE="$T/AQ-none.md" FT_DECISION_NOW=2026-10-20T08:00:00 FT_DECISION_HIL="$T/hil-stub.sh" \
  FT_DECISION_TMUX=false FT_FLAG_OFF_REPO="$R" FT_FLAG_OFF_REF=origin/main "$@" python3 "$BIN/ft_decision_count.py" 2>&1)"; rc=$?; }
TBL() { out="$(cd "$BIN" && env -i HOME="$HOME" PATH="$PATH" FT_ROOT="$R" python3 -I -c '
import sys; sys.path.insert(0, ".")
import ft_decision_count as c
t = c.table("NOENV", sys.argv[1], "cards")
print("NONE" if t is None else f"{len(t[0])} {t[1]}")' "$1" 2>&1)"; rc=$?; }

# ===== ⓐ 체크아웃 명단 없음 → MERGE-QUEUE = ref 본문 · rc0 · 대기 1 =====
C
[ "$rc" = 0 ] && grep -q '^결정 인터뷰 1건 · 스크립트 0건 · 팀 대기 0건' <<<"$out" && ! grep -q 'MERGE-QUEUE 파일 없음' <<<"$out"; ck "ⓐ 공용 루트 cwd: rc0 · 결정 인터뷰 1건(ref MERGE-QUEUE 대기 1)" $?
! grep -q '팀 명단 없음' <<<"$out"; ck "ⓐ «팀 명단 없음» 0(체크아웃 명단 안 씀)" $?
mkdir -p "$T/elsewhere"; git init -q "$T/elsewhere"; CWD="$T/elsewhere" C
[ "$rc" = 0 ] && grep -q '^결정 인터뷰 1건' <<<"$out"; ck "ⓐ 다른 리포 cwd(v6 대역): 같은 줄 rc0" $?
# ⓐ2 카드 워크트리(명단 있음 · 디스크 표 = 미착지 최신 행)가 ref 보다 먼저
W="$R/.worktrees/cards"; mkdir -p "$W/design/planner"; printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | x | 현역 |\n' > "$W/design/TEAMS.md"
printf '| 접수 | 상태 |\n|---|---|\n| a | 대기 |\n| c | 대기 |\n| d | 대기 |\n' > "$W/design/planner/MERGE-QUEUE.md"
C; [ "$rc" = 0 ] && grep -q '^결정 인터뷰 3건' <<<"$out"; ck "ⓐ2 카드 워크트리 MERGE-QUEUE(대기 3)가 ref(대기 1)보다 먼저" $?
rm -rf "$R/.worktrees"

# ===== ⓑ FLAG-DECISIONS 같은 꼴(ref 본문) =====
TBL FLAG-DECISIONS.md
[ "$rc" = 0 ] && grep -q "^1 \['플래그', '결정(켬/끔)', '판정', '날짜'\]" <<<"$out"; ck "ⓑ table(FLAG-DECISIONS) = ref 본문 1행 · 머리 4칸" $?
TBL MERGE-QUEUE.md
[ "$rc" = 0 ] && grep -q "^2 \['접수', '상태'\]" <<<"$out"; ck "ⓑ table(MERGE-QUEUE) = ref 본문 2행" $?
printf '| 아무 | 칸 |\n|---|---|\n| x | y |\n' > "$T/FD-badhead.md"; G "$R" checkout -q main; cp "$T/FD-badhead.md" "$R/$P/FLAG-DECISIONS.md"
G "$R" commit -qam badfd; G "$R" update-ref refs/remotes/origin/main HEAD; G "$R" checkout -q old
C; [ "$rc" = 4 ] && grep -q 'FLAG-DECISIONS 표 머리에 «플래그» 칸이 없다' <<<"$out"; ck "ⓑ 변이: ref FLAG-DECISIONS 머리 손상 → rc4(ref 본문이 실제로 판정에 쓰인다)" $?
G "$R" update-ref refs/remotes/origin/main "$TAB"

# ===== ⓒ ref 에도 표 없음 → 메모 + rc0 =====
G "$R" update-ref refs/remotes/origin/main "$NOTAB"
C; [ "$rc" = 0 ] && grep -q '^결정 인터뷰 0건' <<<"$out" && grep -q '(MERGE-QUEUE 파일 없음)' <<<"$out"; ck "ⓒ ref 에 표 없음 → «(MERGE-QUEUE 파일 없음)» + rc0" $?
TBL FLAG-DECISIONS.md; [ "$rc" = 0 ] && [ "$out" = NONE ]; ck "ⓒ table(FLAG-DECISIONS) = None(파일 없음은 실패 아님)" $?
G "$R" update-ref refs/remotes/origin/main "$TAB"

# ===== ⓓ ref 명단 못 읽음(origin 없음) → rc4 + 사유 =====
G "$R" update-ref -d refs/remotes/origin/main
C; [ "$rc" = 4 ] && grep -q '^ERROR ft-decision-count: .*명단 ref 못 읽음(origin/main:design/TEAMS.md)' <<<"$out" && ! grep -q '^결정 인터뷰' <<<"$out"; ck "ⓓ origin 없음 → rc4 + «명단 ref 못 읽음» · 숫자 0" $?
G "$R" update-ref refs/remotes/origin/main "$TAB"

# ===== ⓔ env 지정 = 그 파일(덮어쓰기 유지) =====
printf '| 접수 | 상태 |\n|---|---|\n| x | 대기 |\n| y | 대기 |\n| z | 대기 |\n' > "$T/MQ.md"
C FT_DECISION_MERGE_QUEUE="$T/MQ.md"; [ "$rc" = 0 ] && grep -q '^결정 인터뷰 3건' <<<"$out"; ck "ⓔ FT_DECISION_MERGE_QUEUE = 그 파일(대기 3)" $?
C FT_DECISION_MERGE_QUEUE="$T/MQ-none.md"; [ "$rc" = 0 ] && grep -q '^결정 인터뷰 0건' <<<"$out" && grep -q '(MERGE-QUEUE 파일 없음)' <<<"$out"; ck "ⓔ env 파일 없음 = 지금처럼 메모(ref 로 새지 않음)" $?

n="$(wc -l < "$BIN/ft_decision_count.py" | tr -d ' ')"; [ "$n" -le 200 ]; ck "ft_decision_count.py ${n}줄 ≤ 200" $?
python3 -B -c 'import sys; [compile(open(f, encoding="utf-8").read(), f, "exec") for f in sys.argv[1:]]' "$BIN/ft_decision_count.py" "$BIN/ft_team_lib.py"; ck "compile 2(바이트코드 파일 0)" $?
echo "== FAIL $fail"; [ "$fail" = 0 ]
