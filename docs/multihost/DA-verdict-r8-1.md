# DA 판정 r8-1 — 최종 APPROVE

발주 #3032 / 심사자 `aifp-multihost-da-codex#1` / 2026-10-21.
대상: `docs/multihost/DESIGN-multihost-20261021.md`, r8, HEAD `4225b15e8bdc424f99658c460c8ee1a4592e564a`.
원문 SHA-256: `dc68ce73da528e7ac4365f0575cda5f7d09d51b67bcbfc324be5eba3e9f098a1`.
L번호는 이 커밋의 설계 문서 1-based 줄이다. 헌장·r8·직전 r7-1 판정과 운영 UX의 계획 계약 L26–27을 대조했다. r7 이후 변경 diff와 해당 본문을 확인했으며 제품 소스·헌장은 불변이다.

STRUCT: 새 구조 반례 없음. r7-1 N1–N3은 해소됐다. 프로세스 종료 범위·UNKNOWN의 사람 처분·자동 이관 없음·동일 세대 쌍의 큐 커밋 순서를 그대로 수용한다. 아래 IMPL-TEST는 현재 데이터·잠금·전이와 이미 선택한 정책으로 구현할 수 있어 설계 재심의 HOLD로 삼지 않는다. 구현 완료/실제 P3 통과를 승인하는 판정은 아니다.

질문 1: PASS — 단일 모드 불변 L17, 명령 단위 tmuxc 실행 §7, P2 전/후 비교 L304. 이전 PASS 유지.

질문 2: PASS — 고정 호스트 재전송 기한/묘비와 불변 시각 L85, canonical mid DUP L101, 같은 세대 쌍 순서 L105–108. 이전 PASS 유지. 디렉터리 전환의 구체적 게시/복구는 IMPL-TEST T1로 닫는다.

질문 3: PASS — L271의 isolate는 각 호스트 안에서만 격리하고 원격은 건수·seq 목록만 반환한다. JSONL도 끝까지 쓴 임시 파일을 os.replace하므로 기존 `_save`의 truncate 반례를 제거했다. 원격 응답 유실은 원격 보존본을 잃게 하지 않는다. 수신 live/host/evict 상태 검사 L227과 완료 전 EVICT_INCOMPLETE L267–269도 유지된다. 원격 목록의 갱신은 T4 대상이며 본문 소유권 이전 프로토콜을 다시 요구하지 않는다.

질문 4: PASS — 동사별 인증 L227, 로컬 isolate/list --isolated 허용 L234, 실제 포워딩 요청 P1 L303은 기존 PASS 및 새 격리 범위와 맞는다. 원격 격리본은 처분 계약 밖 잔재라는 L271과 운영 UX L27의 구분도 일치한다.

질문 5: PASS — 처분의 고정 단위가 원본의 disp.json으로 옮겨졌고 첫 enqueue 전에 기록된다(L272–274). 기록이 있으면 늦은 정보로 재계획해도 같은 new_mid를 쓰므로 r7 N2의 n1/n2 분기가 사라진다. created_at+7일 밖에서는 전송하지 않는 L274–275가 r7 N3의 완료 묘비 만료 뒤 재전송을 막는다. msg/late/disp.json을 한 디렉터리 rename으로 옮기는 L73·100도 표식 분리 문제를 닫는다. 만료 후에는 기존 처분을 몰래 갱신하지 않고 사람의 완료 표시/중복 감수 새 처분으로 넘긴다는 정책을 수용하며 T2·T3에서 확인한다.

질문 6: PASS — 허브 단절 시 원격 수신/스풀 L102, 최소 저하·단일 호스트 후퇴 L281·294. 이전 PASS 유지.

질문 7: PASS — P0/P1/P2/P6 L302–304·309는 기존 판단 유지. P3 L305의 F13은 로컬 격리/JSONL 중단, F20은 enqueue 후 종료+late+재계획 및 디렉터리 이동, F21은 15일 청소 뒤 DISP_EXPIRED를 명시한다. 아래 조합·경합은 이 P3 및 checker의 구현 닫는 증거로 넘길 수 있다. 새 저장 모델·인증 주체·수신 이관·사람 정책을 정해야 하는 STRUCT 항목은 아니다.

IMPL-TEST T1 — 보관함 디렉터리의 원자 게시/복구. L73의 ①임시 디렉터리 ②msg 이동/쓰기 ③canonical 이름 게시 각 경계에서 프로세스를 중단한다. 새로 쓰는 msg와 disp.json은 완성된 임시 파일만 최종 이름으로 게시해야 하며, 존재한다는 이유로 부분 JSON을 완료로 복구해서는 안 된다. 이것은 기존 임시 파일+link/replace 방식을 적용할 문제다. route DUP 조회·late callback·evict 재개·처분 시작이 canonical 항목을 찾기 전에 해당 .tmp-* 복구를 거치게 하고, 출처가 이미 사라진 tmp/msg만 있는 컷에서도 같은 mid를 새 outbound로 만들지 않음을 검사한다. 본문·표식·기록은 한 항목으로 이동하고 `.tries` 같은 보조 파일을 메시지로 열거하거나 유실된 본문으로 오인하지 않아야 한다. JSONL 재작성 중에는 다른 좌석 행이 모두 남아야 한다. F1/F13/F19/F20의 fault hook으로 닫을 수 있다.

IMPL-TEST T2 — 처분 기록 게시와 동시/오래된 계획. disp.json 게시 직전·직후, enqueue 직전·직후, disposed rename 직전·직후를 끊고 재개해 기록의 new_mid가 하나임을 확인한다. 서로 다른 제안 new_mid를 가진 계획 둘과, record 생성 전에 만든 drop 계획이 나중의 resend 기록과 충돌하는 경우도 포함한다. 현재 자료에 plan action과 disp action이 모두 있으므로 잠금 안에서 충돌을 검출할 수 있다. drop 승인 실행이 조용히 resend 권한으로 바뀌지 않게 불일치를 명시적으로 반환/재계획시키고, 호환되는 재계획은 이미 시작한 같은 처분을 마무리해야 한다. 이는 새 정책 선택이 아니라 고정된 처분/승인 범위의 구현 검증이다. enqueue helper는 L135의 seats→mailbox 잠금 순서를 지키고 이미 보유한 잠금을 다시 얻어 self-deadlock하지 않아야 한다. F20에 결합한다.

IMPL-TEST T3 — DISP_EXPIRED의 사람 반환 경로. F21에서 기한 밖 enqueue 0을 확인한 뒤 두 선택을 실제 승인 계획으로 각각 끝낸다. «완료로 표시»는 새 전송 없이 처분만 끝내고 배달 성공이 확인된 것으로 오표시하지 않는다. «중복 감수 새 처분»은 명시적 승인을 거쳐 새 원본 처분/새 ID로 연결하고, 만료된 disp.json의 created_at/new_mid를 갱신해서 기존 7일 기한을 초기화하지 않는다. 같은 만료 계획을 반복 실행해도 자동 전송은 0이어야 한다. 두 결과는 L274 및 운영 UX L27에서 이미 선택돼 있으므로 분기/CLI/HIL 계획 구현을 확인하면 된다.

IMPL-TEST T4 — 원격 격리 정본과 허브 표시. remote isolate가 JSONL replace까지 끝낸 뒤 응답을 잃는 컷을 넣는다. 재호출/`list --isolated`는 원격 quarantine-local의 실제 보존 목록을 재구성하고, «이번 실행에서 새로 옮긴 행 0»을 «격리본 0»으로 오해하지 않아야 한다. 접속 실패는 UNKNOWN, 확인된 조회는 host/seq와 확인 시각이 있는 관측으로 보여 준다. 허브 목록은 복제된 본문이나 삭제 확인이 아니며 원격 파일을 건드리지 않는다. canonical 정보가 원격에 이미 있어 재조회로 닫을 수 있고 새 분산 정합 프로토콜은 필요 없다. F13 및 운영 조회 시험에 결합한다.

검증 증거: 파일/네트워크 쓰기 없는 메모리 사양 모델에서 원본 disp 기록을 유지한 enqueue→중단→late→재계획은 `r8_enqueue_stop_late_replan_unique=1`, 15일 뒤 완료 영수증 제거 후 기한 검사는 `r8_expired_after_receipt_gc_new_transmits=0`, 항목 전체 이동은 `r8_directory_move_preserves_msg_late_disp=True`였다. 이는 이전 구조 반례가 새 규약에서 제거됨을 보는 모델이며 실제 구현·SSH·APFS/ext4·P3 테스트 결과가 아니다.

도구·범위: Serena 문서 검색은 사용했다. ft-mbox.py의 find_symbol/find_referencing_symbols는 여전히 `path is ignored`로 거절돼 관련 코드 심볼 범위는 `serena unavailable, grep-based`다. 기존 `_save` 및 참조 대조와 소스 불변 확인을 근거로 했으며 Serena 복구 후 참조 범위 재검증 대상으로 남긴다. 이번 작업은 판정문 한 파일 작성뿐이고 제품 우편함은 발주 수신/최종 회신에만 사용했다. 제품 Redis·DOM 시험 데이터 쓰기, 커밋·원격 접속·설치·실제 프로세스 종료·시간 변경·브라우저/오디오 시험은 0이다.

checker 확인 대상: P3 F13/F19/F20/F21에 T1–T4를 결합해 실제 구현 증거를 회수한다. 파일시스템 임시 상태를 정본으로 오인하지 않는지, 동일 처분과 승인 action이 보존되는지, 만료 후 사람 선택이 기한 우회가 아닌지, 원격 보존본과 허브 관측이 구분되는지를 확인한다. 구현이 이 조건을 어기면 그 구현을 HOLD로 돌릴 수 있지만, 현재 설계를 다시 바꿔야 하는 STRUCT 사유는 발견하지 못했다.

최종: APPROVE
