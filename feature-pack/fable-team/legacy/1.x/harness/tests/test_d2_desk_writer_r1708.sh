#!/usr/bin/env bash
# test_d2_desk_writer_r1708.sh — r1708 N2: 상시 승인 D2 쓰기 좌석에 desk 를 더한다(자율 ON ∧ 레벨 full 일 때만) · desk 길에만 merge-tree 충돌 0 검사.
#   ⑤ desk + ON full + D2 켜짐 + 판정문 APPROVE + head 일치 + 충돌 0 → STANDING-OK by=desk · 승인 파일 1 · 원장 1행 (기준판 = «ⓑ 팀 master 좌석만»)
#   ⑥ 자율 OFF·mid·each·tamper → REJECT «desk 승인은 자율 풀자동에서만» · 쓰기 0  ⑦ 판정문 없음·head≠승인 sha·merge-tree 충돌·D2 stop → REJECT · 쓰기 0
#   ⑧ 팀 master 길은 앞 판 그대로(merge-tree 안 탐)   ⑨ approve-merge 인자 없음 = 2904 REJECT 그대로 · 도구에 branch -D/force push/kill-server 0
#   변이(사본에서만 · 변이마다 원본으로 반대 결과 대조): W3 자율 레벨 검사 삭제 → ⑥ FAIL · W4 merge-tree 삭제 → ⑦(충돌) FAIL · W5 desk 를 D2 검사 앞에서 통과 → ⑦(판정문 없음) FAIL
# 격리: 임시 BYZ 리포(명부 2팀+desk)·임시 팩 리포(ssh 스텁) · 가짜 tmux·gh·슬랙 · FT_NOW 고정 · 실 gh·슬랙·원격·상태 0 · press 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/stub" "$T/fakebin" "$T/da" "$T/pdir"
T0=1800000000; OD=1794302162.301939; PL='byz-planner-master-claude#105'; HM='byz-harness-master-claude#115'; DESK='byz-planner-desk-pi#134'
mkrepo "$T/byz"; B="$W"; mkdir -p "$B/.fable-team"; printf '.fable-team/\n' >> "$B/.git/info/exclude"
python3 - "$B" "$PL" "$DESK" "$HM" <<'PY'
import json, sys
b, pl, desk, hm = sys.argv[1:5]
json.dump({"_master": pl, "_desk": desk}, open(b + "/.fable-team/seats-planner.json", "w"))
json.dump({"_master": hm}, open(b + "/.fable-team/seats-harness.json", "w"))
PY
SEATFILE="$T/seatname"; export SEATFILE; printf '%s' "$PL" > "$SEATFILE"
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat "$SEATFILE"; exit 0; }\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
mkrepo "$T/pack"; P="$W"; export PACK_ORIGIN="$ORIGIN"
HB="$P/feature-pack/fable-team/harness"; mkdir -p "$HB/bin" "$HB/kit/fable-team/templates"
echo base > "$HB/bin/ft-x.sh"; printf 'LOG_LEVEL=debug\n' > "$HB/bin/.env"; cm "$P" harness; git -C "$P" push -q origin main
git -C "$P" remote set-url origin git@github.com:fake/pack.git
printf '#!/bin/bash\nexec bash -c "$(printf %%s "${!#}" | sed -E "s|'"'"'[^'"'"']*'"'"'|'"'"'$PACK_ORIGIN'"'"'|")"\n' > "$T/stub/ssh"
printf '#!/bin/bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\necho "$*" >> "$STUB_LOG"\nexit 0\n' > "$T/stub/gh"
printf '#!/bin/bash\nexit 0\n' > "$T/stub/noop"; chmod +x "$T/stub"/*
export GIT_SSH_COMMAND="$T/stub/ssh" FT_HARNESS_ROOT="$HB" FT_SCOPE_PACK_TABLE="$BIN/../kit/fable-team/templates/scope-classes-pack.tsv"
export FT_GH="$T/stub/gh" FT_GH_WRITE="$T/stub/gh" STUB_JSON="$T/pr.json" STUB_LOG="$T/gh.log" FT_INSTALL_CHECK="$T/stub/noop"
S="$T/state"; LOG="$S/autonomy.log"; JSON="$S/autonomy.json"
export FT_ROOT="$B" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/pdir" TMUX_PANE=%9 PATH="$T/fakebin:$PATH"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/fake_gh_base.sh"; fake_gh_base "$T/ghb"   # r1955: --pr 의 base 조회(autonomy_pr_target) = 가짜 gh(main)
git -C "$P" fetch -q origin || { echo "FAIL 팩 픽스처 fetch"; exit 1; }
a() { FT_NOW="$T0" "$BASH" "${ABIN:-$BIN}/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
nlog() { grep -c . "$LOG" 2>/dev/null || true; }
fresh() {  # fresh <level> [mode] — 손 작성 autonomy.json + log(ON full 기본 · tamper 는 log 불일치)
  rm -rf "$S"; mkdir -p "$S"
  local lv="${1:-full}" md="${2:-on}"
  printf '{"mode":"%s","since":%s,"event":"A17","until":null,"level":"%s"}\n' "$md" "$T0" "$lv" > "$JSON"
  if [ "$md" = tamper ]; then printf '%s\t%s\t%s\n' "$T0" off A17 > "$LOG"; else printf '%s\t%s\t%s\n' "$T0" "$md" A17 > "$LOG"; fi
  printf '%s\n' "approve-standing D2 $T0 repos=byz,pack classes=code,docs oppa_decision=$OD" >> "$LOG"
}
as_seat() { printf '%s' "$1" > "$SEATFILE"; export FT_SEAT="$1"; }
card() { CARD="$B/card.md"; printf '# 카드\n\n## 상태\n- 세트: %s · 시험: bash tests/x.sh rc=0 · 이슈: 0\n' "$1" > "$CARD"; cardpub; }
cardpub() { grep -qx '/card*.md' "$B/.git/info/exclude" || echo '/card*.md' >> "$B/.git/info/exclude"; git -C "$B" update-ref refs/remotes/origin/ops/main-base "$(git -C "$B" commit-tree "$(printf '100644 blob %s\t%s\n' "$(git -C "$B" hash-object -w "$CARD")" "${CARD##*/}" | git -C "$B" mktree)" -m card)"; }   # r1904: 카드 = 원장(FT_ROOT) 안 · 고정 ref origin/ops/main-base 커밋 판
sa() { as_seat "${SA_SEAT:-$DESK}"; L0="$(nlog)"; run a standing-approve D2 "$1" --pr "$2" --repo "${4:-pack}" --verdict "$3" --card "$CARD"; }
mkpr() {  # mkpr <N> <파일> [내용…] — 팩 origin/main 에서 head 1커밋
  git -C "$P" fetch -q origin; git -C "$P" checkout -q -B "pr$1" origin/main; mkdir -p "$P/$(dirname "$2")"
  { echo "pr$1 $RANDOM"; printf '%s\n' "${@:3}"; } >> "$P/$2"; cm "$P" "pr $1"
  git -C "$P" push -q -f origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$P" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":"pr"+sys.argv[2],"title":"feat PR "+sys.argv[2],"body":"카드 r1708 시험","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"; }
mkda() { DAO="$T/da/$1.out"; printf 'codex\n판정: %s\n\n근거\n\n판정: %s\n' "$2" "$2" > "$DAO"; printf 'head=%s model=gpt-6.1-sol effort=high rc=0 start=1 end=2\n' "$3" > "$DAO.meta"; }
sum256() { shasum -a 256 "$1" | awk '{print $1}'; }
mkv() {  # mkv <이름> <A> <원문> — BYZ origin/main + DA 판정 가지(r1590 ref)
  VF="$B/design/harness/da/VERDICT-$1.md"; mkdir -p "$(dirname "$VF")"
  printf '# 판정 %s\n\n- 승인 sha: %s\n- DA 원문: %s\n- DA 원문 sha256: %s\n- 격리: 세트 %s · rc=0\n' "$1" "$2" "$3" "$(sum256 "$3")" "$2" > "$VF"
  git -C "$B" checkout -q main; cm "$B" "verdict $1" && git -C "$B" push -q origin main && git -C "$B" push -q origin main:refs/heads/docs/da-278062 && git -C "$B" fetch -q origin; }
PRF="feature-pack/fable-team/legacy/1.x/harness/bin/ft-x.sh"
bash -n "$BIN/ft-autonomy-standing-d2.sh"; ck "bash -n" $?
grep -qE 'branch -D|push --force|kill-server' "$BIN/ft-autonomy-standing-d2.sh" && ck "⑨ 도구에 파괴 명령 0" 1 || ck "⑨ 도구에 파괴 명령 0" 0
# 기준판(origin/main 판) — desk 는 D2 를 못 쓴다
BASE="$T/base"; git -C "$HERE/../../../../.." show 20b2beff4f8ea48c9e2082fe9a7eb63a3a0d6496:feature-pack/fable-team/legacy/1.x/harness/bin/ft-autonomy-standing-d2.sh > "$BASE.sh" 2>/dev/null && ck "기준판 사본" 0 || ck "기준판 사본" 1
mkpr 11 "$PRF"; A11="$PRSHA"; mkda ok11 APPROVE "$A11"; mkv ok11 "$A11" "$DAO"; V11="$VF"; card "$A11"
rm -rf "$T/bx"; mkdir -p "$T/bx"; cp "$BIN"/* "$T/bx/" 2>/dev/null; cp "$BASE.sh" "$T/bx/ft-autonomy-standing-d2.sh"
as_seat "$DESK"; fresh; run env "$BASH" "$T/bx/ft-autonomy.sh" standing-approve D2 "$A11" --pr 11 --repo pack --verdict "$V11" --card "$CARD"
[ "$rc" = 2 ] && has '팀 master 좌석만'; ck "기준판 ⑤ desk → REJECT(«팀 master 좌석만»)" $?
# ⑤ desk + ON full → 승인 파일·standing-use·원장(by=desk)
fresh; sa "$A11" 11 "$V11"
[ "$rc" = 0 ] && has "^STANDING-OK $A11 pr=11 repo=pack da=$A11 card=card.md by=$DESK$"; ck "⑤ desk + 자율 ON full → STANDING-OK by=desk" $?
grep -qx "standing-use D2 $A11 $T0 pr=11 repo=pack da=$A11" "$LOG" && [ "$(cat "$S/autonomy-merge-approved/$A11")" = "approve-merge $A11 D2 $T0" ]; ck "⑤ log 1줄 + 승인 파일" $?
[ "$(awk -F'\t' -v a="$A11" '$2==a {print $3 "|" $4}' "$S/autonomy-standing/D2.ledger.tsv")" = "11|da=$A11" ]; ck "⑤ 원장 1행(PR·da)" $?
# ⑥ 자율 OFF·mid·each·tamper → REJECT · 쓰기 0
for lv_md in mid:on each:on full:off full:tamper; do
  lv="${lv_md%%:*}"; md="${lv_md##*:}"; fresh "$lv" "$md"; L0="$(nlog)"; sa "$A11" 11 "$V11"
  [ "$rc" = 2 ] && has 'desk 승인은 자율 풀자동에서만' && [ ! -e "$S/autonomy-merge-approved/$A11" ] && [ "$(nlog)" = "$L0" ]; ck "⑥ 자율 $lv/$md → REJECT «자율 풀자동에서만» · 쓰기 0" $?
done
# ⑦ 판정문 없음 · head≠승인 sha · merge-tree 충돌 · D2 stop
fresh; run a standing-approve D2 "$A11" --pr 11 --repo pack --verdict "$T/없는판정.md" --card "$CARD"
[ "$rc" = 2 ] && has '판정문'; ck "⑦ 판정문 없음 → REJECT" $?
mkpr 12 "$PRF"; A12="$PRSHA"; card "$A12"; fresh; as_seat "$DESK"; run a standing-approve D2 "$A12" --pr 12 --repo pack --verdict "$V11" --card "$CARD"
[ "$rc" = 2 ] && has '승인 sha'; ck "⑦ head ≠ 승인 sha → REJECT" $?
# merge-tree 충돌 재현 = PATH 의 git 스텁(merge-tree 만 rc1 · 나머지는 진짜 git) — desk 길은 거절, 팀 master 길은 안 탄다
mkdir -p "$T/gitstub"; printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = merge-tree ] && { echo "CONFLICT (content): x" >&2; exit 1; }; done\nexec /usr/bin/git "$@"\n' > "$T/gitstub/git"; chmod +x "$T/gitstub/git"
mkda ok12 APPROVE "$A12"; mkv ok12 "$A12" "$DAO"; V12="$VF"; card "$A12"; fresh
PATH="$T/gitstub:$PATH" sa "$A12" 12 "$V12"
[ "$rc" = 2 ] && has 'merge-tree 충돌'; ck "⑦ merge-tree 충돌 → REJECT(desk 길에만)" $?
rm -rf "$T/gitstub"
# ⑧ 팀 master 길 그대로 — 충돌 head 라도 merge-tree 검사 없이 «카드/판정» 판정까지만(거절 사유가 merge-tree 가 아니다)
fresh; SA_SEAT="$HM" sa "$A12" 12 "$V12"
has 'merge-tree' && ck "⑧ 팀 master 길은 merge-tree 안 탄다" 1 || ck "⑧ 팀 master 길은 merge-tree 안 탄다" 0
# ⑨ approve-merge 인자 없음 = 2904 그대로
as_seat "$DESK"; run a approve-merge
[ "$rc" = 2 ] && has '^REJECT'; ck "⑨ approve-merge 인자 없음 = rc2 REJECT 그대로(승인 쓰기 0)" $?
# 변이 W3~W5 (사본 · 원본 대조)
mut2() { R="$T/m-$1"; rm -rf "$R"; mkdir -p "$R"; cp "$BIN"/* "$R/" 2>/dev/null; python3 - "$R/ft-autonomy-standing-d2.sh" "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text(); k = sys.argv[2]
def sub(o, n):
    global s
    assert s.count(o) == 1, o[:50]
    s = s.replace(o, n, 1)
if k == "W3":
    sub('  [ "$(jfield level)" = full ] || std_err "desk 승인은 자율 풀자동에서만(level=$(jfield level))"\n', "")
elif k == "W4":
    sub('  [ -z "${D2_DESK:-}" ] || d2_merge_tree "$head"', '  :')
elif k == "W5":
    sub('  D2_CARD="$card"; D2_DESK=""; d2_seat', '  D2_CARD="$card"; D2_DESK=""; d2_seat; [ -n "${D2_DESK:-}" ] && { d2_write "$head" "$pr" "-" "-"; return 0; }')
p.write_text(s)
PY
  cp "$B"/*/ -r "$R/" 2>/dev/null || true; }
mut2 W3; fresh mid; ABIN="$T/m-W3" sa "$A11" 11 "$V11"
has '자율 풀자동에서만' && ck "W3 자율 레벨 검사 삭제 → ⑥(mid) 가 «자율 풀자동» 사유로 막히지 않음(변이 잡힘)" 1 || ck "W3 자율 레벨 검사 삭제 → ⑥(mid) 가 «자율 풀자동» 사유로 막히지 않음(변이 잡힘)" 0
mkdir -p "$T/gitstub"; printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = merge-tree ] && { echo "CONFLICT" >&2; exit 1; }; done\nexec /usr/bin/git "$@"\n' > "$T/gitstub/git"; chmod +x "$T/gitstub/git"
mut2 W4; fresh; PATH="$T/gitstub:$PATH" ABIN="$T/m-W4" sa "$A12" 12 "$V12"
[ "$rc" = 0 ] && ck "W4 merge-tree 검사 삭제 → ⑦(충돌) 승인됨(변이 잡힘)" 0 || ck "W4 merge-tree 검사 삭제 → ⑦(충돌) 승인됨(변이 잡힘)" 1
fresh; PATH="$T/gitstub:$PATH" sa "$A12" 12 "$V12"
[ "$rc" = 2 ] && has 'merge-tree 충돌'; ck "W4 원본 대조: 충돌이면 REJECT" $?
rm -rf "$T/gitstub"
mut2 W5; fresh; ABIN="$T/m-W5" sa "$A11" 11 "$T/없는판정.md"
has '판정문' && ck "W5 desk 조기 통과 → ⑦(판정문 없음) 거절 아님(변이 잡힘)" 1 || ck "W5 desk 조기 통과 → ⑦(판정문 없음) 거절 아님(변이 잡힘)" 0
fresh; sa "$A11" 11 "$T/없는판정.md"; has '판정문' && ck "W5 원본 대조: 판정문 없음 → REJECT" 0 || ck "W5 원본 대조: 판정문 없음 → REJECT" 1
# R1(DA) — 잠금 «안» OFF 재확인: mkdir 대역이 잠금 직전에 자율을 OFF 로 바꾼다
mkdir -p "$T/mkstub"; printf '#!/bin/bash\ncase "$*" in *lock*) if [ ! -f "$T/off.done" ]; then : > "$T/off.done"; FT_NOW="$T0" "%s" "%s" expire >/dev/null 2>&1; fi;; esac\nexec /bin/mkdir "$@"\n' "$BASH" "$BIN/ft-autonomy.sh" > "$T/mkstub/mkdir"; chmod +x "$T/mkstub/mkdir"
card "$A11"; fresh; printf '{"mode":"on","since":%s,"event":"A17","until":%s,"level":"full"}\n' "$T0" "$((T0 - 1))" > "$JSON"   # 만료 ON(곧 off)
card "$A11"; rm -f "$T/off.done"; PATH="$T/mkstub:$PATH" sa "$A11" 11 "$V11"
[ "$rc" = 2 ] && has '자율 풀자동에서만' && [ ! -e "$S/autonomy-merge-approved/$A11" ]; ck "R1 잠금 안 OFF 재확인 → REJECT · 승인 파일 0" $?
rm -rf "$T/mkstub"; card "$A11"; fresh; sa "$A11" 11 "$V11"; [ "$rc" = 0 ]; ck "R1 원본 대조: 정상 ON full → 승인" $?
# R2(DA) — 최신 원격 기준 확인 줄이 있다(가짜 원격 재현은 DA evidence/da-stale.sh 몫) · r1955 라: 대상 = PR base(D2_TARGET)
[ "$(grep -cF 'fetch -q origin "+refs/heads/$D2_TARGET:refs/remotes/origin/$D2_TARGET"' "$BIN/ft-autonomy-standing-d2.sh")" = 1 ] \
  && ck "R2 merge-tree 전 원격 main 최신성 확인 줄 1개" 0 || ck "R2 merge-tree 전 원격 main 최신성 확인 줄 1개" 1
# R3(DA) — 명부 desk 는 번호 회전(계보) 도 desk(기존 gate 규칙)
python3 - "$B" "$PL" <<'PY'
import json, sys
b, pl = sys.argv[1:3]
json.dump({"_master": pl, "_desk": "byz-planner-tool-pi#135"}, open(b + "/.fable-team/seats-planner.json", "w"))
PY
git -C "$B" checkout -q main; cm "$B" "desk lineage"; git -C "$B" push -q origin main; git -C "$B" fetch -q origin
card "$A11"; fresh; as_seat 'byz-planner-tool-pi#134'; run a standing-approve D2 "$A11" --pr 11 --repo pack --verdict "$V11" --card "$CARD"
[ "$rc" = 0 ] && has 'by=byz-planner-tool-pi#134'; ck "R3 명부 desk 번호 회전(#134) 도 desk → 승인" $?
echo "단계 합계 ${SECONDS}s"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
