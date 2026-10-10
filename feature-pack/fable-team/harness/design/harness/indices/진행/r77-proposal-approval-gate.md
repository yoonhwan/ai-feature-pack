# 인덱스: 제안서→구현 «오빠가 본 승인» 게이트 구조 강제 (R77 · 판정 811·814 · 816 A안 → 826 ①Issue 흡수)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R77(판정 811·814 · master#25 발주 #71347 · 근거 #71355)
- 상태: 진행
- 선행: 없음(오빠 채택 판정 816 · VERDICTS-planner-21-20261010.md 816 줄 · 슬랙 p1791590226702839)
- 시험 입력: 임시 git 리포 + 가짜 발행 장부 JSON + 가짜 planner 판정 원장 폴더 + 가짜 Tank(`FT_TANK_CMD`) + 훅 stdin JSON — 실 슬랙·실 gh·실 tmux 0
- 기준값: 지금 `ft-nano-spawn.sh`·`ft-gh-as-tank.sh create`·`ft-index-lint.sh` 에 제안서 검사 0 · 인터뷰 훅 0
- 제안서: design/harness/PROPOSAL-proposal-approval-gate-20261010.md

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
골의 축: B 「메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의」 + C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행(슬랙) 수신해 반영」. 판정 811·814 · 오빠 「컨펌 전 Issue·코드 0」 규칙의 강제화.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
loom 제안서들이 오빠가 원문을 본 적 없이 구현됐다(planner 대조: 판정 520·548·552 원장 줄 0 · 745 원문 미제시). 나노 spawn·Tank Issue create·planner 인터뷰 세 곳 모두 승인 검사가 없고, 10-08 흐름 설계가 raw 경로 강제를 «완성 후·선언»으로 미뤘다. 오빠가 A안을 채택했다(판정 816): 승인 증거 3개(①제안서 머리줄 `- 상태: 승인 — 판정 N` ②슬랙 발행 장부에 그 제안서 rN `done` ③planner 판정 원장에 `N 오빠 인터뷰` 줄이 있고 그 줄에 ②의 스레드 링크)가 서로 맞을 때만 나노 spawn·Tank Issue create·인터뷰 세 곳을 통과시킨다. 검사는 새 도구 `ft-proposal-gate.sh` 하나가 하고 세 곳이 그것을 부른다. ★r1(판정 826): 오빠가 «제안서를 처음부터 Tank Issue 로 · 본문 탑재 · approved 라벨 · needs-reply 차단 · loom 7건 사후 Issue» 를 채택해 증거 3개는 Issue 하나로 대체됐다 — 아래 «구현 범위 r1» 이 정본이고 위 증거 3개 설명은 옛 판(A안) 기록이다.★

## 사전검증
- 소환: 예 — 구현 뒤 최종판정 DA(da-codex#1 · master 발주 #71387 순서 «R75 뒤») 1회. 사전 설계는 오빠 채택 판정 816 의 제안서 §2 를 그대로 옮긴다.

## 조사 근거
- `scripts/harness-install/fable-team/bin/ft-nano-spawn.sh:73`~`:74` ① lint 호출(여기 바로 뒤에 게이트) · `scripts/harness-install/fable-team/bin/ft-gh-as-tank.sh:49`~`:51` `create <제목> <본문파일>` · `scripts/harness-install/fable-team/bin/ft-index-lint.sh:22` `SECTIONS` · `:89` 절 검사.
- `scripts/harness-install/proposal/ft-proposal-register.sh:4` 머리줄 확인(①만 검사) · `scripts/harness-install/slack-mirror/byz_proposal_publish.py:59`~`:76` 키 = `<제안서 부모 폴더 이름>/<slug>` · 발행 장부 `~/.hermes/state/byz_proposal_publish.json` 모양 `{key: {root_ts, revs: {rN: {phase, ts, md_hash}}}}`.
- planner 판정 원장 줄 모양: `816 오빠 인터뷰(… · 슬랙 https://openclaw-bott.slack.com/archives/C0C6MJGRR89/p1791590226702839): …` (`.worktrees/v6-realtime-live/design/planner/VERDICTS-planner-21-20261010.md:17`).

## 구현 범위 r1 (판정 826 ①흡수 · 같은 브랜치 `nano/r77-proposal-approval-gate` eea86632f6 위에 이어서 · 816 A안 부분은 아래 «살림·바꿈·뺌» 대로)
정본 = 제안 GitHub Issue 하나. 승인 증거 = 그 Issue 의 라벨·작성자·본문 필수 칸·라벨 단 사람. md 머리줄·슬랙 발행 장부는 검사하지 않는다(정보로만 남음).

1. **바꿈 `scripts/harness-install/fable-team/bin/ft-proposal-gate.sh`** (+ 추적 사본 `scripts/fable-team-bin/` 같은 바이트):
   - `--issue <M>`: 읽기 전용 `gh issue view M --json number,author,labels,body,comments` + `gh api repos/{owner}/{repo}/issues/M/timeline`(labeled 이벤트의 actor). 호출마다 `timeout 7` + 재시도 1회(전역 7초 룰). 실패·빈 응답 = REJECT. 시험용 `FT_GH_READ`(가짜 gh) · `GH_REPO`.
   - OK 조건(전부): 라벨 `proposal` + `approved` · `rejected`·`needs-reply` 없음 · 작성자 `byz-tank`(`FT_TANK_LOGIN`) · 본문 첫 줄 숨은 표식 `<!-- byz-proposal-id: <팀>/<slug> -->` · 필수 칸 `## 결론`·`## 오빠가 결정할 것`·`## 배경`·`## 제안`·`## 되돌림`·`## 근거` 가 모두 있고 비어 있지 않음 · `## 근거` 에 7~40자 hex sha 1개 이상.
   - 승인한 사람: 마지막 `approved` labeled 이벤트의 actor 가 ⓐ오빠 계정(`FT_OPPA_GH_LOGINS` · 기본 `yoonhwan`)이면 OK. ⓑ`byz-tank` 면 byz-tank 코멘트 `[인터뷰 판정 N]` 이 있고, planner 원장(`FT_PLANNER_VERDICTS_DIR`)의 `^N 오빠 인터뷰` 줄에 `issues/M` 이 들어 있어야 OK. 출력 `OK #M 승인 ⓐ` 또는 `OK #M 승인 ⓑ 판정 N`.
   - `--card <카드>`: 머리 `- 제안서: #M` → `--issue M`. 값이 `없음 — <사유>` 인데 본문이 `PROPOSAL-*.md` 를 인용하거나, 머리 `- Issue:` 가 `proposal` 라벨 Issue 를 가리키면 REJECT(우회 차단 · 라벨 확인은 gh 읽기).
   - ★DA 2차 B3 필수 교정★: `proposal-` 카드(제안서 작성 카드) 면제는 «구현 범위가 인용한 경로가 1개 이상이고 전부 `design/` 아래 `.md`» 일 때만. 경로 0개면 REJECT. `scripts/`·`docs/`·코드 경로가 하나라도 있으면 REJECT.
   - 뺌: 제안서 파일 모드(md 머리줄 ①)·발행 장부 ②·`--body` 모드.
2. **살림 `ft-nano-spawn.sh` 배선**: `①-0` 두 줄 그대로(`--card`).
3. **뺌 `ft-gh-as-tank.sh` create 게이트**: origin/main 판으로 되돌린다(제안 Issue 를 여는 것이 흐름의 시작이라 막으면 안 됨).
4. **바꿈 `ft-index-lint.sh` `- 제안서:` 줄**: 값 = `#<숫자>` 또는 `없음 — <사유 1자 이상>`. 경로 값은 새 카드에서 REJECT, 옛 카드(첫 추가 2026-10-11 전)는 WARN. 새/옛 판별은 지금 구현 그대로.
5. **새 `scripts/harness-install/proposal/ft-proposal-open.sh <제안서.md> [--apply] [--revision rN]`**: md 를 1회 읽어 필수 칸 6개(위 1과 같은 이름)를 확인한다. 하나라도 비면 Tank 호출 0 + rc 1. 본문 = 숨은 표식 + md 전문(링크만 0 · 60,000자 넘으면 나머지는 코멘트로 — `proposal_register_lib.py` 의 본문 생성·분할·원격 같은 ID 채택 로직 재사용). Tank `create` → `label --add proposal`. 출력 `OPENED #M`. `--revision rN` = Tank `edit --body-file`(래퍼가 옛 본문 보관) + `rN 변경` 코멘트.
6. **바꿈 `ft-proposal-register.sh` → 새 `scripts/harness-install/proposal/ft-proposal-approve.sh <M> --verdict N --interview <파일> [--approve] [--clear-needs-reply] [--apply]`**: planner 원장 `^N 오빠 인터뷰` 줄에 `issues/M` 이 없으면 Tank 호출 0 + rc 1. 있으면 Tank 코멘트 `[인터뷰 판정 N]` + 인터뷰 파일 원문(질문·오빠 답·추가 의견). `--approve` 면 이어서 `label --add approved`(`needs-reply` 가 있으면 거부), `--clear-needs-reply` 면 `label --remove needs-reply`. 옛 `ft-proposal-register.sh` 는 «R77 r1: open/approve 를 쓰세요» 를 출력하고 rc 1 로 끝나게 바꾼다(조용한 통과 0).
7. **새 `scripts/harness-install/proposal/ft-proposal-inbox.sh [--apply]`**: 열린 `proposal` Issue 가운데 마지막 코멘트 작성자가 `byz-tank` 가 아닌 것을 찾아 목록을 낸다(`#M · 작성자 · 시각 · 첫 줄`). `--apply` 면 그 Issue 에 Tank `label --add needs-reply`.
8. **바꿈 훅 `proposal-interview-gate.sh`** ★DA 2차 B1 필수 교정★: 적용 범위 = 질문 글이 «제안 Issue 번호»(`제안(서)?\s*(Issue\s*)?#[0-9]+`) 또는 «제안서 경로»(`PROPOSAL-[a-z0-9-]+-[0-9]{8}\.md`)를 인용한 질문만. 그런 질문에 `github.com/[^/]+/[^/]+/issues/[0-9]+` 링크가 없으면 deny. 그 밖(일반 HIL 승인 질문 포함)은 allow. 슬랙 링크는 요구하지 않는다.
9. **바꿈 `scripts/harness-install/slack-mirror/byz_proposal_publish.py`**: `--issue #M` 이 주어지면 뿌리 글 «결론» 줄 위에 `Issue: https://github.com/<repo>/issues/M` 한 줄. R76 이 먼저 랜딩됐으면 그 위에 얹는다(같은 파일 · origin/main 확인 후 rebase).
10. **문서**: `docs/rules/proposal_flow.md` 흐름 표를 r1 단계(제안서 → open → 슬랙 → 인터뷰 → approve → spawn)로 고치고, `docs/rules/proposal_template.md` 에 `## 배경` 칸을 더하고 «Issue 본문 필수 칸 6개»를 적는다.
11. **시험** (기존 3개 파일 갱신 + 새 2개):
   - `tests/harness/test_proposal_gate.sh` — 가짜 gh 로 12건: ⓐ OK · ⓑ OK · approved 없음 · rejected · needs-reply · 작성자 다름 · 필수 칸 빔 · 근거 sha 없음 · ⓑ 인터뷰 코멘트 없음 · ⓑ 원장 줄에 issues/M 없음 · gh 시간 초과 · gh 빈 응답 → 각 REJECT(앞 2건만 OK).
   - `tests/harness/test_proposal_gate_wiring.sh` — spawn `#M` OK/REJECT · `없음`+`PROPOSAL` 인용 REJECT · `없음`+`- Issue:` 가 proposal Issue REJECT(우회) · `proposal-` 카드 design/ 문서만 = 면제 · ★B3 반례: `proposal-` 카드 구현 범위 «미승인 제안서를 구현한다» + `scripts/x.sh`·`docs/ops.md` → REJECT · 경로 0개 → REJECT★ · Tank create 에 PROPOSAL 인용 본문 → 게이트 없이 dry-run 진행(회귀) · 오탐: 본문에 «제안» 낱말만 있는 일반 카드 → 통과.
   - `tests/harness/test_proposal_interview_gate.sh` — Issue 링크 있는 제안 질문 allow · 「제안 Issue #12 승인할까요」 링크 없음 deny · PROPOSAL 경로 + 슬랙 링크만 deny · ★B1 반례: 「[HIL] 제안서 원본 파일 보존 작업을 승인할까요?」 allow★ · 깨진 JSON allow + 로그.
   - 새 `tests/harness/test_proposal_open.sh` — 필수 칸 빔 → Tank 0 · 정상 → create 1 + label 1 · 같은 ID 원격 있음 → create 0(채택) · 60,000자 초과 → 분할 코멘트.
   - 새 `tests/harness/test_proposal_approve_inbox.sh` — 원장 줄 없음 → Tank 0 · `--approve` + needs-reply 있음 → 거부 · 정상 → 코멘트 1 + 라벨 1 · inbox: 마지막 코멘트가 오빠 → 목록 1 + `--apply` 시 needs-reply 라벨 1.
   - 기존 `test_kit_bin_sync.sh`·`test_index_lint.sh`·`test_proposal_register.sh`(옛 진입점 rc 1 기대로 갱신) PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 실 gh 쓰기·실 슬랙·실 tmux · 라이브 `$FT_BIN`·`~/.claude/hooks`·`settings.json` 수정 · loom 사후 Issue 실제 등록(issues master 몫).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 5개 + 기존 3개 rc=0 · `bash -n` · 새·바뀐 파일 200줄 이하(`ft-nano-spawn.sh` 기존 부채 제외 · 이번에 늘리는 줄 0).
- B1·B3 반례 2건은 eea86632f6 판에서 FAIL, 새 판에서 PASS 를 보고서에 적는다(RED→GREEN).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_proposal_gate.sh rc=0 · 이슈: 0` (나머지 시험 결과는 그 위 «검증 보충» 줄).
- 랜딩 뒤 master 집행(카드 밖): 새 범위 최종판정 DA(리뷰 카운트 새로) · 모든 팀 라이브 bin cp · 훅 설치 + `settings.json` PreToolUse `AskUserQuestion` 등록(`.bak` 먼저) · 라벨 `proposal`·`approved`·`needs-reply`·`rejected`·`사후등록` 생성(Tank label-create) · 진행 중 제안서 Issue 열기.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 991160ae970c5e6c85133a2b0eb48baae1484750 (spawn 2026-10-10)
진행 — 판정 826 r1 반송(Issue 흡수 · DA 2차 B1·B3 필수 교정 포함 · arch#26)
- 슬랙: C0C6MJGRR89 1791590226.702839

## 결과
(컨펌·구현 뒤 기록)
- 2026-10-10 09:01 — 대기→진행 · 좌석 byz-harness-nano-r77-proposal-approval-gate#0
