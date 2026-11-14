#!/usr/bin/env bash
# test_autonomy_standing_d2_r1577.sh — r1577 «상시 승인 D2» (카드 r1577-approval-split-critical-slack-only) ⓐ~ⓖ + 변이 M1~M9
#   + 명부 루트 보정 ⓗⓘⓙ(DA R1 f0191161f9 §2 §3) 와 변이 M10~M13
#   격리: 임시 BYZ 리포(명부 2팀·판정문)·임시 팩 리포(origin = github ssh 꼴 → ssh 스텁이 로컬 bare 로) · 가짜 tmux·gh·슬랙 게시·슬랙 읽기 · FT_NOW 고정
#   실 gh·실 슬랙·실 원격·실 상태 0 · GIT_* env 0 — press 0(나노는 쏘지 않는다)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/stub" "$T/fakebin" "$T/da" "$T/pdir"
T0=1800000000; OD=1794302162.301939; PL='byz-planner-master-claude#105'; HM='byz-harness-master-claude#115'; NANO='byz-harness-nano-r1577-x#0'
# ── BYZ 리포 = 명부 루트 · 판정문 리포 · 실제 좌석 = 가짜 tmux 세션명
mkrepo "$T/byz"; B="$W"; mkdir -p "$B/.fable-team"; printf '.fable-team/\n' >> "$B/.git/info/exclude"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$PL" "$B/.fable-team/seats-planner.json"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$HM" "$B/.fable-team/seats-harness.json"
SEATFILE="$T/seatname"; export SEATFILE; printf '%s' "$PL" > "$SEATFILE"
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat "$SEATFILE"; exit 0; }\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$2" >> "%s"\necho "SLACK-TS 1800000000.000100"\n' "$T/slack.log" > "$T/stub/post.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/stub/postfail.sh"; chmod +x "$T/stub/"*
printf '#!/usr/bin/env bash\ncat "$REPLIES"\n' > "$T/stub/replies"; chmod +x "$T/stub/replies"
printf '{"ok":true,"messages":[{"ts":"1794302162.300000","user":"UBOT","text":"질문"},{"ts":"%s","user":"U0AC2JF0M7D","thread_ts":"1794302162.300000","text":"승인 없어도 되게"}]}' "$OD" > "$T/replies.json"
printf '{"ok":true,"messages":[{"ts":"1794302162.300000","user":"UBOT","text":"질문"},{"ts":"%s","user":"U0DIFFERENT99","thread_ts":"1794302162.300000","text":"남의 글"}]}' "$OD" > "$T/replies-nope.json"
S="$T/state"; LOG="$S/autonomy.log"
export FT_ROOT="$B" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/pdir" FT_SEAT="$PL" TMUX_PANE=%9 PATH="$T/fakebin:$PATH"
export FT_SCOPE_SLACK_POST="$T/stub/post.sh" FT_SLACK_REPLIES_CMD="$T/stub/replies" REPLIES="$T/replies.json"
# ── 팩 리포(하네스 루트 = <리포>/feature-pack/fable-team/harness) · origin = git@github.com:fake/pack.git (ssh 스텁 → 로컬 bare)
mkrepo "$T/pack"; P="$W"; export PACK_ORIGIN="$ORIGIN"
HB="$P/feature-pack/fable-team/harness"; ELB="$P/feature-pack/fable-team/legacy/1.x/harness/bin"; mkdir -p "$HB/bin" "$HB/kit/fable-team/templates" "$ELB"
echo base > "$HB/bin/ft-x.sh"; echo x > "$HB/kit/fable-team/templates/.keep"; printf 'LOG_LEVEL=debug\n' > "$ELB/.env"; cm "$P" harness; git -C "$P" push -q origin main
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
as_seat() { printf '%s' "$1" > "$SEATFILE"; export FT_SEAT="$1"; }
grant() { as_seat "$PL"; L0="$(nlog)"; run a approve-standing D2 --repos byz,pack --classes "${1:-code,docs}" --oppa-decision "${2:-$OD}"; }
card() { CARD="$B/card.md"; printf '# 카드\n\n## 상태\n- 세트: %s · 시험: bash tests/x.sh rc=0 · 이슈: %s\n' "$1" "${2:-0}" > "$CARD"; cardpub; }
cardpub() { grep -qx '/card*.md' "$B/.git/info/exclude" || echo '/card*.md' >> "$B/.git/info/exclude"; git -C "$B" update-ref refs/remotes/origin/ops/main-base "$(git -C "$B" commit-tree "$(printf '100644 blob %s\t%s\n' "$(git -C "$B" hash-object -w "$CARD")" "${CARD##*/}" | git -C "$B" mktree)" -m card)"; }   # r1904: 카드 = 원장(FT_ROOT) 안 · 고정 ref origin/ops/main-base 커밋 판
sa() { as_seat "${SA_SEAT:-$HM}"; L0="$(nlog)"; run a standing-approve D2 "$1" --pr "$2" --repo "${4:-pack}" --verdict "$3" --card "$CARD"; }
rej0() { [ "$rc" = 2 ] && has "$2" && [ ! -e "$S/autonomy-standing" ] && [ "$(nlog)" = "${L0:-$(nlog)}" ]; ck "$1" $?; }
rej() { local sh="$2"; [ "$sh" = - ] && sh=""; [ "$rc" = 2 ] && has "$3" && has '다시: 오빠 h\(approve-merge --oppa-slack\)' && { [ -z "$sh" ] || [ ! -e "$S/autonomy-merge-approved/$sh" ]; } && [ "$(nlog)" = "${L0:-$(nlog)}" ]; ck "$1" $?; }
mkpr() {  # mkpr <N> <파일> [내용…] — 팩 origin/main 에서 PR head 1커밋 → refs/pull/N/head · PRSHA · STUB_JSON
  git -C "$P" fetch -q origin; git -C "$P" checkout -q -B "pr$1" origin/main; mkdir -p "$P/$(dirname "$2")"
  { echo "pr$1 $RANDOM"; printf '%s\n' "${@:3}"; } >> "$P/$2"; cm "$P" "pr $1"
  git -C "$P" push -q -f origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$P" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":"pr"+sys.argv[2],"title":"feat r1577 PR "+sys.argv[2],"body":"카드 r1577 시험","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"; }
mkda() { DAO="$T/da/$1.out"; printf 'codex\n판정: %s\n\n근거\n\n판정: %s\n' "$2" "$2" > "$DAO"; printf 'head=%s model=gpt-6.1-sol effort=high rc=0 start=1 end=2\n' "$3" > "$DAO.meta"; }
sum256() { shasum -a 256 "$1" | awk '{print $1}'; }
mkv() {  # mkv <이름> <A> <원문> → VF(BYZ origin/main 커밋 + DA 판정 가지(r1590: D2 가 읽는 ref) 같은 커밋)
  VF="$B/design/harness/da/VERDICT-$1.md"; mkdir -p "$(dirname "$VF")"
  printf '# 판정 %s\n\n- 승인 sha: %s\n- DA 원문: %s\n- DA 원문 sha256: %s\n- 격리: 세트 %s · rc=0\n' "$1" "$2" "$3" "$(sum256 "$3")" "$2" > "$VF"
  git -C "$B" checkout -q main; cm "$B" "verdict $1" && git -C "$B" push -q origin main && git -C "$B" push -q origin main:refs/heads/docs/da-278062 && git -C "$B" fetch -q origin; }
PRF="feature-pack/fable-team/legacy/1.x/harness/bin/ft-x.sh"

bash -n "$BIN/ft-autonomy-standing-d2.sh" && bash -n "$BIN/ft-autonomy.sh" && bash -n "$BIN/ft-merge-land.sh" && bash -n "$BIN/ft-merge-lib.sh"; ck "bash -n 4종" $?
python3 -c "import ast;ast.parse(open('$BIN/autonomy_scope_rules.py').read());ast.parse(open('$BIN/autonomy_scope_classify.py').read());ast.parse(open('$BIN/ft_doc_exempt.py').read())"; ck "python ast 3종" $?

# ══ ⓐ 켜기 — planner master 좌석 + 오빠 결정 ts 확인 · 켜짐 Slack 1글 먼저 · grants.audit
fresh; rm -f "$T/slack.log"
fresh; as_seat "$HM"; L0="$(nlog)"; run a approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD"
rej0 "ⓐ0 팀 master(비-planner) 켜기 → 거절(M5 근거)" 'STANDING-REJECT approve-standing D2 — 호출 좌석'
fresh; grant "" 1; rej0 "ⓐ0b --oppa-decision 꼴 틀림 → 거절(쓰기 0)" '--oppa-decision 은 Slack ts'
fresh; REPLIES="$T/replies-nope.json" grant; rej0 "ⓐ0c 오빠 글이 아닌 ts → 거절(확인 못 하면 쓰기 0 · M8 근거)" 'ⓐ --oppa-decision 확인 실패'
REPLIES="$T/replies.json"; fresh; grant
[ "$rc" = 0 ] && has "^STANDING-GRANTED D2 repos=byz,pack classes=code,docs oppa_decision=$OD slack_ts=1800000000.000100$"; ck "ⓐ1 approve-standing D2 → GRANTED(오빠 ! 0)" $?
grep -qx "approve-standing D2 $T0 repos=byz,pack classes=code,docs oppa_decision=$OD" "$LOG" && grep -q "oppa_decision=$OD	slack_ts=1800000000.000100$" "$S/autonomy-standing/grants.audit"; ck "ⓐ2 log 꼴 · grants.audit(slack_ts·oppa_decision)" $?
grep -q '상시 승인 D2 켜짐' "$T/slack.log"; ck "ⓐ3 켜짐 알림 슬랙 1글(사람 말 3줄)" $?
L0="$(nlog)"; grant; [ "$rc" = 0 ] && has '^STANDING-NOOP D2 이미 켜짐' && [ "$(nlog)" = "$L0" ]; ck "ⓐ4 두 번 켜기 = NOOP(쓰기 0)" $?
run a approve-standing D2 --repos byz --classes code,docs; [ "$rc" = 2 ] && has '--oppa-decision 은 Slack ts'; ck "ⓐ5 --oppa-decision 없음 = 거절 rc2" $?

# ══ ⓑ 승인 — 분류 ∧ DA APPROVE 꼬리 ∧ 카드 시험 세트 ∧ 크리티컬 0 → STANDING-OK(팀 master 좌석)
fresh; grant; mkpr 11 "$PRF"; A11="$PRSHA"; mkda ok11 APPROVE "$A11"; mkv ok11 "$A11" "$DAO"; V11="$VF"; card "$A11"
as_seat "$HM"; sa "$A11" 11 "$V11"
[ "$rc" = 0 ] && has "^STANDING-OK $A11 pr=11 repo=pack da=$A11 card=card.md by=$HM$"; ck "ⓑ1 code PR(카드 시험 세트 통과) → STANDING-OK(팀 master)" $?
grep -qx "standing-use D2 $A11 $T0 pr=11 repo=pack da=$A11" "$LOG" && grep -qx "approve-merge $A11 D2 $T0" "$LOG" && [ "$(cat "$S/autonomy-merge-approved/$A11")" = "approve-merge $A11 D2 $T0" ]; ck "ⓑ2 log 2줄 + 승인 파일(같은 줄)" $?
[ "$(awk -F'\t' -v a="$A11" '$2==a {print $3 "|" $4}' "$S/autonomy-standing/D2.ledger.tsv")" = "11|da=$A11" ]; ck "ⓑ3 D2 원장 1행(PR·da)" $?
L0="$(nlog)"; sa "$A11" 11 "$V11"; [ "$rc" = 0 ] && has "^STANDING-NOOP $A11" && [ "$(nlog)" = "$L0" ]; ck "ⓑ4 같은 head 두 번 = NOOP(쓰기 0)" $?
mkda hold11 HOLD "$A11"; mkv hold11 "$A11" "$DAO"; VH="$VF"; fresh; grant; sa "$A11" 11 "$VF"; rej "ⓑ5 DA 마지막 블록 HOLD → 거절(ⓑ③ · M3 근거)" "$A11" '⑤ DA 마지막 codex 블록이 APPROVE 아님'
fresh; grant; card "$A11" 1; sa "$A11" 11 "$V11"; rej "ⓑ6 카드 시험 세트 «이슈: 1» → 거절(④ · M2 근거)" "$A11" '카드 증거 줄이'
card "$A11"; fresh; grant docs; sa "$A11" 11 "$V11"; rej "ⓑ7 classes=docs 범위에 code PR → 거절(M7 근거)" "$A11" '② 종류 code 는 상시 승인 범위'
fresh; grant; SA_SEAT="$NANO" sa "$A11" 11 "$V11"; rej "ⓑ8 나노 좌석 → 거절(ⓑ 쓰기 판정 · M4 근거)" "$A11" 'ⓑ 팀 master 좌석만'
run a standing-stop D2 "시험 멈춤"; [ "$rc" = 0 ] && grep -qx "standing-stop D2 $T0 시험 멈춤" "$LOG"; ck "ⓕ1 standing-stop D2 줄" $?
sa "$A11" 11 "$V11"; rej "ⓕ2 멈춘 뒤 승인 → 거절(① 꺼짐)" "$A11" '① 상시 승인 D2 꺼짐'
grant; sa "$A11" 11 "$V11"; [ "$rc" = 0 ] && has "^STANDING-OK $A11 "; ck "ⓕ3 다시 켜기 = 승인 재개" $?
git -C "$B" checkout -q -b byzpr11; mkdir -p "$B/scripts"; echo "echo hi" > "$B/scripts/zz-r1577.sh"; cm "$B" "byz pr 11"; BSHA="$(sha "$B" HEAD)"; git -C "$B" checkout -q main
mkda okb APPROVE "$BSHA"; mkv okb "$BSHA" "$DAO"; card "$BSHA"; sa "$BSHA" 12 "$VF" byz
[ "$rc" = 0 ] && has "^STANDING-OK $BSHA pr=12 repo=byz da=$BSHA "; ck "ⓑ9 --repo byz 승인(내장 BYZ 표)" $?

# ══ ⓒ 크리티컬 종류 — 하나라도 나오면 STANDING-REJECT «⑤ 크리티컬: <종류>»
fresh; grant
crit() {  # crit <라벨> <크리티컬 종류> <경로> [내용…] — PR 1개 → ⑤ 크리티컬 거절
  local lb="$1" kd="$2" pth="$3"; shift 3; mkpr "6$RANDOM" "$pth" "$@"; local sh="$PRSHA"
  mkda "k${kd}$RANDOM" APPROVE "$sh"; mkv "k${kd}$RANDOM" "$sh" "$DAO"; card "$sh"; sa "$sh" 20 "$VF"
  rej "ⓒ $lb → 거절(크리티컬: $kd)" "$sh" "⑤ 크리티컬: $kd"; }
crit "파괴 명령 새 줄" destroy "$PRF" "git branch -D old" "git push origin --delete old" "git push -f origin main"
crit "R2 짧은 +ref force push(git push origin +main:main)" destroy "$PRF" "git push origin +main:main"
okd2() {  # r1934 ⑪ — D2 = profile d2: launchd·cliproxy·models.json apiKey 는 크리티컬 아님(full=try-auto 는 그대로 · r1934 시험)
  local lb="$1" pth="$2"; shift 2; mkpr "6$RANDOM" "$pth" "$@"; local sh="$PRSHA"
  mkda "o$RANDOM" APPROVE "$sh"; mkv "o$RANDOM" "$sh" "$DAO"; card "$sh"; sa "$sh" 20 "$VF"; [ "$rc" = 0 ] && has "^STANDING-OK $sh "; ck "ⓒ $lb → r1934 D2 승인(크리티컬 아님)" $?; }
okd2 "새 launchd plist" "feature-pack/fable-team/legacy/1.x/harness/bin/Library/LaunchAgents/com.x.plist" "x"
okd2 "새 외부 설정 파일(cliproxy)" "feature-pack/fable-team/legacy/1.x/harness/bin/cliproxy.yaml" "a: 1"
okd2 "새 models.json apiKey 칸" "feature-pack/fable-team/legacy/1.x/harness/bin/models.json" '"apiKey": "x"'
crit "R1 기존 .env 일반 값 변경" config "feature-pack/fable-team/legacy/1.x/harness/bin/.env" "LOG_LEVEL=info"
git -C "$B" checkout -q -b byzsec; mkdir -p "$B/design/harness/research"; printf '%s\n' 'export X="$OPENAI_API_KEY"' 'echo "$ANTHROPIC_API_KEY"' > "$B/design/harness/research/k.txt"; cm "$B" "sec"; SEC="$(sha "$B" HEAD)"; git -C "$B" checkout -q main
out="$(python3 "$BIN/autonomy_scope_classify.py" classify "$SEC" --repo "$B" --critical 2>&1)"; rc=$?
[[ "$out" =~ ^CRITICAL\ kind=secret\  ]] && ck "ⓒ secret 비밀 줄(autonomy_scope_secret 재사용)" $? || ck "ⓒ secret 비밀 줄(받은: ${out:0:120})" 1

# ══ ⓓ 병합 뒤 알림 — LANDED + 슬랙 1줄(«병합함: …» · 되돌림 명령) + D2 원장 착지 칸 · 게시 실패 = 착지 rc 불변(M6)
fresh; grant; mkpr 31 "$PRF"; A31="$PRSHA"; mkda ok31 APPROVE "$A31"; mkv ok31 "$A31" "$DAO"; V31="$VF"; card "$A31"; sa "$A31" 31 "$V31"
rm -f "$T/land.log"; out="$(cd "$B" && bash "$BIN/ft-merge-land.sh" 31 --approve-sha "$A31" --repo "$P" 2>&1)"; rc=$?
Q31="${out#*sha=}"; Q31="${Q31%% *}"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(git -C "$PACK_ORIGIN" rev-parse refs/heads/main)" = "$Q31" ]; ck "ⓓ1a D2 승인 줄로 ft-merge-land → LANDED(오빠 h 0)" $?
grep -q "병합함: PR #31 · 카드 r1577 · DA APPROVE · 되돌림: git revert --no-edit $Q31" "$T/slack.log"; ck "ⓓ1b 병합 뒤 슬랙 1줄(카드·DA APPROVE·되돌림)" $?
[ "$(awk -F'\t' -v a="$A31" '$2==a {print $6 "|" $7}' "$S/autonomy-standing/D2.ledger.tsv")" = "$Q31|git revert --no-edit $Q31" ]; ck "ⓓ1c D2 원장 착지 sha·되돌림 칸" $?
grep -q "landed=$Q31 pr=31 approve=$A31 approve-file=$T0 standing=D2" "$S/merge-gate.log"; ck "ⓓ1d merge-gate.log standing=D2" $?
mkpr 32 "$PRF"; A32="$PRSHA"; mkda ok32 APPROVE "$A32"; mkv ok32 "$A32" "$DAO"; card "$A32"; sa "$A32" 32 "$VF"
export FT_SCOPE_SLACK_POST="$T/stub/postfail.sh"; out="$(cd "$B" && bash "$BIN/ft-merge-land.sh" 32 --approve-sha "$A32" --repo "$P" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && grep -q 'WARN 병합 뒤 슬랙 알림 실패' <<<"$out"; ck "ⓓ2 게시 실패 = stderr 1줄 · 착지 rc 0(M6 근거)" $?
export FT_SCOPE_SLACK_POST="$T/stub/post.sh"

# ══ ⓔ 불변 — 크리티컬 판정은 scope 분류표와 «분리»(scope 는 같은 destroy PR 을 still code 로 본다 · M9 근거)
git -C "$B" checkout -q byzpr11; git -C "$B" checkout -q -b byzdestroy 2>/dev/null || git -C "$B" checkout -q byzdestroy
echo 'git branch -D old' > "$B/scripts/zz-kill-r1577.sh"; cm "$B" "byz destroy"; KSH="$(sha "$B" HEAD)"; git -C "$B" checkout -q main
out="$(python3 "$BIN/autonomy_scope_classify.py" classify "$KSH" --repo "$B" --scope S0 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "CLASS code" ]; ck "ⓔ1 scope 분류기는 destroy 줄을 FORBID 로 안 본다(표 불변)" $?
out="$(python3 "$BIN/autonomy_scope_classify.py" classify "$KSH" --repo "$B" --critical 2>&1)"; rc=$?
[ "$rc" = 3 ] && [[ "$out" =~ ^CRITICAL\ kind=destroy\  ]]; ck "ⓔ2 같은 세트를 D2 크리티컬은 destroy 로 잡는다(다른 눈)" $?
out="$(cd "$B" && FT_AUTONOMY_STATE_DIR="$S" bash "$BIN/ft-merge-deny.sh" "$KSH" --branch byzdestroy --repo "$B" 2>&1)"; rc=$?
[ "$rc" = 0 ]; ck "ⓔ3 착지 금지 목록 검사 rc 그대로(훅·가드 경로 불변)" $?

# ══ ⓖ planner 실측 막힘 2곳 — 자율 ON A16 ∧ 범위 S43 꺼짐/유효 상태에서 «비크리티컬 D2 는 --oppa-slack 없이 승인·착지» ∧ «기존 approve-merge 길은 그대로 REJECT»
fresh; printf '%s\ton\tA16\n' "$T0" > "$LOG"; printf '{"mode":"on","since":%s,"event":"A16","until":null}\n' "$T0" > "$S/autonomy.json"
printf 'approve-scope S43 A16 %s until=%s max=20 daily=10 classes=docs,code codemax=5 repos=byz,pack\n' "$T0" "$((T0 + 3600))" >> "$LOG"
mkpr 41 "$PRF"; A41="$PRSHA"; mkda ok41 APPROVE "$A41"; mkv ok41 "$A41" "$DAO"; card "$A41"
out="$(FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" approve-merge "$A41" 2>&1)"; rc=$?
[ "$rc" = 2 ] && has '판정 2904'; ck "ⓖ1 기존 길(approve-merge, --oppa-slack 없음) = 범위 승인 중 REJECT(2904 유지)" $?
as_seat "$HM"; grant; sa "$A41" 41 "$VF"; [ "$rc" = 0 ] && has "^STANDING-OK $A41 "; ck "ⓖ2 같은 SHA 를 D2 길로 = 승인(oppa_gate 안 지남)" $?
out="$(cd "$B" && bash "$BIN/ft-merge-land.sh" 41 --approve-sha "$A41" --repo "$P" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]]; ck "ⓖ3 D2 승인 기록으로 착지(판정 2904 REJECT 0)" $?

# ══ 변이 M1~M9 — 변이 판에서 «빨강이어야 할 칸» 이 통과해 버리는지(그 칸이 그 검사를 실제로 잡는다)
mut() {  # mut <이름> <파일> <원문> <바꿀 글> → $T/mut-<이름>
  local mb="$T/mut-$1"; mkdir -p "$mb"; for f in "$BIN"/*; do ln -s "$f" "$mb/$(basename "$f")"; done; rm -f "$mb/$2"
  python3 - "$BIN/$2" "$mb/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}
mgo() {  # mgo <이름> — 변이 판 + 새 STATE 에 D2 켜고(planner) SA_SEAT(기본 팀 master) 좌석으로 승인
  local st="$T/ms-$1"; rm -rf "$st"; mkdir -p "$st"; as_seat "$PL"
  FT_NOW="$T0" FT_AUTONOMY_STATE_DIR="$st" "$BASH" "$BIN/ft-autonomy.sh" approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD" >/dev/null 2>&1
  as_seat "${SA_SEAT:-$HM}"; L0=0
  out="$(FT_NOW="$T0" FT_AUTONOMY_STATE_DIR="$st" "$BASH" "$T/mut-$MFT/ft-autonomy.sh" standing-approve D2 "$SAH" --pr "${SPR:-7}" --repo pack --verdict "$SVF" --card "$CARD" 2>&1)"; rc=$?; as_seat "$HM"; }
grev() {  # grev <이름> — 변이 판 approve-standing(켜기)만 · GSEAT 좌석
  local st="$T/ms-$1"; rm -rf "$st"; mkdir -p "$st"; as_seat "${GSEAT:-$PL}"
  out="$(FT_NOW="$T0" FT_AUTONOMY_STATE_DIR="$st" REPLIES="$REPLIES" "$BASH" "$T/mut-$MFT/ft-autonomy.sh" approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD" 2>&1)"; rc=$?; as_seat "$HM"; }
D2F=ft-autonomy-standing-d2.sh
mut m1 "$D2F" 'd2_critical "$head"' ':'; MFT=m1; mkpr 51 "$PRF" "git branch -D old"; SAH="$PRSHA"; SPR=51; mkda m1 APPROVE "$SAH"; mkv m1 "$SAH" "$DAO"; SVF="$VF"; card "$SAH"; mgo m1
[ "$rc" = 0 ]; ck "ⓘM1 크리티컬 판정 빼기 → ⓒ destroy 칸이 승인된다(빨강)" $?
mut m2 "$D2F" '[ "$D2_CLS" != code ] || scope_code_check' ':'; MFT=m2; card "$A11" 1; SVF="$V11"; SAH="$A11"; SPR=11; mgo m2
[ "$rc" = 0 ] && has '^STANDING-OK'; ck "ⓘM2 카드 시험 세트 검사 빼기 → ⓑ6 칸이 승인된다(빨강)" $?
mut m3 "$D2F" 'std_da_out "$V_OUT" "$V_A"; ' ''; MFT=m3; card "$A11"; SAH="$A11"; SPR=11; SVF="$VH"; mgo m3
[ "$rc" = 0 ] && has '^STANDING-OK'; ck "ⓘM3 DA 꼬리 검사 빼기 → ⓑ5 칸이 승인된다(빨강)" $?
mut m4 "$D2F" 'D2_CARD="$card"; D2_DESK=""; d2_seat' 'D2_CARD="$card"; D2_BY=mut'; MFT=m4; SA_SEAT="$NANO" SAH="$A11" SPR=11 SVF="$V11" mgo m4
[ "$rc" = 0 ] && has '^STANDING-OK'; ck "ⓘM4 쓰기 좌석 검사 빼기 → ⓑ8 칸이 승인된다(빨강)" $?
mut m5 "$D2F" 'std_seat_probe || {' 'true || {'; MFT=m5; REPLIES="$T/replies.json"; GSEAT="$NANO" grev m5
[ "$rc" = 0 ] && has 'STANDING-GRANTED'; ck "ⓘM5 켜기 좌석 검사 빼기 → ⓐ0 칸이 켜진다(빨강)" $?
mut m6 ft-merge-lib.sh '[ "$rc" = 0 ] || echo "WARN 병합 뒤 슬랙 알림 실패' '[ "$rc" = 0 ] || exit 1; [ "$rc" = 0 ] || echo "WARN 병합 뒤 슬랙 알림 실패'; MFT=m6
mkpr 34 "$PRF"; A34="$PRSHA"; mkda ok34 APPROVE "$A34"; mkv ok34 "$A34" "$DAO"; V34="$VF"; card "$A34"
st="$T/ms-m6"; rm -rf "$st"; mkdir -p "$st"; as_seat "$PL"
FT_NOW="$T0" FT_AUTONOMY_STATE_DIR="$st" "$BASH" "$BIN/ft-autonomy.sh" approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD" >/dev/null 2>&1; GRC=$?
as_seat "$HM"; FT_NOW="$T0" FT_AUTONOMY_STATE_DIR="$st" "$BASH" "$BIN/ft-autonomy.sh" standing-approve D2 "$A34" --pr 34 --repo pack --verdict "$V34" --card "$CARD" >/dev/null 2>&1; SRC=$?
[ "$GRC" = 0 ] && [ "$SRC" = 0 ] && [ -f "$st/autonomy-merge-approved/$A34" ]; ck "ⓘM6 전제: 정상 켜기+승인+승인 파일(원본 ⓓ2 = 같은 조건 rc0)" $?
export FT_SCOPE_SLACK_POST="$T/stub/postfail.sh"; out="$(cd "$B" && FT_AUTONOMY_STATE_DIR="$st" bash "$T/mut-m6/ft-merge-land.sh" 34 --approve-sha "$A34" --repo "$P" 2>&1)"; rc=$?
export FT_SCOPE_SLACK_POST="$T/stub/post.sh"; [ "$rc" != 0 ] && [[ "$out" == LANDED* ]]
ck "ⓘM6 변이(슬랙 실패→착지 실패): 같은 조건에서 원본 rc0 인데 변이 rc≠0(빨강)" $?
mut m7 "$D2F" 'case ",$D2_CLASSES," in *",$k,"*) ;; *) std_err "② 종류 $k 는 상시 승인 범위(classes=$D2_CLASSES) 밖" ;; esac' ':'; MFT=m7; card "$A11"
st="$T/ms-m7"; rm -rf "$st"; mkdir -p "$st"; as_seat "$PL"
FT_NOW="$T0" FT_AUTONOMY_STATE_DIR="$st" "$BASH" "$BIN/ft-autonomy.sh" approve-standing D2 --repos byz,pack --classes docs --oppa-decision "$OD" >/dev/null 2>&1
as_seat "$HM"; out="$(FT_NOW="$T0" FT_AUTONOMY_STATE_DIR="$st" "$BASH" "$BIN/ft-autonomy.sh" standing-approve D2 "$A11" --pr 11 --repo pack --verdict "$V11" --card "$CARD" 2>&1)"; rc=$?
[ "$rc" = 2 ] && has '② 종류 code 는 상시 승인 범위'; ck "ⓘM7 대조: docs grant + code PR = 원본 거절(같은 STATE)" $?
out="$(FT_NOW="$T0" FT_AUTONOMY_STATE_DIR="$st" "$BASH" "$T/mut-m7/ft-autonomy.sh" standing-approve D2 "$A11" --pr 11 --repo pack --verdict "$V11" --card "$CARD" 2>&1)"; rc=$?
[ "$rc" = 0 ] && has '^STANDING-OK'; ck "ⓘM7 변이(분류 ② 검사 제거): 같은 입력이 승인된다(빨강)" $?
mut m8 "$D2F" '  d2_oppa_decision "$od"   # ①' '  :  # ①'; MFT=m8; REPLIES="$T/replies-nope.json"; GSEAT="$PL" grev m8
[ "$rc" = 0 ] && has 'STANDING-GRANTED'; ck "ⓘM8 --oppa-decision 확인 빼기 → ⓐ0c 칸이 켜진다(빨강)" $?; REPLIES="$T/replies.json"
mut m9 autonomy_scope_classify.py '    hit = next(((k, w) for c, k, w in judged if c == "forbid"), None)' '    _cr = rules.critical_kinds(blocks)
    if _cr:
        return 3, "FORBID kind=%s %s" % _cr
    hit = next(((k, w) for c, k, w in judged if c == "forbid"), None)'; MFT=m9
out="$(python3 "$T/mut-m9/autonomy_scope_classify.py" classify "$KSH" --repo "$B" --scope S0 2>&1)"; rc=$?
[ "$rc" = 3 ] && has '^FORBID kind=destroy'; ck "ⓘM9 critical 을 scope FORBID 표에 합침 → ⓔ1 칸이 FORBID 로 바뀐다(빨강)" $?

# ══ ⓗⓘⓙ 명부 루트 — 데이터 루트(D) ≠ 명부 루트(R) 인 격리 꼴(ⓗ 실측 반례 · ⓘ env 무관 · ⓙ 같은 함수)
json1() { python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$1" "$2"; }
mkrepo "$T/rz"; RZS="$W"; mkdir -p "$RZS/.fable-team/comm"; printf '.fable-team/\n' >> "$RZS/.git/info/exclude"
json1 "$PL" "$RZS/.fable-team/seats-planner.json"; json1 "$HM" "$RZS/.fable-team/seats-harness.json"
DZS="$T/rz-live"; git -C "$RZS" worktree add -q "$DZS" -b live
printf '%s\n' "$DZS" > "$RZS/.fable-team/LIVE_ROOT"; mkdir -p "$DZS/.fable-team/comm"
# 가짜 명부(데이터 루트 안): _master = 다른 좌석(NANO) — 명부 루트를 $ROOT·env 로 되돌리면 여기서 잘못 판정된다
for t in planner harness test; do json1 "$NANO" "$DZS/.fable-team/seats-$t.json"; done
hz() { local st="$1" mb="$2"; shift 2; out="$(cd "$RZS" && FT_ROOT="$DZS" FT_MBOX_DIR="$mb" FT_AUTONOMY_STATE_DIR="$st" FT_NOW="$T0" "$BASH" "${HZB:-$BIN/ft-autonomy.sh}" "$@" 2>&1)"; rc=$?; }
HS="$T/hz-s"; rm -rf "$HS"; mkdir -p "$HS"; as_seat "$PL"
hz "$HS" "" approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD"
[ "$rc" = 0 ] && has '^STANDING-GRANTED D2 repos=byz,pack classes=code,docs oppa_decision='; ck "ⓗ1 켜기 = 공용 리포 명부로 planner 판정(데이터 루트 가짜 명부 무시)" $?
grep -qx "approve-standing D2 $T0 repos=byz,pack classes=code,docs oppa_decision=$OD" "$HS/autonomy.log" && grep -q 'slack_ts=' "$HS/autonomy-standing/grants.audit"; ck "ⓗ2 log·grants.audit 은 데이터 루트 \$STATE 그대로(승인 폴더 변경 0)" $?
rm -rf "$HS"; mkdir -p "$HS"; as_seat "$HM"
hz "$HS" "" standing-approve D2 "$A11" --pr 11 --repo pack --verdict "$T/none.md" --card "$CARD"
[ "$rc" = 2 ] && has '① 상시 승인 D2 꺼짐'; ck "ⓙ1 쓰기 좌석도 같은 함수 — 팀 master 판정을 통과해 ①에서 멈춤" $?
rm -rf "$HS"; mkdir -p "$HS"; as_seat "$PL"
hz "$HS" "$DZS/.fable-team/comm" approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD"
[ "$rc" = 0 ] && has '^STANDING-GRANTED D2 '; ck "ⓘ1 FT_MBOX_DIR(데이터 루트 comm)를 줘도 명부 루트는 공용 리포" $?
ND="$T/notgit"; rm -rf "$ND"; mkdir -p "$ND"
out="$(cd "$ND" && FT_ROOT="$ND" FT_AUTONOMY_STATE_DIR="$T/nd-s2" FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD" 2>&1)"; rc=$?
[ "$rc" = 2 ] && has '명부 루트를 못 풂' && [ ! -e "$T/nd-s2/autonomy.log" ]; ck "ⓘ2 데이터 루트가 git 아님 → rc2 «명부 루트를 못 풂» · 쓰기 0" $?

# ══ 변이 M10~M13 — 명부 루트 보정(ⓗⓘⓙ)을 되돌리면 그 칸이 빨강
mut m10 ft-autonomy-standing.sh 'STD_ROOT="$(cd "$FIRST/.." && pwd -P)"' 'STD_ROOT="$ROOT"'
rm -rf "$HS"; mkdir -p "$HS"; as_seat "$PL"; HZB="$T/mut-m10/ft-autonomy.sh" hz "$HS" "" approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD"
[ "$rc" = 2 ] && has '호출 좌석'; ck "ⓘM10 명부 루트를 \$ROOT 로 되돌림 → ⓗ1 칸이 거절된다(빨강 · 실측 꼴)" $?
mut m11 ft-autonomy-standing.sh 'STD_ROOT="$(cd "$FIRST/.." && pwd -P)"' 'STD_ROOT="$(cd "$FT_ROOT/.fable-team/comm/../.." && pwd -P)"'
rm -rf "$HS"; mkdir -p "$HS"; as_seat "$PL"; HZB="$T/mut-m11/ft-autonomy.sh" hz "$HS" "" approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD"
[ "$rc" = 2 ]; ck "ⓘM11 명부 루트를 ft_comm_dir 상위(초안)로 → ⓘ1 칸이 거절된다(빨강)" $?
mut m12 ft-autonomy-standing-d2.sh '--root "$STD_ROOT"' '--root "$ROOT"'
rm -rf "$HS"; mkdir -p "$HS"; as_seat "$HM"; HZB="$T/mut-m12/ft-autonomy.sh" hz "$HS" "" standing-approve D2 "$A11" --pr 11 --repo pack --verdict "$T/none.md" --card "$CARD"
[ "$rc" = 2 ] && has 'ⓑ 팀 master 좌석만'; ck "ⓘM12 켜기만 고치고 쓰기는 그대로 → ⓙ1 칸이 좌석에서 막힌다(빨강)" $?
mut m13 ft-autonomy-standing.sh 'STD_ROOT="$(cd "$FIRST/.." && pwd -P)"' 'STD_ROOT="$(cd "$FIRST/.." && pwd -P)"; [ -n "${FT_MBOX_DIR:-}" ] && STD_ROOT="$(cd "$FT_MBOX_DIR/../.." && pwd -P)"'
rm -rf "$HS"; mkdir -p "$HS"; as_seat "$PL"; HZB="$T/mut-m13/ft-autonomy.sh" hz "$HS" "$DZS/.fable-team/comm" approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD"
[ "$rc" = 2 ]; ck "ⓘM13 FT_MBOX_DIR 을 명부 선택에 반영 → ⓘ1 칸이 거절된다(빨강)" $?

# ══ r1590 ⓐⓑ — ③ 판정문을 «어느 ref» 에서 읽나(D2 = DA 판정 가지 · D1 = origin/main 불변)
mkv_da() {  # mkv_da <이름> <A> <원문> → VF(BYZ origin/docs/da-278062 에만 · 로컬도 그 가지 체크아웃)
  VF="$B/design/harness/da/VERDICT-$1.md"; mkdir -p "$(dirname "$VF")"
  git -C "$B" checkout -q main; git -C "$B" checkout -q -B docs/da-278062
  printf '# 판정 %s\n\n- 승인 sha: %s\n- DA 원문: %s\n- DA 원문 sha256: %s\n- 격리: 세트 %s · rc=0\n' "$1" "$2" "$3" "$(sum256 "$3")" "$2" > "$VF"
  cm "$B" "verdict $1 da"; git -C "$B" push -q origin docs/da-278062:refs/heads/docs/da-278062 && git -C "$B" fetch -q origin; }
mkda r1590a APPROVE "$A11"; fresh; grant; mkv_da r1590a "$A11" "$DAO"; VDA="$VF"
git -C "$B" cat-file -e "refs/remotes/origin/main:design/harness/da/VERDICT-r1590a.md" 2>/dev/null; [ $? != 0 ]; ck "ⓐ0 전제: 판정문이 origin/main 에 없고 DA 가지에만 있음" $?
card "$A11"; as_seat "$HM"; sa "$A11" 11 "$VDA"
[ "$rc" = 0 ] && has "^STANDING-OK $A11 pr=11 repo=pack da=$A11 "; ck "ⓐ1 판정문이 DA 가지에만 있어도 D2 승인 rc0(③ ref = origin/docs/da-278062)" $?
as_seat "$PL"; fresh; run a approve-standing D1 --repos pack --classes code,docs
[ "$rc" = 0 ] && has '^STANDING-GRANTED D1 '; ck "ⓑ0 D1 켜기(planner 좌석)" $?
L0="$(nlog)"; sa_d1() { as_seat "$PL"; L0="$(nlog)"; run a standing-approve "$1" --pr "$2" --repo pack --verdict "$3"; as_seat "$HM"; }
sa_d1 "$A11" 11 "$VDA"
[ "$rc" = 2 ] && has '③ 판정문이 BYZ origin/main 에 없음' && [ ! -e "$S/autonomy-merge-approved/$A11" ]; ck "ⓑ1 같은 판정문으로 D1 = 거절 «origin/main 에 없음»(D1 불변)" $?
mut m14 "$D2F" 'std_verdict "$vf" "$D2_VREF"' 'std_verdict "$vf"'; MFT=m14
SAH="$A11"; SPR=11; SVF="$VDA"; mgo m14
[ "$rc" = 2 ] && has '③ 판정문이 BYZ origin/main 에 없음'; ck "ⓘM14 D2 의 ref 인자를 origin/main 로 되돌림 → ⓐ1 칸이 거절된다(빨강)" $?
git -C "$B" checkout -q main

# ══ 키트 사본 · 크기
for f in ft-autonomy.sh ft-autonomy-standing-d2.sh ft-merge-land.sh ft-merge-lib.sh ft_doc_exempt.py autonomy_scope_rules.py autonomy_scope_classify.py; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f"; ck "키트 사본 cmp0 $f" $?; done
[ "$(wc -l < "$BIN/ft-autonomy.sh")" -le 200 ] && [ "$(wc -l < "$BIN/ft-autonomy-standing.sh")" -le 198 ] && [ "$(wc -l < "$BIN/ft-autonomy-standing-d2.sh")" -le 200 ] && [ "$(wc -l < "$BIN/ft-merge-land.sh")" -le 120 ]; ck "줄 수 상한(autonomy 200 · standing 198 · standing-d2 200 · merge-land 120)   # r1708 N2: desk 갈래로 154 · r1745: standing-status D1·D2 두 줄(+1 → 198)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
