#!/usr/bin/env bash
# test_secret_output_mask.sh — PostToolUse 비밀 출력 가림 훅 secret-output-mask.sh (R135b · 판정 1585)
# 격리: 임시 HOME·원장 + 훅에 가짜 PostToolUse JSON 만 먹인다 — 실 ~/.claude·실 세션 기록·실 비밀 0. 값은 전부 가짜(FAKE…).
# 변이 2: ⓐ형태 키 하나 뺀 복사본 → 형태 축 FAIL · ⓑ자리표시자 제외 지운 복사본 → 오탐 축 FAIL.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; HK="$ROOT/scripts/harness-install/fable-team/templates/hooks"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" FT_SECRET_LEAK_LOG="$T/leak.log" FT_SECRET_FALSEPOS_LOG="$T/falsepos.log"
mkdir -p "$HOME"
FAKE_DSN="postgres://u:FAKEPW1234@h/db"; FAKE_TOK="ghp_FAKEA1b2C3d4E5f6G7h8I9j0K1l2M3n4"; FAKE_JWT="eyJFAKE.FAKE.FAKE"

suite() {  # $1 = 훅 폴더 · stdout 에 PASS/FAIL 줄 · 마지막 줄 fails=N
  local D="$1" fail=0 rc out
  ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
  mk() { python3 -c 'import json,sys;print(json.dumps({"session_id":"s-test","tool_name":sys.argv[1],"tool_response":json.loads(sys.argv[2])},ensure_ascii=False))' "$1" "$2"; }
  run() { out="$(printf '%s' "$1" | "$BASH" "$D/secret-output-mask.sh" 2>"$T/err")"; rc=$?; }
  same_shape() { python3 -c '
import json,sys
a=json.loads(sys.argv[1])["tool_response"]; o=json.loads(sys.argv[2])
b=o["hookSpecificOutput"]["updatedToolOutput"]
def same(x,y):
    if isinstance(x,dict): return isinstance(y,dict) and x.keys()==y.keys() and all(same(x[k],y[k]) for k in x)
    if isinstance(x,list): return isinstance(y,list) and len(x)==len(y) and all(same(p,q) for p,q in zip(x,y))
    if isinstance(x,str): return isinstance(y,str)
    return x==y
assert o["hookSpecificOutput"]["hookEventName"]=="PostToolUse"
sys.exit(0 if same(a,b) else 1)' "$1" "$2"; }
  no_value() { ! grep -q -e FAKEPW -e FAKEA1b2 -e "$FAKE_JWT" "$@"; }

  bash -n "$D/secret-output-mask.sh" 2>/dev/null; ck "bash -n" $?
  local B IN
  B='{"stdout":"conn '"$FAKE_DSN"' ok","stderr":"","interrupted":false,"isImage":false}'
  IN="$(mk Bash "$B")"; run "$IN"
  [ "$rc" = 0 ] && same_shape "$IN" "$out"; ck "형태: Bash {stdout,stderr,interrupted,isImage} 그대로" $?
  grep -q 'postgres://u:\*\*\*@h/db' <<<"$out"; ck "가림: Bash DSN → ***" $?
  no_value "$T/err" "$T/leak.log" <<<"$out"; ck "값 0: 출력 stderr 원장" $?
  printf '%s' "$out" | no_value /dev/stdin; ck "값 0: 훅 출력 본문" $?
  IN="$(mk Read '{"type":"text","file":{"filePath":"/x/a.txt","content":"t '"$FAKE_TOK"'\nok","numLines":2}}')"; run "$IN"
  [ "$rc" = 0 ] && same_shape "$IN" "$out" && ! grep -q FAKEA1b2 <<<"$out"; ck "Read: 중첩 content 가림 · 형태 그대로" $?
  IN="$(mk mcp__x__y '[{"type":"text","text":"jwt '"$FAKE_JWT"'"}]')"; run "$IN"
  [ "$rc" = 0 ] && same_shape "$IN" "$out" && ! grep -q "$FAKE_JWT" <<<"$out"; ck "mcp: 블록 목록 가림 · 형태 그대로" $?
  IN="$(mk WebFetch '"plain '"$FAKE_TOK"'"')"; run "$IN"
  [ "$rc" = 0 ] && same_shape "$IN" "$out" && ! grep -q FAKEA1b2 <<<"$out"; ck "문자열 tool_response 가림" $?
  IN="$(mk Bash '{"stdout":"12 passed in 0.3s\npostgres://u:***@h/db\nAPI_TOKEN=<token>","stderr":"","interrupted":false,"isImage":false}')"; run "$IN"
  r=1; [ "$rc" = 0 ] && [ -z "$out" ] && r=0; ck "오탐 0: 자리표시자·평범한 출력 → 출력 0 rc 0" $r
  grep -q 'tool=Bash kinds=url-cred' "$T/leak.log"; ck "원장: 시각·세션·도구·종류 1줄(값 0)" $?
  run '{ 깨진 json'
  [ "$rc" = 0 ] && [ -z "$out" ] && grep -q fail-open "$T/err" && grep -q 'secret-output-mask' "$T/falsepos.log"; ck "깨진 JSON → 원본 통과 rc 0 + falsepos 1줄" $?
  out="$(printf '%s' "$IN" | FT_SECRET_SHAPES="$T/없는파일.py" "$BASH" "$D/secret-output-mask.sh" 2>/dev/null)"; rc=$?
  r=1; [ "$rc" = 0 ] && [ -z "$out" ] && r=0; ck "모듈 없음 → 원본 통과 rc 0" $r
  IN="$(mk Bash "$B")"; out="$(printf '%s' "$IN" | FT_SECRET_GUARD_TEST_OFF=1 "$BASH" "$D/secret-output-mask.sh" 2>/dev/null)"
  [ -z "$out" ]; ck "FT_SECRET_GUARD_TEST_OFF → 가림 0" $?
  echo "fails=$fail"
}

if [ "${1:-}" = "--suite" ]; then suite "$2"; exit 0; fi
res="$(suite "$HK")"; echo "$res"; f="$(sed -n 's/^fails=//p' <<<"$res")"; fail="${f:-1}"

mut() {  # $1 = 이름 · $2 = sed 식 · $3 = 기대 FAIL 줄에 든 글자
  local M="$T/mut-$1"; mkdir -p "$M"; cp "$HK"/secret-output-mask.sh "$HK"/ft_secret_shapes.py "$HK"/ft_secret_targets.py "$HK"/ft_secret_lex.py "$M/"
  sed -i.bak "$2" "$M/ft_secret_shapes.py"; cmp -s "$M/ft_secret_shapes.py" "$HK/ft_secret_shapes.py" && { echo "FAIL 변이 $1 — 복사본이 원본과 같다(식이 안 맞음)"; fail=$((fail+1)); return; }
  local r; r="$(bash "$HERE/test_secret_output_mask.sh" --suite "$M" 2>&1)"
  if grep -q "^FAIL .*$3" <<<"$r"; then echo "PASS 변이 $1 → $3 축 FAIL 확인"; else echo "FAIL 변이 $1 — $3 축이 안 깨졌다"; fail=$((fail+1)); fi
}
mut shape 's/return {k: _walk(x, hits) for k, x in v.items()}/return {k: _walk(x, hits) for k, x in v.items() if k != "isImage"}/' "형태"
mut placeholder 's/^PH = .*/PH = r""/; s/^_PLACEHOLDER_ONLY = .*/_PLACEHOLDER_ONLY = re.compile(r"(?!)")/' "오탐"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
[ "$fail" = 0 ]
