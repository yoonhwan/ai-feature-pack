#!/usr/bin/env bash
# test_issue_close_gate.sh — R102 이슈 닫기 게이트 시험 (PLAN-r102-close-gate §4 · 판정 1059·1060)
#   ft-issue-close-gate.sh + ft-issue-close-check.sh --gate + ft-gh-as-tank.sh close 1줄.
# 임시 git 리포 + --from-json 상태 파일 + 가짜 Tank 래퍼(stubs/fake-tank.sh)만 쓴다 — 실 gh 호출·Issue 쓰기·루트 .fable-team/ 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"
MIR="$HERE/../../scripts/harness-install/fable-team/bin"
STUB="$HERE/stubs/fake-tank.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in ft-issue-close-check.sh ft-issue-close-gate.sh ft-gh-as-tank.sh; do
  bash -n "$BIN/$f" 2>/dev/null && ok "bash -n $f" || bad "bash -n $f"
done

# ── 임시 리포: main 위에 A→B→C→D (관찰 판·수리 랜딩 sha 용) ──
R="$T/repo"; git init -q -b main "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
echo base > "$R/f"; git -C "$R" add -A; git -C "$R" commit -qm base
mkc() { echo "$1" >> "$R/f"; git -C "$R" commit -qam "$1"; git -C "$R" rev-parse HEAD; }
A="$(mkc a)"; B="$(mkc b)"; C="$(mkc c)"; D="$(mkc d)"
git -C "$R" checkout -q -b side "$C"; E="$(mkc e)"; git -C "$R" checkout -q main   # E = C 의 후손이지만 main 의 조상이 아님(미랜딩 가지)
export FT_LAND_REF=main FT_CLOSE_CHECK_REPO="$R"

S="$T/state.json"; LOG="$T/fake.log"; CF="$T/close-comment.md"
mkstate() { local f="$1" labels="$2"; shift 2
  jq -n --argjson l "$labels" '{number:9000,state:"OPEN",title:"[fixture] gate",labels:$l,closedByPullRequestsReferences:[],comments:[$ARGS.positional[]|{body:.}]}' --args "$@" > "$f"; }
gate() { # gate <상태파일> <apply 0|1> [닫는코멘트파일] → OUT · RC  (FAKE_* 는 호출 앞에 env 로)
  OUT="$(FT_CLOSE_CHECK_FROM_JSON="$1" FT_TANK_WRAPPER="$STUB" FAKE_STATE="$1" FAKE_LOG="$LOG" bash "$BIN/ft-issue-close-gate.sh" 9000 "${3:-}" "$2" 2>&1)"; RC=$?; }
wrap() { # wrap <래퍼 인자…> → 래퍼 dry-run(상태 파일 = $S)
  OUT="$(env -u FT_ISSUE_BOT_TOKEN FT_ISSUE_BOT_TOKEN_FILE=/nonexistent FT_CLOSE_CHECK_FROM_JSON="$S" bash "$BIN/ft-gh-as-tank.sh" "$@" 2>&1)"; RC=$?; }
mcount() { jq '[.comments[].body | split("\n")[] | select(startswith("관찰 시작:"))] | length' "$1"; }
has_label() { jq -e '[.labels[]?.name] | index("status:observing")' "$1" >/dev/null; }
logn() { grep -c "$1" "$LOG" 2>/dev/null || true; }
obs() { echo "관찰: 판=$1 · 결과=$2 · 판정=$3"; }
MARK0=$'관찰 시작: 2026-10-11T00:00:00Z · 사유: 원인 확정 N · token=t-9000-marker\n닫는 조건: 오빠 폰에서 서로 다른 판(sha) 2회 재현 0'
Y0=$'원인 확정: Y — 로그·코드·재현으로 원인 확정함\n같은 증상 보류: 0'
SIX=$'[close-6항]\n- 닫는 사건: 재현 스텝 3회 PASS\n- PR: #9100 squash 랜딩\n- 재현 PASS: repro-e2e 코멘트\n- 정리: 워크트리·나노 세션 정리 확인\n- 기록: design/harness/CLOSEOUT-x.md\n- 정본 영향 없음: 하네스 키트 시험 입력'
w() { printf '%s\n' "$1" > "$CF"; }

# ① 빈 칸 거절 — 1~6항만(7·8 없음) · 래퍼 dry-run
mkstate "$S" '[]' "소유 오케=x"; w "$SIX"; : > "$LOG"
wrap close 9000 --comment "$CF"
[ $RC -eq 3 ] && grep -q "비었거나 무효" <<<"$OUT" && grep -q "status:observing" <<<"$OUT" && grep -q "보존" <<<"$OUT" && grep -q "마커" <<<"$OUT" && grep -q "라벨" <<<"$OUT" && ! grep -q "DRY as=byz-tank gh issue close" <<<"$OUT" \
  && ok "① 빈 칸 거절 rc=3 · 쓸 것 목록 · close 출력 0" || bad "① rc=$RC $OUT"
[ ! -s "$LOG" ] && ok "① dry-run 은 쓰기 0" || bad "① dry-run 인데 쓰기 호출: $(cat "$LOG")"
# ①b 옛 유효 Y·0 → 최신(extra) 무효 줄 = 빈 칸 (옛 값으로 내려가지 않음)
mkstate "$S" '[]' "$Y0"; w $'원인 확정: <근거>\n같은 증상 보류: 0'
gate "$S" 0 "$CF"
[ $RC -eq 3 ] && grep -q "비었거나 무효" <<<"$OUT" && ok "①b 옛 유효 → 최신 무효 = 거절(내려가지 않음)" || bad "①b rc=$RC $OUT"
# ①c 근거 글자 수 경계 (9자 거절 · 10자 통과)
mkstate "$S" '[]'; w $'원인 확정: Y — 가나다라마바사아자\n같은 증상 보류: 0'; gate "$S" 0 "$CF"
[ $RC -eq 3 ] && ok "①c 근거 9자 → 거절" || bad "①c 9자 rc=$RC $OUT"
w $'원인 확정: Y — 가나다라마바사아자차\n같은 증상 보류: 0'; gate "$S" 0 "$CF"
[ $RC -eq 0 ] && ok "①c 근거 10자 → 통과" || bad "①c 10자 rc=$RC $OUT"

# ② 같은 증상 보류 거절
mkstate "$S" '[]' "소유 오케=x"
w $'원인 확정: Y — 로그·코드·재현으로 원인 확정함\n같은 증상 보류: design/graphics/CLOSEOUT-g922-wave-mobile-20261011.md'
wrap close 9000 --comment "$CF"
[ $RC -eq 3 ] && grep -q "관찰 중" <<<"$OUT" && grep -q "CLOSEOUT-g922-wave-mobile-20261011.md" <<<"$OUT" && ok "② 보류 거절 rc=3 · 관찰 중" || bad "② rc=$RC $OUT"
# ②b 원인 확정 N 거절
w $'원인 확정: N — 원인 아직 모름\n같은 증상 보류: 0'; wrap close 9000 --comment "$CF"
[ $RC -eq 3 ] && grep -q "원인 확정=N" <<<"$OUT" && ok "②b 원인 확정 N 거절" || bad "②b rc=$RC $OUT"

# ③ 정상 통과 — Y(10자+) + 보류 0 + 관찰 이력 0
mkstate "$S" '[]' "소유 오케=x"; w "$Y0"
gate "$S" 0 "$CF"; [ $RC -eq 0 ] && ok "③ gate rc=0" || bad "③ gate rc=$RC $OUT"
wrap close 9000 --comment "$CF"
[ $RC -eq 0 ] && grep -q "DRY as=byz-tank gh issue close 9000" <<<"$OUT" && ok "③ 래퍼 DRY close rc=0" || bad "③ 래퍼 rc=$RC $OUT"

# ④ 관찰 2판 통과 — 마커 + 서로 다른 판 2줄(재현 0) · 7항 N 이어도
mkstate "$S" '[]' "$MARK0" "$(obs "$A" '재현 0' 1)" "$(obs "$C" '재현 0' 2)"; w $'원인 확정: N — 원인 불명\n같은 증상 보류: x.md'
gate "$S" 0 "$CF"; [ $RC -eq 0 ] && ok "④ 서로 다른 2판 재현 0 → 통과" || bad "④ rc=$RC $OUT"
mkstate "$S" '[]' "$MARK0" "$(obs "$A" '재현 0' 1)"; gate "$S" 0 "$CF"
[ $RC -eq 3 ] && grep -q "1/2" <<<"$OUT" && ok "④b 1판 → 거절(1/2)" || bad "④b rc=$RC $OUT"
mkstate "$S" '[]' "$MARK0" "$(obs "$A" '재현 0' 1)" "$(obs "$A" '재현 0' 2)"; gate "$S" 0 "$CF"
[ $RC -eq 3 ] && ok "⑤(g) 같은 sha 2줄 → 거절" || bad "⑤(g) rc=$RC $OUT"

# ⑤(a) 재현 있음 → 거절 · 보존 코멘트 · 다음 close 도 거절
mkstate "$S" '[]' "$MARK0" "$(obs "$A" '재현 0' 1)" "$(obs "$C" '재현 0' 2)"
w "$Y0"$'\n'"$(obs "$D" '재현 있음' 3)"; : > "$LOG"
gate "$S" 1 "$CF"
[ $RC -eq 3 ] && grep -q "재현 있음" <<<"$OUT" && jq -e '[.comments[].body | select(startswith("[닫기 거절 · R102"))] | length == 1' "$S" >/dev/null \
  && ok "⑤(a) 재현 있음 rc=3 · 거절 코멘트 보존" || bad "⑤(a) rc=$RC $OUT"
gate "$S" 0 ""; [ $RC -eq 3 ] && ok "⑤(a) 다음 close(extra 없음)도 rc=3" || bad "⑤(a)2 rc=$RC $OUT"
# ⑤(b) 마커 쓰기 실패 → rc 1 · 라벨 호출 0
mkstate "$S" '[]' "소유 오케=x"; w $'원인 확정: N — 원인 불명\n같은 증상 보류: 0'; : > "$LOG"
FAKE_FAIL=comment-marker gate "$S" 1 "$CF"
[ $RC -eq 1 ] && grep -q "거절 기록 쓰기 실패" <<<"$OUT" && [ "$(logn step=label)" = 0 ] && [ "$(mcount "$S")" = 0 ] \
  && ok "⑤(b) 마커 실패 rc=1 · 라벨 0 · 마커 0" || bad "⑤(b) rc=$RC label=$(logn step=label) $OUT"
# ⑤(c) 라벨 실패 → rc 1 · 마커 있음 · 재실행 시 마커 재게시 0 + 라벨 붙음
mkstate "$S" '[]' "소유 오케=x"; : > "$LOG"
FAKE_FAIL=label gate "$S" 1 "$CF"
[ $RC -eq 1 ] && [ "$(mcount "$S")" = 1 ] && ! has_label "$S" && ok "⑤(c) 라벨 실패 rc=1 · 마커 1" || bad "⑤(c) rc=$RC mark=$(mcount "$S") $OUT"
gate "$S" 1 "$CF"
[ $RC -eq 3 ] && [ "$(mcount "$S")" = 1 ] && has_label "$S" && ok "⑤(c) 재실행 마커 재게시 0 · 라벨 붙음" || bad "⑤(c) 재실행 rc=$RC mark=$(mcount "$S") $OUT"
# ⑤(d) 마커 있는 상태에서 거절 반복 → 마커 1개 유지
gate "$S" 1 "$CF"; gate "$S" 1 "$CF"
[ "$(mcount "$S")" = 1 ] && ok "⑤(d) 거절 반복 → 마커 1개 유지" || bad "⑤(d) mark=$(mcount "$S")"
# ⑤(e) 써 놓고 timeout(결과 불명) → 재시도 전 token 발견 · 마커 1개
mkstate "$S" '[]' "소유 오케=x"; : > "$LOG"
FAKE_TIMEOUT_AFTER_WRITE=comment-marker gate "$S" 1 "$CF"
[ $RC -eq 3 ] && [ "$(mcount "$S")" = 1 ] && [ "$(logn step=comment-marker)" = 1 ] && ok "⑤(e) 결과 불명 → token 발견 · 재시도 0 · 마커 1" || bad "⑤(e) rc=$RC mark=$(mcount "$S") calls=$(logn step=comment-marker) $OUT"
# 7초 룰 — 쓰기가 상한을 넘으면 재시도 1 뒤 rc 1
mkstate "$S" '[]' "소유 오케=x"; : > "$LOG"
FT_GATE_TIMEOUT_S=1 FAKE_SLEEP=3 gate "$S" 1 "$CF"
[ $RC -eq 1 ] && grep -q "쓰기 실패" <<<"$OUT" && ok "쓰기 timeout → 재시도 1 뒤 rc=1" || bad "timeout rc=$RC $OUT"

# ⑤(f) 구간(epoch) — 새 수리 랜딩만 구간을 옮긴다
M1="관찰 시작: 2026-10-11T01:00:00Z · 수리 랜딩=$B"
mkstate "$S" '[]' "$MARK0" "$(obs "$A" '재현 있음' 1)" "$M1" "$(obs "$C" '재현 0' 2)" "$(obs "$D" '재현 0' 3)"; w "$Y0"
gate "$S" 0 "$CF"; [ $RC -eq 0 ] && ok "⑤(f1) 재현 있음 뒤 새 수리 랜딩 → 구간 리셋 · 2판 통과" || bad "⑤(f1) rc=$RC $OUT"
mkstate "$S" '[]' "$MARK0" "$(obs "$A" '재현 있음' 1)" $'관찰 시작: 2026-10-11T01:00:00Z · 사유: 다시' "$(obs "$C" '재현 0' 2)" "$(obs "$D" '재현 0' 3)"
gate "$S" 0 "$CF"; [ $RC -eq 3 ] && ok "⑤(f2) 수리 랜딩 없는 마커 → 구간 불변(재현 있음 유지)" || bad "⑤(f2) rc=$RC $OUT"
mkstate "$S" '[]' "$MARK0" "$(obs "$A" '재현 있음' 1)" "$M1" "$(obs "$C" '재현 있음' 2)" "$M1" "$(obs "$C" '재현 0' 3)" "$(obs "$D" '재현 0' 4)"
gate "$S" 0 "$CF"; [ $RC -eq 3 ] && ok "⑤(f3) 같은 수리 sha 재게시 → 구간 불변" || bad "⑤(f3) rc=$RC $OUT"
M2="관찰 시작: 2026-10-11T02:00:00Z · 수리 랜딩=$C"
mkstate "$S" '[]' "$MARK0" "$(obs "$A" '재현 있음' 1)" "$M1" "$(obs "$A" '재현 있음' 2)" "$M2" "$(obs "$D" '재현 있음' 3)" "$M1" "$(obs "$A" '재현 0' 4)" "$(obs "$C" '재현 0' 5)"
gate "$S" 0 "$CF"; [ $RC -eq 3 ] && ok "⑤(f4) 옛 sha 재사용 → 구간 불변" || bad "⑤(f4) rc=$RC $OUT"
mkstate "$S" '[]' "$MARK0" "$(obs "$A" '재현 있음' 1)" "$M1" "$(obs "$C" '재현 0' 2)" "$M2" "$(obs "$D" '재현 0' 3)"
gate "$S" 0 "$CF"; [ $RC -eq 0 ] && ok "⑤(f5) 재현 없이 새 마커 → 구간 불변(앞 판도 센다)" || bad "⑤(f5) rc=$RC $OUT"
# ⑤(f6) 앞 구간 수리 C + 새 마커 수리=A(main 조상이지만 C 보다 오래됨) → 구간 불변(앞 수리의 후손 가드)
mkstate "$S" '[]' "$MARK0" "$(obs "$B" '재현 있음' 1)" "$M2" "$(obs "$D" '재현 있음' 2)" "관찰 시작: 2026-10-11T03:00:00Z · 수리 랜딩=$A" "$(obs "$B" '재현 0' 3)" "$(obs "$D" '재현 0' 4)"
gate "$S" 0 "$CF"; [ $RC -eq 3 ] && ok "⑤(f6) 앞 수리보다 오래된 sha 마커 → 구간 불변" || bad "⑤(f6) rc=$RC $OUT"
# ⑤(f7) 새 마커 수리=E(C 의 후손이지만 main 조상 아님 = 미랜딩 commit) → 구간 불변(랜딩 ref 조상 가드)
mkstate "$S" '[]' "$MARK0" "$(obs "$B" '재현 있음' 1)" "$M2" "$(obs "$D" '재현 있음' 2)" "관찰 시작: 2026-10-11T03:00:00Z · 수리 랜딩=$E" "$(obs "$B" '재현 0' 3)" "$(obs "$D" '재현 0' 4)"
gate "$S" 0 "$CF"; [ $RC -eq 3 ] && ok "⑤(f7) main 조상 아닌 sha 마커 → 구간 불변" || bad "⑤(f7) rc=$RC $OUT"
# ⑤(j) pending — 보존 성공 → 마커 실패 뒤 같은 입력·다른 입력(Y·0) 모두 rc 3 + 마커 1개 복구
mkstate "$S" '[]' "소유 오케=x"; w $'원인 확정: N — 원인 불명\n같은 증상 보류: 0'
FAKE_FAIL=comment-marker gate "$S" 1 "$CF"
gate "$S" 1 "$CF"; r1=$RC; c1="$(mcount "$S")"
mkstate "$S" '[]' "소유 오케=x"; FAKE_FAIL=comment-marker gate "$S" 1 "$CF"; w "$Y0"; gate "$S" 1 "$CF"
[ $r1 -eq 3 ] && [ "$c1" = 1 ] && [ $RC -eq 3 ] && [ "$(mcount "$S")" = 1 ] && ok "⑤(j) pending → 같은 입력·Y·0 모두 rc=3 · 마커 1개 복구" || bad "⑤(j) r1=$r1 c1=$c1 rc=$RC mark=$(mcount "$S")"
# ⑤(h) 라벨만·마커 0 → rc 3 + 마커 복구 쓰기
mkstate "$S" '[{"name":"status:observing"}]' "소유 오케=x"; w "$Y0"
gate "$S" 1 "$CF"
[ $RC -eq 3 ] && grep -q "「관찰 시작:」 줄 없음" <<<"$OUT" && [ "$(mcount "$S")" = 1 ] && ok "⑤(h) 라벨만 → rc=3 · 마커 복구" || bad "⑤(h) rc=$RC mark=$(mcount "$S") $OUT"
# ⑤(i) 관찰 해제 뒤 Y·0 → 통과
mkstate "$S" '[{"name":"status:observing"}]' "$MARK0" "관찰 해제: 판정=900"; w "$Y0"
gate "$S" 0 "$CF"; [ $RC -eq 0 ] && ok "⑤(i) 관찰 해제 뒤 Y·0 → 통과" || bad "⑤(i) rc=$RC $OUT"
# 관찰 중이면 Y·0 이어도 관찰 조건을 요구한다 (#922 교훈)
mkstate "$S" '[]' "$MARK0"; w "$Y0"; gate "$S" 0 "$CF"
[ $RC -eq 3 ] && ok "관찰 중 + Y·0 → 관찰 조건 요구(rc=3)" || bad "관찰 중 Y·0 rc=$RC $OUT"

# 조회 실패 → rc 2 · gh view 7초 + 재시도 1(호출 2회)
mkdir -p "$T/bin"; printf '#!/usr/bin/env bash\necho "gh $*" >> "$GH_LOG"; exit 1\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"
OUT="$(env -u FT_CLOSE_CHECK_FROM_JSON PATH="$T/bin:$PATH" GH_LOG="$T/gh.log" bash "$BIN/ft-issue-close-gate.sh" 9000 "$CF" 0 2>&1)"; RC=$?
[ $RC -eq 2 ] && [ "$(wc -l < "$T/gh.log" | tr -d ' ')" = 2 ] && ok "조회 실패 rc=2 · gh view 2회(재시도 1)" || bad "조회 실패 rc=$RC gh호출=$(wc -l < "$T/gh.log" 2>/dev/null) $OUT"

# ⑥ not-planned = 게이트 생략 (① 입력 그대로)
mkstate "$S" '[]' "소유 오케=x"; w "$SIX"
wrap close 9000 --comment "$CF" --reason not-planned
[ $RC -eq 0 ] && grep -q "DRY as=byz-tank gh issue close 9000" <<<"$OUT" && ok "⑥ not-planned → 게이트 생략 · DRY close" || bad "⑥ rc=$RC $OUT"

# 래퍼 1줄 · 줄 수 · 미러
[ "$(wc -l < "$BIN/ft-gh-as-tank.sh" | tr -d ' ')" = 200 ] && ok "ft-gh-as-tank.sh 200줄" || bad "ft-gh-as-tank.sh 줄 수 $(wc -l < "$BIN/ft-gh-as-tank.sh")"
for f in ft-issue-close-check.sh ft-issue-close-gate.sh ft-gh-as-tank.sh; do
  cmp -s "$BIN/$f" "$MIR/$f" && ok "미러 cmp 0: $f" || bad "미러 불일치: $f"
done

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
