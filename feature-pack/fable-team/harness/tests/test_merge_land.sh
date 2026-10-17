#!/usr/bin/env bash
# test_merge_land.sh — ft-merge-land.sh 착지 시험 (R230 교정 2 H1 · 임시 origin+clone · gh 는 스텁 · 실 gh·실 원격 0)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/shim" "$T/.fable-team"
REAL_GIT="$(command -v git)"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; echo "REJECT usage" >&2; exit 2;; esac   # ft-gh-as-tank.sh 는 하이픈 동사만 받는다(R261)
body=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done
echo "$* :: $body" >> "$STUB_LOG"
EOF
cat > "$T/shim/git" <<EOF
#!/bin/bash
for a in "\$@"; do if [ "\$a" = commit-tree ] && [ -n "\${RACE_WT:-}" ] && [ ! -e "\$RACE_MARK" ]; then : > "\$RACE_MARK"; "$REAL_GIT" -C "\$RACE_WT" commit -q --allow-empty -m race && "$REAL_GIT" -C "\$RACE_WT" push -q origin HEAD:main; fi; done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/gh-stub" "$T/shim/git"
omain() { sha "$ORIGIN" refs/heads/main; }
mkpr() {  # mkpr <번호> <브랜치> <시작점> <state> — PR head 를 origin refs/pull/N/head 에 올리고 스텁 JSON 작성
  git -C "$W" checkout -q -B "$2" "$3"; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"본문 "+sys.argv[2],"state":sys.argv[3],"baseRefName":"main"}))' "$PRSHA" "$1" "${4:-OPEN}" > "$STUB_JSON"
}
land() { apv "$@"; out="$(bash "$LAND" "$@" --repo "$W" 2>&1)"; rc=$?; }
ZERO=0000000000000000000000000000000000000000

bash -n "$LAND"; ck "bash -n land" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄" $?
printf 'l1\nMAIN-LINE\nl2\nl3\n' > "$W/a.txt"; cm "$W" "main adds"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
M1="$(omain)"
mkpr 7 pr7 origin/main; P7="$PRSHA"

land 7; [ "$rc" = 2 ] && [ "$(omain)" = "$M1" ] && [ ! -s "$STUB_LOG" ]; ck "승인 값 없음 → rc2 · main 불변 · PR 쓰기 0(실행 0)" $?
land 7 --approve-sha "$ZERO"; [ "$rc" = 1 ] && [[ "$out" == *"승인 sha"* ]] && [ "$(omain)" = "$M1" ]; ck "승인 sha != PR head → REJECT · main 불변" $?
mkpr 6 pr6 origin/main CLOSED; land 6 --approve-sha "$PRSHA"; [ "$rc" = 1 ] && [[ "$out" == *"OPEN 아님"* ]] && [ "$(omain)" = "$M1" ]; ck "PR 가 OPEN 아님 → REJECT" $?
mkpr 8 pr8 "$M0"; land 8 --approve-sha "$PRSHA"; [ "$rc" = 1 ] && [[ "$out" == *"게이트"* ]] && [[ "$out" == *"포함하지 않음"* ]] && [ "$(omain)" = "$M1" ]; ck "main 미포함 옛 세트 PR → 게이트 REJECT · main 불변" $?

# 검사 뒤 main 전진 → 서버 non-FF 거절(착지 0)
git -C "$T" clone -q "$ORIGIN" "$T/race"; git -C "$T/race" config user.name t; git -C "$T/race" config user.email t@t
mkpr 9 pr9 origin/main; P9="$PRSHA"
apv --approve-sha "$P9"; out="$(PATH="$T/shim:$PATH" RACE_WT="$T/race" RACE_MARK="$T/race.mark" bash "$LAND" 9 --approve-sha "$P9" --repo "$W" 2>&1)"; rc=$?
RACE="$(omain)"
[ "$rc" = 1 ] && [[ "$out" == *"non-FF"* ]]; ck "검사 뒤 main 이 움직임 → 서버 non-FF 거절 → REJECT" $?
[ "$RACE" != "$M1" ] && [ "$(git -C "$ORIGIN" log -1 --format=%s main)" = race ]; ck "착지 0 — origin main 은 경주 커밋 그대로(트리 어긋남 없음)" $?
[ ! -s "$STUB_LOG" ]; ck "거절이면 PR 코멘트·닫기 0" $?

# 정상 착지
git -C "$W" fetch -q origin; mkpr 11 pr11 origin/main; P11="$PRSHA"; M2="$(omain)"
land 11 --approve-sha "$P11"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]]; ck "정상 착지 rc=0" $?
L="$(omain)"; [[ "$out" == *"sha=$L"* ]]; ck "출력 착지 sha == origin main" $?
[ "$(sha "$ORIGIN" "$L^{tree}")" = "$(sha "$W" "$P11^{tree}")" ]; ck "착지 트리 == 검사한 PR head 트리" $?
[ "$(sha "$ORIGIN" "$L^")" = "$M2" ] && [ "$(git -C "$ORIGIN" rev-list --parents -n1 "$L" | wc -w | tr -d ' ')" = 2 ]; ck "squash 1커밋(부모 = 검사 때 main 1개)" $?
git -C "$ORIGIN" log -1 --format=%B "$L" | grep -q 'PR #11' && git -C "$ORIGIN" log -1 --format=%B "$L" | grep -q 'feat: PR 11'; ck "메시지 = PR 제목·본문 + PR #11" $?
grep -q "^pr-close 11 --comment .*--apply :: 착지 sha $L" "$STUB_LOG" && ! grep -q BADVERB "$STUB_LOG"; ck "PR 11 에 착지 sha 코멘트 + 닫기(ft-gh-as-tank 하이픈 동사 pr-close --comment <파일> --apply · R261)" $?
grep -q "head=$P11 method=ft-merge-land .*landed=$L pr=11" "$T/state/merge-gate.log"; ck "결속 기록 1줄(main·head·방법·트리·착지)" $?

# R271: PR head fetch 가 auto gc 실패로 rc≠0 이어도 «fetch 실패» 로 오판하지 않는다 — 프로세스 한정 -c gc.auto=0 이 없으면 rc1 을 내는 shim
mkdir -p "$T/shim3"; printf '#!/bin/bash\nsaw=0; gc=0; for a in "$@"; do case "$a" in pull/*/head) saw=1;; gc.auto=0) gc=1;; esac; done\n"%s" "$@"; r=$?\n[ "$saw" = 1 ] && [ "$gc" = 0 ] && exit 1\nexit $r\n' "$REAL_GIT" > "$T/shim3/git"; chmod +x "$T/shim3/git"
git -C "$W" fetch -q origin; mkpr 12 pr12 origin/main; P12="$PRSHA"
apv --approve-sha "$P12"; out="$(PATH="$T/shim3:$PATH" bash "$LAND" 12 --approve-sha "$P12" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]]; ck "fetch 에 -c gc.auto=0 — gc 실패 rc≠0 이어도 착지(R271)" $?

# 자율 ON — 승인 파일 없으면 실행 0 · approve-merge 뒤 착지
bash "$BIN/ft-autonomy.sh" on >/dev/null 2>&1; git -C "$W" fetch -q origin; mkpr 10 pr10 origin/main; P10="$PRSHA"; M3="$(omain)"; : > "$STUB_LOG"
NOAP=1 land 10 --approve-sha "$P10"; [ "$rc" = 2 ] && [[ "$out" == *"approve-merge"* ]] && [ "$(omain)" = "$M3" ] && [ ! -s "$STUB_LOG" ]; ck "자율 ON · 승인 파일 없음 → rc2 · 실행 0" $?
bash "$BIN/ft-autonomy.sh" approve-merge "$P10" >/dev/null 2>&1
land 10 --approve-sha "$P10"; [ "$rc" = 0 ] && [ "$(omain)" != "$M3" ]; ck "자율 ON · approve-merge 승인 뒤 착지" $?

[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
! grep -vE '^\s*#' "$LAND" | grep -qE 'git[^|]*(reset|rebase|--force|\+refs)|push[^|]*-f '; ck "정적: land 에 force·reset·rebase·+refspec 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
