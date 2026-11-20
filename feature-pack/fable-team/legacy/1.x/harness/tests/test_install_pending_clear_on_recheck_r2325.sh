#!/usr/bin/env bash
# test_install_pending_clear_on_recheck_r2325.sh — r2325: 착지 설치 검사가 시간 초과로 남긴 설치 대기 파일을, 같은 착지 범위를 덮는 손 재검(OK)이 그 자리에서 지운다
#   c1~c11 = 반례 ①~⑪(카드 동결) · c8 = 착지 도구 두 길(시간 초과 · PENDING) → 대기 파일 «마지막 줄 range=M..Q» + 안내 문구(착지 검사 argv 그대로)
#   c9 = 옛 소비자 호환 · 키트 사본 cmp0 · 문법(회귀 시험 6종의 실패 이름 대조는 좌석 보고에 적는다 — 시험 1개 70초 상한 · 하드 룰 22)
#   기준판 Red ① · 변이 M1~M5 = 짝 시험 test_install_pending_clear_on_recheck_mut_r2325.sh
#   FT_R2325_BIN = 시험할 bin(기본 추적본) · FT_R2325_ONLY = 돌릴 사례(빈 값 = 전부) · 임시 리포·임시 루트·가짜 gh · 실 원격·실 상태·네트워크 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "${FT_R2325_BIN:-$HERE/../../harness/bin}" && pwd -P)"
CHK="$BIN/ft-live-install-check.sh"; KITMAP="$HERE/../../harness/kit/LIVE-MAP.tsv"
ONLY="${FT_R2325_ONLY:-}"
fail=0; rc=0; out=""; el=0; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:600}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
on() { [ -z "$ONLY" ] || [[ " $ONLY " == *" $1 "* ]]; }
T="$(mktemp -d)"; trap 'touch "$T/go"; rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home" FT_BIN="$T/ftbin"; mkdir -p "$HOME" "$FT_BIN"

# ── 재검 리포(임시): 키트 파일 1개 · X → M → MID → Q → TIP
R="$T/repo"; KD=scripts/harness-install; KA="$KD/fable-team/bin/ft-a.sh"
mkdir -p "$R/$KD/fable-team/bin"; G() { git -C "$R" "$@"; }
G init -q -b main . && G config user.name t && G config user.email t@t
cp "$KITMAP" "$R/$KD/LIVE-MAP.tsv"
put() { printf '#!/bin/bash\necho %s\n' "$2" > "$1"; chmod 755 "$1"; }
commit_kit() { G add -A && G commit -qm "$1" && G update-ref refs/remotes/origin/main HEAD; G rev-parse HEAD; }
put "$R/$KA" v0; X="$(commit_kit x-base)"
put "$R/$KA" v1; M="$(commit_kit m-main-before-land)"
put "$R/$KA" v2; MID="$(commit_kit mid-between)"
put "$R/$KA" v3; Q="$(commit_kit q-landed)"
put "$R/$KA" v4; TIP="$(commit_kit tip-after)"
put "$FT_BIN/ft-a.sh" v4   # 라이브 = tip
PR="$T/root"; PD="$PR/.fable-team/state/install-pending"; mkdir -p "$PD"
pd() { mkdir -p "$PD"; printf '%s\n' "${@:2}" > "$PD/$1.txt"; }
chk() { out="$(bash "$CHK" "$@" --repo "$R" --kit "$KD" 2>&1)"; rc=$?; }
F40=1111111111111111111111111111111111111111

if on c1; then  # ① 실물 꼴: 시간 초과 1줄 + range 마지막 줄 · A = M
  pd "$Q" "INSTALL-PENDING 검사 시간 초과" "range=$M..$Q"
  chk --range "$M..$Q" --ref "$TIP" --clear-pending "$PR"
  [ "$rc" = 0 ] && has "OK n=1" && has "CLEARED install-pending ${Q:0:10}" && [ ! -e "$PD/$Q.txt" ]
  ck "① 실물 꼴(range=M..Q · A=M) → CLEARED · 파일 0 rc0" $?
fi
if on c2; then  # ② A = M 의 조상(더 넓은 범위)
  pd "$Q" "INSTALL-PENDING 검사 시간 초과" "range=$M..$Q"
  chk --range "$X..$Q" --ref "$TIP" --clear-pending "$PR"
  [ "$rc" = 0 ] && has "CLEARED install-pending ${Q:0:10}" && [ ! -e "$PD/$Q.txt" ]
  ck "② A = M 의 조상 → CLEARED" $?
fi
if on c3; then  # ③ A = M 과 Q 사이(범위 좁음) → KEEP
  pd "$Q" "INSTALL-PENDING 검사 시간 초과" "range=$M..$Q"
  chk --range "$MID..$Q" --ref "$TIP" --clear-pending "$PR"
  [ "$rc" = 0 ] && has "KEEP install-pending ${Q:0:10}" && has "범위 좁음" && [ -e "$PD/$Q.txt" ]
  ck "③ 범위 좁음 → KEEP · 파일 그대로" $?
fi
if on c4; then  # ④ 검사 PENDING(DIFF 1) → KEEP · rc 1
  put "$FT_BIN/ft-a.sh" v3; pd "$Q" "INSTALL-PENDING 검사 시간 초과" "range=$M..$Q"
  chk --range "$M..$Q" --ref "$TIP" --clear-pending "$PR"
  [ "$rc" = 1 ] && has "PENDING n=1" && has "KEEP install-pending ${Q:0:10}" && has "검사 rc=1" && [ -e "$PD/$Q.txt" ]
  ck "④ 검사 PENDING → KEEP · 파일 그대로 · rc1" $?; put "$FT_BIN/ft-a.sh" v4
fi
if on c5; then  # ⑤ range 줄 0개(옛 파일) · range 줄 2개 · 여러 줄 IOUT + 마지막 range(자리 무관)
  rm -f "$PD/$Q.txt"; pd "$Q" "INSTALL-PENDING 검사 시간 초과"
  chk --range "$M..$Q" --ref "$TIP" --clear-pending "$PR"
  r1=$([ "$rc" = 0 ] && has "KEEP install-pending ${Q:0:10}" && has "range 줄 0개" && [ -e "$PD/$Q.txt" ]; echo $?)
  pd "$Q" "range=$M..$Q" "INSTALL-PENDING 검사 시간 초과" "range=$M..$Q"
  chk --range "$M..$Q" --ref "$TIP" --clear-pending "$PR"
  r2=$([ "$rc" = 0 ] && has "KEEP install-pending ${Q:0:10}" && has "range 줄 2개" && [ -e "$PD/$Q.txt" ]; echo $?)
  pd "$Q" "INSTALL DIFF $KA -> $FT_BIN/ft-a.sh live=x tip=y" "INSTALL-PENDING 검사 시간 초과" "range=$M..$Q"
  chk --range "$M..$Q" --ref "$TIP" --clear-pending "$PR"
  r3=$([ "$rc" = 0 ] && has "CLEARED install-pending ${Q:0:10}" && [ ! -e "$PD/$Q.txt" ]; echo $?)
  [ "$r1" = 0 ] && [ "$r2" = 0 ] && [ "$r3" = 0 ]
  ck "⑤ 옛 파일(0줄)·겹침(2줄) KEEP · 여러 줄 IOUT+마지막 range → CLEARED(자리 무관)" $?
fi
if on c6; then  # ⑥ 옵션 없이 OK → CLEARED·KEEP 줄 0 · 파일 그대로(쓰기 0)
  pd "$Q" "INSTALL-PENDING 검사 시간 초과" "range=$M..$Q"
  chk --range "$M..$Q" --ref "$TIP"
  [ "$rc" = 0 ] && has "OK n=1" && ! has "CLEARED" && ! has "KEEP" && [ -e "$PD/$Q.txt" ]
  ck "⑥ 옵션 없음 → 출력 줄 0 · 파일 그대로(쓰기 0)" $?
fi
if on c7; then  # ⑦ B = 짧은 sha(10자 · desk 손 재검 꼴)
  pd "$Q" "INSTALL-PENDING 검사 시간 초과" "range=$M..$Q"
  chk --range "$M..${Q:0:10}" --ref "$TIP" --clear-pending "$PR"
  [ "$rc" = 0 ] && has "CLEARED install-pending ${Q:0:10}" && [ ! -e "$PD/$Q.txt" ]
  ck "⑦ B = 짧은 sha → 40hex 로 풀어 CLEARED" $?
fi

if on c8; then  # ⑧ 착지 두 길 → 본문 마지막 줄 range=M..Q · 안내 문구 = 착지 검사 argv 그대로
  S=$SECONDS
  . "$HERE/_merge_fixture.sh"
  L="$T/land"; mkdir -p "$L/state"; GO="$T/go"; rm -f "$GO"
  export FT_ROOT="$L" FT_AUTONOMY_STATE_DIR="$L/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json"
  mkrepo "$T"
  mkdir -p "$W/$KD/fable-team/bin"; cp "$KITMAP" "$W/$KD/LIVE-MAP.tsv"   # ⑧c 재검용: 착지 리포 안에 키트(지도) — 하네스 루트가 --repo 밖이면 outside_repo 로 빠진다
  put "$W/$KD/fable-team/bin/ft-a.sh" vland; cm "$W" kit-map; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
  put "$FT_BIN/ft-a.sh" vland   # 라이브 = 키트(OK n=0 이지만 하네스 루트 안쪽 길을 탄다)
  cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
exit 0
EOF
  printf '#!/bin/bash\n[ -z "${HOLD_INSTALL:-}" ] || while [ ! -e "%s" ]; do :; done\necho "OK n=1 (r2325 stub)"\nexit 0\n' "$GO" > "$T/install-hold"
  printf '#!/bin/bash\necho "DIFF scripts/harness-install/fable-team/bin/ft-a.sh -> %s/ft-a.sh live=1111111111 tip=2222222222 landed=3333333333"\nexit 1\n' "$FT_BIN" > "$T/install-pending"
  printf '#!/bin/bash\nexit 0\n' > "$T/lag-stub"
  FIX="$T/bin"; rm -rf "$FIX"; cp -R "$BIN" "$FIX"; rm -rf "$FIX/__pycache__"
  cp "$T/lag-stub" "$FIX/ft-head-lag.sh"; chmod +x "$FIX/ft-head-lag.sh"
  printf 'fm_land_notify_land() { :; }\n' >> "$FIX/ft-merge-lib.sh"
  chmod +x "$T/gh-stub" "$T/install-hold" "$T/install-pending"
  LANDPD="$L/.fable-team/state/install-pending"
  mkpr() {
    git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
    git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
    python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
  }
  land1() {  # land1 <번호> <설치 검사> [KEY=VAL…]
    local n="$1" sc="$2"; shift 2; mkpr "$n"; apv --approve-sha "$PRSHA"; rm -f "$GO"; : > "$STUB_LOG"
    out="$(env FT_INSTALL_CHECK="$sc" "$@" timeout 40 bash "$FIX/ft-merge-land.sh" "$n" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?; touch "$GO"
  }
  tail_range() { tail -n1 "$LANDPD/$1.txt" 2>/dev/null; }
  outl() { printf '%s\n' "$out" | grep -m1 "$1" || true; }
  # ⑧a 시간 초과 길: 검사가 멈춰 상한에 끊긴다
  land1 81 "$T/install-hold" HOLD_INSTALL=1 FT_INSTALL_CHECK_TIMEOUT=2 "FT_LAND_DEADLINE=$(( $(date +%s) + 40 ))"
  qa="$(sed -n 's/^LANDED pr=[0-9]* sha=\([0-9a-f]*\).*/\1/p' <<<"$out")"; ma="$(sed -n 's/.*main_before=\([0-9a-f]*\).*/\1/p' <<<"$out")"
  ra=$([ "$rc" = 0 ] && [ -n "$qa" ] && [ "$(tail_range "$qa")" = "range=$ma..$qa" ] && [ "$(wc -l < "$LANDPD/$qa.txt" | tr -d ' ')" -ge 2 ]; echo $?)
  ga="$(outl 'INSTALL-PENDING 설치 검사 [0-9]*초 초과')"
  [ "$ra" = 0 ] && has "ft-live-install-check.sh --range $ma..$qa --repo $W --clear-pending $L" && has "INSTALL-PENDING"
  ck "⑧a 시간 초과 길 → 대기 파일 마지막 줄 range=M..Q · 안내 문구 argv 그대로" $?
  # ⑧b PENDING 길(DIFF 1): 검사는 rc1 로 끝난다
  land1 82 "$T/install-pending"
  qb="$(sed -n 's/^LANDED pr=[0-9]* sha=\([0-9a-f]*\).*/\1/p' <<<"$out")"; mb="$(sed -n 's/.*main_before=\([0-9a-f]*\).*/\1/p' <<<"$out")"
  [ "$rc" = 0 ] && [ -n "$qb" ] && [ "$(tail_range "$qb")" = "range=$mb..$qb" ] && has "INSTALL-PENDING 손 재검: ft-live-install-check.sh --range $mb..$qb --repo $W --clear-pending $L"
  ck "⑧b PENDING 길(DIFF 1) → range 마지막 줄 · 안내 문구 argv 그대로" $?
  # ⑧c 그 대기 파일을 손 재검 + --clear-pending 으로 지운다(⑧a 파일 · ⑪ 아님 — --repo 를 같이 준다)
  out="$(bash "$CHK" --range "$ma..$qa" --ref "$qa" --repo "$W" --kit "$KD" --clear-pending "$L" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && has "CLEARED install-pending ${qa:0:10}" && [ ! -e "$LANDPD/$qa.txt" ]
  ck "⑧c 착지가 남긴 대기 파일을 같은 argv 손 재검 → CLEARED" $?
  el=$((SECONDS - S))
fi
if on c9; then  # ⑨ 회귀: 옛 소비자(뉴스 셈) 호환 · 키트 사본 cmp0 · 문법
  put "$FT_BIN/ft-a.sh" v4   # c8 이 라이브를 바꿨다 — 아래 사례는 «라이브 = tip» 을 전제
  pd "$Q" "INSTALL-PENDING 검사 시간 초과" "range=$M..$Q"
  out="$(bash "$BIN/ft-install-pending.sh" --root "$PR" 2>&1)"; rc=$?
  r1=$([ "$rc" = 0 ] && [[ "$out" == *"설치 대기 1 병합"* ]]; echo $?)
  rm -f "$PD/$Q.txt"
  r2=0; for f in ft-merge-land.sh ft_live_install_check.py ft-live-install-check.sh; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f" || r2=1; done
  r3=0; bash -n "$BIN/ft-merge-land.sh" && bash -n "$BIN/ft-live-install-check.sh" && python3 -c "import py_compile,sys;py_compile.compile(sys.argv[1],doraise=True)" "$BIN/ft_live_install_check.py" 2>/dev/null || r3=1
  rm -rf "$BIN/__pycache__"
  [ "$r1" = 0 ] && [ "$r2" = 0 ] && [ "$r3" = 0 ]
  ck "⑨ 뉴스 셈(새 꼴 본문) 1병합 · 키트 3파일 cmp0 · 문법" $?
fi
if on c10; then  # ⑩ range 줄 M 이 이 리포에 없음 → 판정 불가 1줄 · 파일 그대로 · rc 불변
  pd "$Q" "INSTALL-PENDING 검사 시간 초과" "range=$F40..$Q"
  chk --range "$M..$Q" --ref "$TIP" --clear-pending "$PR"
  [ "$rc" = 0 ] && has "판정 불가 — install-pending ${Q:0:10}" && ! has "KEEP" && [ -e "$PD/$Q.txt" ]
  ck "⑩ 못 푸는 M → 판정 불가(하드 룰 20) · 파일 그대로" $?
fi
if on c11; then  # ⑪ 다른 리포 착지를 --repo 없이 재검 → 검사 ERROR rc3 → KEEP · rc 3 그대로
  pd "$Q" "INSTALL-PENDING 검사 시간 초과" "range=$M..$Q"
  out="$(bash "$CHK" --range "$F40..1111111111111111111111111111111111111112" --kit "$KD" --clear-pending "$PR" 2>&1)"; rc=$?
  [ "$rc" = 3 ] && has "ERROR" && has "KEEP install-pending" && [ -e "$PD/$Q.txt" ]
  ck "⑪ 못 푸는 범위 재검 = ERROR rc3 → KEEP · rc 3 그대로" $?
fi

echo "단계별 초: 전체 $((SECONDS - T0))(c8 ${el}s)"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
