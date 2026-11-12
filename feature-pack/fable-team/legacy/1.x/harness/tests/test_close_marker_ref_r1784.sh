#!/usr/bin/env bash
# test_close_marker_ref_r1784.sh — r1784: DA 닫힘 표식 «리포·ref» 선택자(ft_close_marker 한 함수) 반례 ①~⑪.
#   실사건: r1763 판정문 «닫힘 — <카드> — BYZ origin/ops/main-base `<sha>`» 를 다섯 판정기가 못 읽어 완성 이동 0(no-da-row).
#   임시 리포 2개(카드 리포: origin/main · origin/ops/main-base — 착지 커밋은 ops 에만 / 팩 리포: origin/ops/x) + 임시 판정문·카드만.
#   실 판정문·실 카드·실 리포 ref 손 0 · sleep 0 · 외부 호출 0. SRC=<bin 폴더> 로 기준판(Red)·변이를 같은 시험으로 돌린다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${SRC:-$(cd "$HERE/../bin" && pwd -P)}"; KIT="$HERE/../kit/fable-team/bin"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { [[ "$2" == *"$3"* ]] && ok "$1" || bad "$1 :: ${2:0:400}"; }
T="$(mktemp -d)"; [ -n "${KEEP:-}" ] && echo "T=$T" || trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$T/home"; mkdir -p "$HOME"
unset GIT_DIR GIT_WORK_TREE FT_HARNESS_ROOT FT_LAND_REF FT_LANDED_MARKER FT_INSTALL_CHECK FT_TRACK
BIN="$T/bin"; mkdir -p "$BIN"
cp -p "$SRC"/ft-team-lib.sh "$SRC"/ft-harness-root.sh "$SRC"/ft-index-move.sh "$SRC"/ft-index-move-install.sh \
      "$SRC"/ft-index-move-canon.sh "$SRC"/ft-index-close-landed.sh "$SRC"/ft_da_hold_gate.py "$SRC"/ft_git_capped.py "$BIN/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-index-lint.sh"
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

# ── 0. bin=kit 짝 · 문법 (SRC 가 기본 bin 일 때만 짝 대조)
if [ -z "${SRC_ALT:-}" ] && [ "$SRC" = "$(cd "$HERE/../bin" && pwd -P)" ]; then
  for f in ft-team-lib.sh ft_da_hold_gate.py ft-index-move.sh ft-index-move-canon.sh ft-index-close-landed.sh; do cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 cmp0 $f" || bad "짝 불일치 $f"; done
fi
for f in ft-team-lib.sh ft-index-move.sh ft-index-move-canon.sh ft-index-close-landed.sh; do /bin/bash -n "$BIN/$f" && ok "bash3.2 -n $f" || bad "bash -n $f"; done

# ── 카드 리포(BYZ 꼴): main = C0→C1 · ops/main-base = C0→SOPS(코드 파일 · 문서 카드 인정 길 밖)
CR="$T/byz"; IDX="$CR/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성}
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$CR/design/TEAMS.md"
g "$CR" init -q -b main; echo a > "$CR/f.txt"; g "$CR" add -A; g "$CR" commit -qm c0
echo b >> "$CR/f.txt"; g "$CR" commit -qam c1; C1="$(g "$CR" rev-parse HEAD)"; g "$CR" update-ref refs/remotes/origin/main "$C1"
g "$CR" checkout -q -b ops/main-base HEAD~1; echo ops > "$CR/g.txt"; g "$CR" add -A; g "$CR" commit -qm ops; SOPS="$(g "$CR" rev-parse HEAD)"
g "$CR" update-ref refs/remotes/origin/ops/main-base "$SOPS"; g "$CR" checkout -q main
# ── 팩 리포: origin/ops/x 에만 PX
PR="$T/pack"; KD="$PR/feature-pack/fable-team/harness"; mkdir -p "$KD/kit/fable-team/bin"; echo p > "$KD/kit/fable-team/bin/x.sh"
g "$PR" init -q -b main; g "$PR" add -A; g "$PR" commit -qm p0; g "$PR" update-ref refs/remotes/origin/main "$(g "$PR" rev-parse HEAD)"
g "$PR" checkout -q -b x; echo q >> "$KD/kit/fable-team/bin/x.sh"; g "$PR" commit -qam px; PX="$(g "$PR" rev-parse HEAD)"; g "$PR" update-ref refs/remotes/origin/ops/x "$PX"; g "$PR" checkout -q main

DAF="$CR/design/harness/DA-close-r1784.md"
{ echo '# 닫힘 판정문(임시)'
  echo '## §1 r1'; echo "닫힘 — r1 — BYZ origin/ops/main-base \`$SOPS\`"
  echo '## §2 r2'; echo "닫힘 — r2 — BYZ origin/ops/main-base \`$SOPS\`"
  echo '## §3 r3'; echo "닫힘 — r3 — BYZ origin/ops/main-base \`$SOPS\`"
  echo '## §4 r4'; echo "닫힘 — r4 — 팩 origin/ops/x \`$PX\`"
  echo '## §5 r5'; echo "닫힘 — r5 — main \`$C1\`"; echo "닫힘 — r5 — BYZ origin/ops/main-base \`$SOPS\`"
  echo '## §6 r6 — 닫힘 (CLOSE)'; echo '- 본문만 있고 표식 줄 없음'
  echo '## §7 r7'; echo '닫힘 — r7 — 버림 (쓸모 줄어 정리)'; echo "닫힘 — r7 — BYZ origin/ops/main-base \`$SOPS\`"
  echo '## §9 r9'; echo "닫힘 — r9 — main \`$SOPS\`"; echo "닫힘 — r9 — BYZ origin/ops/main-base \`$SOPS\`"
  echo '## §10 r10'; echo "닫힘 — r10 — BYZ origin/main \`$C1\`"
  echo '## §11 r11'; echo "닫힘 — r11 — main \`$C1\`"
  echo '## §12 r12'; echo "닫힘 — r12 — BYZ origin/main \`$C1\`"; echo "닫힘 — r12 — BYZ origin/ops/main-base \`$C1\`"
  echo '## §13 r13'; echo "닫힘 — r13 — main \`$C1\`"; echo "닫힘 — r13 — 팩 origin/ops/x \`$C1\`"; } > "$DAF"
card() { local f="$IDX/$2/$1.md"
  { echo "# 인덱스: $1"; echo "## 상태"; echo "- 정본 영향 없음: 하네스 도구만 바뀐 시험 카드 — 제품 정본 없음"
    echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"; echo "- 설치: 없음"; } > "$f"; echo "$f"; }
for n in r1 r2 r3 r4 r5 r6 r9 r10; do card "$n" 진행 >/dev/null; done; card r7 대기 >/dev/null
g "$CR" add -A; g "$CR" commit -qm cards
sec() { awk -v s="## §$1 " 'index($0,"## ")==1{f=(index($0,s)==1)} f' "$DAF"; }
cm() { local n="$1"; shift; sec "$n" | ( for a in "$@"; do export "$a"; done; bash -c '. "$1" >/dev/null 2>&1; ft_close_marker "$2"' x "$BIN/ft-team-lib.sh" "r$n" 2>&1 ); }
gate() { local n="$1" e="$2"; shift 2; ( [ -z "$e" ] || export "$e"; python3 "$BIN/ft_da_hold_gate.py" "$IDX/진행/r$n.md" --root "$CR" --seats-dir "$T/none" --comm "$T/none" --closing --da "$DAF#§$n" "$@" 2>&1 ); }
TAB=$'\t'
mkdir -p "$T/state" "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/fake-mbox.sh"; chmod 755 "$T/fake-mbox.sh"
mv_() { ( cd "$CR" && export FT_MBOX="$T/fake-mbox.sh" FT_INDEX_STATE_DIR="$T/state" FT_SEATS_JSON="$T/none.json" FT_THREAD_POST="$T/none.py" FT_ROOT="$CR" PATH="$T/stub:$PATH" && bash "$@" 2>&1 ); }

# ① BYZ origin/ops/main-base 표식 · env 없음 → 보류 가드 LANDED-CLOSE rc0
o="$(gate 1 "" --landed "$SOPS")"; rc=$?
{ [ "$rc" = 0 ] && [[ "${o%%$'\n'*}" == "LANDED-CLOSE sha=$SOPS"* ]]; } && ok "① BYZ ops 표식 · env 없음 → LANDED-CLOSE rc0" || bad "① rc=$rc ${o:0:300}"
o="$(cm 1)"; [ "$o" = "card${TAB}explicit${TAB}origin/ops/main-base${TAB}$SOPS" ] && ok "① ft_close_marker = card·explicit·origin/ops/main-base·sha" || bad "① cm «${o}»"
# ② 같은 꼴로 ft-index-move 완성 갈래 끝까지 → 이동 rc0
o="$(mv_ "$BIN/ft-index-move.sh" "$IDX/진행/r2.md" 완성 --da "$DAF#§2" --landed "$SOPS")"; rc=$?
{ [ "$rc" = 0 ] && [ -f "$IDX/완성/r2.md" ]; } && ok "② ft-index-move 완성 rc0(정본 검사 포함)" || bad "② rc=$rc $(printf '%s' "$o" | grep -m1 REJECT)"
# ③ ① + FT_LAND_REF=origin/main → ref-mismatch · 이동 0
o="$(gate 3 FT_LAND_REF=origin/main --landed "$SOPS")"; has "③ 보류 가드: env origin/main ≠ 표식 → LANDED-INVALID ref-mismatch" "$o" "LANDED-INVALID ref-mismatch origin/main ≠ origin/ops/main-base"
[[ "$o" != *LANDED-CLOSE* ]] && ok "③ LANDED-CLOSE 0" || bad "③ LANDED-CLOSE 나옴"
o="$(FT_LAND_REF=origin/main mv_ "$BIN/ft-index-move.sh" "$IDX/진행/r3.md" 완성 --da "$DAF#§3" --landed "$SOPS")"; rc=$?
{ [ "$rc" = 1 ] && [ -f "$IDX/진행/r3.md" ] && [[ "$o" == *ref-mismatch* ]]; } && ok "③ ft-index-move: ref-mismatch REJECT · 이동 0" || bad "③ move rc=$rc $(printf '%s' "$o" | grep -m1 REJECT)"
# ④ 팩 origin/ops/x 표식 · sha 팩에만 → pack 리포에서 LANDED-CLOSE
o="$(cm 4)"; [ "$o" = "pack${TAB}explicit${TAB}origin/ops/x${TAB}$PX" ] && ok "④ ft_close_marker = pack·explicit·origin/ops/x" || bad "④ cm «${o}»"
o="$(gate 4 FT_HARNESS_ROOT="$KD" --landed "$PX")"; rc=$?
{ [ "$rc" = 0 ] && [[ "${o%%$'\n'*}" == "LANDED-CLOSE sha=$PX"* ]]; } && ok "④ 팩 표식 → 팩 리포 LANDED-CLOSE rc0" || bad "④ rc=$rc ${o:0:300}"
# ⑤ main <sha1> + BYZ ops <sha2> (sha 다름) → REJECT «표식 여러 개»
o="$(cm 5)"; has "⑤ ft_close_marker: sha 다른 두 표식 → REJECT 표식 여러 개" "$o" "REJECT 표식 여러 개"
o="$(gate 5 "" --landed "$SOPS")"; { [[ "$o" == *"표식 여러 개"* ]] && [[ "$o" != *LANDED-CLOSE* ]]; } && ok "⑤ 보류 가드: 표식 여러 개 · LANDED-CLOSE 0" || bad "⑤ gate ${o:0:300}"
# ⑥ 절 헤더만(표식 줄 없음) → no-da-row (r959 그대로)
o="$(gate 6 FT_LAND_REF=origin/ops/main-base --landed "$SOPS")"; has "⑥ 절 헤더만 → LANDED-INVALID no-da-row" "$o" "LANDED-INVALID no-da-row"
o="$(cm 6)"; rc=$?; { [ "$rc" = 1 ] && [ -z "$o" ]; } && ok "⑥ ft_close_marker: 표식 없음 = rc1 빈 줄" || bad "⑥ cm rc=$rc «${o}»"
# ⑦ 아카이브 갈래: 새 꼴 표식이 있는 카드 → «착지한 카드» REJECT
o="$(mv_ "$BIN/ft-index-move.sh" "$IDX/대기/r7.md" 아카이브 --da "$DAF#§7" --seat s)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"착지한 카드"* ]] && [ -f "$IDX/대기/r7.md" ]; } && ok "⑦ 아카이브: BYZ 표식 카드 → 착지 카드 REJECT · 이동 0" || bad "⑦ rc=$rc ${o:0:300}"
# ⑨ 실 r1763 §1 꼴: main <sha> + BYZ ops <sha> 같은 sha → explicit 이 이긴다 · env 없음 = env 일치
want9="card${TAB}explicit${TAB}origin/ops/main-base${TAB}$SOPS"
o="$(cm 9)"; [ "$o" = "$want9" ] && ok "⑨ 혼합 짝 env 없음 → card·explicit·origin/ops/main-base" || bad "⑨ cm «${o}»"
o="$(cm 9 FT_LAND_REF=origin/ops/main-base)"; [ "$o" = "$want9" ] && ok "⑨ 혼합 짝 env 일치 → 같은 결과" || bad "⑨ cm env «${o}»"
o="$(gate 9 "" --landed "$SOPS")"; rc=$?; { [ "$rc" = 0 ] && [[ "${o%%$'\n'*}" == "LANDED-CLOSE sha=$SOPS"* ]]; } && ok "⑨ 보류 가드 env 없음 → LANDED-CLOSE" || bad "⑨ gate rc=$rc ${o:0:300}"
o="$(gate 9 FT_LAND_REF=origin/ops/main-base --landed "$SOPS")"; rc=$?; { [ "$rc" = 0 ] && [[ "${o%%$'\n'*}" == LANDED-CLOSE* ]]; } && ok "⑨ 보류 가드 env 일치 → LANDED-CLOSE" || bad "⑨ gate env rc=$rc ${o:0:300}"
# ⑩ BYZ origin/main + env ops = ref-mismatch · main + env ops = card·legacy·ops(지금 동작) · 각 기본값
o="$(cm 10 FT_LAND_REF=origin/ops/main-base)"; has "⑩ «BYZ origin/main» + env ops → ref-mismatch" "$o" "LANDED-INVALID ref-mismatch origin/ops/main-base ≠ origin/main"
o="$(cm 11 FT_LAND_REF=origin/ops/main-base)"; [ "$o" = "card${TAB}legacy${TAB}origin/ops/main-base${TAB}$C1" ] && ok "⑩ «main» + env ops → card·legacy·origin/ops/main-base" || bad "⑩ legacy env «${o}»"
o="$(cm 10)"; [ "$o" = "card${TAB}explicit${TAB}origin/main${TAB}$C1" ] && ok "⑩ «BYZ origin/main» env 없음 → card·explicit·origin/main" || bad "⑩ explicit «${o}»"
o="$(cm 11)"; [ "$o" = "card${TAB}legacy${TAB}origin/main${TAB}$C1" ] && ok "⑩ «main» env 없음 → card·legacy·origin/main" || bad "⑩ legacy «${o}»"
o="$(gate 10 FT_LAND_REF=origin/ops/main-base --landed "$C1")"; has "⑩ 보류 가드 «BYZ origin/main» + env ops → ref-mismatch" "$o" "ref-mismatch"
# ⑪ explicit 둘 같은 sha ref 다름 → REJECT · main + 팩 origin/ops/x 같은 sha(선택자 다름) → REJECT
o="$(cm 12)"; has "⑪ explicit 두 ref → REJECT 표식 여러 개" "$o" "REJECT 표식 여러 개"
o="$(cm 13)"; has "⑪ main + 팩 ref(선택자 다름) → REJECT 표식 여러 개" "$o" "REJECT 표식 여러 개"
# close-landed: BYZ ops 행을 읽고 그 ref 로 조상 검사(dry-run · 쓰기 0)
o="$(mv_ "$BIN/ft-index-close-landed.sh" "$DAF" --dry-run)"
has "close-landed dry-run: §1 r1 BYZ ops 행 → 조상 ok · LANDED-CLOSE" "$o" "| §1 | r1 | 진행 | ok | 무 | LANDED-CLOSE sha=$SOPS"

echo "fail=$fail"; [ "$fail" = 0 ]
