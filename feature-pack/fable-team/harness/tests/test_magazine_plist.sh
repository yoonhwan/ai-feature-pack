#!/usr/bin/env bash
# test_magazine_plist.sh — 설계 §9 시험 9: install-magazine.sh 치환 뒤 plutil -lint · Hour 8 Minute 0 · KeepAlive 없음 · RunAtLoad false
# + launchctl 0 (--load 없음) · .bak · ops/magazine 워크트리는 «없을 때만» 생성. HOME·BYZ_ROOT 를 임시로 바꿔 실 ~/.hermes·launchd 는 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
INSTALL="$HERE/../../harness/kit/slack-mirror/install-magazine.sh"
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
[ "$(plutil -extract EnvironmentVariables.MAGAZINE_MALFORMED_CARDS raw "$P")" = "report" ] && ok "형식 미달 카드 opt-in(report)" || bad "MAGAZINE_MALFORMED_CARDS=report 없음"
grep -q '__[A-Z_]*__' "$P" && bad "미치환 토큰 남음" || ok "미치환 토큰 0"
# R184 ⓐ 08:00 예약 명령 = 발행 길(magazine_from_news.sh --publish) · --emit-model 단독 아님 · FT_ROOT 주입
grep -q "$T/home/.hermes/scripts/magazine_from_news.sh" "$P" && grep -q '<string>--publish</string>' "$P" && ok "ⓐ 예약 명령 = magazine_from_news.sh --publish" || bad "ⓐ 예약 명령이 발행 길이 아님"
grep -q -- '--emit-model' "$P" && bad "ⓐ 발행 예약에 --emit-model 이 남음(게시 0 모드)" || ok "ⓐ 발행 예약에 --emit-model 0"
[ "$(plutil -extract EnvironmentVariables.FT_ROOT raw "$P")" = "$T/root" ] && ok "ⓐ FT_ROOT 주입" || bad "ⓐ FT_ROOT"
PM="$T/home/Library/LaunchAgents/com.byz.ft-magazine-model.plist"
plutil -lint "$PM" >/dev/null 2>&1 && grep -q -- '--emit-model' "$PM" && grep -q "$T/root/.fable-team/state/sheet-story.json" "$PM" && ok "ⓐ 시트 모델 예약은 별 Label(--emit-model)" || bad "ⓐ 별 Label 예약"
[ -x "$T/home/.hermes/scripts/magazine_from_news.sh" ] && ok "magazine_from_news.sh 설치(+x)" || bad "magazine_from_news.sh 미설치"
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

# R184 ⓑ disabled 인데 --load → rc 1 + ERROR · enable/bootstrap 호출 0 (몰래 켜지 않는다)
: > "$T/launchctl.calls"
printf '#!/usr/bin/env bash\necho "$@" >> "%s/launchctl.calls"\n[ "$1" = print-disabled ] && printf "disabled services = {\\n\\t\\"com.byz.ft-magazine\\" => disabled\\n}\\n"\nexit 0\n' "$T" > "$T/bin/launchctl"
OUTD="$(run --load)"; rcd=$?
[ $rcd -eq 1 ] && echo "$OUTD" | grep -q 'ERROR 예약이 꺼져 있음(disabled): com.byz.ft-magazine' && ok "ⓑ disabled + --load → rc 1 + ERROR" || bad "ⓑ rc=$rcd: $OUTD"
grep -qE '^(enable|bootstrap|bootout)' "$T/launchctl.calls" && bad "ⓑ disabled 인데 enable/bootstrap/bootout 호출됨" || ok "ⓑ enable·bootstrap 호출 0"

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
