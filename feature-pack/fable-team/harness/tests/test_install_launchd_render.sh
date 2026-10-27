#!/usr/bin/env bash
# test_install_launchd_render.sh — r538: launchd com.byz.ft-wt-sweep plist 가 손 sed 로 판 붙은 라이브 경로(live/1.1.16/bin)에 고정돼
# 키트를 올려도 sweep 이 옛 판으로 돈 사건. 설치기(install.sh)가 `__FT_BIN__` 키트 템플릿을 판 없는 루트 shim(<루트>/.fable-team/bin)으로
# 렌더해 설치본과 다르면 교체·재적재하고, 설치 검사가 판 붙은 live 경로 plist 를 DRIFT 로 센다.
# 임시 HOME·임시 루트·임시 키트 리포·가짜 launchctl 만 — 실 LaunchAgents·실 launchd·외부 호출 0 · GIT_* env 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CEILING_DIRECTORIES
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$(cd "$HERE/../../harness" && pwd -P)"
ENV_PY="$H/bin/ft_plist_env.py"; CHK="$H/bin/ft-live-install-check.sh"; INST="$H/install.sh"
SWEEP=com.byz.ft-wt-sweep; STALL=com.byz.ft-stall-scan; USERP=com.byz.ft-leak-reap
fail=0; rc=0; out=""; START=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# ── 픽스처 ─────────────────────────────────────────────────────────────────────
export HOME="$T/home"; LA="$HOME/Library/LaunchAgents"; mkdir -p "$LA" "$T/proj/.fable-team/bin"
P="$(cd "$T/proj" && pwd -P)"; RB="$P/.fable-team/bin"
git -C "$P" init -q -b main && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m p0   # 루트 = git 공용 루트
VER="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$H/../manifest.json")"
# 손 렌더(사건 당시 방식 = r444 master-steps.md:11 «sed -e "s|__FT_BIN__|<LIVE_BIN>|g"»)
hand() { sed -e "s|__FT_BIN__|$2|g" -e "s|__BYZ_ROOT__|$P|g" "$H/kit/launchd/$1.plist.template"; }
hand "$SWEEP" "$HOME/.claude/fable-team/live/1.1.16/bin" > "$T/pinned.plist"                                           # ⓑ 판 고정
plutil -insert EnvironmentVariables.FT_MACHINE_ONLY -string keep "$T/pinned.plist"                                      #   + 템플릿에 없는 머신별 env(보존돼야 함)
plutil -replace EnvironmentVariables.FT_WT_SWEEP_MAX -string 7 "$T/pinned.plist"; cp -p "$T/pinned.plist" "$LA/$SWEEP.plist"   #   + 손으로 바꾼 값(보존)
hand "$STALL" "$RB" > "$LA/$STALL.plist"; cp -p "$LA/$STALL.plist" "$T/stall.plist"                                      # ⓒ 이미 렌더본
printf '<?xml version="1.0"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string></dict></plist>\n' "$USERP" > "$LA/$USERP.plist"
cp -p "$LA/$USERP.plist" "$T/user.plist"                                                                                  # ⓓ 템플릿 밖
cat > "$T/fake-launchctl" <<'EOF'
#!/bin/bash
echo "$*" >> "$LC_LOG"
if [ "$1" = bootstrap ]; then
  c=$(( $(cat "$BOOT_CNT" 2>/dev/null || echo 0) + 1 )); echo "$c" > "$BOOT_CNT"
  [ "$c" -gt "${FT_FAKE_BOOTSTRAP_FAIL:-0}" ] || { echo "Bootstrap failed: 5: Input/output error" >&2; exit 5; }
fi
[ "$1" = list ] && exit 113
exit 0
EOF
chmod +x "$T/fake-launchctl"
export FT_LAUNCHCTL="$T/fake-launchctl" LC_LOG="$T/lc.log" BOOT_CNT="$T/boot.cnt"; : > "$LC_LOG"
nlc() { grep -cE '^(bootstrap|bootout|kickstart)' "$LC_LOG"; }
nboot() { grep -c "^bootstrap gui/$(id -u) $LA/$1.plist" "$LC_LOG"; }
nkick() { grep -c '^kickstart' "$LC_LOG"; }
arg1() { plutil -extract ProgramArguments.1 raw "$LA/$1.plist"; }
inst() { out="$(bash "$INST" "$@" --project "$P" --home "$HOME" 2>&1)"; rc=$?; }

python3 -m py_compile "$ENV_PY" "$H/bin/ft_live_install_check.py" && bash -n "$INST"; ck "py_compile 2 · bash -n install.sh" $?
cmp -s "$ENV_PY" "$H/kit/fable-team/bin/ft_plist_env.py" && cmp -s "$H/bin/ft_live_install_check.py" "$H/kit/fable-team/bin/ft_live_install_check.py"
ck "bin/kit 짝 cmp0 (ft_plist_env · ft_live_install_check)" $?

# ⓔ --dry-run = 렌더 비교 줄만 · 쓰기 0 · launchctl 0
s0="$(cksum "$LA"/*)"; inst --dry-run
[ "$rc" = 0 ] && has "PENDING launchd $SWEEP" && has "OK launchd $STALL" && has "LAUNCHD rendered=2 changed=1 restarted=0 (dry-run" \
  && [ "$(cksum "$LA"/*)" = "$s0" ] && [ "$(nlc)" = 0 ] && [ ! -e "$LA/$SWEEP.plist.bak-r538" ]
ck "ⓔ --dry-run → PENDING/OK launchd 줄 · LAUNCHD 요약 · 쓰기 0 · launchctl 0" $?

# ⓐ 템플릿 → 렌더본: __FT_BIN__ = <루트>/.fable-team/bin · __BYZ_ROOT__ = 루트 (실패 시험 먼저 — 고치기 전 설치기는 렌더 0)
out="$(python3 "$ENV_PY" bin-list "$H/kit" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(grep -c . <<< "$out")" = 10 ] && has "$SWEEP	" && has "com.byz.ft-board-publish	" && ! has "com.hermes."   # r544: 7 → 9(__BYZ_ROOT__/.fable-team/bin/ 템플릿도 렌더 목록) · r868: 9 → 10(postboot-measure)
ck "ⓐ bin-list = 루트 bin 템플릿 10개(__FT_BIN__ 8(launchd 7 + board-publish) + r544 루트 bin 꼴 2(secret-scan·weekly-review)) · 미러(com.hermes) 0" $?
out="$(python3 "$ENV_PY" render-bin "$H/kit/launchd/$SWEEP.plist.template" "$P" 2>&1)"; rc=$?; printf '%s\n' "$out" > "$T/r.plist"
[ "$rc" = 0 ] && plutil -lint "$T/r.plist" >/dev/null && [ "$(plutil -extract ProgramArguments.1 raw "$T/r.plist")" = "$RB/ft-wt-sweep.sh" ] \
  && [ "$(plutil -extract WorkingDirectory raw "$T/r.plist")" = "$P" ] && [ "$(plutil -extract EnvironmentVariables.FT_ROOT raw "$T/r.plist")" = "$P" ] \
  && ! has "__" && ! has "/fable-team/live/"
ck "ⓐ render-bin → 실행 경로 <루트>/.fable-team/bin/ft-wt-sweep.sh · WorkingDirectory·FT_ROOT=<루트> · 자리표시·판 경로 0 · plutil rc0" $?

# ⓑ 판 붙은 설치본 → 교체 + .bak-r538 + bootout·bootstrap (kickstart 0 — 주기 job 을 지금 돌리지 않는다)
: > "$LC_LOG"; inst --apply
[ "$rc" = 0 ] && has "PENDING launchd $SWEEP" && has "LAUNCHD applied $SWEEP" && has "LAUNCHD rendered=2 changed=1 restarted=1" \
  && [ "$(arg1 "$SWEEP")" = "$RB/ft-wt-sweep.sh" ] && cmp -s "$LA/$SWEEP.plist.bak-r538" "$T/pinned.plist" \
  && grep -q "^bootout gui/$(id -u)/$SWEEP" "$LC_LOG" && [ "$(nboot "$SWEEP")" = 1 ] && [ "$(nkick)" = 0 ] && has "INSTALLED $VER · PLIST ok"
ck "ⓑ --apply → wt-sweep 실행 경로 = 루트 shim · .bak-r538 = 판 고정 원본 · bootout·bootstrap 각 1 · kickstart 0 · rc0" $?
[ -f "$RB/ft-wt-sweep.sh" ] && head -3 "$RB/ft-wt-sweep.sh" | grep -q '# ft-root-bin-shim:' && plutil -lint "$LA/$SWEEP.plist" >/dev/null
ck "ⓑ 렌더된 실행 경로 = 실재 루트 shim(연결 파일 표식) · plutil rc0" $?
env1() { plutil -extract "EnvironmentVariables.$2" raw "$LA/$1.plist"; }
[ "$(env1 "$SWEEP" FT_MACHINE_ONLY)" = keep ] && [ "$(env1 "$SWEEP" FT_WT_SWEEP_MAX)" = 7 ] && [ "$(env1 "$SWEEP" FT_ROOT)" = "$P" ] \
  && [ "$(plutil -extract StartCalendarInterval.Minute raw "$LA/$SWEEP.plist")" = 15 ] && [ "$(plutil -extract ProgramArguments.2 raw "$LA/$SWEEP.plist")" = --launchd ]
ck "ⓑ 바뀌는 것 = ProgramArguments 하나 · 머신별 env(FT_MACHINE_ONLY·손 값 FT_WT_SWEEP_MAX=7)·주기 보존" $?

# ⓒ 설치본 = 렌더본 → 손 0 · launchctl 0
cmp -s "$LA/$STALL.plist" "$T/stall.plist" && [ "$(nboot "$STALL")" = 0 ] && [ ! -e "$LA/$STALL.plist.bak-r538" ]; ck "ⓒ 같은 설치본(stall-scan) → 쓰기 0 · bootstrap 0 · 백업 0" $?
: > "$LC_LOG"; s0="$(cksum "$LA"/*.plist)"; inst --apply
[ "$rc" = 0 ] && has "OK launchd $SWEEP" && has "LAUNCHD rendered=2 changed=0 restarted=0" && [ "$(nlc)" = 0 ] && [ "$(cksum "$LA"/*.plist)" = "$s0" ]
ck "ⓒ 재apply(멱등) → OK launchd · changed=0 · launchctl 0 · 쓰기 0" $?

# ⓓ 템플릿에 없는 사용자 plist · 설치 안 된 템플릿 라벨 → 손 0 (새로 깔지 않는다)
cmp -s "$LA/$USERP.plist" "$T/user.plist" && ! has "$USERP" && has "SKIP launchd com.byz.ft-head-lag (설치 안 됨" \
  && [ ! -e "$LA/com.byz.ft-head-lag.plist" ] && [ ! -e "$LA/com.byz.ft-board-publish.plist" ]
ck "ⓓ 템플릿 밖 plist cmp 불변 · 미설치 라벨 SKIP(새 plist 0)" $?

# ⓑ' 재적재 실패 → 직전 plist 원복 + 다시 올림 · PLIST ERROR rc1 (조용한 통과 0)
cp -p "$T/pinned.plist" "$LA/$SWEEP.plist"; : > "$BOOT_CNT"; export FT_FAKE_BOOTSTRAP_FAIL=3; inst --apply; export FT_FAKE_BOOTSTRAP_FAIL=0
[ "$rc" = 1 ] && has "PLIST RESTORED $SWEEP" && cmp -s "$LA/$SWEEP.plist" "$T/pinned.plist" && has "INSTALLED $VER · PLIST ERROR" && ! has "LAUNCHD applied"
ck "ⓑ' bootstrap 3회 실패 → 원복(cmp0) · RESTORED · rc1" $?
cmp -s "$LA/$SWEEP.plist.bak-r538" "$T/pinned.plist"; ck "ⓑ' .bak-r538(첫 원본) 보존" $?
inst --apply; [ "$rc" = 0 ] && [ "$(arg1 "$SWEEP")" = "$RB/ft-wt-sweep.sh" ]; ck "ⓑ' 다음 apply → 렌더본 복구 rc0" $?

# 렌더 실패 = ERROR (조용한 통과 0)
sed 's|<string>--launchd</string>|<string>__OTHER__</string>|' "$H/kit/launchd/$SWEEP.plist.template" > "$T/bad.template"
out="$(python3 "$ENV_PY" render-bin "$T/bad.template" "$P" 2>&1)"; rc=$?; [ "$rc" = 3 ] && has "ERROR" && has "__OTHER__"; ck "렌더: 자리표시 잔재 → ERROR rc3" $?
sed 's|ft-wt-sweep.sh|ft-no-such.sh|' "$H/kit/launchd/$SWEEP.plist.template" > "$T/miss.template"
out="$(python3 "$ENV_PY" render-bin "$T/miss.template" "$P" --need-exist 2>&1)"; rc=$?; [ "$rc" = 3 ] && has "ft-no-such.sh"; ck "렌더 --need-exist: 실행 경로 없음 → ERROR rc3" $?
out="$(python3 "$ENV_PY" render-bin "$H/kit/launchd/$SWEEP.plist.template" "$T/no-root" 2>&1)"; rc=$?; [ "$rc" = 3 ] && has "ERROR"; ck "렌더: git 공용 루트 아님 → ERROR rc3" $?
git -C "$P" worktree add -q --detach "$P/.worktrees/w" && mkdir -p "$P/.worktrees/w/.fable-team/bin"; W="$(cd "$P/.worktrees/w" && pwd -P)"
cp -p "$T/pinned.plist" "$LA/$SWEEP.plist"; : > "$LC_LOG"
out="$(bash "$INST" --apply --project "$W" --home "$HOME" 2>&1)"; rc=$?
[ "$rc" = 0 ] && has "SKIP launchd (--project 가 git 공용 루트 아님" && cmp -s "$LA/$SWEEP.plist" "$T/pinned.plist" && [ "$(nlc)" = 0 ]
ck "워크트리 --project → SKIP launchd · plist 불변 · launchctl 0" $?

# ⓕ 설치 검사: 판 붙은 live 경로 plist(판 ≠ 지금 LIVE_BIN 판) → DRIFT launchd <라벨> pinned=<판>
R="$T/repo"; mkdir -p "$R/kit/launchd"; G() { git -C "$R" "$@"; }
G init -q -b main . && G config user.name t && G config user.email t@t
cp "$H/kit/LIVE-MAP.tsv" "$R/kit/LIVE-MAP.tsv"; G add -A && G commit -qm c0; C0="$(G rev-parse HEAD)"
echo memo > "$R/kit/launchd/README.md"; G add -A && G commit -qm c1; C1="$(G rev-parse HEAD)"
chk() { out="$(bash "$CHK" --range "$C0..$C1" --ref "$C1" --repo "$R" --kit kit --project "$P" 2>&1)"; rc=$?; }
chk; [ "$rc" = 1 ] && has "DRIFT launchd $SWEEP pinned=1.1.16" && has "HINT launchd bash " && has "install.sh --apply --project $P" && ! has "DRIFT launchd $STALL"
ck "ⓕ install-check: live/1.1.16 고정 plist → DRIFT launchd pinned=1.1.16 rc1 + HINT · 루트 shim plist 는 DRIFT 0" $?
hand "$SWEEP" "$HOME/.claude/fable-team/live/$VER/bin" > "$LA/$SWEEP.plist"; chk; [ "$rc" = 0 ] && ! has "DRIFT"
ck "ⓕ 판 = 지금 LIVE_BIN 판($VER) → DRIFT 0 · OK rc0" $?
inst --apply; chk; [ "$rc" = 0 ] && ! has "DRIFT" && [ "$(arg1 "$SWEEP")" = "$RB/ft-wt-sweep.sh" ]; ck "ⓕ apply 뒤 → 루트 shim · DRIFT 0 · OK rc0" $?

# 7초 룰 · 10분 룰
! grep -nE '(timeout|TIMEOUT)[^0-9]{0,12}(600|300)\b' "$ENV_PY" "$INST" "$H/bin/ft_live_install_check.py"; ck "600/300 초 상한 0" $?
[ $((SECONDS - START)) -lt 600 ]; ck "시험 시간 < 10분 ($((SECONDS - START))s)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
