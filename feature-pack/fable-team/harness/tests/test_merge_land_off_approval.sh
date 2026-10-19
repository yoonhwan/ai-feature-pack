#!/usr/bin/env bash
# test_merge_land_off_approval.sh — R336: 자율 OFF 에서도 착지 = 오빠 approve-merge 승인 파일 + log 한 줄 (임시 origin+clone · gh 스텁 · 가짜 state-dir · 실 PR·실 main 0)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; LAND="$BIN/ft-merge-land.sh"; AUT="$BIN/ft-autonomy.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/.fable-team"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/install-stub"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
echo "$*" >> "$STUB_LOG"
EOF
printf '#!/bin/bash\nexit 0\n' > "$T/install-stub"; chmod +x "$T/gh-stub" "$T/install-stub"
omain() { sha "$ORIGIN" refs/heads/main; }
mkpr() {  # mkpr <번호> — origin/main 에서 딴 PR head 를 refs/pull/N/head 에 올리고 스텁 JSON 작성
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"본문 "+sys.argv[2],"state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
land() { out="$(bash "$LAND" "$@" --repo "$W" 2>&1)"; rc=$?; }
approve() { out="$(bash "$AUT" approve-merge "$@" 2>&1)"; rc=$?; }
FILE() { echo "$T/state/autonomy-merge-approved/$1"; }

bash -n "$LAND" && bash -n "$AUT"; ck "bash -n land·autonomy" $?
[ "$(bash "$AUT" mode)" = off ]; ck "전제: 자율 OFF" $?

# ① OFF · 승인 파일 없음 → REJECT rc2 · main 불변 · PR 쓰기 0
mkpr 1; P1="$PRSHA"; M1="$(omain)"
land 1 --approve-sha "$P1"
[ "$rc" = 2 ] && [[ "$out" == *"승인 파일"* ]] && [ "$(omain)" = "$M1" ] && [ ! -s "$STUB_LOG" ]; ck "① OFF · 승인 파일 없음 → REJECT rc2 · main 불변 · 실행 0" $?

# ④ OFF 에서 approve-merge → 기록 1줄(이벤트 칸 OFF) · 파일 1줄 · 상태는 OFF 그대로(위변조 아님)
approve "$P1"
[ "$rc" = 0 ] && [[ "${out%%$'\n'*}" == "APPROVED $P1 OFF" ]];ck "④ OFF · approve-merge 기록 성공(APPROVED … OFF)" $?
[ "$(wc -l < "$(FILE "$P1")" | tr -d ' ')" = 1 ] && grep -qE "^approve-merge $P1 OFF [0-9]+$" "$(FILE "$P1")" && grep -qxF "$(head -n1 "$(FILE "$P1")")" "$T/state/autonomy.log"; ck "④ 승인 파일 1줄 == autonomy.log 한 줄(이벤트 OFF)" $?
[ "$(bash "$AUT" mode)" = off ]; ck "④ 승인 뒤에도 mode=off(위변조 아님)" $?
approve "$P1" "xyz"; [ "$rc" = 2 ]; ck "④ 형식 틀린 sha → 여전히 REJECT rc2" $?

# ② OFF · 승인 파일+로그 있음 → 착지 · merge-gate.log 에 approve-file=<epoch>
land 1 --approve-sha "$P1"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(omain)" != "$M1" ]; ck "② OFF · 승인 파일 있음 → 착지" $?
EP="$(awk '{print $4}' "$(FILE "$P1")")"
grep -q "method=ft-merge-land .*pr=1 approve=$P1 approve-file=$EP$" "$T/state/merge-gate.log"; ck "② merge-gate.log 줄에 approve-file=<승인 epoch>" $?

# 파일만 직접 쓰기(로그 줄 없음) → OFF 여도 REJECT (파일+log 글자 일치)
mkpr 2; P2="$PRSHA"; M2="$(omain)"
mkdir -p "$T/state/autonomy-merge-approved"; echo "approve-merge $P2 OFF 1" > "$(FILE "$P2")"
land 2 --approve-sha "$P2"
[ "$rc" = 2 ] && [ "$(omain)" = "$M2" ]; ck "OFF · 파일만 있고 log 줄 없음 → REJECT rc2" $?

# ③ ON 위변조 → 승인 파일 없으면 그대로 REJECT · approve-merge 도 REJECT
bash "$AUT" on >/dev/null 2>&1; printf 'garbage line\n' >> "$T/state/autonomy.log"
[ "$(bash "$AUT" mode)" = tamper ]; ck "전제: 위변조 상태" $?
mkpr 3; P3="$PRSHA"; M3="$(omain)"
land 3 --approve-sha "$P3"; [ "$rc" = 2 ] && [ "$(omain)" = "$M3" ]; ck "③ 위변조 · 승인 파일 없음 → REJECT rc2" $?
approve "$P3"; [ "$rc" = 2 ] && [ ! -e "$(FILE "$P3")" ]; ck "③ 위변조 · approve-merge → REJECT rc2 · 파일 0" $?

[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
