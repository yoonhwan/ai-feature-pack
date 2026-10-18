#!/usr/bin/env bash
# test_live_install_check.sh — R245 병합 ≠ 끝: 키트 → 라이브 설치 대조(ft-live-install-check.sh) · 착지 INSTALL 줄 · 카드 완성 이동 설치 게이트 · 뉴스 줄.
# 임시 HOME·임시 git 리포·가짜 launchctl/ps 만 — 실 라이브(~/.hermes·~/.claude·FT_BIN)·실 원격·실 gh 0. press 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KITMAP="$HERE/../../harness/kit/LIVE-MAP.tsv"
CHK="$BIN/ft-live-install-check.sh"; LAND="$BIN/ft-merge-land.sh"; GATE="$BIN/ft-index-move-install.sh"; PEND="$BIN/ft-install-pending.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# ── 픽스처: 임시 HOME + 임시 FT_BIN + 임시 키트 저장소 ─────────────────────────────
export HOME="$T/home" FT_BIN="$T/ftbin"; mkdir -p "$HOME/.claude/hooks" "$HOME/.hermes/scripts" "$FT_BIN"
R="$T/repo"; KD=scripts/harness-install
mkdir -p "$R/$KD"/{fable-team/bin,hooks,slack-mirror,tmm}
G() { git -C "$R" "$@"; }
G init -q -b main . && G config user.name t && G config user.email t@t
[ -f "$KITMAP" ] && cp "$KITMAP" "$R/$KD/LIVE-MAP.tsv"
printf '#!/bin/bash\necho a1\n' > "$R/$KD/fable-team/bin/ft-a.sh"; chmod 755 "$R/$KD/fable-team/bin/ft-a.sh"
printf '#!/bin/bash\necho h1\n' > "$R/$KD/hooks/h.sh"; chmod 755 "$R/$KD/hooks/h.sh"
printf 'print(1)\n' > "$R/$KD/slack-mirror/x.py"; echo tmm1 > "$R/$KD/tmm/tmm"
cat > "$R/$KD/slack-mirror/com.hermes.test-x.plist.template" <<'EOF'
<plist><dict><key>Label</key><string>com.hermes.test-x</string><key>ProgramArguments</key><array><string>__PY__</string><string>__HOME__/.hermes/scripts/x.py</string></array></dict></plist>
EOF
G add -A && G commit -qm c0; C0="$(G rev-parse HEAD)"; G update-ref refs/remotes/origin/main HEAD
live_sync() { git -C "$R" show "$1:$KD/$2" > "$3"; [ -z "${4:-}" ] || chmod "$4" "$3"; }   # live_sync <ref> <키트상대> <라이브경로> [모드]
live_sync "$C0" fable-team/bin/ft-a.sh "$FT_BIN/ft-a.sh" 755; live_sync "$C0" hooks/h.sh "$HOME/.claude/hooks/h.sh" 755; live_sync "$C0" slack-mirror/x.py "$HOME/.hermes/scripts/x.py"
# 가짜 launchctl · ps
cat > "$T/fake-launchctl" <<'EOF'
#!/bin/bash
[ "$1" = list ] || exit 64
case " ${STUB_LOADED:-} " in *" $2 "*) printf '{\n\t"Label" = "%s";\n\t"PID" = 4242;\n};\n' "$2"; exit 0;; esac
exit 113
EOF
printf '#!/bin/bash\necho "${STUB_LSTART:-Thu Oct 15 10:00:00 2026}"\n' > "$T/fake-ps"; chmod +x "$T/fake-launchctl" "$T/fake-ps"
export FT_LAUNCHCTL="$T/fake-launchctl" FT_PS="$T/fake-ps" STUB_LOADED=""
chk() { out="$(bash "$CHK" "$@" --repo "$R" 2>&1)"; rc=$?; }
commit_kit() { G add -A && G commit -qm "$1"; G update-ref refs/remotes/origin/main HEAD; G rev-parse HEAD; }   # 새 HEAD sha 출력 · origin/main = HEAD (R367: --range 대조는 ref tip)

[ -f "$CHK" ] && bash -n "$CHK"; ck "bash -n ft-live-install-check.sh (파일 실재)" $?
[ -f "$KITMAP" ]; ck "LIVE-MAP.tsv 실재" $?
[ "$(wc -l < "$CHK" 2>/dev/null | tr -d ' ')" -le 60 ]; ck "진입 ft-live-install-check.sh ≤ 60줄" $?

# ⓐ 범위 안 키트 파일이 라이브와 같음 → OK rc0
echo 'echo a2' >> "$R/$KD/fable-team/bin/ft-a.sh"; C1="$(commit_kit c1)"; live_sync "$C1" fable-team/bin/ft-a.sh "$FT_BIN/ft-a.sh" 755
chk --range "$C0..$C1"; [ "$rc" = 0 ] && has "OK n=1"; ck "ⓐ 같음 → OK n=1 rc0" $?
# 라이브 쪽 잔재: .bak · 키트에 없는 새 파일 → 무시
echo old > "$FT_BIN/ft-a.sh.bak-1"; echo extra > "$FT_BIN/ft-only-live.sh"
chk --range "$C0..$C1"; [ "$rc" = 0 ] && ! has "ft-only-live" && ! has ".bak"; ck "ⓐ' .bak·라이브 전용 파일은 오탐 0" $?
# ⓑ 내용 다름 → DIFF
echo drift >> "$FT_BIN/ft-a.sh"
chk --range "$C0..$C1"; [ "$rc" = 1 ] && has "PENDING n=1" && has "DIFF $KD/fable-team/bin/ft-a.sh -> $FT_BIN/ft-a.sh"; ck "ⓑ 다름 → PENDING + DIFF <키트> -> <라이브> rc1" $?
has "HINT"; ck "ⓑ' 폴더별 HINT 줄" $?
# ⓒ 라이브 없음 → MISSING
rm "$FT_BIN/ft-a.sh"
chk --range "$C0..$C1"; [ "$rc" = 1 ] && has "MISSING $KD/fable-team/bin/ft-a.sh -> $FT_BIN/ft-a.sh"; ck "ⓒ 라이브 없음 → MISSING rc1" $?
live_sync "$C1" fable-team/bin/ft-a.sh "$FT_BIN/ft-a.sh" 755
# MODE: 키트 755 · 라이브 실행 비트 없음
chmod 644 "$FT_BIN/ft-a.sh"; chk --range "$C0..$C1"; [ "$rc" = 1 ] && has "MODE $KD/fable-team/bin/ft-a.sh"; ck "ⓒ' 실행 비트 어긋남 → MODE rc1" $?
chmod 755 "$FT_BIN/ft-a.sh"
# ⓓ 지도에 없는 폴더 → UNMAPPED (조용한 통과 0)
mkdir -p "$R/$KD/newdir"; echo y > "$R/$KD/newdir/y.txt"; C2="$(commit_kit c2)"
chk --range "$C1..$C2"; [ "$rc" = 1 ] && has "UNMAPPED $KD/newdir/y.txt"; ck "ⓓ 지도에 없음 → UNMAPPED rc1" $?
# skip 행(tmm) → 어긋나도 OK, skip 개수만 표시
echo tmm2 > "$R/$KD/tmm/tmm"; C3="$(commit_kit c3)"
chk --range "$C2..$C3"; [ "$rc" = 0 ] && has "skip=1"; ck "skip 종류(tmm) → OK + skip=1" $?
# ⓕ 범위 밖 파일의 어긋남은 출력 0 (ft-a.sh 는 지금도 다르게 만들어 둔다)
echo drift2 >> "$FT_BIN/ft-a.sh"; echo 'echo h2' >> "$R/$KD/hooks/h.sh"; C4="$(commit_kit c4)"; live_sync "$C4" hooks/h.sh "$HOME/.claude/hooks/h.sh" 755
chk --range "$C3..$C4"; [ "$rc" = 0 ] && ! has "ft-a.sh"; ck "ⓕ 범위 밖 어긋남은 출력 0 · 범위 안 훅 OK" $?
live_sync "$C4" fable-team/bin/ft-a.sh "$FT_BIN/ft-a.sh" 755
echo 'echo h3' >> "$R/$KD/hooks/h.sh"; C5="$(commit_kit c5)"
chk --range "$C4..$C5"; [ "$rc" = 1 ] && has "DIFF $KD/hooks/h.sh -> $HOME/.claude/hooks/h.sh"; ck "훅 어긋남 → DIFF (홈 훅 경로)" $?
live_sync "$C5" hooks/h.sh "$HOME/.claude/hooks/h.sh" 755
# ⓔ plist 템플릿: 적재 여부 · 재시작 필요
echo '<!-- v2 -->' >> "$R/$KD/slack-mirror/com.hermes.test-x.plist.template"; C6="$(commit_kit c6)"
STUB_LOADED=""; chk --range "$C5..$C6"; [ "$rc" = 1 ] && has "NOTLOADED com.hermes.test-x"; ck "ⓔ 라벨 미적재 → NOTLOADED rc1" $?
export STUB_LOADED="com.hermes.test-x" STUB_LSTART="Mon Jan  1 00:00:00 2024"; touch "$HOME/.hermes/scripts/x.py"
chk --range "$C5..$C6"; [ "$rc" = 1 ] && has "RESTART com.hermes.test-x"; ck "ⓔ 적재 · 프로세스 시작 < 라이브 스크립트 mtime → RESTART rc1" $?
export STUB_LSTART="Fri Jan  1 00:00:00 2100"
chk --range "$C5..$C6"; [ "$rc" = 0 ] && has "OK"; ck "ⓔ 적재 · 프로세스가 스크립트보다 새로움 → OK" $?
# 기본 오류: 인자 없음 rc2 · 못 푸는 ref rc3
out="$(bash "$CHK" 2>&1)"; rc=$?; [ "$rc" = 2 ]; ck "인자 없음 → usage rc2" $?
chk --range "nosuchref..$C6"; [ "$rc" = 3 ] && has "ERROR"; ck "ref 못 품 → ERROR rc3(#0 RULE)" $?
chk --range "$C5..$C6" --map "$T/no-such-map.tsv"; [ "$rc" = 3 ] && has "ERROR"; ck "지도 못 읽음 → ERROR rc3" $?
# --all (ref 기준) : 훅 라이브 지우면 MISSING
rm "$HOME/.claude/hooks/h.sh"; chk --all --ref "$C6"; [ "$rc" = 1 ] && has "MISSING $KD/hooks/h.sh"; ck "--all --ref → 훅 MISSING 을 잡는다" $?
live_sync "$C6" hooks/h.sh "$HOME/.claude/hooks/h.sh" 755
# DA⑥ HOLD1: 설치 대상 아닌 폴더 문서(README·notes)는 UNMAPPED 오탐 0 · zombie-clean/*.sh 는 스킬 scripts 폴더와 cmp
mkdir -p "$R/$KD"/{launchd,loom-tunnel,stt-tunnel,zombie-clean}; echo doc > "$R/$KD/launchd/README.md"; echo doc > "$R/$KD/loom-tunnel/README.md"; echo doc > "$R/$KD/stt-tunnel/notes.txt"
C7="$(commit_kit c7)"; chk --range "$C6..$C7"; [ "$rc" = 0 ] && ! has "UNMAPPED" && has "skip=3"; ck "DA⑥ launchd·loom-tunnel·stt-tunnel 문서 파일 → OK skip=3 (UNMAPPED 0)" $?
printf '#!/bin/bash\necho z1\n' > "$R/$KD/zombie-clean/x.sh"; chmod 755 "$R/$KD/zombie-clean/x.sh"; C8="$(commit_kit c8)"
ZD="$HOME/.claude/skills/zombie-clean/scripts"; mkdir -p "$ZD"; printf '#!/bin/bash\necho OLD\n' > "$ZD/x.sh"; chmod 755 "$ZD/x.sh"
chk --range "$C7..$C8"; [ "$rc" = 1 ] && has "DIFF $KD/zombie-clean/x.sh -> $ZD/x.sh"; ck "DA⑥ zombie-clean/x.sh 내용 다름 → DIFF (스킬 scripts 경로)" $?
live_sync "$C8" zombie-clean/x.sh "$ZD/x.sh" 755; chk --range "$C7..$C8"; [ "$rc" = 0 ]; ck "DA⑥ zombie-clean/x.sh 같음 → OK" $?

# ── 착지 도구: INSTALL 줄 + 상태 파일 + rc/LANDED 불변 (ⓖ) ─────────────────────────
. "$HERE/_merge_fixture.sh"
L="$T/land"; mkdir -p "$L/state" "$L/.fable-team"; mkrepo "$L"; LW="$W"; LORIGIN="$ORIGIN"
export FT_ROOT="$L" FT_AUTONOMY_STATE_DIR="$L/state" FT_GH="$L/gh-stub" FT_GH_WRITE="$L/gh-stub" STUB_LOG="$L/gh.log" STUB_JSON="$L/pr.json"
printf '#!/bin/bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\necho "$*" >> "$STUB_LOG"\n' > "$L/gh-stub"; chmod +x "$L/gh-stub"
mkpr() { git -C "$LW" checkout -q -B "$2" origin/main; echo "pr$1" > "$LW/pr$1.txt"; cm "$LW" "pr $1"; git -C "$LW" push -q origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$LW" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"t "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"; }
land() { apv "$@"; out="$(bash "$LAND" "$@" --repo "$LW" 2>&1)"; rc=$?; }
fakechk() { printf '#!/bin/bash\n%s\n' "$1" > "$L/fakechk"; chmod +x "$L/fakechk"; }
export FT_INSTALL_CHECK="$L/fakechk" FT_INSTALL_CHECK_TIMEOUT=2
PD="$L/.fable-team/state/install-pending"

fakechk 'echo "PENDING n=1"; echo "DIFF a -> b"; exit 1'
git -C "$LW" fetch -q origin; mkpr 21 pr21; land 21 --approve-sha "$PRSHA"; Q21="$(sha "$LORIGIN" refs/heads/main)"
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=21"* ]] && has "INSTALL PENDING n=1" && has "INSTALL DIFF a -> b"; ck "ⓖ 검사 rc1 → LANDED·rc0 불변 + INSTALL 줄" $?
[ -s "$PD/$Q21.txt" ] && grep -q 'DIFF a -> b' "$PD/$Q21.txt"; ck "ⓖ PENDING → install-pending/<Q>.txt 1개" $?
fakechk 'echo "ERROR 지도 못 품"; exit 3'
git -C "$LW" fetch -q origin; mkpr 22 pr22; land 22 --approve-sha "$PRSHA"; Q22="$(sha "$LORIGIN" refs/heads/main)"
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=22"* ]] && has "INSTALL ERROR" && [ -s "$PD/$Q22.txt" ]; ck "ⓖ 검사 rc3 → LANDED·rc0 불변 + 상태 파일" $?
fakechk 'exec sleep 30'
git -C "$LW" fetch -q origin; mkpr 23 pr23; land 23 --approve-sha "$PRSHA"; Q23="$(sha "$LORIGIN" refs/heads/main)"
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=23"* ]] && has "INSTALL-PENDING" && [ -s "$PD/$Q23.txt" ]; ck "ⓖ 검사 타임아웃 → LANDED·rc0 불변 + INSTALL-PENDING 줄 + 상태 파일" $?
fakechk 'echo "OK n=2 skip=0"; exit 0'
git -C "$LW" fetch -q origin; mkpr 24 pr24; land 24 --approve-sha "$PRSHA"; Q24="$(sha "$LORIGIN" refs/heads/main)"
[ "$rc" = 0 ] && has "INSTALL OK n=2" && [ ! -e "$PD/$Q24.txt" ]; ck "ⓖ OK → INSTALL OK 줄 · 상태 파일 0" $?
fakechk 'echo "$@" > "$STUB_LOG.chkargs"; echo "OK n=1 skip=0"; exit 0'
git -C "$LW" fetch -q origin; mkpr 25 pr25; land 25 --approve-sha "$PRSHA"; Q25="$(sha "$LORIGIN" refs/heads/main)"
[ "$rc" = 0 ] && grep -q -- "--ref $Q25" "$STUB_LOG.chkargs"; ck "R367 착지 직후 검사에 --ref <착지 sha> 전달(로컬 origin/main 미갱신 경로 ERROR 0)" $?
grep -q 'ft-live-install-check' "$LAND" && [ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "착지 도구에 검사 호출 · ≤ 120줄(test_merge_land 와 같은 상한)" $?

# ── 뉴스 줄 (ft-install-pending.sh) ────────────────────────────────────────────
out="$(FT_ROOT="$L" bash "$PEND" 2>&1)"; rc=$?; [ "$rc" = 0 ] && has "설치 대기 3 병합" && has "${Q21:0:10}"; ck "⑦ 대기 파일 3개 → 「설치 대기 3 병합 — 짧은 sha」 1줄" $?
rm -f "$PD"/*.txt; out="$(FT_ROOT="$L" bash "$PEND" 2>&1)"; [ -z "$out" ]; ck "⑦ 대기 0 → 줄 0" $?
grep -q 'ft-install-pending' "$BIN/ft-news-tick.sh"; ck "⑦ 뉴스 틱이 ft-install-pending 호출" $?

# ── 카드 완성 이동 게이트 (ft-index-move-install.sh) ───────────────────────────
CR="$R"; mkdir -p "$CR/design/harness/indices/진행" "$CR/design/cfo/indices/진행"; export FT_INSTALL_PENDING_DIR="$PD"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| cfo | `design/cfo/` | c | 현역 |\n' > "$CR/design/TEAMS.md"   # R383: 하네스 카드 판정이 팀 폴더 명단을 읽는다

card() {  # card <이름> <설치줄|-> <실사건줄|-> [dir]
  local f="$CR/${4:-design/harness/indices}/진행/$1.md"
  { echo "# 인덱스: $1"; [ "$2" = "-" ] || echo "- 설치: $2"; [ "$3" = "-" ] || echo "- 실사건: $3"; echo "## 상태"; echo "- x"; } > "$f"; echo "$f"
}
gate() { out="$(bash "$GATE" "$@" 2>&1)"; rc=$?; }
fakechk 'echo "OK n=1 skip=0"; exit 0'
c="$(card g1 없음 -)"; gate "$c" ; [ "$rc" = 0 ]; ck "ⓗ 설치: 없음 → 통과(검사 호출 0)" $?
c="$(card g2 - -)"; gate "$c"; [ "$rc" = 1 ] && has "설치:"; ck "ⓗ 하네스 카드에 「- 설치:」 줄 없음 → REJECT" $?
c="$(card g3 - - design/cfo/indices)"; gate "$c"; [ "$rc" = 0 ]; ck "ⓗ 다른 팀 indices 는 줄 없음 = 통과(범위 밖)" $?
c="$(card g4 있음 '검증 · #95500')"; gate "$c"; [ "$rc" = 1 ] && has "--landed"; ck "ⓗ 설치: 있음 + --landed 없음 → REJECT" $?
fakechk 'echo "PENDING n=1"; echo "MISSING k -> l"; echo "HINT x"; exit 1'
gate "$c" --landed "$C5..$C6"; [ "$rc" = 1 ] && has "MISSING k -> l"; ck "ⓗ 있음 + 검사 PENDING → REJECT(항목 줄·HINT 출력)" $?
fakechk 'echo "ERROR x"; exit 3'
gate "$c" --landed "$C5..$C6"; [ "$rc" = 1 ]; ck "ⓗ 있음 + 검사 ERROR → REJECT" $?
fakechk 'echo "OK n=1 skip=0"; exit 0'
c="$(card g5 있음 -)"; gate "$c" --landed "$C5..$C6"; [ "$rc" = 1 ] && has "실사건"; ck "ⓗ 있음 + OK + 실사건 줄 없음 → REJECT" $?
c="$(card g6 있음 '(병합 뒤 master 기재)')"; gate "$c" --landed "$C5..$C6"; [ "$rc" = 1 ] && has "실사건"; ck "ⓗ 있음 + OK + 실사건 증거 토큰 0(자리표시) → REJECT" $?
mkdir -p "$PD"; : > "$PD/$C6.txt"
c="$(card g7 있음 '다음 하네스 병합 착지 INSTALL 줄 · 증거 mbox #95500')"; gate "$c" --landed "$C5..$C6"; [ "$rc" = 0 ]; ck "ⓗ 있음 + OK + 실사건 증거 → 통과" $?
[ ! -e "$PD/$C6.txt" ]; ck "ⓗ 통과 시 그 범위 sha 의 install-pending 파일 삭제" $?
grep -q 'ft-index-move-install' "$BIN/ft-index-move.sh"; ck "ft-index-move.sh 가 설치 게이트를 호출" $?
[ "$(wc -l < "$GATE" 2>/dev/null | tr -d ' ')" -le 60 ]; ck "ft-index-move-install.sh ≤ 60줄" $?

# ── 린트 ⑥: 하네스 카드 「- 설치:」 줄 ──────────────────────────────────────────
LINT="$HERE/../../harness/kit/fable-team/bin/ft-index-lint.sh"
LR="$T/lintrepo"; mkdir -p "$LR/design/harness/indices/대기" "$LR/design/other/indices/대기" "$LR/src"; git -C "$LR" init -q -b main .
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| other | `design/other/` | o | 현역 |\n' > "$LR/design/TEAMS.md"   # R383: 하네스 카드 판정이 팀 폴더 명단을 읽는다
G1='골 첫 줄 시험용 문장이다.'; G2='골 둘째 줄 시험용 문장이다.'; G3='골 셋째 줄 시험용 문장이다.'
printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > "$LR/goal.txt"; echo '원장 본문: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > "$LR/LEDGER.md"; echo x > "$LR/src/t.sh"
lcard() {  # lcard <dir> <이름> <설치줄|-> <구현 범위 본문>
  local f="$LR/$1/indices/대기/$2.md"
  { echo "# 인덱스: $2"; echo '- 제안서: 없음 — 시험 카드'; [ "$3" = "-" ] || echo "- 설치: $3"; echo "## 골 원문"; printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3"
    echo "## 골좌표"; echo '「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」'; echo "## 배경"; echo 'x.'
    echo "## 구현 범위"; echo "$4"; echo "## 완료 조건"; echo 'ok.'; echo "## 상태"; echo '- x'; } > "$f"; echo "$f"
}
lint() { out="$(cd "$LR" && FT_GOAL_LINES_FILE="$LR/goal.txt" FT_GOAL_LEDGER=LEDGER.md bash "$LINT" "$1" 2>&1)"; rc=$?; }
lint "$(lcard design/harness l1 - '1. src/t.sh')"; [ "$rc" = 1 ] && has "설치"; ck "⑥ 하네스 카드 「- 설치:」 줄 없음 → REJECT" $?
lint "$(lcard design/harness l2 있음 '1. src/t.sh')"; [ "$rc" = 0 ]; ck "⑥ 설치: 있음 → 통과" $?
lint "$(lcard design/harness l3 없음 '1. src/t.sh')"; [ "$rc" = 0 ]; ck "⑥ 설치: 없음 + 키트 언급 없음 → 통과" $?
lint "$(lcard design/harness l4 없음 '1. src/t.sh 와 scripts/harness-install/hooks/x.sh')"; [ "$rc" = 1 ] && has "설치"; ck "⑥ 구현 범위가 scripts/harness-install/ 언급 + 없음 → REJECT" $?
lint "$(lcard design/other o1 - '1. src/t.sh')"; [ "$rc" = 0 ]; ck "⑥ 다른 폴더 카드는 줄 없음 = 통과(범위 밖)" $?

[ "$(git -C "$R" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
