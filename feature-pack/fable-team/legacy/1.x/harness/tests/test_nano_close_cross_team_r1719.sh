#!/usr/bin/env bash
# test_nano_close_cross_team_r1719.sh — r1719: 팀 넘는 나노(좌석 팀 ≠ 카드 팀) 닫기 — 카드는 «카드 팀 ref» 판에서 읽고, 원장 WT 신선도는 «좌석 팀 ref» 로 잰다.
#   사건 = feature 나노가 harness 카드를 맡음 → --landed-pr 가 «원장 WT 낡음 · ff 불가(갈라짐) (ref=origin/ops/main-base)» REJECT(2/2).
# 픽스처 = 임시 bare remote 1(main 꼴 · ops 꼴 — 서로 조상 아님) + 사본 리포 + 작업 트리(좌석 팀 원장 WT · 카드 팀 WT · 나노 WT) + 가짜 명부 2 + 가짜 tmux·gh
#   · 실 명부·실 리포·외부 호출 0 · sleep 0 · 사례마다 70초 안
# 반례 ①같은 팀 = 기준판 바이트 같음 ②팀 넘음 LANDED-PR-OK(기준판 = 갈라짐 REJECT) ③카드 ref fetch 실패 = 판정 불가 ④원장 WT 3커밋 뒤 = 따라감
#   ⑤원장 WT 갈라짐 = REJECT(ref=좌석 팀 ref) ⑥원장 행 = 좌석 팀 원장만 · 카드 팀 WT·명부 바이트 같음 ⑦--suspended + 카드 팀 WT 없음 = 판정 불가 · 쓰기 0
#   ⑧INFO 1줄(②) · 0줄(①) ⑨착지 줄 없음 = 지금 문구 REJECT · 변이 M1→② M2→③ M3→④ M4→⑧(변이마다 원본 BIN 대조 · bin·kit cmp0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../harness/kit/fable-team/bin"; BINP="$HERE/../../harness/bin/ft-nano-close.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; STEPS=""; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:900}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
step() { STEPS+="$1=$((SECONDS-T0))s "; T0=$SECONDS; }
cmp0() { cmp -s "$BINP" "$KIT/ft-nano-close.sh" && ok "  └ bin·kit cmp0" || bad "bin·kit cmp 다름"; }
GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
bash "$HERE/lib/kit_bin_copy.sh" "$T/bin" >/dev/null || bad "kit_bin_copy"
mkdir -p "$T/basebin"; cp -p "$T/bin/"* "$T/basebin/"
BASE_SHA=d41191f80e4216231fd9e4535641d49962678ff4   # 기준판 = 이 카드의 팩 base(origin/main 은 착지 뒤 움직인다)
git -C "$HERE" show "$BASE_SHA:feature-pack/fable-team/legacy/1.x/harness/bin/ft-nano-close.sh" > "$T/basebin/ft-nano-close.sh" 2>/dev/null \
  || git -C "$HERE" show "origin/main:feature-pack/fable-team/legacy/1.x/harness/bin/ft-nano-close.sh" > "$T/basebin/ft-nano-close.sh"
mkdir -p "$T/fake" "$T/home" "$T/sheet" "$T/hil" "$T/comm/bodies"; echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes|ls) echo "no server running on /tmp/fake"; exit 1;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
printf '#!/usr/bin/env bash\ncat "$FAKE_GH_JSON"\n' > "$T/fake/gh"; chmod +x "$T/fake/"*

REMOTE="$T/remote.git"; R="$T/repo"; NW="$R/.worktrees/v65-k"; HW="$R/.worktrees/harness-lead"; LWT="$R/.worktrees/feature-lead"
IDX='design/harness/indices/진행/k.md'; LF="$T/ledger-feature.md"; LH="$T/ledger-harness.md"
git init -q --bare "$REMOTE"; git -C "$R" init -q -b main 2>/dev/null || { mkdir -p "$R"; git -C "$R" init -q -b main; }
printf '.fable-team/\n.worktrees/\n' > "$R/.gitignore"; GC "$R" add -A; GC "$R" commit -qm init
GC "$R" checkout -q -b ops; GC "$R" commit -q --allow-empty -m "ops 꼴"; GC "$R" checkout -q main
for i in 1 2 3; do GC "$R" commit -q --allow-empty -m "main 꼴 $i"; done
BYZ_URL='https://github.com/lptest/byz.git'   # ⑥ 리포 판정 = https 꼴 origin(실 네트워크 0 · insteadOf 로 임시 bare)
set_origin() { while read -r _k _v; do git -C "$R" config --unset-all "$_k"; done < <(git -C "$R" config --get-regexp '^url\..*\.insteadof$'); git -C "$R" config "url.$1.insteadOf" "$BYZ_URL"; }
git -C "$R" remote add origin "$BYZ_URL"; set_origin "$REMOTE"; git -C "$R" push -q origin main ops; git -C "$R" fetch -q origin
mkdir -p "$R/.fable-team/state"; printf '*\t.\torigin/main\tdesign/teams/*/indices\nharness\t.\torigin/ops\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
GC "$R" worktree add -q -b nano/k "$NW" origin/main; mkdir -p "$NW/web"; echo x > "$NW/web/a.txt"; GC "$NW" add -A; GC "$NW" commit -qm "work (착지한 세트)"
SET="$(git -C "$NW" rev-parse HEAD)"
c="$(GC "$R" commit-tree "$(git -C "$R" rev-parse 'origin/main^{tree}')" -p origin/main -m "squash 착지"$'\n\n'"PR #363 (head $SET)")"
git -C "$R" push -q origin "$c:refs/heads/main"; git -C "$R" fetch -q origin; GC "$R" merge -q --ff-only origin/main
GC "$R" worktree add -q "$HW" ops
card() {  # card <착지 줄 1|0> — 카드는 카드 팀 ref(origin/ops)에만(카드 팀 WT 커밋 → push · ROOT·좌석 원장 WT 디스크 사본 0)
  mkdir -p "$HW/design/harness/indices/진행"
  { printf '# 인덱스: k\n<!-- ledger: design/harness/GOAL-harness.md -->\n## 상태\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n' "$SET"; [ "$1" = 0 ] || echo '- 착지: PR #363 squash'; } > "$HW/$IDX"
  GC "$HW" add -A; GC "$HW" commit -qm "card $1" --allow-empty; git -C "$HW" push -q origin ops; git -C "$R" fetch -q origin; }
NL=0
reset() {  # reset <좌석> <원장 WT 꼴: tip|behind3|diverged|hw> — 명부·원장·나노 WT·원장 WT·gh·로그를 매번 새로
  SEAT="$1"; PFX="${SEAT%%k#0}"; set_origin "$REMOTE"
  printf '{"byz-feature-nano-k#0":{"role":"nano","index":"%s"}}\n' "$IDX" > "$T/seats-feature.json"
  printf '{"byz-harness-nano-k#0":{"role":"nano","index":"%s"}}\n' "$IDX" > "$T/seats-harness.json"
  case "$SEAT" in byz-feature-*) SEATS="$T/seats-feature.json"; LEDGER="$LF";; *) SEATS="$T/seats-harness.json"; LEDGER="$LH";; esac
  : > "$LF"; : > "$LH"; : > "$T/tlog"; rm -rf "$T/wtclean"; printf '%s' "$NW" > "$T/cwd"
  printf '{"state":"CLOSED","mergeCommit":null,"headRefOid":"%s"}\n' "$SET" > "$T/gh.json"
  [ -d "$NW" ] || { git -C "$R" worktree prune; git -C "$R" branch -q nano/k "$SET" 2>/dev/null; git -C "$R" worktree add -q "$NW" nano/k; }
  git -C "$NW" reset -q --hard "$SET"; git -C "$NW" clean -qfd; find "$NW" -type f -not -path '*/.git*' -exec touch -t 202001010101 {} +
  NL=$((NL+1)); rm -rf "$LWT"; git -C "$R" worktree prune; L="$LWT"
  case "$2" in tip) GC "$R" worktree add -q -b "lw$NL" "$LWT" origin/main;;
    behind3) GC "$R" worktree add -q -b "lw$NL" "$LWT" origin/main~3;;
    diverged) GC "$R" worktree add -q -b "lw$NL" "$LWT" origin/main~1; GC "$LWT" commit -q --allow-empty -m "원장 WT 만의 커밋";;
    hw) L="$HW";; esac; }
close() { local sut="$1"; shift; ( cd "$R" && env -i HOME="$T/home" FT_SHEET_ROOT="$T/sheet" HIL_DIR="$T/hil" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" \
  FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_JSON="$T/gh.json" FT_ALLOW_TRACKED_BIN=1 FT_NANO_PREFIX="$PFX" FT_SEATS_JSON="$SEATS" \
  FT_NANO_LEDGER="$LEDGER" FT_NANO_LEDGER_WT="$L" FT_NANO_FEAT=main FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
  bash "$sut" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>&1 ); }
untouched() {
  [ ! -s "$T/tlog" ] && ok "  └ kill·태그 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$SEATS" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LF" ] && [ ! -s "$LH" ] && ok "  └ 원장 행 0" || bad "$1: 원장 행 생김"
  [ "$(git -C "$R" rev-parse -q --verify nano/k)" = "$SET" ] && ok "  └ 가지 그대로" || bad "$1: 가지 바뀜"; }
XS='byz-feature-nano-k#0'; HS='byz-harness-nano-k#0'; BASE="$T/basebin/ft-nano-close.sh"; NEW="$T/bin/ft-nano-close.sh"
mutant() {  # mutant <old> <new> → $T/mutbin/ft-nano-close.sh (자리 정확 1곳)
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 -c 'import sys;p,a,b=sys.argv[1:4];s=open(p,encoding="utf-8").read();assert s.count(a)==1,a;open(p,"w",encoding="utf-8").write(s.replace(a,b,1))' "$T/mutbin/ft-nano-close.sh" "$1" "$2" || bad "변이 자리 없음: $1"; }
card 1

echo "== ① 같은 팀 나노 → 기준판과 stdout·rc 바이트 같음 (원장 WT 2꼴)"
norm() { sed -e "s#$T/basebin#$T/bin#g" -e 's/^\(STEP .*\) +[0-9][0-9]*s$/\1 +Ns/'; }   # 실행 폴더 이름·단계 초만 가린다(그 밖 바이트 대조)
for lw in tip hw; do
  reset "$HS" "$lw"; ob="$(close "$BASE" --landed-pr 363 | norm)"; rb=${PIPESTATUS[0]}; reset "$HS" "$lw"; o1="$(close "$NEW" --landed-pr 363 | norm)"; r1=${PIPESTATUS[0]}
  [ "$ob" = "$o1" ] && [ "$rb" = "$r1" ] && ok "① [$lw] 바이트 같음 rc=$r1" || bad "① [$lw] 다름 rc ${rb}→${r1} ← $(diff <(echo "$ob") <(echo "$o1") | head -6)"
  hasnt "$o1" "팀 넘는 나노" "⑧ ① [$lw] INFO 0줄"; done
step ①
echo "== ② 팀 넘는 나노 · 카드 = 카드 팀 ref 에만 · 세트·착지 줄 → LANDED-PR-OK (기준판 = 갈라짐 REJECT)"
reset "$XS" tip; hb="$(git -C "$HW" rev-parse HEAD)"; hc="$(shasum "$HW/$IDX")"; o2="$(close "$NEW" --landed-pr 363)"; r2=$?
[ "$r2" = 0 ] && ok "② rc=0" || bad "② rc=$r2 ← ${o2:0:1500}"
has "$o2" "LANDED-PR-OK #363" "② LANDED-PR-OK"; hasnt "$o2" "ff 불가(갈라짐)" "② 갈라짐 거절 0"
[ "$(printf '%s\n' "$o2" | grep -c 'INFO 팀 넘는 나노 — 카드 ref=origin/ops · 원장 ref=origin/main')" = 1 ] && ok "⑧ ② INFO 1줄" || bad "⑧ ② INFO 줄 수 ≠ 1"
echo "== ⑥ 원장 1행 = 좌석 팀 원장 파일에만 · 카드 팀 WT·카드 팀 명부 바이트 같음"
[ "$(grep -c . "$LF")" = 1 ] && ok "⑥ 좌석 팀 원장 1행" || bad "⑥ 좌석 팀 원장 행 $(grep -c . "$LF")"
[ ! -s "$LH" ] && ok "⑥ 카드 팀 원장 0행" || bad "⑥ 카드 팀 원장에 행"
[ "$(git -C "$HW" rev-parse HEAD)" = "$hb" ] && [ "$(shasum "$HW/$IDX")" = "$hc" ] && [ -z "$(git -C "$HW" status --porcelain)" ] && ok "⑥ 카드 팀 WT 바이트 같음" || bad "⑥ 카드 팀 WT 바뀜"
jq -e 'has("byz-harness-nano-k#0")' "$T/seats-harness.json" >/dev/null && ok "⑥ 카드 팀 명부 그대로" || bad "⑥ 카드 팀 명부 바뀜"
reset "$XS" tip; ob="$(close "$BASE" --landed-pr 363)"; rb=$?
[ "$rb" = 1 ] && has "$ob" "ff 불가(갈라짐)" "② 기준판 Red = 갈라짐 REJECT(이 카드가 고치는 자리)" || bad "② 기준판 Red 아님 rc=$rb ← ${ob:0:600}"
step ②⑥⑧
echo "== ③ 카드 팀 ref fetch 실패(remote 경로 없음) → 판정 불가 · 닫기 0"
reset "$XS" tip; set_origin "$T/nope.git"; o3="$(close "$NEW" --landed-pr 363)"; r3=$?
[ "$r3" -ne 0 ] && has "$o3" "판정 불가 — 팀 넘는 나노 카드 ref fetch 실패(origin/ops" "③ 판정 불가 rc=$r3" || bad "③ rc=$r3 ← ${o3:0:800}"
untouched "③"; step ③
echo "== ④ 원장 WT 가 좌석 팀 ref 보다 3커밋 뒤(ff 가능 · 미커밋 0) → 따라감 · 통과"
reset "$XS" behind3; o4="$(close "$NEW" --landed-pr 363)"; r4=$?
[ "$r4" = 0 ] && ok "④ rc=0" || bad "④ rc=$r4 ← ${o4:0:1200}"
has "$o4" "INFO 원장 WT ff" "④ 따라감 줄"; [ "$(git -C "$LWT" rev-parse HEAD)" = "$(git -C "$R" rev-parse origin/main)" ] && ok "④ 원장 WT = 좌석 팀 ref" || bad "④ 원장 WT 안 따라감"
step ④
echo "== ⑤ 원장 WT 가 좌석 팀 ref 와 갈라짐 → 지금 문구 REJECT(ref = 좌석 팀 ref)"
reset "$XS" diverged; o5="$(close "$NEW" --landed-pr 363)"; r5=$?
[ "$r5" = 1 ] && has "$o5" "ff 불가(갈라짐)" "⑤ 갈라짐 REJECT" || bad "⑤ rc=$r5 ← ${o5:0:800}"
has "$o5" "(ref=origin/main)" "⑤ ref 이름 = 좌석 팀 ref"; untouched "⑤"; step ⑤
echo "== ⑦ --suspended + 카드 팀 작업 트리 없음 → 판정 불가 1줄 · 쓰기 0"
reset "$XS" tip; o7="$(close "$NEW" --suspended "팀 정지")"; r7=$?
[ "$r7" -ne 0 ] && [ "$(printf '%s\n' "$o7" | grep -c '판정 불가')" = 1 ] && ok "⑦ 판정 불가 1줄 rc=$r7" || bad "⑦ rc=$r7 ← ${o7:0:900}"
untouched "⑦"; [ "$(git -C "$NW" rev-parse HEAD)" = "$SET" ] && ok "  └ 나노 WT HEAD 그대로([wip] 0)" || bad "⑦ 나노 WT 커밋 생김"; step ⑦
echo "== ⑨ 카드 팀 ref 판 카드에 «- 착지:» 줄 없음 → 지금 문구 REJECT"
card 0; reset "$XS" tip; o9="$(close "$NEW" --landed-pr 363)"; r9=$?
[ "$r9" = 1 ] && has "$o9" "카드에 «- 착지:» 줄이 없다" "⑨ 착지 줄 없음 REJECT" || bad "⑨ rc=$r9 ← ${o9:0:800}"
untouched "⑨"; card 1; step ⑨

echo "== 변이 (각 뒤 원본 BIN 같은 사례 = 반대 결과)"
mutant 'if [ -n "$_team" ] && [ "$_team" != "$_ct" ]; then   # r1719-mut:xteam' 'if false; then'
reset "$XS" tip; o="$(close "$T/mutbin/ft-nano-close.sh" --landed-pr 363)"; has "$o" "ff 불가(갈라짐)" "M1 팀 판정 삭제 → ② FAIL(갈라짐 REJECT)"
reset "$XS" tip; o="$(close "$NEW" --landed-pr 363)"; has "$o" "LANDED-PR-OK #363" "  └ 원본 = ② 통과"; cmp0
mutant '[ -z "${_xteam:-}" ] || { echo "판정 불가 — 팀 넘는 나노 카드 ref fetch' 'true || { echo "판정 불가 — 팀 넘는 나노 카드 ref fetch'
reset "$XS" tip; set_origin "$T/nope.git"; o="$(close "$T/mutbin/ft-nano-close.sh" --landed-pr 363)"; hasnt "$o" "판정 불가 — 팀 넘는 나노" "M2 fetch 실패 처리 삭제 → ③ FAIL(판정 불가 줄 0)"
reset "$XS" tip; set_origin "$T/nope.git"; o="$(close "$NEW" --landed-pr 363)"; has "$o" "판정 불가 — 팀 넘는 나노" "  └ 원본 = ③ 판정 불가"; cmp0
mutant '_fref="$_lref"; }   # r1719-mut:lref' '_fref="$_cref"; }'
reset "$XS" behind3; o="$(close "$T/mutbin/ft-nano-close.sh" --landed-pr 363)"; has "$o" "ff 불가(갈라짐)" "M3 원장 ref = 카드 ref → ④ FAIL(갈라짐 REJECT)"
reset "$XS" behind3; o="$(close "$NEW" --landed-pr 363)"; has "$o" "INFO 원장 WT ff" "  └ 원본 = ④ 따라감"; cmp0
mutant '[ -z "$_xteam" ] || echo "INFO 팀 넘는 나노' 'echo "INFO 팀 넘는 나노'
reset "$HS" tip; o="$(close "$T/mutbin/ft-nano-close.sh" --landed-pr 363)"; has "$o" "INFO 팀 넘는 나노" "M4 INFO 조건 삭제 → ⑧ FAIL(① 에 INFO 줄)"
reset "$HS" tip; o="$(close "$NEW" --landed-pr 363)"; hasnt "$o" "INFO 팀 넘는 나노" "  └ 원본 = ① INFO 0줄"; cmp0
step 변이
echo "SUMMARY 단계별 초: $STEPS"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
