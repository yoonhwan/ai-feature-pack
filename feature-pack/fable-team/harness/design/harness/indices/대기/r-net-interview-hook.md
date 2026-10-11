# 인덱스: 인터뷰 lint 훅 — AskUserQuestion PreToolUse(종류 머리 6 · 종류별 필수 줄 · 질문 1) (N5 · 팀 운영 구조 근원 수정 · 판정 1070·1079 · arch#29)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → planner ORDER(판정 1069·1070) · 설계 PLAN-harness-networking-20261011.md §2 D7
- 제안서: 없음 — 오빠 판정 1070 으로 착수 승인된 하네스 구조 수정(판정 1079 3차 DA APPROVE #76290)
- 상태: 대기
- 선행: N4(`선례:` 줄 문자열) · N3(`[결정]` 3줄 꼴 공유) · 설계 = `git show f0d974ab20:design/harness/PLAN-harness-networking-20261011.md`(r2 · ★나노 워크트리에는 없다★)
- 시험 입력: 훅 입력 JSON 픽스처 8종(stdin) — 실 settings.json·실 세션 0
- 기준값(arch#29 실측 · 2026-10-11): 오빠가 안 본 것이 승인된 사례 811·660·713·1004(REVIEW §4 ③ · 인터뷰가 요약+경로만) · AskUserQuestion 사건 460/4일(115/일) · 기존 훅 꼴 `~/.claude/hooks/report-coverage.sh`·`boot-read-gate.sh`(PreToolUse · stdin JSON `tool_name`·`tool_input` · exit 2 = 차단 · fail-open 관례) · 제안서 Issue+`approved` 라벨 흐름 도입됨(PROPOSAL-proposal-approval-gate r1) · governance §4 각주 표 규칙.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
상위 제약(제품 골 · CLAUDE.md ACTIVE TRACK GOAL 바이트 일치): 목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다. / LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다. / 단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.
planner 원문 2(팀 배정·운영) / 닫는 증거(PLAN §6 N5 복붙): 「planner 인터뷰 1건 실측 = 머리 + 필수 줄 + 질문 1 · `[HIL]` 인터뷰가 링크 없이 통과」.
골의 축: 근원 ③(오빠가 안 본 것이 승인됨) — 채택안 C.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
인터뷰가 «요약 + 경로»만 보여 줘서 오빠가 원문을 안 본 채 승인이 넘어갔다(사례 4건). 쉬운 말 1장은 제안 Issue 본문(이미 도입)이 맡으니, 인터뷰는 «그 링크 1개 + 선례 줄 + 질문 1개»만 하도록 훅으로 강제한다. 새 PreToolUse 훅 `interview-lint.sh`(`tool_name=="AskUserQuestion"` 일 때만 · planner 세션 한정은 settings.json 등록 위치로 — 다른 세션 settings 에는 넣지 않는다)는 첫 질문 본문 첫 줄 머리로 종류를 가른다: `[제안]`·`[이슈]`·`[합치기]` = GitHub 링크(`github.com/…/(issues|pull)/\d+`) 정확히 1개 ∧ `선례:` 줄 1 ∧ questions 길이 1 ∧ 물음표 1 ∧ 본문 `#\d+` 가 있으면 끝에 각주 표(`| 번호 |`로 시작하는 표) · `[HIL]` = 막힌 명령 원문 줄(코드블록 또는 `명령:` 줄) 1 ∧ 영향·되돌림 줄 1 ∧ 선택지 ∧ 질문 1 — 링크 불요 · `[긴급]` = 질문 1 만(링크·선례·각주 면제 · 로그 1줄) · `[결정]` = `비가역:`·`선례:`·`선택지:` 3줄 ∧ 질문 1(링크 있으면 1개) · 머리 없음 = exit 2 `인터뷰 머리 [제안]·[이슈]·[합치기]·[HIL]·[긴급]·[결정] 중 하나`. 어긋나면 exit 2 + stderr 에 어느 항인지 1줄 · 훅 자체 오류(JSON 못 읽음 등)는 fail-open + `~/.claude/logs/interview-lint.log` 1줄(#0 RULE: 무음 아님). 세부는 PLAN §2 D7 이 정본 — 카드와 PLAN 이 다르면 PLAN 이 이긴다.

## 사전검증
- 소환: 예 — DA byz-harness-da-codex#1 r0 HOLD #76217(F2 긴급 경로) · r1 F2 교정 · r2 APPROVE #76290(판정 1079 · F2 한정 확인) — arch 서명 byz-harness-arch-claude#29
- 조사 근거: `~/.claude/hooks/report-coverage.sh`·`boot-read-gate.sh`(PreToolUse 입출력 계약 · exit 코드 · 로그 위치) · `~/.claude/settings.json` hooks 등록 꼴 · `scripts/harness-install/`(키트 `templates/hooks/` 사본 자리 · `TABLE-gate-hook-copies-20261008.md` 3사본 정합) · governance §2·§4·§7
- 7초 룰 점검(판정 666): 외부 호출 0(stdin JSON 파싱만)

## 구현 범위 (닫힌 목록 · 나노 · PLAN §6 N5 · 한 번에 하나)
관련 파일(기존 · origin/main 실재 · 나노 base): scripts/harness-install/fable-team/templates/hooks/boot-read-gate.sh · scripts/harness-install/fable-team/templates/hooks/block-destructive.sh · design/harness/TABLE-gate-hook-copies-20261008.md
1. ①시험 빨강 먼저 — 새 `tests/harness/test_interview_lint.sh` + 픽스처 `tests/fixtures/interview_lint/*.json` 8종(머리 없음 · 제안 링크 0 · 제안 링크 2 · HIL 원문 줄 0 · HIL 정상(링크 없음 → 통과) · 긴급 · 결정 3줄 · 질문 2) + 깨진 JSON(fail-open rc 0 + 로그 1줄). 이 커밋 rc≠0(빨강).
2. ②새 `scripts/harness-install/hooks/interview-lint.sh`(≤150줄 · bash+python3 · 다른 tool_name 은 즉시 rc 0).
3. ③설치 안내 1장 `design/harness/INSTALL-interview-lint.md`(master 집행용: settings.json 의 PreToolUse 배열에 1행 · planner 세션이 쓰는 settings 위치 · `.bak` · 되돌림 1줄 · 3사본 자리 — 글만 · 실 설치 0).
4. ④미러: 키트 `templates/hooks/` 사본 `cmp` 0(자리 없으면 TABLE-gate-hook-copies 의 정본 위치에 1벌).

커밋은 자기 브랜치(단계별 · [test]→[feature]→[docs] 분리), **push 금지**. **금지**: `~/.claude/settings.json`·`~/.claude/hooks/` 실 설치(master 집행) · 다른 훅 파일 변경 · governance 글 변경(S5 arch 초안) · 위 목록 밖 파일 수정 0.

## 완료 조건 (닫힘 판정 기준)
- `bash tests/harness/test_interview_lint.sh` rc=0 · `bash -n` · 미러 `cmp` 0 · 훅 ≤150줄.
- 카드 증거 줄(«세트:» 로 시작 · 접두 없음): 세트: <40hex> · 시험: bash tests/harness/test_interview_lint.sh rc=0 · 이슈: 0
- 루트 지침: 완료 그 턴에 증거 줄 + arch#29 에 `[완료·휴식]` 1통.

## 상태
- base: origin/main 32d0374ed0e8c600e3c7ae07537cc814be989b60 (arch#29 카드 작성 시점 · spawn 때 `--base origin/main` 으로 다시 고정 · base_sha 줄은 spawn 도구가 쓴다)
- 2026-10-12 — 대기/ 생성 (byz-harness-arch-claude#29 · N5 · 설계 PLAN r2 f0d974ab20 · DA APPROVE #76290 · 판정 1070·1079).
- 정본 영향: 훅 신규 1(키트 templates/hooks) · 설치 안내 1장 · 홈 settings.json 등록은 master 집행(별도) · governance §2 글은 S5.
