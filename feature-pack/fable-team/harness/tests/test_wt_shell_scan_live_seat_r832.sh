#!/usr/bin/env bash
# test_wt_shell_scan_live_seat_r832.sh — 카드 r832: 껍데기 경보(ft-wt-sweep.sh shell_scan)가 살아 있는 나노 좌석 폴더를 올리던 것.
#   ⓐpane 경로가 그 폴더(또는 하위)면 SKIP «세션 있음» · 경로 앞부분만 같은 형제(A-r2)는 세션 없음 ⓑpane 0 · 미커밋(수정·새 파일) → SKIP «미커밋 N»
#   ⓒpane 0 · 미커밋 0(지워짐만) → 지금처럼 경보 + «(세션 0 · 미커밋 0)» ⓓtmux 목록 못 읽음 → 경보 0 · NOTE · 서명 파일 그대로
#   ⓔ.deleting-* = 지금 규칙 그대로(검사 밖) ⓕgit status 상한 초과 = SKIP «판정 못 함» · .git 링크 없는 폴더가 부모 리포 상태를 읽지 않음
#   r2(외부 DA r1 HOLD): ①pane 경로 별칭(심링크 · 심링크/하위 · /private 없는 /var 표기)도 실제 경로로 맞춤 · 없는 pane 경로 = 글자 비교만
#     ②판정 못 한 폴더 = 그 폴더만 이전 서명 이어받음(정상 → git rc128 → 정상 에서 같은 경보 재발 0)
#   r2b: 한 폴더 판정 못 함이 회차 전체 경보를 끄지 않음(X + 진짜 껍데기 C → C 경보) · .git 연결 끊긴 폴더 = 껍데기 «(git 연결 끊김)» · pane 있으면 SKIP
#   r3: 연결 판정 = git rev-parse(.git 파일 자체 파싱 0) · CRLF .git(DA r2 반례) → 연결됨 · 변형(상대 경로·끝 공백·앞 빈 줄)은 git 답과 같게 · rev-parse 상한 초과 = 판정 못 함
#   r844(외부 DA r3 HOLD 2): ⓐ.git 권한 000(rc128 «error opening») · 가리킨 gitdir 위 폴더 000 → 판정 못 함(이어받기 · 복구 전후 서명 같음)
#     ⓑ물려받은 GIT_DIR·GIT_WORK_TREE·GIT_INDEX_FILE(상위·다른 리포) → env 영향 0 ⓒ.git 없음 · gitdir 경로 없음 = 끊김 ⓓ한국어 로캘에서도 같은 판정
#   r844 r2(외부 DA r1): 심링크 .git 대상 상위 000 → 판정 못 함 · 깨진 심링크 = 끊김
#   r844 r3(외부 DA r2 · 재설계): 끊김 = .git 없음 · gitdir 경로 자체 없음 하나 — gitdir HEAD 000 · 저장소 아닌 폴더 · gitfile 꼴 틀림 = 판정 못 함
#   r844 r5(외부 DA r3 HOLD 2 · 재설계 r4): worktree list SHA 0(등록 gitdir HEAD 000) → ls-tree 실패 = 판정 못 함(서명 유지 · NOTE 1 · 복구 회차 경보 0) · worktree list rc≠0 = 판정 생략 · FT_WT_SCAN_ROOT 없이 물려받은 GIT_* 4개 = 원래 리포 판정 그대로
# 임시 git 리포 + 임시 워크트리 + 가짜 tmux(list-panes 출력 = 파일) 만 — 실 tmux·실 리포 0 · 외부 호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${WT_TEST_SRC:-$HERE/../../harness/kit/fable-team/bin}"   # 고치기 전 코드로 돌려 FAIL 을 기록할 때만 덮어쓴다
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
# listed <출력> <이름> — [HIL] 껍데기 줄의 폴더 목록(«): » 와 «—» 사이)에 그 이름이 «낱말로» 있나
listed() { printf '%s\n' "$1" | grep '^\[HIL\] seat=byz-.*-wt-shell ' | sed -n 's/^[^)]*): \(.*\)— 처리는.*/\1/p' | tr ' ' '\n' | grep -qxF -- "$2"; }

mkdir -p "$T/bin" "$T/fake" "$T/clean"
cp "$SRC/ft-wt-sweep.sh" "$T/bin/"
bash -n "$T/bin/ft-wt-sweep.sh" && ok "bash -n" || bad "bash -n"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_TMUX_LOG"
case "$1" in
  list-panes) [ -n "${FAKE_TMUX_FAIL:-}" ] && { echo "error connecting to /tmp/fake"; exit 1; }; cat "$FAKE_PANE_CWDS" 2>/dev/null; exit 0;;
  *) exit 1;;
esac
EOF
REAL_GIT="$(command -v git)"
mkdir -p "$T/slowgit"
cat > "$T/slowgit/git" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *" status "*) [ -n "\${FAKE_GIT_SLOW:-}" ] && sleep 4; [ -n "\${FAKE_GIT_FAIL:-}" ] && exit 128
    [ -n "\${FAKE_GIT_FAIL_DIR:-}" ] && case " \$* " in *" \$FAKE_GIT_FAIL_DIR "*) exit 128;; esac;;
  *" rev-parse "*) [ -n "\${FAKE_REVPARSE_DIR:-}" ] && case " \$* " in *" \$FAKE_REVPARSE_DIR "*) sleep "\${FAKE_REVPARSE_SLOW:-0}";; esac;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/fake/"* "$T/slowgit/git"

REPO="$T/repo"; mkdir -p "$REPO"
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
git -C "$REPO" init -q -b main
for d in 0 1 2 3 4 5; do mkdir -p "$REPO/d$d"; echo x > "$REPO/d$d/x"; done
GIT add -A && GIT commit -q -m init
# 폴더 만들기 — 최상위 항목 d0·d1 지움(부재 2 = 껍데기 후보)
mk() { GIT worktree add -q --detach "$REPO/.worktrees/$1" main; rm -rf "$REPO/.worktrees/$1/d0" "$REPO/.worktrees/$1/d1"; }
mk A; mk A-r2; mk B; mk C; mk E.deleting-123; GIT worktree add -q --detach "$REPO/.worktrees/OK" main
echo y >> "$REPO/.worktrees/B/d2/x"; echo new > "$REPO/.worktrees/B/new.txt"   # 미커밋 2(수정 1 · 새 파일 1)
printf '%s\n' "$REPO/.worktrees/A/d3" "$REPO/.worktrees/E.deleting-123" "/somewhere/else" > "$T/panes"

swp() { ( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FT_TMUX_BIN="$T/fake/tmux" FAKE_PANE_CWDS="$T/panes" FAKE_TMUX_LOG="$T/tmux.log" \
  FT_WT_CLEAN_DIR="$T/clean" FT_WT_SCAN_ROOT="$REPO" FT_WT_SHELL_SCAN_SEC=0 HIL_DIR="$T/hil" HIL_CLIP=0 "$@" bash "$T/bin/ft-wt-sweep.sh" 2>&1 ); }
# swcd <폴더> [VAR=…] — FT_WT_SCAN_ROOT 없이(자동 루트 결정) 그 폴더에서 실행 — r844 r5 ⓐ 시험용
swcd() { local d="$1"; shift; ( cd "$d" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FT_TMUX_BIN="$T/fake/tmux" FAKE_PANE_CWDS="$T/panes" FAKE_TMUX_LOG="$T/tmux.log" \
  FT_WT_CLEAN_DIR="$T/clean" FT_WT_SHELL_SCAN_SEC=0 HIL_DIR="$T/hil" HIL_CLIP=0 "$@" bash "$T/bin/ft-wt-sweep.sh" 2>&1 ); }

echo "== ⓐⓑⓒⓔ 한 회차"
: > "$T/tmux.log"; rm -f "$T/clean/.shell-sig"
o="$(swp)"
if listed "$o" A; then bad "ⓐ pane 있는 A 가 경보 목록에 있음 ← ${o:0:600}"; else ok "ⓐ pane 이 A/d3(하위) → A 경보 목록에서 빠짐"; fi
has "$o" "SKIP 껍데기 후보 A — 세션 있음" "ⓐ SKIP 1줄(세션 있음)"
hasnt "$o" "[HIL] seat=byz-harness-wt-shell 반쯤 지워진 워크트리 껍데기 1곳(전체 1곳): A " "ⓐ SKIP 줄은 경보가 아님"
listed "$o" A-r2 && ok "ⓐ 경로 앞부분만 같은 형제 A-r2 = 세션 없음 → 경보 목록에" || bad "ⓐ A-r2 를 세션 있음으로 착각 ← ${o:0:600}"
if listed "$o" B; then bad "ⓑ 미커밋 B 가 경보 목록에 있음"; else ok "ⓑ pane 0 · 미커밋 → B 빠짐"; fi
has "$o" "SKIP 껍데기 후보 B — 미커밋 2" "ⓑ SKIP 1줄(미커밋 2 · 지워짐 줄은 안 셈)"
listed "$o" C && ok "ⓒ pane 0 · 미커밋 0(지워짐만) → C 경보 목록에" || bad "ⓒ C 없음 ← ${o:0:600}"
has "$o" "(세션 0 · 미커밋 0)" "ⓒ 경보 문구에 «세션 0 · 미커밋 0»"
listed "$o" E.deleting-123 && ok "ⓔ 포인터 없는 .deleting-* = 지금 규칙 그대로(pane 있어도 검사 밖)" || bad "ⓔ .deleting 빠짐 ← ${o:0:600}"
if listed "$o" OK; then bad "멀쩡한 OK 가 경보 목록에"; else ok "  └ 멀쩡한 폴더(OK)는 안 셈"; fi
hasnt "$o" "NOTE 껍데기 판정 못 함" "  └ 판정 다 끝난 회차 = 판정 못 함 NOTE 0"
[ -n "$(cat "$T/clean/.shell-sig" 2>/dev/null)" ] && ok "  └ 완전한 회차 = 서명 저장" || bad "서명 없음"
[ "$(grep -c '^list-panes' "$T/tmux.log")" = 1 ] && ok "ⓐ tmux pane 목록 = 회차당 1회" || bad "tmux 호출 $(grep -c '^list-panes' "$T/tmux.log")회"
grep -q -- "-F #{pane_current_path}" "$T/tmux.log" && grep -q -- "list-panes -a" "$T/tmux.log" && ok "  └ list-panes -a -F '#{pane_current_path}'" || bad "tmux 인자 $(cat "$T/tmux.log")"

echo "== r2 ① pane 경로 별칭 → 실제 경로로 맞춤(각각 A SKIP «세션 있음» · A 경보 0)"
ln -s "$REPO/.worktrees/A" "$T/alias"
case "$REPO" in /private/*) VARFORM="${REPO#/private}/.worktrees/A";; *) VARFORM="";; esac
[ -n "$VARFORM" ] && [ -d "$VARFORM" ] && ok "① /var 표기 준비($VARFORM)" || bad "① 임시 폴더가 /private/… 아님 — /var 표기 시험 못 함 ($REPO)"
for q in "$T/alias" "$T/alias/d2" "$VARFORM"; do
  printf '%s\n' "$q" > "$T/panes"; rm -f "$T/clean/.shell-sig"
  o="$(swp)"
  has "$o" "SKIP 껍데기 후보 A — 세션 있음" "① pane=$q → A SKIP «세션 있음»"
  if listed "$o" A; then bad "① pane=$q → A 가 경보 목록에 ← ${o:0:600}"; else ok "① pane=$q → A 경보 0"; fi
  listed "$o" A-r2 && ok "  └ 별칭이어도 형제 A-r2 는 세션 없음(경보 목록에)" || bad "① A-r2 를 세션 있음으로 착각 ← ${o:0:600}"
done

echo "== r2 없는 pane 경로(지워진 폴더) → 글자 비교만 · 진짜 껍데기 C 는 경보(회귀)"
printf '%s\n' "$REPO/.worktrees/gone/x" "$REPO/.worktrees/A" > "$T/panes"; rm -f "$T/clean/.shell-sig"
o="$(swp)"
listed "$o" C && ok "없는 pane 경로 섞여도 C 경보 목록에" || bad "C 없음 ← ${o:0:600}"
has "$o" "SKIP 껍데기 후보 A — 세션 있음" "  └ 글자 그대로 pane(A) 은 그대로 맞춤"
hasnt "$o" "NOTE 껍데기 판정 못 함" "  └ 없는 pane 경로는 판정 못 함 아님"

echo "== r2 ② 정상 → git status rc128 → 정상 : 2·3회차 경보 0 · 서명 1회차와 같음"
printf '%s\n' "$REPO/.worktrees/A/d3" > "$T/panes"; rm -f "$T/clean/.shell-sig"
swg() { swp PATH="$T/slowgit:$T/fake:$PATH" "$@"; }
o1="$(swg)"; s1="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
listed "$o1" C && ok "② 1회차 경보(C)" || bad "② 1회차 경보 없음 ← ${o1:0:600}"
o2="$(swg FAKE_GIT_FAIL=1)"; s2="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
hasnt "$o2" "[HIL]" "② 2회차(git rc128) 경보 0"
has "$o2" "SKIP 껍데기 후보 C — 판정 못 함(git status rc=128)" "② 2회차 C 판정 못 함"
has "$o2" "NOTE 껍데기 판정 못 함 3곳(이전 판정 이어받음)" "② 2회차 NOTE «판정 못 함 3곳(이전 판정 이어받음)»"
[ -n "$s1" ] && [ "$s2" = "$s1" ] && ok "② 2회차 서명 = 1회차(판정 못 한 A-r2·C 이어받음)" || bad "② 서명 바뀜: 1«${s1}» 2«${s2}»"
o3="$(swg)"
hasnt "$o3" "[HIL]" "② 3회차(정상) 경보 0 — 서명 같음"
printf '%s\n' "$REPO/.worktrees/A/d3" "$REPO/.worktrees/E.deleting-123" "/somewhere/else" > "$T/panes"

echo "== ⓓ tmux 목록 못 읽음 → 경보 0 · 서명 그대로"
printf 'keep-me' > "$T/clean/.shell-sig"
o="$(swp FAKE_TMUX_FAIL=1)"
hasnt "$o" "[HIL]" "ⓓ 경보 0"
has "$o" "NOTE 껍데기 판정 생략 — tmux 목록 못 읽음" "ⓓ NOTE 1줄"
[ "$(cat "$T/clean/.shell-sig")" = keep-me ] && ok "ⓓ 서명 파일 안 바꿈" || bad "ⓓ 서명 바뀜: $(cat "$T/clean/.shell-sig" 2>/dev/null || echo 없음)"

echo "== ⓕ git status 상한 초과 → 판정 못 함 SKIP · 경보 0(그 폴더)"
rm -f "$T/clean/.shell-sig"
t0=$(date +%s); o="$( ( cd "$T" && env -i HOME="$HOME" PATH="$T/slowgit:$T/fake:$PATH" FT_TMUX_BIN="$T/fake/tmux" FAKE_PANE_CWDS="$T/panes" FAKE_TMUX_LOG="$T/tmux.log" \
  FT_WT_CLEAN_DIR="$T/clean" FT_WT_SCAN_ROOT="$REPO" FT_WT_SHELL_SCAN_SEC=0 FT_WT_SHELL_GIT_SEC=1 FAKE_GIT_SLOW=1 bash "$T/bin/ft-wt-sweep.sh" 2>&1 ) )"; el=$(( $(date +%s) - t0 ))
has "$o" "SKIP 껍데기 후보 C — 판정 못 함" "ⓕ 상한 1s · git status 4s → C 판정 못 함 SKIP"
has "$o" "NOTE 껍데기 판정 못 함" "ⓕ 상한 초과 = 판정 못 함 NOTE(이전 서명 없음 → 이어받을 것 0)"
if listed "$o" C; then bad "ⓕ 판정 못 한 C 가 경보에"; else ok "ⓕ C 경보 0"; fi
[ "$el" -lt 15 ] && ok "ⓕ 상한이 먹음(${el}s · 후보 4 × 4s 를 기다리지 않음)" || bad "ⓕ ${el}s"
grep -q 'FT_WT_SHELL_GIT_SEC:-7}' "$T/bin/ft-wt-sweep.sh" && ok "ⓕ 기본 상한 7 s" || bad "ⓕ 기본 상한 7 아님"
grep -q -- '--untracked-files=normal' "$T/bin/ft-wt-sweep.sh" && ok "ⓕ status --porcelain --untracked-files=normal" || bad "ⓕ untracked 옵션 없음"

echo "== r2b 나노 지적 꼴 — X(연결됨 · git status 실패) + 진짜 껍데기 C → C 경보 · X 빠짐 · NOTE 1"
mk X
rm -f "$T/clean/.shell-sig"
o="$(swg FAKE_GIT_FAIL_DIR="$REPO/.worktrees/X")"
has "$o" "SKIP 껍데기 후보 X — 판정 못 함" "r2b X 판정 못 함 SKIP"
listed "$o" C && ok "r2b 한 폴더 판정 못 함이 회차 전체를 막지 않음 → C 경보" || bad "r2b C 경보 없음 ← ${o:0:600}"
if listed "$o" X; then bad "r2b 이전 서명에 없는 X 가 경보에"; else ok "r2b X(이전 서명에 없음) 빠짐"; fi
has "$o" "NOTE 껍데기 판정 못 함 1곳(이전 판정 이어받음)" "r2b NOTE 1곳"
hasnt "$o" "(git 연결 끊김)" "  └ gitdir 가 있는 X 는 «git 연결 끊김» 아님"

echo "== r2b .git 없는 폴더 Y(F) = 껍데기 «(git 연결 끊김)» · pane 있으면 SKIP"
mk F; rm -f "$REPO/.worktrees/F/.git"                                            # 부모 리포로 올라가면 «?? .worktrees/» 를 읽는다
rm -f "$T/clean/.shell-sig"
o="$(swp)"
listed "$o" F && ok "r2b .git 없는 F(세션 0) → 경보 목록에" || bad "r2b F 경보 없음 ← ${o:0:600}"
has "$o" " F (git 연결 끊김) " "r2b 경보 줄에 «F (git 연결 끊김)»"
hasnt "$o" "SKIP 껍데기 후보 F — 미커밋" "  └ 부모 리포 «?? .worktrees/» 를 F 의 미커밋으로 셈 0"
hasnt "$o" "SKIP 껍데기 후보 F — 판정 못 함" "  └ F 는 판정 못 함 아님"
hasnt "$o" " C (git 연결 끊김)" "  └ 표시는 F 에만"
printf '%s\n' "$REPO/.worktrees/F" > "$T/panes"; rm -f "$T/clean/.shell-sig"
o="$(swp)"
has "$o" "SKIP 껍데기 후보 F — 세션 있음" "r2b F 에 pane 있음 → SKIP «세션 있음»(세션 검사 먼저)"
if listed "$o" F; then bad "r2b pane 있는 F 가 경보에"; else ok "r2b pane 있는 F 경보 0"; fi
mkdir -p "$T/gone-gitdir"; printf 'gitdir: %s\n' "$T/gone-gitdir/nope" > "$REPO/.worktrees/X/.git"; : > "$T/panes"; rm -f "$T/clean/.shell-sig"
o="$(swp)"
has "$o" " X (git 연결 끊김) " "r2b gitdir 가 가리키는 곳 없음 → «X (git 연결 끊김)»"
mkdir -p "$T/bogus"; printf 'gitdir: %s\n' "$T/bogus" > "$REPO/.worktrees/X/.git"; rm -f "$T/clean/.shell-sig"
o="$(swp)"
has "$o" "SKIP 껍데기 후보 X — 판정 못 함(git rev-parse rc=" "r844 r3 gitdir 는 있으나 저장소 아님(git rc≠0) → 끊김 아님 · X 판정 못 함"
hasnt "$o" "X (git 연결 끊김)" "  └ gitdir 경로가 있으면 «git 연결 끊김» 아님(r844 r3 개정)"

echo "== r3 DA r2 반례 — CRLF 줄끝 .git(gitdir 실재) + 수정 1 · 새 파일 1 → SKIP «미커밋 2» · 경보 0"
mk G; g="$(cat "$REPO/.worktrees/G/.git")"; printf '%s\r\n' "$g" > "$REPO/.worktrees/G/.git"
echo y >> "$REPO/.worktrees/G/d2/x"; echo new > "$REPO/.worktrees/G/new.txt"
rm -f "$T/clean/.shell-sig"
o="$(swp)"
has "$o" "SKIP 껍데기 후보 G — 미커밋 2" "r3 CRLF .git → 연결됨 · SKIP «미커밋 2»"
if listed "$o" G; then bad "r3 CRLF G 가 경보에(«미커밋 0» 으로 읽음)"; else ok "r3 CRLF G 경보 0"; fi
echo "== r3 .git 파일 변형 — git 이 받아들이면 연결됨(git 답 = 판정)"
vg() { # vg <이름> <.git 내용 printf 형식> <gitdir 값> — 새 파일 1(연결되면 «미커밋 1»)
  mk "$1"; printf "$2" "${3}" > "$REPO/.worktrees/$1/.git"; echo new > "$REPO/.worktrees/$1/new.txt"
}
vg H1 'gitdir: %s\n' "../../.git/worktrees/H1"
vg H2 'gitdir: %s  \n' "$REPO/.git/worktrees/H2"
vg H3 '\ngitdir: %s\n' "$REPO/.git/worktrees/H3"
rm -f "$T/clean/.shell-sig"
o="$(swp)"
# r844 r3: git 이 거절하면 — gitdir: 뒤 경로(끝 \r\n 만 뗌)가 없으면 끊김(H2 «끝 공백» 경로) · gitdir: 줄 꼴이 아니면 판정 못 함(H3)
for h in H1:상대경로:끊김 H2:끝공백:끊김 H3:앞빈줄:판정; do
  n="${h%%:*}"; r="${h#*:}"; w="${r#*:}"; r="${r%%:*}"
  if GIT_CEILING_DIRECTORIES="$REPO/.worktrees" git -C "$REPO/.worktrees/$n" rev-parse --git-dir >/dev/null 2>&1; then
    has "$o" "SKIP 껍데기 후보 $n — 미커밋 1" "r3 $r .git — git 이 받아들임 → 연결됨 · SKIP «미커밋 1»"
  elif [ "$w" = 끊김 ]; then
    has "$o" " $n (git 연결 끊김) " "r3 $r .git — git 거절 · gitdir: 뒤 경로 없음 → «git 연결 끊김»"
  else
    has "$o" "SKIP 껍데기 후보 $n — 판정 못 함(git rev-parse rc=" "r844 r3 $r .git — gitdir: 줄 꼴 아님 → 판정 못 함"
  fi
done

echo "== r3 rev-parse 지연 7.5 s(상한 7) → 판정 못 함 · 이전 서명 이어받음"
rm -f "$T/clean/.shell-sig"; o1="$(swp)"; s1="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
listed "$o1" C && ok "r3 1회차 C 경보" || bad "r3 1회차 C 없음 ← ${o1:0:600}"
o2="$(swg FAKE_REVPARSE_DIR="$REPO/.worktrees/C" FAKE_REVPARSE_SLOW=7.5)"; s2="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
has "$o2" "SKIP 껍데기 후보 C — 판정 못 함(git rev-parse 7s 초과)" "r3 지연 → C 판정 못 함"
hasnt "$o2" "C (git 연결 끊김)" "  └ 시간 초과를 연결 끊김으로 읽지 않음"
hasnt "$o2" "[HIL]" "r3 2회차 경보 0(이어받음)"
[ -n "$s1" ] && [ "$s2" = "$s1" ] && ok "r3 2회차 서명 = 1회차" || bad "r3 서명 바뀜: 1«${s1}» 2«${s2}»"

echo "== r844 ⓐ DA r3 반례 ① — K 미커밋 3(수정·새 파일·staged) · K/.git 권한 000 → 판정 못 함 · 이어받기 · 복구 전후 서명 같음 · C 경보 반복 0"
mk K; echo y >> "$REPO/.worktrees/K/d2/x"; echo new > "$REPO/.worktrees/K/new.txt"; echo st > "$REPO/.worktrees/K/st.txt"; git -C "$REPO/.worktrees/K" add st.txt
printf '%s\n' "$REPO/.worktrees/A/d3" > "$T/panes"; rm -f "$T/clean/.shell-sig"
o1="$(swp)"; s1="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
has "$o1" "SKIP 껍데기 후보 K — 미커밋 3" "ⓐ 1회차 K SKIP «미커밋 3»"
listed "$o1" C && ok "ⓐ 1회차 C 경보" || bad "ⓐ 1회차 C 없음 ← ${o1:0:600}"
chmod 000 "$REPO/.worktrees/K/.git"; o2="$(swp)"; s2="$(cat "$T/clean/.shell-sig" 2>/dev/null)"; chmod 644 "$REPO/.worktrees/K/.git"
has "$o2" "SKIP 껍데기 후보 K — 판정 못 함(git rev-parse rc=128 · fatal: error opening" "ⓐ .git 000 → K 판정 못 함(rc128 · git 원문)"
hasnt "$o2" "K (git 연결 끊김)" "ⓐ 권한 실패를 «연결 끊김» 으로 읽지 않음"
if listed "$o2" K; then bad "ⓐ 미커밋 3 인 K 가 경보에"; else ok "ⓐ K 경보 0"; fi
hasnt "$o2" "[HIL]" "ⓐ 2회차 경보 0(서명 그대로)"
[ -n "$s1" ] && [ "$s2" = "$s1" ] && ok "ⓐ 권한 000 회차 서명 = 1회차" || bad "ⓐ 서명 바뀜: 1«${s1}» 2«${s2}»"
o3="$(swp)"; s3="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
hasnt "$o3" "[HIL]" "ⓐ 권한 복구 회차 경보 0(C 경보 반복 0)"
[ "$s3" = "$s1" ] && ok "ⓐ 복구 전후 서명 같음" || bad "ⓐ 복구 뒤 서명 바뀜: 1«${s1}» 3«${s3}»"
echo "== r844 ⓐ' 가리킨 gitdir 못 읽음(권한) · 위 폴더 권한으로 있는지 모름 → 판정 못 함(끊김 아님)"
chmod 000 "$REPO/.git/worktrees/K"; o="$(swp)"; s="$(cat "$T/clean/.shell-sig" 2>/dev/null)"; chmod 755 "$REPO/.git/worktrees/K"
if listed "$o" K; then bad "ⓐ' 등록 폴더 000 → K 가 경보에"; else ok "ⓐ' 등록 폴더(.git/worktrees/K) 000 → K 경보 0(worktree list 가 후보에서 뺌)"; fi
hasnt "$o" "K (git 연결 끊김)" "ⓐ' 등록 폴더 권한을 «연결 끊김» 으로 읽지 않음"
[ "$s" = "$s1" ] && ok "ⓐ' 서명 = 1회차" || bad "ⓐ' 서명 바뀜: 1«${s1}» «${s}»"
# K2: 등록(.git/worktrees/K2)은 그대로 두고 폴더 .git 만 숨긴 사본($T/hide/K2)을 가리킴 → 사본 위 폴더 000 = git «저장소 아님»(가리킨 곳 있는지 모름)
mk K2; mkdir -p "$T/hide"; cp -R "$REPO/.git/worktrees/K2" "$T/hide/K2"; echo "$REPO/.git" > "$T/hide/K2/commondir"
printf 'gitdir: %s\n' "$T/hide/K2" > "$REPO/.worktrees/K2/.git"; echo new > "$REPO/.worktrees/K2/new.txt"
GIT_CEILING_DIRECTORIES="$REPO/.worktrees" git -C "$REPO/.worktrees/K2" rev-parse --git-dir >/dev/null 2>&1 && ok "ⓐ' K2 준비(gitdir = $T/hide/K2 · 연결됨)" || bad "ⓐ' K2 준비 실패"
rm -f "$T/clean/.shell-sig"; o="$(swp)"
has "$o" "SKIP 껍데기 후보 K2 — 미커밋 1" "ⓐ' K2 평소 = SKIP «미커밋 1»"
chmod 000 "$T/hide"; o="$(swp)"; chmod 755 "$T/hide"
has "$o" "SKIP 껍데기 후보 K2 — 판정 못 함(git rev-parse rc=128 · fatal: not a git repository" "ⓐ' gitdir 위 폴더 000(git «저장소 아님») → 있는지 모름 = K2 판정 못 함"
hasnt "$o" "K2 (git 연결 끊김)" "ⓐ' 위 폴더 권한을 «연결 끊김» 으로 읽지 않음"

echo "== r844 ⓑ DA r3 반례 ② — 물려받은 GIT_DIR·GIT_WORK_TREE·GIT_INDEX_FILE(상위 리포) → B SKIP «미커밋 2»"
rm -f "$T/clean/.shell-sig"; o0="$(swp)"; s0="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
rm -f "$T/clean/.shell-sig"; o="$(swp GIT_DIR="$REPO/.git" GIT_WORK_TREE="$REPO" GIT_INDEX_FILE="$REPO/.git/index")"; s="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
has "$o" "SKIP 껍데기 후보 B — 미커밋 2" "ⓑ env 상위 리포 → B SKIP «미커밋 2»(env 영향 0)"
if listed "$o" B; then bad "ⓑ B 가 «미커밋 0» 경보에"; else ok "ⓑ B 경보 0"; fi
[ -n "$s0" ] && [ "$s" = "$s0" ] && ok "ⓑ 서명 = env 없는 회차" || bad "ⓑ 서명 다름: 0«${s0}» «${s}»"
U="$T/other"; git init -q -b main "$U"; git -C "$U" -c user.email=t@t -c user.name=t commit -q --allow-empty -m u
rm -f "$T/clean/.shell-sig"; o="$(swp GIT_DIR="$U/.git" GIT_WORK_TREE="$U" GIT_INDEX_FILE="$U/.git/index" GIT_COMMON_DIR="$U/.git")"; s="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
has "$o" "SKIP 껍데기 후보 B — 미커밋 2" "ⓑ env 다른 깨끗한 리포 → B SKIP «미커밋 2»"
[ "$s" = "$s0" ] && ok "ⓑ 다른 리포 env 에도 폴더 목록·서명 같음(SCAN_ROOT 호출도 env 지움)" || bad "ⓑ 서명 다름: 0«${s0}» «${s}»"

echo "== r844 ⓒ(r3 개정) 끊김 = .git 없음 · gitdir 경로 없음 하나 — 저장소 아닌 폴더 · gitfile 꼴 틀림 = 판정 못 함"
mk K3; printf 'garbage\n' > "$REPO/.worktrees/K3/.git"
rm -f "$T/clean/.shell-sig"; o="$(swp)"
has "$o" "SKIP 껍데기 후보 X — 판정 못 함(git rev-parse rc=" "ⓒ X(gitdir = 있는 폴더 · 저장소 아님) → 판정 못 함"
has "$o" " F (git 연결 끊김) " "ⓒ F(.git 없음) → 끊김 그대로"
has "$o" "SKIP 껍데기 후보 K3 — 판정 못 함(git rev-parse rc=" "ⓒ K3(.git 내용 틀림 · gitdir: 줄 없음) → 판정 못 함"
hasnt "$o" "K3 (git 연결 끊김)" "  └ gitfile 꼴 틀림을 «연결 끊김» 으로 읽지 않음"
printf 'gitdir: %s\n' "$T/gone-gitdir/nope" > "$REPO/.worktrees/X/.git"; rm -f "$T/clean/.shell-sig"; o="$(swp)"
has "$o" " X (git 연결 끊김) " "ⓒ X(gitdir 가리킨 곳 없음) → 끊김 그대로"
listed "$o" X && ok "ⓒ X(gitdir: 대상 없음) 첫 회차 경보" || bad "ⓒ X 첫 회차 경보 없음 ← ${o:0:600}"
hasnt "$o" "SKIP 껍데기 후보 X — 판정 못 함" "ⓒ 진짜 끊김은 판정 못 함 아님"

echo "== r844 ⓓ 오류 문구 판별 = LC_ALL=C 고정 — 한국어 로캘에서도 같은 판정"
KO="$(LC_ALL=ko_KR.UTF-8 LANG=ko_KR.UTF-8 GIT_CEILING_DIRECTORIES="$REPO/.worktrees" git -C "$REPO/.worktrees/X" rev-parse --git-dir 2>&1 >/dev/null)"
case "$KO" in *"not a git repository"*) bad "ⓓ 준비 — 이 git 은 한국어 문구가 없음(시험 무의미) «$KO»";; *) ok "ⓓ 준비 — 한국어 로캘 git 문구 «${KO:0:60}»";; esac
rm -f "$T/clean/.shell-sig"; o="$(swp LC_ALL=ko_KR.UTF-8 LANG=ko_KR.UTF-8)"
has "$o" " X (git 연결 끊김) " "ⓓ 한국어 로캘 · X(가리킨 곳 없음) → 끊김"
chmod 000 "$REPO/.worktrees/K/.git"; o="$(swp LC_ALL=ko_KR.UTF-8 LANG=ko_KR.UTF-8)"; chmod 644 "$REPO/.worktrees/K/.git"
has "$o" "SKIP 껍데기 후보 K — 판정 못 함" "ⓓ 한국어 로캘 · K .git 000 → 판정 못 함"

echo "== r844 r2 외부 DA r1 반례 — K4 미커밋 3 · .git = 정상 gitfile 의 심링크 · 대상 상위 폴더만 000 → 판정 못 함 · 서명 그대로 · 복구 회차 경보 0"
mk K4; mkdir -p "$T/lnk/sub"; mv "$REPO/.worktrees/K4/.git" "$T/lnk/sub/gitfile"; ln -s "$T/lnk/sub/gitfile" "$REPO/.worktrees/K4/.git"
echo y >> "$REPO/.worktrees/K4/d2/x"; echo new > "$REPO/.worktrees/K4/new.txt"; echo st > "$REPO/.worktrees/K4/st.txt"; git -C "$REPO/.worktrees/K4" add st.txt
rm -f "$T/clean/.shell-sig"; o1="$(swp)"; s1="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
has "$o1" "SKIP 껍데기 후보 K4 — 미커밋 3" "r2 1회차 K4(심링크 .git) SKIP «미커밋 3»"
chmod 000 "$T/lnk/sub"; o2="$(swp)"; s2="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
o2ko="$(swp LC_ALL=ko_KR.UTF-8 LANG=ko_KR.UTF-8)"; chmod 755 "$T/lnk/sub"
has "$o2" "SKIP 껍데기 후보 K4 — 판정 못 함(git rev-parse rc=128" "r2 심링크 대상 상위 000 → K4 판정 못 함(rev-parse 먼저 · 접근 불가)"
hasnt "$o2" "K4 (git 연결 끊김)" "r2 접근 불가를 «.git 없음»·«연결 끊김» 으로 읽지 않음"
if listed "$o2" K4; then bad "r2 미커밋 3 인 K4 가 경보에"; else ok "r2 K4 경보 0"; fi
hasnt "$o2" "[HIL]" "r2 000 회차 경보 0(서명 그대로)"
[ -n "$s1" ] && [ "$s2" = "$s1" ] && ok "r2 000 회차 서명 = 1회차" || bad "r2 서명 바뀜: 1«${s1}» 2«${s2}»"
has "$o2ko" "SKIP 껍데기 후보 K4 — 판정 못 함" "r2 한국어 로캘에서도 K4 판정 못 함"
o3="$(swp)"; s3="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
has "$o3" "SKIP 껍데기 후보 K4 — 미커밋 3" "r2 권한 복구 → K4 SKIP «미커밋 3»"
hasnt "$o3" "[HIL]" "r2 권한 복구 회차 경보 0"
[ "$s3" = "$s1" ] && ok "r2 복구 전후 서명 같음" || bad "r2 복구 뒤 서명 바뀜: 1«${s1}» 3«${s3}»"
echo "== r844 r2 진짜 끊김은 그대로 — 심링크 .git 대상 없음(매달린 심링크) → 끊김"
mk K5; rm -f "$REPO/.worktrees/K5/.git"; ln -s "$T/lnk/nope/gitfile" "$REPO/.worktrees/K5/.git"
rm -f "$T/clean/.shell-sig"; o="$(swp)"
has "$o" " K5 (git 연결 끊김) " "r2 매달린 심링크 .git(대상 없음 ENOENT) → 끊김"
hasnt "$o" "SKIP 껍데기 후보 K5" "r2 매달린 심링크 → SKIP 아님"
listed "$o" K5 && ok "r3 깨진 심링크 K5 첫 회차 경보" || bad "r3 K5 첫 회차 경보 없음 ← ${o:0:600}"

echo "== r844 r3 외부 DA r2 반례 — K6 미커밋 3 · 정상 gitdir · gitdir 의 HEAD 만 000 → 판정 못 함 · 서명 그대로 · 복구 회차 경보 0"
# 등록 폴더(.git/worktrees/K6) HEAD 000 은 worktree list 의 HEAD sha 가 비어 후보에서 빠진다 → 폴더 .git 이 가리킨 gitdir 사본($T/hide3/K6)의 HEAD 를 막는다(등록은 그대로)
mk K6; mkdir -p "$T/hide3"; cp -R "$REPO/.git/worktrees/K6" "$T/hide3/K6"; echo "$REPO/.git" > "$T/hide3/K6/commondir"
printf 'gitdir: %s\n' "$T/hide3/K6" > "$REPO/.worktrees/K6/.git"
echo y >> "$REPO/.worktrees/K6/d2/x"; echo new > "$REPO/.worktrees/K6/new.txt"; echo st > "$REPO/.worktrees/K6/st.txt"; git -C "$REPO/.worktrees/K6" add st.txt
rm -f "$T/clean/.shell-sig"; o1="$(swp)"; s1="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
has "$o1" "SKIP 껍데기 후보 K6 — 미커밋 3" "r3 1회차 K6 SKIP «미커밋 3»"
chmod 000 "$T/hide3/K6/HEAD"
e6="$(GIT_CEILING_DIRECTORIES="$REPO/.worktrees" LC_ALL=C git -C "$REPO/.worktrees/K6" rev-parse --git-dir 2>&1)"
case "$e6" in *"not a git repository"*) ok "r3 K6 준비 — HEAD 000 에 git «not a git repository»(DA r2 꼴)";; *) bad "r3 K6 준비 — git 답이 DA r2 꼴 아님 «${e6:0:160}»";; esac
o2="$(swp)"; s2="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
o2ko="$(swp LC_ALL=ko_KR.UTF-8 LANG=ko_KR.UTF-8)"; chmod 644 "$T/hide3/K6/HEAD"
has "$o2" "SKIP 껍데기 후보 K6 — 판정 못 함(git rev-parse rc=" "r3 HEAD 000(git «저장소 아님») → K6 판정 못 함"
hasnt "$o2" "K6 (git 연결 끊김)" "r3 gitdir 안 파일 권한을 «연결 끊김» 으로 읽지 않음"
if listed "$o2" K6; then bad "r3 미커밋 3 인 K6 가 경보에"; else ok "r3 K6 경보 0"; fi
hasnt "$o2" "[HIL]" "r3 000 회차 경보 0(서명 그대로)"
[ -n "$s1" ] && [ "$s2" = "$s1" ] && ok "r3 000 회차 서명 = 1회차" || bad "r3 서명 바뀜: 1«${s1}» 2«${s2}»"
has "$o2ko" "SKIP 껍데기 후보 K6 — 판정 못 함" "r3 한국어 로캘에서도 K6 판정 못 함"
o3="$(swp)"; s3="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
has "$o3" "SKIP 껍데기 후보 K6 — 미커밋 3" "r3 권한 복구 → K6 SKIP «미커밋 3»"
hasnt "$o3" "[HIL]" "r3 권한 복구 회차 경보 0(C 경보 반복 0)"
[ "$s3" = "$s1" ] && ok "r3 복구 전후 서명 같음" || bad "r3 복구 뒤 서명 바뀜: 1«${s1}» 3«${s3}»"

echo "== r844 r3 진짜 끊김 — gitdir 대상 삭제(등록은 그대로 · 폴더 .git 이 가리킨 사본을 지움) → 첫 회차 경보"
mk K7; mkdir -p "$T/hide2"; cp -R "$REPO/.git/worktrees/K7" "$T/hide2/K7"; echo "$REPO/.git" > "$T/hide2/K7/commondir"
printf 'gitdir: %s\n' "$T/hide2/K7" > "$REPO/.worktrees/K7/.git"
GIT_CEILING_DIRECTORIES="$REPO/.worktrees" git -C "$REPO/.worktrees/K7" rev-parse --git-dir >/dev/null 2>&1 && ok "r3 K7 준비(gitdir = $T/hide2/K7 · 연결됨)" || bad "r3 K7 준비 실패"
rm -rf "$T/hide2/K7"; rm -f "$T/clean/.shell-sig"; o="$(swp)"
has "$o" " K7 (git 연결 끊김) " "r3 gitdir 대상 삭제 → K7 끊김"
listed "$o" K7 && ok "r3 K7 첫 회차 경보" || bad "r3 K7 첫 회차 경보 없음 ← ${o:0:600}"

echo "== r844 r5 ⓑ DA r3 반례 1 — worktree list SHA 0(등록 gitdir HEAD 000) → ls-tree 실패 → 서명 유지 · 경보 0 · NOTE 1 · 복구 회차 경보 0"
mk Q; printf '%s\n' "$REPO/.worktrees/A/d3" > "$T/panes"; rm -f "$T/clean/.shell-sig"
o1="$(swp)"; s1="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
listed "$o1" Q && ok "r5 1회차 Q(껍데기 · 세션 0 · 미커밋 0) 경보" || bad "r5 1회차 Q 경보 없음 ← ${o1:0:600}"
chmod 000 "$REPO/.git/worktrees/Q/HEAD"
o2="$(swp)"; s2="$(cat "$T/clean/.shell-sig" 2>/dev/null)"; chmod 644 "$REPO/.git/worktrees/Q/HEAD"
has "$o2" "SKIP 껍데기 후보 Q — 판정 못 함(ls-tree 실패" "r5 SHA 0 → Q 판정 못 함(ls-tree 실패)"
hasnt "$o2" "[HIL]" "r5 판정 못 한 회차 경보 0(서명 그대로)"
[ "$(printf '%s\n' "$o2" | grep -c 'NOTE 껍데기 판정 못 함')" = 1 ] && ok "r5 NOTE 1줄" || bad "r5 NOTE 줄 수 $(printf '%s\n' "$o2" | grep -c 'NOTE 껍데기 판정 못 함')"
has "$o2" "(ls-tree 실패 1곳" "r5 NOTE 에 «(ls-tree 실패 1곳)»"
[ -n "$s1" ] && [ "$s2" = "$s1" ] && ok "r5 판정 못 한 회차 서명 = 1회차(지우지 않음)" || bad "r5 서명 바뀜: 1«${s1}» 2«${s2}»"
o3="$(swp)"; s3="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
hasnt "$o3" "[HIL]" "r5 복구 회차 경보 0(같은 경보 반복 0)"
[ "$s3" = "$s1" ] && ok "r5 복구 전후 서명 같음" || bad "r5 복구 뒤 서명 바뀜: 1«${s1}» 3«${s3}»"

# r5 ⓑ worktree list 자체 실패 — 가짜 git 이 그 호출만 rc≠0
mkdir -p "$T/wlgit"
cat > "$T/wlgit/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" worktree list "*) [ -n "\${FAKE_WL_FAIL:-}" ] && exit 128;; esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/wlgit/git"
printf 'keep-wl' > "$T/clean/.shell-sig"
o="$(swp PATH="$T/wlgit:$T/fake:$PATH" FAKE_WL_FAIL=1)"
hasnt "$o" "[HIL]" "r5 worktree list rc≠0 → 경보 0"
has "$o" "NOTE 껍데기 판정 생략 — worktree list 실패(rc=128" "r5 worktree list 실패 NOTE 1줄"
[ "$(cat "$T/clean/.shell-sig")" = keep-wl ] && ok "r5 worktree list 실패 = 서명 그대로" || bad "r5 worktree list 실패에 서명 바뀜: $(cat "$T/clean/.shell-sig")"

echo "== r844 r5 ⓐ DA r3 반례 2 — FT_WT_SCAN_ROOT 없이 다른 리포 GIT_* 4개 물려받음 → 원래 리포 판정 그대로 · 서명 유지"
printf '%s\n' "$REPO/.worktrees/A/d3" > "$T/panes"; rm -f "$T/clean/.shell-sig"
o0="$(swcd "$REPO/.worktrees/C")"; s0="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
has "$o0" "SKIP 껍데기 후보 B — 미커밋 2" "r5 env 없는 회차(자동 루트) B SKIP «미커밋 2»"
listed "$o0" C && ok "r5 env 없는 회차 C 경보" || bad "r5 env 없는 회차 C 없음 ← ${o0:0:600}"
rm -f "$T/clean/.shell-sig"
o="$(swcd "$REPO/.worktrees/C" GIT_DIR="$U/.git" GIT_WORK_TREE="$U" GIT_INDEX_FILE="$U/.git/index" GIT_COMMON_DIR="$U/.git")"; s="$(cat "$T/clean/.shell-sig" 2>/dev/null)"
has "$o" "SKIP 껍데기 후보 B — 미커밋 2" "r5 물려받은 GIT_* 4개 → 원래 리포 B SKIP «미커밋 2»"
listed "$o" C && ok "r5 물려받은 GIT_* → 원래 리포 C 경보" || bad "r5 물려받은 GIT_* 에 C 경보 없음(남의 리포를 봄) ← ${o:0:600}"
[ -n "$s0" ] && [ "$s" = "$s0" ] && ok "r5 물려받은 GIT_* 회차 서명 = env 없는 회차" || bad "r5 서명 다름: 0«${s0}» «${s}»"


[ -d "$REPO/.worktrees/A" ] && [ -d "$REPO/.worktrees/B" ] && [ -d "$REPO/.worktrees/C" ] && ok "경보는 읽기만 — 폴더 손 0" || bad "폴더가 사라짐"
[ "$(git -C "$REPO/.worktrees/B" status --porcelain --untracked-files=normal | grep -cvE '^( D|D ) ')" = 2 ] && ok "B 미커밋 그대로" || bad "B 미커밋 바뀜"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
