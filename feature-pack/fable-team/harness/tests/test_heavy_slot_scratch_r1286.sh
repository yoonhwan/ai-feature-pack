#!/usr/bin/env bash
# test_heavy_slot_scratch_r1286.sh — r1286 scratch-repo(사본 만들기·--done·--sweep) + ft-disk-alarm + 상속 반례
#   R13a 자리 둘 다 참 → 만들기 rc5 · «사본 0» · 폴더·등록 0 / --done rc5 · 사본 그대로
#   R13b --sweep: 바깥 쥔 쪽 1 → 사본 3개 모두 삭제 · 항목 사이에 바깥 대기자가 slot-2 를 잡음(항목마다 풂) · 끝 줄 / 바깥 쥔 쪽 2 → rc5 · «자리 대기 초과» · 끝 줄 · 사본 유지
#   R13c ft-disk-alarm: sweep 스텁 rc5 → swept 그대로 · 쪽지 «[사본 정리 미완]» / rc0 → swept = NOW
#   R5b 가짜 git worktree add 가 표식 기다림 → scratch-repo 셸만 SIGKILL → 계속 쥠 · 가짜 git 끝나면 풀림
#   변이 4(sweep 항목마다 안 풂) → R13b FAIL · 변이 6(scratch rc5→0) → R13a FAIL · 변이 11(disk-alarm 이 rc 무시) → R13c FAIL
#   실 tmux·실 원격 0 · 자기 재호출 0 · 고정 sleep 0(표식 폴링) · 시험 1개 상한 70초
set -uo pipefail
[ -z "${FT_R1286S_REENTRY:-}" ] || { echo "FAIL 재진입"; exit 1; }
export FT_R1286S_REENTRY=1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; SCR="$BIN/ft-scratch-repo.sh"; DISK="$BIN/ft-disk-alarm.sh"; LIBD="$BIN/ft-heavy-slot-lib.sh"
fail=0; BAD=""; BG=()
T="$(mktemp -d "${TMPDIR:-/tmp}/r1286s.XXXXXX")"
trap 'for p in ${BG[@]+"${BG[@]}"}; do kill -9 "$p" 2>/dev/null; done; rm -rf "$T"' EXIT
bad(){ echo "FAIL $1" >&2; fail=$((fail+1)); BAD="$BAD $1"; }
run(){ local n="$1" f="$2"; if "$f"; then return 0; fi; bad "$n"; return 1; }
runv(){ local n="$1" f="$2"; if "$f"; then bad "변이 $n — $f 통과"; else echo "변이 $n → $f FAIL(정상)"; fi; }
waitfor(){ local i; for i in $(seq 1 300); do [ -e "$1" ] && return 0; command sleep 0.03; done; return 1; }
probe(){ local f="$1" fd=9; { exec 9>>"$f"; } 2>/dev/null || return 2   # r1338: 고정 fd(bash 3.2)
  perl -MFcntl=:flock -e 'open(my $h, ">&=", $ARGV[0]) or exit 3; flock($h, LOCK_EX|LOCK_NB) or exit 1;' "$fd" 2>/dev/null
  local rc=$?; exec 9>&-; return $rc; }
hold(){ # <자리폴더> <이름> → 자리를 쥔 holder(해제는 stop.<이름>)
  local d="$1" n="$2"; mkdir -p "$d"
  cat > "$T/hold-$n.sh" <<EOF
#!/usr/bin/env bash
export FT_HEAVY_DIR="$d"
. "$LIBD"
hs_acquire "$n" 0 >/dev/null || exit 1
trap 'hs_release' EXIT
touch "$T/held.$n"
while [ ! -f "$T/stop.$n" ]; do command sleep 0.03; done
EOF
  rm -f "$T/held.$n" "$T/stop.$n"; bash "$T/hold-$n.sh" 2>/dev/null & BG+=($!); waitfor "$T/held.$n"; }
rel(){ touch "$T/stop.$1"; }
# ── scratch-repo 준비 ────────────────────────────────────────────
S="$T/s"; mkdir -p "$S/src" "$S/R/.fable-team/state" "$S/scr" "$S/tmpd" "$S/bin"
git -C "$S/src" init -q; echo a > "$S/src/a.txt"; git -C "$S/src" add a.txt; git -C "$S/src" -c user.name=t -c user.email=t@t commit -q -m c1
SHA="$(git -C "$S/src" rev-parse HEAD)"
printf '#!/bin/sh\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$S" > "$S/bin/tmux"; chmod 755 "$S/bin/tmux"
printf 'live-owner\n' > "$S/sessions"
sc(){ out="$(env PATH="$S/bin:$PATH" FT_RES_ROOT="$S/R" FT_SCRATCH_DIR="$S/scr" TMPDIR="$S/tmpd" FT_SCRATCH_OWNER="${OWN:-live-owner}" FT_HEAVY_DIR="${HSD:-$S/R/.fable-team/state/heavy-slots}" FT_HEAVY_WAIT_S="${HSW:-2}" bash "$SCR" "$@" 2>&1)"; rc=$?; }
TSV="$S/R/.fable-team/state/scratch-repos.tsv"
age_reg(){ awk -F'\t' -v p="$1" -v t="$(( $(date +%s) - $2 ))" 'BEGIN{OFS="\t"} $1==p{$3=t} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"; }
R13a(){ HSD="$S/R/.fable-team/state/heavy-slots"; hold "$HSD" b1 || return 1; hold "$HSD" b2 || return 1
  sc "$SHA" --repo "$S/src"; local r=$rc o="$out"; rel b1; rel b2
  [ "$r" = 5 ] || { echo "  R13a rc=$r" >&2; return 1; }
  case "$o" in *"사본 0"*) ;; *) return 1;; esac
  [ ! -s "$TSV" ] && [ -z "$(ls "$S/scr" 2>/dev/null)" ] || return 1
  sc "$SHA" --repo "$S/src" >/dev/null; local P="$out"; [ -d "$P" ] || return 1
  hold "$HSD" b1 || return 1; hold "$HSD" b2 || return 1
  sc --done "$P"; local rd=$rc; rel b1; rel b2
  [ "$rd" = 5 ] && [ -d "$P" ] || { echo "  R13a done rc=$rd" >&2; return 1; }
  OWN=live-owner sc --done "$P" >/dev/null; }
R13a_min(){ HSD="$S/R/.fable-team/state/heavy-slots"; hold "$HSD" b1 || return 1; hold "$HSD" b2 || return 1
  sc "$SHA" --repo "$S/src"; local r=$rc; rel b1; rel b2; [ "$r" = 5 ]; }
R13b(){ # ⓑ sweep 3개 · 자리 1개 쥔 채
  local i P; for i in 1 2 3; do OWN=gone-$i sc "$SHA" --repo "$S/src" >/dev/null; age_reg "$out" 90000; done
  mkdir -p "$S/R/.fable-team/state"; date +%s > "$S/R/.fable-team/state/scratch-sweep.armed"
  rm -rf "$S/scr"; mkdir -p "$S/scr"
  for i in 1 2 3; do sc "$SHA" --repo "$S/src" >/dev/null; age_reg "$out" 90000; done   # 주인 살아 있음 → sweep 대상 아님
  OWN=gone-x sc "$SHA" --repo "$S/src" >/dev/null; local G1="$out"; age_reg "$G1" 90000
  OWN=gone-y sc "$SHA" --repo "$S/src" >/dev/null; local G2="$out"; age_reg "$G2" 90000
  OWN=gone-z sc "$SHA" --repo "$S/src" >/dev/null; local G3="$out"; age_reg "$G3" 90000
  HSD="$S/R/.fable-team/state/heavy-slots"; hold "$HSD" c1 || return 1
  # 항목 사이에 slot-2 를 잡는 바깥 대기자 — 표식 남기고 바로 놓는다
  ( for k in $(seq 1 200); do
      if FT_HEAVY_DIR="$HSD" bash -c '. "$0"; hs_acquire waiter 0 >/dev/null' "$LIBD" 2>/dev/null; then echo hit >> "$T/waiter.log"; break; fi
      command sleep 0.02; done ) & BG+=($!)
  sc --sweep; local r=$rc o="$out"; rel c1
  [ "$r" = 0 ] || { echo "  R13b rc=$r out=${o:0:200}" >&2; return 1; }
  [ ! -d "$G1" ] && [ ! -d "$G2" ] && [ ! -d "$G3" ] || { echo "  R13b 삭제 안 됨" >&2; return 1; }
  grep -q '^swept=' <<<"$o" || return 1
  waitfor "$T/waiter.log" || { echo "  R13b 항목 사이 대기자 없음(항목마다 안 풀었나)" >&2; return 1; }
  # 자리 둘 다 참 → rc5 · 남은 항목 0
  OWN=gone-w1 sc "$SHA" --repo "$S/src" >/dev/null; local H1="$out"; age_reg "$H1" 90000
  hold "$HSD" d1 || return 1; hold "$HSD" d2 || return 1
  sc --sweep; local r2=$rc o2="$out"; rel d1; rel d2
  [ "$r2" = 5 ] || { echo "  R13b rc2=$r2" >&2; return 1; }
  case "$o2" in *"자리 대기 초과"*) ;; *) return 1;; esac
  grep -q '^swept=' <<<"$o2" || return 1
  [ -d "$H1" ] || return 1; }
R13c(){ # ⓒ ft-disk-alarm 이 sweep rc 5 를 읽는다
  local st="$S/R/.fable-team/state/disk-alarm.state" mb="$T/mbox.sh" sw="$T/sweep-stub.sh" pl="$T/planner.json"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/mbox.log"\n' "$T" > "$mb"; chmod +x "$mb"
  printf '{"_hil_route":"byz-planner-master-claude#206"}\n' > "$pl"
  local now; now="$(date +%s)"
  printf 'last=0\nstage=ok\nsent=0\nswept=%s\nreaped=0\nroutefail=0\nwtscan=0\nspcensus=0\nacc=0\n' "$((now-90000))" > "$st"
  printf '#!/usr/bin/env bash\necho "rc5-stub-line"\nexit 5\n' > "$sw"; chmod +x "$sw"; chmod +x "$sw"
  FT_RES_ROOT="$S/R" FT_DISK_FREE_GIB=100 FT_DISK_NOW="$now" FT_MBOX_SH="$mb" FT_SEATS_JSON="$pl" FT_SCRATCH_REPO_SH="$sw" \
    FT_RES_WATCH_SH=/usr/bin/true FT_RESOURCE_CAUSE_SH=/usr/bin/true FT_WT_MODE_STAMP_SH=/usr/bin/true FT_SCRATCHPAD_CENSUS_SH=/usr/bin/true \
    FT_DOCKER_REAP_SH=/usr/bin/true FT_ACCUM_SWEEP=/usr/bin/true bash "$DISK" >/dev/null 2>&1
  grep -q "^swept=$((now-90000))$" "$st" || { echo "  R13c swept 바뀜: $(cat "$st")" >&2; return 1; }
  grep -q '사본 정리 미완' "$T/mbox.log" 2>/dev/null || { echo "  R13c 쪽지 없음" >&2; return 1; }
  printf '#!/usr/bin/env bash\necho "swept=1 owner-dead=1"\nexit 0\n' > "$sw"; chmod +x "$sw"
  printf 'last=0\nstage=ok\nsent=0\nswept=%s\nreaped=0\nroutefail=0\nwtscan=0\nspcensus=0\nacc=0\n' "$((now-90000))" > "$st"
  FT_RES_ROOT="$S/R" FT_DISK_FREE_GIB=100 FT_DISK_NOW="$now" FT_MBOX_SH="$mb" FT_SEATS_JSON="$pl" FT_SCRATCH_REPO_SH="$sw" \
    FT_RES_WATCH_SH=/usr/bin/true FT_RESOURCE_CAUSE_SH=/usr/bin/true FT_WT_MODE_STAMP_SH=/usr/bin/true FT_SCRATCHPAD_CENSUS_SH=/usr/bin/true \
    FT_DOCKER_REAP_SH=/usr/bin/true FT_ACCUM_SWEEP=/usr/bin/true bash "$DISK" >/dev/null 2>&1
  grep -q "^swept=$now$" "$st"; }
R5b(){ # 가짜 git worktree add 가 표식 기다림 · 셸만 SIGKILL
  REAL_GIT="${REAL_GIT:-$(command -v git)}"
  local S5="$T/s5"; mkdir -p "$S5/src" "$S5/R/.fable-team/state" "$S5/scr" "$S5/bin" "$S5/shim"
  git -C "$S5/src" init -q; echo a > "$S5/src/a.txt"; git -C "$S5/src" add a.txt; git -C "$S5/src" -c user.name=t -c user.email=t@t commit -q -m c1
  printf '#!/bin/sh\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$S5" > "$S5/bin/tmux"; chmod 755 "$S5/bin/tmux"
  printf 'live-owner\n' > "$S5/sessions"
  cat > "$S5/shim/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = add ]; then touch "$S5/git-add.started"; while [ ! -f "$S5/git-add.stop" ]; do command sleep 0.03; done; fi
done
exec "$REAL_GIT" "\$@"
EOF
  chmod +x "$S5/shim/git"
  local HSD="$S5/R/.fable-team/state/heavy-slots" out5 rc5
  ( env PATH="$S5/shim:$S5/bin:$PATH" FT_RES_ROOT="$S5/R" FT_SCRATCH_DIR="$S5/scr" TMPDIR="$S5/scr" FT_SCRATCH_OWNER=live-owner FT_HEAVY_DIR="$HSD" FT_HEAVY_WAIT_S=5 bash "$SCR" HEAD --repo "$S5/src" > "$T/s5.out" 2>&1 ) & local sp=$!; BG+=($sp)
  waitfor "$S5/git-add.started" || { echo "  R5b git-add.started 없음 out=[$(head -3 "$T/s5.out" 2>/dev/null)] realgit=[$REAL_GIT]" >&2; return 1; }
  kill -9 "$sp" 2>/dev/null; command sleep 0.2
  probe "$HSD/slot-1.lock"; local p1=$?
  [ "$p1" = 1 ] || { echo "  R5b 셸 죽음 뒤 자리 풀혔다 out=[$(head -3 "$T/s5.out" 2>/dev/null)] slots=[$(ls "$HSD" 2>/dev/null | tr '\n' ' ')]" >&2; touch "$S5/git-add.stop"; return 1; }
  touch "$S5/git-add.stop"
  local i; for i in $(seq 1 200); do probe "$HSD/slot-1.lock"; [ $? = 0 ] && return 0; command sleep 0.03; done; return 1; }

CASES="${FT_CASES:-R13a R13b R13c R5b}"
for c in $CASES; do run "$c" "$c"; done
mkvar(){ # <이름> <파일> <python 치환> → 변이 폴더(bin 전체 링크)의 같은 이름 파일
  local d="$T/vb-$1" out f; mkdir -p "$d" || return 1
  for f in "$BIN"/*; do ln -sf "$f" "$d/${f##*/}" 2>/dev/null || true; done
  out="$d/${2##*/}"; rm -f "$out"; python3 -I - "$2" "$out" "$3" <<'PY' || return 1
import sys
s = open(sys.argv[1], encoding="utf-8").read()
ns = {"s": s}; exec(sys.argv[3], ns)
assert ns["s"] != s
open(sys.argv[2], "w", encoding="utf-8").write(ns["s"])
PY
}
S0="$SCR"; D0="$DISK"
mkvar 4 "$S0" 's = s.replace("""    delete_copy "$p" "$ty" "${own:--}" sweep; rc=$?
    hs_release""", """    delete_copy "$p" "$ty" "${own:--}" sweep; rc=$?""")' \
  && { SCR="$T/vb-4/ft-scratch-repo.sh"; runv "4(sweep 항목마다 안 풂)" R13b; }
SCR="$S0"; mkvar 6 "$S0" 's = s.replace("(사본 0 · 등록 0)\" 5", "(사본 0 · 등록 0)\" 0")' \
  && { SCR="$T/vb-6/ft-scratch-repo.sh"; runv "6(scratch rc5→0)" R13a; }
SCR="$S0"; mkvar 11 "$D0" 's = s.replace("""  if [ "$rc" = 5 ]; then""", """  if false; then""")' \
  && { DISK="$T/vb-11/ft-disk-alarm.sh"; runv "11(disk-alarm rc 무시)" R13c; }
DISK="$D0"; SCR="$S0"
[ -z "$BAD" ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail$BAD"; exit 1
