#!/usr/bin/env bash
# test_r963_unpushed_local_refs.sh — r963 «push 안 된 커밋 하루 요약 = 로컬 ref 만(원격 조회 0)»
# 전부 mktemp 임시 리포 + 가짜 git(PATH 선두 · 추적 + 원격 접촉 차단 + 지정 호출 sleep) — 실 루트·실 명부·실 mbox·실 원격 0 · press 0.
# 케이스: ⓐ 있음/없음/HEAD 분리 셈·꼴 · ⓑ 한 워크트리 rev-list sleep 8 → 표식 0 + ERROR 1줄 + 발신 0 · ⓒ 루트 700자+ → 본문 ≤700 · 절대경로 0
#        ⓓ 로그 경로가 디렉터리 → 잠금 잔류 0 · rc0 · ⓔ FT_TICK_TEAM 있으면 ft-tick 이 부르지 않음 · ⓕ 원격 접촉 0(ls-remote·fetch·pull·push 0)
#        ⓖ ref 확인만 sleep 8 → 표식 0 + ERROR(시간 초과 ≠ 없음) · ⓗ rev-list «0» + rc128 → 표식 0 + ERROR · ⓘ ref 정말 없음(rc1) → 정상 진행 · 표식 1
#  r3 구조(실행기 gq 1곳 + 끝 한 곳 finish_round): ⓐ1 루트 탐색 정상 출력 + rc128 → rc4 · 표식 0 · ERROR «확인 불가 1곳» · 발신 «확인 불가»
#        ⓐ3 git 호출 수 1+2N / 2+2N(늘지 않음) · ⓐ4 안전망 «실행기 밖 git 0줄» · ⓐ5 실패 2곳 주입 → ERROR 1줄에 사유 2 · 표식 0 · 발신 «확인 불가 2곳»
# 변이: «시간 초과도 표식» → ⓑ·ⓐ1 · «절대 경로 본문» → ⓒ · «ls-remote 로 upstream 확인» → ⓕ · «시간 초과 = 없음» → ⓖ · «종료값 안 봄» → ⓗ
#        «gq 안 rc 검사 삭제» → ⓐ1 · «중간 exit 되살림» → ⓐ5(사유 수) · «맨 git 1줄 삽입» → ⓐ4(안전망)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; MIR="$HERE/../../harness/kit/fable-team/bin"
SCRIPT="$BIN/ft-unpushed-summary.sh"; TICK="$BIN/ft-tick.sh"
REALGIT="$(command -v git)"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
NOW=2026-10-26; MARKNAME="$NOW.done"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
cfail=0; p() { echo "PASS $*"; }; f() { echo "FAIL $*"; cfail=1; }
eqv()  { [ "$2" = "$3" ] && p "$1" || f "$1 (기대 '$3' 실제 '$2')"; }
has()  { printf '%s' "$2" | grep -qF -- "$3" && p "$1" || f "$1 (없음: $3)"; }
lacks(){ printf '%s' "$2" | grep -qF -- "$3" && f "$1 (있으면 안 됨: $3)" || p "$1"; }
chars(){ printf '%s' "$1" | python3 -c 'import sys;print(len(sys.stdin.read()))'; }
mkrepo() {  # $1=리포 경로 → 기준 커밋 sha (refs/remotes/origin/main = 그 커밋 · 원격 접촉 없이 «기준선» 만 흉내)
  "$REALGIT" init -q "$1" && "$REALGIT" -C "$1" config user.email t@t && "$REALGIT" -C "$1" config user.name t || return 1
  echo base > "$1/f" && "$REALGIT" -C "$1" add f && "$REALGIT" -C "$1" -c commit.gpgsign=false commit -qm base || return 1
  "$REALGIT" -C "$1" update-ref refs/remotes/origin/main HEAD && "$REALGIT" -C "$1" rev-parse HEAD
}
commits() {  # <리포> <워크트리> <n> <접두>
  local i; for i in $(seq 1 "$3"); do echo "$4$i" >> "$2/f"; "$REALGIT" -C "$2" -c commit.gpgsign=false commit -qam "$4$i" || return 1; done
}
mkroot() {  # 가짜 공용 루트(명부 _master + mbox 스텁)
  mkdir -p "$1/.fable-team/comm" "$1/.fable-team/state"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$T/mbox.calls" > "$1/.fable-team/comm/mbox.sh"
  printf '{"_version":"1.0.0","_master":"byz-tt-master#1"}\n' > "$1/.fable-team/seats-harness.json"
}
mkdir -p "$T/fakebin"
cat > "$T/fakebin/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "\$TRACE"
if [ -n "\${FAKE_SLEEP_ARG:-}" ]; then case "\$*" in *"\$FAKE_SLEEP_ARG"*) sleep 8;; esac; fi
if [ -n "\${FAKE_BADRC_ARG:-}" ]; then case "\$*" in *"\$FAKE_BADRC_ARG"*) printf '%s\n' "\${FAKE_BADRC_OUT:-0}"; exit "\${FAKE_BADRC:-128}";; esac; fi
for a in "\$@"; do case "\$a" in ls-remote|fetch|pull|push) exit 128;; esac; done
exec "$REALGIT" "\$@"
EOF
chmod +x "$T/fakebin/git"
remote_calls() { grep -Eq '(^| )(ls-remote|fetch|pull|push)( |$)' "$T/trace" 2>/dev/null; }
# ── 픽스처: A=로컬 추적 ref 있음(2) · B=없음(3) · C=HEAD 분리 ──
BASE="$(mkrepo "$T/repo")" || { echo "FAIL 픽스처 리포"; exit 1; }
"$REALGIT" -C "$T/repo" worktree add -q -b brA "$T/wt-a" "$BASE" && commits "$T/repo" "$T/wt-a" 2 a
"$REALGIT" -C "$T/repo" update-ref refs/remotes/origin/brA "$BASE"
"$REALGIT" -C "$T/repo" worktree add -q -b brB "$T/wt-b" "$BASE" && commits "$T/repo" "$T/wt-b" 3 b
"$REALGIT" -C "$T/repo" worktree add -q --detach "$T/wt-c" "$BASE"
LP="$T/lang"; while [ "${#LP}" -lt 700 ]; do LP="$LP/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; done
LBASE="$(mkrepo "$LP")" && "$REALGIT" -C "$LP" worktree add -q -b brL "$LP/wt-long" "$LBASE" && commits "$LP" "$LP/wt-long" 2 l
"$REALGIT" -C "$LP" update-ref refs/remotes/origin/brL "$LBASE"
mkroot "$T/root-a"; mkroot "$T/root-e"
printf '{"_version":"1.0.0","_master":"byz-tt-master#1","byz-tt-master#1":{"role":"master","agent":"pi","tick":"ft-master-tick","index":"x"}}\n' > "$T/root-e/.fable-team/seats.json"
runs() {  # <스크립트> <루트> <상태폴더> <stderr 파일> [추가 env…] → stdout(rc 는 $RRC)
  local s="$1" r="$2" st="$3" ef="$4"; shift 4
  env PATH="$T/fakebin:$PATH" TRACE="$T/trace" FT_ROOT="$r" FT_UNPUSHED_STATE_DIR="$st" FT_UNPUSHED_NOW="$NOW" \
      FT_UNPUSHED_MIN=1 FT_UNPUSHED_BASE=origin/main "$@" bash "$s" --repo "$T/repo" 2>"$ef"
  printf '%s' "$?" > "$T/rc"
}
newst() { mktemp -d "$T/st-XXXXXX"; }
cnt() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
# ── ⓐ 셈·꼴 ──
case_a() {
  cfail=0; local out err SA; SA="$(newst)"
  : > "$T/trace"
  out="$(runs "$SCRIPT" "$T/root-a" "$SA" "$T/a.err" FT_UNPUSHED_DRY=1)"; err="$(cat "$T/a.err")"; RRC="$(cat "$T/rc")"
  eqv 'ⓐ rc=0(--dry-run)' "$RRC" 0
  has 'ⓐ 본문 «미push 2곳»' "$out" '미push 2곳'
  has 'ⓐ 본문 «HEAD 분리 1곳»' "$out" 'HEAD 분리 1곳'
  has 'ⓐ 로컬 추적 ref 셈=2' "$err" 'LIST wt-a · brA · 로컬 추적 ref=2'
  has 'ⓐ 원격 가지 없음 셈=3' "$err" 'LIST wt-b · brB · 원격 가지 없음 · main 에 없는 커밋=3'
  has 'ⓐ 본문 꼴(전체 = 상대 이름)' "$out" '전체 = unpushed/2026-10-26.txt'
  lacks 'ⓐ dry-run 은 표식 안 씀' "$(ls "$SA" 2>/dev/null)" "$MARKNAME"
  return $cfail
}
# ── ⓑ 한 워크트리만 sleep 8 → 미완주(표식 0 · ERROR 1줄 · 발신 0) ──
case_b() {
  cfail=0; local err n0 n1 SB; SB="$(newst)"
  n0="$(cnt "$T/mbox.calls")"
  runs "$SCRIPT" "$T/root-a" "$SB" "$T/b.err" FAKE_SLEEP_ARG='rev-list --count refs/remotes/origin/brA..HEAD' >/dev/null
  err="$(cat "$T/b.err")"; RRC="$(cat "$T/rc")"
  eqv 'ⓑ rc=4(미완주)' "$RRC" 4
  has 'ⓑ ERROR 1줄' "$err" 'ERROR r963 미완주'
  lacks 'ⓑ 표식 0' "$(ls "$SB" 2>/dev/null)" "$MARKNAME"
  lacks 'ⓑ 전체 파일도 0' "$(ls "$SB" 2>/dev/null)" "$NOW.txt"
  eqv 'ⓑ 잠금 잔류 0' "$([ -d "$SB/lock" ] && echo 있음 || echo 없음)" 없음
  eqv 'ⓑ 발신 1통(확인 불가)' "$(( $(cnt "$T/mbox.calls") - n0 ))" 1
  has 'ⓑ 발신 본문에 확인 불가' "$(tail -1 "$T/mbox.calls")" '확인 불가'
  lacks 'ⓑ 발신 본문에 «문턱» 0' "$(tail -1 "$T/mbox.calls")" '문턱'
  return $cfail
}
# ── ⓒ 루트 경로 700자+ → 본문 ≤700 · 절대 경로 0 ──
case_c() {
  cfail=0; local out s="$SCRIPT"
  : > "$T/trace"
  out="$(env PATH="$T/fakebin:$PATH" TRACE="$T/trace" FT_ROOT="$LP" FT_UNPUSHED_STATE_DIR="$(newst)" FT_UNPUSHED_NOW="$NOW" \
        FT_UNPUSHED_MIN=1 bash "$s" --repo "$LP" --dry-run 2>"$T/c.err")"; RRC=$?
  eqv 'ⓒ rc=0' "$RRC" 0
  has 'ⓒ 셈 1곳' "$out" '미push 1곳'
  [ "$(chars "$out")" -le 700 ] && p 'ⓒ 본문 ≤700자' || f "ⓒ 본문 $(chars "$out")자(>700) — 루트 ${#LP}자"
  has 'ⓒ 이름 = 바닥 이름' "$out" 'wt-long(2)'
  lacks 'ⓒ 본문에 절대 경로 없음' "$out" "$LP"
  return $cfail
}
# ── ⓓ 로그 경로가 디렉터리 → 잠금 잔류 0 · rc0 · 표식 1 ──
case_d() {
  cfail=0; local err n0 n1 SD; SD="$(newst)"
  rm -rf "$T/alogdir"; mkdir -p "$T/alogdir"
  n0="$(cnt "$T/mbox.calls")"
  runs "$SCRIPT" "$T/root-a" "$SD" "$T/d.err" FT_UNPUSHED_LOG="$T/alogdir" >/dev/null; err="$(cat "$T/d.err")"; RRC="$(cat "$T/rc")"
  eqv 'ⓓ rc=0(로그 실패와 분리)' "$RRC" 0
  has 'ⓓ 경고 1줄' "$err" 'WARN 로그 쓰기 실패'
  eqv 'ⓓ 표식 있음' "$([ -e "$SD/$MARKNAME" ] && echo 있음 || echo 없음)" 있음
  eqv 'ⓓ 잠금 잔류 0' "$([ -d "$SD/lock" ] && echo 있음 || echo 없음)" 없음
  eqv 'ⓓ 발신 1통' "$(( $(cnt "$T/mbox.calls") - n0 ))" 1
  return $cfail
}
# ── ⓔ ft-tick: FT_TICK_TEAM 있으면 부르지 않는다 ──
case_e() {
  cfail=0; local out
  mkdir -p "$T/stamp" "$T/ftstate"
  tick() { env FT_ROOT="$T/root-e" FT_TICK_SEATS="$T/root-e/.fable-team/seats.json" FT_TICK_STATE_DIR="$T/ftstate" \
      FT_TICK_STAMP_PREFIX="$T/stamp/" FT_TICK_PIDFILE="$T/tick.pid" ${1:+FT_TICK_TEAM="$1"} /bin/bash "$TICK" --dry-run 2>&1; }
  out="$(tick)";          has  'ⓔ 팀 틱 아님 → 부름' "$out" 'kind=unpushed-daily'
  out="$(tick harness)";  lacks 'ⓔ 팀 틱 → 실행 0' "$out" 'kind=unpushed-daily'
  return $cfail
}
# ── ⓕ 원격 접촉 0 ──
case_f() {
  cfail=0
  : > "$T/trace"
  env PATH="$T/fakebin:$PATH" TRACE="$T/trace" FT_ROOT="$T/root-a" FT_UNPUSHED_STATE_DIR="$(newst)" FT_UNPUSHED_NOW="$NOW" \
      FT_UNPUSHED_MIN=1 bash "$SCRIPT" --repo "$T/repo" >/dev/null 2>&1
  if remote_calls; then f "ⓕ 원격 접촉 0 (원격 호출 있음: $(grep -E '(^| )(ls-remote|fetch|pull|push)( |$)' "$T/trace" | head -1))"; else p 'ⓕ 원격 접촉 0'; fi
  has 'ⓕ 로컬 ref 만 씀' "$(cat "$T/trace")" 'show-ref --verify --quiet refs/remotes/origin/brA'
  return $cfail
}
# ── ⓖ 추적 ref 확인만 sleep 8 → 시간 초과를 «없음» 으로 접지 않는다(표식 0 · ERROR · 발신 0) ──
case_g() {
  cfail=0; local err n0 SG; SG="$(newst)"
  n0="$(cnt "$T/mbox.calls")"
  runs "$SCRIPT" "$T/root-a" "$SG" "$T/g.err" FAKE_SLEEP_ARG='show-ref --verify --quiet refs/remotes/origin/brA' >/dev/null
  err="$(cat "$T/g.err")"; RRC="$(cat "$T/rc")"
  eqv 'ⓖ rc=4(미완주)' "$RRC" 4
  has 'ⓖ ERROR 1줄' "$err" 'ERROR r963 미완주'
  has 'ⓖ 까닭에 ref 확인 실패' "$err" '추적 ref 확인 실패'
  lacks 'ⓖ 표식 0' "$(ls "$SG" 2>/dev/null)" "$MARKNAME"
  eqv 'ⓖ 발신 1통(확인 불가)' "$(( $(cnt "$T/mbox.calls") - n0 ))" 1
  lacks 'ⓖ 발신 본문에 «문턱» 0' "$(tail -1 "$T/mbox.calls")" '문턱'
  return $cfail
}
# ── ⓗ rev-list 가 «0» 을 찍고 rc128 → 정상 0 으로 받지 않는다(표식 0 · ERROR) ──
case_h() {
  cfail=0; local err SH; SH="$(newst)"
  runs "$SCRIPT" "$T/root-a" "$SH" "$T/h.err" FAKE_BADRC_ARG='rev-list --count refs/remotes/origin/brA..HEAD' FAKE_BADRC_OUT=0 >/dev/null
  err="$(cat "$T/h.err")"; RRC="$(cat "$T/rc")"
  eqv 'ⓗ rc=4(미완주)' "$RRC" 4
  has 'ⓗ ERROR 1줄' "$err" 'ERROR r963 미완주'
  has 'ⓗ 까닭에 rev-list 실패' "$err" 'rev-list 실패'
  lacks 'ⓗ 표식 0' "$(ls "$SH" 2>/dev/null)" "$MARKNAME"
  return $cfail
}
# ── ⒤ 추적 ref 가 «정말 없음»(rc1) → 실패가 아니다(정상 진행 · 표식 1 · ERROR 0) ──
case_i() {
  cfail=0; local err SI; SI="$(newst)"
  : > "$T/trace"
  runs "$SCRIPT" "$T/root-a" "$SI" "$T/i.err" >/dev/null; err="$(cat "$T/i.err")"; RRC="$(cat "$T/rc")"
  eqv '⒤ rc=0(없음은 정상)' "$RRC" 0
  lacks '⒤ ERROR 0' "$err" 'ERROR'
  has '⒤ ref 없음도 확인함(종료값 사용)' "$(cat "$T/trace")" 'show-ref --verify --quiet refs/remotes/origin/brB'
  eqv '⒤ 표식 1' "$([ -e "$SI/$MARKNAME" ] && echo 있음 || echo 없음)" 있음
  return $cfail
}
# ── ⓐ1 루트 탐색이 «정상 출력 + rc≠0» (r2 반례 그대로 · FT_ROOT 해제 · --repo) ──
runs_nr() {  # FT_ROOT 없이 · 명부·mbox 경로 명시(루트 탐색이 실패해도 발신 경로는 남긴다)
  local s="$1" st="$2" ef="$3"; shift 3
  env PATH="$T/fakebin:$PATH" TRACE="$T/trace" FT_UNPUSHED_STATE_DIR="$st" FT_UNPUSHED_NOW="$NOW" \
      FT_UNPUSHED_MIN=1 FT_UNPUSHED_BASE=origin/main \
      FT_UNPUSHED_SEATS="$T/root-a/.fable-team/seats-harness.json" \
      FT_TICK_MBOX="$T/root-a/.fable-team/comm/mbox.sh" "$@" bash "$s" --repo "$T/repo" 2>"$ef"
  printf '%s' "$?" > "$T/rc"
}
case_a1() {
  cfail=0; local err n0 S; S="$(newst)"; n0="$(cnt "$T/mbox.calls")"; : > "$T/trace"
  runs_nr "$SCRIPT" "$S" "$T/a1.err" FAKE_BADRC_ARG='--git-common-dir' FAKE_BADRC_OUT="$T/root-a" FAKE_BADRC=128 >"$T/a1.out"
  err="$(cat "$T/a1.err")"; RRC="$(cat "$T/rc")"
  eqv 'ⓐ1 rc=4(정상 출력 + rc128)' "$RRC" 4
  has 'ⓐ1 ERROR 에 사유' "$err" '확인 불가 1곳: 루트 탐색 rc=128'
  lacks 'ⓐ1 표식 0' "$(ls "$S" 2>/dev/null)" "$MARKNAME"
  eqv 'ⓐ1 발신 1통' "$(( $(cnt "$T/mbox.calls") - n0 ))" 1
  has 'ⓐ1 발신 본문 «확인 불가»' "$(tail -1 "$T/mbox.calls")" '확인 불가'
  lacks 'ⓐ1 본문에 «문턱» 0' "$(cat "$T/a1.out")" '문턱'
  return $cfail
}
# ── ⓐ3 정상: git 호출 수 = 1+2N(FT_ROOT 있음) · 2+2N(없음) — 실행기 도입으로 늘지 않는다 ──
case_a3() {
  cfail=0; local n S; S="$(newst)"; : > "$T/trace"
  runs "$SCRIPT" "$T/root-a" "$S" "$T/a3.err" >/dev/null
  n="$(cnt "$T/trace")"; eqv 'ⓐ3 호출 수 = 1+2N(FT_ROOT 있음 · N=3)' "$n" 7
  S="$(newst)"; : > "$T/trace"
  runs_nr "$SCRIPT" "$S" "$T/a3b.err" >/dev/null
  n="$(cnt "$T/trace")"; eqv 'ⓐ3 호출 수 = 2+2N(FT_ROOT 없음)' "$n" 8
  return $cfail
}
# ── ⓐ4 안전망: 본문에 «실행기 밖 git » 0줄 ──
safety_lines() {
  python3 - "$1" <<'PYSAFE'
import re,sys
for i,line in enumerate(open(sys.argv[1],encoding="utf-8").read().splitlines(),1):
    s=line.strip()
    if s.startswith("#"): continue                                  # ② 주석 줄
    if '"$TB"' in line and "gc.auto=0" in line: continue            # ① 실행기 호출 1줄
    t=re.sub(r'"[^"]*"','""',line); t=re.sub(r"'[^']*'","''",t)     # ③ 따옴표 안 문자열
    if re.search(r'(^|[^A-Za-z0-9_])git ',t): print("%d:%s"%(i,s))
PYSAFE
}
case_a4() {
  cfail=0
  eqv 'ⓐ4 실행기 밖 git 0줄' "$(safety_lines "$SCRIPT")" ''
  return $cfail
}
# ── ⓐ5 실패 2곳(루트 rc128 + ref 시간 초과) → 모아서 1줄·표식 0·발신 1 ──
case_a5() {
  cfail=0; local err n0 S; S="$(newst)"; n0="$(cnt "$T/mbox.calls")"
  runs_nr "$SCRIPT" "$S" "$T/a5.err" FAKE_BADRC_ARG='--git-common-dir' FAKE_BADRC_OUT="$T/root-a" FAKE_BADRC=128 \
    FAKE_SLEEP_ARG='show-ref --verify --quiet refs/remotes/origin/brA' >"$T/a5.out"
  err="$(cat "$T/a5.err")"; RRC="$(cat "$T/rc")"
  eqv 'ⓐ5 rc=4' "$RRC" 4
  has 'ⓐ5 사유 2 모음' "$err" '확인 불가 2곳: 루트 탐색 rc=128'
  has 'ⓐ5 사유에 추적 ref 확인 실패' "$err" '추적 ref 확인 실패'
  eqv 'ⓐ5 ERROR 1줄' "$(printf '%s\n' "$err" | grep -c '^ERROR r963 미완주')" 1
  lacks 'ⓐ5 표식 0' "$(ls "$S" 2>/dev/null)" "$MARKNAME"
  eqv 'ⓐ5 발신 1통' "$(( $(cnt "$T/mbox.calls") - n0 ))" 1
  has 'ⓐ5 발신 본문 «확인 불가 2곳»' "$(tail -1 "$T/mbox.calls")" '확인 불가 2곳'
  return $cfail
}
run_case() { local out; out="$( SCRIPT="${2:-$SCRIPT}" "case_$1" 2>&1 )"; local rc=$?; [ "${3:-}" = q ] || printf '%s\n' "$out"; return $rc; }
mut() {  # <이름> <옛 문자열> <새 문자열> → $T/mut-<이름>.sh
  python3 - "$SCRIPT" "$T/mut-$1.sh" "$2" "$3" <<'PY' || return 1
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert s.count(old) == 1, f"변이 대상이 1회가 아니다: {old[:40]}"
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
PY
  chmod +x "$T/mut-$1.sh"
}
# ── 파일 위생 ──
for f in "$SCRIPT" "$MIR/ft-unpushed-summary.sh" "$TICK"; do
  [ -f "$f" ] && ok "있어야 함: $(basename "$f")" || bad "없음: $f"
done
bash -n "$SCRIPT" && ok 'bash -n' || bad 'bash -n'
/bin/bash -n "$SCRIPT" && ok '/bin/bash 3.2 -n' || bad '/bin/bash -n'
[ "$(wc -l < "$SCRIPT")" -le 200 ] && ok '≤200줄' || bad '200줄 초과'
cmp -s "$SCRIPT" "$MIR/ft-unpushed-summary.sh" && ok 'kit 짝 cmp0' || bad 'kit 짝 불일치'
cmp -s "$TICK" "$MIR/ft-tick.sh" && ok 'ft-tick 짝 cmp0' || bad 'ft-tick 짝 불일치'
for c in a a1 a3 a4 a5 b c d e f g h i; do run_case "$c" >/dev/null 2>&1 && ok "케이스 $c" || bad "케이스 $c"; done
run_case a; run_case a1; run_case a3; run_case a4; run_case a5; run_case b; run_case c; run_case d; run_case e; run_case f; run_case g; run_case h; run_case i
# ── 변이 3종이 각각 잡히는가 ──
GQL1='  out="$("$TB" "$left" git -c gc.auto=0 "$@" 2>/dev/null)"; rc=$?'
if mut m1 '  err "ERROR r963 미완주' '  : > "$MARK" 2>/dev/null; err "ERROR r963 미완주' &&
   mut m2 'name_of() { local b; b="$(basename "$1")"; printf '"'"'%s'"'"' "${b:0:60}"; }' 'name_of() { printf '"'"'%s'"'"' "$1"; }' &&
   mut m3 '  [ -n "${p:-}" ] || continue' '  [ -n "${p:-}" ] || continue
  gq "0" "원격 확인" -C "$REPO" ls-remote origin >/dev/null 2>&1' &&
   mut m4 "$GQL1
  GQ_RC=\"\$rc\"; GQ_OUT=\"\"
  case \"\$rc\" in 124|128) hard=1;; *) hard=0;; esac" "$GQL1
  [ \"\$rc\" = 124 ] && rc=1
  GQ_RC=\"\$rc\"; GQ_OUT=\"\"
  case \"\$rc\" in 124|128) hard=1;; *) hard=0;; esac" &&
   mut m5 "$GQL1
  GQ_RC=\"\$rc\"; GQ_OUT=\"\"" "$GQL1
  [ -n \"\$out\" ] && rc=0
  GQ_RC=\"\$rc\"; GQ_OUT=\"\"" &&
   mut m6 '  FAILS+=("$why rc=$rc"); return 1' '  GQ_OUT="$out"; return 0' &&
   mut m7 '  FAILS+=("$why rc=$rc"); return 1' '  FAILS+=("$why rc=$rc"); exit 4' &&
   mut m9 '  [ -n "${p:-}" ] || continue' '  [ -n "${p:-}" ] || continue
  git rev-parse --show-toplevel >/dev/null 2>&1'; then
  run_case b  "$T/mut-m1.sh" q && bad '변이 ① «시간 초과도 표식» → ⓑ FAIL 해야 함' || ok '변이 ① «시간 초과도 표식» → ⓑ FAIL(잡음)'
  run_case a1 "$T/mut-m1.sh" q && bad '변이 ① «끝 한 곳 밖 표식» → ⓐ1 FAIL 해야 함' || ok '변이 ① «끝 한 곳 밖 표식» → ⓐ1 FAIL(잡음)'
  run_case c "$T/mut-m2.sh" q && bad '변이 ② «절대 경로 본문» → ⓒ FAIL 해야 함' || ok '변이 ② «절대 경로 본문» → ⓒ FAIL(잡음)'
  run_case f "$T/mut-m3.sh" q && bad '변이 ③ «ls-remote 로 upstream 확인» → ⓕ FAIL 해야 함' || ok '변이 ③ «ls-remote 확인» → ⓕ FAIL(잡음)'
  run_case g "$T/mut-m4.sh" q && bad '변이 ④ «시간 초과 = 없음» → ⓖ FAIL 해야 함' || ok '변이 ④ «시간 초과 = 없음» → ⓖ FAIL(잡음)'
  run_case h "$T/mut-m5.sh" q && bad '변이 ⑤ «종료값 안 봄» → ⓗ FAIL 해야 함' || ok '변이 ⑤ «종료값 안 봄» → ⓗ FAIL(잡음)'
  run_case a1 "$T/mut-m6.sh" q && bad '변이 ⑥ «gq 안 rc 검사 삭제» → ⓐ1 FAIL 해야 함' || ok '변이 ⑥ «gq 안 rc 검사 삭제» → ⓐ1 FAIL(잡음)'
  run_case a5 "$T/mut-m7.sh" q && bad '변이 ⑦ «중간 exit 되살림» → ⓐ5 FAIL 해야 함' || ok '변이 ⑦ «중간 exit 되살림» → ⓐ5 FAIL(잡음)'
  [ -n "$(safety_lines "$T/mut-m9.sh")" ] && ok '변이 ⑧ «맨 git 1줄» → 안전망 FAIL(잡음)' || bad '변이 ⑧ «맨 git 1줄» → 안전망이 못 잡음'
else bad '변이본 생성 실패'; fi
echo "── r963 결과: fail=$fail"
[ "$fail" = 0 ] || exit 1
exit 0
