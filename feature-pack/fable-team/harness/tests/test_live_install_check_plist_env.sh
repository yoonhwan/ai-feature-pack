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
git -C "$P" init -q -b main && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m p0  # r457: 프로젝트 = git 공용 루트
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
# r464: FT_FAKE_BOOTSTRAP_FAIL=<n> → 이 값을 켠 뒤 첫 n 회 bootstrap 실패(카운터 = $BOOT_CNT · 시각 = $BOOT_TS)
if [ "$1" = bootstrap ]; then
  date +%s >> "$BOOT_TS"; c=$(( $(cat "$BOOT_CNT" 2>/dev/null || echo 0) + 1 )); echo "$c" > "$BOOT_CNT"
  [ "$c" -gt "${FT_FAKE_BOOTSTRAP_FAIL:-0}" ] || { echo "Bootstrap failed: 5: Input/output error" >&2; exit 5; }
fi
[ "$1" = list ] || exit 0
case " ${STUB_LOADED:-} " in *" $2 "*) printf '{\n\t"Label" = "%s";\n};\n' "$2"; exit 0;; esac
exit 113
EOF
chmod +x "$T/fake-launchctl"
export FT_LAUNCHCTL="$T/fake-launchctl" LC_LOG="$T/lc.log" STUB_LOADED="$LABEL" BOOT_CNT="$T/boot.cnt" BOOT_TS="$T/boot.ts"; : > "$LC_LOG"
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

# r457 — plist 는 git 공용 루트 설치에서만 · 워크트리 --project(r413 shim 설치)는 plist 0
git -C "$P" worktree add -q --detach "$P/.worktrees/w" && mkdir -p "$P/.worktrees/w/.fable-team/bin"; W="$(cd "$P/.worktrees/w" && pwd -P)"
instw() { out="$(bash "$INST" "$@" --project "$W" --home "$HOME" 2>&1)"; rc=$?; }
inst --dry-run; [ "$rc" = 0 ] && has "OK plist-env $LABEL" && ! has "SKIP plist-env"; ck "r457ⓐ --project <공용 루트> → 기존 그대로(OK plist-env · SKIP 0)" $?
cp -p "$T/legacy.plist" "$DST"; k0="$(nkick)"; b0="$(nboot)"
instw --dry-run; [ "$rc" = 0 ] && has "SKIP plist-env $LABEL (--project 가 git 공용 루트 아님: 루트=$P" && ! has "PENDING plist-env" && cmp -s "$DST" "$T/legacy.plist"
ck "r457ⓑ 워크트리 dry-run → SKIP plist-env 1줄 · plist 불변" $?
instw --apply; [ "$rc" = 0 ] && [ "$(grep -c '^SKIP plist-env' <<< "$out")" = 1 ] && ! has "PLIST applied" && cmp -s "$DST" "$T/legacy.plist" \
  && [ "$(nkick)" = "$k0" ] && [ "$(nboot)" = "$b0" ] && [ -f "$W/.fable-team/LIVE_BIN" ]
ck "r457ⓑ 워크트리 apply → SKIP 1줄 · plist cmp 불변 · launchctl 0 · shim 설치(LIVE_BIN)는 그대로" $?
out="$(python3 "$ENV_PY" render "$LABEL" "$TPL" "$T/good.plist" "$W" "$LB" "$HOME" 2>&1)"; rc=$?; [ "$rc" = 3 ] && has "루트가 git 공용 루트 아님(워크트리)"
ck "r457ⓒ 렌더기 직접 · 워크트리 루트 → RenderError rc3" $?
out="$(python3 "$ENV_PY" render "$LABEL" "$TPL" "$T/good.plist" "$P" "$LB" "$HOME" 2>&1)"; rc=$?; [ "$rc" = 0 ]; ck "r457ⓒ 렌더기 직접 · 공용 루트 → rc0" $?
chk --project "$W"; [ "$rc" = 1 ] && has "PENDING plist-env $LABEL" && has "FT_ROOT=$P)" && has "HINT plist-env bash " && has "install.sh --apply --project $P" && ! has "--project $W"
ck "r457ⓓ install-check 워크트리 --project → plist-env 대조·HINT 는 공용 루트($P)" $?
Q="$T/nogit"; mkdir -p "$Q/.fable-team/bin"; cp -p "$P/.fable-team/LIVE_BIN" "$Q/.fable-team/LIVE_BIN"; Q="$(cd "$Q" && pwd -P)"; k0="$(nkick)"
out="$(bash "$INST" --apply --project "$Q" --home "$HOME" 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "ERROR" && has "git 공용 루트 아님(.git 없음)" && cmp -s "$DST" "$T/legacy.plist" && [ "$(nkick)" = "$k0" ]
ck "r457ⓔ git 밖 --project → install.sh ERROR rc1 · plist 불변(새 통과 0)" $?
chk --project "$Q"; [ "$rc" = 3 ] && has "git 공용 루트 아님"; ck "r457ⓔ git 밖 --project → install-check ERROR rc3" $?
cp -p "$T/good.plist" "$DST"

# r464 — bootout 직후 bootstrap 실패(launchd 비동기) → 1초 간격 최대 3회 · 그래도 실패면 직전 plist 원복 + 다시 올림 · LIVE_BIN 전환은 plist «앞»
VER="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$H/../manifest.json")"; NEWBIN="$(cd "$HOME/.claude/fable-team/live/$VER/bin" && pwd -P)"
lbin() { (cd "$(sed -n 1p "$P/.fable-team/LIVE_BIN")" && pwd -P); }
fails() { export FT_FAKE_BOOTSTRAP_FAIL="$1"; : > "$BOOT_CNT"; : > "$BOOT_TS"; }
cp -p "$T/legacy.plist" "$DST"; cp -p "$DST.bak-r426" "$T/bak0"; printf '%s\n' "$LB" > "$P/.fable-team/LIVE_BIN"; k0="$(nkick)"; fails 1
inst --apply; [ "$rc" = 0 ] && has "PLIST applied $LABEL (retry=1 · 되돌림 = $DST.bak-$VER" && [ "$(grep -c . "$BOOT_TS")" = 2 ] && [ "$(nkick)" = $((k0 + 1)) ] \
  && cmp -s "$DST" "$T/good.plist" && [ "$(lbin)" = "$NEWBIN" ] && has "INSTALLED $VER · PLIST ok"
ck "r464ⓐ bootstrap 1회 실패 뒤 성공 → PLIST applied (retry=1) · kickstart 1 · 렌더본 · LIVE_BIN 전환 · rc0" $?
cp -p "$T/legacy.plist" "$DST"; printf '%s\n' "$LB" > "$P/.fable-team/LIVE_BIN"; k0="$(nkick)"; fails 3
inst --apply; [ "$rc" = 1 ] && has "PLIST RESTORED $LABEL — 새 렌더본 적용 실패(bootstrap 3회 실패: Bootstrap failed: 5: Input/output error)" \
  && cmp -s "$DST" "$T/legacy.plist" && [ "$(grep -c . "$BOOT_TS")" = 4 ] && [ "$(nkick)" = "$k0" ] && ! has "PLIST applied" \
  && has "INSTALLED $VER · PLIST ERROR" && [ "$(lbin)" = "$NEWBIN" ]
ck "r464ⓑ bootstrap 3회 실패 → 직전 plist 원복(cmp0) + 원복본 bootstrap · RESTORED · rc1 · LIVE_BIN 은 이미 새 버전" $?
cmp -s "$DST.bak-r426" "$T/bak0"; ck "r464ⓑ .bak-r426(첫 원본) 보존" $?
fails 6; cp -p "$T/legacy.plist" "$DST"; inst --apply; [ "$rc" = 1 ] && has "ERROR: plist 원복본 bootstrap 도 실패 $LABEL" && has "손 복구 = launchctl bootstrap" \
  && cmp -s "$DST" "$T/legacy.plist" && has "INSTALLED $VER · PLIST ERROR"
ck "r464ⓑ' 원복본 bootstrap 도 실패 → ERROR + 손 복구 1줄 · plist 는 원복본 · rc1" $?
fails 0; cp -p "$T/good.plist" "$DST"; k0="$(nkick)"; b0="$(nboot)"; s0="$(sum)"
inst --apply; [ "$rc" = 0 ] && has "OK plist-env $LABEL" && [ "$(nkick)" = "$k0" ] && [ "$(nboot)" = "$b0" ] && [ "$(sum)" = "$s0" ]
ck "r464ⓒ 렌더본 같음 → 쓰기 0 · bootstrap·kickstart 0" $?
sed '/<key>FT_ROOT<\/key>/d' "$T/good.plist" > "$T/prev.plist"; cp -p "$T/prev.plist" "$DST"; inst --apply
[ "$rc" = 0 ] && cmp -s "$DST.bak-$VER" "$T/prev.plist" && cmp -s "$DST.bak-r426" "$T/bak0" && ! cmp -s "$T/prev.plist" "$T/bak0" && cmp -s "$DST" "$T/good.plist"
ck "r464ⓓ 되돌림 기준 = 직전 plist(.bak-$VER) · .bak-r426 보존" $?
fails 3; cp -p "$T/legacy.plist" "$DST"; inst --apply; span=$(( $(tail -1 "$BOOT_TS") - $(head -1 "$BOOT_TS") ))
[ "$rc" = 1 ] && [ "$(grep -c . "$BOOT_TS")" = 4 ] && [ "$span" -le 7 ]; ck "r464ⓔ 재시도 첫~마지막 bootstrap ${span}s ≤ 7초" $?
fails 0; cp -p "$T/good.plist" "$DST"

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
