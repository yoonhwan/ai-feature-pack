# 인덱스: 카드 이동 때 슬랙 과정·결과 답글 자동 + 결과 없으면 CLOSE 금지 + 손 hermes send 슬랙 차단 (판정 404 ② · 카드 2/2)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 오빠 판정 404·405(planner#9 #62157 · master#14 #62159·#62177)
- 상태: 대기
- 선행: 카드 1 resume-block-thread-post 랜딩(byz_thread_post.py check·progress·result 가 main 에 있어야 함)
- 시험 입력: 가짜 byz_thread_post(PATH·env 로 주입하는 스텁 — rc·출력 지정) + 임시 git 리포의 카드 픽스처 · 훅은 가짜 PreToolUse JSON 입력
- 기준값: 지금 ft-index-move 진행→완성 = DA 판정문 §N «닫힘» 확인만 · 슬랙 결과 답글 0건이어도 이동 · 손 `hermes send --to slack:` 차단 0(감사: 제안서 4건 손 발행)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A 모니터·오빠 요청 + C 배포 발행·반영. 핵심 한 줄: 판정 405 전제 3 「판정·랜딩·닫힘 때 그 스레드에 자동, 안 보내면 CLOSE 금지」 + 전제 1 「손 hermes send 슬랙 발행 금지」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
카드 1 이 만든 `byz_thread_post.py`(check/progress/result)를 카드 이동 문(`ft-index-move.sh`)에 연결한다. «게시 대상» 판단은 장부가 아니라 카드 상태 절의 `- 슬랙:` 줄 유무다(장부 유실을 미게시로 오판하지 않기 — DA HOLD-I1). 대기→진행이면 그 스레드에 착수 답글, 진행→완성이면 결과 답글(판정문 §N 제목 줄)을 자동으로 보내고, 보내지 못하거나 장부가 불명이면 이동을 막는다. 그리고 나노·좌석이 `hermes send` 로 슬랙에 직접 올리는 것을 PreToolUse 훅으로 막는다(오빠 판정 405 — 채널 #byz-planner 하나 · 공식 도구만). 설계 정본 §4·§5·§8-b.

## 사전검증
- 소환: 예
- DA: design/teams/harness/DA-resume-index-20261008.md

## 조사 근거
- `scripts/fable-team-bin/ft-index-move.sh:21` 대기→진행 분기(lint + --seat) — 착수 답글 자리.
- `scripts/fable-team-bin/ft-index-move.sh:25` 진행→완성 분기(--da 판정문 §N 확인) — 결과 답글·CLOSE 금지 자리.
- `scripts/fable-team-bin/ft-index-move.sh:83` 이동(git mv) — 슬랙 처리는 이동 «전»에 끝나야 한다(실패면 이동 0).
- `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh:1` PreToolUse 가드 훅 꼴(입력 JSON·deny 출력) — 새 훅이 따를 형식.

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-index-move.sh`(+ 키트 사본): 이동 «전»에
   - 대기→진행: 카드에 `^- 슬랙:` 줄이 있으면 `byz_thread_post.py progress --card <SRC> --text "착수 — <SEAT>"` · rc≠0 = REJECT(이동 0). 줄 없으면 슬랙 단계 0.
   - 진행→완성: 카드에 `^- 슬랙:` 줄이 있으면 `byz_thread_post.py check --card <SRC>` → rc 0 = 통과 · rc 1 = `byz_thread_post.py result --card <SRC> --verdict <DA> [--landed <sha>]` 자동 → rc≠0 이면 REJECT · rc 3 = REJECT 「장부 복구 필요 — byz_thread_post.py repair --card <카드>」. 줄 없으면 지금 동작 그대로.
   - 새 선택 인자 `--landed <sha>`(결과 줄에 붙음 · 없으면 도구가 `랜딩 없음`).
   - 도구 경로 = env `FT_THREAD_POST`(기본 = 설치된 slack-mirror 의 byz_thread_post.py) · 없으면 슬랙 줄 있는 카드는 REJECT(폴백 0).
   - 파일 길이: 지금 123줄 — 200 이하 유지(넘으면 슬랙 단계를 `ft-index-move-slack.sh` 로 분리 · 같은 두 사본).
2. `scripts/harness-install/fable-team/templates/hooks/slack-post-guard.sh` 신설: PreToolUse(Bash) 입력의 명령에 `hermes send` 가 있고 대상이 slack(`-t slack`·`--to slack`·`-t slack:`·`--to slack:`)이면 deny + 사유 「슬랙 발행은 byz_thread_post.py start|progress|result 로 — 판정 405」. 다른 플랫폼·`--list`·읽기는 통과. 우회 문자열(따옴표 분리·변수 대입)은 «명령 문자열에 hermes 와 slack 이 함께 있으면» 보수적으로 deny(오탐은 기록 — 전역 오탐 규칙).
3. 시험: `tests/harness/test_index_move_slack.sh`(가짜 byz_thread_post 스텁 rc 0/1/3·발송 실패 · 카드 픽스처 슬랙 줄 있음/없음 · 대기→진행·진행→완성 · REJECT 시 파일 위치 불변) + `tests/harness/test_slack_post_guard.sh`(deny 6 · allow 4) + 기존 index-move 시험·`test_kit_bin_sync.sh` PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 장부 직접 읽기(형식은 byz_thread_post 만 안다) · 슬랙 실패 시 이동 허용 · 훅 홈 설치(master 몫) · 실제 슬랙 호출.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_index_move_slack.sh` rc=0 · `bash tests/harness/test_slack_post_guard.sh` rc=0 · 기존 index-move 시험 PASS · `test_kit_bin_sync.sh` PASS · 사본 cmp · bash -n.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_index_move_slack.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN 에 ft-index-move cp(+분리 파일) · `ft-live-bin-drift-check.sh` OK · 훅 홈 설치 + settings PreToolUse 등록 · 소급 7건(설계 §7) `byz_thread_post.py result --legacy-root …` 1회씩 → 각 스레드 [결과] 답글 실측 → 판정 404 소급 보고 1통.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: d6e6785fb2240d8a9b74daacb3b21752f5eaf82a (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#12 · 판정 404·405 · 설계 DA 교정 1 APPROVE #62213). spawn = 카드 1 랜딩 뒤.
- 정본 영향 없음: 하네스 카드 이동 도구·가드 훅·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 14:34 — 대기→진행 · 좌석 byz-harness-nano-result-reply-close-gate#0
- 2026-10-08 — 세트: 111360204dea1cb7ef607db07e4d45c2bbad69be · 시험: bash tests/harness/test_index_move_slack.sh rc=0 · 이슈: 0
- 2026-10-08 15:08 — 진행→완성 · 좌석 byz-harness-nano-result-reply-close-gate#0 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§60
