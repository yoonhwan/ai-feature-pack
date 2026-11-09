#!/usr/bin/env bash
# test_team_boot_pack_r1535.sh — ft-team-boot.sh r1535 B2: 팩 위성팀(airag) 팀장 = PACK/.fable-team/seats-aifp.json 의 aifp-<팀>-master-* 중 #N 최대 · 워크트리 뿌리 PACK/.worktrees · 행 0 = 멈춤(팩 _master 대체 0) · BYZ 팀 변화 0.
#   격리: 임시 PACK 리포(design/aifp CLOSEOUT · seats-aifp.json · PACK/.worktrees/rag-transplant) + 임시 aifp 루트(A) + 임시 BYZ 리포 + 가짜 successor-open·nano·mbox·tmux·all-stop·launchd 자리 — 실 세션·실 우편함·실 명부 0 · press 0.
#   사례: ⓐ airag = #14(키 순서 아님) · ⓑ airag 팀장 행 0 = 멈춤 · ⓒ #14 워크트리 PACK/.worktrees 에 없음 = 멈춤 · ⓓ BYZ 팀 = 지금 그대로 · ⓔ FT_SEATS_JSON 이 있으면 그 명부(같은 규칙)
#   변이: M1 명부를 $DROOT/.fable-team/seats-<팀>.json 로 되돌림 → ⓐ FAIL · M2 첫 행(최대 #N 아님) → ⓐ FAIL · M3 워크트리 뿌리 ROOT → ⓐ FAIL
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
FAKE="$T/fake"; mkdir -p "$FAKE" "$T/la"
cat > "$FAKE/so.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FT_REC/so.log"
while [ $# -gt 0 ]; do case "$1" in --name) echo "$2" >> "$FT_REC/live.txt"; shift 2;; *) shift;; esac; done
echo "DONE"; exit "${STUB_SO_RC:-0}"
EOF
cat > "$FAKE/nano.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FT_REC/nano.log"; echo "SPAWNED"; exit 0
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
export FT_REC="$REC" FT_LAUNCHAGENTS="$T/la" FT_BOOT_ME='byz-harness-nano-r1535#0' FT_BOOT_REPORT_TO='byz-planner-master-pi#245'
export FT_MBOX_SH="$FAKE/mbox.sh" FT_NANO_SPAWN="$FAKE/nano.sh" FT_ALL_STOP="$FAKE/allstop.sh" FT_TMUX="$FAKE/tmux.sh" FT_SUCCESSOR_OPEN="$FAKE/so.sh"
g() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$2"; }
closeout() {  # <리포> <경로> <날짜표시>
  mkdir -p "$(dirname "$1/$2")"
  { echo "# CLOSEOUT 테스트 $3"; echo; echo "## 골 원문"; echo; echo "골 첫 줄 $3"; echo "골 둘째 줄"; echo "골 셋째 줄"; echo
    echo "## 4. 다시 여는 법"; echo; echo "- 새 세션 → 이 CLOSEOUT → 카드"; } > "$1/$2"
}
SEATS_OK='{"_name":"AIFP","_master":"aifp-pi-master-pi#0","_cards":"design/aifp/indices","_cards_wt":"wt-none",
 "aifp-pi-master-pi#0":{"role":"master","agent":"pi","model":"deepseek/deepseek-v4.1-flash-ultrafast"},
 "aifp-airag-master-claude#12":{"role":"master","agent":"claude","model":"claude-opus-5-5","worktree":"rag-transplant"},
 "aifp-airag-master-claude#14":{"role":"master","agent":"claude","model":"claude-opus-5-6[1m]","worktree":"rag-transplant"},
 "aifp-airag-master-claude#13":{"role":"master","agent":"claude","model":"claude-opus-5-5","worktree":"rag-transplant"}}'
mkpack() {  # <PACK> <A> [seats json] — 팩 위성팀 픽스처
  local p="$1" a="$2" s="${3:-$SEATS_OK}"
  mkdir -p "$p/design/aifp/indices/진행" "$p/.fable-team/comm" "$p/design/teams/airag" "$p/.worktrees/rag-transplant" \
           "$a/.fable-team/comm" "$a/state" "$a/design/teams/airag"
  git -C "$p" init -q -b main >/dev/null 2>&1
  git -C "$a" init -q -b main >/dev/null 2>&1
  printf 'k\n' > "$p/design/teams/airag/keep.md"
  closeout "$p" design/aifp/CLOSEOUT-airag-20261109.md 20261109
  printf '%s\n' "$s" > "$p/.fable-team/seats-aifp.json"
  g "$p" pack-init; git -C "$p" update-ref refs/remotes/origin/main HEAD
  printf '{"_master":"byz-planner-master-pi#245"}\n' > "$a/.fable-team/seats-planner.json"
  printf 'k\n' > "$a/design/teams/airag/keep.md"
  g "$a" aifp-root; git -C "$a" update-ref refs/remotes/origin/main HEAD
}
runpack() {  # <PACK> <A> [env…] — out·rc 갱신
  local p="$1" a="$2"; shift 2
  : > "$REC/live.txt"; : > "$REC/so.log"; : > "$REC/mbox.log"
  out="$(cd "$a" && env FT_REPO_ROOT="$a" FT_PACK_ROOT="$p" FT_AIFP_ROOT="$a" FT_BOOT_STATE="$a/state/team-boot" "$@" bash "$BIN/ft-team-boot.sh" airag 2>&1)"; rc=$?
}
cnt() { local n=0; [ -f "$REC/$1" ] && n="$(grep -c . "$REC/$1" 2>/dev/null)"; echo "${n:-0}"; }

# ---------- ⓐ airag = seats-aifp.json 의 #N 최대(#14 — 키 순서 아님) · 워크트리 PACK/.worktrees ----------
P="$T/pack1"; A="$T/a1"; mkpack "$P" "$A"
runpack "$P" "$A"
ck "ⓐ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
grep -qF "$P/.worktrees/rag-transplant --name aifp-airag-master-claude#15 --agent claude --model claude-opus-5-6[1m]" "$REC/so.log" \
  && grep -q "^aifp-airag-master-claude#14 " "$REC/so.log" && ok || bad "ⓐ OLD=#14 · 이름 #15 · agent·model = #14 행 · 워크트리 = PACK/.worktrees"
grep -q '^aifp-pi-master-pi#0 ' "$REC/so.log" && bad "ⓐ 팩 팀장(_master) 대체 0" || ok
has 'total=' && printf '%s' "$out" | grep -qE 'B0=[0-9]+s.*B5=[0-9]+s' && ok || bad "ⓐ 단계별 초(하드 룰 22)"
grep -q 'closeout=design/aifp/CLOSEOUT-airag-20261109.md' "$(ls -1t "$A/state/team-boot/"airag-*.plan | head -1)" && ok || bad "ⓐ 정본 = PACK design/aifp"
[ "$(cnt mbox.log)" = 1 ] && grep -q '좌석=aifp-airag-master-claude#15' "$REC/mbox.log" && ok || bad "ⓐ B5 보고 좌석 = #15"

# ---------- ⓑ airag 팀장 행 0 — 팩 _master 로 대체 0 · 멈춤 ----------
P="$T/pack2"; A="$T/a2"
mkpack "$P" "$A" '{"_name":"AIFP","_master":"aifp-pi-master-pi#0","_cards_wt":"rag-transplant",
 "aifp-pi-master-pi#0":{"role":"master","agent":"pi","model":"deepseek/deepseek-v4.1-flash-ultrafast"},
 "aifp-airag-da-claude#3":{"role":"da","agent":"claude","model":"claude-opus-5-5","worktree":"rag-transplant"}}'
runpack "$P" "$A"
ck "ⓑ 멈춤 rc1" "$([ "$rc" = 1 ] && echo 0 || echo 1)"
has '멈춤 명부 팀장 없음' && printf '%s' "$out" | grep -qF 'seats-aifp.json aifp-airag-master-*' && ok || bad "ⓑ 멈춤 문면(seats-aifp.json aifp-airag-master-*)"
[ "$(cnt so.log)" = 0 ] && ok || bad "ⓑ 팩 팀장 대체 0(spawn 0)"
[ "$(cnt mbox.log)" = 0 ] && ok || bad "ⓑ 보고 0"

# ---------- ⓒ #14 행 워크트리가 PACK/.worktrees 에 없음 — 멈춤 ----------
P="$T/pack3"; A="$T/a3"
mkpack "$P" "$A" '{"_name":"AIFP","_master":"aifp-pi-master-pi#0","_cards_wt":"wt-none",
 "aifp-airag-master-claude#14":{"role":"master","agent":"claude","model":"claude-opus-5-6[1m]","worktree":"no-such-wt"}}'
runpack "$P" "$A"
ck "ⓒ 멈춤 rc1" "$([ "$rc" = 1 ] && echo 0 || echo 1)"
has '멈춤 워크트리 없음 aifp-airag-master-claude#14' && ok || bad "ⓒ 워크트리 없음 멈춤(#14)"
[ "$(cnt so.log)" = 0 ] && ok || bad "ⓒ spawn 0"

# ---------- ⓓ BYZ 팀 = 지금 그대로(명부 seats-<팀>.json _master · 워크트리 ROOT/.worktrees) ----------
R="$T/byz"; mkdir -p "$R/design/teams/t1" "$R/.fable-team/comm" "$R/state" "$R/.worktrees/wtt1"
git -C "$R" init -q -b main >/dev/null 2>&1
printf '{"_name":"T","_master":"byz-t1-master-claude#4","_cards":"design/teams/t1/indices","_cards_wt":"wtt1",\n "byz-t1-master-claude#4":{"role":"master","agent":"claude","model":"claude-sonnet-5-5[1m]"}}\n' > "$R/.fable-team/seats-t1.json"
printf '{"_master":"byz-planner-master-pi#245"}\n' > "$R/.fable-team/seats-planner.json"
closeout "$R" design/teams/t1/CLOSEOUT-t1-20261109.md 20261109
g "$R" byz-init; git -C "$R" update-ref refs/remotes/origin/main HEAD
: > "$REC/live.txt"; : > "$REC/so.log"
out="$(cd "$R" && FT_REPO_ROOT="$R" bash "$BIN/ft-team-boot.sh" t1 2>&1)"; rc=$?
ck "ⓓ BYZ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
grep -qF -- "byz-t1-master-claude#4 $R/.worktrees/wtt1 --name byz-t1-master-claude#5 --agent claude --model claude-sonnet-5-5[1m]" "$REC/so.log" && ok || bad "ⓓ BYZ 팀 = _master · ROOT/.worktrees 그대로"
grep -q 'closeout=design/teams/t1/CLOSEOUT-t1-20261109.md' "$(ls -1t "$R/state/team-boot/"t1-*.plan | head -1)" && ok || bad "ⓓ BYZ 정본 = design/teams/<팀>"

# ---------- ⓔ FT_SEATS_JSON 을 주면 그 명부 — 팀장 고르기 규칙은 그대로(#N 최대) ----------
P="$T/pack4"; A="$T/a4"; mkpack "$P" "$A"
ALT="$T/alt-seats.json"
printf '{"_name":"ALT","_master":"aifp-pi-master-pi#0","_cards_wt":"rag-transplant",\n "aifp-airag-master-codex#21":{"role":"master","agent":"codex","model":"gpt-5.6-luna","worktree":"rag-transplant"},\n "aifp-airag-master-codex#20":{"role":"master","agent":"codex","model":"gpt-5.6-luna","worktree":"rag-transplant"}}\n' > "$ALT"
runpack "$P" "$A" FT_SEATS_JSON="$ALT"
ck "ⓔ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
grep -qF -- "--name aifp-airag-master-codex#22 --agent codex --model gpt-5.6-luna" "$REC/so.log" && ok || bad "ⓔ FT_SEATS_JSON 명부 · #N 최대(#21) · 이름 #22"

# ---------- 변이 3종 — 각각 ⓐ 를 FAIL 시켜야 한다(변이 흡수 0) ----------
mut() {  # <이름> <파일> <sed 식> — 변이 bin 사본을 만들어 ⓐ 를 다시 돌린다
  local n="$1" f="$2" e="$3" d="$T/mut-$1"
  mkdir -p "$d"; cp "$BIN/ft-team-boot.sh" "$BIN/ft-team-seats-lib.sh" "$d/"
  sed -i '' "$e" "$d/$f"
  if cmp -s "$BIN/$f" "$d/$f"; then bad "변이 $n 미적용(sed 0)"; return 1; fi
  P="$T/pack1"; A="$T/a1"   # ⓐ 와 같은 픽스처(같은 plan 재사용을 피해 상태 새로)
  : > "$REC/live.txt"; : > "$REC/so.log"
  rm -rf "$A/state/team-boot"
  out="$(cd "$A" && FT_REPO_ROOT="$A" FT_PACK_ROOT="$P" FT_AIFP_ROOT="$A" FT_BOOT_STATE="$A/state/team-boot" FT_SUCCESSOR_OPEN="$FAKE/so.sh" bash "$d/ft-team-boot.sh" airag 2>&1)"; rc=$?
  printf '%s' "$out"
}
o="$(mut M1 ft-team-seats-lib.sh 's|SEATS="${FT_SEATS_JSON:-$PACK/.fable-team/seats-aifp.json}"|SEATS="${FT_SEATS_JSON:-$DROOT/.fable-team/seats-$TEAM.json}"|')"
printf '%s' "$o" | grep -qF '멈춤 명부 없음' && ok || bad "M1 명부를 seats-<팀>.json 로 되돌리면 ⓐ 가 FAIL 해야 한다"
o="$(mut M2 ft-team-seats-lib.sh 's|print(max(ks, key=lambda k:int(k.rsplit("#",1)\[1\])) if ks else "")|print(ks[0] if ks else "")|')"
rc=1; printf '%s' "$o" | grep -qF -- '--name aifp-airag-master-claude#15' && bad "M2 첫 행이면 #14 를 집으면 안 된다(변이 흡수)" || ok
o="$(mut M3 ft-team-boot.sh 's|SAT=1; WROOT="$PACK/.worktrees"|SAT=1; WROOT="$ROOT/.worktrees"|')"
printf '%s' "$o" | grep -qF '멈춤 워크트리 없음' && ok || bad "M3 워크트리 뿌리를 ROOT 로 되돌리면 ⓐ 가 FAIL 해야 한다"
mut_n="$(ls -1d "$T"/mut-M1 "$T"/mut-M2 "$T"/mut-M3 2>/dev/null | wc -l | tr -d ' ')"

# ---------- 정적 — kit 사본 같은 내용 · 실행 비트 0(새 lib) ----------
cmp -s "$BIN/ft-team-boot.sh" "$BIN/../kit/fable-team/bin/ft-team-boot.sh" && ok || bad "정적: kit 사본 ft-team-boot.sh diff 0"
cmp -s "$BIN/ft-team-seats-lib.sh" "$BIN/../kit/fable-team/bin/ft-team-seats-lib.sh" && ok || bad "정적: kit 사본 ft-team-seats-lib.sh diff 0"
[ -x "$BIN/ft-team-seats-lib.sh" ] && bad "정적: 새 lib 실행 비트 0(r1305)" || ok

echo "----"
if [ "$fail" = 0 ]; then echo "ALL PASS ($npass) · 변이적용 $mut_n/3"; exit 0; fi
echo "FAILED $fail"; exit 1
