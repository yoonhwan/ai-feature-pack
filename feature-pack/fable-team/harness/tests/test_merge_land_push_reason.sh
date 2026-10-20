#!/usr/bin/env bash
# test_merge_land_push_reason.sh — r595: push 실패 REJECT 문구가 거부 사유 줄(로컬 pre-push 훅 PUSH_DENIED · 서버 remote: 줄)을
#   보여 주고 출력 전문을 파일로 남기는지 (임시 origin+clone · gh 스텁 · 실제 GitHub push 0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) exit 2;; esac
echo "$*" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
omain() { sha "$ORIGIN" refs/heads/main; }
mkpr() {  # mkpr <번호> <브랜치> <시작점>
  git -C "$W" checkout -q -B "$2" "$3"; rm -rf "$W/.git/hooks/pre-push"; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"본문 "+sys.argv[2],"state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
land() { apv "$@"; out="$(bash "$LAND" "$@" --repo "$W" 2>&1)"; rc=$?; }
newfiles() { find "$T/state/push-out" -type f 2>/dev/null | sort; }

bash -n "$LAND"; ck "bash -n land" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄" $?

# ⓐ 로컬 pre-push 훅 거부(PUSH_DENIED 여러 줄 · exit 1) → REJECT 줄에 그 사유 + 전문=<파일> 1개 · 파일에 전문
git -C "$W" fetch -q origin; mkpr 51 pr51 origin/main; MA="$(omain)"
printf '#!/bin/bash\necho "PUSH_DENIED — 이 push range 에 제품코드가 있다" >&2\necho "range f537bd6b..ee674d91 · clients/web/src/x.ts" >&2\nexit 1\n' > "$W/.git/hooks/pre-push"; chmod +x "$W/.git/hooks/pre-push"
land 51 --approve-sha "$PRSHA"
[ "$rc" = 1 ] && [[ "$out" == *"PUSH_DENIED"* ]]; ck "ⓐ1 훅 거부 → REJECT 줄에 PUSH_DENIED 원문" $?
FA="$(newfiles)"; [ "$(printf '%s\n' "$FA" | grep -c .)" = 1 ] && [[ "$out" == *"전문=$FA"* ]]; ck "ⓐ2 REJECT 줄에 전문=<파일> 1개(그 경로 실재)" $?
grep -q 'PUSH_DENIED' "$FA" && grep -q 'clients/web/src/x.ts' "$FA"; ck "ⓐ3 전문 파일에 훅 stderr 전 줄" $?
[ "$(omain)" = "$MA" ]; ck "ⓐ4 main 불변(착지 0)" $?
rm -f "$W/.git/hooks/pre-push"; rm -rf "$T/state/push-out"

# ⓑ 서버 pre-receive 훅이 remote: 5줄 내고 거부 → REJECT 에 remote: 줄 최대 3줄 · 전문 파일에 5줄 전부
git -C "$W" fetch -q origin; mkpr 52 pr52 origin/main; MB="$(omain)"
printf '#!/bin/bash\ncat >/dev/null\nfor i in 1 2 3 4 5; do echo "server says no $i" >&2; done\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod +x "$ORIGIN/hooks/pre-receive"
land 52 --approve-sha "$PRSHA"
[ "$rc" = 1 ] && [ "$(printf '%s' "$out" | grep -o 'remote: server says no' | grep -c .)" = 3 ]; ck "ⓑ1 REJECT 에 remote: 사유 줄 최대 3줄(앞에서부터)" $?
[[ "$out" == *"remote: server says no 1"* ]] && [[ "$out" != *"remote: server says no 4"* ]]; ck "ⓑ2 앞 3줄만(1~4번째 줄 0)" $?
FB="$(newfiles)"; [ -n "$FB" ] && [ "$(grep -c 'server says no' "$FB")" = 5 ]; ck "ⓑ3 전문 파일에 5줄 전부" $?
[ "$(omain)" = "$MB" ]; ck "ⓑ4 main 불변" $?
rm -f "$ORIGIN/hooks/pre-receive"; rm -rf "$T/state/push-out"

# ⓒ 서버 응답 전 연결 실패 → 재시도 1회 그대로(횟수·rc 불변) · 최종 착지
SP="$T/shimP"; mkdir -p "$SP"; PLOG="$T/push.log"; REAL_TO="$(command -v timeout)"
cat > "$SP/timeout" <<EOF
#!/bin/bash
p=0; for a in "\$@"; do [ "\$a" = push ] && p=1; done
[ "\$p" = 1 ] || exec "$REAL_TO" "\$@"
echo x >> "$PLOG"; [ "\$(wc -l < "$PLOG" | tr -d ' ')" = 1 ] && { echo "ssh: connect to host github.com port 22: Connection timed out" >&2; echo "fatal: Could not read from remote repository." >&2; exit 128; }
shift; exec "\$@"
EOF
chmod +x "$SP/timeout"; : > "$PLOG"
git -C "$W" fetch -q origin; mkpr 53 pr53 origin/main
apv --approve-sha "$PRSHA"; out="$(env PATH="$SP:$PATH" bash "$LAND" 53 --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(wc -l < "$PLOG" | tr -d ' ')" = 2 ] && [[ "$out" == LANDED* ]]; ck "ⓒ1 연결 실패 → 재시도 1회(2시도) 그대로 · 착지 rc0" $?
[ -z "$(newfiles)" ]; ck "ⓒ2 성공 경로는 전문 파일 0" $?

# ⓓ 성공 push → LANDED·push ok 줄 불변 · 전문 파일 0
git -C "$W" fetch -q origin; mkpr 54 pr54 origin/main
land 54 --approve-sha "$PRSHA"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [[ "$out" == *"push ok objects="* ]]; ck "ⓓ1 성공 착지 LANDED + push ok 줄 불변" $?
[ -z "$(newfiles)" ]; ck "ⓓ2 성공 시 전문 파일 0" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
