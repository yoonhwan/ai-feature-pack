#!/usr/bin/env bash
# test_iap_tunnels.sh — R327b: IAP 터널 2개 launchd 설치 스크립트 (실 터널·실 launchd·실 홈 0).
# 가짜 launchctl·lsof·curl·gcloud(PATH 앞/주입) · 임시 홈 — plutil -lint + 치환 결과 대조 + REJECT·ROLLBACK 경로.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; D="$REPO/harness/kit/iap-tunnels"; INST="$D/install.sh"; TPL="$D/com.byz.iap-tunnel.plist.template"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:240}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }

F="$T/fake"; mkdir -p "$F"; LOADED="$T/loaded"; LCLOG="$T/launchctl.log"; HCODE="$T/hcode"; FOREIGN="$T/foreign"
cat > "$F/launchctl" <<EOF
#!/bin/bash
echo "\$*" >> "$LCLOG"
case "\$1" in
  print) [ -f "$LOADED" ];;
  bootstrap) : > "$LOADED";;
  bootout) rm -f "$LOADED";;
esac
EOF
cat > "$F/lsof" <<EOF
#!/bin/bash
[ -f "$FOREIGN" ] && { echo 777; exit 0; }
[ -f "$LOADED" ] && echo 4242
exit 0
EOF
cat > "$F/curl" <<EOF
#!/bin/bash
cat "$HCODE"
EOF
printf '#!/bin/bash\nexit 0\n' > "$F/gcloud"
chmod +x "$F/launchctl" "$F/lsof" "$F/curl" "$F/gcloud"

IH="$T/ihome"; mkdir -p "$IH"
run() {  # 시험 주입 + 가짜 도구 PATH 앞
  PATH="$F:/usr/bin:/bin" IAP_TUNNEL_HOME="$IH" IAP_TUNNEL_LAUNCHCTL="$F/launchctl" IAP_TUNNEL_GCLOUD="$F/gcloud" \
    IAP_TUNNEL_WAIT=2 IAP_TUNNEL_CALL_TMO=1 /bin/bash "$INST" "$@" 2>&1
}
rc() { run "$@" >/dev/null; echo $?; }
reset() { rm -f "$LOADED" "$FOREIGN" "$LCLOG"; rm -rf "$IH"; mkdir -p "$IH"; }

# ── 정적 ──
/bin/bash -n "$INST" && ok "/bin/bash -n install.sh" || bad "/bin/bash -n install.sh"
command -v plutil >/dev/null 2>&1 && { plutil -lint "$TPL" >/dev/null && ok "plutil -lint 템플릿" || bad "plutil -lint 템플릿"; }
bash "$REPO/harness/bin/ft-tmp-trap-lint.sh" "$INST" >/dev/null 2>&1 && ok "ft-tmp-trap-lint" || bad "ft-tmp-trap-lint"
eq "$(rc bogus)" 2 "알 수 없는 이름 rc=2"

# ── 치환 결과 대조 (render · 변경 0) ──
e="$(run embed render)"
has "$e" "<string>com.byz.iap-tunnel-18712</string>" "embed Label"
has "$e" "<string>byz-agents-gce-stt-tts-dev</string>" "embed VM"
has "$e" "<string>8100</string>" "embed 원격 포트 8100"
has "$e" "--local-host-port=127.0.0.1:18712" "embed 로컬 포트 18712"
has "$e" "--zone=asia-northeast3-a" "embed 존"
has "$e" "--account=byz-local-dev@byz-agents-484214.iam.gserviceaccount.com" "embed 계정"
has "$e" "<key>RunAtLoad</key><true/>" "embed RunAtLoad true"
has "$e" "<key>KeepAlive</key><true/>" "embed KeepAlive true"
hasnt "$e" "__" "embed 치환 잔여 0"
hasnt "$e" "~" "embed ~ 0"
l="$(run llm render)"
has "$l" "<string>com.byz.iap-tunnel-18703</string>" "llm Label"
has "$l" "<string>byz-agents-gce-llm-dev</string>" "llm VM"
has "$l" "<string>8000</string>" "llm 원격 포트 8000"
has "$l" "--local-host-port=127.0.0.1:18703" "llm 로컬 포트 18703"
hasnt "$l" "__" "llm 치환 잔여 0"
eq "$(ls -A "$IH")" "" "render 는 홈에 아무것도 안 만든다"

# ── embed dry-run · apply ──
reset
out="$(run embed)"
has "$out" "DRY plist" "embed 기본 = dry-run"
eq "$(ls -A "$IH")" "" "dry-run 은 홈 변경 0"
eq "$(grep -c bootstrap "$LCLOG" 2>/dev/null)" 0 "dry-run 은 bootstrap 0"
out="$(run embed --apply)"
has "$out" "INSTALLED launchd=com.byz.iap-tunnel-18712" "embed apply 설치"
[ -f "$IH/Library/LaunchAgents/com.byz.iap-tunnel-18712.plist" ] && ok "embed plist 기록" || bad "embed plist 없음"
has "$(cat "$LCLOG")" "bootstrap gui/" "embed bootstrap 호출"
: > "$LCLOG"; out="$(run embed --apply)"
has "$out" "ALREADY" "embed 재실행 멱등"
eq "$(grep -c bootstrap "$LCLOG")" 0 "재실행 bootstrap 0"

# ── 남의 리스너 REJECT ──
reset; : > "$FOREIGN"
eq "$(rc embed --apply)" 3 "포트를 남이 쥐면 rc=3"
eq "$(ls -A "$IH")" "" "REJECT 는 변경 0"
eq "$(grep -c bootstrap "$LCLOG" 2>/dev/null)" 0 "REJECT 는 bootstrap 0"

# ── llm: 오빠 확인 전 설치 금지 ──
reset
eq "$(rc llm --apply)" 3 "llm --oppa-confirmed 없으면 rc=3"
has "$(run llm --apply)" "오빠 확인 전 설치 금지" "llm REJECT 사유 표기"
eq "$(ls -A "$IH")" "" "llm REJECT 는 변경 0"
# 확인 뒤: health 200 이면 설치 · 아니면 ROLLBACK
echo 200 > "$HCODE"; reset
has "$(run llm --apply --oppa-confirmed)" "INSTALLED launchd=com.byz.iap-tunnel-18703" "llm health 200 → 설치"
echo 503 > "$HCODE"; reset
eq "$(rc llm --apply --oppa-confirmed)" 5 "llm health 503 → rc=5"
reset; run llm --apply --oppa-confirmed >/dev/null
eq "$(ls "$IH/Library/LaunchAgents" 2>/dev/null)" "" "health 실패면 plist 삭제"
has "$(cat "$LCLOG")" "bootout" "health 실패면 bootout"

# ── 제거·해제도 --apply 게이트 (DA⑥ HOLD 1) ──
echo 200 > "$HCODE"; reset; run llm --apply --oppa-confirmed >/dev/null      # 적재 상태 만들기
PL="$IH/Library/LaunchAgents/com.byz.iap-tunnel-18703.plist"; : > "$LCLOG"
out="$(run llm uninstall)"
has "$out" "DRY" "uninstall 기본 = dry-run"
[ -f "$LOADED" ] && ok "dry-run uninstall 은 적재 유지" || bad "dry-run uninstall 이 launchd 를 내렸다"
[ -f "$PL" ] && ok "dry-run uninstall 은 plist 유지" || bad "dry-run uninstall 이 plist 를 지웠다"
eq "$(grep -c bootout "$LCLOG")" 0 "dry-run uninstall 은 bootout 0"
out="$(run llm uninstall --apply)"
has "$out" "UNINSTALLED" "uninstall --apply 는 제거"
[ -f "$LOADED" ] && bad "--apply uninstall 뒤에도 적재됨" || ok "--apply uninstall 은 launchd 내림"
[ -f "$PL" ] && bad "--apply uninstall 뒤에도 plist 남음" || ok "--apply uninstall 은 plist 삭제"

# ── 이미 적재된 llm 재설치도 health 실패면 rollback (DA⑥ HOLD 2) ──
echo 200 > "$HCODE"; reset; run llm --apply --oppa-confirmed >/dev/null
echo 503 > "$HCODE"; : > "$LCLOG"
out="$(run llm --oppa-confirmed)"; r=$?
eq "$r" 0 "적재된 llm 재설치 dry-run + health 503 은 변경 0 (rc=0)"
[ -f "$LOADED" ] && [ -f "$PL" ] && ok "dry-run 재설치는 적재·plist 유지" || bad "dry-run 재설치가 롤백했다"
out="$(run llm --apply --oppa-confirmed)"; r=$?
eq "$r" 5 "적재된 llm 재설치 --apply + health 503 → rc=5"
[ -f "$PL" ] && bad "재설치 health 실패 뒤 plist 남음" || ok "재설치 health 실패면 plist 삭제"
has "$(cat "$LCLOG")" "bootout" "재설치 health 실패면 bootout"
echo 200 > "$HCODE"; reset; run llm --apply --oppa-confirmed >/dev/null
has "$(run llm --apply --oppa-confirmed)" "ALREADY" "health 200 이면 재설치는 ALREADY"

# ── LIVE-MAP ──
MAP="$REPO/harness/kit/LIVE-MAP.tsv"
has "$(grep -F 'iap-tunnels/*' "$MAP")" "skip" "LIVE-MAP iap-tunnels skip 행"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL=$fail"; exit 1; }
