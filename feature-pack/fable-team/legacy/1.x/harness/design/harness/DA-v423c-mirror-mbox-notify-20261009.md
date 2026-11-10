# v423c 구현 DA — r1
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 58aca7b614 · 요청 고정 Q1~Q4 · 라이브 반영 제외.

- Q1 HOLD — _is_reply는 bare #번호∩과거 수신 seq만 검사해 `PR #1027 업데이트입니다`도 받은 seq1027이 있으면 True입니다(tools/comm-canonical/mbox.py:344-361). 같은 받은 seq를 무관한 서로 다른 본문 8개에 반복 인용해도 모두 True인 순수 반례를 독립 확인했습니다; 각각 r=1이라 RATE 셈에서 계속 빠집니다(:374, :414-415). 명시 쪽지 회신 식별/수신 건별 면제 사용 계약이 필요합니다. record/verdict는 동일 함수를 쓰나 사본 회전/조회 실패가 중간에 바뀌면 판정 결과를 공유하지 않는 경계도 구현 시험으로 확인해야 합니다.
- Q2 APPROVE(코드 확인) — 인박스 cls①~④/미상만 notify=1로 올리고 실패/SKIP/미인식 출력은 INBOX_CLS 빈값으로 원래 notify_policy를 유지합니다(tools/comm-canonical/mbox.sh:169-177, :202, :223). 빈 seq/ingest 실패를 삼켜 전송 rc를 바꾸지 않으며 send/relay 동일 분기를 확인했습니다. 기존 agent 생존/doorbell 억제 규칙 자체를 우회하는 승인으로 보지는 않습니다.
- Q3 HOLD — todo의 «할 일» 여부가 아니라 normalized 부분문자열 포함만 검사하고, 검사 전에 110자로 잘라 생성된 뒷부분을 버립니다(mirror_summary.py:39-56). 독립 순수 반례: source=`배포는 이미 완료됐습니다`, todo 동일 → 할 일이 아닌 상태가 todo로 남음; source의 110자 prefix 뒤에 모델이 `새 작업을 시작하세요`를 붙이면 절단 후 원문 포함 조건으로 통과합니다. 원문에서 명시된 할 일 문장/필드만 허용하고 원래 todo 전체를 절단 전에 검증하는 계약·반례 시험이 필요합니다. HIL 강제 todo 생성 지시는 제거됐습니다.
- Q4 HOLD — planner regex·좌석명 번호 제외·첫 유효 스레드 한 번 return은 수락하지만 스레드 존재 검사와 deliver가 분리돼 새 루트 0을 보장하지 못합니다(mirror_board.py:159-165). 다른 미러가 공유 맵에서 그 key를 eviction한 사이 deliver.send가 thread_ts→ensure_thread를 호출하면 make_root로 새 글을 만들 수 있습니다(mirror_deliver.py:81-91, :46-55). 확인한 기존 thread_ts로만 답글 게시하고 매핑 소실이면 건너뛰는 비생성 경로 및 검사 뒤 맵 변경 fixture가 필요합니다. 실제 Slack 호출로 재현하지 않고 코드의 생성 경로를 대조했습니다.

독립 검증은 Q1/Q3 순수 함수 4반례뿐이며 실제 send/RATE 가드 기록·인박스·doorbell·LLM·Slack·라이브 설치 0. arch 기존 pytest 실패목록 동일/키트 시험은 보고 증거입니다. 통합 반송: 회신의 명시/반복 면제, todo 전체/명시 원천, 기존 thread 전용 비생성 게시. 수정은 같은 나노, 설치·모델 공유 영향 결정은 master/planner 범위입니다.

HOLD

## r2
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

Q1 HOLD — 명시 쪽지 표기·send 잠금 안 면제 1회 계산/동일 verdict-record 전달은 수락합니다. 그러나 사용된 seq는 가드 log에만 있고 _guard_record가 마지막 200행만 저장합니다(tools/comm-canonical/mbox.py:374-390). 같은 시간창에 수신 seq10000~10200의 회신 201개를 보낸 뒤 10000을 재인용하면 그 사용 기록이 밀려 _reply_exempt가 [10000]을 다시 반환합니다. log 전체에서는 []·동일 log[-200:]에서는 [10000]인 순수 반례를 독립 확인했습니다; 201개를 순환하면 각 발신이 계속 면제됩니다. 이는 옛 r:int 호환 경계가 아니라 새 r:list의 같은 창 보존 문제입니다. RATE 이력 절단과 분리해 사용한 seq를 보존하거나 보존 한계 도달 시 추가 면제를 닫는 계약·회귀 시험이 필요합니다.
Q3 APPROVE — HIL 라벨/절단 전 whole≤110/원문 문장 집합의 정규화 전체 일치로 이전 꼬리·조각·일반 보고 상태 반례를 닫았습니다(mirror_summary.py:44-72). 독립 순수 5 cases 통과. HIL 안 상태 문장과 옛 r:int의 두 설계 경계는 재심하지 않았습니다.
Q4 APPROVE — reply_only는 정상/resume 모두 existing_thread 조회만 거쳐 키 없으면 WARN/return이며 생성 경로를 호출하지 않습니다(mirror_deliver.py:97-108). post_handled가 만든 item에는 question이 없으므로 _send_item의 question→thread_ts 분기를 타지 않습니다(mirror_board.py:165, byz_mbox_slack_mirror.py:69-75). Q2 재심 없음(기존 수락 유지).

독립 검증은 순수 함수뿐으로 실제 send/RATE 기록·Slack/LLM·doorbell·인박스·제품 Redis·설치 실행 0. arch shell39/34 및 회귀 결과는 보고 증거입니다. 두 번째 HOLD이므로 연속 DA 리뷰 종료·master 통합 이관. 수락 교정: 명시 회신·동일 면제값·todo 전체 검사·reply_only 비생성. 잔여 1개: 같은 RATE 창에서 면제 사용 이력이 200행 절단으로 소실됨.

HOLD
