#!/usr/bin/env bash
# test_accum_sweep_r1293.sh — r1293 누적 정리(ft-accum-sweep.sh · ft_accum_sweep.py · ft-disk-alarm accum()).
#   계약: 옮기기·목록만(지우기 0) · 나이/개수 규칙 · 덮어쓰기 0(-2) · 잠금 · 하루 1회 표식 · 예산(git·스캔 상한) ·
#        보관 경보 · planner [HIL] 두 종류(실제 판정기 reject 모드 통과) · ft-disk-alarm 하루 1회 · 회귀 스텁
#   쓰는 법: bash tests/test_accum_sweep_r1293.sh            # 반례 R1·R2·R7~R10·R12~R19
#            bash tests/test_accum_sweep_r1293.sh --mutate   # 변이 1·2·7~18 — 사본에 한 줄 어긋나게 하고 그 칸이 «무너지는지» 를 본다
#   실 상태·실 쪽지·실 git·실 /tmp 작업 0 — 임시 루트·임시 리포·가짜 mbox·가짜 git 만. ulimit -u + timeout 70. 자기 재호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
BIN="$REPO/harness/bin"; COMM="$REPO/harness/comm"
ALARMD="$BIN"; SUTD="$BIN"
MUT=0; [ "${1:-}" = --mutate ] && MUT=1
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT   # bg-ok: 잠금 점유 자식은 wait 로 회수하고, 남으면 EXIT 에서 kill
NOW0="$(python3 -c 'import datetime;print(int(datetime.datetime(2026,11,1,12,0,tzinfo=datetime.timezone.utc).timestamp()))')"
REALGIT="$(command -v git)"
dstr() { python3 -c 'import datetime,sys;print(datetime.datetime.fromtimestamp(int(sys.argv[1])).strftime("%Y%m%d"))' "$1"; }
setm() { python3 -c 'import os,sys;os.utime(sys.argv[1],(float(sys.argv[2]),float(sys.argv[2])))' "$1" "$2"; }
mb()   { python3 -c 'import sys;p=sys.argv[1];f=open(p,"wb");f.truncate(int(sys.argv[2]));f.close()' "$1" "$2"; }
timed() { local s e; s="$(python3 -c 'import time;print(int(time.time()*1000))')"; "$@"; e="$(python3 -c 'import time;print(int(time.time()*1000))')"; MS=$((e-s)); }
cnt() { if [ -d "$1" ]; then ls "$1" 2>/dev/null | wc -l | tr -d ' '; elif [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }

BODYDIR="$T/bodies"
printf '#!/bin/sh\nmkdir -p "%s"\nf="$(mktemp "%s/body.XXXXXX")"\nprintf "%%s\\n%%s\\n" "$2" "$4" > "$f"\n' "$BODYDIR" "$BODYDIR" > "$T/mbox.sh"
chmod 755 "$T/mbox.sh"
printf '#!/bin/sh\nexit 0\n' > "$T/noscratch.sh"; chmod 755 "$T/noscratch.sh"
printf '#!/bin/sh\necho "[scratchpad 사본] DEAD-SAFE 0개 0.00GiB · DEAD-KEEP 0 · LIVE 0 · UNKNOWN 0 · 삭제 0"\n' > "$T/spc0.sh"; chmod 755 "$T/spc0.sh"
printf '#!/bin/sh\nexit 3\n' > "$T/git-fail.sh"; chmod 755 "$T/git-fail.sh"
printf '#!/bin/sh\nsleep 10\n' > "$T/git-slow.sh"; chmod 755 "$T/git-slow.sh"
mkdir -p "$T/seats-dir"
printf '{"_hil_route":"byz-planner-master-claude#99","_master":"byz-planner-master-claude#99"}\n' > "$T/seats-dir/seats-planner.json"
printf '{"_hil_route":"byz-planner-master-claude#99"}\n' > "$T/seats.json"
printf '{}\n' > "$T/seats-dir/seats.json"
SEATS="$T/seats-dir/seats-planner.json"

[ -f "$BIN/ft-accum-sweep.sh" ] && [ -f "$BIN/ft_accum_sweep.py" ] || { bad "ft-accum-sweep.sh · ft_accum_sweep.py 없음"; echo "(1 failed)"; exit 1; }

mkroot() { R="$T/$1"; rm -rf "$R"; mkdir -p "$R/.fable-team/state"; rm -rf "$T/bodies"; }
sw() {  # sw [VAR=VAL …] → OUT · RC (SUTD 기준 = 실제 또는 변이 사본)
  OUT="$(env FT_ACCUM_ROOT="$R" FT_ACCUM_NOW="${NOWT:-$NOW0}" FT_ACCUM_SEATS="$SEATS" FT_MBOX_SH="$T/mbox.sh" \
        FT_ACCUM_GIT="$REALGIT" "$@" bash "$SUTD/ft-accum-sweep.sh" 2>&1)"; RC=$?
}
alarm() {  # alarm <시계 오프셋> → $AO · $ARC (ACCUM_SUT 있으면 그 sweep 을 쓴다)
  local -a A=(); [ -n "${ACCUM_SUT:-}" ] && A+=("FT_ACCUM_SWEEP=$ACCUM_SUT")
  AO="$(env FT_RES_ROOT="$R" FT_DISK_FREE_GIB=60 FT_DISK_NOW=$((NOW0+$1)) FT_MBOX_SH="$T/mbox.sh" \
        FT_SEATS_JSON="$T/seats.json" FT_RES_WATCH_SH="$T/noscratch.sh" FT_SCRATCH_REPO_SH="$T/noscratch.sh" \
        FT_SCRATCHPAD_CENSUS_SH="$T/spc0.sh" FT_DOCKER_REAP_SH="$T/noscratch.sh" FT_WT_MODE_STAMP_SH="$T/noscratch.sh" \
        "${A[@]}" bash "$ALARMD/ft-disk-alarm.sh" 2>&1)"; ARC=$?
}
endline() { tail -n 1 <<<"$OUT"; }
body_head() { for f in $(ls "$BODYDIR" 2>/dev/null); do sed -n '2p' "$BODYDIR/$f"; done; }
body_text() { sed -n '2,$p' "$1"; }   # 스텁이 적은 첫 줄 = 수신자 → 본문은 2번째 줄부터

# ── R1 헤드라인 기록: 이름 날짜 8일만 옮김 · HEADLINE.md·seats·PAUSED·오늘 기록 그대로 ──
mkroot r1; H="$R/.fable-team/state/harness-tick"; mkdir -p "$H"
for f in HEADLINE-log-20261024.md HEADLINE-log-20261101.md HEADLINE.md HEADLINE-seats.txt PAUSED; do printf 'x\n' > "$H/$f"; done
sw
{ [ $RC = 0 ] && [ -f "$H/archive/HEADLINE-log-20261024.md" ] && [ -f "$H/HEADLINE-log-20261101.md" ] && [ -f "$H/HEADLINE.md" ] \
  && [ -f "$H/HEADLINE-seats.txt" ] && [ -f "$H/PAUSED" ] && [ ! -e "$H/archive/HEADLINE.md" ] && [ ! -e "$H/archive/PAUSED" ]; } \
  && ok "R1 8일 헤드라인 기록만 archive/ 로 · HEADLINE.md·seats·PAUSED·오늘 기록 그대로" || bad "R1 $(endline) · $(ls "$H" "$H/archive" 2>/dev/null | tr '\n' ' ')"
grep -q '옮김 1(헤드라인 1' <<<"$(endline)" && ok "R1 끝 줄에 옮김 1(헤드라인 1)" || bad "R1 끝 줄 $(endline)"

# ── R2 planner-tick: .bak 최근 3 남기고 7개 + VERDICTS-pending(1일) → archive/<mtime 날짜>/ ──
mkroot r2; P="$R/.fable-team/state/planner-tick"; mkdir -p "$P"
Y=$((NOW0-86400)); YD="$(dstr "$Y")"
for i in 1 2 3 4 5 6 7 8 9 10; do printf '%s\n' "$i" > "$P/TEAM-STATUS.md.bak-$i"; setm "$P/TEAM-STATUS.md.bak-$i" $((Y+i)); done
for f in TEAM-STATUS.md RULE-x.md VERDICTS-pending-1.md; do printf 'x\n' > "$P/$f"; done
setm "$P/VERDICTS-pending-1.md" "$Y"
sw
{ [ "$(cnt "$P/archive/$YD")" = 8 ] && [ -f "$P/TEAM-STATUS.md.bak-8" ] && [ -f "$P/TEAM-STATUS.md.bak-9" ] && [ -f "$P/TEAM-STATUS.md.bak-10" ] \
  && [ -f "$P/TEAM-STATUS.md" ] && [ -f "$P/RULE-x.md" ] && [ -f "$P/archive/$YD/VERDICTS-pending-1.md" ] && [ ! -e "$P/VERDICTS-pending-1.md" ]; } \
  && ok "R2 .bak 최근 3 남김 + 나머지 7 + VERDICTS-pending 1 → archive/$YD/ · TEAM-STATUS.md·RULE 그대로" || bad "R2 archive=$(cnt "$P/archive/$YD") $(ls "$P" | tr '\n' ' ')"
grep -q '옮김 8(헤드라인 0 · planner-tick 8' <<<"$(endline)" && ok "R2 끝 줄에 planner-tick 8" || bad "R2 끝 줄 $(endline)"

# ── R7 완성 카드 목록: 40일 전 2장만 목록 · git status 깨끗 · HEAD 그대로 ──
mkroot r7; R7="$R"
git -c init.defaultBranch=main init -q "$R7"
printf '.fable-team/\n' > "$R7/.gitignore"; git -C "$R7" add .gitignore
git -C "$R7" -c user.email=t@t -c user.name=t commit -qm init
mkdir -p "$R7/design/harness/indices/완성"
D40="$(date -u -v-40d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '40 days ago' +%Y-%m-%dT%H:%M:%SZ)"
D10="$(date -u -v-10d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '10 days ago' +%Y-%m-%dT%H:%M:%SZ)"
printf 'a\n' > "$R7/design/harness/indices/완성/old-a.md"; printf 'b\n' > "$R7/design/harness/indices/완성/old-b.md"
git -C "$R7" add -A; GIT_AUTHOR_DATE="$D40" GIT_COMMITTER_DATE="$D40" git -C "$R7" -c user.email=t@t -c user.name=t commit -qm old
printf 'c\n' > "$R7/design/harness/indices/완성/new-c.md"
git -C "$R7" add -A; GIT_AUTHOR_DATE="$D10" GIT_COMMITTER_DATE="$D10" git -C "$R7" -c user.email=t@t -c user.name=t commit -qm new
printf 'harness\t.\tHEAD\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
HEAD0="$(git -C "$R7" rev-parse HEAD)"
sw
L="$R/.fable-team/state/accum/cards-done-30d-$(dstr "$NOW0").txt"
{ [ $RC = 0 ] && [ "$(grep -c . "$L")" = 2 ] && ! grep -q new-c "$L" && grep -q old-a "$L" && [ "$(git -C "$R7" status --porcelain | grep -v '^?? .fable-team/' | grep -c .)" = 0 ] \
  && [ "$(git -C "$R7" rev-parse HEAD)" = "$HEAD0" ]; } \
  && ok "R7 40일 전 2장만 목록 · git status 깨끗 · HEAD 그대로" || bad "R7 list=[$(cat "$L" 2>/dev/null | tr '\n' ' ')] status=[$(git -C "$R7" status --porcelain)]"

# ── R16 이름 바꿈으로 완성에 들어온 카드(10일 전 git mv)는 목록에 없다 ──
mkroot r16; RA="$R"
git -c init.defaultBranch=main init -q "$RA"
printf '.fable-team/\n' > "$RA/.gitignore"
mkdir -p "$RA/design/harness/indices/완성" "$RA/design/harness/indices/진행"
printf 'x\n' > "$RA/design/harness/indices/완성/old-40.md"; printf 'y\n' > "$RA/design/harness/indices/진행/moved.md"
git -C "$RA" add -A; GIT_AUTHOR_DATE="$D40" GIT_COMMITTER_DATE="$D40" git -C "$RA" -c user.email=t@t -c user.name=t commit -qm old
git -C "$RA" mv design/harness/indices/진행/moved.md design/harness/indices/완성/moved.md
GIT_AUTHOR_DATE="$D10" GIT_COMMITTER_DATE="$D10" git -C "$RA" -c user.email=t@t -c user.name=t commit -qm moved
printf 'harness\t.\tHEAD\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
sw
L="$(ls "$R"/.fable-team/state/accum/cards-done-30d-*.txt 2>/dev/null | tail -1)"
{ [ "$(grep -c . "$L")" = 1 ] && grep -q old-40 "$L" && ! grep -q moved "$L"; } \
  && ok "R16 10일 전 git mv 로 완성에 들어온 카드는 목록 제외 · 40일 것만 1줄" || bad "R16 [$(cat "$L" 2>/dev/null | tr '\n' ' ')]"

# ── R8 백업 폴더: 크기 1줄 · 이동·지우기 0 ──
mkroot r8; BK="$R/.fable-team/state/v6-uncommitted-backup-20261023"; mkdir -p "$BK"
for i in 1 2 3; do mb "$BK/f$i" 1048576; done
sw
BL="$R/.fable-team/state/accum/sweep-$(dstr "$NOW0").log"
{ [ $RC = 0 ] && grep -q "백업 v6-uncommitted-backup-20261023 0.00GiB" "$BL" && grep -q '백업 1곳' <<<"$(endline)" && [ "$(cnt "$BK")" = 3 ]; } \
  && ok "R8 백업 폴더 1곳 크기 1줄 · 폴더 안 파일 수 그대로 3" || bad "R8 $(grep '백업' "$BL" 2>/dev/null | tr '\n' ' ') · $(endline)"

# ── R9 같은 시각 두 실행: 잠금이 잡혀 있으면 «앞 실행이 돈다 — 건너뜀» rc 0 ──
mkroot r9; H="$R/.fable-team/state/harness-tick"; mkdir -p "$H"; printf 'x\n' > "$H/HEADLINE-log-20261024.md"
mkdir -p "$R/.fable-team/state/accum"
python3 - "$R/.fable-team/state/accum/sweep.lock" > "$T/lock.ok" <<'PY' &
import fcntl, sys, time
f = open(sys.argv[1], "a"); fcntl.flock(f, fcntl.LOCK_EX); print("held", flush=True); time.sleep(6)
PY
LP=$!; for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s "$T/lock.ok" ] && break; sleep 0.1; done
sw
{ [ $RC = 0 ] && grep -q '앞 실행이 돈다 — 건너뜀' <<<"$OUT" && [ ! -e "$H/archive/HEADLINE-log-20261024.md" ] && [ ! -e "$R/.fable-team/state/accum/done-$(dstr "$NOW0")" ]; } \
  && ok "R9 잠금 잡힘 → «앞 실행이 돈다 — 건너뜀» rc 0 · 옮김 0 · 표식 0" || bad "R9 rc=$RC $(cat "$OUT")"
wait "$LP" 2>/dev/null
sw
{ [ $RC = 0 ] && [ -f "$H/archive/HEADLINE-log-20261024.md" ]; } && ok "R9 잠금 풀린 뒤 같은 날 실행 → 정상 1회" || bad "R9 재실행 rc=$RC $(endline)"

# ── R10 ft-disk-alarm: 하루 1회만 accum 부름(같은 날 두 번째 틱 0) ──
mkroot r10
printf '#!/bin/sh\necho "$*" >> "%s/accum.calls"\necho "[누적 정리] 옮김 0(헤드라인 0 · planner-tick 0 · 자기 기록 0) · 목록만(완성 카드 0 · 백업 0곳 0.0G) · 판정 불가 0 · 보관 합 0.0G"\n' "$T" > "$T/accum-stub.sh"
chmod 755 "$T/accum-stub.sh"; ACCUM_SUT="$T/accum-stub.sh"
alarm 0; A1="$(cnt "$T/accum.calls")"
alarm 900; A2="$(cnt "$T/accum.calls")"
alarm 87000; A3="$(cnt "$T/accum.calls")"
{ [ "$A1" = 1 ] && [ "$A2" = 1 ] && [ "$A3" = 2 ]; } && ok "R10 하루 1회 accum(첫 틱 1 · 15분 뒤 0 · 다음 날 1)" || bad "R10 calls $A1/$A2/$A3"
grep -q 'accum-sweep rc=0 \[누적 정리\] 옮김 0' "$R/.fable-team/state/disk-alarm.log" && ok "R10 끝 줄 1줄이 disk-alarm 로그에 남는다" || bad "R10 로그 $(tail -2 "$R/.fable-team/state/disk-alarm.log" | tr '\n' ' ')"
unset ACCUM_SUT

# ── R12 보관 합 > 경보값 → planner [HIL] 1통 · 지우기 0 ──
mkroot r12; AR="$R/.fable-team/state/accum/archive"; mkdir -p "$AR"; mb "$AR/big.bin" 1048576
sw FT_ACCUM_ARCHIVE_WARN_GIB=0.0005
{ [ "$(cnt "$BODYDIR")" = 1 ] && grep -q '누적 보관 큼' <<<"$(body_head)" && [ -f "$AR/big.bin" ]; } \
  && ok "R12 보관 합 > 경보값 → [HIL] 누적 보관 큼 1통 · 보관물 그대로(지우기 0)" || bad "R12 $(body_head) · $(ls "$AR")"
sw FT_ACCUM_ARCHIVE_WARN_GIB=0.0005
[ "$(cnt "$BODYDIR")" = 1 ] && ok "R12 같은 날 두 번째 실행 → 같은 종류 쪽지 0" || bad "R12 두 번째 실행 $(cnt "$BODYDIR")통"

# ── R13 예산: 1초 + 대상 많음 → «예산 초과 — 남은 …» 1줄 · 걸린 시간 ≤ 예산+2 · 지우기 0 ──
mkroot r13; H="$R/.fable-team/state/harness-tick"; mkdir -p "$H"
for i in 1 2 3 4 5 6 7 8 9 10; do printf 'x\n' > "$H/HEADLINE-log-2026100$i.md" 2>/dev/null || printf 'x\n' > "$H/HEADLINE-log-202610${i}0.md"; done
for d in a b; do mkdir -p "$R/.fable-team/state/v6-uncommitted-backup-$d"; for i in 1 2 3 4 5; do mb "$R/.fable-team/state/v6-uncommitted-backup-$d/f$i" 1024; done; done
BEFORE="$(ls "$H" | sort | tr '\n' ' ')$(ls "$R/.fable-team/state/v6-uncommitted-backup-a" "$R/.fable-team/state/v6-uncommitted-backup-b" | sort | tr '\n' ' ')"
timed sw FT_ACCUM_BUDGET_SEC=1
ENDS="$(endline)"
AFTER="$(ls "$H" | sort | tr '\n' ' ')$(ls "$R/.fable-team/state/v6-uncommitted-backup-a" "$R/.fable-team/state/v6-uncommitted-backup-b" | sort | tr '\n' ' ')"
{ [ "$MS" -le 3000 ] && grep -q '예산 초과 — 남은 ' <<<"$OUT" && grep -q '^\[누적 정리\]' <<<"$ENDS" && [ "$BEFORE" = "$AFTER" ]; } \
  && ok "R13 예산 1초 · ${MS}ms(≤3000) · «예산 초과 — 남은 …» 1줄 · 끝 줄 있음 · 파일 이름 집합 그대로" || bad "R13 ${MS}ms $(cat "$OUT") · before=[$BEFORE] after=[$AFTER]"

# ── R13b 가짜 git 10초 잠 → 상한 min(7, 남은−1) 에서 끊김 «판정 불가 cards git» ──
mkroot r13b; printf 'harness\t.\tHEAD\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
timed sw FT_ACCUM_BUDGET_SEC=3 FT_ACCUM_GIT="$T/git-slow.sh"
{ [ $RC = 3 ] && [ "$MS" -le 5000 ] && grep -q '판정 불가 cards git' "$R/.fable-team/state/accum/sweep-$(dstr "$NOW0").log" && grep -q '판정 불가 1' <<<"$(endline)"; } \
  && ok "R13b 가짜 git 10초 잠 → ${MS}ms(≤5000) 에 끊김 · 판정 불가 cards git · rc3" || bad "R13b ${MS}ms rc=$RC $(endline)"

# ── R14 archive/ 에 같은 이름이 있으면 -2 · 옛 파일 바이트 그대로 ──
mkroot r14; H="$R/.fable-team/state/harness-tick"; mkdir -p "$H/archive"
printf 'old\n' > "$H/archive/HEADLINE-log-20261024.md"; printf 'new\n' > "$H/HEADLINE-log-20261024.md"
sw
{ [ -f "$H/archive/HEADLINE-log-20261024-2.md" ] && [ "$(cat "$H/archive/HEADLINE-log-20261024.md")" = old ] && [ "$(cat "$H/archive/HEADLINE-log-20261024-2.md")" = new ]; } \
  && ok "R14 같은 이름 → -2 로 이동 · 옛 파일 바이트 그대로(덮어쓰기 0)" || bad "R14 $(ls "$H/archive") · $(cat "$H/archive/HEADLINE-log-20261024.md")"

# ── R15 두 disk-alarm 이 같은 옛 acc 를 읽고 차례로 sweep → 둘째 «오늘 이미 함» · 옮김 1회분 ──
mkroot r15; H="$R/.fable-team/state/harness-tick"; mkdir -p "$H"; printf 'x\n' > "$H/HEADLINE-log-20261024.md"
rm -f "$T/state.pre"; [ -f "$R/.fable-team/state/disk-alarm.state" ] && cp "$R/.fable-team/state/disk-alarm.state" "$T/state.pre"
alarm 0
{ [ -f "$T/state.pre" ] && cp "$T/state.pre" "$R/.fable-team/state/disk-alarm.state"; } || rm -f "$R/.fable-team/state/disk-alarm.state"
alarm 900
{ [ "$(cnt "$H/archive")" = 1 ] && grep -q 'accum-sweep rc=0 .*옮김 1' "$R/.fable-team/state/disk-alarm.log" && grep -q '오늘 이미 함' "$R/.fable-team/state/disk-alarm.log"; } \
  && ok "R15 두 disk-alarm 이 같은 옛 acc 를 읽어도 → 옮김 1회분 · 둘째 «오늘 이미 함»" || bad "R15 archive=$(cnt "$H/archive") · $(grep accum-sweep "$R/.fable-team/state/disk-alarm.log" | tr '\n' ' ')"

# ── R17 실제 판정기(reject 모드): [HIL] 본문 2개 REJECT·WARN·PROMOTE 0 · rc 0 실행은 쪽지 0 ──
guard_body() {  # guard_body <본문 파일> → 판정 출력(비면 통과)
  ( DIR="$COMM"; _seats_json() { echo "$T/seats-dir/seats.json"; }
    . "$COMM/mbox_guard.sh"
    FT_PLANNER_HEAD_MODE=reject _guard_py_head "byz-planner-master-claude#99" reject "$(body_text "$1")" )
}
mkroot r17; printf 'harness\t.\tHEAD\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
mkdir -p "$R/.fable-team/state/accum/archive"; mb "$R/.fable-team/state/accum/archive/big.bin" 1048576
sw FT_ACCUM_GIT="$T/git-fail.sh" FT_ACCUM_ARCHIVE_WARN_GIB=0.0005
G1=""; G2=""
for f in $(ls "$BODYDIR" 2>/dev/null); do
  case "$(sed -n '2p' "$BODYDIR/$f")" in *판정\ 불가*) G1="$(guard_body "$BODYDIR/$f")";; *보관\ 큼*) G2="$(guard_body "$BODYDIR/$f")";; esac
done
{ [ $RC = 3 ] && [ "$(cnt "$BODYDIR")" = 2 ] && [ -z "$G1" ] && [ -z "$G2" ]; } \
  && ok "R17 [HIL] 판정 불가·보관 큼 본문 2개 → 실제 판정기 REJECT 0 · WARN 0 · PROMOTE 0" || bad "R17 rc=$RC bodies=$(cnt "$BODYDIR") g1=[$G1] g2=[$G2]"
sw FT_ACCUM_GIT="$T/git-fail.sh" FT_ACCUM_ARCHIVE_WARN_GIB=0.0005
{ [ "$(cnt "$BODYDIR")" = 2 ] && grep -q '오늘 이미 함' <<<"$OUT"; } && ok "R17 같은 날 두 번째 실행 → 쪽지 0 · «오늘 이미 함» rc 0" || bad "R17 두 번째 $(cnt "$BODYDIR")통 · $OUT"
mkroot r17c
sw
{ [ $RC = 0 ] && [ "$(cnt "$BODYDIR")" = 0 ] && grep -q '\[누적 정리\] 옮김 0' "$R/.fable-team/state/accum/sweep-$(dstr "$NOW0").log"; } \
  && ok "R17 rc 0 실행은 쪽지 0(끝 줄은 sweep 로그 1줄)" || bad "R17c rc=$RC bodies=$(cnt "$BODYDIR")"

# ── R19 예산 3초 · 백업 2곳 × 200 · 스캔 지연 50ms → 걸린 시간 ≤ 예산+2 · «≥ …» 또는 «예산 초과 — 남은 백업 …» ──
mkroot r19
for d in a b; do mkdir -p "$R/.fable-team/state/v6-uncommitted-backup-$d"; for i in $(seq 1 200); do mb "$R/.fable-team/state/v6-uncommitted-backup-$d/f$i" 1024; done; done
timed sw FT_ACCUM_BUDGET_SEC=3 FT_ACCUM_SCAN_DELAY_MS=50
{ [ "$MS" -le 5000 ] && { grep -q '≥ ' <<<"$OUT" || grep -q '예산 초과 — 남은 백업' <<<"$OUT"; } && grep -q '^\[누적 정리\]' <<<"$(endline)" \
  && [ "$(cnt "$R/.fable-team/state/v6-uncommitted-backup-a")" = 200 ] && [ "$(cnt "$R/.fable-team/state/v6-uncommitted-backup-b")" = 200 ]; } \
  && ok "R19 예산 3초 · ${MS}ms(≤5000) · 백업 스캔 상한에서 끊김 · 파일 수 그대로" || bad "R19 ${MS}ms $(cat "$OUT")"

if [ "$MUT" = 1 ]; then
  # 변이 = 사본에 «한 줄» 어긋나게 하고, 그 칸의 단언이 무너지는지 같은 프로세스에서 본다(자기 재호출 0).
  mut() {  # mut <이름> <파일> <old> <new> → 사본 폴더(실패면 빈 줄)
    local MD="$T/mut-$1"; rm -rf "$MD"; mkdir -p "$MD"
    cp "$BIN/ft-disk-alarm.sh" "$BIN/ft_accum_sweep.py" "$BIN/ft-accum-sweep.sh" "$MD"/ 2>/dev/null
    python3 - "$MD/$2" "$3" "$4" <<'PY' || { echo ""; return 0; }
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if old not in s: sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
    echo "$MD"
  }
  SUTD0="$SUTD"; ALARMD0="$ALARMD"
  # 변이 1: regex 를 ^HEADLINE 으로 넓히고 나이를 8일 고정 → HEADLINE.md·seats·오늘 기록까지 옮겨 R1 이 무너진다
  MD="$(mut m1 ft_accum_sweep.py '            m = re.match(r"^HEADLINE-log-(\d{8})\.md$", f)
            d = age_days(m.group(1)) if m else None' '            m = re.match(r"^HEADLINE", f)
            d = 8')"
  if [ -z "$MD" ]; then bad "변이 1 패치 실패"; else
    mkroot m1; H="$R/.fable-team/state/harness-tick"; mkdir -p "$H"
    for f in HEADLINE-log-20261024.md HEADLINE-log-20261101.md HEADLINE.md HEADLINE-seats.txt PAUSED; do printf 'x\n' > "$H/$f"; done
    SUTD="$MD"; sw; SUTD="$SUTD0"
    { [ -f "$H/archive/HEADLINE.md" ] && [ -f "$H/archive/HEADLINE-log-20261101.md" ]; } \
      && ok "변이 1(HEADLINE.md 도 대상) → R1 «HEADLINE.md 그대로» 단언이 무너진다" || bad "변이 1 미검출 $(ls "$H/archive" 2>/dev/null | tr '\n' ' ')"
  fi
  # 변이 2: .bak 남기기 3 → 0 → R2 의 «최근 3 남음» 단언이 무너진다
  MD="$(mut m2 ft_accum_sweep.py '[:3])' '[:0])')"
  if [ -z "$MD" ]; then bad "변이 2 패치 실패"; else
    mkroot m2; P="$R/.fable-team/state/planner-tick"; mkdir -p "$P"
    for i in 1 2 3 4 5; do printf '%s\n' "$i" > "$P/TEAM-STATUS.md.bak-$i"; setm "$P/TEAM-STATUS.md.bak-$i" $((NOW0-86400+i)); done
    SUTD="$MD"; sw; SUTD="$SUTD0"
    { [ ! -f "$P/TEAM-STATUS.md.bak-5" ] && [ "$(cnt "$P/archive")" = 1 ]; } \
      && ok "변이 2(.bak 남기기 3→0) → R2 «최근 3 남음» 단언이 무너진다(최신 .bak 까지 옮겨짐)" || bad "변이 2 미검출 $(ls "$P" | tr '\n' ' ')"
  fi
  # 변이 7: 완성 카드를 git mv 로 옮김 → R7 «git status 깨끗 · HEAD 그대로» 단언이 무너진다
  MD="$(mut m7 ft_accum_sweep.py '                out.append(rel)' '                out.append(rel); subprocess.run([GIT, "-C", repo, "mv", rel, rel + "-mut"])')"
  if [ -z "$MD" ]; then bad "변이 7 패치 실패"; else
    mkroot m7; R7="$R"; git -c init.defaultBranch=main init -q "$R7"
    printf '.fable-team/\n' > "$R7/.gitignore"; mkdir -p "$R7/design/harness/indices/완성"
    printf 'a\n' > "$R7/design/harness/indices/완성/old-a.md"
    git -C "$R7" add -A; GIT_AUTHOR_DATE="$D40" GIT_COMMITTER_DATE="$D40" git -C "$R7" -c user.email=t@t -c user.name=t commit -qm old
    printf 'harness\t.\tHEAD\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
    SUTD="$MD"; sw; SUTD="$SUTD0"
    { [ "$(git -C "$R7" status --porcelain | grep -c .)" -ge 1 ] || [ ! -f "$R7/design/harness/indices/완성/old-a.md" ]; } \
      && ok "변이 7(완성 카드를 git mv) → R7 «git status 깨끗» 단언이 무너진다" || bad "변이 7 미검출"
  fi
  # 변이 8: lock 제거 → R9 «앞 실행이 돈다 — 건너뜀» 단언이 무너진다
  MD="$(mut m8 ft_accum_sweep.py '        fcntl.flock(lf, fcntl.LOCK_EX | fcntl.LOCK_NB)' '        pass')"
  if [ -z "$MD" ]; then bad "변이 8 패치 실패"; else
    mkroot m8; H="$R/.fable-team/state/harness-tick"; mkdir -p "$H"; printf 'x\n' > "$H/HEADLINE-log-20261024.md"
    mkdir -p "$R/.fable-team/state/accum"
    python3 - "$R/.fable-team/state/accum/sweep.lock" > "$T/lock.ok" <<'PY' &
import fcntl, sys, time
f = open(sys.argv[1], "a"); fcntl.flock(f, fcntl.LOCK_EX); print("held", flush=True); time.sleep(4)
PY
    LP=$!; for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s "$T/lock.ok" ] && break; sleep 0.1; done
    SUTD="$MD"; sw; SUTD="$SUTD0"; wait "$LP" 2>/dev/null
    { ! grep -q '앞 실행이 돈다' <<<"$OUT" && [ -f "$H/archive/HEADLINE-log-20261024.md" ]; } \
      && ok "변이 8(lock 제거) → R9 «앞 실행이 돈다 — 건너뜀» 단언이 무너진다" || bad "변이 8 미검출 $OUT"
  fi
  # 변이 9: 하루 1회 검사 제거 → R10/R17 «같은 날 두 번째 실행» 단언이 무너진다
  MD="$(mut m9 ft_accum_sweep.py '    if os.path.exists(done):' '    if False:')"
  if [ -z "$MD" ]; then bad "변이 9 패치 실패"; else
    mkroot m9; H="$R/.fable-team/state/harness-tick"; mkdir -p "$H"
    printf 'x\n' > "$H/HEADLINE-log-20261023.md"; printf 'x\n' > "$H/HEADLINE-log-20261024.md"
    SUTD="$MD"; sw; sw; SUTD="$SUTD0"
    { [ "$(cnt "$H/archive")" = 2 ]; } && ok "변이 9(하루 1회 검사 제거) → 같은 날 두 번째 실행이 또 옮겨 R10 단언이 무너진다" || bad "변이 9 미검출"
  fi
  # 변이 10: 예산 초과 줄을 조용히 → R13 «예산 초과 — 남은 …» 단언이 무너진다
  MD="$(mut m10 ft_accum_sweep.py '            print("예산 초과 — 남은 백업 %d곳 다음 날" % (len(dirs) - done))' '            pass')"
  if [ -z "$MD" ]; then bad "변이 10 패치 실패"; else
    mkroot m10; for d in a b; do mkdir -p "$R/.fable-team/state/v6-uncommitted-backup-$d"; for i in 1 2 3; do mb "$R/.fable-team/state/v6-uncommitted-backup-$d/f$i" 1024; done; done
    SUTD="$MD"; sw FT_ACCUM_BUDGET_SEC=1; SUTD="$SUTD0"
    { ! grep -q '예산 초과 — 남은 ' <<<"$OUT"; } && ok "변이 10(예산 초과를 조용히) → R13 «예산 초과 — 남은 …» 단언이 무너진다" || bad "변이 10 미검출 $OUT"
  fi
  # 변이 11: 이름 접미 제거(덮어쓰기) → R14 «옛 파일 바이트 그대로» 단언이 무너진다
  MD="$(mut m11 ft_accum_sweep.py '        dst = os.path.join(dstdir, base if i == 1 else "%s-%d%s" % (stem, i, ext))' '        dst = os.path.join(dstdir, base)')"
  if [ -z "$MD" ]; then bad "변이 11 패치 실패"; else
    MD2="$(mut m11b ft_accum_sweep.py '            os.close(os.open(dst, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644))' '            os.close(os.open(dst, os.O_CREAT | os.O_WRONLY, 0o644))')"
    [ -z "$MD2" ] && { bad "변이 11 b 패치 실패"; } || {
      mkroot m11; H="$R/.fable-team/state/harness-tick"; mkdir -p "$H/archive"
      printf 'old\n' > "$H/archive/HEADLINE-log-20261024.md"; printf 'new\n' > "$H/HEADLINE-log-20261024.md"
      SUTD="$MD2"; sw; SUTD="$SUTD0"
      { [ "$(cat "$H/archive/HEADLINE-log-20261024.md")" = new ]; } \
        && ok "변이 11(이름 접미 제거·덮어쓰기) → R14 «옛 파일 바이트 그대로» 단언이 무너진다" || bad "변이 11 미검출"
    }
  fi
  # 변이 12: 하루 표식 «생성» 제거(disk-alarm acc 값에만 기댐) → R15 «둘째 오늘 이미 함» 단언이 무너진다
  MD="$(mut m12 ft_accum_sweep.py '    open(done, "w").close()' '    pass')"
  if [ -z "$MD" ]; then bad "변이 12 패치 실패"; else
    mkroot m12; H="$R/.fable-team/state/harness-tick"; mkdir -p "$H"
    printf 'x\n' > "$H/HEADLINE-log-20261023.md"; printf 'x\n' > "$H/HEADLINE-log-20261024.md"
    SUTD="$MD"; sw; sw; SUTD="$SUTD0"
    { [ "$(cnt "$H/archive")" = 2 ]; } && ok "변이 12(표식 생성 제거) → 둘째 실행이 또 옮겨 R15 단언이 무너진다" || bad "변이 12 미검출"
  fi
  # 변이 13: diff-filter=A 만 → R16 «이름 바꿈으로 들어온 카드 제외» 단언이 무너진다
  MD="$(mut m13 ft_accum_sweep.py '"--diff-filter=AR"' '"--diff-filter=A"')"
  if [ -z "$MD" ]; then bad "변이 13 패치 실패"; else
    mkroot m13; RA="$R"; git -c init.defaultBranch=main init -q "$RA"
    printf '.fable-team/\n' > "$RA/.gitignore"; mkdir -p "$RA/design/harness/indices/완성" "$RA/design/harness/indices/진행"
    printf 'x\n' > "$RA/design/harness/indices/완성/old-40.md"; printf 'y\n' > "$RA/design/harness/indices/진행/moved.md"
    git -C "$RA" add -A; GIT_AUTHOR_DATE="$D40" GIT_COMMITTER_DATE="$D40" git -C "$RA" -c user.email=t@t -c user.name=t commit -qm old
    git -C "$RA" mv design/harness/indices/진행/moved.md design/harness/indices/완성/moved.md
    GIT_AUTHOR_DATE="$D10" GIT_COMMITTER_DATE="$D10" git -C "$RA" -c user.email=t@t -c user.name=t commit -qm moved
    printf 'harness\t.\tHEAD\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
    SUTD="$MD"; sw; SUTD="$SUTD0"
    L="$(ls "$R"/.fable-team/state/accum/cards-done-30d-*.txt 2>/dev/null | tail -1)"
    { [ "$(grep -c . "$L")" = 2 ]; } && ok "변이 13(diff-filter=A 만) → 이동으로 들어온 카드가 목록에 들어와 R16 단언이 무너진다" || bad "변이 13 미검출 [$(cat "$L" | tr '\n' ' ')]"
  fi
  # 변이 14: 머리 [HIL]→[정리] → R17 실제 판정기가 REJECT 한다
  MD="$(mut m14 ft_accum_sweep.py '[HIL] 누적 보관 큼: %.1fG' '[정리] 누적 보관 큼: %.1fG')"
  if [ -z "$MD" ]; then bad "변이 14 패치 실패"; else
    mkroot m14; mkdir -p "$R/.fable-team/state/accum/archive"; mb "$R/.fable-team/state/accum/archive/big.bin" 1048576
    SUTD="$MD"; sw FT_ACCUM_ARCHIVE_WARN_GIB=0.0005; SUTD="$SUTD0"
    G=""; for f in $(ls "$BODYDIR" 2>/dev/null); do G="$(guard_body "$BODYDIR/$f")"; done
    { [ -n "$G" ] && grep -q 'REJECT' <<<"$G"; } && ok "변이 14(머리 [정리]) → 실제 판정기 reject 모드가 막는다: $(head -1 <<<"$G")" || bad "변이 14 미검출 [$G]"
  fi
  # 변이 15: FT_ACCUM_SWEEP 무시(실 도구 호출) → 회귀 스텁 단언이 무너진다
  MD="$(mut m15 ft-disk-alarm.sh 'ACC="${FT_ACCUM_SWEEP:-$HERE/ft-accum-sweep.sh}"' 'ACC="$HERE/ft-accum-sweep.sh"')"
  if [ -z "$MD" ]; then bad "변이 15 패치 실패"; else
    mkroot m15; H="$R/.fable-team/state/harness-tick"; mkdir -p "$H"; printf 'x\n' > "$H/HEADLINE-log-20261024.md"
    ALARMD="$MD"; ACCUM_SUT="$T/accum-stub.sh"
    printf '#!/bin/sh\necho "$*" >> "%s/accum.calls"\nexit 0\n' "$T" > "$T/accum-stub.sh"; chmod 755 "$T/accum-stub.sh"
    alarm 0; ALARMD="$ALARMD0"; unset ACCUM_SUT
    { [ -f "$H/archive/HEADLINE-log-20261024.md" ]; } \
      && ok "변이 15(FT_ACCUM_SWEEP 무시) → 스텁 대신 실 도구가 돌아 회귀 «스텁 호출» 단언이 무너진다" || bad "변이 15 미검출"
    rm -f "$T/accum.calls"
  fi
  # 변이 16: git 상한 7초 고정(예산 무시) → R13b «예산+2 안에 끊김» 단언이 무너진다
  MD="$(mut m16 ft_accum_sweep.py '        t = cap()' '        t = 7')"
  if [ -z "$MD" ]; then bad "변이 16 패치 실패"; else
    mkroot m16; printf 'harness\t.\tHEAD\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
    SUTD="$MD"; timed sw FT_ACCUM_BUDGET_SEC=3 FT_ACCUM_GIT="$T/git-slow.sh"; SUTD="$SUTD0"
    { [ "$MS" -gt 5000 ]; } && ok "변이 16(git 상한 7초 고정) → ${MS}ms 로 R13b «≤ 예산+2» 단언이 무너진다" || bad "변이 16 미검출 ${MS}ms"
  fi
  # 변이 17: 백업 스캔 상한 7초 고정(마감 무시) → R19 «예산+2 안에 끊김» 단언이 무너진다
  MD="$(mut m17 ft_accum_sweep.py '    end = time.monotonic() + max(0.0, budget)' '    end = time.monotonic() + 7')"
  if [ -z "$MD" ]; then bad "변이 17 패치 실패"; else
    mkroot m17; for d in a b; do mkdir -p "$R/.fable-team/state/v6-uncommitted-backup-$d"; for i in $(seq 1 200); do mb "$R/.fable-team/state/v6-uncommitted-backup-$d/f$i" 1024; done; done
    SUTD="$MD"; timed sw FT_ACCUM_BUDGET_SEC=3 FT_ACCUM_SCAN_DELAY_MS=50; SUTD="$SUTD0"
    { [ "$MS" -gt 5000 ]; } && ok "변이 17(스캔 상한 7초 고정) → ${MS}ms 로 R19 «≤ 예산+2» 단언이 무너진다" || bad "변이 17 미검출 ${MS}ms"
  fi
  # 변이 18: rc 0 끝 줄도 쪽지 → R17 «rc 0 실행은 쪽지 0» 단언이 무너진다
  MD="$(mut m18 ft_accum_sweep.py '    log(line)
    print(line)' '    log(line)
    print(line)
    send(line, "end")')"
  if [ -z "$MD" ]; then bad "변이 18 패치 실패"; else
    mkroot m18; SUTD="$MD"; sw; SUTD="$SUTD0"
    { [ "$(cnt "$BODYDIR")" = 1 ]; } && ok "변이 18(rc 0 끝 줄도 쪽지) → R17 «rc 0 실행 쪽지 0» 단언이 무너진다" || bad "변이 18 미검출 $(cnt "$BODYDIR")통"
  fi
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
