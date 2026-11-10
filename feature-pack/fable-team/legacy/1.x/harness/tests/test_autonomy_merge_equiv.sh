#!/usr/bin/env bash
# test_autonomy_merge_equiv.sh — r462: 자율 ON 병합 훅이 «오빠 승인 sha 위 main 병합만 더한 head»(같은 변경 집합)를 재승인 없이 통과시키는가.
#   판정기 = ft_approval_equiv.py(R247·r411 과 같은 것). 축 ⓐ~ⓔ: ⓐ A+main 병합 → 통과+로그 ⓑ +가지 새 커밋 → deny(재승인 필요)
#   ⓒ A 를 조상으로 안 둔 다른 변경 → deny ⓓ H==A → 통과(기존) ⓔ 승인 파일만(log 줄 없음) → deny(EQUIV 도 못 씀).
# 격리: 임시 FT_ROOT·상태 + 임시 git 저장소(origin/main = 가짜 ref) + 훅 stdin JSON — 실 상태·실 gh·외부 호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each   # r466: --level 생략 = full(범위 승인 + 슬랙 게시) — 이 시험은 레벨 밖이라 each(실 슬랙 0)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; MG="$ROOT/harness/kit/fable-team/templates/hooks/autonomy-merge-guard.sh"; BIN="$ROOT/harness/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
IH="$T/hooks"; mkdir -p "$IH"; cp "$ROOT/harness/kit/fable-team/templates/hooks/autonomy-"*.sh "$ROOT/harness/kit/hooks/merge_cmd.py" "$IH"/   # r546: 설치 꼴(한 폴더) 재현 — 공용 모듈 merge_cmd.py 를 훅 옆에 둔다
MG="$IH/autonomy-merge-guard.sh"
S="$T/state"; AP="$S/autonomy-merge-approved"; W="$T/w"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/planner" FT_AUTONOMY_SH="$BIN/ft-autonomy.sh" FT_AUTONOMY_HOOK_LOG="$T/hook.log"
mkdir -p "$T/.fable-team" "$S" "$T/planner"
a() { "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
mkbash() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "$W"; }
merge_cmd() { run "$(mkbash "gh pr merge 7 --squash --match-head-commit $1")"; }
run() { out="$(printf '%s' "$1" | "$BASH" "$MG" 2>"$T/err")"; rc=$?; }
denied() { [ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; }
g() { git -C "$W" -c user.email=t@t -c user.name=t "$@"; }
put() { printf '%s\n' "$2" > "$W/$1"; g add "$1" && g commit -qm "$1"; }

bash -n "$MG"; ck "bash -n autonomy-merge-guard.sh" $?
python3 -m py_compile "$BIN/ft_approval_equiv.py"; ck "py_compile ft_approval_equiv.py" $?

# 픽스처: base → 가지 A(2커밋) · main 이 m.txt 1커밋 전진(origin/main 가짜 ref)
git -c init.defaultBranch=main init -q "$W" && put base.txt base
BASE="$(g rev-parse HEAD)"
g checkout -qb feat && put a.txt a1 && put b.txt a2; A="$(g rev-parse HEAD)"
g checkout -q main && put m.txt m1; g update-ref refs/remotes/origin/main "$(g rev-parse HEAD)"
g checkout -qb h1 "$A" && g merge -q --no-edit origin/main; H1="$(g rev-parse HEAD)"
g checkout -qb h2 "$H1" && put c.txt extra; H2="$(g rev-parse HEAD)"
g checkout -qb h3 "$BASE" && put x.txt other && g merge -q --no-edit origin/main; H3="$(g rev-parse HEAD)"

a on >/dev/null 2>&1; a approve-merge "$A" >/dev/null 2>&1
[ -f "$AP/$A" ] && [ "$(a mode)" = on ]; ck "픽스처: 자율 ON · 승인 A 기록" $?

merge_cmd "$H1"; [ "$rc" = 0 ] && [ -z "$out" ] && grep -q "EQUIV $A -> $H1" "$T/hook.log"; ck "ⓐ A 위 main 병합만 = 통과 + 로그 EQUIV A -> H1" $?
merge_cmd "$H2"; denied && grep -q '재승인 필요' <<<"$out" && grep -q '일반 커밋 1' <<<"$out"; ck "ⓑ A+main 병합+가지 새 커밋 = deny(재승인 필요 · 사유 원문)" $?
merge_cmd "$H3"; denied && grep -q '재승인 필요' <<<"$out"; ck "ⓒ A 를 조상으로 안 둔 다른 변경 = deny" $?
merge_cmd "$A"; [ "$rc" = 0 ] && [ -z "$out" ]; ck "ⓓ H == A = 통과(기존 · 변경 0)" $?
n0="$(grep -c 'EQUIV ' "$T/hook.log")"; [ "$n0" = 1 ]; ck "ⓓ 정확 일치는 EQUIV 로그 0(ⓐ 1줄뿐)" $?

# ⓔ 승인 파일만 있고 log 줄 없음(직접 쓰기) → 정확 일치도 EQUIV 도 근거 0
rm -rf "$S"; mkdir -p "$S"; a on >/dev/null 2>&1; mkdir -p "$AP"; printf 'approve-merge %s A1 1\n' "$A" > "$AP/$A"
merge_cmd "$H1"; denied; ck "ⓔ 승인 파일만(log 줄 없음) · H1 = deny(EQUIV 도 못 씀)" $?
merge_cmd "$A"; denied; ck "ⓔ 승인 파일만(log 줄 없음) · A = deny(기존)" $?

# 판정기 없음 = EQUIV 0(통과 0) — 정확 일치는 그대로
rm -rf "$S"; mkdir -p "$S"; a on >/dev/null 2>&1; a approve-merge "$A" >/dev/null 2>&1
mkdir -p "$T/bin2"; cp "$BIN/ft-autonomy.sh" "$T/bin2/"; cp "$BIN"/ft-autonomy-*.sh "$BIN"/autonomy_*.py "$T/bin2/" 2>/dev/null
FT_AUTONOMY_SH="$T/bin2/ft-autonomy.sh" merge_cmd "$H1"; denied; ck "판정기(ft_approval_equiv.py) 없음 = H1 deny" $?
FT_AUTONOMY_SH="$T/bin2/ft-autonomy.sh" merge_cmd "$A"; [ "$rc" = 0 ] && [ -z "$out" ]; ck "판정기 없음에도 H == A 통과" $?

# approve-merge 출력에 «EQUIV 허용 범위» 1줄(stderr) · stdout 은 APPROVED 줄 그대로
o="$(a approve-merge "$H1" 2>/dev/null)"; e="$(a approve-merge "$H1" 2>&1 >/dev/null)"
[ "$o" = "APPROVED $H1 A1" ] && grep -q '^EQUIV 허용 범위: ' <<<"$e"; ck "approve-merge stdout 불변 · stderr EQUIV 허용 범위 1줄" $?
git config --get core.bare >/dev/null 2>&1 && [ "$(git config --get core.bare)" = true ] && { echo "FAIL 공용 config core.bare=true"; fail=$((fail+1)); }
echo "fail=$fail"; [ "$fail" = 0 ]
