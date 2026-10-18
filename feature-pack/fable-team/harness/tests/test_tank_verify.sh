#!/usr/bin/env bash
# test_tank_verify.sh — ft-tank-verify.sh 5단계 시험 (가짜 gh · 네트워크 0)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"; BIN="$HERE/../../harness/bin"
T="$(mktemp -d)"; trap 'find "$T" -mindepth 1 -delete 2>/dev/null; rmdir "$T" 2>/dev/null' EXIT
pass=0; fail=0
ok() { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
a="$*"
case "$a" in
  "api users/"*) [ "${STUB_ACCOUNT:-1}" = 1 ] && echo "${STUB_LOGIN:-byz-tank}" || exit 1;;
  "api repos/"*"/collaborators/"*) [ -n "${STUB_PERM:-}" ] && echo "$STUB_PERM" || exit 1;;
  "api user"*) echo "${STUB_WHO:-byz-tank}";;
  "issue create"*) echo "https://github.com/x/y/issues/901";;
  "api repos/"*"/issues/"*) echo "${STUB_AUTHOR:-byz-tank}";;
  "issue close"*) exit 0;;
  *) exit 1;;
esac
STUB
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" HOME="$T/home"; mkdir -p "$HOME/.config/byz-harness"
TF="$HOME/.config/byz-harness/issue-bot.token"
run() { bash "$BIN/ft-tank-verify.sh" "$@" 2>&1; }

bash -n "$BIN/ft-tank-verify.sh" && ok "bash -n" || bad "bash -n"
OUT="$(STUB_ACCOUNT=0 run)"; rc=$?; [ $rc -eq 1 ] && echo "$OUT" | grep -q 'FAIL \[1\]' && ok "계정 없음 → FAIL 1" || bad "계정 없음 rc=$rc"
OUT="$(STUB_PERM= run)"; rc=$?; [ $rc -eq 1 ] && echo "$OUT" | grep -q 'FAIL \[2\]' && ok "권한 없음 → FAIL 2" || bad "권한 없음 rc=$rc"
OUT="$(STUB_PERM=read run)"; rc=$?; [ $rc -eq 1 ] && echo "$OUT" | grep -q 'triage 이상 필요' && ok "read 권한 → FAIL 2" || bad "read 권한 rc=$rc"
OUT="$(STUB_PERM=triage run)"; rc=$?; [ $rc -eq 1 ] && echo "$OUT" | grep -q 'FAIL \[3\]' && ok "토큰 없음 → FAIL 3" || bad "토큰 없음 rc=$rc"
echo "tok123" > "$TF"; chmod 644 "$TF"
OUT="$(STUB_PERM=triage run)"; rc=$?; [ $rc -eq 1 ] && echo "$OUT" | grep -q '권한 644' && ok "토큰 파일 644 → FAIL 3" || bad "토큰 644 rc=$rc"
chmod 600 "$TF"
OUT="$(STUB_PERM=triage STUB_WHO=yoonhwan run)"; rc=$?; [ $rc -eq 1 ] && echo "$OUT" | grep -q 'FAIL \[4\]' && ok "토큰 주인 오빠 → FAIL 4" || bad "토큰 주인 rc=$rc"
OUT="$(STUB_PERM=triage run)"; rc=$?; [ $rc -eq 0 ] && echo "$OUT" | grep -q 'ALL PASS' && ok "1~4 통과 → ALL PASS" || bad "1~4 rc=$rc"
echo "$OUT" | grep -q 'tok123' && bad "토큰 값 출력됨" || ok "토큰 값 미출력"
OUT="$(STUB_PERM=triage STUB_AUTHOR=yoonhwan run --issue-test)"; rc=$?; [ $rc -eq 1 ] && echo "$OUT" | grep -q 'FAIL \[5\]' && ok "시험 Issue 작성자 오빠 → FAIL 5" || bad "작성자 rc=$rc"
OUT="$(STUB_PERM=triage run --issue-test)"; rc=$?; [ $rc -eq 0 ] && echo "$OUT" | grep -q 'issue=#901 author=byz-tank' && ok "시험 Issue 작성자 byz-tank → PASS 5" || bad "작성자 통과 rc=$rc"
bash "$BIN/ft-tank-verify.sh" --bogus >/dev/null 2>&1; [ $? -eq 2 ] && ok "알 수 없는 인자 exit 2" || bad "usage rc"
echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
