#!/usr/bin/env bash
# test_live_install_check_plist_env.sh — r426: 쪽지→슬랙 미러 plist 가 FT_ROOT 없이 옛 bin 을 불러 7시간 47분 정지한 사건.
# 설치기(install.sh)가 설치된 미러 plist 를 키트 템플릿 렌더본(FT_ROOT=프로젝트 · inbox=LIVE_BIN)으로 갱신하고, install-check 가 PENDING plist-env 를 센다.
# 임시 HOME·임시 프로젝트·임시 키트 리포·가짜 launchctl 만 — 실 LaunchAgents·실 launchctl 등록 0 · press 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$(cd "$HERE/../../harness" && pwd -P)"
ENV_PY="$H/bin/ft_plist_env.py"; CHK="$H/bin/ft-live-install-check.sh"; INST="$H/install.sh"
TPL_REL="slack-mirror/com.hermes.byz-mbox-slack-mirror.plist.template"; TPL="$H/kit/$TPL_REL"
LABEL="com.hermes.byz-mbox-slack-mirror"
fail=0; rc=0; out=""; START=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# ── 픽스처 ─────────────────────────────────────────────────────────────────────
export HOME="$T/home"; LA="$HOME/Library/LaunchAgents"; DST="$LA/$LABEL.plist"
mkdir -p "$LA" "$HOME/.hermes/scripts" "$T/proj/.fable-team/bin" "$T/livebin"
echo 'print(1)' > "$HOME/.hermes/scripts/byz_mbox_slack_mirror.py"
P="$(cd "$T/proj" && pwd -P)"; LB="$T/livebin"
printf '#!/bin/bash\n' > "$LB/ft-inbox.sh"; printf '%s\n' "$LB" > "$P/.fable-team/LIVE_BIN"
# 옛 설치본(사건 당시 꼴) = FT_ROOT 없음 · inbox 가 워크트리 옛 bin
legacy() {
  sed -e '/<key>FT_ROOT<\/key>/d' -e "s#__PY__#/opt/homebrew/bin/python3#; s#__HOME__#$HOME#g; s#__PROJECT__#byz#; s#__MAILBOX__#$P/.fable-team/comm/mailbox.log.jsonl#" \
      -e "s#__SEAT__#^byz-planner-(arch|master-claude)\#[0-9]+\$#; s#__CHANNEL__#C0TEST#; s#__MENTION__#U0TEST#; s#__REPO__#o/r#; s#__INBOX_BIN__#$P/.worktrees/old/.fable-team/bin/ft-inbox.sh#" "$TPL" > "$T/legacy.plist"
}
legacy; cp -p "$T/legacy.plist" "$DST"
cat > "$T/fake-launchctl" <<'EOF'
#!/bin/bash
echo "$*" >> "$LC_LOG"
[ "$1" = list ] || exit 0
case " ${STUB_LOADED:-} " in *" $2 "*) printf '{\n\t"Label" = "%s";\n};\n' "$2"; exit 0;; esac
exit 113
EOF
chmod +x "$T/fake-launchctl"
export FT_LAUNCHCTL="$T/fake-launchctl" LC_LOG="$T/lc.log" STUB_LOADED="$LABEL"; : > "$LC_LOG"
nkick() { grep -c '^kickstart' "$LC_LOG"; }
nboot() { grep -c '^bootstrap' "$LC_LOG"; }
sum() { cksum < "$DST"; }
# 임시 키트 리포 = 미러 템플릿 1개 + 지도 (c0 → c1 이 템플릿을 넣는다)
R="$T/repo"; KD=kit; mkdir -p "$R/$KD/slack-mirror"; G() { git -C "$R" "$@"; }
G init -q -b main . && G config user.name t && G config user.email t@t
cp "$H/kit/LIVE-MAP.tsv" "$R/$KD/LIVE-MAP.tsv"; G add -A && G commit -qm c0; C0="$(G rev-parse HEAD)"
cp "$TPL" "$R/$KD/$TPL_REL"; G add -A && G commit -qm c1; C1="$(G rev-parse HEAD)"
chk() { out="$(bash "$CHK" --range "$C0..$C1" --ref "$C1" --repo "$R" --kit "$KD" "$@" 2>&1)"; rc=$?; }
inst() { out="$(bash "$INST" "$@" --project "$P" --home "$HOME" 2>&1)"; rc=$?; }

python3 -m py_compile "$ENV_PY" "$H/bin/ft_live_install_check.py" && bash -n "$INST"; ck "py_compile 2 · bash -n install.sh" $?
cmp -s "$ENV_PY" "$H/kit/fable-team/bin/ft_plist_env.py" && cmp -s "$H/bin/ft_live_install_check.py" "$H/kit/fable-team/bin/ft_live_install_check.py"; ck "bin/kit 짝 cmp0 (ft_plist_env · ft_live_install_check)" $?
grep -q '<key>FT_ROOT</key><string>__ROOT__</string>' "$TPL"; ck "미러 템플릿에 FT_ROOT=__ROOT__ 키" $?

# ⓐ 템플릿 → 렌더본: FT_ROOT=프로젝트 · inbox=LIVE_BIN · 머신별 값(채널) 보존 · plutil -lint rc0
out="$(python3 "$ENV_PY" render "$LABEL" "$TPL" "$DST" "$P" "$LB" "$HOME" 2>&1)"; rc=$?; printf '%s\n' "$out" > "$T/r.plist"
[ "$rc" = 0 ] && plutil -lint "$T/r.plist" >/dev/null \
  && [ "$(plutil -extract EnvironmentVariables.FT_ROOT raw "$T/r.plist")" = "$P" ] \
  && has "<string>$LB/ft-inbox.sh</string>" && has "<string>C0TEST</string>" && ! has "__"; ck "ⓐ 렌더본 FT_ROOT=<루트> · inbox=<LIVE_BIN>/ft-inbox.sh · 채널 보존 · plutil rc0" $?

# ⓑ 옛 설치본(FT_ROOT 없음) → install-check PENDING plist-env rc1 · 설치기 dry-run 은 쓰기 0
chk --project "$P"; [ "$rc" = 1 ] && has "PENDING plist-env $LABEL" && has "HINT plist-env"; ck "ⓑ install-check: FT_ROOT 없는 설치본 → PENDING plist-env rc1 + HINT" $?
s0="$(sum)"; inst --dry-run; [ "$rc" = 0 ] && has "PLIST $LABEL" && [ "$(sum)" = "$s0" ] && [ "$(nkick)" = 0 ]; ck "ⓑ install.sh --dry-run(설치본 bin 전) → PLIST 줄 · rc0 · 쓰기 0 · kickstart 0" $?
inst --apply; [ "$rc" = 0 ] && has "PENDING plist-env $LABEL" && has "PLIST applied $LABEL" && [ -f "$DST.bak-r426" ] && [ "$(nkick)" = 1 ] && [ "$(nboot)" = 1 ]
ck "ⓑ install.sh --apply → 교체 + .bak-r426 + bootstrap·kickstart 각 1" $?
cmp -s "$DST.bak-r426" "$T/legacy.plist" && [ "$(plutil -extract EnvironmentVariables.FT_ROOT raw "$DST")" = "$P" ] \
  && plutil -lint "$DST" >/dev/null; ck "ⓑ .bak-r426 = 옛 설치본 · 설치본 FT_ROOT=<루트> · plutil rc0" $?
LIVEBIN="$(sed -n 1p "$P/.fable-team/LIVE_BIN")"
grep -q "<string>$LIVEBIN/ft-inbox.sh</string>" "$DST"; ck "ⓑ inbox 경로 = 설치본 LIVE_BIN($LIVEBIN)" $?
chk --project "$P"; [ "$rc" = 0 ] && has "OK"; ck "ⓑ apply 뒤 install-check → OK rc0" $?

# ⓒ 같으면 쓰기 0 · kickstart 0
k0="$(nkick)"; s0="$(sum)"; inst --apply; [ "$rc" = 0 ] && has "OK plist-env $LABEL" && [ "$(nkick)" = "$k0" ] && [ "$(sum)" = "$s0" ]; ck "ⓒ 같음 → OK plist-env · 쓰기 0 · kickstart 0" $?
inst --dry-run; [ "$rc" = 0 ] && has "OK plist-env $LABEL"; ck "ⓒ dry-run(설치 뒤) → OK plist-env" $?
cp -p "$DST" "$T/good.plist"; sed -i '' '/<key>FT_ROOT<\/key>/d' "$DST"; s0="$(sum)"; k0="$(nkick)"
inst --dry-run; [ "$rc" = 0 ] && has "PENDING plist-env $LABEL" && [ "$(sum)" = "$s0" ] && [ "$(nkick)" = "$k0" ]; ck "ⓒ' 설치 뒤 FT_ROOT 빠짐 → dry-run PENDING plist-env · 쓰기 0" $?
cp -p "$DST.bak-r426" "$T/bak0"; inst --apply; cmp -s "$DST.bak-r426" "$T/bak0" && cmp -s "$DST" "$T/good.plist"; ck "ⓒ' 재apply → .bak-r426 는 첫 원본 보존 · 렌더본 복구" $?

# ⓓ 치환 실패 = ERROR (조용한 통과 0)
out="$(python3 "$ENV_PY" render "$LABEL" "$TPL" "$DST" "$T/no-root" "$LB" "$HOME" 2>&1)"; rc=$?; [ "$rc" = 3 ] && has "ERROR" && has "루트 없음"; ck "ⓓ 렌더: 루트 없음 → ERROR rc3" $?
chk --project "$T/no-root"; [ "$rc" = 3 ] && has "ERROR"; ck "ⓓ install-check --project 없는 루트 → ERROR rc3" $?
mv "$P/.fable-team/LIVE_BIN" "$T/LIVE_BIN.keep"; chk --project "$P"; [ "$rc" = 3 ] && has "LIVE_BIN 없음"; ck "ⓓ install-check LIVE_BIN 없음 → ERROR rc3" $?
mv "$T/LIVE_BIN.keep" "$P/.fable-team/LIVE_BIN"
sed -i '' -e '/<string>--channel<\/string>/s#<string>--channel</string><string>[^<]*</string>##' "$DST"; s0="$(sum)"; k0="$(nkick)"
inst --apply; [ "$rc" = 1 ] && has "ERROR" && has "--channel" && [ "$(sum)" = "$s0" ] && [ "$(nkick)" = "$k0" ]; ck "ⓓ 설치본에 --channel 값 없음 → install.sh ERROR rc1 · 쓰기 0 · kickstart 0" $?
out="$(python3 "$ENV_PY" render com.other.x "$TPL" "$DST" "$P" "$LB" "$HOME" 2>&1)"; rc=$?; [ "$rc" = 3 ] && has "관리 대상 라벨 아님"; ck "ⓓ 관리 밖 라벨 → ERROR rc3" $?
out="$(python3 "$ENV_PY" bogus 2>&1)"; rc=$?; [ "$rc" = 2 ]; ck "usage → rc2" $?
rm -f "$DST" "$DST.bak-r426"; k0="$(nkick)"; inst --apply; [ "$rc" = 0 ] && has "SKIP plist $LABEL" && [ ! -e "$DST" ] && [ "$(nkick)" = "$k0" ]; ck "미설치 → SKIP(새로 깔지 않음 · 처음 설치는 slack-mirror/install.sh)" $?

# ⓔ 600/300 초 상한 0 · 10분 룰
! grep -nE '(timeout|TIMEOUT)[^0-9]{0,12}(600|300)\b' "$ENV_PY" "$INST" "$H/bin/ft_live_install_check.py"; ck "ⓔ 600/300 초 상한 0" $?
[ $((SECONDS - START)) -lt 600 ]; ck "ⓔ 시험 시간 < 10분 ($((SECONDS - START))s)" $?
[ "$(git -C "$R" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
