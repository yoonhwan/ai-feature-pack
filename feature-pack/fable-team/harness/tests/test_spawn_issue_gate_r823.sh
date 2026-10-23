#!/usr/bin/env bash
# test_spawn_issue_gate_r823.sh — r823: 대기/ 카드 착수(ft-nano-spawn) = 카드 머리 `- Issue: #N` 이 «열린 깃 이슈» 일 때만 · 판별·면제 0
#   ⓐ Issue 없음 → REJECT(만들기 안내) · 부작용 0 (빨강: 게이트 호출을 뺀 판 = 착수 PLAN)
#   ⓑ OPEN 착수 · CLOSED·없는 이슈·Issue 줄 없음 REJECT   ⓒ gh 실패·시간 초과 = 판정 불가 · ≤15 s · 재시도 = 출력 0 일 때만 1
#   ⓓ 판독 = 머리 Issue 줄 첫 #숫자만 · owner/repo#N REJECT   ⓔ 면제 0(proposal-*·템플릿)   ⓕ --research·--dry-run 대상 아님
#   ⓖ 순서 = lint 뒤 · 부작용 전   ⓘ 변이 7   ⓙ r2: 값 맨 앞 #숫자만 · 링크·주소·owner/repo 꼴 = 꼴 오류(외부 DA r1 반례)
#   ⓚ r3: 시간 상수 7 s(env 조절 0 · 스텁 지연으로 시험) · #012·8자리 = 꼴 오류 · number = JSON 정수 비교(외부 DA r2 반례)
# 실 gh·실 tmux·실 명부 0 — 가짜 gh(FT_GH_READ) · 가짜 tmux/tmuxc · 임시 리포 · spawn 은 디스크 문턱(FT_DISK_FREE_GIB=0)에서 멈춘다(PLAN 뒤 · 부작용 전).
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
REPO="$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
KIT="$REPO/feature-pack/fable-team/harness/kit/fable-team/bin"; TRK="$REPO/feature-pack/fable-team/harness/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:400}";; *) ok "$3";; esac; }

# 가짜 gh — 번호별 응답 · 호출마다 1줄 기록(인자 그대로)
cat > "$T/gh" <<'SH'
#!/bin/bash
echo "$*" >> "$GHLOG"
n="$3"
case "$n" in
  7)  echo "{\"number\":7,\"state\":\"OPEN\",\"url\":\"https://github.com/t/r/issues/7\"}";;
  8)  echo "{\"number\":8,\"state\":\"CLOSED\",\"url\":\"https://github.com/t/r/issues/8\"}";;
  9)  echo "GraphQL: Could not resolve to an issue or pull request with the number of 9. (repository.issue)" >&2; exit 1;;
  10) trap '' TERM; sleep 8; echo "{\"number\":10,\"state\":\"OPEN\",\"url\":\"https://github.com/t/r/issues/10\"}";;
  11) exit 1;;
  12|012) echo "{\"number\":12,\"state\":\"OPEN\",\"url\":\"https://github.com/t/r/issues/12\"}";;   # 실 gh 처럼 012 도 #12 로 답함
  21) printf '{"number":21,"sta'; exit 0;;
  13) echo "HTTP 502: Bad Gateway" >&2; exit 1;;
  14) exit 0;;
  15) echo "{\"number\":15,\"state\":\"OPEN\",\"url\":\"https://github.com/t/r/pull/15\"}";;
  16) trap '' TERM; sleep 7.5; echo "{\"number\":16,\"state\":\"OPEN\",\"url\":\"https://github.com/t/r/issues/16\"}";;
  17) sleep 0.1; echo "{\"number\":17,\"state\":\"OPEN\",\"url\":\"https://github.com/t/r/issues/17\"}";;
  18) echo "{\"number\":\"18\",\"state\":\"OPEN\",\"url\":\"https://github.com/t/r/issues/18\"}";;
  19) echo "{\"number\":19.0,\"state\":\"OPEN\",\"url\":\"https://github.com/t/r/issues/19\"}";;
  20) echo "{\"state\":\"OPEN\",\"url\":\"https://github.com/t/r/issues/20\"}";;
esac
SH
chmod 755 "$T/gh"
export GHLOG="$T/ghlog" FT_GH_READ="$T/gh" GH_REPO="t/r"
calls() { cat "$GHLOG" 2>/dev/null | grep -c .; }

# 임시 bin = spawn 원본 + 이 게이트 원본 + 가짜(이 카드 소관 아닌 문지기들)
B="$T/bin"; mkdir -p "$B" "$T/fake"
cp "$KIT/ft-nano-spawn.sh" "$KIT/ft-spawn-issue-gate.sh" "$KIT/ft_teamset.py" "$KIT/ft_spawn_queue.py" "$B/"
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/bin_source_deps.sh"; copy_source_deps "$KIT" "$B" || bad "사본 source 대상 채우기"
printf '#!/bin/bash\nexit "${FAKE_LINT_RC:-0}"\n' > "$B/ft-index-lint.sh"
printf '#!/bin/bash\necho "OK 제안서 없음 선언(stub)"\n' > "$B/ft-proposal-gate.sh"
for s in ft-resource-gate.sh ft-all-stop.sh; do printf '#!/bin/bash\nexit 0\n' > "$B/$s"; done
printf '#!/bin/bash\necho "SENT stub"\n' > "$B/ft-send-verified.sh"; printf '#!/bin/bash\necho READY\n' > "$B/ft-agent-ready.sh"
printf '#!/usr/bin/env python3\nimport sys\nsys.exit(1)\n' > "$B/ft_raised.py"
printf 'ft_team_has_ref() { return 1; }\nft_card_location_ok() { return 0; }\nft_index_twin() { return 1; }\n' > "$B/ft-team-lib.sh"
printf '#!/bin/bash\ncase "$1" in has-session) exit 1;; list-sessions) exit 0;; *) exit 0;; esac\n' > "$T/fake/tmux"
printf '#!/bin/bash\necho "TMUXC $*"\n' > "$T/fake/tmuxc"
chmod 755 "$B"/* "$T/fake"/*

R="$T/repo"; mkdir -p "$R/.fable-team/state" "$R/.fable-team/comm" "$R/design/harness/indices/대기" "$R/design/harness/indices/진행"
git init -q -b main "$R"; git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
printf '{"_parent":null}\n' > "$R/.fable-team/seats.json"
HEAD40="$(git -C "$R" rev-parse HEAD)"
card() { # <이름> <머리 Issue 줄(빈 = 줄 없음)> [폴더] [본문 추가] → 경로
  local p="$R/design/harness/indices/${3:-대기}/$1.md"
  { echo "# 인덱스: $1"; [ -z "$2" ] || echo "$2"; echo "- 상태: 대기"; echo; echo "## 구현 범위"; echo "1. x"; [ -z "${4:-}" ] || echo "$4"
    echo; echo "## 상태"; echo "- base_sha: $HEAD40 (spawn 시험)"; } > "$p"; echo "$p"; }
spawn() { # <bin> <카드> [인자…]
  local b="$1" c="$2"; shift 2
  ( cd "$R" && PATH="$T/fake:$PATH" FT_SEATS_JSON="$R/.fable-team/seats.json" FT_NANO_PREFIX=byz-harness-nano- FT_TEAMSET=0 \
    FT_DISK_FREE_GIB=0 bash "$b/ft-nano-spawn.sh" "$c" --from dispatch "$@" 2>&1 ); }
G="$B/ft-spawn-issue-gate.sh"
wts() { git -C "$R" worktree list | grep -c .; }

echo "== ⓐ Issue 없음 → REJECT · 부작용 0 (빨강 = 게이트 호출 뺀 판은 착수)"
C="$(card a '- Issue: 없음 → master 150649(오빠 발주 1/5)')"; before="$(shasum "$C")"; : > "$GHLOG"
o="$(spawn "$B" "$C")"; rc=$?
[ "$rc" = 1 ] && has "$o" "REJECT 착수 = 열린 깃 이슈 번호 필수" "ⓐ 새 판 REJECT rc1" || bad "ⓐ rc=$rc ← $o"
has "$o" "ft-issue-create-pair.sh" "ⓐ 만들기 안내(ft-issue-create-pair.sh → 「- Issue: #N」)"
hasnt "$o" "PLAN seat=" "ⓐ 착수 PLAN 0"
[ "$before" = "$(shasum "$C")" ] && [ -f "$C" ] && ok "ⓐ 카드 바이트 그대로 · 대기/ 그대로(①b base_sha 갱신 전에 막힘)" || bad "ⓐ 카드 바뀜·이동"
[ "$(wts)" = 1 ] && [ "$(calls)" = 0 ] && ok "ⓐ 워크트리 0 · gh 호출 0(번호 없으면 조회 안 함)" || bad "ⓐ wt=$(wts) calls=$(calls)"
O="$T/old"; mkdir -p "$O"; cp -p "$B"/* "$O/"; grep -v 'ft-spawn-issue-gate.sh" "$IDX"' "$B/ft-nano-spawn.sh" > "$O/ft-nano-spawn.sh"
o="$(spawn "$O" "$C")"; has "$o" "PLAN seat=" "ⓐ 빨강: 게이트 호출 뺀 판(= 지금 판) 은 같은 카드를 착수(PLAN) — ⓘ 변이 1 도 이것"
card a '- Issue: 없음 → master 150649(오빠 발주 1/5)' >/dev/null

echo "== ⓑ OPEN 착수 · CLOSED·없는 이슈·줄 없음 REJECT"
o="$(spawn "$B" "$(card b7 '- Issue: #7')")"; has "$o" "OK #7 열린 이슈" "ⓑ #7 OPEN → OK"; has "$o" "PLAN seat=" "ⓑ #7 OPEN → 착수(PLAN)"
grep -q -- 'issue view 7 --repo t/r --json' "$GHLOG" && ok "ⓑ 조회 = gh issue view 7 --repo \$GH_REPO" || bad "ⓑ 조회 인자 ← $(cat "$GHLOG")"
o="$(spawn "$B" "$(card b8 '- Issue: #8')")"; has "$o" "REJECT 닫힌 이슈 #8" "ⓑ CLOSED → REJECT 닫힌 이슈"; hasnt "$o" "PLAN seat=" "ⓑ CLOSED → PLAN 0"
o="$(spawn "$B" "$(card b9 '- Issue: #9')")"; has "$o" "REJECT 없는 이슈 #9" "ⓑ 없는 이슈 → REJECT"; hasnt "$o" "PLAN seat=" "ⓑ 없는 이슈 → PLAN 0"
o="$(spawn "$B" "$(card bn '')")"; has "$o" "「- Issue:」 줄 없음" "ⓑ Issue 줄 없음 → REJECT"; hasnt "$o" "PLAN seat=" "ⓑ 줄 없음 → PLAN 0"
o="$(bash "$G" "$(card b15 '- Issue: #15')")"; [ $? = 1 ] && has "$o" "이슈 아님" "ⓑ 번호가 PR(url /pull/) → REJECT" || bad "ⓑ PR 번호 ← $o"

echo "== ⓒ gh 실패·시간 초과 = 판정 불가 · ≤15 s · 재시도 = 출력 0 일 때만"
: > "$GHLOG"; S=$SECONDS; o="$(bash "$G" "$(card c10 '- Issue: #10')")"; rc=$?; el=$((SECONDS - S))
[ "$rc" = 1 ] && has "$o" "REJECT 판정 불가(통과 0)" "ⓒ TERM 무시 8 s 스텁 → REJECT 판정 불가" || bad "ⓒ timeout rc=$rc ← $o"
[ "$el" -le 15 ] && ok "ⓒ 경과 ≤ 15 s ($el s · KILL 7 × 2)" || bad "ⓒ 경과 $el s"
[ "$(calls)" = 2 ] && ok "ⓒ 시간 초과(출력 0) → 재시도 1(호출 2)" || bad "ⓒ 호출 $(calls)"
for n in 11 14; do : > "$GHLOG"; o="$(bash "$G" "$(card c$n "- Issue: #$n")")"; rc=$?
  [ "$rc" = 1 ] && has "$o" "판정 불가" "ⓒ #$n 출력 0(rc=$([ $n = 11 ] && echo 1 || echo 0)) → REJECT" || bad "ⓒ #$n rc=$rc ← $o"
  [ "$(calls)" = 2 ] && ok "ⓒ #$n 출력 0 → 재시도 1(호출 2)" || bad "ⓒ #$n 호출 $(calls)"; done
for n in 21 13; do : > "$GHLOG"; o="$(bash "$G" "$(card c$n "- Issue: #$n")")"; rc=$?
  [ "$rc" = 1 ] && has "$o" "판정 불가" "ⓒ #$n 출력 있음(불완전 JSON·rc≠0) → REJECT" || bad "ⓒ #$n rc=$rc ← $o"
  [ "$(calls)" = 1 ] && ok "ⓒ #$n 출력 있음 → 재시도 0(호출 1)" || bad "ⓒ #$n 호출 $(calls)"; done
o="$(spawn "$B" "$(card c13s '- Issue: #13')")"; hasnt "$o" "PLAN seat=" "ⓒ spawn 경유 gh 실패 → PLAN 0(통과로 읽지 않음)"

echo "== ⓓ 판독 = 머리 Issue 줄 첫 #숫자만 · owner/repo#N REJECT"
o="$(bash "$G" "$(card d1 '- Issue: #7 (관련 #8)')")"; [ $? = 0 ] && has "$o" "OK #7" "ⓓ 첫 #7 만(뒤 #8 무시)" || bad "ⓓ1 ← $o"
o="$(bash "$G" "$(card d2 '- Issue: #8 (관련 #7)')")"; [ $? = 1 ] && has "$o" "닫힌 이슈 #8" "ⓓ 첫 #8 만(뒤 #7 로 통과 0)" || bad "ⓓ2 ← $o"
o="$(bash "$G" "$(card d3 '- Issue: 없음' 대기 '- Issue: #7 · 본문 #7')")"; [ $? = 1 ] && has "$o" "Issue 줄 꼴 오류" "ⓓ 본문(## 뒤) #7 무시 → REJECT" || bad "ⓓ3 ← $o"
o="$(bash "$G" "$(card d4 '- Issue: other/repo#7')")"; [ $? = 1 ] && has "$o" "Issue 줄 꼴 오류" "ⓓ owner/repo#N → REJECT 꼴 오류" || bad "ⓓ4 ← $o"
o="$(bash "$G" "$(card d5 '- Issue: (#7) 오빠 발주')")"; [ $? = 1 ] && has "$o" "Issue 줄 꼴 오류" "ⓓ r2: 괄호 (#7) = 맨 앞 #숫자 아님 → REJECT" || bad "ⓓ5 ← $o"

echo "== ⓙ r2 — 값 맨 앞 «#숫자» 만 · 링크·주소·owner/repo 꼴 = 꼴 오류 · gh 호출 0 · 부작용 0 (외부 DA r1 반례)"
for v in '[#7](https://github.com/other/repo/issues/7)' '[#7](https://github.com/other/repo/pull/7)'; do
  C="$(card j1 "- Issue: $v")"; before="$(shasum "$C")"; : > "$GHLOG"; o="$(spawn "$B" "$C")"; rc=$?
  [ "$rc" = 1 ] && has "$o" "Issue 줄 꼴 오류" "ⓙ DA 반례 ${v:0:44} → spawn REJECT 꼴 오류" || bad "ⓙ $v rc=$rc ← $o"
  hasnt "$o" "PLAN seat=" "ⓙ DA 반례 → PLAN 0"
  [ "$(calls)" = 0 ] && [ "$(wts)" = 1 ] && [ "$before" = "$(shasum "$C")" ] && ok "ⓙ DA 반례 → gh 호출 0 · 워크트리 0 · 카드 그대로" || bad "ⓙ 부작용 calls=$(calls) wt=$(wts)"; done
for v in 'https://github.com/t/r/issues/7' '#7a' 'GH-7' '없음 → master 150649'; do
  : > "$GHLOG"; o="$(bash "$G" "$(card j2 "- Issue: $v")")"; rc=$?
  [ "$rc" = 1 ] && has "$o" "Issue 줄 꼴 오류" "ⓙ «${v}» → REJECT 꼴 오류" || bad "ⓙ «${v}» rc=$rc ← $o"
  [ "$(calls)" = 0 ] && ok "ⓙ «${v}» → gh 호출 0" || bad "ⓙ «${v}» 호출 $(calls)"; done
o="$(bash "$G" "$(card j3 '- Issue: #7 · 설명 [링크](https://github.com/other/repo/issues/9)')")"; [ $? = 0 ] && has "$o" "OK #7" "ⓙ «#7 · 설명 [링크](…)» → 맨 앞 #7 통과(스텁 OPEN)" || bad "ⓙ j3 ← $o"
o="$(bash "$G" "$(card j4 '-   Issue:    #7')")"; [ $? = 0 ] && ok "ⓙ 콜론 뒤 앞 공백 깎고 #7 통과" || bad "ⓙ j4 ← $o"

echo "== ⓚ r3 — 시간 상수 7 s(env 조절 0) · 번호 0 시작·8자리 = 꼴 오류 · number = JSON 정수 비교 (외부 DA r2 반례)"
for e in 0 9; do : > "$GHLOG"; S=$SECONDS; o="$(FT_SPAWN_ISSUE_TIMEOUT=$e bash "$G" "$(card k1 '- Issue: #16')")"; rc=$?; el=$((SECONDS - S))
  [ "$rc" = 1 ] && has "$o" "판정 불가" "ⓚ DA r2 반례①: FT_SPAWN_ISSUE_TIMEOUT=$e 줘도 7.5 s 스텁 → REJECT 판정 불가" || bad "ⓚ env=$e rc=$rc ← $o"
  [ "$el" -le 15 ] && [ "$(calls)" = 2 ] && ok "ⓚ env=$e 경과 ≤ 15 s ($el s · 7 s KILL × 2)" || bad "ⓚ env=$e 경과 $el s 호출 $(calls)"; done
o="$(bash "$G" "$(card k2 '- Issue: #17')")"; [ $? = 0 ] && has "$o" "OK #17" "ⓚ 0.1 s 스텁 → 통과(상한 안)" || bad "ⓚ 0.1 s ← $o"
: > "$GHLOG"; o="$(bash "$G" "$(card k3 '- Issue: #012 · 설명')")"; [ $? = 1 ] && has "$o" "Issue 줄 꼴 오류" "ⓚ DA r2 반례②: #012 → REJECT 꼴 오류" || bad "ⓚ #012 ← $o"
[ "$(calls)" = 0 ] && ok "ⓚ #012 → gh 호출 0" || bad "ⓚ #012 호출 $(calls)"
o="$(bash "$G" "$(card k4 '- Issue: #12 · 설명')")"; [ $? = 0 ] && has "$o" "OK #12" "ⓚ #12 · 설명 + number=12 → 통과(회귀)" || bad "ⓚ #12 ← $o"
: > "$GHLOG"; o="$(bash "$G" "$(card k5 '- Issue: #12345678')")"; [ $? = 1 ] && has "$o" "Issue 줄 꼴 오류" "ⓚ 8자리 → 꼴 오류" || bad "ⓚ 8자리 ← $o"
[ "$(calls)" = 0 ] && ok "ⓚ 8자리 → gh 호출 0" || bad "ⓚ 8자리 호출 $(calls)"
for n in 18 19 20; do o="$(bash "$G" "$(card k$n "- Issue: #$n")")"; rc=$?
  [ "$rc" = 1 ] && has "$o" "판정 불가" "ⓚ gh number $([ $n = 18 ] && echo '"18"(문자열)' || { [ $n = 19 ] && echo '19.0' || echo '누락'; }) → REJECT 판정 불가" || bad "ⓚ #$n rc=$rc ← $o"; done

echo "== ⓔ 면제 0"
o="$(spawn "$B" "$(card proposal-x '- Issue: 없음 — 제안서 작성 카드')")"; has "$o" "REJECT 착수 = 열린 깃 이슈" "ⓔ proposal-* 카드도 REJECT"; hasnt "$o" "PLAN seat=" "ⓔ proposal-* PLAN 0"
o="$(spawn "$B" "$(card tpl $'- 템플릿: 빈 카드(나노가 채움)\n- Issue: 없음')")"; has "$o" "REJECT 착수 = 열린 깃 이슈" "ⓔ 템플릿 카드도 REJECT"

echo "== ⓕ --research(진행/ 부모)·--dry-run = 대상 아님"
: > "$GHLOG"; o="$(spawn "$B" "$C" --dry-run)"; has "$o" "PLAN seat=" "ⓕ --dry-run 은 Issue 없음 카드도 PLAN(동작 그대로)"; hasnt "$o" "열린 깃 이슈" "ⓕ --dry-run 게이트 0"
o="$(spawn "$B" "$(card rs '- Issue: 없음' 진행)" --research)"; has "$o" "PLAN seat=" "ⓕ --research 진행/ 카드 PLAN(동작 그대로)"; hasnt "$o" "열린 깃 이슈" "ⓕ --research 게이트 0"
[ "$(calls)" = 0 ] && ok "ⓕ gh 호출 0" || bad "ⓕ 호출 $(calls)"

echo "== ⓖ 순서 = ① lint 뒤 · 부작용 전"
ln() { grep -n -F -- "$1" "$KIT/ft-nano-spawn.sh" | head -1 | cut -d: -f1; }
l_lint="$(ln 'ft-index-lint.sh" "$IDX"')"; l_g="$(ln 'ft-spawn-issue-gate.sh" "$IDX"')"; l_renew="$(ln 'python3 - "$IDX" "$CUR_HEAD"')"; l_wt="$(ln 'worktree add "$WTDIR"')"
[ -n "$l_g" ] && [ "$l_lint" -lt "$l_g" ] && [ "$l_g" -lt "$l_renew" ] && [ "$l_renew" -lt "$l_wt" ] && ok "ⓖ lint($l_lint) < 게이트($l_g) < 첫 카드 쓰기($l_renew) < 워크트리($l_wt)" || bad "ⓖ 줄 lint=$l_lint g=$l_g renew=$l_renew wt=$l_wt"
: > "$GHLOG"; o="$(FAKE_LINT_RC=1 spawn "$B" "$(card g1 '- Issue: #7')")"; has "$o" "REJECT lint 실패" "ⓖ lint 실패 → lint REJECT 가 먼저"
[ "$(calls)" = 0 ] && ok "ⓖ lint 실패면 gh 호출 0(게이트는 lint 뒤)" || bad "ⓖ 호출 $(calls)"

echo "== ⓘ 변이 — 열림 확인 삭제 → CLOSED 통과 · 출력 확인 삭제 → 출력 있는 실패도 재시도"
M="$T/mut"; mkdir -p "$M"; sed 's/^  OPEN) echo/  OPEN|CLOSED) echo/' "$G" > "$M/g2.sh"; grep -v '&& break' "$G" > "$M/g3.sh"
cmp -s "$G" "$M/g2.sh" && bad "ⓘ 변이 2 가 안 걸림(sed 무효)" || { o="$(bash "$M/g2.sh" "$(card m2 '- Issue: #8')")"; [ $? = 0 ] && ok "ⓘ 변이 2(열림 확인 삭제) → CLOSED 통과 = ⓑ CLOSED 단언 FAIL 로 잡힌다" || bad "ⓘ 변이 2 rc ← $o"; }
cmp -s "$G" "$M/g3.sh" && bad "ⓘ 변이 3 이 안 걸림" || { : > "$GHLOG"; bash "$M/g3.sh" "$(card m3 '- Issue: #21')" >/dev/null; [ "$(calls)" = 2 ] && ok "ⓘ 변이 3(출력 확인 삭제) → 불완전 JSON 재시도(호출 2) = ⓒ 단언 FAIL 로 잡힌다" || bad "ⓘ 변이 3 호출 $(calls)"; }
sed "s/^RE=.*/RE='#([0-9]+)'/" "$G" > "$M/g4.sh"   # r2 변이: «맨 앞 #숫자» → «첫 #숫자 아무 데나»
cmp -s "$G" "$M/g4.sh" && bad "ⓘ 변이 4 가 안 걸림(sed 무효)" || { o="$(bash "$M/g4.sh" "$(card m4 '- Issue: [#7](https://github.com/other/repo/issues/7)')")"; [ $? = 0 ] && ok "ⓘ 변이 4(맨 앞 검사 → 아무 데나) → DA 반례 통과 = ⓙ 단언 FAIL 로 잡힌다(빨강)" || bad "ⓘ 변이 4 rc ← $o"; }
sed 's/^LIM=7$/LIM="${FT_SPAWN_ISSUE_TIMEOUT:-7}"/' "$G" > "$M/g5.sh"   # r3 변이: env 시간 읽기 되살림
cmp -s "$G" "$M/g5.sh" && bad "ⓘ 변이 5 가 안 걸림(sed 무효)" || { o="$(FT_SPAWN_ISSUE_TIMEOUT=9 bash "$M/g5.sh" "$(card m5 '- Issue: #16')")"; [ $? = 0 ] && ok "ⓘ 변이 5(env 시간 되살림) → env=9 에 7.5 s 스텁 통과 = ⓚ 반례① 단언 FAIL 로 잡힌다(빨강)" || bad "ⓘ 변이 5 rc ← $o"; }
sed 's/^ok = type(num) is int and num == int(sys.argv\[1\])$/ok = str(num) == sys.argv[1]/' "$G" > "$M/g6.sh"   # r3 변이: 정수 비교 → 글자 비교
cmp -s "$G" "$M/g6.sh" && bad "ⓘ 변이 6 이 안 걸림(sed 무효)" || { o="$(bash "$M/g6.sh" "$(card m6 '- Issue: #18')")"; [ $? = 0 ] && ok "ⓘ 변이 6(글자 비교) → number=\"18\" 통과 = ⓚ 문자열 칸 FAIL 로 잡힌다(빨강)" || bad "ⓘ 변이 6 rc ← $o"; }
sed "s/^RE=.*/RE='^#([0-9]{1,7})([[:space:]]|\$)'/" "$G" > "$M/g7.sh"   # r3 변이: 0 시작 검사 삭제
cmp -s "$G" "$M/g7.sh" && bad "ⓘ 변이 7 이 안 걸림(sed 무효)" || { o="$(bash "$M/g7.sh" "$(card m7 '- Issue: #012 · 설명')")"; [ $? = 0 ] && ok "ⓘ 변이 7(0 시작 검사 삭제) → #012 통과 = ⓚ 반례② 단언 FAIL 로 잡힌다(빨강)" || bad "ⓘ 변이 7 rc ← $o"; }

echo "== 짝 사본 cmp0 · bash -n"
for s in ft-nano-spawn.sh ft-spawn-issue-gate.sh; do bash -n "$KIT/$s" && cmp -s "$KIT/$s" "$TRK/$s" && ok "cmp0 · bash -n $s" || bad "짝 불일치·문법 $s"; done

echo; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED ($fail)"; exit "$fail"
