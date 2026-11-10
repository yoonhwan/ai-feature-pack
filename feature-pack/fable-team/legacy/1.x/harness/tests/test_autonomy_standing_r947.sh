#!/usr/bin/env bash
# test_autonomy_standing_r947.sh — r947 오빠 D1 «외부 DA APPROVE 팩 PR 상시 승인» (카드 r947-d1-standing-approve-external-da-pack-land 시험 ⓐ~ⓘ)
# 격리: 임시 BYZ 리포(판정문 = origin/main 커밋 · DA 원문 = 로컬) · 임시 팩 리포(origin = 깃허브 ssh 꼴 → ssh 스텁이 로컬 bare 로) · 가짜 tmux(실제 좌석)
#       · 가짜 gh · 슬랙 게시 스텁 · FT_NOW 고정 — 실 gh·실 슬랙·실 원격·실 상태 0 · GIT_* env 0 · FT_R947_SKIP_OLD=1 이면 ⓗ(기존 시험 묶음) 생략
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "$HERE/../bin" && pwd -P)"; TOP="$(git -C "$HERE" rev-parse --show-toplevel)"; BASEREF="${FT_R947_BASE:-origin/main}"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/stub" "$T/fakebin" "$T/da" "$T/pdir"
T0=1800000000; SEAT='byz-planner-master-claude#105'

# ── BYZ 리포(명부 루트 · 판정문 리포) + 실제 좌석 = 가짜 tmux 세션명
mkrepo "$T/byz"; B="$W"
mkdir -p "$B/.fable-team"; printf '.fable-team/\n' >> "$B/.git/info/exclude"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$SEAT" "$B/.fable-team/seats-planner.json"
SEATFILE="$T/seatname"; export SEATFILE; printf '%s' "$SEAT" > "$SEATFILE"
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat "$SEATFILE"; exit 0; }\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
S="$T/state"; LOG="$S/autonomy.log"
export FT_ROOT="$B" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/pdir" FT_SEAT="$SEAT" TMUX_PANE=%9 PATH="$T/fakebin:$PATH"
printf '#!/usr/bin/env bash\necho "SLACK-TS 1800000000.000100"\n' > "$T/stub/post.sh"; export FT_SCOPE_SLACK_POST="$T/stub/post.sh"

# ── 팩 리포(하네스 루트 = <리포>/feature-pack/fable-team/harness) · origin = git@github.com:fake/pack.git (ssh 스텁 → 로컬 bare)
mkrepo "$T/pack"; P="$W"; export PACK_ORIGIN="$ORIGIN"
HB="$P/feature-pack/fable-team/harness"; mkdir -p "$HB/kit/fable-team/bin" "$HB/bin"; echo base > "$HB/bin/ft-x.sh"; cm "$P" harness; git -C "$P" push -q origin main
git -C "$P" remote set-url origin git@github.com:fake/pack.git
printf '#!/bin/bash\nexec bash -c "$(printf %%s "${!#}" | sed -E "s|'"'"'[^'"'"']*'"'"'|'"'"'$PACK_ORIGIN'"'"'|")"\n' > "$T/stub/ssh"
printf '#!/bin/bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\necho "$*" >> "$STUB_LOG"\nexit 0\n' > "$T/stub/gh"
printf '#!/bin/bash\nexit 0\n' > "$T/stub/noop"; chmod +x "$T/stub"/*
export GIT_SSH_COMMAND="$T/stub/ssh" FT_HARNESS_ROOT="$HB" FT_SCOPE_PACK_TABLE="$BIN/../kit/fable-team/templates/scope-classes-pack.tsv"
export FT_GH="$T/stub/gh" FT_GH_WRITE="$T/stub/gh" STUB_JSON="$T/pr.json" STUB_LOG="$T/gh.log" FT_INSTALL_CHECK="$T/stub/noop"
git -C "$P" fetch -q origin || { echo "FAIL 팩 픽스처 fetch"; exit 1; }

a() { FT_NOW="$T0" "$BASH" "${ABIN:-$BIN}/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
nlog() { grep -c . "$LOG" 2>/dev/null || true; }
fresh() { rm -rf "$S"; mkdir -p "$S"; }
grant() { run a approve-standing D1 --repos pack --classes "${1:-code,docs}"; }
sa() { L0="$(nlog)"; run a standing-approve "$1" --pr "$2" --repo pack --verdict "$3"; }
rej() { [ "$rc" = 2 ] && has "$3" && has '다시: 오빠 h\(approve-merge' && [ ! -e "$S/autonomy-merge-approved/$2" ] && [ "$(nlog)" = "$L0" ]; ck "$1" $?; }   # 거절 = rc2 · 사유 · «다시» 줄 · 승인 파일 0 · log 줄 0
seat_set() { printf '%s' "$1" > "$SEATFILE"; }
mode_state() { printf '%s\t%s\tA1\n' "$T0" "$1" > "$LOG"; printf '{"mode":"%s","since":%s,"event":"A1","until":null}\n' "$1" "$T0" > "$S/autonomy.json"; }
mkpr() {  # mkpr <N> <파일> [base 가지] — 팩 origin/main(또는 base)에서 PR head(그 파일 1줄 추가) → refs/pull/N/head · STUB_JSON · PRSHA
  git -C "$P" fetch -q origin; git -C "$P" checkout -q -B "pr$1" "${3:-origin/main}"
  mkdir -p "$P/$(dirname "$2")"; echo "pr$1 $RANDOM" >> "$P/$2"; cm "$P" "pr $1"
  git -C "$P" push -q -f origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$P" HEAD)"; pjson "$1"; }
pjson() { python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":"pr"+sys.argv[2],"title":"feat: PR "+sys.argv[2],"body":"본문","state":"OPEN","baseRefName":"main"}))' "$(sha "$P" HEAD)" "$1" > "$STUB_JSON"; }
mkda() {  # mkda <이름> <meta head|nometa> <마지막 블록 판정> [앞 블록 판정] [모델] — codex exec 원문 꼴 → DAO
  DAO="$T/da/$1.out"
  { printf 'OpenAI Codex v0.163.0\n--------\nworkdir: /tmp/repo-x\nmodel: gpt-6.1-sol\n--------\nuser\n질문 1\n'
    [ -z "${4:-}" ] || printf 'codex\n판정: %s\n\n중간 의견\n판정: %s\nexec\nbash -lc ls\n' "$4" "$4"
    printf 'codex\n판정: %s\n\n근거 본문\n\n판정: %s\n' "$3" "$3"; } > "$DAO"
  [ "$2" = nometa ] || printf 'head=%s model=%s effort=high rc=0 start=1 end=2\n' "$2" "${5:-gpt-6.1-sol}" > "$DAO.meta"; }
sum256() { shasum -a 256 "$1" | awk '{print $1}'; }
mkv() {  # mkv <이름> <A> <원문> [격리 세트] [local] → VF — 기본은 BYZ origin/main 에 커밋·push
  VF="$B/design/harness/da/VERDICT-$1.md"; mkdir -p "$(dirname "$VF")"
  printf '# 판정 %s\n\n- 승인 sha: %s\n- DA 원문: %s\n- DA 원문 sha256: %s\n- 격리: 세트 %s · rc=0\n\n판정: APPROVE\n' "$1" "$2" "$3" "$(sum256 "$3")" "${4:-$2}" > "$VF"
  [ "${5:-}" = local ] || { cm "$B" "verdict $1" && git -C "$B" push -q origin main && git -C "$B" fetch -q origin; }; }
PF="feature-pack/fable-team/harness/bin/ft-x.sh"

bash -n "$BIN/ft-autonomy.sh" && bash -n "$BIN/ft-autonomy-standing.sh" && bash -n "$BIN/ft-merge-land.sh"; ck "bash -n 3종" $?

# ══ ⓐ 빨강 먼저: 지금 판(origin/main) ft-autonomy.sh = 상시 승인 명령 없음
mkdir -p "$T/red"; for f in "$BIN"/*; do ln -s "$f" "$T/red/$(basename "$f")"; done; rm -f "$T/red/ft-autonomy.sh" "$T/red/ft-autonomy-standing.sh"
git -C "$TOP" show "$BASEREF:feature-pack/fable-team/harness/bin/ft-autonomy.sh" > "$T/red/ft-autonomy.sh" || { echo "FAIL 옛 판 못 꺼냄"; exit 1; }
fresh; mkpr 5 "$PF"; A5="$PRSHA"; mkda ok5 "$A5" APPROVE; mkv ok5 "$A5" "$DAO"; V5="$VF"
ABIN="$T/red" run a approve-standing D1 --repos pack --classes code,docs; r1=$rc; ABIN="$T/red" sa "$A5" 5 "$V5"
[ "$r1" = 2 ] && [ "$rc" = 2 ] && has '^usage:' && [ ! -e "$S/autonomy-merge-approved/$A5" ]; ck "ⓐ0 지금 판 = approve-standing·standing-approve 없음(usage rc2 · 승인 파일 0)" $?
grant; [ "$rc" = 0 ] && has "^STANDING-GRANTED D1 repos=pack classes=code,docs slack_ts=1800000000.000100$"; ck "ⓐ1 approve-standing → 슬랙 1글 먼저 · GRANTED" $?
grep -qx "approve-standing D1 $T0 repos=pack classes=code,docs da=external" "$LOG" && grep -q "slack_ts=1800000000.000100$" "$S/autonomy-standing/grants.audit"; ck "ⓐ2 log 줄 꼴 · grants.audit 슬랙 ts" $?
sa "$A5" 5 "$V5"
[ "$rc" = 0 ] && has "^STANDING-OK $A5 pr=5 repo=pack da=$A5 by=$SEAT$"; ck "ⓐ3 standing-approve A → STANDING-OK(좌석 = 실측 planner)" $?
grep -qx "standing-use D1 $A5 $T0 pr=5 repo=pack da=$A5" "$LOG" && grep -qx "approve-merge $A5 D1 $T0" "$LOG" && [ "$(cat "$S/autonomy-merge-approved/$A5")" = "approve-merge $A5 D1 $T0" ]; ck "ⓐ4 log 2줄 + 승인 파일(같은 줄)" $?
[ "$(a mode)" = off ] && [ "$(a status)" = "[자율 OFF]" ]; ck "ⓐ5 자율 OFF 에서 통과 · 위변조 아님" $?
M5="$(sha "$P" origin/main)"; out="$(cd "$B" && bash "$BIN/ft-merge-land.sh" 5 --approve-sha "$A5" --repo "$P" 2>&1)"; rc=$?; Q5="${out#*sha=}"; Q5="${Q5%% *}"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(git -C "$PACK_ORIGIN" rev-parse refs/heads/main)" = "$Q5" ] && [ "$Q5" != "$M5" ]; ck "ⓐ6 ft-merge-land A → LANDED(팩 main = 착지 sha · 오빠 h 0)" $?
grep -q "head=$A5 .*landed=$Q5 pr=5 approve=$A5 approve-file=$T0 standing=D1$" "$S/merge-gate.log"; ck "ⓐ7 merge-gate.log approve=A approve-file … standing=D1" $?
[ "$(awk -F'\t' -v a="$A5" '$2==a {print $3 "|" $4 "|" $5 "|" $6 "|" $7}' "$S/autonomy-standing/D1.ledger.tsv")" = "5|da=$A5|$DAO|$Q5|git revert --no-edit $Q5" ]; ck "ⓖ1 D1 원장 = PR·da·DA 원문 경로·착지 sha·되돌림 명령" $?
run a standing-status --since "$T0"
[ "$rc" = 0 ] && has '^\[상시 승인 D1 켜짐 · 팩 코드 병합 · 문서 병합' && has "^외부 DA 승인으로 바로 착지한 팩 PR 1건이에요\.$" && has "팩 PR #5 · 착지 ${Q5:0:10} · 되돌림: git revert --no-edit $Q5"; ck "ⓖ2 standing-status --since = 사람 말 1덩이" $?
run a standing-status --since $((T0 + 1)); has '없어요\.$'; ck "ⓖ3 --since 뒤 행 없음 = «없어요»" $?

# ══ ⓑ 거절 — 전부 rc2 · 승인 파일 0 · log 줄 0 · «다시: 오빠 h(approve-merge)»
fresh; mkpr 6 "$PF"; A6="$PRSHA"; mkda ok6 "$A6" APPROVE; mkv ok6 "$A6" "$DAO"; V6="$VF"; OK6="$DAO"
sa "$A6" 6 "$V6"; rej "ⓑ1 상시 승인 줄 없음 → ① 거절" "$A6" '① 상시 승인 D1 꺼짐'
grant; run a standing-stop D1 "시험 멈춤"; [ "$rc" = 0 ] && grep -qx "standing-stop D1 $T0 시험 멈춤" "$LOG"; ck "ⓑ2a standing-stop 줄" $?
sa "$A6" 6 "$V6"; rej "ⓑ2 standing-stop 뒤 → ① 거절" "$A6" '① 상시 승인 D1 꺼짐'
grant; run a standing-status; has '켜짐'; ck "ⓑ2b stop 뒤 새 approve-standing = 다시 켜짐" $?
mkda hold6 "$A6" HOLD APPROVE; mkv hold6 "$A6" "$DAO"; VH="$VF"; sa "$A6" 6 "$VH"; rej "ⓑ3 DA 마지막 블록 HOLD(앞 블록 APPROVE 섞음) → 거절" "$A6" '⑤ DA 마지막 codex 블록이 APPROVE 아님'
mkda tail6 "$A6" APPROVE; printf '판정: HOLD\n' >> "$DAO"; mkv tail6 "$A6" "$DAO"; sa "$A6" 6 "$VF"; rej "ⓑ3b 블록 첫 줄 APPROVE · 끝 판정 줄 HOLD → 거절" "$A6" '⑤ DA 마지막'
mkda tailc6 "$A6" APPROVE; printf '최종 검토가 완료되지 않았습니다.\n' >> "$DAO"; mkv tailc6 "$A6" "$DAO"; VT="$VF"; sa "$A6" 6 "$VF"; rej "ⓐ-tail APPROVE 원문 끝에 판정 아닌 줄 1줄 추가 → 거절(마지막 비어 있지 않은 줄 검사 · DA 반례 2)" "$A6" '⑤ DA 마지막 codex 블록이 APPROVE 아님'
mkda nometa6 nometa APPROVE; mkv nometa6 "$A6" "$DAO"; sa "$A6" 6 "$VF"; rej "ⓑ4 .meta 없음 → 거절" "$A6" '⑤ DA 원문 \.meta 없음'
mkda mh6 "$(sha "$P" origin/main)" APPROVE; mkv mh6 "$A6" "$DAO"; VMH="$VF"; sa "$A6" 6 "$VMH"; rej "ⓑ4b .meta head ≠ A → 거절" "$A6" '⑤ \.meta head'
mkda cl6 "$A6" APPROVE "" claude-opus-5-5; mkv cl6 "$A6" "$DAO"; sa "$A6" 6 "$VF"; rej "ⓑ4c DA 모델 claude 계열 → 거절" "$A6" 'claude 계열'
mkda loc6 "$A6" APPROVE; mkv loc6 "$A6" "$DAO" "" local; VL="$VF"; sa "$A6" 6 "$VL"; rej "ⓑ5 판정문이 BYZ origin/main 에 없음(로컬만) → 거절" "$A6" '③ 판정문이 BYZ origin/main 에 없음'
mkda sw6 "$A6" APPROVE; mkv sw6 "$A6" "$DAO"; VSW="$VF"; SWO="$DAO"; printf '\n덧붙인 줄\n판정: APPROVE\n' >> "$SWO"; sa "$A6" 6 "$VSW"; rej "ⓑ6 DA 원문 sha256 ≠ 판정문(판정 뒤 바꿔치기) → 거절" "$A6" '④ DA 원문 sha256'
mkv iso6 "$A6" "$OK6" "$M5"; sa "$A6" 6 "$VF"; rej "ⓑ6b 격리 세트 ≠ 승인 sha → 거절" "$A6" '④ 격리 줄'
mkpr 7 README-outside.md; A7="$PRSHA"; mkda ok7 "$A7" APPROVE; mkv ok7 "$A7" "$DAO"; V7="$VF"; sa "$A7" 7 "$V7"; rej "ⓑ7 팩 분류표 forbid(repo-outside) → 거절" "$A7" '② 분류기 거절 rc=3: FORBID kind=repo-outside'
fresh; grant code; mkpr 8 feature-pack/fable-team/NOTES.md; A8="$PRSHA"; mkda ok8 "$A8" APPROVE; mkv ok8 "$A8" "$DAO"; sa "$A8" 8 "$VF"; rej "ⓑ8 종류 docs ∉ classes=code → 거절" "$A8" '② 종류 docs 는 상시 승인 범위'
fresh; grant; sa "$A8" 8 "$VF"; [ "$rc" = 0 ] && has "^STANDING-OK $A8 "; ck "ⓑ8b 대조: 문서만 PR(분류기 ff = docs) · classes=code,docs → 통과" $?
fresh; grant; sa "$A6" 6 "$V6"; [ "$rc" = 0 ] && has "^STANDING-OK $A6 "; ck "ⓑ0 대조: 같은 PR·좋은 판정문 = 통과(거절 사유가 그 칸 하나뿐)" $?
sa "$A6" 6 "$V6"; [ "$rc" = 0 ] && has "^STANDING-NOOP $A6" && [ "$(nlog)" = "$L0" ]; ck "ⓑ0b 같은 head 두 번 = NOOP(쓰기 0)" $?
mkpr 10 "$PF"; A10="$PRSHA"; mkda taild10 "$A10" APPROVE; printf '\n\n  \n' >> "$DAO"; mkv taild10 "$A10" "$DAO"; sa "$A10" 10 "$VF"
[ "$rc" = 0 ] && has "^STANDING-OK $A10 "; ck "ⓐ-tail2 끝의 빈 줄만 = 통과(마지막 «비어 있지 않은» 줄)" $?

# ══ ⓒ head ≠ A: main 병합만이면 EQUIV 통과(use 줄 da=A) · 자기 변경이 다르면 거절
git -C "$P" checkout -q -B mv origin/main; echo moved > "$P/feature-pack/fable-team/harness/bin/other.sh"; cm "$P" "main moves"; git -C "$P" push -q origin mv:main
git -C "$P" checkout -q pr6; git -C "$P" merge -q --no-edit origin/main; H6="$(sha "$P" HEAD)"
sa "$H6" 6 "$V6"; [ "$rc" = 0 ] && has "^STANDING-OK $H6 pr=6 repo=pack da=$A6 equiv=$A6 by=$SEAT$" && grep -qx "standing-use D1 $H6 $T0 pr=6 repo=pack da=$A6" "$LOG"; ck "ⓒ1 A 위 main 병합만 → EQUIV 통과 · use 줄 da=A" $?
echo self-change >> "$P/$PF"; cm "$P" "self change"; H6b="$(sha "$P" HEAD)"; sa "$H6b" 6 "$V6"; rej "ⓒ2 자기 변경이 다름 → ⑥ 거절" "$H6b" '⑥ head ≠ 승인 sha'

# ══ ⓓ 좌석 제한: planner master 밖 = 거절(문서 전용 예외와 같은 좌석 함수 · 실제 좌석)
fresh; grant; mkpr 9 "$PF"; A9="$PRSHA"; mkda ok9 "$A9" APPROVE; mkv ok9 "$A9" "$DAO"; V9="$VF"
for x in 'byz-planner-arch-claude#16' 'byz-harness-master-claude#115' 'byz-harness-nano-r947-x#0'; do
  seat_set "$x"; L0="$(nlog)"; out="$(FT_SEAT="$x" FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" standing-approve "$A9" --pr 9 --repo pack --verdict "$V9" 2>&1)"; rc=$?
  rej "ⓓ $x → 거절" "$A9" 'ⓓ planner master 좌석만'
done
seat_set 'byz-harness-nano-r947-x#0'; L0="$(nlog)"; out="$(FT_DOC_EXEMPT_SELFTEST=1 FT_DOC_EXEMPT_SEAT="$SEAT" FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" standing-approve "$A9" --pr 9 --repo pack --verdict "$V9" 2>&1)"; rc=$?
rej "ⓓ2 실제 좌석 나노 · SELFTEST·자기신고를 planner 로 위조 → 거절(env -u)" "$A9" 'ⓓ planner master 좌석만'
seat_set "$SEAT"

# ══ ⓕ 모드 무관: 자율 ON·OFF(json 있음) 모두 통과 · scope 한도 안 셈
fresh; mode_state on; grant; sa "$A9" 9 "$V9"
[ "$rc" = 0 ] && [ "$(a mode)" = on ] && [[ "$(a status)" == "[자율 ON A1 "* ]] && ! grep -q '^scope-use ' "$LOG" && [ "$(a scope-status)" = "[범위 승인 없음]" ]; ck "ⓕ1 자율 ON 에서 통과 · mode on 그대로 · scope-use 0" $?
fresh; mode_state off; grant; sa "$A9" 9 "$V9"; [ "$rc" = 0 ] && [ "$(a mode)" = off ]; ck "ⓕ2 자율 OFF(json 있음)에서 통과 · mode off" $?

# ══ ⓔ log 정합: 새 꼴 4종이 있어도 mode·status 정상 · 꼴 하나라도 틀린 줄 = tamper
fresh; mode_state on; grant; sa "$A9" 9 "$V9"; run a standing-stop D1 "끝"; printf 'approve-merge %s D1 %s\n' "$A9" "$T0" >> "$LOG"
[ "$(a mode)" = on ] && [[ "$(a status)" != *위변조* ]]; ck "ⓔ1 approve-standing·standing-use·standing-stop·approve-merge D1 → 위변조 아님" $?
cp "$LOG" "$T/log.bak"; bad=0
for l in "standing-use D1 $A9 $T0 pr=9 repo=pack" "approve-standing D1 $T0 repos=byz classes=code da=external" "approve-standing D1 $T0 repos=pack classes=code,ff da=external" \
         "approve-merge $A9 D2 $T0" "standing-stop D1 $T0" "standing-use D2 $A9 $T0 pr=9 repo=pack da=$A9" "approve-standing D1 $T0 repos=pack classes=code da=internal"; do
  cp "$T/log.bak" "$LOG"; printf '%s\n' "$l" >> "$LOG"; [ "$(a mode)" = tamper ] && [ "$(a status)" = "[자율 ?? 위변조 → OFF]" ] || { bad=1; echo "  tamper 아님: $l"; }
done; cp "$T/log.bak" "$LOG"; [ "$bad" = 0 ]; ck "ⓔ2 꼴 틀린 줄 7종 → 전부 tamper" $?
printf 'standing-use D1 %s %s pr=9 repo=pack\n' "$A9" "$T0" >> "$LOG"; run a approve-standing D1 --repos pack --classes code; [ "$rc" = 2 ] && has '위변조'; ck "ⓔ3 tamper 면 approve-standing 거절" $?
cp "$T/log.bak" "$LOG"

# ══ ft-da-codex.sh .meta — head = codex «전» cwd HEAD · git 아님 = none · stdout 계약 그대로
DAC="$BIN/../kit/fable-team/bin/ft-da-codex.sh"; mkdir -p "$T/codexbin" "$T/home"
printf '#!/bin/bash\n[ -n "${FAKE_COMMIT:-}" ] && git -C "$FAKE_COMMIT" commit -q --allow-empty -m da-commit\necho "판정: APPROVE"\nexit 0\n' > "$T/codexbin/codex"; chmod +x "$T/codexbin/codex"
printf 'q\n' > "$T/p.txt"; HB0="$(sha "$B" HEAD)"
out="$(HOME="$T/home" CODEX_HOME="$T/home" FAKE_COMMIT="$B" PATH="$T/codexbin:$PATH" bash "$DAC" --cwd "$B" --prompt-file "$T/p.txt" --out-dir "$T/dac" 2>/dev/null)"; rc=$?; DF="${out#OUT }"; DF="${DF% rc=*}"
[ "$rc" = 0 ] && [[ "$out" =~ ^OUT\ .*\.out\ rc=0$ ]] && [[ "$(cat "$DF.meta")" =~ ^head=$HB0\ model=gpt-6\.1-sol\ effort=high\ rc=0\ start=[0-9]+\ end=[0-9]+$ ]] && [ "$(sha "$B" HEAD)" != "$HB0" ]; ck "da-codex .meta head = 실행 «전» HEAD(codex 가 커밋해도) · 끝줄 OUT 그대로" $?
git -C "$B" reset -q --hard "$HB0"
out="$(HOME="$T/home" CODEX_HOME="$T/home" PATH="$T/codexbin:$PATH" bash "$DAC" --cwd "$T/home" --prompt-file "$T/p.txt" --out-dir "$T/dac" 2>/dev/null)"; DF="${out#OUT }"; DF="${DF% rc=*}"
grep -q '^head=none ' "$DF.meta"; ck "da-codex cwd 가 git 아님 → head=none(상시 승인 거절 쪽)" $?

# ══ ⓧ r5 (arch 149 안1) — D1 켜기는 «쓰기 자리» 좌석 판정: 경유(heredoc·eval·변수 조립·사본)와 무관하게 planner master 만
HKIT="$(cd "$HERE/../kit" && pwd -P)"; mkdir -p "$T/hk"; cp "$HKIT/fable-team/templates/hooks/autonomy-"*.sh "$HKIT/hooks/merge_cmd.py" "$T/hk"/
snap() { if [ -f "$LOG" ]; then shasum -a 256 "$LOG" | awk '{print $1}'; else echo none; fi; }
hok() {  # hok <명령> <이름> — 훅 판정 = allow(stdout 0줄) + WARN 1줄(막지 않는다)
  local j; j="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$1" "$B")"
  out="$(printf '%s' "$j" | FT_AUTONOMY_HOOK_LOG="$T/hk.log" "$BASH" "$T/hk/autonomy-state-guard.sh" 2>"$T/hk.err")"; rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ] && ! grep -q permissionDecision <<<"$out" && grep -q '^WARN autonomy-state-guard' "$T/hk.err"; ck "$2" $?; }
HCMD="\"$BASH\" \"$BIN/ft-autonomy.sh\" approve-standing D1 --repos pack --classes code,docs"
HDOC="$(printf '/bin/bash <<%sEOF%s\n%s\nEOF' "'" "'" "$HCMD")"
sta() { out="$(FT_SEAT="$SEAT" FT_NOW="$T0" "$BASH" -c "$1" 2>&1)"; rc=$?; }
SREJ='STANDING-REJECT approve-standing D1 — 호출 좌석 byz-harness-nano-r947-x#0 ≠ planner master · 쓰기 0'
NANO='byz-harness-nano-r947-x#0'
fresh; seat_set "$NANO"; N0="$(snap)"
hok "$HDOC" "ⓧ1a 훅: 좌석의 heredoc approve-standing → allow + WARN(글자 검사는 보조)"
sta "$HDOC"
[ "$rc" = 2 ] && has "$SREJ" && [ "$(snap)" = "$N0" ] && [ ! -e "$S/autonomy-standing" ]; ck "ⓧ1 도구 안 좌석 판정: r4 반례 heredoc 경유 → rc2 · 상태·원장·슬랙 쓰기 0" $?
mkdir -p "$T/r5bin"; for f in "$BIN"/*; do ln -s "$f" "$T/r5bin/$(basename "$f")"; done; cp "$BIN/ft-autonomy.sh" "$T/r5bin/x.sh"
for c in "eval '$HCMD'" "T=\"$BIN/ft-autonomy.sh\"; \"\$T\" approve-standing D1 --repos pack --classes code,docs" "bash \"$T/r5bin/x.sh\" approve-standing D1 --repos pack --classes code,docs"; do
  sta "$c"
  [ "$rc" = 2 ] && has "$SREJ" && [ "$(snap)" = "$N0" ]; ck "ⓧ2 경유 묶음(eval·변수 조립·사본) → rc2 · 쓰기 0: ${c:0:36}" $?
done
seat_set "$SEAT"; fresh
sta "$HDOC"
[ "$rc" = 0 ] && has '^STANDING-GRANTED D1 repos=pack classes=code,docs slack_ts=1800000000.000100$' && grep -qx "approve-standing D1 $T0 repos=pack classes=code,docs da=external" "$LOG"; ck "ⓧ3 정상 경로: 실제 좌석 = planner 명부 _master → rc0 GRANTED · 원장 줄 1" $?
fresh
out="$(FT_DOC_EXEMPT_SELFTEST=1 FT_DOC_EXEMPT_SEAT="$SEAT" FT_SEAT="$SEAT" FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" approve-standing D1 --repos pack --classes code,docs 2>&1)"; rc=$?
[ "$rc" = 3 ] && has 'SELFTEST' && [ ! -e "$S/autonomy-standing" ] && [ ! -e "$LOG" ]; ck "ⓧ4 SELFTEST env 켜짐 → rc3 · 승인 0(설계된 방어 그대로)" $?
seat_set "$SEAT"

# ══ ⓘ 변이 — 변이마다 «빨강이어야 할 칸» 이 변이 판에서 통과해 버리는지(= 그 칸이 그 검사를 실제로 잡는다)
mut() {  # mut <이름> <파일> <원문> <바꿀 글> [<원문2> <바꿀 글2>] → MB
  MB="$T/mut-$1"; mkdir -p "$MB"; for f in "$BIN"/*; do ln -s "$f" "$MB/$(basename "$f")"; done; rm -f "$MB/$2"
  python3 - "$BIN/$2" "$MB/$2" "${@:3}" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read(); r = sys.argv[3:]
for i in range(0, len(r), 2):
    assert s.count(r[i]) == 1, r[i]; s = s.replace(r[i], r[i + 1])
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY
}
msa() {  # msa <변이 이름> <head> <PR> <판정문> [좌석] — 새 상태 폴더에서 approve-standing 뒤 standing-approve(변이 판)
  local st="$T/ms-$1"; rm -rf "$st"; mkdir -p "$st"; seat_set "${5:-$SEAT}"
  out="$(FT_SEAT="${5:-$SEAT}" FT_AUTONOMY_STATE_DIR="$st" FT_NOW="$T0" "$BASH" "$MB/ft-autonomy.sh" approve-standing D1 --repos pack --classes code,docs 2>&1 && \
         FT_SEAT="${5:-$SEAT}" FT_AUTONOMY_STATE_DIR="$st" FT_NOW="$T0" "$BASH" "$MB/ft-autonomy.sh" standing-approve "$2" --pr "$3" --repo pack --verdict "$4" 2>&1)"; rc=$?; seat_set "$SEAT"; }
SD=ft-autonomy-standing.sh
mut m1 "$SD" '[ "$r" = $'"'"'판정: APPROVE\t판정: APPROVE'"'"' ] ||' 'grep -q "^판정: APPROVE" "$f" ||'; msa m1 "$A6" 6 "$VH"
[ "$rc" = 0 ]; ck "ⓘ1 변이(마지막 블록 대신 아무 «판정: APPROVE» 줄) → ⓑ3 HOLD 섞음 칸 빨강" $?
mut m7 "$SD" 'c && NF {last=$0}' 'c && /^판정:/ {last=$0}'; msa m7 "$A6" 6 "$VT"
[ "$rc" = 0 ]; ck "ⓘ7 변이(끝줄 검사 끔 = 마지막 «판정:» 줄만) → ⓐ-tail 칸 빨강" $?
mut m2 "$SD" '[ "${BASH_REMATCH[1]}" = "$2" ] || std_err "⑤ .meta head' 'true || std_err "⑤ .meta head'; msa m2 "$A6" 6 "$VMH"
[ "$rc" = 0 ]; ck "ⓘ2 변이(.meta head 대조 끔) → ⓑ4b 칸 빨강" $?
mkv loc6 "$A6" "$T/da/loc6.out" "" local; VL="$VF"
mut m3 "$SD" 'git -C "$ROOT" cat-file -e "refs/remotes/origin/main:$rel" 2>/dev/null ||' 'true ||' 'body="$(git -C "$ROOT" show "refs/remotes/origin/main:$rel")"' 'body="$(cat "$f")"'; msa m3 "$A6" 6 "$VL"
[ "$rc" = 0 ]; ck "ⓘ3 변이(origin/main 존재 검사 끔 · 로컬 판정문 읽기) → ⓑ5 칸 빨강" $?
rm -f "$VL"
mut m4 "$SD" '[ "$got" = "$sum" ] ||' 'true ||'; msa m4 "$A6" 6 "$VSW"
[ "$rc" = 0 ]; ck "ⓘ4 변이(sha256 대조 끔) → ⓑ6 칸 빨강" $?
mut m5 ft-autonomy.sh ' || "$line" =~ $STANDING_GRANT_RE || "$line" =~ $STANDING_USE_RE || "$line" =~ $STANDING_STOP_RE' ''
rm -rf "$T/ms-m5"; mkdir -p "$T/ms-m5"; printf '%s\ton\tA1\n' "$T0" > "$T/ms-m5/autonomy.log"; printf '{"mode":"on","since":%s,"event":"A1","until":null}\n' "$T0" > "$T/ms-m5/autonomy.json"
FT_AUTONOMY_STATE_DIR="$T/ms-m5" FT_NOW="$T0" "$BASH" "$MB/ft-autonomy.sh" approve-standing D1 --repos pack --classes code,docs >/dev/null 2>&1
[ "$(FT_AUTONOMY_STATE_DIR="$T/ms-m5" "$BASH" "$MB/ft-autonomy.sh" mode)" = tamper ]; ck "ⓘ5 변이(log 새 꼴 등록 끔) → ⓔ1 칸 빨강(tamper)" $?
mut m6 "$SD" '  std_seat
  lock;' '  STD_BY=mut
  lock;' 'STD_SEAT_ERR=""; STD_SEAT_ACTUAL="unknown"' 'STD_SEAT_ERR=""; STD_SEAT_ACTUAL="unknown"; STD_BY=mut; return 0'; msa m6 "$A9" 9 "$V9" 'byz-harness-nano-r947-x#0'
[ "$rc" = 0 ]; ck "ⓘ6 변이(좌석 검사 끔) → ⓓ 칸 빨강" $?
mut m8 "$SD" '  std_seat_probe || {' '  true || {'
st="$T/ms-m8"; rm -rf "$st"; mkdir -p "$st"; seat_set "$NANO"
out="$(FT_SEAT="$SEAT" FT_AUTONOMY_STATE_DIR="$st" FT_NOW="$T0" "$BASH" "$MB/ft-autonomy.sh" approve-standing D1 --repos pack --classes code,docs 2>&1)"; rc=$?; seat_set "$SEAT"
[ "$rc" = 0 ] && has 'STANDING-GRANTED'; ck "ⓘ8 변이(approve-standing 좌석 판정 호출 끔) → ⓧ1·ⓧ2 칸 빨강(좌석 위조로 승인됨)" $?
mut m9 "$SD" 'std_t7 env -u FT_DOC_EXEMPT_SELFTEST -u FT_DOC_EXEMPT_SEAT python3' 'std_t7 python3'
st="$T/ms-m9"; rm -rf "$st"; mkdir -p "$st"
out="$(FT_DOC_EXEMPT_SELFTEST=1 FT_DOC_EXEMPT_SEAT="$SEAT" FT_SEAT="$SEAT" FT_AUTONOMY_STATE_DIR="$st" FT_NOW="$T0" "$BASH" "$MB/ft-autonomy.sh" approve-standing D1 --repos pack --classes code,docs 2>&1)"; rc=$?
[ "$rc" = 2 ] && has 'STANDING-REJECT approve-standing'; ck "ⓘ9 변이(env -u 삭제) → ⓧ4 칸 빨강(SELFTEST 가 rc3 이어야 할 자리가 rc2)" $?
mut m10 "$SD" '  std_t7 env -u FT_DOC_EXEMPT_SELFTEST -u FT_DOC_EXEMPT_SEAT python3 "$dx" --mode planner-seat --repo "$ROOT" --root "$ROOT"
  if [ "$RC" = 0 ] && [[ "$FIRST" =~ ^PLANNER-SEAT\ ([A-Za-z0-9#_-]+)$ ]]; then STD_BY="${BASH_REMATCH[1]}"; return 0; fi' '  if [ -n "${FT_SEAT:-}" ]; then STD_BY="$FT_SEAT"; return 0; fi'
st="$T/ms-m10"; rm -rf "$st"; mkdir -p "$st"; seat_set "$NANO"
out="$(FT_SEAT="$SEAT" FT_AUTONOMY_STATE_DIR="$st" FT_NOW="$T0" "$BASH" "$MB/ft-autonomy.sh" approve-standing D1 --repos pack --classes code,docs 2>&1)"; rc=$?; seat_set "$SEAT"
[ "$rc" = 0 ] && has 'STANDING-GRANTED'; ck "ⓘ10 변이(planner-seat 대신 FT_SEAT 자기 신고만) → ⓧ1 칸 빨강" $?

# ══ ⓗ 기존 시험(autonomy·scope·merge-land·da-codex·doc-exempt·훅) · 키트 사본 · 줄 수
for f in ft-autonomy.sh ft-autonomy-standing.sh ft-merge-land.sh ft_doc_exempt.py; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f"; ck "키트 사본 cmp0 $f" $?; done
[ "$(wc -l < "$BIN/ft-autonomy.sh")" -le 200 ] && [ "$(wc -l < "$BIN/ft-autonomy-standing.sh")" -le 200 ] && [ "$(wc -l < "$BIN/ft-merge-land.sh")" -le 120 ]; ck "줄 수 상한(autonomy 200 · standing 200 · merge-land 120)" $?
if [ -z "${FT_R947_SKIP_OLD:-}" ]; then
  for t in test_autonomy_core test_autonomy_scope test_autonomy_scope_pack test_autonomy_kinds_1675 test_autonomy_hooks test_merge_land test_merge_land_pack_repo test_merge_land_equiv test_merge_land_off_approval test_da_codex_wrapper test_doc_exempt_r725; do
    "$BASH" "$HERE/$t.sh" > "$T/$t.out" 2>&1; r=$?
    [ "$r" = 0 ]; ck "ⓗ $t rc=0 ($(grep -c '^PASS' "$T/$t.out" | tr -d ' ') PASS)" $?
  done
fi
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
