#!/usr/bin/env bash
# test_index_move_slack.sh — ft-index-move 슬랙 단계(판정 405 §4) 시험. 가짜 byz_thread_post 스텁(rc 지정) + 임시 git 리포 카드 픽스처. 실제 슬랙 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC_MOVE="$HERE/../../harness/kit/fable-team/bin/ft-index-move.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$SRC_MOVE" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BIN="$T/bin"; mkdir -p "$BIN"
cp "$SRC_MOVE" "$BIN/ft-index-move.sh"; cp "$(dirname "$SRC_MOVE")/ft-index-move-canon.sh" "$(dirname "$SRC_MOVE")/ft-index-move-install.sh" "$(dirname "$SRC_MOVE")/ft_da_hold_gate.py" "$BIN/"
cp "$(dirname "$SRC_MOVE")/ft-team-lib.sh" "$BIN/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-index-lint.sh"        # lint 는 별도 시험 — 여기선 통과 스텁
printf '#!/usr/bin/env bash\necho "bash ring $1"\n' > "$BIN/ft-resume-cmd.sh"
STUB="$T/byz_thread_post_stub.sh"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
echo "$*" >> "$TP_LOG"
case "$1" in
  check) exit "${TP_CHECK_RC:-0}";;
  progress) exit "${TP_PROGRESS_RC:-0}";;
  result) exit "${TP_RESULT_RC:-0}";;
esac
exit 9
STUBEOF
chmod 755 "$STUB"
export FT_THREAD_POST="$STUB" TP_LOG="$T/tp.log" FT_SEATS_JSON="$T/none.json" FT_INDEX_STATE_DIR="$T/state"
mkdir -p "$T/state"

REPO="$T/repo"; mkdir -p "$REPO/design/harness/indices"/{대기,진행,완성}
git -C "$REPO" init -q -b main . && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
printf '# 판정문\n## §1 닫힘: 결과 제목 줄 시험 b1 b2 b3 b3b b4 b5 b6 b7\n본문\n' > "$REPO/design/harness/DA-x.md"   # R37: 절에 카드 이름이 있어야 닫힌 절
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$REPO/design/TEAMS.md"   # R383: 하네스 카드 판정이 팀 폴더 명단을 읽는다
git -C "$REPO" add -A && git -C "$REPO" commit -qm base   # 6: --landed 는 랜딩 브랜치 조상 commit 이어야 한다(영향 없음 카드도 (가) 검사)
LSHA="$(git -C "$REPO" rev-parse HEAD)"; export FT_LAND_REF=HEAD
DA="$REPO/design/harness/DA-x.md#§1"

# card <폴더> <이름> <슬랙줄 있음 0|1> — 카드 경로를 출력
card() {
  local f="$REPO/design/harness/indices/$1/$2.md"
  { echo "# 인덱스: $2"; echo "- Issue: 없음 → 시험"; echo "## 상태"; echo "- 정본 영향 없음: 하네스 도구만 변경 — 제품 정본 없음"; echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"; echo "- 설치: 없음"
    [ "$3" = 1 ] && echo "- 슬랙: C0C6MJGRR89 1700000000.000100"; } > "$f"
  echo "$f"
}
mv_() { bash "$BIN/ft-index-move.sh" "$@" 2>&1; }
reset() { : > "$TP_LOG"; unset TP_CHECK_RC TP_PROGRESS_RC TP_RESULT_RC; }
calls() { grep -c "^$1 " "$TP_LOG" 2>/dev/null || true; }
IDX="$REPO/design/harness/indices"

# 1. 대기→진행 · 슬랙 줄 없음 → 도구 호출 0 · 이동
reset; c="$(card 대기 a1 0)"; out="$(mv_ "$c" 진행 --seat s1)"
[ -f "$IDX/진행/a1.md" ] && [ ! -s "$TP_LOG" ] && ok "1 대기→진행 슬랙 줄 없음: 호출 0·이동" || bad "1: $out / $(cat "$TP_LOG")"

# 2. 대기→진행 · 슬랙 줄 있음 · progress rc0 → 착수 답글 + 블록 인자 · 이동
reset; c="$(card 대기 a2 1)"; out="$(mv_ "$c" 진행 --seat seat-x#0)"
[ -f "$IDX/진행/a2.md" ] && [ "$(calls progress)" = 1 ] \
  && grep -q -- '--text 착수 — seat-x#0' "$TP_LOG" && grep -q -- '--issue 없음 --seat seat-x#0 --canon 없음' "$TP_LOG" \
  && ok "2 대기→진행 착수 답글(카드·블록 인자)·이동" || bad "2: $out / $(cat "$TP_LOG")"

# 3. 대기→진행 · progress rc1 → REJECT · 파일 위치 불변
reset; c="$(card 대기 a3 1)"; out="$(TP_PROGRESS_RC=1 mv_ "$c" 진행 --seat s3)"
[ -f "$c" ] && [ ! -f "$IDX/진행/a3.md" ] && echo "$out" | grep -q '^REJECT 슬랙 착수 답글 실패' \
  && ok "3 progress 실패 → REJECT·위치 불변" || bad "3: $out"

# 4. 진행→완성 · 슬랙 줄 없음 → 호출 0 · 이동
reset; c="$(card 진행 b1 0)"; out="$(mv_ "$c" 완성 --da "$DA" --seat s)"
[ -f "$IDX/완성/b1.md" ] && [ ! -s "$TP_LOG" ] && ok "4 진행→완성 슬랙 줄 없음: 호출 0·이동" || bad "4: $out"

# 5. 진행→완성 · check rc0(이미 결과 있음) → result 호출 0 · 이동
reset; c="$(card 진행 b2 1)"; out="$(TP_CHECK_RC=0 mv_ "$c" 완성 --da "$DA" --seat s)"
[ -f "$IDX/완성/b2.md" ] && [ "$(calls check)" = 1 ] && [ "$(calls result)" = 0 ] \
  && ok "5 check 0 → result 호출 0·이동" || bad "5: $out / $(cat "$TP_LOG")"

# 6. check rc1 → result 자동(--verdict·--landed) · 이동
reset; c="$(card 진행 b3 1)"; out="$(TP_CHECK_RC=1 mv_ "$c" 완성 --da "$DA" --seat s --landed $LSHA)"
[ -f "$IDX/완성/b3.md" ] && [ "$(calls result)" = 1 ] \
  && grep -q -- "--verdict $DA" "$TP_LOG" && grep -q -- "--landed $LSHA" "$TP_LOG" \
  && ok "6 check 1 → result 자동(verdict·landed)·이동" || bad "6: $out / $(cat "$TP_LOG")"

# 6b. --landed 없음 → result 인자에 --landed 없음
reset; c="$(card 진행 b3b 1)"; out="$(TP_CHECK_RC=1 mv_ "$c" 완성 --da "$DA" --seat s)"
grep -q '^result ' "$TP_LOG" && ! grep -q -- '--landed' "$TP_LOG" && ok "6b --landed 생략 → 인자 없음" || bad "6b: $(cat "$TP_LOG")"

# 7. check rc1 · result rc1(발송 실패) → REJECT · 위치 불변
reset; c="$(card 진행 b4 1)"; out="$(TP_CHECK_RC=1 TP_RESULT_RC=1 mv_ "$c" 완성 --da "$DA" --seat s)"
[ -f "$c" ] && [ ! -f "$IDX/완성/b4.md" ] && echo "$out" | grep -q '^REJECT 슬랙 결과 답글 실패' \
  && ok "7 result 실패 → REJECT·위치 불변" || bad "7: $out"

# 8. check rc3(장부 불명) → REJECT(repair 안내) · result 호출 0 · 위치 불변
reset; c="$(card 진행 b5 1)"; out="$(TP_CHECK_RC=3 mv_ "$c" 완성 --da "$DA" --seat s)"
[ -f "$c" ] && [ "$(calls result)" = 0 ] && echo "$out" | grep -q 'byz_thread_post.py repair --card' \
  && ok "8 check 3 → REJECT(repair)·result 0·위치 불변" || bad "8: $out"

# 9. 그 밖 rc(예: 2) → REJECT · 위치 불변
reset; c="$(card 진행 b6 1)"; out="$(TP_CHECK_RC=2 mv_ "$c" 완성 --da "$DA" --seat s)"
[ -f "$c" ] && echo "$out" | grep -q '^REJECT 슬랙 장부 확인 실패 rc=2' && ok "9 check 기타 rc → REJECT" || bad "9: $out"

# 10. 슬랙 줄 있는 카드 + 발행 도구 없음 → REJECT(폴백 0) · 위치 불변
reset; c="$(card 대기 a4 1)"; out="$(FT_THREAD_POST="$T/nope.py" mv_ "$c" 진행 --seat s)"
[ -f "$c" ] && echo "$out" | grep -q '^REJECT 카드에 「- 슬랙:」 줄이 있는데 발행 도구가 없다' && ok "10 도구 없음 → REJECT" || bad "10: $out"

# 11. 슬랙 줄 없는 카드 + 도구 없음 → 지금처럼 이동(슬랙 단계 0)
reset; c="$(card 대기 a5 0)"; out="$(FT_THREAD_POST="$T/nope.py" mv_ "$c" 진행 --seat s)"
[ -f "$IDX/진행/a5.md" ] && ok "11 슬랙 줄 없음 + 도구 없음 → 이동" || bad "11: $out"

# 12. 되돌리기(진행→대기)는 슬랙 단계 0
reset; c="$(card 진행 b7 1)"; out="$(mv_ "$c" 대기 --seat s)"
[ -f "$IDX/대기/b7.md" ] && [ ! -s "$TP_LOG" ] && ok "12 되돌리기: 호출 0" || bad "12: $out"

echo "fail=$fail"; [ "$fail" = 0 ]
