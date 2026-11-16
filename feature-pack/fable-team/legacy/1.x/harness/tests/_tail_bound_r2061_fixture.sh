# _tail_bound_r2061_fixture.sh — r2061 시험 공용(source 전용): 임시 origin+clone · 가짜 gh · 손자 스텁(설치 대조 · 뒤처짐 알림 · nano-record 알림)
#   손자 = 스텁이 띄운 중첩 timeout 30(자기 process group · 바깥 상한이 못 끝냄) + fifo 읽는 cat · 출력 fd 를 물고 멈춘다 · 각 착지 뒤 fifo 를 열고 닫아 풂 · 고정 sleep 0
#   fx_init <폴더> = 그 폴더에 fixture 1벌(병렬 짝마다 따로) · 실 원격·실 gh·실 mbox 0
export FT_AUTONOMY_LEVEL=each
unset FT_SEAT FT_MBOX FT_MBOX_DIR FT_SEATS_JSON FM_NOTIFY_REPO FT_REPO_ROOT   # 실 우편함·명부로 새는 길 0
BIN="$(cd "$HERE/../../harness/bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; el=0; FIFO=""; TBIN="$(command -v timeout || command -v gtimeout)"; export TBIN
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:600}"; fail=$((fail+1)); fi; }
rel() { [ -p "${1:-}" ] || return 0; exec 3<>"$1"; exec 3>&-; }   # fifo 풀기 — 막힌 cat 이 EOF 를 받는다
fx_init() {
  T="$1"; mkdir -p "$T/state"; mkrepo "$T"; ORDER="$T/order.txt"
  export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" ORDER FT_INSTALL_CHECK="$T/install-stub" FT_HEAVY_DIR="$T/heavy" FT_PUSH_FIXED_S=1   # push 1단위 = 8초 → 마감 12 안에 착지
  cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
[ "$1" = pr-close ] || exit 0
[ -z "${FAIL_CLOSE:-}" ] || { echo "GraphQL: Resource not accessible (addComment)" >&2; exit 1; }
exit 0
EOF
  cat > "$T/install-stub" <<'EOF'
#!/bin/bash
echo install >> "$ORDER"
if [ -n "${HOLD_INSTALL:-}" ]; then "$TBIN" 30 cat "$FIFO" >/dev/null & wait; fi
echo "OK n=1 (r2061 stub)"
EOF
  cat > "$T/lag-stub" <<'EOF'
#!/bin/bash
echo head-lag >> "$ORDER"
echo "판정 불가 2곳(훑기 예산 7초 · r2061 stub)" >&2
if [ -n "${HOLD_LAG:-}" ]; then "$TBIN" 30 cat "$FIFO" >/dev/null & wait; fi
exit 0
EOF
  cat > "$T/nrec-stub" <<'EOF'
#!/bin/bash
echo nano-notify >> "$ORDER"
echo "NOTIFY r2061 stub pr=$3"
if [ -n "${HOLD_NOTIFY:-}" ]; then "$TBIN" 30 cat "$FIFO" & wait; fi
exit 0
EOF
  chmod +x "$T/gh-stub" "$T/install-stub" "$T/lag-stub" "$T/nrec-stub"
}
mkbin() {  # mkbin <폴더> [<파일> <원문> <새문>]… — HERE 사본 + 가짜 head-lag + 가짜 ft-nano-record · REAL_NOTIFY 없으면 착지 알림 함수 = 순서 1줄 · 치환 실패 = rc1
  local d="$1"; shift; rm -rf "$d"; cp -R "$BIN" "$d"; cp "$T/lag-stub" "$d/ft-head-lag.sh"; cp "$T/nrec-stub" "$d/ft-nano-record.sh"
  [ -n "${REAL_NOTIFY:-}" ] || printf 'fm_land_notify_land() { echo notify >> "$ORDER"; }\n' >> "$d/ft-merge-lib.sh"
  while [ $# -ge 3 ]; do python3 -c 'import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
if s.count(sys.argv[2])!=1: sys.exit("치환 원문 없음: "+sys.argv[2][:60])
open(p,"w",encoding="utf-8").write(s.replace(sys.argv[2],sys.argv[3]))' "$d/$1" "$2" "$3" || return 1; shift 3; done
}
mkpr() {
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
land() {  # land <bin> <번호> <바깥 상한초> [KEY=VAL…] — el = 착지 1회 초 · 끝나면 그 착지의 fifo 를 푼다
  local b="$1" n="$2" o="$3" s; shift 3; mkpr "$n"; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"; : > "$ORDER"
  FIFO="$T/fifo-$n"; rm -f "$FIFO"; mkfifo "$FIFO"; export FIFO; s=$SECONDS
  out="$(env "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?; el=$((SECONDS - s)); rel "$FIFO"
}
ran() { grep -qx "$1" "$ORDER" 2>/dev/null; }
q() { sed -n 's/^LANDED pr=[0-9]* sha=\([0-9a-f]*\).*/\1/p' <<<"$out"; }
c1() { land "$1" "$2" $(($3 + 2)) FT_LAND_TOTAL_S="$3" HOLD_LAG=1   # ① 뒤처짐 알림 손자 멈춤 → 마감 안 rc0 · WARN 1줄
  [ "$rc" = 0 ] && grep -q '^LANDED' <<<"$out" && [ "$(grep -cE '^WARN 뒤처짐 알림 [0-9]+초 초과' <<<"$out")" = 1 ] && [ "$el" -le "$3" ]; }
c2() { land "$1" "$2" $(($3 + 2)) FT_LAND_TOTAL_S="$3" HOLD_INSTALL=1   # ② 설치 대조 손자 멈춤 → rc0 · INSTALL-PENDING 1줄 · 대기 파일 1개
  [ "$rc" = 0 ] && grep -q '^LANDED' <<<"$out" && [ "$(grep -c '^INSTALL-PENDING 설치 검사' <<<"$out")" = 1 ] && [ -f "$T/.fable-team/state/install-pending/$(q).txt" ] && [ "$el" -le "$3" ]; }
c8() { land "$1" "$2" $(($3 + 2)) FT_LAND_TOTAL_S="$3" HOLD_NOTIFY=1   # ⑧ 착지 알림(실 함수)의 nano-record 손자가 stdout 을 물고 멈춤 → 마감 안 rc0 · 알림 줄 통과
  [ "$rc" = 0 ] && grep -q '^LANDED' <<<"$out" && ran nano-notify && grep -q "^NOTIFY r2061 stub pr=$2" <<<"$out" && [ "$el" -le "$3" ]; }
norm() { sed -E 's/[0-9a-f]{7,40}/H/g; s/[0-9]+/N/g'; }
OLDI='IOUT="$(FT_BIN="${FT_BIN:-$HERE}" "$TB" "$ITO" bash "${FT_INSTALL_CHECK:-$HERE/ft-live-install-check.sh}" --range "$M..$Q" --ref "$Q" --repo "$REPO" 2>&1)"; irc=$?'
NEWI='fm_tail_run IOUT all env FT_BIN="${FT_BIN:-$HERE}" "$TB" "$ITO" bash "${FT_INSTALL_CHECK:-$HERE/ft-live-install-check.sh}" --range "$M..$Q" --ref "$Q" --repo "$REPO"; irc=$?'
OLDH='HLO="$(FT_ROOT="$ROOT" "$TB" "$HLTO" bash "$HERE/ft-head-lag.sh" --event --repo "$REPO" --base "$REMOTE/$TARGET" 2>&1 >/dev/null)"; hrc=$?'
NEWH='fm_tail_run HLO err env FT_ROOT="$ROOT" "$TB" "$HLTO" bash "$HERE/ft-head-lag.sh" --event --repo "$REPO" --base "$REMOTE/$TARGET"; hrc=$?'
OLDN='FT_ROOT="$c" fm_try "$cap" bash "$FM_HERE/ft-nano-record.sh" notify --pr "$pr" --no-fetch 2>&1 || true'
NEWN='{ fm_tail_run p all env FT_ROOT="$c" "$(fm_timeout_bin)" "$cap" bash "$FM_HERE/ft-nano-record.sh" notify --pr "$pr" --no-fetch; [ -z "$p" ] || printf '"'"'%s\n'"'"' "$p"; }'
