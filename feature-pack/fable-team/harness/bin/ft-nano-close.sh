#!/usr/bin/env bash
# ft-nano-close.sh <좌석> --result <산출경로> --recv <master seq> [--kill]
#   Seatbelt 0.3 · 나노 좌석을 «값으로» 닫는다 (SEATBELT-README §3 닫기 · NANO-LEDGER 종료조건 3).
#   exit 0 = 닫힘(명부 삭제·원장 append·@zc_v65_active 해제·세션 kill) · 1 = REJECT(조건 미충족) 또는 FAIL(해제/kill 실패, 사유 stdout) · 2 = usage
#   --kill 은 호환용 — 닫으면 항상 태그 해제 + kill-session(2026-10-02 · keep-last-2 검사 삭제, nano 계보는 대상 아님).
# 종료조건 3 (전부 «값»): ①--result 경로 실재 ②--recv master 회수 seq 가 우편함/bodies 에 실재 ③jsonl 마지막 활동 ≥ IDLE_MIN 분 전
# 종료조건 ④ (팩 1.0.2): press/시험 카드면 마지막 checkpoint 표 실재 + alarm=no (checkpoint.json 미설정 프로젝트는 경고만).
# 하네스 0.5 행 2 r3 (표준승인 2026-09-25 · ~/.claude/CLAUDE.md HIL 절 · DA r1 조건 1~7 · DA r2 조건 1~5):
#   close 는 워크트리 정리 계획을 «생성만» 한다(.fable-team/state/wt-clean/<seat>.sh · 원장 행 wt=planned). 조건 ③이 세션 실재를 요구하므로
#   close 시점엔 좌석이 살아 있다 — 실행은 «세션이 사라진 뒤»: --kill 이 KILLED 를 낸 직후, 또는 ft-wt-sweep.sh(ft-tick.sh 가 매 루프 호출 · r3 배선).
#   계획 스크립트가 가드 6(계보 세션 자기 포함 0 · 워크트리 cwd 보유 프로세스 0 · info branch nano/* · HEAD=branch+도달성 · 실작업물은 WIP 커밋(r7) · ignored 보관)과
#   원장 표식(wt=… · 좌석명 행 · mkdir 락)을 맡는다. ★가드 도구(lsof·tmux) 실패 = skipped(fail-closed · DA r2 R12)★. 브랜치는 절대 지우지 않는다.
#   FT_WT_AUTOCLEAN=0 = 실행 경로 전부 끔(계획만 남김). 원장 경로는 리포 고정(ROOT 기준 · DA r2 MINOR C) — FT_NANO_LEDGER 로 override.
set -uo pipefail
SEAT="${1:-}"; shift || { echo "usage: $0 <seat> --result <path> --recv <seq> [--kill]" >&2; exit 2; }
RESULT=""; RECV=""; KILL=1; IDLE_MIN="${FT_NANO_IDLE_MIN:-3}"
while [ $# -gt 0 ]; do case "$1" in --result) RESULT="$2"; shift 2;; --recv) RECV="$2"; shift 2;; --kill) KILL=1; shift;; *) echo "unknown $1" >&2; exit 2;; esac; done
NANO_PREFIX="${FT_NANO_PREFIX:-ft-v65-temp-}"
case "$SEAT" in "$NANO_PREFIX"*) ;; *) echo "REJECT 나노(${NANO_PREFIX}*)만 닫는다: $SEAT"; exit 1;; esac   # role 무관(nano·impl·checker·tester 전부 temp- 접두)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"
SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"; COMM="${FT_INBOX_ROOT:-$ROOT/.fable-team/comm}"
# 원장 = 리포 고정(운영 정본 = v6-realtime-live 워크트리 · FT_NANO_LEDGER_WT 로 override). $WT 에 묶지 않는다 — 나노가 자기 워크트리에서 부르면 원장이 삭제 대상 안에 놓인다(DA r2 C).
LEDGER_WT="${FT_NANO_LEDGER_WT:-$ROOT/.worktrees/v6-realtime-live}"; [ -d "$LEDGER_WT" ] || LEDGER_WT="$WT"
LEDGER="${FT_NANO_LEDGER:-design/v65/20260912/NANO-LEDGER-pm1-temp-sessions.md}"; case "$LEDGER" in /*) ;; *) LEDGER="$LEDGER_WT/$LEDGER";; esac
WT_CLEAN_DIR="${FT_WT_CLEAN_DIR:-$ROOT/.fable-team/state/wt-clean}"

# 계획 «생성» — 좌석의 워크트리 = $ROOT/.worktrees/v65-<seat 에서 접두·#N 제거>. 없으면 PLAN="" · WT_MARK=none.
# key 는 $_KEY(하단 ③ 에서 1회 계산) 를 그대로 쓴다 — 두 곳에서 따로 계산하면 한쪽만 바뀔 때 ABSENT 판정과 계획 워크트리가 어긋난다(DA r5 MINOR 3).
_wt_clean_plan() {
  local key="$_KEY"
  local wt="$ROOT/.worktrees/v65-$key"
  PLAN=""; WT_MARK=none
  [ -d "$wt" ] || return 0
  mkdir -p "$WT_CLEAN_DIR"; PLAN="$WT_CLEAN_DIR/$SEAT.sh"; WT_MARK=planned
  [ "${FT_WT_AUTOCLEAN:-1}" != 0 ] || WT_MARK="planned(autoclean=0)"
  {
    printf '#!/bin/bash\n# wt-clean 계획 — ft-nano-close.sh 가 %s 에 생성. 가드 6 → ignored 보관 → WIP 커밋 → baton wt-clean → 원장 표식. 브랜치는 지우지 않는다.\n' "$(date '+%Y-%m-%d %H:%M')"
    printf '# baton 부작용(승인 범위에 명시): 아카이브 30일 초과분 prune · 분기 원장(.baton/branches.json) 의 같은 child_branch 행 status=abandoned.\n'
    # FT_NANO_WIP 는 close 실행 시점 값을 계획에 «굽는다» — sweep 은 나중 다른 프로세스/환경에서 돌아 close 의 env 를 못 물려받는다.
    printf 'SEAT=%q; KEY=%q; WT=%q; PREFIX=%q; LEDGER=%q; PLAN=%q; FT_NANO_WIP=%q\n' "$SEAT" "$key" "$wt" "$NANO_PREFIX" "$LEDGER" "$PLAN" "${FT_NANO_WIP:-0}"
    cat <<'SH'
set -uo pipefail
BATON="${BATON_BIN:-$HOME/.baton/current/bin/baton}"
# ★변수명 TMUX 금지★ — tmux 가 $TMUX 를 소켓 경로로 읽는다(r3 시험에서 «error connecting to /opt/homebrew/bin/tmux» 실측). 바이너리는 TMUX_BIN.
LSOF="${FT_LSOF_BIN:-/usr/sbin/lsof}"; TMUX_BIN="${FT_TMUX_BIN:-$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)}"
# 원장 표식 — 좌석명 행(그 좌석의 «마지막» 닫힘 행)의 wt= 필드 교체. mkdir 락(<원장>.lock · 최대 10s) 아래 read→write · 실패는 stdout+exit 1 (#0 RULE · DA r2 B)
mark() {
  local lock="$LEDGER.lock" i=0 rc
  until mkdir "$lock" 2>/dev/null; do i=$((i+1)); [ "$i" -lt 100 ] || { echo "skipped:원장 락 실패($lock)"; exit 1; }; sleep 0.1; done
  python3 - "$LEDGER" "$SEAT" "$1" <<'PY'
import os, re, sys
p, seat, val = sys.argv[1:4]
s = open(p, encoding="utf-8").read(); lines = s.split("\n")
key = "`%s` 닫힘(ft-nano-close)" % seat
idx = [i for i, l in enumerate(lines) if key in l]
if not idx: sys.exit(3)
i = idx[-1]; lines[i] = re.sub(r"( · wt=.*)?$", " · wt=" + val, lines[i], count=1)
tmp = p + ".tmp.%d" % os.getpid()
with open(tmp, "w", encoding="utf-8") as f: f.write("\n".join(lines)); f.flush(); os.fsync(f.fileno())
os.replace(tmp, p)
PY
  rc=$?; rmdir "$lock"
  [ "$rc" -eq 0 ] || { echo "skipped:원장 표식 실패(rc=$rc · $SEAT 행 없음=3)"; exit 1; }
}
fail() { mark "skipped:$1"; echo "skipped:$1"; exit 1; }
[ -d "$WT" ] || { mark none; echo none; exit 0; }
# ① 계보(<PREFIX><KEY>#N) 세션 — «자기 포함» 0. tmux 실패는 「no server running」만 0세션으로 인정, 그 외(바이너리 없음·소켓 오류)는 skipped (DA r2 R12)
# r8(DA r7 조건1): rc=1 요건 추가 — 「소켓 없음」 문구만 0세션(그 외 rc1 연결 장애는 skipped, close 쪽과 같은 좁힘).
[ -x "$TMUX_BIN" ] || fail "tmux 실행 불가($TMUX_BIN)"
out="$("$TMUX_BIN" ls -F '#{session_name}' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  case "$rc:$out" in
    1:*"no server running"*) out="";;
    1:*"error connecting to "*"(No such file or directory)"*)
      # r9(오빠 판정 ㉙ Q5)+r10(DA r9 M1·M2): 소켓 파일만 없고 서버 프로세스가 살아있으면 고아 서버 — 0세션이 아니라 REJECT.
      # M2: -a 로 호출자 조상(서버 자신) 도 포함(pgrep 기본은 조상 제외). M1: -U "$(id -u)" 로 fail-open 제거 · rc 를 |wc -l 로 삼키지 않고 분리.
      n=0
      op="$(pgrep -a -U "$(id -u)" -x tmux 2>&1)"; prc=$?
      case "$prc" in 0) n="$(printf '%s\n' "$op" | grep -c .)";; 1) n=0;; *) fail "pgrep 실패(rc=$prc: ${op:0:60})";; esac
      if [ -n "${FT_TMUX_BIN:-}" ]; then
        op2="$(pgrep -a -U "$(id -u)" -f "$TMUX_BIN" 2>&1)"; prc2=$?
        case "$prc2" in 0) n=$((n + $(printf '%s\n' "$op2" | grep -c .)));; 1) ;; *) fail "pgrep 실패(rc=$prc2: ${op2:0:60})";; esac
      fi
      [ "$n" -eq 0 ] || fail "③고아 tmux 서버(pgrep ${n} · 소켓 부재)"
      out="";;
    *) fail "tmux 조회 실패(rc=$rc: ${out:0:60})";;
  esac
fi
live="$(printf '%s\n' "$out" | grep -x "${PREFIX}${KEY}#[0-9]*" | tr '\n' ' ')"
[ -z "$live" ] || fail "좌석 ${live% }"
# ② 워크트리를 cwd 로 쥔 프로세스 0 (tmux 밖 node·mcp·zsh 포함). lsof 절대경로 + 실행 가능 + 종료코드를 grep 과 분리(fail-closed · DA r2 R12)
[ -x "$LSOF" ] || fail "lsof 실행 불가($LSOF)"
lsout="$("$LSOF" -Fn -d cwd 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] || fail "lsof 실패(rc=$rc)"
holders="$(printf '%s\n' "$lsout" | grep -cE "^n${WT}(/|$)")"
[ "$holders" -eq 0 ] || fail "cwd 보유 프로세스 ${holders}개"
# ③ .worktree-info.json 의 branch 가 nano/*
br="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("branch",""))' "$WT/.worktree-info.json" 2>/dev/null)"
case "$br" in nano/*) ;; *) fail "branch=${br:-?} (nano/* 아님)";; esac
# ④ 도달성 — HEAD 브랜치 = info branch(detached 금지) 이고 HEAD 가 refs/heads/<br> 에 포함 (DA r1 R1②)
hb="$(git -C "$WT" symbolic-ref --short -q HEAD)"
[ "$hb" = "$br" ] || fail "HEAD=${hb:-detached} ≠ info $br"
git -C "$WT" merge-base --is-ancestor HEAD "refs/heads/$br" || fail "HEAD 가 $br 에 미포함"
# ⑤ 미커밋 상태 확인.
#   r8(DA r7 잔여 질문1): #30467 「dirty 는 [wip] 커밋」은 20건 백필 맥락이었다 — 답 전까지 «백필 한정 플래그»로 분리해
#   어느 판정이든(영구 적용/백필 한정) 수용한다. FT_NANO_WIP=1 일 때만 아래 새 경로, 미설정(기본)은 r6 이전 기존 REJECT.
if [ "${FT_NANO_WIP:-0}" = 1 ]; then
  # r7 · 하네스 0.5 행 2 · 오빠 판정 #30467 「dirty 는 [wip] 커밋 경로」 · DA r6 잔여 질문 2 정리.
  # 브랜치는 지우지 않으므로 커밋해 두면 baton wt-clean 뒤에도 git 이력으로 복원 가능 — REJECT 로 워크트리를 잔존시키는 쪽이 더 나쁘다(#0 RULE).
  # r8(DA r7 MAJOR 2): baton 자신이 만드는 임시 재생성물 .unmerged-changes.patch 는 커밋 대상이 아니다 — add -A 전에 지운다(언제든 재생성됨).
  rm -f "$WT/.unmerged-changes.patch"
  dirty="$(git -C "$WT" status --porcelain)"
  # r8(DA r7 MAJOR 2): untracked 합계 상한 — baton 산출물이 중단돼 수 GB 로 남으면 커밋이 눈덩이가 된다(k6/k7 실측). 상한 초과는 REJECT(사람 판정).
  cap="${FT_WT_DIRTY_CAP_BYTES:-52428800}"
  usum=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    sz="$(stat -f '%z' "$WT/$p" 2>/dev/null || echo 0)"
    usum=$((usum + sz))
  done < <(git -C "$WT" ls-files -o --exclude-standard)
  [ "$usum" -le "$cap" ] || fail "dirty 대용량(${usum}B > ${cap}B)"
else
  # 기존(r6 이전) 동작 — 실작업물(.serena/project.yml 제외) 있으면 REJECT, .serena 만 있으면 그 아래 WIP 커밋으로.
  dirty="$(git -C "$WT" status --porcelain)"
  real="$(printf '%s\n' "$dirty" | grep -v '\.serena/project\.yml$' | grep -c .)"
  [ "$real" -eq 0 ] || fail "실작업물 미커밋 ${real}파일"
fi
# ⑥ ignored — 재생성 허용 목록(이름 · «임의 깊이»의 경로 요소에 적용 · DA r2 A)을 뺀 나머지를 <PLAN>.ignored.tar.gz 로 보관한 뒤 진행 (DA r1 R1③')
#   ★파일 단위로 센다(`ls-files -o -i`)★ — `status --ignored` 는 «내용이 전부 ignored 인 디렉터리»를 `clients/` 한 줄로 접어 그 안의 node_modules 가 안 보인다(r3 실측).
allow="${FT_WT_IGNORED_ALLOW:-.env .venv venv .worktree-info.json .serena node_modules .next __pycache__ .pytest_cache .ruff_cache .mypy_cache .turbo dist build coverage}"
list="$PLAN.ignored.list"; : > "$list"
while IFS= read -r p; do
  [ -n "$p" ] || continue; skip=0
  IFS=/ read -ra segs <<< "$p"
  for seg in "${segs[@]}"; do case " $allow " in *" $seg "*) skip=1; break;; esac; done
  [ "$skip" = 1 ] || printf '%s\n' "$p" >> "$list"
done < <(git -C "$WT" ls-files -o -i --exclude-standard)
nkeep="$(grep -c . "$list")"
if [ "$nkeep" -gt 0 ]; then
  tar -C "$WT" -czf "$PLAN.ignored.tar.gz" -T "$list" || fail "ignored 보관 실패(${nkeep}파일)"
else rm -f "$list"; fi
# 미커밋(실작업물 포함, r7)은 WIP 커밋 성공 뒤에만 진행 — 실패하면 정리 자체를 REJECT(#0 RULE, 조용히 버리지 않는다)
# r9(오빠 판정 ㉙ Q4): .serena/project.yml 은 activate_project 가 매번 갱신하는 노이즈 — WIP 커밋 전에 되돌린다(tracked 인 경우만 · untracked 는 대상 아님).
if git -C "$WT" ls-files --error-unmatch .serena/project.yml >/dev/null 2>&1; then
  # r10(DA r9 MINOR b 채택): staged(M ) 상태에서도 「.serena-only = [wip] 0」 이 되도록 index 가 아니라 HEAD 기준으로 되돌린다.
  git -C "$WT" checkout HEAD -- .serena/project.yml || fail ".serena/project.yml checkout 실패"
  dirty="$(git -C "$WT" status --porcelain)"
fi
if [ -n "$dirty" ]; then git -C "$WT" add -A && git -C "$WT" commit -q -m "[wip] nano close $SEAT" || fail "wip commit 실패"; fi
BATON_TMUX_DISABLE=true "$BATON" wt-clean "$WT" || fail "baton wt-clean 실패"
[ -d "$WT" ] && fail "baton 뒤에도 워크트리 남음"
res=cleaned; [ -f "$PLAN.ignored.tar.gz" ] && res="cleaned(ignored ${nkeep}파일 보관)"
mark "$res"; echo "$res"
SH
  } > "$PLAN"
  chmod 755 "$PLAN"
}
# 세션이 사라진 뒤(--kill KILLED 직후)의 실행 — 결과는 계획이 원장에 직접 표식. skipped 는 사람 판정 분기 → stdout [HIL](호출자가 mbox 로 올린다).
_wt_clean_run() {
  local res
  res="$(/bin/bash "$PLAN" 2>&1 | tee "$PLAN.log" | tail -1)"
  # [HIL] 은 1회만 — 계획을 <seat>.sh.hil 로 옮겨 sweep 순회에서 뺀다(사람이 .sh 로 되돌리면 재시도 · DA r3 MAJOR N1)
  case "$res" in cleaned*|none) mv "$PLAN" "$PLAN.done";; skipped:좌석*|skipped:cwd*) ;; *) mv "$PLAN" "$PLAN.hil"; echo "[HIL] ${res#skipped:} · 스크립트 $PLAN.hil";; esac
  echo "워크트리 정리: $res (로그 $PLAN.log)"
}
bad=()
# ① 결과 보존
[ -n "$RESULT" ] && [ -e "$RESULT" ] || bad+=("①결과 경로 없음: ${RESULT:-<미지정>}")
# ② master 회수 — 그 seq 가 실제로 존재했는가 (행이 소비돼도 bodies/<seq>.txt 또는 카운터 이하)
if [ -z "$RECV" ]; then bad+=("②--recv <seq> 미지정")
elif ! { [ -f "$COMM/bodies/$RECV.txt" ] || grep -q "\"seq\": *$RECV," "$COMM/mailbox.jsonl" 2>/dev/null || [ "$RECV" -le "$(cat "$COMM/.mbox-seq" 2>/dev/null || echo 0)" ]; }; then
  bad+=("②seq $RECV 가 우편함 기록에 없다")
fi
# ③ 실제 유휴 — pane 이 아니라 jsonl 마지막 레코드 시각 (pane ❯ 는 ghost 를 못 가른다)
# pane_id 경유 — `-t "=$SEAT"` 는 `#` 든 이름에 display-message 가 빈 값을 돌려준다(실측 2026-09-14)
# 하네스 0.5 행 2 r6(DA r5 MAJOR 1): tmux 조회 자체의 성공을 먼저 본다 — 계획 본문 가드 ①(:71-77)과 같은 규칙.
# r7(DA r6 MAJOR 2ⓐ): no-server 판정을 좁힌다 — rc=1 «이고» 메시지에 no server running|error connecting to 가 있을 때만 0세션.
# r8(DA r7 MAJOR 1 — 회귀): r7 의 "error connecting to" 단독 매칭이 «모든» 소켓 연결 장애(Operation not permitted 등, 전부 rc1)를
# 서버없음으로 삼켰다 — 생존 좌석까지 ABSENT 로 넘겼다(재현 C1). 「소켓 파일 자체가 없다」는 문구까지 요구해 좁힌다.
tmux_out="$(tmux list-panes -a -F '#{session_name}|#{pane_id}' 2>&1)"; tmux_rc=$?; tmux_ok=1
if [ "$tmux_rc" -ne 0 ]; then
  case "$tmux_rc:$tmux_out" in
    1:*"no server running"*) tmux_out="";;
    1:*"error connecting to "*"(No such file or directory)"*)
      # r9(오빠 판정 ㉙ Q5)+r10(DA r9 M1·M2): 소켓 파일만 없고 서버 프로세스가 살아있으면 고아 서버 — 0세션이 아니라 REJECT(같은 화이트리스트, 계획 본문 guard①과 동일).
      n=0
      op="$(pgrep -a -U "$(id -u)" -x tmux 2>&1)"; prc=$?
      case "$prc" in 0) n="$(printf '%s\n' "$op" | grep -c .)";; 1) n=0;; *) tmux_ok=0; bad+=("③pgrep 실패(rc=$prc: ${op:0:60})");; esac
      if [ "$tmux_ok" = 1 ] && [ -n "${FT_TMUX_BIN:-}" ]; then
        op2="$(pgrep -a -U "$(id -u)" -f "$FT_TMUX_BIN" 2>&1)"; prc2=$?
        case "$prc2" in 0) n=$((n + $(printf '%s\n' "$op2" | grep -c .)));; 1) ;; *) tmux_ok=0; bad+=("③pgrep 실패(rc=$prc2: ${op2:0:60})");; esac
      fi
      if [ "$tmux_ok" = 1 ]; then
        if [ "$n" -gt 0 ]; then tmux_ok=0; bad+=("③고아 tmux 서버(pgrep ${n} · 소켓 부재)")
        else tmux_out=""; fi
      fi
      ;;
    *) tmux_ok=0; bad+=("③tmux 조회 실패(rc=$tmux_rc: ${tmux_out:0:60})");;
  esac
fi
PANE="$(printf '%s\n' "$tmux_out" | awk -F'|' -v s="$SEAT" '$1==s{print $2; exit}')"
# r7(DA r6 MAJOR 2ⓑ): PANE 은 있는데 display-message 가 실패하거나 빈 경로를 주면 ABSENT 가 아니라 REJECT — ABSENT 는 «PANE 자체가 없을 때」만.
cwd=""
if [ -n "$PANE" ]; then
  cwd="$(tmux display-message -p -t "$PANE" '#{pane_current_path}' 2>&1)"; dm_rc=$?
  if [ "$dm_rc" -ne 0 ] || [ -z "$cwd" ]; then bad+=("③pane 경로 조회 실패(rc=$dm_rc)"); tmux_ok=0; cwd=""; fi
fi
# 하네스 0.5 행 2 r5(오빠 판정 #30467): 세션이 먼저 죽은 좌석 — 세션 없음 + 워크트리 실재는 REJECT 대신 「세션 없음 자체가 충족」(유휴 검사 불요).
# 워크트리 부재(닫을 것 없음)는 기존 REJECT 유지. ABSENT 는 아래 명부/원장 처리 분기에서만 쓴다. tmux_ok=0 이면 이 블록 전체를 건너뛴다(위에서 이미 REJECT 사유 기록).
_KEY="${SEAT#"$NANO_PREFIX"}"; _KEY="${_KEY%#*}"
ABSENT=0
if [ "$tmux_ok" = 1 ]; then
  if [ -z "$cwd" ]; then
    if [ -d "$ROOT/.worktrees/v65-$_KEY" ]; then ABSENT=1; else bad+=("③세션 없음: $SEAT"); fi
  else
    enc="$(printf '%s' "$cwd" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"; dir="$HOME/.claude/projects/$enc"
    # r7(DA r6 MAJOR 1): 같은 좌석명 jsonl 이 여러 개(재기동)일 수 있다 — 「이름순 첫 파일」(head -1) 대신 «매칭 전부 중 mtime 최대».
    f="$(grep -lE "\"(agentName|customTitle)\":\"$(printf '%s' "$SEAT" | sed 's/[][\.*^$/]/\\&/g')\"" "$dir"/*.jsonl 2>/dev/null \
        | while IFS= read -r mf; do stat -f '%m %N' "$mf"; done | sort -rn | head -1 | cut -d' ' -f2-)"
    if [ -z "$f" ]; then
      # codex/cmd/opencode 는 claude jsonl 이 없다 — 파일 mtime 으로 대신(에이전트 무관 하한)
      last="$(find "$cwd" -type f -newer "$SEATS" -not -path '*/.git/*' -mmin -"$IDLE_MIN" 2>/dev/null | head -1)"
      [ -z "$last" ] || bad+=("③워크트리에 ${IDLE_MIN}분 내 편집: $last")
    else
      age=$(( ( $(date +%s) - $(stat -f %m "$f") ) / 60 ))
      [ "$age" -ge "$IDLE_MIN" ] || bad+=("③jsonl 마지막 활동 ${age}분 전 < ${IDLE_MIN}분")
    fi
  fi
fi
# ④ 카드가 checkpoint 를 요구하면(`ft-checkpoint.sh` 줄) 마지막 checkpoint 표 실재 + 경보 아님 (팩 SEATBELT.md §6-2 · 설정 없는 프로젝트는 경고만)
IDX="$(jq -r --arg s "$SEAT" '.[$s].index // empty' "$SEATS" 2>/dev/null)"; CARD=""
for c in "$WT/$IDX" "$ROOT/$IDX" "$LEDGER_WT/$IDX"; do [ -n "$IDX" ] && [ -f "$c" ] && { CARD="$c"; break; }; done
if [ -n "$CARD" ] && grep -qF 'ft-checkpoint.sh' "$CARD"; then
  CPCFG="${FT_CHECKPOINT_JSON:-$ROOT/.fable-team/checkpoint.json}"; CPST="$ROOT/.fable-team/checkpoint/${SEAT//\//_}.last"
  if [ ! -f "$CPCFG" ]; then echo "WARN ④press/시험 카드인데 checkpoint 미설정($CPCFG) — 경고만(§6-2)"
  elif [ ! -f "$CPST" ]; then bad+=("④press/시험 카드인데 checkpoint 실행 기록 없음: ft-checkpoint.sh <증거폴더> --seat $SEAT")
  else
    cp_tab="$(jq -r '.table // empty' "$CPST")"; cp_al="$(jq -r '.alarm // empty' "$CPST")"; cp_ex="$(jq -r '.exit // empty' "$CPST")"
    [ -n "$cp_tab" ] && [ -f "$cp_tab" ] || bad+=("④checkpoint 표 없음: ${cp_tab:-<빈 경로>}")
    [ "$cp_al" = "no" ] || bad+=("④마지막 checkpoint alarm=$cp_al exit=$cp_ex — 경보면 4축 정리 → arch(+DA) 처방 → 수정 → 재실행 후 닫는다")
  fi
fi
# ⑥ 나노 생애 ③④ 증거 줄 (M7 · REVIEW arch141 §2-2) — role=nano 좌석만: 카드 «## 상태» 의 `세트: <HEAD> · 시험: … rc=0 · 이슈: …` 가 현재 나노 HEAD 와 맞아야 닫힌다.
#   impl·tester·checker 등 tier 좌석은 대상 아님(role 이 nano 가 아님). 루트 포함은 cherry-gate --mode land 가 랜딩 요청 시점에 맡는다(close 에는 걸지 않는다).
_role="$(jq -r --arg s "$SEAT" '.[$s].role // empty' "$SEATS" 2>/dev/null)"
if [ "$_role" = nano ] && [ -z "$CARD" ]; then
  # 카드를 못 찾으면 증거를 대조할 수 없다 — 건너뛰고 CLOSED 하면 무음 통과(#0 RULE · DA⑥ 관측 A3). grandfather 와 무관하게 REJECT.
  bad+=("⑥카드 못 찾음: seats.json index=${IDX:-<빈 값>} (후보 $WT/·$ROOT/·$LEDGER_WT/ 아래 어디에도 없음) — 증거 줄을 대조할 카드가 없다")
elif [ "$_role" = nano ] && [ -n "$CARD" ]; then
  if [ ! -x "$HERE/ft-nano-evidence-check.sh" ]; then bad+=("⑥증거 검사 스크립트 없음: $HERE/ft-nano-evidence-check.sh (런타임 bin 에 같이 복사)")
  elif [ ! -d "$ROOT/.worktrees/v65-$_KEY" ]; then bad+=("⑥나노 워크트리 없음: $ROOT/.worktrees/v65-$_KEY — 증거 줄의 HEAD 를 대조할 수 없다")
  else
    # 언제부터 요구하나: 워크트리 .worktree-info.json created_at 날짜 >= FT_EVIDENCE_SINCE(기본 2026-10-03)인 나노만 REJECT — 그 전에 열린 진행 나노는 WARN 만(한 번에 막히지 않게).
    #   created_at 을 못 읽으면 요구한다(fail-closed · 값 추론 금지).
    _ev_created="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("created_at","")[:10])' "$ROOT/.worktrees/v65-$_KEY/.worktree-info.json" 2>/dev/null)"
    _ev_since="${FT_EVIDENCE_SINCE:-2026-10-03}"
    _ev_out="$("$HERE/ft-nano-evidence-check.sh" "$CARD" --repo "$ROOT/.worktrees/v65-$_KEY" --feat "${FT_NANO_FEAT:-feat/v6-realtime-live}" 2>&1)"; _ev_rc=$?
    if [ "$_ev_rc" -eq 0 ]; then echo "$_ev_out"
    elif [ -n "$_ev_created" ] && [[ "$_ev_created" < "$_ev_since" ]]; then echo "WARN ⑥증거 줄 미충족(grandfather — 워크트리 created_at $_ev_created < $_ev_since): $(printf '%s' "$_ev_out" | head -1)"
    else bad+=("⑥$(printf '%s' "$_ev_out" | sed -e 's/^REJECT //' -e '2,$s/^/    /')"); fi
  fi
fi
# ⑤ 산출물 회수 — 그 좌석 브랜치의 «+» 커밋(git cherry <feat> <branch>)이 0 (G4 · 골좌표 M7). 좌석이 닫혔다 ≠ 산출물이 들어왔다.
#   feat = FT_NANO_FEAT(기본 feat/v6-realtime-live) · 브랜치 = 워크트리 .worktree-info.json 의 branch, 워크트리가 없으면 nano/<key>. 못 찾으면 REJECT(침묵 통과 0).
_gate_br="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("branch",""))' "$ROOT/.worktrees/v65-$_KEY/.worktree-info.json" 2>/dev/null)"
[ -n "$_gate_br" ] || _gate_br="nano/$_KEY"
if [ -x "$HERE/ft-nano-cherry-gate.sh" ]; then
  _gate_out="$("$HERE/ft-nano-cherry-gate.sh" "${FT_NANO_FEAT:-feat/v6-realtime-live}" "$_gate_br" --repo "$ROOT" --mode close 2>&1)"; _gate_rc=$?
  [ "$_gate_rc" -eq 0 ] || bad+=("⑤$(printf '%s' "$_gate_out" | sed '2,$s/^/    /')")
  # 나노 생애(오빠 ORDERS 103 · docs/rules/single_set_testing.md §3): 미랜딩이면 «루트부터» 판정과 다음 수(최신 루트 병합→시험→squash 랜딩)를 같이 낸다.
  if [ "$_gate_rc" -ne 0 ] && [ -x "$HERE/ft-nano-freshness.sh" ]; then
    _fresh_out="$(cd "$ROOT" && "$HERE/ft-nano-freshness.sh" "$_gate_br" --root "${FT_NANO_FEAT:-feat/v6-realtime-live}" 2>&1 | grep -E '^(base|branch|overlap|다음|VERDICT|  )')"
    bad+=("⑤-생애 $(printf '%s' "$_fresh_out" | sed '2,$s/^/    /')")
  fi
  [ "$_gate_rc" -ne 0 ] || echo "$_gate_out"
else
  bad+=("⑤cherry 게이트 스크립트 없음: $HERE/ft-nano-cherry-gate.sh (런타임 bin 에 같이 복사)")
fi
if [ "${#bad[@]}" -gt 0 ]; then echo "REJECT $SEAT"; printf '  - %s\n' "${bad[@]}"; exit 1; fi

# 재실행 감지 — 명부에 좌석이 이미 없으면(해제/kill 실패 뒤 같은 close 재호출) 원장 닫힘 행이 이미 있는 한 append 하지 않는다(멱등).
# jq 종료코드 1(has=false) 만 «없음» — 파일 오류(2·5)는 RERUN=0 으로 두어 기존 동작(append) 유지.
RERUN=0; jq -e --arg s "$SEAT" 'has($s)' "$SEATS" >/dev/null 2>&1; [ "$?" -ne 1 ] || RERUN=1
# 명부 삭제 + 원장 append (pm 만 원장을 쓴다는 §2-7 의 예외 = 이 스크립트의 append 1줄)
python3 - "$SEATS" "$SEAT" <<'PY'
import json, sys, collections
p, s = sys.argv[1:3]
d = json.load(open(p, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
d.pop(s, None)
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
PY
_wt_clean_plan
# 원장 append 도 계획의 mark() 와 «같은» mkdir 락(<원장>.lock) 아래 — 락 밖 >> 와 mark 의 read→replace 가 겹치면 행이 소실된다(DA r3 실측 204/8000). 락 실패는 REJECT 가 아니라 append 강행(닫힘 행이 없는 것이 더 나쁘다) + 경고.
_lock="$LEDGER.lock"; _i=0
until mkdir "$_lock" 2>/dev/null; do _i=$((_i+1)); [ "$_i" -lt 100 ] || { echo "WARN 원장 락 10s 초과($_lock) — 락 없이 처리" >&2; _lock=""; break; }; sleep 0.1; done
_rowexists=0; grep -qF "\`$SEAT\` 닫힘(ft-nano-close)" "$LEDGER" 2>/dev/null && _rowexists=1
if [ "$ABSENT" = 1 ] && [ "$_rowexists" = 1 ]; then
  # r5(오빠 판정 #30467): 세션이 먼저 죽어 이미 닫힘 행이 있는 좌석(백필) — 새 행을 만들지 않고 마지막 행의 wt= 만 표식(mark() 와 같은 방식).
  # r6(DA r5 MINOR c): 이 경로는 닫힘 행이 이미 있어 「잃을 것」이 append 와 다르다 — 락 실패는 강행이 아니라 REJECT(재시도).
  [ -n "$_lock" ] || { echo "REJECT $SEAT"; echo "  - 원장 락 10s 초과(재시도) — 닫힘 행 이미 있음, 표식은 락 아래서만"; exit 1; }
  python3 - "$LEDGER" "$SEAT" "$WT_MARK" <<'PY'
import os, re, sys
p, seat, val = sys.argv[1:4]
s = open(p, encoding="utf-8").read(); lines = s.split("\n")
key = "`%s` 닫힘(ft-nano-close)" % seat
idx = [i for i, l in enumerate(lines) if key in l]
i = idx[-1]; lines[i] = re.sub(r"( · wt=.*)?$", " · wt=" + val, lines[i], count=1)
tmp = p + ".tmp.%d" % os.getpid()
with open(tmp, "w", encoding="utf-8") as f: f.write("\n".join(lines)); f.flush(); os.fsync(f.fileno())
os.replace(tmp, p)
PY
  # r6(DA r5 MINOR b): mark-only 도 종료코드를 본다(#0 RULE — 실패를 삼키지 않는다).
  _mrc=$?; [ -z "$_lock" ] || rmdir "$_lock"
  [ "$_mrc" -eq 0 ] || { echo "REJECT $SEAT"; echo "  - 원장 표식 실패(rc=$_mrc)"; exit 1; }
elif [ "$RERUN" = 1 ] && [ "$_rowexists" = 1 ]; then
  echo "재실행 — 명부에 없고 원장 닫힘 행이 이미 있다: append 생략, 남은 세션 정리만 이어간다"
  [ -z "$_lock" ] || rmdir "$_lock"
else
  printf -- '- **[%s KST, `date` 실측] `%s` 닫힘(ft-nano-close)**: ①결과 `%s` ②회수 seq %s ③%s. kill=%s · wt=%s\n' \
    "$(date '+%Y-%m-%d %H:%M')" "$SEAT" "$RESULT" "$RECV" "$([ "$ABSENT" = 1 ] && echo "세션 없음(백필)" || echo "유휴 jsonl/mtime ≥${IDLE_MIN}분")" "$KILL" "$WT_MARK" >> "$LEDGER"
  [ -z "$_lock" ] || rmdir "$_lock"
fi
[ -z "$PLAN" ] || echo "워크트리 정리 계획: $PLAN (실행은 세션 kill 직후 — 미완이면 ft-wt-sweep.sh)"
# r6(DA r5 MINOR e): 명부 pop 은 ABSENT 여부와 무관하게 위에서 항상 실행된다 — 「명부 확인」은 사실과 달랐다.
if [ "$ABSENT" = 1 ]; then echo "CLOSED-ABSENT $SEAT (명부 삭제 · 원장 표식) — 워크트리 정리 계획만"; exit 0; fi
echo "CLOSED $SEAT (명부 삭제 · 원장 append) — 좌석은 정지 레디"
# 슬롯 채움(오빠 2026-10-02): 닫은 같은 턴에 빈 석·후보를 보인다 — 출력만, 실패해도 close 결과는 그대로.
bash "$(dirname "$0")/ft-nano-slots.sh" || echo "WARN ft-nano-slots 실패(rc=$?) — 빈 석을 손으로 세라"

# 닫힌 나노는 «항상» 태그 해제 + 세션 kill — 근거: 글로벌 ~/.claude/CLAUDE.md 「나노 세션 정리 표준승인 (2026-10-02 · 오빠 AskUserQuestion master-claude#120)」
# (nano-close 경로 하나 · 나노 계보 keep-last-2 면제 · ★브랜치 삭제 0★ · 역할 좌석은 keep-last-2 그대로).
# 둘 중 하나라도 실패하면 조용히 넘기지 않는다(#0 RULE) — 명부는 이미 지워졌으므로 같은 close 를 다시 부르면 남은 정리만 이어진다(RERUN).
tmux set-option -t "$PANE" -u @zc_v65_active || { echo "FAIL $SEAT — @zc_v65_active 해제 실패(세션 잔존 · 명부는 삭제됨)"; exit 1; }
tmux kill-session -t "$PANE" || { echo "FAIL $SEAT — kill-session 실패(세션 잔존 · 태그는 해제됨)"; exit 1; }
echo "KILLED $SEAT (@zc_v65_active 해제 · 세션 kill · 브랜치 보존)"
# 세션이 사라졌다 — 이제 계획을 실행한다(계보의 다른 세션·cwd 보유가 남아 있으면 계획이 skipped:좌석/cwd 로 대기시킨다)
[ -n "$PLAN" ] && [ "${FT_WT_AUTOCLEAN:-1}" != 0 ] && _wt_clean_run
exit 0
