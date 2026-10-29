#!/usr/bin/env bash
# test_nano_close_base_sha_main_r1122.sh — 카드 r1122: R42 sha 길에서 base_sha 가 팀 가지(FT_NANO_FEAT)의 조상이 아니어도
#   origin/main 의 조상이면 랜딩 브랜치 = origin/main 으로 바꿔 통과 · 둘 다 아니면 REJECT 그대로.
# 계약↔시험: ⓐ R1·R2 INFO · REJECT 0 + 변이 1(분기 끔) · ⓑ R3 문구 그대로 + 변이 2(조상 검사 생략) · ⓒ R4~R7 기준판(분기 제거 사본)과 출력 동일 · ⓓ bin·kit cmp
# 임시 git 리포 + 가짜 원격 bare(fetch 대역 · url.insteadOf) + 가짜 tmux·gh(PATH 앞) — 실 리포·명부·tmux·gh·네트워크 0 · 자기 재호출 0 · 고정 sleep 0. 꼴 = test_nano_detached_base_r1120.sh
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
TRK="$HERE/../../harness/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

echo "== ⓓ bin·kit 같은 내용"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n" || bad "bash -n"
/bin/bash -n "$SRC/ft-nano-close.sh" && ok "/bin/bash 3.2 -n" || bad "/bin/bash 3.2 -n"
cmp -s "$SRC/ft-nano-close.sh" "$TRK/ft-nano-close.sh" && ok "사본 cmp" || bad "사본 불일치"

# ── 픽스처: FORK0 = 팀 가지 feat/t-main(뒤처짐) · main 은 S0 로 한 칸 감 · 나노는 S0 에서 · squash 착지는 원격 main 에만
URL='https://github.com/lptest/byz.git'
REPO="$T/repo"; BARE="$T/remote.git"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
echo base > "$REPO/a.txt"; GIT add a.txt; GIT commit -q -m init; FORK0="$(GIT rev-parse HEAD)"
TEAM=feat/t-main; GIT branch "${TEAM}" "$FORK0"
GIT checkout -q -b side; echo x > "$REPO/x.txt"; GIT add x.txt; GIT commit -q -m side; XSHA="$(GIT rev-parse HEAD)"; GIT checkout -q main
echo s0 > "$REPO/s0.txt"; GIT add s0.txt; GIT commit -q -m s0; S0="$(GIT rev-parse HEAD)"
git init -q --bare "$BARE"
GIT remote add origin "$URL"; GIT config "url.$BARE.insteadOf" "$URL"   # gh 식별자 = lptest/byz · 전송 = 로컬 bare
GIT push -q origin main
mkdir -p "$REPO/.fable-team" "$REPO/design/ops/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"; : > "$T/ledger.md"
echo ".worktree-info.json" >> "$REPO/.git/info/exclude"
SEAT='byz-ops-nano-bs#0'; CARD="$REPO/design/ops/indices/진행/bs.md"
NW="$REPO/.worktrees/bs"; BR="nano/bs"
GIT worktree add -q "$NW" -b "$BR" "$S0"
echo work > "$NW/work.txt"; git -C "$NW" add work.txt; git -C "$NW" -c user.email=t@t -c user.name=t commit -q -m work
SHA="$(git -C "$NW" rev-parse HEAD)"
# 원격 main 에 squash 착지(로컬 origin/main 추적 ref 는 S0 에 둔다 — 닫기의 fetch 가 옮겨야 착지가 보인다)
GIT worktree add -q --detach "$T/land" "$S0"
git -C "$T/land" merge --squash -q "$BR" >/dev/null 2>&1; git -C "$T/land" -c user.email=t@t -c user.name=t commit -q -m "squash land"
LANDSHA="$(git -C "$T/land" rev-parse HEAD)"; GIT update-ref refs/land "$LANDSHA"
git -C "$BARE" fetch -q "$REPO" refs/land:refs/heads/main   # 원격 main = 착지 커밋(push 0 · bare 가 끌어온다)
[ "$(git -C "$BARE" rev-parse main)" = "$LANDSHA" ] || { echo "FAIL 픽스처: 원격 main ≠ 착지"; exit 1; }

mkdir -p "$T/bin" "$T/fake"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
for f in ft-nano-close.sh ft-nano-evidence-check.sh ft-nano-cherry-gate.sh ft-nano-superseded-check.sh ft-nano-suspended-check.sh \
         ft-wt-sweep.sh ft-team-lib.sh ft-card-target-lib.sh ft_git_capped.py ft_teamset.py ft-sheet-events.sh ft_sheet_events.py ft_sheet_confirm.py \
         ft_sheet_key.py ft_board_env.py ft_board_mail.py ft-approval-equiv.sh ft_approval_equiv.py ft-nano-freshness.sh; do
  [ ! -e "$SRC/$f" ] || cp "$SRC/$f" "$T/bin/"
done
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    case "$*" in
      *pane_current_path*) if [ -s "$FAKE_PANE_CWDS" ]; then cat "$FAKE_PANE_CWDS"; else echo "no server running on /tmp/fake"; exit 1; fi;;
      *) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
    esac;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
cat > "$T/fake/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_LOG"
cat "$FAKE_GH_JSON"
EOF
chmod +x "$T/bin/"* "$T/fake/"*
printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$LANDSHA" "$SHA" > "$T/gh.json"
# 기준판 = r1122 분기를 뺀 사본(변이 1 과 같은 자리) · 변이 2 = 조상 검사 생략
mutate() {  # mutate <out> <old> <new>
  python3 - "$T/bin/ft-nano-close.sh" "$@" <<'PY'
import sys
src, out, a, b = sys.argv[1:5]; s = open(src, encoding='utf-8').read()
assert s.count(a) == 1, f"변이 자리 {s.count(a)}곳: {a}"
open(out, 'w', encoding='utf-8').write(s.replace(a, b))
PY
}
mutate "$T/bin/base-close.sh" 'elif [ "$_FEAT" != origin/main ] && _fetch_remote_feat origin/main' 'elif false && _fetch_remote_feat origin/main' || bad "기준판 사본 실패"
mutate "$T/bin/mut2-close.sh" $' \\\n       && git -C "$SEAT_REPO" merge-base --is-ancestor "$_BASE_SHA" refs/remotes/origin/main 2>/dev/null; then' '; then' || bad "변이 2 사본 실패"

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" \
  FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" FT_NANO_FEAT="${TEAM}" "$@" 2>&1 ); }
setinfo() {  # setinfo <base> [base_sha | -(칸 없음)]
  if [ "${2:-}" = - ]; then printf '{"branch":"%s","base":"%s","purpose":"t"}\n' "$BR" "$1" > "$NW/.worktree-info.json"
  else printf '{"branch":"%s","base":"%s","base_sha":"%s","purpose":"t"}\n' "$BR" "$1" "${2:-$S0}" > "$NW/.worktree-info.json"; fi
}
setup() {
  printf '{"%s":{"role":"nano","index":"design/ops/indices/진행/bs.md"}}\n' "$SEAT" > "$REPO/.fable-team/seats-ops.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pane-cwds"; printf '%s' "$NW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ghlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean"
  git -C "$REPO" update-ref refs/remotes/origin/main "$S0"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
}
close() { local cl="$1"; shift; run FT_NANO_PREFIX=byz-ops-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-ops.json" FT_NANO_LEDGER="$T/ledger.md" \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "$cl" "$SEAT" --result "$T/result.md" --recv 1 --wt "$NW" "$@"; }
closeb() { local cl="$1"; shift; close "$cl" --branch "$BR" "$@"; }   # 표준 닫기(--landed-pr 는 --branch 와 같이 못 쓴다)
noside() {  # noside <이름> — REJECT 뒤 부작용 0
  [ -z "$(cat "$T/tlog")" ] && ok "  └ $1 kill·태그 해제 0" || bad "$1 REJECT 인데 tmux 변경: $(cat "$T/tlog")"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-ops.json" >/dev/null && ok "  └ $1 명부 그대로" || bad "$1 REJECT 인데 명부 삭제"
}
NEWL="INFO base sha ${S0:0:9} → 랜딩 브랜치 origin/main(팀 가지 ${TEAM} 뒤처짐"
OLDREJ="이고 ${TEAM} 의 조상이 아니다 — FT_NANO_FEAT=<랜딩 브랜치> 로 다시"
r1_check() {  # r1_check <close 파일> <info base> → 0 = 통과(INFO 줄 · REJECT 0 · CLOSED · 게이트 기준 origin/main)
  setinfo "$2"; setup; local out rc; out="$(closeb "$1")"; rc=$?
  [ "$rc" -eq 0 ] || { echo "  rc=$rc ← ${out:0:900}"; return 1; }
  case "$out" in *"$NEWL"*) ;; *) echo "  INFO 줄 없음"; return 1;; esac
  case "$out" in *"$OLDREJ"*) echo "  옛 REJECT 있음"; return 1;; esac
  case "$out" in *"CLOSED $SEAT"*) ;; *) echo "  CLOSED 없음"; return 1;; esac
  return 0
}
r3_check() {  # r3_check <close 파일> → 0 = 통과(REJECT 문구 그대로 · 새 INFO 0 · 닫기 0)
  setinfo "$XSHA"; setup; local out rc; out="$(closeb "$1")"; rc=$?
  [ "$rc" -eq 1 ] || { echo "  rc=$rc"; return 1; }
  case "$out" in *"base 가 sha ${XSHA:0:9} $OLDREJ"*) ;; *) echo "  REJECT 문구 없음 ← ${out:0:600}"; return 1;; esac
  case "$out" in *"랜딩 브랜치 origin/main(팀 가지"*|*"CLOSED $SEAT"*) echo "  새 INFO·CLOSED 있음"; return 1;; esac
  return 0
}
same_as_base() {  # same_as_base <이름> <info base> [base_sha|-] [-- close 인자…] — 새판·기준판 출력 동일(ⓒ)
  local nm="$1" b="$2" s="${3:-}"; shift 3 2>/dev/null || shift $#; [ "${1:-}" != -- ] || shift
  local o1 o2 r1 r2
  setinfo "$b" ${s:+"$s"}; setup; o1="$(closeb "$T/bin/ft-nano-close.sh" "$@")"; r1=$?
  setinfo "$b" ${s:+"$s"}; setup; o2="$(closeb "$T/bin/base-close.sh" "$@")"; r2=$?
  o1="$(printf '%s\n' "$o1" | sed -E 's/^(STEP .*) \+[0-9]+s$/\1 +Ns/')"; o2="$(printf '%s\n' "$o2" | sed -E 's/^(STEP .*) \+[0-9]+s$/\1 +Ns/')"   # 단계 초는 매번 다르다
  [ "$r1" = "$r2" ] && [ "$o1" = "$o2" ] && ok "$nm 출력·rc($r1) 기준판과 같음" || bad "$nm 기준판과 다름 rc $r1/$r2$(printf '\n%s' "$(diff <(printf '%s\n' "$o2") <(printf '%s\n' "$o1") | head -8)")"
  LAST_OUT="$o1"; LAST_RC="$r1"
}

echo "== R1 ops 꼴: base «HEAD» + base_sha S0(∈ origin/main · ∉ ${TEAM}) → 랜딩 브랜치 origin/main · 닫힘"
o="$(r1_check "$T/bin/ft-nano-close.sh" HEAD)" && ok "R1 INFO · REJECT 0 · CLOSED" || bad "R1$(printf '\n%s' "$o")"
echo "== R2 base 40hex(R42) 같은 꼴 → R1 과 같음"
o="$(r1_check "$T/bin/ft-nano-close.sh" "$S0")" && ok "R2 INFO · REJECT 0 · CLOSED" || bad "R2$(printf '\n%s' "$o")"
echo "== 변이 1: 분기 끔(=기준판) → R1 FAIL 이어야 한다"
r1_check "$T/bin/base-close.sh" HEAD >/dev/null && bad "변이 1 이 R1 을 통과 — 시험이 분기를 못 본다" || ok "변이 1 → R1 FAIL(잡힘)"

echo "== R3 base_sha 가 origin/main·${TEAM} 둘 다 조상 아님 → REJECT 문구 그대로 · 닫기 0"
o="$(r3_check "$T/bin/ft-nano-close.sh")" && ok "R3 REJECT 그대로" || bad "R3$(printf '\n%s' "$o")"
noside R3
echo "== 변이 2: origin/main 조상 검사 생략 → R3 FAIL 이어야 한다"
r3_check "$T/bin/mut2-close.sh" >/dev/null && bad "변이 2 가 R3 을 통과 — 시험이 조상 검사를 못 본다" || ok "변이 2 → R3 FAIL(잡힘)"

echo "== R4 base_sha ∈ ${TEAM} → 지금 INFO «랜딩 브랜치 ${TEAM}» 그대로"
same_as_base R4 "$FORK0" ""
has "$LAST_OUT" "INFO base sha ${FORK0:0:9} → 랜딩 브랜치 ${TEAM}" "  └ R4 INFO 랜딩 브랜치 ${TEAM}"
hasnt "$LAST_OUT" "랜딩 브랜치 origin/main(팀 가지" "  └ R4 새 INFO 없음"
echo "== R5 base 가 가지 이름(${TEAM}) → 이 분기 안 탐 · 출력 그대로"
same_as_base R5 "${TEAM}" ""
hasnt "$LAST_OUT" "INFO base sha" "  └ R5 sha 줄 없음"
echo "== R6 --landed-pr 로 닫는 R1 꼴 → LANDED-PR-OK 길 그대로 + R1 INFO 줄"
lpcard() { printf -- '- 착지: %s\n' "$LANDSHA" >> "$CARD"; }   # --landed-pr 카드 꼴(test_nano_close_landed_pr_root_r1053.sh)
setinfo HEAD; setup; lpcard; out="$(close "$T/bin/ft-nano-close.sh" --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "R6 rc=0" || bad "R6 rc=$rc ← ${out:0:900}"
has "$out" "LANDED-PR-OK #363 merged=${LANDSHA:0:9} state=MERGED head=${SHA:0:9}" "  └ R6 LANDED-PR-OK"
has "$out" "$NEWL" "  └ R6 R1 INFO 줄"
hasnt "$out" "$OLDREJ" "  └ R6 옛 REJECT 없음"
setinfo HEAD; setup; lpcard; bout="$(close "$T/bin/base-close.sh" --landed-pr 363)"
has "$bout" "LANDED-PR-OK #363 merged=${LANDSHA:0:9} state=MERGED head=${SHA:0:9}" "  └ R6 기준판도 같은 LANDED-PR-OK 줄(길 그대로)"
echo "== R7 r1120 «HEAD» + base_sha 없음 → 판정 불가 REJECT 그대로"
same_as_base R7 HEAD -
has "$LAST_OUT" "base_sha(없음)를 $REPO 에서 못 푼다 — 판정 불가" "  └ R7 판정 불가 REJECT"
[ "$LAST_RC" -eq 1 ] && ok "  └ R7 rc=1" || bad "R7 rc=$LAST_RC"
noside R7

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
