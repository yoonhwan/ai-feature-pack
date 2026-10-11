#!/usr/bin/env bash
# test_deferral_lint.sh — ft-deferral-lint 시험. 일회용 git 저장소에서만 돈다(실 push·실 CI 0).
# 픽스처 = tests/fixtures/deferral/<케이스>.<확장자>.fx — 케이스가 «추가되는 줄»이 되도록 커밋해 diff 를 만든다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LINT="$HERE/../../scripts/fable-team-bin/ft-deferral-lint.sh"
FX="$HERE/../fixtures/deferral"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$LINT" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q . && git config user.email t@t && git config user.name t || { echo "FAIL git init"; exit 1; }
mkdir -p design/t/indices src tests/fixtures docs
echo 카드 > design/t/indices/c.md
git add -A && git commit -qm base

# lint_fx <픽스처> [저장 경로] — 픽스처를 커밋해 만든 diff 를 stdin 으로 넣는다. 출력+rc 는 OUT·RC.
lint_fx() {
  local base="${1%.fx}" dest="${2:-src/${1%.fx}}"
  mkdir -p "$(dirname "$dest")"; cp "$FX/$1" "$dest"
  git add -A && git commit -qm "$1"
  OUT="$(git diff HEAD~1 HEAD | bash "$LINT" 2>&1)"; RC=$?
}
expect_ok()  { lint_fx "$1" "${3:-}"; [ $RC -eq 0 ] && echo "$OUT" | grep -q '^OK ' && ok "$2" || bad "$2 → rc=$RC $OUT"; }
expect_rej() { lint_fx "$1" "${4:-}"; [ $RC -eq 1 ] && echo "$OUT" | grep -q "$3" && ok "$2" || bad "$2 → rc=$RC $OUT"; }

expect_rej rej-py-nocard.py.fx "유예 주석 + 경로 없음 → REJECT(파일:행·줄 복사)" 'REJECT src/rej-py-nocard.py:2 .*적용 후 별건으로 되살린다'
expect_ok  ok-py-card.py.fx "+ → 카드 <실재 경로> → OK"
expect_ok  ok-py-issue.py.fx "+ #1234 → OK"
expect_rej rej-py-badpath.py.fx "카드 경로가 실재하지 않음 → REJECT" '카드 경로 실재 0'
expect_rej rej-py-hashnoDigit.py.fx "# 뒤가 숫자가 아님 → REJECT" 'REJECT '
expect_ok  ok-py-fallback0.py.fx "「폴백 0 — raise」 설명 주석(패턴 축소) → OK"
expect_ok  ok-py-tempfile.py.fx "「임시 파일」 명사 수식(임시 단독 제거) → OK"
expect_rej rej-py-temporarily.py.fx "「임시로 빼 둔다」 → REJECT" 'REJECT src/rej-py-temporarily.py:1'
expect_ok  ok-py-plain.py.fx "패턴 밖 일반 주석 → OK"
expect_ok  ok-py-string.py.fx "문자열 안 단어(py) → OK"
expect_ok  ok-ts-string.ts.fx "문자열·템플릿 안 단어(ts) → OK"
expect_rej rej-ts-line.ts.fx "// 줄 주석 TODO → REJECT" 'REJECT src/rej-ts-line.ts:1'
expect_rej rej-ts-block.ts.fx "/** */ 블록 안 줄 → REJECT(행번호 3)" 'REJECT src/rej-ts-block.ts:3'
expect_ok  ok-ts-block-card.ts.fx "블록 주석 + 카드 경로 → OK"
expect_ok  ok-py-nextline.py.fx "바로 다음 줄에 카드 경로 → OK"
expect_ok  ok-py-blocktail.py.fx "같은 연속 주석 덩어리 안의 카드 경로 1개로 덩어리 전체 통과"
expect_rej rej-py-farcard.py.fx "코드 줄로 끊긴 먼 주석의 카드 경로 → REJECT" 'REJECT src/rej-py-farcard.py:1'
expect_rej rej-py-docstring.py.fx "docstring 안 유예 문구 → REJECT" 'REJECT src/rej-py-docstring.py:3'
expect_rej rej-html-comment.html.fx "<!-- --> 안 유예 문구 → REJECT" 'REJECT src/rej-html-comment.html:1'
expect_rej rej-t0-org-service.py.fx "T0(4c35d4c0a1) 주석 원문 → REJECT" 'REJECT src/rej-t0-org-service.py:6 .*적용 후 별건으로 추가한다'

lint_fx ok-py-exempt.py.fx
[ $RC -eq 0 ] && echo "$OUT" | grep -q '^EXEMPT src/ok-py-exempt.py:1 ' && echo "$OUT" | grep -q '^OK ' && ok "면제 꼬리 → OK + EXEMPT 1줄" || bad "면제 꼬리 → rc=$RC $OUT"

expect_ok  rej-py-nocard.py.fx "tests/fixtures/ 는 제외" tests/fixtures/excluded.py
expect_ok  rej-html-comment.html.fx "docs/·*.md 는 제외" docs/excluded.md
mkdir -p design/x; expect_ok rej-py-nocard.py.fx "design/ 는 제외" design/x/excluded.py

# 바뀌지 않은 옛 줄은 대상이 아니다(추가되는 줄만)
printf '# 별건 옛 주석\nz = 0\n' > src/old.py; git add -A; git commit -qm old
printf '# 별건 옛 주석\nz = 0\nw = 1\n' > src/old.py; git add -A; git commit -qm touch
OUT="$(git diff HEAD~1 HEAD | bash "$LINT" 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "문맥(옛) 줄은 무시" || bad "문맥 줄 → rc=$RC $OUT"

# SUMMARY 줄 — rc 와 무관하게 마지막 줄 (판정 1097 DA H2)
lint_fx rej-py-nocard.py.fx src/sum-rej.py
[ $RC -eq 1 ] && [ "$(echo "$OUT" | tail -1)" = "SUMMARY deferral-lint checked=1 rejected=1 exempt=0" ] && ok "REJECT 출력 마지막 줄 = SUMMARY rejected=1" || bad "SUMMARY(REJECT) → rc=$RC $OUT"
lint_fx ok-py-card.py.fx src/sum-ok.py
[ $RC -eq 0 ] && echo "$OUT" | grep -q '^OK deferral-lint checked=1 exempt=0$' && [ "$(echo "$OUT" | tail -1)" = "SUMMARY deferral-lint checked=1 rejected=0 exempt=0" ] && ok "OK 줄 유지 + SUMMARY rejected=0" || bad "SUMMARY(OK) → rc=$RC $OUT"
lint_fx ok-py-exempt.py.fx src/sum-ex.py
[ "$(echo "$OUT" | tail -1)" = "SUMMARY deferral-lint checked=1 rejected=0 exempt=1" ] && ok "SUMMARY exempt=1" || bad "SUMMARY(EXEMPT) → $OUT"

# 전수 모드(--files): 파일 전체가 대상
OUT="$(bash "$LINT" --files src/rej-py-nocard.py 2>&1)"; RC=$?
[ $RC -eq 1 ] && echo "$OUT" | grep -q '^REJECT ' && ok "--files 전수: 거부" || bad "--files 거부 → rc=$RC $OUT"
OUT="$(bash "$LINT" --files src/ok-py-card.py 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "--files 전수: 통과" || bad "--files 통과 → rc=$RC $OUT"

# 입력 없음 = 사용법 오류 rc 2
OUT="$(bash "$LINT" </dev/null 2>&1)"; RC=$?
[ $RC -eq 2 ] && ok "빈 입력 rc 2" || bad "빈 입력 → rc=$RC $OUT"

# ── push 게이트 훅(.claude/hooks/deferral-lint-gate.sh) ──
GATE="$HERE/../../.claude/hooks/deferral-lint-gate.sh"
bash -n "$GATE" && ok "gate bash -n" || bad "gate bash -n"
G="$T/gate"; mkdir -p "$G" && cd "$G" && git init -q -b main . && git config user.email t@t && git config user.name t
mkdir -p design/t/indices src && echo 카드 > design/t/indices/c.md && git add -A && git commit -qm base
git init -q --bare "$T/origin.git" && git remote add origin "$T/origin.git" && git push -q origin main 2>/dev/null
git checkout -q -b feat && git branch -q --set-upstream-to=origin/main
# gate <명령> — 훅에 PreToolUse JSON 을 넣는다. 출력+rc 는 OUT·RC.
gate() {
  OUT="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$1" "$G" \
    | FT_DEFERRAL_LINT_BIN="$LINT" bash "$GATE" 2>&1)"; RC=$?
}
cp "$FX/ok-py-card.py.fx" src/good.py; git add -A; git commit -qm good
gate "git push -u origin feat"; [ $RC -eq 0 ] && ok "gate: 통과 커밋 push → 허용" || bad "gate 허용 → rc=$RC $OUT"
cp "$FX/rej-py-nocard.py.fx" src/bad.py; git add -A; git commit -qm bad
gate "git push -u origin feat"; [ $RC -eq 2 ] && echo "$OUT" | grep -q 'REJECT src/bad.py:2' && ok "gate: 유예 주석 push → 차단(lint 출력 그대로)" || bad "gate 차단 → rc=$RC $OUT"
gate "cd /x && git -C . push origin feat"; [ $RC -eq 2 ] && ok "gate: 복합 명령 안 git push 도 차단" || bad "gate 복합 → rc=$RC $OUT"
gate "git commit -m 'git push 글자만 있는 메시지'"; [ $RC -eq 0 ] && ok "gate: 따옴표 안 'git push' 글자는 push 아님 → 허용" || bad "gate 따옴표 → rc=$RC $OUT"
gate "ls -la && echo git"; [ $RC -eq 0 ] && ok "gate: push 아닌 명령 → 허용" || bad "gate 비-push → rc=$RC $OUT"
echo '{broken' | bash "$GATE" >/dev/null 2>&1; [ $? -eq 0 ] && ok "gate: 입력 파싱 불가 → 통과(세션 brick 방지)" || bad "gate 파싱 불가"

# ── H1: 검사 대상 저장소 = 명령의 `git -C <dir>` (판정 1097 DA H1) — 가짜 저장소 2개 ──
mkrepo() {  # mkrepo <이름> <bad|clean>
  local r="$T/$1"; mkdir -p "$r" && ( cd "$r" && git init -q -b main . && git config user.email t@t && git config user.name t \
    && mkdir -p design/t/indices src && echo 카드 > design/t/indices/c.md && git add -A && git commit -qm base \
    && git init -q --bare "$T/$1-origin.git" && git remote add origin "$T/$1-origin.git" && git push -q origin main 2>/dev/null \
    && git checkout -q -b feat && git branch -q --set-upstream-to=origin/main \
    && { [ "$2" = bad ] && cp "$FX/rej-py-nocard.py.fx" src/bad.py && git add -A && git commit -qm bad || true; } ); }
mkrepo hbad bad; mkrepo hclean clean
HB="$T/hbad"; HC="$T/hclean"
# gate_in <cwd> <명령> — 지정 cwd 로 훅 호출
gate_in() {
  OUT="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$2" "$1" \
    | FT_DEFERRAL_LINT_BIN="$LINT" bash "$GATE" 2>&1)"; RC=$?
}
gate_in "$HC" "git -C $HB push origin feat"; [ $RC -eq 2 ] && echo "$OUT" | grep -q 'REJECT src/bad.py:2' && ok "H1(a): cwd=clean · -C bad 절대경로 → 차단" || bad "H1(a) → rc=$RC $OUT"
gate_in "$HB" "git -C $HC push origin feat"; [ $RC -eq 0 ] && ok "H1(b): cwd=bad · -C clean → 허용(오차단 0)" || bad "H1(b) → rc=$RC $OUT"
gate_in "$HC" "git -C $T/없는/경로 push origin feat"; [ $RC -eq 2 ] && echo "$OUT" | grep -q '검사 불가 대상' && ok "H1(c): -C 없는 경로 → 차단 + 사유(조용한 허용 0)" || bad "H1(c) → rc=$RC $OUT"
gate_in "$T" "git -C hbad push origin feat"; [ $RC -eq 2 ] && ok "H1(e): 상대경로 -C 는 cwd 기준" || bad "H1(e) → rc=$RC $OUT"
gate_in "$HC" "git -C $HB -C ../hclean push origin feat"; [ $RC -eq 0 ] && ok "H1(f): -C 연속은 누적(마지막이 clean)" || bad "H1(f) → rc=$RC $OUT"
gate_in "$HC" "git -C \"$HB\" push origin feat"; [ $RC -eq 2 ] && ok "H1(g): 따옴표 친 -C 경로도 해석" || bad "H1(g) → rc=$RC $OUT"
NG="$(mktemp -d)"; gate_in "$HC" "git -C $NG push origin feat"; rmdir "$NG"; [ $RC -eq 2 ] && echo "$OUT" | grep -q '검사 불가 대상' && ok "H1(h): -C 가 git 저장소 아님 → 차단 + 사유" || bad "H1(h) → rc=$RC $OUT"
gate_in "$HC" "git push origin feat"; [ $RC -eq 0 ] && ok "H1(d): -C 없음 = cwd(clean) → 허용" || bad "H1(d) → rc=$RC $OUT"

# ── fix2b: 같은 명령 안 cd/pushd 추적 (H1 동원인) ──
gate_in "$HC" "cd $HB && git push origin feat"; [ $RC -eq 2 ] && echo "$OUT" | grep -q 'REJECT src/bad.py:2' && ok "cd(i): cwd=clean · cd bad && push → 차단" || bad "cd(i) → rc=$RC $OUT"
gate_in "$HB" "cd $HC && git push origin feat"; [ $RC -eq 0 ] && ok "cd(j): cwd=bad · cd clean && push → 허용(오차단 0)" || bad "cd(j) → rc=$RC $OUT"
gate_in "$HC" "cd $HB && git -C . push origin feat"; [ $RC -eq 2 ] && ok "cd(k): cd bad && git -C . push → 차단(-C 는 cd 위에서 누적)" || bad "cd(k) → rc=$RC $OUT"
gate_in "$HC" "cd - && git push origin feat"; [ $RC -eq 2 ] && echo "$OUT" | grep -q 'cd 추적 불가' && ok "cd(l): cd - → 차단 + 「cd 추적 불가」" || bad "cd(l) → rc=$RC $OUT"
gate_in "$HC" "cd && git push origin feat"; [ $RC -eq 2 ] && echo "$OUT" | grep -q 'cd 추적 불가' && ok "cd(l2): cd 단독 → 차단 + 사유" || bad "cd(l2) → rc=$RC $OUT"
gate_in "$HC" "pushd $HB; git push origin feat"; [ $RC -eq 2 ] && ok "cd(n): pushd bad; push → 차단" || bad "cd(n) → rc=$RC $OUT"
gate_in "$HC" "pushd $HB && popd && git push origin feat"; [ $RC -eq 2 ] && echo "$OUT" | grep -q 'cd 추적 불가' && ok "cd(o): popd 뒤 push → 차단 + 사유" || bad "cd(o) → rc=$RC $OUT"
gate_in "$T" "cd hbad && git push origin feat"; [ $RC -eq 2 ] && ok "cd(p): 상대경로 cd 는 지금 위치 기준" || bad "cd(p) → rc=$RC $OUT"
gate_in "$HC" "cd $HB || true; ls; git push origin feat"; [ $RC -eq 2 ] && ok "cd(q): || ; 구분자는 cur 를 되돌리지 않음" || bad "cd(q) → rc=$RC $OUT"
gate_in "$HC" "cd $HB && git commit -m x && cd $HC && git push origin feat"; [ $RC -eq 0 ] && ok "cd(r): 다시 clean 으로 cd 한 뒤 push → 허용" || bad "cd(r) → rc=$RC $OUT"
cd "$T"

[ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
