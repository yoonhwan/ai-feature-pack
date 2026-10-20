#!/usr/bin/env bash
# test_root_bin_shim.sh — R201: 루트 .fable-team/bin 옛 사본 → 라이브 bin 연결 파일 (ft-root-bin-shim.sh) · 축 ⓐ~ⓔ + 변이.
# mktemp 만 쓴다(임시 «루트» 리포 + 임시 «라이브 bin»(자기 $HERE·인자를 찍는 가짜 도구)) — 진짜 루트 .fable-team/bin 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SH="$HERE/../../harness/bin/ft-root-bin-shim.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }

bash -n "$SH" && ok "bash -n" || bad "bash -n"

KP="scripts/harness-install/fable-team/bin"
build() {  # $1 = 작업 폴더 → 루트 리포($1/root) + 라이브($1/live)
  local W="$1"; rm -rf "$W"; mkdir -p "$W/root/$KP" "$W/root/.fable-team/bin" "$W/live"
  git init -q -b main "$W/root"
  printf 'x\n' > "$W/root/$KP/ft-a.sh"; printf 'y\n' > "$W/root/$KP/ft-b.py"; printf 'z\n' > "$W/root/$KP/data.txt"
  git -C "$W/root" add -A && git -C "$W/root" -c user.email=t@t -c user.name=t commit -q -m kit
  # 라이브 bin = 자기 $HERE·인자·stdin 을 찍는 가짜 도구
  printf '#!/usr/bin/env bash\nHERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"\necho "LIVE-A HERE=$HERE args=$*"; cat; exit 7\n' > "$W/live/ft-a.sh"
  printf 'import sys,os\nprint("LIVE-B", os.path.dirname(os.path.abspath(__file__)), sys.argv[1:])\n' > "$W/live/ft-b.py"
  printf 'data\n' > "$W/live/data.txt"
  # 루트 옛 사본: 키트 이름 옛 사본 + 키트 밖 이름 + .bak + __pycache__
  printf '#!/usr/bin/env bash\necho OLD-A\n' > "$W/root/.fable-team/bin/ft-a.sh"; chmod 755 "$W/root/.fable-team/bin/ft-a.sh"
  printf 'echo weird\n' > "$W/root/.fable-team/bin/weird.sh"
  printf 'bak\n' > "$W/root/.fable-team/bin/ft-a.sh.bak-1"
  mkdir -p "$W/root/.fable-team/bin/__pycache__"; printf 'c\n' > "$W/root/.fable-team/bin/__pycache__/x.pyc"
}
RUN() { bash "$SH" --root "$W/root" --live "$W/live" --ref HEAD --repo "$W/root" --path "$KP" "$@"; }   # r385 뒤 키트 기본 = 팩 리포 → 픽스처 키트를 명시

W="$T/w1"; build "$W"; RB="$W/root/.fable-team/bin"
before_a="$(cksum < "$RB/ft-a.sh")"

# ⓔ dry-run = 쓰기 0
out="$(RUN --dry-run 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓔ dry-run"; has "$out" "SHIM 2 · MOVED 4 · UNKNOWN 1" "ⓔ dry-run 숫자(SHIM 2 · MOVED 4 · UNKNOWN 1)"
[ "$(cksum < "$RB/ft-a.sh")" = "$before_a" ] && [ ! -e "$W/root/.fable-team/LIVE_BIN" ] && ! ls "$W/root/.fable-team" | grep -q stale && ok "ⓔ dry-run 쓰기 0(옛 사본 그대로 · LIVE_BIN 없음 · stale 폴더 없음)" || bad "ⓔ dry-run 이 썼다"

# 실제 실행
out="$(RUN 2>&1)"; rc=$?
rc_is "$rc" 0 "실행"; has "$out" "SHIM 2 · MOVED 4 · UNKNOWN 1" "숫자 일치(dry-run 과 같음)"
has "$out" "UNKNOWN weird.sh" "ⓒ 키트 밖 이름 목록 보고"
ST="$(ls -d "$W/root/.fable-team"/bin.stale-* 2>/dev/null | head -1)"
[ -n "$ST" ] && ok "stale 폴더 생성" || bad "stale 폴더 없음"
[ -f "$ST/weird.sh" ] && [ -f "$ST/ft-a.sh.bak-1" ] && [ -f "$ST/__pycache__/x.pyc" ] && [ -f "$ST/ft-a.sh" ] && ok "ⓒ·ⓓ 키트 밖·.bak·__pycache__·옛 사본 전부 stale 로 옮김" || bad "stale 내용 부족"
[ "$(cksum < "$ST/ft-a.sh")" = "$before_a" ] && ok "ⓓ 옛 사본 바이트 그대로" || bad "ⓓ 옛 사본 바이트 변함"
[ ! -e "$RB/weird.sh" ] && [ ! -e "$RB/ft-a.sh.bak-1" ] && [ ! -e "$RB/__pycache__" ] && ok "ⓒ 루트 bin 에 키트 밖·bak·pycache 연결 0(없음)" || bad "ⓒ 루트 bin 에 남음"
[ ! -e "$RB/data.txt" ] && ok "ⓒ *.sh·*.py 가 아닌 키트 이름(data.txt)은 연결 0" || bad "ⓒ data.txt 연결됨"
[ "$(cat "$W/root/.fable-team/LIVE_BIN")" = "$W/live" ] && ok "LIVE_BIN 1줄" || bad "LIVE_BIN 값"

# ⓐ 연결 파일로 부르면 $HERE = 라이브 · 인자·stdin·rc 그대로
out="$(printf 'IN\n' | bash "$RB/ft-a.sh" one "two words" 2>&1)"; rc=$?
has "$out" "LIVE-A HERE=$W/live args=one two words" "ⓐ \$HERE=라이브 bin · 인자 그대로"
has "$out" "IN" "ⓐ stdin 그대로"; rc_is "$rc" 7 "ⓐ rc 그대로"; hasnt "$out" "OLD-A" "ⓐ 옛 사본 실행 0"
out="$(bash "$RB/ft-b.py" 1 2 2>&1)"; has "$out" "LIVE-B $W/live ['1', '2']" "ⓐ .py 연결(python3)"

# ⓓ 멱등
snap1="$(cd "$RB" && cksum * | sort)"; nst1="$(ls -d "$W/root/.fable-team"/bin.stale-* | wc -l | tr -d ' ')"
out="$(RUN 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓓ 두 번째 실행"; has "$out" "SHIM 2 · MOVED 0 · UNKNOWN 0" "ⓓ 두 번째 = MOVED 0"
snap2="$(cd "$RB" && cksum * | sort)"; nst2="$(ls -d "$W/root/.fable-team"/bin.stale-* | wc -l | tr -d ' ')"
[ "$snap1" = "$snap2" ] && [ "$nst1" = "$nst2" ] && ok "ⓓ 멱등(바이트·stale 폴더 수 불변)" || bad "ⓓ 멱등 아님"

# ⓑ LIVE_BIN 없음·빈 값·대상 파일 없음 → ERROR rc≠0 (옛 사본 실행 0 — 옛 사본은 이미 stale 로 갔고 OLD 가 나오면 안 된다)
mv "$W/root/.fable-team/LIVE_BIN" "$T/lb.bak"
out="$(bash "$RB/ft-a.sh" 2>&1)"; rc=$?; [ "$rc" != 0 ] && has "$out" "ERROR" "ⓑ LIVE_BIN 없음 → ERROR rc≠0 (rc=$rc)" || bad "ⓑ LIVE_BIN 없음인데 rc=0"
: > "$W/root/.fable-team/LIVE_BIN"
out="$(bash "$RB/ft-a.sh" 2>&1)"; rc=$?; [ "$rc" != 0 ] && has "$out" "ERROR" "ⓑ LIVE_BIN 빈 값 → ERROR rc≠0" || bad "ⓑ 빈 값인데 rc=0"
printf '%s\n' "$W/live" > "$W/root/.fable-team/LIVE_BIN"; mv "$W/live/ft-a.sh" "$T/a.bak"
out="$(bash "$RB/ft-a.sh" 2>&1)"; rc=$?; [ "$rc" != 0 ] && has "$out" "ERROR" "ⓑ 대상 파일 없음 → ERROR rc≠0" || bad "ⓑ 대상 없음인데 rc=0"
hasnt "$out" "OLD-A" "ⓑ 옛 사본 실행 0"; mv "$T/a.bak" "$W/live/ft-a.sh"

# H1(r3 · DA r1): 상대 경로 LIVE_BIN → ERROR rc≠0 · 라이브 도구 실행 0 (cwd=$W 에서 "live" 는 실재하는 폴더라 검사가 없으면 LIVE-A 가 돈다)
printf 'live\n' > "$W/root/.fable-team/LIVE_BIN"
out="$(cd "$W" && bash "$RB/ft-a.sh" 2>&1)"; rc=$?
[ "$rc" != 0 ] && has "$out" "ERROR" "H1 연결 파일: 상대 LIVE_BIN → ERROR rc≠0(rc=$rc)" || bad "H1 상대 LIVE_BIN 인데 rc=0"
hasnt "$out" "LIVE-A" "H1 연결 파일: 상대 LIVE_BIN → 라이브 도구 실행 0"
printf '%s\n' "$W/live" > "$W/root/.fable-team/LIVE_BIN"
# H1(r3): 생성 도구 --live 가 상대 경로 → ERROR rc3 · 쓰기 0(LIVE_BIN 불변)
lb_before="$(cksum < "$W/root/.fable-team/LIVE_BIN")"
out="$(cd "$W" && bash "$SH" --root "$W/root" --live live --ref HEAD --repo "$W/root" --path "$KP" 2>&1)"; rc=$?
rc_is "$rc" 3 "H1 생성 도구: 상대 --live → rc3"; has "$out" "ERROR" "H1 생성 도구: ERROR 줄"
[ "$(cksum < "$W/root/.fable-team/LIVE_BIN")" = "$lb_before" ] && ok "H1 생성 도구: 거절 시 LIVE_BIN 불변" || bad "H1 생성 도구가 상대 --live 로 LIVE_BIN 을 바꿨다"

# 변이: 연결 파일의 «대상 없음 검사» 를 지운 도구 → ⓑ 가 FAIL 해야 한다(시험이 이빨이 있는지)
MUT="$T/shim-mut.sh"; grep -v '라이브 도구 없음' "$SH" > "$MUT"
[ "$(grep -c '라이브 도구 없음' "$MUT" || true)" = 0 ] && ok "변이 파일 생성(대상 없음 검사 제거)" || bad "변이 생성 실패"
W2="$T/w2"; build "$W2"; bash "$MUT" --root "$W2/root" --live "$W2/live" --ref HEAD --repo "$W2/root" --path "$KP" >/dev/null 2>&1
mv "$W2/live/ft-a.sh" "$T/a2.bak"; out="$(bash "$W2/root/.fable-team/bin/ft-a.sh" 2>&1)"; rc=$?
{ [ "$rc" = 0 ] || ! grep -q 'ERROR' <<<"$out"; } && ok "변이 시 ⓑ 단언이 깨진다(대상 없음인데 ERROR 가 사라짐 — 시험이 변이를 잡는다)" || bad "변이인데도 ⓑ 가 통과 — 시험이 이빨이 없다"

# ── r484: 뉴스 틱 ⑥ 은 $HERE(LIVE_BIN) 의 진짜 .py 를 부른다 · shim 은 exec 만(인터프리터에 넘기지 않는다) ──
KB="$HERE/../../harness/kit/fable-team/bin"; LINT="$KB/ft-shim-exec-lint.sh"
R="$T/r484"; L="$R/live"; V="$R/.worktrees/v6-realtime-live"; mkdir -p "$L" "$V/$KP" "$V/.fable-team/bin"
cp -p "$KB/ft-news-tree.py" "$KB/ft-harness-root.sh" "$KB/ft-team-lib.sh" "$LINT" "$L/"
# ⑥ 절만 도는 사본(머리 ~ WT= 줄 + ⑥ 절) — ①~⑤ 의 tmux·docker·mbox 호출 0
awk '1; /^WT=/{exit}' "$KB/ft-news-tick.sh" > "$L/ft-news-tick-s6.sh"
awk '/════ ⑥/{p=1} p' "$KB/ft-news-tick.sh" >> "$L/ft-news-tick-s6.sh"
grep -q 'ft-news-tree.py' "$L/ft-news-tick-s6.sh" && ok "r484 ⑥ 절 사본 생성" || bad "r484 ⑥ 절 사본에 트리 호출 없음"
mkdir -p "$R/.fable-team"; printf '%s\n' "$L" > "$R/.fable-team/LIVE_BIN"
# 옛 라이브 워크트리 자리 = 생성기가 만든 진짜 bash shim
git init -q -b main "$V"; cp -p "$KB/ft-news-tree.py" "$V/$KP/"
git -C "$V" add -A && git -C "$V" -c user.email=t@t -c user.name=t commit -q -m kit
bash "$SH" --root "$V" --live "$L" --ref HEAD --repo "$V" --path "$KP" >/dev/null 2>&1
head -1 "$V/.fable-team/bin/ft-news-tree.py" | grep -q bash && ok "r484 픽스처: 워크트리 ft-news-tree.py = bash shim" || bad "r484 픽스처: shim 아님"
git init -q -b main "$R"; printf '{}\n' > "$R/.fable-team/seats.json"   # ft-news-tree.py 는 트리 파일 리포의 공용 .fable-team/seats.json 을 읽는다
MD="$R/NEWS-TREE.md"; printf '[✅] 알파 끝\n[🔄] 베타 하는 중\n[⏳] 감마 대기\n' > "$MD"
# ⓐ 고친 ⑥ 절 → 트리 줄 ≥1 · SyntaxError 0
out="$(cd "$R" && FT_NEWS_ROOT="$R" FT_NEWS_TREE="$MD" FT_ME=t bash "$L/ft-news-tick-s6.sh" 2>"$R/err")"; err="$(cat "$R/err")"
has "$out" "베타 하는 중" "r484 ⓐ ⑥ 절 아래 트리 줄 ≥1"; hasnt "$err$out" "SyntaxError" "r484 ⓐ stderr SyntaxError 0"
# 대조: 옛 호출 꼴(python3 "$WT/…/ft-news-tree.py") 은 같은 픽스처에서 SyntaxError — 버그 재현(시험 이빨)
out="$(python3 "$V/.fable-team/bin/ft-news-tree.py" "$MD" 2>&1)"; has "$out" "SyntaxError" "r484 대조: 옛 호출 꼴 = SyntaxError 재현"
# ⓑ 옛 줄을 넣은 사본 → 린트 REJECT rc1
LB="$R/lintbad"; mkdir -p "$LB"; cp -p "$KB/ft-news-tick.sh" "$LB/"
sed -i.bak '56s#python3 "\$HERE/ft-news-tree.py"#python3 "$WT/.fable-team/bin/ft-news-tree.py"#' "$LB/ft-news-tick.sh"; rm -f "$LB/ft-news-tick.sh.bak"
out="$(bash "$LINT" "$LB" 2>&1)"; rc=$?
rc_is "$rc" 1 "r484 ⓑ 옛 줄 → 린트 rc1"; has "$out" 'REJECT ft-news-tick.sh:56 인터프리터가 shim 을 읽는다 — $HERE/ft-news-tree.py 로' "r484 ⓑ REJECT 파일:줄 원문"
# ⓒ 키트 bin 전수 = OK 0건
out="$(bash "$LINT" "$KB" 2>&1)"; rc=$?; rc_is "$rc" 0 "r484 ⓒ 키트 bin 전수 린트"; has "$out" "OK 0건" "r484 ⓒ OK 0건"
# ⓓ shim 직접 실행은 그대로(생성기 변경 0)
out="$(bash "$V/.fable-team/bin/ft-news-tree.py" "$MD" 2>&1)"; has "$out" "베타 하는 중" "r484 ⓓ bash <shim> 직접 실행 = 트리 줄"; hasnt "$out" "SyntaxError" "r484 ⓓ SyntaxError 0"

# ── r494: 새 워크트리(bin 0) = shim --init 으로 bin 생성 · install.sh 워크트리 경유 · 훅 deny 설치 1줄 · nano-spawn NOTE/SHIM ──
R4="$T/r494"; RP="$R4/repo"; LV="$R4/live"; mkdir -p "$RP/$KP" "$LV" "$R4/plain"
git init -q -b main "$RP"; printf 'g\n' > "$RP/$KP/ft-press-gate.sh"; printf 'a\n' > "$RP/$KP/ft-a.sh"
git -C "$RP" add -A && git -C "$RP" -c user.email=t@t -c user.name=t commit -q -m kit
printf '#!/usr/bin/env bash\necho "LIVE-GATE $*"\n' > "$LV/ft-press-gate.sh"; printf 'echo A\n' > "$LV/ft-a.sh"
mkdir -p "$RP/.fable-team/bin"; printf '%s\n' "$LV" > "$RP/.fable-team/LIVE_BIN"; printf '/old/v6-realtime-live\n' > "$RP/.fable-team/LIVE_ROOT"   # 공용 루트 LIVE_ROOT = 다른 값(복사 0 확인)
for w in w1 w2 w3 w4; do git -C "$RP" worktree add -q -b "$w" "$RP/.worktrees/$w" main; done
R4RUN() { local r="$1"; shift; bash "$SH" --root "$r" --live "$LV" --ref HEAD --repo "$RP" --path "$KP" "$@"; }
W1="$RP/.worktrees/w1"
# ⓐ --init → bin 생성 + 연결 파일 + LIVE_BIN + LIVE_ROOT(= 공용 루트 경로) · 두 번째 = 쓰기 0
out="$(R4RUN "$W1" --init 2>&1)"; rc=$?
rc_is "$rc" 0 "r494 ⓐ --init"; has "$out" "INIT $W1/.fable-team/bin" "r494 ⓐ INIT 줄"; has "$out" "SHIM 2 · MOVED 0 · UNKNOWN 0" "r494 ⓐ SHIM 2 · MOVED 0 · UNKNOWN 0"
[ -x "$W1/.fable-team/bin/ft-press-gate.sh" ] && ok "r494 ⓐ ft-press-gate.sh 연결 파일 실행 가능" || bad "r494 ⓐ 연결 파일 없음"
[ "$(cat "$W1/.fable-team/LIVE_BIN")" = "$LV" ] && ok "r494 ⓐ LIVE_BIN = 라이브" || bad "r494 ⓐ LIVE_BIN 값"
[ "$(cat "$W1/.fable-team/LIVE_ROOT")" = "$RP" ] && ok "r494 ⓐ LIVE_ROOT = 공용 루트 경로(파일 값 /old/… 복사 0)" || bad "r494 ⓐ LIVE_ROOT=$(cat "$W1/.fable-team/LIVE_ROOT")"
has "$(bash "$W1/.fable-team/bin/ft-press-gate.sh" x 2>&1)" "LIVE-GATE x" "r494 ⓐ 연결 파일 → 라이브 게이트 실행"
snap1="$(cd "$W1/.fable-team" && cksum LIVE_BIN LIVE_ROOT bin/* | sort)"
out="$(R4RUN "$W1" --init 2>&1)"; rc=$?
rc_is "$rc" 0 "r494 ⓐ 두 번째 --init"; has "$out" "SHIM 2 · MOVED 0 · UNKNOWN 0" "r494 ⓐ 두 번째 MOVED 0"; hasnt "$out" "INIT " "r494 ⓐ 두 번째 INIT 0"; hasnt "$out" "NOTE" "r494 ⓐ 두 번째 NOTE 0"
[ "$snap1" = "$(cd "$W1/.fable-team" && cksum LIVE_BIN LIVE_ROOT bin/* | sort)" ] && ok "r494 ⓐ 두 번째 = 쓰기 0(바이트 불변)" || bad "r494 ⓐ 두 번째가 썼다"
out="$(R4RUN "$RP/.worktrees/w2" --init --dry-run 2>&1)"; rc=$?
rc_is "$rc" 0 "r494 ⓐ --init --dry-run"; has "$out" "PLAN init $RP/.worktrees/w2/.fable-team/bin" "r494 ⓐ dry-run PLAN init 줄"
[ ! -e "$RP/.worktrees/w2/.fable-team" ] && ok "r494 ⓐ dry-run 쓰기 0" || bad "r494 ⓐ dry-run 이 썼다"
# ⓑ --init 없이 bin 없음 → 기존 ERROR + 안내 · 생성 0
out="$(R4RUN "$RP/.worktrees/w3" 2>&1)"; rc=$?
rc_is "$rc" 3 "r494 ⓑ --init 없음 → rc3"; has "$out" "ERROR 루트 bin 없음: $RP/.worktrees/w3/.fable-team/bin (새 워크트리면 --init)" "r494 ⓑ ERROR + --init 안내"
[ ! -e "$RP/.worktrees/w3/.fable-team" ] && ok "r494 ⓑ 생성 0" || bad "r494 ⓑ 생성됨"
# ⓒ git 밖 · 공용 루트 자체(bin 지운 사본) · 설치 안 된 리포(LIVE_BIN 없음) → rc3 ERROR · 생성 0
out="$(R4RUN "$R4/plain" --init 2>&1)"; rc=$?
rc_is "$rc" 3 "r494 ⓒ git 밖 → rc3"; has "$out" "ERROR --init 불가 — git 밖" "r494 ⓒ git 밖 사유"; [ ! -e "$R4/plain/.fable-team" ] && ok "r494 ⓒ git 밖 생성 0" || bad "r494 ⓒ git 밖 생성됨"
C2="$R4/common2"; mkdir -p "$C2/.fable-team"; git init -q -b main "$C2"; printf '%s\n' "$LV" > "$C2/.fable-team/LIVE_BIN"
out="$(R4RUN "$C2" --init 2>&1)"; rc=$?
rc_is "$rc" 3 "r494 ⓒ 공용 루트 자체 → rc3"; has "$out" "공용 루트 자체다: $C2 — 공용 루트 설치는 install.sh" "r494 ⓒ 공용 루트 사유"; [ ! -e "$C2/.fable-team/bin" ] && ok "r494 ⓒ 공용 루트 생성 0" || bad "r494 ⓒ 공용 루트 bin 생성됨"
C3="$R4/noinst"; mkdir -p "$C3"; git init -q -b main "$C3"; git -C "$C3" -c user.email=t@t -c user.name=t commit -q --allow-empty -m e; git -C "$C3" worktree add -q -b x "$C3/.worktrees/x" main
out="$(R4RUN "$C3/.worktrees/x" --init 2>&1)"; rc=$?
rc_is "$rc" 3 "r494 ⓒ 설치 안 된 리포 → rc3"; has "$out" "설치된 리포가 아님" "r494 ⓒ LIVE_BIN 없음 사유"; [ ! -e "$C3/.worktrees/x/.fable-team" ] && ok "r494 ⓒ 설치 안 된 리포 생성 0" || bad "r494 ⓒ 생성됨"
# ⓓ install.sh: 워크트리 bin 없음 → dry-run PLAN shim-init · apply = bin 실재 · 공용 루트 bin 없음 = REJECT rc2 그대로
HINST="$HERE/../install.sh"; IH="$R4/home"; mkdir -p "$IH/Library/LaunchAgents" "$R4/fb"; printf '#!/bin/sh\nexit 0\n' > "$R4/fb/launchctl"; chmod 755 "$R4/fb/launchctl"
hinst() { local p="$1"; shift; env HOME="$IH" FT_LAUNCHCTL="$R4/fb/launchctl" bash "$HINST" "$@" --project "$p" --home "$IH" 2>&1; }
W4="$RP/.worktrees/w4"
out="$(hinst "$W4" --dry-run)"; rc=$?
rc_is "$rc" 0 "r494 ⓓ install --dry-run 워크트리"; has "$out" "PLAN shim-init $W4" "r494 ⓓ PLAN shim-init 줄"; [ ! -e "$W4/.fable-team/bin" ] && ok "r494 ⓓ dry-run 생성 0" || bad "r494 ⓓ dry-run 생성됨"
out="$(hinst "$W4" --apply)"; rc=$?
rc_is "$rc" 0 "r494 ⓓ install --apply 워크트리"; has "$out" "INIT $W4/.fable-team/bin" "r494 ⓓ apply INIT 줄"
[ -x "$W4/.fable-team/bin/ft-press-gate.sh" ] && ok "r494 ⓓ apply 뒤 bin/ft-press-gate.sh 실재" || bad "r494 ⓓ apply 뒤 bin 없음 :: $(printf '%s' "$out" | tail -4)"
[ "$(cat "$W4/.fable-team/LIVE_ROOT" 2>/dev/null)" = "$RP" ] && ok "r494 ⓓ apply LIVE_ROOT = 공용 루트" || bad "r494 ⓓ LIVE_ROOT=$(cat "$W4/.fable-team/LIVE_ROOT" 2>/dev/null)"
out="$(hinst "$C2" --dry-run)"; rc=$?
rc_is "$rc" 2 "r494 ⓓ 공용 루트 bin 없음 → REJECT rc2"; has "$out" "REJECT 프로젝트에 .fable-team/bin 없음" "r494 ⓓ REJECT 문구 그대로"
# ⓔ 훅: bin 없는 워크트리에서 러너 실행 → deny 문구에 설치 1줄(리포 LIVE_BIN 값) · 판정 deny 그대로
HOOK="$HERE/../kit/fable-team/templates/hooks/press-runner-gate.sh"; W3="$RP/.worktrees/w3"
hk() { printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"$1\",\"tool_input\":{\"command\":\"python3 tests/e2e/realtime_multi_e2e.py\"}}" | env -u FT_PRESS_GATE_BIN FT_PRESS_RUNNER_GATE_LOG="$R4/gate.log" bash "$HOOK" 2>&1; }
out="$(hk "$W3")"
has "$out" '"permissionDecision": "deny"' "r494 ⓔ 훅 판정 deny 그대로"
has "$out" "설치(master) = bash $LV/ft-root-bin-shim.sh --root $W3 --live $LV --init" "r494 ⓔ deny 문구에 shim --init 1줄(리포 LIVE_BIN)"
out="$(hk "$R4/plain")"; has "$out" "--live <LIVE_BIN> --init" "r494 ⓔ LIVE_BIN 못 읽으면 글자 <LIVE_BIN>"
# ⓔ nano-spawn: 워크트리 생성 직후 shim --init 줄 — 성공 = SHIM 끝줄 · 실패 = NOTE shim-init 실패(조용한 통과 0) · 추적본·키트 둘 다
for SP in "$HERE/../bin/ft-nano-spawn.sh" "$HERE/../kit/fable-team/bin/ft-nano-spawn.sh"; do
  tag="$(basename "$(dirname "$(dirname "$SP")")")"; SN="$R4/sn-$tag"; mkdir -p "$SN/h" "$SN/root/.fable-team"; printf '%s\n' "$LV" > "$SN/root/.fable-team/LIVE_BIN"
  awk '/# r494: 새 워크트리에 하네스 입구/{f=1;next} f{print} f && /NOTE shim-init 실패/{exit}' "$SP" > "$SN/snip.sh"
  [ "$(grep -c . "$SN/snip.sh")" = 2 ] && ok "r494 ⓔ $tag spawn shim-init 2줄 추출" || bad "r494 ⓔ $tag 추출 실패"
  printf '#!/usr/bin/env bash\necho "args=$*"; echo "SHIM 9 · MOVED 0 · UNKNOWN 0"\n' > "$SN/h/ft-root-bin-shim.sh"
  out="$(HERE="$SN/h" ROOT="$SN/root" WTDIR="$SN/wt" bash -c ". '$SN/snip.sh'" 2>&1)"
  has "$out" "SHIM 9 · MOVED 0 · UNKNOWN 0 (shim-init $SN/wt)" "r494 ⓔ $tag 성공 = SHIM 줄 1"
  printf '#!/usr/bin/env bash\necho "args=$*" >&2; echo "ERROR --init 불가 — git 밖: x"; exit 3\n' > "$SN/h/ft-root-bin-shim.sh"
  out="$(HERE="$SN/h" ROOT="$SN/root" WTDIR="$SN/wt" bash -c ". '$SN/snip.sh'; echo CONT" 2>&1)"
  has "$out" "NOTE shim-init 실패: ERROR --init 불가 — git 밖: x" "r494 ⓔ $tag 실패 = NOTE 줄"; has "$out" "CONT" "r494 ⓔ $tag 실패에도 spawn 계속"
  printf '#!/usr/bin/env bash\necho "$*"\n' > "$SN/h/ft-root-bin-shim.sh"
  has "$(HERE="$SN/h" ROOT="$SN/root" WTDIR="$SN/wt" bash -c ". '$SN/snip.sh'" 2>&1)" "--root $SN/wt --live $LV --init" "r494 ⓔ $tag 인자 = --root 워크트리 --live 루트 LIVE_BIN --init"
done
cmp -s "$HERE/../bin/ft-root-bin-shim.sh" "$HERE/../kit/fable-team/bin/ft-root-bin-shim.sh" && ok "r494 shim 추적본 = 키트(cmp)" || bad "r494 shim 추적본 ≠ 키트"
cmp -s "$HERE/../bin/ft-nano-spawn.sh" "$HERE/../kit/fable-team/bin/ft-nano-spawn.sh" && ok "r494 nano-spawn 추적본 = 키트(cmp)" || bad "r494 nano-spawn 추적본 ≠ 키트"

echo "== fail=$fail"; [ "$fail" = 0 ]
