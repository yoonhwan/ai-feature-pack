#!/usr/bin/env bash
# test_wt_sweep_budget_replan_r535.sh — 카드 r535: 닫힌 나노 정리 계획이 밀리지 않게.
#   ⓐ한 pass = 시간 상한(FT_WT_SWEEP_BUDGET_SEC) 안에서 막히지 않은 계획 여러 건(옛 판 = 1건) ⓑcwd WAIT 는 건너뛰고 뒤 계획 계속
#   ⓒ옛 판 계획 → 같은 좌석·같은 WT 로 재생성(.replanned) 뒤 실행 · 좌석 세션이 살아 있으면 재생성 0(WAIT) ⓓ재생성 불가 → .stale + 사유
#   ⓔ지운 폴더 크기(du 상한) → .done·요약·wt-sweep.log freed_kb ⓕ등록 없는 폴더 → wt-orphans.tsv 목록만 ⓖ.hil 계획 수 → 요약만
# 임시 git 리포 + 임시 워크트리 + 가짜 tmux·lsof·du·baton 만 — 실 리포·워크트리·baton·tmux·mbox 0 · 외부 호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${WT_TEST_SRC:-$HERE/../../harness/kit/fable-team/bin}"   # 고치기 전 코드로 돌려 FAIL 을 기록할 때만 덮어쓴다
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
nfiles() { ls "$1"/$2 2>/dev/null | wc -l | tr -d ' '; }
isf() { [ -f "$1" ] && echo yes || echo no; }

mkdir -p "$T/bin" "$T/fake" "$T/hil"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-hil.sh" "$T/bin/"
bash -n "$T/bin/ft-wt-sweep.sh" && bash -n "$T/bin/ft-nano-close.sh" && ok "bash -n 2종" || bad "bash -n"
: > "$T/sessions"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  ls) if [ -s "$FAKE_SESSIONS" ]; then cat "$FAKE_SESSIONS"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  *) exit 1;;
esac
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/fake/lsof"
printf '#!/usr/bin/env bash\nprintf "%%s\\t%%s\\n" "${FAKE_KB:-1234}" "$2"\n' > "$T/fake/du"
printf '#!/usr/bin/env bash\nsleep 10\nprintf "9\\t%%s\\n" "$2"\n' > "$T/fake/du-slow"
chmod +x "$T/bin/"* "$T/fake/"*

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
printf '.worktree-info.json\n' > "$REPO/.gitignore"
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
GIT add .gitignore && GIT commit -q -m init
printf '#!/usr/bin/env bash\ngit -C "%s" worktree remove --force "$2"\n' "$REPO" > "$T/fake/baton"; chmod +x "$T/fake/baton"

# swp <계획 디렉터리> [env…] — 리포 밖 cwd · 격리 계획 디렉터리 · 가짜 도구
swp() { local d="$1"; shift; ( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" BATON_BIN="$T/fake/baton" FT_WT_CLEAN_DIR="$d" FT_WT_PLAN_TIMEOUT=20 \
  FT_WT_RESUME_GRACE=0 FT_TMUX_BIN="$T/fake/tmux" FT_LSOF_BIN="$T/fake/lsof" FT_DU_BIN="$T/fake/du" FAKE_SESSIONS="$T/sessions" \
  HIL_DIR="$T/hil" HIL_CLIP=0 "$@" bash "$T/bin/ft-wt-sweep.sh" 2>&1 ); }
stub() { mkdir -p "$1"; printf '%s\n' "$3" > "$1/$2.sh"; }
gone() { local _; for _ in $(seq 1 60); do [ ! -e "$1" ] && return 0; sleep 0.25; done; return 1; }

echo "== ⓐ 한 pass = 시간 상한 안의 막히지 않은 계획 여러 건"
D="$T/a"; for s in a1 a2 a3 a4 a5; do stub "$D" "$s#0" 'echo cleaned'; done
o="$(swp "$D")"
chk "ⓐ 막힘 없는 계획 5 → 한 pass 에 .done 5" "$(nfiles "$D" '*.sh.done')" 5
hasnt "$o" "이월" "ⓐ 이월 0"
D="$T/a2"; for s in b1 b2 b3 b4; do stub "$D" "$s#0" 'sleep 1; echo cleaned'; done
o="$(swp "$D" FT_WT_SWEEP_BUDGET_SEC=2)"; n="$(nfiles "$D" '*.sh.done')"
if [ "$n" -ge 1 ] && [ "$n" -lt 4 ]; then ok "ⓐ 시간 상한 2s · 계획 1s×4 → 일부만(.done=$n)"; else bad "ⓐ 시간 상한이 안 먹음(.done=$n)"; fi
has "$o" "이월" "ⓐ 상한 넘긴 나머지 = 이월"
D="$T/a3"; for s in c1 c2 c3; do stub "$D" "$s#0" 'echo cleaned'; done
o="$(swp "$D" FT_WT_SWEEP_MAX=2)"
chk "ⓐ FT_WT_SWEEP_MAX=2 명시 → 건수 상한 2" "$(nfiles "$D" '*.sh.done')" 2
has "$o" "이월 1" "ⓐ 건수 상한 나머지 이월 1"

echo "== ⓑ cwd 보유(WAIT) 계획은 건너뛰고 뒤 계획 계속"
D="$T/b"; stub "$D" 'a0#0' 'echo "skipped:cwd 보유 프로세스 1개"'; for s in b1 b2 b3; do stub "$D" "$s#0" 'echo cleaned'; done
o="$(swp "$D")"
chk "ⓑ 뒤 계획 3 → .done 3" "$(nfiles "$D" '*.sh.done')" 3
chk "ⓑ WAIT 계획 제자리" "$(isf "$D/a0#0.sh")" yes
has "$o" "WAIT a0#0" "ⓑ WAIT 1줄"
hasnt "$o" "이월" "ⓑ 이월 0(머리 막힘 0)"

# 옛 판 생성기 계획 — 굽힌 값 줄 + 옛 몸통(돌면 «OLD BODY RAN»)
SEAT='byz-harness-nano-rp#0'; LEDGER="$T/ledger.md"
oldplan() { # <디렉터리> <좌석> <키> <WT>
  mkdir -p "$1"
  { printf '#!/bin/bash\n# wt-clean 계획 — ft-nano-close.sh 가 2026-10-19 00:00 에 생성. (옛 판)\n# plan-ver: %s\n' 0000000000000000000000000000000000000000
    printf 'SEAT=%q; KEY=%q; WT=%q; PREFIX=%q; LEDGER=%q; PLAN=%q; FT_NANO_WIP=%q; NAMED_BR=%q; SWEEPER=%q; GEN=%q; PLANVER=%q; PLAN_ONLY=%q; LANDCHK=%q; MAINREF=%q; ROOTR=%q\n' \
      "$2" "$3" "$4" byz-harness-nano- "$LEDGER" "$1/$2.sh" 0 '' /old/ft-wt-sweep.sh /old/ft-nano-close.sh 0000 0 /old/ft-landed-check.sh '' "$REPO"
    printf 'echo "OLD BODY RAN"; echo cleaned\n'; } > "$1/$2.sh"
}
mkwt() { # <이름> <가지>
  GIT worktree add -q "$REPO/.worktrees/$1" -b "$2"
  echo x > "$REPO/.worktrees/$1/f.txt"; printf '{"branch":"%s"}\n' "$2" > "$REPO/.worktrees/$1/.worktree-info.json"
  git -C "$REPO/.worktrees/$1" add -A && git -C "$REPO/.worktrees/$1" -c user.email=t@t -c user.name=t commit -q -m w
}
LIVEVER="$(git hash-object "$T/bin/ft-nano-close.sh")"

echo "== ⓒ 옛 판 계획 → 같은 좌석·같은 WT 로 재생성 → 같은 pass 에 실행 · 좌석 살아 있으면 재생성 0"
mkwt v65-rp nano/rp; NW="$REPO/.worktrees/v65-rp"
printf -- '- `%s` 닫힘(ft-nano-close) · wt=planned\n' "$SEAT" > "$LEDGER"
D="$T/c"; oldplan "$D" "$SEAT" rp "$NW"
printf '%s\n' "$SEAT" > "$T/sessions"
o="$(swp "$D")"
has "$o" "WAIT $SEAT" "ⓒ 좌석 세션 살아 있음 → WAIT"
chk "ⓒ  └ 계획 제자리(옛 판 그대로)" "$(grep -c '^# plan-ver: 0000' "$D/$SEAT.sh" 2>/dev/null)" 1
chk "ⓒ  └ .replanned 0" "$(isf "$D/$SEAT.sh.replanned")" no
chk "ⓒ  └ .stale 0" "$(isf "$D/$SEAT.sh.stale")" no
: > "$T/sessions"
o="$(swp "$D")"
has "$o" "REPLAN $SEAT" "ⓒ 좌석 없음 → REPLAN 1줄"
chk "ⓒ  └ 옛 계획 .replanned 로 보존" "$(grep -c 'OLD BODY RAN' "$D/$SEAT.sh.replanned" 2>/dev/null)" 1
has "$o" "OK   $SEAT wt=cleaned" "ⓒ  └ 새 계획이 같은 pass 에 실행 → cleaned"
hasnt "$o$(cat "$D/$SEAT.sh.log" 2>/dev/null)" "OLD BODY RAN" "ⓒ  └ 옛 몸통 실행 0"
chk "ⓒ  └ 새 계획 plan-ver = 라이브 생성기" "$(grep -c "^# plan-ver: $LIVEVER\$" "$D/$SEAT.sh.done" 2>/dev/null)" 1
has "$(grep '^SEAT=' "$D/$SEAT.sh.done")" "WT=$NW" "ⓒ  └ 같은 WT 를 굽힘"
has "$o" "replanned 1" "ⓒ  └ 요약 replanned 1"
gone "$D/$SEAT.sh.deleting"; [ ! -e "$NW" ] && ok "ⓒ  └ 원래 경로 정리됨" || bad "ⓒ 원래 경로 남음"
GIT rev-parse --verify -q refs/heads/nano/rp >/dev/null && ok "ⓒ  └ 가지 nano/rp 보존" || bad "ⓒ 가지가 사라짐"

echo "== ⓓ 재생성 불가 → .stale + 사유 1줄 (실작업물 미커밋은 새 계획의 가드가 HIL)"
D="$T/d1"; oldplan "$D" 'byz-harness-nano-nw#0' nw "$REPO/.worktrees/v65-nowhere"
o="$(swp "$D")"
has "$o" "STALE byz-harness-nano-nw#0" "ⓓ WT 없음 → STALE"
has "$o" "WT 없음" "ⓓ  └ 사유 1줄"
chk "ⓓ  └ .stale 이동" "$(isf "$D/byz-harness-nano-nw#0.sh.stale")" yes
mkwt v65-ft feat/ft
D="$T/d2"; oldplan "$D" 'byz-harness-nano-ft#0' ft "$REPO/.worktrees/v65-ft"
o="$(swp "$D")"
has "$o" "STALE byz-harness-nano-ft#0" "ⓓ 가지 nano/* 아님 → STALE"
has "$o" "nano/* 아님" "ⓓ  └ 사유 1줄"
[ -d "$REPO/.worktrees/v65-ft" ] && ok "ⓓ  └ 워크트리 그대로" || bad "ⓓ 워크트리가 사라짐"
mkwt v65-dt nano/dt; echo changed >> "$REPO/.worktrees/v65-dt/f.txt"
printf -- '- `%s` 닫힘(ft-nano-close) · wt=planned\n' 'byz-harness-nano-dt#0' >> "$LEDGER"
D="$T/d3"; oldplan "$D" 'byz-harness-nano-dt#0' dt "$REPO/.worktrees/v65-dt"
o="$(swp "$D")"
has "$o" "REPLAN byz-harness-nano-dt#0" "ⓓ 미커밋 → 재생성은 됨"
has "$o" "[HIL] seat=byz-harness-nano-dt#0 실작업물 미커밋" "ⓓ  └ 새 계획 가드가 미커밋을 HIL 로(정리 0)"
[ -d "$REPO/.worktrees/v65-dt" ] && ok "ⓓ  └ 워크트리 그대로" || bad "ⓓ 워크트리가 사라짐"

echo "== ⓔ 지운 폴더 크기 — du 상한 · .done·요약·wt-sweep.log freed_kb"
mkdir -p "$T/e-wt1" "$T/e-wt2"; D="$T/e/wt-clean"
stub "$D" 'e1#0' "SEAT=e1#0; KEY=e1; WT=$T/e-wt1"$'\n''echo cleaned'
o="$(swp "$D")"
chk "ⓔ .done 에 freed_kb=1234" "$(grep -c '^# freed_kb=1234$' "$D/e1#0.sh.done" 2>/dev/null)" 1
has "$o" "freed_kb 1234" "ⓔ 요약 freed_kb 1234"
has "$(cat "$T/e/wt-sweep.log" 2>/dev/null)" "freed seat=e1#0 kb=1234" "ⓔ wt-sweep.log 폴더별 KB 줄"
has "$(grep ' pass ' "$T/e/wt-sweep.log" 2>/dev/null | tail -1)" "freed_kb=1234" "ⓔ wt-sweep.log pass 줄 끝 freed_kb"
stub "$D" 'e2#0' "SEAT=e2#0; KEY=e2; WT=$T/e-wt2"$'\n''echo cleaned'
s0="$(date +%s)"; o="$(swp "$D" FT_DU_BIN="$T/fake/du-slow" FT_WT_DU_SEC=1)"; el=$(( $(date +%s) - s0 ))
chk "ⓔ du 상한 넘김 → freed_kb=?" "$(grep -c '^# freed_kb=?$' "$D/e2#0.sh.done" 2>/dev/null)" 1
[ "$el" -lt 8 ] && ok "ⓔ  └ 느린 du 를 상한에서 끊음(${el}s)" || bad "ⓔ du 상한이 안 먹음(${el}s)"
has "$(cat "$T/e/wt-sweep.log")" "freed seat=e2#0 kb=?" "ⓔ  └ 로그 kb=?"
mkdir -p "$REPO/.fable-team/state/wt-clean"; stub "$REPO/.fable-team/state/wt-clean" 'e3#0' "SEAT=e3#0; KEY=e3; WT=$T/e-wt1"$'\n''echo cleaned'
( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FT_ROOT="$REPO" FT_WT_ARCHIVE=0 FT_MBOX_SH=/usr/bin/true FT_DU_BIN="$T/fake/du" FAKE_KB=55 \
  HIL_DIR="$T/hil" HIL_CLIP=0 bash "$T/bin/ft-wt-sweep.sh" --launchd >/dev/null 2>&1 )
has "$(grep ' rc=' "$REPO/.fable-team/state/wt-sweep.log" 2>/dev/null | tail -1)" "freed_kb=55" "ⓔ --launchd 줄에 freed_kb"
has "$(grep ' rc=' "$REPO/.fable-team/state/wt-sweep.log" 2>/dev/null | tail -1)" "replanned=0" "ⓔ --launchd 줄에 replanned"

echo "== ⓕ 등록 없는 폴더 → wt-orphans.tsv 목록만 · 삭제 0"
mkdir -p "$REPO/.worktrees/orphan1/sub"; echo y > "$REPO/.worktrees/orphan1/sub/y"
D="$T/f/wt-clean"; mkdir -p "$D"
o="$(swp "$D" FT_WT_SCAN_ROOT="$REPO" FT_WT_ORPHAN_SCAN_SEC=0 FAKE_KB=77)"
TSV="$T/f/wt-orphans.tsv"
chk "ⓕ 목록에 orphan1 1줄(크기 77)" "$(grep -c "^orphan1	.*	77\$" "$TSV" 2>/dev/null)" 1
chk "ⓕ 등록 워크트리는 목록 밖" "$(grep -cE '^v65-(ft|dt)	' "$TSV" 2>/dev/null)" 0
has "$o" "orphans 1" "ⓕ 요약 orphans 1"
[ -f "$REPO/.worktrees/orphan1/sub/y" ] && ok "ⓕ  └ 폴더 그대로(삭제 0)" || bad "ⓕ 폴더가 지워짐"

echo "== ⓖ .hil 계획 → 요약 수만 · 처리 0"
D="$T/g"; stub "$D" 'h1#0' 'echo cleaned'; mv "$D/h1#0.sh" "$D/h1#0.sh.hil"; stub "$D" 'h2#0' 'echo cleaned'; mv "$D/h2#0.sh" "$D/h2#0.sh.hil"
o="$(swp "$D")"
has "$o" "hil_files 2" "ⓖ 요약 hil_files 2"
chk "ⓖ  └ .hil 그대로 2 · .done 0" "$(nfiles "$D" '*.sh.hil'):$(nfiles "$D" '*.done')" "2:0"

echo "== 위생"
grep -nE 'branch +-[dD]|update-ref +-d' "$SRC/ft-wt-sweep.sh" >/dev/null && bad "sweep 에 브랜치 삭제 코드" || ok "sweep 에 브랜치 삭제 코드 0"
[ "$(git -C "$HERE/../.." config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare 이상"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
