#!/usr/bin/env bash
# test_ft_tick_renamed_args.sh — r507: ft-tick renamed_watch 가 명부 폴더의 seats-*.json 을 배열+glob 으로 넘긴다(ls 파싱 0).
# ⓒ 공백 이름 포함 2개 → 인자 = 파일 2개 정확히 · 0개 → 인자 0개(glob 글자가 그대로 넘어가지 않음).
# 함수만 떼어 가짜 RENAMED(받은 argv 를 JSON 으로 적음)로 돌린다 — 외부 호출 0 · 쓰기는 mktemp 안. bash 와 /bin/bash(3.2) 둘 다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
TICK="$ROOT/harness/bin/ft-tick.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

awk '/^renamed_watch\(\) \{/,/^\}/' "$TICK" > "$TMP/fn.sh"
[ -s "$TMP/fn.sh" ] && ok "renamed_watch 함수 추출" || { bad "renamed_watch 함수 추출 0"; exit 1; }
grep -q '\$(ls ' "$TMP/fn.sh" && bad "renamed_watch 에 \$(ls …) 남음" || ok "renamed_watch ls 파싱 0"

cat > "$TMP/stub.py" <<'PY'
import json, os, sys
json.dump(sys.argv[1:], open(os.environ["STUB_OUT"], "w"))
PY

# run <셸> <명부 폴더> <이름> → 가짜 RENAMED 가 받은 argv = $TMP/args.<이름>
run() {
  STUB_OUT="$TMP/args.$3" "$1" -c '
    set -uo pipefail
    now() { date +%s; }
    DRY=0; STATE_DIR="$1/state"; MBOX="$1/mbox.sh"; SEATS="$2/seats.json"; RENAMED="$1/stub.py"
    . "$1/fn.sh"; renamed_watch' _ "$TMP" "$2" 2>"$TMP/err.$3"
}
# want <이름> <기대 명부 파일…> → argv = watch MBOX SEATS + 기대 파일들(순서 그대로)
want() {
  local name="$1" dir="$2"; shift 2
  python3 -I - "$TMP/args.$name" "$TMP/mbox.sh" "$dir/seats.json" "$@" <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
exp = ["watch", sys.argv[2], sys.argv[3], *sys.argv[4:]]
sys.exit(0 if got == exp else print(f"got={got}\nexp={exp}") or 1)
PY
}

two="$TMP/two"; none="$TMP/none"; mkdir -p "$two" "$none"
echo '{}' > "$two/seats.json"; echo '{}' > "$two/seats-a.json"; echo '{}' > "$two/seats-b c.json"
echo '{}' > "$none/seats.json"

for sh in bash /bin/bash; do
  [ -x "$(command -v "$sh")" ] || { echo "SKIP $sh 없음"; continue; }
  v="$("$sh" -c 'echo ${BASH_VERSINFO[0]}')"
  run "$sh" "$two" "two-$v"; rc=$?
  [ "$rc" = 0 ] && want "two-$v" "$two" "$two/seats-a.json" "$two/seats-b c.json" \
    && ok "ⓒ bash$v 명부 2개(공백 이름 1) → 인자 2개 정확히" || bad "ⓒ bash$v 2개 rc=$rc $(cat "$TMP/err.two-$v")"
  rm -rf "$TMP/state"
  run "$sh" "$none" "none-$v"; rc=$?
  [ "$rc" = 0 ] && want "none-$v" "$none" \
    && ok "ⓒ bash$v 명부 0개 → 인자 0개(glob 글자 안 넘어감 · set -u 통과)" || bad "ⓒ bash$v 0개 rc=$rc $(cat "$TMP/err.none-$v")"
  rm -rf "$TMP/state"
done

echo "---- fail=$fail"
[ "$fail" = 0 ]
