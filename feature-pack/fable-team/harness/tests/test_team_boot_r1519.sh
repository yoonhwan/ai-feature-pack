#!/usr/bin/env bash
# test_team_boot_r1519.sh — ft-team-boot.sh (r1519 · DESIGN-r1498 §4 B0~B5) 9사례 + 재개 두 갈래 + 정적 검사.
#   격리: 임시 git 리포(origin/main 대역 · design/teams/<팀>/ 재귀 CLOSEOUT) + 임시 명부 + 가짜 successor-open·nano-spawn·mbox·tmux·all-stop·launchd 자리 — 실 세션·실 우편함·실 좌석 0 · press 0.
#   사례: ①1장 ②날짜 다름 ③같은 날 ④옛 꼴 design/<팀>/ 만 ⑤0장 ⑥airag→aifp ⑦B5 실패 뒤 재실행(B5 만) ⑧이미 부팅됨 ⑨ALL_STOP · ⑩재개기록 있음(--resume 1개) ⑪없음(새 세션)
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
has() { printf '%s' "$out" | grep -q -- "$1"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ---------- 가짜 도구 ----------
FAKE="$T/fake"; mkdir -p "$FAKE" "$T/la"   # T/la = 빈 LaunchAgents 자리(launchd 미등재)
cat > "$FAKE/so_resume.sh" <<'EOF'
#!/usr/bin/env bash
[ $# -gt 0 ] || { echo "usage: $0 <구> <wt> --name N --agent A --model M --body-file F [--resume]" >&2; exit 2; }
printf '%s\n' "$*" >> "$FT_REC/so.log"
while [ $# -gt 0 ]; do case "$1" in --name) echo "$1=$2" >/dev/null; n="$2"; shift 2;; *) shift;; esac; done
echo "${n:-}" >> "$FT_REC/live.txt"; echo "DONE"; exit "${STUB_SO_RC:-0}"
EOF
sed 's/ \[--resume\]//' "$FAKE/so_resume.sh" > "$FAKE/so_plain.sh"   # --resume 을 모르는 도구(usage 에 없음)
cat > "$FAKE/nano.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FT_REC/nano.log"; echo "SPAWNED"; exit "${STUB_NANO_RC:-0}"
EOF
cat > "$FAKE/mbox.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FT_REC/mbox.log"; [ "${STUB_MBOX_RC:-0}" = 0 ] || { echo "ERROR 송신 실패(stub)"; exit 1; }
echo "QUEUED seq=4242 to=$2 pending=0"; exit 0
EOF
cat > "$FAKE/tmux.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = ls ] || exit 0; cat "$FT_REC/live.txt" 2>/dev/null; exit 0
EOF
cat > "$FAKE/allstop.sh" <<'EOF'
#!/usr/bin/env bash
[ "${STUB_ALLSTOP_RC:-0}" = 0 ] || { echo "REJECT 전팀 정지 중(stub 사유)"; exit 1; }
exit 0
EOF
chmod +x "$FAKE"/*.sh

REC="$T/rec"; mkdir -p "$REC"; : > "$REC/live.txt"
export FT_REC="$REC" FT_FIX="$T/fix"
export FT_MBOX_SH="$FAKE/mbox.sh" FT_NANO_SPAWN="$FAKE/nano.sh" FT_ALL_STOP="$FAKE/allstop.sh"
export FT_TMUX="$FAKE/tmux.sh" FT_LAUNCHAGENTS="$T/la" FT_BOOT_ME='byz-t1-nano-boot#0' FT_BOOT_REPORT_TO='byz-planner-master-pi#245'
export FT_SUCCESSOR_OPEN="$FAKE/so_resume.sh"

# ---------- 픽스처 리포 ----------
g() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$2"; }
mkfix() {  # <루트> <팀> [master_extra_json]
  local r="$1" t="$2" x="${3:-}" 
  mkdir -p "$r/design/teams/$t/indices/진행" "$r/.fable-team/comm" "$r/state" "$r/.worktrees/wt$t"
  git -C "$r" init -q -b main
  printf '{"_name":"T","_master":"byz-%s-master-claude#4","_cards":"design/teams/%s/indices","_cards_wt":"wt%s",\n "byz-%s-master-claude#4":{"role":"master","agent":"claude","model":"claude-sonnet-5-5[1m]"%s}}\n' \
    "$t" "$t" "$t" "$t" "$x" > "$r/.fable-team/seats-$t.json"
  echo '{"_master":"byz-planner-master-pi#245"}' > "$r/.fable-team/seats-planner.json"
  printf 'x\n' > "$r/design/teams/$t/indices/진행/a.md"; printf 'x\n' > "$r/design/teams/$t/indices/진행/b.md"
}
closeout() {  # <리포> <경로> <제목날짜> <재개행 수>
  mkdir -p "$(dirname "$1/$2")"
  { echo "# CLOSEOUT 테스트 $3"; echo; echo "## 골 원문"; echo; echo "골 첫 줄 $3"; echo "골 둘째 줄"; echo "골 셋째 줄"; echo
    echo "## 3. 진행 카드"; echo; i=0; while [ "$i" -lt "${4:-0}" ]; do
      c="a"; [ "$i" -gt 0 ] && c="b"; echo "| 카드 $c | \`indices/진행/$c.md\` | 재개: 예 |"; i=$((i+1)); done
    echo "| 카드 z | \`indices/진행/z.md\` | 재개: 아니오 |"; echo
    echo "## 4. 다시 여는 법"; echo; echo "- 새 세션 → 이 CLOSEOUT → 카드"; } > "$1/$2"
}
run() {  # <루트> <팀>  — out·rc 갱신(살아 있는 세션 자리 초기화 — 사례끼리 안 섞는다)
  : > "$REC/live.txt"
  out="$(cd "$1" && FT_REPO_ROOT="$1" bash "$BIN/ft-team-boot.sh" "$2" 2>&1)"; rc=$?
}
cnt() { local n=0; [ -f "$REC/$1" ] && n="$(grep -c . "$REC/$1" 2>/dev/null)"; echo "${n:-0}"; }

# ---------- ① CLOSEOUT 1장 (재개 0) ----------
R="$T/r1"; mkfix "$R" t1; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0
g "$R" c1; git -C "$R" update-ref refs/remotes/origin/main HEAD
run "$R" t1
ck "① rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"; has "부팅 완료 t1" && ok || bad "① 완료 줄"
[ "$(cnt so.log)" = 1 ] && ok || bad "① spawn 팀장 1"
[ "$(cnt nano.log)" = 0 ] && ok || bad "① 재개 카드 0 → nano 호출 0"
[ "$(cnt mbox.log)" = 1 ] && grep -q '\[부팅\] t1 — 좌석=byz-t1-master-claude#5' "$REC/mbox.log" && ok || bad "① B5 보고 1통 꼴"
grep -q 'launchd=미등재' "$REC/mbox.log" && grep -qF 'cron=판정 불가(세션 안' "$REC/mbox.log" && ok || bad "① B5 cron·launchd 칸(r1534: claude 팀장 = 판정 불가)"
has 'total=' && printf '%s' "$out" | grep -qE 'B0=[0-9]+s.*B5=[0-9]+s' && ok || bad "① 단계별 초(하드 룰 22)"
PLAN1="$(ls -1 "$R/.fable-team/state/team-boot/"t1-*.plan | head -1)"
grep -q 'closeout=design/teams/t1/CLOSEOUT-t1-20261109.md' "$PLAN1" && grep -q '^status=완료' "$PLAN1" && ok || bad "① plan 정본·status"

# ---------- ② 날짜 다름 — 이름 날짜 최대값 (옛 이름이 더 최근 커밋이어도) ----------
R="$T/r2"; mkfix "$R" t1; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261101.md 01 0
g "$R" old-first; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0; g "$R" dup-newer-commit
git -C "$R" update-ref refs/remotes/origin/main HEAD
run "$R" t1
ck "② rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"; grep -q 'CLOSEOUT-t1-20261109.md' "$(ls -1 "$R/.fable-team/state/team-boot/"t1-*.plan | head -1)" && ok || bad "② 이름 날짜 최대값"

# ---------- ③ 같은 날 2장 — 최신 커밋 ----------
R="$T/r3"; mkfix "$R" t1
closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109-a.md a 0; g "$R" a-first
closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109-b.md b 0; g "$R" b-later
git -C "$R" update-ref refs/remotes/origin/main HEAD
run "$R" t1
ck "③ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"; grep -q 'CLOSEOUT-t1-20261109-b.md' "$(ls -1 "$R/.fable-team/state/team-boot/"t1-*.plan | head -1)" && ok || bad "③ 같은 날 = 최신 커밋"

# ---------- ④ 옛 꼴 design/<팀>/ 에만 정본 — 집지 않는다 ----------
R="$T/r4"; mkfix "$R" t1; closeout "$R" design/t1/CLOSEOUT-t1-20261101.md 01 0; g "$R" legacy
git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/so.log"; run "$R" t1
ck "④ 멈춤 rc1" "$([ "$rc" = 1 ] && echo 0 || echo 1)"; has "멈춤 정본 없음" && ok || bad "④ 정본 없음 멈춤"
[ "$(cnt so.log)" = 0 ] && ok || bad "④ 손 부팅 대체 0"

# ---------- ⑤ 0장 ----------
R="$T/r5"; mkfix "$R" t1; g "$R" no-closeout; git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/so.log"; run "$R" t1
ck "⑤ 멈춤 rc1" "$([ "$rc" = 1 ] && echo 0 || echo 1)"; has "멈춤 정본 없음" && ok || bad "⑤ 정본 없음"
[ "$(cnt so.log)" = 0 ] && ok || bad "⑤ spawn 0"

# ---------- ⑥ airag → 팩 위성팀(r1535 B2): 정본 = PACK design/aifp · 명부 = PACK/.fable-team/seats-aifp.json · 팀장 = aifp-airag-master-* 최대 #N · 워크트리 = PACK/.worktrees ----------
P="$T/pack"; A="$T/aifp"
mkdir -p "$P/design/aifp" "$A/.fable-team" "$P/.worktrees/wtairag" "$P/.fable-team" "$P/design/teams/airag" "$A/design/teams/airag"
git -C "$P" init -q -b main; closeout "$P" design/aifp/CLOSEOUT-airag-20261109.md airag 0
git -C "$A" init -q -b main
# 키 순서가 #N 순서가 아니다(#14 가 맨 앞이 아니다) — «첫 행» 이 아니라 «최대 #N» 이라야 #14 를 집는다
printf '{"_name":"AIFP","_master":"aifp-pi-master-pi#0","_cards":"design/aifp/indices","_cards_wt":"wtairag",\n "aifp-airag-master-claude#14":{"role":"master","agent":"claude","model":"claude-opus-5-6[1m]"},\n "aifp-pi-master-pi#0":{"role":"master","agent":"pi","model":"deepseek/deepseek-v4.1-flash-ultrafast"},\n "aifp-airag-master-claude#12":{"role":"master","agent":"claude","model":"claude-opus-5-5"},\n "aifp-airag-master-claude#13":{"role":"master","agent":"claude","model":"claude-opus-5-5"}}\n' > "$P/.fable-team/seats-aifp.json"
echo '{"_master":"byz-planner-master-pi#245"}' > "$A/.fable-team/seats-planner.json"
printf 'k\n' > "$A/design/teams/airag/keep.md"; g "$P" aifp; g "$A" a-base
git -C "$P" update-ref refs/remotes/origin/main HEAD; git -C "$A" update-ref refs/remotes/origin/main HEAD
: > "$REC/so.log"; : > "$REC/live.txt"
out="$(cd "$A" && FT_REPO_ROOT="$A" FT_PACK_ROOT="$P" FT_AIFP_ROOT="$A" FT_BOOT_STATE="$A/.fable-team/state/team-boot" bash "$BIN/ft-team-boot.sh" airag 2>&1)"; rc=$?
ck "⑥ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"; grep -q 'closeout=design/aifp/CLOSEOUT-airag-20261109.md' "$(ls -1 "$A/.fable-team/state/team-boot/"airag-*.plan | head -1)" && ok || bad "⑥ aifp 경로"
grep -q "^aifp-airag-master-claude#14 $P/.worktrees/wtairag --name aifp-airag-master-claude#15 --agent claude --model claude-opus-5-6\[1m\] " "$REC/so.log" && ok || bad "⑥ 팀장 = seats-aifp 최대 #N(#14) · 워크트리 = PACK/.worktrees · 이름 #15"
grep -q 'aifp-pi-master-pi#0' "$REC/so.log" && bad "⑥ 팩 팀장(_master) 대체 0" || ok

# ---------- ⑦ B5 송신 실패 → 재실행 = B5 만 · spawn 0 ----------
R="$T/r7"; mkfix "$R" t1; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 1
g "$R" c7; git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/so.log"; : > "$REC/nano.log"; : > "$REC/mbox.log"; : > "$REC/live.txt"
out="$(cd "$R" && FT_REPO_ROOT="$R" STUB_MBOX_RC=1 bash "$BIN/ft-team-boot.sh" t1 2>&1)"; rc=$?
ck "⑦ 보고 미도달 rc5" "$([ "$rc" = 5 ] && echo 0 || echo 1)"; has "보고 미도달" && ok || bad "⑦ 보고 미도달 줄"
P7="$(ls -1 "$R/.fable-team/state/team-boot/"t1-*.plan | head -1)"
grep -q '^b5=보고 미도달' "$P7" && ok || bad "⑦ plan b5 실패 기록"
ck "⑦ spawn = 팀장 1 + 재개 카드 1" "$([ "$(cnt so.log)" = 1 ] && [ "$(cnt nano.log)" = 1 ] && echo 0 || echo 1)"
so1="$(cnt so.log)"; nano1="$(cnt nano.log)"
out="$(cd "$R" && FT_REPO_ROOT="$R" bash "$BIN/ft-team-boot.sh" t1 2>&1)"; rc=$?
ck "⑦ 재실행 rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"; has "B2 skip" && ok || bad "⑦ 재실행 spawn 0(B2 skip)"
has "B3 skip" && ok || bad "⑦ 재실행 B3 skip"
[ "$(cnt so.log)" = "$so1" ] && ok || bad "⑦ 재실행 successor 호출 0"
[ "$(cnt nano.log)" = "$nano1" ] && ok || bad "⑦ 재실행 nano 호출 0"
grep -q '^b5=done seq=4242' "$P7" && ok || bad "⑦ plan b5 seq 기록"

# ---------- ⑧ 이미 부팅됨 ----------
R="$T/r8"; mkfix "$R" t1; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0; g "$R" c8
git -C "$R" update-ref refs/remotes/origin/main HEAD
printf 'byz-t1-master-claude#9\n' > "$REC/live.txt"; : > "$REC/so.log"
out="$(cd "$R" && FT_REPO_ROOT="$R" bash "$BIN/ft-team-boot.sh" t1 2>&1)"; rc=$?
ck "⑧ 멈춤 rc1" "$([ "$rc" = 1 ] && echo 0 || echo 1)"; has "이미 부팅됨 byz-t1-master-claude#9" && ok || bad "⑧ 이미 부팅됨"
[ "$(cnt so.log)" = 0 ] && ok || bad "⑧ 두 번 열기 0"

# ---------- ⑨ ALL_STOP 켜짐 — check REJECT 그대로 ----------
R="$T/r9"; mkfix "$R" t1; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0; g "$R" c9
git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/live.txt"; : > "$REC/so.log"
out="$(cd "$R" && FT_REPO_ROOT="$R" STUB_ALLSTOP_RC=1 bash "$BIN/ft-team-boot.sh" t1 2>&1)"; rc=$?
ck "⑨ 멈춤 rc1" "$([ "$rc" = 1 ] && echo 0 || echo 1)"
has 'REJECT 전팀 정지 중(stub 사유)' && ok || bad "⑨ check REJECT 그대로"
[ "$(cnt so.log)" = 0 ] && ok || bad "⑨ spawn 0"

# ---------- ⑩⑪ 재개 두 갈래 — 기록 있으면 --resume 1개 · 없으면 새 세션 ----------
R="$T/r10"; mkfix "$R" t1 ',"_resume_uuid":"11111111-2222-3333-4444-555555555555"'
closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0; g "$R" c10
git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/live.txt"; : > "$REC/so.log"
out="$(cd "$R" && FT_REPO_ROOT="$R" FT_SUCCESSOR_OPEN="$FAKE/so_resume.sh" bash "$BIN/ft-team-boot.sh" t1 2>&1)"; rc=$?
ck "⑩ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
grep -q -- '--resume' "$REC/so.log" && [ "$(grep -o -- '--resume' "$REC/so.log" | wc -l | tr -d ' ')" = 1 ] && ok || bad "⑩ 기록 있음 → --resume 인자 1개"
R="$T/r11"; mkfix "$R" t1 ',"_resume_uuid":"99999999-8888-7777-6666-555555555555"'
closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0; g "$R" c11
git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/live.txt"; : > "$REC/so.log"
out="$(cd "$R" && FT_REPO_ROOT="$R" FT_SUCCESSOR_OPEN="$FAKE/so_plain.sh" bash "$BIN/ft-team-boot.sh" t1 2>&1)"; rc=$?
ck "⑪ rc0(미지원 도구)" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
grep -q -- '--resume' "$REC/so.log" && bad "⑪ 미지원 도구에 --resume 넘김 0" || ok
has 'WARN --resume 미지원' && ok || bad "⑪ 미지원 WARN(조용한 대체 아님)"
R="$T/r12"; mkfix "$R" t1; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0; g "$R" c12
git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/live.txt"; : > "$REC/so.log"
out="$(cd "$R" && FT_REPO_ROOT="$R" bash "$BIN/ft-team-boot.sh" t1 2>&1)"; rc=$?
ck "⑫ rc0(재개 기록 없음)" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
grep -q -- '--resume' "$REC/so.log" && bad "⑫ 기록 없음 → --resume 0" || ok
has 'WARN' && bad "⑫ 기록 없음 = WARN 0" || ok

# ---------- ⑬ R1 B0 동점 — 같은 이름날짜·같은 커밋초 선형(old-z → new-a) = 계보가 뒤인 new-a ----------
R="$T/r13"; mkfix "$R" t1
closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109-z.md z 0
z="design/teams/t1/CLOSEOUT-t1-20261109-z.md"; a="design/teams/t1/CLOSEOUT-t1-20261109-a.md"
git -C "$R" add -A >/dev/null 2>&1
GIT_COMMITTER_DATE='2026-11-09T00:00:00 +0000' GIT_AUTHOR_DATE='2026-11-09T00:00:00 +0000' git -C "$R" -c user.name=t -c user.email=t@t commit -q -m z-old
closeout "$R" "$a" a 0
git -C "$R" add -A >/dev/null 2>&1
GIT_COMMITTER_DATE='2026-11-09T00:00:00 +0000' GIT_AUTHOR_DATE='2026-11-09T00:00:00 +0000' git -C "$R" -c user.name=t -c user.email=t@t commit -q -m a-new
# 계보가 뒤인 new-a 의 sha 가 더 «작은» 경우를 강제 — sha 사전순 우연으로 통과하지 못하게 한다(DA R1 은 «계보가 뒤 = 최신»)
sa=""; sz=""; k=0
while [ "$k" -lt 40 ]; do
  GIT_COMMITTER_DATE='2026-11-09T00:00:00 +0000' GIT_AUTHOR_DATE='2026-11-09T00:00:00 +0000' git -C "$R" -c user.name=t -c user.email=t@t commit -q --amend -m "a-new $k"
  sa="$(git -C "$R" rev-parse HEAD)"; sz="$(git -C "$R" rev-parse HEAD~1)"
  [ "$sa" \< "$sz" ] && break
  k=$((k+1))
done
git -C "$R" update-ref refs/remotes/origin/main HEAD
[ "$sa" \< "$sz" ] && ok || bad "⑬ 픽스처: 계보 뒤 new-a 의 sha 가 더 작다(sha 사전순이면 옛 장이 뽑힌다)"
[ "$(git -C "$R" log -1 --format=%ct -- "$z")" = "$(git -C "$R" log -1 --format=%ct -- "$a")" ] && ok || bad "⑬ 픽스처 커밋초 동점 성립"
: > "$REC/live.txt"; : > "$REC/so.log"; run "$R" t1
ck "⑬ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
grep -q 'closeout=design/teams/t1/CLOSEOUT-t1-20261109-a.md' "$(ls -1t "$R/.fable-team/state/team-boot/"t1-*.plan | head -1)" && ok || bad "⑬ 동점 = 계보 뒤(new-a) · ls-tree 경로 순서 의존 0"

# ---------- ⑭ R2 완료 plan 뒤 새 정본 = 새 생명(새 plan·spawn 1) · 같은 정본 = 이미 부팅됨 ----------
R="$T/r14"; mkfix "$R" t1; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0; g "$R" c14; git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/live.txt"; : > "$REC/so.log"; run "$R" t1
ck "⑭ 1회차 rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
closeout "$R" design/teams/t1/CLOSEOUT-t1-20261110.md 10 0; g "$R" c14b; git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/live.txt"; run "$R" t1
ck "⑭ 새 정본 뒤 rc0(과거 완료 plan 이 막지 않는다)" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
[ "$(cnt so.log)" = 2 ] && ok || bad "⑭ 새 생명 = 팀장 spawn 합계 2"
[ "$(ls -1 "$R/.fable-team/state/team-boot/"t1-*.plan 2>/dev/null | grep -c .)" = 2 ] && ok || bad "⑭ plan 2장(생명마다 1장)"
grep -q 'closeout=design/teams/t1/CLOSEOUT-t1-20261110.md' "$(ls -1t "$R/.fable-team/state/team-boot/"t1-*.plan | head -1)" && ok || bad "⑭ 새 plan 정본 = 20261110"
: > "$REC/live.txt"; run "$R" t1
ck "⑭ 같은 정본 재실행 = 멈춤 rc1" "$([ "$rc" = 1 ] && echo 0 || echo 1)"
has '이미 부팅됨' && ok || bad "⑭ 같은 정본 = 이미 부팅됨"
[ "$(cnt so.log)" = 2 ] && ok || bad "⑭ 같은 정본 두 번 열기 0"

# ---------- ⑮ R3 B5 재시도 = 같은 plan b2name 고정(NEXT 재계산 아님) ----------
R="$T/r15"; mkfix "$R" t1; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0; g "$R" c15; git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/live.txt"; : > "$REC/so.log"; : > "$REC/mbox.log"
est=$(cd "$R" && FT_REPO_ROOT="$R" STUB_MBOX_RC=1 bash "$BIN/ft-team-boot.sh" t1 2>&1); rc=$?
out="$est"
ck "⑮ 1회차 보고 미도달 rc5" "$([ "$rc" = 5 ] && echo 0 || echo 1)"
[ "$(cnt so.log)" = 1 ] && ok || bad "⑮ 1회차 팀장 1"
python3 - "$R/.fable-team/seats-t1.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); old="byz-t1-master-claude#4"; new="byz-t1-master-claude#5"
d[new]=dict(d[old]); d["_master"]=new
json.dump(d,open(p,"w"),ensure_ascii=False)
PY
printf 'byz-t1-master-claude#5\n' > "$REC/live.txt"
: > "$REC/mbox.log"
out="$(cd "$R" && FT_REPO_ROOT="$R" bash "$BIN/ft-team-boot.sh" t1 2>&1)"; rc=$?
ck "⑮ 재시도 rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
has 'B2 skip' && ok || bad "⑮ 재시도 B2 skip(spawn 0)"
[ "$(cnt so.log)" = 1 ] && ok || bad "⑮ 재시도 팀장 spawn 합계 1"
grep -q '좌석=byz-t1-master-claude#5' "$REC/mbox.log" && ok || bad "⑮ 보고 좌석 = plan b2name(#5) · NEXT(#6) 아님"
grep -q '좌석=byz-t1-master-claude#6' "$REC/mbox.log" && bad "⑮ NEXT 재계산 좌석(#6) 0" || ok

# ---------- ⑯ 로케일 — LC_ALL 없이도(기본 UTF-8 쉘) 변수명 오결합 0 — 보통 $NREOPEN장 → $NREOPEN 었(ELF)으로 잃지 않는다 ----------
R="$T/r16"; mkfix "$R" t1; closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 09 0; g "$R" c16; git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/live.txt"; : > "$REC/so.log"
out="$(cd "$R" && env -u LC_ALL FT_REPO_ROOT="$R" bash "$BIN/ft-team-boot.sh" t1 2>&1)"; rc=$?
ck "⑯ LC_ALL 없음 rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
printf '%s' "$out" | grep -qE '바인딩 해제|unbound' && bad "⑯ 로케일 변수명 오결합 0" || ok

# ---------- 정적 검사 — 크론·launchd 생성 0 (r1534: CronCreate 는 정본 «읽기»만 — 도구 호출 꼴 «CronCreate(» 만 생성으로 본다) ----------
grep -nE 'CronCreate[[:space:]]*\(|launchctl (bootstrap|load)|crontab ' "$BIN/ft-team-boot.sh" >/dev/null 2>&1 && bad "정적: 크론·launchd 생성 줄" || ok
for f in ft-successor-open.sh ft-nano-spawn.sh ft-all-stop.sh; do grep -q "$f" "$BIN/ft-team-boot.sh" && ok || bad "정적: $f 호출만(수정 0)"; done

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS ($npass)"; exit 0; }
echo "FAILED $fail"; exit 1
