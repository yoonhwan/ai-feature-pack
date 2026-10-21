# DA 판정 r6-1 — 최종 HOLD

발주 #3024 / 심사자 `aifp-multihost-da-codex#1` / 2026-10-21.
대상: `docs/multihost/DESIGN-multihost-20261021.md`, r6, HEAD `19bfac39f9668a99a240e0616d68ffb209b97f81`.
원문 SHA-256: `a620489231a428adf90fc39ba141ed2e2507a57e9435e8376acbe91ba6b3e016`.
L번호는 이 커밋의 설계 문서 1-based 줄이다. 헌장 → r6 → 직전 `DA-verdict-r5-1.md`를 대조했다. 처분 계획이 다른 문서에서 이미 정의됐는지도 `DESIGN-multihost-ops-ux-20261021.md`의 계획/보관함 부분으로 확인했다. 그 문서 전체를 별도로 승인하는 심사는 아니다.

전제: 프로세스 종료까지의 장애 범위(L108)와 결과 모름=사람 처분(L117·266)은 유지한다. 자동 이관 제거 자체를 HOLD 사유로 삼지 않는다. r5의 fence·목록 부재 재조정·export·hold 복귀 반례는 해당 기능 제거 및 새 세대 쌍 순서(L102)로 해소된 것으로 본다. 아래 HOLD는 남겨 둔 경로와 새 evict 절차의 문제에 한정한다.

질문 1: PASS — 단일 모드 코드/출력 보존(L15), 명령 단위 tmuxc 원격 실행(§7), 전/후 비교 P2(L294)는 기존 PASS를 유지한다. 실제 구현 검증이 끝났다는 뜻은 아니다.

질문 2: PASS — 자동 원격 배달의 동일 mid 범위에서 link 생성·rename 소비(L77–81·85), quarantine/disposed까지 포함한 허브 DUP(L98), 같은 수신 세대 쌍 순서(L102–105)가 정합성 근거다. 최초 outbound 호스트를 바꾸지 않고 진입+7일 뒤에는 quarantine으로 끝내므로(L82), 14일 묘비를 넘긴 자동 이관/재export라는 이전 반례는 사라졌다. 발신 스풀의 재전송도 커밋+7일로 제한한 L98을 함께 적용해야 한다. 최초 진입/커밋 시각은 재시도·메타데이터 갱신으로 초기화하지 않는 것이 checker 대상이다. 로컬 세대 혼입은 질문 3, 사람의 처분 재실행은 질문 5에서 따로 다룬다.

질문 3: HOLD — inbound에만 둔 세대 필터가 모든 소비 경로를 닫지 못하고(R1), evict 이후에도 살아 있는 발신자가 evicted 수신자 앞으로 enqueue할 수 있다(R2).

R1 — 기존 로컬 JSONL 경로는 세대 필터를 우회한다. L63은 같은 호스트의 메시지를 기존 mailbox.jsonl에 넣고, L85는 그 경로를 «코드 그대로» recv에 합친다. 실제 `_rows_for`는 to/from만 검사(ft-mbox.py L571–572), recv는 그 행을 `_consume`으로 삭제한다(L592–607). to_gen/FT_SEAT_GEN 검사도 없고 기존 send가 만드는 로컬 행에도 세대가 없다(L465–471). 따라서 같은 호스트에서 같은 이름을 새 세대로 만들었을 때, 로컬 큐에 남은 옛 행은 새 recv가 소비한다. L86의 «FT_SEAT_GEN 없는 사람 recv는 inbound를 소비하지 않음»도 JSONL 소비를 막지 않는다. 실제 기존 함수를 메모리에서 실행해 옛 행이 소비됨을 확인했다.
L95·99의 «원격 좌석끼리도 허브 경유»로 L63의 로컬 경로 범위를 제한하려는 의도라면 그 적용 범위를 명시해야 한다. 그래도 기존 로컬 큐가 있는 호스트의 멀티 모드 진입·좌석 이름 재사용 정책은 필요하다. 멀티 모드에서 JSONL에도 세대를 붙여 필터하거나, 새 세대 생성 전에 기존 이름의 무세대/옛 세대 행을 격리하는 등 한 가지 규칙을 정해야 한다. 단일 모드 변경을 요구하는 것이 아니다. F13(L295)은 inbound 파일만으로 «새 세대 소비 0»을 증명해서는 안 된다.

R2 — route의 수신 대상 검사가 evict의 격리 경계를 다시 연다. L224의 ⑤는 «to가 명부에 있고 retired 호스트가 아님»뿐이며 수신 좌석 live/수신 호스트 active 여부가 없다. 순서: Y의 host-evict가 끝나 Y=revoked, 수신 좌석 R=evicted, 기존 outbound/Y가 전부 quarantine으로 이동(L264) → 새 세대 예약(L265) 전에 정상 발신 X가 R 앞으로 route → source 인증은 통과하고 Y는 retired가 아니므로 ⑤도 통과 → evict가 이미 훑은 outbound/Y에 새 파일이 생긴다. forwarder는 revoked 호스트라 보내지 않아 이 파일은 quarantine에도 없고 정상 전송도 안 된다. readmit 뒤에는 옛 to_gen 대상으로 전송될 여지도 생긴다. 새 세대 필터는 잘못 enqueue된 파일을 뒤에서 건너뛸 뿐 이 라우팅/격리 문제를 해결하지 않는다.
새 메시지의 수신자도 같은 SH 구간에서 live 및 수신 가능한 host 상태인지 검사하고, reserved/evicted/revoked 대상은 명시적 거절 또는 격리 결과로 끝내야 한다. 과거에 이미 접수한 mid의 DUP를 성공으로 돌려주는 경우와, 처음 접수하는 새 mid의 대상 검사는 구분하면 된다. 정상 경로를 재정의할 필요 없이 L224와 L264–265 사이의 상태 조건을 닫는 수정이다.

질문 4: PASS — K1/K2·stdin JSON·동사/PTY 거절 구분을 유지하고, 읽기 전용 inbox list <seat|--spool>가 표 L231과 철수 L279에 모두 있다. P1(L293)은 실제 로컬 TCP 연결을 발생시켜 direct-tcpip 거절을 검사한다. 두 소수정은 설계 수준에서 해소됐다. 수신 대상 인증의 R2는 질문 3의 HOLD다.

질문 5: HOLD — 기록·HIL·원격 잔재 미이동·retired(UNKNOWN) 보고(L276–284)는 적절하다. 그러나 여러 파일을 바꾸는 evict를 같은 EX 잠금 안에서 실행하는 것만으로 프로세스 종료 뒤 완료 경계가 생기지는 않는다(R3).

R3 — L264에서 hosts=revoked/좌석=evicted를 기록하고 outbound m1만 quarantine으로 옮긴 뒤 프로세스가 종료되면, m2는 outbound에 남고 잠금은 해제된다. rollback은 없다. L265는 새 reserve에 «evict의 전체 격리 완료» 조건을 요구하지 않고, L279는 outbound가 이미 모두 격리됐다고 가정한다. 따라서 다른 실행자가 revoked/evicted를 완료 상태로 보고 새 좌석을 만들거나 철수 다음 단계로 진행할 수 있다. L261의 EX 커밋이라는 표현만으로 이 중간 상태와 완료 상태를 구분할 수 없다.
단계 진행 기록과 재실행 규칙을 정해야 한다. 예를 들어 중단된 evict는 이미 이동한 mid를 건너뛰고 남은 outbound를 끝까지 처리하며, 격리 완료 전에는 reserve/retire 완료 선언을 허용하지 않는 방식이면 된다. hosts/seats 저장도 프로세스 종료 시 파싱 가능한 상태로 남기는 원자 교체가 필요하다. 머신 장애 트랜잭션을 다시 요구하는 것이 아니라 이번 보장 범위인 프로세스 종료의 재개 계약이다. P3에는 상태 기록 전후·각 rename 뒤 종료→재개를 넣어야 한다.

사람 재전송 점검(R4): 옛 메시지가 이미 전달됐을 수 있고 새 mid로 다시 보낼 수 있다는 정책(L87·266)은 수용한다. 다만 «처분 한 건의 재실행»은 별도 경계다. 다시 보내기 enqueue 성공 뒤 quarantine→disposed 전에 계획 프로세스가 종료되면 원본은 아직 미처분으로 보인다. 같은 계획을 재실행할 때 매번 새 mid를 만들면 서로 다른 두 새 메시지가 전달되고 route의 mid DUP로는 막히지 않는다. 이는 같은 mid 한 번 소비 약속의 반례라고 주장하는 것이 아니다. 같은 승인 계획의 재개를 새 처분으로 셀 것인지, 동일 처분으로 재개할 것인지 확정해야 한다. 권장 최소 계약은 계획/원본에 재전송 mid를 전송 전에 고정하고 재실행은 그 mid를 재사용하는 것이다. 운영 UX 문서는 h 계획을 만든다고만 하며 이 계약을 추가로 정하지 않았다. F15는 중단 없는 새 메시지 1회만 보므로 이 위험을 놓친다.
또 L97의 늦은 성공 표시와 L266의 disposed 전환도 같은 canonical mid 상태를 잠금 아래 찾아 갱신하도록 해야 한다. 사람이 이미 disposed로 옮긴 항목을 늦은 callback이 quarantine에 다시 만들거나, 표시 실패 때문에 «이미 갔을 수 있음» 정보를 잃지 않아야 한다.

질문 6: PASS — 허브 star와 원격 로컬 수신/발신 스풀(L99), 단일 호스트 후퇴(L271·284)의 이전 PASS를 유지한다. 자동 이관 대신 사람 처분을 택한 비용은 D12(L317)와 보관함 알림에 드러나 있다. 이 선택 때문에 강한 자동 failover 요구를 되살리지 않는다.

질문 7: HOLD — 기존 PASS인 읽기 전용 P0(L292), 실제 포워딩 요청 P1(L293), 마이크 확정 P6(L299)는 유지한다. 추가 닫는 증거는 R1의 로컬/무세대 행을 포함한 F13, R2의 evict 완료~새 reserve 사이 신규 수신 route, R3의 evict 각 파일 작업 중단/재개 및 완료 전 reserve 차단이다. 사람 처분 시험에는 같은 계획이 enqueue 직후 끊긴 뒤 재실행되는 R4와 late_delivered/disposed 경합을 포함해야 한다. 정상 배달 N=200이나 F11의 중단 없는 전량 이동만으로 이 경계를 검증할 수 없다.

검증 증거: 실제 ft-mbox.py를 AST로 읽어 recv/_rows_for/_consume 함수만 실행하고 파일 I/O·잠금·clip을 메모리 스텁으로 대체했다. 출력은 `actual_legacy_path_old_row_consumed=True`였다. 이는 r6가 그대로 유지한다고 한 기존 JSONL 경로의 증거이며 미구현 멀티 recv 전체 실행은 아니다. 문서 조건만 따른 별도 메모리 모델 결과는 `route_target_evicted_after_sweep_accepted=True`, `partial_evict_remaining_outbound=1`, `reserve_has_no_evict_completion_guard=True`, `one_disposition_retry_new_messages=2`였다. 후자의 결과는 사양 반례/위험 예시이며 제품 구현·SSH 실측 결과가 아니다.

도구·범위: Serena 문서 검색은 성공했다. ft-mbox.py의 find_symbol/find_referencing_symbols는 `path is ignored`로 거절돼 해당 코드 심볼 범위는 `serena unavailable, grep-based`다. 앞서 전수 대조한 send/recv/_consume/_rows_for/_locked 참조와 실제 함수 본문을 근거로 했고, 제품 소스·헌장은 r5 기준 커밋 이후 불변을 git diff로 확인했다. Serena 복구 후 참조 범위는 재검증 대상으로 남긴다. 제품 Redis·DOM에 시험 데이터를 쓰지 않았으며 제품 우편함 조작은 발주 수신/최종 회신뿐이다. 실제 프로세스 종료·시간 변경·원격 접속·설치·브라우저/오디오 시험은 0이다. 쓰기는 이 판정문 한 파일, 커밋 0이다.

checker 확인 대상: R1 모든 소비 경로의 세대/무세대 행 정책, R2 신규 target의 live/host 상태와 기존 mid DUP의 분리, R3 evict 진행/완료 및 재실행 경계, R4 동일 처분 계획의 재전송 mid와 late callback의 canonical 상태 갱신을 확인한다. 같은 호스트 최초 7일 기한과 14일 묘비의 기존 수명 증명, 사람 처분 및 프로세스 종료 범위는 유지해도 된다.

최종: HOLD
