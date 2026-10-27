#!/usr/bin/env bash
# test_proposal_gate_wiring.sh — 승인 게이트(ft-proposal-gate.sh --card)가 나노 spawn 입구에 걸린 배선 시험(R77 r1 · 판정 826). 가짜 gh·가짜 Tank 만 — 실 gh·실 슬랙·실 tmux 0.
#   (lint 의 `- 제안서:` 줄 시험은 test_index_lint.sh ⑨ — 카드 새/옛 판별에 git 커밋 날짜가 필요해 그 시험의 임시 리포를 쓴다.)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_TEAMSET=0   # R351: 팀셋 표는 이 시험의 주제가 아님(임시 리포엔 origin/main 표가 없다) — 표 판정은 test_teamset_gitref.sh·test_nano_spawn_teamset_cap.sh 가 본다
# shellcheck source=_proposal_issue_env.sh
. "$(dirname "${BASH_SOURCE[0]:-$0}")/_proposal_issue_env.sh"
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok   # R218: 자원 문지기 센서를 가짜로(실 머신 부하·압력 무관)
KIT="$HERE/../../harness/kit/fable-team/bin"
for f in "$KIT"/ft-{nano-spawn,proposal-gate,gh-as-tank}.sh; do bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $f"; done

# ── spawn --dry-run: lint 는 항상 통과하는 가짜 · 게이트는 진짜 · gh 는 가짜 ──
. "$HERE/lib/fake_tmm.sh"; fake_tmm "$T/fake" byz-harness-master-claude#1 byz-v65-master-claude#1   # r975 r4: 살아 있는 좌석 목록 대역
mkdir -p "$T/bin" "$T/idx/대기"; cp "$KIT/ft-nano-spawn.sh" "$KIT/ft-proposal-gate.sh" "$KIT/ft-resource-gate.sh" "$KIT/ft_raised.py" "$KIT/ft_teamset.py" "$KIT/ft_spawn_queue.py" "$KIT/ft-team-lib.sh" "$T/bin/"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/ft-index-lint.sh"; echo '{"_master":"byz-harness-master-claude#1","byz-harness-master-claude#1":{"role":"master"}}' > "$T/seats.json"   # r975: 회신 대상 = 명부 _master
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin"/ft-all-stop.sh   # r626 DA⑥ r2: spawn 이 .fable-team 있으면 늘 전팀 정지 check — 사본 bin 에 없으면 REJECT · 이 시험 주제 밖이라 통과 스텁
. "$HERE/lib/bin_source_deps.sh"; copy_source_deps "$KIT" "$T/bin" || bad "r686 사본 source 대상 채우기"   # r686: 고른 도구가 source 하는 같은 폴더 lib(r672 swap · research-seat …)
card() {  # card <파일이름> <머리 제안서 줄|-> [머리 Issue 줄|-] [구현 범위 줄 · 기본 x] [본문 추가 줄]
  { echo "# 인덱스: $1"; [ "${3:--}" = "-" ] && echo "- Issue: 없음" || echo "$3"; echo "- 상태: 대기"; echo "- 선행: 없음"; echo "- 시험 입력: 없음"; echo "- 기준값: 없음 → 대체 축 x"
    [ "$2" = "-" ] || echo "$2"; echo "## 구현 범위"; echo "${4:-x}"; [ -n "${5:-}" ] && echo "$5"; } > "$T/idx/대기/$1.md"; }
spawn() { out="$(cd "$HERE/../.." && PATH="$T/fake:$PATH" FT_SEATS_JSON="$T/seats.json" FT_NANO_PREFIX=zz- bash "$T/bin/ft-nano-spawn.sh" "$T/idx/대기/$1.md" --dry-run 2>&1)"; rc=$?; }
rejected() { [ "$rc" = 1 ] && echo "$out" | grep -q "^REJECT 제안서 승인 증거 부족 — REJECT .*$1" && ! echo "$out" | grep -q '^PLAN '; }   # 워크트리·tmux 0 = PLAN 줄 0
passed() { ! echo "$out" | grep -q 'REJECT 제안서'; }
WR='1. `design/team/PROPOSAL-foo-20261010.md` 제안서 1개만 쓴다 · 읽기 `design/team/GOAL.md`'

reset; fx 12; card c-ok "- 제안서: #12"; spawn c-ok
echo "$out" | grep -q '^OK #12 승인 ⓐ$' && passed && ok "1 spawn: 「- 제안서: #12」 승인된 제안 Issue → 통과(OK #12 승인 ⓐ)" || bad "1 rc=$rc $out"
reset; fx 12 noapproved; card c-noapp "- 제안서: #12"; spawn c-noapp
rejected '#12 .*approved' && ok "2 spawn: approved 없는 제안 Issue → REJECT rc=1 · PLAN 0" || bad "2 rc=$rc $out"
reset; card c-bypass "- 제안서: 없음 — 급해서" - 'x' "참고: design/team/PROPOSAL-foo-20261010.md 를 구현한다"; spawn c-bypass
rejected 'PROPOSAL-foo-20261010.md 를 인용' && ok "3 spawn: 「없음」 + PROPOSAL 인용 → REJECT(우회 차단)" || bad "3 rc=$rc $out"
reset; fx 12; card c-issue "- 제안서: 없음 — 이슈로 진행" "- Issue: #12"; spawn c-issue
rejected 'proposal 라벨 Issue' && ok "4 spawn: 「없음」 + 「- Issue: #12」(proposal 라벨 Issue) → REJECT(우회 차단)" || bad "4 rc=$rc $out"
reset; printf '{"number":30,"author":{"login":"yoonhwan"},"labels":[{"name":"bug"}],"body":"x","comments":[]}' > "$T/view-30.json"; card c-plain-issue "- 제안서: 없음 — 버그 수정" "- Issue: #30"; spawn c-plain-issue
passed && ok "5 spawn: 「없음」 + 일반(bug) Issue 연결 → 통과" || bad "5 rc=$rc $out"
reset; card c-ghfail "- 제안서: 없음 — 버그 수정" "- Issue: #30"; out="$(GH_FAIL=1 bash -c ". /dev/null; cd '$HERE/../..' && PATH='$T/fake:$PATH' FT_SEATS_JSON='$T/seats.json' FT_NANO_PREFIX=zz- bash '$T/bin/ft-nano-spawn.sh' '$T/idx/대기/c-ghfail.md' --dry-run" 2>&1)"; rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT 제안서 승인 증거 부족' && ok "6 spawn: 「- Issue:」 라벨 조회 gh 실패 → REJECT(조용한 통과 0)" || bad "6 rc=$rc $out"
reset; card c-path "- 제안서: design/team/PROPOSAL-foo-20261010.md"; spawn c-path
[ "$rc" = 1 ] && echo "$out" | grep -q '^REJECT 제안서 승인 증거 부족 — REJECT 머리 「- 제안서:」 값은 #<제안 Issue 번호>' && ok "7 spawn: 경로 값(옛 r0 방식) → REJECT" || bad "7 rc=$rc $out"
reset; card proposal-x "- 제안서: 없음 — 제안서를 쓰는 카드" - "$WR"; spawn proposal-x
echo "$out" | grep -q '^OK 면제 ' && passed && ok "8 spawn: proposal- 카드 + 구현 범위 design/ 문서만 → 면제" || bad "8 rc=$rc $out"
# ★B3 반례(DA 2차)★ — 이름만 proposal- 인 구현 카드 3종 모두 REJECT
reset; card proposal-nopath "- 제안서: 없음 — 작성 카드" - "미승인 제안서를 구현한다"; spawn proposal-nopath
rejected 'proposal-\* 카드가 제안서 작성 카드 형식이 아니다' && ok "9 ★B3 반례★ proposal- 카드 + 구현 범위 경로 0개 → REJECT" || bad "9 rc=$rc $out"
reset; card proposal-docs "- 제안서: 없음 — 작성 카드" - '미승인 제안서를 구현한다 `docs/ops.md` 수정'; spawn proposal-docs
rejected 'proposal-\* 카드가 제안서 작성 카드 형식이 아니다' && ok "10 ★B3 반례★ proposal- 카드 + docs/ops.md → REJECT" || bad "10 rc=$rc $out"
reset; card proposal-code "- 제안서: 없음 — 작성 카드" - '미승인 제안서를 구현한다 `scripts/x.sh` · `docs/ops.md` 수정'; spawn proposal-code
rejected 'proposal-\* 카드가 제안서 작성 카드 형식이 아니다' && ok "11 ★B3 반례★ proposal- 카드 + scripts/x.sh·docs/ops.md → REJECT" || bad "11 rc=$rc $out"
reset; fx 12; card proposal-impl-ok "- 제안서: #12" - '`scripts/x.sh` 를 수정한다'; spawn proposal-impl-ok
echo "$out" | grep -q '^OK #12 승인 ⓐ$' && ok "12 proposal- 이름 구현 카드라도 승인된 「- 제안서: #M」 이면 통과(이름 면제 아님 · 증거 통과)" || bad "12 rc=$rc $out"
# 오탐: 「제안」 낱말만 있는 일반 카드
reset; card c-word "- 제안서: 없음 — 구조 정리" - "제안 내용을 검토하고 제안서 폴더 이름을 정리한다" "제안 1: 정리"; spawn c-word
passed && ok "13 오탐 회귀: 본문에 「제안」 낱말만 있는 일반 카드 → 통과" || bad "13 rc=$rc $out"

# ── Tank create 는 게이트 없이(r1: 제안 Issue 를 여는 것이 흐름의 시작) — PROPOSAL 인용 본문도 dry-run 진행 ──
printf '제안서 design/team/PROPOSAL-foo-20261010.md 를 Issue 로 연다\n' > "$T/body.md"
# r455a: create 는 ft-issue-create-pair.sh 로 위임 — 그 도구 계약(데이터 루트 comm · 보내는 좌석 · issues 명부)을 임시 값으로 준다
mkdir -p "$T/root/.fable-team/comm"; echo '{"_master":"zz-mgr#0"}' > "$T/seats-issues.json"
out="$(env -u FT_ISSUE_BOT_TOKEN -u FT_MBOX_CMD FT_ROOT="$T/root" FT_ME=zz-test#0 FT_ISSUES_SEATS="$T/seats-issues.json" FT_ISSUE_BOT_TOKEN_FILE=/nonexistent bash "$KIT/ft-gh-as-tank.sh" create "제목" "$T/body.md" 2>&1)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '^DRY as=' && ok "14 Tank create: PROPOSAL 인용 본문 → 게이트 없이 dry-run 진행(회귀)" || bad "14 rc=$rc $out"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/mbox-stub"
out="$(env -u FT_ISSUE_BOT_TOKEN -u FT_ROOT FT_MBOX_CMD="bash $T/mbox-stub" FT_ME=zz-test#0 FT_ISSUES_SEATS="$T/seats-issues.json" FT_ISSUE_BOT_TOKEN_FILE=/nonexistent bash "$KIT/ft-gh-as-tank.sh" create "제목" "$T/body.md" 2>&1)"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '^DRY as=' && ok "14c Tank create: FT_MBOX_CMD 스텁(데이터 루트 없이)도 dry-run 진행" || bad "14c rc=$rc $out"
grep -q 'proposal-gate' "$KIT/ft-gh-as-tank.sh" && bad "14b Tank 래퍼에 게이트 호출이 남아 있다" || ok "14b Tank 래퍼에 게이트 호출 0(origin/main 판)"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
