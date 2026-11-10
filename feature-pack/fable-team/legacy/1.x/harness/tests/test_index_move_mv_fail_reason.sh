#!/usr/bin/env bash
# test_index_move_mv_fail_reason.sh — r959: (ⓐ) 인덱스 이동 실패 REJECT 에 git 원문 사유 1줄 · (ⓑⓒ) 정본 게이트가 팩 착지 카드를 통과한다.
#   사건(master#116 #170071·#170104 · done110 일괄 이동 로그):
#     ⓐ r737·r847 = «REJECT 이동 실패: <진행/카드> → <완성/카드>» 뿐 — git 이 왜 실패했는지가 버려져 무엇을 고칠지 알 수 없다.
#     ⓑ r462·r560·r756 = «정본 게이트 — 랜딩 안 됨 — <sha> 가 origin/main 의 조상이 아니다» — 세 sha 는 팩 origin/main 조상인데
#        판정문 절 «닫힘 — <카드> — main(팩) `sha`» 줄을 «## §32 <카드> — 닫힘 (CLOSE)» 헤더로 오인해(카드 이름에 «main» 이 든다) 카드 리포로 풀렸다.
#   임시 리포 2개(BYZ 꼴 · 팩 꼴 · 각 origin/main) + 카드·판정문 픽스처만 — 실 라이브·실 원격·실 indices 쓰기 0.
#   SRC=<bin 폴더> 로 옛 판(전 빨강)·변이(사유 붙이기 끔 · 표식 줄 파싱 옛 판)를 같은 시험으로 돌린다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${SRC:-$(cd "$HERE/../bin" && pwd -P)}"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'chmod 755 "$T"/* 2>/dev/null; rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$T/home" LC_ALL=C
mkdir -p "$HOME"
unset FT_HARNESS_ROOT FT_INSTALL_CHECK FT_INSTALL_PENDING_DIR FT_LANDED_MARKER FT_LAND_REF FT_TEAMS_MD FT_TRACK FT_SEATS_JSON FT_MBOX
BIN="$T/bin"; mkdir -p "$BIN"
cp -p "$SRC"/ft-team-lib.sh "$SRC"/ft-harness-root.sh "$SRC"/ft-index-move.sh "$SRC"/ft-index-move-canon.sh \
      "$SRC"/ft-index-move-install.sh "$SRC"/ft-index-close-landed.sh "$SRC"/ft_da_hold_gate.py "$SRC"/ft_git_capped.py "$SRC"/ft-live-install-check.sh \
      "$SRC"/ft_live_install_check.py "$SRC"/ft_plist_env.py "$BIN/"
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

# ── 팩 리포(하네스 키트 꼴) — kit/fable-team 이 있어야 ft_harness_root 가 루트를 푼다
PR="$T/pack"; KD="$PR/feature-pack/fable-team/harness"
mkdir -p "$KD/kit/fable-team/bin"
printf '#!/bin/bash\necho v1\n' > "$KD/kit/fable-team/bin/x.sh"; chmod 755 "$KD/kit/fable-team/bin/x.sh"
g "$PR" init -q -b main; g "$PR" add -A; g "$PR" commit -qm p0; P0="$(g "$PR" rev-parse HEAD)"
printf '#!/bin/bash\necho v2\n' > "$KD/kit/fable-team/bin/x.sh"; g "$PR" add -A; g "$PR" commit -qm p1; P1="$(g "$PR" rev-parse HEAD)"
g "$PR" update-ref refs/remotes/origin/main "$P1"

# ── 카드 리포(BYZ 꼴) — 카드·정본·origin/main(자기 main 만)
CR="$T/byz"; IDX="$CR/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성} "$CR/docs/architect"
g "$CR" init -q -b main
mkdir -p "$CR/.fable-team/state"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$CR/design/TEAMS.md"
printf '## 절A 제목\nv1\n' > "$CR/docs/architect/X.md"
card() { local f="$IDX/진행/$1.md"
  { echo "# 인덱스: $1"; echo "## 상태"; echo "- 정본 영향 없음: 하네스 도구만 바뀐 카드 — 제품 정본 없음"
    echo "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)"; echo "- 설치: 없음"; } > "$f"; echo "$f"; }
kpackmain="$(card kpackmain)"          # 카드 이름에 «main» 이 든다(실사건 r462·r756 꼴)
kmv="$(card kmv)"; kmv2="$(card kmv2)"
printf '# 인덱스: kdone\n## 상태\n' > "$IDX/진행/kdone.md"; rm -f "$IDX/진행/kdone.md"; kdone="$(card kdone)"; rm -f "$kdone"
g "$CR" add -A; g "$CR" commit -qm c0; C0="$(g "$CR" rev-parse HEAD)"
echo x >> "$CR/docs/architect/X.md"; g "$CR" commit -qam c1; C1="$(g "$CR" rev-parse HEAD)"
g "$CR" update-ref refs/remotes/origin/main "$C1"
# 팩 객체를 카드 리포로 fetch 해 둔 꼴(실사건 · r581) — P1 은 두 리포에 다 있다
g "$CR" fetch -q "$PR" '+refs/heads/main:refs/remotes/pack/main'
# fetch «뒤» 에 생긴 팩 커밋 = 카드 리포에 없는 팩 sha(팩에만 있는 착지 sha)
printf 'note\n' > "$PR/README.md"; g "$PR" add -A; g "$PR" commit -qm p2; P2="$(g "$PR" rev-parse HEAD)"; g "$PR" update-ref refs/remotes/origin/main "$P2"
cat > "$CR/design/harness/DA-r959.md" <<EOF
# 판정문
## §1 kpackmain — 닫힘 (CLOSE)
닫힘 — kpackmain — main(팩) \`$P1\`
- 카드: design/harness/indices/진행/kpackmain.md
## §2 kpackmain — 닫힘 (CLOSE)
닫힘 — kpackmain — main(팩) \`$P2\`
## §3 kpackmain — 닫힘 (CLOSE)
닫힘 — kpackmain — main(팩) \`$(printf '0%.0s' {1..40})\`
## §4 kpackmain — 닫힘 (CLOSE)
닫힘 — kpackmain — main \`$P2\`
## §5 kpackmain — 닫힘 (CLOSE)
닫힘 — kpackmain — main(팩) \`$C1\`
## §6 kpackmain — 닫힘 (CLOSE)
닫힘 — kpackmain — main \`$C1\`
EOF
export FT_HARNESS_ROOT="$KD"
canon() { printf '## %s\n%s\n' "$1" "$2" | bash "$BIN/ft-index-move-canon.sh" "$kpackmain" "$CR" "$3"; }
sec() { printf '## §%s kpackmain — 닫힘 (CLOSE)\n닫힘 — kpackmain — %s `%s`\n- 정본 영향 없음: 하네스 도구만 바뀐 카드\n' "$1" "$2" "$3"; }

# ⓐ 이동 실패 사유 — git stderr 첫 줄이 REJECT 줄에 붙는다
cp -p "$kmv" "$IDX/대기/kmv.md"; g "$CR" add -A; g "$CR" commit -qm c2       # 목적지에 같은 이름 파일 = git mv 실패
out="$(bash "$BIN/ft-index-move.sh" "$kmv" 대기 2>&1)"; rc=$?
rej1="$(printf '%s\n' "$out" | grep -m1 '^REJECT 이동 실패')"
[[ "$rej1" == *" — "* ]] && [[ "$rej1" == *estination* || "$rej1" == *"already exists"* ]] \
  && ck "ⓐ git mv 실패 → REJECT 줄 «안»에 git 원문 사유(«destination exists») 포함" 0 || ck "ⓐ git mv 실패 사유 :: $rej1" 1
rm -f "$IDX/대기/kmv.md"; g "$CR" add -A; g "$CR" commit -qm c3
mv_untracked=1; chmod 555 "$IDX/대기"
out="$(bash "$BIN/ft-index-move.sh" "$kmv2" 대기 2>&1)"; rc=$?
chmod 755 "$IDX/대기"
rej2="$(printf '%s\n' "$out" | grep -m1 '^REJECT 이동 실패')"
[[ "$rej2" == *" — "*"enied"* ]] && mv_untracked=0
ck "ⓐ mv(untracked) 실패 → REJECT 줄 «안»에 원문 사유(«Permission denied») :: $rej2" "$mv_untracked"
out="$(bash "$BIN/ft-index-move.sh" "$kmv" 대기 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == MOVED* ]] && ck "ⓐ 정상 이동은 그대로 MOVED rc0(회귀 0)" 0 || ck "ⓐ 정상 이동 rc0" 1
bash "$BIN/ft-index-move.sh" "$IDX/대기/kmv.md" 진행 --seat s >/dev/null 2>&1 || true   # 원위치(아래 시험은 대기 방향을 다시 안 쓴다)

# ⓑⓒ 정본 게이트 — 표식 줄을 절 헤더로 오인하지 않고, 팩 착지 카드를 통과시킨다
out="$(canon '§1 kpackmain — 닫힘 (CLOSE)' "$(sec 1 'main(팩)' "$P1")" "$P1" 2>"$T/w1")"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "OK"$'\t'"정본 영향 없음:"* ]] && ck "ⓑ 두 리포에 다 있는 팩 sha + 표식 main(팩) → OK(절 헤더 오인 0)" 0 || ck "ⓑ 팩 착지(두 리포) → OK" 1
out="$(canon '§2 kpackmain — 닫힘 (CLOSE)' "$(sec 2 'main(팩)' "$P2")" "$P2" 2>"$T/w2")"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "OK"$'\t'* ]] && ck "ⓑ 팩에만 있는 착지 sha + 표식 main(팩) → OK(«랜딩 안 됨» 0)" 0 || ck "ⓑ 팩에만 있는 sha → OK" 1
out="$(canon '§3 kpackmain — 닫힘 (CLOSE)' "$(sec 3 'main(팩)' "$(printf '0%.0s' {1..40})")" "$(printf '0%.0s' {1..40})" 2>"$T/w3")"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "REJECT"$'\t'* ]] && ck "ⓑ 두 리포 어디에도 없는 sha → 지금처럼 REJECT" 0 || ck "ⓑ 없는 sha → REJECT" 1
out="$(canon '§4 kpackmain — 닫힘 (CLOSE)' "$(sec 4 'main' "$P2")" "$P2" 2>"$T/w4")"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "OK"$'\t'* ]] && [[ "$(cat "$T/w4")" == *"표식 오기(팩 착지)"* ]] \
  && ck "ⓒ 표식 main 인데 sha 가 팩에만 → «표식 오기(팩 착지)» WARN + 팩 조상이면 통과" 0 || ck "ⓒ 표식 오기(팩) → WARN + 통과 :: $(cat "$T/w4")" 1
out="$(canon '§5 kpackmain — 닫힘 (CLOSE)' "$(sec 5 'main(팩)' "$C1")" "$C1" 2>"$T/w5")"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "REJECT"$'\t'*"표식 오기"* ]] && ck "ⓒ 표식 main(팩) 인데 sha 가 카드 리포에만 → REJECT(숨김 0 · 회귀 0)" 0 || ck "ⓒ 표식 오기(카드) → REJECT" 1
out="$(canon '§6 kpackmain — 닫힘 (CLOSE)' "$(sec 6 'main' "$C1")" "$C1" 2>"$T/w6")"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "OK"$'\t'* ]] && ck "ⓒ 표식 main + 카드 리포 착지 → OK(정상 길 회귀 0)" 0 || ck "ⓒ 카드 착지 → OK" 1

# ⓑ2 끝에서 끝까지 — ft-index-move.sh 진행→완성 이 팩 착지 카드를 실제로 옮긴다(두 파일의 표식 파싱을 같이 덮는다)
printf -- '- 착지: %s\n' "$P1" >> "$kpackmain"
out="$(bash "$BIN/ft-index-move.sh" "$kpackmain" 완성 --da "$CR/design/harness/DA-r959.md#§1" --landed "$P1" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"MOVED 진행→완성"* ]] && [ -f "$IDX/완성/kpackmain.md" ] \
  && ck "ⓑ 진행→완성: 팩 착지 카드가 정본 게이트를 통과해 실제로 이동" 0 || ck "ⓑ 진행→완성 이동 :: $out" 1

# ⓒ2 두 게이트가 «같은 판정» — 설치: 있음 + 표식 main + 팩 착지(팩 origin/main 조상) → 정본 WARN 뒤 이동 통과
printf '# 인덱스: kpackmain2\n## 상태\n- 정본 영향 없음: 하네스 도구만 바뀐 카드 — 제품 정본 없음\n- 규칙: 없음 — 시험 fixture 카드(규칙 무관)\n- 설치: 있음\n- 실사건: 라이브 대조 1회 · 증거 mbox #170281\n' > "$IDX/진행/kpackmain2.md"
printf '#!/bin/bash\necho "OK n=0 skip=0"\n' > "$T/fake-chk.sh"; chmod 755 "$T/fake-chk.sh"
sec7="$(printf '## §7 kpackmain2 — 닫힘 (CLOSE)\n닫힘 — kpackmain2 — main `%s`\n- 정본 영향 없음: 하네스 도구만 바뀐 카드\n' "$P2")"
printf '## §7 kpackmain2 — 닫힘 (CLOSE)\n닫힘 — kpackmain2 — main `%s`\n' "$P2" >> "$CR/design/harness/DA-r959.md"
out="$(FT_INSTALL_CHECK="$T/fake-chk.sh" FT_HARNESS_ROOT="$KD" bash "$BIN/ft-index-move.sh" "$IDX/진행/kpackmain2.md" 완성 --da "$CR/design/harness/DA-r959.md#§7" --landed "$P2" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"MOVED 진행→완성"* ]] && [[ "$out" == *"표식 오기(팩 착지)"* ]] \
  && ck "ⓒ2 설치: 있음 + 표식 main + 팩 착지 → 정본·설치 두 게이트 같은 판정(WARN 뒤 이동 통과)" 0 || ck "ⓒ2 두 게이트 같은 판정 :: $out" 1

# ⓒ3 보류 이력이 있는 카드도 같다 — DA⑥ r2 반례 그대로(ⓒ2 카드 + `- DA⑥ r1 HOLD 4`·`- DA⑥ r2 HOLD 1`) → 보류 가드가 먼저 거절하지 않는다
printf '# 인덱스: kpackmain3\n## 상태\n- 정본 영향 없음: 하네스 도구만 바뀐 카드 — 제품 정본 없음\n- 규칙: 없음 — 시험 fixture 카드(규칙 무관)\n- 설치: 있음\n- 실사건: 라이브 대조 1회 · 증거 mbox #170281\n- DA⑥ r1 HOLD 4\n- DA⑥ r2 HOLD 1\n' > "$IDX/진행/kpackmain3.md"
printf '## §8 kpackmain3 — 닫힘 (CLOSE)\n닫힘 — kpackmain3 — main `%s`\n' "$P2" >> "$CR/design/harness/DA-r959.md"
out="$(FT_INSTALL_CHECK="$T/fake-chk.sh" FT_HARNESS_ROOT="$KD" bash "$BIN/ft-index-move.sh" "$IDX/진행/kpackmain3.md" 완성 --da "$CR/design/harness/DA-r959.md#§8" --landed "$P2" 2>&1)"; rc=$?
nwarn=$(printf '%s\n' "$out" | grep -c '표식 오기(팩 착지)')
[ "$rc" = 0 ] && [[ "$out" == *"MOVED 진행→완성"* ]] && [ "$nwarn" -ge 1 ] \
  && ck "ⓒ3 보류 이력 2줄 카드 + 표식 main + 팩 착지 → 이동 통과(WARN 1회 이상 · 이동 명령 전체 출력에서)" 0 || ck "ⓒ3 보류 이력 카드 :: $out" 1

# ⓒ4 네 번째 호출 — ft-index-close-landed.sh 도 같은 판정(표식 main · 팩에만 · 팩 조상 → 조상 ok)
printf '# 인덱스: kclose\n## 상태\n- 설치: 없음\n' > "$IDX/진행/kclose.md"
printf '# 판정문\n## §1 kclose — 닫힘 (CLOSE)\n닫힘 — kclose — main `%s`\n' "$P2" > "$CR/design/harness/DA-close959.md"
out="$(FT_HARNESS_ROOT="$KD" bash "$BIN/ft-index-close-landed.sh" "$CR/design/harness/DA-close959.md" --dry-run 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"| §1 | kclose | 진행 | ok |"* ]] && [[ "$out" != *"not-found"* ]] \
  && ck "ⓒ4 close-landed(네 번째 호출)도 표식 오기 보정 → 조상 ok" 0 || ck "ⓒ4 close-landed 보정 :: $out" 1

# ⓒ5 안전망 — 네 호출이 모두 기본 함수를 쓰고, 보정은 함수 안에 있다(부르는 쪽마다 붙이지 않는다)
callers="$(grep -l 'ft_landed_repo ' "$BIN"/ft-index-move-canon.sh "$BIN"/ft-index-move-install.sh "$BIN"/ft-index-close-landed.sh "$BIN"/ft_da_hold_gate.py 2>/dev/null | wc -l | tr -d ' ')"
alias_hits="$(grep -rn 'ft_landed_repo_marked' "$BIN" | wc -l | tr -d ' ')"
incorr="$(awk '/^ft_landed_repo\(\)/,/^ft_team_has\(\)/' "$BIN/ft-team-lib.sh" | grep -c '표식 오기(팩 착지)')"
[ "$callers" = 4 ] && [ "$alias_hits" = 0 ] && [ "$incorr" -ge 1 ] \
  && ck "ⓒ5 호출 4곳 모두 기본 함수 · 보정은 ft_landed_repo 안 · 별칭 잔재 0" 0 || ck "ⓒ5 호출 자리 :: callers=$callers alias=$alias_hits incorr=$incorr" 1

# ⓕ ④(r426 rc3): --range 갈래(팩 착지 sha)도 `--project <카드 리포 공용 루트>` 를 넘긴다 — 안 넘기면 검사기가 팩 리포를 프로젝트로 보아 «plist-env … LIVE_BIN 없음» ERROR(rc3)
LBL=com.hermes.byz-mbox-slack-mirror; TPLREL="slack-mirror/$LBL.plist.template"; KSRC="$(cd "$HERE/../kit" && pwd -P)"
PR2="$T/pack2"; K2="$PR2/feature-pack/fable-team/harness"
mkdir -p "$K2/kit/fable-team/bin" "$K2/kit/slack-mirror"
cp -p "$KSRC/LIVE-MAP.tsv" "$K2/kit/LIVE-MAP.tsv"; printf '#!/bin/bash\n' > "$K2/kit/fable-team/bin/x.sh"
g "$PR2" init -q -b main; g "$PR2" add -A; g "$PR2" commit -qm q0; Q0="$(g "$PR2" rev-parse HEAD)"
cp -p "$KSRC/$TPLREL" "$K2/kit/$TPLREL"; g "$PR2" add -A; g "$PR2" commit -qm q1; Q1="$(g "$PR2" rev-parse HEAD)"
g "$PR2" update-ref refs/remotes/origin/main "$Q1"
LB2="$T/livebin2"; mkdir -p "$LB2"; printf '#!/bin/bash\n' > "$LB2/ft-inbox.sh"; printf '%s\n' "$LB2" > "$CR/.fable-team/LIVE_BIN"
H2="$T/home2"; mkdir -p "$H2/Library/LaunchAgents" "$H2/.hermes/scripts"
cp -p "$KSRC/slack-mirror/byz_mbox_slack_mirror.py" "$H2/.hermes/scripts/byz_mbox_slack_mirror.py"   # 라이브 = 키트 사본(대조 통과)
cat > "$T/fake-launchctl" <<'LC'
#!/bin/bash
[ "$1" = list ] || exit 0
printf '{\n\t"Label" = "%s";\n};\n' "$STUB_LOADED"; exit 0
LC
chmod 755 "$T/fake-launchctl"
# 설치본(사건 당시 꼴 = FT_ROOT 없음 · inbox 옛 bin) → 렌더기가 이것을 읽어 렌더본을 만든다(dst 가 없으면 렌더기가 ERROR)
sed -e '/<key>FT_ROOT<\/key>/d' -e "s#__PY__#$(command -v python3)#; s#__HOME__#$H2#g; s#__PROJECT__#byz#; s#__MAILBOX__#$CR/.fable-team/comm/mailbox.log.jsonl#" \
    -e "s#__SEAT__#^byz-harness-(arch|master-claude)\#[0-9]+\$#; s#__CHANNEL__#C0TEST#; s#__MENTION__#U0TEST#; s#__REPO__#o/r#; s#__INBOX_BIN__#$CR/.worktrees/old/.fable-team/bin/ft-inbox.sh#" \
    "$KSRC/$TPLREL" > "$H2/Library/LaunchAgents/$LBL.plist"
CRP="$(cd "$CR" && pwd -P)"   # 검사기는 realpath(root) 로 렌더한다 — 같은 글자로 맞춘다(/var ↔ /private/var)
python3 "$KSRC/fable-team/bin/ft_plist_env.py" render "$LBL" "$KSRC/$TPLREL" "$H2/Library/LaunchAgents/$LBL.plist" "$CRP" "$LB2" "$H2" > "$T/rendered.plist" 2>"$T/render.err" \
  && mv "$T/rendered.plist" "$H2/Library/LaunchAgents/$LBL.plist" || echo "FIXTURE-FAIL ⓕ 렌더본을 못 만들었다: $(cat "$T/render.err")"
kf="$IDX/진행/kinstmain.md"
{ echo '# 인덱스: kinstmain'; echo '## 상태'; echo '- 설치: 있음'; echo '- 실사건: 라이브 대조 1회 · 증거 mbox #170228'; } > "$kf"
inst() { HOME="$H2" FT_BIN="$LB2" FT_HARNESS_ROOT="$K2" FT_LAUNCHCTL="$T/fake-launchctl" STUB_LOADED="$LBL" bash "$1/ft-index-move-install.sh" "$kf" --landed "$Q1" 2>&1; }
out="$(inst "$BIN")"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"OK 설치 확인"* ]] && [[ "$out" != *"ERROR plist-env"* ]] \
  && ck "ⓕ 팩 착지 + plist 템플릿을 바꾼 범위 → --project 를 넘겨 plist-env ERROR 0 · rc0" 0 || ck "ⓕ --range 갈래 --project :: $out" 1

# ⓓ 오염 0 — 픽스처 밖 변경 없음(팩 무변경 · 카드 리포는 design/harness 만)
[ -z "$(g "$PR" status --porcelain)" ] && ck "ⓓ 팩 리포 변경 0" 0 || ck "ⓓ 팩 리포 변경 0 :: $(g "$PR" status --porcelain | head -2)" 1

# ⓔ bash 3.2(/bin/bash) 문법 — 고친 두 파일 + lib
b32=0
for f in ft-index-move.sh ft-index-move-canon.sh ft-index-move-install.sh ft-team-lib.sh; do /bin/bash -n "$BIN/$f" 2>/dev/null || b32=1; done
[ "$b32" = 0 ] && ck "ⓔ bash 3.2(/bin/bash) -n rc0 — 고친 두 파일 + lib" 0 || ck "ⓔ bash 3.2 문법" 1

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
