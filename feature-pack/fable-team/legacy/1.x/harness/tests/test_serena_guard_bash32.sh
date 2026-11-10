#!/usr/bin/env bash
# test_serena_guard_bash32.sh — R327: serena-guard 가 /bin/bash(3.2) 에서 끝까지 돈다 (mapfile 제거).
# 가짜 pgrep·ps(PATH 앞) · 임시 로그 · SERENA_GUARD_DRY=1 — 실 Serena 기동·kill 0 · 실 launchctl 0.
# 판정 셸 = /bin/bash(3.2) + bash 5(있으면) 둘 다.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
ZC="$REPO/harness/kit/zombie-clean"
GUARD="$ZC/serena-guard.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:240}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }

F="$T/fake"; mkdir -p "$F"
cat > "$F/pgrep" <<EOF
#!/bin/bash
[ -s "$T/pgrep.out" ] || exit 1
cat "$T/pgrep.out"
EOF
cat > "$F/ps" <<EOF
#!/bin/bash
# 사용: ps -o command= -p PID | ps -o rss= -p PID | ps -o ppid= -p PID
field="" pid=""
while [ \$# -gt 0 ]; do
  case "\$1" in -o) field="\${2%=}"; shift 2;; -p) pid="\$2"; shift 2;; *) shift;; esac
done
line="\$(grep "^\$pid " "$T/ps.tbl")" || exit 1
rss="\$(echo "\$line" | awk '{print \$2}')"
case "\$field" in
  rss) echo "\$rss";;
  ppid) echo 1;;
  command) echo "\${line#* * }";;
esac
EOF
chmod +x "$F/pgrep" "$F/ps"

SRV='python serena start-mcp-server --transport streamable-http --host 127.0.0.1'
run_guard() {  # $1=셸  → rc=<n> 와 stderr 를 $T/err 에 남긴다
  : > "$T/log"
  PATH="$F:/usr/bin:/bin" HOME="$T/home" SERENA_GUARD_LOG="$T/log" SERENA_GUARD_DRY=1 \
    "$1" "$GUARD" 2>"$T/err" >/dev/null
  echo $?
}

SHELLS="/bin/bash"; [ -x /opt/homebrew/bin/bash ] && SHELLS="$SHELLS /opt/homebrew/bin/bash"
for sh in $SHELLS; do
  ver="$("$sh" -c 'echo ${BASH_VERSION%%.*}')"; tag="bash$ver"

  # ⓐ pgrep 0개 → exit 0 · 로그 없음
  : > "$T/pgrep.out"; : > "$T/ps.tbl"
  eq "$(run_guard "$sh")" 0 "[$tag] pgrep 0개 rc=0"
  eq "$(cat "$T/err")" "" "[$tag] pgrep 0개 stderr 비어 있음"
  eq "$(cat "$T/log")" "" "[$tag] pgrep 0개 로그 없음"

  # ⓑ 1개·임계 미만 → rc 0 · 재기동 판정 없음
  echo 201 > "$T/pgrep.out"
  echo "201 102400 $SRV --port 9493 --project /x" > "$T/ps.tbl"
  eq "$(run_guard "$sh")" 0 "[$tag] pgrep 1개(100MB) rc=0"
  hasnt "$(cat "$T/log")" "restart" "[$tag] 임계 미만이면 재기동 판정 0"

  # ⓒ 2개 중 하나만 임계 초과 → 그 pid 만 dry 재기동 판정
  printf '201\n202\n' > "$T/pgrep.out"
  { echo "201 102400 $SRV --port 9493 --project /x"
    echo "202 4096000 $SRV --port 9494 --project /y"; } > "$T/ps.tbl"
  eq "$(run_guard "$sh")" 0 "[$tag] pgrep 2개 rc=0"
  has "$(cat "$T/log")" "[dry] restart pid=202 port=9494 rss=4000MB" "[$tag] 임계 초과 pid=202 만 판정"
  hasnt "$(cat "$T/log")" "pid=201" "[$tag] 임계 미만 pid=201 은 판정 0"

  # ⓓ uv 래퍼는 크기가 커도 건너뛴다
  echo 203 > "$T/pgrep.out"
  echo "203 4096000 /opt/homebrew/bin/uv tool uvx --from x serena start-mcp-server --transport streamable-http --port 9495" > "$T/ps.tbl"
  eq "$(run_guard "$sh")" 0 "[$tag] uv 래퍼 rc=0"
  hasnt "$(cat "$T/log")" "restart" "[$tag] uv 래퍼는 건너뜀"
done

# ── 설치 스크립트 · plist 템플릿 (실 launchctl·실 홈 0) ──
TPL="$ZC/com.byz.serena-ensure.plist.template"; INST="$ZC/install.sh"
for sh in $SHELLS; do
  for f in serena-guard.sh serena-mcp.sh install.sh; do "$sh" -n "$ZC/$f" && ok "$sh -n $f" || bad "$sh -n $f"; done
done
if command -v plutil >/dev/null 2>&1; then plutil -lint "$TPL" >/dev/null && ok "plutil -lint 템플릿" || bad "plutil -lint 템플릿"; fi
tpl="$(cat "$TPL")"
has "$tpl" "<key>RunAtLoad</key><true/>" "plist RunAtLoad true"
has "$tpl" "<key>KeepAlive</key><false/>" "plist KeepAlive false"
hasnt "$tpl" "~" "plist 에 ~ 0 (절대경로만)"

IH="$T/ihome"; IR="$T/iroot"; mkdir -p "$IH" "$IR"; LCLOG="$T/launchctl.log"; LOADED="$T/loaded"
cat > "$F/launchctl" <<EOF
#!/bin/bash
echo "\$*" >> "$LCLOG"
case "\$1" in
  print) [ -f "$LOADED" ];;
  bootstrap) : > "$LOADED";;
  bootout) rm -f "$LOADED";;
esac
EOF
chmod +x "$F/launchctl"
run_inst() { SERENA_INSTALL_HOME="$IH" SERENA_INSTALL_LAUNCHCTL="$F/launchctl" /bin/bash "$INST" --root "$IR" "$@" 2>&1; }

out="$(run_inst)"
has "$out" "DRY cp -p" "install 기본 = dry-run 출력"
eq "$(ls -A "$IH")" "" "dry-run 은 홈에 아무것도 안 만든다"
eq "$(cat "$LCLOG" 2>/dev/null | grep -c bootstrap)" 0 "dry-run 은 launchctl bootstrap 0"

out="$(run_inst --apply)"
has "$out" "INSTALLED com.byz.serena-ensure" "apply 설치 완료 줄"
cmp -s "$ZC/serena-guard.sh" "$IH/.claude/skills/zombie-clean/scripts/serena-guard.sh" && ok "guard 사본 cmp 0" || bad "guard 사본 어긋남"
cmp -s "$ZC/serena-mcp.sh" "$IH/.claude/scripts/serena-mcp.sh" && ok "serena-mcp 사본 cmp 0" || bad "serena-mcp 사본 어긋남"
P="$IH/Library/LaunchAgents/com.byz.serena-ensure.plist"; pl="$(cat "$P" 2>/dev/null)"
has "$pl" "<string>$IR</string>" "plist 에 메인 루트 절대경로"
has "$pl" "<string>$IH/.claude/scripts/serena-mcp.sh</string>" "plist 에 serena-mcp 절대경로"
hasnt "$pl" "__" "plist 치환 잔여 0"
hasnt "$pl" "~" "렌더 plist ~ 0"
has "$(cat "$LCLOG")" "bootstrap gui/" "launchctl bootstrap 호출"

: > "$LCLOG"; out="$(run_inst --apply)"
has "$out" "ALREADY com.byz.serena-ensure" "재실행은 멱등(ALREADY)"
eq "$(grep -c bootstrap "$LCLOG")" 0 "재실행은 bootstrap 0"

# ── ensure 대기 = 실경과 기준 마감 (DA⑥ HOLD 3 · 전역 하드 룰 12 · 70초 천장) ──
MCP="$ZC/serena-mcp.sh"; MH="$T/mcphome"; mkdir -p "$MH" "$T/proj"; CURLN="$T/curl.n"; : > "$CURLN"
cat > "$F/curl" <<EOF
#!/bin/bash
echo x >> "$CURLN"
echo 000
EOF
printf '#!/bin/bash\nexit 0\n' > "$F/pkill"; printf '#!/bin/bash\nexit 0\n' > "$F/uvx"
printf '#!/bin/bash\n/bin/sleep 0.1\n' > "$F/sleep"
chmod +x "$F/curl" "$F/pkill" "$F/uvx" "$F/sleep"
t0=$SECONDS
out="$(PATH="$F:/usr/bin:/bin" HOME="$MH" SERENA_UVX="$F/uvx" SERENA_ENSURE_DEADLINE_S=2 /bin/bash "$MCP" ensure "$T/proj" 2>&1)"; r=$?
el=$((SECONDS - t0))
[ "$r" != 0 ] && ok "ensure 기동 실패는 rc≠0" || bad "ensure 가 실패 스텁에서 rc=0"
[ "$el" -le 6 ] && ok "ensure 마감이 실경과 기준(2s 설정 → ${el}s)" || bad "ensure 가 마감 2s 를 넘겨 ${el}s 걸림"
curls="$(wc -l < "$CURLN" | tr -d ' ')"
[ "$curls" -lt 60 ] && ok "ensure curl 횟수 상한(${curls}회)" || bad "ensure curl ${curls}회 — 횟수 기반 루프"
grep -q 'SERENA_ENSURE_DEADLINE_S:-60' "$MCP" && ok "ensure 기본 마감 60s(총 70s 천장 안)" || bad "ensure 기본 마감값 없음"

# LIVE-MAP: serena-mcp 는 ~/.claude/scripts · guard 는 skills 폴더 · install.sh 는 skip
MAP="$REPO/harness/kit/LIVE-MAP.tsv"
has "$(grep -F 'zombie-clean/serena-mcp.sh' "$MAP")" '$HOME/.claude/scripts' "LIVE-MAP serena-mcp 행"
has "$(grep -F 'zombie-clean/install.sh' "$MAP")" "skip" "LIVE-MAP install.sh skip 행"
l_mcp="$(grep -n -F 'zombie-clean/serena-mcp.sh' "$MAP" | cut -d: -f1)"; l_all="$(grep -n -F 'zombie-clean/*.sh' "$MAP" | cut -d: -f1)"
[ "$l_mcp" -lt "$l_all" ] && ok "serena-mcp 행이 와일드카드 앞(첫 일치)" || bad "serena-mcp 행 순서"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL=$fail"; exit 1; }
