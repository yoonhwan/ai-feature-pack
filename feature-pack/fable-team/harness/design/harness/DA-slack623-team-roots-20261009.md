model: GPT-6 (runtime; context window size unconfirmed)
provider: OpenAI

# 판정 623 설계 DA r1 — 2026-10-09

대상: DA-REQ-slack623-team-roots-20261009.md 및 indices/대기/slack623-team-roots.md 설계 1~8/T1~T8. 기준 코드: origin/main의 scripts/harness-install/slack-mirror/. 읽기 검토이며 실 Slack·홈 상태·GitHub 쓰기 및 제품 Redis/DOM 조작은 하지 않았다. Serena 도구 노출은 확인했다. 고정 원격 코드 근거는 git show로 읽었다.

## Q1 — APPROVE

설계 2의 이슈 라벨 정상/없음/조회 실패는 각각 지정 팀/기타/기타로 귀착하고, 좌석 키와 GAP도 경로가 있다. 조회 실패의 ERROR와 다음 글 재조회는 조용한 누락을 막는다. 설계 1의 KST 08:00 경계는 T3의 07:59/08:00으로 검증 가능하다. reply_only의 루트 부재 시 WARN·미게시 예외는 설계 4의 명시 계약으로 수락한다.

## Q2 — HOLD

HIL을 기존 이슈 루트에 남기는 방향은 타당하지만, 실제 코드의 가정은 ‘스레드당 질문 정확히 하나’가 아니다. mirror_plan.plan은 open+delivered 질문이 여럿이면 planner에게 원문을 보내고, 질문이 없으면 mirror_inbound.inferred_seat가 루트와 같은 봇의 마지막 글 3번째 줄에서 좌석을 추정한다. 따라서 팀 스레드에 이슈 A와 B의 보고가 섞인 후 A에 대한 사용자 답글이 오면 B 보고 좌석+planner로 갈 수 있다. 설계 7의 inbound 유지와 설계 4의 format_row 유지로 이 동작이 그대로 발생할 수 있으나, 수신자 계약 및 시험이 없다.

또한 byz_mbox_slack_mirror.Mirror._row는 원래 key로 _close_answered를 호출하고, mirror_questions.delivered_for는 질문 key·seat·mbox_seq 이후 보고를 대조한다. 전송용 팀 key로 원래 질문 key까지 치환하면 HIL 답변 뒤 일반 보고가 질문을 닫지 못한다. _send_item의 질문 등록 thread_ts와 send의 실제 HIL 게시 thread_ts도 같아야 한다.

교정: 설계 5·7에 팀 답글의 무질문 라우팅을 명시하고(예: 팀 루트는 planner만), 원래 업무/질문 key와 전송용 팀 key를 분리하며 HIL 등록·게시·후속 close의 동일성을 고정한다. T5에 같은 이슈 복수 질문, 답변 후 팀 보고로 close, 서로 다른 좌석의 팀 스레드 답글 수신자 시험을 추가한다.

## Q3 — HOLD

mirror_deliver.ensure_thread의 flock은 기존 threads 맵의 읽기→루트 게시→맵 저장까지만 보호한다. Deliverer.send의 reply 게시와 별도 팀 상태 파일/루트 갱신은 그 잠금 밖이다. ‘기존 flock 유지’만으로 새 byz_team_roots.json의 RMW와 Slack 전송 순서가 보장되지 않는다.

반례 1: GitHub와 mbox가 같은 상태 S를 읽고 각각 이슈 A/B를 더한 뒤 저장하면 마지막 저장이 다른 이슈를 없앤다. 반례 2: 저장만 잠가도 A가 이전 상태를 렌더링하고 지연되는 동안 B가 최신 내용을 update한 뒤 A의 update가 성공하면 화면은 역전된다. planner 요약도 같은 경쟁을 갖는다. 설계 6의 ‘다음 글에서 복원’은 상태 자체가 소실되는 반례 1을 복구하지 못한다.

재시작도 reply 마커만으로 충분하지 않다. Mirror.deliver는 pending을 먼저 저장하고, Deliverer.send는 resume 때 기존 reply 마커가 있으면 반환한다. 팀 상태를 먼저 갱신한 뒤 reply 전에 죽으면 같은 pending의 진행 수를 두 번 올릴 수 있다. 반대로 reply 성공 뒤 update 실패·종료가 겹친 경우 resume의 마커 반환 경로가 갱신 복구까지 수행하는지 현재 설계에는 없다. T6/T7은 이 중간 종료를 다루지 않는다.

교정: 설계 3·6에 두 프로세스 공용 잠금의 범위(상태 읽기/멱등 이벤트 반영/원자 저장/팀·planner update 순서), 잠금 순서, 상태 저장 실패 시 진행 중단, 이벤트 id별 중복 반영 방지와 resume 복원 경로를 고정한다. 두 writer의 교차 실행, 이전 update 지연, 상태 저장 뒤·reply 뒤 종료 후 재시작을 가짜 API로 검증한다. 기존 루트 맵과 새 root_ts 상태 사이 종료 구간의 재사용 정본도 명시한다.

설계 교정 두 건을 함께 전달한다. 코드 구현·설치 승인으로 해석하지 않는다. 초기 검토 r1이며 교정 검토는 bounded 1회 남는다.

HOLD

## r2 — 2026-10-09 · 기준 7009926437

요청서 r2와 카드 «설계 r2»만 대조했다. r1의 Q2·Q3 교정 확인 범위이며 새 요구를 추가하지 않았다. 아래 판정은 설계 승인으로, 구현 시험 통과 또는 설치 완료를 뜻하지 않는다.

### Q2 — APPROVE

r2-A는 원래 `key`를 질문 등록·_close_answered·delivered_for에 보존하고 게시 선택에만 `post_key`를 사용한다. HIL의 등록 및 게시 thread_ts는 같은 원래 key의 ensure_thread 결과로 고정한다. 따라서 팀 일반 보고로 전환해도 기존 질문 종료 대조가 유지된다.

팀 스레드는 맵의 `team:` 키로 식별하여 좌석 추정을 생략하고 planner에게만 원문과 링크를 전달한다. r1의 ‘마지막 B 보고 좌석으로 A 답글 전달’ 반례가 제거된다. 같은 이슈 복수 질문은 기존 planner 원문 전달을 유지하며 T5a~c가 복수 질문·후속 close·팀 답글 수신자를 각각 검증한다.

### Q3 — APPROVE

r2-B는 두 미러 공용 flock 안에서 상태 읽기→이벤트 id 멱등 추가→원자 저장→전체 렌더→팀 및 planner update를 직렬화한다. r1의 동시 RMW 소실과 오래된 update 역전을 모두 막는 설계 계약이다. root_ts 정본을 기존 스레드 맵으로 통일하고 맵 잠금을 해제한 뒤 공용 상태 잠금을 취하도록 하여 중첩 잠금을 배제한다.

reply 마커로 resume 게시를 생략해도 상태 반영과 렌더를 항상 실행하며, 이벤트 id는 중복 반영되지 않는다. 저장 실패는 raise하고 pending을 남긴다. 따라서 reply 뒤 종료와 상태 저장 뒤 종료의 복구 경로가 명시됐고, T9~T11이 교차 writer·지연 update·중간 종료 및 진행 수 중복을 검증한다. chat.update 실패의 상태 보존과 다음 렌더 복구도 유지한다. r2의 실패 경고는 이미 게시된 답글이 아니라 ‘다음 답글’에 싣는 계약으로 읽으며 T6 역시 이 r2 계약에 맞춰 확인해야 한다.

Q1의 r1 APPROVE는 유지한다. Q2·Q3의 r1 HOLD 사유는 설계 r2로 해소됐다. 실제 병렬 실행·종료 주입·가짜 Slack 검증은 카드의 구현 및 arch 독립 재현 단계에 남는다. 실 Slack·홈 상태·GitHub·제품 Redis/DOM 쓰기는 하지 않았다.

APPROVE
