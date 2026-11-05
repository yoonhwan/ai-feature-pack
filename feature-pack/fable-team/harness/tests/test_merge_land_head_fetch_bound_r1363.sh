#!/usr/bin/env bash
# test_merge_land_head_fetch_bound_r1363.sh — r1363 (1/3 · H1~H7 + 변이 1·2): 하네스 공용 fetch «지정 없음» 상한 = 25초(판정 4114) · 착지 1회 마감(FT_LAND_DEADLINE) 안에서만 · 총 마감 100초(25초 × 단계 4)
#   임시 origin+clone · gh 스텁 · 실 gh·실 GitHub 0 · 느린 fetch 는 «timeout 이 걸린 초»를 대역이 기록해 잰다(긴 sleep 0 = 걸린 초가 상한 이상이면 124)
#   반례 H1~H7 · D1~D7 · 변이 6(검출력) — 카드 design/harness/indices/진행/r1363-merge-land-pr-head-fetch-fixed-cost-bound.md
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each FT_HEAVY_WAIT_S=0   # r466: 레벨 밖(each) — 실 슬랙 0 · r1286 무거운 git 자리 대기는 이 시험에서 0(시간 변수 제거)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; LAND="$BIN/ft-merge-land.sh"; LIB="$BIN/ft-merge-lib.sh"; GATE="$BIN/ft-merge-gate.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; first=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state"
REAL_GIT="$(command -v git)"; REAL_TO="$(command -v timeout)"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; echo "REJECT usage" >&2; exit 2;; esac
body=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done
echo "$* :: $body" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
sha_p() { sha "$ORIGIN" refs/heads/main; }
mkpr() {  # mkpr <번호> <브랜치> <시작점> — PR head 를 origin refs/pull/N/head 에 올리고 스텁 JSON(같은 리포 PR 꼴)
  git -C "$W" checkout -q -B "$2" "$3"; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "$2:refs/pull/$1/head" "$2:refs/heads/$2"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"isCrossRepository":False,"title":"feat: PR "+sys.argv[3],"body":"본문 "+sys.argv[3],"state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "$1" > "$STUB_JSON"
}
# 대역: timeout 은 «fetch·push·ls-remote 에 몇 초 상한이 걸렸나» 만 적고, FT_SLOW_<모드>(걸린 초) ≥ 상한이면 124(진짜 sleep 0) · FT_REAL_<모드> = 실제로 흘려보낼 초
FS="$T/shim"; FTLOG="$T/bound.log"; mkdir -p "$FS"
cat > "$FS/timeout" <<EOF
#!/bin/bash
b="\$1"; shift
m=NONE; for a in "\$@"; do case "\$a" in fetch) m=FETCH;; ls-remote) m=LS;; push) m=PUSH;; esac; done
[ "\$m" = NONE ] || echo "\$m \$b" >> "$FTLOG"
s="FT_SLOW_\$m"; sim="\${!s:-}"; r="FT_REAL_\$m"; real="\${!r:-}"
[ -n "\$real" ] && sleep "\$real"
[ -n "\$sim" ] && [ "\$sim" -ge "\$b" ] && exit 124
exec "$REAL_TO" "\$b" "\$@"
EOF
cat > "$FS/git" <<EOF
#!/bin/bash
f=0; for a in "\$@"; do [ "\$a" = fetch ] && f=1; done
if [ "\$f" = 1 ] && [ -n "\${FT_NOPULL:-}" ]; then
  for a in "\$@"; do case "\$a" in *pull/*/head*) echo "fatal: couldn't find remote ref" >&2; exit 128;; esac; done
fi
exec "$REAL_GIT" "\$@"
EOF
printf '#!/bin/bash\necho "ICHK $*"\n' > "$FS/ichk"
chmod +x "$FS/timeout" "$FS/git" "$FS/ichk"
nth() { sed -n "${1}p" "$FTLOG" | awk -v k="$2" '{print $k}'; }   # nth <n> <1=모드|2=상한>
nmax() { awk '$2>m{m=$2} END{print m+0}' "$FTLOG"; }
nmaxf() { awk '$1=="FETCH" && $2>m{m=$2} END{print m+0}' "$FTLOG"; }
nf() { grep -c '^FETCH ' "$FTLOG" || true; }
nls() { grep -c '^LS ' "$FTLOG" || true; }
npush() { grep -c '^PUSH ' "$FTLOG" || true; }
land() {  # land <PR> <env…>
  local pr="$1"; shift; : > "$FTLOG"; git -C "$W" fetch -q origin; mkpr "$pr" "pr$pr" origin/main; local P="$PRSHA"; apv --approve-sha "$P"
  out="$(env PATH="$FS:$PATH" FT_INSTALL_CHECK="$FS/ichk" "$@" bash "$LAND" "$pr" --approve-sha "$P" --repo "$W" 2>&1)"; rc=$?
  first="$(printf '%s\n' "$out" | head -n1)"
}
gate() {  # gate <sha> <env…>
  local s="$1"; shift; : > "$FTLOG"
  out="$(env PATH="$FS:$PATH" "$@" bash "$GATE" "$s" --repo "$W" --base-head-file "$T/none" 2>&1)"; rc=$?
  first="$(printf '%s\n' "$out" | head -n1)"
}
tomain() { git -C "$W" fetch -q origin && git -C "$W" checkout -q -B main origin/main; MT="$(sha "$W" HEAD)"; }
landm() {  # landm <도구폴더> <PR> <env…> — 변이본으로 착지(PR·승인 먼저 만든다)
  local d="$1" pr="$2"; shift 2; : > "$FTLOG"; git -C "$W" fetch -q origin; mkpr "$pr" "pr$pr" origin/main
  local P="$PRSHA"; apv --approve-sha "$P"
  out="$(env PATH="$FS:$PATH" FT_INSTALL_CHECK="$FS/ichk" "$@" bash "$d/ft-merge-land.sh" "$pr" --approve-sha "$P" --repo "$W" 2>&1)"; rc=$?
}
mutd() { local d="$1"; mkdir -p "$d"; cp "$LAND" "$GATE" "$LIB" "$d/"
  for f in "$BIN"/*; do local b; b="$(basename "$f")"; case "$b" in ft-merge-land.sh|ft-merge-lib.sh|ft-merge-gate.sh) ;; *) ln -sf "$f" "$d/$b";; esac; done; }
IN='fetch 상한 25(판정 4114)'
git -C "$W" checkout -q -B main origin/main; MT="$(sha "$W" HEAD)"

# ── H1 merge-land 지정 없음 · head fetch 15초(11-05 실측 10~16초 꼴) → 상한 25 · rc0 · LANDED · INFO 1줄 ──
land 101 FT_SLOW_FETCH=15
B1="$(nth 1 2)"; M1="$(nth 1 1)"
[ "$rc" = 0 ] && [[ "$out" == *LANDED* ]] && [ "$M1" = FETCH ] && [ "$B1" = 25 ] && [[ "$out" == *"${IN}"* ]]; ck "H1 지정 없음 → head fetch 상한 ${B1}초(15초 통과) · 착지 rc0 · INFO «${IN}»" $?

tomain

# ── H2 merge-gate 지정 없음 · main fetch 15초 → 같은 상한 25 · ALLOW(«판정 불가» 0) ──
gate "$MT" FT_SLOW_FETCH=15
B2="$(nth 1 2)"
[ "$rc" = 0 ] && [[ "$out" == ALLOW* ]] && [ "$B2" = 25 ] && [[ "$out" == *"${IN}"* ]]; ck "H2 게이트 main fetch 도 같은 상한 ${B2}초 → ALLOW · INFO 1줄" $?

tomain

# ── H3 24초 → 통과 / H6·D6 26초 → 25초 × 2(재시도 1) 뒤 DENY · 3차 0 ──
gate "$MT" FT_SLOW_FETCH=24
B3="$(nth 1 2)"; N3="$(nf)"
[ "$rc" = 0 ] && [[ "$out" == ALLOW* ]] && [ "$B3" = 25 ] && [ "$N3" = 1 ]; ck "H3 24초 < 상한 ${B3}초 → ALLOW 1회(절단 0)" $?
gate "$MT" FT_SLOW_FETCH=26
N6="$(nf)"; B6="$(nth 2 2)"
[ "$rc" = 1 ] && [ "$N6" = 2 ] && [ "$B6" = 25 ] && [[ "$out" == DENY* ]] && [[ "$out" == *"fetch origin main 실패"* ]]; ck "H6·D6 26초 → 상한 ${B6}초 × ${N6}(재시도 1) 뒤 DENY · 3차 호출 0" $?

tomain

# ── H4 남은 시간 11초 → 시도 11초 1회 · 재시도 0 ──
gate "$MT" FT_LAND_DEADLINE="$(( $(date +%s) + 11 ))" FT_SLOW_FETCH=25
B4="$(nth 1 2)"; N4="$(nf)"
[ "$rc" = 1 ] && [ "$N4" = 1 ] && [ "$B4" -ge 9 ] && [ "$B4" -le 11 ] && [[ "$out" == *"총 마감"* ]]; ck "H4 착지 마감 남은 11초 → 시도 ${B4}초(9~11) 1회 · 재시도 0 · DENY" $?


# ── H5 FT_FETCH_TIMEOUT_SEC(오빠 예외) 지정이 이긴다 — r1069 그대로 ──
land 102 FT_FETCH_TIMEOUT_SEC=20 FT_SLOW_FETCH=15
B5="$(nth 1 2)"
[ "$rc" = 0 ] && [ "$first" = "오빠 예외 판정 · 지정 20" ] && [ "$B5" = 20 ] && [[ "$out" != *"${IN}"* ]]; ck "H5 지정 20 → 첫 줄 «오빠 예외 판정 · 지정 20» · 상한 ${B5}초 · INFO 25줄 0" $?


# ── H7 pull/N/head 없음 → 가지 갈래도 같은 상한 · headRefOid 대조 그대로(r1127) ──
land 103 FT_NOPULL=1 FT_SLOW_FETCH=15
N7="$(nf)"; X7="$(nmax)"
[ "$rc" = 0 ] && [[ "$out" == *LANDED* ]] && [[ "$out" == *"head ref 없음"* ]] && [ "$N7" -ge 3 ] && [ "$X7" = 25 ]; ck "H7 pull ref 없음 → fetch ${N7}회 모두 상한 ${X7}초 · rc0 LANDED · headRefOid 대조 통과" $?

tomain

# ── 변이 6 — 각 변이가 위 계약 칸에서 FAIL 하는지(검출력) ──
MV="$T/m1"; mutd "$MV"; sed -i '' 's/b=25; FM_FETCH_SEC=\$b/b=7; FM_FETCH_SEC=$b/' "$MV/ft-merge-lib.sh"
! cmp -s "$LIB" "$MV/ft-merge-lib.sh"; ck "변이1 적용(지정 없음 기본 7 로 되돌림)" $?
: > "$FTLOG"; out="$(env PATH="$FS:$PATH" FT_SLOW_FETCH=15 bash "$MV/ft-merge-gate.sh" "$MT" --repo "$W" --base-head-file "$T/none" 2>&1)"; rc=$?
Bm="$(nth 1 2)"
[ "$Bm" = 7 ] && [ "$rc" = 1 ]; ck "변이1 은 H1·H2 칸에서 FAIL(상한 ${Bm}초 · 15초 fetch DENY)" $?


MV="$T/m2"; mutd "$MV"; sed -i '' 's/\[ "\$rem" -lt "\$a" \]/[ "$rem" -lt 0 ]/' "$MV/ft-merge-lib.sh"
! cmp -s "$LIB" "$MV/ft-merge-lib.sh"; ck "변이2 적용(남은 시간 min 끔)" $?
: > "$FTLOG"; out="$(env PATH="$FS:$PATH" FT_LAND_DEADLINE="$(( $(date +%s) + 11 ))" FT_SLOW_FETCH=25 bash "$MV/ft-merge-gate.sh" "$MT" --repo "$W" --base-head-file "$T/none" 2>&1)"; rc=$?
Bm="$(nth 1 2)"
[ "$Bm" = 25 ]; ck "변이2 는 H4·D1 칸에서 FAIL(남은 11초인데 상한 ${Bm}초 — 마감 밖)" $?


[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
