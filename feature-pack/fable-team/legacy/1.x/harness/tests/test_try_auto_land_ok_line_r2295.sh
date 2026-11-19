#!/usr/bin/env bash
# test_try_auto_land_ok_line_r2295.sh — r2295 try-auto --land 가 STANDING-OK·SCOPE-OK 줄의 class=·kind=·learned= 낱말을 읽는다
#   (계약 A1~A4 · 반례 ①~⑤ · ⑦~⑨ · 변이 M1~M4 · 카드 r2295-try-auto-pass-output-class-line · 사전 DA#33 APPROVE-DESIGN)
#   격리: 임시 BYZ·팩 리포 · 임시 상태 폴더 · 가짜 tmux·분류기 큐(FT_SCOPE_CLASSIFY) · 대상 bin 사본 + 가짜 ft-merge-land(인자 기록)
#   실 상태·실 원격·실 gh·실 병합 0 · sleep 0 · R2295_BIN=<bin 폴더> 로 대상 바꿈(기준판 대조)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "${R2295_BIN:-$HERE/../bin}" && pwd -P)"
KIT="$(cd "$HERE/../kit/fable-team" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/fakebin" "$T/da" "$T/pdir"
T0=1800000000; OD=1794302162.301939; HM='byz-harness-master-claude#115'
mkrepo "$T/byz"; B="$W"; mkdir -p "$B/.fable-team"; printf '.fable-team/\n' >> "$B/.git/info/exclude"
for t in planner harness; do python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$HM" "$B/.fable-team/seats-$t.json"; done
SEATFILE="$T/seatname"; export SEATFILE; printf '%s' "$HM" > "$SEATFILE"
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat "$SEATFILE"; exit 0; }\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
mkrepo "$T/pack"; P="$W"; mkdir -p "$P/kit/fable-team"; echo x > "$P/kit/fable-team/.keep"; cm "$P" kit; git -C "$P" push -q origin main
PTOP="$(git -C "$P" rev-parse --show-toplevel)"
S="$T/state"; LOG="$S/autonomy.log"; LAND_LOG="$T/land.log"
export FT_ROOT="$B" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/pdir" FT_SEAT="$HM" TMUX_PANE=%9 FT_HARNESS_ROOT="$P" PATH="$T/fakebin:$PATH" LAND_LOG
. "$HERE/lib/fake_gh_base.sh"; fake_gh_base "$T/ghb"
cat > "$T/cls.py" <<'EOF'
import os, sys
if sys.argv[1:2] == ["check-revert"]: print("OK"); raise SystemExit(0)
q = os.environ["STUB_QUEUE"]; lines = [x for x in open(q, encoding="utf-8").read().splitlines() if x.strip()] if os.path.exists(q) else []
out = lines.pop(0) if lines else "CLASS code"
open(q, "w", encoding="utf-8").write("".join(x + "\n" for x in lines))
print(out); raise SystemExit(3 if out.split()[:1] in (["FORBID"], ["CRITICAL"]) else 0)
EOF
export FT_SCOPE_CLASSIFY="$T/cls.py" STUB_QUEUE="$T/cls.queue" FT_SCOPE_PACK_TABLE="$KIT/templates/scope-classes-pack.tsv"
q() { printf '%s\n' "$@" > "$STUB_QUEUE"; }
onfix() {  # 자율 ON · 범위 S1(code,docs) · D2 켜짐 — 픽스처가 log 에 직접
  rm -rf "$S"; mkdir -p "$S"; printf '%s\ton\tA17\n' "$T0" > "$LOG"
  printf '{"mode":"on","since":%s,"event":"A17","until":null,"level":"full"}\n' "$T0" > "$S/autonomy.json"
  printf 'approve-scope S1 A17 %s until=%s max=30 daily=15 classes=code,docs codemax=5 repos=byz,pack\n' "$T0" "$((T0 + 3600))" >> "$LOG"
  printf 'approve-standing D2 %s repos=byz,pack classes=code,docs oppa_decision=%s\n' "$T0" "$OD" >> "$LOG"
}
sum256() { shasum -a 256 "$1" | awk '{print $1}'; }
mkda() { DAO="$T/da/$1.out"; printf 'codex\n판정: %s\n\n근거\n\n판정: %s\n' "$2" "$2" > "$DAO"; printf 'head=%s model=gpt-6.1-sol effort=high rc=0 start=1 end=2\n' "$3" > "$DAO.meta"; }
mkv() {  # mkv <이름> <A> <원문> → VF
  VF="$B/design/harness/da/VERDICT-$1.md"; mkdir -p "$(dirname "$VF")"
  printf '# 판정 %s\n\n- 승인 sha: %s\n- DA 원문: %s\n- DA 원문 sha256: %s\n- 격리: 세트 %s · rc=0\n' "$1" "$2" "$3" "$(sum256 "$3")" "$2" > "$VF"
  git -C "$B" checkout -q main; cm "$B" "verdict $1" && git -C "$B" push -q origin main && git -C "$B" push -q origin main:refs/heads/docs/da-278062 && git -C "$B" fetch -q origin; }
. "$HERE/lib/card_ref_fixture.sh"
card() { CARD="$(fx_card_path "$B" "${2:-card-$1.md}")"; printf '# 카드\n\n## 상태\n- 세트: %s · 시험: bash tests/x.sh rc=0 · 이슈: 0\n' "$1" > "$CARD"; fx_card_pub "$B" "$CARD"; }
mkpr() { git -C "$P" checkout -q -B "prx$RANDOM" main; mkdir -p "$P/$(dirname "$1")"; { echo "x $RANDOM"; printf '%s\n' "${@:2}"; } >> "$P/$1"; cm "$P" "pr $1"; PRSHA="$(sha "$P" HEAD)"; }
mkbin() {  # mkbin <원본 bin> <폴더> — bin 사본 + templates + 가짜 ft-merge-land(인자 기록) · 가짜 equiv(EQ_A 있을 때만 · 없으면 원본)
  mkdir -p "$2/bin" "$2/kit/fable-team"; cp -R "$1/." "$2/bin/"; cp -R "$KIT/templates" "$2/kit/fable-team/templates"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$LAND_LOG"\necho "LANDED 대역"\n' > "$2/bin/ft-merge-land.sh"
  printf '#!/usr/bin/env bash\n[ -n "${EQ_A:-}" ] && { echo "$EQ_A EQUIV 대역"; exit 0; }\nexec "$BASH" "%s/ft-approval-equiv.sh" "$@"\n' "$1" > "$2/bin/ft-approval-equiv.sh"
}
tryit() { : > "$LAND_LOG"; out="$(FT_NOW="$T0" "$BASH" "$ABIN/ft-autonomy.sh" try-auto "$@" 2>&1)"; rc=$?; }
lands() { grep -c . "$LAND_LOG"; }
has() { grep -qE -- "$1" <<<"$out"; }
okline() { grep -m1 '^TRY-OK ' <<<"$out"; }
# ── 사례(대상 bin 폴더 = $ABIN)
c1() { onfix; mkpr "scripts/zz-r2295-1.sh" "echo a"; local a="$PRSHA"; card "$a"; mkda c1 APPROVE "$a"; mkv c1 "$a" "$DAO"   # ① D2 code kind=global-rule
  q "CLASS code kind=global-rule d2" "CRITICAL-OK"; tryit "$a" --pr 21 --repo pack --card "$CARD" --verdict "$VF" --land
  [ "$rc" = 0 ] && [[ "$(okline)" == "TRY-OK via=D2 STANDING-OK $a pr=21 "*" class=code kind=global-rule" ]] && has '^자동 착지 제외 kind=global-rule · h 길$' && [ "$(lands)" = 0 ]; }
c2() { onfix; mkpr "design/r2295-2.md" "doc"; local a="$PRSHA"; card "$a"; mkda c2 APPROVE "$a"; mkv c2 "$a" "$DAO"   # ② D2 docs → 착지 1회(desk h 인자)
  q "CLASS docs" "CRITICAL-OK"; tryit "$a" --pr 22 --repo pack --card "$CARD" --verdict "$VF" --land
  [ "$rc" = 0 ] && [[ "$(okline)" == "TRY-OK via=D2 STANDING-OK $a pr=22 "*" class=docs" ]] && [ "$(cat "$LAND_LOG")" = "22 --approve-sha $a --repo $PTOP" ] && has '^LANDED 대역$'; }
c3() { onfix; mkpr "design/r2295-3.md" "doc"; local a="$PRSHA" o; card "$a"; q "CLASS docs"   # ③ S docs · 새 대기 카드 0 → SCOPE-OK 1줄 · 착지 1회
  o="$(FT_NOW="$T0" "$BASH" "$ABIN/ft-autonomy.sh" scope-approve "$a" --pr 23 --card "$CARD" --repo pack 2>&1)" || return 1
  [ "$(grep -c . <<<"$o")" = 1 ] && [[ "$o" == "SCOPE-OK $a class=docs "* ]] || return 1
  onfix; q "CLASS docs"; tryit "$a" --pr 23 --repo pack --card "$CARD" --land
  [ "$rc" = 0 ] && [[ "$(okline)" == "TRY-OK via=S1 SCOPE-OK $a class=docs "* ]] && [ "$(cat "$LAND_LOG")" = "23 --approve-sha $a --repo $PTOP" ]; }
c7() { onfix; mkpr "design/r2295-7.md" "doc"; local a="$PRSHA"; card "$a"; q "CLASS docs kind=ddl learned"   # ⑦ S learned=ddl → 착지 0
  tryit "$a" --pr 27 --repo pack --card "$CARD" --land
  [ "$rc" = 0 ] && [[ "$(okline)" == "TRY-OK via=S1 SCOPE-OK $a class=docs "*" learned=ddl" ]] && has '^자동 착지 제외 kind=ddl · h 길$' && [ "$(lands)" = 0 ]; }
c8() { onfix; mkpr "design/r2295-8a.md" "doc"; local a="$PRSHA" b; card "$a"; q "CLASS docs"; tryit "$a" --pr 28 --repo pack --card "$CARD"   # ⑧ 이미 센 A 의 EQUIV → class=equiv · 착지 0
  [ "$rc" = 0 ] || return 1
  mkpr "design/r2295-8b.md" "doc"; b="$PRSHA"; card "$b"; q "CLASS docs"; EQ_A="$a" tryit "$b" --pr 29 --repo pack --card "$CARD" --land
  [ "$rc" = 0 ] && [[ "$(okline)" == "TRY-OK via=S1 SCOPE-OK $b class=equiv "*"equiv=$a"* ]] && has '^자동 착지 0 · class=equiv · h 길$' && [ "$(lands)" = 0 ]; }
c9() { onfix; mkpr "design/r2295-9.md" "doc"; local a="$PRSHA"; card "$a" "r9-class=code-kind=x.md"; mkda c9 APPROVE "$a"; mkv c9 "$a" "$DAO"   # ⑨ card= 이름 속 class=·kind= 무시
  q "CLASS docs" "CRITICAL-OK"; tryit "$a" --pr 30 --repo pack --card "$CARD" --verdict "$VF" --land
  [ "$rc" = 0 ] && grep -q ' card=r9-class=code-kind=x.md ' <<<"$(okline)" && [ "$(lands)" = 1 ]; }
c5() { onfix; mkpr "scripts/zz-r2295-5.sh" "echo e"; local a="$PRSHA" l1; card "$a"; mkda c5 APPROVE "$a"; mkv c5 "$a" "$DAO"   # ⑤ --land 없음 = 2줄 · 착지 0
  q "CLASS code kind=global-rule d2" "CRITICAL-OK"; tryit "$a" --pr 25 --repo pack --card "$CARD" --verdict "$VF"; l1="$(okline)"
  [ "$rc" = 0 ] && [ "$(grep -c . <<<"$out")" = 2 ] && [[ "$l1" == "TRY-OK via=D2 STANDING-OK $a pr=25 "* ]] && [ "$(sed -n 2p <<<"$out")" = "SHARE 범위 안 · 질문 없이 진행(상시 D2) · PR 25" ] && [ "$(lands)" = 0 ]; }
# ── ④·⑤ 바이트 = 대역 approve(r2293 시험 꼴 · 통과 출력을 그대로 주입) — try-auto 동작만 본다
stubbin() {  # <try 파일> <폴더>
  mkdir -p "$2"; cp "$1" "$2/ft-autonomy-try.sh"
  printf 'd2_on() { [ "${STUB_D2:-1}" = 0 ]; }\nscope_load() { G_S=S1; }\n' > "$2/ft-autonomy-standing-d2.sh"
  printf '#!/usr/bin/env bash\nHERE="$(cd -- "$(dirname -- "$0")" && pwd)"; ROOT="$FT_ROOT"; mode() { echo on; }\ncase "$1" in\n  try-auto) . "$HERE/ft-autonomy-try.sh"; cmd_try_auto "${@:2}" ;;\n  standing-approve|scope-approve) printf "%%b" "$STUB_OUT"; exit 0 ;;\nesac\n' > "$2/ft-autonomy.sh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$LAND_LOG"\necho "LANDED 대역"\n' > "$2/ft-merge-land.sh"
}
H=0123456789abcdef0123456789abcdef01234567; printf '# 판정\n\n- 승인 sha: %s\n' "$H" > "$T/verdict.md"
stubit() { : > "$LAND_LOG"; out="$(STUB_OUT="$1" "$BASH" "$T/st/ft-autonomy.sh" try-auto "$H" --pr 7 --repo byz --card c.md "${@:2}" 2>&1)"; rc=$?; }
c4() { stubit "SCOPE-OK $H used=1/30 today=1/15\n" --land   # ④ OK 줄 class·kind 칸 0 · CLASS 줄 0 → 판독 불가
  [ "$rc" = 0 ] && has '^자동 착지 0 · kind 판독 불가 · h 길$' && [ "$(lands)" = 0 ]; }
c5b() { local l="STANDING-OK $H pr=7 repo=byz da=$H card=c.md by=x class=code kind=global-rule"   # ⑤ --land 없음 = TRY-OK 2줄 바이트(기준판 꼴)
  STUB_D2=0 stubit "$l\n" --verdict "$T/verdict.md"
  [ "$rc" = 0 ] && [ "$out" = "$(printf 'TRY-OK via=D2 %s\nSHARE 범위 안 · 질문 없이 진행(상시 D2) · PR 7' "$l")" ] && [ "$(lands)" = 0 ]; }
ck() { local s=$SECONDS; if "$2"; then echo "PASS $1 ($((SECONDS - s))s)"; else echo "FAIL $1 :: rc=$rc out=${out:0:400} land=$(cat "$LAND_LOG" 2>/dev/null)"; fail=$((fail + 1)); fi; }
t0=$SECONDS
mkbin "$BIN" "$T/o"; ABIN="$T/o/bin"; stubbin "$BIN/ft-autonomy-try.sh" "$T/st"
for c in c1 c2 c3 c4 c5 c5b c7 c8 c9; do ck "$c" "$c"; done
kitcmp() { cmp -s "$BIN/ft-autonomy-try.sh" "$KIT/bin/ft-autonomy-try.sh" && cmp -s "$BIN/ft-autonomy-standing-d2.sh" "$KIT/bin/ft-autonomy-standing-d2.sh"; }
[ -n "${R2295_BIN:-}" ] || ck "bin·kit cmp0" kitcmp
[ -z "${R2295_BIN:-}" ] || { echo "기준판 대조 fail=$fail ($((SECONDS - t0))s)"; [ "$fail" = 0 ]; exit; }
mut() {  # mut <이름> <파일> <옛 글자> <새 글자> <사례…> — 사본에서만 · 사례 FAIL 이어야 · 원본 같은 사례 1회 더
  local m="$T/$1" c; mkdir -p "$m-src"; cp -R "$BIN/." "$m-src/"
  python3 - "$m-src/$2" "$3" "$4" <<'PY' || { echo "FAIL $1 :: 변이 글자 1곳 아님"; fail=$((fail + 1)); return; }
import sys
p, old, new = sys.argv[1:4]
text = open(p, encoding="utf-8").read()
assert text.count(old) == 1, old
open(p, "w", encoding="utf-8").write(text.replace(old, new))
PY
  mkbin "$m-src" "$m"
  for c in "${@:5}"; do
    ABIN="$m/bin"; if "$c"; then echo "FAIL $1 :: 변이가 $c 를 통과"; fail=$((fail + 1)); else echo "PASS $1 ($c FAIL)"; fi
    ABIN="$T/o/bin"; ck "$1-원본 $c" "$c"
  done
}
mut M1 ft-autonomy-standing-d2.sh '${D2_KIND:+ kind=$D2_KIND}' '' c1   # STANDING-OK kind 칸 지움
mut M2 ft-autonomy-try.sh "w=\"\$(grep -E '^(STANDING|SCOPE)-OK ' <<<\"\$t\" | tr ' ' '\\n' | grep -E '^(class|kind|learned)=')\"" 'w=""' c2 c3   # OK 줄 판독 지움
mut M3 ft-autonomy-try.sh 'kind=*|learned=*)' 'kind=global-rule*|kind=billing*|kind=deps*)' c7   # kind 막기 = 3종 대조
mut M4 ft-autonomy-try.sh "tr ' ' '\\n' | grep -E '^(class|kind|learned)='" "grep -oE '(class|kind|learned)=[a-z0-9,-]*'" c9   # 낱말 머리 대신 줄 안 출현
echo "r2295 try-auto --land OK 줄 fail=$fail ($((SECONDS - t0))s)"
[ "$fail" = 0 ]
