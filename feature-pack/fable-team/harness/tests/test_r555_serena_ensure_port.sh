#!/usr/bin/env bash
# test_r555_serena_ensure_port.sh — R555: 부팅 ensure plist 의 프로젝트 = «좌석이 실제로 쓰는 포트» 의 프로젝트 (+ 자식 정리 0 · BOOT 인자 이름)
# 가짜 HOME(.claude.json · .serena/bridges) · 가짜 launchctl · 임시 루트 — 실 launchd·uvx·9493 호출 0 · 실 홈 쓰기 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
ZC="$REPO/harness/kit/zombie-clean"
INSTALL="$ZC/install.sh"
TPL="$ZC/com.byz.serena-ensure.plist.template"
BOOT="$REPO/../tmuxc/claude-code/skills/tmuxc/COMM-GUIDE-BOOT.md"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:240}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }

# serena-mcp.sh:33 port_for 와 같은 식 (시험 쪽 독립 계산)
port_for() { echo $((9200 + $(printf '%s' "$1" | cksum | awk '{print $1}') % 700)); }

H="$T/home"; ROOT="$T/root"; PROJ="$T/proj/.worktrees/v6-realtime-live"; OTHER="$T/other"
mkdir -p "$H/Library/LaunchAgents" "$H/.serena/bridges" "$ROOT" "$PROJ" "$OTHER" "$T/fake"
P="$(port_for "$PROJ")"; P_OTHER="$(port_for "$OTHER")"
[ "$P" != "$(port_for "$ROOT")" ] || { echo "FAIL 준비 — 픽스처 포트 충돌"; exit 1; }
[ "$P" != "$P_OTHER" ] || { echo "FAIL 준비 — 픽스처 포트 충돌(other)"; exit 1; }

cat > "$T/fake/launchctl" <<EOF
#!/bin/bash
echo "\$*" >> "$T/launchctl.log"
[ "\${1:-}" = print ] && exit 1
exit 0
EOF
chmod +x "$T/fake/launchctl"

write_claude_json() {  # $1 = serena url (빈값 = serena 키 없음)
  if [ -z "$1" ]; then
    printf '{"projects": {"%s": {"mcpServers": {}}}}\n' "$ROOT" > "$H/.claude.json"
  else
    printf '{"projects": {"%s": {"mcpServers": {"serena": {"type": "http", "url": "%s"}}}}}\n' \
      "$ROOT" "$1" > "$H/.claude.json"
  fi
}
write_bridge() {  # $1 = 포트 · $2 = project
  printf '{"project": "%s", "port": %s, "started": "2026-10-20 18:31:39"}\n' "$2" "$1" \
    > "$H/.serena/bridges/$1.json"
}
PLIST="$H/Library/LaunchAgents/com.byz.serena-ensure.plist"
run_install() {  # 남는 인자 = install.sh 추가 인자 → rc 를 돌려준다 (stderr = $T/err)
  : > "$T/err"
  SERENA_INSTALL_HOME="$H" SERENA_INSTALL_LAUNCHCTL="$T/fake/launchctl" \
    bash "$INSTALL" --apply --root "$ROOT" "$@" >"$T/out" 2>"$T/err"
  echo $?
}
ensure_arg() {  # 렌더된 plist 의 ProgramArguments 중 ensure 뒤 인자
  python3 - "$PLIST" <<'PY' 2>/dev/null
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
a = d.get('ProgramArguments', [])
print(a[a.index('ensure') + 1] if 'ensure' in a else '')
PY
}

# ── ⓐ 좌석 포트(bridges 기록)로 렌더 — 고치기 전 판은 ROOT 를 쓴다 (FAIL 지점)
write_claude_json "http://127.0.0.1:$P/mcp"; write_bridge "$P" "$PROJ"
eq "$(run_install)" 0 "ⓐ rc=0 (좌석 포트 기록 있음)"
eq "$(ensure_arg)" "$PROJ" "ⓐ ensure 인자 = 좌석 포트의 프로젝트($PROJ)"
hasnt "$(ensure_arg)" "$ROOT" "ⓐ ensure 인자에 ROOT 가 아님"
has "$(cat "$T/out")" "ensure project=$PROJ port=$P" "ⓐ dry/apply 줄에 «ensure project=<경로> port=<n>»"

# ── ⓑ url 포트의 bridges 기록 없음 → die 2 (루트로 조용히 내려가기 0)
rm -f "$H/.serena/bridges/$P.json"
eq "$(run_install)" 2 "ⓑ 기록 없음 rc=2"
has "$(cat "$T/err")" "좌석 포트 $P 의 프로젝트 기록 없음" "ⓑ die 문구에 «좌석 포트 <n> 의 프로젝트 기록 없음»"
has "$(cat "$T/err")" "serena-mcp.sh ensure <경로>" "ⓑ die 문구에 처방(ensure <경로>)"

# ── ⓒ --ensure-project 명시 → 그 경로 · 포트 불일치면 die 2
write_bridge "$P" "$PROJ"
eq "$(run_install --ensure-project "$PROJ")" 0 "ⓒ 맞는 경로 명시 rc=0"
eq "$(ensure_arg)" "$PROJ" "ⓒ 명시 경로가 그대로 렌더"
eq "$(run_install --ensure-project "$OTHER")" 2 "ⓒ 포트 불일치(other=$P_OTHER) rc=2"
has "$(cat "$T/err")" "port_for=$P_OTHER" "ⓒ die 문구에 계산 포트"

# ── ⓓ .claude.json 에 serena url 없음 → ROOT 렌더 + stderr WARN 1줄
write_claude_json ""
eq "$(run_install)" 0 "ⓓ url 없음 rc=0"
eq "$(ensure_arg)" "$ROOT" "ⓓ 맞출 대상 없음 = ROOT 그대로"
eq "$(grep -c 'WARN' "$T/err")" 1 "ⓓ stderr WARN 1줄"

# ── ⓔ 렌더 plist plutil 통과 + AbandonProcessGroup true (자식 정리 0)
if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$PLIST" >/dev/null 2>&1 && ok "ⓔ plutil -lint OK" || bad "ⓔ plutil -lint 실패"
else
  echo "SKIP ⓔ plutil 없음"
fi
eq "$(python3 - "$PLIST" <<'PY' 2>/dev/null
import plistlib, sys
print(plistlib.load(open(sys.argv[1], 'rb')).get('AbandonProcessGroup'))
PY
)" "True" "ⓔ AbandonProcessGroup true"
hasnt "$(cat "$TPL")" "__ROOT__" "ⓔ 템플릿에 옛 자리표 __ROOT__ 없음"

# ── ⓕ BOOT 1번 줄 = session (1번 Serena 조항 문구만 — 다른 조항 변경과 무관 · r625)
eq "$(grep -c '^1\. \*\*Serena\*\*' "$BOOT")" 1 "ⓕ 1번 조항 1개"
line1="$(grep -m1 '^1\. \*\*Serena\*\*' "$BOOT")"
has "$line1" "session=" "ⓕ 1번 줄 인자 이름 = session"
has "$line1" "session 없이" "ⓕ 1번 줄에 «session 없이» 문구"
hasnt "$line1" "session_id=…" "ⓕ 1번 줄에 옛 인자 «session_id=…» 없음"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
