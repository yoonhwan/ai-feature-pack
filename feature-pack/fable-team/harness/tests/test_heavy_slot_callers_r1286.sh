#!/usr/bin/env bash
# test_heavy_slot_callers_r1286.sh — r1286 부르는 곳 반례(merge-land · scratch-repo · nano-spawn · disk-alarm)
#   R12 merge-land ⓐ 자리 둘 다 참 → 1초 안 rc1 «무거운 git 자리 없음 … 착지 0» · gh/push 호출 0
#              ⓑ 첫 push = 연결 실패 스텁 · 둘째 성공 → 두 push «동안» 밖에서 거절(쥠) · PR 닫기 스텁 중엔 잡힘(풂)
#              ⓒ 자리 빔 착지 시간 − FT_HEAVY_SLOTS=0 착지 시간 ≤ 1초(같은 스텁)
#   R13 scratch-repo ⓐ 자리 둘 다 참 → 만들기 rc5 · 폴더·등록 0 / --done rc5 · 사본 그대로
#                    ⓑ --sweep 항목 3 · 바깥 쥔 쪽 1 → 3개 삭제 · 항목 사이 바깥 대기자가 잡음 / 바깥 쥔 쪽 2 → rc5 · 남은 항목 0 줄 · 끝 줄
#                    ⓒ ft-disk-alarm: sweep 스텁 rc5 → swept 그대로 · 쪽지 첫 줄 «[사본 정리 미완]» / rc0 → swept = NOW
#   R14 nano-spawn ⓐ 자리 둘 다 참 → «REJECT 판정 불가 — 무거운 git 자리 …» · 워크트리 0
#                  ⓑ 워크트리 블록 안에서 풀고(블록 뒤 = 세션 띄우기) trap 은 _on_exit 하나 그대로
#   R5b 가짜 git 의 worktree add 가 표식을 기다림 → scratch-repo 셸만 SIGKILL → 계속 쥠 · 가짜 git 끝나면 풀림
#   변이 4(sweep 항목마다 안 풂) → R13ⓑ FAIL · 변이 5(merge-land 대기 실패 rc3) → R12ⓐ FAIL · 변이 6(scratch rc5→0) → R13ⓐ FAIL
#   변이 8(spawn trap 덮어쓰기) → R14ⓑ FAIL · 변이 11(disk-alarm 이 rc 무시) → R13ⓒ FAIL · 변이 12(merge-land 첫 push 뒤 풂) → R12ⓑ FAIL
#   실 tmux·실 원격·실 gh 0 · 자기 재호출 0 · 고정 sleep 0(표식 폴링) · 시험 1개 상한 70초
set -uo pipefail
export FT_AUTONOMY_LEVEL=each FT_MERGE_LAND_CODE_AUTOMERGE=0
[ -z "${FT_R1286C_REENTRY:-}" ] || { echo "FAIL 재진입"; exit 1; }
export FT_R1286C_REENTRY=1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; LAND="$BIN/ft-merge-land.sh"; SCR="$BIN/ft-scratch-repo.sh"; SPAWN="$BIN/ft-nano-spawn.sh"; DISK="$BIN/ft-disk-alarm.sh"
LIBD="$BIN/ft-heavy-slot-lib.sh"
. "$HERE/_merge_fixture.sh"
fail=0; BAD=""; BG=()
T="$(mktemp -d "${TMPDIR:-/tmp}/r1286c.XXXXXX")"
trap 'for p in ${BG[@]+"${BG[@]}"}; do kill -9 "$p" 2>/dev/null; done; rm -rf "$T"' EXIT
ok(){ :; }; bad(){ echo "FAIL $1" >&2; fail=$((fail+1)); BAD="$BAD $1"; }
run(){ local n="$1" f="$2"; if "$f"; then return 0; fi; bad "$n"; return 1; }
ms(){ python3 -c 'import time;print(int(time.time()*1000))'; }
waitfor(){ local i; for i in $(seq 1 300); do [ -e "$1" ] && return 0; command sleep 0.03; done; return 1; }
probe(){ local f="$1" fd; { exec {fd}>>"$f"; } 2>/dev/null || return 2
  perl -MFcntl=:flock -e 'open(my $h, ">&=", $ARGV[0]) or exit 3; flock($h, LOCK_EX|LOCK_NB) or exit 1;' "$fd" 2>/dev/null
  local rc=$?; eval "exec ${fd}>&-" 2>/dev/null; return $rc; }
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

# ── merge-land 준비 ──────────────────────────────────────────────
mkrepo "$T/m"; mkdir -p "$T/m/state" "$T/m/.fable-team" "$T/m/shim" "$T/m/ghlog"
REAL_GIT="$(command -v git)"
export FT_ROOT="$T/m" FT_AUTONOMY_STATE_DIR="$T/m/state" FT_GH="$T/m/gh-stub" FT_GH_WRITE="$T/m/gh-stub" STUB_LOG="$T/m/gh.log" STUB_JSON="$T/m/pr.json"
cat > "$T/m/gh-stub" <<EOF
#!/usr/bin/env bash
_lk(){ local fd; { exec {fd}>>"\$1"; } 2>/dev/null || return 2
  perl -MFcntl=:flock -e 'open(my \$h, ">&=", \$ARGV[0]) or exit 3; flock(\$h, LOCK_EX|LOCK_NB) or exit 1;' "\$fd" 2>/dev/null
  local r=\$?; eval "exec \${fd}>&-" 2>/dev/null; return \$r; }
[ "\$1 \$2" = "pr view" ] && { cat "\$STUB_JSON"; exit 0; }
case "\$1" in
  pr-close|pr-comment) _lk "\$PROBE_DIR/slot-1.lock"; echo "close-probe=\$?" >> "\$STUB_LOG"; echo "\$*" >> "\$STUB_LOG"; exit 0;;
  *) echo "BADVERB \$*" >> "\$STUB_LOG"; exit 2;;
esac
EOF
cat > "$T/m/shim/git" <<EOF
#!/usr/bin/env bash
_lk(){ local fd; { exec {fd}>>"\$1"; } 2>/dev/null || return 2
  perl -MFcntl=:flock -e 'open(my \$h, ">&=", \$ARGV[0]) or exit 3; flock(\$h, LOCK_EX|LOCK_NB) or exit 1;' "\$fd" 2>/dev/null
  local r=\$?; eval "exec \${fd}>&-" 2>/dev/null; return \$r; }
is_push=0; for a in "\$@"; do [ "\$a" = push ] && is_push=1; done
if [ "\$is_push" = 1 ] && [ -f "\$PUSH_ACTIVE" ]; then
  n=\$(cat "\$PUSH_CNT" 2>/dev/null || echo 0); n=\$((n+1)); echo "\$n" > "\$PUSH_CNT"
  _lk "\$PROBE_DIR/slot-1.lock"; echo "push\$n-probe=\$?" >> "\$PUSH_LOG"
  if [ "\$n" = 1 ]; then echo "fatal: could not resolve host: github.com" >&2; exit 128; fi
fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/m/gh-stub" "$T/m/shim/git"
export PROBE_DIR="$T/m/hs" PUSH_LOG="$T/m/push.log" PUSH_CNT="$T/m/push.cnt" PUSH_ACTIVE="$T/m/push.active"
mkpr() { git -C "$W" checkout -q -B "$2" "$3"; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"; git -C "$W" push -q origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"본문 "+sys.argv[2],"state":sys.argv[3],"baseRefName":"main"}))' "$PRSHA" "$1" "${4:-OPEN}" > "$STUB_JSON"; }
land(){ local e=("FT_RES_ROOT=$T/m" "FT_HEAVY_DIR=$T/m/hs"); [ -z "${HS:-}" ] || e+=("FT_HEAVY_SLOTS=$HS"); : > "$PUSH_ACTIVE"; out="$(cd "$W" && env "${e[@]}" PATH="$T/m/shim:$PATH" bash "$LAND" "$@" --repo "$W" 2>&1)"; rc=$?; rm -f "$PUSH_ACTIVE"; }

R12(){ # ⓐ 자리 둘 다 참
  hold "$T/m/hs" a1 || return 1; hold "$T/m/hs" a2 || return 1
  mkpr 21 pr21 origin/main; apv --approve-sha "$PRSHA"; M="$(sha "$ORIGIN" refs/heads/main)"; : > "$STUB_LOG"; : > "$PUSH_LOG"
  local t0 t1; t0="$SECONDS"; land 21 --approve-sha "$PRSHA"; t1="$SECONDS"
  rel a1; rel a2
  [ "$rc" = 1 ] || { echo "  R12a rc=$rc" >&2; return 1; }
  case "$out" in *"무거운 git 자리 없음"*) ;; *) return 1;; esac
  [ "$(sha "$ORIGIN" refs/heads/main)" = "$M" ] || { echo "  R12a main 움직임 rc=$rc out=${out:0:300}" >&2; return 1; }
  [ ! -s "$STUB_LOG" ] || { echo "  R12a gh 호출됨: $(cat "$STUB_LOG")" >&2; return 1; }
  [ ! -s "$PUSH_LOG" ] || { echo "  R12a push 호출됨: $(cat "$PUSH_LOG")" >&2; return 1; }
  [ $((t1-t0)) -le 1 ] || { echo "  R12a 느림 $((t1-t0))초" >&2; return 1; }; }
R12b(){ # ⓑ push 두 번 쥠 · 닫기 때 풂
  git -C "$W" fetch -q origin; mkpr 22 pr22 origin/main; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"; : > "$PUSH_LOG"; rm -f "$PUSH_CNT"
  land 22 --approve-sha "$PRSHA"; local r=$rc o="$out"
  grep -q 'push1-probe=1' "$PUSH_LOG" || { echo "  R12b 첫 push 중 자리 안 쥠: log=[$(cat "$PUSH_LOG" 2>/dev/null)] out=${o:0:300}" >&2; return 1; }
  grep -q 'push2-probe=1' "$PUSH_LOG" || return 1
  grep -q 'close-probe=0' "$STUB_LOG" || { echo "  R12b 닫기 때 자리 안 풀림: $(cat "$STUB_LOG" 2>/dev/null)" >&2; return 1; }
  [ "$r" = 0 ] || { echo "  R12b rc=$r out=${o:0:300}" >&2; return 1; }; }
R12c(){ # ⓒ 자리 검사 비용 ≤ 1초
  git -C "$W" fetch -q origin; mkpr 23 pr23 origin/main; apv --approve-sha "$PRSHA"; rm -f "$PUSH_CNT"; : > "$PUSH_LOG"
  local t0 t1 t2 t3; t0="$(ms)"; HS=1 land 23 --approve-sha "$PRSHA"; t1="$(ms)"; local r1=$rc
  git -C "$W" fetch -q origin; mkpr 24 pr24 origin/main; apv --approve-sha "$PRSHA"; rm -f "$PUSH_CNT"
  t2="$(ms)"; HS=0 land 24 --approve-sha "$PRSHA"; t3="$(ms)"; local r0=$rc
  [ "$r1" = 0 ] && [ "$r0" = 0 ] || { echo "  R12c rc=$r1/$r0 out=${out:0:200}" >&2; return 1; }
  local d=$(( (t1-t0) - (t3-t2) )); [ "$d" -le 1000 ] || { echo "  R12c 자리 검사 비용 ${d}ms" >&2; return 1; }; }

R14(){ # ⓐ 자리 둘 다 참 → REJECT · 워크트리 0
  local R="$T/sp/R" WT="$T/sp/wt"; mkdir -p "$R/design/teams/v65/indices/진행"
  git -C "$R" init -q -b main; echo x > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" -c user.name=t -c user.email=t@t commit -q -m c1
  echo '# card' > "$R/design/teams/v65/indices/진행/r1286-t.md"
  hold "$T/sp/hs" e1 || return 1; hold "$T/sp/hs" e2 || return 1
  local LN ST EN SNIP; LN="$(grep -n 'hs_acquire spawn' "$SPAWN" | cut -d: -f1 | head -1)"
  ST=$((LN-2)); EN="$(awk -v s="$ST" 'NR>=s && /^hs_release /{print NR; exit}' "$SPAWN")"
  SNIP="$(sed -n "${ST},${EN}p" "$SPAWN")"; [ -n "$SNIP" ] || { echo "  R14 SNIP 없음" >&2; return 1; }
  local out2; out2="$(WTDIR="$WT" FT_HEAVY_DIR="$T/sp/hs" FT_HEAVY_WAIT_S=1 bash -c "set -uo pipefail; . \"$LIBD\"; WTDIR=\"$WT\"; ROOT=\"$R\"; BRANCH=nano/t; BASE_BRANCH=main; IDX_ABS=\"$R/design/teams/v65/indices/진행/r1286-t.md\"; IDX_REL=design/teams/v65/indices/진행/r1286-t.md; SLUG=r1286-t; HERE=\"$BIN\"; $SNIP" 2>&1)"; local rr=$?
  rel e1; rel e2
  [ "$rr" = 1 ] || { echo "  R14 rc=$rr out=${out2:0:200}" >&2; return 1; }
  case "$out2" in *"REJECT 판정 불가 — 무거운 git 자리"*) ;; *) return 1;; esac
  [ ! -d "$WT" ] || return 1
  # ⓑ trap 은 _on_exit 하나 + 블록 안 풂
  grep -q '^hs_release   # r1286' "$SPAWN" || return 1
  grep -qx 'trap _on_exit EXIT' "$SPAWN" || { echo "  R14 spawn trap 줄이 _on_exit 아님" >&2; return 1; }
  hold "$T/sp/hs2" f0 || return 1
  local out3; out3="$(WTDIR="$WT" bash -c "set -uo pipefail; . \"$LIBD\"; FT_HEAVY_DIR=\"$T/sp/hs2\"; hs_acquire spawn 0 >/dev/null; hs_release; echo relok" 2>&1)"
  rel f0; probe "$T/sp/hs2/slot-1.lock" >/dev/null 2>&1; case "$out3" in *relok*) return 0;; *) return 1;; esac; }
# ── 표본(ft-resource-sample) ─────────────────────────────────────
RS="$T/rs"; HD="$RS/.fable-team/state/heavy-slots"; PTSV="$RS/.fable-team/state/pressure.tsv"; HTSV="$RS/.fable-team/state/heavy.tsv"
mkdir -p "$RS/.fable-team/state"
samp(){ out="$(FT_RES_ROOT="$RS" FT_HEAVY_DIR="$HD" FT_HEAVY_SLOTS="${HSLOT:-1}" bash "$BIN/ft-resource-sample.sh" 2>&1)"; rc=$?; }
R9(){ rm -rf "$HD"; : > "$PTSV"; samp || { echo "  R9 rc=$rc out=${out:0:200}" >&2; return 1; }
  [ "$(tail -1 "$HTSV" | awk -F'\t' '{print NF}')" = 3 ] || { echo "  R9 heavy 칸수 $(tail -1 "$HTSV")" >&2; return 1; }
  [ "$(tail -1 "$HTSV" | awk -F'\t' '{print $2" "$3}')" = "- -" ] || { echo "  R9 폴더 없음 «-» 아님: $(tail -1 "$HTSV")" >&2; return 1; }
  [ "$(tail -1 "$PTSV" | awk -F'\t' '{print NF}')" = 5 ] || { echo "  R9 pressure 5칸 아님" >&2; return 1; }
  hold "$HD" s1 || return 1; : > "$PTSV"; samp; local r=$rc; rel s1
  [ "$r" = 0 ] || { echo "  R9 rc2=$r" >&2; return 1; }
  [ "$(tail -1 "$HTSV" | awk -F'\t' '{print $2" "$3}')" = "1 0" ] || { echo "  R9 쥔 자리 1 아님: $(tail -1 "$HTSV")" >&2; return 1; }
  [ "$(tail -1 "$PTSV" | awk -F'\t' '{print NF}')" = 5 ]; }
R10s(){ rm -rf "$HD"; : > "$PTSV"; HSLOT=0 samp || return 1
  [ "$(tail -1 "$HTSV" | awk -F'\t' '{print $2" "$3}')" = "- -" ] || { echo "  R10 끈 상태 «-» 아님: $(tail -1 "$HTSV")" >&2; return 1; }
  [ -z "$(ls "$HD"/slot-*.lock 2>/dev/null)" ] || return 1
  HSLOT=0 out="$(FT_HEAVY_DIR="$HD" bash -c '. "$0"; hs_acquire a 5; echo "acq=$?"; hs_release; echo "rel=$?"' "$LIBD" 2>&1)"
  printf '%s' "$out" | grep -q 'acq=0' && printf '%s' "$out" | grep -q 'rel=0'; }

CASES="${FT_CASES:-R12 R12b R12c R14 R9 R10s}"
want(){ case " $CASES " in *" $1 "*) return 0;; esac; return 1; }
runv(){ local c="$1" n="$2" f="$3"; want "$c" || return 0; if "$f"; then bad "변이 $n — $f 통과"; else echo "변이 $n → $f FAIL(정상)"; fi; }
for c in $CASES; do _t=$SECONDS; run "$c" "$c"; echo "  [$c $((SECONDS-_t))초]" >&2; done
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
S0="$SCR"; L0="$LAND"; P0="$SPAWN"
mkvar 5 "$L0" 's = s.replace("""hs_acquire land 0 || rej "무거운 git 자리 없음""", """hs_acquire land 0 || { echo "REJECT 무거운 git 자리 없음"; exit 3; }; rej "무거운 git 자리 없음""")' \
  && { LAND="$T/vb-5/ft-merge-land.sh"; runv R12 "5(merge-land 대기 실패 rc3)" R12; }
LAND="$L0"; mkvar 8 "$P0" 's = s.replace("""trap _on_exit EXIT""", """trap "hs_release" EXIT""")' \
  && { SPAWN="$T/vb-8/ft-nano-spawn.sh"; runv R14 "8(spawn trap 덮어쓰기)" R14; }
SPAWN="$P0"; mkvar 12 "$L0" 's = s.replace("""done
hs_release""", """done""")' \
  && { LAND="$T/vb-12/ft-merge-land.sh"; runv R12b "12(첫 push 뒤 풂)" R12b; }
LAND="$L0"; mkvar 7 "$BIN/ft-resource-sample.sh" 's = s.replace("""printf '\''%s\t%s\t%s\t%s\t%s\n'\''""", """printf '\''%s\t%s\t%s\t%s\t%s\t0\n'\''""")' \
  && { SAMPLEC="$T/vb-7/ft-resource-sample.sh"; runv R9 "7(pressure 칸 추가)" R9; }
LAND="$L0"
[ -z "$BAD" ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail$BAD"; exit 1