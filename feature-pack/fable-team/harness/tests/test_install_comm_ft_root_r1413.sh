#!/usr/bin/env bash
# test_install_comm_ft_root_r1413.sh — r1413: install.sh 의 comm 칸이 env FT_ROOT(= --project 인 데이터 루트)에도 팩 comm 도구를 cp -p
#   + comm/mbox.py 우편함 고르기 ⓒ: 호출 위치가 roots.tsv «경로» 칸과 정확히 같을 때만 그 루트 comm(kakao 꼴 데이터 루트).
#   반례 I1~I11 · 변이 9 (mut-a = install.sh 3 + I1~I5 · mut-b = mbox.py 6 + I6~I11).
#   bash tests/test_install_comm_ft_root_r1413.sh [green|mut-a|mut-b|all]   (부르는 쪽: ulimit -u + timeout 70)
# 실 HOME·실 우편함·실 명부·실 launchd 쓰기 0 — 전부 mktemp 픽스처 · 가짜 launchctl/tmux/pgrep · 고정 sleep 0 · 자기 재호출 0.
[ "${FT_TEST_R1413_RUNNING:-0}" = 1 ] && { echo "SKIP 재진입(이미 도는 시험)"; exit 0; }
export FT_TEST_R1413_RUNNING=1
ulimit -u "$(( $(ps -u "$(id -u)" 2>/dev/null | wc -l | tr -d ' ') + 300 ))" 2>/dev/null || true
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROOT FT_MBOX_DIR FT_ROOTS_TSV FT_MBOX_LEGACY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; HROOT="$(cd -- "$HERE/.." && pwd -P)"
MODE="${1:-all}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$(dirname -- "$T")"
T0=$(date +%s); PH() { echo "PHASE $1 +$(( $(date +%s) - T0 ))s"; }
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq() { [ "$1" = "$2" ] && ok "$3" || bad "$3 — 값 «$1» 기대 «$2»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
nhas() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:300}";; *) ok "$3";; esac; }
SEAT='byz-zz-nano-r1413#0'; TO='byz-zz-master#166'
IR="${IR:-$HROOT}"; MBOXSRC="${MBOXSRC:-$HROOT/comm}"       # 변이 = 사본 트리로 바꾼다
FB="$T/fb"; mkdir -p "$FB" "$T/home/Library/LaunchAgents"
printf '#!/bin/sh\nexit 1\n' > "$FB/tmux"; printf '#!/bin/sh\nexit 1\n' > "$FB/pgrep"
printf '#!/bin/sh\necho "${R1413_LSTART:-Mon Jan  1 00:00:00 2024}"\n' > "$FB/ps"
printf '#!/bin/sh\necho "$@" >> "%s/lc.log"\nexit 0\n' "$T" > "$FB/launchctl"
chmod 755 "$FB"/*
mkrepo() { mkdir -p "$1"; git init -q -b main "$1" && git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i; }
mkeq() {  # <루트> — .fable-team/{comm(팩 사본·데이터 0), bin, seats-harness.json}
  mkdir -p "$1/.fable-team/comm" "$1/.fable-team/bin"; cp -p "$MBOXSRC"/* "$1/.fable-team/comm/" 2>/dev/null
  printf '{"%s":{"role":"nano","agent":"pi","tick":null},"%s":{"role":"master","agent":"pi","tick":null}}\n' "$SEAT" "$TO" > "$1/.fable-team/seats-harness.json"
}
ql() { [ -f "$1/.fable-team/comm/mailbox.jsonl" ] && wc -l < "$1/.fable-team/comm/mailbox.jsonl" | tr -d ' ' || echo 0; }
py() { local r="$1"; shift; ( cd "$T" && env HOME="$T/home" FT_ROOTS_TSV="${RT:-$T/none.tsv}" FT_MBOX_SEQ_FLOOR=1 FT_SEATS_JSON="${SJ:-$T/home/none.json}" \
        PATH="$FB:$PATH" ${EXTRA_ENV:-} python3 "$r/.fable-team/comm/mbox.py" "$@" 2>&1 ); }
sh_send() { local r="$1"; shift; ( cd "$T" && env HOME="$T/home" FT_ROOTS_TSV="${RT:-$T/none.tsv}" FT_MBOX_SEQ_FLOOR=1 FT_SEATS_JSON="${SJ:-$T/home/none.json}" \
        PATH="$FB:$PATH" bash "$r/.fable-team/comm/mbox.sh" send "$@" 2>&1 ); }
inst() { local pr="$1" fl="$2"; shift 2; ( cd "$T" && env HOME="$T/home" FT_LAUNCHCTL="$FB/launchctl" PATH="$FB:$PATH" "$@" bash "$IR/install.sh" "$fl" --home "$T/home" --project "$pr" 2>&1 ); }
mk_kakao() {  # <이름> — git 최상위 K + 데이터 루트 = K/.worktrees/bootstrap/<이름> (kakao 꼴)
  local K DR; K="$T/$1/KakaoBot"; DR="$K/.worktrees/bootstrap/$1"; rm -rf "$T/$1"; mkrepo "$K"; mkeq "$DR"
  printf 'kakao\t%s\t현역\trefs/heads/main\tme\tme-lock\n' "$DR" > "$T/$1/roots.tsv"
  printf '%s\n' "$DR" > "$T/$1/dat"; printf '%s\n' "$K" > "$T/$1/top"
}
mk_byz() {  # <이름> — 공용 루트 BYZ + .worktrees/w1 사본 (BYZ 꼴 · roots.tsv 엔 공용 루트만)
  local C="$T/$1/BYZ" W="$T/$1/BYZ/.worktrees/w1"; rm -rf "$T/$1"; mkrepo "$C"; mkeq "$W"; mkeq "$C"
  printf 'byz\t%s\t현역\trefs/heads/main\tme\tme-lock\n' "$C" > "$T/$1/roots.tsv"
  printf '%s\n' "$C" > "$T/$1/top"; printf '%s\n' "$W" > "$T/$1/wt"
}
snap() { ( cd "$1" && find . -type f -exec cksum {} + 2>/dev/null | LC_ALL=C sort ); }

# ══ I1: K1 꼴(데이터 루트 = --project) + FT_ROOT → 그 데이터 루트에 comm 설치 ══
g_i1() {
  mk_kakao k1; local DR; DR="$(cat "$T/k1/dat")"
  printf 'old\n' > "$DR/.fable-team/comm/mbox.sh"; printf '{}\n' > "$DR/.fable-team/comm/mailbox.jsonl"
  mkdir -p "$DR/.fable-team/comm/bodies"; printf 'b\n' > "$DR/.fable-team/comm/bodies/1.txt"
  local snap0; snap0="$(cd "$DR/.fable-team/comm" && find mailbox.jsonl bodies -type f -exec cksum {} + | LC_ALL=C sort)"
  local out rc; out="$(inst "$DR" --dry-run FT_ROOT="$DR")"; rc=$?
  eq "$rc" 0 "I1 dry-run rc0"
  has "$out" "COMM $DR/.fable-team/comm/mbox.sh <- $IR/comm/mbox.sh" "I1 dry-run: 데이터 루트에 COMM 줄"
  nhas "$out" "SKIP comm" "I1 dry-run: SKIP comm 안 탄다"
  out="$(inst "$DR" --apply FT_ROOT="$DR")"; rc=$?
  eq "$rc" 0 "I1 apply rc0"
  for f in mbox.sh mbox_doorbell.sh mbox.py; do
    cmp -s "$MBOXSRC/$f" "$DR/.fable-team/comm/$f" && ok "I1 $f cmp0" || bad "I1 $f 다름/없음"
  done
  eq "$(cd "$DR/.fable-team/comm" && find mailbox.jsonl bodies -type f -exec cksum {} + | LC_ALL=C sort)" "$snap0" "I1 우편함 데이터 바이트 불변"
}

# ══ I2·I3: FT_ROOT 없으면 지금과 같다(BYZ 꼴 공용 루트 / K1 꼴 SKIP) ══
g_i2() {
  local R="$T/i2/repo"; rm -rf "$T/i2"; mkrepo "$R"; mkeq "$R"
  local out; out="$(inst "$R" --dry-run)"
  has "$out" "COMM copied=" "I2 BYZ 꼴 무변경: COMM copied 줄"
  has "$out" "dest=$R/.fable-team/comm" "I2 BYZ 꼴 무변경: 공용 루트가 대상"
  nhas "$out" "SKIP comm" "I2 SKIP 없음"; nhas "$out" "INFO FT_ROOT" "I2 INFO 줄 없음"
  mk_kakao i2k; local DR; DR="$(cat "$T/i2k/dat")"; out="$(inst "$DR" --dry-run)"
  has "$out" "SKIP comm (--project 가 git 공용 루트 아님" "I3 K1 꼴 · FT_ROOT 없음 → SKIP comm 그대로"
}
g_i4() {
  mk_kakao i4k; local DR K2; DR="$(cat "$T/i4k/dat")"; K2="$T/i4k/KakaoBot"; mkdir -p "$K2/.fable-team/bin"
  local out; out="$(inst "$K2" --dry-run FT_ROOT="$DR")"
  has "$out" "INFO FT_ROOT ≠ --project ($DR ≠ $K2) — comm 은 공용 루트 규칙" "I4ⓐ FT_ROOT ≠ --project → INFO 1줄"
  has "$out" "dest=$K2/.fable-team/comm" "I4ⓐ 공용 루트에 정상 설치"
  mkdir -p "$T/i4k/other/.fable-team"
  out="$(inst "$DR" --dry-run FT_ROOT="$T/i4k/other")"
  has "$out" "SKIP comm (--project 가 git 공용 루트 아님" "I4ⓑ --project = 하위 폴더 · FT_ROOT 다름 → SKIP 줄"
  has "$out" "INFO FT_ROOT ≠ --project" "I4ⓑ INFO 1줄"
}

# ══ I5: FT_ROOT 에 .fable-team 없음 → REJECT rc2 · 첫 쓰기 전(쓰기 0) ══
g_i5() {
  mk_kakao i5k; local K NO; K="$T/i5k/KakaoBot"; NO="$T/i5k/nofte"; mkdir -p "$NO"
  local b1 b2 h1 h2 rc out
  b1="$(cd "$T" && find . -path ./fb -prune -o -path ./home -prune -o -type f -print | LC_ALL=C sort)"; h1="$(snap "$T/home")"
  out="$(inst "$K" --apply FT_ROOT="$NO")"; rc=$?
  eq "$rc" 2 "I5 .fable-team 없는 FT_ROOT → rc2"
  has "$out" "REJECT FT_ROOT 에 .fable-team 없음: $NO (쓰기 0)" "I5 REJECT 문구"
  b2="$(cd "$T" && find . -path ./fb -prune -o -path ./home -prune -o -type f -print | LC_ALL=C sort)"; h2="$(snap "$T/home")"
  eq "$b2" "$b1" "I5 실행 전후 파일 목록 같음(장부·state·comm 쓰기 0)"
  eq "$h2" "$h1" "I5 설치본(홈)에도 쓰기 0"
  out="$(inst "$K" --dry-run FT_ROOT="$NO")"; rc=$?
  eq "$rc" 2 "I5 dry-run 도 rc2"; has "$out" "REJECT FT_ROOT 에 .fable-team 없음" "I5 dry-run REJECT"
}

# ══ I6: kakao 꼴 우편함 = 데이터 루트(roots.tsv 경로 정확 일치) · 네 변형 같은 결과 ══
g_i6() {
  mk_kakao i6; local DR K; DR="$(cat "$T/i6/dat")"; K="$(cat "$T/i6/top")"; RT="$T/i6/roots.tsv"
  local LNK="$T/i6/link"; ln -s "$T/i6/KakaoBot" "$LNK"
  local v out
  for v in none live-symlink trailing-slash symlink-path; do
    case "$v" in
      none) rm -f "$K/.fable-team/LIVE_ROOT";;
      live-symlink) printf '%s\n' "$LNK" > "$K/.fable-team/LIVE_ROOT";;
      trailing-slash) rm -f "$K/.fable-team/LIVE_ROOT"; printf 'kakao\t%s/\t현역\trefs/heads/main\tme\tme-lock\n' "$DR" > "$RT";;
      symlink-path) printf 'kakao\t%s\t현역\trefs/heads/main\tme\tme-lock\n' "$LNK/.worktrees/bootstrap/i6" > "$RT";;
    esac
    [ "$v" = trailing-slash ] || [ "$v" = symlink-path ] || printf 'kakao\t%s\t현역\trefs/heads/main\tme\tme-lock\n' "$DR" > "$RT"
    out="$(py "$DR" recv "$SEAT")"
    has "$out" "SCANNED 1 mailbox(es): $DR/.fable-team/comm/mailbox.jsonl" "I6[$v] 데이터 루트 우편함을 고른다"
    nhas "$out" "$K/.fable-team/comm/mailbox.jsonl" "I6[$v] 공용 루트 우편함 아님"
    EXTRA_ENV="FT_ROOT=$K" py "$DR" send "$TO" "$SEAT" "I6[$v] 쪽지" >/dev/null
    eq "$(ql "$DR")" 1 "I6[$v] send 1줄 → 데이터 루트 mailbox.jsonl"
    eq "$(ql "$K")" 0 "I6[$v] 공용 루트 우편함 0줄"
    out="$(py "$DR" recv "$TO")"; has "$out" "[$SEAT->$TO]" "I6[$v] 같은 도구 recv 가 그 쪽지를 읽는다"
  done
  rm -f "$K/.fable-team/LIVE_ROOT"; printf 'kakao\t%s\t현역\trefs/heads/main\tme\tme-lock\n' "$DR" > "$RT"
  out="$(sh_send "$DR" "$TO" "$SEAT" "I6 mbox.sh 입구")"; has "$out" "QUEUED seq=" "I6 mbox.sh send QUEUED"
  eq "$(ql "$DR")" 1 "I6 mbox.sh send → 데이터 루트 1줄"; eq "$(ql "$K")" 0 "I6 mbox.sh send → 공용 루트 0줄"
}

# ══ I7: BYZ 꼴(roots.tsv 엔 공용 루트) — 사본·LIVE_ROOT·FT_ROOT·두 단계·prefix 무엇이든 공용 루트 ══
g_i7() {
  mk_byz i7; local C W; C="$(cat "$T/i7/top")"; W="$(cat "$T/i7/wt")"
  local OLDR="$C/.worktrees/kakao-agent-bot-planning" NEW="$C/.worktrees/kakao-agent-bot-planning-old"
  mkeq "$OLDR"; mkeq "$NEW"; mkeq "$T/i7/.claude/x"; mkeq "$C/.worktrees/a/.worktrees/b"
  printf 'byz\t%s\t현역\trefs/heads/main\tme\tme-lock\nkakao\t%s\t현역\trefs/heads/main\tme\tme-lock\n' "$C" "$OLDR" > "$T/i7/roots2.tsv"
  local v out
  for v in prefix two-level plain live-root-common live-root-self live-root-other live-root-claude ft-root; do
    RT="$T/i7/roots.tsv"; EXTRA_ENV=""; local want="$C/.fable-team/comm/mailbox.jsonl"
    case "$v" in
      plain) rm -f "$W/.fable-team/LIVE_ROOT";;
      live-root-common) printf '%s\n' "$C" > "$W/.fable-team/LIVE_ROOT";;
      live-root-self) printf '%s\n' "$W" > "$W/.fable-team/LIVE_ROOT";;
      live-root-other) printf '%s\n' "$W" > "$W/.fable-team/LIVE_ROOT";;
      live-root-claude) printf '%s\n' "$T/i7/.claude/x" > "$W/.fable-team/LIVE_ROOT";;
      ft-root) EXTRA_ENV="FT_ROOT=$NEW";;
      prefix) RT="$T/i7/roots2.tsv";;
      two-level) want="$C/.worktrees/a/.fable-team/comm/mailbox.jsonl";;   # 지금 _repo_root = 첫 .worktrees 조상 위 (깊이 2 함정 그대로)
    esac
    case "$v" in
      two-level) out="$(py "$C/.worktrees/a/.worktrees/b" recv "$SEAT")";;
      prefix) out="$(py "$NEW" recv "$SEAT")";;
      *) out="$(py "$W" recv "$SEAT")";;
    esac
    has "$out" "SCANNED 1 mailbox(es): $want" "I7[$v] 지금과 같은 우편함"
    nhas "$out" "$NEW/.fable-team/comm/mailbox.jsonl" "I7[$v] prefix 사본 우편함 아님"
  done
  rm -f "$W/.fable-team/LIVE_ROOT"; RT="$T/i7/roots.tsv"
  py "$W" send "$TO" "$SEAT" "I7 쪽지" >/dev/null
  eq "$(ql "$C")" 1 "I7 send → 공용 루트 1줄"; eq "$(ql "$W")" 0 "I7 사본 우편함 0줄"
}

# ══ I8: FT_MBOX_DIR 명시가 이긴다 · 명부 깨짐이어도 고르기 rc0 · send 는 기준판(다리 r1309)과 같은 rc4 ══
g_i8() {
  mk_kakao i8; local DR; DR="$(cat "$T/i8/dat")"; local MB="$T/i8/explicit"; mkdir -p "$MB"
  RT="$T/i8/roots.tsv"; printf 'broken\trow\n' > "$RT"           # 칸 2개 = RootsError
  local out rc
  out="$(EXTRA_ENV="FT_MBOX_DIR=$MB" py "$DR" recv "$SEAT")"; rc=$?
  eq "$rc" 0 "I8 FT_MBOX_DIR + 명부 깨짐 → recv rc0"
  has "$out" "SCANNED 1 mailbox(es): $MB/mailbox.jsonl" "I8 CANON = FT_MBOX_DIR 값"
  out="$(EXTRA_ENV="FT_MBOX_DIR=$MB" py "$DR" peek "$SEAT")"; rc=$?
  eq "$rc" 0 "I8 명부 깨짐이어도 peek rc0"
  out="$(EXTRA_ENV="FT_MBOX_DIR=$MB" py "$DR" send "$TO" "$SEAT" "I8 쪽지")"; rc=$?
  eq "$rc" 4 "I8 send 는 다리 판정(r1309) 그대로 rc4"
  has "$out" "받는이 판정 불가" "I8 send 판정 불가 1줄"
  eq "$(ql "$MB")" 0 "I8 send rc4 = 큐 쓰기 0"
}

# ══ I9: mbox.py 를 심링크로 부름 → 호출 위치(데이터 루트) 기준 ══
g_i9() {
  mk_kakao i9; local DR; DR="$(cat "$T/i9/dat")"; RT="$T/i9/roots.tsv"
  rm -f "$DR/.fable-team/comm/mbox.py"; ln -s "$MBOXSRC/mbox.py" "$DR/.fable-team/comm/mbox.py"
  local out; out="$(py "$DR" recv "$SEAT")"
  has "$out" "SCANNED 1 mailbox(es): $DR/.fable-team/comm/mailbox.jsonl" "I9 심링크로 불러도 데이터 루트 우편함"
}

# ══ I10: 명부 없음 = 지금 · 깨짐 + 사본 = 판정 불가 rc2(쓰기 0) · 깨짐 + 본판 = rc0 ══
g_i10() {
  mk_byz i10; local C W; C="$(cat "$T/i10/top")"; W="$(cat "$T/i10/wt")"
  local out rc
  out="$(RT="$T/i10/nope.tsv" py "$W" recv "$SEAT")"
  has "$out" "SCANNED 1 mailbox(es): $C/.fable-team/comm/mailbox.jsonl" "I10 명부 없음 → 지금(_repo_root = 공용 루트)"
  RT="$T/i10/broken.tsv"; printf 'x\ty\n' > "$RT"
  local b1 b2; b1="$(snap "$C/.fable-team/comm"; snap "$W/.fable-team/comm")"
  out="$(py "$W" recv "$SEAT")"; rc=$?
  eq "$rc" 2 "I10 깨짐 + 사본 → rc2"
  has "$out" "NO_MAILBOX_ROOT: roots.tsv 판정 불가" "I10 «판정 불가» 1줄"
  b2="$(snap "$C/.fable-team/comm"; snap "$W/.fable-team/comm")"
  eq "$b2" "$b1" "I10 큐 쓰기 0"
  mkeq "$T/i10/plain"; local P="$T/i10/plain"
  out="$(py "$P" recv "$SEAT")"; rc=$?
  eq "$rc" 0 "I10 깨짐 + 본판(X = _ROOT) → rc0(명부 안 연다)"
  has "$out" "SCANNED 1 mailbox(es): $P/.fable-team/comm/mailbox.jsonl" "I10 본판 = 자기 comm"
}

# ══ I11: aifp 꼴(본판 comm · roots.tsv 에 팩 루트 등록) → 지금과 같음 ══
g_i11() {
  local P="$T/i11/pack"; rm -rf "$T/i11"; mkeq "$P"
  RT="$T/i11/roots.tsv"; printf 'aifp\t%s\t현역\trefs/heads/main\tme\tme-lock\n' "$P" > "$RT"
  local out; out="$(py "$P" recv "$SEAT")"
  has "$out" "SCANNED 1 mailbox(es): $P/.fable-team/comm/mailbox.jsonl" "I11 aifp 본판 = 자기 comm"
  printf 'x\ty\n' > "$RT"; out="$(py "$P" recv "$SEAT")"
  has "$out" "SCANNED 1 mailbox(es): $P/.fable-team/comm/mailbox.jsonl" "I11 깨짐이어도 본판 고르기는 rc0(명부 안 연다)"
}

green() {
  PH I1; g_i1; PH I2-I3; g_i2; PH I4; g_i4; PH I5; g_i5; PH I6; g_i6
  PH I7; g_i7; PH I8; g_i8; PH I9; g_i9; PH I10; g_i10; PH I11; g_i11; PH green-end
}

# ══ 변이 — 사본 트리에 한 줄 어긋나게 → 그 칸이 FAIL 하는지(같은 프로세스 · 자기 재호출 0) ══
U=$'\x1f'; NL=$'\n'
mutant() {  # <번호> <칸 함수> <치환식...>
  local n="$1" fn="$2"; shift 2
  local d="$T/mut$n"; rm -rf "$d"; mkdir -p "$d/harness"; git init -q -b main "$d"
  ln -s "$HROOT/kit" "$d/harness/kit"; ln -s "$HROOT/comm" "$d/harness/comm"; ln -s "$HROOT/../manifest.json" "$d/manifest.json"
  cp -p "$HROOT/install.sh" "$d/harness/install.sh"; cp -R "$HROOT/comm" "$d/comm"
  python3 - "$d" "$@" <<'PY' || { bad "변이 $n — 치환 자리를 못 찾음"; return; }
import sys, os
d = sys.argv[1]
for spec in sys.argv[2:]:
    f, old, new = spec.split("\x1f")
    p = os.path.join(d, f); s = open(p, encoding="utf-8").read()
    if s.count(old) != 1: sys.exit("%s: «%s» %d곳" % (f, old[:50], s.count(old)))
    open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c user.email=t@t -c user.name=t commit -qm mut >/dev/null 2>&1
  local out; out="$( ( IR="$d/harness" MBOXSRC="$d/comm" "$fn" ) 2>&1 | grep '^FAIL' | head -2 )"
  [ -n "$out" ] && ok "변이 $n → FAIL: ${out:0:90}" || bad "변이 $n → 그 칸이 안 무너짐($fn)"
}
INST=harness/install.sh; AT="  if [ \"\$COMM_DATA_ROOT\" = \"\$PROJECT\" ]; then COMM_AT_DATA_ROOT=1"
mut_a() {
  mutant 1 g_i1 "$INST${U}$AT${U}  if false; then COMM_AT_DATA_ROOT=1"
  mutant 2 g_i4 "$INST${U}$AT${U}  if [ -n \"\$COMM_DATA_ROOT\" ]; then COMM_AT_DATA_ROOT=1"
  mutant 3 g_i5 "$INST${U}  [ -n \"\$COMM_DATA_ROOT\" ] && [ -d \"\$COMM_DATA_ROOT/.fable-team\" ] \\${U}  true \\" \
                 "$INST${U}  local f n dst copied=0 same=0${NL}${U}  local f n dst copied=0 same=0${NL}  [ -z \"\$COMM_DATA_ROOT\" ] || [ -d \"\$COMM_DATA_ROOT/.fable-team\" ] || { echo \"REJECT FT_ROOT 에 .fable-team 없음: \$COMM_DATA_ROOT (쓰기 0)\" >&2; exit 2; }${NL}"
  PH mut-a-end
}
MP=comm/mbox.py
mut_b() {
  mutant 4 g_i6 "$MP${U}if os.path.realpath(str(r[\"path\"])) == want:${U}if False:"
  mutant 5 g_i7 "$MP${U}if os.path.realpath(str(r[\"path\"])) == want:${U}if want.startswith(os.path.realpath(str(r[\"path\"]))):"
  mutant 6 g_i6 "$MP${U}if os.path.realpath(str(r[\"path\"])) == want:${U}if os.path.abspath(str(r[\"path\"])) == os.path.abspath(x):"
  mutant 7 g_i10 "$MP${U}if not x or os.path.realpath(x) == os.path.realpath(root):${U}if not x:"
  mutant 8 g_i10 "$MP${U}    except mbox_roots.RootsError as e:${NL}        sys.stderr.write(\"NO_MAILBOX_ROOT: roots.tsv 판정 불가 %s\\n\" % e)${NL}        sys.exit(2)${U}    except mbox_roots.RootsError:${NL}        rows = []"
  mutant 9 g_i8 "$MP${U}if os.environ.get(\"FT_MBOX_DIR\"):${U}if _ROOT and _data_root_canon(_ROOT):${NL}    CANON = _data_root_canon(_ROOT)${NL}elif os.environ.get(\"FT_MBOX_DIR\"):"
  PH mut-b-end
}
case "$MODE" in
  green) green ;;
  mut-a) mut_a ;;
  mut-b) mut_b ;;
  all) green; mut_a; mut_b ;;
  *) echo "usage: $0 [green|mut-a|mut-b|all]" >&2; exit 2 ;;
esac
echo "== $MODE: FAIL=$fail =="
[ "$fail" = 0 ]
