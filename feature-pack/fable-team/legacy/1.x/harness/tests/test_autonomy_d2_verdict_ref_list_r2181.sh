#!/usr/bin/env bash
# test_autonomy_d2_verdict_ref_list_r2181.sh — r2181 D2 ③ 판정문 ref 목록(origin/docs/da-278062 → origin/main) 반례 ②~⑩ + 변이 M1~M5(원본 대조)
#   카드 r2181-autonomy-d2-verdict-ref-list-main-then-da · 대역 = r1577 시험의 임시 BYZ 리포 + 가짜 원격(bare) · 실 BYZ·실 push·실 try-auto 0 · 외부 호출 0 · sleep 0
#   기준판 = 지금 bin 에서 d2_vref 호출만 뺀 사본(b0 · archive 사본에서도 돈다) · 기준판 Red = ③ ⑤ ⑦ · ⑨ 는 기준판 PASS 이고 M5 사본에서 Red
#   설정 줄은 tests/test_autonomy_standing_d2_r1577.sh 머리를 그대로 빌린다(가짜 tmux·gh·슬랙·ssh)
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
mkdir -p "$B/design"; printf '| 팀 | 폴더 | 상태 | 명부 |\n|---|---|---|---|\n| planner | `design/planner/` | 현역 | |\n| harness | `design/harness/` | 현역 | |\n' > "$B/design/TEAMS.md"; printf '/design/TEAMS.md\n' >> "$B/.git/info/exclude"   # r2086: r1907 명부 이름 = TEAMS.md «명부» 칸(빈 칸 = seats-<팀>.json) · exclude = PR 파일 밖
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
card() { CARD="$(fx_card_path "$B" card.md)"; printf '# 카드\n\n## 상태\n- 세트: %s · 시험: bash tests/x.sh rc=0 · 이슈: %s\n' "$1" "${2:-0}" > "$CARD"; cardpub; }
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/card_ref_fixture.sh"; cardpub() { fx_card_pub "$B" "$CARD"; }   # r1904: 카드 = 원장(FT_ROOT) 안 · 고정 ref origin/ops/main-base 커밋 판 · r1951: 팀 카드 꼴 + 표 harness 행
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
PRF="feature-pack/fable-team/legacy/1.x/harness/bin/ft-x.sh"

# ── r2181 도구
D2F=ft-autonomy-standing-d2.sh; RG="$(command -v git)"; VD="$B/design/harness/da"; W40=0123456789abcdef0123456789abcdef01234567
mutx() {  # mutx <이름> <파일> <원문> <바꿀 글> [0] → $T/mut-<이름> (끝 인자 0 = 원문이 없어도 됨 · 기준판 b0 용)
  local mb="$T/mut-$1"; mkdir -p "$mb"; for f in "$BIN"/*; do ln -s "$f" "$mb/$(basename "$f")"; done; rm -f "$mb/$2"
  python3 - "$BIN/$2" "$mb/$2" "$3" "$4" "${5:-1}" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1 or (sys.argv[5] == "0" and s.count(sys.argv[3]) == 0), sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}
vb() { printf '# 판정 r2181\n\n- 승인 sha: %s\n- DA 원문: %s\n- DA 원문 sha256: %s\n- 격리: 세트 %s · rc=0\n' "$1" "$2" "$(sum256 "$2")" "${3:-$1}"; }   # vb <승인 sha> <원문> [격리 세트]
printf '/design/harness/da/V2181-*\n' >> "$B/.git/info/exclude"
pub() {  # pub main|da <판정문> <내용> — 그 원격 가지에만 커밋 · 작업 트리는 main 으로 돌아온다(그 파일은 지워짐 → loc 로 다시 쓴다)
  local br=main; [ "$1" = da ] && br=docs/da-278062
  if git -C "$B" rev-parse -q --verify "refs/remotes/origin/$br" >/dev/null; then git -C "$B" checkout -q -B "w-$1" "origin/$br"; else git -C "$B" checkout -q -B "w-$1" main; fi
  mkdir -p "$(dirname "$2")"; printf '%s' "$3" > "$2"; git -C "$B" add -f -- "$2" && git -C "$B" commit -qm "pub $1" && git -C "$B" push -q origin "w-$1:refs/heads/$br" && git -C "$B" fetch -q origin
  git -C "$B" checkout -q main; }
loc() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; }   # 작업 트리 파일(exclude · 커밋 0)
newA() { mkpr "$1" "$PRF"; A="$PRSHA"; mkda "d$1" APPROVE "$A"; }
go() {  # go <bin 폴더> <A> <PR> <판정문> → out rc · 새 STATE · D2 켜고 팀 master 좌석으로 승인
  fresh; ABIN="$1" grant; card "$2"; as_seat "$HM"; L0="$(nlog)"; ABIN="$1" run a standing-approve D2 "$2" --pr "$3" --repo pack --verdict "$4" --card "$CARD"; }
okk() { [ "$rc" = 0 ] && has "^STANDING-OK $1 pr=$2 " && [ -e "$S/autonomy-merge-approved/$1" ]; }
noap() { [ ! -e "$S/autonomy-merge-approved/$1" ]; }
same() { local o1="$out" r1="$rc"; "$@"; [ "$out" = "$o1" ] && [ "$rc" = "$r1" ]; }   # same <명령…> — 앞 out·rc 와 바이트 같음
mkdir -p "$T/fg"; printf '#!/bin/bash\ncase "${FG_LS:-} $*" in "1 "*ls-tree*da-278062*) exit 128;; " "*da-278062*) exit 128;; esac\nexec "%s" "$@"\n' "$RG" > "$T/fg/git"; chmod +x "$T/fg/git"
mutx b0 "$D2F" 'd2_vref "$vf"; ' '' 0
bash -n "$BIN/$D2F"; ck "bash -n $D2F" $?

# ══ ⑦ 앞 ref 없음 — 원격에 DA 가지 없음 · main 에 판정문 → ③ 통과(기준판 = REJECT)
git -C "$B" rev-parse -q --verify refs/remotes/origin/docs/da-278062 >/dev/null; [ $? = 1 ]; ck "⑦0 전제: 원격에 DA 가지 없음" $?
newA 71; A7="$A"; V7="$VD/V2181-7.md"; pub main "$V7" "$(vb "$A" "$DAO")"; loc "$V7" "$(vb "$A" "$DAO")"
go "$BIN" "$A7" 71 "$V7"; okk "$A7" 71 && ! has '로컬만'; ck "⑦ DA 가지 없음 · main 에만 판정문 → ③ 통과 rc0" $?
go "$T/mut-b0" "$A7" 71 "$V7"; [ "$rc" = 2 ] && has '③ 판정문이 BYZ origin/docs/da-278062 에 없음\(로컬만\)' && noap "$A7"; ck "⑦b 기준판 = ③ REJECT(Red 대조)" $?

# ══ ③ main 에만(실사건 꼴) · DA 가지는 있으나 그 경로 없음 · 작업 트리 값은 틀림 → main blob 값으로 통과
pub da "$VD/V2181-seed.md" seed
newA 31; A3="$A"; V3="$VD/V2181-3.md"; pub main "$V3" "$(vb "$A" "$DAO")"; loc "$V3" "$(vb "$W40" "$DAO")"
! git -C "$B" cat-file -e "refs/remotes/origin/docs/da-278062:design/harness/da/V2181-3.md" 2>/dev/null && git -C "$B" rev-parse -q --verify refs/remotes/origin/docs/da-278062 >/dev/null; ck "③0 전제: DA 가지 있음 · 그 경로 없음" $?
go "$BIN" "$A3" 31 "$V3"; okk "$A3" 31 && ! has '로컬만'; ck "③ 판정문이 origin/main 에만 → ③ 통과 · 필드 = main blob(작업 트리 값 틀림)" $?
go "$T/mut-b0" "$A3" 31 "$V3"; [ "$rc" = 2 ] && has '③ 판정문이 BYZ origin/docs/da-278062 에 없음\(로컬만\)'; ck "③b 기준판 = ③ REJECT(Red 대조)" $?
mutx m1 "$D2F" 'D2_VREFS="$D2_VREF refs/remotes/origin/main"' 'D2_VREFS="$D2_VREF"'
go "$T/mut-m1" "$A3" 31 "$V3"; [ "$rc" = 2 ] && noap "$A3"; ck "M1 목록에서 origin/main 뺌 → ③ 칸이 거절된다(빨강)" $?
mutx m3 "$D2F" '{ D2_VREF="$r"; return 0; }' '{ return 0; }'
go "$T/mut-m3" "$A3" 31 "$V3"; [ "$rc" = 2 ] && noap "$A3"; ck "M3 있음 검사만 목록 · 필드는 DA 가지 고정 → ③ 칸이 거절된다(빨강)" $?
go "$BIN" "$A3" 31 "$V3"; okk "$A3" 31; ck "M1·M3 원본 대조 = ③ 통과" $?

# ══ ② DA 가지에만 → 통과 · 출력·rc 가 기준판과 바이트 같음
newA 21; A2="$A"; V2="$VD/V2181-2.md"; pub da "$V2" "$(vb "$A" "$DAO")"; loc "$V2" "$(vb "$A" "$DAO")"
go "$BIN" "$A2" 21 "$V2"; okk "$A2" 21; ck "② DA 가지에만 → ③ 통과 rc0" $?
same go "$T/mut-b0" "$A2" 21 "$V2"; ck "②b 출력·rc = 기준판 바이트 같음" $?

# ══ ④ 두 ref 에 같은 경로 · 내용 다름(DA = 맞는 sha · main = 틀린 sha) → DA 판으로 통과 · 기준판과 같음
newA 41; A4="$A"; V4="$VD/V2181-4.md"; pub da "$V4" "$(vb "$A" "$DAO")"; pub main "$V4" "$(vb "$W40" "$DAO")"; loc "$V4" "$(vb "$A" "$DAO")"
go "$BIN" "$A4" 41 "$V4"; okk "$A4" 41; ck "④ 두 ref · 내용 다름 → DA 가지 판으로 통과" $?
same go "$T/mut-b0" "$A4" 41 "$V4"; ck "④b 출력·rc = 기준판 바이트 같음" $?
mutx m2 "$D2F" 'D2_VREFS="$D2_VREF refs/remotes/origin/main"' 'D2_VREFS="refs/remotes/origin/main $D2_VREF"'
go "$T/mut-m2" "$A4" 41 "$V4"; [ "$rc" = 2 ] && noap "$A4"; ck "M2 순서 뒤집음(main 먼저) → ④ 칸이 거절된다(빨강)" $?
go "$BIN" "$A4" 41 "$V4"; okk "$A4" 41; ck "M2 원본 대조 = ④ 통과" $?

# ══ ⑤ 두 ref 에 없음 · 작업 트리에만 맞는 판정문 → REJECT · 글에 두 ref
newA 51; A5="$A"; V5="$VD/V2181-5.md"; loc "$V5" "$(vb "$A" "$DAO")"
go "$T/mut-b0" "$A5" 51 "$V5"; R5="$rc"; [ "$rc" = 2 ] && has '③ 판정문이 BYZ origin/docs/da-278062 에 없음\(로컬만\)'; ck "⑤0 기준판 = rc2 · ref 이름 1개" $?
go "$BIN" "$A5" 51 "$V5"; [ "$rc" = "$R5" ] && has '③ 판정문이 BYZ origin/docs/da-278062 · origin/main 에 없음\(로컬만\): design/harness/da/V2181-5.md' && noap "$A5"; ck "⑤ 두 ref 에 없음 → REJECT rc 같음 · 글에 두 ref" $?
mutx m4 "$D2F" 'std_err "③ 판정문이 BYZ $seen 에 없음(로컬만): $f — 착지·git fetch 뒤 다시"' 'git -C "$ROOT" add -f -- "$f"; D2_VREF=":0"; return 0'
go "$T/mut-m4" "$A5" 51 "$V5"; git -C "$B" reset -q; okk "$A5" 51; ck "M4 두 ref 에 없으면 작업 트리 판을 읽음 → ⑤ 칸이 통과로 바뀐다(빨강)" $?
go "$BIN" "$A5" 51 "$V5"; [ "$rc" = 2 ] && noap "$A5"; ck "M4 원본 대조 = ⑤ REJECT" $?

# ══ ⑥ 섞임 0 — DA 가지에 없음 · main 판은 승인 sha 틀림 · 작업 트리는 맞음 → 필드 REJECT
newA 61; A6="$A"; V6="$VD/V2181-6.md"; pub main "$V6" "$(vb "$W40" "$DAO" "$A")"; loc "$V6" "$(vb "$A" "$DAO")"
go "$BIN" "$A6" 61 "$V6"; [ "$rc" = 2 ] && has "^STANDING-REJECT ④ 격리 줄\(세트 $A6 · rc=0\) 의 세트 ≠ 승인 sha\(${W40:0:10}\)" && noap "$A6"; ck "⑥ main 판 필드 틀림 → ③ 지나 ④ 필드 REJECT(작업 트리 값 안 씀)" $?

# ══ ⑨ 조회 실패 — 가짜 git 이 DA 가지 이름이 든 호출만 rc128 · main 에는 맞는 판정문 → 판정 불가 REJECT · 승인 0
newA 91; A9="$A"; V9="$VD/V2181-9.md"; pub main "$V9" "$(vb "$A" "$DAO")"; loc "$V9" "$(vb "$A" "$DAO")"
PATH="$T/fg:$PATH" go "$T/mut-b0" "$A9" 91 "$V9"; R9="$rc"; [ "$rc" = 2 ] && noap "$A9"; ck "⑨0 기준판(가짜 git) = STANDING-REJECT rc2" $?
PATH="$T/fg:$PATH" go "$BIN" "$A9" 91 "$V9"; [ "$rc" = "$R9" ] && has '^STANDING-REJECT ③ 판정 불가 — 판정문 조회 실패 origin/docs/da-278062 rc=128' && noap "$A9"; ck "⑨ ref 조회 rc128 → 판정 불가 REJECT · rc 기준판과 같음 · 승인 0" $?
FG_LS=1 PATH="$T/fg:$PATH" go "$BIN" "$A9" 91 "$V9"; [ "$rc" = "$R9" ] && has '^STANDING-REJECT ③ 판정 불가 — 판정문 조회 실패 origin/docs/da-278062 rc=128' && noap "$A9"; ck "⑨b 경로 조회(ls-tree) rc128 → 판정 불가 REJECT · 승인 0" $?
mutx m5 "$D2F" 'elif [ "$RC" != 1 ] || [ -n "$OUT" ]; then std_err "③ 판정 불가 — 판정문 조회 실패 ${r#refs/remotes/} rc=$RC"; fi' 'fi'
PATH="$T/fg:$PATH" go "$T/mut-m5" "$A9" 91 "$V9"; okk "$A9" 91; ck "M5 조회 실패를 «없음» 으로 읽음 → ⑨ 칸이 rc0 승인으로 바뀐다(빨강)" $?
PATH="$T/fg:$PATH" go "$BIN" "$A9" 91 "$V9"; [ "$rc" = 2 ] && noap "$A9"; ck "M5 원본 대조 = ⑨ REJECT" $?

# ══ ⑩ D1 불변 — 판정문 ref = origin/main 1개 · 있음(⑦ 판)·없음(⑤ 판) 출력·rc 가 기준판과 바이트 같음
d1() { fresh; as_seat "$PL"; ABIN="$1" run a approve-standing D1 --repos pack --classes code,docs; L0="$(nlog)"; ABIN="$1" run a standing-approve "$2" --pr "$3" --repo pack --verdict "$4"; as_seat "$HM"; }
d1 "$BIN" "$A7" 71 "$V7"; same d1 "$T/mut-b0" "$A7" 71 "$V7"; ck "⑩a D1 판정문 있음 = 기준판 바이트 같음" $?
d1 "$BIN" "$A5" 51 "$V5"; [ "$rc" = 2 ] && has '③ 판정문이 BYZ origin/main 에 없음\(로컬만\)'; ck "⑩b0 D1 판정문 없음 = REJECT «origin/main 에 없음»" $?
same d1 "$T/mut-b0" "$A5" 51 "$V5"; ck "⑩b D1 판정문 없음 = 기준판 바이트 같음" $?

# ══ ⑧ bin = kit
for f in ft-autonomy-standing-d2.sh ft-autonomy-standing.sh; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f"; ck "⑧ 키트 사본 cmp0 $f" $?; done
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
