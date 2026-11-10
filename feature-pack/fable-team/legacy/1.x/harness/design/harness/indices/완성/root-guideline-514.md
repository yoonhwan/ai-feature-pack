# 인덱스: 하네스 루트 지침 초안 — 「골을 끝내면 멈추고 다음 일을 묻는다」 모든 팀·좌석이 부팅 때 읽는 최상위 지침 + 판정 511 «완료·휴식» 상태 반영 (판정 514 · 설계 좌석 Fable 5.1 high · DA sol high)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 514(오빠 절대 지침 21:3x · planner#12 #64807 · 「골을 줬으면 끝내고 놀아」·「이거 기획 da 높은 브래인으로 하네스 루트 브레인 지침 만드는거다」 · master#18)
- 상태: 대기
- 선행: 없음 (v421-board 랜딩과 무관 · 문서 산출만)
- 시험 입력: 문서 산출 단위 — 시험 코드 0. 검증 = 초안 파일 존재 + DA(codex gpt-6.1-sol high) 판정문 APPROVE + 아래 «완료 조건» 대조표
- 기준값: 없음 → 대체 축 «금지 4 행동의 실측 건수» — 지금 부팅 지침(BOOT 17조항 · main-team-governance)에 「골 끝 → 멈춤 → 다음 일 묻기」 조항 0줄 · closeout-policy 1·4 와 승계 금지는 있으나 «완료·휴식 상태» 정의 0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(오빠 요청 즉시 반영 — 판정 514 오빠 절대 지침). 핵심 한 줄: 받은 골을 끝낸 좌석이 «멈춰 노는 것»을 정답 상태로 정의하고, 질질 끌기·옛 데이터 재소환·승계로 잇기·끝없는 루프·옆 확장을 지침으로 막는다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오빠 21:3x 원문: 「메인팀이 발주한 작업을 끝내고 멈춰서 놀고있는게 최고야. 지금 보면 하네스해보니 안끝내고 어떻게든 질질질 끌고 과거의 옛데이터 마저 끌어와다가 세션을 이어 토큰을 소모하는 형상이다. 이거 절대 반대해야하고 절대 지침으로 플래너와 하네트마스터가 개선해야한다.」·「골을 줬으면 끝내고 놀아. 노는게 맞는거야. 놀고있는걸 캐치시키고 플래너와 나한테 다음작업을 물어보는게 가장 건강한거고 중요한거다.」·「밤새도록, 한두달 영원히 안끝나게 돌리는건 그건 사람생각을 흐리게 만들고 작업을 옆으로 확장해 멀하는지도 모르게하는 아주 나쁜거다」·「이거 기획 da 높은 브래인으로 하네스 루트 브레인 지침 만드는거다」·「대충 너랑 하네스 마스터 둘이 어떻게 해보려하면 답없다」. 전문 = `/tmp/mbox/20261008T212923-byz-planner-master-claude#12-to-byz-harness-master-claude#18-goal5-harness-18.md`(planner GOAL-planner.md 원문 5 · 커밋 8647e975b4). 좌석 상태는 세 가지로 가른다: ①진행 ②정지·미완(안 끝났는데 서로 기다림 → 깨움 대상 · 판정 511) ③완료·휴식(받은 골을 끝냄 → 정답 · 「끝났음 + 닫는 증거 + 다음 일 요청」 1통을 planner 에 올리고 쉼). 금지 4: ①끝난 단위를 닫지 않고 «추가 확인·재측정·옆 작업»으로 이어가기 ②옛 데이터·옛 인계서·옛 증거를 끌어와 세션 이어 붙이기(승계로 버티기) ③끝이 없는 루프·골 밖 옆 확장 ④다음 일을 스스로 정해 시작(다음 일은 planner·오빠가 정함).

## 사전검증
- 소환: 예
- DA: codex gpt-6.1-sol effort high (기본 low 아님 · 오빠 지시) — 초안 완성 뒤 master 가 소환 · 판정문 `design/teams/harness/DA-root-guideline-514-20261008.md`

## 조사 근거
- 기존 조항: `~/.claude/rules/closeout-policy.md` 1·4(열어 두고 이어가기 금지 · 재개 = 이벤트 기반) · `~/.claude/skills/fable-team/references/main-team-governance.md`(§8 판정 511 초안 포함) · `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md`(현재 17조항 · 18줄 초안은 `design/teams/harness/DESIGN-511-seat-stall-watch-20261008.md`).
- 판정 511 설계·DA: `design/teams/harness/DESIGN-511-seat-stall-watch-20261008.md` · `design/teams/harness/DA-511-seat-stall-watch-20261008.md` — 511 의 «정지 = 나쁨» 은 «안 끝났는데 기다리며 멈춤» 에만 해당한다는 정정을 이 단위가 반영한다.
- 메모리 근거 `~/.claude/projects/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents/memory/feedback_finish_goal_then_rest_no_dragging.md`.
- 방송 이력: 판정 511 방송은 master#17 이 6팀에 이미 발신(규칙 문서 `RULE-status-from-measurement-20261008.md`) — 정정 방송 필요 여부를 초안에 판단으로 적는다.

## 구현 범위 (닫힌 목록)
1. 산출 파일 1: `design/teams/harness/ROOT-GUIDELINE-draft-20261008.md` — «하네스 루트 지침» 초안. 모든 팀·좌석이 부팅 때 읽는다는 전제로 짧고 강제력 있게(조항마다 «무엇을 하지 않는다 + 하면 어떻게 잡는가»). 포함: ①오빠 원문 인용(위 배경 그대로) ②좌석 상태 3분류 정의와 판별 근거(jsonl turn 끝 · 닫는 증거 유무) ③완료·휴식 절차(끝났음 + 닫는 증거 + 다음 일 요청 1통을 planner 에 · 그 뒤 쉼 · 세션 닫기는 closeout-policy 5) ④금지 4 + 각각의 «잡는 방법» ⑤판정 511 과의 관계 정정 ⑥정본 반영 위치 제안(main-team-governance 조항 · COMM-GUIDE-BOOT 한 줄 · 상태판 «완료·휴식 = 다음 일 대기» 칸)과 각 문구 초안.
2. 산출 파일 2: `design/teams/harness/DESIGN-511-seat-stall-watch-20261008.md` 에 «완료·휴식» 상태 절 추가(`§4-r3`) — 기존 §4-r2 는 지우지 않고, 정지(3분+) 열이 완료·휴식 좌석을 정지·미완으로 세지 않게 하는 판별 규칙만 더한다.
3. 산출 파일 3: 전 팀 방송 문안 초안(오빠 원문 3줄 + 금지 4 · 팀별로 문구를 달리 쓸 필요가 있으면 그 이유 1줄 · 511 방송 정정 필요 여부 판단).
4. 순서: 초안 → master 에 RESULT(mbox) → master 가 DA 소환 → HOLD 면 반영 → APPROVE 면 planner 가 오빠 컨펌 → master 가 정본 반영·방송. ★정본 파일(`~/.claude/**`) 직접 수정 금지★ — 이 단위는 초안까지.

## 완료 조건 (RESULT 에 복붙할 줄)
- 초안 3개 파일 경로 + 커밋 sha(자기 브랜치 · push 금지)
- 오빠 원문 5줄 인용이 초안 §1 에 그대로 있음(grep 줄 번호)
- 금지 4 각각에 «잡는 방법» 1개 이상(줄 번호)
- 세션을 이어 붙이는 문구·밤새 도는 루프를 허용하는 문구가 새 조항에 0 (자기 대조 표)
- 카드 증거 줄(필수 · RESULT 맨 끝 · 문서 단위라 시험 칸은 키트 동기 시험 1개): `세트: <40hex> · 시험: bash tests/harness/test_kit_bin_sync.sh rc=0 · 이슈: 0`

## 금지
- 정본(`~/.claude/**`, main-team-governance, COMM-GUIDE-BOOT) 직접 편집 · 방송 발신 · DA 직접 소환 · push · 다음 일을 스스로 만들어 이어가기(이 카드 자체가 금지 4 의 적용 대상 — 초안 RESULT 를 보내면 멈추고 master 회신을 기다린다)

## 상태
- base_sha: 990b9786862667f529564a7d9df95e631363c7f2 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-master-claude#18 · 판정 514 · planner#12 #64807 · 판정 516 으로 511 정본 설치 보류 → 이 단위에 511+514 합침).
- 정본 영향: 이 카드는 초안까지. 정본 반영(governance · BOOT)은 DA APPROVE + 오빠 컨펌 뒤 master 가 cp+cmp.
- 2026-10-08 21:32 — 대기→진행 · 좌석 byz-harness-nano-root-guideline-514#0
세트: 6fdb732e1fb4b6d948d978e995b13c9d7d6c989b · 시험: bash tests/harness/test_kit_bin_sync.sh rc=0 · 이슈: 0
세트: 965c6695d28bce4f38cd99f59f0b7d5a631ac935 · 시험: bash tests/harness/test_kit_bin_sync.sh rc=0 · 이슈: 0
- 정본 영향 없음: 하네스 지침 문서·홈 정본(~/.claude 이미 설치)만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 22:17 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§79
