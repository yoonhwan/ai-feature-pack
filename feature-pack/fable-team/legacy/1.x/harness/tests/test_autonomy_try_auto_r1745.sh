#!/usr/bin/env bash
# test_autonomy_try_auto_r1745.sh — r1745 «묻기 전에 먼저 시도» try-auto + brief (계약 A1·A2·A4·A5·A6·A7·A8·A9·A10 · 반례 ①~⑪ · 변이 M1~M5)
#   격리: 임시 BYZ 리포(명부·DA 판정문)·임시 팩 리포 · 가짜 tmux·분류기 큐 · FT_NOW 고정 · 실 상태·실 슬랙·실 원격·실 gh 0
#   press 0(나노는 쏘지 않는다) · D2·S 켜기 줄은 픽스처가 직접 쓴다(r1577 시험이 켜기 길을 이미 본다) — 쓰기 경로는 기존 명령 그대로 부른다
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:320}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
hasin() { grep -qE -- "$1" <<<"$2"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/fakebin" "$T/da" "$T/pdir"
T0=1800000000; OD=1794302162.301939; PL='byz-planner-master-claude#105'; HM='byz-harness-master-claude#115'
# ── BYZ 리포 = 명부 루트 · 판정문 리포 · 실제 좌석 = 가짜 tmux 세션명
mkrepo "$T/byz"; B="$W"; mkdir -p "$B/.fable-team"; printf '.fable-team/\n' >> "$B/.git/info/exclude"
for t in planner harness; do python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$HM" "$B/.fable-team/seats-$t.json"; done
SEATFILE="$T/seatname"; export SEATFILE; printf '%s' "$HM" > "$SEATFILE"
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat "$SEATFILE"; exit 0; }\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/stub-noop"; chmod +x "$T/stub-noop"
# ── 팩 리포(FT_HARNESS_ROOT) — kit/fable-team 이 있어야 ft_harness_root 가 받는다
mkrepo "$T/pack"; P="$W"; mkdir -p "$P/kit/fable-team" "$P/fixtures"; echo x > "$P/kit/fable-team/.keep"; cm "$P" kit; git -C "$P" push -q origin main
S="$T/state"; LOG="$S/autonomy.log"
export FT_ROOT="$B" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/pdir" FT_SEAT="$HM" TMUX_PANE=%9 FT_HARNESS_ROOT="$P" PATH="$T/fakebin:$PATH"
# ── 분류기 = 큐 1줄씩(시험마다 명시) · 실 분류기 0 · classify 와 check-revert 두 갈래
cat > "$T/cls.py" <<'EOF'
import os, sys
if sys.argv[1:2] == ["check-revert"]: print("OK"); raise SystemExit(0)
q = os.environ["STUB_QUEUE"]; lines = [x for x in open(q, encoding="utf-8").read().splitlines() if x.strip()] if os.path.exists(q) else []
out = lines.pop(0) if lines else "CLASS code"
open(q, "w", encoding="utf-8").write("".join(x + "\n" for x in lines))
print(out); raise SystemExit(3 if out.split()[:1] in (["FORBID"], ["CRITICAL"]) else 0)
EOF
export FT_SCOPE_CLASSIFY="$T/cls.py" STUB_QUEUE="$T/cls.queue" FT_SCOPE_PACK_TABLE="$BIN/../kit/fable-team/templates/scope-classes-pack.tsv"
q() { printf '%s\n' "$@" > "$STUB_QUEUE"; }
onfix() {  # onfix [S classes] [S until] — 자율 ON · 범위 S1 · D2 켜짐(픽스처가 log 에 직접 · 켜기 길은 r1577 시험 몫)
  rm -rf "$S"; mkdir -p "$S"; printf '%s\ton\tA17\n' "$T0" > "$LOG"
  printf '{"mode":"on","since":%s,"event":"A17","until":null,"level":"full"}\n' "$T0" > "$S/autonomy.json"
  printf 'approve-scope S1 A17 %s until=%s max=30 daily=15 classes=%s codemax=5 repos=byz,pack\n' "$T0" "${2:-$((T0 + 3600))}" "${1:-code,docs}" >> "$LOG"
  printf 'approve-standing D2 %s repos=byz,pack classes=code,docs oppa_decision=%s\n' "$T0" "$OD" >> "$LOG"
}
offfix() { rm -rf "$S"; mkdir -p "$S"; printf '%s\toff\tA17\n' "$T0" > "$LOG"; printf '{"mode":"off","since":%s,"event":"A17","until":null,"level":"full"}\n' "$T0" > "$S/autonomy.json"; }
sum256() { shasum -a 256 "$1" | awk '{print $1}'; }
mkda() { DAO="$T/da/$1.out"; printf 'codex\n판정: %s\n\n근거\n\n판정: %s\n' "$2" "$2" > "$DAO"; printf 'head=%s model=gpt-6.1-sol effort=high rc=0 start=1 end=2\n' "$3" > "$DAO.meta"; }
mkv() {  # mkv <이름> <A> <원문> → VF (BYZ origin/main + DA 판정 가지 둘 다에 커밋)
  VF="$B/design/harness/da/VERDICT-$1.md"; mkdir -p "$(dirname "$VF")"
  printf '# 판정 %s\n\n- 승인 sha: %s\n- DA 원문: %s\n- DA 원문 sha256: %s\n- 격리: 세트 %s · rc=0\n' "$1" "$2" "$3" "$(sum256 "$3")" "$2" > "$VF"
  git -C "$B" checkout -q main; cm "$B" "verdict $1" && git -C "$B" push -q origin main && git -C "$B" push -q origin main:refs/heads/docs/da-278062 && git -C "$B" fetch -q origin; }
card() { CARD="$(fx_card_path "$B" "card-$1.md")"; printf '# 카드\n\n## 상태\n- 세트: %s · 시험: bash tests/x.sh rc=0 · 이슈: 0\n' "$1" > "$CARD"; cardpub; }
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/card_ref_fixture.sh"; cardpub() { fx_card_pub "$B" "$CARD"; }   # r1904: 카드 = 원장(FT_ROOT) 안 · 고정 ref origin/ops/main-base 커밋 판 · r1951: 팀 카드 꼴 + 표 harness 행
mkpr() {  # mkpr <경로> [내용…] → PRSHA(팩 리포 새 커밋)
  git -C "$P" checkout -q -B "prx$RANDOM" main; mkdir -p "$P/$(dirname "$1")"
  { echo "x $RANDOM"; printf '%s\n' "${@:2}"; } >> "$P/$1"; cm "$P" "pr $1"; PRSHA="$(sha "$P" HEAD)"; }
tryit() { out="$(FT_NOW="$T0" "$BASH" "${ABIN:-$BIN}/ft-autonomy.sh" try-auto "$@" 2>&1)"; rc=$?; }
briefit() { out="$(FT_NOW="$T0" "$BASH" "${ABIN:-$BIN}/ft-autonomy.sh" brief 2>&1)"; rc=$?; }
desk() {  # 뉴스 ③ 오빠 손 블록(자율 1줄 포함)
  FT_DESK_AUTONOMY="$BIN/ft-autonomy.sh" FT_DESK_STATE="$T/desk" FT_DESK_HIL="$T/stub-noop" FT_DESK_DECISION="$T/stub-noop" \
    FT_DESK_GIT="$T/stub-noop" FT_DESK_LAND_REPO="$B" FT_DESK_TOOL_TIMEOUT=7 FT_NOW="$T0" python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from pathlib import Path
import ft_news_desk_oppa as m
print("\n".join(m.oppa_block(Path(sys.argv[2]))))' "$BIN/../kit/fable-team/bin" "$B"; }

bash -n "$BIN/ft-autonomy.sh" && bash -n "$BIN/ft-autonomy-try.sh" && bash -n "$BIN/ft-autonomy-standing.sh"; ck "bash -n 3종" $?
python3 -c "import ast;ast.parse(open('$BIN/../kit/fable-team/bin/ft_news_desk_oppa.py').read())"; ck "python ast(desk)" $?

# ══ ① 자율 ON · D2 켜짐 · DA APPROVE 판정문 · code PR → TRY-OK via=D2 · D2 원장 1줄
onfix; mkpr "scripts/zz-r1745-a.sh" "echo a"; A1="$PRSHA"; card "$A1"; mkda ok1 APPROVE "$A1"; mkv ok1 "$A1" "$DAO"; V1="$VF"
q "CLASS code" "CRITICAL-OK"; tryit "$A1" --pr 11 --repo pack --card "$CARD" --verdict "$V1"; o1="$out"
[ "$rc" = 0 ] && has "^TRY-OK via=D2 STANDING-OK $A1 pr=11 repo=pack da=$A1 "; ck "① code PR(D2 통과) → TRY-OK via=D2 + 기존 명령 끝줄" $?
[ -f "$S/autonomy-merge-approved/$A1" ] && [ "$(awk -F'\t' -v a="$A1" '$2==a {print $3}' "$S/autonomy-standing/D2.ledger.tsv")" = 11 ]; ck "① 승인 파일·D2 원장 1줄(PR 11 · k기록은 기존 명령 몫)" $?
grep -qx "standing-use D2 $A1 $T0 pr=11 repo=pack da=$A1" "$LOG"; ck "① D2 원장·log 꼴 그대로(이 동사가 직접 쓴 줄 0)" $?

# ══ ② --verdict 없음 · S 살아 있음 · docs PR → TRY-OK via=S1 · S 원장 1줄
onfix; mkpr "design/r1745-doc.md" "doc 1"; A2="$PRSHA"; card "$A2"; q "CLASS docs"; tryit "$A2" --pr 12 --repo pack --card "$CARD"; o2="$out"
[ "$rc" = 0 ] && has "^TRY-OK via=S1 SCOPE-OK $A2 class=docs"; ck "② 판정문 없음 → S 시도 → TRY-OK via=S1" $?
[ "$(awk -F'\t' -v a="$A2" '$2==a {print $3}' "$S/autonomy-scope/S1.ledger.tsv")" = 12 ]; ck "② S 원장 1줄(PR 12 — 동사가 직접 쓴 것 0)" $?

# ══ ③ D2 거절(크리티컬) + S 거절(classes 밖) → TRY-REJECT 두 사유 · rc 2 · 원장 0
onfix docs; mkpr "design/r1745-c.md" "doc 3"; A3="$PRSHA"; card "$A3"; mkda ok3 APPROVE "$A3"; mkv ok3 "$A3" "$DAO"; V3="$VF"
q "CLASS docs" "CRITICAL kind=destroy git branch -D" "CLASS code"; tryit "$A3" --pr 13 --repo pack --card "$CARD" --verdict "$V3"; o3="$out"
[ "$rc" = 2 ] && has '^TRY-REJECT ⑤ 크리티컬: destroy' && has '종류 code 는 승인 범위\(docs\) 밖'; ck "③ 둘 다 거절 → TRY-REJECT <D2 사유> · <S 사유> rc 2(A4 거절 보존)" $?
[ ! -e "$S/autonomy-merge-approved/$A3" ] && [ ! -e "$S/autonomy-standing/D2.ledger.tsv" ]; ck "③ 승인 파일·원장 0(거절이 통과로 안 바뀐다)" $?

# ══ ④ 자율 OFF → TRY-SKIP rc 3 · D2·S 호출 0
offfix; n0="$(grep -c . "$LOG")"; tryit "$A1" --pr 11 --repo pack --card "$CARD" --verdict "$V1"; o4="$out"
[ "$rc" = 3 ] && has '^TRY-SKIP 자율 OFF$' && [ "$(grep -c . "$LOG")" = "$n0" ] && [ ! -e "$S/autonomy-merge-approved" ]; ck "④ 자율 OFF → TRY-SKIP rc 3 · 호출·쓰기 0" $?

# ══ ⑤ 범위 만료 → S «기간 끝 도달» · D2 가 통과하면 via=D2
onfix code,docs "$((T0 - 60))"; q "CLASS docs" "CRITICAL kind=destroy x"; tryit "$A3" --pr 13 --repo pack --card "$CARD" --verdict "$V3"; o5="$out"
[ "$rc" = 2 ] && has '기간 끝 도달'; ck "⑤ 만료된 S → S 사유 «기간 끝 도달(=만료)»" $?
onfix code,docs "$((T0 - 60))"; card "$A1"; q "CLASS code" "CRITICAL-OK"; tryit "$A1" --pr 11 --repo pack --card "$CARD" --verdict "$V1"
[ "$rc" = 0 ] && has '^TRY-OK via=D2'; ck "⑤ S 만료여도 D2 통과 = via=D2" $?

# ══ ⑥ brief 3꼴 + 뉴스 ③ 첫 줄 같은 글자
onfix; briefit; b1="$out"; has '^자율 ON A17 · 범위 S1 ~[0-9][0-9]:[0-9][0-9] · 사용 0/30\(code 0/5\) · 상시 D2 켜짐$'; ck "⑥a ON·S 살아 있음·D2 켜짐 → 1줄(사용·code·D2 글자)" $?
offfix; briefit; has '^자율 OFF · 병합·착수는 오빠 질문$'; ck "⑥b OFF → «자율 OFF · 병합·착수는 오빠 질문»" $?
rm -rf "$S"; briefit; has '^자율 상태 확인 불가' && ! has '자율 (ON|OFF)'; ck "⑥c 상태 폴더 못 읽음 → «자율 상태 확인 불가»(ON·OFF 글자 0 · 추정 0)" $?
onfix; out="$(desk 2>/dev/null)"; rc=$?; [ "$(sed -n '1p' <<<"$out")" = "## 오빠 손" ] && [ "$(sed -n '2p' <<<"$out")" = "- 자율: $b1" ]; ck "⑥d 뉴스 ③ 오빠 손 첫 줄 = same brief 글자" $?

# ══ ⑦ 질문 구분(사람 말 1줄) — ①③④ 결과에서
hasin '^SHARE 범위 안 · 질문 없이 진행\(상시 D2\) · PR 11$' "$o1"; ck "⑦a TRY-OK → «범위 안 · 질문 없이 진행(상시 D2)»" $?
hasin '^범위 밖 · 오빠 질문 — ⑤ 크리티컬' "$o3"; ck "⑦b TRY-REJECT → «범위 밖 · 오빠 질문 — <사유>»" $?
hasin '^자율 OFF · 오빠 질문$' "$o4"; ck "⑦c TRY-SKIP → «자율 OFF · 오빠 질문»" $?

# ══ ⑧ Slack 공유 1줄 — 통과에도 남기고 거절·SKIP 은 질문 머리 그대로(글 꼴만 · 실 발신 0)
hasin '^SHARE .* · PR 11$' "$o1" && ! hasin '^SHARE' "$o3" && ! hasin '^SHARE' "$o4"; ck "⑧ TRY-OK = SHARE 1줄 · 거절·SKIP = 질문 머리 그대로" $?

# ══ ⑨ standing-status = D1·D2 한 줄씩
onfix; out="$(FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" standing-status 2>&1)"; rc=$?
has '^\[상시 승인 D1 꺼짐\]$' && has '^\[상시 승인 D2 켜짐 · 코드 병합 · 문서 병합'; ck "⑨ standing-status 가 D2 켜짐을 보여준다(D1 줄 그대로)" $?

# ══ ⑩ 판정문 꼴 — ⓐ 리포 상대 경로 → 리포 루트 기준 · ⓑ «승인 sha:» 줄 0
git -C "$B" checkout -q -B byzpr1 main; mkdir -p "$B/scripts"; echo "echo hi" > "$B/scripts/zz-r1745.sh"; cm "$B" "byz pr 14"; BSHA="$(sha "$B" HEAD)"; git -C "$B" checkout -q main
card "$BSHA"; mkda okb APPROVE "$BSHA"; mkv okb "$BSHA" "$DAO"; VB="$VF"; onfix; q "CLASS code" "CRITICAL-OK"
tryit "$BSHA" --pr 14 --repo byz --card "$CARD" --verdict "design/harness/da/VERDICT-okb.md"
[ "$rc" = 0 ] && has "^TRY-OK via=D2 STANDING-OK $BSHA pr=14 repo=byz" && ! has '③ 판정문 없음'; ck "⑩a 상대 경로 판정문 → 리포 루트 기준 절대 경로로 통과" $?
VF2="$B/design/harness/da/VERDICT-nosha.md"; printf '# 판정\n\n- DA 원문: %s\n' "$DAO" > "$VF2"; git -C "$B" add -A >/dev/null && git -C "$B" commit -qm nosha && git -C "$B" push -q origin main && git -C "$B" push -q origin main:refs/heads/docs/da-278062 && git -C "$B" fetch -q origin
onfix docs; q "CLASS code"; tryit "$A3" --pr 13 --repo pack --card "$CARD" --verdict "$VF2"
[ "$rc" = 2 ] && has 'DA 판정문 D2 꼴 아님\(승인 sha: 줄 0\)' && has '종류 code 는 승인 범위'; ck "⑩b «승인 sha:» 줄 0 → D2 사유 그대로 + 이어서 S 시도" $?

# ══ ⑪ 분류기 «여러 줄 env 대입 뒤 명령» 재현(팩 #987 실사건 꼴) — 오탐 0 이면 고칠 것 없음, 결과를 그대로 적는다
git -C "$P" checkout -q -B prF main; mkdir -p "$P/feature-pack/fable-team/legacy/1.x/harness/tests"; printf 'FT_A=1 \\\nFT_B=2 \\\nbash run.sh\n' > "$P/feature-pack/fable-team/legacy/1.x/harness/tests/env-multi.sh"; cm "$P" "env multi"; ESHA="$(sha "$P" HEAD)"
out="$(python3 "$BIN/autonomy_scope_classify.py" classify "$ESHA" --repo "$P" --remote origin --target main --scope S0 --table "$BIN/../kit/fable-team/templates/scope-classes-pack.tsv" 2>&1)"; rc=$?
seen="$(python3 -c "import sys;sys.path.insert(0,'$BIN');import ft_secret_judge as j;print(j.plan(open('$P/feature-pack/fable-team/legacy/1.x/harness/tests/env-multi.sh',encoding='utf-8').read()))" 2>&1)"
closed="$(python3 -c "import sys;sys.path.insert(0,'$BIN');import ft_secret_judge as j;print(j.plan('env A=1 \"\$BASH\" x.sh\n')[0][1][:20])" 2>&1)"
echo "⑪ 재현 결과: 실 분류기 = «${out:0:60}» · plan(여러 줄 env+명령) = «${seen}» · 닫힌 쪽(env + \$BASH) = «${closed}»"
[ "$rc" = 0 ] && has '^CLASS (code|docs|ff)$' && ! has 'FORBID'; ck "⑪ 여러 줄 env 대입 뒤 리터럴 명령 = FORBID 아님(오탐 재현 0 · 고칠 줄 0)" $?

# ══ 변이 M1~M5 — 변이 판이 «빨강이어야 할 칸» 을 통과시키는지(각 변이 뒤 원본 같은 사례로 반대 결과 대조)
mut() {  # mut <이름> <파일> <원문> <바꿀 글>
  local mb="$T/mut-$1"; rm -rf "$mb"; mkdir -p "$mb"; for f in "$BIN"/*; do ln -s "$f" "$mb/$(basename "$f")"; done; rm -f "$mb/$2"
  python3 - "$BIN/$2" "$mb/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}
TF=ft-autonomy-try.sh
mut m1 "$TF" 'if [ -n "$vf" ] && d2_on; then' 'if false; then'; onfix; card "$A1"; q "CLASS code"
ABIN="$T/mut-m1" tryit "$A1" --pr 11 --repo pack --card "$CARD" --verdict "$V1"; has '^TRY-OK via=S1' && ! has 'via=D2'; ck "㉠M1 D2 단계 삭제 → ① 칸이 via=S 로 바뀐다(빨강)" $?
onfix; card "$A1"; q "CLASS code" "CRITICAL-OK"; tryit "$A1" --pr 11 --repo pack --card "$CARD" --verdict "$V1"; has '^TRY-OK via=D2'; ck "㉠M1 원본 대조: 같은 입력 = via=D2(초록)" $?
mut m2 "$TF" 'scope-approve "$head" --pr "$pr" --card "$card" --repo "$rk" >"$o" 2>"$e"; then' 'scope-approve "$head" --pr "$pr" --card "$card" --repo "$rk" >"$o" 2>"$e" || true; then'
onfix docs; q "CLASS docs" "CRITICAL kind=destroy x" "CLASS code"; ABIN="$T/mut-m2" tryit "$A3" --pr 13 --repo pack --card "$CARD" --verdict "$V3"
[ "$rc" = 0 ] && has '^TRY-OK'; ck "㉠M2 S 거절을 통과로(rc 무시) → ③ 칸이 승인된다(빨강)" $?
onfix docs; q "CLASS docs" "CRITICAL kind=destroy x" "CLASS code"; tryit "$A3" --pr 13 --repo pack --card "$CARD" --verdict "$V3"; [ "$rc" = 2 ]; ck "㉠M2 원본 대조: 같은 입력 = rc 2(초록)" $?
mut m3 "$TF" '[ "$(mode)" = on ] || { printf' ': || { printf'; offfix
ABIN="$T/mut-m3" tryit "$A1" --pr 11 --repo pack --card "$CARD" --verdict "$V1"; ! has '^TRY-SKIP'; ck "㉠M3 OFF 확인 삭제 → ④ 칸이 TRY-SKIP 이 아니다(빨강)" $?
offfix; tryit "$A1" --pr 11 --repo pack --card "$CARD" --verdict "$V1"; [ "$rc" = 3 ] && has '^TRY-SKIP'; ck "㉠M3 원본 대조: 같은 입력 = TRY-SKIP rc 3(초록)" $?
mut m4 "$TF" '{ echo "자율 상태 확인 불가(상태 폴더 없음: $STATE)"; return 0; }' '{ echo "자율 OFF · 병합·착수는 오빠 질문"; return 0; }'; rm -rf "$S"
ABIN="$T/mut-m4" briefit; has '자율 OFF'; ck "㉠M4 못 읽음을 OFF 로 냄 → ⑥c 칸이 «자율 OFF»(빨강)" $?
rm -rf "$S"; briefit; has '^자율 상태 확인 불가'; ck "㉠M4 원본 대조: 같은 조건 = «자율 상태 확인 불가»(초록)" $?
mut m5 "$TF" 'if d2_on; then echo "자율 ON $ev · $s · 상시 D2 켜짐"; else echo "자율 ON $ev · $s · 상시 D2 꺼짐"; fi' 'echo "자율 ON $ev · $s"'; onfix
ABIN="$T/mut-m5" briefit; ! has '상시 D2 켜짐'; ck "㉠M5 brief 의 D2 칸 삭제 → ⑥a 칸이 D2 글자 없음(빨강)" $?
onfix; briefit; has '상시 D2 켜짐'; ck "㉠M5 원본 대조: 같은 상태 = «상시 D2 켜짐»(초록)" $?

# ══ 크기·사본 — 파일 상한 · bin↔kit cmp0(사본 있는 파일만) · 새 파일 실행 비트 0
[ "$(wc -l < "$BIN/ft-autonomy.sh")" -le 200 ] && [ "$(wc -l < "$BIN/ft-autonomy-try.sh")" -le 100 ] && [ "$(wc -l < "$BIN/ft-autonomy-standing.sh")" -le 198 ]; ck "줄 수 상한(autonomy ≤200 · try ≤100 · standing ≤198)" $?
for f in ft-autonomy.sh ft-autonomy-standing.sh ft-autonomy-try.sh; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f"; ck "키트 사본 cmp0 $f" $?; done
[ ! -x "$BIN/ft-autonomy-try.sh" ] && [ ! -x "$HERE/test_autonomy_try_auto_r1745.sh" ]; ck "새 파일 실행 비트 0(644)" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
