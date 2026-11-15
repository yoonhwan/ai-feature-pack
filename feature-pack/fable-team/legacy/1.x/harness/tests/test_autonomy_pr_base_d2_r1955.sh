#!/usr/bin/env bash
# test_autonomy_pr_base_d2_r1955.sh — r1955 상시 승인 D2(자율 범위 길·desk 길)가 PR base 한 값을 분류·critical·gate·merge-tree·결속까지 쓴다 (반례 ⑥⑨ · 변이 M7 대상)
#   격리: 임시 BYZ 리포(명부·판정문·PR · 로컬 bare origin) · 가짜 tmux·gh · 분류기 = 인자 기록 스텁 · 실 ft-merge-gate · FT_NOW 고정 · 실 상태·실 GitHub 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"; . "$HERE/lib/fake_gh_base.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/fakebin" "$T/da" "$T/pdir"; fake_gh_base "$T/ghb"
T0=1800000000; HM='byz-harness-master-claude#115'; DK='byz-planner-desk-claude#3'; S="$T/state"; LOG="$S/autonomy.log"
mkrepo "$T/byz"; B="$W"; mkdir -p "$B/.fable-team"; printf '.fable-team/\n' >> "$B/.git/info/exclude"
for t in planner harness; do python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$HM" "$B/.fable-team/seats-$t.json"; done
SEATFILE="$T/seatname"; export SEATFILE
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat "$SEATFILE"; exit 0; }\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
cat > "$T/cls.py" <<'EOF'
import os, sys
open(os.environ["CLS_ARGS"], "a").write(" ".join(sys.argv[1:]) + "\n")
print("CRITICAL-OK" if "--critical" in sys.argv else ("OK" if sys.argv[1] == "check-revert" else "CLASS docs"))
EOF
export FT_ROOT="$B" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/pdir" TMUX_PANE=%9 PATH="$T/fakebin:$PATH" FT_SCOPE_CLASSIFY="$T/cls.py" CLS_ARGS="$T/cls.args"
# ⑨ 리포: ops = main 갈래 + o.txt · main 은 ops 와 갈라져 앞으로(a.txt l1 바꿈) · PR head = ops 자손(main 미포함 · a.txt l1 을 다르게 = main 과만 충돌)
git -C "$B" checkout -q -b ops; echo o > "$B/o.txt"; cm "$B" ops; git -C "$B" push -q origin ops:ops/main-base
git -C "$B" checkout -q main; sed -i '' 's/^l1$/main-l1/' "$B/a.txt"; cm "$B" m; git -C "$B" push -q origin main
git -C "$B" checkout -q -b pr ops; mkdir -p "$B/design"; echo d > "$B/design/d.md"; sed -i '' 's/^l1$/pr-l1/' "$B/a.txt"; cm "$B" pr; H="$(sha "$B" HEAD)"
DAO="$T/da/ok.out"; printf 'codex\n판정: APPROVE\n' > "$DAO"; printf 'head=%s model=gpt-6.1-sol effort=high rc=0 start=1 end=2\n' "$H" > "$DAO.meta"
VF="$B/design/harness/da/VERDICT-r1955.md"; git -C "$B" checkout -q main; mkdir -p "$(dirname "$VF")"
printf -- '- 승인 sha: %s\n- DA 원문: %s\n- DA 원문 sha256: %s\n- 격리: 세트 %s · rc=0\n' "$H" "$DAO" "$(shasum -a 256 "$DAO" | awk '{print $1}')" "$H" > "$VF"
cm "$B" verdict; git -C "$B" push -q origin main main:refs/heads/docs/da-278062; git -C "$B" fetch -q origin
onfix() { rm -rf "$S"; mkdir -p "$S"; : > "$CLS_ARGS"; printf '%s\ton\tA17\n' "$T0" > "$LOG"
  printf '{"mode":"on","since":%s,"event":"A17","until":null,"level":"full"}\n' "$T0" > "$S/autonomy.json"
  printf 'approve-scope S1 A17 %s until=%s max=30 daily=15 classes=docs level=full\n' "$T0" "$((T0 + 3600))" >> "$LOG"; }
d2() { printf '%s' "$1" > "$SEATFILE"; export FT_SEAT="$1"; out="$(FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" standing-approve D2 "$H" --pr 5 --repo byz --verdict "$VF" --card "$T/card.md" 2>&1)"; rc=$?; }
tg() { grep -E -- "$1" "$CLS_ARGS" | grep -oE -- '--target [^ ]+' | sort -u | tr '\n' ' '; }

# ⑥⑨ PR base = ops/main-base · 자율 범위 길(팀 master) → 분류·critical = ops · gate ALLOW(ops) · 결속 ops
onfix; FAKE_GH_BASE=ops/main-base d2 "$HM"
[ "$rc" = 0 ] && has "^STANDING-OK $H pr=5 repo=byz .*via=S1"; ck "⑨ 자율 길 ops 후보(main 미포함) → d2_gate ALLOW(ops 기준) · STANDING-OK" $?
[ "$(tg 'classify .* --scope S0')" = "--target ops/main-base " ] && [ "$(tg -- '--critical')" = "--target ops/main-base " ]; ck "⑥ 분류·critical = --target ops/main-base(같은 값)" $?
[ "$(cat "$S/autonomy-merge-target/$H")" = ops/main-base ] && [ -f "$S/autonomy-merge-approved/$H" ]; ck "마 D2 결속 파일 = ops/main-base · 승인 파일" $?
FAKE_GH_BASE=main d2 "$HM"; [ "$rc" = 2 ] && has '판정 불가 — 승인 base ops/main-base ≠ 지금 PR base main' && ! has NOOP; ck "마② D2 NOOP 앞 대조: retarget → 판정 불가" $?
# ⑥ PR base = main → 분류·critical = main · gate = main 미포함 거절 · 쓰기 0
onfix; FAKE_GH_BASE=main d2 "$HM"
[ "$rc" = 2 ] && has 'merge-gate ALLOW 아님' && [ "$(tg -- '--critical')" = "--target main " ] && [ ! -e "$S/autonomy-merge-approved/$H" ]; ck "⑥ main PR → critical main 기준 · gate 거절 · 쓰기 0" $?
# ⑨ desk 길: merge-tree 대상 = origin/ops/main-base(main 과는 a.txt 충돌 · ops 와는 0)
onfix; FAKE_GH_BASE=ops/main-base d2 "$DK"
[ "$rc" = 0 ] && has "^STANDING-OK $H .*by=$DK"; ck "⑨ desk 길 merge-tree = origin/ops/main-base(main 충돌 무관) → STANDING-OK" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
