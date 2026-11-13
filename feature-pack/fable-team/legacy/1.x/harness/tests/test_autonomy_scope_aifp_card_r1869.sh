#!/usr/bin/env bash
# test_autonomy_scope_aifp_card_r1869.sh — r1869: 팩 aifp 카드 폴더(design/aifp/indices/<상태>/) 사이 같은 카드 이동(R099) = CLASS docs
#   ① aifp 진행→완성 내용 1줄 바뀜 → CLASS docs · 반례 ②~⑥(폴더 밖·모드·이름·aifpx·teams→aifp) = FORBID(전부 R0xx · R100 아님)
#   변이 M1(aifp 뒤 / 빼서 넓힘 → ⑤) · M2(group(1) 같음 검사 빼기 → ⑥) · 사본에서만 고친다
#   격리: 임시 리포(origin bare + clone) · 실 리포·실 원격·네트워크 0 · GIT_* env 0(_merge_fixture 의 설정 2종만) · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN0="$(cd "$HERE/../bin" && pwd -P)"
TBL0="$HERE/../kit/fable-team/templates/scope-classes-pack.tsv"
. "$HERE/_merge_fixture.sh"
fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T/iso"; R="$W"
body() { for i in $(seq 1 40); do echo "카드 줄 $i"; done; }   # 40줄 중 1줄만 바꾼다 → R09x
for d in "design/aifp/indices/진행" "design/aifpx/indices/진행" "design/teams/harness/indices/진행"; do mkdir -p "$R/$d"; body > "$R/$d/a.md"; done
cm "$R" "r1869 base"; git -C "$R" push -q origin main; git -C "$R" fetch -q origin

pr() {  # pr <셸 한 줄(리포 안에서)> → PRSHA(origin/main 에서 1커밋)
  git -C "$R" checkout -q -B "pr$RANDOM$RANDOM" origin/main
  (cd "$R" && eval "$1") && cm "$R" "r1869 case"; PRSHA="$(sha "$R" HEAD)"; git -C "$R" checkout -q main; }
SEED="$T/seeds.tsv"; : > "$SEED"
seed() { pr "$2"; printf '%s\t%s\n' "$1" "$PRSHA" >> "$SEED"; }   # 커밋은 한 번만 — 본판·변이가 같은 sha 를 판정
mvc() { mkdir -p "$(dirname "$2")"; git mv "$1" "$2"; sed -i.bak 's/^카드 줄 7$/카드 줄 7 고침/' "$2"; rm -f "$2.bak"; }   # 이동 + 내용 1줄
seed c1 'mvc "design/aifp/indices/진행/a.md" "design/aifp/indices/완성/a.md"'
seed c2 'mvc "design/aifp/indices/진행/a.md" "design/aifp/notes/a.md"'
seed c3 'mvc "design/aifp/indices/진행/a.md" "design/aifp/indices/완성/a.md"; chmod 755 "design/aifp/indices/완성/a.md"'
seed c4 'mvc "design/aifp/indices/진행/a.md" "design/aifp/indices/완성/b.md"'
seed c5 'mvc "design/aifpx/indices/진행/a.md" "design/aifpx/indices/완성/a.md"'
seed c6 'mvc "design/teams/harness/indices/진행/a.md" "design/aifp/indices/완성/a.md"'

s() { awk -F'\t' -v k="$1" '$1==k{print $2}' "$SEED"; }
for k in c1 c2 c3 c4 c5 c6; do   # 전제: 각 입력이 R0xx 한 행(R100 아님 · R100 fallback 은 범위 밖)
  st="$(git -C "$R" diff --name-status -M origin/main "$(s $k)" | cut -f1)"
  [[ "$st" =~ ^R0[0-9][0-9]$ ]] && echo "PASS 전제 $k = $st" || { echo "FAIL 전제 $k = ${st:-빈칸}"; fail=$((fail+1)); }
done

cases() {  # cases <bin> <팩 표> — PASS/FAIL 줄만 낸다 · 틀린 수 = rc
  local B="$1" TB="$2" f=0 out rc
  run() { out="$(python3 "$B/autonomy_scope_classify.py" classify "$(s "$1")" --repo "$R" --scope S1 --table "$TB" 2>&1)"; rc=$?; }
  ok() { if [ "$rc" = "$2" ] && [[ "$out" =~ ^($3) ]]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:160}"; f=$((f+1)); fi; }
  run c1; ok "① aifp 진행→완성 R09x → CLASS docs" 0 "CLASS (docs|ff)$"
  run c2; ok "② aifp 진행→notes/ R09x → FORBID" 3 "FORBID"
  run c3; ok "③ aifp 진행→완성 + 100755 → FORBID" 3 "FORBID"
  run c4; ok "④ aifp 진행→완성 이름 a→b → FORBID" 3 "FORBID"
  run c5; ok "⑤ aifpx 진행→완성 R09x → FORBID" 3 "FORBID"
  run c6; ok "⑥ teams/harness → aifp R09x → FORBID" 3 "FORBID"
  return "$f"
}

cases "$BIN0" "$TBL0"; fail=$((fail+$?))
cmp -s "$BIN0/autonomy_scope_rules.py" "$HERE/../kit/fable-team/bin/autonomy_scope_rules.py"; r=$?
[ "$r" = 0 ] && echo "PASS 키트 사본 cmp0" || { echo "FAIL 키트 사본 다름"; fail=$((fail+1)); }

mut() {  # mut <이름> <sed 식> <기대 FAIL 머리> — 사본($T/mN)에서 고친다 · 기대 FAIL 줄이 «그 칸» 에서 나야 변이 통과
  local D="$T/$1"; mkdir -p "$D"; cp "$BIN0"/*.py "$D/"
  local F="$D/autonomy_scope_rules.py"; cp "$F" "$F.orig"; sed -i.bak -E "$2" "$F"
  if cmp -s "$F" "$F.orig"; then echo "FAIL 변이 $1 적용 실패"; fail=$((fail+1)); return; fi
  local o; o="$(cases "$D" "$TBL0")"
  if grep -q "^FAIL $3" <<<"$o"; then echo "PASS 변이 $1 → FAIL $3"; else echo "FAIL 변이 $1 가 «$3» 를 못 깸"; fail=$((fail+1)); fi
}
mut M1 's#\|design/aifp\)/indices#|design/aifp[^/]*)/indices#' "⑤"
mut M2 's/ma\.group\(1\) == mb\.group\(1\) and //' "⑥"

[ "$fail" = 0 ] && echo "ALL PASS r1869" || echo "FAIL $fail"
exit "$fail"
