#!/usr/bin/env bash
# test_gh_tank_comment_edit.sh — ft-gh-as-tank.sh comment-edit + ft-gh-tank-comment-edit.sh(본체) 시험. 실제 GitHub 호출 0 — PATH 맨 앞 가짜 gh.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
WRAP="$ROOT/scripts/fable-team-bin/ft-gh-as-tank.sh"
BODY="$ROOT/scripts/fable-team-bin/ft-gh-tank-comment-edit.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"; LOG="$T/gh.log"; ARGV="$T/gh.argv"; PATCH_IN="$T/patch.stdin"; ALLOUT="$T/all.out"; : > "$LOG"; : > "$ARGV"; : > "$ALLOUT"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
# 가짜 gh: 호출(env 토큰 포함)을 STUB_LOG, 인자만 STUB_ARGV 에 남긴다. api user = STUB_LOGIN, comments GET = STUB_GET_JSON, PATCH = stdin 을 저장하고 되돌려준다.
echo "GH_TOKEN=${GH_TOKEN:-} $*" >> "$STUB_LOG"; echo "$*" >> "$STUB_ARGV"
case "$1 $2" in
  "api user") echo "${STUB_LOGIN:-byz-tank}";;
  "api -X")
    cat > "$STUB_PATCH_IN"
    [ "${STUB_PATCH_RC:-0}" = 0 ] || exit 1
    python3 -c 'import json,os,sys
d=json.load(open(sys.argv[1])); b=os.environ.get("STUB_PATCH_BODY")
print(json.dumps({"body": d["body"] if b is None else b, "html_url":"u"}))' "$STUB_PATCH_IN";;
  "api repos/"*) [ "${STUB_GET_RC:-0}" = 0 ] || exit 1; echo "${STUB_GET_JSON-}";;
esac
exit 0
EOF
chmod +x "$T/bin/gh"
export STUB_LOG="$LOG" STUB_ARGV="$ARGV" STUB_PATCH_IN="$PATCH_IN" PATH="$T/bin:$PATH"
TOKEN="tok_SECRET_VALUE_123"; BAK="$T/bak"
export FT_ISSUE_EDIT_BAK_DIR="$BAK"

ORIG=$'옛 본문 "따옴표"\n`백틱` 둘째줄\n끝'
NEW=$'새 본문 "따옴표" \'작은따옴표\'\n`백틱` $HOME \\n\n마지막 줄'
printf '%s' "$NEW" > "$T/new.md"
getjson() { python3 -c 'import json,sys
print(json.dumps({"user":{"login":sys.argv[1]},"html_url":"https://github.com/o/r/issues/6#issuecomment-123","body":sys.argv[2]}))' "$1" "$ORIG"; }
export STUB_GET_JSON; STUB_GET_JSON="$(getjson byz-tank)"

bash -n "$WRAP" && ok "bash -n 래퍼" || bad "bash -n 래퍼"
bash -n "$BODY" && ok "bash -n 본체" || bad "bash -n 본체"
[ -x "$BODY" ] && ok "본체 실행 비트" || bad "본체 실행 비트 없음"
for f in "$WRAP" "$BODY"; do n=$(wc -l < "$f"); [ "$n" -le 200 ] && ok "$(basename "$f") ${n}줄 ≤ 200" || bad "$(basename "$f") ${n}줄 > 200"; done

run() { out="$("$@" 2>&1)"; rc=$?; echo "$out" >> "$ALLOUT"; }   # 출력 전부를 ALLOUT 에 모아 마지막에 토큰 누출 검사
apply() { run env FT_ISSUE_BOT_TOKEN=$TOKEN "$@" bash "$WRAP" comment-edit 123 "$T/new.md" --apply; }
gh_lines() { grep -c -- "$1" "$LOG"; }
reset() { : > "$LOG"; : > "$ARGV"; rm -rf "$BAK" "$PATCH_IN"; }

# ⓐ dry-run → gh 호출 0 · DRY 줄
reset
run env -u FT_ISSUE_BOT_TOKEN FT_ISSUE_BOT_TOKEN_FILE=/nonexistent bash "$WRAP" comment-edit 123 "$T/new.md"
[ $rc -eq 0 ] && [ "$out" = "DRY as=byz-tank comment-edit 123 $T/new.md" ] && ok "ⓐ dry-run DRY 줄" || bad "ⓐ dry-run → rc=$rc $out"
[ ! -s "$LOG" ] && ok "ⓐ dry-run gh 호출 0" || bad "ⓐ dry-run 인데 gh 호출됨: $(cat "$LOG")"

# ⓑ 작성자 byz-tank → GET 1 · PATCH 1(body = 파일 내용) · 보관 = 원문 · OK 줄 + 되돌림 줄
reset; apply
[ $rc -eq 0 ] && ok "ⓑ apply rc=0" || bad "ⓑ apply → rc=$rc $out"
[ "$(gh_lines 'api repos/SecondWindStudio/byz-agents/issues/comments/123$')" = 1 ] && ok "ⓑ 코멘트 GET 1" || bad "ⓑ GET 횟수: $(cat "$LOG")"
[ "$(gh_lines 'api -X PATCH repos/SecondWindStudio/byz-agents/issues/comments/123 --input -')" = 1 ] && ok "ⓑ PATCH 1" || bad "ⓑ PATCH 횟수: $(cat "$LOG")"
grep -F "GH_TOKEN=$TOKEN" "$LOG" | grep -q "api -X PATCH" && ok "ⓑ PATCH 에 Tank 토큰" || bad "ⓑ PATCH 토큰 누락"
python3 -c 'import json,sys
sys.exit(0 if json.load(open(sys.argv[1]))["body"]==open(sys.argv[2],encoding="utf-8",newline="").read() else 1)' "$PATCH_IN" "$T/new.md" \
  && ok "ⓑ PATCH stdin JSON body = 파일 내용(따옴표·줄바꿈·백틱)" || bad "ⓑ PATCH body ≠ 파일: $(cat "$PATCH_IN" 2>&1)"
BF="$(ls "$BAK"/comment123-*.body.md 2>/dev/null | head -1)"
[ -n "$BF" ] && [ "$(cat "$BF"; printf x)" = "${ORIG}x" ] && ok "ⓑ 보관 파일 = 원문" || bad "ⓑ 보관 파일: ${BF:-없음}"
grep -q "^OK as=byz-tank comment-edit 123 — https://github.com/o/r/issues/6#issuecomment-123 bak=$BF\$" <<<"$out" && ok "ⓑ OK 줄" || bad "ⓑ OK 줄: $out"
grep -q "^되돌림: bash .*ft-gh-as-tank.sh comment-edit 123 $BF --apply\$" <<<"$out" && ok "ⓑ 되돌림 줄" || bad "ⓑ 되돌림 줄: $out"

# ⓒ 작성자 다른 계정 → PATCH 0 · exit 1
reset; STUB_GET_JSON="$(getjson yoonhwan)" apply
[ $rc -eq 1 ] && grep -q "REJECT 코멘트 작성자가 byz-tank 가 아니다(작성자=yoonhwan)" <<<"$out" && ok "ⓒ 작성자 불일치 rc=1" || bad "ⓒ rc=$rc $out"
[ "$(gh_lines PATCH)" = 0 ] && [ ! -d "$BAK" ] && ok "ⓒ PATCH 0 · 보관 0" || bad "ⓒ PATCH/보관 발생"

# ⓓ GET 실패(rc≠0 · 빈 응답 · JSON 아님) → PATCH 0 · exit 1
for mode in "STUB_GET_RC=1" "STUB_GET_JSON=" "STUB_GET_JSON=not-json"; do
  reset; apply env "$mode"
  [ $rc -eq 1 ] && [ "$(gh_lines PATCH)" = 0 ] && ok "ⓓ 조회 이상 [$mode] → rc=1 · PATCH 0" || bad "ⓓ [$mode] rc=$rc PATCH=$(gh_lines PATCH) $out"
done

# ⓔ 보관 폴더 쓰기 불가 → PATCH 0 · exit 1
reset; : > "$T/notadir"
apply FT_ISSUE_EDIT_BAK_DIR="$T/notadir/sub"
[ $rc -eq 1 ] && grep -q "보관 폴더 생성 실패" <<<"$out" && [ "$(gh_lines PATCH)" = 0 ] && ok "ⓔ 보관 불가 → rc=1 · PATCH 0" || bad "ⓔ rc=$rc PATCH=$(gh_lines PATCH) $out"

# ⓕ 토큰 없음 → exit 2 · gh 호출 0 (래퍼 · 본체 직접)
reset
run env -u FT_ISSUE_BOT_TOKEN FT_ISSUE_BOT_TOKEN_FILE=/nonexistent bash "$WRAP" comment-edit 123 "$T/new.md" --apply
[ $rc -eq 2 ] && grep -q "봇 토큰 없음" <<<"$out" && ok "ⓕ 래퍼 토큰 없음 rc=2" || bad "ⓕ 래퍼 rc=$rc $out"
run env -u FT_TANK_TOK bash "$BODY" 123 "$T/new.md"
[ $rc -eq 2 ] && ok "ⓕ 본체 토큰 없음 rc=2" || bad "ⓕ 본체 rc=$rc $out"
[ ! -s "$LOG" ] && ok "ⓕ gh 호출 0" || bad "ⓕ gh 호출됨: $(cat "$LOG")"

# ⓖ 토큰 주인 ≠ byz-tank → exit 1 · 코멘트 GET 0
reset; apply STUB_LOGIN=yoonhwan
[ $rc -eq 1 ] && grep -q "토큰 주인이 byz-tank 가 아니다(주인=yoonhwan)" <<<"$out" && [ "$(gh_lines 'issues/comments')" = 0 ] && ok "ⓖ 토큰 주인 불일치 rc=1 · 코멘트 GET 0" || bad "ⓖ rc=$rc $out"

# ⓗ 응답 body ≠ 파일 → exit 1
reset; apply STUB_PATCH_BODY="다른 본문"
[ $rc -eq 1 ] && grep -q "응답 본문이 파일과 다르다" <<<"$out" && ok "ⓗ 응답 불일치 rc=1" || bad "ⓗ rc=$rc $out"
reset; apply STUB_PATCH_RC=1
[ $rc -eq 1 ] && grep -q "PATCH 실패" <<<"$out" && ok "ⓗ PATCH 실패 rc=1" || bad "ⓗ PATCH 실패 rc=$rc $out"

# ⓘ 출력·로그·인자 어디에도 토큰 값 0 (env 접두 GH_TOKEN= 줄은 가짜 gh 가 쓰는 검증용 기록)
grep -qF "$TOKEN" "$ALLOUT" && bad "ⓘ 출력에 토큰 노출" || ok "ⓘ 출력 전부 토큰 0"
grep -qF "$TOKEN" "$ARGV" && bad "ⓘ gh 인자에 토큰 노출" || ok "ⓘ gh 인자 토큰 0"

# ⓙ 인자 오류 → exit 2 (래퍼 · 본체)
for args in "comment-edit x $T/new.md" "comment-edit 123 /nonexistent" "comment-edit 123" "comment-edit" "comment-edit 123 $T/new.md extra"; do
  # shellcheck disable=SC2086
  bash "$WRAP" $args >/dev/null 2>&1; [ $? -eq 2 ] && ok "ⓙ 래퍼 usage exit 2: [$args]" || bad "ⓙ 래퍼 exit 2 여야 함: [$args]"
done
for args in "x $T/new.md" "123 /nonexistent" "123" "" "123 $T/new.md extra"; do
  # shellcheck disable=SC2086
  FT_TANK_TOK=$TOKEN bash "$BODY" $args >/dev/null 2>&1; [ $? -eq 2 ] && ok "ⓙ 본체 usage exit 2: [$args]" || bad "ⓙ 본체 exit 2 여야 함: [$args]"
done

echo
[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
