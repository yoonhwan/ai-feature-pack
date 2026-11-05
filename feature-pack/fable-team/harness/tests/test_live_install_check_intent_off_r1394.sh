#!/usr/bin/env bash
# test_live_install_check_intent_off_r1394.sh — r1394: 설치 대조(ft-live-install-check)가 «의도로 끈» launchd 라벨을 NOTLOADED 로 세지 않는다.
# 사건: r1355·r1377 카드가 완성 이동(ft-index-move 설치 게이트)에서 이 머신이 일부러 꺼 둔 5라벨 때문에 PENDING 으로 막혔다.
# I1 .off 파일만 있음(본 plist 없음) → SKIP 의도 끔 · rc0 · I2 명단 tsv 행 → SKIP · rc0
# I3 plist 있고 적재 0 · 명단에도 없음 → NOTLOADED rc1 (설치 누락은 그대로) · I4 plist·.off·명단 다 없음 → NOTLOADED rc1
# I5 명단 행 칸 2개 → ERROR rc3(어느 줄인지) · I6 .off 와 본 plist 가 둘 다 있음 → NOTLOADED(다시 켠 것으로 본다)
# 임시 HOME·임시 LaunchAgents·가짜 launchctl(전부 미적재)·임시 git 리포·임시 명단 tsv 만 — 실 launchd·실 홈·press 0 · 시간 상한 timeout 70.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CEILING_DIRECTORIES
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$(cd "$HERE/../../harness" && pwd -P)"
CHK="$H/bin/ft-live-install-check.sh"; PY="$H/bin/ft_live_install_check.py"
fail=0; rc=0; out=""; START=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:900}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
hasnt() { [[ "$out" != *"$1"* ]]; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# ── 픽스처: 임시 홈 · 임시 LaunchAgents · 가짜 launchctl(무엇을 물어도 미적재) ────────────────
export HOME="$T/home"; LA="$HOME/Library/LaunchAgents"; mkdir -p "$LA"
cat > "$T/fake-launchctl" <<'EOF'
#!/bin/bash
[ "$1" = list ] || exit 0
exit 113
EOF
chmod +x "$T/fake-launchctl"; export FT_LAUNCHCTL="$T/fake-launchctl"
P="$T/proj"; mkdir -p "$P/.fable-team/state"
git -C "$P" init -q -b main && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m p0   # 프로젝트 루트 = git 공용 루트
TSV="$P/.fable-team/state/launchd-intent-off.tsv"
# 라벨 4개(A·B·C·D) — 키트 템플릿은 라벨만 있고 하네스 경로를 부르지 않는다(NOROOT 갈래 회피)
tpl() { printf '<?xml version="1.0"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string>\n<key>ProgramArguments</key><array><string>/bin/echo</string></array>\n<key>StartInterval</key><integer>600</integer></dict></plist>\n' "$1"; }
R="$T/repo"; KD=kit; G() { git -C "$R" "$@"; }
mkdir -p "$R/$KD"; G init -q -b main .; G config user.name t; G config user.email t@t
printf 'intent-*.plist.template\tplist\t-\t-\n' > "$R/$KD/LIVE-MAP.tsv"
commit_kit() { G add -A >/dev/null && G commit -qm "$1" && G rev-parse HEAD; }
C0="$(commit_kit c0-map)"
tpl com.byz.intent-a > "$R/$KD/intent-a.plist.template"; tpl com.byz.intent-b > "$R/$KD/intent-b.plist.template"
C1="$(commit_kit c1-ab)"
tpl com.byz.intent-c > "$R/$KD/intent-c.plist.template"; C2="$(commit_kit c2-c)"
tpl com.byz.intent-d > "$R/$KD/intent-d.plist.template"; C3="$(commit_kit c3-d)"
chk() { out="$(timeout 70 bash "$CHK" "$@" --repo "$R" --kit "$KD" --project "$P" 2>&1)"; rc=$?; }

python3 -m py_compile "$PY" && bash -n "$CHK"; ck "py_compile · bash -n" $?
cmp -s "$PY" "$H/kit/fable-team/bin/ft_live_install_check.py"; ck "bin/kit 짝 cmp0 (ft_live_install_check)" $?

# ── I1 · I2: 의도로 끈 라벨은 SKIP(rc0) ───────────────────────────────────────────────
: > "$LA/com.byz.intent-a.plist.off-20261102"                       # ⓐ 꼴: 본 plist 없음 · .off 만
tpl com.byz.intent-b > "$LA/com.byz.intent-b.plist"                 # ⓑ 꼴: plist 있고 적재 0 · 명단에 행
printf 'com.byz.intent-b\tplanner 결정 대기\t쪽지 260673\n' > "$TSV"
chk --range "$C0..$C1" --ref "$C1"
[ "$rc" = 0 ] && has "OK n=2" && has "SKIP 의도 끔 com.byz.intent-a — .off 파일 com.byz.intent-a.plist.off-20261102" \
  && has "SKIP 의도 끔 com.byz.intent-b — planner 결정 대기" && hasnt "PENDING" && hasnt "NOTLOADED"
ck "I1 .off 파일만(본 plist 0) → SKIP 의도 끔 · rc0" $?
[ "$rc" = 0 ] && has "skip=2"; ck "I2 명단 tsv 행 → SKIP · OK 집계 skip (PENDING 아님)" $?

# ── I3: plist 있고 적재 0 · 명단에도 없음 → NOTLOADED rc1 ──────────────────────────────
tpl com.byz.intent-c > "$LA/com.byz.intent-c.plist"
chk --range "$C1..$C2" --ref "$C2"
[ "$rc" = 1 ] && has "PENDING n=1" && has "NOTLOADED com.byz.intent-c" && hasnt "SKIP 의도 끔 com.byz.intent-c"
ck "I3 plist 있음 · 적재 0 · 명단 없음 → NOTLOADED rc1" $?

# ── I4: plist·.off·명단 다 없음 → NOTLOADED rc1 ───────────────────────────────────────
chk --range "$C2..$C3" --ref "$C3"
[ "$rc" = 1 ] && has "PENDING n=1" && has "NOTLOADED com.byz.intent-d" && hasnt "SKIP"
ck "I4 plist·.off·명단 다 없음 → NOTLOADED rc1" $?

# ── I6: .off 와 본 plist 가 둘 다 있음 = 다시 켠 것 → NOTLOADED ────────────────────────
tpl com.byz.intent-a > "$LA/com.byz.intent-a.plist"
chk --range "$C0..$C1" --ref "$C1"
[ "$rc" = 1 ] && has "NOTLOADED com.byz.intent-a" && hasnt "SKIP 의도 끔 com.byz.intent-a"
ck "I6 .off + 본 plist 둘 다 → NOTLOADED rc1(다시 켠 것으로 본다)" $?

# ── I5: 명단 꼴 위반(칸 2개) → ERROR rc3 · 어느 줄인지 ────────────────────────────────
printf 'com.byz.intent-c\t\n' > "$TSV"
chk --range "$C1..$C2" --ref "$C2"
[ "$rc" = 3 ] && has "ERROR" && has "launchd-intent-off.tsv:1" && hasnt "PENDING"
ck "I5 명단 행 칸 2개(빈 사유) → ERROR rc3 + 줄 번호" $?

grep -q "def intent_off(" "$PY" && grep -q "SKIP 의도 끔" "$PY"; ck "판정 1함수(intent_off) + SKIP 줄" $?
[ $(( START + SECONDS )) -ge 0 ] && [ "$SECONDS" -le 70 ]; ck "시험 시간 상한(70초 · 실측 ${SECONDS}s)" $?
[ "$fail" = 0 ] && echo "ALL PASS (${SECONDS}s)" || { echo "FAILED $fail"; exit 1; }
