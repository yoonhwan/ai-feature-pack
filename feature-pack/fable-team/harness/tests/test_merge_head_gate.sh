#!/usr/bin/env bash
# test_merge_head_gate.sh — 홈 훅 merge-head-gate.sh 시험 (R230 · stdin JSON 만 먹인다 — 실 ~/.claude·실 gh·실 원격 0)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; HK="$ROOT/harness/kit/hooks/merge-head-gate.sh"; BIN="$ROOT/harness/bin"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/.fable-team"
export FT_ROOT="$T" FT_MERGE_GATE_SH="$BIN/ft-merge-gate.sh" FT_MERGE_GATE_HOOK_LOG="$T/hook.log"
mkbash() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "${2:-$W}"; }
run() { out="$(printf '%s' "$(mkbash "$1" "${2:-$W}")" | ${ENVPFX:-} bash "$HK" 2>"$T/err")"; rc=$?; }
al() { run "$1" "${3:-$W}"; [ "$rc" = 0 ] && [ -z "$out" ]; ck "$2" $?; }
dn() { run "$1" "${3:-$W}"; [ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; ck "$2" $?; }

bash -n "$HK"; ck "bash -n hook" $?; python3 -I -c "import ast;ast.parse(open('$ROOT/harness/kit/hooks/merge_cmd.py').read())"; ck "py 구문 merge_cmd" $?
# 픽스처: main 이 줄을 더한 뒤 — 옛 브랜치(old: 못 포함) · 병합한 브랜치(good) · 현재 main 에서 딴 브랜치(fresh)
git -C "$W" checkout -q -b old; echo c > "$W/c.txt"; cm "$W" "old work"; git -C "$W" branch good
git -C "$W" checkout -q main; printf 'l1\nMAIN-LINE\nl2\nl3\n' > "$W/a.txt"; cm "$W" "main adds"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
git -C "$W" checkout -q good; git -C "$W" merge -q --no-edit origin/main
OLD="$(sha "$W" old)"; GOOD="$(sha "$W" good)"

echo "== 음성(통과) — 병합이 아닌 것"
al 'git push --dry-run origin HEAD:main' "git push --dry-run"
al 'gh pr merge --help' "gh pr merge --help"
al 'echo "gh pr merge 5 --squash"' "echo 따옴표 본문의 같은 글자"
al $'cat <<\'EOF\'\ngh pr merge 7\ngit push origin +x:main\nEOF' "heredoc 본문의 같은 글자"
al 'git push origin good' "main 아닌 대상 push"
al 'bash /x/ft-merge-land.sh 5 --approve-sha abc' "ft-merge-land.sh 호출은 병합 명령으로 인식 안 함"
ENVPFX="env -u FT_ROOT -u CLAUDE_PROJECT_DIR"; mkdir -p "$T/outside"; al 'gh pr merge 5 --squash' "BYZ 밖(FT_ROOT 없음·git 아님)" "$T/outside"; ENVPFX=""

echo "== 양성(deny) — main 병합 경로"
dn "gh pr merge 5 --squash --match-head-commit $GOOD" "gh pr merge --match-head-commit → deny(ft-merge-land 로)"
dn "ft-gh-as-tank.sh pr merge 5 --squash" "ft-gh-as-tank.sh pr merge → deny"
dn "bash /x/ft-gh-as-tank.sh pr merge 5" "bash <경로>/ft-gh-as-tank.sh pr merge → deny"
dn "gh api repos/o/r/pulls/5/merge -X PUT" "gh api …/pulls/N/merge → deny"
dn "bash -c 'gh pr merge 3'" "bash -c 안의 gh pr merge → deny"
dn "env -S 'gh pr merge 3'" "env -S 안의 gh pr merge → deny"
grep -q 'ft-merge-land.sh' <<<"$out"; ck "deny 사유에 ft-merge-land.sh 안내" $?
dn 'git push origin +good:main' "+refspec main push → deny"
dn 'git push --force origin good:main' "--force main push → deny"
dn 'git push --force-with-lease origin good:main' "--force-with-lease main push → deny"
dn 'git push origin :main' "main 삭제 push → deny"
dn 'git push --mirror origin' "--mirror → deny"
dn 'git push origin good:ma*' "와일드카드 → deny"

echo "== main 향 git push — 게이트 결과"
dn "git push origin $OLD:main" "옛 세트(main 미포함) main push → deny(게이트 사유)"
grep -q '포함하지 않음' <<<"$out"; ck "deny 사유에 게이트 문구(main 포함 안 함)" $?
dn "git push origin old:refs/heads/main" "old:refs/heads/main → deny"
al "git push origin $GOOD:main" "main 을 포함한 세트 main push → allow"
al "cd $W && git push origin good:main" "cd 뒤 push 도 같은 판정 → allow"
dn "git push origin deadbeefdeadbeefdeadbeefdeadbeefdeadbeef:main" "sha 를 못 뽑는 main push → deny"
FT_MERGE_GATE_SH="$T/none.sh"; dn "git push origin $GOOD:main" "게이트 도구 못 찾음 → deny(병합은 되돌리기 어려움)"; export FT_MERGE_GATE_SH="$BIN/ft-merge-gate.sh"
grep -q 'ALLOW push' "$T/hook.log"; ck "결속 기록: hook.log 에 ALLOW push sha 줄" $?
printf 'not json' | bash "$HK" >/dev/null 2>&1; [ $? = 0 ]; ck "JSON 파싱 불가 = 인식 전 단계 → 통과" $?
! grep -vE '^\s*#' "$HK" "$ROOT/harness/kit/hooks/merge_cmd.py" | grep -qE 'git[^|]*(reset|rebase)'; ck "정적: 훅·모듈에 reset·rebase 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
