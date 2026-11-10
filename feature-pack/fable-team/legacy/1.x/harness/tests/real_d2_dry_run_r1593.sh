#!/usr/bin/env bash
# real_d2_dry_run_r1593.sh — r1593 ⓔ 실측: 실 판정문 1건으로 D2 standing-approve «항목별» dry-run → 남은 거절 사유를 전부 1줄씩 낸다(항목 = ①d2_on ②d2_repo+d2_classify ③④std_verdict ⑤std_da_out ⑥std_equiv ④카드 시험 세트 ⑤크리티컬)
#   읽기 전용 — lock·d2_write·원장·로그 쓰기 0(앞뒤 지문 비교로 확인) · 항목마다 서브셸 1개(std_err 의 exit 은 그 서브셸만 끝낸다) · 항목당 timeout 70(하드 룰 22)
#   쓰는 법: bash feature-pack/fable-team/legacy/1.x/harness/tests/real_d2_dry_run_r1593.sh  · 입력은 env FT_DRY_* 로만 바꾼다(기본 = r1592 실 판정문 aifp#861)
#   닫는 조건 = 전 항목 PASS · rc 0 = 전 항목 PASS · rc 1 = 거절 있음(그 줄들이 r1593 이 아직 못 닫은 사유) · rc 2 = 입력/루트 없음
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
V="${FT_DRY_VERDICT:-/tmp/da-278062-verdict/design/harness/DA-r1592-280374.md}"
A="${FT_DRY_SHA:-4190a13e5f124813a467b716ca11fec0d1b4f596}"
CARD="${FT_DRY_CARD:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops-m175/design/harness/indices/완성/r1592-merge-land-close-pr-right-after-push.md}"
RK="${FT_DRY_REPO:-pack}"; ROOT="${FT_ROOT:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents}"
[ -n "$ROOT" ] && [ -f "$V" ] || { echo "REJECT 입력 없음 — 루트=${ROOT:-없음} 판정문=$V"; exit 2; }
STATE="${FT_AUTONOMY_STATE_DIR:-$ROOT/.fable-team/state}"; LOG="$STATE/autonomy.log"; PACK="$(git -C "$BIN" rev-parse --show-toplevel 2>/dev/null)"
PRE="HERE='$BIN'; STATE='$STATE'; LOG='$LOG'; ROOT='$ROOT'; . \"\$HERE/ft-autonomy-level.sh\"; . \"\$HERE/ft-autonomy-standing-d2.sh\";"   # 레벨 파일 = ft-autonomy.sh 가 먼저 source 하는 것과 같은 문맥(tpl_file)
B4="$( { shasum -a 256 "$LOG" 2>/dev/null; ls -1 "$STATE" 2>/dev/null | wc -l; } | shasum -a 256)"   # 쓰기 0 확인용 앞 지문
if grep -qE '^approve-standing D2 [0-9]+ ' "$LOG" 2>/dev/null; then RANGE=live; else RANGE=declared; fi   # 실 로그에 D2 승인 줄이 없으면 ② 이후를 «내용» 으로 판정하려고 범위만 선언값으로(실 상태 변경 0)
DR="${FT_DRY_REPOS:-byz,pack}"; DC="${FT_DRY_CLASSES:-code,docs}"
CTX="D2_REPOS='$DR'; D2_RK='$RK'; D2_REPO='$PACK'; PREPO=\$D2_REPO; SCOPE_REPO=\$D2_REPO; D2_CLASSES='$DC'; D2_CLS='code';"
echo "DRY-D2 판정문=$V · 승인=$A · repo=$RK · 범위=$RANGE($DR/$DC) · 상태=$STATE(읽기만)"
n=0; bad=""
item() {  # <라벨> <셸 조각> — 서브셸 1개 · timeout 70 · rc0 = PASS · rc≠0 = STANDING-REJECT 1줄
  local o r
  o="$( timeout 70 bash -c "$PRE $CTX $2" 2>&1 )"; r=$?
  if [ "$r" = 0 ]; then echo "PASS $1"; else echo "STANDING-REJECT $1 :: $(printf '%s' "$o" | head -1)"; n=$((n+1)); bad="${bad}$1 "; fi
}
item "① d2_on(실 로그 그대로)" 'd2_on || { echo "① 상시 승인 D2 꺼짐(approve-standing D2 줄 없음 또는 standing-stop 뒤)"; exit 1; }'
item "② d2_repo+d2_classify" "d2_repo '$RK'; d2_classify '$A'"
item "③④ std_verdict(D2_VREF · 4줄 · 원문 sha256)" "std_verdict '$V' \"\$D2_VREF\""
item "⑤ std_da_out(마지막 codex 블록 APPROVE · .meta head=A rc=0)" "std_verdict '$V' \"\$D2_VREF\"; std_da_out \"\$V_OUT\" \"\$V_A\""
item "⑥ std_equiv(승인 sha ↔ 대상 sha)" "std_verdict '$V' \"\$D2_VREF\"; std_equiv \"\$V_A\" '$A'"
item "④ 카드 시험 세트(scope_code_check)" "scope_code_check '$A' '$CARD'"
item "⑤ 크리티컬 0(d2_critical)" "d2_critical '$A'"
T2="$(mktemp -d)"; trap 'rm -rf "$T2"' EXIT; mkdir -p "$T2/design/harness"   # 자체 확인: «승인 sha:» 줄을 지운 사본 → ③④ 만 새로 거절
sed '/^승인 sha:/d' "$V" > "$T2/design/harness/DA-r1592-280374.md"; git -C "$T2" init -q
git -C "$T2" add -A; git -C "$T2" -c user.email=t@t -c user.name=t commit -qm mut; TREF="$(git -C "$T2" symbolic-ref --short HEAD)"
o="$( timeout 70 bash -c "$PRE ROOT='$T2'; std_verdict '$T2/design/harness/DA-r1592-280374.md' '$TREF'" 2>&1 )"; r=$?
if [ "$r" != 0 ] && [[ "$o" == *"«승인 sha:» 줄이 0개"* ]]; then echo "PASS SELFCHECK(«승인 sha:» 줄 지운 사본 → ③④ STANDING-REJECT)"; else echo "STANDING-REJECT SELFCHECK :: rc=$r $(printf '%s' "$o" | head -1)"; n=$((n+1)); bad="${bad}SELFCHECK "; fi
AF="$( { shasum -a 256 "$LOG" 2>/dev/null; ls -1 "$STATE" 2>/dev/null | wc -l; } | shasum -a 256)"
[ "$B4" = "$AF" ] && echo "PASS WRITE-0(실 상태 지문 불변)" || { echo "STANDING-REJECT WRITE-0 :: 실 상태가 바뀌었다"; n=$((n+1)); bad="${bad}WRITE-0 "; }
echo "남은 거절 사유 ${n}건 — ${bad:-없음}"
[ "$n" = 0 ]
