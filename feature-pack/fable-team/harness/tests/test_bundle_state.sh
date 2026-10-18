#!/usr/bin/env bash
# test_bundle_state.sh — C10 ft-bundle-state.sh 시험: 정상 1바퀴 · 금지 전이 3종 · 재오픈 경로 · 원본 JSON 불변. 복사본만 만진다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="$HERE/../../harness/bin/ft-bundle-state.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$TOOL" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ORIG="$T/orig.json"
cat > "$ORIG" <<'EOF'
{"team":"t","test_bundle":{"mode":"press-api","card":"C10","seat":"ft-x-tester#0","state":"open","open_event":"100","close_event":null}}
EOF
MD5_BEFORE="$(md5 -q "$ORIG" 2>/dev/null || md5sum "$ORIG" | cut -d' ' -f1)"
W="$T/work.json"; cp "$ORIG" "$W"
st() { jq -r '.test_bundle.state' "$1"; }
run() { bash "$TOOL" "$@" 2>&1; }

# 정상 1바퀴: open → reported → classified(PASS) → closed
out="$(run "$W" C10 reported)"; [ $? -eq 0 ] && [ "$(st "$W")" = reported ] && ok "open->reported" || bad "open->reported: $out"
out="$(run "$W" C10 classified --result PASS)"; [ $? -eq 0 ] && [ "$(st "$W")" = classified ] && ok "reported->classified" || bad "reported->classified: $out"
out="$(run "$W" C10 closed --event 120)"; [ $? -eq 0 ] && [ "$(st "$W")" = closed ] && ok "classified->closed" || bad "classified->closed: $out"
[ "$(jq -r '.test_bundle.close_event' "$W")" = 120 ] && ok "close_event 기록" || bad "close_event"

# 금지 전이 3종 (파일 불변 확인)
cp "$ORIG" "$W"
before="$(md5 -q "$W" 2>/dev/null || md5sum "$W" | cut -d' ' -f1)"
run "$W" C10 closed >/dev/null; rc=$?
[ $rc -eq 1 ] && ok "금지 open->closed exit 1" || bad "open->closed rc=$rc"
run "$W" C10 classified --result PASS >/dev/null; rc=$?
[ $rc -eq 1 ] && ok "금지 open->classified exit 1" || bad "open->classified rc=$rc"
run "$W" C10 open >/dev/null; rc=$?
[ $rc -eq 1 ] && ok "금지 open->open exit 1" || bad "open->open rc=$rc"
after="$(md5 -q "$W" 2>/dev/null || md5sum "$W" | cut -d' ' -f1)"
[ "$before" = "$after" ] && ok "거부된 전이는 파일 불변" || bad "거부 후 파일 변경됨"

# 결과 규칙: result 없이 classified 거부 · FAIL 이면 closed 거부
run "$W" C10 reported >/dev/null
run "$W" C10 classified >/dev/null; [ $? -eq 1 ] && ok "classified --result 없으면 거부" || bad "result 없는 classified"
run "$W" C10 classified --result FAIL >/dev/null
run "$W" C10 closed >/dev/null; [ $? -eq 1 ] && ok "result=FAIL 이면 closed 거부" || bad "FAIL closed"

# 재오픈 경로: classified(FAIL) → reopen → reported → classified(UNMEASURED) → reopen 2회째 거부
out="$(run "$W" C10 reopen)"; [ $? -eq 0 ] && [ "$(st "$W")" = reopen ] && [ "$(jq -r '.test_bundle.reopen_count' "$W")" = 1 ] && ok "classified->reopen (count=1)" || bad "reopen: $out"
run "$W" C10 reported >/dev/null; [ "$(st "$W")" = reported ] && ok "reopen->reported" || bad "reopen->reported"
run "$W" C10 classified --result UNMEASURED >/dev/null
run "$W" C10 reopen >/dev/null; [ $? -eq 1 ] && ok "reopen 2회째 거부" || bad "reopen 2회째"

# 입력 오류: 카드 불일치 · 없는 파일 · 나쁜 상태 → exit 2
run "$W" C99 reported >/dev/null; [ $? -eq 2 ] && ok "카드 불일치 exit 2" || bad "카드 불일치"
run "$T/none.json" C10 reported >/dev/null; [ $? -eq 2 ] && ok "없는 파일 exit 2" || bad "없는 파일"
run "$W" C10 bogus >/dev/null; [ $? -eq 2 ] && ok "나쁜 상태 exit 2" || bad "나쁜 상태"

# 임시파일 잔여 0 · 원본 JSON 바이트 불변
[ -z "$(ls -A "$T" | grep '^\.bundle-state')" ] && ok "임시파일 잔여 0" || bad "임시파일 잔여"
MD5_AFTER="$(md5 -q "$ORIG" 2>/dev/null || md5sum "$ORIG" | cut -d' ' -f1)"
[ "$MD5_BEFORE" = "$MD5_AFTER" ] && ok "원본 JSON md5 동일 ($MD5_AFTER)" || bad "원본 JSON 변경됨"

echo "fail=$fail"; [ $fail -eq 0 ]
