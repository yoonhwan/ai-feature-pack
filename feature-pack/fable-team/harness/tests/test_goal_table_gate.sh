#!/usr/bin/env bash
# test_goal_table_gate.sh — R362 골 표(A6) 상시 게재 문: 렌더(ⓐⓑ) · 판정기 check(ⓗ) · 쪽지 가드 문 ③(ⓔⓕⓘⓙ).
# 가짜 정본·원장 파일(R371: 상태 출처 = planner 원장 «## 메인 골 6줄» 표) + 임시 폴더의 정본 mbox*.py·mbox*.sh 사본 + 격리 큐(FT_MBOX_DIR) — 실 큐·실 doorbell(tmux 스텁)·루트 .fable-team/ 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
TOOL="$REPO/harness/bin/ft-goal-table.sh"; SRC="$REPO/harness/comm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
teams_md() { mkdir -p "$1/design"; printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | x | 현역 |\n' > "$1/design/TEAMS.md"   # R382b: planner 폴더는 TEAMS.md 칸으로 풀린다
  # r479: 명단 = ref origin/main(체크아웃 파일 아님) — 그 폴더를 리포로 만들고 명단 커밋을 origin/main 에 둔다
  [ -d "$1/.git" ] || git -C "$1" init -q; git -C "$1" add design/TEAMS.md && git -C "$1" -c user.name=t -c user.email=t@t commit -qm teams && git -C "$1" update-ref refs/remotes/origin/main HEAD; }
CANON="$T/AUTONOMY-GOAL-A6.md"; LEDGER="$T/PLAN-oppa-ledger.md"
cat > "$CANON" <<'EOF'
# 자율 골 A6 (시험 픽스처 — 실 정본 표 6행 복사)

## 골 → 팀 → 닫는 증거

| 골(원문) | 담당 팀 | 닫는 증거 |
|---|---|---|
| v65 마이크 넘기기 완성 | v65 (byz-v65-master) | main 착지 sha(r3 841838491b) + 라이브 확인(기존 러너 --mic-pass) |
| m.room 멀티 사용자 v65 마이그레이션 + 게스트 대화 사용성 3명 이상 | room (byz-room-master) · 설계 v65 arch | main 착지 sha + 3명 겹쳐 말하기 --overlap 4자 표(+turbopack 칸) |
| m.lecture 멀티 사용자 v65 마이그레이션 + 게스트채팅 PiP · 번역 PiP 전부 | lecture (byz-lecture-master) | main 착지 sha(N5c #1854 · N6) + 강의방 라이브 확인 |
| 하네스팀 랜딩부터 | harness (byz-harness-master) | 남은 하네스 카드 main 착지 + 라이브 설치 cmp0(ft-live-install-check OK) |
| 전팀 지침과 프로젝트 폴더 기준 재기동 | harness(지침 파일 배치) · planner(팀별 확인) | 12팀 cwd 에서 ft-teamset-check ERROR 0 + 팀별 확인 1줄 |
| 메모리 세션 제한으로 안 멈춰 있게 완성 | harness(장치) · 각 팀장(끝난 좌석 닫기) | 정지 좌석 = 승인·차례 대기만(사유 1줄) · 자원 문지기 REJECT 로 멈춘 팀 0 |
EOF
SHA="$(shasum -a 256 "$CANON" | cut -c1-10)"
NOWSTAMP="$(python3 -c 'import datetime;print(datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))')"
mkledger() {  # <갱신 'YYYY-MM-DD HH:MM'> [행 수=6] [절 제목=기본] — planner 원장 모양: 골 글자는 정본과 다르다(순번 결속만) · 뒤쪽 절의 표는 읽히면 안 된다
  python3 - "$1" "${2:-6}" "${3:-## 메인 골 6줄 — 지금 상태 (오빠 원문 그대로)}" > "$LEDGER" <<'PY'
import sys
stamp, n, head = sys.argv[1], int(sys.argv[2]), sys.argv[3]
print("# 오빠 원장\n\n> 마지막 갱신: " + stamp + " · planner#68\n\n**결론**: 시험\n\n" + head + "\n")
print("| 골(오빠 원문) | 지금 상태 | 닫히려면 남은 것 |\n|---|---|---|")
for i in range(1, n + 1):
    st = "긴상태값이길다긴상태값이길다긴상태값이길다긴상태값" if i == 2 else f"상태{i} 진행"
    print(f"| 원장 글자 {i} | {st} | 남은{i} |")
print("\n## 다른 절\n\n| a | 읽히면 안 됨 | c |\n|---|---|---|\n| x | 새는상태 | z |")
PY
}
render() { FT_GOAL_A6_MD="${CANON_OVERRIDE:-$CANON}" FT_GOAL_A6_LEDGER="${LEDGER_OVERRIDE:-$LEDGER}" bash "$TOOL" "$@"; }
# check_body <본문> → RC·OUT
check_body() { OUT="$(printf '%s' "$1" | render check - 2>&1)"; RC=$?; }

# ── ⓐ 렌더: 머리·6행·꼬리·1600B·상태 칸(원장 2열 · 행 순번 결속)
mkledger "$NOWSTAMP"; BLOCK="$(render 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "ⓐ 렌더 rc0" || bad "ⓐ 렌더 rc=$RC :: $BLOCK"
printf '%s\n' "$BLOCK" | head -1 | grep -qxF "★골 표 A6 ($SHA · 원장:${NOWSTAMP:5})★" && ok "ⓐ 머리 마커 줄(원장:<갱신>)" || bad "ⓐ 머리 :: $(printf '%s' "$BLOCK" | head -1)"
printf '%s\n' "$BLOCK" | tail -1 | grep -qx '★/골 표★' && ok "ⓐ 꼬리 마커 줄" || bad "ⓐ 꼬리"
[ "$(printf '%s\n' "$BLOCK" | grep -c '^| .* | .* | .* | .* |$')" = 7 ] && ok "ⓐ 표 7줄(제목 1 + 골 6)" || bad "ⓐ 표 행 수"
printf '%s' "$BLOCK" | grep -q '상태3 진행' && ok "ⓐ 상태 칸 = 원장 2열 값(행 3)" || bad "ⓐ 상태 칸 값 없음"
printf '%s' "$BLOCK" | grep -qF '긴상태값이길다긴상태값이길다긴상태값이길다긴상태…' && ok "ⓐ 상태 칸 24자 + «…»" || bad "ⓐ 24자 축약"
printf '%s' "$BLOCK" | grep -q '원장 글자' && bad "ⓐ 원장 골 글자가 블록에 샘(정본 글자만)" || ok "ⓐ 골 칸은 정본 글자(원장 글자 0)"
printf '%s' "$BLOCK" | grep -q '새는상태' && bad "ⓐ 뒤쪽 절 표가 읽힘" || ok "ⓐ 첫 표만 읽음(뒤쪽 절 표 0)"
[ "$RC" = 0 ] && [ "$(printf '%s\n' "$BLOCK" | wc -c)" -gt 100 ] && [ "$(printf '%s\n' "$BLOCK" | wc -c)" -le 1600 ] && ok "ⓐ ≤1600B" || bad "ⓐ $(printf '%s\n' "$BLOCK" | wc -c)B"
OUT="$(LEDGER_OVERRIDE="$T/없는원장.md" render 2>"$T/err")"; RC=$?
[ "$RC" = 0 ] && [ "$(printf '%s' "$OUT" | grep -o '상태 없음' | wc -l)" -ge 6 ] && [ "$(grep -c '^WARN 골 표 원장' "$T/err")" = 1 ] && ok "ⓐ 원장 파일 없음 = «상태 없음» 6칸 + WARN 1줄 rc0" || bad "ⓐ 원장 없음 rc=$RC :: $OUT :: $(cat "$T/err")"

# ── ⓑ 정본 이상 = ERROR rc1 (조용한 빈 표 0)
OUT="$(CANON_OVERRIDE="$T/없는정본.md" render 2>&1)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 정본'*) true;; *) false;; esac && ok "ⓑ 정본 없음 ERROR rc1" || bad "ⓑ 정본 없음 rc=$RC :: $OUT"
grep -v 'harness(장치)' "$CANON" > "$T/canon5.md"
OUT="$(CANON_OVERRIDE="$T/canon5.md" render 2>&1)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 정본'*) true;; *) false;; esac && ok "ⓑ 표 5행 ERROR rc1" || bad "ⓑ 5행 rc=$RC :: $OUT"

# ── ⓑ 원장 행 수 ≠ 6 = ERROR rc1 (조용한 «상태 없음» 0)
for n in 5 7; do
  mkledger "$NOWSTAMP" "$n"; OUT="$(render 2>&1)"; RC=$?
  [ "$RC" = 1 ] && case "$OUT" in *"ERROR 골 표 원장 행 수 ${n}≠6"*) true;; *) false;; esac && ok "ⓑ 원장 표 ${n}행 ERROR rc1" || bad "ⓑ 원장 ${n}행 rc=$RC :: $OUT"
done

# ── ⓒ 원장에 절 없음 = 6칸 «상태 없음» + stderr WARN 1줄 · rc0 (발행은 된다)
mkledger "$NOWSTAMP" 6 "## 엉뚱한 절"; OUT="$(render 2>"$T/err")"; RC=$?
[ "$RC" = 0 ] && [ "$(printf '%s' "$OUT" | grep -o '상태 없음' | wc -l)" -ge 6 ] && [ "$(grep -c '^WARN 골 표 원장' "$T/err")" = 1 ] && ok "ⓒ 절 없음 = «상태 없음» 6칸 + WARN 1줄 rc0" || bad "ⓒ 절 없음 rc=$RC :: $OUT :: $(cat "$T/err")"

# ── ⓓ gitref 출처 = 파일과 같은 결과
mkledger "$NOWSTAMP"; FILE_OUT="$(render 2>&1)"
GR="$T/gitrepo"; mkdir -p "$GR/design/planner"; cp "$LEDGER" "$GR/design/planner/PLAN-oppa-ledger.md"
git -C "$GR" init -q && git -C "$GR" add -A && git -C "$GR" -c user.name=t -c user.email=t@t commit -qm l
OUT="$(FT_GOAL_REPO="$GR" LEDGER_OVERRIDE="gitref:HEAD:design/planner/PLAN-oppa-ledger.md" render 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ "$OUT" = "$FILE_OUT" ] && ok "ⓓ gitref 원장 = 파일 원장과 같은 블록" || bad "ⓓ gitref rc=$RC :: $OUT"

# ── ⓔ 원장 «마지막 갱신» 24h 초과 = 머리 «상태 낡음»
mkledger "2020-01-01 10:30"; STALE="$(render 2>&1)"; RC=$?
[ "$RC" = 0 ] && printf '%s\n' "$STALE" | head -1 | grep -q '상태 낡음' && printf '%s\n' "$STALE" | head -1 | grep -q '원장:01-01 10:30' && ok "ⓔ 24h 초과 머리에 «상태 낡음» + 원장:<갱신>" || bad "ⓔ 낡음 rc=$RC :: $(printf '%s' "$STALE" | head -1)"
printf '%s\n' "$FILE_OUT" | head -1 | grep -q '상태 낡음' && bad "ⓔ 신선한 원장이 낡음으로 찍힘" || ok "ⓔ 신선한 원장은 «상태 낡음» 0"

# ── ⓕ check 불변 — 상태 칸·낡음이 바뀌어도 check rc 동일
check_body "$STALE"$'\n골좌표: 3 — m.lecture 멀티'; R1=$RC
check_body "$FILE_OUT"$'\n골좌표: 3 — m.lecture 멀티'; R2=$RC
[ "$R1" = 0 ] && [ "$R2" = 0 ] && ok "ⓕ 상태칸·낡음 달라도 check rc 동일(0)" || bad "ⓕ check rc $R1/$R2"

# ── ⓜ DA⑥ r1 H1 — 표 셀 `\|` 복원 · 열 수 검증 · 빈 셀 구분 (표본 3)
mkledger "$NOWSTAMP"; sed -i.bak -e 's/^| 원장 글자 3 | 상태3 진행 |/| 원장 글자 3 \\| 골 | 상태3 진행\\|검증 |/' -e 's/| 남은4 |$/| 남은\\|4 |/' "$LEDGER"; rm -f "$LEDGER.bak"
OUT="$(render 2>&1)"; RC=$?
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qF '상태3 진행/검증' && ! printf '%s' "$OUT" | grep -qE '상태3 진행/?\|? *\|' && ok "ⓜ1 상태 셀 `진행\|검증` → 전체 보존(절단 0) · 골·남은것 칸의 `\|` 도 열 수 유지" || bad "ⓜ1 이스케이프 rc=$RC :: $OUT"
mkledger "$NOWSTAMP"; sed -i.bak 's/^| 원장 글자 4 | 상태4 진행 | 남은4 |$/| 원장 글자 4 | 상태4 진행 |/' "$LEDGER"; rm -f "$LEDGER.bak"
OUT="$(render 2>&1)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 원장 열 수 2≠3'*) true;; *) false;; esac && ok "ⓜ2 열 수 부족 ERROR rc1(행 수 6 이어도)" || bad "ⓜ2 부족 rc=$RC :: $OUT"
mkledger "$NOWSTAMP"; sed -i.bak 's/^| 원장 글자 4 | 상태4 진행 | 남은4 |$/| 원장 글자 4 | 상태4 진행|검증 | 남은4 |/' "$LEDGER"; rm -f "$LEDGER.bak"
OUT="$(render 2>&1)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 원장 열 수 4≠3'*) true;; *) false;; esac && ok "ⓜ2 열 수 초과(이스케이프 없는 |) ERROR rc1" || bad "ⓜ2 초과 rc=$RC :: $OUT"
mkledger "$NOWSTAMP"; sed -i.bak 's/^| 원장 글자 5 | 상태5 진행 | 남은5 |$/| 원장 글자 5 |  | 남은5 |/' "$LEDGER"; rm -f "$LEDGER.bak"
OUT="$(render 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ "$(printf '%s' "$OUT" | grep -o '상태 없음' | wc -l | tr -d ' ')" = 1 ] && printf '%s' "$OUT" | grep -q '상태6 진행' && ok "ⓜ3 진짜 빈 셀 = 그 행만 «상태 없음»(나머지 행 보존)" || bad "ⓜ3 빈 셀 rc=$RC :: $OUT"

# ── ⓝ DA⑥ r1 H2 + R382 — 기본 출처 = `.fable-team/LIVE_ROOT` 파일 1행(코드 위치 LIVE_BIN/../.. 유도 폐지) → 그 폴더의 원장 · 옛 v6 원장·고정 접미사 후퇴 0 (표본 2)
mkledger "$NOWSTAMP"; BASE="$LEDGER"
LR="$(mktemp -d "$T/lr.XXXXXX")"; mkdir -p "$LR/live/.fable-team/bin" "$LR/live/design/planner" "$LR/root/.fable-team" "$LR/root/.worktrees/v6-realtime-live/design/planner"
teams_md "$LR/live"; sed 's/상태\([0-9]\) 진행/NEW\1 진행/' "$BASE" > "$LR/live/design/planner/PLAN-oppa-ledger.md"
sed 's/상태\([0-9]\) 진행/OLD\1 진행/' "$BASE" > "$LR/root/.worktrees/v6-realtime-live/design/planner/PLAN-oppa-ledger.md"
default_render() { env -u FT_GOAL_A6_LEDGER FT_ROOT="$LR/root" FT_GOAL_A6_MD="$CANON" python3 "$REPO/harness/bin/ft_goal_table.py" 2>&1; }
printf '%s\n' "$LR/live/.fable-team/bin" > "$LR/root/.fable-team/LIVE_BIN"; printf '%s\n' "$LR/live" > "$LR/root/.fable-team/LIVE_ROOT"
OUT="$(default_render)"; RC=$?
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'NEW3 진행' && ! printf '%s' "$OUT" | grep -q 'OLD' && ok "ⓝ1 LIVE_ROOT 파일 → 새 LIVE 원장만(옛 v6 원장 OLD 0)" || bad "ⓝ1 두 루트 rc=$RC :: $OUT"
mkdir -p "$LR/elsewhere/bin"; printf '%s\n' "$LR/elsewhere/bin" > "$LR/root/.fable-team/LIVE_BIN"; OUT="$(default_render)"; RC=$?
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'NEW3 진행' && ! printf '%s' "$OUT" | grep -q 'OLD' && ok "ⓓ LIVE_BIN 위치를 바꿔도 같은 원장(코드 위치 유도 0)" || bad "ⓓ LIVE_BIN 이동 rc=$RC :: $OUT"
rm -f "$LR/root/.fable-team/LIVE_ROOT"; OUT="$(default_render)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 기본 출처: LIVE_ROOT 이 없거나 무효'*) true;; *) false;; esac && ! printf '%s' "$OUT" | grep -q 'OLD' && ok "ⓝ2 LIVE_ROOT 없음 = ERROR rc1(LIVE_BIN 에서 유도 0 · 옛 원장 선택 0)" || bad "ⓝ2 LIVE_ROOT 없음 rc=$RC :: $OUT"
printf '%s\n' "$LR/없는폴더" > "$LR/root/.fable-team/LIVE_ROOT"; OUT="$(default_render)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'LIVE_ROOT 이 없거나 무효'*) true;; *) false;; esac && ok "ⓝ2 LIVE_ROOT 값 무효(없는 폴더) = ERROR rc1" || bad "ⓝ2 무효 rc=$RC :: $OUT"
printf 'live\n' > "$LR/root/.fable-team/LIVE_ROOT"; OUT="$(default_render)"; RC=$?
[ "$RC" = 1 ] && ok "ⓝ2 LIVE_ROOT 상대경로 = ERROR rc1" || bad "ⓝ2 상대 rc=$RC :: $OUT"
printf '%s\n' "$LR/live" > "$LR/root/.fable-team/LIVE_ROOT"; OUT="$(FT_GOAL_A6_LEDGER="$BASE" FT_ROOT="$LR/root" FT_GOAL_A6_MD="$CANON" python3 "$REPO/harness/bin/ft_goal_table.py" 2>&1)"
printf '%s' "$OUT" | grep -q '상태3 진행' && ok "ⓝ FT_GOAL_A6_LEDGER 가 LIVE_ROOT 보다 우선" || bad "ⓝ env 우선 :: $OUT"
mkledger "$NOWSTAMP"

# ── ⓣ arch 재현 r3 — 설치본 위치 FT_ROOT 없음(조상 탐색) · FT_ROOT=LIVE_BIN 없는 폴더 · LIVE_BIN 삭제 = 정본·원장 둘 다 ERROR(고정 v6 경로 0) (표본 3)
mkledger "$NOWSTAMP"
TR="$(mktemp -d "$T/tr.XXXXXX")"; LV="$TR/.worktrees/live"; mkdir -p "$LV/.fable-team/bin" "$LV/design/planner" "$TR/.fable-team" "$TR/.worktrees/v6-realtime-live/design/planner"
cp "$REPO/harness/bin/ft_goal_table.py" "$REPO/harness/bin/ft_goal_ledger.py" "$REPO/harness/bin/ft_team_lib.py" "$LV/.fable-team/bin/"; teams_md "$LV"
cp "$CANON" "$LV/design/planner/AUTONOMY-GOAL-A6-20261018.md"; cp "$CANON" "$TR/.worktrees/v6-realtime-live/design/planner/AUTONOMY-GOAL-A6-20261018.md"
sed 's/상태\([0-9]\) 진행/NEW\1 진행/' "$LEDGER" > "$LV/design/planner/PLAN-oppa-ledger.md"; sed 's/상태\([0-9]\) 진행/OLD\1 진행/' "$LEDGER" > "$TR/.worktrees/v6-realtime-live/design/planner/PLAN-oppa-ledger.md"
printf '%s\n' "$LV/.fable-team/bin" > "$TR/.fable-team/LIVE_BIN"; printf '%s\n' "$LV" > "$TR/.fable-team/LIVE_ROOT"
inst_render() { env -u FT_ROOT -u FT_GOAL_A6_MD -u FT_GOAL_A6_LEDGER "$@" python3 "$LV/.fable-team/bin/ft_goal_table.py" 2>&1; }
OUT="$(inst_render)"; RC=$?
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'NEW3 진행' && ! printf '%s' "$OUT" | grep -q 'OLD' && [ "$(printf '%s' "$OUT" | grep -c '^| .* | .* | .* | .* |$')" = 7 ] && ok "ⓣ1 설치본 위치 + FT_ROOT 없음 → 조상 탐색으로 정본·원장 기본 경로 해석 · 6칸 채움(OLD 0)" || bad "ⓣ1 설치본 rc=$RC :: $OUT"
OUT="$(inst_render FT_ROOT="$LV")"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *"$LV/.fable-team/LIVE_BIN"*) true;; *) false;; esac && ok "ⓣ2 FT_ROOT=LIVE_BIN 없는 폴더 → ERROR 사유에 그 경로" || bad "ⓣ2 FT_ROOT rc=$RC :: $OUT"
rm -f "$TR/.fable-team/LIVE_BIN" "$TR/.fable-team/LIVE_ROOT"; OUT="$(inst_render)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'LIVE_BIN 이 없거나 무효'*) true;; *) false;; esac && ! printf '%s' "$OUT" | grep -q 'OLD' && ok "ⓣ3 LIVE_BIN 삭제 → ERROR(정본·원장 둘 다 고정 v6 경로 0)" || bad "ⓣ3 LIVE_BIN 삭제 rc=$RC :: $OUT"
OUT="$(env -u FT_ROOT -u FT_GOAL_A6_LEDGER FT_GOAL_A6_MD="$CANON" python3 "$LV/.fable-team/bin/ft_goal_table.py" 2>&1)"; RC=$?
[ "$RC" = 1 ] && ok "ⓣ3 정본만 env 로 줘도 원장 기본 경로는 LIVE_BIN 없으면 ERROR" || bad "ⓣ3 원장 :: rc=$RC $OUT"
mkledger "$NOWSTAMP"

# ── 후퇴 0 — 옛 상태 파일 출처 문자열이 코드·도구에 없다
if grep -rnE 'FT_GOAL_A6_STATE|GOAL-A6-STATE|--state' "$REPO/harness/bin"/ft_goal*.py "$TOOL" >/dev/null 2>&1; then bad "후퇴 0: 옛 상태 파일 출처가 남음"; else ok "후퇴 0: FT_GOAL_A6_STATE·GOAL-A6-STATE·--state 참조 0"; fi
mkledger "$NOWSTAMP"

# ── ⓗ check 단독
GOOD="$BLOCK"$'\n골좌표: 3 — m.lecture 멀티'
check_body "$GOOD";                                    [ "$RC" = 0 ] && case "$OUT" in *'GOAL-OK n=3'*) true;; *) false;; esac && ok "ⓗ 블록+좌표 → GOAL-OK n=3" || bad "ⓗ 정상 rc=$RC :: $OUT"
check_body "$BLOCK";                                   [ "$RC" = 3 ] && case "$OUT" in *'REJECT 골 없음'*) true;; *) false;; esac && ok "ⓗ 블록만 → REJECT" || bad "ⓗ 블록만 rc=$RC :: $OUT"
check_body $'골좌표: 3 — m.lecture 멀티';               [ "$RC" = 3 ] && ok "ⓗ 좌표만(블록 없음) → REJECT" || bad "ⓗ 좌표만 rc=$RC :: $OUT"
check_body "$BLOCK"$'\n골좌표: 7 — m.lecture 멀티';     [ "$RC" = 3 ] && ok "ⓗ 번호 7(범위 밖) → REJECT" || bad "ⓗ 번호 7 rc=$RC :: $OUT"
check_body "$BLOCK"$'\n골좌표: 3 — 하네스팀 랜딩부터';   [ "$RC" = 3 ] && ok "ⓗ 번호와 원문 불일치 → REJECT" || bad "ⓗ 불일치 rc=$RC :: $OUT"
check_body "$BLOCK"$'\n골좌표: 3';                      [ "$RC" = 3 ] && ok "ⓗ 번호만(원문 없음) → REJECT" || bad "ⓗ 번호만 rc=$RC :: $OUT"
check_body $'★골 표 A6 (abcdef0123 · 상태 10:30)★\n| 골 | 팀 | 지금 상태 | 닫는 증거 |\n| a | b | c | d |\n★/골 표★\n골좌표: 3 — m.lecture 멀티'
[ "$RC" = 3 ] && ok "ⓗ 블록 안 행 6 아님 → REJECT" || bad "ⓗ 행 수 rc=$RC :: $OUT"
check_body $'★/골 표★\n골좌표: 3 — m.lecture 멀티'; [ "$RC" = 3 ] && ok "ⓕ 꼬리 마커만 → REJECT" || bad "ⓕ 꼬리만 rc=$RC :: $OUT"

# ── 쪽지 가드 문 ③ — 격리 루트
new_env() {
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; mkdir -p "$ENVROOT/.fable-team/comm" "$ENVROOT/.fable-team/state" "$ENVROOT/.fable-team/bin" "$ENVROOT/seats"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$ENVROOT/.fable-team/comm/"; cp "$TOOL" "$(dirname "$TOOL")/ft_goal_table.py" "$(dirname "$TOOL")/ft_goal_ledger.py" "$(dirname "$TOOL")/ft_team_lib.py" "$ENVROOT/.fable-team/bin/" 2>/dev/null; git -C "$ENVROOT" init -q
  echo '{"_master":"byz-planner-master-claude#9","_desk":"byz-planner-desk-claude#3","_arch":"byz-planner-arch-claude#4"}' > "$ENVROOT/seats/seats-planner.json"
  echo '{"_master":"byz-harness-master-claude#64","_arch":"byz-harness-arch-claude#81","byz-harness-nano-x#0":{"role":"nano"}}' > "$ENVROOT/seats/seats-harness.json"
  echo '{}' > "$ENVROOT/seats/seats.json"; [ "${UNARMED:-0}" = 1 ] || : > "$ENVROOT/.fable-team/state/goal-gate.armed"
}
send_from() {  # <from> <body> → RC·OUT (수신자 = 명부에 없는 나노 → 수신자 문·planner 머리 문 둘 다 비켜 간다)
  OUT="$(cd "$ENVROOT" && env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_GOAL_A6_MD="$CANON" FT_GOAL_A6_LEDGER="$LEDGER" \
    FT_MBOX_DIR="$ENVROOT/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
    bash "$ENVROOT/.fable-team/comm/mbox.sh" send 'byz-zz-nano-q#0' "$1" "$2" 2>&1)"; RC=$?
}
queued() { local n; n="$(grep -c '"to": *"byz-zz-nano-q#0"' "$ENVROOT/.fable-team/comm/mailbox.jsonl" 2>/dev/null)"; echo "${n:-0}"; }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
PM='byz-planner-master-claude#9'; HM='byz-harness-master-claude#64'; HN='byz-harness-nano-x#0'
WITH="$BLOCK"$'\n골좌표: 4 — 하네스팀 랜딩부터'

# ⓔ planner 팀 발주 머리 4종 — 블록 없으면 REJECT·큐 0, 블록+좌표면 통과
for h in '[발주 #1]' '[팀 발주]' '[착지 차례]' '[A6 점검]'; do
  new_env; send_from "$PM" "$h 해라"$'\n본문'
  [ "$RC" = 3 ] && case "$OUT" in *'골 없음'*'ft-goal-table.sh'*) true;; *) false;; esac && [ "$(queued)" = 0 ] && ok "ⓔ $h 블록 없음 → REJECT·큐 0" || bad "ⓔ $h rc=$RC q=$(queued) :: $OUT"
  new_env; send_from "$PM" "$h 해라"$'\n'"$WITH"
  [ "$RC" = 0 ] && [ "$(queued)" = 1 ] && ok "ⓔ $h 블록+좌표 → 통과" || bad "ⓔ $h 통과 rc=$RC :: $OUT"
done
# ⓔ 안전 보고는 검사 밖
for h in '[HIL] 막힘' '[긴급] 중단' '[반송 · 골] 다시'; do
  new_env; send_from "$PM" "$h"$'\n본문'
  [ "$RC" = 0 ] && ok "ⓙ $h 블록 없음 → 통과(안전 보고 우선)" || bad "ⓙ $h rc=$RC :: $OUT"
done

# ⓘ 다른 팀 master — 틱·부팅도 검사 · 나노 발신은 검사 0
for h in '[틱]' '[부팅 보고]' '[완료·휴식]'; do
  new_env; send_from "$HM" "$h 보고"$'\n세션=x'
  [ "$RC" = 3 ] && case "$OUT" in *'골 없음'*) true;; *) false;; esac && ok "ⓘ harness master $h 블록 없음 → REJECT" || bad "ⓘ master $h rc=$RC :: $OUT"
done
new_env; send_from "$HN" $'[틱] 보고\n본문'
[ "$RC" = 0 ] && ok "ⓘ 나노 발신 [틱] 블록 없음 → 통과(검사 0)" || bad "ⓘ 나노 rc=$RC :: $OUT"
new_env; send_from 'byz-planner-desk-claude#3' $'[발주] x\n본문'
[ "$RC" = 3 ] && ok "ⓘ planner desk 도 대상" || bad "ⓘ desk rc=$RC :: $OUT"
new_env; send_from "$PM" "[발주 #1] 골좌표 줄 없음"$'\n'"$BLOCK"
[ "$RC" = 3 ] && ok "ⓔ 블록만(좌표 줄 없음) 발주 → REJECT" || bad "ⓔ 블록만 rc=$RC :: $OUT"

# ⓚ 실물 정본(1274B 표) — 골 원문 전문 보존 + ≤1600B
REAL="$REPO/tests/fixtures/goal_table/AUTONOMY-GOAL-A6-20261018.md"
OUT="$(CANON_OVERRIDE="$REAL" LEDGER_OVERRIDE="$T/없음.md" render 2>/dev/null)"; RC=$?
[ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | wc -c)" -le 1600 ] && ok "ⓚ 실물 정본 ≤1600B" || bad "ⓚ rc=$RC $(printf '%s\n' "$OUT" | wc -c)B :: $OUT"
full=0; while IFS= read -r g; do printf '%s' "$OUT" | grep -qF "$g" || full=1; done < <(python3 -c 'import sys;[print(l.split("|")[1].strip()) for l in open(sys.argv[1],encoding="utf-8") if l.startswith("| ") and not l.startswith("| 골(")]' "$REAL")
[ "$full" = 0 ] && ok "ⓚ 골 원문 6칸 전문 보존(절단 0)" || bad "ⓚ 골 원문 절단"

# ⓛ 비무장 = WOULD-REJECT 로그 + 통과 · 무장 = REJECT 로그
UNARMED=1 new_env; send_from "$PM" $'[발주 #1] 블록 없음\n본문'
[ "$RC" = 0 ] && [ "$(queued)" = 1 ] && grep -q 'WOULD-REJECT' "$ENVROOT/.fable-team/state/mbox-guard-goal.log" && ok "ⓛ 비무장: 큐 적재 + WOULD-REJECT 로그" || bad "ⓛ 비무장 rc=$RC :: $OUT"
new_env; send_from "$PM" $'[발주 #1] 블록 없음\n본문'
grep -q '^[^ ]* REJECT from=' "$ENVROOT/.fable-team/state/mbox-guard-goal.log" && ok "ⓛ 무장: REJECT 로그 1줄" || bad "ⓛ 무장 로그 없음"

# ⓝ relay — 첨부 사본을 검사하고 그 사본이 그대로 relay 된다
relay_from() {  # <from> <첨부 파일> <요약> → RC·OUT
  OUT="$(cd "$ENVROOT" && env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_GOAL_A6_MD="$CANON" FT_GOAL_A6_LEDGER="$LEDGER" \
    FT_MBOX_DIR="$ENVROOT/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
    bash "$ENVROOT/.fable-team/comm/mbox.sh" relay 'byz-zz-nano-q#0' "$1" "$2" "$3" 2>&1)"; RC=$?
}
printf '%s\n본문\n' "$BLOCK" > "$T/attach-ok.md"; printf '본문만\n' > "$T/attach-no.md"
SUM=$'[발주 #2] 긴 발주\n골좌표: 4 — 하네스팀 랜딩부터'
new_env; relay_from "$PM" "$T/attach-ok.md" "$SUM"
[ "$RC" = 0 ] && [ "$(queued)" = 1 ] && ok "ⓝ relay 첨부에 블록 + 요약에 좌표 → 통과" || bad "ⓝ relay 통과 rc=$RC :: $OUT"
new_env; relay_from "$PM" "$T/attach-no.md" "$SUM"
[ "$RC" = 3 ] && [ "$(queued)" = 0 ] && ok "ⓝ relay 첨부에 블록 없음 → REJECT·큐 0" || bad "ⓝ relay 거절 rc=$RC :: $OUT"
ls "$ENVROOT/.fable-team/state/" | grep -q '^goal-relay' && bad "ⓝ relay 검사 사본 폴더 잔존" || ok "ⓝ relay 검사 사본 폴더 정리"

# ⓞ 머리 [회신·착지·정지] = 대상 밖(집행 회신·안전 보고)
for h in '[회신] 확인' '[착지] 끝' '[정지] 멈춤'; do
  new_env; send_from "$PM" "$h"$'\n본문'
  [ "$RC" = 0 ] && ok "ⓞ $h 블록 없음 → 통과" || bad "ⓞ $h rc=$RC :: $OUT"
done

# ⓟ 마커 sha10 ≠ 본문 6행 · 모르는 sha10 → REJECT
check_body "$(printf '%s' "$BLOCK" | sed 's/^| v65 마이크 넘기기 완성/| 바꾼 골 원문/')"$'\n골좌표: 3 — m.lecture 멀티'
[ "$RC" = 3 ] && ok "ⓟ 정본과 다른 6행 + 진짜 마커 → REJECT" || bad "ⓟ 변조 rc=$RC :: $OUT"
check_body "$(printf '%s' "$BLOCK" | sed "1s/($SHA/(ffffffffff/")"$'\n골좌표: 3 — m.lecture 멀티'
[ "$RC" = 3 ] && ok "ⓟ 모르는 마커 sha10 → REJECT" || bad "ⓟ sha rc=$RC :: $OUT"

# ⓠ H1① 문 본체 파일 없음 — 무장 = REJECT · 비무장 = WOULD-REJECT 로그 + 통과 · 비대상(나노·안전 보고)은 통과
new_env; rm -f "$ENVROOT/.fable-team/comm/mbox_guard_goal.sh"; send_from "$PM" $'[발주 #1] 본문 파일 없음\n본문'
[ "$RC" = 3 ] && [ "$(queued)" = 0 ] && case "$OUT" in *'문 파일 없음'*) true;; *) false;; esac && ok "ⓠ 무장 + 문 본체 없음 → REJECT" || bad "ⓠ 무장 rc=$RC :: $OUT"
UNARMED=1 new_env; rm -f "$ENVROOT/.fable-team/comm/mbox_guard_goal.sh"; send_from "$PM" $'[발주 #1] 본문 파일 없음\n본문'
[ "$RC" = 0 ] && [ "$(queued)" = 1 ] && grep -q 'WOULD-REJECT' "$ENVROOT/.fable-team/state/mbox-guard-goal.log" && ok "ⓠ 비무장 + 문 본체 없음 → WOULD-REJECT 로그 + 통과" || bad "ⓠ 비무장 rc=$RC :: $OUT"
new_env; rm -f "$ENVROOT/.fable-team/comm/mbox_guard_goal.sh"; send_from "$HN" $'[틱] 나노\n본문'
[ "$RC" = 0 ] && ok "ⓠ 문 본체 없음 + 나노 발신 → 통과(대상 아님)" || bad "ⓠ 나노 rc=$RC :: $OUT"
new_env; rm -f "$ENVROOT/.fable-team/comm/mbox_guard_goal.sh"; send_from "$PM" $'[HIL] 막힘\n본문'
[ "$RC" = 0 ] && ok "ⓠ 문 본체 없음 + [HIL] → 통과(안전 보고)" || bad "ⓠ HIL rc=$RC :: $OUT"

# ⓡ H1② 명부 읽기 실패 — «대상 아님» 과 분리: 무장 = REJECT(판정 불가) · 비무장 = WOULD-REJECT · 다른 명부에서 역할이 확인되면 정상 판정
new_env; echo '{' > "$ENVROOT/seats/seats-harness.json"; send_from "$HM" $'[틱] 보고\n본문'
[ "$RC" = 3 ] && case "$OUT" in *'판정 불가'*) true;; *) false;; esac && ok "ⓡ 무장 + 명부 깨짐 + 역할 미확인 → REJECT(판정 불가)" || bad "ⓡ 무장 rc=$RC :: $OUT"
UNARMED=1 new_env; echo '{' > "$ENVROOT/seats/seats-harness.json"; send_from "$HM" $'[틱] 보고\n본문'
[ "$RC" = 0 ] && grep -q 'WOULD-REJECT.*판정 불가' "$ENVROOT/.fable-team/state/mbox-guard-goal.log" && ok "ⓡ 비무장 + 명부 깨짐 → WOULD-REJECT 로그 + 통과" || bad "ⓡ 비무장 rc=$RC :: $OUT"
new_env; echo '{' > "$ENVROOT/seats/seats-harness.json"; send_from "$PM" "[발주 #1] 정상"$'\n'"$WITH"
[ "$RC" = 0 ] && ok "ⓡ 다른 명부가 깨져도 발신자 역할이 확인되면 정상 판정" || bad "ⓡ 정상 rc=$RC :: $OUT"

# ⓢ H2 relay 사본 — 복사 실패 = REJECT · 검사 뒤 원본 변경 = 사본 전달 · 요약에 골좌표 없음 = REJECT(첨부 안 좌표는 요약 대신이 아니다)
printf '%s\n본문\n' "$BLOCK" > "$T/att-unreadable.md"; chmod 000 "$T/att-unreadable.md"
new_env; relay_from "$PM" "$T/att-unreadable.md" "$SUM"
[ "$RC" = 3 ] && [ "$(queued)" = 0 ] && case "$OUT" in *'사본 생성·읽기 실패'*) true;; *) false;; esac && ok "ⓢ 첨부 사본 복사 실패 → REJECT(원본 후퇴 0)" || bad "ⓢ 복사 실패 rc=$RC :: $OUT"
chmod 644 "$T/att-unreadable.md"
printf '%s\n본문\n' "$BLOCK" > "$T/att-tamper.md"
new_env; printf '#!/usr/bin/env bash\n[ "$1" = check ] && echo TAMPER >> "%s"\nexec bash "%s" "$@"\n' "$T/att-tamper.md" "$TOOL" > "$ENVROOT/.fable-team/bin/ft-goal-table.sh"
relay_from "$PM" "$T/att-tamper.md" "$SUM"
SNAP="$(python3 -c 'import json,re,sys;l=[json.loads(x) for x in open(sys.argv[1],encoding="utf-8") if x.strip()][-1];print(re.search(r"상세\(전문\): (\S+)",l["body"]).group(1))' "$ENVROOT/.fable-team/comm/mailbox.jsonl" 2>/dev/null)"
[ "$RC" = 0 ] && grep -q TAMPER "$T/att-tamper.md" && [ -n "$SNAP" ] && ! grep -q TAMPER "$SNAP" && ok "ⓢ 검사 뒤 원본이 바뀌어도 전달본 = 검사한 사본" || bad "ⓢ 사본 전달 rc=$RC snap=$SNAP :: $OUT"
printf '%s\n골좌표: 4 — 하네스팀 랜딩부터\n본문\n' "$BLOCK" > "$T/att-coord.md"
new_env; relay_from "$PM" "$T/att-coord.md" $'[발주 #3] 요약만 — 좌표 줄 없음'
[ "$RC" = 3 ] && [ "$(queued)" = 0 ] && ok "ⓢ 요약에 골좌표 없음(첨부 안에만 있음) → REJECT" || bad "ⓢ 요약 좌표 rc=$RC :: $OUT"

# ══ R458 — 뉴스 폴더·원장 sha·경로 = 원장 리포 1곳 · 팀별 완성 진행 블록(뉴스 첫 판·매거진) · 거절 게이트 0
NR="$T/r458"; NROOT="$NR/root"; NREPO="$NR/ledger"; mkdir -p "$NROOT/.fable-team/state/news-ledger" "$NROOT/design/planner/news" "$NREPO/design/planner"   # 루트 = TEAMS.md 없음(로컬 main 이 뒤처진 공용 루트 재현)
teams_md "$NREPO"; mkledger "$NOWSTAMP"; TLED="$NR/ledger-teams.md"
{ cat "$LEDGER"; printf '\n## 팀별 완성 진행\n\n| 팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것 |\n|---|---|---|---|\n'
  for i in 0 1 2 3 4 5 6 7 8 9 10 11; do printf '| team%s | %s/6 | abcdef%04d | 지금하는일%s 길게길게길게길게길게길게길게길게 |\n' "$i" "$((i % 7))" "$i" "$i"; done; } > "$TLED"
cp "$TLED" "$NREPO/design/planner/PLAN-oppa-ledger.md"; git -C "$NREPO" init -q && git -C "$NREPO" add -A && git -C "$NREPO" -c user.name=t -c user.email=t@t commit -qm base
BASE_SHA="$(git -C "$NREPO" rev-parse HEAD)"; printf '\n## 3. 팀 작업\n\n- 새 줄 r458\n' >> "$NREPO/design/planner/PLAN-oppa-ledger.md"; git -C "$NREPO" -c user.name=t -c user.email=t@t commit -qam cur
news_run() {  # [env…] → OUT(ERROR 로그·news=·parts) · RC — 발행 도구·알림·요약 송신은 시험 대역(실 슬랙·실 mbox 0)
  OUT="$(env -u FT_NEWS_DIR -u FT_LEDGER_PATH FT_ROOT="$NROOT" FT_LEDGER_REPO="$NREPO" FT_LEDGER_SYNCED=1 FT_NEWS_STATUS_INTERVAL=0 FT_NEWS_NOW="2026-10-19 18:00" FT_GOAL_A6_MD="$CANON" FT_GOAL_A6_LEDGER="$TLED" "$@" python3 - "$REPO/harness/bin" "$NROOT" <<'PY' 2>&1
import logging, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1]); logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
import ft_news_ledger as nl
def fake(news, state, parts, now, cur):
    print(f"news={news}"); [print(f"===PART {i}\n{p}") for i, p in enumerate(parts, 1)]
    return 0, [None] * len(parts)
nl.publish, nl.maybe_send, nl.notify = fake, lambda *a, **k: None, lambda *a, **k: None
state = Path(sys.argv[2]) / ".fable-team/state/news-ledger"
rc, why = nl._run(Path(sys.argv[2]), state); print(f"rc={rc} why={why}"); raise SystemExit(rc)
PY
)"; RC=$?; }
part1() { printf '%s\n' "$OUT" | awk '/^===PART 1$/{f=1;next} /^===PART /{f=0} f'; }

# ⓐ 루트에 TEAMS.md 없음 + 원장 리포 명단(옛 꼴) → 뉴스 폴더 = <루트>/design/planner/news (지금 ERROR 팀 명단 없음 재현 → 통과)
printf '%s\n' "$BASE_SHA" > "$NROOT/.fable-team/state/news-ledger/last.sha"; news_run
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qxF "news=$NROOT/design/planner/news" && ! printf '%s' "$OUT" | grep -q '팀 명단 없음' && ok "ⓐ r458 루트 명단 없음 → 원장 리포 명단으로 뉴스 폴더 풀림 rc0" || bad "ⓐ r458 뉴스 폴더 rc=$RC :: $OUT"
mv "$NROOT/design/planner/news" "$NR/news.off"; news_run
[ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q "ERROR 원장 뉴스 실패: 뉴스 폴더 없음 $NROOT/design/planner/news" && ! printf '%s' "$OUT" | grep -q '^news=' && ok "ⓐ r458 폴더 실재 0 → ERROR 뉴스 폴더 없음(폴백 0 · 발행 0)" || bad "ⓐ r458 폴더 없음 rc=$RC :: $OUT"
mv "$NR/news.off" "$NROOT/design/planner/news"
# ⓑ FT_NEWS_DIR 지정은 그대로 우선
news_run FT_NEWS_DIR="$NR/custom-news"
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qxF "news=$NR/custom-news" && ok "ⓑ r458 FT_NEWS_DIR 우선" || bad "ⓑ r458 FT_NEWS_DIR rc=$RC :: $OUT"
# ⓒ ft-goal-table.sh teams — 마커 2줄 · 열 4 · 12행 · ≤1600B · 표 없음 = 빈 출력 + WARN rc0(거절 0)
TB="$(FT_GOAL_A6_LEDGER="$TLED" bash "$TOOL" teams 2>"$T/err")"; RC=$?; TSHA="$(shasum -a 256 "$TLED" | cut -c1-10)"
[ "$RC" = 0 ] && printf '%s\n' "$TB" | head -1 | grep -qxF "★팀별 완성 진행 ($TSHA)★" && printf '%s\n' "$TB" | tail -1 | grep -qxF '★/팀별 완성 진행★' && ok "ⓒ r458 teams 마커 2줄(원장 sha10)" || bad "ⓒ r458 teams 마커 rc=$RC :: $TB"
[ "$(printf '%s\n' "$TB" | grep -c '^| team')" = 12 ] && printf '%s' "$TB" | grep -qF '| team3 | 3/6 | abcdef0003 |' && [ "$(printf '%s\n' "$TB" | wc -c)" -le 1600 ] && ok "ⓒ r458 teams 12행·칸(팀|끝선|착지|지금) · ≤1600B($(printf '%s\n' "$TB" | wc -c | tr -d ' ')B)" || bad "ⓒ r458 teams 행 :: $TB"
printf '%s' "$TB" | grep -q '읽히면 안 됨\|원장 글자' && bad "ⓒ r458 다른 절 표가 섞임" || ok "ⓒ r458 «## 팀별 완성 진행» 절 표만 읽음"
TB0="$(FT_GOAL_A6_LEDGER="$LEDGER" bash "$TOOL" teams 2>"$T/err")"; RC=$?
[ "$RC" = 0 ] && [ -z "$TB0" ] && grep -q '^WARN 팀별 완성 진행 표 없음' "$T/err" && ok "ⓒ r458 표 없음 = 빈 출력 + WARN rc0(거절 0)" || bad "ⓒ r458 표 없음 rc=$RC :: $TB0 :: $(cat "$T/err")"
check_body "$BLOCK"$'\n'"$TB"$'\n골좌표: 4 — 하네스팀 랜딩부터'; [ "$RC" = 0 ] && ok "ⓒ r458 check 불변(골 표 + teams 블록 → GOAL-OK)" || bad "ⓒ r458 check rc=$RC :: $OUT"
# ⓓ 뉴스 첫 판 = 머리 → 골 표 → 팀별 진행 → lead · 3500B 포함 · 이어진 판엔 없음
news_run; P1="$(part1)"
lno() { printf '%s\n' "$P1" | grep -n "$1" | head -1 | cut -d: -f1; }
ORDER="$(lno '^\*뉴스 ') $(lno '^★골 표 A6') $(lno '^★/골 표★') $(lno '^★팀별 완성 진행 (') $(lno '^★/팀별 완성 진행★') $(lno '^\*바뀐 것\*')"
[ "$RC" = 0 ] && [ "$ORDER" = "$(printf '%s\n' $ORDER | sort -n | tr '\n' ' ' | sed 's/ $//')" ] && [ "$(printf '%s\n' $ORDER | wc -l | tr -d ' ')" = 6 ] && ok "ⓓ r458 첫 판 순서 머리→골 표→팀별 진행" || bad "ⓓ r458 순서 [$ORDER] :: $P1"
OUT="$(FT_GOAL_A6_MD="$CANON" FT_GOAL_A6_LEDGER="$TLED" python3 - "$REPO/harness/bin" <<'PY' 2>&1
import sys; from datetime import datetime
sys.path.insert(0, sys.argv[1])
import ft_goal_table as gt, ft_news_ledger_text as t
goal, teams = gt.render(), gt.render_teams()
diff = [("새로", f"줄 {i} " + "가" * 120) for i in range(60)]
parts = t.render_parts(datetime(2026, 10, 19, 18, 0), {}, diff, "design/planner/PLAN-oppa-ledger.md", (), "결정 인터뷰 0건", goal, teams)
print(len(parts), max(len(p.encode()) for p in parts), "★팀별 완성 진행 (" in parts[0], sum("★팀별 완성 진행" in p for p in parts[1:]), parts[0].index("★/팀별 완성 진행★") < parts[0].index("결정 인터뷰"))
none = t.render_parts(datetime(2026, 10, 19, 18, 0), {}, diff[:1], "x", (), "", goal, "")
print("빈teams", "팀별" not in none[0])
PY
)"
set -- $OUT; [ "${1:-0}" -ge 2 ] && [ "${2:-9999}" -le 3500 ] && [ "${3:-}" = True ] && [ "${4:-}" = 0 ] && [ "${5:-}" = True ] && [ "${7:-}" = True ] && ok "ⓓ r458 판 $1개 · 최대 ${2}B ≤3500 · 팀별 진행 첫 판만(lead 앞) · 빈 값 = 줄 0" || bad "ⓓ r458 나누기 :: $OUT"
# ⓔ 매거진 — 같은 블록이 뿌리 글·HTML 절에 · 표 없음·도구 실패 = 빈 글(무장이어도 발행 거절 0)
MAG="$REPO/harness/kit/slack-mirror"; mkdir -p "$NR/mag/.fable-team/state"; : > "$NR/mag/.fable-team/state/goal-gate.armed"
OUT="$(FT_ROOT="$NR/mag" FT_GOAL_TABLE="$TOOL" FT_GOAL_A6_MD="$CANON" python3 - "$MAG" "$TLED" "$LEDGER" <<'PY' 2>&1
import os, sys
sys.path.insert(0, sys.argv[1])
import magazine_goal as mg
os.environ["FT_GOAL_A6_LEDGER"] = sys.argv[2]
goal = "\n".join(x for x in (mg.block(), mg.teams_block()) if x)
root = mg.with_root("매거진 2026-10-19 · 오빠 확인판\n둘째 줄", goal)
lines = root.splitlines()
print("first", lines[0] == "매거진 2026-10-19 · 오빠 확인판", "order", lines.index("★/골 표★") < lines.index(next(l for l in lines if l.startswith("★팀별 완성 진행 ("))) < lines.index("둘째 줄"), "html", "★팀별 완성 진행 (" in mg.html_section(goal))
os.environ["FT_GOAL_A6_LEDGER"] = sys.argv[3]
print("empty", repr(mg.teams_block()))
os.environ["FT_GOAL_TABLE"] = "/없는/ft-goal-table.sh"
print("broken", repr(mg.teams_block()))
PY
)"
printf '%s' "$OUT" | grep -q '^first True order True html True$' && printf '%s' "$OUT" | grep -q "^empty ''$" && printf '%s' "$OUT" | grep -q "^broken ''$" && ok "ⓔ r458 매거진 뿌리 글(첫 줄 그대로 → 골 표 → 팀별 진행)·HTML 절 · 표 없음/도구 없음 = 빈 글(무장 거절 0)" || bad "ⓔ r458 매거진 :: $OUT"
# ⓕ 원장 sha·경로·리포 = 원장 정본 한 값(FT_LEDGER_REPO + 경로) — 기준선 판이 옛 경로(design/planner/)·지금 판이 새 경로(design/teams/planner/) = 명확한 ERROR(옛 경로 후퇴·쌍둥이 읽기 0 · 발행 0)
mkdir -p "$NREPO/design/teams" "$NROOT/design/teams/planner/news"; git -C "$NREPO" mv design/planner design/teams/planner && sed -i.bak 's#`design/planner/`#`design/teams/planner/`#' "$NREPO/design/TEAMS.md" && rm -f "$NREPO/design/TEAMS.md.bak"
git -C "$NREPO" -c user.name=t -c user.email=t@t commit -qam move; MOVE_SHA="$(git -C "$NREPO" rev-parse HEAD)"
printf '%s\n' "$BASE_SHA" > "$NROOT/.fable-team/state/news-ledger/last.sha"; news_run FT_GOAL_A6_LEDGER=
[ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q "ERROR 원장 뉴스 실패: 기준선 ${BASE_SHA:0:10} 판에 원장 정본 design/teams/planner/PLAN-oppa-ledger.md 이 없다" && printf '%s' "$OUT" | grep -q '옛 경로 후퇴 0' && ! printf '%s' "$OUT" | grep -q '^news=\|exists on disk, but not in' && ok "ⓕ r458 기준선 옛 경로 ≠ 정본 새 경로 → 명확한 ERROR(발행 0 · git show 날 오류 0)" || bad "ⓕ r458 옛 경로 기준선 rc=$RC :: $OUT"
printf '%s\n' "ffffffffffffffffffffffffffffffffffffffff" > "$NROOT/.fable-team/state/news-ledger/last.sha"; news_run FT_GOAL_A6_LEDGER=
[ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '기준선 ffffffffff 판에 원장 정본' && ! printf '%s' "$OUT" | grep -q '^news=' && ok "ⓕ r458 원장 리포에 없는 기준선 sha(다른 리포 판) → ERROR(발행 0)" || bad "ⓕ r458 남의 sha rc=$RC :: $OUT"
printf '\n- 이동 뒤 줄 r458\n' >> "$NREPO/design/teams/planner/PLAN-oppa-ledger.md"; git -C "$NREPO" -c user.name=t -c user.email=t@t commit -qam after
printf '%s\n' "$MOVE_SHA" > "$NROOT/.fable-team/state/news-ledger/last.sha"; news_run FT_GOAL_A6_LEDGER=
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qxF "news=$NROOT/design/teams/planner/news" && printf '%s' "$OUT" | grep -q '이동 뒤 줄 r458' && printf '%s' "$OUT" | grep -q '^★팀별 완성 진행 (' && ok "ⓕ r458 기준선·지금 둘 다 정본 경로 → 발행 rc0 · 뉴스 폴더·골 표 원장 = 같은 정본(기본값)" || bad "ⓕ r458 정본 판 rc=$RC :: $OUT"
printf '%s\n' "$MOVE_SHA" > "$NROOT/.fable-team/state/news-ledger/last.sha"; mkdir -p "$NROOT/design/alt/news" "$NREPO/design/alt"; cp "$NREPO/design/teams/planner/PLAN-oppa-ledger.md" "$NREPO/design/alt/L.md"; git -C "$NREPO" add -A; git -C "$NREPO" -c user.name=t -c user.email=t@t commit -qm alt
printf '%s\n' "$(git -C "$NREPO" rev-parse HEAD)" > "$NROOT/.fable-team/state/news-ledger/last.sha"; printf '\n- alt 줄 r458\n' >> "$NREPO/design/alt/L.md"; git -C "$NREPO" -c user.name=t -c user.email=t@t commit -qam alt2
news_run FT_GOAL_A6_LEDGER= FT_LEDGER_PATH=design/alt/L.md
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qxF "news=$NROOT/design/alt/news" && printf '%s' "$OUT" | grep -q 'alt 줄 r458' && printf '%s' "$OUT" | grep -q '^★팀별 완성 진행 (' && ok "ⓕ r458 FT_LEDGER_PATH 한 값 → 원장·뉴스 폴더·팀별 진행 출처 모두 그 경로(TEAMS.md 무관)" || bad "ⓕ r458 FT_LEDGER_PATH rc=$RC :: $OUT"
grep -nE '\b(600|300)\b' "$REPO/harness/bin/ft_news_ledger.py" "$REPO/harness/bin/ft_goal_table.py" "$REPO/harness/kit/slack-mirror/magazine_goal.py" >/dev/null && bad "ⓕ r458 600/300 상한 등장" || ok "ⓕ r458 600/300 0"

echo "fail=$fail"; [ "$fail" = 0 ]
