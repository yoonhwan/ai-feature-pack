#!/usr/bin/env bash
# test_index_move_canon_landed.sh — ft-index-move 진행→완성: 정본 갱신 카드의 랜딩 commit 사실 검사(판정 440 r2 §6-1/§6-5) + R37 절-카드 결속 + 정본 쪽지 수신자 _arch.
# 임시 git 리포(main 흉내)·가짜 mbox·카드/판정문 픽스처만 — 실제 indices·판정서·seats.json·mbox 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRCDIR="$HERE/../../harness/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in ft-index-move.sh ft-index-move-canon.sh; do bash -n "$SRCDIR/$f" && ok "bash -n $f" || bad "bash -n $f"; done

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BIN="$T/bin"; mkdir -p "$BIN"
cp "$SRCDIR/ft-index-move.sh" "$SRCDIR/ft-index-move-canon.sh" "$SRCDIR/ft-index-move-install.sh" "$SRCDIR/ft_da_hold_gate.py" "$SRCDIR/ft_git_capped.py" "$BIN/"
cp "$SRCDIR/ft-team-lib.sh" "$BIN/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-index-lint.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "$MBOX_LOG"\nexit 0\n' > "$T/fake-mbox.sh"; chmod 755 "$T/fake-mbox.sh"
export FT_MBOX="$T/fake-mbox.sh" MBOX_LOG="$T/mbox.log" FT_INDEX_STATE_DIR="$T/state" FT_LAND_REF=main FT_SEATS_JSON="$T/none.json"
mkdir -p "$T/state"

REPO="$T/repo"; IDX="$REPO/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성} "$REPO/docs/architect"
G() { git -C "$REPO" "$@"; }
G init -q -b main . && G config user.email t@t && G config user.name t
X=docs/architect/X.md
printf '## 절A 제목\nv1\n' > "$REPO/$X"; echo base > "$REPO/code.txt"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$REPO/design/TEAMS.md"   # R383: 하네스 카드 판정이 팀 폴더 명단을 읽는다
G add -A && G commit -qm base
sha() { G rev-parse HEAD; }
edit_x() { echo "$1" >> "$REPO/$X"; G commit -qam "x $1"; }
edit_code() { echo "$1" >> "$REPO/code.txt"; G commit -qam "code $1"; }

# card <이름> <갱신|없음> — 진행/ 에 카드 생성, 경로 출력
card() {
  local f="$IDX/진행/$1.md"
  { echo "# 인덱스: $1"; echo "## 상태"
    if [ "$2" = 갱신 ]; then echo "- 정본 갱신: $X §절A"; else echo "- 정본 영향 없음: 하네스 도구만 변경 — 제품 정본 없음"; fi
    echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"; echo "- 설치: 없음"; } > "$f"
  echo "$f"
}
# da <파일명> <절본문...> — 판정문 생성, 경로 출력
da() { local f="$REPO/design/harness/$1.md"; shift; printf '# 판정문\n' > "$f"; printf '%s\n' "$@" >> "$f"; echo "$f"; }
mv_() { bash "$BIN/ft-index-move.sh" "$@" 2>&1; }
expect_rej() { # <번호> <카드경로> <출력> <사유 패턴>
  local n="$1" c="$2" out="$3" pat="$4"
  [ -f "$c" ] && [ ! -f "$IDX/완성/$(basename "$c")" ] && echo "$out" | grep -q "^REJECT.*$pat" && ok "$n" || bad "$n: $out"
}

# ① 카드 브랜치엔 X 수정 · 랜딩 S 에는 코드만 → (나) REJECT
G checkout -q -b c1; edit_x v2; C1="$(sha)"; G checkout -q main; edit_code a; S1="$(sha)"
c="$(card k1 갱신)"; d="$(da da1 "## §1 닫힘: k1" "정본 diff 확인: $X §절A @$C1 — v2")"
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s --landed "$S1")"
expect_rej "1 랜딩 commit 에 정본 없음 → REJECT(나)" "$c" "$out" "랜딩 commit 에 정본"

# ② 정상 squash S(X 포함) · S 가 main 조상 · 뒤에 코드 커밋이 더 있어도 빈 구간 거짓 REJECT 0
G checkout -q -b c2; edit_x v3; C2="$(sha)"; G checkout -q main; G merge -q --squash c2 >/dev/null; G commit -qm "squash c2"; S2="$(sha)"; edit_code b
c="$(card k2 갱신)"; d="$(da da2 "## §1 닫힘: k2" "정본 diff 확인: $X §절A @$C2 — v3")"
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s --landed "$S2")"
[ -f "$IDX/완성/k2.md" ] && echo "$out" | grep -q '^MOVED' && ok "2 정상 squash → 통과" || bad "2: $out"

# ③ arch 확인 C 뒤 X 재수정 → 랜딩 S → (다) REJECT
G checkout -q -b c3; edit_x v4; C3="$(sha)"; edit_x v5; G checkout -q main; G merge -q --squash c3 >/dev/null; G commit -qm "squash c3"; S3="$(sha)"
c="$(card k3 갱신)"; d="$(da da3 "## §1 닫힘: k3" "정본 diff 확인: $X §절A @$C3 — v4")"
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s --landed "$S3")"
expect_rej "3 확인 뒤 정본이 바뀜 → REJECT(다)" "$c" "$out" "검토 뒤 정본이 바뀜"

# ④ ff 랜딩 --landed T..S 통과 · 같은 S 만 주면 S^1..S 에 X 없어 REJECT
T4="$(sha)"; G checkout -q -b c4; edit_x v6; C4="$(sha)"; edit_code c; G checkout -q main; G merge -q --ff-only c4; S4="$(sha)"
c="$(card k4 갱신)"; c4b="$(card k4b 갱신)"; d="$(da da4 "## §1 닫힘: k4 k4b" "정본 diff 확인: $X §절A @$C4 — v6")"
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s --landed "$T4..$S4")"
[ -f "$IDX/완성/k4.md" ] && echo "$out" | grep -q '^MOVED' && ok "4 ff --landed T..S → 통과" || bad "4: $out"
out="$(mv_ "$c4b" 완성 --da "$d#§1" --seat s --landed "$S4")"
expect_rej "4b ff 인데 S 만 → 구간에 X 없어 REJECT" "$c4b" "$out" "랜딩 commit 에 정본"

# ⑤ --landed 없는 갱신 카드 → REJECT
c="$(card k5 갱신)"; d="$(da da5 "## §1 닫힘: k5" "정본 diff 확인: $X §절A @$C4 — v6")"
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s)"
expect_rej "5 --landed 없음 → REJECT" "$c" "$out" "--landed <랜딩 commit> 필수"

# ⑤b 확인 줄 없음 → REJECT · ⑤c 랜딩 안 된 sha(main 조상 아님) → REJECT
c="$(card k5b 갱신)"; d="$(da da5b "## §1 닫힘: k5b" "본문 확인 줄 없음")"
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s --landed "$T4..$S4")"
expect_rej "5b arch 확인 줄 없음 → REJECT" "$c" "$out" "정본 diff 확인"
c="$(card k5c 없음)"; d="$(da da5c "## §1 닫힘: k5c")"
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s --landed "$C1")"
expect_rej "5c 영향 없음 + main 조상 아닌 S → REJECT(가)" "$c" "$out" "랜딩 안 됨"
c="$(card k5d 없음)"; d="$(da da5d "## §1 닫힘: k5d")"
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s --landed "$S4")"
[ -f "$IDX/완성/k5d.md" ] && ok "5d 영향 없음 + 랜딩된 S → (가)만 통과" || bad "5d: $out"

# ⑥ (R37) 다른 카드 절 인용 → REJECT · 파일 위치 불변
c="$(card k6 없음)"; d="$(da da6 "## §1 닫힘: 다른-카드-이름")"
out="$(mv_ "$c" 완성 --da "$d#§1" --seat s)"
expect_rej "6 다른 카드 절 인용 → REJECT" "$c" "$out" "절에 카드 이름 없음).*대상 카드: k6"

# ⑦ (R37) §5 인용이 §57 절로 통과 0 · §5 자체 닫힘 없으면 §57 본문을 빌리지 않음
c="$(card k7 없음)"; d="$(da da7 "## §57 닫힘: k7")"
out="$(mv_ "$c" 완성 --da "$d#§5" --seat s)"
expect_rej "7 §5 인용 + §57 절만 → REJECT(절 없음)" "$c" "$out" "절 «§5» 없음"
d="$(da da7b "## §57 닫힘: k7" "## §5 보류: k7")"
out="$(mv_ "$c" 완성 --da "$d#§5" --seat s)"
expect_rej "7b §5 절에 닫힘 없음 → REJECT" "$c" "$out" "「닫힘」/「CLOSE」 없음"
d="$(da da7c "## §57 보류" "## §5 닫힘: k7")"
out="$(mv_ "$c" 완성 --da "$d#§5" --seat s)"
[ -f "$IDX/완성/k7.md" ] && ok "7c §5 정확 일치 절 → 통과" || bad "7c: $out"

# ⑧ 쪽지 수신자 — _arch 있음 = 그 좌석 · 없음 = 쪽지 0 + INFO
printf '{"_arch":"team-arch#3"}\n' > "$T/seats-arch.json"; : > "$MBOX_LOG"
G checkout -q -b c8; edit_x v8; C8="$(sha)"; G checkout -q main; G merge -q --squash c8 >/dev/null; G commit -qm "squash c8"; S8="$(sha)"
c="$(card k8 갱신)"; d="$(da da8 "## §1 닫힘: k8 k8b k8c" "정본 diff 확인: $X §절A @$C8 — v8")"
out="$(FT_SEATS_JSON="$T/seats-arch.json" mv_ "$c" 완성 --da "$d#§1" --seat s --landed "$S8")"
grep -q '^send team-arch#3 ' "$MBOX_LOG" && echo "$out" | grep -q '^NOTIFIED' && ok "8 _arch 있음 → 그 좌석에 쪽지" || bad "8: $out / $(cat "$MBOX_LOG")"
: > "$MBOX_LOG"; printf '{"seats":{}}\n' > "$T/seats-none.json"; c="$(card k8b 갱신)"
out="$(FT_SEATS_JSON="$T/seats-none.json" mv_ "$c" 완성 --da "$d#§1" --seat s --landed "$S8")"
[ ! -s "$MBOX_LOG" ] && echo "$out" | grep -q '^INFO 정본 쪽지 생략 — 명부에 _arch 없음' && [ -f "$IDX/완성/k8b.md" ] && ok "8b _arch 없음 → 쪽지 0·INFO·이동 완료" || bad "8b: $out / $(cat "$MBOX_LOG")"
# ⑧c (R41) _arch 있음 + 「정본 영향 없음」 카드 → 쪽지 0 + INFO 1줄 + 이동 완료
: > "$MBOX_LOG"; c="$(card k8c 없음)"
out="$(FT_SEATS_JSON="$T/seats-arch.json" mv_ "$c" 완성 --da "$d#§1" --seat s --landed "$S8")"
[ ! -s "$MBOX_LOG" ] && echo "$out" | grep -q '^INFO 정본 쪽지 생략 — 정본 영향 없음 카드' && ! echo "$out" | grep -q '^NOTIFIED' && [ -f "$IDX/완성/k8c.md" ] && ok "8c _arch 있음 + 영향 없음 카드 → 쪽지 0·INFO·이동 완료" || bad "8c: $out / $(cat "$MBOX_LOG")"


# ⑨ (r1018) 문서 카드(«- 설치: 없음» · design/**.md 만 · 문서 가지 조상) 인정 — stdout 은 «OK» 한 줄뿐, 안내 줄 «착지 인정 =» 은 stderr
G checkout -q -b docbase main; printf 'doc only\n' > "$REPO/design/harness/NOTE-doc.md"; G add -A; G commit -qm "doc note"; SDOC="$(sha)"; G checkout -q main
mkdir -p "$IDX/진행"
c="$(card k9 없음)"; d="$(da da9 "## §1 닫힘: k9")"
out9="$(printf '%s\n' "## §1 닫힘: k9" | FT_DOC_LAND_REF=docbase bash "$BIN/ft-index-move-canon.sh" "$c" "$REPO" "$SDOC" 2>"$T/c9.err")"
n9="$(printf '%s\n' "$out9" | awk 'END{print NR}')"
[ "$n9" = 1 ] && [ "$(printf '%s\n' "$out9" | cut -f1)" = OK ] && [ "$(grep -c '착지 인정' "$T/c9.err")" = 1 ] && ok "9a 문서 카드 → stdout 1줄 OK · 안내 줄 stderr" || bad "9a: n=$n9 out=[$out9] err=[$(cat "$T/c9.err")]"
# ⑨b 호출자 ft-index-move.sh 흐름 — «정본 게이트 검사 실행 실패» 0 · 완성 이동 성공
out9b="$(FT_DOC_LAND_REF=docbase mv_ "$c" 완성 --da "$d#§1" --seat s --landed "$SDOC")"
! echo "$out9b" | grep -q '정본 게이트 검사 실행 실패' && echo "$out9b" | grep -q '^MOVED' && [ -f "$IDX/완성/k9.md" ] && ok "9b 문서 카드 → 호출자 실행 실패 0 · 이동 완료" || bad "9b: $out9b"

echo "fail=$fail"; [ "$fail" = 0 ]
