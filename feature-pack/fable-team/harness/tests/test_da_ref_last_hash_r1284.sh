#!/usr/bin/env bash
# test_da_ref_last_hash_r1284.sh — r1284: 판정문 참조 «<파일>#<절>» 을 읽는 다섯 곳이 «마지막 #» 에서 자른다.
#   사건(room #221394): 카드를 완성으로 옮길 때 주는 판정문 참조가 절대 경로면 «좌석 scratch 폴더 이름» 의 #(…-claude#198)을
#     절 구분자로 읽어 파일 이름이 잘렸다 → «판정문 없음» REJECT — 상대 경로 우회만 됐다.
#   자르는 곳: ft-index-move.sh(완성·아카이브) · ft_da_hold_gate.py · ft_doc_exempt_moves.py · ft-issue-close-check.sh(정본 줄).
#   절 이름에 # 는 없다(판정문 머리 «## §N …») — 그래서 «마지막 #» 이면 두 꼴(# 없는 지금 입력 · 경로에 # 이 낀 입력)이 다 맞는다.
#   임시 git 리포 + 픽스처 카드·판정문만 — 실 라이브·실 원격·실 indices·실 mbox 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${SRC:-$(cd "$HERE/../bin" && pwd -P)}"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$T/home"
mkdir -p "$HOME"
unset FT_HARNESS_ROOT FT_INSTALL_CHECK FT_INSTALL_PENDING_DIR FT_LANDED_MARKER
export FT_LAND_REF=main

BIN="$T/bin"; mkdir -p "$BIN"
cp -p "$SRC"/ft-index-move.sh "$SRC"/ft-index-move-canon.sh "$SRC"/ft-index-move-install.sh \
      "$SRC"/ft_da_hold_gate.py "$SRC"/ft_git_capped.py "$SRC"/ft-team-lib.sh "$SRC"/ft-harness-root.sh \
      "$SRC"/ft-issue-close-check.sh "$BIN/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-index-lint.sh"; chmod 755 "$BIN/ft-index-lint.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "$MBOX_LOG"\nexit 0\n' > "$T/fake-mbox.sh"; chmod 755 "$T/fake-mbox.sh"
export FT_MBOX="$T/fake-mbox.sh" MBOX_LOG="$T/mbox.log" FT_INDEX_STATE_DIR="$T/state" FT_SEATS_JSON="$T/none.json"
mkdir -p "$T/state" "$T/none"

# ── ⓪ 문법 — 바뀐 두 셸 파일 ──
for f in ft-index-move.sh ft-issue-close-check.sh; do bash -n "$SRC/$f"; rc=$?; ck "⓪ bash -n $f" "$rc"; done

# ── 임시 리포(main 흉내) ──
R="$T/repo"; IDX="$R/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성} "$R/docs/architect"
G() { git -C "$R" -c user.name=t -c user.email=t@t "$@"; }
G init -q -b main
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$R/design/TEAMS.md"
printf '## §3 절\nv1\n' > "$R/docs/architect/X.md"
G add -A; G commit -qm base; S1="$(G rev-parse HEAD)"
# 정본 줄 시험용 — 경로 «폴더 이름» 에 # 이 든 파일(판정문 아님 · 정본 파일)
mkdir -p "$R/design/harness/arch#198"
printf '## §3 절\nv1\n' > "$R/design/harness/arch#198/ISSUE-TRANSITIONS.md"
G add -A; G commit -qm "canon # path"; S2="$(G rev-parse HEAD)"

card() { # <이름> → 카드 경로(진행/)
  local f="$IDX/진행/$1.md"
  { echo "# 인덱스: $1"; echo "## 상태"
    echo "- 정본 영향 없음: 하네스 도구만 바뀐 카드 — 제품 정본 없음"
    echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"
    echo "- 설치: 없음"; } > "$f"
  echo "$f"
}
mkverdict() { # <경로> <카드 이름> <절…>
  local f="$1" c="$2"; shift 2
  mkdir -p "$(dirname -- "$f")"; printf '# 판정문\n' > "$f"
  local s; for s in "$@"; do printf '## %s 닫힘: %s\n' "$s" "$c" >> "$f"; done
}
mv_() { bash "$BIN/ft-index-move.sh" "$@" 2>&1; }
done_() { [ -f "$IDX/완성/$1.md" ] && [[ "$out" == *"MOVED"* ]]; }   # rc 무관 판정은 ck 인자로

# ── R1 경로에 # 없음 — 지금과 같은 결과(이동 OK) ──
V1="$T/w/design/harness/VERDICT-r1.md"; mkverdict "$V1" k1 §12
c="$(card k1)"; out="$(mv_ "$c" 완성 --da "$V1#§12" --seat s --landed "$S1")"; rc=$?
done_ k1; ck "R1 # 없는 상대 경로 «…VERDICT-r1.md#§12» → 이동 OK(지금 그대로)" "$?"

# ── R2 폴더 이름에 # 하나(절대 경로) — 지금은 «판정문 없음» REJECT ──
V2="$T/w/arch-claude#198/repo/design/harness/VERDICT-r2.md"; mkverdict "$V2" k2 §12
c="$(card k2)"; out="$(mv_ "$c" 완성 --da "$V2#§12" --seat s --landed "$S1")"; rc=$?
done_ k2; ck "R2 절대 경로 폴더 «arch-claude#198» → 파일=# 앞 전체 · 절 §12 · 이동 OK" "$?"

# ── R3 경로에 # 둘 ──
V3="$T/w/a#b/arch-claude#198/VERDICT-r3.md"; mkverdict "$V3" k3 §12
c="$(card k3)"; out="$(mv_ "$c" 완성 --da "$V3#§12" --seat s --landed "$S1")"; rc=$?
done_ k3; ck "R3 경로에 # 둘(«a#b/arch-claude#198») → 마지막 # 기준 · 이동 OK" "$?"

# ── R3b 절 정확 일치 유지 — §5 인용이 §57 절을 빌리지 않는다(# 경로에서도) ──
V3B="$T/w/arch-claude#198/repo/design/harness/VERDICT-r3b.md"
mkverdict "$V3B" k3b §57 §5
c="$(card k3b)"; out="$(mv_ "$c" 완성 --da "$V3B#§5" --seat s --landed "$S1")"; rc=$?
done_ k3b; ck "R3b # 낀 경로 + «§5» 인용 → §57 이 아니라 §5 절 → 이동 OK" "$?"

# ── R4 # 없음 — 지금처럼 거절(조용한 통과 0) ──
V4="$T/w/design/harness/VERDICT-r4.md"; mkverdict "$V4" k4 §12
c="$(card k4)"; out="$(mv_ "$c" 완성 --da "$V4" --seat s --landed "$S1")"; rc=$?
[ "$rc" != 0 ] && [ ! -f "$IDX/완성/k4.md" ] && [[ "$out" == *"REJECT"* ]] && [ -f "$c" ] && ck "R4 «#» 없는 참조 → 지금처럼 REJECT(이동 0)" 0 || ck "R4 # 없음 → REJECT" 1

# ── R5 ft_da_hold_gate.py — # 낀 경로의 판정문 절을 읽는다(지금은 da-missing) ──
V5="$T/w/arch-claude#198/repo/design/harness/VERDICT-r5.md"
mkdir -p "$(dirname -- "$V5")"; printf '# 판정문\n## §1 닫힘: k5\n- 닫힘 — k5 — main `%s`\n' "$S1" > "$V5"
{ echo "# 인덱스: k5"; echo "## 상태"; echo "- 정본 영향 없음: 하네스 도구만 바뀐 카드 — 제품 정본 없음"; } > "$IDX/진행/k5.md"
out="$(FT_HARNESS_ROOT= python3 "$BIN/ft_da_hold_gate.py" "$IDX/진행/k5.md" --root "$R" --seats-dir "$T/none" --comm "$T/none" --closing --da "$V5#§1" --landed "$S1" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "${out%%$'\n'*}" == "LANDED-CLOSE sha=$S1"* ]] && ck "R5 ft_da_hold_gate --da «# 낀 경로#§1» → LANDED-CLOSE rc0(지금은 da-missing rc3)" 0 || ck "R5 보류 가드 절 읽기" 1

# ── R6 ft-issue-close-check.sh 정본 줄 «<# 낀 경로>#§3@<sha>» → 파일·절·sha 셋 다 갈림 ──
FX="$HERE/../fixtures/issue_close/closed-with-6items-canon.json"
sed -e 's|design/harness/ISSUE-TRANSITIONS.md#§3|design/harness/arch#198/ISSUE-TRANSITIONS.md#§3|' -e "s|__S1__|$S2|g" "$FX" > "$T/fx-r6.json"
out="$(bash "$BIN/ft-issue-close-check.sh" 9002 --from-json "$T/fx-r6.json" --repo "$R" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"OK   6항 정본 design/harness/arch#198/ISSUE-TRANSITIONS.md @ $S2"* ]] && ck "R6 정본 줄 «arch#198/…#§3@sha» → 파일·절·sha 셋 다 맞음 rc0" 0 || ck "R6 정본 줄 # 경로" 1

# ── 변이 1 ft-index-move.sh 를 «첫 #» 로 되돌림 → R2 가 FAIL(이동 0 · 판정문 없음) ──
cp -p "$BIN/ft-index-move.sh" "$T/im.bak"
python3 - "$BIN/ft-index-move.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s = s.replace('DAF="${DA%#*}"; SEC="${DA##*#}"', 'DAF="${DA%%#*}"; SEC="${DA#*#}"')
open(p, "w", encoding="utf-8").write(s)
PY
c="$(card k2m)"; out="$(bash "$BIN/ft-index-move.sh" "$c" 완성 --da "$V2#§12" --seat s --landed "$S1" 2>&1)"; rc=$?
[ ! -f "$IDX/완성/k2m.md" ] && [[ "$out" == *"REJECT DA 판정문 없음"* ]] && ck "변이 1 첫 # 로 되돌림 → R2 FAIL(«판정문 없음» · 이동 0)" 0 || ck "변이 1" 1
cp -p "$T/im.bak" "$BIN/ft-index-move.sh"

# ── 변이 2 ft_da_hold_gate.py partition 되돌림 → R5 FAIL(da-missing rc3) ──
cp -p "$BIN/ft_da_hold_gate.py" "$T/gate.bak"
python3 - "$BIN/ft_da_hold_gate.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s = s.replace('path, _, sec = da.rpartition("#") if "#" in da else (da, "", "")', 'path, _, sec = da.partition("#")')
open(p, "w", encoding="utf-8").write(s)
PY
out="$(python3 "$BIN/ft_da_hold_gate.py" "$IDX/진행/k5.md" --root "$R" --seats-dir "$T/none" --comm "$T/none" --closing --da "$V5#§1" --landed "$S1" 2>&1)"; rc=$?
[ "${out%%$'\n'*}" != LANDED-CLOSE* ] && [[ "$out" == *"LANDED-INVALID da-missing"* ]] && ck "변이 2 partition 되돌림 → R5 FAIL(LANDED-INVALID da-missing)" 0 || ck "변이 2" 1
cp -p "$T/gate.bak" "$BIN/ft_da_hold_gate.py"

# ── 변이 3 ft-issue-close-check.sh 첫 # 로 되돌림 → R6 FAIL(정본 파일 못 찾음) ──
cp -p "$BIN/ft-issue-close-check.sh" "$T/icc.bak"
python3 - "$BIN/ft-issue-close-check.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s = s.replace('X="${V%#*}"; REST="${V##*#}"', 'X="${V%%#*}"; REST="${V#*#}"')
open(p, "w", encoding="utf-8").write(s)
PY
out="$(bash "$BIN/ft-issue-close-check.sh" 9002 --from-json "$T/fx-r6.json" --repo "$R" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"MISS 6항 정본"* ]] && [[ "$out" == *"정본 design/harness/arch "* ]] && ck "변이 3 첫 # 로 되돌림 → R6 FAIL(정본 파일 잘림)" 0 || ck "변이 3" 1
cp -p "$T/icc.bak" "$BIN/ft-issue-close-check.sh"

# ── 복원 확인 — 변이 뒤 파일이 원판과 같다 ──
for f in ft-index-move.sh ft_da_hold_gate.py ft-issue-close-check.sh; do cmp -s "$BIN/$f" "$SRC/$f"; rc=$?; ck "복원 cmp $f" "$rc"; done

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
