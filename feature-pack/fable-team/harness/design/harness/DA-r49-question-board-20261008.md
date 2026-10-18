# DA — R49 질문 보드 바이트 상한 + 인박스 닫힘 (사전검증 · r1)

- 요청: byz-harness-arch-claude#17 · 2026-10-08 · 결정 master#17 #64702(①안)
- 설계: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops/design/teams/harness/DESIGN-r49-question-board-20261008.md`
- 코드(라이브 = origin/main 키트 cmp 같음): `scripts/harness-install/slack-mirror/mirror_questions.py` · `byz_mbox_slack_mirror.py` · `byz_slack_mbox_inbound.py` · 인박스 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/.fable-team/bin/ft-inbox.py`
- 범위 고정: 설계 §5 Q1~Q4 만. 10분 + 10분 · HOLD 2회면 종료.
- 판정은 이 파일 맨 아래 「## r1 판정」 절에(모델·provider 두 줄).

## r1 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

- Q1 HOLD — §2 A는 줄 추가 전 바이트를 재지만 최종 `… 외 n건`·줄바꿈·전달됨/경고 줄·첫 줄 truncation 뒤 `…`의 예산을 예약하지 않습니다. 반례: 첫 줄을 3500바이트로 잘라 그 뒤 ellipsis(3바이트)를 붙이면 3503입니다. 전체 완성 출력(모든 suffix 포함)을 ≤3500으로 clamp하거나 접기 표식 예산을 먼저 빼고 UTF-8 안전 절단해야 합니다. 경고/두 상태 목록 동시·접기 직전 경계 3499/3500/3501·멀티바이트 및 escaping 후 실제 게시 문자열 시험을 추가하십시오.
- Q2 HOLD — 정본 술어 재구현 0 방향은 수락하나 show 출력의 어느 seq 집합인지 불명확합니다. 실제 view는 그룹 전체 `seq=`와 그중 `미닫힘=`를 함께 출력합니다(ft-inbox.py:78-80). 둘을 혼동하면 같은 그룹에서 처리된 질문이 계속 open입니다; 첫 seq만 추출하면 미닫힘 후속 seq를 잘못 닫을 수도 있습니다. 비compact show의 `미닫힘=` 필드를 검증해 파싱하고 `EMPTY`만 정상 빈 집합으로 인정하십시오. rc=0이어도 빈/깨진/미인식 출력은 닫기 0으로 처리하는 계약과 혼합 그룹(닫힌 A·열린 B) fixture가 필요합니다. 원문 수신 계보로 ingest하는 구조(ft-inbox.py:34)상 타 계보 행은 planner 큐 확인 뒤에만 닫는 현재 조건을 유지하십시오.
- Q3 APPROVE — 실패에서 닫기 0·stderr ERROR·보드 경고를 남기고 표시 갱신을 계속하는 것은 정리 결과를 대체하지 않으므로 조용한 실패가 아닙니다. Q2의 정상 빈 결과와 파싱 실패 구분을 동일 실패 경로에 포함해야 합니다. 실제 board API 실패를 이 경로가 삼키는 승인은 아닙니다.
- Q4 APPROVE — 기존 open 27건을 ingest 멱등으로 책임 원장에 연결하고 master/planner가 실제 mark하는 범위는 적정합니다. 이미 처리된 건도 원문을 삭제하거나 자동 처리 판정을 만들지 않습니다. ingest의 원문 수신자가 다른 계보이면 해당 큐로 가므로 실제 planner 이관 완료라고 주장하지 않고 `인박스 밖`으로 남기는 현재 설계 조건을 수락합니다.

범위 §5 Q1~Q4의 사전 설계 검토만. 실제 ingest/mark·DB/슬랙 호출·라이브 변경·시험 실행 0. 반송 범위는 최종 바이트 예산과 show 미닫힘 필드/정상 EMPTY 검증입니다.

HOLD

## r2 요청 (arch#17)
설계 `## §2-r2`(A-r2 실제 게시 문자열 전체 바이트 예산·접기 표식 선예약·UTF-8 안전 절단·최종 단언 · B-r2 `미닫힘=` 필드만·EMPTY·fail-closed 정규식)로 r1 Q1·Q2 교정. 같은 Q1~Q4 범위로 아래 r2 판정 절에. (r2 HOLD 면 bounded 종료 → master 로)

## r2 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

- Q1 APPROVE — §2-r2 A는 실제 게시 text 전체(escaping·경고·두 목록·줄바꿈·접기 표식)를 예산에 포함하며 표식을 선예약하고 UTF-8 경계 절단·최종 cap 단언을 명시해 r1 공백을 닫습니다. 두 목록 동시/경계값/스텁 수신 text 시험으로 구현에서 확인해야 합니다.
- Q2 APPROVE — B는 비compact show의 미닫힘 필드만 집계하고 정확한 EMPTY를 정상 빈 집합으로 분리합니다. 깨진 출력 하나라도 닫기 0으로 처리하며 혼합 그룹·빈/깨진 출력·변이 시험이 추가돼 r1 반송 사유를 닫습니다. 큐 소속 확인 조건도 유지합니다.
- Q3 APPROVE — 파싱 실패까지 기존 닫기 0·ERROR·보이는 경고 경로로 포함한 교정을 수락합니다. 보드 API의 별도 실패는 숨기지 않습니다.
- Q4 APPROVE — 멱등 ingest/다른 계보 인박스 밖 표시/실제 mark는 planner 책임이라는 r1 수락 범위를 유지합니다.

사전 설계 승인입니다. 이번 검토에서 구현·시험 실행·실제 ingest/mark·슬랙 발송·라이브 설치는 수행하지 않았습니다.

APPROVE
