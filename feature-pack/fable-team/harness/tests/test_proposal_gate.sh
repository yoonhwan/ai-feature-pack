#!/usr/bin/env bash
# test_proposal_gate.sh — ft-proposal-gate.sh --issue 단독 시험(R77 r1 · 판정 826). 가짜 gh(PATH 대신 FT_GH_READ)·가짜 planner 원장만 — 실 gh·실 슬랙·실 tmux 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$HERE/../../harness/kit/fable-team/bin/ft-proposal-gate.sh"; FX="$HERE/_proposal_issue_fixture.py"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1 :: rc=$rc out=$out"; fail=$((fail+1)); }
bash -n "$GATE" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/planner"
cat > "$T/gh" <<'EOF'
#!/usr/bin/env bash
# 가짜 gh(읽기): issue view N → view-N.json · api …/issues/N/timeline → timeline-N.json · GH_FAIL=1 rc1 · GH_EMPTY=1 빈 응답 · GH_SLOW=1 3초 지연
echo "$*" >> "$FAKE/gh.log"
[ -n "${GH_SLOW:-}" ] && sleep 3
[ -n "${GH_FAIL:-}" ] && { echo "boom" >&2; exit 1; }
[ -n "${GH_EMPTY:-}" ] && exit 0
case "$1 $2" in
  "issue view") cat "$FAKE/view-$3.json";;
  "api --paginate") n="${4#repos/*/issues/}"; cat "$FAKE/timeline-${n%/timeline}.json";;
  *) exit 1;;
esac
EOF
export FAKE="$T" FT_GH_READ="bash $T/gh" GH_REPO="o/r" FT_PLANNER_VERDICTS_DIR="$T/planner" FT_GATE_GH_TIMEOUT=1
fx() { python3 "$FX" "$T" 12 "$@"; }
ledger() { printf '%s\n' "$@" > "$T/planner/VERDICTS-planner-1.md"; }
expect() {  # <이름> <rc> <패턴> [env…]
  out="$(bash "$GATE" --issue 12 2>&1)"; rc=$?; if [ "$rc" = "$2" ] && echo "$out" | grep -qE "$3"; then ok "$1"; else bad "$1"; fi; }
ledger "816 오빠 인터뷰(A안 · 슬랙 https://x.slack.com/archives/C/p1 · Issue https://github.com/o/r/issues/12): 채택"

fx;                      expect "1 ⓐ 오빠 계정이 approved → OK" 0 '^OK #12 승인 ⓐ$'
fx b;                    expect "2 ⓑ byz-tank approved + 인터뷰 코멘트 + 원장 줄 issues/12 → OK" 0 '^OK #12 승인 ⓑ 판정 816$'
fx noapproved;           expect "3 approved 라벨 없음 → REJECT" 1 '^REJECT #12 .*라벨 approved 없음'
fx rejected;             expect "4 rejected 라벨 → REJECT" 1 '^REJECT #12 .*라벨 rejected 있음'
fx needsreply;           expect "5 needs-reply 라벨 → REJECT" 1 '^REJECT #12 .*라벨 needs-reply 있음'
fx otherauthor;          expect "6 작성자가 byz-tank 아님 → REJECT" 1 '^REJECT #12 .*작성자'
fx emptysec;             expect "7 필수 칸 「제안」 빔 → REJECT" 1 '^REJECT #12 .*「제안」'
fx nosha;                expect "8 근거에 sha 없음 → REJECT" 1 '^REJECT #12 .*sha'
fx b-nocomment;          expect "9 ⓑ 인터뷰 코멘트 없음 → REJECT" 1 '^REJECT #12 .*인터뷰 판정 N'
fx b; ledger "816 오빠 인터뷰(A안 · Issue https://github.com/o/r/issues/120): 다른 Issue"
                         expect "10 ⓑ 원장 줄에 issues/12 없음(issues/120 는 다른 번호) → REJECT" 1 '^REJECT #12 .*issues/12 없음'
ledger "816 오빠 인터뷰(A안 · Issue https://github.com/o/r/issues/12): 채택"
fx; GH_SLOW=1 expect "11 gh 시간 초과(1초 + 재시도 1회) → REJECT" 1 '^REJECT #12 .*시간 초과'
fx; GH_EMPTY=1 expect "12 gh 빈 응답 → REJECT" 1 '^REJECT #12 .*빈 응답'
fx; GH_FAIL=1 expect "12b gh 실패 rc → REJECT" 1 '^REJECT #12 .*rc=1'
n1="$(grep -c 'issue view' "$T/gh.log")"; [ "$n1" -ge 2 ] && ok "재시도 1회 실제로 일어남(issue view ≥ 2회 기록)" || bad "재시도 기록 $n1"
fx nomarker;             expect "13 본문 첫 줄 숨은 표식 없음 → REJECT" 1 '^REJECT #12 .*표식'
fx otheractor;           expect "14 approved 를 단 사람이 오빠·Tank 아님 → REJECT" 1 '^REJECT #12 .*someone'
fx noevent;              expect "15 라벨은 있는데 timeline 에 labeled 이벤트 없음 → REJECT" 1 '^REJECT #12 .*timeline'
fx split;                expect "16 60,000자 초과 분할(근거 칸이 이어서 코멘트에) → OK" 0 '^OK #12 승인 ⓐ$'
# ── H1: 승인 «뒤» 의견·본문 변경에 과거 승인 재사용 금지 ──
fx oppa-late;            expect "17 ★H1★ 승인 뒤 오빠 코멘트(needs-reply 라벨은 없음) → REJECT" 1 '^REJECT #12 .*승인 이후'
fx oppa-nots;            expect "17b ★H1★ 오빠 코멘트 시각 불명 → REJECT(fail-closed)" 1 '^REJECT #12 .*승인 이후'
fx oppa-early;           expect "17c 승인 «전» 오빠 코멘트 → OK(승인 때 본 의견)" 0 '^OK #12 승인 ⓐ$'
fx rev-late;             expect "18 ★H1★ 승인 뒤 Tank 「r1 변경」 코멘트 → REJECT(본문 갱신 뒤 과거 승인)" 1 '^REJECT #12 .*본문 변경'
fx rev-early;            expect "18b 승인 «전» 「r1 변경」 코멘트(재승인 뒤) → OK" 0 '^OK #12 승인 ⓐ$'
# ── H2: 원장 줄의 Issue 는 저장소까지 같아야 한다 ──
fx b; ledger "816 오빠 인터뷰(A안 · Issue https://github.com/other/repo/issues/12): 다른 저장소"
                         expect "19 ★H2★ ⓑ 원장 줄이 다른 저장소 issues/12 → REJECT" 1 '^REJECT #12 .*issues/12 없음'
ledger "816 오빠 인터뷰(A안 · Issue https://evilgithub.com/o/r/issues/12): 가짜 호스트"
                         expect "19b ★H2★ 호스트 접두가 다른 링크(evilgithub.com/o/r) → REJECT" 1 '^REJECT #12 .*issues/12 없음'
ledger "816 오빠 인터뷰(A안 · Issue https://GitHub.com/O/R/issues/12): 대소문자만 다름"
                         expect "19c 저장소 대소문자 무시 → OK" 0 '^OK #12 승인 ⓑ 판정 816$'
ledger "816 오빠 인터뷰(A안 · Issue https://github.com/o/r/issues/12): 채택"

# ── r492: 원장 = ref(origin/main) 트리 · 체크아웃 파일 0(옛 라이브 모사) · 표 행 꼴 ──
V="$T/vrepo"; VO="$T/vorigin.git"; git init -q --bare "$VO"; git init -q "$V"
vg() { git -C "$V" -c user.name=t -c user.email=t@t "$@"; }
vpush() {  # vpush <원장 본문|-(원장 없음)> <TEAMS.md 있음 1|0> — origin/main 에 그 상태를 올리고 체크아웃은 원장 «이전» 커밋으로
  rm -rf "$V/design"; mkdir -p "$V/design"; echo base > "$V/README"; vg add -A >/dev/null; vg commit -q --allow-empty -m base
  [ "$2" = 1 ] && printf '| 팀 | 폴더 | master | 상태 |\n|---|---|---|---|\n| planner | `design/teams/planner/` | x | 현역 |\n' > "$V/design/TEAMS.md"
  [ "$1" != - ] && { mkdir -p "$V/design/teams/planner"; printf '%s\n' "$1" > "$V/design/teams/planner/VERDICTS-planner-1.md"; }
  vg add -A >/dev/null; vg commit -q --allow-empty -m ledger; vg push -q -f "$VO" HEAD:main; vg fetch -q "$VO" "+main:refs/remotes/origin/main"; vg reset -q --hard HEAD~1; }
rexpect() {  # 체크아웃 = 원장 없음 · FT_PLANNER_VERDICTS_DIR 비움 · BYZ_ROOT=임시 리포
  out="$(cd "$T" && env -u FT_PLANNER_VERDICTS_DIR BYZ_ROOT="$V" bash "$GATE" --issue 12 2>&1)"; rc=$?
  if [ "$rc" = "$2" ] && echo "$out" | grep -qE "$3" && [ ! -e "$V/design/teams/planner/VERDICTS-planner-1.md" ]; then ok "$1"; else bad "$1"; fi; }
fx b
vpush "| 816 | 23:0x | (오빠 인터뷰 4) A안 채택 · https://github.com/o/r/issues/12 · 1580b" 1
rexpect "ⓐ ★r492★ origin/main 원장 표 행 + 체크아웃 파일 0 → OK" 0 '^OK #12 승인 ⓑ 판정 816$'
vpush "| 816 | 23:0x | (오빠 인터뷰 4) A안 채택 · https://github.com/o/r/issues/120" 1
rexpect "ⓑ ★r492★ 같은 표 행인데 링크 issues/120 → REJECT" 1 '^REJECT #12 .*ⓑ planner 원장 「816 오빠 인터뷰」 줄에 o/r issues/12 없음'
vpush "816 오빠 인터뷰(A안 · Issue https://github.com/o/r/issues/12): 채택" 1
rexpect "ⓒ ★r492★ 줄머리 꼴도 ref 경유로 OK" 0 '^OK #12 승인 ⓑ 판정 816$'
vpush "816 오빠 인터뷰(A안 · Issue https://github.com/o/r/issues/12): 채택" 0
rexpect "ⓓ ★r492★ origin/main 에 TEAMS.md 없음(ref 못 읽음) → REJECT(후퇴 0)" 1 '^REJECT #12 판정 원장 폴더를 못 풀었다'
vpush - 1
rexpect "ⓓb ★r492★ 명단은 있는데 ref 에 원장 파일 0 → REJECT" 1 '^REJECT #12 판정 원장 폴더를 못 풀었다 .*후보 0개'

# ── B3: --writing-card 경로 정규화(.. 해소) · 심링크 탈출 ──
mkdir -p "$T/cards" "$T/repo/design/harness" "$T/outside" "$T/repo2/design/team" "$T/repo2/idx"; ln -s "$T/outside" "$T/repo2/design/x"; ( cd "$T/repo2" && git init -q . )
wcard() {  # wcard <파일> <구현 범위 본문>
  printf '# 인덱스: t\n- 상태: 대기\n## 구현 범위\n%s\n' "$2" > "$1"; }
wexpect() {  # wexpect <이름> <rc> <구현 범위 본문> [카드 폴더 · 기본 $T/cards · cwd = $T/repo]
  wcard "${4:-$T/cards}/w.md" "$3"; ( cd "$T/repo" && bash "$GATE" --writing-card "${4:-$T/cards}/w.md" ) >/dev/null 2>&1; rc=$?; out="$3"; [ "$rc" = "$2" ] && ok "$1" || bad "$1"; }
wexpect "20 design/ 아래 .md 만 → 면제(rc0)" 0 '`design/harness/PROPOSAL-foo-20261010.md` 를 쓴다'
wexpect "21 ★B3★ design/harness/../../AGENTS.md → rc1(.. 로 design/ 탈출)" 1 '`design/harness/PROPOSAL-foo-20261010.md` 와 `design/harness/../../AGENTS.md`'
wexpect "21b ★B3★ ../AGENTS.md → rc1" 1 '`design/harness/PROPOSAL-foo-20261010.md` 와 `../AGENTS.md`'
wexpect "21c design/harness/../harness/PROPOSAL-foo-20261010.md(.. 해소 뒤에도 design/ 안) → rc0" 0 '`design/harness/../harness/PROPOSAL-foo-20261010.md`'
wexpect "21d ★B3★ design/..  만 → rc1" 1 '`design/..` 정리'
wexpect "22 읽기 예외: evidence 폴더·proposal_template.md 와 함께 → rc0" 0 '`design/harness/PROPOSAL-foo-20261010.md` · 읽기 `design/harness/evidence/proposal-foo/` · `docs/rules/proposal_template.md`'
wexpect "22b ★B3★ evidence 폴더 뒤 .. 로 탈출(evidence/proposal-x/../../../AGENTS.md) → rc1" 1 '`design/harness/PROPOSAL-foo-20261010.md` · `design/harness/evidence/proposal-x/../../../AGENTS.md`'
wexpect "22c ★B3★ docs/rules/../ops.md → rc1(템플릿 예외 아님)" 1 '`design/harness/PROPOSAL-foo-20261010.md` · `docs/rules/../ops.md`'
wexpect "23 ★B3★ 심링크 design/x → 리포 밖 · design/x/PROPOSAL-a-20261010.md → rc1" 1 '`design/x/PROPOSAL-a-20261010.md`' "$T/repo2/idx"
wexpect "23b 카드가 있는 git toplevel(repo2) 기준 정상 경로 → rc0(cwd=repo 와 달라도)" 0 '`design/team/PROPOSAL-a-20261010.md`' "$T/repo2/idx"
out="$(bash "$GATE" 2>&1)"; rc=$?; [ "$rc" = 2 ] && ok "usage → rc 2" || bad "usage"
out="$(bash "$GATE" --issue abc 2>&1)"; rc=$?; [ "$rc" = 2 ] && ok "번호 아님 → rc 2" || bad "번호 아님"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
