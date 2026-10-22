# 설계 1장 — mini·OCI 자체 IAP 터널 (호스트별 새 서비스 계정 · 최소 권한)

골 축 원문(발주 #3189): «두 곳에서 CLI 로 실제 운용» + «시험 이관» — mini 시험 서버 worker 가 LLM·STT·TTS GPU 워커에 닿아야 1회차가 돈다.
상태: 읽기 전용 실측 완료 · 쓰기(SA 생성·IAM) 0 · DA 전 초안.

## 1. 실측 (이 맥 gcloud 읽기 전용 · 2026-10-22 · 프로젝트 byz-agents-484214)

| 항목 | 실측 |
|---|---|
| 지금 터널 4개의 계정 | 전부 `--account=byz-local-dev@…` (launchd plist 인자) |
| byz-local-dev 프로젝트 역할 10개 | artifactregistry.reader · **compute.instanceAdmin.v1** · **compute.securityAdmin** · **iam.serviceAccountUser** · iap.tunnelResourceAccessor · logging.logWriter · logging.viewer · run.viewer · **secretmanager.secretAccessor** · viewer |
| 인스턴스 IAM(llm-dev·stt-tts-dev) | 스케줄러 SA 1개뿐 — 인스턴스 단위 바인딩 없음 |
| SSH 방식 | OS Login 아님. 프로젝트 메타데이터 `ssh-keys` 에 사용자 1개(`yoonhwan`). `gcloud compute ssh` 는 키 추가를 위해 메타데이터 쓰기 필요 → instanceAdmin.v1 + serviceAccountUser 가 그래서 붙어 있음 |
| 방화벽 | `byz-agents-allow-iap-dev`: IAP 대역(35.235.240.0/20) → tcp 22·8000·8100 허용 |

## 2. 터널 4개가 실제 필요로 하는 것

| 터널 | 지금 방식 | 필요한 것 |
|---|---|---|
| 18703 → llm-dev:8000 | start-iap-tunnel | IAP 터널 권한만 |
| 18712 → stt-tts-dev:8100 | start-iap-tunnel | IAP 터널 권한만 |
| 8001 → stt-tts-dev 의 localhost:8000 | compute ssh -L | 방화벽이 IAP→8000 을 이미 허용 → ★start-iap-tunnel stt-tts-dev 8000 으로 바꾸면 ssh 불필요★ |
| 38309 → 10.2.0.10:5432 (DB) | compute ssh -L | VM 을 경유한 포워딩이라 ssh 필요 — 유일한 ssh 터널 |

## 3. 설계 (복사하지 않고 줄인다)

- 호스트별 SA 2개(mini용·OCI용). byz-local-dev 의 10개 역할을 그대로 복사하지 않는다.
- 부여 역할: `roles/iap.tunnelResourceAccessor` 만(★DA r1: IAP 는 `resource.name` 조건 미지원 → IAP 터널 리소스(VM별)에 직접 바인딩 + `destination.port` 조건: llm-dev 8000, stt-tts-dev 22·8000·8100★). 키 발급은 SA 당 1개.
- ssh 터널 1개(DB)는 `gcloud compute ssh` 대신 `ssh -o ProxyCommand="gcloud compute start-iap-tunnel stt-tts-dev 22 --listen-on-stdin …"` — 이 경우 SA 는 메타데이터를 쓰지 않으므로 instanceAdmin·serviceAccountUser 불필요. 대신 호스트별 전용 ssh 공개키를 ★stt-tts-dev «인스턴스» 메타데이터 ssh-keys 에만★ «사람이 h-A 에서 1회» 추가(DA r1·반영) — 기존 인스턴스 키 목록을 읽어 «보존한 채 추가»(덮어쓰기 금지) · block-project-ssh-keys 는 건드리지 않음(yoonhwan 키 유지). 롤백 = 그 줄 제거.
- 8001 은 ssh 가 아니라 start-iap-tunnel(8000) 로 교체. ★DA r1: 보류 — 기존 ssh 는 VM 안 localhost:8000, IAP 직접은 VM nic0 내부 IP:8000 이라 리스너가 127.0.0.1 전용이면 실패. h-A 시험에서 같은 요청·응답으로 입증되기 전엔 기존 ssh -L 방식 유지.★
- 비밀: SA 키는 화면 출력 0 · 0600 임시 파일 → ssh stdin 으로 호스트 0600 · 이 맥 임시본 삭제.

## 4. 미확정 (h-A 에서 새 SA 로 «실제로 돌려 보기» 전엔 모름)

1. `start-iap-tunnel <인스턴스명>` 이 인스턴스 조회(compute.instances.get)를 요구하는지 — 요구하면 `roles/compute.viewer` 를 인스턴스 한정 조건으로 추가.
2. IAM 조건으로 인스턴스 한정이 IAP 터널 역할에서 실제로 먹는지.
3. DB 5432 가 stt-tts-dev VM 에서 10.2.0.10 으로 닿는 방식 그대로 ProxyCommand ssh 에서도 되는지(지금 ssh -L 과 같은 경로라 가능성 높음).

## 5. h 순서 (제안 · 각 h 는 하나씩 오빠 승인)

- h-A (이 맥): SA 2개 생성 + 역할 + 키 2개 → 0600 임시 + 전용 ssh 키 공개부 프로젝트 메타 추가. 롤백(키·SA·ssh-keys 줄 삭제)은 HIL 로 분리 표기. ★생성 직후 새 SA 로 §4 세 가지를 이 맥에서 먼저 시험해 부족한 역할만 보탠다★.
- h-B (mini): gcloud 사용자 설치(sudo 0·버전 고정) · SA 활성화 · 터널 4개 launchd 상주 · 포트 LISTEN + health(7초 룰) 증거.
- h-C (OCI): 같은 구성 · systemd --user.
- h381: LOCAL_VLLM_BASE_URL 등 env 이름은 이 맥 server.sh 와 같게, 38309 역방향 포워딩은 mini 자체 터널로 대체.

## 6. DA 권고

IAM 변경(SA 생성·역할·프로젝트 ssh-keys 수정)이라 1회 권장. 질문 후보: ① 역할 최소성 ② 프로젝트 ssh-keys 추가의 범위(전 인스턴스에 키가 퍼짐) ③ 키 수명·회수.

## 7. DA r1 판정 HOLD 반영 (gpt-6.1-sol · headroom · 출력 첫 줄 «판정: HOLD»)

| DA 지적 | 반영 |
|---|---|
| 1 `resource.name` 은 IAP 미지원 / compute.instances.get·list 필요 여부는 SDK 동작 의존 | VM별 IAP 리소스 바인딩 + destination.port 조건. gcloud SDK 버전·`--project`·`--zone`·`--account` 고정. 조회 권한 «없는» 새 SA 로 연결·재연결 입증 — 실패하면 커스텀 역할(get 만) 설계 |
| 2 ssh 키는 인스턴스 메타데이터에만 · 기존 키 보존 | 위 §3 반영. 호스트별 키 2줄(mini·OCI) |
| 3 키 수명·회수 부재 | 호스트↔SA↔키 ID 표 + 교체 주기 + 교체 절차(새 키 검증 후 기존 비활성→폐기) + 유출 시 SA 키 차단·ssh 키 제거 각각 + 열린 포워딩 종료 확인. JSON 키는 «기한 있는 과도기안», WIF 는 신뢰 IdP 경로 미입증이라 후속 |
| 4 8001 교체 동등성 미입증 | 보류(§3). 시험으로만 해제 |
| 5 DB 전용 키가 일반 ssh 로 확대 | 전용 Linux 사용자 · sudo 금지 · authorized_keys `restrict,port-forwarding,permitopen="10.2.0.10:5432"` · 셸 불가 |
| 6 무인 재기동·유휴 단절 | OCI `loginctl enable-linger` · mini LaunchAgent 로그인 세션 의존 확인 · keepalive·backoff · IAP 1시간 비활성 단절 후 «실제 요청 복구» 를 합격 기준에 |
| 7 거짓 통과(기존 계정·기존 포트) | 시험은 전용 `CLOUDSDK_CONFIG` + 명시 계정 · 포트 소유 프로세스 확인 · `ExitOnForwardFailure=yes` · loopback 고정 · LISTEN 만으로 통과 금지(새 SA 연결 증거+API 응답+DB 쿼리) |

DA 카운터: 이 설계 보류 1회.
