#!/usr/bin/env bash
# test_magazine_plist.sh — 설계 §9 시험 9: install-magazine.sh 치환 뒤 plutil -lint · Hour 8 Minute 0 · KeepAlive 없음 · RunAtLoad false
# + launchctl 0 (--load 없음) · .bak · ops/magazine 워크트리는 «없을 때만» 생성. HOME·BYZ_ROOT 를 임시로 바꿔 실 ~/.hermes·launchd 는 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
INSTALL="$HERE/../../scripts/harness-install/slack-mirror/install-magazine.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$INSTALL" && ok "bash -n install-magazine.sh" || bad "bash -n"

# launchctl 가짜 — 호출되면 기록한다 (--load 없이 불리면 실패)
mkdir -p "$T/bin" "$T/home" "$T/root"
printf '#!/usr/bin/env bash\necho "$@" >> "%s/launchctl.calls"\n' "$T" > "$T/bin/launchctl"; chmod +x "$T/bin/launchctl"

# 임시 리포 + 가짜 origin(main) — 워크트리 생성 시험용
git init -q --bare -b main "$T/origin.git"
git clone -q "$T/origin.git" "$T/root" 2>/dev/null
git -C "$T/root" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$T/root" push -q origin HEAD:main 2>/dev/null; git -C "$T/root" fetch -q

run() { HOME="$T/home" BYZ_ROOT="$T/root" GH_REPO="o/r" MAGAZINE_CHANNEL="C9" PATH="$T/bin:$PATH" bash "$INSTALL" "$@" 2>&1; }
OUT="$(run)"; rc=$?
[ $rc -eq 0 ] && ok "install rc=0" || { bad "install rc=$rc: $OUT"; }
P="$T/home/Library/LaunchAgents/com.byz.ft-magazine.plist"
[ -f "$P" ] && ok "plist 생성" || bad "plist 없음"
plutil -lint "$P" >/dev/null 2>&1 && ok "plutil -lint" || bad "plutil -lint"
[ "$(plutil -extract StartCalendarInterval.Hour raw "$P")" = "8" ] && ok "Hour 8" || bad "Hour"
[ "$(plutil -extract StartCalendarInterval.Minute raw "$P")" = "0" ] && ok "Minute 0" || bad "Minute"
[ "$(plutil -extract RunAtLoad raw "$P")" = "false" ] && ok "RunAtLoad false" || bad "RunAtLoad"
plutil -extract KeepAlive raw "$P" >/dev/null 2>&1 && bad "KeepAlive 가 있다" || ok "KeepAlive 없음"
[ "$(plutil -extract Label raw "$P")" = "com.byz.ft-magazine" ] && ok "Label" || bad "Label"
[ "$(plutil -extract EnvironmentVariables.GH_REPO raw "$P")" = "o/r" ] && [ "$(plutil -extract EnvironmentVariables.MAGAZINE_CHANNEL raw "$P")" = "C9" ] && ok "환경값 치환" || bad "환경값"
grep -q '__[A-Z_]*__' "$P" && bad "미치환 토큰 남음" || ok "미치환 토큰 0"
grep -q "$T/home/.hermes/scripts/byz_morning_magazine.py" "$P" && ok "스크립트 경로" || bad "스크립트 경로"
[ -f "$T/home/.hermes/scripts/magazine_publish.py" ] && ok "모듈 복사" || bad "모듈 복사"
[ -f "$T/launchctl.calls" ] && bad "--load 없이 launchctl 호출됨" || ok "launchctl 호출 0"
[ -e "$T/root/.worktrees/ops-magazine/.git" ] && [ "$(git -C "$T/root/.worktrees/ops-magazine" rev-parse --abbrev-ref HEAD)" = "ops/magazine" ] && ok "ops/magazine 워크트리 생성" || bad "워크트리 생성"

# 멱등: 두 번째 실행은 .bak 을 남기고 워크트리는 그대로 둔다
OUT2="$(run)"; rc=$?
[ $rc -eq 0 ] && echo "$OUT2" | grep -q "worktree 있음" && ok "재실행: 워크트리 그대로" || bad "재실행 rc=$rc: $OUT2"
ls "$T/home/.hermes/scripts"/magazine_publish.py.bak-* >/dev/null 2>&1 && ok ".bak 생성" || bad ".bak 없음"

# --load 일 때만 launchctl
run --load >/dev/null
grep -q "bootstrap" "$T/launchctl.calls" 2>/dev/null && ok "--load 는 bootstrap 호출" || bad "--load 인데 bootstrap 없음"

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
