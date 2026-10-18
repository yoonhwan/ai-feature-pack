# 인덱스: Issue 쓰기를 Tank 봇 이름으로 — gh 래퍼(create·comment·label·close) + 오빠 로그인 직접 호출 가드 + 부팅 문서 금지 줄
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의) · 원문 7. 핵심 한 줄: 좌석이 gh 기본 로그인(오빠 계정)으로 Issue 를 쓰면 «등록자가 오빠»가 되어 누가 올렸는지·사람 vs 좌석 구분이 깨진다 — 모든 Issue 쓰기는 byz-tank 이름으로 나가야 한다. 요청 원문(오빠 10-07 · issues 총괄 쪽지 58342): 「등록자가 왜 나인지 하네스로 보내서 개선」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
Tank 봇(GitHub 계정 `byz-tank`)은 이미 있고, 토큰은 `~/.config/byz-harness/issue-bot.token`(또는 env `FT_ISSUE_BOT_TOKEN`) — 읽는 법은 `scripts/fable-team-bin/ft-issue-create-pair.sh`·`ft-tank-verify.sh` 가 정본이다(토큰 값은 절대 출력·로그 금지, `unset GH_TOKEN` 선행). 그런데 issues 총괄 좌석이 `gh issue create/comment/edit/close` 를 직접 쳐서 #839 등이 오빠 계정(yoonhwan) 작성자로 올라갔고 코멘트·라벨 변경·#819 close 도 전부 오빠 이름으로 나갔다(#834·#835 는 Tank 경로라 byz-tank). 사람 승인 영역(오빠 판정)은 이 카드 밖이다.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-gh-as-tank.sh <create|comment|label|close|reopen> …`(신규): Tank 토큰으로 실행하는 래퍼. 기본 = dry-run(실행할 gh 명령만 출력) · `--apply` 때만 실제 실행(읽기 전용 조회는 래퍼 불필요). 토큰이 없으면 exit 2 raise(폴백 0 — 오빠 로그인으로 폴백 금지). 실행 전 `gh api user` 로 작성자 로그인이 `byz-tank` 인지 확인하고 아니면 REJECT. `ft-issue-create-pair.sh` 의 마커·매니저 알림 규약과 충돌하지 않게 create 는 기존 쌍 스크립트를 재사용(중복 구현 금지).
2. 가드 훅 `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh`(신규 · PreToolUse Bash): 명령에 `gh issue (create|comment|edit|close|reopen)` 또는 `gh issue` 쓰기용 `gh api …/issues` 가 있고 `ft-gh-as-tank.sh`·`ft-issue-create-pair.sh` 를 거치지 않으면 exit 2 로 막고 「래퍼를 써라」 메시지. 읽기(`view`·`list`)는 통과. ★설치(~/.claude/settings.json 등록)는 이 카드 범위 밖 — 오빠 승인 후 ops 가 한다★.
3. 시험 `tests/harness/test_gh_as_tank.sh` + 부팅 문서 한 줄: 래퍼 dry-run 출력·토큰 없음 rc=2·가드가 직접 호출 차단/래퍼 경유 통과/조회 통과(훅에 JSON 입력을 stdin 으로 넣는 방식) · `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 는 «수정 금지» — 대신 제안 문구를 `design/teams/harness/RESULT-gh-as-tank-20261007.md` 에 적는다(ops 가 반영). 커밋은 자기 브랜치, **push 금지**.
**금지**: 실제 Issue 쓰기(--apply) 실행 · 토큰 값 출력 · ~/.claude 수정 · 기존 `ft-issue-create-pair.sh`·`ft-tank-verify.sh` 수정.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 래퍼 dry-run 이 4동작(create·comment·label·close)의 gh 명령을 올바르게 출력 · 토큰 없음 rc=2 · 작성자 불일치 REJECT(시험 출력).
- 가드 시험 3종 통과(직접 호출 차단 · 래퍼 경유 통과 · 조회 통과) · 훅 `bash -n` OK.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: f02307ea7ae2bea6acd23ecfbe5eea08d9fc3b6b (spawn 2026-10-07)
- 2026-10-07 — 대기/ 생성 (ft-harness-ops#6 · issues 총괄 쪽지 58342 · 오빠 10-07 개선 지시).
- 정본 영향 없음: 하네스 스크립트·훅 템플릿·시험만 추가 — docs/architect 제품 정본 변경 없음
- 2026-10-07 11:21 — 대기→진행 · 좌석 ft-harness-temp-gh-as-tank-wrapper-guard#0
- 2026-10-07 11:26 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§21
- 세트: 92831cb4afe99e0a4231f3e326f31693045e1d06 · 시험: bash tests/harness/test_gh_as_tank.sh rc=0 · 이슈: 0
