#!/usr/bin/env bash
# test_doc_exempt_r725.sh — R725 «planner 인계·마감 문서 PR 은 승인 h 없이 착지» 판정 1곳(ft_doc_exempt.py) + 두 문(ft-merge-land·autonomy-merge-guard) + docs-push 구멍
# 격리: 임시 origin(bare)+clone · 가짜 gh 스텁 · 임시 루트(FT_ROOT·FT_AUTONOMY_STATE_DIR) — 실 gh·실 저장소·실 쪽지·press 0 (카드 ⓘ)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each   # r466: --level 생략 = full(범위 슬랙 게시) — 이 시험은 레벨 밖이라 each(실 슬랙 0)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; BIN="$ROOT/harness/bin"; LAND="$BIN/ft-merge-land.sh"; AUT="$BIN/ft-autonomy.sh"; DX="$BIN/ft_doc_exempt.py"; PX="$BIN/ft-proxy-decide.sh"
HK="$ROOT/harness/kit/fable-team/templates/hooks"; MG="$HK/autonomy-merge-guard.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SEAT='byz-planner-master-claude#105'   # 현역 planner 이름 꼴(ft-name-lint PASS) — 실 명부 아님(임시)
mkrepo "$T"; mkdir -p "$T/state" "$W/.fable-team" "$T/hooks" "$T/pdir"
printf '.fable-team/\n' >> "$W/.git/info/exclude"   # r2: 명부는 «대상 리포 공용 루트» 에 둔다(출처 검증) — 커밋·diff 에 안 들어가게 제외
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$SEAT" "$W/.fable-team/seats-planner.json"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' 'byz-issues-master-claude#7' "$W/.fable-team/seats-issues.json"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' 'byz-cfo-master-claude#3' "$W/.fable-team/seats-cfo.json"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' 'byz-feature-master-claude#2' "$W/.fable-team/seats-feature.json"   # R741: 하위 폴더가 있는 팀 폴더 판정 픽스처
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' 'byz-room-master-claude#4' "$W/.fable-team/seats-room.json"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' 'byz-v65-master-claude#6' "$W/.fable-team/seats-v65.json"   # R741 DA⑥ r1: baselines·BTS.md 픽스처 팀
printf -- '- **1** 착수 승인\n' > "$T/pdir/VERDICTS-planner-1.md"
# r3: 실제 좌석 = TMUX_PANE 의 세션명 — 시험은 «가짜 tmux» 로 실경로를 그대로 탄다(SELFTEST env 는 실경로에서 못 쓴다 · rc3)
mkdir -p "$T/fakebin"; SEATFILE="$T/seatname"; export SEATFILE; printf '%s' "$SEAT" > "$SEATFILE"
tmux_stub() { printf '#!/bin/bash\n[ "$1" = display-message ] && { cat "$%s"; exit 0; }\nexit 1\n' "$1" > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"; }
tmux_stub SEATFILE
export FT_ROOT="$W" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/pdir" FT_SEAT="$SEAT" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/install-stub" FT_AUTONOMY_SH="$AUT"
export TMUX_PANE=%9 PATH="$T/fakebin:$PATH"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
echo "$*" >> "$STUB_LOG"
EOF
printf '#!/bin/bash\nexit 0\n' > "$T/install-stub"; chmod +x "$T/gh-stub" "$T/install-stub"
cp "$ROOT/harness/kit/hooks/merge_cmd.py" "$T/hooks/"
cp "$HK/autonomy-merge-guard.sh" "$T/hooks/"; MGH="$T/hooks/autonomy-merge-guard.sh"
mkdir -p "$T/nojudge"; ln -s "$AUT" "$T/nojudge/ft-autonomy.sh"   # 판정 모듈이 «없는» 도구 자리(ⓔ7)
DOC='design/teams/planner/HANDOFF-pr1.md'   # ⓑ 에서 착지하는 파일 = 이후 반례 기준선

bash -n "$LAND" && bash -n "$AUT" && bash -n "$PX" && bash -n "$MG" && bash -n "$MGH" \
  && python3 -c 'import ast,sys;ast.parse(open(sys.argv[1]).read())' "$DX"; ck "bash -n 5종 · py 문법" $?

omain() { sha "$ORIGIN" refs/heads/main; }
# 자율 ON 상태 = autonomy.json + autonomy.log 짝(ft-autonomy.sh 가 쓰는 두 파일 그대로) — 이 시험 루트는 git 리포가 아니라 `on` 의 사전 점검이 못 돈다
mode_on() { local e; e="$(date +%s)"; rm -f "$T/state/autonomy.json" "$T/state/autonomy.log"
  printf '%s\ton\tA1\n' "$e" > "$T/state/autonomy.log"; printf '{"mode":"on","since":"%s","event":"A1","until":null}\n' "$e" > "$T/state/autonomy.json"; }
# mkpr <N> [add:<경로>|del:<경로>|sym:<경로>|exe:<경로>]… — origin/main 에서 딴 PR head 를 refs/pull/N/head 에 올리고 스텁 JSON 작성
mkpr() { local n="$1"; shift; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$n" origin/main
  for spec in "$@"; do case "$spec" in doc) spec="add:design/teams/planner/HANDOFF-pr$n.md";; esac; local k="${spec%%:*}" p="${spec#*:}"; mkdir -p "$W/$(dirname "$p")"
    case "$k" in add) printf 'x\n' > "$W/$p";; del) git -C "$W" rm -q "$p";; sym) ln -snf target "$W/$p";; exe) printf '#!/bin/sh\n' > "$W/$p"; chmod +x "$W/$p";; esac; done
  cm "$W" "pr $n work"; git -C "$W" push -q origin "pr$n:refs/pull/$n/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"docs: PR "+sys.argv[2],"body":"본문","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$n" > "$STUB_JSON"; }
land() { out="$(bash "$LAND" "$@" --repo "$W" 2>&1)"; rc=$?; }
seat_set() { printf '%s' "${1-$SEAT}" > "$SEATFILE"; }   # «실제 좌석»(가짜 tmux 세션명) 픽스처
dx() { seat_set "${DXSEAT-$SEAT}"; out="$(FT_SEAT="${DXFTSEAT-${DXSEAT-$SEAT}}" python3 "$DX" --mode "${DXMODE:-doc-exempt}" --repo "${DXREPO:-$W}" --root "${DXROOT-$W}" "$@" 2>&1)"; rc=$?; }
dxm() { seat_set "${DXSEAT-$SEAT}"; out="$(FT_SEAT="${DXFTSEAT-${DXSEAT-$SEAT}}" python3 "$1" --mode doc-exempt --repo "$C" --root "${DXROOT-$W}" --base "$BASEC" --head "$2" 2>&1)"; rc=$?; }   # 변이 사본 실행
runhook() { out="$(printf '%s' "$1" | bash "${HOOKSH:-$MGH}" 2>"$T/err")"; rc=$?; }
mkbash() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "${2:-$W}"; }

# ===== ⓐ 빨강 먼저: 옛 판(origin/main) ft-merge-land 는 문서만 바뀐 PR 도 승인 파일을 요구한다 =====
TOP="$(git -C "$HERE" rev-parse --show-toplevel)"; TOPSHA="$(git -C "$TOP" rev-parse HEAD)"; PFX="$(cd "$HERE/.." && pwd)"; PFX="${PFX#$TOP/}"   # 팩 리포의 옛 판을 «그 리포» 에서 꺼낸다(임시 리포 origin 아님)
mkdir -p "$T/red"; for f in "$BIN"/*; do ln -s "$f" "$T/red/$(basename "$f")"; done; rm -f "$T/red/ft-merge-land.sh"
git -C "$TOP" show "origin/main:$PFX/kit/fable-team/bin/ft-merge-land.sh" > "$T/red/ft-merge-land.sh" || { echo "FAIL 옛 판을 못 꺼냄"; exit 1; }
[ -s "$T/red/ft-merge-land.sh" ] || { echo "FAIL 옛 판이 비었다"; exit 1; }
mkpr 1 doc; P1="$PRSHA"; M0="$(omain)"
out="$(bash "$T/red/ft-merge-land.sh" 1 --approve-sha "$P1" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 2 ] && [[ "$out" == *"승인 파일"* ]] && [ "$(omain)" = "$M0" ]; ck "ⓐ 빨강: 문서만 PR · 승인 파일 없음 → REJECT rc2 · main 불변(옛 판)" $?

# ===== ⓑ 초록: 승인 h 없이 같은 PR 이 squash 로 착지 · 기록 두 곳 =====
land 1
[ "$rc" = 0 ] && [[ "$out" == *LANDED* ]] && [ "$(omain)" != "$M0" ]; ck "ⓑ doc-exempt 로 승인 없이 착지" $?
grep -q "doc-exempt=yes team=planner files=1 by=$SEAT" "$T/state/merge-gate.log"; ck "ⓑ merge-gate.log 에 doc-exempt 기록" $?
grep -qxF "doc-exempt $P1 team=planner files=1 by=$SEAT" "$T/state/autonomy.log"; ck "ⓑ autonomy.log «doc-exempt <sha> team=planner files=1 by=<좌석>» 한 줄" $?
[ "$(bash "$AUT" mode)" = off ] && [ "$(git -C "$W" log -1 --format=%s origin/main)" = "docs: PR 1" ]; ck "ⓑ autonomy.log 줄이 위변조 아님(mode=off) · 착지 커밋 = PR 1개(squash)" $?
git -C "$W" ls-tree -r --name-only origin/main | grep -qxF "$DOC"; ck "ⓑ 착지 트리에 인계서 존재" $?

# ===== ⓓ 판정 실패 = 면제 0(조용한 대체 금지) =====
mkpr 2 doc; P2="$PRSHA"; M2="$(omain)"
land 2 --approve-sha "$P2"
[ "$rc" = 2 ] && [[ "$out" == *"승인 파일"* ]] && [ "$(omain)" = "$M2" ]; ck "ⓓ① 승인 값 있는데 파일 없음 → 대체 없이 REJECT rc2 · main 불변" $?
printf 'garbage\n' > "$STUB_JSON"; land 3
[ "$rc" != 0 ] && [ "$(omain)" = "$M2" ]; ck "ⓓ② gh JSON 깨짐 → 착지 0" $?
mkpr 3 doc; land 3; [ "$rc" = 0 ]; ck "ⓓ③(대조) 정상 문서 PR 은 rc0" $?
mkpr 4 doc; M4="$(omain)"
out="$(FT_DOC_EXEMPT=0 bash "$LAND" 4 --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"doc-exempt 아님"* ]] && [ "$(omain)" = "$M4" ] && grep -qxF "doc-exempt-reject $PRSHA by=$SEAT" "$T/state/autonomy.log"; ck "ⓖ FT_DOC_EXEMPT=0 → 예외 꺼짐 · reject 기록 · 착지 0" $?

# ===== ⓒ 모듈 통과 대조 / 반례 =====
C="$W"; git -C "$C" fetch -q origin; git -C "$C" checkout -q -B c-main origin/main
BASEC="$(sha "$C" c-main)"
cmk() { git -C "$C" checkout -q -B "$1" c-main; shift; for spec in "$@"; do local k="${spec%%:*}" p="${spec#*:}"
  mkdir -p "$C/$(dirname "$p")"; case "$k" in add) printf 'x\n' > "$C/$p";; del) git -C "$C" rm -q "$p";; sym) ln -snf target "$C/$p";; exe) printf '#!/bin/sh\n' > "$C/$p"; chmod +x "$C/$p";; esac; done
  cm "$C" "case $1"; }
git -C "$C" checkout -q -B c-ok c-main; printf 'y\n' >> "$C/$DOC"; cm "$C" "edit doc"
dx --base "$BASEC" --head "$(sha "$C" c-ok)"
[ "$rc" = 0 ] && [ "$out" = "DOC-EXEMPT $(sha "$C" c-ok) files=1 team=planner by=$SEAT" ]; ck "ⓑ+ 수정(M) 만도 통과 · 판정 줄에 실측 좌석" $?
cmk c-issues "add:design/teams/issues/TABLE-2576.md"
dx --base "$BASEC" --head "$(sha "$C" c-issues)"
[ "$rc" = 0 ] && [[ "$out" == *"team=issues"* ]]; ck "ⓑ+ 다른 팀 폴더(issues) .md · planner 좌석 → 통과" $?
DXSEAT='byz-issues-master-claude#7' dx --base "$BASEC" --head "$(sha "$C" c-issues)"
[ "$rc" = 0 ] && [[ "$out" == *"team=issues"* ]]; ck "ⓑ+ 그 팀 master 좌석 → 통과" $?
DXSEAT='byz-cfo-master-claude#3' dx --base "$BASEC" --head "$(sha "$C" c-issues)"
[ "$rc" = 2 ] && [[ "$out" == *"도 planner"* ]]; ck "ⓒ 부른 좌석 팀 ≠ 폴더 팀 → 면제 0(rc2)" $?
cmk c-two "add:design/teams/issues/ISSUE-A.md" "add:design/teams/cfo/ISSUE-B.md"
dx --base "$BASEC" --head "$(sha "$C" c-two)"
[ "$rc" = 1 ] && [[ "$out" == *"한 PR 한 팀 폴더"* ]]; ck "ⓒ 두 팀 폴더 섞인 PR → 면제 0" $?
dcase() { local name="$1"; shift; local br="c-$(echo "$name" | tr -cd 'a-z0-9')"; cmk "$br" "$@"
  dx --base "$BASEC" --head "$(sha "$C" "$br")"
  [ "$rc" != 0 ] && [[ "$out" == NOT* ]]; ck "ⓒ ${name} → 면제 0 (${out:0:64})" $?; }
dcase "VERDICTS 원장" "add:design/teams/planner/VERDICTS-planner-9.md"
dcase "GOAL GUIDE SEATBELT" "add:design/teams/issues/GOAL-issues.md" "add:design/teams/issues/GUIDE-desk.md" "add:design/teams/issues/SEATBELT-x.md"
dcase "README BOARD" "add:design/teams/issues/README.md" "add:design/teams/issues/BOARD.md"
dcase "제외 폴더 indices(카드)" "add:design/teams/planner/indices/HANDOFF-x.md"   # R741: 옛 «팀 하위 폴더» 반례는 이 카드가 뒤집었다(문서 범위 확대) — 제외 폴더 꼼로 유지
dcase "md 아닌 파일" "add:design/teams/planner/HANDOFF-x.md" "add:design/teams/planner/note.txt"
dcase "삭제 1개" "del:$DOC"
dcase "링크 md" "sym:design/teams/planner/HANDOFF-link.md"
dcase "실행비트 md" "exe:design/teams/planner/HANDOFF-run.md"
dcase "옛 꼴 design/issues" "add:design/issues/TABLE.md"
dcase "팀 폴더 밖 design/TEAMS.md" "add:design/TEAMS.md"
dcase "팀 이름 대문자" "add:design/teams/Issues/TABLE.md"
DXSEAT='byz-harness-nano-other#0' dx --base "$BASEC" --head "$(sha "$C" c-ok)"
[ "$rc" = 2 ] && [[ "$out" == *"도 planner"* ]]; ck "ⓒ 팀 master 도 planner 도 아닌 좌석 → 면제 0(rc2)" $?
DXSEAT='' dx --base "$BASEC" --head "$(sha "$C" c-ok)"
[ "$rc" = 2 ] && [[ "$out" == *"좌석 해석 실패"* ]]; ck "ⓒ 좌석 해석 실패 → 면제 0(rc2)" $?
mv "$W/.fable-team/seats-planner.json" "$T/seats-planner.json.bak"
dx --base "$BASEC" --head "$(sha "$C" c-ok)"
[ "$rc" = 2 ] && [[ "$out" == *"planner 명부"* ]]; ck "ⓒ 명부 없음 → 면제 0(rc2)" $?
mv "$T/seats-planner.json.bak" "$W/.fable-team/seats-planner.json"
dx --base "$(sha "$C" c-ok)" --head "$(sha "$C" c-ok)"
[ "$rc" = 1 ] && [[ "$out" == *"바뀐 경로 0"* ]]; ck "ⓒ 판정 뒤 head/base 바뀜(빈 diff) → 면제 0" $?
dx --base "$BASEC" --head 0000000000000000000000000000000000000000
[ "$rc" != 0 ] && [[ "$out" == NOT* ]]; ck "ⓒ 없는 head → 면제 0" $?
dx --base deadbeef --head "$(sha "$C" c-ok)"
[ "$rc" = 2 ]; ck "ⓒ base 형식 틀림 → 판정 불가 rc2" $?
# ⓗ 외부 호출 상한: 닿지 않는 원격 → 7초+재시도 1 안에 면제 0(무한 대기 0)
t0=$SECONDS; DXREMOTE="$T/nope.git"; out="$(python3 "$DX" --repo "$C" --root "$T" --remote "$DXREMOTE" --head "$(sha "$C" c-ok)" 2>&1)"; rc=$?
el=$((SECONDS - t0)); [ "$rc" = 2 ] && [ "$el" -le 20 ]; ck "ⓗ 원격 불통 → 면제 0 · ${el}s(≤20)" $?

# ===== ⓕ docs-push: design/x.py = QUEUE · .md 만 = 통과 =====
git -C "$W" checkout -q -B docs-py origin/main; printf 'd\n' > "$W/design/teams/planner/HANDOFF-docs.md"; cm "$W" "doc head"; git -C "$W" push -q origin docs-py
mkdir -p "$W/design/teams/planner"; printf 'print(1)\n' > "$W/design/teams/planner/x.py"; cm "$W" "py under design"; DP="$(sha "$W" HEAD)"
DXMODE=md-files dx --base "$(sha "$W" origin/main)" --head "$DP"
[ "$rc" = 1 ] && [[ "$out" == *"문서(.md) 아닌 파일"* ]]; ck "ⓕ design/x.py = 면제 0(옛 design/* 구멍 막힘)" $?
git -C "$W" checkout -q -B docs-md origin/main; printf 'm\n' > "$W/design/teams/planner/HANDOFF-push.md"; cm "$W" "md only"; DM="$(sha "$W" HEAD)"
DXMODE=md-files dx --base "$(sha "$W" origin/main)" --head "$DM"
[ "$rc" = 0 ] && [[ "$out" == DOC-FILES* ]]; ck "ⓕ .md 만이면 DOC-FILES" $?
mode_on; [ "$(bash "$AUT" mode)" = on ]; ck "ⓕ·ⓔ 전제: 자율 ON · autonomy.log 위변조 아님" $?
out="$(cd "$W" && FT_DEPLOY_BRANCHES='feat/*' bash "$PX" --kind docs-push --branch docs-py --sha "$DP" --q q --choice c --why w --undo u 2>&1)"; rc=$?
[ "$rc" = 2 ] && [[ "$out" == *"문서(.md) 아닌 파일"* ]]; ck "ⓕ ft-proxy-decide docs-push 가 같은 판정을 부른다(QUEUE)" $?

# ===== ⓔ 가드(DA⑥ r1 질문 6): 문서 전용 예외는 ft-merge-land 경유 «한 길»뿐 — 직접 push·gh pr merge 는 승인 파일 필요 그대로 =====
git -C "$W" checkout -q -B g-doc origin/main; mkdir -p "$W/design/teams/planner"; printf 'g\n' > "$W/design/teams/planner/CLOSEOUT-planner-1.md"; cm "$W" "guard doc"; GD="$(sha "$W" HEAD)"
git -C "$W" checkout -q -B g-code origin/main; printf 'code\n' >> "$W/a.txt"; cm "$W" "guard code"; GC="$(sha "$W" HEAD)"
git -C "$W" checkout -q main
mode_on
runhook "$(mkbash "git push origin $GD:refs/heads/main")"
[ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; ck "ⓔ1 ON · 승인 없음 · 문서만 sha 직접 push → deny(면제 0)" $?
runhook "$(mkbash "gh pr merge 7 --squash --match-head-commit $GD")"
[ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; ck "ⓔ2 ON · gh pr merge 문서 sha → deny(면제 0)" $?
runhook "$(mkbash "git push origin $GC:refs/heads/main")"
[ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; ck "ⓔ3 ON · 코드 sha → deny" $?
runhook "$(mkbash "git push other $GD:refs/heads/main")"
[ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; ck "ⓔ4 목적지 other 여도 직접 push → deny" $?
bash "$AUT" approve-merge "$GD" >/dev/null 2>&1 && [ "$(bash "$AUT" mode)" = on ]
runhook "$(mkbash "git push origin $GD:refs/heads/main")"
[ "$rc" = 0 ] && [ -z "$out" ]; ck "ⓔ5(대조) 오빠 승인 파일 있는 sha 는 그대로 allow" $?
[ "$(bash "$AUT" mode)" = on ]; ck "ⓔ6 hook 이 자율 상태를 위변조로 만들지 않음(mode=on 유지)" $?

# ===== ⓝ r2(DA⑥ r1 HOLD 처방 1~5): 새 검사가 «옛 판 동작» 을 거절한다 — 각 항목 빨강(그 검사 지운 사본 = 통과) → 초록(새 판 = 거절) =====
MUT2="$T/mut2"; mkdir -p "$MUT2"; ln -s "$BIN/ft-name-lint.sh" "$MUT2/"; cp "$ROOT/harness/kit/hooks/merge_cmd.py" "$MUT2/"   # 가드 사본도 같은 폴더 공용 모듈(r546)을 갖는다
cp "$BIN/ft_doc_exempt.py" "$BIN/ft_doc_exempt_paths.py" "$MUT2/"   # R741: 사본도 같은 폴더 경로 모듈을 갖는다(없으면 import 실패 = 전부 rc2 로 덮인다)
mut2p() { python3 - "$BIN/ft_doc_exempt_paths.py" "$MUT2/ft_doc_exempt_paths.py" "$1" "$2" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  [ -s "$MUT2/ft_doc_exempt_paths.py" ] || { echo "FAIL 변이 생성 실패(대상 문장이 없다): $1"; fail=$((fail+1)); return 1; }
}
mut2() { python3 - "$DX" "$MUT2/$1" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  [ -s "$MUT2/$1" ] || { echo "FAIL 변이 생성 실패(대상 문장이 없다): $1"; fail=$((fail+1)); return 1; }   # r3: 생성 실패를 ALL PASS 로 덮지 않는다
}
OKSHA="$(sha "$C" c-ok)"
# ⓝ① 실제 좌석(DA⑥ 질문 1 · r3: SELFTEST env 는 실경로에서 못 쓴다)
mut2 n1.py 'if os.environ.get("FT_DOC_EXEMPT_SELFTEST") == "1":' 'if True: '   # 좌석 = 자기 신고만 보는 «옛 판» 동작
DXSEAT='byz-cfo-master-claude#3' DXFTSEAT="$SEAT" dxm "$MUT2/n1.py" "$OKSHA"; [ "$rc" = 0 ]; ck "ⓝ①a 빨강(자기 신고 좌석만 보는 사본 = 실제 좌석 cfo 인데도 rc0)" $?
out="$(env -u TMUX_PANE FT_SEAT="$SEAT" python3 "$DX" --mode doc-exempt --repo "$W" --root "$W" --base "$BASEC" --head "$OKSHA" 2>&1)"; rc=$?
[ "$rc" = 2 ] && [[ "$out" == *"좌석 해석 실패"* ]]; ck "ⓝ①b TMUX_PANE 없이 자기 신고만 → 면제 0(rc2)" $?
dx --base "$BASEC" --head "$OKSHA"; [ "$rc" = 0 ] && [ "$out" = "DOC-EXEMPT $OKSHA files=1 team=planner by=$SEAT" ]; ck "ⓝ①c 실제 좌석(가짜 tmux 세션명) == 자기 신고 → 통과 · 판정 줄에 실측 좌석" $?
DXFTSEAT='byz-cfo-master-claude#3' dx --base "$BASEC" --head "$OKSHA"
[ "$rc" = 2 ] && [[ "$out" == *"자기 신고 좌석"* ]]; ck "ⓝ①d 자기 신고 ≠ 실제 좌석 → 면제 0(rc2)" $?
tmux_stub NOPE   # display-message 실패 = 좌석 해석 실패
dx --base "$BASEC" --head "$OKSHA"; [ "$rc" = 2 ] && [[ "$out" == *"좌석 해석 실패"* ]]; ck "ⓝ①e tmux 조회 실패 → 면제 0(rc2)" $?
tmux_stub SEATFILE
out="$(FT_DOC_EXEMPT_SELFTEST=1 FT_DOC_EXEMPT_SEAT="$SEAT" FT_SEAT="$SEAT" python3 "$DX" --mode doc-exempt --repo "$W" --root "$W" --base "$BASEC" --head "$OKSHA" 2>&1)"; rc=$?
[ "$rc" = 3 ] && [[ "$out" == *"DOC-EXEMPT $OKSHA files=1 team=planner by=$SEAT"* ]] && [[ "$out" == *SELFTEST* ]]; ck "ⓝ①f SELFTEST 판정 성공도 rc3(착지에 못 쓴다)" $?
mkpr 7 doc; M7="$(omain)"; seat_set 'byz-harness-nano-other#0'   # 실제 좌석 = 나노, 자기 신고·SELFTEST 는 planner 로 위조
out="$(FT_SEAT="$SEAT" FT_DOC_EXEMPT_SELFTEST=1 FT_DOC_EXEMPT_SEAT="$SEAT" bash "$LAND" 7 --repo "$W" 2>&1)"; rc=$?
[ "$rc" != 0 ] && [ "$(omain)" = "$M7" ]; ck "ⓝ①g 실경로: SELFTEST·자기신고 export 로는 착지 0(lib 가 env -u)" $?
seat_set; land 7; [ "$rc" = 0 ] && [ "$(omain)" != "$M7" ]; ck "ⓝ①h (대조) 같은 PR 을 정상 좌석으로는 착지" $?
# ⓝ② 명부 루트 출처(DA⑥ 질문 4) — 가짜 명부에 자기 이름을 _master 로 쳐밖는 길
mkdir -p "$T/fakeroot/.fable-team"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' 'byz-harness-nano-other#0' "$T/fakeroot/.fable-team/seats-planner.json"
mut2 n2.py 'root = verified_root(repo, roota)' 'root = roota or os.environ.get("FT_ROOT") or repo'
DXSEAT='byz-harness-nano-other#0' DXROOT="$T/fakeroot" dxm "$MUT2/n2.py" "$OKSHA"; [ "$rc" = 0 ]; ck "ⓝ②a 빨강(옛 판 = 가짜 루트·가짜 _master 로 rc0)" $?
DXSEAT='byz-harness-nano-other#0' DXROOT="$T/fakeroot" dx --base "$BASEC" --head "$OKSHA"
[ "$rc" = 2 ] && [[ "$out" == *"명부 루트"* ]]; ck "ⓝ②b 가짜 명부 루트(_master = 나) → 면제 0(rc2)" $?
mkdir -p "$T/dataroot/.fable-team"; cp "$W/.fable-team/seats-planner.json" "$T/dataroot/.fable-team/"
printf '%s\n' "$T/dataroot" > "$W/.fable-team/LIVE_ROOT"
DXROOT="$T/dataroot" dx --base "$BASEC" --head "$OKSHA"
[ "$rc" = 0 ] && [[ "$out" == DOC-EXEMPT* ]]; ck "ⓝ②c 대상 리포 .fable-team/LIVE_ROOT 1행의 루트 → 통과" $?
rm -f "$W/.fable-team/LIVE_ROOT"
# ⓝ③ 바이너리 fail-closed(DA⑥ 질문 3) — numstat 실패·속성 강제로 바이너리가 통과하던 자리
mkdir -p "$T/gitbin"; printf '#!/bin/bash\ncase "$*" in *--numstat*) exit 128;; esac\nexec %s "$@"\n' "$(command -v git)" > "$T/gitbin/git"; chmod +x "$T/gitbin/git"
mut2 n3.py 'why = blob_bad(repo, head, p)' 'why = ""'
git -C "$C" checkout -q -B n-nul c-main; mkdir -p "$C/design/teams/planner"; printf 'A\000B\n' > "$C/design/teams/planner/HANDOFF-nul.md"; cm "$C" "nul md"; NS="$(sha "$C" n-nul)"
dxm "$MUT2/n3.py" "$NS"; [ "$rc" = 0 ]; ck "ⓝ③a 빨강(옛 판 = NUL 바이트 .md 가 rc0)" $?
out="$(env PATH="$T/gitbin:$PATH" FT_SEAT="$SEAT" FT_DOC_EXEMPT_SEAT="$SEAT" python3 "$DX" --mode doc-exempt --repo "$C" --root "$W" --base "$BASEC" --head "$OKSHA" 2>&1)"; rc=$?
[ "$rc" = 2 ] && [[ "$out" == *"numstat 실패"* ]]; ck "ⓝ③b numstat rc≠0 = 판정 불가(rc2 · 면제 0) — 정상 문서에도 못 넘긴다" $?
dx --base "$BASEC" --head "$NS"
[ "$rc" = 1 ] && [[ "$out" == *"바이너리"* ]]; ck "ⓝ③d NUL 바이트 .md → 면제 0" $?
git -C "$C" checkout -q -B n-utf c-main; printf 'A\377B\n' > "$C/design/teams/planner/HANDOFF-utf.md"; cm "$C" "bad utf8 md"; US="$(sha "$C" n-utf)"
dx --base "$BASEC" --head "$US"
[ "$rc" = 1 ] && [[ "$out" == *"UTF-8"* ]]; ck "ⓝ③e UTF-8 아닌 .md → 면제 0" $?
printf '*.md diff\n' > "$C/.git/info/attributes"
dx --base "$BASEC" --head "$NS"
[ "$rc" = 1 ] && [[ "$out" == *"바이너리"* ]]; ck "ⓝ③e git info attributes 의 *.md diff 속성으로도 안 열린다" $?
rm -f "$C/.git/info/attributes"
# ⓝ④ 판정 입력 .md 제외(DA⑥ 질문 5)
python3 - "$BIN/ft_doc_exempt_paths.py" "$MUT2/ft_doc_exempt_paths.py" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
for old, new in [
    ('         "PLAN-oppa-ledger", "FLAG-DECISIONS", "MERGE-QUEUE", "STATE.md", "NANO-LEDGER", "NEWS-TREE", "DECISION",\n         "LEDGER")',
     '         "STATE.md", "NANO-LEDGER", "NEWS-TREE", "DECISION")'),
    ('"plan-oppa-ledger.md", ', ''),
]:
    assert old in s, "변이 대상 없음: " + old
    s = s.replace(old, new, 1)
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY
[ -s "$MUT2/ft_doc_exempt_paths.py" ] || { echo "FAIL 변이 생성 실패(ⓝ④a)"; fail=$((fail+1)); }   # R741 DA⑥ r1: CANON 과 EXCLUDE_NAMES «둘 다» 에서 빠야 옛 판 동작(통과)이 재현된다
cmk n-plan "add:design/teams/planner/PLAN-oppa-ledger.md"
DXROOT="$W" dxm "$MUT2/ft_doc_exempt.py" "$(sha "$C" n-plan)"; [ "$rc" = 0 ]; ck "ⓝ④a 빨강(추가분 제거한 사본 = PLAN-oppa-ledger ✓ 통과)" $?
for nm in PLAN-oppa-ledger.md FLAG-DECISIONS.md MERGE-QUEUE.md STATE.md NANO-LEDGER.md NEWS-TREE.md DECISION-x.md; do
  dcase "canon-${nm,,}" "add:design/teams/planner/$nm"
done
# ⓝ⑤ 가드 직접 경로에 면제 복원 = 변이로 잡힌다(DA⑥ 질문 6)
python3 - "$MGH" "$MUT2/n5.py" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = "        if not self.approved or not self.judge:\n            return False"
assert old in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, "        if True:\n            return True", 1))
PY
git -C "$W" checkout -q -B g-doc2 origin/main; mkdir -p "$W/design/teams/planner"; printf 'g2\n' > "$W/design/teams/planner/CLOSEOUT-planner-2.md"; cm "$W" "guard doc2"; GD2="$(sha "$W" HEAD)"; git -C "$W" checkout -q main
runhook "$(mkbash "git push origin $GD2:refs/heads/main")"
[ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; ck "ⓝ⑤a (대조) 새 문서 sha · 승인 없음 → 원판 가드 deny" $?
out="$(printf '%s' "$(mkbash "git push origin $GD2:refs/heads/main")" | bash "$MUT2/n5.py" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ! grep -q 'permissionDecision": "deny"' <<<"$out"; ck "ⓝ⑤ 빨강(가드에 직접경로 면제를 되살리면 allow — 변이 감지)" $?

# ===== ⓙ 변이: 검사를 지우면 그 반례가 통과해 버린다(시험이 검사를 실제로 잡는다) =====
MUT="$T/mut"; mkdir -p "$MUT"; ln -s "$BIN/ft-name-lint.sh" "$MUT/"   # 변이 사본도 이름 lint 자리를 갖는다(같은 폴더 규칙)
cp "$BIN/ft_doc_exempt.py" "$BIN/ft_doc_exempt_paths.py" "$MUT/"   # R741: 경로 판정 = 같은 폴더 새 모듈 · 변이는 그 모듈에서
PM="$BIN/ft_doc_exempt_paths.py"
mut() { python3 - "$DX" "$MUT/$1" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  [ -s "$MUT/$1" ] || { echo "FAIL 변이 생성 실패(대상 문장이 없다): $1"; fail=$((fail+1)); return 1; }   # r3
}
mutp() { python3 - "$PM" "$MUT/ft_doc_exempt_paths.py" "$1" "$2" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  [ -s "$MUT/ft_doc_exempt_paths.py" ] || { echo "FAIL 변이 생성 실패(대상 문장이 없다): $1"; fail=$((fail+1)); return 1; }
}
unmutp() { cp "$PM" "$MUT/ft_doc_exempt_paths.py"; }
cmk m-name "add:design/teams/planner/VERDICTS-planner-9.md"
mutp "if canon_hit(name):" "if False:"
dxm "$MUT/ft_doc_exempt.py" "$(sha "$C" m-name)"; [ "$rc" = 0 ]; ck "ⓙ① 정본·승인근거 이름 검사 삭제 → VERDICTS 반례가 통과(FAIL 재현)" $?
unmutp
cmk m-sub "add:design/teams/planner/sub/HANDOFF-x.md"   # R741: 이제 범위 안 — 대조(원판 rc0 · 변이 무관)
dx --base "$BASEC" --head "$(sha "$C" m-sub)"; [ "$rc" = 0 ] && [[ "$out" == *"team=planner"* ]]; ck "ⓙ②(R741 대조) 하위 폴더 .md = 범위 안 → rc0" $?
cmk m-ind "add:design/teams/planner/indices/HANDOFF-x.md"   # 교체된 반례: 제외 폴더 — 검사 삭제 시 통과해야 변이가 잡힌다
mutp 'if key(seg) in EXCLUDE_DIRS:' 'if False:'
dxm "$MUT/ft_doc_exempt.py" "$(sha "$C" m-ind)"; [ "$rc" = 0 ]; ck "ⓙ② 제외 폴더 검사 삭제 → indices 하위 폴더 반례가 통과(FAIL 재현)" $?
unmutp
mutp 'if key(seg) in EXCLUDE_DIRS:' 'if seg in EXCLUDE_DIRS:'
cmk m-indicase "add:design/teams/planner/Indices/HANDOFF-x.md"
dxm "$MUT/ft_doc_exempt.py" "$(sha "$C" m-indicase)"; [ "$rc" = 0 ]; ck "ⓙ②b 제외 폴더 «대소문자 무시» 삭제 → Indices 반례가 통과(FAIL 재현)" $?
unmutp
mutp 'low = key(name)' 'low = name'
cmk m-canoncase "add:design/teams/planner/evidence/Goal-x.md"
dxm "$MUT/ft_doc_exempt.py" "$(sha "$C" m-canoncase)"; [ "$rc" = 0 ]; ck "ⓙ②c 이름 거절 «대소문자 무시» 삭제 → Goal-x 반례가 통과(FAIL 재현)" $?
unmutp
mutp '         "LEDGER")' '         )'
cmk m-ledger "add:design/teams/planner/a/LEDGER-run.md"
dxm "$MUT/ft_doc_exempt.py" "$(sha "$C" m-ledger)"; [ "$rc" = 0 ]; ck "ⓙ②d LEDGER 접두 삭제 → 깊은 LEDGER-run 반례가 통과(FAIL 재현)" $?
unmutp
mutp 'if seg.startswith("."):' 'if False:'
cmk m-dot "add:design/teams/planner/.omc/NOTE-omc.md"
dxm "$MUT/ft_doc_exempt.py" "$(sha "$C" m-dot)"; [ "$rc" = 0 ]; ck "ⓙ②e 점 폴더 검사 삭제 → .omc 반례가 통과(FAIL 재현)" $?
unmutp
MUTB="$T/mutbin"; mkdir -p "$MUTB"; for f in "$BIN"/*; do ln -s "$f" "$MUTB/$(basename "$f")"; done; rm -f "$MUTB/ft-merge-land.sh"
python3 - "$LAND" "$MUTB/ft-merge-land.sh" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = '[ -z "$FF" ] || [ "$HEADSHA" = "$AP" ] || rej "ff 는'
assert old in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, 'true || true || rej "ff 는', 1))
PY
mkpr 5 doc; M5="$(omain)"
out="$(bash "$MUTB/ft-merge-land.sh" 5 --ff --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(omain)" != "$M5" ]; ck "ⓙ③ --ff 강제 삭제 → ff 반례가 통과(FAIL 재현)" $?
mkpr 6 doc; M6="$(omain)"; out="$(bash "$LAND" 6 --ff --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"ff 는 승인 sha"* ]] && [ "$(omain)" = "$M6" ]; ck "ⓙ③b 원판은 --ff 를 REJECT(문서 경로도 squash 만)" $?

# ===== R741 (카드 r741-doc-exempt-team-subfolders): 면제 범위 = 팀 폴더 «하위 폴더» .md 까지 · 제외 폴더·이름 거절·대소문자는 모든 깊이 =====
pcase() { local name="$1" team="$2"; shift 2; local br="r7-$(echo "$name" | tr -cd 'a-z0-9')" hs; cmk "$br" "$@"; hs="$(sha "$C" "$br")"
  dx --base "$BASEC" --head "$hs"
  if [ "$rc" = 0 ] && [ "$out" = "DOC-EXEMPT $hs files=$# team=$team by=$SEAT" ]; then ck "ⓑ ${name} → DOC-EXEMPT team=$team files=$#" 0
  else local keep="$out"; out="rc=$rc $keep"; ck "ⓑ ${name} → DOC-EXEMPT team=$team files=$#" 1; fi; }
pcase "feature/evidence" feature "add:design/teams/feature/evidence/NOTE-r741.md"
pcase "room/evidence-t1" room "add:design/teams/room/evidence-t1/y.md"
pcase "planner/20261022 날짜 폴더" planner "add:design/teams/planner/20261022/z.md"
pcase "feature/a/b/c 깊은 폴더" feature "add:design/teams/feature/a/b/c.md"
pcase "하위 폴더 두 곳 한 PR" feature "add:design/teams/feature/evidence/NOTE-a.md" "add:design/teams/feature/20261022/NOTE-b.md"
DXSEAT='byz-feature-master-claude#2' dx --base "$BASEC" --head "$(sha "$C" r7-featureevidence)"
[ "$rc" = 0 ] && [[ "$out" == *"team=feature by=byz-feature-master-claude#2"* ]]; ck "ⓑ 하위 폴더 PR · 그 팀 master 좌석 → 통과" $?
# ⓒ 제외 폴더 = 도구가 판정 입력으로 읽는 곳 — 어느 깊이에서든 거절
dcase "제외 indices/완성" "add:design/teams/planner/indices/완성/x.md"
dcase "제외 indices/inbox/arch" "add:design/teams/planner/indices/inbox/arch/x.md"
dcase "제외 keys" "add:design/teams/planner/keys/x.md"
dcase "제외 a/indices(깊이 무관)" "add:design/teams/planner/a/indices/x.md"
dcase "제외 .omc(점 폴더)" "add:design/teams/planner/.omc/x.md"
dcase "하위 폴더 링크 md" "sym:design/teams/planner/evidence/l.md"
dcase "두 팀 하위 폴더 섞임" "add:design/teams/feature/evidence/a.md" "add:design/teams/room/evidence/b.md"
# ⓓ 대소문자 우회 · ⓔ 이름 거절 목록은 모든 깊이
dcase "제외 폴더 대문자 Indices" "add:design/teams/planner/Indices/x.md"
dcase "제외 폴더 대문자 KEYS" "add:design/teams/planner/KEYS/x.md"
dcase "이름 거절(증거 폴더 goal-x)" "add:design/teams/planner/evidence/goal-x.md"
dcase "이름 거절(증거 폴더 Goal-x)" "add:design/teams/planner/evidence/Goal-x.md"
dcase "깊은 PLAN-oppa-ledger" "add:design/teams/planner/evidence/PLAN-oppa-ledger.md"
dcase "깊은 STATE.md" "add:design/teams/planner/a/STATE.md"
dcase "깊은 LEDGER-keys(LEDGER 접두)" "add:design/teams/planner/a/LEDGER-keys.md"
dcase "직속 LEDGER-keys" "add:design/teams/planner/LEDGER-keys.md"
# ⓓ2 DA⑥ r1 처방 2·3·5 = baselines 제외 폴더 · 키트가 이름으로 부르는 .md(FLAGS.md·BTS.md) · 긴 s ſ · 대문자 확장자
dcase "제외 baselines/FLAGS.md" "add:design/teams/v65/baselines/FLAGS.md"
dcase "제외 Baselines(대소문자)" "add:design/teams/v65/Baselines/FLAGS-notes.md"
dcase "이름 거절 BTS.md(증거 폴더 깊이 2)" "add:design/teams/v65/evidence/r1/BTS.md"
dcase "이름 거절 bts.MD(대문자 확장자)" "add:design/teams/v65/evidence/r1/bts.MD"
dcase "이름 거절 readme.md(직속 대소문자)" "add:design/teams/planner/readme.md"
# ⓕ 경로 모양 우회 — 모듈 함수 직접( git 은 정규화된 경로만 낸다 )
pj() { python3 - "$BIN" "$1" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ft_doc_exempt_paths as m
team, why = m.team_of(sys.argv[2])
print(("REJECT " + why) if why else ("OK " + team))
PY
}
shape() { local name="$1" path="$2"; out="$(pj "$path")"; if [[ "$out" == REJECT* ]]; then ck "ⓕ ${name} → 거절(${out:0:70})" 0; else ck "ⓕ ${name} → 거절(${out:0:70})" 1; fi; }
shape ".. 조각" "design/teams/planner/a/../b/x.md"
shape ". 조각" "design/teams/planner/./x.md"
shape "빈 조각(//)" "design/teams/planner//x.md"
shape "제어문자" "design/teams/planner/a"$'\x01'"x.md"
shape "NFC 아님" "design/teams/planner/evide"$'\xcc\x81'"nce/x.md"
shape "점으로 시작하는 파일 이름" "design/teams/planner/evidence/.hidden.md"
shape "긴 s ſ 폴더(indiceſ)" "design/teams/planner/indice"$'\xc5\xbf'"/진행/r741.md"
shape "긴 s ſ 파일 이름(ſTATE)" "design/teams/planner/evidence/"$'\xc5\xbf'"TATE.md"
shape "호환문자 ﬁ 파일 이름" "design/teams/planner/evidence/"$'\xef\xac\x81'"le.md"
shape "NFC 아닌 폴더 이름" "design/teams/planner/evide"$'\xcc\x81'"nce2/NOTE.md"
# ⓑ+ 직속 .md 회귀 0 — 범위 확대가 직속을 깨지 않는다
cmk r7-direct "add:design/teams/planner/HANDOFF-direct.md"
dx --base "$BASEC" --head "$(sha "$C" r7-direct)"
[ "$rc" = 0 ] && [[ "$out" == "DOC-EXEMPT $(sha "$C" r7-direct) files=1 team=planner by=$SEAT" ]]; ck "ⓑ+ 직속 .md 회귀 0(범위 확대 뒤에도 그대로 rc0)" $?
# ⓙ②f⁃g⁃h DA⑥ r1 처방 1·3 변이 — 비교 키(NFKC·casefold)와 EXCLUDE_NAMES 를 지우면 그 반례가 통과해 버린다
mutp 'if unicodedata.normalize("NFKC", seg) != seg:' 'if False:'
cmk r7-longs "add:design/teams/planner/evidence/NOTE-"$'\xc5\xbf'"x.md"
dxm "$MUT/ft_doc_exempt.py" "$(sha "$C" r7-longs)"; [ "$rc" = 0 ]; ck "ⓙ②f 호환문자(긴 s ſ) 검사 삭제 → ſ 반례가 통과(FAIL 재현)" $?
unmutp
mutp 'if key(seg) in EXCLUDE_DIRS:' 'if seg in EXCLUDE_DIRS:'
cmk r7-basecase "add:design/teams/v65/Baselines/FLAGS-notes.md"
dxm "$MUT/ft_doc_exempt.py" "$(sha "$C" r7-basecase)"; [ "$rc" = 0 ]; ck "ⓙ②g 제외 폴더 key(NFKC+casefold) 비교 삭제 → Baselines 반례가 통과(FAIL 재현)" $?
unmutp
mutp 'if excluded_name(name):' 'if False:'
cmk r7-bts "add:design/teams/v65/evidence/r1/BTS.md"
dxm "$MUT/ft_doc_exempt.py" "$(sha "$C" r7-bts)"; [ "$rc" = 0 ]; ck "ⓙ②h 이름 목록(EXCLUDE_NAMES) 검사 삭제 → BTS.md 반례가 통과(FAIL 재현)" $?
unmutp
# ⓗ r3 (오바 결정 선택지 1) — 팀 하위 폴더는 «새 파일 추가(A)» 만 면제 · 수정/삭제/이름바꾸기(M/D/R)는 직속만
SD="design/teams/planner/evidence/EDITED-r741.md"
git -C "$C" checkout -q -B sk-base c-main; mkdir -p "$C/$(dirname "$SD")"; printf 'v1\n' > "$C/$SD"; cm "$C" "sk base"; E_BASE="$(sha "$C" sk-base)"
git -C "$C" checkout -q -B sk-mod "$E_BASE"; printf 'v2\n' > "$C/$SD"; cm "$C" "sk mod"; E_MOD="$(sha "$C" sk-mod)"
git -C "$C" checkout -q -B sk-del "$E_BASE"; git -C "$C" rm -q "$SD"; cm "$C" "sk del"; E_DEL="$(sha "$C" sk-del)"
git -C "$C" checkout -q -B sk-ren "$E_BASE"; git -C "$C" mv "$SD" "design/teams/planner/evidence/EDITED-renamed.md"; cm "$C" "sk ren"; E_REN="$(sha "$C" sk-ren)"
git -C "$C" checkout -q -B sk-new "$E_BASE"; printf 'n\n' > "$C/design/teams/planner/evidence/NEWFILE-r741.md"; cm "$C" "sk new"; E_NEW="$(sha "$C" sk-new)"
dx --base "$E_BASE" --head "$E_MOD"
[ "$rc" = 1 ] && [[ "$out" == *"하위 폴더는 «새 파일 추가(A)» 만"* ]]; ck "ⓗ① 하위 폴더 기존 파일 «수정(M)» → 면제 0" $?
dx --base "$E_BASE" --head "$E_DEL"
[ "$rc" = 1 ] && [[ "$out" == NOT* ]] && [[ "$out" == *"$SD"* ]]; ck "ⓗ② 하위 폴더 파일 «삭제(D)» → 면제 0(${out:0:44})" $?
dx --base "$E_BASE" --head "$E_REN"
[ "$rc" = 1 ] && [[ "$out" == NOT* ]] && [[ "$out" == *"$SD"* ]]; ck "ⓗ③ 하위 폴더 «이름바꾸기» → 면제 0(${out:0:44})" $?
dx --base "$E_BASE" --head "$E_NEW"
[ "$rc" = 0 ] && [[ "$out" == "DOC-EXEMPT $E_NEW files=1 team=planner by=$SEAT" ]]; ck "ⓗ④ 하위 폴더 «새 파일 추가(A)» → 통과" $?
git -C "$C" checkout -q -B sk-dir "$E_BASE"; printf 'd\n' > "$C/design/teams/planner/HANDOFF-moded.md"; cm "$C" "sk dir mod"; E_DIRM="$(sha "$C" sk-dir)"
# 직속 «수정(M)» 은 지금처럼 통과 — 하위 폴더 규칙이 직속을 깎지 않는다(direct doc = $DOC·수정은 c-ok 가 이미 확인 · 이중 확인)
git -C "$C" checkout -q -B sk-direct "$E_BASE"; printf 'x\n' > "$C/design/teams/planner/HANDOFF-direct2.md"; cm "$C" "sk direct add"; E_DA="$(sha "$C" sk-direct)"
dx --base "$E_BASE" --head "$E_DA"
[ "$rc" = 0 ] && [[ "$out" == "DOC-EXEMPT $E_DA files=1 team=planner by=$SEAT" ]]; ck "ⓗ⑤ (대조) 직속 새 파일 → 통과(직속은 A·M 그대로)" $?
mutp 'if len(segs) > 1 and status != "A":' 'if False:'
dxm "$MUT/ft_doc_exempt.py" "$E_MOD"; [ "$rc" = 0 ]; ck "ⓗ⑥ 변이: 하위 폴더 A-only 검사 삭제 → 수정(M) 반례가 통과(FAIL 재현)" $?
unmutp
# ⓚ 격리: 실 리포·팀 폴더·명부 무변경(임시 리포·임시 명부만 썼다)
[ "$(git -C "$TOP" rev-parse HEAD)" = "$TOPSHA" ] && [ -z "$(git -C "$TOP" status --porcelain -- design/teams)" ]; ck "ⓚ 격리: 실 리포 HEAD·팀 폴더 무변경" $?

! grep -qE '^pr merge' "$STUB_LOG"; ck "ⓘ 격리: 실 PR 병합 호출 0(가짜 gh 만)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
