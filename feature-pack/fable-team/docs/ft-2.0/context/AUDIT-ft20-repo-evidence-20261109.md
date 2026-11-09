# 저장소 조사 재점검: 완료 범위와 남은 검증

사용자 요청: arch·DA 협의로 추천안을 정리하고 인터뷰 답변 뒤 결론을 작성하기 전에, repo 조사가 실제로 어디까지 끝났는지 재확인한다.
판정: **비교용 정적 조사 산출은 완료했고 핵심 코드 경로를 다시 확인했다. 저장소 전수 검토·실행 검증·장애 안전성 확인까지 완료한 것은 아니다.** 원안 3개도 큰 운영 모델은 2계열이며 DA/Astra는 같은 팀 상태 직렬화 모델의 저장 전략 변형이다.
메인: 현재 Astra. 이번 작업은 읽기 전용. 저장소 설치·빌드·외부 서비스 호출·Slack 송신·제품 변경 없음. `ci doctor` smoke OK, 좁은 경로의 ci 검색/호출자와 필요한 줄 읽기를 사용했다.

## 1. 저장소와 원자료 보존

| 대상 | 고정 SHA 재확인 | 로컬 위치 | 변경 여부 |
|---|---|---|---|
| OMO | 511dc35e22a7c4e2cebb8f0c5bab74b8660dc430 | /tmp/ft-2.0/repos/oh-my-openagent | git status --short 빈 출력 |
| gajae-code | b4127889c4a849133f868cbf8f4d5a65126baec4 | /tmp/ft-2.0/repos/gajae-code | git status --short 빈 출력 |

원래 조사 나노의 r1488/r1489 worktree 경로는 정리되어 더는 없다. 조사 내용은 Git commit c80279585d/db554d3112에 있고, 두 조사·현행 비교·checker 문서4개가 현재 harness-ops의 `design/harness/research/ft-2.0/`에 있음을 확인했다. 외부 저장소 clone도 그대로 있다. worktree 경로가 없다는 것과 산출물 소실을 구분한다.

## 2. 이번에 소스로 다시 확인한 핵심

| 항목 | 소스 근거(위 고정 SHA) | 재확인 결과와 해석 |
|---|---|---|
| OMO 메모리 주입 | packages/memory-core/src/compile/compile.ts:24,36,61 | HEAD 또는 지정 revision에서 compile. 세션의 고정 시각으로 expiry를 평가할 수 있고 degraded 이유를 남긴다. commit별 메모리 주입 구조는 확인. 실제 토큰·품질·복구는 미측정 |
| OMO 부모 상태별 회수 | packages/senpi-task/src/completion/routing.ts:20 | idle은 wake, streaming은 deliver_streaming, compacting/switching/shutdown은 buffer로 분기 |
| OMO 완료 통지와 재시작 | packages/senpi-task/src/completion/notifier.ts:95,114,135,154,186 | run_epoch와 notified_epoch, 전달 실패 시 epoch 되돌림, 세션 재시작 때 미통지 결과 재탐색이 있다. buffer는 메모리 Map이며 재시작 복구는 영속 task 기록에 의존한다. replaced flush는 dropped 기록을 남기는 별도 경로다. «무조건 유실0·정확히1회»로 줄이면 안 됨 |
| gajae Slack 접수 순서 | packages/coding-agent/src/sdk/bus/slack-daemon.ts:496~543 | 허용된 inbound는 claim → transport ACK → dispatch. 부적합·미인가 입력은 ACK만 하고 처리하지 않는 분기가 있다. 모든 ACK가 업무 접수 성공이라는 뜻은 아님 |
| gajae 효과 보존 | packages/coding-agent/src/sdk/bus/chat-effect-journal.ts:10,112,145,475 | 기본 terminal retention128. 정리 시 mapping에서 참조 중인 terminal은 삭제하지 않고 nonterminal도 보호한다. **128이 전체 파일/효과 총량의 절대 상한은 아니다.** 실제 disk full·오래된 재전달 안전성은 별도 확인 필요 |
| gajae 메모리 기본값 | packages/coding-agent/src/memories/index.ts:67~85, config/settings-schema.ts:2329~2354 | 기본 off, stage1Concurrency8, stage1 lease120초, phase2 lease180초·heartbeat30초. 원 조사 미확인 목록의 기본값 항목을 정적 근거로 보완 |
| gajae phase2 소유권 | packages/coding-agent/src/memories/storage.ts:394~452,479~491 | cwd별 job key, lease·watermark·재시도 조건부 UPDATE, ownership_token으로 heartbeat/확정 범위를 제한. 자동 실행 성공이나 전원손실 검증은 아님 |
| gajae master snapshot 시점 | packages/coding-agent/src/master-mode/first-request.ts:69~101, snapshot.ts:22~27 | 최초 accepted provider request 직전에 수집하는 contributor. persisted injection이 있으면 재주입하지 않음. snapshot 자체를 주기적인 현재 상태 감시로 해석하지 않는다. 원 조사의 호출 지점 미확인을 보완 |

소스 줄을 읽은 사실은 해당 구현의 실행 보장이 아니다. OMO의 «1회 통지», gajae의 «중복 주입0·효과1회»라는 기존 조사 요약은 조건부 설계 설명으로 제한한다. 이번에는 이들의 테스트를 실행하지 않았다.

## 3. 아직 끝나지 않은 확인

| 남은 항목 | 상태 | 선택에 미치는 영향 |
|---|---|---|
| OMO DAG WAL의 외부 부수효과 복구, omo-thread offline 큐 상한·drop | 정적 조사 미완. openclaw-core의 queueOffline 검색 무결과는 전체 부재 증거 아님 | 이 구현을 그대로 가져오거나 유실/정확히1회 근거로 쓰지 않음 |
| OMO 모든 하네스의 턴/멈춤 판정, 권한·Slack 확장 전체 | 원 조사 범위에서만 확인. 파일명/검색 무결과로 전체 부재 단정 불가 | 기존 ft 우위·외부 기능 부재 주장의 범위를 제한 |
| gajae 부모 사망 뒤 subagent 결과 회수, ultragoal 실제 승계 | 코드 경로 추적/실행 미완 | 해당 승계 구현을 채택 근거로 쓰지 않음 |
| gajae Slack 재접속·만료 dedupe·rate-limit·권한의 실동작 | 코드·문서 조사만. 실제 Slack 연결0 | 전송 어댑터 선택 뒤 별도 계약 검증 필요 |
| 두 repo의 전원손실·외부 효과·동시 실행 보장 | 실행0 | 파일 실험이나 제품 안전성 통과로 인용 금지 |
| 토큰·캐시·메모리 품질·장기 보존 비용 | 미측정 | 호출 수만으로 비용 우위 또는 무손실 기억을 선언하지 않음 |

현재 추천은 외부 구현 전체 이식이 아니라 확인된 계약(접수/실행 분리, 세대, 보호 기록, 작은 주입)을 우리 기존 ft에 맞춰 최소 상태 모델로 실험하는 것이다. 따라서 위 미완을 전부 새 조사 라운드로 늘리지 않는다. 실제로 채택하려는 메커니즘의 안전성에 필요한 항목은 해당 실험/적용 단계의 닫는 조건으로 남긴다.

## 4. 현행 ft 대조에서 확인된 정정

지원자: `aifp-ft-master-pi#2`. 근거는 `/tmp/ft-2.0/STATUS-aifp-ft-20261109.md` 및 addendum, 쪽지275393·275403. 메인이 문서를 회수했으며 이번에 모든 설치 경로를 직접 재실행한 것은 아니다.

- lessons/evolution·Slack mirror·seat binding은 존재한다. 새 기능이 전혀 없다는 비교는 철회한다.
- 리포와 live가 같은1.1.291 표기여도 bin4개 내용 차이, comm 차이, kakao1.1.287이 있다. 버전 번호만으로 마이그레이션 기준선을 삼지 않는다.
- 일반화는 일부 LATEST·색인 도구가 있고, 공통 jsonl-reader·일반 compact는 지원자의 확인 범위에서 미발견이다. 기존 PLAN 전체 구현/적용 완료가 아니다.
- 지원자의 확인 범위에서 `ft_seat_bind --expect`는 Pi close에서 호출되며 집행 전 전면 적용은 확인되지 않았다. 구형 명부·큐 writer를 전환 때 막는 전용 입구도 확인되지 않았다.
- 따라서 일반 파일 잠금 또는 실험 대역의 owner 거절 성공을 실제 모든 도구·Bash의 쓰기 권한 통제로 확대하지 않는다.

## 5. 인터뷰와 결정문에 사용할 결론

«repo를 다 확인했으니 안전하다»는 문장을 쓰지 않는다. «비교 조사와 핵심 소스 재확인 완료, 미확인 범위 공개, 선택 후보의 실제 계약은 별도 반증»으로 쓴다.
arch·DA 공동 추천, 사용자 인터뷰 답변, 최소 격리 실험 판정, aifp 설치 제약을 각각 근거로 붙인다. 사용자 답변 전에는 선택 결정문을 완료 처리하지 않는다.
