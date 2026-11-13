#!/usr/bin/env bash
# test_autonomy_scope_reversible_r1866.sh — r1866: 되돌릴 수 있는 두 종류를 scope 분류기가 자율로 읽는다
#   ① 새 tests/test_*.sh 100755(A 000000→100755 · 분류 code) = CLASS code ② 팩 표 design/<x>/…/*.md = CLASS docs
#   반례 ③~⑧(helper·M 모드·심링크·design .py·크리티컬 destroy·launchd) + 변이 M1~M3(사본에서만 고침 · 기대 FAIL 칸)
#   격리: 임시 리포(origin bare + clone) · 실 리포·실 원격·네트워크 0 · GIT_* env 0(_merge_fixture 의 설정 2종만) · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN0="$(cd "$HERE/../bin" && pwd -P)"
TBL0="$HERE/../kit/fable-team/templates/scope-classes-pack.tsv"
. "$HERE/_merge_fixture.sh"
fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T/iso"; R="$W"
mkdir -p "$R/tests"; echo 'echo m' > "$R/tests/test_m.sh"; cm "$R" "r1866 base"; git -C "$R" push -q origin main; git -C "$R" fetch -q origin

pr() {  # pr <셸 한 줄(리포 안에서)> → PRSHA(origin/main 에서 1커밋)
  git -C "$R" checkout -q -B "pr$RANDOM$RANDOM" origin/main
  (cd "$R" && eval "$1") && cm "$R" "r1866 case"; PRSHA="$(sha "$R" HEAD)"; git -C "$R" checkout -q main; }
SEED="$T/seeds.tsv"; : > "$SEED"
seed() { pr "$2"; printf '%s\t%s\n' "$1" "$PRSHA" >> "$SEED"; }   # 커밋은 한 번만 — 본판·변이가 같은 sha 를 판정
seed c1 'mkdir -p harness/tests; printf "echo 1\n" > harness/tests/test_x.sh; chmod 755 harness/tests/test_x.sh'
seed c1p 'd=feature-pack/fable-team/legacy/1.x/harness/tests; mkdir -p $d; printf "echo 1\n" > $d/test_seat_close_ft2_pi_r1855.sh; chmod 755 $d/test_seat_close_ft2_pi_r1855.sh'
seed c2 'mkdir -p "design/aifp/indices/진행"; echo "# x" > "design/aifp/indices/진행/x.md"'
seed c3 'printf "echo h\n" > tests/helper.sh; chmod 755 tests/helper.sh'
seed c4 'chmod 755 tests/test_m.sh'
seed c5 'ln -s ../a.txt tests/test_x.sh'
seed c6 'mkdir -p design/aifp; echo "x = 1" > design/aifp/x.py'
seed c7 'printf "tmux kill-server\n" > tests/test_k.sh; chmod 755 tests/test_k.sh'
seed c8 'mkdir -p design/aifp/LaunchAgents; echo "<plist/>" > design/aifp/LaunchAgents/x.plist'

cases() {  # cases <bin> <팩 표> — PASS/FAIL 줄만 낸다 · 틀린 수 = rc
  local B="$1" TB="$2" f=0 out rc
  s() { awk -F'\t' -v k="$1" '$1==k{print $2}' "$SEED"; }
  run() { out="$(python3 "$B/autonomy_scope_classify.py" classify "$(s "$1")" --repo "$R" "${@:2}" 2>&1)"; rc=$?; }
  ok() { if [ "$rc" = "$2" ] && [[ "$out" == "$3"* ]]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:160}"; f=$((f+1)); fi; }
  run c1 --scope S1;               ok "① 새 harness/tests/test_x.sh 100755 → CLASS code" 0 "CLASS code"
  run c1p --scope S1 --table "$TB"; ok "①' 팩 표 · r1855 꼴 새 시험 sh 100755 → CLASS code" 0 "CLASS code"
  run c2 --scope S1 --table "$TB"; ok "② 팩 표 · 새 design/aifp/indices/진행/x.md → CLASS docs" 0 "CLASS docs"
  run c3 --scope S1;               ok "③ 새 tests/helper.sh 100755 → FORBID mode" 3 "FORBID kind=mode"
  run c4 --scope S1;               ok "④ tests/test_m.sh M 100644→100755 → FORBID mode" 3 "FORBID kind=mode"
  run c5 --scope S1;               ok "⑤ 새 tests/test_x.sh 120000(심링크) → FORBID mode" 3 "FORBID kind=mode"
  run c6 --scope S1 --table "$TB"; ok "⑥ 팩 표 · 새 design/aifp/x.py → FORBID repo-outside" 3 "FORBID kind=repo-outside"
  run c7 --critical;               ok "⑦ 새 시험 sh 안 tmux kill-server + --critical → CRITICAL destroy rc3" 3 "CRITICAL kind=destroy"
  run c8 --scope S1 --table "$TB"; ok "⑧a 팩 표 · design/aifp/LaunchAgents/x.plist → FORBID repo-outside" 3 "FORBID kind=repo-outside"
  run c8 --critical;               ok "⑧b 같은 plist + --critical → CRITICAL launchd" 3 "CRITICAL kind=launchd"
  return "$f"
}

cases "$BIN0" "$TBL0"; fail=$((fail+$?))
cmp -s "$BIN0/autonomy_scope_rules.py" "$HERE/../kit/fable-team/bin/autonomy_scope_rules.py"; r=$?
[ "$r" = 0 ] && echo "PASS 키트 사본 cmp0" || { echo "FAIL 키트 사본 다름"; fail=$((fail+1)); }

# 변이 — 사본($T/mN)에서 고친다 · 기대 FAIL 줄이 «그 칸» 에서 나야 변이 통과
mut() {  # mut <이름> <sed 식> <대상: rules|table> <기대 FAIL 머리>
  local D="$T/$1"; mkdir -p "$D"; cp "$BIN0"/*.py "$D/"; cp "$TBL0" "$D/pack.tsv"
  local F="$D/autonomy_scope_rules.py"; [ "$3" = table ] && F="$D/pack.tsv"
  cp "$F" "$F.orig"; sed -i.bak -E "$2" "$F"
  if cmp -s "$F" "$F.orig"; then echo "FAIL 변이 $1 적용 실패"; fail=$((fail+1)); return; fi
  local o; o="$(cases "$D" "$D/pack.tsv")"
  if grep -q "^FAIL $4" <<<"$o"; then echo "PASS 변이 $1 → FAIL $4"; else echo "FAIL 변이 $1 가 «$4» 를 못 깸"; fail=$((fail+1)); fi
}
mut M1 's/st == "A" and om == "000000" and //' rules "④"
mut M2 's#\(\^\|/\)tests/test_\[\^/\]\*\\\.sh\$#\\.sh$#' rules "③"
mut M3 '/pack-design-md/s/\\\.md\$/$/' table "⑥"

[ "$fail" = 0 ] && echo "ALL PASS r1866" || echo "FAIL $fail"
exit "$fail"
