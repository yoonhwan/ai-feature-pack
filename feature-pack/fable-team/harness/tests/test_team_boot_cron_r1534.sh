#!/usr/bin/env bash
# test_team_boot_cron_r1534.sh — ft-team-boot.sh r1534: B4 정본 CronCreate 경고 + B5 cron 칸 실측(고정 «none» 0).
#   격리: 임시 git 리포(CLOSEOUT 픽스처) + 가짜 successor-open·nano-spawn·mbox·tmux·all-stop·launchd 자리 — 실 세션·실 우편함·실 launchd 0 · press 0.
#   사례: ⓐ pi 팀장 = cron=none(pi …) ⓑ claude 팀장 = cron=판정 불가 ⓒ 정본 CronCreate 2줄 → WARN 1줄·부팅 계속(rc0) ⓓ 0줄 → WARN 0 ⓔ B2 본문 지시 문면 그대로
#   변이: M1 cron 칸을 고정 «none» 으로 되돌림 → ⓑ 가 FAIL 해야 한다 · M2 CronCreate 검사를 끔 → ⓒ 가 FAIL 해야 한다
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -u   # pipefail 안 쓴다 — `cmd | grep -q` 의 SIGPIPE(141) 거짓 FAIL 방지
export LC_ALL=C
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"
fail=0; out=""; rc=0; npass=0
ok()  { npass=$((npass+1)); }
bad() { echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); }
ck()  { if [ "$2" = 0 ]; then ok; else bad "$1"; fi; }
has() { printf '%s' "$out" | grep -qF -- "$1"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ---------- 가짜 도구 ----------
FAKE="$T/fake"; mkdir -p "$FAKE" "$T/la"   # T/la = 빈 LaunchAgents 자리(launchd 미등재)
cat > "$FAKE/so.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FT_REC/so.log"
while [ $# -gt 0 ]; do case "$1" in --name) echo "$2" >> "$FT_REC/live.txt"; shift 2;; *) shift;; esac; done
echo "DONE"; exit 0
EOF
cat > "$FAKE/mbox.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FT_REC/mbox.log"; echo "QUEUED seq=4242 to=$2 pending=0"; exit 0
EOF
cat > "$FAKE/tmux.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = ls ] || exit 0; cat "$FT_REC/live.txt" 2>/dev/null; exit 0
EOF
cat > "$FAKE/allstop.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE"/*.sh
REC="$T/rec"; mkdir -p "$REC"; : > "$REC/live.txt"
export FT_REC="$REC"
export FT_MBOX_SH="$FAKE/mbox.sh" FT_ALL_STOP="$FAKE/allstop.sh" FT_TMUX="$FAKE/tmux.sh"
export FT_LAUNCHAGENTS="$T/la" FT_BOOT_ME='byz-t1-nano-boot#0' FT_BOOT_REPORT_TO='byz-planner-master-pi#245'
export FT_SUCCESSOR_OPEN="$FAKE/so.sh"

g() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$2"; }
mkfix() {  # <루트> <팀> <팀장 agent>
  local r="$1" t="$2" a="$3"
  mkdir -p "$r/design/teams/$t" "$r/.fable-team/comm" "$r/state" "$r/.worktrees/wt$t"
  git -C "$r" init -q -b main
  printf '{"_name":"T","_master":"byz-%s-master-%s#4","_cards":"design/teams/%s/indices","_cards_wt":"wt%s",\n "byz-%s-master-%s#4":{"role":"master","agent":"%s","model":"claude-sonnet-5-5[1m]"}}\n' \
    "$t" "$a" "$t" "$t" "$t" "$a" "$a" > "$r/.fable-team/seats-$t.json"
  echo '{"_master":"byz-planner-master-pi#245"}' > "$r/.fable-team/seats-planner.json"
}
closeout() {  # <리포> <경로> <제목날짜> <CronCreate 줄 수>
  mkdir -p "$(dirname "$1/$2")"
  { echo "# CLOSEOUT 테스트 $3"; echo; echo "## 골 원문"; echo; echo "골 첫 줄 $3"; echo "골 둘째 줄"; echo "골 셋째 줄"; echo
    echo "## 1. 첫 일"; echo; i=0; while [ "$i" -lt "${4:-0}" ]; do
      echo "- 세션 안 CronCreate 15분 1개 (픽스처 $i)"; i=$((i+1)); done
    echo "- 그 밖 손 할 일 없음"; echo
    echo "## 4. 다시 여는 법"; echo; echo "- 새 세션 → 이 CLOSEOUT → 카드"; } > "$1/$2"
}
runit() {  # <리포> <팀> [bin]  — out·rc 갱신(살아 있는 세션 자리 초기화)
  : > "$REC/live.txt"; local b="${3:-$BIN/ft-team-boot.sh}"
  out="$(cd "$1" && FT_REPO_ROOT="$1" bash "$b" "$2" 2>&1)"; rc=$?
}
body_of() { ls -1t "$1/state/team-boot/$2"*.body 2>/dev/null | head -1; }

# ---------- ⓐ pi 팀장 — cron=none(pi …) ----------
R="$T/r1"; mkfix "$R" t1 pi; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0
g "$R" c1; git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/mbox.log"; runit "$R" t1
ck "ⓐ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
grep -qF 'cron=none(pi · CronCreate 도구 없음)' "$REC/mbox.log" && ok || bad "ⓐ pi 팀장 = cron=none(pi · CronCreate 도구 없음)"
grep -qF 'cron=none ·' "$REC/mbox.log" && bad "ⓐ 고정 «cron=none» 0" || ok
# ---------- ⓔ B2 본문 지시 문면은 그대로 ----------
B="$(body_of "$R" t1)"
[ -n "$B" ] && grep -qF '크론 0 · 호출될 때만' "$B" && ok || bad "ⓔ B2 본문 «크론 0 · 호출될 때만» 그대로"

# ---------- ⓑ claude 팀장 — cron=판정 불가(세션 안 …) ----------
R="$T/r2"; mkfix "$R" t1 claude; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0
g "$R" c2; git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/mbox.log"; runit "$R" t1
ck "ⓑ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
grep -qF 'cron=판정 불가(세션 안 · 팀장 부팅 보고가 CronList 실측)' "$REC/mbox.log" && ok || bad "ⓑ claude 팀장 = cron=판정 불가(세션 안 …)"
grep -qF 'cron=none' "$REC/mbox.log" && bad "ⓑ 고정 «none» 0" || ok

# ---------- ⓒ 정본에 CronCreate 2줄 — WARN 1줄 · 부팅은 계속 ----------
R="$T/r3"; mkfix "$R" t1 claude; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 2
g "$R" c3; git -C "$R" update-ref refs/remotes/origin/main HEAD
runit "$R" t1
ck "ⓒ rc0(멈추지 않는다)" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
has 'WARN 정본에 CronCreate 줄 2 — 오빠 11-08 자기 틱 크론 0(#274576) · 그 줄 지우고 다시 부팅' && ok || bad "ⓒ WARN 1줄(줄 수·인용)"
[ "$(printf '%s' "$out" | grep -cF 'WARN 정본에 CronCreate')" = 1 ] && ok || bad "ⓒ WARN 중복 0"
has '부팅 완료 t1' && ok || bad "ⓒ 경고 뒤에도 부팅 완료"

# ---------- ⓓ CronCreate 0줄 — WARN 0 ----------
R="$T/r4"; mkfix "$R" t1 claude; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0
g "$R" c4; git -C "$R" update-ref refs/remotes/origin/main HEAD
runit "$R" t1
ck "ⓓ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
has 'WARN' && bad "ⓓ CronCreate 0줄 → WARN 0" || ok

# ---------- 변이 M1·M2 — 검출력(변이본이면 ⓑ·ⓒ 가 FAIL 해야 한다) ----------
mut() {  # <src> <dst> <M1|M2>
  python3 - "$1" "$2" "$3" <<'PY'
import sys
src, dst, kind = sys.argv[1:4]
out = []
for line in open(src, encoding='utf-8').read().split('\n'):
    if kind == 'M1' and (line.startswith('  cron_cell=') or line.startswith('  [ "$AGENT" = pi ] && cron_cell=')):
        if '  cron_cell="none"' not in out:
            out.append('  cron_cell="none"')
        continue
    if kind == 'M2' and line.startswith('  ncron='):
        out.append('  ncron=0')
        continue
    out.append(line)
open(dst, 'w', encoding='utf-8').write('\n'.join(out))
PY
}
mut "$BIN/ft-team-boot.sh" "$T/m1.sh" M1; mut "$BIN/ft-team-boot.sh" "$T/m2.sh" M2
cp "$BIN/ft-team-seats-lib.sh" "$T/"   # r1535: 명부 읽기 = 같은 폴더 lib — 변이본 옆에도 둔다(B2 는 사례 밖)
bash -n "$T/m1.sh" && bash -n "$T/m2.sh" && ok || bad "변이본 bash -n"
diff -q "$BIN/ft-team-boot.sh" "$T/m1.sh" >/dev/null && bad "M1 변이 미적용" || ok
diff -q "$BIN/ft-team-boot.sh" "$T/m2.sh" >/dev/null && bad "M2 변이 미적용" || ok

R="$T/m1"; mkfix "$R" t1 claude; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0
g "$R" m1; git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/mbox.log"; runit "$R" t1 "$T/m1.sh"
grep -qF 'cron=판정 불가' "$REC/mbox.log" && bad "M1 미검출(변이본이 ⓑ 를 통과)" || ok
grep -qF 'cron=none ·' "$REC/mbox.log" && ok || bad "M1 변이본이 옛 고정 «none» 을 쓴다(검출 근거)"

R="$T/m2"; mkfix "$R" t1 claude; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 2
g "$R" m2; git -C "$R" update-ref refs/remotes/origin/main HEAD
runit "$R" t1 "$T/m2.sh"
has 'WARN 정본에 CronCreate' && bad "M2 미검출(변이본이 ⓒ 를 통과)" || ok

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS ($npass)"; exit 0; }
echo "FAILED $fail"; exit 1
