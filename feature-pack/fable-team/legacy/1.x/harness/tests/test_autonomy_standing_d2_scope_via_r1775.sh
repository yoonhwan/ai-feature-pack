#!/usr/bin/env bash
# test_autonomy_standing_d2_scope_via_r1775.sh — r1775 «자율 풀자동 중 병합 자동 승인» (카드 r1775-r336-autonomy-auto-merge-switch-window-delete-scope)
#   반례 ①~⑪(진입 조건 · 범위 출처 · 착지 소비자 · 자율 정합 유지 · gate) + 변이 M1~M5
#   격리: 임시 BYZ 리포(명부·판정문)·임시 팩 리포(origin = ssh 스텁) · 가짜 tmux·gh·슬랙 게시 · FT_NOW 고정 · 실 상태 0 · press 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/stub" "$T/fakebin" "$T/da" "$T/pdir"
T0=1800000000; PL='byz-planner-master-claude#105'; HM='byz-harness-master-claude#115'
# ── BYZ 리포 = 명부 루트 · 판정문 리포 · 실제 좌석 = 가짜 tmux 세션명
mkrepo "$T/byz"; B="$W"; mkdir -p "$B/.fable-team"; printf '.fable-team/\n' >> "$B/.git/info/exclude"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$PL" "$B/.fable-team/seats-planner.json"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$HM" "$B/.fable-team/seats-harness.json"
SEATFILE="$T/seatname"; export SEATFILE; printf '%s' "$HM" > "$SEATFILE"
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat "$SEATFILE"; exit 0; }\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$2" >> "%s"\necho "SLACK-TS 1800000000.000100"\n' "$T/slack.log" > "$T/stub/post.sh"
printf '#!/bin/bash\nexit 0\n' > "$T/stub/noop"; chmod +x "$T/stub/"*
S="$T/state"
export FT_ROOT="$B" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/pdir" FT_SEAT="$HM" TMUX_PANE=%9 PATH="$T/fakebin:$PATH"
export FT_SCOPE_SLACK_POST="$T/stub/post.sh"
# ── 팩 리포(하네스 루트 = <리포>/feature-pack/fable-team/harness) · origin = github ssh 꼴(ssh 스텁 → 로컬 bare)
mkrepo "$T/pack"; P="$W"; export PACK_ORIGIN="$ORIGIN"
HB="$P/feature-pack/fable-team/harness"; ELB="$P/feature-pack/fable-team/legacy/1.x/harness/bin"; mkdir -p "$HB/bin" "$HB/kit/fable-team/templates" "$ELB"
echo base > "$HB/bin/ft-x.sh"; echo x > "$HB/kit/fable-team/templates/.keep"; printf 'LOG_LEVEL=debug\n' > "$ELB/.env"; cm "$P" harness; git -C "$P" push -q origin main
git -C "$P" remote set-url origin git@github.com:fake/pack.git
printf '#!/bin/bash\nexec bash -c "$(printf %%s "${!#}" | sed -E "s|'"'"'[^'"'"']*'"'"'|'"'"'$PACK_ORIGIN'"'"'|")"\n' > "$T/stub/ssh"
printf '#!/bin/bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\necho "$*" >> "$STUB_LOG"\nexit 0\n' > "$T/stub/gh"; chmod +x "$T/stub/"*
export GIT_SSH_COMMAND="$T/stub/ssh" FT_HARNESS_ROOT="$HB" FT_SCOPE_PACK_TABLE="$BIN/../kit/fable-team/templates/scope-classes-pack.tsv"
export FT_GH="$T/stub/gh" FT_GH_WRITE="$T/stub/gh" FT_INSTALL_CHECK="$T/stub/noop" STUB_JSON="$T/pr.json" STUB_LOG="$T/gh.log"
git -C "$P" fetch -q origin || { echo "FAIL 팩 픽스처 fetch"; exit 1; }
a() { FT_NOW="$T0" "$BASH" "${ABIN:-$BIN}/ft-autonomy.sh" "$@"; }
as_seat() { printf '%s' "$1" > "$SEATFILE"; export FT_SEAT="$1"; }
nlog() { wc -l < "$1/autonomy.log" | tr -d ' '; }
mkpr() {  # mkpr <N> <파일> [내용…] — 팩 origin/main 에서 PR head 1커밋 → refs/pull/N/head · PRSHA
  git -C "$P" fetch -q origin; git -C "$P" checkout -q -B "pr$1" origin/main; mkdir -p "$P/$(dirname "$2")"
  { echo "pr$1 $RANDOM"; printf '%s\n' "${@:3}"; } >> "$P/$2"; cm "$P" "pr $1"
  git -C "$P" push -q -f origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$P" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":"pr"+sys.argv[2],"title":"feat r1775 PR "+sys.argv[2],"body":"카드 r1775 시험","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"; }
mkda() { DAO="$T/da/$1.out"; printf 'codex\n판정: %s\n\n근거\n\n판정: %s\n' "$2" "$2" > "$DAO"; printf 'head=%s model=gpt-6.1-sol effort=high rc=0 start=1 end=2\n' "$3" > "$DAO.meta"; }
sum256() { shasum -a 256 "$1" | awk '{print $1}'; }
mkv() {  # mkv <이름> <A> <원문> → VF(BYZ origin main + DA 판정 가지 둘 다)
  VF="$B/design/harness/da/VERDICT-$1.md"; mkdir -p "$(dirname "$VF")"
  printf '# 판정 %s\n\n- 승인 sha: %s\n- DA 원문: %s\n- DA 원문 sha256: %s\n- 격리: 세트 %s · rc=0\n' "$1" "$2" "$3" "$(sum256 "$3")" "$2" > "$VF"
  git -C "$B" checkout -q main; cm "$B" "verdict $1" && git -C "$B" push -q origin main && git -C "$B" push -q origin main:refs/heads/docs/da-278062 && git -C "$B" fetch -q origin; }
card() { CARD="$(fx_card_path "$B" card.md)"; printf '# 카드\n\n## 상태\n- 세트: %s · 시험: bash tests/x.sh rc=0 · 이슈: %s\n' "$1" "${2:-0}" > "$CARD"; cardpub; }
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/card_ref_fixture.sh"; cardpub() { fx_card_pub "$B" "$CARD"; }   # r1904: 카드 = 원장(FT_ROOT) 안 · 고정 ref origin/ops/main-base 커밋 판 · r1951: 팀 카드 꼴 + 표 harness 행
PRF="feature-pack/fable-team/legacy/1.x/harness/bin/ft-x.sh"
SC45="approve-scope S45 A16 $T0 until=$((T0 + 3600)) max=20 daily=10 classes=docs,code codemax=5 repos=byz,pack level=full"
autolog() {  # autolog <상태> <레벨> <이벤트> [범위줄] — 자율 ON 1줄 + json + (범위 승인 줄)
  rm -rf "$1"; mkdir -p "$1"; printf '%s\ton\t%s\n' "$T0" "$3" > "$1/autonomy.log"
  [ $# -lt 4 ] || printf '%s\n' "$4" >> "$1/autonomy.log"
  printf '{"mode":"on","since":%s,"event":"%s","until":null,"level":"%s"}\n' "$T0" "$3" "$2" > "$1/autonomy.json"; }
autolog_off() { rm -rf "$1"; mkdir -p "$1"; printf '%s\toff\tA16\n' "$T0" > "$1/autonomy.log"
  printf '{"mode":"off","since":%s,"event":"A16","until":null}\n' "$T0" > "$1/autonomy.json"; }
sa() {  # sa <상태> <sha> <PR> <판정문> [repo]
  local s="$1"; as_seat "${SA_SEAT:-$HM}"
  out="$(FT_NOW="$T0" FT_AUTONOMY_STATE_DIR="$s" "$BASH" "${ABIN:-$BIN}/ft-autonomy.sh" standing-approve D2 "$2" --pr "$3" --repo "${5:-pack}" --verdict "$4" --card "$CARD" 2>&1)"; rc=$?; as_seat "$HM"; }
rej0() {  # rej0 <라벨> <상태> <sha> <사유 정규식> — rc2 · 사유 · 승인 파일/원장/via 없음 · log 줄 수 불변
  [ "$rc" = 2 ] && has "$4" && [ ! -e "$2/autonomy-merge-approved/$3" ] && [ ! -e "$2/autonomy-standing/D2.ledger.tsv" ] && [ ! -e "$2/autonomy-standing/D2.via.tsv" ] && [ "$(nlog "$2")" = "${L0:-$(nlog "$2")}" ]; ck "$1" $?; }

bash -n "$BIN/ft-autonomy-standing-d2.sh"; ck "bash -n ft-autonomy-standing-d2.sh" $?

# ══ ①-a D2 기록 한 번도 없음 — 자율 ON full ∧ S45 활성 ∧ DA APPROVE ∧ gate ALLOW → 승인 · 착지 · Slack 질문 0
S1="$T/s1"; autolog "$S1" full A16 "$SC45"; L0="$(nlog "$S1")"; rm -f "$T/slack.log"
mkpr 11 "$PRF"; A11="$PRSHA"; mkda ok11 APPROVE "$A11"; mkv ok11 "$A11" "$DAO"; V11="$VF"; card "$A11"
grep -q '^approve-standing D2 ' "$S1/autonomy.log" && ck "①-a0 전제: D2 켜짐 줄 없음" 1 || ck "①-a0 전제: D2 켜짐 줄 없음" 0
sa "$S1" "$A11" 11 "$V11"
[ "$rc" = 0 ] && has "^STANDING-OK $A11 pr=11 repo=pack da=$A11 card=card.md by=$HM via=S45$"; ck "①-a1 자율 풀자동 + 활성 S45 → STANDING-OK(via=S45 · 오빠 질문 0)" $?
grep -qx "approve-merge $A11 D2 $T0" "$S1/autonomy.log" && grep -qx "standing-use D2 $A11 $T0 pr=11 repo=pack da=$A11" "$S1/autonomy.log"; ck "①-a2 승인 줄 이벤트 칸 = D2 그대로 · standing-use 꼴" $?
[ ! -s "$T/slack.log" ] && ck "①-a3 승인 단계 슬랙 질문 0(게시 0)" 0 || ck "①-a3 승인 단계 슬랙 질문 0" 1
[ "$(cat "$S1/autonomy-standing/D2.via.tsv")" = "$T0	$A11	A16	S45" ]; ck "①-a4 D2.via.tsv 1행(시각·head·A16·S45)" $?
# ② 착지 → LANDED · D2 착지 알림 1줄 · 원장 착지 칸
out="$(cd "$B" && FT_AUTONOMY_STATE_DIR="$S1" bash "$BIN/ft-merge-land.sh" 11 --approve-sha "$A11" --repo "$P" 2>&1)"; rc=$?
Q11="${out#*sha=}"; Q11="${Q11%% *}"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(git -C "$PACK_ORIGIN" rev-parse refs/heads/main)" = "$Q11" ]; ck "②1 자율 길 승인 기록으로 ft-merge-land → LANDED" $?
grep -q "병합함: PR #11 · 카드 r1775 · DA APPROVE · 되돌림: git revert --no-edit $Q11" "$T/slack.log"; ck "②2 착지 뒤 병합 알림 1줄(fm_land_notify_d2 소비자 그대로)" $?
[ "$(awk -F'\t' -v a="$A11" '$2==a {print $6 "|" $7}' "$S1/autonomy-standing/D2.ledger.tsv")" = "$Q11|git revert --no-edit $Q11" ]; ck "②3 D2 원장 착지 sha·되돌림 칸" $?
# ⑪ 착지 직후 자율 정합 그대로 · 다음 승인 rc0 · via 그 head 1행
out="$(FT_NOW="$T0" FT_AUTONOMY_STATE_DIR="$S1" bash "$BIN/ft-autonomy.sh" status 2>&1)"; rc=$?
[ "$rc" = 0 ] && has '^\[자율 ON A16'; ck "⑪1 착지 뒤 status = 자율 ON 그대로(tamper 0)" $?
mkpr 12 "$PRF"; A12="$PRSHA"; mkda ok12 APPROVE "$A12"; mkv ok12 "$A12" "$DAO"; card "$A12"; sa "$S1" "$A12" 12 "$VF"
[ "$rc" = 0 ] && has "^STANDING-OK $A12 "; ck "⑪2 같은 상태에서 다음 승인도 rc0" $?
[ "$(grep -c "^$T0	$A12	A16	S45$" "$S1/autonomy-standing/D2.via.tsv")" = 1 ] && [ "$(wc -l < "$S1/autonomy-standing/D2.via.tsv" | tr -d ' ')" = 2 ]; ck "⑪3 D2.via.tsv 그 head 정확히 1행" $?

# ══ ①-b D2 standing-stop 뒤 — 옛 D2 줄의 범위(docs)를 안 읽고 S45(code,docs)로 승인
S2="$T/s2"; autolog "$S2" full A16 "$SC45"
printf 'approve-standing D2 %s repos=byz,pack classes=docs oppa_decision=1794302162.301939\nstanding-stop D2 %s 시험 멈춤\n' "$T0" "$T0" >> "$S2/autonomy.log"
mkpr 21 "$PRF"; A21="$PRSHA"; mkda ok21 APPROVE "$A21"; mkv ok21 "$A21" "$DAO"; card "$A21"; sa "$S2" "$A21" 21 "$VF"
[ "$rc" = 0 ] && has "^STANDING-OK $A21 .* via=S45$"; ck "①-b1 D2 정지 뒤에도 S45 범위로 code PR 승인(옛 D2 범위 재사용 0)" $?
grep -q '^\(approve-standing\|standing-stop\) D2 ' "$S2/autonomy.log"; ck "①-b2 뒤: 새 켜짐 줄 없음" $?

# ══ ③④⑤⑥⑧⑨⑩ — 거절 칸
S3="$T/s3"; autolog "$S3" mid A16 "$SC45"; card "$A11"; L0="$(nlog "$S3")"; sa "$S3" "$A11" 11 "$V11"
rej0 "③ 자율 ON ∧ 레벨 mid → 거절(풀자동 아님)" "$S3" "$A11" '① 자율 레벨 full 아님'
S4="$T/s4"; autolog_off "$S4"; L0="$(nlog "$S4")"; sa "$S4" "$A11" 11 "$V11"
rej0 "④ 자율 OFF ∧ D2 꺼짐 → 거절" "$S4" "$A11" '① 상시 승인 D2 꺼짐'
S5="$T/s5"; autolog "$S5" full A16 "approve-scope S45 A16 $T0 until=$((T0 - 60)) max=20 daily=10 classes=docs,code codemax=5 repos=byz,pack level=full"
L0="$(nlog "$S5")"; sa "$S5" "$A11" 11 "$V11"; rej0 "⑤ 활성 S45 없음(만료) → «A 진입 범위 없음» · 쓰기 0" "$S5" "$A11" 'A 진입 범위 없음'
S6="$T/s6"; autolog "$S6" full A16 "approve-scope S46 A16 $T0 until=$((T0 + 3600)) max=20 daily=10 classes=docs repos=byz,pack level=full"
L0="$(nlog "$S6")"; sa "$S6" "$A11" 11 "$V11"; rej0 "⑥ PR 종류가 S46 classes(docs) 밖 → 거절" "$S6" "$A11" '② 종류 code 는 상시 승인 범위'
S6b="$T/s6b"; autolog "$S6b" full A16 "approve-scope S47 A16 $T0 until=$((T0 + 3600)) max=20 daily=10 classes=docs,code"
L0="$(nlog "$S6b")"; sa "$S6b" "$A11" 11 "$V11"; rej0 "⑥b repos 칸 없음 → 기본 byz(팩 PR 거절)" "$S6b" "$A11" '② 저장소 pack 은 승인 범위\(repos=byz\) 밖'
S7="$T/s7"; autolog "$S7" full A16 "$SC45"; mkda hold11 HOLD "$A11"; mkv hold11 "$A11" "$DAO"; VH="$VF"; L0="$(nlog "$S7")"; sa "$S7" "$A11" 11 "$VH"
rej0 "⑧ 판정문 APPROVE 아님 → 거절" "$S7" "$A11" '⑤ DA 마지막 codex 블록이 APPROVE 아님'
S8="$T/s8"; autolog "$S8" full A16 "$SC45"; SKV="sk-$(printf 'x%.0s' $(seq 1 24))"; mkpr 31 "$PRF" "token=\"$SKV\""; A31="$PRSHA"; mkda sec31 APPROVE "$A31"; mkv sec31 "$A31" "$DAO"; card "$A31"; L0="$(nlog "$S8")"; sa "$S8" "$A31" 31 "$VF"
[ "$rc" = 2 ] && has 'FORBID kind=secret' && has '다시: 오빠 h\(approve-merge --oppa-slack\)' && [ ! -e "$S8/autonomy-merge-approved/$A31" ] && [ "$(nlog "$S8")" = "$L0" ]; ck "⑨ secret 경로 → 오빠 답글 길(자율 0 · 쓰기 0)" $?
S9="$T/s9"; autolog "$S9" full A16 "$SC45"; printf '모르는 줄 위변조\n' >> "$S9/autonomy.log"; card "$A11"; L0="$(nlog "$S9")"; sa "$S9" "$A11" 11 "$V11"
rej0 "⑩ autonomy.log 위변조 → tamper 거절" "$S9" "$A11" '위변조'
# ⑦ gate DENY — PR head 뒤로 pack main 이 더 나아감(후보가 main 을 안 품음) → 게이트 DENY
S10="$T/s10"; autolog "$S10" full A16 "$SC45"; mkpr 41 "$PRF"; A41="$PRSHA"; mkda ok41 APPROVE "$A41"; mkv ok41 "$A41" "$DAO"; V41="$VF"; card "$A41"
git -C "$P" checkout -q main; git -C "$P" pull -q origin main; echo later >> "$P/feature-pack/fable-team/legacy/1.x/harness/bin/ft-x.sh"; cm "$P" "main 나아감"; git -C "$P" push -q origin main; git -C "$P" fetch -q origin
L0="$(nlog "$S10")"; sa "$S10" "$A41" 41 "$VF"; rej0 "⑦ gate DENY → STANDING-REJECT · 쓰기 0" "$S10" "$A41" '⑦ merge-gate ALLOW 아님'

# ══ 변이 M1~M5 — 변이 판에서 «빨강이어야 할 칸» 이 통과해 버리는지
mut() {  # mut <이름> <파일> <원문> <바꿀 글> → $T/mut-<이름>
  local mb="$T/mut-$1"; mkdir -p "$mb"; for f in "$BIN"/*; do ln -s "$f" "$mb/$(basename "$f")"; done; rm -f "$mb/$2"
  python3 - "$BIN/$2" "$mb/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}
D2F=ft-autonomy-standing-d2.sh
mkpr 51 "$PRF"; A51="$PRSHA"; mkda ok51 APPROVE "$A51"; mkv ok51 "$A51" "$DAO"; V51="$VF"
mut m1 "$D2F" '  [ "$(jfield level)" = full ] || std_err "① 자율 레벨 full 아님(level=$(jfield level)) — 풀자동만 범위 승인 길"' '  :'
Sm="$T/sm1"; autolog "$Sm" mid A16 "$SC45"; card "$A51"; ABIN="$T/mut-m1" sa "$Sm" "$A51" 51 "$V51"
[ "$rc" = 0 ] && has '^STANDING-OK'; ck "M1 «∧ full» 삭제 → ③ 칸이 승인된다(빨강)" $?
Sm="$T/sm2a"; autolog "$Sm" full A16 "$SC45"; card "$A41"; L0="$(nlog "$Sm")"; sa "$Sm" "$A41" 41 "$V41"
[ "$rc" = 2 ] && has '⑦ merge-gate ALLOW 아님'; ck "M2 대조: 원본은 같은 입력을 ⑦ 에서 거절" $?
mut m2 "$D2F" '  [ -z "${D2_VIA_S:-}" ] || d2_gate "$head"   # r1775 ⑤ 자율 길에만 게이트 ALLOW 재확인' '  :'
Sm="$T/sm2"; autolog "$Sm" full A16 "$SC45"; card "$A41"; ABIN="$T/mut-m2" sa "$Sm" "$A41" 41 "$V41"
[ "$rc" = 0 ] && has '^STANDING-OK'; ck "M2 gate 확인 삭제 → ⑦ 칸이 승인된다(빨강)" $?
mut m3 "$D2F" '  D2_REPOS="$G_REPOS"; D2_CLASSES="$G_CLASSES"; D2_VIA_S="$G_S"; D2_VIA_A="$G_A"' '  d2_on || std_err "옛 D2 줄 없음"; D2_VIA_S="$G_S"; D2_VIA_A="$G_A"'
Sm="$T/sm3"; autolog "$Sm" full A16 "$SC45"; card "$A51"; ABIN="$T/mut-m3" sa "$Sm" "$A51" 51 "$V51"
[ "$rc" = 2 ] && has '옛 D2 줄 없음'; ck "M3 자율 길에서 옛 D2 줄 범위 읽기 → ①-a 칸이 거절된다(빨강)" $?
mut m4 "$D2F" 'line="approve-merge $1 D2 $now"' 'line="approve-merge $1 ${D2_VIA_A:-D2} $now"'
Sm="$T/sm4"; autolog "$Sm" full A16 "$SC45"; card "$A51"; ABIN="$T/mut-m4" sa "$Sm" "$A51" 51 "$V51"
rm -f "$T/slack.log"; out="$(cd "$B" && FT_AUTONOMY_STATE_DIR="$Sm" bash "$BIN/ft-merge-land.sh" 51 --approve-sha "$A51" --repo "$P" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && ! grep -q '병합함' "$T/slack.log" 2>/dev/null; ck "M4 이벤트 칸을 A<N> 으로 씀 → ② 알림 0(빨강)" $?
mut m5 "$D2F" "printf 'standing-use D2 %s %s pr=%s repo=%s da=%s\\n' \"\$1\" \"\$now\" \"\$2\" \"\$D2_RK\" \"\$3\"" "printf 'standing-use D2 %s %s pr=%s repo=%s da=%s via=%s\\n' \"\$1\" \"\$now\" \"\$2\" \"\$D2_RK\" \"\$3\" \"\${D2_VIA_S:-x}\""
mkpr 52 "$PRF"; A52="$PRSHA"; mkda ok52 APPROVE "$A52"; mkv ok52 "$A52" "$DAO"; V52="$VF"
Sm="$T/sm5"; autolog "$Sm" full A16 "$SC45"; card "$A52"; ABIN="$T/mut-m5" sa "$Sm" "$A52" 52 "$V52"
out="$(FT_NOW="$T0" FT_AUTONOMY_STATE_DIR="$Sm" bash "$T/mut-m5/ft-autonomy.sh" status 2>&1)"; rc=$?
has '위변조'; ck "M5 출처를 log suffix 로 씀 → ⑪ 착지 뒤 tamper(빨강)" $?

# ══ 키트 사본 · 줄 수
cmp -s "$BIN/$D2F" "$BIN/../kit/fable-team/bin/$D2F"; ck "키트 사본 cmp0 $D2F" $?
[ "$(wc -l < "$BIN/$D2F")" -le 200 ]; ck "줄 수 상한 standing-d2 200" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
