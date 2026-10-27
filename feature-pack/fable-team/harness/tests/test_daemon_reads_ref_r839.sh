#!/usr/bin/env bash
# test_daemon_reads_ref_r839.sh — r839: 읽기만 하는 잡(결정 셈)이 정본 문서를 «루트 디스크» 가 아니라 «origin/main 판 본문» 으로 읽는다 · ref 읽기 git 호출은 시도당 7초 상한(넘으면 ERROR rc, 디스크 후퇴 0).
#   ⓐ 결정 셈 = origin/main 판 AUTONOMY-QUEUE(새 줄 반영 · 디스크 옛 본문 0) · 루트 작업 폴더·index 변경 0
#   ⓑ origin/main 판에 파일 없음 → 결정 셈 0(지금 규칙) · ref 못 읽음 → ERROR + rc4(숫자 0)
#   ⓒ ft_team_doc_ref_only = ref 본문(디스크 옛 본문 0) · ref 에 없음 → ERROR rc1
#   ⓓ ft-queue.sh = 옮긴 공용 함수 호출(자체 정의 0 · r557 시험 그대로)
#   ⓔ FT_PLANNER_DIR·FT_DECISION_AUTONOMY_QUEUE = 그 경로 그대로
#   ⓣ 상한: `git show` 8초 지연 래퍼 → ft_planner_queue_ref·ft_team_doc_ref_only·결정 셈 ERROR · 경과 ≤ 9초 · 남은 자식 0 · TERM 무시 래퍼도 ≤ 9초(KILL) · 첫 시도 «출력 0» 은 재시도 1회로 정상
#   ⓐⓑⓒ DA⑥ r4·r5: 빈 값 2회 = ERROR rc4 · 재시도 딱 1회(파이썬 한 벌) · 예산 소진 = rc4(미종료 0) · cat-file rc128 = 판정 불가 · 오류 1줄
#   ⓖ DA⑥ r2 반례: 빈 출력으로 «없음/0건» 을 가장하지 않는다 · 큐 명령 오류 문구 = 기준판 바이트 그대로
#   ⓕ 키트 미러 cmp 0 · bash -n · 정적 검사(ref_read 밖 git 0) · 변이 7종 → 해당 칸 FAIL
# 격리: 임시 bare 원격 + 임시 «루트» 클론(원격 main 보다 뒤 · 작업 폴더에 옛 큐 · 합치다 만 UU 1) · 가짜 tmux·hil · 실 리포·실 launchd 0 · GIT_* 0.
#   R839_BIN=<옛 bin 폴더> 로 돌리면 기준판(빨강) 대조 — 미러 cmp·변이·ⓓ 는 건너뜀.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_TEAMS_REF FT_TEAMS_MD FT_REPO_ROOT FT_PLANNER_DIR FT_LEDGER_REPO \
  FT_REF_GIT_SEC FT_DECISION_MERGE_QUEUE FT_DECISION_FLAG_DECISIONS FT_DECISION_AUTONOMY_QUEUE FT_DECISION_BUDGET_S FT_QUEUE_FILE FT_ROOT
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="${R839_BIN:-$HERE/../bin}"; KIT="$HERE/../kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
G() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
now() { python3 -c 'import time;print(time.time())'; }
le() { python3 -c 'import sys,time;sys.exit(0 if time.time()-float(sys.argv[1])<=float(sys.argv[2]) else 1)' "$1" "$2"; }
mkq() { # $1 파일 · $2 열린 A9 줄 수 · $3 표지
  { printf '# AUTONOMY-QUEUE\n\n| 자율 | 시각 | 종류 | 질문 | 추천안 | 사유 | 상태 | 번호 | 팀 | 보여준 시각 |\n|---|---|---|---|---|---|---|---|---|---|\n'
    for i in $(seq 1 "$2"); do printf '| A9 | 2026-10-24 08:00 | card-start | %s %s | 추 | 사 | 대기 | q%s | graphics | - |\n' "$3" "$i" "$i"; done; } > "$1"; }
QP="design/teams/planner/AUTONOMY-QUEUE.md"

# ── 픽스처: 원격 main = 새 판(큐 3줄) · 루트 = 옛 판(큐 1줄) + 합치다 만 UU + 원격보다 뒤
REM="$T/remote.git"; S="$T/seed"; RT="$T/root"
git init -q --bare -b main "$REM"; git init -q -b main "$S"; mkdir -p "$S/design"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `design/teams/planner/` | x | 현역 |\n' > "$S/design/TEAMS.md"
mkdir -p "$S/design/teams/planner"; mkq "$S/$QP" 1 옛줄; echo base > "$S/conflict.txt"
G "$S" add -A; G "$S" commit -qm old; G "$S" remote add origin "$REM"; G "$S" push -q origin main
git clone -q "$REM" "$RT" 2>/dev/null
G "$RT" checkout -q -b side; echo side > "$RT/conflict.txt"; G "$RT" commit -qam side
G "$RT" checkout -q main; echo ours > "$RT/conflict.txt"; G "$RT" commit -qam ours
G "$RT" merge -q side >/dev/null 2>&1
mkq "$S/$QP" 3 새줄; G "$S" add -A; G "$S" commit -qm new
echo x > "$S/more.txt"; G "$S" add -A; G "$S" commit -qm more; G "$S" push -q origin main
G "$S" checkout -q -b noq; G "$S" rm -q "$QP"; G "$S" commit -qm noq; G "$S" push -q origin noq; G "$S" checkout -q main
G "$S" checkout -q -b emptyq; : > "$S/$QP"; G "$S" add -A; G "$S" commit -qm emptyq; G "$S" push -q origin emptyq; G "$S" checkout -q main
G "$RT" fetch -q origin
printf '.fable-team/\n' >> "$RT/.git/info/exclude"
F="$RT/.fable-team"; mkdir -p "$F/state/inbox" "$F/comm"; : > "$F/state/inbox/byz-planner-master-claude.jsonl"
printf '{"_master":"byz-planner-master-claude#82","_cards_wt":"cards"}\n' > "$F/seats-planner.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/hil-stub.sh"
PD="$T/pdir"; mkdir -p "$PD"; mkq "$PD/AUTONOMY-QUEUE.md" 4 플래너폴더; mkq "$T/AQ.md" 2 직접지정
snap() { { G "$RT" status --porcelain=v1 -uall; G "$RT" ls-files -s; G "$RT" rev-parse HEAD MERGE_HEAD; cat "$RT/$QP"; } 2>&1 | shasum | cut -c1-12; }
tmux() { [ "$1" = has-session ]; }; export -f tmux
# 느린 git: AUTONOMY-QUEUE 본문 `show` 만 12초 지연($2=1 이면 TERM 무시) — 나머지 호출은 진짜 git · 띄운 pid 를 <d>/pids 에 남긴다(«남은 자식 0» 판정용)
REALGIT="$(command -v git)"
slowgit() { local d="$1" trapme="${2:-0}"; mkdir -p "$d"
  { printf '#!/bin/bash\n'; [ "$trapme" = 1 ] && printf "trap '' TERM\n"
    printf 'for a in "$@"; do case "$a" in *AUTONOMY-QUEUE.md) echo "$$" >> %s/pids; sleep 12 & sp=$!; echo "$sp" >> %s/pids; wait;; esac; done\nexec %s "$@"\n' "$d" "$d" "$REALGIT"; } > "$d/git"; chmod +x "$d/git"; }
alive_pids() { local f="$1/pids" p n=0; [ -f "$f" ] || { echo 0; return 0; }
  while IFS= read -r p; do [ -n "$p" ] && kill -0 "$p" 2>/dev/null && n=$((n+1)); done < "$f"; echo "$n"; }
slowgit "$T/slow"; slowgit "$T/noterm" 1
mkdir -p "$T/empty"   # AUTONOMY-QUEUE 본문만 첫 시도 «출력 0»
{ printf '#!/bin/bash\nfor a in "$@"; do case "$a" in *AUTONOMY-QUEUE.md) [ -f %s/once ] || { : > %s/once; exit 0; };; esac; done\nexec %s "$@"\n' "$T/empty" "$T/empty" "$REALGIT"; } > "$T/empty/git"; chmod +x "$T/empty/git"
# 파이썬 첫 조회 «출력 0·rc0» — $1 = ls-tree | show 만 비운다(DA⑥ r2 반례 ①)
pyempty() { local d="$T/py-$1"; mkdir -p "$d"
  { printf '#!/bin/bash\nhit=0; q=0\nfor a in "$@"; do [ "$a" = %s ] && hit=1; case "$a" in *AUTONOMY-QUEUE.md) q=1;; esac; done\nif [ "$hit" = 1 ] && [ "$q" = 1 ] && [ ! -f %s/once ]; then : > %s/once; exit 0; fi\nexec %s "$@"\n' "$1" "$d" "$d" "$REALGIT"; } > "$d/git"; chmod +x "$d/git"; }
pyempty ls-tree; pyempty show
# DA⑥ r4 반례 — AUTONOMY-QUEUE 본문 `show` 가 «항상 빈 값» / «N번 빈 뒤 본문» / «빈 값+6초» · 나머지는 진짜 git
showfake() { local d="$1" n="$2" delay="${3:-0}"; mkdir -p "$d"; echo 0 > "$d/n"
  { printf '#!/bin/bash\nfor a in "$@"; do case "$a" in *AUTONOMY-QUEUE.md) c=$(cat %s/n); [ -n "$c" ] || c=0; if [ "$c" -lt %s ]; then echo $((c+1)) > %s/n; [ %s -gt 0 ] && sleep %s; exit 0; fi;; esac; done\nexec %s "$@"\n' "$d" "$n" "$d" "$delay" "$delay" "$REALGIT"; } > "$d/git"; chmod +x "$d/git"; }
showfake "$T/show-empty" 99; showfake "$T/show-empty2" 2; showfake "$T/show-slow-empty" 99 6
# r5 반례 — cat-file 만 rc128(stderr 0) / 큐 본문 show 만 rc42 / 모든 git 이 0.7초 지연
mkdir -p "$T/catfail" "$T/showfail" "$T/slow07"
{ printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = cat-file ] && exit 128; done\nexec %s "$@"\n' "$REALGIT"; } > "$T/catfail/git"
{ printf '#!/bin/bash\ns=0; q=0\nfor a in "$@"; do [ "$a" = show ] && s=1; case "$a" in *AUTONOMY-QUEUE.md) q=1;; esac; done\n[ "$s" = 1 ] && [ "$q" = 1 ] && exit 42\nexec %s "$@"\n' "$REALGIT"; } > "$T/showfail/git"
{ printf '#!/bin/bash\nsleep 0.7\nexec %s "$@"\n' "$REALGIT"; } > "$T/slow07/git"
chmod +x "$T/catfail/git" "$T/showfail/git" "$T/slow07/git"

suite() { # $1 = bin 폴더 — 줄마다 PASS/FAIL «칸»
  local B="$1" out rc s
  ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fi; }
  C() { out="$(cd "$RT" && env FT_ROOT="$RT" FT_DECISION_NOW=2026-10-24T09:00:00 FT_DECISION_HIL="$T/hil-stub.sh" FT_DECISION_TMUX=false \
      FT_FLAG_OFF_REPO="$RT" FT_FLAG_OFF_REF=origin/main "$@" python3 "$B/ft_decision_count.py" 2>&1)"; rc=$?; }
  # lib 함수 1회 호출: $1 = PATH 앞 폴더 · $2 = 함수 이름
  L() { out="$(cd "$RT" && env FT_ROOT="$RT" PATH="$1:$PATH" bash -c ". \"\$0/ft-team-lib.sh\" && $2" "$B" 2>&1)"; rc=$?; }
  local s0; s0="$(snap)"
  [ "$(G "$RT" rev-list --count HEAD..origin/main)" -ge 2 ] && G "$RT" status --porcelain | grep -q '^UU conflict.txt' && grep -q '옛줄' "$RT/$QP"
  rc=$?; out=""; ck "준비: 루트 = 원격보다 뒤 · UU 1 · 디스크 옛 큐(1줄)" $rc
  # ⓐ 결정 셈 = ref 판
  C; echo "  ⓐ 원문: $out"
  [ "$rc" = 0 ] && grep -q '^결정 인터뷰 3건 ' <<<"$out"; ck "ⓐ 결정 셈 = origin/main 판 큐 3줄(디스크 옛 1줄 아님)" $?
  [ "$(snap)" = "$s0" ]; ck "ⓐ 루트 작업 폴더·index·HEAD·MERGE_HEAD 변경 0" $?
  # ⓑ 판에 없음 = 0 · 못 읽음 = ERROR rc4
  C FT_TEAMS_REF=origin/noq; echo "  ⓑ 원문(파일 없음): $out"
  [ "$rc" = 0 ] && grep -q '^결정 인터뷰 0건 ' <<<"$out"; ck "ⓑ ref 판에 큐 없음 → 결정 셈 0(파일 없음 = 0 · 디스크 1줄로 후퇴 0)" $?
  C FT_TEAMS_REF=origin/nope; echo "  ⓑ 원문(ref 없음): $out"
  [ "$rc" = 4 ] && grep -q '^ERROR ft-decision-count: ' <<<"$out" && ! grep -q '^결정 인터뷰' <<<"$out"; ck "ⓑ ref 못 읽음 → ERROR 1줄 + rc4 · 숫자 0" $?
  # ⓒ ft_team_doc_ref_only = ref 본문 / ref 에 없음 = ERROR
  L "$T/fast" 'ft_team_doc_ref_only "$FT_ROOT" planner AUTONOMY-QUEUE.md'; echo "  ⓒ 원문: $out"
  [ "$rc" = 0 ] && [ -n "$out" ] && grep -q '새줄' "$out" && ! grep -q '옛줄' "$out" && case "$out" in "$TMPDIR"/ft-team-doc.*) true;; *) false;; esac
  rc=$?; ck "ⓒ ft_team_doc_ref_only = origin/main 판 본문(디스크 옛 본문 0 · 임시 파일)" $rc
  [ -n "${out:-}" ] && [ -f "${out:-/nonexistent}" ] && rm -f "$out"
  L "$T/fast" 'FT_TEAMS_REF=origin/noq ft_team_doc_ref_only "$FT_ROOT" planner AUTONOMY-QUEUE.md'; echo "  ⓒ 원문(없음): $out"
  [ "$rc" = 1 ] && grep -q '^ERROR planner ' <<<"$out" && case "$out" in *'옛줄'*) false;; *) true;; esac; ck "ⓒ ref 판에 없음 → ERROR rc1(디스크 옛 본문 후퇴 0)" $?
  [ -z "$(ls -A "$TMPDIR")" ]; ck "ⓒ 임시 본문 정리(TMPDIR 비어 있음)" $?
  # ⓖ DA⑥ r2 반례 ② — 큐 명령 오류 문구 = 기준판 바이트 그대로
  L "$T/fast" 'FT_TEAMS_REF=origin/noq ft_planner_queue_ref "$FT_ROOT"'; echo "  ⓖ 원문(큐 판 없음): $out"
  [ "$rc" = 1 ] && [ "$out" = "ERROR 오빠 큐 origin/main 판을 못 읽음: origin/noq:design/teams/planner/AUTONOMY-QUEUE.md" ]; ck "ⓖ 큐 판 없음 → 기준판 문구 바이트 그대로 · rc1" $?
  L "$T/fast" 'FT_TEAMS_REF=origin/emptyq ft_planner_queue_ref "$FT_ROOT"'; echo "  ⓖ 원문(빈 큐 판): $out"
  [ "$rc" = 1 ] && [ "$out" = "ERROR 오빠 큐 origin/main 판을 못 읽음: origin/emptyq:design/teams/planner/AUTONOMY-QUEUE.md" ]; ck "ⓖ 빈 큐 판 → 기준판 문구·rc1 그대로(«판이 비었다» 0)" $?
  L "$T/fast" 'FT_TEAMS_REF=origin/nope ft_planner_queue_ref "$FT_ROOT"'; echo "  ⓖ 원문(없는 ref): $out"
  [ "$rc" = 1 ] && [ "$out" = "ERROR planner 명단(origin/nope:design/TEAMS.md)을 못 읽음: $RT" ]; ck "ⓖ 없는 ref → 기준판 명단 문구 바이트 그대로" $?
  # ⓖ DA⑥ r2 반례 ① — 파이썬 첫 조회 «출력 0·rc0» 은 재시도 1회(0건으로 읽지 않는다)
  rm -f "$T/py-ls-tree/once"; C PATH="$T/py-ls-tree:$PATH"; echo "  ⓖ 원문(빈 ls-tree): $out"
  [ "$rc" = 0 ] && grep -q '^결정 인터뷰 3건 ' <<<"$out"; ck "ⓖ 첫 ls-tree 출력 0 → 재시도 1회로 3건(0건 아님)" $?
  rm -f "$T/py-show/once"; C PATH="$T/py-show:$PATH"; echo "  ⓖ 원문(빈 show): $out"
  [ "$rc" = 0 ] && grep -q '^결정 인터뷰 3건 ' <<<"$out"; ck "ⓖ 첫 show 출력 0 → 재시도 1회로 3건(«표가 없다» rc4 아님)" $?
  # ⓐ DA⑥ r4 — 두 번 연속 빈 값(rc0) = ERROR rc4 «빈 응답 2회» · 재시도는 «딱 1회» · 결정 0건 출력 0
  L "$T/show-empty" 'ref_read "$FT_ROOT" show origin/main:design/teams/planner/AUTONOMY-QUEUE.md'; echo "  ⓐ 원문(빈 2회): $out"
  [ "$rc" = 4 ] && grep -q '^ERROR 빈 응답 2회: git -C ' <<<"$out"; ck "ⓐ 셸 ref_read 빈 값 2회 → ERROR rc4 «빈 응답 2회»" $?
  L "$T/show-empty2" 'ref_read "$FT_ROOT" show origin/main:design/teams/planner/AUTONOMY-QUEUE.md'; echo "  ⓐ 원문(빈 2번 뒤 본문): $out"
  [ "$rc" = 4 ] && grep -q '^ERROR 빈 응답 2회' <<<"$out"; ck "ⓐ 재시도는 딱 1회(3번째 답이 있어도 rc4)" $?
  C PATH="$T/catfail:$PATH"; echo "  ⓐ 원문(cat-file rc128·stderr 0): $out"
  [ "$rc" = 4 ] && grep -q '판정 불가' <<<"$out" && ! grep -q '^결정 인터뷰' <<<"$out"; ck "ⓐ cat-file rc128 만으로 «없음/0건» 을 만들지 않는다(판정 불가 rc4)" $?
  L "$T/showfail" 'ft_planner_queue_ref "$FT_ROOT"'; echo "  ⓐ 원문(show rc42): $out"
  [ "$rc" = 4 ] && [ "$out" = "ERROR 오빠 큐 origin/main 판을 못 읽음: origin/main:design/teams/planner/AUTONOMY-QUEUE.md" ]; ck "ⓐ 큐 본문 rc42 → ERROR 1줄(기준판 바이트 · rc4 · 호출자 덧붙임 0)" $?
  C PATH="$T/show-empty:$PATH"; s="$(now)"; C PATH="$T/show-empty:$PATH"; le "$s" 15; t1=$?
  echo "  ⓐ 원문(결정 셈 빈 2회): $out"
  [ "$rc" = 4 ] && grep -q '^ERROR ft-decision-count: ' <<<"$out" && ! grep -q '^결정 인터뷰' <<<"$out" && [ "$t1" = 0 ]; ck "ⓐ 파이썬 빈 값 2회 → ERROR rc4 · 결정 0건 출력 0 · ≤15초" $?
  # ⓑ 첫 빈 → 재시도 뒤 정상 = 셸·파이썬 둘 다 성공(대조)
  L "$T/empty" 'ref_read "$FT_ROOT" show origin/main:design/teams/planner/AUTONOMY-QUEUE.md'; echo "  ⓑ 원문(셸): $out"
  [ "$rc" = 0 ] && grep -q '새줄' <<<"$out"; ck "ⓑ 셸 ref_read 첫 빈 → 재시도 뒤 본문(rc0)" $?
  rm -f "$T/py-show/once"; C PATH="$T/py-show:$PATH"; echo "  ⓑ 원문(파이썬): $out"
  [ "$rc" = 0 ] && grep -q '^결정 인터뷰 3건 ' <<<"$out"; ck "ⓑ 파이썬 첫 빈 → 재시도 뒤 3건(셸과 같은 규칙)" $?
  # ⓒ 예산 소진 = ERROR rc4(미종료 0) · 기본 예산 70초 = 두 구현 같음
  s="$(now)"; L "$T/fast" 'FT_REF_BUDGET_SEC=0 ref_read "$FT_ROOT" show origin/main:design/teams/planner/AUTONOMY-QUEUE.md'; le "$s" 5; t1=$?
  echo "  ⓒ 원문(예산): $out"
  [ "$rc" = 4 ] && grep -q '^ERROR ref 읽기 예산 소진' <<<"$out" && [ "$t1" = 0 ]; ck "ⓒ 예산 소진 → rc4 · ≤5초(미종료 0 · 디스크 후퇴 0)" $?
  s="$(now)"; L "$T/show-slow-empty" 'FT_REF_BUDGET_SEC=3 ref_read "$FT_ROOT" show origin/main:design/teams/planner/AUTONOMY-QUEUE.md'; le "$s" 15; t1=$?
  echo "  ⓒ 원문(빈·지연): $out"
  [ "$rc" = 4 ] && [ "$t1" = 0 ] && [ -z "$(alive_pids "$T/show-slow-empty" 2>/dev/null | grep -v '^0$')" ]; ck "ⓒ 빈 답·지연 답도 ≤15초 rc4(미종료 0)" $?
  s="$(now)"; L "$T/slow07" 'FT_REF_BUDGET_SEC=1 ft_team_doc_ref_only "$FT_ROOT" planner AUTONOMY-QUEUE.md'; le "$s" 6; t1=$?
  echo "  ⓒ 원문(예산 1초·0.7초 지연): $out"
  [ "$rc" = 4 ] && grep -qE '^(ERROR ref 읽기 예산 소진|ERROR git)' <<<"$out" && [ "$t1" = 0 ]; ck "ⓒ 예산 1초 + 0.7초 지연 → rc4 · ≤6초(셸 2.4초 rc0 아님)" $?
  grep -q 'REF_BUDGET_S = 70' "$B/ft_team_lib.py" && ! grep -q 'FT_REF_BUDGET_SEC_DEFAULT' "$B/ft-team-lib.sh"; ck "ⓒ 예산은 파이썬 한 벌(70초 · 셸에 예산 로직 0)" $?
  # ⓔ env 지정 = 그 경로 그대로
  C FT_DECISION_AUTONOMY_QUEUE="$T/AQ.md"; [ "$rc" = 0 ] && grep -q '^결정 인터뷰 2건 ' <<<"$out"; ck "ⓔ FT_DECISION_AUTONOMY_QUEUE = 그 파일(2)" $?
  C FT_PLANNER_DIR="$PD"; [ "$rc" = 0 ] && grep -q '^결정 인터뷰 4건 ' <<<"$out"; ck "ⓔ FT_PLANNER_DIR = 그 폴더(4)" $?
  # ⓣ 상한 — 느린 git show(12초): 시도당 7초에서 끊고 ERROR(디스크 후퇴 0)
  rm -f "$T/slow/pids"; s="$(now)"; L "$T/slow" 'ref_read "$FT_ROOT" show origin/main:design/teams/planner/AUTONOMY-QUEUE.md'; le "$s" 9; local t1=$?
  echo "  ⓣ 원문(느린 본문): $out"
  [ "$rc" = 4 ] && grep -qE '^ERROR (빈 응답 2회|git -C |ref 읽기 예산 소진)' <<<"$out" && [ "$t1" = 0 ]; ck "ⓣ 느린 git show → ref_read ERROR rc4 · 경과 ≤9초(7초 상한)" $?
  out="$(alive_pids "$T/slow")"; [ "$out" = 0 ]; ck "ⓣ 상한 초과 뒤 남은 자식 0(프로세스 그룹 KILL)" $?
  s="$(now)"; L "$T/slow" 'ft_team_doc_ref_only "$FT_ROOT" planner AUTONOMY-QUEUE.md'; le "$s" 9; t1=$?
  echo "  ⓣ 원문(느린 문서): $out"
  [ "$rc" = 4 ] && grep -qE '^ERROR (planner 명단|planner AUTONOMY-QUEUE.md|git -C )' <<<"$out" && [ "$t1" = 0 ]; ck "ⓣ 느린 git show → ft_team_doc_ref_only ERROR(rc≠0) · 경과 ≤9초" $?
  s="$(now)"; L "$T/noterm" 'ft_team_doc_ref_only "$FT_ROOT" planner AUTONOMY-QUEUE.md'; le "$s" 9; t1=$?
  echo "  ⓣ 원문(TERM 무시): $out"
  [ "$rc" = 4 ] && [ "$t1" = 0 ]; ck "ⓣ TERM 무시 래퍼도 ≤9초(KILL 이 끊는다)" $?
  s="$(now)"; C PATH="$T/slow:$PATH"; le "$s" 9; t1=$?
  echo "  ⓣ 원문(느린 결정 셈): $out"
  [ "$rc" = 4 ] && grep -q '^ERROR ft-decision-count: ' <<<"$out" && [ "$t1" = 0 ]; ck "ⓣ 느린 git show → 결정 셈 ERROR rc4 · 경과 ≤9초(디스크 셈 0)" $?
  s="$(now)"; L "$T/empty" 'ft_planner_queue_ref "$FT_ROOT"'; le "$s" 9; t1=$?
  echo "  ⓣ 원문(첫 시도 빈 응답): $out"
  [ "$rc" = 0 ] && [ -n "$out" ] && grep -q '새줄' "$out" && [ "$t1" = 0 ]; ck "ⓣ 첫 시도 «출력 0» → 재시도 1회로 정상(rc0 · ref 본문)" $?
  [ -n "${out:-}" ] && [ -f "${out:-/nonexistent}" ] && rm -f "$out"
  [ -z "$(ls -A "$TMPDIR")" ]; ck "ⓣ 임시 본문 정리 · 루트 변경 0" $?
  # ⓕ 정적 검사(r5) — ref_read 밖 git 호출 0(파이썬) · 셸은 호출 한 줄씩(로직 0)
  [ "$(grep -c '_git_once(' "$B/ft_team_lib.py")" = 3 ] && awk '/^def team_rows_ref/,/^def _cands_ref/' "$B/ft_team_lib.py" | grep -q 'ref_read('; ck "ⓕ 파이썬 정적: _git_once 자리 3(정의+ref_read+_ref_present) · 명단 조회도 ref_read" $?
  [ "$(grep -cE '^(ref_read|_ft_ref_present|ft_team_doc_ref_only|ft_planner_queue_ref)\(\) \{ python3 ' "$B/ft-team-lib.sh")" = 4 ] && ! grep -qE 'for i in|for attempt|FT_REF_BUDGET_SEC|g\.run_cmd|ft_ref_git_once' "$B/ft-team-lib.sh"; ck "ⓕ 셸 정적: ref 읽기 = 파이썬 호출 한 줄씩 4개(재시도·예산·문구 로직 0)" $?
}
fail=0
res="$(suite "$BIN0")"; printf '%s\n' "$res"; fail=$((fail + $(grep -c '^FAIL' <<<"$res")))
if [ -z "${R839_BIN:-}" ]; then
  ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
  for f in ft_decision_count.py ft_team_lib.py ft-team-lib.sh ft-queue.sh; do cmp -s "$BIN0/$f" "$KIT/$f" && ok "ⓕ 키트 미러 cmp 0: $f" || bad "ⓕ 키트 미러 다름: $f"; done
  for f in ft-team-lib.sh ft-queue.sh; do bash -n "$BIN0/$f" && ok "ⓕ bash -n $f" || bad "ⓕ bash -n $f"; done
  python3 -m py_compile "$BIN0/ft_team_lib.py" && ok "ⓕ py_compile ft_team_lib.py" || bad "ⓕ py_compile ft_team_lib.py"
  [ "$(wc -l < "$BIN0/ft_decision_count.py")" -le 200 ] && ok "ⓕ ft_decision_count.py ≤ 200줄" || bad "ⓕ ft_decision_count.py 200줄 넘음"
  ! grep -q '^ft_queue_ref()' "$BIN0/ft-queue.sh" && grep -q 'ft_planner_queue_ref "\$ROOT"' "$BIN0/ft-queue.sh" && ok "ⓓ ft-queue.sh = 공용 ft_planner_queue_ref 호출(자체 정의 0)" || bad "ⓓ ft-queue.sh 정의/호출"
  awk '/^ft_team_doc_ref\(\)/,/^  printf .%s\\n. "\$tmp"; }$/' "$BIN0/ft-team-lib.sh" > "$T/docref.txt"
  [ -s "$T/docref.txt" ] && [ "$(cat "$T/docref.txt")" = "$(awk '/^ft_team_doc_ref\(\)/,/^  printf .%s\\n. "\$tmp"; }$/' "$KIT/ft-team-lib.sh")" ] && ok "ⓓ 기존 ft_team_doc_ref 본문 그대로(변경 0)" || bad "ⓓ ft_team_doc_ref 바뀜"
  o="$(env -u TMPDIR bash "$HERE/test_queue_remind_origin_main_r557.sh" 2>&1)"; f557="$(grep '^FAIL ' <<<"$o" | grep -v '^FAIL ⓖ 기존 큐 시험 파일 base 대조 diff 0')"
  [ -z "$f557" ] && [ "$(grep -c '^PASS' <<<"$o")" -ge 20 ] && ok "ⓓ r557 시험 PASS(remind·due·shown·take·add · ⓖ 가지 범위 가드 1줄 제외)" || bad "ⓓ r557 시험 :: $(head -3 <<<"$f557")"
  mut() { # $1 칸 이름 · $2 파일 · $3 옛 글자 · $4 새 글자 · $5 FAIL 이어야 하는 칸 머리
    local M="$T/mut"; rm -rf "$M"; cp -R "$BIN0" "$M"
    python3 -I -c 'import sys; p,a,b=sys.argv[1:]; s=open(p,encoding="utf-8").read(); assert s.count(a)==1, s.count(a); open(p,"w",encoding="utf-8").write(s.replace(a,b))' "$M/$2" "$3" "$4" || { bad "변이 적용 실패: $1"; return; }
    local r; r="$(suite "$M")"; grep -q "^FAIL $5" <<<"$r" && ok "변이 $1 → «$5» FAIL" || bad "변이 $1 이 잡히지 않음"; }
  mut "결정 셈을 디스크 읽기로" ft_decision_count.py '(lambda: planner_queue(data_root(R))) if os.environ.get("FT_PLANNER_DIR") else None, lambda: data_root(R)' 'lambda: planner_queue(data_root(R))' "ⓐ 결정 셈"
  mut "ref git 상한 삭제" ft_team_lib.py 'rc, out, _err = _git_once(base, list(args), min(7.0, left))' 'rc, out, _err = _git_once(base, list(args), 300)' "ⓣ 느린 git show → ref_read"
  mut "재시도를 3번으로" ft_team_lib.py 'for _attempt in (1, 2):' 'for _attempt in (1, 2, 3):' "ⓐ 재시도는 딱 1회"
  mut "빈 값을 성공으로" ft_team_lib.py 'raise RefReadError(f"ERROR 빈 응답 2회: {shown}")' 'return ""' "ⓐ 셸 ref_read 빈 값 2회"
  mut "cat-file rc128 = 없음" ft_team_lib.py 'if rc in (1, 128) and re.search(r"(does not exist in|exists on disk, but not in)", err):' 'if rc in (1, 128):' "ⓐ cat-file rc128"
  mut "셸 로직 부활(재시도·예산)" ft-team-lib.sh 'ref_read() { python3 "$_FT_TEAM_LIB_PY" ref-read "$@"; }' 'ref_read() { local i; for i in 1 2 3; do python3 "$_FT_TEAM_LIB_PY" ref-read "$@" && return 0; done; return 4; }' "ⓕ 셸 정적: ref 읽기 = 파이썬 호출 한 줄씩 4개"
  mut "ref 에 없을 때 디스크로 후퇴" ft_decision_count.py 'team_doc_ref(ref_at() if ref_at else R, "planner", name, os.environ.get("FT_TEAMS_REF") or "origin/main")' '(team_doc_ref(ref_at() if ref_at else R, "planner", name, os.environ.get("FT_TEAMS_REF") or "origin/main") or (Path(planner_queue(data_root(R))).read_text(encoding="utf-8") if ref_at else None))' "ⓑ ref 판에 큐 없음"
fi
echo "== FAIL $fail"; [ "$fail" = 0 ] && echo "ALL PASS"; [ "$fail" = 0 ]
