#!/usr/bin/env bash
# test_successor_open_symlink_r2090.sh — r2090: 심링크로 불러도 ft-successor-open 이 자기 실제 폴더에서 짝 파일을 찾는다.
#   ① 절대 심링크 = 직접 호출과 같은 «REJECT 이름 lint —» rc1 | ② 정책표에 역할 없음 rc2 = 직접 호출과 같음
#   ③ 상대 · 2단 심링크 = ① 과 같음 | ④ lint 도구 없음 = «REJECT 이름 lint 도구 없음: <경로>» rc1(이름 멀쩡해도)
#   ⑤ FT_NAME_LINT 를 준 심링크 호출 = 준 lint 를 씀 · FT_RUNTIME_POLICY 를 준 직접 호출 = 기준판과 같음
#   임시 폴더의 도구 사본(FT_SO_KIT 로 바꿀 수 있음 = 변이 시험) + 가짜 lint · 정책표만 — 열기 전 단계에서 끝남 · 세션 열기 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1; unset FT_NAME_LINT FT_RUNTIME_POLICY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${FT_SO_KIT:-$HERE/../kit/fable-team/bin}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; TMP="$(cd "$TMP" && pwd)"
REAL="$TMP/real"; NOLINT="$TMP/nolint"; LNK="$TMP/links"; WT="$TMP/wt"; BODY="$TMP/body.txt"
mkdir -p "$REAL" "$NOLINT" "$LNK" "$WT"; echo body > "$BODY"
printf '#!/usr/bin/env bash\ncase "$1" in *-sol#*) echo "FAKE 모델 꼬리 sol: $1"; exit 1;; esac; exit 0\n' > "$REAL/ft-name-lint.sh"
printf 'master\tclaude\tclaude-sonnet-5-5\n' > "$REAL/runtime-policy.tsv"
for d in "$REAL" "$NOLINT"; do cp "$KIT/ft-successor-open.sh" "$d/"; done
cp "$REAL/runtime-policy.tsv" "$NOLINT/"
ln -s "$REAL/ft-successor-open.sh" "$LNK/abs"
ln -s ../real/ft-successor-open.sh "$LNK/rel"
ln -s "$LNK/abs" "$LNK/two"
ln -s "$NOLINT/ft-successor-open.sh" "$LNK/nolint"

BAD=(old "$WT" --name byz-x-arch-sol#1 --agent claude --model op --body-file "$BODY")
NOROLE=(old "$WT" --name byz-x-zzz-claude#1 --body-file "$BODY")
GOOD=(old "$WT" --name byz-x-arch-claude#1 --agent claude --model op --body-file "$BODY")
OUT=""; RC=0
call() { OUT="$(cd "$TMP" && bash "$@" 2>&1)"; RC=$?; }
same() {   # same <사례> <심링크> <직접 경로> <기대 rc> <기대 첫머리> -- 인자...
  local name="$1" lnk="$2" dir="$3" erc="$4" head="$5"; shift 6
  call "$dir" "$@"; local dout="$OUT" drc="$RC"
  call "$lnk" "$@"
  if [ "$OUT" = "$dout" ] && [ "$RC" = "$drc" ] && [ "$RC" = "$erc" ] && [ "${OUT#"$head"}" != "$OUT" ]; then ok "$name rc=$RC"
  else bad "$name rc=$RC/직접 $drc · 심링크 «${OUT}» · 직접 «${dout}»"; fi
}
LINE1="REJECT 이름 lint — FAKE 모델 꼬리 sol: byz-x-arch-sol#1 (세션 열기 0 · 명부 쓰기 0)"
# ① 절대 심링크 · 이름 불량
same "① 절대 심링크 = 직접" "$LNK/abs" "$REAL/ft-successor-open.sh" 1 "$LINE1" -- "${BAD[@]}"
# ② 정책표에 역할 없음
same "② 정책표 = 직접" "$LNK/abs" "$REAL/ft-successor-open.sh" 2 "REJECT 정책표에 역할 없음: byz-x-zzz-claude —" -- "${NOROLE[@]}"
# ③ 상대 · 2단
same "③a 상대 심링크" "$LNK/rel" "$REAL/ft-successor-open.sh" 1 "$LINE1" -- "${BAD[@]}"
same "③b 2단 심링크" "$LNK/two" "$REAL/ft-successor-open.sh" 1 "$LINE1" -- "${BAD[@]}"
same "③c 2단 정책표" "$LNK/two" "$REAL/ft-successor-open.sh" 2 "REJECT 정책표에 역할 없음" -- "${NOROLE[@]}"
# ④ lint 도구 없음 — 이름 멀쩡해도 · 불량이어도 같은 줄
LINE4="REJECT 이름 lint 도구 없음: $NOLINT/ft-name-lint.sh (세션 열기 0 · 명부 쓰기 0)"
for a in GOOD BAD; do
  eval 'args=("${'"$a"'[@]}")'
  call "$NOLINT/ft-successor-open.sh" "${args[@]}"
  [ "$RC" = 1 ] && [ "$OUT" = "$LINE4" ] && ok "④ $a 직접 lint 없음" || bad "④ $a 직접 rc=$RC «${OUT}»"
  call "$LNK/nolint" "${args[@]}"
  [ "$RC" = 1 ] && [ "$OUT" = "$LINE4" ] && ok "④ $a 심링크 lint 없음" || bad "④ $a 심링크 rc=$RC «${OUT}»"
done
# ⑤ 손잡이 우선 — FT_NAME_LINT 를 준 심링크 호출은 준 lint 를 쓴다
OUT="$(cd "$TMP" && FT_NAME_LINT="$REAL/ft-name-lint.sh" bash "$LNK/nolint" "${BAD[@]}" 2>&1)"; RC=$?
[ "$RC" = 1 ] && [ "$OUT" = "$LINE1" ] && ok "⑤ FT_NAME_LINT 우선" || bad "⑤ FT_NAME_LINT rc=$RC «${OUT}»"
OUT="$(cd "$TMP" && FT_RUNTIME_POLICY="$TMP/none.tsv" bash "$REAL/ft-successor-open.sh" "${NOROLE[@]}" 2>&1)"; RC=$?
[ "$RC" = 2 ] && [ "${OUT#REJECT 런타임 정책표 없음: $TMP/none.tsv}" != "$OUT" ] && ok "⑤ FT_RUNTIME_POLICY 우선" || bad "⑤ FT_RUNTIME_POLICY rc=$RC «${OUT}»"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
