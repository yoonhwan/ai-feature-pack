#!/usr/bin/env bash
# test_plist_workdir_exist_r544.sh — r544: 고장 데몬 3개(r532 점검표).
# ① com.byz.ft-secret-scan(종료 3)·com.byz.ft-weekly-review(종료 1) = 설치본에 WorkingDirectory 가 없어 launchd cwd=/ → «리포 공용 루트 못 풂».
#    키트 템플릿엔 `<key>WorkingDirectory</key><string>__BYZ_ROOT__</string>` 가 있는데 r538 렌더가 «실행 경로만» 옮기고
#    bin-list 가 __FT_BIN__ 템플릿만 골라 이 두 라벨은 렌더 목록에도 안 들어갔다.
# ② com.byz.gce-guard-check(종료 78) = 지운 워크트리(.worktrees/ops-guard) 스크립트를 매시간 실행 — 설치 검사가 «실행 경로 파일 없음» 을 안 봤다.
# 이 시험은 ⓐ~ⓖ 만 본다 — 임시 HOME·임시 루트·임시 키트 리포·가짜 launchctl · 실 LaunchAgents·실 launchd·외부 호출 0 · GIT_* env 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CEILING_DIRECTORIES
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$(cd "$HERE/../../harness" && pwd -P)"
ENV_PY="$H/bin/ft_plist_env.py"; CHK="$H/bin/ft-live-install-check.sh"; INST="$H/install.sh"
SEC=com.byz.ft-secret-scan; WEEK=com.byz.ft-weekly-review; SWEEP=com.byz.ft-wt-sweep; GUARD=com.byz.gce-guard-check
fail=0; rc=0; out=""; START=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:900}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# ── 픽스처 ─────────────────────────────────────────────────────────────────────
export HOME="$T/home"; LA="$HOME/Library/LaunchAgents"; mkdir -p "$LA" "$T/proj/.fable-team/bin"
P="$(cd "$T/proj" && pwd -P)"; RB="$P/.fable-team/bin"
git -C "$P" init -q -b main && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m p0   # 루트 = git 공용 루트
for t in ft-secret-scan.sh ft-weekly-review.sh ft-wt-sweep.sh; do printf '#!/bin/bash\n# ft-root-bin-shim: r544\n' > "$RB/$t"; done     # --need-exist 용 루트 shim(표식 있음 = 옛 사본 아님)
VER="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$H/../manifest.json")"
# 사건 당시 설치본 = r538 렌더본(ProgramArguments 만 루트 shim · WorkingDirectory 키 없음)
r544() { printf '%s\n' "$1" > "$T/r.plist"; }
old_rendered() { python3 "$ENV_PY" render-bin "$H/kit/fable-team/$1.plist.template" "$P" > "$T/o.plist" && plutil -remove WorkingDirectory "$T/o.plist" && cat "$T/o.plist"; }
old_rendered "$SEC" > "$LA/$SEC.plist"; cp -p "$LA/$SEC.plist" "$T/sec.old.plist"                              # ⓐ 사건본
plutil -insert EnvironmentVariables.FT_MACHINE_ONLY -string keep "$LA/$SEC.plist"                                # ⓑ 머신별 env
plutil -replace StartCalendarInterval.Minute -integer 41 "$LA/$SEC.plist"                                        # ⓑ 손으로 바꾼 주기
python3 "$ENV_PY" render-bin "$H/kit/fable-team/$WEEK.plist.template" "$P" > "$LA/$WEEK.plist" && plutil -remove WorkingDirectory "$LA/$WEEK.plist"   # ⓓ 꼴
# ⓕ 키트 템플릿 밖 plist(gce-guard 꼴) — 지운 워크트리 스크립트를 가리킨다
cat > "$LA/$GUARD.plist" <<EOF
<?xml version="1.0"?>
<plist version="1.0"><dict><key>Label</key><string>$GUARD</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$P/.worktrees/ops-guard/scripts/ops/gce-guard-check.sh</string></array>
<key>StartInterval</key><integer>3600</integer></dict></plist>
EOF
cp -p "$LA/$GUARD.plist" "$T/guard.plist"
cat > "$T/fake-launchctl" <<'EOF'
#!/bin/bash
[ "$1" = list ] && exit 113
exit 0
EOF
chmod +x "$T/fake-launchctl"; export FT_LAUNCHCTL="$T/fake-launchctl"

python3 -m py_compile "$ENV_PY" "$H/bin/ft_live_install_check.py" && bash -n "$INST"; ck "py_compile 2 · bash -n install.sh" $?
cmp -s "$ENV_PY" "$H/kit/fable-team/bin/ft_plist_env.py" && cmp -s "$H/bin/ft_live_install_check.py" "$H/kit/fable-team/bin/ft_live_install_check.py"
ck "bin/kit 짝 cmp0 (ft_plist_env · ft_live_install_check)" $?

# ⓐ 사건본(WorkingDirectory 없음) + 템플릿엔 __BYZ_ROOT__ → 렌더본에 «없음» 이 아니라 루트가 들어와야 한다 (고치기 전 FAIL == 이 시험)
out="$(python3 "$ENV_PY" render-bin "$H/kit/fable-team/$SEC.plist.template" "$P" "$LA/$SEC.plist" 2>&1)"; rc=$?; r544 "$out"
[ "$rc" = 0 ] && [ -f "$T/r.plist" ] && plutil -lint "$T/r.plist" >/dev/null \
  && [ "$(plutil -extract WorkingDirectory raw "$T/r.plist" 2>/dev/null)" = "$P" ] \
  && [ "$(plutil -extract ProgramArguments.1 raw "$T/r.plist")" = "$RB/ft-secret-scan.sh" ]
ck "ⓐ 사건본(WorkingDirectory 0) → 렌더본 WorkingDirectory=<루트> · 실행 경로 루트 shim · plutil rc0" $?

# ⓑ 옮기는 것 = ProgramArguments + WorkingDirectory · 머신별 env·주기·나머지 키는 설치본 그대로
[ "$(plutil -extract EnvironmentVariables.FT_MACHINE_ONLY raw "$T/r.plist")" = keep ] \
  && [ "$(plutil -extract StartCalendarInterval.Minute raw "$T/r.plist")" = 41 ] \
  && [ "$(plutil -extract EnvironmentVariables.PATH raw "$T/r.plist")" = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" ] \
  && [ "$(plutil -extract StandardOutPath raw "$T/r.plist")" = /tmp/ft-secret-scan.log ]
ck "ⓑ 머신별 env(FT_MACHINE_ONLY)·손 값(주기 41)·PATH·로그 경로 보존" $?
out="$(python3 "$ENV_PY" render-bin "$H/kit/fable-team/$SEC.plist.template" "$P" "$LA/$SEC.plist" 2>&1)"; rc=$?
s0="$(plutil -p "$LA/$SEC.plist")"; printf '%s\n' "$out" > "$T/r2.plist"
[ "$s0" = "$(plutil -p "$LA/$SEC.plist")" ] && [ "$rc" = 0 ] && cmp -s "$T/r.plist" "$T/r2.plist" \
  && [ "$(plutil -extract WorkingDirectory raw "$T/r2.plist")" = "$P" ]
ck "ⓑ 렌더 두 번 = 같은 결론(멱등 · WorkingDirectory=<루트>)" $?

# ⓒ 템플릿에 WorkingDirectory 가 없으면 렌더본에도 0 — 설치본 값은 지어내지 않고 그대로 둔다
grep -v '<key>WorkingDirectory</key>' "$H/kit/launchd/$SWEEP.plist.template" > "$T/nowd.template"
python3 "$ENV_PY" render-bin "$H/kit/launchd/$SWEEP.plist.template" "$P" > "$LA/$SWEEP.plist" && plutil -replace WorkingDirectory -string /tmp/hand-set "$LA/$SWEEP.plist"
cp -p "$LA/$SWEEP.plist" "$T/sweep.hand.plist"
out="$(python3 "$ENV_PY" render-bin "$T/nowd.template" "$P" "$LA/$SWEEP.plist" 2>&1)"; rc=$?; r544 "$out"
[ "$rc" = 0 ] && plutil -lint "$T/r.plist" >/dev/null && [ "$(plutil -extract WorkingDirectory raw "$T/r.plist")" = /tmp/hand-set ] \
  && [ "$(plutil -extract ProgramArguments.1 raw "$T/r.plist")" = "$RB/ft-wt-sweep.sh" ] \
  && cmp -s "$LA/$SWEEP.plist" "$T/sweep.hand.plist"
ck "ⓒ WorkingDirectory 없는 템플릿 → 그 키 안 만짐(손 값 /tmp/hand-set 유지 · 쓰기 0)" $?

# ⓓ bin-list = 루트 bin 을 부르는 템플릿 전부(__FT_BIN__ 7 + __BYZ_ROOT__/.fable-team/bin/ 2) · __HOME__·__REPO__ 를 쓰는 magazine 류 0
out="$(python3 "$ENV_PY" bin-list "$H/kit" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(grep -c . <<< "$out")" = 10 ] && has "$SEC	" && has "$WEEK	" && has "$SWEEP	" && ! has "com.byz.ft-magazine" && ! has "com.hermes."
ck "ⓓ bin-list = 10(__FT_BIN__ 8(r868 postboot-measure 포함) + 루트 bin 꼴 2 · magazine·미러 0)" $?
out="$(python3 "$ENV_PY" render-bin "$H/kit/fable-team/$WEEK.plist.template" "$P" --need-exist 2>&1)"; rc=$?; r544 "$out"
[ "$rc" = 0 ] && plutil -lint "$T/r.plist" >/dev/null && [ "$(plutil -extract ProgramArguments.1 raw "$T/r.plist")" = "$RB/ft-weekly-review.sh" ] \
  && [ "$(plutil -extract WorkingDirectory raw "$T/r.plist")" = "$P" ] && ! has "__" && ! has "/fable-team/live/"
ck "ⓓ weekly-review 렌더(--need-exist) → 루트 shim 실행 경로 · WorkingDirectory=<루트> · 자리표시·판 경로 0" $?

# ⓔ 설치 검사 = 실행 경로 스크립트가 없는 plist → DRIFT launchd <라벨> missing=<경로> (있으면 줄 0)
R="$T/repo"; mkdir -p "$R/kit/launchd"; G() { git -C "$R" "$@"; }
G init -q -b main . && G config user.name t && G config user.email t@t
cp "$H/kit/LIVE-MAP.tsv" "$R/kit/LIVE-MAP.tsv"; G add -A && G commit -qm c0; C0="$(G rev-parse HEAD)"
echo memo > "$R/kit/launchd/README.md"; G add -A && G commit -qm c1; C1="$(G rev-parse HEAD)"
chk() { out="$(bash "$CHK" --range "$C0..$C1" --ref "$C1" --repo "$R" --kit kit --project "$P" 2>&1)"; rc=$?; }
chk; [ "$rc" = 1 ] && has "DRIFT launchd $GUARD missing=$P/.worktrees/ops-guard/scripts/ops/gce-guard-check.sh" && has "HINT launchd-missing " \
  && has "키트 밖 plist 는 설치기 손 0" && ! has "DRIFT launchd $SEC missing=" && ! has "UNMAPPED"
ck "ⓔ install-check: 지운 경로를 가리키는 plist → DRIFT missing · HINT(사람 단계) · rc1" $?
mkdir -p "$P/.worktrees/ops-guard/scripts/ops" && printf '#!/bin/bash\n' > "$P/.worktrees/ops-guard/scripts/ops/gce-guard-check.sh"
chk; [ "$rc" = 0 ] && has "OK n=0 skip=1" && ! has "DRIFT"
ck "ⓔ 같은 plist · 스크립트 실재 → DRIFT 0 · rc0" $?

# ⓕ 키트 밖 plist 는 «실재» 만 본다 — 렌더·고치기 0(설치기 launchd_sync 목록에도 0 · 파일 불변)
out="$(python3 "$ENV_PY" bin-list "$H/kit" 2>&1)"; rc=$?; ! has "$GUARD"
ck "ⓕ 설치기 렌더 목록에 키트 밖 plist 0(고치기 0)" $?
out="$(bash "$INST" --apply --project "$P" --home "$HOME" 2>&1)"; rc=$?
cmp -s "$LA/$GUARD.plist" "$T/guard.plist" && [ ! -e "$LA/$GUARD.plist.bak-r538" ]
ck "ⓕ install.sh --apply 뒤에도 키트 밖 plist 불변(cmp0 · 백업 0)" $?

# ⓖ 기존 시험 base 대조 — r538(렌더)·r426(plist env)·설치 검사·shim · rc0
for t in test_install_launchd_render test_live_install_check_plist_env test_live_install_check_shim test_installed_root; do
  out="$(bash "$H/tests/$t.sh" 2>&1)"; rc=$?
  ck "ⓖ 기존 $t → rc0 ($(grep -c '^PASS' <<< "$out") PASS)" "$rc"
done

# 7초 룰 · 10분 룰
! grep -nE '(timeout|TIMEOUT)[^0-9]{0,12}(600|300)\b' "$ENV_PY" "$INST" "$H/bin/ft_live_install_check.py"; ck "600/300 초 상한 0" $?
[ $((SECONDS - START)) -lt 600 ]; ck "시험 시간 < 10분 ($((SECONDS - START))s)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
