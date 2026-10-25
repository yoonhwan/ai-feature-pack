골(원문 발췌): 「…두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고…」(오빠 2026-10-21) · 「DB 경로: 읽기 전용 검증부터」(오빠 2026-10-25)
골의 어느 축: «시험 이관» 의 남은 의존 하나 — mini 서버의 DB 길이 이 맥 역방향 포워딩(38309)에 걸려 있다. 닫는 증거 = mini 가 이 맥 없이 DB 에 닿는 것(mini 자체 IAP 길 1개 + 러너 통과).

# DB 경로 읽기 전용 검증 (2026-10-25 · aifp-multihost-master-claude#4 · 쓰기 0 · gcloud 읽기 명령만 · developer.ts 계정)

## 확인한 사실
| 항목 | 값 | 근거 |
|---|---|---|
| 이 맥의 DB 길 | `gcloud compute ssh byz-agents-gce-stt-tts-dev --tunnel-through-iap -- -N -L 38309:10.2.0.10:5432` (launchd `com.byz.loom-pg-tunnel` · SA byz-local-dev) | `~/Library/LaunchAgents/com.byz.loom-pg-tunnel.plist` |
| DB | Cloud SQL `byz-agents-postgres-prod` 사설 IP 10.2.0.10 (옆에 `-dev` 10.2.0.3 · `-ccu` 10.2.0.19) · 상위 판정(#3202): «이름만 prod, 실제 dev 런타임» | `gcloud sql instances list` |
| 중계 VM | `byz-agents-gce-stt-tts-dev` · g2-standard-8 · COS · 내부 IP 10.0.0.9 · 메타데이터 키 3개(container-env · container-image · startup-script) · 이 VM 은 GPU STT/TTS 를 서빙 | `gcloud compute instances describe` |
| VM → DB 도달성 | 되고 있다(이 맥 터널이 매일 이 경로로 10.2.0.10:5432 에 닿음) | launchd 터널이 상시 동작 |
| mini 의 IAP 권한 | SA `byz-mini-tunnel` = `roles/iap.tunnelResourceAccessor` **조건부**: 목적지 IP+포트 쌍만(10.0.0.8:8000 · 10.0.0.9 의 8000 등). **22 와 DB 포트는 없다** | `gcloud projects get-iam-policy` |
| IAP 방화벽 | `byz-agents-allow-iap-dev`: 35.235.240.0/20 → tcp 22·8000·8100 (DB 용 포트 없음) | `gcloud compute firewall-rules list` |

## 그래서 mini 가 DB 에 닿으려면 («추가만» 3가지 · 아직 하나도 하지 않음)
1. **포워더 1개**: 10.0.0.x 의 한 곳에서 `0.0.0.0:<전용포트>` → `10.2.0.10:5432` 로 넘기는 TCP 포워더. 위치 2안 — ⓐ 새 e2-micro VM(`byz-db-fwd`, 같은 VPC) ⓑ 기존 GPU VM(10.0.0.9)의 컨테이너/startup-script 추가.
2. **방화벽 1줄**: 35.235.240.0/20 → tcp:<전용포트> (대상 태그 한정).
3. **IAP 조건 1줄 확장**: `byz-mini-tunnel` 의 조건식에 `(destination.ip == <포워더 IP> && destination.port == <전용포트>)` 추가.
- 그 뒤 mini 는 기존 방식(h101·h215 처럼 자체 launchd `start-iap-tunnel`)으로 38309 를 로컬에 연다 → 이 맥 의존 0.
- DB 인증(계정·비밀번호)은 지금처럼 mini 가 가진 DSN 그대로 — 이 경로는 «길»만 연다.

## 안 한 것·모르는 것
- **ⓑ(GPU VM 에 포워더)는 권하지 않는다**: COS 읽기 전용 루트라 startup-script 로만 영구화되고 STT/TTS 서비스 VM 의 재부팅·충돌 위험이 생긴다(리서치 나노 Q2 «추정»). ⓐ 가 STT 서비스와 분리돼 안전하다 — 단 새 VM 1대 비용(e2-micro 월 수 달러대 «추정 · 미검증»).
- 방화벽 대상 태그 방식·VPC 서브넷·`byz-db-fwd` 이름 충돌·조직 정책(외부 IP 금지 등)은 확인하지 못했다. 쓰기 단계 전에 읽기 전용으로 한 번 더 확인한다.
- 참고(범위 밖·미검증): 방화벽 목록에 `default-allow-ssh`·`default-allow-rdp` 가 0.0.0.0/0 로 있다 — 어느 네트워크에 붙은 규칙인지(네트워크 열)는 보지 않았다.

## 오빠 승인이 필요한 변경 (실행은 `! bash /tmp/h<N>` · gcloud 계정 developer.ts 고정)
| # | 변경 | 되돌림 |
|---|---|---|
| 1 | `byz-db-fwd` VM 생성 + 포워더 기동 | VM 삭제(HIL) |
| 2 | 방화벽 규칙 1개 추가 | 규칙 삭제(HIL) |
| 3 | `byz-mini-tunnel` IAP 조건식 1줄 확장 | 이전 조건식 복원 |
