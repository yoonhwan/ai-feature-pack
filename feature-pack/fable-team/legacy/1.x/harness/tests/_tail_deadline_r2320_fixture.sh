# _tail_deadline_r2320_fixture.sh — r2320 시험 공용(source 전용 · r2061 꼴): fixture·반례 사례·변이 헬퍼
#   fx_init <임시 폴더> = 그 폴더에 origin(bare)+clone · 가짜 gh·설치 대조·head-lag·루트 shim·git(push/ls-remote) 1벌
#   fx_fix = 대상 사본($T/fix · 가짜 착지 알림 포함) · fx_base = 기준판(origin/main) 사본(⑦ 줄 비교) · 사례 k1~k12 · 변이 mut
#   실 원격·실 gh·실 mbox 0 · sleep 0 · 시험 1개 70초 상한(하드 룰 22) = 반례와 변이를 두 파일로 쪼갠다
export FT_AUTONOMY_LEVEL=each
unset FT_SEAT FT_MBOX FT_MBOX_DIR FT_SEATS_JSON FM_NOTIFY_REPO FT_REPO_ROOT   # 실 우편함·명부로 새는 길 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2320_BIN:-$(cd "$HERE/../bin" && pwd -P)}"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; el=0; PRSHA=""; BASE_OK=0; BASE=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:500}"; fail=$((fail+1)); fi; }
fx_init() {  # fx_init <임시 폴더> — 임시 origin+clone · 가짜 gh·설치 대조·head-lag·루트 shim·git(push/ls-remote) · 대상 사본
T="$1"; mkrepo "$T"
D="$T/data"; W="$T/w"; ORDER="$T/order.txt"; FIFO="$T/fifo"; DLF="$T/dl.txt"; GB="$T/gb"; GB_LOG="$T/git.log"; TSV="$T/state/push-timing.tsv"
TBIN="$(command -v timeout || command -v gtimeout)"; REAL_GIT="$(command -v git)"
mkdir -p "$T/state" "$D/.fable-team/bin" "$D/.fable-team/state" "$T/live" "$GB"; printf 'x\n' > "$T/live/ft-x.sh"; printf '%s\n' "$T/live" > "$D/.fable-team/LIVE_BIN"
export FT_ROOT="$D" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" ORDER FIFO DLF GB_LOG REAL_GIT TBIN \
       FT_INSTALL_CHECK="$T/install-stub" FT_ROOT_SHIM="$T/shim-stub" FT_HEAVY_DIR="$T/heavy" FT_PUSH_FIXED_S=1
printf '#!/bin/bash\necho "$*" >> "$STUB_LOG"\ncase "$1 $2" in "pr view") cat "$STUB_JSON"; exit 0;; esac\necho close >> "$ORDER"\nexit 0\n' > "$T/gh-stub"
cat > "$T/install-stub" <<'EOF'
#!/bin/bash
printf '%s\n' "$FT_LAND_DEADLINE" > "$DLF"; echo install >> "$ORDER"
[ -z "${FT_INSTALL_EXIT:-}" ] || exit "$FT_INSTALL_EXIT"
[ -z "${HOLD_INSTALL:-}" ] || read -r _ < "$FIFO"
echo "OK n=1 (r2320 stub)"
EOF
cat > "$T/lag-stub" <<'EOF'
#!/bin/bash
echo head-lag >> "$ORDER"; echo "판정 불가 2곳(훑기 예산 7초 · r2320 stub)" >&2; exit 0
EOF
cat > "$T/shim-stub" <<'EOF'
#!/bin/bash
while [ $# -gt 0 ]; do case "$1" in --root) R="$2"; shift 2;; --live) L="$2"; shift 2;; *) shift;; esac; done
echo shim >> "$ORDER"; echo "SHIM r2320 · MOVED 1 · UNKNOWN 0"
EOF
cat > "$GB/git" <<'EOF'
#!/bin/bash
for a in "$@"; do case "$a" in
  push) echo push >> "$GB_LOG"; echo "가짜 timeout(r2320)" >&2; exit 124;;
  ls-remote) printf '%s\trefs/heads/main\n' "$GB_M"; exit 0;;
esac; done
exec "$REAL_GIT" "$@"
EOF
chmod +x "$T/gh-stub" "$T/install-stub" "$T/lag-stub" "$T/shim-stub" "$GB/git"
mkbin() {  # mkbin <폴더> [<파일> <옛> <새>]… — BIN 사본 + 가짜 착지 알림(순서·인자 기록) · 치환 1곳 아님 = rc1
  local d="$1"; shift; rm -rf "$d"; cpclone "$BIN" "$d"; cp "$T/lag-stub" "$d/ft-head-lag.sh"
  printf 'fm_land_notify_land() { echo notify >> "$ORDER"; echo "NOTIFIED r2320 pr=$2 install=$5"; }\n' >> "$d/ft-merge-lib.sh"
  while [ $# -ge 3 ]; do python3 -c 'import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
if s.count(sys.argv[2])!=1: sys.exit("치환 원문 1곳 아님: "+sys.argv[2][:60])
open(p,"w",encoding="utf-8").write(s.replace(sys.argv[2],sys.argv[3]))' "$d/$1" "$2" "$3" || return 1; shift 3; done
}
mkpr() {  # mkpr <번호> [<객체수>] — 임시 origin 의 pull/<번호>/head 에 PR 1개
  local n="$1" k="${2:-1}" i; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$n" origin/main >/dev/null 2>&1
  printf 'pr%s\n' "$n" > "$W/pr$n.txt"; if [ "$k" -ge 2 ]; then for i in $(seq 2 "$k"); do printf '%s\n' "$i" > "$W/obj$i.txt"; done; fi; cm "$W" "pr $n work"
  git -C "$W" push -q -f origin "pr$n:refs/pull/$n/head" >/dev/null 2>&1; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$n" > "$STUB_JSON"
}
land() {  # land <bin> <번호> <바깥 상한초> [KEY=VAL…] · 객체수 = R2320_OBJ · DL_OFF=<초> = 호출 직전 기준 env 마감
  local b="$1" n="$2" o="$3" s; shift 3; mkpr "$n" "${R2320_OBJ:-1}"; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"; : > "$ORDER"; : > "$GB_LOG"; rm -f "$DLF" "$FIFO"; mkfifo "$FIFO"
  s=$SECONDS; LT0=$(date +%s)
  if [ -n "${DL_OFF:-}" ]; then export FT_LAND_DEADLINE=$((LT0 + DL_OFF)); else unset FT_LAND_DEADLINE; fi
  out="$(env "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?; el=$((SECONDS - s))
  rm -f "$FIFO"; unset FT_LAND_DEADLINE
}
within() { local d=$(( $1 - LT0 )); [ "$d" -ge "$2" ] && [ "$d" -le "$3" ]; }   # <dl> <최소> <최대> — 호출 직전 초 기준(부하 큰 기계에서 env·timeout·bash 뜨는 초까지 허용 = +3)
dl() { tr -d '[:space:]' < "$DLF" 2>/dev/null; }
tail_line() { grep -m1 '^LAND-TAIL ' <<<"$out"; }
tailv() { sed -n "s/.* $1=\([^ ]*\).*/\1/p" <<<"$(tail_line)"; }
ord() { grep -n "^$1\$" "$ORDER" 2>/dev/null | head -1 | cut -d: -f1; }
at() { grep -nE "$1" <<<"$out" 2>/dev/null | head -1 | cut -d: -f1; }
norm() { sed -E 's/[0-9a-f]{7,40}/H/g; s/[0-9]+/N/g' <<<"${1:-}"; }
set-() { norm "$1" | sort; }   # 줄 «모임» 비교(순서 무관 — 순서는 ③ 이 본다)
cpclone() { cp -Rc "$1" "$2" 2>/dev/null || cp -R "$1" "$2"; }
MB() { git -C "$ORIGIN" rev-parse main; }
}
fx_fix() { FIX="$T/fix"; mkbin "$FIX" || { echo "FAIL 사본 만들기"; exit 1; }; }
fx_base() {  # 기준판(origin/main) 사본 — ⑦ 줄 비교용 · 못 만들면 BASE_OK=0
  BASE="$T/base"; local RP REL
  RP="$(git -C "$BIN" rev-parse --show-toplevel 2>/dev/null)"; REL="$(cd "$BIN" && pwd -P)"; REL="${REL#"$RP"/}"
  if [ -n "$RP" ] && mkbin "$BASE" && git -C "$RP" show "origin/main:$REL/ft-merge-land.sh" > "$BASE/ft-merge-land.sh" && \
     git -C "$RP" show "origin/main:$REL/ft-autonomy-try.sh" > "$BASE/ft-autonomy-try.sh"; then BASE_OK=1; fi; }
k1() {  # ① FT_LAND_TOTAL_S 없음 → 마감 = 시작 + 67(기준판 100 → Red) · 꼬리 정상 = LAND-TAIL 0
  land "$1" 101 45
  [ "$rc" = 0 ] && within "$(dl)" 66 70 && ! grep -q '^LAND-TAIL' <<<"$out"; }
k2() {  # ② 지정값 = 1~100 안에서만(40 그대로 · 150 은 100 으로 깎임) — 지금 그대로
  local ok=0; land "$1" 102 45 FT_LAND_TOTAL_S=40; within "$(dl)" 39 43 && ok=1
  land "$1" 103 45 FT_LAND_TOTAL_S=150; within "$(dl)" 99 103 && [ "$ok" = 1 ]; }
k3() {  # ③ 착지 알림이 루트 shim 앞 — 기준판 = 알림이 shim 뒤(Red)
  land "$1" 104 45; local a b c e
  a="$(ord notify)"; b="$(ord shim)"; c="$(at '^NOTIFIED r2320')"; e="$(at '^(SHIM-AFTER-LAND |WARN 루트 shim)')"
  [ "$rc" = 0 ] && [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && [ -n "$c" ] && [ -n "$e" ] && [ "$c" -lt "$e" ]; }
k4() {  # ④ 착지 마감이 꼬리 중간에 바닥(남은 3초) → shim·lag 호출 0 · LAND-TAIL 1줄 skip=shim,lag · rc 0
  DL_OFF=11 land "$1" 105 45 FT_PUSH_FIXED_S=0.5 FT_INSTALL_CHECK_TIMEOUT=20 HOLD_INSTALL=1   # env 마감 11초 = push 1단위(7) + 꼬리 3 + 여유 1 · 설치 상한을 «남은−3» 이 먼저 물리게 해 설치 뒤 = 3초
  [ "$rc" = 0 ] && [ -n "$(tail_line)" ] && [ "$(tailv skip)" = "shim,lag" ] && [ -z "$(ord shim)" ] && [ -z "$(ord head-lag)" ] && [ -n "$(ord install)" ]; }
k5() {  # ⑤ 꼬리 모두 정상 → LAND-TAIL 0 · 네 단계 모두 호출(설치·알림·shim·뒤처짐)
  land "$1" 106 45; local o; o="$(grep -cE '^(install|notify|shim|head-lag)$' "$ORDER")"
  [ "$rc" = 0 ] && [ -z "$(tail_line)" ] && [ "$o" = 4 ]; }
k6() {  # ⑥ 설치 대조 rc124 → 알림 인자 그대로(install=124 = PENDING 자리) · LAND-TAIL 1줄 install 칸 · rc 0
  land "$1" 107 45 FT_INSTALL_EXIT=124
  [ "$rc" = 0 ] && grep -q '^INSTALL-PENDING 설치 검사' <<<"$out" && grep -q '^NOTIFIED r2320 pr=107 install=124' <<<"$out" && \
  [ -n "$(tail_line)" ] && [ -n "$(tailv install)" ] && [ -z "$(tailv skip)" ]; }
k7() {  # ⑦ 문서 PR 꼴(설치 대조·shim 즉시 OK) → 출력 줄 = 기준판(origin/main)과 같음 · LAND-TAIL 0
  local on ob tn tb; land "$FIX" 108 45; on="$(set- "$(grep -v '^LAND-PHASE ' <<<"$out")")"; tn="$(grep -c '^LAND-TAIL' <<<"$out")"; [ "$rc" = 0 ] || return 1   # r2355: 새 계약 = LAND-PHASE 1줄 — 그 줄만 빼고 기준판과 같은 줄인가
  [ "$BASE_OK" = 1 ] || return 0
  land "$BASE" 109 45; ob="$(set- "$(grep -v '^LAND-PHASE ' <<<"$out")")"; tb="$(grep -c '^LAND-TAIL' <<<"$out")"
  [ "$rc" = 0 ] && [ -n "$on" ] && [ "$on" = "$ob" ] && [ "$tn" = 0 ] && [ "$tb" = 0 ]; }
k10() {  # ⑩ env 마감 남은 30초 + LIM 67 → push 시도 상한 AB ≤ 30 · 남은−7 < PB = 재시도 0 · ls-remote 판정 그대로
  local ab mb; mb="$(MB)"; rm -f "$TSV"
  R2320_OBJ=5 DL_OFF=30 land "$1" 110 45 FT_PUSH_UNIT_OBJECTS=1 "PATH=$GB:$PATH" "GB_M=$mb"
  ab="$(awk -F'\t' 'END{print $6}' "$TSV" 2>/dev/null)"
  [ "$rc" != 0 ] && [ "$ab" -le 30 ] && [ "$ab" -ge 25 ] && [ "$(grep -c . "$TSV")" = 1 ] && ! grep -q '^INFO 재시도 1' <<<"$out" && \
  grep -q '^REJECT 착지 0 확정' <<<"$out" && [ "$(grep -c '^push$' "$GB_LOG")" = 1 ]; }
k10b() {  # ⑩-b deadline() 도 env 마감을 본다 = 이미 지난 마감이면 그 자리에서 깨끗한 REJECT(push 0)
  DL_OFF=-5 land "$1" 111 45 "PATH=$GB:$PATH" "GB_M=$(MB)"
  [ "$rc" != 0 ] && grep -q '^REJECT 총 마감 ' <<<"$out" && [ ! -s "$GB_LOG" ]; }
k11() {  # ⑪ 남은 초 < push 1단위 → 착지 0 · push 0 · rc≠0(기준판 = push 진입 → Red) — r2355: 같은 사정을 앞 단계에서 먼저 잡는다 = «push 몫 예약: gh pr view 앞 남은 7s − push 1단위 8s < 1»(옛 글 «총 마감 67 s 안에 push 를 끝낼 수 없음» 은 이제 안 나온다)
  DL_OFF=7 land "$1" 112 45 "PATH=$GB:$PATH" "GB_M=$(MB)"
  [ "$rc" != 0 ] && [ "$(grep -c '^REJECT push 몫 예약: ' <<<"$out")" = 1 ] && [ ! -s "$GB_LOG" ]; }
k12() {  # ⑨ try-auto --land 앞 TRY 판정이 쓴 초도 같은 마감에 듦 → merge-land 받은 마감 = try 시작 + 67(기준판 = 없음 → Red)
  local b="$1" d le; rm -rf "$T/tr"; mkdir -p "$T/tr"; cp "$b/ft-autonomy-try.sh" "$T/tr/"
  printf 'd2_on() { return 1; }\nscope_load() { G_S=S1; }\n' > "$T/tr/ft-autonomy-standing-d2.sh"
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "$FT_LAND_DEADLINE" "$(date +%%s)" >> "$DL2"\necho "LANDED 대역"\n' > "$T/tr/ft-merge-land.sh"
  cat > "$T/tr/ft-autonomy.sh" <<'EOF'
#!/usr/bin/env bash
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"; ROOT="$FT_ROOT"; mode() { echo on; }
case "$1" in
  try-auto) . "$HERE/ft-autonomy-try.sh"; cmd_try_auto "${@:2}" ;;
  scope-approve|standing-approve) "$TBIN" 2 cat "$FIFO" >/dev/null 2>&1 || true; echo "SCOPE-OK $2 class=code used=1/30"; exit 0 ;;
  *) exit 9 ;;
esac
EOF
  chmod +x "$T/tr/ft-autonomy.sh"; : > "$T/dl2"; : > "$T/land.log"; unset FT_LAND_DEADLINE; rm -f "$FIFO"; mkfifo "$FIFO"
  out="$(DL2="$T/dl2" bash "$T/tr/ft-autonomy.sh" try-auto "$M0" --pr 7 --repo byz --card c.md --land 2>&1)"; rc=$?
  read -r d le < "$T/dl2" 2>/dev/null; rm -f "$FIFO"
  [ "$rc" = 0 ] && [ -n "${d:-}" ] && [ -n "${le:-}" ] && [ $((d - le)) -ge 63 ] && [ $((d - le)) -le 66 ] && grep -q 'LANDED 대역' <<<"$out"; }
