#!/usr/bin/env bash
# test_evidence_log_gate.sh — r449 증거 로그 게이트: pre-commit(index 단계) · ft-merge-land(가지 diff) · ft-evidence-untrack(이미 tracked) · install.sh(git 훅 복사)
#   임시 리포만(실 리포·실 gh·실 원격 0) · 시험에 GIT_* 경로 env 0(BOOT 25 — 전부 git -C) · core.hooksPath = 키트 githooks(임시 리포 로컬 config).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$(cd "$HERE/.." && pwd)"; BIN="$H/bin"; KIT="$H/kit/fable-team"; LAND="$BIN/ft-merge-land.sh"; UNT="$BIN/ft-evidence-untrack.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
GI='*.log
design/**/*.out
design/**/*.nohup
design/**/*.stdout
design/**/*.stderr
design/**/*.pid
design/**/*guard*.jsonl*
design/**/*poller*.jsonl*
design/**/*guard*.txt
design/**/*poller*.txt'
nc() { git -C "$1" rev-list --count HEAD; }

# 문법·짝
bash -n "$LAND" && bash -n "$UNT" && sh -n "$KIT/githooks/pre-commit" && sh -n "$BIN/ft-evidence-lib.sh"; ck "bash -n · sh -n (land·untrack·pre-commit·lib)" $?
for f in ft-merge-land.sh ft-evidence-untrack.sh ft-evidence-lib.sh; do cmp -s "$BIN/$f" "$KIT/bin/$f"; ck "bin·kit 짝 cmp0 $f" $?; done
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄" $?

# 판정식 단위 — 같은 함수 한 곳
. "$BIN/ft-evidence-lib.sh"
for p in design/x/a.log design/x/b.out design/x/c.nohup design/x/d_guard.log design/x/poller_dom.jsonl design/x/poller_dom.jsonl.gz design/x/guard_base.txt design/a/b/worker.pid design/x/r.stdout; do
  ft_evidence_log_path "$p"; ck "판정식 증거 $p" $?; done
for p in design/x/SUMMARY-x.md design/x/note.md design/x/guard.sh design/x/poller_intent.json design/x/DESIGN-guard.md design/x/results.jsonl a.log scripts/x.out design/x/poller.py; do
  ! ft_evidence_log_path "$p"; ck "판정식 아님 $p" $?; done

# ⓐ~ⓒ pre-commit — 임시 리포 + core.hooksPath = 키트 githooks(판정식 = 키트 ../bin)
R="$T/r"; git init -q -b main "$R"; git -C "$R" config user.name t; git -C "$R" config user.email t@t; git -C "$R" config commit.gpgsign false
printf '%s\n' "$GI" | head -1 > "$R/.gitignore"; echo base > "$R/README"; git -C "$R" add -A; git -C "$R" commit -q -m base
git -C "$R" config core.hooksPath "$KIT/githooks"
mkdir -p "$R/design/x"; for f in a.log b.out c.nohup d_guard.log poller_dom.jsonl SUMMARY-x.md note.md guard.sh; do echo "$f" > "$R/design/x/$f"; done
N0="$(nc "$R")"
out="$(cd "$R" && git add -f design/x/a.log design/x/b.out design/x/c.nohup design/x/d_guard.log design/x/poller_dom.jsonl && git commit -q -m logs 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"EVIDENCE-LOG-GATE: 증거 로그 5 staged — git rm --cached "* ]] && [[ "$out" == *"design/x/poller_dom.jsonl"* ]] && [[ "$out" == *"요약은 SUMMARY-*.md"* ]] && [ "$(nc "$R")" = "$N0" ]
ck "ⓐ git add -f 로그 5 + commit → EVIDENCE-LOG-GATE rc1 · 커밋 0" $?
out="$(cd "$R" && git commit -q --only -m logs2 -- design/x/a.log 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"증거 로그 1 staged"* ]] && [ "$(nc "$R")" = "$N0" ]; ck "ⓐ' commit --only(임시 index) 도 REJECT" $?
git -C "$R" reset -q
out="$(cd "$R" && git add design/x/SUMMARY-x.md design/x/note.md design/x/guard.sh && git commit -q -m summary 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(nc "$R")" = $((N0 + 1)) ]; ck "ⓑ SUMMARY-x.md·note.md·guard.sh 만 → 통과" $?
git -C "$R" add -f design/x/a.log
out="$(cd "$R" && BYZ_EVIDENCE_LOG_OK=77 git commit -q -m 'log ok' 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"승인 표식"* ]]; ck "ⓒ env 만(표식 없음) → REJECT" $?
out="$(cd "$R" && BYZ_EVIDENCE_LOG_OK=1 git commit -q -m 'log ok' 2>&1)"; rc=$?
[ "$rc" = 1 ]; ck "ⓒ env=1(번호 표식 없음) → REJECT" $?
mkdir -p "$R/.fable-team/state"; : > "$R/.fable-team/state/evidence-log-ok.77"
out="$(cd "$R" && git commit -q -m 'log ok' 2>&1)"; rc=$?
[ "$rc" = 1 ]; ck "ⓒ 표식만(env 없음) → REJECT" $?
out="$(cd "$R" && BYZ_EVIDENCE_LOG_OK=77 git commit -q -m 'log ok 승인 77' 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"사람 승인 77"* ]] && [ "$(nc "$R")" = $((N0 + 2)) ]; ck "ⓒ env 77 + 표식 evidence-log-ok.77 → 통과" $?
mkdir -p "$T/nolib/githooks"; cp -p "$KIT/githooks/pre-commit" "$T/nolib/githooks/"; git -C "$R" config core.hooksPath "$T/nolib/githooks"
git -C "$R" add -f design/x/b.out; out="$(cd "$R" && git commit -q -m nolib 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"판정식 없음"* ]]; ck "판정식 lib 못 찾음 + design/ staged → REJECT(조용한 통과 0)" $?
git -C "$R" reset -q; echo x > "$R/other.txt"; git -C "$R" add other.txt; out="$(cd "$R" && git commit -q -m other 2>&1)"; rc=$?
[ "$rc" = 0 ]; ck "판정식 lib 못 찾음이어도 design/ 밖 커밋은 통과" $?
git -C "$R" config core.hooksPath "$KIT/githooks"

# ⓓ ft-merge-land 가지 diff — 임시 origin+clone · gh 스텁(실 gh 0)
mkrepo "$T/m"; mkdir -p "$T/m/state"
export FT_ROOT="$T/m" FT_AUTONOMY_STATE_DIR="$T/m/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/install-stub"
printf '#!/bin/bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\necho "$*" >> "$STUB_LOG"\n' > "$T/gh-stub"; printf '#!/bin/bash\nexit 0\n' > "$T/install-stub"; chmod +x "$T/gh-stub" "$T/install-stub"
mkpr() {  # mkpr <번호> <브랜치> <경로…> — origin/main 에서 가지 · 경로 파일 추가(add -f) · refs/pull/N/head
  local n="$1" b="$2"; shift 2; git -C "$W" checkout -q -B "$b" origin/main
  for p in "$@"; do mkdir -p "$W/$(dirname "$p")"; echo "$p" > "$W/$p"; git -C "$W" add -f "$p"; done
  git -C "$W" commit -q -m "pr $n"; git -C "$W" push -q origin "$b:refs/pull/$n/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$n" > "$STUB_JSON"
}
omain() { sha "$ORIGIN" refs/heads/main; }
mkpr 21 p21 design/y/z.out design/y/SUMMARY-z.md; M1="$(omain)"; apv --approve-sha "$PRSHA"
out="$(bash "$LAND" 21 --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"REJECT 증거 로그 1 — git rm --cached 뒤 다시: design/y/z.out"* ]] && [ "$(omain)" = "$M1" ] && [ "$(printf '%s\n' "$out" | grep -c REJECT)" = 1 ]
ck "ⓓ 가지 diff 에 design/y/z.out → REJECT 1줄(파일명) · main 불변" $?
mkpr 22 p22 design/y/SUMMARY-z.md design/y/note.md; apv --approve-sha "$PRSHA"
out="$(bash "$LAND" 22 --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]]; ck "ⓓ 요약 md 만 → 착지" $?
git -C "$W" fetch -q origin; git -C "$W" checkout -q -B seed origin/main; mkdir -p "$W/design/y"; echo old > "$W/design/y/old.log"; git -C "$W" add -f design/y/old.log; git -C "$W" commit -q -m seed; git -C "$W" push -q origin seed:main; git -C "$W" fetch -q origin
git -C "$W" checkout -q -B p23 origin/main; git -C "$W" rm -q --cached design/y/old.log; git -C "$W" commit -q -m untrack; git -C "$W" push -q origin p23:refs/pull/23/head; PRSHA="$(sha "$W" HEAD)"
python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"PR 23","body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" > "$STUB_JSON"; apv --approve-sha "$PRSHA"
out="$(bash "$LAND" 23 --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ! git -C "$ORIGIN" ls-tree -r --name-only main | grep -q 'old.log'; ck "ⓓ untrack 가지(D 만) → 착지 · main 에서 로그 0" $?
mkdir -p "$T/inst"; for f in ft-merge-land.sh ft-merge-lib.sh ft-merge-gate.sh ft_merge_lines.py ft-autonomy.sh; do cp -p "$BIN/$f" "$T/inst/"; done
out="$(bash "$T/inst/ft-merge-land.sh" 22 --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 2 ] && [[ "$out" == *"판정식 없음"* ]]; ck "ⓓ 판정식 lib 없는 설치 → 실행 0 rc2(조용한 통과 0)" $?

# ⓔ ft-evidence-untrack — 이미 tracked(훅 끈 리포) · 한글·공백 이름 포함
U="$T/u"; git init -q -b main "$U"; git -C "$U" config user.name t; git -C "$U" config user.email t@t; git -C "$U" config commit.gpgsign false
mkdir -p "$U/design/teams/v65/e" "$U/design/z"; for f in a.log b.out "한글 c.nohup" poller_dom.jsonl poller_dom.jsonl.gz guard_base.txt fe.pid SUMMARY-e.md note.md guard.sh results.jsonl; do echo "$f" > "$U/design/teams/v65/e/$f"; done
echo z > "$U/design/z/w.stdout"; echo k > "$U/keep.log"
git -C "$U" add -f -A; git -C "$U" commit -q -m seed
EXP="$(git -C "$U" ls-files -z -- design | tr '\0' '\n' | ft_evidence_filter | LC_ALL=C sort)"
echo dirty >> "$U/design/teams/v65/e/note.md"; out="$(bash "$UNT" "$U" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"[wip] 먼저"* ]] && [ "$(git -C "$U" ls-files design | grep -c .)" = 12 ]; ck "ⓔ 미커밋 있으면 REJECT · index 불변" $?
git -C "$U" checkout -q -- design/teams/v65/e/note.md
out="$(bash "$UNT" --dry-run "$U" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -v '^UNTRACK' | LC_ALL=C sort)" = "$EXP" ] && [[ "$out" == *"UNTRACK n=8 MB="*" dry=1"* ]] && [ "$(git -C "$U" ls-files design | grep -c .)" = 12 ]
ck "ⓔ --dry-run 목록 = 판정식과 같음(n=8) · index 불변" $?
out="$(bash "$UNT" "$U" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "UNTRACK n=8 MB="*" dry=0" ]]; ck "ⓔ 적용 UNTRACK n=8 dry=0" $?
[ -z "$(git -C "$U" ls-files -z -- design | tr '\0' '\n' | ft_evidence_filter)" ] && [ "$(git -C "$U" ls-files design | grep -c .)" = 4 ]; ck "ⓔ 적용 뒤 ls-files design | 판정식 0 · 나머지 4 tracked" $?
ok=0; while IFS= read -r p; do [ -f "$U/$p" ] || ok=1; done <<< "$EXP"; [ "$ok" = 0 ] && [ -f "$U/keep.log" ]; ck "ⓔ 파일은 디스크에 그대로(8 + design 밖 keep.log)" $?
git -C "$U" ls-files --error-unmatch keep.log >/dev/null 2>&1; ck "ⓔ design/ 밖 로그는 건드리지 않음(범위 밖)" $?
printf '%s\n' "$GI" > "$U/.gitignore"; git -C "$U" add .gitignore
[ -z "$(git -C "$U" status --porcelain --untracked-files=all | grep -v '^[DA] ' )" ]; ck "ⓔ .gitignore 줄 뒤 git status 에 untrack 한 파일 0(?? 없음)" $?
git -C "$U" config core.hooksPath "$KIT/githooks"; out="$(cd "$U" && git commit -q -m 'untrack evidence' 2>&1)"; rc=$?
[ "$rc" = 0 ]; ck "ⓔ untrack 커밋(D)은 pre-commit 통과" $?
out="$(bash "$UNT" "$U" 2>&1)"; rc=$?; [ "$rc" = 0 ] && [ "$out" = "UNTRACK n=0 MB=0.0 dry=0" ]; ck "ⓔ 2회째 n=0(멱등)" $?
out="$(bash "$UNT" 2>&1)"; rc=$?; [ "$rc" = 2 ]; ck "ⓔ 인자 없음 → usage rc2" $?
# ⓔ' sparse-checkout 워크트리(나노 spawn 기본 · cone 밖 design/teams/*) — r449 실측: --sparse 없으면 59/614 만 빠지고 실패
S="$T/s"; git init -q -b main "$S"; git -C "$S" config user.name t; git -C "$S" config user.email t@t; git -C "$S" config commit.gpgsign false
mkdir -p "$S/design/teams/v65/e" "$S/design/teams/harness/e"; echo a > "$S/design/teams/v65/e/a.log"; echo b > "$S/design/teams/harness/e/b.out"; echo c > "$S/design/teams/v65/e/n.md"
git -C "$S" add -f -A; git -C "$S" commit -q -m seed; git -C "$S" sparse-checkout set --no-cone '/*' '!/design/teams/*/' '/design/teams/harness/' >/dev/null 2>&1
[ ! -e "$S/design/teams/v65/e/a.log" ]; ck "ⓔ' 픽스처 = cone 밖 파일은 디스크에 없음" $?
out="$(bash "$UNT" "$S" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "UNTRACK n=2 MB="*" dry=0" ]] && [ "$(git -C "$S" ls-files design | grep -c .)" = 1 ] && [ -f "$S/design/teams/harness/e/b.out" ]; ck "ⓔ' sparse 워크트리에서 cone 밖 포함 n=2 전부 untrack · 디스크 보존" $?

# ⓖ install.sh --apply → <프로젝트>/.fable-team/githooks/pre-commit cmp0 · 덮기 전 .bak-<버전> · 2회째 same
P="$T/proj"; mkdir -p "$P/.fable-team/bin" "$P/.fable-team/githooks" "$T/home/.claude/hooks"; git init -q -b main "$P"; echo old > "$P/.fable-team/githooks/pre-commit"
out="$(bash "$H/install.sh" --apply --project "$P" --home "$T/home" 2>&1)"; rc=$?
VER="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$H/../manifest.json")"
[ "$rc" = 0 ] && cmp -s "$KIT/githooks/pre-commit" "$P/.fable-team/githooks/pre-commit" && [ -x "$P/.fable-team/githooks/pre-commit" ] && [ "$(cat "$P/.fable-team/githooks/pre-commit.bak-$VER")" = old ] && [[ "$out" == *"GITHOOKS copied=2 same=0"* ]]
ck "ⓖ install --apply → githooks/pre-commit cmp0 · 실행 비트 · .bak-$VER" $?
# r511: 키트 githooks = pre-commit + pre-push
cmp -s "$KIT/githooks/pre-push" "$P/.fable-team/githooks/pre-push" && [ -x "$P/.fable-team/githooks/pre-push" ]; ck "ⓖ install --apply → githooks/pre-push cmp0 · 실행 비트" $?
out="$(bash "$H/install.sh" --apply --project "$P" --home "$T/home" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"GITHOOKS copied=0 same=2"* ]]; ck "ⓖ 2회째 same=2(멱등)" $?
git -C "$P" config core.hooksPath /elsewhere; out="$(bash "$H/install.sh" --dry-run --project "$P" --home "$T/home" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"WARN core.hooksPath=/elsewhere"* ]] && [[ "$out" == *"GITHOOK $(cd "$P" && pwd -P)/.fable-team/githooks/pre-commit"* ]]; ck "ⓖ dry-run GITHOOK 줄 · hooksPath 어긋남 WARN" $?

# ⓕ 정적 — 600/300 0 · 외부 호출 0 · 시험 GIT_* 경로 env 0
NEW="$BIN/ft-evidence-lib.sh $UNT $KIT/githooks/pre-commit"
! grep -nE '\b(600|300)\b' $NEW; ck "ⓕ 새 파일 600/300 0" $?
! grep -nE '\b(curl|gh|wget|ssh)\b' $NEW; ck "ⓕ 새 파일 외부 호출 0" $?
! grep -nE '(^|[^_A-Z])GIT_(DIR|WORK_TREE|INDEX_FILE|COMMON_DIR|OBJECT_DIRECTORY)=' "$0"; ck "ⓕ 이 시험에 GIT_* 경로 env 0" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
