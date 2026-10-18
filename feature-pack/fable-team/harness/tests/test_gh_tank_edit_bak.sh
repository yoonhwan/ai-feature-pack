#!/usr/bin/env bash
# test_gh_tank_edit_bak.sh — ft-gh-tank-edit-bak.sh(본체) + ft-gh-as-tank.sh edit·pr-edit 위임 시험. 실제 GitHub 호출 0 — PATH 맨 앞 가짜 gh.
# 분리 전(원장 R236 base_sha) 래퍼와 edit --apply 출력이 «시각 칸 제외» 바이트 같은지도 비교한다(그 커밋이 없으면 SKIP).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
BIN="$ROOT/scripts/fable-team-bin"
WRAP="$BIN/ft-gh-as-tank.sh"
BODY="$BIN/ft-gh-tank-edit-bak.sh"
KIT="$ROOT/scripts/harness-install/fable-team/bin"
BASE_SHA="abf90e322108d6d1c1a780257deb0b7d9a4104f1"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"; LOG="$T/gh.log"; : > "$LOG"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
# 가짜 gh: 호출을 STUB_LOG 에 남긴다. api user = byz-tank · issue|pr view = STUB_VIEW(rc=STUB_VIEW_RC) · issue|pr edit = URL 1줄.
echo "GH_TOKEN=${GH_TOKEN:-} $*" >> "$STUB_LOG"
case "$1 $2" in
  "api user") echo byz-tank;;
  "issue view"|"pr view") [ "${STUB_VIEW_RC:-0}" = 0 ] || { echo "view boom"; exit 1; }; printf '%s' "${STUB_VIEW-}";;
  "issue edit"|"pr edit") echo "https://github.com/o/r/issues/5";;
esac
exit 0
EOF
chmod +x "$T/bin/gh"
export STUB_LOG="$LOG" PATH="$T/bin:$PATH"
TOKEN="tok_SECRET_VALUE_123"; BAK="$T/bak"
export FT_ISSUE_EDIT_BAK_DIR="$BAK"

ORIG_T=$'옛 제목 "따옴표"'
ORIG_B=$'옛 본문 "따옴표"\n`백틱` 둘째줄\n끝'
mkjson() { python3 -c 'import json,sys;print(json.dumps({"title":sys.argv[1],"body":sys.argv[2]}))' "$1" "$2"; }
export STUB_VIEW; STUB_VIEW="$(mkjson "$ORIG_T" "$ORIG_B")"
printf '%s' "새 본문" > "$T/new.md"

bash -n "$WRAP" && ok "bash -n 래퍼" || bad "bash -n 래퍼"
bash -n "$BODY" && ok "bash -n 본체" || bad "bash -n 본체"
[ -x "$BODY" ] && ok "본체 실행 비트" || bad "본체 실행 비트 없음"
n=$(($(wc -l < "$WRAP"))); [ "$n" -le 195 ] && ok "래퍼 ${n}줄 ≤ 195" || bad "래퍼 ${n}줄 > 195"
n=$(($(wc -l < "$BODY"))); [ "$n" -le 200 ] && ok "본체 ${n}줄 ≤ 200" || bad "본체 ${n}줄 > 200"
for f in ft-gh-as-tank.sh ft-gh-tank-edit-bak.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp0: $f" || bad "키트 사본 불일치: $f"; done

run() { out="$("$@" 2>&1)"; rc=$?; }
reset() { : > "$LOG"; rm -rf "$BAK"; }
bak_args() { echo "$1 5 $2"; }

# ⓐ 정상 → BAK_BODY= 1줄 · 두 파일 내용 = 원문 · gh view 1회에 Tank 토큰
for kind in issue pr; do
  pfx=""; [ "$kind" = pr ] && pfx=pr
  reset; run env FT_TANK_TOK=$TOKEN bash "$BODY" "$kind" 5 "$pfx"
  BF="${out#BAK_BODY=}"; TF="${BF%.body.md}.title.txt"
  [ $rc -eq 0 ] && [[ "$out" == BAK_BODY=$BAK/${pfx}5-*.body.md ]] && [ "$(wc -l <<<"$out")" -eq 1 ] && ok "ⓐ[$kind] rc=0 · 출력 BAK_BODY= 1줄" || bad "ⓐ[$kind] rc=$rc $out"
  [ "$(cat "$BF"; printf x)" = "${ORIG_B}x" ] && [ "$(cat "$TF"; printf x)" = "${ORIG_T}x" ] && ok "ⓐ[$kind] 본문·제목 파일 = 원문" || bad "ⓐ[$kind] 보관 내용 불일치"
  [ "$(grep -c -- "^GH_TOKEN=$TOKEN $kind view 5 -R SecondWindStudio/byz-agents --json title,body$" "$LOG")" = 1 ] && ok "ⓐ[$kind] gh view 1회 · Tank 토큰" || bad "ⓐ[$kind] gh 호출: $(cat "$LOG")"
done

# ⓑ view 실패 → exit 1 · «수정 시도 0»
reset; run env FT_TANK_TOK=$TOKEN STUB_VIEW_RC=1 bash "$BODY" issue 5 ""
[ $rc -eq 1 ] && grep -q "REJECT 수정 전 원문 조회 실패 — 수정 시도 0: view boom" <<<"$out" && ok "ⓑ view 실패 rc=1 · 수정 시도 0" || bad "ⓑ rc=$rc $out"

# ⓒ 빈 응답 → exit 1
reset; run env FT_TANK_TOK=$TOKEN STUB_VIEW= bash "$BODY" issue 5 ""
[ $rc -eq 1 ] && grep -q "REJECT 수정 전 원문 조회 응답이 비었다 — 수정 시도 0" <<<"$out" && ok "ⓒ 빈 응답 rc=1" || bad "ⓒ rc=$rc $out"

# ⓓ title 빈 JSON · JSON 아님 → exit 1 · 보관 실패 문구
for v in "$(mkjson "" "본문만")" "not-json"; do
  reset; run env FT_TANK_TOK=$TOKEN STUB_VIEW="$v" bash "$BODY" issue 5 ""
  [ $rc -eq 1 ] && grep -q "REJECT 수정 전 원문 보관 실패(응답 해석·쓰기) — 수정 시도 0" <<<"$out" && ok "ⓓ 해석 실패 rc=1 [${v:0:12}]" || bad "ⓓ [${v:0:12}] rc=$rc $out"
done

# ⓕ 보관 폴더 쓰기 불가 → exit 1 · gh view 0
reset; : > "$T/notadir"
run env FT_TANK_TOK=$TOKEN FT_ISSUE_EDIT_BAK_DIR="$T/notadir/sub" bash "$BODY" issue 5 ""
[ $rc -eq 1 ] && grep -q "보관 폴더 생성 실패" <<<"$out" && [ ! -s "$LOG" ] && ok "ⓕ 보관 불가 rc=1 · gh 호출 0" || bad "ⓕ rc=$rc $out"

# ⓖ usage·토큰 없음 → exit 2 · gh 호출 0
reset
for args in "" "issue 5" "tree 5 x" "issue x ''"; do
  # shellcheck disable=SC2086
  FT_TANK_TOK=$TOKEN bash "$BODY" $args >/dev/null 2>&1; [ $? -eq 2 ] && ok "ⓖ usage exit 2: [$args]" || bad "ⓖ exit 2 여야 함: [$args]"
done
run env -u FT_TANK_TOK bash "$BODY" issue 5 ""
[ $rc -eq 2 ] && [ ! -s "$LOG" ] && ok "ⓖ 토큰 없음 rc=2 · gh 호출 0" || bad "ⓖ rc=$rc $out"

# ⓗ 래퍼 edit·pr-edit --apply → 분리 전 래퍼와 출력 바이트 같음(시각 칸 제외) · view 실패 시 gh edit 0
norm() { sed -E "s/[0-9]{8}T[0-9]{6}Z/TS/g; s#$1#BIN#g"; }
OLD="$T/old"; mkdir "$OLD"
if git -C "$ROOT" show "$BASE_SHA:scripts/fable-team-bin/ft-gh-as-tank.sh" > "$OLD/ft-gh-as-tank.sh" 2>/dev/null; then
  for act in edit pr-edit; do
    reset; run env FT_ISSUE_BOT_TOKEN=$TOKEN bash "$WRAP" "$act" 5 --body-file "$T/new.md" --title "새 제목" --apply; new_out="$(norm "$BIN" <<<"$out")"; new_rc=$rc
    reset; run env FT_ISSUE_BOT_TOKEN=$TOKEN bash "$OLD/ft-gh-as-tank.sh" "$act" 5 --body-file "$T/new.md" --title "새 제목" --apply; old_out="$(norm "$OLD" <<<"$out")"; old_rc=$rc
    [ "$new_rc" = "$old_rc" ] && [ "$new_out" = "$old_out" ] && ok "ⓗ[$act] 분리 전후 출력 바이트 같음(rc=$new_rc)" || bad "ⓗ[$act] 분리 전후 불일치: new=[$new_out] old=[$old_out]"
  done
  for act in edit pr-edit; do
    for mode in "STUB_VIEW_RC=1" "STUB_VIEW="; do
      reset; run env FT_ISSUE_BOT_TOKEN=$TOKEN "$mode" bash "$WRAP" "$act" 5 --title "새 제목" --apply; new_out="$(norm "$BIN" <<<"$out")"; new_rc=$rc; new_edit=$(grep -c " edit 5 " "$LOG")
      reset; run env FT_ISSUE_BOT_TOKEN=$TOKEN "$mode" bash "$OLD/ft-gh-as-tank.sh" "$act" 5 --title "새 제목" --apply; old_out="$(norm "$OLD" <<<"$out")"; old_rc=$rc
      [ "$new_rc" = 1 ] && [ "$new_rc" = "$old_rc" ] && [ "$new_out" = "$old_out" ] && [ "$new_edit" = 0 ] && ok "ⓗ[$act $mode] 보관 실패 rc=1 · 문구 동일 · gh edit 0" || bad "ⓗ[$act $mode] rc new=$new_rc old=$old_rc edit=$new_edit new=[$new_out] old=[$old_out]"
    done
  done
else
  echo "SKIP ⓗ base_sha $BASE_SHA 객체 없음 — 분리 전 비교 생략"
fi
reset; run env FT_ISSUE_BOT_TOKEN=$TOKEN bash "$WRAP" edit 5 --title "새 제목" --apply
grep -q "^OK as=byz-tank edit 5 — https://github.com/o/r/issues/5 bak=$BAK/5-" <<<"$out" && grep -q "^되돌림: bash $BIN/ft-gh-as-tank.sh edit 5 --body-file $BAK/5-.*--title \"\$(cat $BAK/5-.*\.title\.txt)\" --apply\$" <<<"$out" && ok "ⓗ OK 줄 + 되돌림 줄 형식" || bad "ⓗ 출력 형식: $out"
grep -qF "$TOKEN" <<<"$out" && bad "ⓗ 출력에 토큰 노출" || ok "ⓗ 출력 토큰 0"

echo
[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
