# BYZ GPU 사용 경로 — KakaoBot#0 확인 (2026-09-09)

이 문서는 요청받은 정보 중 **실물로 확인된 것만** 담는다. 확인 안 된 항목은 그렇게 표시했다 — 추측으로 채우지 않았다.
GPU 재시작/변경 요청 아님, 사용경로 확인만.

## 1. 정본 위치

- `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents`(로컬 경로, "howtotalk"은 이 프로젝트를 가리키는 것으로 보임 — 명칭 자체는 재확인 못함)
- 읽을 문서: `.claude/plans/d4-gpu-vm-control-design.md`(GCE 제어 설계, 출처 최상위) + `harness/evidence/BYZ/api-spec-research.md`(KakaoBot 쪽 — OpenAI 호환 API 스키마 조사, **실서버 값 아닌 웹조사 기반**)

## 2. GCP — 확인됨

| 항목 | 값 | 출처 |
|---|---|---|
| zone | `asia-northeast3-a` | d4-gpu-vm-control-design.md:151 |
| LLM 인스턴스 | `byz-agents-gce-llm-dev` | 같은 문서 §0,§1-3 |
| STT/TTS 인스턴스 | `byz-agents-gce-stt-tts-dev` | 같은 문서 |
| project 식별자(숫자) | `1024379410733`(서비스어카운트 접두사로만 확인, project-id 문자열은 미확인) | 같은 문서:48 |
| 자동 종료 | `maxRunDuration` 12시간(43200s) — **누가 어떻게 기동해도 적용**, 별도 구현 불필요 | 같은 문서 §1-3, §7-1 |

## 3. IAP 터널 — ★검증된 형태만★

문서가 스스로 "이 형태가 실제로 검증된 것 — `start-iap-tunnel <VM> <port>` 단축형 아님"이라 명시:

```
gcloud compute start-iap-tunnel byz-agents-gce-llm-dev     8000 --local-host-port=localhost:8002 --zone=asia-northeast3-a &
gcloud compute start-iap-tunnel byz-agents-gce-stt-tts-dev 8100 --local-host-port=localhost:8100 --zone=asia-northeast3-a &
```

★불일치 발견★: 다른 위치(같은 프로젝트 내 §151 부근)에 STT/TTS 로컬포트가 `8001`로 적힌 곳도 있었다 — 어느 쪽이 현재 유효한지 **문서 두 개가 서로 다르다**. 실행 전 오빠에게 직접 재확인 필요.

## 4. 게이트웨이 제어 API (직접 gcloud 대신 이 경로가 있을 수 있음)

```
GET  /api/v1/gpu/vm/status
POST /api/v1/gpu/vm/{target}/start   (target = llm | stt-tts | all, require_admin)
POST /api/v1/gpu/vm/{target}/stop    (require_admin)
```
게이트웨이 자체 SA는 Compute 권한이 ★없음★(aiplatform·secretmanager 등만) — VM 시작/정지는 별도 SA(`byz-gce-scheduler-start@…`)나 사람의 `gcloud` 권한이 필요. IAM에 `iap.tunnelResourceAccessor`·`compute.instanceAdmin.v1`·`aiplatform.user`·`secretmanager.secretAccessor` 롤이 잡혀 있음(같은 문서:269) — **인증은 gcloud ADC(Application Default Credentials) + IAM 롤 기반으로 보이나, 정확한 절차 문서는 못 찾음**.

## 5. 모델 API 규격 (BYZ-001 웹조사, 실측 아님)

OpenAI 호환: `POST /v1/embeddings`, `POST /v1/chat/completions`. `base_url=http://<host>:<port>/v1`, `Authorization: Bearer <api_key>`(env `BYZ_*_API_TOKEN`/`BYZ_*_BASE_URL` — SEC-001, 변수명만이지 실제 존재 여부 미확인).

## 6. ★확인 못한 것 — 오빠 직접 확인 필요★

- 정확한 임베딩 모델 ID·revision·실제 임베딩 차원·context 토큰 상한 (grep으로 못 찾음, "1536" 등은 무관 라이브러리 예시코드에서 나온 값이라 신뢰 불가 — 배제)
- LLM 모델 ID·revision
- IAP 로컬포트 8100 vs 8001 불일치의 정답
- 인증 절차의 정확한 변수명·발급 방법(SA 롤만 확인, 실행 스텝은 못 찾음)
- "howtotalk"이라는 이름이 이 프로젝트를 가리키는 게 맞는지
