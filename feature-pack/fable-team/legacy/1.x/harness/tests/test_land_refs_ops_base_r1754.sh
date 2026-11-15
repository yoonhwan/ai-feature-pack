#!/usr/bin/env bash
# test_land_refs_ops_base_r1754.sh — r1754: 착지 ref 후보 규칙 1개(ft-card-target-lib.sh ft_land_refs)를 닫기 차례(close-due)·나노 닫기(nano-close)·증거 검사(evidence-check)가 같이 쓴다
#   + close-due 가 끝줄 꼬리 «main 자동 병합(…) C=<HEAD>» 꼴(착지 도구가 나노 가지에 main 을 병합한 HEAD)을 squash 로 본다.
#   반례 ①~⑧(카드 «반례 집합» 그대로) · 기준판(BASE_SHA = 이 카드의 팩 base) ③④⑥⑦ Red · 변이 M1~M3 = bin 사본에서 한 곳만 + 원본 대조(반대 결과)
#   임시 리포(bare origin)·가짜 tmux·ft-seat-status·gh 만 쓴다 — 실 명부·실 리포·실 좌석 0 · sleep 0 · 70초 안 · ⑥ 은 r1737 공용 픽스처(하위 셸)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_LAND_REF
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
BASE_SHA=ca6c3f2a   # 기준판 = 이 카드 나노의 팩 base(고치기 전 · origin/main 은 착지 뒤 움직인다)
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$(date +%s); TL=$T0; STEPS=""
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got=[${1:0:400}] want=[${2:0:400}])"; }
lap() { local n; n=$(date +%s); STEPS="$STEPS $1=$((n-TL))s"; TL=$n; }
F4="ft-card-target-lib.sh ft-nano-close-due.sh ft-nano-close.sh ft-nano-evidence-check.sh"

echo "== 짝 cmp · bash -n"
for f in $F4; do cmp -s "$BIN/$f" "$KIT/$f" && ok "cmp bin == kit $f" || bad "cmp 다름 $f"; /bin/bash -n "$BIN/$f" && ok "/bin/bash 3.2 -n $f" || bad "bash -n $f"; done

# ── 판(bin 폴더) 만들기 — NEW = 지금 bin · BASE = 기준판 4파일 · M* = 사본에서 한 곳만 ──
variant() { local d="$T/v-$1"; rm -rf "$d"; cp -R "$BIN" "$d"; echo "$d"; }
mutate() {  # mutate <판> <파일> <옛 글자> <새 글자> — 정확 1곳
  python3 - "$1/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:60]}"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
NEW="$BIN"; BASEB="$(variant base)"; HAVE_BASE=1
for f in $F4; do git -C "$HERE" show "$BASE_SHA:feature-pack/fable-team/legacy/1.x/harness/bin/$f" > "$BASEB/$f" 2>/dev/null || HAVE_BASE=0; done
M1="$(variant M1)"; mutate "$M1" ft-card-target-lib.sh '&& echo origin/ops/main-base   # r1754-mut:ops' '&& true   # r1754-mut:ops'
M2="$(variant M2)"; mutate "$M2" ft-nano-close-due.sh 'if fp.strip() == mx.group(2): return' 'if True: return'
M3="$(variant M3)"; mutate "$M3" ft-card-target-lib.sh '[ "$rc" -eq 0 ] || { echo "판정 불가 착지 ref' 'true || { echo "판정 불가 착지 ref'

# ── 공용 리포 설비 ──
mkr() { git init -q --bare -b main "$1.git"; git init -q -b main "$1"; git -C "$1" remote add origin "$1.git"
  echo a > "$1/a"; git -C "$1" add a; git -C "$1" commit -qm M0; git -C "$1" push -q origin main 2>/dev/null; git -C "$1" fetch -q origin; }
wk() { printf '%s\n' "$3" > "$R/$1"; git -C "$R" add "$1"; git -C "$R" commit -qm "$2"; git -C "$R" rev-parse HEAD; }   # wk <파일> <메시지> <내용>
onto() {  # onto <원격 가지> <트리 커밋> <메시지> — 그 가지 위에 커밋 1개(그 트리) · push 뒤 로컬 remote-tracking 은 지운다(도구가 fetch 해야 보인다)
  local c; c="$(printf '%s\n' "$3" | git -C "$R" commit-tree "$(git -C "$R" rev-parse "$2^{tree}")" -p "$(git -C "$R" rev-parse "refs/remotes/origin/$1")")"
  git -C "$R" push -q --force origin "$c:refs/heads/$1" 2>/dev/null; echo "$c"; }
adv() { local base blob tree c; base="$(git -C "$R" rev-parse "refs/remotes/origin/$1")"   # adv <원격 가지> <파일> — 다른 커밋 1개
  blob="$(printf '%s\n' "$2" | git -C "$R" hash-object -w --stdin)"
  GIT_INDEX_FILE="$T/idx" git -C "$R" read-tree "$base"; GIT_INDEX_FILE="$T/idx" git -C "$R" update-index --add --cacheinfo "100644,$blob,$2"
  tree="$(GIT_INDEX_FILE="$T/idx" git -C "$R" write-tree)"; rm -f "$T/idx"; c="$(git -C "$R" commit-tree "$tree" -p "$base" -m "$1 $2")"
  git -C "$R" push -q --force origin "$c:refs/heads/$1" 2>/dev/null; git -C "$R" fetch -q origin; }

# ── close-due 설비(r1713 꼴): pane 리포 W · 데이터 루트 ROOT(카드·명부) · 가짜 tmux·seat-status ──
FK="$T/fake"; mkdir -p "$FK"
printf '#!/usr/bin/env bash\ncase "$1" in list-sessions) echo "$FAKE_SEAT";; display-message) cat "$FAKE_CWD";; *) exit 9;; esac\n' > "$FK/tmux"
printf '#!/usr/bin/env bash\n[ "${1:-}" = turn ] && { echo "IDLE - - - jsonl"; exit 0; }\nexit 1\n' > "$FK/ss.sh"
chmod +x "$FK/tmux" "$FK/ss.sh"
SEAT="byz-harness-nano-lr#0"; export FAKE_SEAT="$SEAT"
base_case() { C="$T/$1"; rm -rf "$C"; mkdir -p "$C"; W="$C/w"; R="$W"; mkr "$W"; ROOT="$C/root"
  mkdir -p "$ROOT/design/teams/harness/indices/진행" "$ROOT/.fable-team/state"; printf '%s\n' "$W" > "$C/cwd"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | byz-harness-master-pi | 현역 |\n' > "$ROOT/design/TEAMS.md"
  printf '{"_master":"byz-harness-master-pi#1","%s":{"role":"nano","agent":"pi","cwd":"/nonexistent","index":"design/teams/harness/indices/진행/lr.md"}}\n' "$SEAT" > "$ROOT/.fable-team/seats-harness.json"
  git -C "$W" checkout -q -b nano/x; }
card() { printf '# 인덱스: lr\n## 상태\n- 세트: %s · 시험: bash x rc=0 · 이슈: 0\n' "$1" > "$ROOT/design/teams/harness/indices/진행/lr.md"; }
due() { OUT="$(cd "$ROOT" && PATH="$FK:$PATH" FT_ROOT="$ROOT" FT_PACK_REPO="$C/nopack" FT_CLOSE_DUE_SEAT_STATUS="$FK/ss.sh" FAKE_CWD="$C/cwd" \
  FT_CLOSE_DUE_CURSOR="$C/cursor" bash "$1/ft-nano-close-due.sh" --all --why 2>&1)"; RC=$?; }
in_() { case "$OUT" in *"$1"*) return 0;; esac; WHY="없음 «$1» ← ${OUT:0:500}"; return 1; }
NONE="제외 $SEAT main 에 산출 없음(ff 0 · squash 끝줄 0)"
mk3() { base_case c3; git -C "$W" push -q origin main:refs/heads/ops/main-base 2>/dev/null; git -C "$W" fetch -q origin; adv ops/main-base o1.txt
  S="$(wk s.txt "work s" s1)"; onto ops/main-base "$S" "$(printf 'squash 착지\n\nPR #7 (head %s)' "$S")" >/dev/null
  git -C "$W" update-ref -d refs/remotes/origin/ops/main-base; card "$S"; }
mk45() {  # mk45 <c4|c5> — HEAD = C(S 와 main 병합) · main 끝줄 «PR #7 (head S)» + 꼬리 «… C=<C>» · c5 = C 의 첫 부모가 main(≠ S)
  base_case "$1"; S="$(wk s.txt "work s" s1)"; adv main g1.txt
  if [ "$1" = c4 ]; then git -C "$W" merge -q --no-ff -m "merge main" refs/remotes/origin/main
  else git -C "$W" checkout -q --detach refs/remotes/origin/main; git -C "$W" merge -q --no-ff -m "merge S" "$S"; git -C "$W" checkout -q -B nano/x; fi
  CC="$(git -C "$W" rev-parse HEAD)"
  onto main "$CC" "$(printf 'squash 착지\n\nPR #7 (head %s)\nmain 자동 병합(코드 · 승인 EQUIV) C=%s' "$S" "$CC")" >/dev/null; card "$CC"; }
mk8m() { base_case c8m; S="$(wk s.txt "work s" s1)"; onto main "$S" "$(printf 'squash 착지\n\nPR #7 (head %s)' "$S")" >/dev/null; card "$S"; }   # main 정확 착지(팩 꼴 · ops 가지 0)

c1() { local o r; base_case c1; git -C "$W" push -q origin main:refs/heads/ops/main-base 2>/dev/null
  o="$(. "$1/ft-card-target-lib.sh" && ft_land_refs "$W")"; r=$?; [ "$r/$o" = "0/origin/main"$'\n'"origin/ops/main-base" ] || { WHY="ops 있음 rc=$r «$o»"; return 1; }
  git -C "$W" push -q origin --delete ops/main-base 2>/dev/null
  o="$(. "$1/ft-card-target-lib.sh" && ft_land_refs "$W")"; r=$?; [ "$r/$o" = "0/origin/main" ] || { WHY="팩 꼴 rc=$r «$o»"; return 1; }; }
c2() { local o r; base_case c2; git -C "$W" remote set-url origin "$C/없는리포.git"
  o="$(. "$1/ft-card-target-lib.sh" && ft_land_refs "$W")"; r=$?
  [ "$r" -ne 0 ] && [ "$(printf '%s\n' "$o" | grep -c .)" = 1 ] && case "$o" in "판정 불가 착지 ref — git ls-remote origin rc=128"*) true;; *) false;; esac || { WHY="rc=$r «$o»"; return 1; }; }
c3() { mk3; due "$1"; in_ "닫기 차례 $SEAT 팀=harness 가지=nano/x landed=squash ref=origin/ops/main-base main=" \
  && in_ " — FT_LAND_REF=origin/ops/main-base bash ft-nano-close.sh $SEAT --landed-pr 7 " && [ "$RC" = 0 ]; }
c4() { mk45 c4; due "$1"; in_ "닫기 차례 $SEAT 팀=harness 가지=nano/x landed=squash ref=origin/main main=" && in_ " — bash ft-nano-close.sh $SEAT --landed-pr 7 " && [ "$RC" = 0 ]; }
c5() { mk45 c5; due "$1"; in_ "$NONE" && ! in_ "닫기 차례 $SEAT" && [ "$RC" = 0 ]; }

# ── ⑦ evidence-check: origin main · ops/main-base(갈라짐) · 세트 S(ops 위) · HEAD = S 에 ops/main-base 병합 ──
mk7() { C="$T/c7"; rm -rf "$C"; mkdir -p "$C"; W="$C/w"; R="$W"; mkr "$W"; git -C "$W" push -q origin main:refs/heads/ops/main-base 2>/dev/null; git -C "$W" fetch -q origin
  adv ops/main-base o1.txt; git -C "$W" checkout -q -b nano/x refs/remotes/origin/ops/main-base; S="$(wk s.txt "work s" s1)"
  adv ops/main-base o2.txt; adv main m1.txt; git -C "$W" merge -q --no-ff -m "merge ops/main-base" refs/remotes/origin/ops/main-base
  printf '# 인덱스: ev\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$S" > "$C/card.md"; }
ev() { OUT="$(bash "$1/ft-nano-evidence-check.sh" "$C/card.md" --repo "$W" 2>&1)"; RC=$?; }
c7() { mk7; ev "$1"; [ "$RC" = 0 ] || { WHY="rc=$RC ← ${OUT:0:300}"; return 1; }; in_ "OK 증거 줄" && in_ "target=ops/main-base"; }

# ── ⑥ nano-close(r1737 공용 픽스처 · 하위 셸): env 없음 · PR head 가 ops/main-base 에만 → 착지 확인 ref=origin/ops/main-base ──
c6() { WHY="$( B="$1" bash -c '
  . "$0/_landed_ref_wt_r1737_fixture.sh" >/dev/null 2>&1 || { echo "픽스처 실패"; exit 1; }
  cp "$B/ft-nano-close.sh" "$B/ft-card-target-lib.sh" "$T/bin/"
  setup; push_ref "$SET" ops/main-base; git -C "$ROOT" fetch -q origin
  out="$(close --landed-pr 363)"; rc=$?
  case "$out" in *"ref=origin/ops/main-base"*) [ "$rc" -eq 0 ] && exit 0;; esac
  echo "rc=$rc ← $(printf "%s" "$out" | grep -E "착지|REJECT|main 에" | head -3 | cut -c1-300)"; exit 1' "$HERE" 2>&1)"; }

# ── ⑧ env FT_LAND_REF=origin/main · 팩 꼴 → 기준판과 같은 출력·rc ──
c8() { local a b ar br
  base_case c8; git -C "$W" remote set-url origin "$C/없는리포.git"; o="$(FT_LAND_REF=origin/main bash -c '. "$1/ft-card-target-lib.sh"; ft_land_refs "$2"' _ "$1" "$W" 2>&1)"   # env = 그 하나(ls-remote 0 · 원격이 없어도 성공)
  [ "$o" = origin/main ] || { WHY="ft_land_refs env «$o»"; return 1; }
  mk3; FT_LAND_REF=origin/main due "$1"; a="$OUT"; ar=$RC; FT_LAND_REF=origin/main due "$BASEB"; [ "$a/$ar" = "$OUT/$RC" ] || { WHY="due env main ③ 다름 «$a» vs «$OUT»"; return 1; }
  case "$a" in *"$NONE"*) ;; *) WHY="due env main ③ 제외 아님 «$a»"; return 1;; esac
  mk8m; due "$1"; a="$(printf '%s' "$OUT" | sed 's/ ref=origin\/main / /')"; ar=$RC; due "$BASEB"; [ "$a/$ar" = "$OUT/$RC" ] || { WHY="due main 착지 다름(ref= 칸 빼고) «$a» vs «$OUT»"; return 1; }
  mk7; FT_LAND_REF=origin/main ev "$1"; a="$OUT"; ar=$RC; FT_LAND_REF=origin/main ev "$BASEB"; [ "$a/$ar" = "$OUT/$RC" ] && [ "$ar" = 1 ] || { WHY="evidence env main 다름 «$a»/$ar vs «$OUT»/$RC"; return 1; }; }
lap 준비

pass() { WHY=""; if "$2" "$3"; then ok "$1"; else bad "$1 — $WHY"; fi; }
red()  { WHY=""; if "$2" "$3"; then bad "$1 — 통과해 버림(Red 아님)"; else ok "$1 Red($(printf '%s' "$WHY" | head -1))"; fi; }
echo "== ① ft_land_refs: ops 있음 → 2줄 · 팩 꼴 → 1줄";            pass ① c1 "$NEW"
echo "== ② ls-remote rc128 → «판정 불가 착지 ref» 1줄 rc≠0";       pass ② c2 "$NEW"
echo "== ③ due: ops/main-base squash 끝줄 정확 · main 0 → 닫기 차례 ref=origin/ops/main-base + FT_LAND_REF= 명령"; pass ③ c3 "$NEW"
echo "== ④ due: HEAD = C(첫 부모 S) · main 끝줄 PR + C 꼬리 → landed=squash pr=7"; pass ④ c4 "$NEW"
echo "== ⑤ due: ④ 꼴인데 C 의 첫 부모 ≠ S → 제외 그대로";          pass ⑤ c5 "$NEW"
lap ①~⑤
echo "== ⑥ nano-close --landed-pr · env 없음 · 착지 = ops/main-base → ref=origin/ops/main-base"; pass ⑥ c6 "$NEW"
echo "== ⑦ evidence-check: 세트 S · HEAD = S + ops/main-base 병합 → EQUIV target=ops/main-base"; pass ⑦ c7 "$NEW"
echo "== ⑧ env FT_LAND_REF=origin/main · 팩 꼴 → 기준판과 같은 출력·rc";  pass ⑧ c8 "$NEW"
lap ⑥~⑧

echo "== 기준판($BASE_SHA) ③④⑥⑦ Red"
if [ "$HAVE_BASE" = 1 ]; then red "기준판 ③" c3 "$BASEB"; red "기준판 ④" c4 "$BASEB"; red "기준판 ⑥" c6 "$BASEB"; red "기준판 ⑦" c7 "$BASEB"
else echo "SKIP 기준판 — $BASE_SHA 객체 없음(얕은 사본)"; fi
lap 기준판

echo "== 변이 — 사본에서 한 곳만 · 각 뒤 원본으로 같은 사례 1회(반대 결과)"
for c in c3 c6 c7; do red "M1(ops 후보 지움) $c" "$c" "$M1"; pass "M1 원본 대조 $c" "$c" "$NEW"; done
red "M2(C 첫 부모 검사 지움) c5" c5 "$M2"; pass "M2 원본 대조 c5" c5 "$NEW"
red "M3(ls-remote rc 검사 지움) c2" c2 "$M3"; pass "M3 원본 대조 c2" c2 "$NEW"
for f in $F4; do cmp -s "$BIN/$f" "$KIT/$f" || bad "변이 뒤 cmp 다름 $f"; done; ok "변이 뒤 bin·kit cmp0(4파일)"
lap 변이

echo "단계별 초: 전체=$(( $(date +%s) - T0 ))s ·$STEPS"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
