#!/usr/bin/env bash
# test_da_hold_gate_landed.sh — r456: «이미 main 에 착지한 카드» 닫기 경로 ⓐ~ⓕ.
#   판정기 --closing 의 LANDED-CLOSE(착지 sha 조상 ∧ 판정문 행) · ft-index-move 거절 문구 = 판정기 첫 줄 · 일괄 도구 ft-index-close-landed.sh.
#   전부 mktemp 임시 리포(origin/main = 같은 리포 ref) · 가짜 mbox · 실 명부·실 큐·외부 호출 0 · GIT_* env 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_LAND_REF
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { { [ "$5" = "$2" ] && [[ "$4" == *"$3"* ]]; } && ok "$1" || bad "$1 → rc=$5 $4"; }

# ── 0. 문법 · 짝 cmp0 · ruff · 600/300 ──
for f in ft_da_hold_gate.py ft-index-move.sh ft-index-close-landed.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "짝 cmp0 $f" || bad "짝 불일치 $f"; done
for f in ft-index-move.sh ft-index-close-landed.sh; do bash -n "$KIT/$f" && ok "bash -n $f" || bad "bash -n $f"; done
ruff check "$KIT/ft_da_hold_gate.py" >/dev/null 2>&1 && ok "ruff ft_da_hold_gate.py" || bad "ruff"
grep -vE '^[[:space:]]*#' "$KIT/ft_da_hold_gate.py" "$KIT/ft-index-close-landed.sh" | grep -qE '\b(600|300)\b' && bad "600/300 값 발견" || ok "600/300 값 0"

# ── 픽스처: 임시 리포 · origin/main ref · 팀 alpha · 판정문 ──
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
R="$T/repo"; TD="$R/design/teams/alpha"; mkdir -p "$TD/indices/진행" "$TD/indices/대기" "$TD/indices/완성"
G() { git -C "$R" "$@"; }
G init -q -b main . && G config user.email t@t && G config user.name t
printf '| 팀 | 폴더 | 팀장 | 상태 |\n|---|---|---|---|\n| alpha | `design/teams/alpha/` | a | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$R/design/TEAMS.md"
echo base > "$R/f.txt"; G add -A; G commit -qm base; S1="$(G rev-parse HEAD)"
echo two >> "$R/f.txt"; G commit -qam two; S2="$(G rev-parse HEAD)"
G update-ref refs/remotes/origin/main "$S2"
G checkout -q -b side "$S1"; echo side >> "$R/f.txt"; G commit -qam side; SX="$(G rev-parse HEAD)"; G checkout -q main
G update-ref refs/pack-landing/x "$SX"   # r663: origin/main 과 다른 착지 ref(팩 카드 자리)
DAF="$TD/DA-CLOSE-batch.md"
{ echo '# 닫힘 판정문'; echo '## §1 c-unp'; echo "닫힘 — c-unp — main \`$S1\` / PR #0"
  echo '## §2 c-hold'; echo "닫힘 — c-hold — main \`$S2\` / PR #0"
  echo '## §3 c-gone'; echo "닫힘 — c-gone — main \`$S1\` / PR #0"
  echo '## §4 c-side'; echo "닫힘 — c-side — main \`$SX\` / PR #0"
  echo '## §5 c-other'; echo "닫힘 — c-other — main \`$S2\` / PR #0"; } > "$DAF"
# card <이름> <폴더> <상태 줄…> → CARD
card() { local n="$1" d="$2"; shift 2; CARD="$TD/indices/$d/$n.md"
  { echo "# 인덱스: $n"; echo '## 배경'; echo 'x'; echo '## 상태'; echo '- 정본 영향 없음: 시험 픽스처 카드 — 하네스 도구 시험만';echo '- 규칙: 없음 — 시험 픽스처 카드(규칙 무관)'; echo '- 설치: 없음'; printf '%s\n' "$@"; } > "$CARD"; }
UNP='- 2026-10-13 — r2 사전 DA r1 HOLD 2(옛 표기)'
gate() { python3 "$KIT/ft_da_hold_gate.py" "$CARD" --root "$R" --seats-dir "$T/none" --comm "$T/none" "$@" 2>&1; }

# ⓐ UNPARSED + 착지 줄 + 판정문 행 → LANDED-CLOSE rc0
card c-unp 진행 "$UNP" "- 착지: $S1"; o="$(gate --closing --da "$DAF#§1")"; rc=$?
chk "ⓐ UNPARSED + 착지(조상) + 판정문 행 → LANDED-CLOSE rc0" 0 "LANDED-CLOSE sha=$S1 da=$DAF#§1" "$o" $rc; echo "  ⓐ 원문: ${o%%$'\n'*}"
[[ "${o%%$'\n'*}" == LANDED-CLOSE* ]] && ok "ⓐ 첫 줄 = LANDED-CLOSE" || bad "ⓐ 첫 줄 ${o%%$'\n'*}"
o="$(gate --closing --da "$DAF#§1" --landed "$S1")"; chk "ⓐ' 카드 줄 + --landed 일치 → rc0" 0 "LANDED-CLOSE" "$o" $?
# ⓑ events=2 + 같은 조건(카드 줄 없이 --landed) → rc0
card c-hold 진행 '- DA⑥ r1 HOLD 4' '- DA⑥ r2 HOLD 1'
o="$(gate --closing)"; chk "ⓑ 전제: 착지 증거 없으면 HOLD events=2 rc3" 3 "HOLD events=2" "$o" $?
o="$(gate --closing --da "$DAF#§2" --landed "$S2")"; rc=$?; chk "ⓑ events=2 + --landed + 판정문 행 → LANDED-CLOSE rc0" 0 "LANDED-CLOSE sha=$S2" "$o" $rc; echo "  ⓑ 원문: ${o%%$'\n'*}"
# ⓒ 착지 줄만 · 판정문 행 없음 / sha 불일치 → 기존 첫 줄 rc3
card c-unp 진행 "$UNP" "- 착지: $S1"
o="$(gate --closing)"; rc=$?; chk "ⓒ 착지 줄만(--da 없음) → UNPARSED 그대로 rc3" 3 "UNPARSED" "$o" $rc; [[ "${o%%$'\n'*}" == UNPARSED* ]] && ok "ⓒ 첫 줄 UNPARSED 불변" || bad "ⓒ 첫 줄 ${o%%$'\n'*}"
o="$(gate --closing --da "$DAF#§2")"; rc=$?; chk "ⓒ 다른 카드 절(§2) → 행 없음 → UNPARSED rc3 + LANDED-INVALID no-da-row" 3 "LANDED-INVALID no-da-row" "$o" $rc; [[ "${o%%$'\n'*}" == UNPARSED* ]] && ok "ⓒ 행 없음 첫 줄 UNPARSED" || bad "ⓒ 행없음 첫 줄 ${o%%$'\n'*}"
card c-hold 진행 '- DA⑥ r1 HOLD 4' '- DA⑥ r2 HOLD 1' "- 착지: $S1"
o="$(gate --closing --da "$DAF#§2")"; rc=$?; chk "ⓒ sha 불일치(카드 S1 · 판정문 S2) → HOLD … budget_left=0 rc3" 3 "budget_left=0" "$o" $rc; [[ "${o%%$'\n'*}" == "HOLD events=2"* ]] && ok "ⓒ 불일치 첫 줄 HOLD" || bad "ⓒ 불일치 첫 줄 ${o%%$'\n'*}"
o="$(gate --closing --da "$DAF#§2" --landed "$S2")"; chk "ⓒ 카드 줄 ≠ --landed → rc3 LANDED-INVALID mismatch" 3 "LANDED-INVALID mismatch" "$o" $?
# ⓓ sha 가 origin/main 조상 아님 → rc3 + LANDED-INVALID not-ancestor
card c-side 진행 "$UNP" "- 착지: $SX"; o="$(gate --closing --da "$DAF#§4")"; rc=$?
chk "ⓓ 조상 아닌 sha → rc3 + LANDED-INVALID not-ancestor" 3 "LANDED-INVALID not-ancestor $SX" "$o" $rc; echo "  ⓓ 원문: $(printf '%s' "$o" | tr '\n' ' ')"
# ── r663: 착지 기준 ref = env FT_LAND_REF(기본 origin/main) ──
# ⓖⓐ 다른 ref(refs/pack-landing/x)에만 있는 sha + FT_LAND_REF=<그 ref> → LANDED-CLOSE rc0
card c-side 진행 "$UNP" "- 착지: $SX"; o="$(FT_LAND_REF=refs/pack-landing/x gate --closing --da "$DAF#§4")"; rc=$?
chk "ⓖⓐ FT_LAND_REF=refs/pack-landing/x → LANDED-CLOSE rc0" 0 "LANDED-CLOSE sha=$SX da=$DAF#§4" "$o" $rc; echo "  ⓖⓐ 원문: ${o%%$'\n'*}"
# ⓖⓑ FT_LAND_REF 없으면 기본값 불변 = origin/main 조상 검사(기존 ⓓ 그대로)
card c-side 진행 "$UNP" "- 착지: $SX"; o="$(gate --closing --da "$DAF#§4")"; rc=$?
chk "ⓖⓑ FT_LAND_REF 미설정 → 기본 origin/main · not-ancestor rc3(기본값 불변)" 3 "LANDED-INVALID not-ancestor $SX" "$o" $rc
# ⓖⓒ 없는 ref → not-ancestor(조용한 통과 0)
card c-side 진행 "$UNP" "- 착지: $SX"; o="$(FT_LAND_REF=refs/pack-landing/nope gate --closing --da "$DAF#§4")"; rc=$?
chk "ⓖⓒ FT_LAND_REF=없는 ref → not-ancestor rc3(통과 0)" 3 "LANDED-INVALID not-ancestor $SX" "$o" $rc
# ⓔ --entry 는 착지 줄과 무관(입장 우회 0)
card c-hold 진행 '- DA⑥ r1 HOLD 4' '- DA⑥ r2 HOLD 1' '- DA⑥ r3 발주'; e0="$(gate --entry ⑥ r3)"; r0=$?
card c-hold 진행 '- DA⑥ r1 HOLD 4' '- DA⑥ r2 HOLD 1' '- DA⑥ r3 발주' "- 착지: $S2"; e1="$(gate --entry ⑥ r3 --da "$DAF#§2" --landed "$S2")"; r1=$?
{ [ "$r0" = 3 ] && [ "$r1" = 3 ] && [ "$e0" = "$e1" ]; } && ok "ⓔ --entry: 착지 증거 있어도 판정 동일 rc3 («${e1}»)" || bad "ⓔ entry r0=$r0 r1=$r1 «${e0}» vs «${e1}»"
[[ "$e1" != *LANDED* ]] && ok "ⓔ --entry 출력에 LANDED 0" || bad "ⓔ LANDED 섞임 $e1"

# ── ⓕ ft-index-move 거절 문구 + 일괄 도구 ──
TB="$T/bin"; mkdir -p "$TB"; cp "$KIT"/ft-index-move.sh "$KIT"/ft-index-move-canon.sh "$KIT"/ft-index-move-install.sh "$KIT"/ft_da_hold_gate.py "$KIT"/ft_git_capped.py "$KIT"/ft-team-lib.sh "$KIT"/ft-index-close-landed.sh "$TB/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TB/ft-index-lint.sh"; printf '#!/usr/bin/env bash\necho "$*" >> "$MBOX_LOG"\nexit 0\n' > "$T/fake-mbox.sh"; chmod 755 "$T/fake-mbox.sh"
mkdir -p "$T/state" "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
export FT_MBOX="$T/fake-mbox.sh" MBOX_LOG="$T/mbox.log" FT_INDEX_STATE_DIR="$T/state" FT_SEATS_JSON="$T/none.json" FT_THREAD_POST="$T/none.py" FT_ROOT="$R"
run() { ( cd "$R" && PATH="$T/stub:$PATH" bash "$@" 2>&1 ); }
G add -A; G commit -qm cards
card c-unp 진행 "$UNP"; o="$(run "$TB/ft-index-move.sh" "$CARD" 완성 --da "$DAF#§1" --seat s)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"REJECT DA 보류 가드: UNPARSED"* ]] && [[ "$o" == *"옛 표기"* ]] && [[ "$o" != *"보류 2회"* ]]; } && ok "ⓕ index-move: UNPARSED 거절 = 판정기 첫 줄 + 옛 표기 안내(«보류 2회» 0)" || bad "ⓕ UNPARSED 문구 rc=$rc $o"
echo "  ⓕ 원문(UNPARSED): $(printf '%s' "$o" | grep -m1 '^REJECT' | cut -c1-240)"
card c-hold 진행 '- DA⑥ r1 HOLD 4' '- DA⑥ r2 HOLD 1'; o="$(run "$TB/ft-index-move.sh" "$CARD" 완성 --da "$DAF#§2" --seat s)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"REJECT DA 보류 가드: HOLD events=2"*"재설계 해제"* ]]; } && ok "ⓕ index-move: HOLD 거절 = «HOLD events=2 …» + 재설계 해제 안내" || bad "ⓕ HOLD 문구 rc=$rc $o"
o="$(run "$TB/ft-index-move.sh" "$CARD" 완성 --da "$DAF#§2" --seat s --landed "$S2")"; rc=$?
{ [[ "$o" != *"DA 보류 가드"* ]]; } && ok "ⓕ index-move: --landed + 판정문 행 → 보류 가드 통과(rc=$rc · ${o%%$'\n'*})" || bad "ⓕ index-move landed $o"
[ -f "$TD/indices/완성/c-hold.md" ] && [ "$(grep -c "^- 착지: $S2" "$TD/indices/완성/c-hold.md")" = 1 ] && ok "ⓕ index-move 착지 → 완성/ + 착지 줄 1개" || bad "ⓕ index-move 완성 이동·착지 줄 $(ls "$TD/indices/완성")"
G add -A; G commit -qm moved
# 일괄: c-unp(진행 UNPARSED) · c-hold2 → §2 는 이미 완성 · c-gone(카드 없음) · c-side(조상 아님) · c-other(대기 events=2)
card c-unp 진행 "$UNP"; card c-side 진행 "$UNP"; card c-other 대기 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1'; G add -A; G commit -qm batch
before="$(cd "$R" && git status --porcelain | wc -l | tr -d ' ')"
o="$(run "$TB/ft-index-close-landed.sh" "$DAF" --team alpha --dry-run)"; rc=$?; echo "$o" | sed 's/^/  dry: /'
after="$(cd "$R" && git status --porcelain | wc -l | tr -d ' ')"
{ [ "$rc" = 0 ] && [ "$before" = "$after" ] && [[ "$o" == *"| §1 | c-unp | 진행 | ok | 무 | LANDED-CLOSE sha=$S1"* ]] && [[ "$o" == *"| §2 | c-hold | 완성 |"*"SKIP 이미 완성"* ]] && [[ "$o" == *"| §3 | c-gone | 없음 |"*"SKIP 카드 없음"* ]] && [[ "$o" == *"| §4 | c-side | 진행 | no |"*"not-ancestor"* ]] && [[ "$o" == *"| §5 | c-other | 대기 | ok | 무 | LANDED-CLOSE"* ]]; } \
  && ok "ⓕ --dry-run: 행마다 카드·위치·조상·착지 줄·예상 표 · 쓰기 0" || bad "ⓕ dry-run rc=$rc before=$before after=$after"
o="$(run "$TB/ft-index-close-landed.sh" "$DAF" --team alpha)"; rc=$?; echo "$o" | sed 's/^/  run: /'
{ [ "$rc" = 1 ] && [[ "$o" == *"MOVED c-unp"* ]] && [[ "$o" == *"MOVED c-other"* ]] && [[ "$o" == *"SKIP c-hold 이미 완성"* ]] && [[ "$o" == *"SKIP c-gone 카드 없음"* ]] && [[ "$o" == *"REJECT c-side LANDED-INVALID not-ancestor"* ]] && [[ "$o" == *"TOTAL rows=5 MOVED=2 REJECT=1 SKIP=2"* ]]; } \
  && ok "ⓕ 실행: MOVED 2 · SKIP 2 · REJECT 1(조상 아님) · 집계 줄 · rc1" || bad "ⓕ 실행 rc=$rc"
for c in c-unp c-other; do f="$TD/indices/완성/$c.md"; { [ -f "$f" ] && [ "$(grep -c '^- 착지:' "$f")" = 1 ] && grep -q "^- 착지: [0-9a-f]\{40\} (DA 닫힘 DA-CLOSE-batch.md#§" "$f"; } && ok "ⓕ $c 완성/ + 착지 줄 1개(판정문#§ 출처)" || bad "ⓕ $c 착지 줄 $(grep '착지' "$f" 2>/dev/null)"; done
{ [ -f "$TD/indices/진행/c-side.md" ] && ! grep -q '^- 착지:' "$TD/indices/진행/c-side.md"; } && ok "ⓕ 조상 아닌 카드: 이동 0 · 쓰기 0" || bad "ⓕ c-side 변경됨"
o="$(run "$TB/ft-index-close-landed.sh" "$T/none.md")"; [ $? = 2 ] && ok "ⓕ 판정문 없음 → rc2" || bad "ⓕ usage $o"

echo "fail=$fail"; [ "$fail" = 0 ]
