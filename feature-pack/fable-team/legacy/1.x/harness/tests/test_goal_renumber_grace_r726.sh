#!/usr/bin/env bash
# test_goal_renumber_grace_r726.sh — r726: 골 정본 번호표가 바뀐 직후(골 2·3 교체 + 7행 추가) 옛 블록·옛 골좌표 쪽지가 «한꺼번에» REJECT 되던 것
#   → «직전 정본 1판» 을 정해진 시간(기본 24h · FT_GOAL_RENUMBER_GRACE_H)만 인정 + 경고 줄, 그 뒤 = 지금처럼 REJECT.
#   ⓐ 빨강(base 판 = origin/main) 같은 쪽지 → REJECT rc3   ⓑ 후판 = 옛 번호표 유예 rc0 + 발신 좌석 로그 1줄(남은 시간이 줄어든다)
#   ⓒ 유예 밖 · 두 판 이상 옛 판 · 표식 없음 · 표식 손상 = REJECT rc3(유예로 새지 않는다)
#   ⓓ 새 판 블록·새 골좌표 = 지금처럼 GOAL-OK(유예 문구 0)   ⓔ 유예 중에도 옛 판에 없는 번호 = REJECT
#   ⓕ 격리(임시 리포·임시 루트·가짜 mbox — 실 쪽지 0 · 실 리포 변경 0)   ⓖ 변이 2(유예 시간 검사 삭제 / 두 판 이상 허용)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd -- "$HERE/../.." && pwd -P)"
TOOL="$REPO/harness/kit/fable-team/bin/ft_goal_table.py"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음 «$2» ← ${1:0:300}";; esac; }
not() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨 «$2» ← ${1:0:300}»";; *) ok "$3";; esac; }

# ── ⓐ 대조용 base 판 — «이동하는 origin/main» 이 아니라 고정 sha 050dae3e(이 카드 이전 · r726 r3 DA 질문 7)
ROOT="$(git -C "$REPO" rev-parse --show-toplevel)"; KITREL="${REPO#"$ROOT"/}/harness/kit/fable-team/bin"
BASESHA=050dae3e; OLDSHA=ce876315fcfa191cf6c206050527e6a018d0c301   # OLDSHA = r726 r2 판(r3 반송 입력)
MODS="ft_goal_table.py ft_goal_ledger.py ft_team_lib.py ft_goal_readjust_state.py"
snap() {  # <sha> <폴더> — 그 sha 의 판정기 모듈 사본(없는 모듈은 건너뛴다) · 성공 0
  local sha="$1" d="$2" f got=0; mkdir -p "$d"
  for f in $MODS; do git -C "$ROOT" cat-file -e "$sha:$KITREL/$f" 2>/dev/null || continue
    git -C "$ROOT" show "$sha:$KITREL/$f" > "$d/$f" && got=1 || return 1; done
  [ "$got" = 1 ]
}
BASE="$T/basebin"; snap "$BASESHA" "$BASE" || bad "base 사본 못 뜸($BASESHA)"
OLD="$T/oldbin"; snap "$OLDSHA" "$OLD" || bad "r2 판 사본 못 뜸($OLDSHA)"
BEFORE="$(git -C "$ROOT" status --porcelain | wc -l | tr -d ' ')"

CPATH=design/planner/AUTONOMY-GOAL-A6-20261018.md; LPATH=design/planner/PLAN-oppa-ledger.md
R="$T/repo"; mkdir -p "$R/design/planner" "$R/.fable-team/state" "$T/mbox"; git -C "$R" init -q -b main
: > "$R/.fable-team/LIVE_BIN"; printf '{"_master":"master-a#1"}\n' > "$R/.fable-team/seats-a.json"
cat > "$T/mbox/mbox.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MBOX_LOG"
[ -z "${MBOX_FAIL:-}" ] || [ ! -e "$MBOX_FAIL" ] || exit 1   # r3 ⓟ: 공지 실패를 흉내내는 스위치(파일이 있으면 송신 실패)
SH
chmod +x "$T/mbox/mbox.sh"; export MBOX_LOG="$T/mbox.log" MBOX_FAIL="$T/mbox.fail"; : > "$MBOX_LOG"
MARK="$R/.fable-team/state/goal-numbering.tsv"
NOW="2026-10-22 12:00"; LATER="2026-10-23 11:00"; EXPIRED="2026-10-23 13:00"   # 번호표 바뀐 시각 = NOW · 유예 24h
canon() {  # <골 이름...>
  printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'
  local g; for g in "$@"; do printf '| %s | 팀x | 착지 sha |\n' "$g"; done
}
ledger() {  # <행 수> — 원장 절 이름은 옛 꼴(«메인 골 6줄») 그대로 둔다(이 카드 범위 밖)
  printf '# 원장\n\n> 마지막 갱신: %s · planner#1\n\n## 메인 골 6줄 — 지금 상태\n\n| 골(오빠 원문) | 지금 상태 | 닫히는 조건 |\n|---|---|---|\n' "$NOW"
  local i; for i in $(seq 1 "$1"); do printf '| 원장 글자 %s | 상태%s 진행 | 남은%s |\n' "$i" "$i" "$i"; done
}
commit() { git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -q -m "$1" && git -C "$R" update-ref refs/remotes/origin/main HEAD; }
render() {  # <FT_NOW> — 실 mbox 대신 스텁(인자만 기록)
  env -u FT_GOAL_MAX FT_ROOT="$R" FT_MBOX="$T/mbox/mbox.sh" FT_NOW="$1" FT_GOAL_A6_MD="gitref:origin/main:$CPATH" \
    FT_GOAL_A6_LEDGER="gitref:origin/main:$LPATH" FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "$TOOL" 2>&1
}
checkx() {  # <본문> <FT_NOW> [도구] — 판정 + stderr(GRACE 로그)를 한 글자에
  printf '%s\n' "$1" | env FT_ROOT="$R" FT_NOW="$2" FT_SEAT="byz-nano-grace-test#0" FT_GOAL_A6_MD="gitref:origin/main:$CPATH" \
    FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "${3:-$TOOL}" check - 2>&1
}

echo "== 기준선 — 정본 6행 렌더(표식 첫 줄만 · 공지 0)"
canon k1 k2 k3 k4 k5 k6 > "$R/$CPATH"; ledger 6 > "$R/$LPATH"; commit base6
BLOCK6="$(render "$NOW")"; RC=$?
[ "$RC" = 0 ] && [ "$(printf '%s\n' "$BLOCK6" | grep -c '^| .* | .* | .* | .* |$')" = 7 ] && ok "기준선 6행 → rc0 · 표 7줄" || bad "기준선 rc=$RC :: $BLOCK6"
[ "$(wc -l < "$MARK" | tr -d ' ')" = 1 ] && [ ! -s "$MBOX_LOG" ] && ok "표식 = 첫 줄만(직전 판 0) · 공지 0" || bad "표식/공지 :: $(cat "$MARK") / $(cat "$MBOX_LOG")"
S1SHA="$(printf '%s\n' "$BLOCK6" | head -1 | sed -n 's/.*origin\/main@\([0-9a-f]\{10\}\) .*/\1/p')"

echo "== 번호표 바뀜 — 골 2·3 교체 + 7행 추가(planner 정본 PR 꼴)"
canon k1 k9 k9b k4 k5 k6 k7 > "$R/$CPATH"; ledger 7 > "$R/$LPATH"; commit renumber7
BLOCK7="$(render "$NOW")"; RC=$?
[ "$RC" = 0 ] && ok "새 정본 7행 렌더 → rc0" || bad "새 정본 rc=$RC :: $BLOCK7"
grep -q "^prev	$S1SHA	" "$MARK" && ok "표식 둘째 줄 = «직전 판» = 옛 정본 sha($S1SHA)" || bad "표식 :: $(cat "$MARK")"
[ "$(wc -l < "$MBOX_LOG" | tr -d ' ')" = 1 ] && ok "번호 바뀜 공지 = 팀장 1명 1통" || bad "공지 :: $(cat "$MBOX_LOG")"
cp "$MARK" "$T/mark-prev6"   # 유예 판정 기준 상태(직전 판 = 6행 판) — 변이 시험에서 되돌린다

echo "== ⓐ 빨강 — base 판(origin/main)은 같은 쪽지를 REJECT"
OUT="$(checkx "$BLOCK6"$'\n'"골좌표: 2 — k2" "$NOW" "$BASE/ft_goal_table.py")"; RC=$?
[ "$RC" = 3 ] || bad "ⓐ 옛 블록 + 옛 골좌표 → REJECT rc3(빨강) — rc=$RC :: $OUT"
[ "$RC" = 3 ] && has "$OUT" "옛 번호표로는 판정하지 않는다" "ⓐ 옛 블록 + 옛 골좌표 → REJECT rc3(빨강)"
has "$OUT" "새 번호표 7줄: 1 — k1" "ⓐ 거절 문구에 새 번호표 7줄"
echo "   ⓐ 원문(base): $OUT"

echo "== ⓑ 후판 — 직전 판 1개를 유예로 인정(GOAL-OK + 경고 줄)"
OUT="$(checkx "$BLOCK6"$'\n'"골좌표: 2 — k2" "$NOW")"; RC=$?
[ "$RC" = 0 ] || bad "ⓑ 옛 블록 → GOAL-OK n=2 rc0(유예 24시간 남음) — rc=$RC :: $OUT"
[ "$RC" = 0 ] && has "$OUT" "GOAL-OK n=2 옛 번호표(유예 24시간 남음 · 새 번호표 7줄: 1 — k1" "ⓑ 옛 블록 → GOAL-OK n=2 rc0(유예 24시간 남음)"
has "$OUT" "GRACE 옛 번호표 수용 — 좌석 byz-nano-grace-test#0 · 마커 $S1SHA" "ⓑ 통과 때 발신 좌석 이름과 함께 로그 1줄"
echo "   ⓑ 판정(새 판): $(printf '%s\n' "$OUT" | grep '^GOAL-OK')"
OUT="$(checkx "$BLOCK6"$'\n'"골좌표: 2 — k2" "$LATER")"; RC=$?
[ "$RC" = 0 ] || bad "ⓑ2 23시간 뒤 = 남은 시간이 줄어든다(유예 1시간 남음) — rc=$RC :: $OUT"
[ "$RC" = 0 ] && has "$OUT" "유예 1시간 남음" "ⓑ2 23시간 뒤 = 남은 시간이 줄어든다(유예 1시간 남음)"
OUT="$(checkx "$BLOCK6"$'\n'"골좌표: 2 — k2" "$NOW" "$BASE/ft_goal_table.py")"; RC=$?
[ "$RC" = 3 ] || bad "ⓑ3 같은 쪽지 · base 판은 여전히 REJECT(차이 = 이 카드) — rc=$RC :: $OUT"
[ "$RC" = 3 ] && ok "ⓑ3 같은 쪽지 · base 판은 여전히 REJECT(차이 = 이 카드)"

echo "== ⓔ 유예 중에도 옛 판에 없는 번호 = REJECT"
OUT="$(checkx "$BLOCK6"$'\n'"골좌표: 7 — k7" "$NOW")"; RC=$?
[ "$RC" = 3 ] || bad "ⓔ 옛 6행 판에 번호 7 → REJECT rc3(유예는 행 수를 늘리지 않는다) — rc=$RC :: $OUT"
[ "$RC" = 3 ] && has "$OUT" "번호 1~6" "ⓔ 옛 6행 판에 번호 7 → REJECT rc3(유예는 행 수를 늘리지 않는다)"

echo "== ⓒ1 유예 밖(25시간) = 지금처럼 REJECT"
OUT="$(checkx "$BLOCK6"$'\n'"골좌표: 2 — k2" "$EXPIRED")"; RC=$?
[ "$RC" = 3 ] || bad "ⓒ1 유예 밖 → REJECT rc3 — rc=$RC :: $OUT"
[ "$RC" = 3 ] && has "$OUT" "옛 번호표로는 판정하지 않는다" "ⓒ1 유예 밖 → REJECT rc3"
OUT="$(printf '%s\n%s\n' "$BLOCK6" "골좌표: 2 — k2" | env FT_ROOT="$R" FT_NOW="$EXPIRED" FT_GOAL_RENUMBER_GRACE_H=0 FT_GOAL_A6_MD="gitref:origin/main:$CPATH" \
  FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "$TOOL" check - 2>&1)"; RC=$?
[ "$RC" = 3 ] || bad "ⓒ1b FT_GOAL_RENUMBER_GRACE_H=0 = 유예 없음(지금 판과 같다 · 되돌림 손잡이) — rc=$RC :: $OUT"
[ "$RC" = 3 ] && ok "ⓒ1b FT_GOAL_RENUMBER_GRACE_H=0 = 유예 없음(지금 판과 같다 · 되돌림 손잡이)"

echo "== ⓓ 새 판 블록·새 골좌표 = 지금처럼 GOAL-OK(유예 문구 0)"
OUT="$(checkx "$BLOCK7"$'\n'"골좌표: 2 — k9" "$NOW")"; RC=$?
[ "$RC" = 0 ] || bad "ⓓ 새 판 → GOAL-OK n=2 rc0 — rc=$RC :: $OUT"
[ "$RC" = 0 ] && has "$OUT" "GOAL-OK n=2" "ⓓ 새 판 → GOAL-OK n=2 rc0"
not "$OUT" "유예" "ⓓ 새 판 판정에는 유예 문구가 없다"

echo "== 두 번째 번호표 바뀜(8행) — 직전 판이 앞으로 밀린다"
canon k1 k9 k9b k4 k5 k6 k7 k8 > "$R/$CPATH"; ledger 8 > "$R/$LPATH"; commit renumber8
render "$NOW" > /dev/null
S2SHA="$(printf '%s\n' "$BLOCK7" | head -1 | sed -n 's/.*origin\/main@\([0-9a-f]\{10\}\) .*/\1/p')"
grep -q "^prev	$S2SHA	" "$MARK" && ok "표식 직전 판 = 7행 판($S2SHA)" || bad "표식 :: $(cat "$MARK")"
OUT="$(checkx "$BLOCK7"$'\n'"골좌표: 2 — k9" "$NOW")"; RC=$?
[ "$RC" = 0 ] || bad "ⓑ4 직전 판(7행)은 유예로 통과 — rc=$RC :: $OUT"
[ "$RC" = 0 ] && has "$OUT" "옛 번호표(유예 24시간 남음 · 새 번호표 8줄" "ⓑ4 직전 판(7행)은 유예로 통과"
OUT="$(checkx "$BLOCK6"$'\n'"골좌표: 2 — k2" "$NOW")"; RC=$?
[ "$RC" = 3 ] || bad "ⓒ2 두 판 이상 옛 판(6행) → REJECT rc3(1판만 인정) — rc=$RC :: $OUT"
[ "$RC" = 3 ] && has "$OUT" "새 번호표 8줄" "ⓒ2 두 판 이상 옛 판(6행) → REJECT rc3(1판만 인정)"

echo "== ⓒ3 표식 없음 · ⓒ4 표식 손상 = REJECT(유예로 새지 않는다)"
cp "$MARK" "$T/mark.bak"; rm -f "$MARK"
OUT="$(checkx "$BLOCK7"$'\n'"골좌표: 2 — k9" "$NOW")"; RC=$?
[ "$RC" = 3 ] || bad "ⓒ3 표식 없음 → REJECT rc3 — rc=$RC :: $OUT"
[ "$RC" = 3 ] && has "$OUT" "새 번호표 8줄" "ⓒ3 표식 없음 → REJECT rc3"
printf '%s\t%s\nprev\t%s\t%s\tnope\n' "deadbeef00" "0123456789ab" "$S2SHA" "0123456789ab" > "$MARK"
OUT="$(checkx "$BLOCK7"$'\n'"골좌표: 2 — k9" "$NOW")"; RC=$?
[ "$RC" = 3 ] || bad "ⓒ4 표식 손상(시각 칸이 숫자가 아니다) → REJECT rc3 — rc=$RC :: $OUT"
[ "$RC" = 3 ] && ok "ⓒ4 표식 손상(시각 칸이 숫자가 아니다) → REJECT rc3"
printf 'garbage\n' > "$MARK"
OUT="$(checkx "$BLOCK7"$'\n'"골좌표: 2 — k9" "$NOW")"; RC=$?
[ "$RC" = 3 ] || bad "ⓒ4b 표식 손상(직전 판 줄 없음) → REJECT rc3 — rc=$RC :: $OUT"
[ "$RC" = 3 ] && ok "ⓒ4b 표식 손상(직전 판 줄 없음) → REJECT rc3"
cp "$T/mark.bak" "$MARK"

echo "== ⓕ 격리 — 임시 리포·임시 루트·가짜 mbox(실 쪽지 0 · 실 리포 변경 0)"
[ "$(wc -l < "$MBOX_LOG" | tr -d ' ')" = 2 ] && ok "ⓕ 쪽지는 스텁에만(팀장 1명 × 번호표 바뀜 2회 = 2통)" || bad "쪽지 :: $(cat "$MBOX_LOG")"
[ ! -e "$R/.fable-team/comm/mailbox.jsonl" ] && ok "ⓕ 임시 루트에 실 우편함 파일 0" || bad "ⓕ 임시 루트에 실 우편함 파일이 생겼다"
[ "$(git -C "$ROOT" status --porcelain | wc -l | tr -d ' ')" = "$BEFORE" ] && ok "ⓕ 실 리포 작업 트리 변경 0(이 시험은 자기 파일만 쓴다)" || bad "실 리포가 바뀌었다"

echo "== ⓖ 변이 — 유예 시간 검사·직전 판 결속을 지우면 ⓒ 가 뚫린다(시험이 잡는다)"
mut() {  # <이름> <지울 조각> → 변이 도구 경로
  local d="$T/mut-$1"; mkdir -p "$d"
  cp $REPO/harness/kit/fable-team/bin/{ft_goal_table.py,ft_goal_ledger.py,ft_team_lib.py,ft_goal_readjust_state.py} "$d"/ 2>/dev/null
  python3 - "$d/ft_goal_table.py" "$2" <<'PY' || return 1
import sys
p, pat = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
assert pat in s, "변이 대상 없음: " + pat
open(p, "w", encoding="utf-8").write(s.replace(pat, "", 1))
PY
  printf '%s\n' "$d/ft_goal_table.py"
}
cp "$T/mark.bak" "$MARK"   # 변이 A 는 «직전 판 = 7행 판 · 표식 첫 줄 = 지금(8행) 판» 상태에서 잰다(r3: 표식 첫 줄 대조를 만족해야 시간 검사만 남는다)
MA="$(mut time "    if elapsed < 0 or elapsed >= hours * 3600:
        return \"\"")" || bad "변이 A 못 만듦"
OUT="$(checkx "$BLOCK7"$'\n'"골좌표: 2 — k9" "$EXPIRED" "$MA")"; RC=$?
[ "$RC" = 0 ] && ok "ⓖ1 유예 시간 검사 삭제 → ⓒ1(유예 밖)이 GOAL-OK 로 뚫린다(변이 감지)" || bad "ⓖ1 변이 A rc=$RC :: $OUT"
cp "$T/mark.bak" "$MARK"   # 변이 B 는 «직전 판 = 7행 판» 상태(두 판 이상 옛 판)
MB="$(mut onepan "rec[1] != _num_hash(old_num) or ")" || bad "변이 B 못 만듦"
OUT="$(checkx "$BLOCK6"$'\n'"골좌표: 2 — k2" "$NOW" "$MB")"; RC=$?
[ "$RC" = 0 ] && ok "ⓖ2 직전 판 결속 삭제 → ⓒ2(두 판 이상 옛 판)가 통과한다(변이 감지)" || bad "ⓖ2 변이 B rc=$RC :: $OUT"

echo "== ⓗ·ⓘ·ⓖ3 — 유예는 «main 커밋 1개» 가 아니라 «직전 번호표 1판» 에 건다(r2 반송 고침 · arch 123 반례)"
mutsub() {  # <이름> <찾을 글> <바꿀 글> → 변이 도구 경로(치환 1회)
  local d="$T/mut2-$1"; mkdir -p "$d"
  cp $REPO/harness/kit/fable-team/bin/{ft_goal_table.py,ft_goal_ledger.py,ft_team_lib.py,ft_goal_readjust_state.py} "$d"/ 2>/dev/null
  python3 - "$d/ft_goal_table.py" "$2" "$3" <<'PY' || return 1
import sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
assert a in s, "변이 대상 없음: " + a
open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
  printf '%s\n' "$d/ft_goal_table.py"
}
newrepo() {  # <경로> — 임시 리포·임시 루트(가짜 mbox 스텁은 그대로, 로그만 새 파일)
  R="$1"; mkdir -p "$R/design/planner" "$R/.fable-team/state"; git -C "$R" init -q -b main
  : > "$R/.fable-team/LIVE_BIN"; printf '{"_master":"master-a#1"}\n' > "$R/.fable-team/seats-a.json"
  MARK="$R/.fable-team/state/goal-numbering.tsv"; export MBOX_LOG="$2"; : > "$MBOX_LOG"
}
newrepo "$T/repo2" "$T/mbox2.log"
canon k1 k2 k3 k4 k5 k6 > "$R/$CPATH"; ledger 6 > "$R/$LPATH"; commit base6c
BLOKA="$(render "$NOW")"; RC=$?
[ "$RC" = 0 ] && ok "ⓗ 준비: A 렌더(6행) rc0" || bad "ⓗ 준비 rc=$RC :: $BLOKA"
printf 'note\n' > "$R/note.txt"; commit unrelatedB; render "$NOW" > /dev/null   # 정본 무관 main 커밋 B + 렌더 → 표식이 B 로 전진
BSHA="$(git -C "$R" rev-parse --short=10 HEAD)"
canon k1 k9 k9b k4 k5 k6 k7 > "$R/$CPATH"; ledger 7 > "$R/$LPATH"; commit renumber7c; render "$NOW" > /dev/null
grep -q "^prev	$BSHA	" "$MARK" && ok "ⓗ 표식 직전 판 = B(무관 커밋) 렌더 ($BSHA) — A 와 다른 main 커밋" || bad "ⓗ 표식 :: $(cat "$MARK")"
OUT="$(checkx "$BLOKA"$'\n'"골좌표: 2 — k2" "$NOW")"; RC=$?
[ "$RC" = 0 ] || bad "ⓗ 같은 옛 번호표 · 한 커밋 앞에서 렌더된 블록 = 유예 GOAL-OK rc0 — rc=$RC :: $OUT"
[ "$RC" = 0 ] && has "$OUT" "GOAL-OK n=2 옛 번호표(유예" "ⓗ 같은 옛 번호표 · 한 커밋 앞에서 렌더된 블록 = 유예 GOAL-OK rc0"
echo "   ⓗ 판정: $(printf '%s\n' "$OUT" | grep '^GOAL-OK')"
MR1="$(mutsub r1 'if rec is None or rec[1] != _num_hash(old_num)' 'if rec is None or rec[0] != sha or rec[1] != _num_hash(old_num)')" || bad "ⓗ 빨강 변이 못 만듦"
OUT="$(checkx "$BLOKA"$'\n'"골좌표: 2 — k2" "$NOW" "$MR1")"; RC=$?
[ "$RC" = 3 ] || bad "ⓗ 빨강 = 5a6b558d5d 판(rec[0]==sha 결속)은 같은 쪽지를 REJECT rc3 — rc=$RC :: $OUT"
[ "$RC" = 3 ] && has "$OUT" "옛 번호표로는 판정하지 않는다" "ⓗ 빨강 = 5a6b558d5d 판(rec[0]==sha 결속)은 같은 쪽지를 REJECT rc3"
echo "   ⓗ 원문(빨강): $OUT"
newrepo "$T/repo3" "$T/mbox3.log"
canon k1 k2 k3 k4 k5 k6 > "$R/$CPATH"; ledger 6 > "$R/$LPATH"; commit base6d
BLOKI="$(render "$NOW")"; RC=$?
[ "$RC" = 0 ] && ok "ⓘ 준비: 옛 판 렌더 rc0" || bad "ⓘ 준비 rc=$RC :: $BLOKI"
for i in $(seq 1 13); do printf 'n\n' > "$R/n$i.txt"; commit "unrelated $i"; done   # 옛 판과 직전 판 사이에 첫 부모 13커밋
render "$NOW" > /dev/null
canon k1 k9 k9b k4 k5 k6 k7 > "$R/$CPATH"; ledger 7 > "$R/$LPATH"; commit renumber7d; render "$NOW" > /dev/null
OUT="$(checkx "$BLOKI"$'\n'"골좌표: 2 — k2" "$NOW")"; RC=$?
[ "$RC" = 3 ] && ok "ⓘ 직전 판보다 첫 부모 13커밋 앞 렌더 블록 = REJECT rc3(상한 12 · 낡은 블록이 유예로 새지 않는다)" || bad "ⓘ rc=$RC :: $OUT"
echo "   ⓘ 원문: $OUT"
MO="$(mutsub nocap "    base, dist = _fp_dist(rec[0]), _fp_dist(sha)
    if base is None or dist is None or dist > base + STALE_FP_MAX:
        return \"\"
" "")" || bad "ⓖ3 변이 못 만듦"
OUT="$(checkx "$BLOKI"$'\n'"골좌표: 2 — k2" "$NOW" "$MO")"; RC=$?
[ "$RC" = 0 ] && ok "ⓖ3 신선도 상한 삭제 → ⓘ 가 GOAL-OK 로 뚫린다(변이 감지)" || bad "ⓖ3 변이 rc=$RC :: $OUT"
R="$T/repo"; MARK="$T/repo/.fable-team/state/goal-numbering.tsv"; export MBOX_LOG="$T/mbox.log"   # 뒤 시험을 위해 원래 리포로 되돌린다

echo "== ⓙ~ⓠ r3 — 표식 형식 · prev 이력 대조 · 시간·env 경계 · 가드 경고(DA⑥ r1 처방 5 · 빨강 = r2 판 $OLDSHA)"
# 공통 픽스처: C6 렌더 → C7 렌더(번호표 바뀜 · 표식 = 첫 줄 7행 / 직전 6행) → BLOCK6 이 유예 대상
csnap() { cp "$MARK" "$1"; }   # <파일> 표식 스냅샷
cur_line() { head -1 "$MARK"; }  # 지금 표식 첫 줄
prev_line() { sed -n '2p' "$MARK"; }
fp6=""; fp7=""; ts7=""; c6sha=""; c7sha=""
newrepo "$T/repo4" "$T/mbox4.log"
canon k1 k2 k3 k4 k5 k6 > "$R/$CPATH"; ledger 6 > "$R/$LPATH"; commit base6e
B4="$(render "$NOW")"; RC=$?
[ "$RC" = 0 ] || bad "ⓙ 준비: C6 렌더 rc=$RC :: $B4"
c6sha="$(printf '%s\n' "$B4" | head -1 | sed -n 's/.*origin\/main@\([0-9a-f]\{10\}\) .*/\1/p')"
canon k1 k9 k9b k4 k5 k6 k7 > "$R/$CPATH"; ledger 7 > "$R/$LPATH"; commit renumber7e
BLOCK7B="$(render "$NOW")"; RC=$?
[ "$RC" = 0 ] || bad "ⓙ 준비: C7 렌더 rc=$RC :: $BLOCK7B"
c7sha="$(printf '%s\n' "$BLOCK7B" | head -1 | sed -n 's/.*origin\/main@\([0-9a-f]\{10\}\) .*/\1/p')"
fp6="$(prev_line | cut -f3)"; ts7="$(prev_line | cut -f4)"; fp7="$(cur_line | cut -f2)"
[ "${#fp6}" = 12 ] && [ "${#fp7}" = 12 ] && [ "$fp6" != "$fp7" ] && ok "ⓙ 준비: 표식 지문 6행=$fp6 · 7행=$fp7" || bad "ⓙ 표식 :: $(cat "$MARK")"
csnap "$T/mark-r3"   # 정상 상태(첫 줄 = 7행 · 직전 = 6행)
base_q() { printf '%s\n%s\n' "$B4" "골좌표: 2 — k2"; }   # 6행 판 블록 + 옛 골좌표

echo "-- ⓙ 손상 첫 줄(garbage) = 유예 0"
cp "$T/mark-r3" "$MARK"; printf 'garbage\n%s\n' "$(prev_line)" > "$MARK"
OUT="$(checkx "$(base_q)" "$NOW")"; RC=$?
[ "$RC" = 3 ] || bad "ⓙ 손상 첫 줄 → 새 판은 REJECT 여야 한다 — rc=$RC :: $OUT"
[ "$RC" = 3 ] && ok "ⓙ 손상 첫 줄(형식 위반) → REJECT rc3"
OUT="$(checkx "$(base_q)" "$NOW" "$OLD/ft_goal_table.py")"; RC=$?
[ "$RC" = 0 ] && ok "ⓙ 빨강 = r2 판은 같은 쪽지를 통과시켰다(rc0 · 형식 검사가 없었다)" || bad "ⓙ 빨강 rc=$RC(기대 0) :: $OUT"

echo "-- ⓚ 빈 prev sha = 유예 0(_fp_dist(\"\") 가 0 을 돌지 않는다)"
cp "$T/mark-r3" "$MARK"; printf '%s\nprev\t\t%s\t%s\n' "$(cur_line)" "$fp6" "$ts7" > "$MARK"
OUT="$(checkx "$(base_q)" "$NOW")"; RC=$?
[ "$RC" = 3 ] && ok "ⓚ 빈 prev sha → REJECT rc3" || bad "ⓚ 빈 prev sha rc=$RC :: $OUT"
OUT="$(checkx "$(base_q)" "$NOW" "$OLD/ft_goal_table.py")"; RC=$?
[ "$RC" = 0 ] && ok "ⓚ 빨강 = r2 판은 빈 sha 로도 통과(rc0)" || bad "ⓚ 빨강 rc=$RC(기대 0) :: $OUT"

echo "-- ⓛ 가짜 prev(이력과 지문이 다르다) = 유예 0"
cp "$T/mark-r3" "$MARK"; printf '%s\nprev\t%s\t%s\t%s\n' "$(cur_line)" "$c7sha" "$fp6" "$ts7" > "$MARK"
OUT="$(checkx "$(base_q)" "$NOW")"; RC=$?
[ "$RC" = 3 ] && ok "ⓛ prev sha 가 C7 인데 지문은 6행 → REJECT rc3(이력 대조)" || bad "ⓛ 가짜 prev rc=$RC :: $OUT"
OUT="$(checkx "$(base_q)" "$NOW" "$OLD/ft_goal_table.py")"; RC=$?
[ "$RC" = 0 ] && ok "ⓛ 빨강 = r2 판은 표식에 적힌 sha·지문을 그대로 믿었다(rc0)" || bad "ⓛ 빨강 rc=$RC(기대 0) :: $OUT"

echo "-- ⓜ 미래 시각 = 유예 0(경과 < 0)"
cp "$T/mark-r3" "$MARK"; printf '%s\nprev\t%s\t%s\t%s\n' "$(cur_line)" "$c6sha" "$fp6" "$(( ts7 + 8784 * 3600 ))" > "$MARK"
OUT="$(checkx "$(base_q)" "$NOW")"; RC=$?
[ "$RC" = 3 ] && ok "ⓜ 미래 시각(+8784h) → REJECT rc3" || bad "ⓜ 미래 시각 rc=$RC :: $OUT"
OUT="$(checkx "$(base_q)" "$NOW" "$OLD/ft_goal_table.py")"; RC=$?
[ "$RC" = 0 ] && ok "ⓜ 빨강 = r2 판은 미래 시각을 «남은 시간 큼» 으로 읽었다(rc0)" || bad "ⓜ 빨강 rc=$RC(기대 0) :: $OUT"

echo "-- ⓝ 시각 칸이 NaN = 유예 0(유한 정수만)"
cp "$T/mark-r3" "$MARK"; printf '%s\nprev\t%s\t%s\tnan\n' "$(cur_line)" "$c6sha" "$fp6" > "$MARK"
OUT="$(checkx "$(base_q)" "$NOW")"; RC=$?
[ "$RC" = 3 ] && ok "ⓝ 시각 nan → REJECT rc3" || bad "ⓝ nan rc=$RC :: $OUT"
OUT="$(checkx "$(base_q)" "$NOW" "$OLD/ft_goal_table.py")"; RC=$?
[ "$RC" = 0 ] && ok "ⓝ 빨강 = r2 판은 float(\"nan\") 을 받아 rem 비교가 전부 거짓 → 통과(rc0)" || bad "ⓝ 빨강 rc=$RC(기대 0) :: $OUT"

echo "-- ⓞ env 유예는 «줄이기» 만 = 25시간 뒤엔 REJECT(GRACE_H=1e9 무시)"
cp "$T/mark-r3" "$MARK"
OUT="$(printf '%s\n' "$(base_q)" | env FT_ROOT="$R" FT_NOW="$EXPIRED" FT_SEAT="byz-nano-grace-test#0" FT_GOAL_RENUMBER_GRACE_H=1e9 \
  FT_GOAL_A6_MD="gitref:origin/main:$CPATH" FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "$TOOL" check - 2>&1)"; RC=$?
[ "$RC" = 3 ] && ok "ⓞ GRACE_H=1e9 · 25시간 뒤 → REJECT rc3(min(env,24))" || bad "ⓞ env 큰 값 rc=$RC :: $OUT"
OUT="$(printf '%s\n' "$(base_q)" | env FT_ROOT="$R" FT_NOW="$EXPIRED" FT_SEAT="byz-nano-grace-test#0" FT_GOAL_RENUMBER_GRACE_H=1e9 \
  FT_GOAL_A6_MD="gitref:origin/main:$CPATH" FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "$OLD/ft_goal_table.py" check - 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "ⓞ 빨강 = r2 판은 env 값 그대로 유예를 늘렸다(25시간 뒤 rc0)" || bad "ⓞ 빨강 rc=$RC(기대 0) :: $OUT"
cp "$T/mark-r3" "$MARK"

echo "-- ⓟ 공지 실패 뒤 «두 판 전» = 유예 0(표식 첫 줄이 지금 판이 아니다)"
newrepo "$T/repo5" "$T/mbox5.log"
canon k1 k2 k3 k4 k5 k6 > "$R/$CPATH"; ledger 6 > "$R/$LPATH"; commit base6f
B5="$(render "$NOW")"; RC=$?
[ "$RC" = 0 ] || bad "ⓟ 준비: 6행 렌더 rc=$RC :: $B5"
canon k1 k2 k3 k4 k5 > "$R/$CPATH"; ledger 5 > "$R/$LPATH"; commit renumber5   # 6→5 : 공지 성공
render "$NOW" > /dev/null; cp "$MARK" "$T/mark-r5a"
canon k1 k2 k3 k4 > "$R/$CPATH"; ledger 4 > "$R/$LPATH"; commit renumber4        # 5→4 : 공지 실패
: > "$MBOX_FAIL"; render "$NOW" > /dev/null; rm -f "$MBOX_FAIL"
cmp -s "$MARK" "$T/mark-r5a" && ok "ⓟ 공지 실패 = 표식 전진 0(첫 줄은 아직 5행 판)" || bad "ⓟ 표식이 전진했다 :: $(cat "$MARK")"
OUT="$(checkx "$B5"$'\n'"골좌표: 6 — k6" "$NOW")"; RC=$?
[ "$RC" = 3 ] && ok "ⓟ 공지 실패 뒤 두 판 전(6행) 블록 → REJECT rc3(표식 첫 줄 ≠ 지금 판)" || bad "ⓟ 두 판 전 rc=$RC :: $OUT"
OUT="$(checkx "$B5"$'\n'"골좌표: 6 — k6" "$NOW" "$OLD/ft_goal_table.py")"; RC=$?
[ "$RC" = 0 ] && ok "ⓟ 빨강 = r2 판은 두 판 전 블록을 유예로 통과시켰다(rc0)" || bad "ⓟ 빨강 rc=$RC(기대 0) :: $OUT"

echo "-- ⓠ 가드가 유예 통과를 송신자에게 보인다(GL-GRACE 1줄)"
GUARD="$REPO/harness/comm/mbox_guard_goal.sh"; GUARDREL="${REPO#"$ROOT"/}/harness/comm/mbox_guard_goal.sh"
GUARDOLD="$T/guard-old.sh"; git -C "$ROOT" show "$OLDSHA:$GUARDREL" > "$GUARDOLD" 2>/dev/null || bad "r2 판 가드 사본 못 뜸"
mkdir -p "$T/gbin" "$T/gstate"
printf '#!/usr/bin/env bash\nexec python3 "$GOAL_TOOL" "$@"\n' > "$T/gbin/ft-goal-table.sh"; chmod +x "$T/gbin/ft-goal-table.sh"
R="$T/repo4"; MARK="$R/.fable-team/state/goal-numbering.tsv"; cp "$T/mark-r3" "$MARK"
gtest() {  # <가드 파일> <본문> [첨부] — 가드 한 번 · stdout+stderr
  env GOAL_TOOL="$TOOL" FT_ROOT="$R" FT_NOW="$NOW" FT_SEAT="byz-nano-grace-test#0" \
      FT_GOAL_A6_MD="gitref:origin/main:$CPATH" FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" \
      bash -c 'GOAL_HEADS="^\[(부팅|틱|발주|완료·휴식)"; GUARD_STATE="$1"; DIR="$1"; GT="$2"
        _goal_sender_in_roles() { return 0; }
        _ft_live_bin() { printf "%s" "$GT/gbin/$1"; }
        _goal_refuse() { printf "REFUSE %s\n" "$3" >&2; return 3; }
        . "$3"; _guard_goal_lint "$4" "master-a#1" "${5:-}"' _ "$T/gstate" "$T" "$1" "$2" "${3:-}" 2>&1
}
GBODY="[발주] r726 곡 표 시험"$'\n'"$(base_q)"
GOUT="$(gtest "$GUARD" "$GBODY")"; GRC=$?
[ "$GRC" = 0 ] && ok "ⓠ 가드는 유예 통과를 막지 않는다(rc0)" || bad "ⓠ 가드 rc=$GRC :: $GOUT"
case "$GOUT" in *"GL-GRACE"*"옛 번호표(유예"*) ok "ⓠ 가드 stderr 에 GL-GRACE … 옛 번호표(유예 …) 1줄";; *) bad "ⓠ 가드 경고 0 ← $GOUT";; esac
GOUT="$(gtest "$GUARDOLD" "$GBODY")"
case "$GOUT" in *"GL-GRACE"*) bad "ⓠ 빨강 = r2 판 가드는 경고를 내면 안 되는데 냈다 ← $GOUT";; *) ok "ⓠ 빨강 = r2 판 가드는 rc0 이면 출력을 버렸다(경고 0)";; esac
echo "-- ⓡ·ⓢ relay 경로 — 유예 경고는 «본문 판정 1회» 만(r4 · 첨부 검사에서는 안 낸다)"
GATT="$T/guard-attach.txt"; printf '%s\n' "$B4" > "$GATT"   # 첨부 = 골 표 블록만(골좌표 줄 없음)
GOUT="$(gtest "$GUARD" "[발주] relay 시험"$'\n'"골좌표: 2 — k2" "$GATT")"; GRC=$?
[ "$GRC" = 0 ] || bad "ⓡ relay 유예 통과 rc=$GRC :: $GOUT"
GN="$(printf '%s\n' "$GOUT" | grep -c 'GL-GRACE')"
[ "$GN" = 1 ] && ok "ⓡ relay 유예 = GL-GRACE 1줄(첨부·본문 합쳐)" || bad "ⓡ relay 경고 ${GN}줄(기대 1) ← $GOUT"
GOUT="$(gtest "$GUARDOLD" "[발주] relay 시험"$'\n'"골좌표: 2 — k2" "$GATT")"
[ "$(printf '%s\n' "$GOUT" | grep -c 'GL-GRACE')" = 0 ] && ok "ⓡ 빨강 = r1 판 가드는 relay 에서도 경고 0" || bad "ⓡ 빨강 ← $GOUT"
GUARDR3="$T/guard-r3.sh"; python3 - "$GUARD" "$GUARDR3" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
a = '\n    text="$(_goal_block_of "$GUARD_FILE")'
assert a in s, "r3 판 복원 대상 없음"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(a, '\n    _goal_grace_note "$res"' + a, 1))
PY
GOUT="$(gtest "$GUARDR3" "[발주] relay 시험"$'\n'"골좌표: 2 — k2" "$GATT")"
[ "$(printf '%s\n' "$GOUT" | grep -c 'GL-GRACE')" = 2 ] && ok "ⓡ 빨강2 = r3 판(첨부 경로도 경고)은 같은 relay 에서 경고 2줄" || bad "ⓡ 빨강2 r3 판 경고 $(printf '%s\n' "$GOUT" | grep -c 'GL-GRACE')줄(기대 2) ← $GOUT"
GNEW="$(gtest "$GUARD" "[발주] relay 시험" "$GATT")"; GNRC=$?   # 본문에 골좌표 없음 → REJECT
GOLD="$(gtest "$GUARDOLD" "[발주] relay 시험" "$GATT")"; GORC=$?
[ "$GNEW" = "$GOLD" ] && [ "$GNRC" = "$GORC" ] && ok "ⓢ relay 첨부 유예 + 본문 REJECT = r1 판과 같은 출력·rc($GNRC)" || bad "ⓢ relay REJECT 출력이 r1 판과 다르다 — new(rc=$GNRC)=$GNEW / old(rc=$GORC)=$GOLD"
[ "$GNRC" = 3 ] || bad "ⓢ relay 첨부 유예 + 본문 REJECT 는 rc3 이어야 한다 — rc=$GNRC"
R="$T/repo"; MARK="$T/repo/.fable-team/state/goal-numbering.tsv"   # 뒤 시험을 위해 원래 리포로 되돌린다

echo "== test_goal_renumber_grace_r726: fail=$fail"
[ "$fail" = 0 ]
