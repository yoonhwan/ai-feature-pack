#!/usr/bin/env bash
# test_tick_install_msg_paths_r1464.sh — r1464: 팀 틱 설치기 ① 문구 속 경로 실재 검사 ② bootout → bootstrap 사이 «내려감» 대기
#   T1 문구 속 경로(design/… · .worktrees/…) 전부 실재 → 렌더 rc0 · 두 키 값 불변
#   T2 문구 속 경로 1개 없음 → REJECT 1줄(키·토큰) · rc1 · plist 쓰기 0 · launchctl 호출 0
#   T3 `{진행,대기,완성}`·끝 구두점(. ·)·백틱·«» 을 벗긴 토큰으로 검사 · 없는 토큰은 벗긴 꼴로 보고
#   T4 --dry-run 도 같은 REJECT · 기존 r962 시험 rc0
#   T5 가짜 launchctl: bootout 뒤 print 3회 rc0 → 4번째 rc113 → bootout→print×4→bootstrap 1회 · rc0 (팀·메인 두 경로)
#   T6 가짜 launchctl: print 계속 rc0 → REJECT 1줄(되돌림 안내) · bootstrap 0 · rc1 · 15초 안 (팀·메인 두 경로 · 팀은 print 1초 = 경과 초 마감)
#   T7 (DA R1) print rc1(113 아님) → 판정 불가 REJECT 1줄 · bootstrap 0 · rc1 (팀·메인)
#   T8 (DA R2) ft_team_attach_ops.py → 설치기 timeout 25 = 설치기 예산(마감 10초 + print 1회 + 2초 + bootstrap) 이상
# 실 launchd·실 ~/Library/LaunchAgents 0 — HOME·FT_TICK_PLIST_DIR·FT_TICK_LAUNCHCTL 를 임시로 돌린다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
KBIN="$REPO/harness/kit/fable-team/bin"; INST="$KBIN/ft-tick-install.sh"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
unset FT_ROOT FT_MBOX_DIR FT_TICK_MBOX FT_HARNESS_ROOT FT_TICK_TEAM_TSV FT_TICK_PLIST_DIR FT_TICK_LAUNCHCTL

bash -n "$INST" && ok "bash -n ft-tick-install.sh" || bad "bash -n ft-tick-install.sh"
chk "kit·bin 짝 cmp0" "$(cmp -s "$INST" "$REPO/harness/bin/ft-tick-install.sh" && echo same || echo differ)" same

# ── 픽스처: 공용 루트(git) · 팀 폴더·워크트리 실재 · 가짜 launchctl ──
R="$TMP/root"
mkdir -p "$R/.fable-team/comm" "$R/.fable-team/bin" "$R/.worktrees/ops-lead" \
         "$R/design/teams/ops/indices/진행" "$R/design/teams/ops/indices/대기" "$R/design/teams/ops/indices/완성"
: > "$R/design/teams/ops/GOAL-ops.md"
git -C "$R" init -q -b main; git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
cp "$KBIN/ft-tick.sh" "$KBIN/ft-seat-status.sh" "$R/.fable-team/bin/"
export HOME="$TMP/home"; mkdir -p "$HOME"
LC="$TMP/launchctl"; export LC_LOG="$TMP/lc.log" LC_CNT="$TMP/lc.cnt" LC_UP=0
cat > "$LC" <<'SH'
#!/bin/bash
echo "$1" >> "$LC_LOG"
if [ "$1" = print ]; then
  n=$(( $(cat "$LC_CNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$LC_CNT"
  [ "${LC_SLOW:-0}" = 0 ] || sleep "$LC_SLOW"          # R2: print 자체가 느린 입력(마감 = 경과 초)
  [ -z "${LC_PRC:-}" ] || exit "$LC_PRC"                # R1: print 판독 실패(113 아님)
  [ "$LC_UP" = always ] && exit 0
  [ "$n" -le "$LC_UP" ] && exit 0
  exit 113
fi
exit 0
SH
chmod +x "$LC"
# 안전망: PATH 의 launchctl 도 가짜(설치기가 FT_TICK_LAUNCHCTL 을 안 쓰면 여기로 온다 — 실 launchd 접촉 0)
mkdir -p "$TMP/shim"; printf '#!/bin/bash\necho "$*" >> "%s"\nexit 0\n' "$TMP/shim.log" > "$TMP/shim/launchctl"; chmod +x "$TMP/shim/launchctl"
export PATH="$TMP/shim:$PATH"; : > "$TMP/shim.log"
lcreset() { : > "$LC_LOG"; rm -f "$LC_CNT"; LC_UP="$1"; export LC_SLOW=0 LC_PRC=; }

mkfrom() {  # $1 = 출력 plist · $2 = MASTER 문구 · $3 = PM 문구
  python3 - "$@" "$R" <<'PY'
import plistlib, sys
out, m, p, r = sys.argv[1:5]
plistlib.dump({"Label": "com.byz.ft-tick-ops", "ProgramArguments": ["/opt/homebrew/bin/bash", "/nonexistent"],
  "EnvironmentVariables": {"FT_TICK_MASTER_MSG": m, "FT_TICK_PM_MSG": p,
                           "FT_TICK_SEATS": r + "/.fable-team/seats-ops.json"}}, open(out, "wb"))
PY
}
team() {  # $1 = PDIR · $2 = --from plist · 나머지 = 인자
  ( cd "$R" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE FT_TICK_TEAM_TSV="$KBIN/team-tick-env.tsv" FT_TICK_PLIST_DIR="$1" \
      FT_TICK_LAUNCHCTL="$LC" bash "$INST" --team ops --from "$2" --script "$R/.fable-team/bin/ft-tick.sh" "${@:3}" 2>&1 ); echo "rc=$?"; }
main() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE FT_TICK_LAUNCHCTL="$LC" \
           bash "$INST" --worktree "$R" --script "$R/.fable-team/bin/ft-tick.sh" "$@" 2>&1; echo "rc=$?"; }
rc()   { printf '%s\n' "$1" | sed -n '$s/^rc=//p'; }
rej()  { printf '%s\n' "$1" | grep -c '^REJECT'; }
envget() {  # $1 = 출력 텍스트 · $2 = 키
  printf '%s\n' "$1" | sed -n '/^<?xml/,/<\/plist>/p' > "$TMP/pl.plist"
  python3 -c 'import plistlib,sys
try: print(plistlib.load(open(sys.argv[1],"rb"))["EnvironmentVariables"][sys.argv[2]])
except Exception: print("<none>")' "$TMP/pl.plist" "$2" 2>/dev/null; }
nfiles() { ls "$1" 2>/dev/null | wc -l | tr -d ' '; }
seq_() { tr '\n' ' ' < "$LC_LOG" | sed 's/ $//'; }

GOOD_M='[cron-tick · 뉴스] ops 팀. 골 원문 정본 design/teams/ops/GOAL-ops.md (워크트리 .worktrees/ops-lead). 인덱스 정본 design/teams/ops/indices/{진행,대기,완성}. 변화 없으면 변화 없음 한 줄.'
GOOD_P='[cron-tick] ops pm 점검 틱 — design/teams/ops/indices/ 전수 대조. 변화 없으면 변화 없음 한 줄.'
mkfrom "$TMP/good.plist" "$GOOD_M" "$GOOD_P"

# ── T1 경로 전부 실재 → rc0 · 두 키 값 불변 ──
o="$(team "$TMP/p1" "$TMP/good.plist" --dry-run)"
chk "T1 경로 전부 실재 → rc" "$(rc "$o")" 0
chk "T1 MASTER 문구 불변" "$(envget "$o" FT_TICK_MASTER_MSG)" "$GOOD_M"
chk "T1 PM 문구 불변" "$(envget "$o" FT_TICK_PM_MSG)" "$GOOD_P"

# ── T2 없는 경로 1개 → REJECT 1줄(키·토큰) · rc1 · plist 쓰기 0 · launchctl 0 (실설치 모드) ──
mkfrom "$TMP/bad-m.plist" '골 원문 정본 design/ops/GOAL-ops.md (워크트리 .worktrees/ops-lead).' "$GOOD_P"
lcreset 0; o="$(team "$TMP/p2" "$TMP/bad-m.plist")"
chk "T2 MASTER 없는 경로 → rc" "$(rc "$o")" 1
chk "T2 REJECT 1줄" "$(rej "$o")" 1
chk "T2 REJECT 에 키·토큰" "$(printf '%s\n' "$o" | grep -c '^REJECT 문구 경로 없음: FT_TICK_MASTER_MSG design/ops/GOAL-ops.md ')" 1
chk "T2 plist 쓰기 0" "$(nfiles "$TMP/p2")" 0
chk "T2 launchctl 호출 0" "$(wc -l < "$LC_LOG" | tr -d ' ')" 0
mkfrom "$TMP/bad-p.plist" "$GOOD_M" '[cron-tick] ops pm — .worktrees/ops-main 전수.'
o="$(team "$TMP/p2" "$TMP/bad-p.plist")"
chk "T2 PM 없는 경로 → rc·키·토큰" "$(rc "$o")/$(printf '%s\n' "$o" | grep -c 'FT_TICK_PM_MSG .worktrees/ops-main ')" 1/1
chk "T2 PM: plist 쓰기 0" "$(nfiles "$TMP/p2")" 0

# ── T3 벗김: {진행,대기,완성} · 끝 구두점 · 백틱 · «» ──
mkfrom "$TMP/strip.plist" '정본 `design/teams/ops/GOAL-ops.md` · «.worktrees/ops-lead» · design/teams/ops/indices/{진행,대기,완성}· design/teams/ops/GOAL-ops.md. 끝 design/teams/ops/indices,' "$GOOD_P"
o="$(team "$TMP/p3" "$TMP/strip.plist" --dry-run)"
chk "T3 벗긴 토큰 전부 실재 → rc" "$(rc "$o")" 0
mkfrom "$TMP/strip-bad.plist" '인덱스 design/teams/ops/nope/{진행,대기,완성}.' "$GOOD_P"
o="$(team "$TMP/p3" "$TMP/strip-bad.plist" --dry-run)"
chk "T3 없는 토큰 → rc" "$(rc "$o")" 1
chk "T3 보고 토큰 = 벗긴 꼴" "$(printf '%s\n' "$o" | grep -c 'FT_TICK_MASTER_MSG design/teams/ops/nope/ (루트')" 1

# ── T4 --dry-run 도 같은 REJECT · 기존 r962 시험 rc0 ──
o="$(team "$TMP/p4" "$TMP/bad-m.plist" --dry-run)"
chk "T4 dry-run REJECT rc·1줄" "$(rc "$o")/$(rej "$o")" 1/1
chk "T4 dry-run 렌더본 출력 0" "$(printf '%s\n' "$o" | grep -c '^<?xml')" 0
bash "$HERE/test_r962_tick_install_root_bin_only.sh" >"$TMP/r962.out" 2>&1; chk "T4 기존 r962 시험 rc" "$?" 0

# ── T5 bootout 뒤 print 3회 rc0 → 4번째 rc113 → bootstrap 1회 (팀·메인) ──
lcreset 3; o="$(team "$TMP/p5" "$TMP/good.plist")"
chk "T5 팀: rc" "$(rc "$o")" 0
chk "T5 팀: 호출 순서" "$(seq_)" "bootout print print print print bootstrap"
lcreset 3; o="$(main)"
chk "T5 메인: rc" "$(rc "$o")" 0
chk "T5 메인: 호출 순서(bootstrap 까지)" "$(head -6 "$LC_LOG" | tr '\n' ' ' | sed 's/ $//')" "bootout print print print print bootstrap"
chk "T5 메인: bootstrap 1회" "$(grep -c '^bootstrap$' "$LC_LOG")" 1

# ── T6 print 계속 rc0(안 내려감) → REJECT 1줄 · bootstrap 0 · rc1 · 15초 안 (팀·메인) ──
#   팀 = print 1회 1초(R2) — 횟수 마감(0.5초×20)이면 약 30초 · 경과 초 마감이면 10~12초
lcreset always; export LC_SLOW=1; s=$SECONDS; o="$(team "$TMP/p6" "$TMP/good.plist")"; el=$((SECONDS - s))
chk "T6 팀: rc" "$(rc "$o")" 1
chk "T6 팀: REJECT 1줄(되돌림 안내)" "$(printf '%s\n' "$o" | grep -c '^REJECT bootout 미완(10초) — 되돌림: cp -p ')" 1
chk "T6 팀: bootstrap 0" "$(grep -c '^bootstrap$' "$LC_LOG")" 0
chk "T6 팀: 15초 안" "$([ "$el" -le 15 ] && echo yes || echo "no(${el}s)")" yes
lcreset always; s=$SECONDS; o="$(main)"; el=$((SECONDS - s))
chk "T6 메인: rc" "$(rc "$o")" 1
chk "T6 메인: REJECT 1줄" "$(printf '%s\n' "$o" | grep -c '^REJECT bootout 미완(10초) — 되돌림: ')" 1
chk "T6 메인: bootstrap 0" "$(grep -c '^bootstrap$' "$LC_LOG")" 0
chk "T6 메인: 15초 안" "$([ "$el" -le 15 ] && echo yes || echo "no(${el}s)")" yes

# ── T7 (DA R1) print 판독 실패(rc1 · 113 아님) → 판정 불가 REJECT 1줄 · bootstrap 0 · rc1 (팀·메인) ──
lcreset 0; export LC_PRC=1; o="$(team "$TMP/p7" "$TMP/good.plist")"
chk "T7 팀: rc" "$(rc "$o")" 1
chk "T7 팀: 판정 불가 REJECT 1줄" "$(printf '%s\n' "$o" | grep -c '^REJECT 판정 불가 — launchctl print rc=1')" 1
chk "T7 팀: 호출 순서(bootstrap 0)" "$(seq_)" "bootout print"
lcreset 0; export LC_PRC=1; o="$(main)"
chk "T7 메인: rc" "$(rc "$o")" 1
chk "T7 메인: 판정 불가 REJECT 1줄" "$(printf '%s\n' "$o" | grep -c '^REJECT 판정 불가 — launchctl print rc=1')" 1
chk "T7 메인: bootstrap 0" "$(grep -c '^bootstrap$' "$LC_LOG")" 0

# ── T8 (DA R2) 호출자 예산 = 설치기 전체 예산(마감 10초 + print 1회 + 2초 + bootstrap) ≤ 25초 ──
ATT="$KBIN/ft_team_attach_ops.py"
chk "T8 attach kit·bin cmp0" "$(cmp -s "$ATT" "$REPO/harness/bin/ft_team_attach_ops.py" && echo same || echo differ)" same
chk "T8 attach → 설치기 timeout = 25" "$(grep 'str(installer), "--team"' "$ATT" | sed -n 's/.*timeout=\([0-9]*\).*/\1/p')" 25
chk "T8 설치기 마감 = 경과 10초 1곳" "$(grep -c 'end=\$((SECONDS + 10))' "$INST")" 1

chk "PATH launchctl(= FT_TICK_LAUNCHCTL 우회) 호출 0" "$(wc -l < "$TMP/shim.log" | tr -d ' ')" 0

echo "fail=$fail"
[ "$fail" = 0 ] && echo "ALL PASS"
exit "$fail"
