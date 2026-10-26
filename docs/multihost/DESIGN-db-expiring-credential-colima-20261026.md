「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스에 tailscale 연결, cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영」(오빠 2026-10-21)
「DB 경로: 읽기 전용 검증부터」(오빠 2026-10-25)
골의 어느 축: «시험 이관(mini 러너)» 의 남은 의존 하나 = mini 서버가 DB 에 닿는 길(지금은 이 맥의 역방향 포워딩 38309 에 걸려 있음) + 서버 묶음을 어떻게 mini 로 보내 운영하나.

# 설계 — 만료 열쇠(이 맥이 하루 1회 열어 주는 DB 길) + 콜리마 도커 세트(mini 와 이 맥 같은 묶음)

> ★분할됨(master #3311 · 2026-10-26) — 이 파일은 **r1~r3 심사본·반영표(역사 기록)** 이다. 현행 정본은 두 카드: 카드 하나(DB 길 열쇠 · DA r3 APPROVE 조건 반영) = `DESIGN-db-key-vm-cycle-20261026.md` · 카드 둘(콜리마 도커 세트 · 초안) = `DESIGN-colima-docker-set-20261026.md`. 아래 본문의 `STOPPED`·감독 3회·정지 90초 같은 옛 수치는 반영표 안의 역사 기록이며 실행 기준이 아니다(실행 기준 = 카드 파일).★

작성: aifp-multihost-arch-claude#2 (Fable 5.1 팀 좌석) · 2026-10-26 · 발주 #3305(= `ORDER-arch-db-expiring-colima-20261026.md`) · **r3(DA r1 HOLD 13건 + DA r2 HOLD 10건 반영 · §11)**
★오빠 결정(쪽지 #3309 · 2026-10-26): 열쇠 창 = **14시간 · 하루 2회 끄고 다시 켜기**(하루 두 번 1~2분 DB 단절 수용) · 이 맥 자신의 DB 터널은 **그대로**. 아래 본문은 이 결정 기준으로 쓴다.★
조사 = 읽기 전용만(gcloud 읽기 · ssh mini 읽기 · BYZ 리포 읽기). 쓰기·원격 변경·키 값 출력 0. 커밋·push 는 master 집행.
오빠 지시 원문 5줄은 발주서 §오빠 지시 원문 그대로 따른다(「이 맥이 키」·「만료를 넣고 하루 1회 적용·부팅」·「콜리마 도커 세트로 박싱」·「로컬도 마찬가지」·「패블팀 좌석」).

## 0. 결론 (첫 줄)

**가능하다.** 열쇠는 «포워더 VM 을 이 맥이 **하루 2회 끄고 다시 켜고**(새 가동 주기 · 08:07·20:07), VM 은 최대 가동 시간 **14시간**이 지나면 Google 이 스스로 끈다» 로 건다. 이 맥이 꺼져 있으면 다음 재기동이 없어 창이 닫히고, mini 는 DB 에 못 닿는다(닫힘 쪽으로 실패). 요구를 정확히 적으면 「이 맥의 최근 승인(재기동)에 따라 **DB 길만** 일정 시간 허용」이다 — 「이 맥이 없으면 즉시 아무것도 못 함」은 아니다(§4 · DA r1 #7). 도커 박싱은 DB 길과 **별개 문제**이고 메모리는 더 든다(이 맥 실측: 콜리마 VM 본체 RSS 1,477MB). 그래서 **DB 길 → 도커** 순서로 들어간다.

## 1. 가능/불가 판정과 이유 (꼭 답할 것 1)

**가능.** 근거 3개(오늘 읽기 전용 실측).
- 열쇠를 걸 자리가 이미 있다: 이전 안의 «새 VM byz-db-fwd + 방화벽 1 + IAP 조건 1»(`VERIFY-db-path-20261025.md`)에서 mini 의 DB 길은 **포워더 VM 하나에만** 걸린다(단, 지금의 역방향 포워딩을 반드시 걷어야 유일해진다 — §3 끝 · DA r1 #8).
- Google 이 만료를 강제하는 수단이 있다: `--max-run-duration`(«VM 이 마지막으로 켜진 때부터 상대 시간» · `instances create` 도움말 658행) + `--instance-termination-action=STOP`(546행). ★`instances update` 에는 이 플래그가 **없다**(오늘 도움말 확인) → 가동 중 갱신 불가 → 하루 절차는 «켜기» 가 아니라 **«끄고 켜기»** 다(§6).★ mini 의 SA 는 IAP 터널 권한뿐이라 이 시계를 못 만진다(프로젝트 IAM 실측: `byz-mini-tunnel` 바인딩은 `roles/iap.tunnelResourceAccessor` 조건부 1개뿐. 단 **그 바인딩만으로 mini 가 인스턴스 이름으로 IAP 터널을 이미 열고 있다** — mini launchd `com.byz.iap-tunnel-llm` 가동 중 실측 · 즉 별도 compute 조회 권한 없이 동작함).
- 이 맥이 매일 끄고 켤 권한이 이미 있다: 이 맥의 SA `byz-local-dev` 에 `roles/compute.instanceAdmin.v1`(프로젝트 IAM 실측). 새 권한 추가 0.

트레이드오프(오빠 원문 1 「느리고 절차가 복잡」): 하루 2회 «끄고 켜기» 는 자동(launchd)이라 손은 0 이고, 비용은 **매일 두 번 정해진 시각에 DB 길 단절 회당 ≤ 120초**(정지 → TERMINATED → 기동 → 첫 DB 응답)이다(예산 §6).

## 2. 만료를 «어디에» 거는지 — 후보 5안 비교 (꼭 답할 것 2)

| 안 | 무엇을 매일 하나 | 만료 강제 주체(mini 가 어겨도 막히나) | 이 맥이 꺼져 있으면 | 하루 절차 실패 시 | 필요한 권한·변경(추가만?) | 되돌림 |
|---|---|---|---|---|---|---|
| **VM 하루 재기동** (추천) | 이 맥이 `instances stop` → `start byz-db-fwd`. VM 은 `--max-run-duration` + `STOP` 으로 스스로 꺼짐 | **Google(Compute)**. TERMINATED(정지 완료) 뒤엔 그 VM 을 지나는 신규·기존 전달 모두 불가(정지 요청→TERMINATED 사이 수십 초 지연은 있다 · §4) | 재기동 없음 → 창이 끝나면 닫힘 | 닫힘(안전한 쪽) | 이전 안 3가지 + VM 생성 플래그 2개 + 내부 고정 IP 1개. 이 맥 쪽 새 IAM 0 | VM·방화벽·고정 IP 삭제(HIL) · IAP 조건식 원본 복원 |
| **IAM 시간 조건** | 이 맥이 mini SA 의 IAP 조건식에 `request.time < timestamp("내일")` 을 매일 갱신 | Google(IAM). ★이미 열린 IAP 세션이 만료 뒤에도 살아 있을 수 있다 [확인 필요]★ | 새 연결 거부 | 닫힘 | 이 맥 자동화 자격에 **프로젝트 IAM 쓰기**(setIamPolicy)가 필요 — `byz-local-dev` 에 없다 → 강한 권한 «추가» | 조건식 복원 |
| **단기 토큰 전달** | 이 맥이 mini SA 액세스 토큰(기본 1시간 · 최대 12시간)을 mini 로 전달 | Google(토큰) | 닫힘 | 닫힘 | `serviceAccountTokenCreator` · 12시간 넘기려면 조직 정책 → **«하루 1회» 불가** | 만료 |
| **하루 키 교체** | 만료일 박힌 X.509 공개키 업로드 + 개인키 전달 + 어제 키 삭제 | Google(키) [확인 필요: 업로드 키 `validBeforeTime` 이 인증서 만료를 따르는지] | mini 의 **LLM·STT 까지** 닫힘(범위가 넓다) | 닫힘 | `serviceAccountKeyAdmin` · mini 원격 쓰기 매일 | 상시 키 환원 |
| **DB 자격 자체 만료** | mini 의 DB 로그인을 하루짜리로(IAM DB 인증·비번 회전) | Google(Cloud SQL) | 닫힘 | 닫힘 | ★DB 변경★ 실측 `cloudsql.iam_authentication` 미설정 · 사용자 4명 전부 BUILT_IN → 재시작 + DSN·Secret Manager·`loom_dsn.sh` 롤 계약 변경. 오빠 원문 «이번 일은 길» 과 어긋남 | 플래그 끄기 |

판정: **VM 하루 재기동**이 1안. (1) 강제 주체가 Google (2) 이 맥에 새 권한 0 (3) 오빠 원문 2 「이 맥에서 받아서 적용해 부팅해주고」 그대로. **IAM 시간 조건**은 2안(VM 상시·IAM 쓰기 권한을 이 맥에 얹는 값). **DB 자격 자체 만료**는 후속(길 다음에 자격).

## 3. 이전 안(새 VM byz-db-fwd + 방화벽 1 + IAP 조건 1)과의 관계 (꼭 답할 것 3)

**그 3가지 위에 얹힌다. 포워더 없이는 안 된다.**
- Cloud SQL 은 사설 IP(10.2.0.10)뿐이고(실측 `ipv4Enabled: false`), IAP 는 VPC 안 VM 의 포트로만 들어간다. VPC 안에 «mini 를 위해 5432 로 넘겨 주는 자리» 가 필요하고, 열쇠를 «VM 켜고 끄기» 로 거는 이상 **끌 수 있는 전용 VM 이 곧 열쇠 구멍**이다. GPU VM(이전 안 ⓑ)은 끌 수 없으니 양립하지 않는다.
- VM 생성 플래그 2개가 더해진다: `--max-run-duration=14h --instance-termination-action=STOP` (+ `--no-restart-on-failure`: 자동 재시작이 가동 주기를 새로 만들지 않게). 방화벽 1줄(35.235.240.0/20 → tcp:38309 · 대상 태그 `db-fwd`)·IAP 조건 1줄(`destination.ip == <포워더 고정 IP> && destination.port == 38309` 추가)은 이전 안 그대로.
- **내부 고정 IP 예약**(서브넷 `byz-agents-subnet-dev` 10.0.0.0/24 실측) → IAP 조건식의 `destination.ip` 가 정지·재기동에 흔들리지 않는다. 되돌림 = 주소 해제(§7 h1).
- 포워더 구현: e2-micro · COS · `create-with-container` 컨테이너 1개(`alpine/socat` `TCP-LISTEN:38309,fork,reuseaddr TCP:10.2.0.10:5432`) · ssh 불필요. ★`create-with-container` + `--max-run-duration` 조합이 안 먹으면 **도입 중단**(게스트 `shutdown` 타이머로 대체하지 않는다 — 「Google 이 강제」 전제를 바꾸므로 · DA r1 #12).★ h1 합격 조건 = `describe` 의 `scheduling.maxRunDuration.seconds == 50400`(14시간) 과 `scheduling.instanceTerminationAction == STOP` · `terminationTime` 은 상대 시간 설정에서 반환이 보장되는지 모르므로 **있으면 기록, 필수 아님**(DA r2 r1#12). 만료가 실제로 강제되는지는 **첫날 실측**으로 판정한다: 08:07 기동 뒤 22:07 전후에 VM 이 사람 손 없이 TERMINATED 가 되는 것(launchd 가 20:07 에 끄고 켜므로 첫날은 20:07 재기동을 1회 건너뛰어 관찰).
- **포워더가 유일한 길이 되게 하는 조건(DA r1 #8)**: ⓐ 지금의 역방향 포워딩을 걷는다 — 정본 `h-plans/h-mini-byz-server.sh` 29행 `FWD_PORTS=("$TUN_PORT" $FWD_EXTRA)` 는 DB 38309 를 **항상** 넣으므로, `FWD_DB=0`(기본) 스위치를 추가해 DB 를 목록에서 빼고(진입점 `h-mini-byz-server-run.sh` 는 `FWD_DB=0` 고정), h2 첫 단계에서 **살아 있는 `ssh -R` pid 를 `ACTION=stop` 경로로 종료**한다(목록만 바꾸면 이미 열린 포워딩은 남는다). ⓑ mini 에 다른 GCP 자격이 없음을 확인(`~/.config/byz-tunnel/` 의 SA 1개뿐 · 오늘 ls 실측 · 프로젝트 IAM 에 mini 주체는 그 SA 1개). ⓒ 합격 시험 = VM TERMINATED 상태에서 mini 의 **기존 DB 연결**(열어 둔 세션)과 **신규 DB 연결** 모두 실패.

## 4. «이 맥이 열쇠» 보안 성질 — 현재 vs 설계 (꼭 답할 것 4)

요구 정의(정확히): 「이 맥의 최근 재기동에 따라 **DB 길만** 창 길이만큼 허용. 창이 끝나면 Google 이 닫는다. 이 맥이 안 켜 주면 다음 창은 없다」. LLM·STT 터널은 이 설계 범위 밖(이전 설계대로 상시 · mini 침해 시 그 두 길은 남는다).

| 항목 | 현재(이 맥 역방향 포워딩 38309) | 설계(VM 하루 재기동) |
|---|---|---|
| mini 가 DB 에 닿는 조건 | 이 맥이 켜져 있고 + h 가 연 `ssh -R` 이 살아 있을 때(한 번 열면 며칠이고 산다) | 포워더 VM 이 RUNNING 일 때 = 이 맥이 마지막으로 켜 준 뒤 창 길이 안 |
| mini 침해 시 공격자가 얻는 것 | 127.0.0.1:38309 + DSN → DB(롤 권한만큼) · 유효 시간 상한 없음 | mini SA 키 + DSN → 같은 DB 권한 · **유효 시간 상한 = 남은 창**(26시간 안이면 최대 26시간 · 14시간 ×2 안이면 최대 14시간) |
| 즉시 차단 | 이 맥에서 ssh pid kill | 이 맥에서 `instances stop byz-db-fwd` 1줄 → 상태 **TERMINATED**(Compute API 의 정지 완료 상태 이름 · gcloud 도 이 값을 보인다) 뒤 신규·기존 전달 불가. ★보장은 «TERMINATED 이후» 이고 정지 요청→TERMINATED 는 비동기(게스트 종료 절차 포함 · 허용 지연 목표 ≤ 60초 [확인 필요: h1 실측]) · 이미 DB 에서 도는 쿼리가 즉시 취소되는 건 아니다(DA r1 #6)★ |
| 이 맥이 꺼져 있으면 | 즉시 닫힘 | 남은 창이 끝나면 닫힘(최대 14시간 · 그 사이는 열림) ← 이 느슨함이 오빠 원문 1 의 트레이드오프(오빠 수용 · #3309) |
| 이 맥 쪽 새 권한 | 0 | 0(후속: VM 단위 커스텀 역할 start·stop·get 만) |
| mini → 이 맥 되돌아올 길 | 0 | 0 |
| DB 자격(DSN) 자체 | mini 디스크 상시 | 같다(이 설계는 «길» 만) → 후속 «DB 자격 자체 만료» |

창 길이 비교(DA r1 #7 권고 = 14시간 ×2 · **오빠 결정 = 14시간 ×2**):

| 창 | 하루 재기동 | 이 맥 꺼진 뒤 최대 열림 | 단절 횟수/일 |
|---|---|---|---|
| 26시간 | 08:07 1회 | 26시간 | 1 |
| 14시간 | 08:07 · 20:07 2회 | 14시간 | 2 |

## 5. 도커 세트 (꼭 답할 것 5)

### 5-① 도커 박싱이 DB 길 문제를 풀어 주나
**아니다. 별개다.** 컨테이너도 «IAP 터널 → 포워더 VM → 10.2.0.10» 길이 똑같이 필요하다. 도커가 주는 것은 «터널을 세트 안 사이드카로 넣어 서버와 한 묶음으로 켜고 끄기» 다.

### 5-② 리소스 효율·테스트 분리 비교 (정직하게)

| 항목 | 지금(네이티브) | 콜리마 도커 세트 |
|---|---|---|
| 상주 메모리(mini 16GB) | 서버 4프로세스 RSS 합 약 600MB · 여유 64%(오늘 실측) | 콜리마 VM 본체 + 컨테이너. **이 맥 실측 VM 본체 RSS 1,477MB**(설정 8GiB · 컨테이너 19개). mini 전용 프로필 3GiB → 본체 0.8~1.2GB [확인 필요: h4 실측] + 서버 약 600MB ≈ **1.5~1.8GB(2.5~3배)** |
| 테스트 분리 | 홈에 venv·node_modules·.h-pids 누적 · stop 로직 60줄 | `compose down` 1줄 소거 · 이미지 태그 = 시험 sha · 두 호스트 같은 이미지 |
| 설치·빌드 | mini 가 rsync 받아 uv sync·next build(수 분) | 이 맥 1회 빌드 → `docker save` 전송 → mini 는 `load` 만 |
| macOS 오디오·화면 | 호스트 네이티브 | **컨테이너 불가** — Chrome(CDP 9333·마이크)·BlackHole·tts-say·러너는 호스트 네이티브 |

판정: «리소스 효율» 은 도커의 이득이 아니다(메모리가 는다). 이득은 분리·재현성·같은 세트·정리 1줄. **서버 묶음만 박싱, 러너·브라우저는 호스트 네이티브**(확정).

### 5-③ 같은 compose · 달라지는 값은 한곳
서비스들이 네트워크 이름공간 하나를 공유한다(`network_mode: service:net`) → 컨테이너 안에서 서로를 `127.0.0.1:포트` 로 본다 → 정본 `loom_dsn.sh` 의 «DSN host 를 127.0.0.1:$LOOM_PG_TUNNEL_PORT 로» 규칙과 `REDIS_URL=redis://127.0.0.1:38311/0` 등 **네이티브 env 를 그대로** 쓴다. 웹 번들에 빌드 때 박히는 `NEXT_PUBLIC_*`(127.0.0.1:38312) 도 두 호스트 같은 포트라 이미지 하나.

★DA r1 #2·#4·#3 반영★ (a) **호스트에서 들어오는 포트는 컨테이너 안에서 `0.0.0.0` 바인딩**이어야 도달한다(포트 공개는 컨테이너 주소로 들어오므로 127.0.0.1 바인딩은 밖에서 못 닿는다). 호스트 쪽 공개는 `127.0.0.1:포트` 로 제한. gateway·web·worker 는 이미지 기본(0.0.0.0)을 그대로 쓴다. (b) 컨테이너 안에서 읽을 변수는 `$$VAR`. (c) 흐름형 목록 문자열은 따옴표. (d) worker 의 `V6_C1C_TA_ENABLED=1` 거부 조건을 보존.

제안 파일(aifp 쪽 `docs/multihost/compose/` · BYZ 리포 편집 0 · 이미지는 BYZ 의 기존 Dockerfile 3개 + aifp 얇은 2장):

```yaml
# docs/multihost/compose/byz-test.compose.yml  (제안 r2 · 두 호스트 공통 · 포트 38301~38399 만)
name: byz-test
x-shared: &shared
  network_mode: "service:net"
  restart: unless-stopped
services:
  net:                                  # 이름공간 소유자 · 밖으로 여는 포트는 여기서만(호스트 127.0.0.1 한정)
    image: alpine:3.20
    command: ["sleep","infinity"]
    restart: unless-stopped
    ports: ["127.0.0.1:38312:38312", "127.0.0.1:38314:38314", "127.0.0.1:38313:38313"]
  tunnels:                              # 열쇠 사이드카 · aifp 얇은 이미지(cloud-sdk slim + postgresql-client + curl)
    <<: *shared
    image: byz-tunnels:${TUNNELS_IMG_TAG:?}
    secrets: [sa_key]
    environment:
      CLOUDSDK_CONFIG: /dev/shm/gcloud   # 자격 저장소는 tmpfs(디스크 0)
      IAP_DB_TARGET: "${IAP_DB_TARGET:?}"
    command: ["bash","/opt/tunnels.sh"] # activate-service-account --key-file /run/secrets/sa_key → start-iap-tunnel ×3(127.0.0.1:38309·8000·8001)
                                        # 감독 루프 30초: pg_isready -h 127.0.0.1 -p 38309 -t 5 + curl -sf -m 5 -o /dev/null http://127.0.0.1:8000/health(HTTP 2xx 만 통과) + 같은 꼴 8001
                                        # 연속 5회(150초 · 계획 단절 120초보다 길게) 실패 → 자식 전부 kill → exit 1 (restart 가 다시 올림)
    healthcheck: { test: ["CMD","pg_isready","-h","127.0.0.1","-p","38309","-q"], interval: 30s, timeout: 5s, retries: 3, start_period: 40s }
  redis:
    <<: *shared
    image: redis:7-alpine
    command: ["redis-server","--port","38311","--save","","--appendonly","no"]
  web:
    <<: *shared
    image: byz-web:${BYZ_SHA:?}
    environment: { PORT: "38314", HOSTNAME: "0.0.0.0" }       # 이미지 기본과 같음(밖에서 닿으려면 0.0.0.0)
  gateway:
    <<: *shared
    image: byz-gateway:${BYZ_SHA:?}
    secrets: [byz_env]                  # DSN 등 비밀 env 는 파일로만(컨테이너 설정·docker inspect 에 안 남음)
    environment: { PORT: "38312", REDIS_URL: "redis://127.0.0.1:38311/0", WORKER_HEALTH_URL: "http://127.0.0.1:38313", APP_ENV: local }
    depends_on: { tunnels: { condition: service_healthy }, redis: { condition: service_started } }
    command: ["sh","-c","set -a; . /run/secrets/byz_env; set +a; export PORT=38312 REDIS_URL=redis://127.0.0.1:38311/0 WORKER_HEALTH_URL=http://127.0.0.1:38313 APP_ENV=local; exec uvicorn gateway.main:app --host 0.0.0.0 --port $$PORT"]   # 고정값은 secret 을 읽은 «뒤» 다시 export(우선순위: 고정값 > secret 파일)
  worker:
    <<: *shared
    image: byz-worker-lane:${BYZ_SHA:?} # aifp 얇은 이미지(FROM byz-worker + scripts/ops/deploy_standing_replacement_gate.py)
    secrets: [byz_env]
    environment: { PORT: "38313", REDIS_URL: "redis://127.0.0.1:38311/0", APP_ENV: local, WORKER_LANE: "${WORKER_LANE:-flagoff}", BYZ_SHA: "${BYZ_SHA:?}" }
    depends_on: { tunnels: { condition: service_healthy }, redis: { condition: service_started } }
    command: ["sh","-c","set -a; . /run/secrets/byz_env; set +a; export PORT=38313 REDIS_URL=redis://127.0.0.1:38311/0 APP_ENV=local; if [ \"$$V6_C1C_TA_ENABLED\" = 1 ]; then echo REFUSED: C1c-TA flag-on sealed >&2; exit 1; fi; if [ \"$$WORKER_LANE\" = dev ]; then python scripts/ops/deploy_standing_replacement_gate.py approve-build-local --build-sha $$BYZ_SHA --redis-url $$REDIS_URL && exec python -m worker.c2c_act_entrypoint --c2c-act-dev; else exec python -m worker.main; fi"]
secrets:
  sa_key:  { file: "${BYZ_SA_KEY:?}" }    # 호스트 0600 파일 → /run/secrets/sa_key
  byz_env: { file: "${BYZ_ENV_FILE:?}" }  # 호스트 0600 파일 → /run/secrets/byz_env (아래 «비밀 취급» 참조)
```

★secret 파일 형식 계약(DA r2 새 발견 3)★ — `byz_env` 는 **POSIX sh 가 `.` 로 읽는 파일**이다. 생성기(이 맥 h)가 지키는 규칙 4개: ① 한 줄 = `NAME='값'` · 값 안의 `'` 는 `'\''` 로 치환(bash `%q` 를 쓰지 않는다 — `%q` 출력은 bash 전용 꼴이 섞인다) ② 이름 허용 목록 = 정본 `h-mini-byz-server.sh` 의 `KEYS` 배열 + DSN 2개(`LOOM_INTERIM_DB_URL`·`SUPABASE_DB_URL`) + 정본 `WORKER_ENV_SPEC` 고정값 ③ compose 가 고정하는 이름(`PORT`·`REDIS_URL`·`REDIS_HOST`·`REDIS_PORT`·`APP_ENV`·`WORKER_HEALTH_URL`·`WORKER_LANE`·`BYZ_SHA`)은 **파일에 넣지 않고**, 컨테이너 command 도 secret 을 읽은 뒤 고정값을 다시 export 한다(이중 안전) ④ 생성 뒤 `sh -n` 으로 구문 검사 · 값 출력 0.

달라지는 값은 **호스트별 env 파일 하나**(`compose/host.mini.env` · `compose/host.mac.env`):

| 이름 | mini | 이 맥(로컬) | 뜻 |
|---|---|---|---|
| `BYZ_SHA` | 3c250223d1 | 같음 | 시험 코드 = 이미지 태그 |
| `WORKER_LANE` | flagoff / dev | 같음 | 레인 스위치 |
| `BYZ_SA_KEY` | `~/.config/byz-tunnel/sa.json`(byz-mini-tunnel · 지금 그 자리) | `~/.config/byz/sa.json`(byz-local-dev) | 열쇠 파일 |
| `BYZ_ENV_FILE` | `~/.config/byz-test/env`(0600) | 같음 | 비밀 env(DSN 2개 포함) |
| `IAP_DB_TARGET` | `byz-db-fwd:38309` | `byz-db-fwd:38309`(★아래 «로컬 세트의 DB 길» · DA r2 새 발견 4) | 사이드카가 여는 DB 터널 목적지 |
| `TUNNELS_IMG_TAG` | 고정 태그 | 같음 | 사이드카 이미지 |
| `DOCKER_CONTEXT` | `colima-byz-test` | `colima`(기존 기본 프로필) | compose 가 쓸 도커 컨텍스트(프로필 고정 · DA r2 새 발견 2) |

**로컬(이 맥) 세트의 DB 길(DA r2 새 발견 4)**: 이 맥의 네이티브 DB 터널(`com.byz.loom-pg-tunnel` · ssh 경유 · 호스트 127.0.0.1:38309)은 오빠 결정 2 대로 **그대로 두고 건드리지 않는다**. 그러나 컨테이너 안의 127.0.0.1 은 호스트가 아니므로 그 터널에 닿지 못한다 → 로컬 도커 세트는 **mini 와 똑같이 사이드카가 포워더 VM 으로 IAP 터널**을 연다(이 맥 SA `byz-local-dev` 는 `iap.tunnelResourceAccessor` 를 조건 없이 보유 · 실측). 결과: 이 맥에는 길이 두 개 공존한다 — 네이티브 서버(server.sh) = 기존 ssh 터널 · 도커 세트 = 포워더(창 14시간 · 하루 2회 단절에 종속). 호스트 포트 충돌 없음(사이드카의 38309 는 컨테이너 이름공간 안). 합격 시험 = 로컬 세트 gateway 컨테이너에서 실제 DSN 으로 `SELECT 1`.

운용 규칙(DA r1 #10 · DA r2 새 발견 1·2): 세트는 **항상 통째로** 다룬다(`compose up -d` / `compose down`). `net` 만 재생성하면 공유 서비스가 옛 이름공간에 남으므로 `net` 을 바꿀 땐 `compose up -d --force-recreate`. 콜리마는 mini **전용 프로필 `byz-test`**(`colima start -p byz-test --cpu 2 --memory 3 --disk 30` → 도커 컨텍스트 `colima-byz-test` 가 생긴다) · 재부팅 자동 기동은 `brew services`(기본 프로필만 켠다) 가 아니라 **전용 LaunchAgent `com.byz.colima-byz-test`**(`colima start -p byz-test` · RunAtLoad) · compose 호출은 `DOCKER_CONTEXT=colima-byz-test` 고정 · 컨테이너는 `restart: unless-stopped`. 재부팅 합격 = 재부팅 뒤 손 없이 `docker --context colima-byz-test compose ps` 전부 running + gateway health 200. **h5 사전조건** = 네이티브 세트 `ACTION=stop` 완료 + **공개 포트 38312·38313·38314 가 0 LISTEN** + 38309 는 «소유 pid 가 mini launchd 의 gcloud(`com.byz.iap-tunnel-db`)» 인지 확인(비어 있을 필요 없음 — 호스트 터널은 네이티브 서버용으로 계속 산다 · 사이드카의 38309 는 컨테이너 이름공간 안이라 충돌 0).

비밀 취급(DA r1 #11 · 정직하게): SA 키와 DSN 은 **mini 디스크에 0600 으로 보관**된다(SA 키는 지금도 `~/.config/byz-tunnel/sa.json` 0600 · DSN 은 지금 네이티브 h 도 `env.sh` 임시 파일을 만든다 — 177·200행). 이 설계가 지키는 것: ① 컨테이너 설정·`docker inspect`·`compose config` 출력에 값이 안 남게 **env 가 아니라 파일 secret** 으로 넣고 컨테이너 안에서 읽는다 ② gcloud 자격 저장소는 tmpfs ③ 명령줄 0 ④ 로그·디버그 출력에 값 0(h 는 이름·rc·포트만). «디스크 보관 0» 은 이 설계로는 못 지키며, 그것은 후속 «DB 자격 자체 만료» 가 푼다.

### 5-④ 열쇠는 사이드카인가 주입인가 · 만료 시 세트가 스스로 닫히나
- 터널 = 세트 안 사이드카(`tunnels`). 열쇠 파일 = 파일 secret. 
- 만료(VM TERMINATED) 시: ★`nc -z` 는 로컬 수신 소켓이 살아 있어 통과해 버린다(DA r1 #5) → **실제 프로토콜 응답**으로 본다: `pg_isready` 가 socat 너머 Postgres 의 응답을 요구하므로 VM 이 꺼지면 실패한다.★ 감독 루프가 연속 5회(150초) 실패하면 자식 gcloud 를 모두 죽이고 exit 1 → `restart: unless-stopped` 가 재기동 → VM 이 다시 켜지면 **사람 손 없이** 복구. `start-iap-tunnel` 의 로컬 리스너는 «들어오는 연결마다» IAP 세션을 새로 만들므로 VM 이 돌아오면 새 연결은 재시작 없이도 통한다(그래서 계획 단절 120초는 5회 문턱 안에 끝나 불필요한 재시작이 없다). **복구 합격 조건은 `pg_isready` 가 아니라 실제 DSN 인증 `SELECT 1`**(DA r2 r1#5): h 시험·일일 절차 3단계가 gateway 컨테이너(또는 mini 네이티브 venv python)에서 `psycopg` 로 `SELECT 1` 을 친다 — `pg_isready` 는 감독 루프의 «살았나» 신호일 뿐이다. gateway·worker 는 compose 가 자동으로 멈추지 않는다(`depends_on` 은 기동 순서만) — DB 오류를 내며 떠 있다 = «길은 닫혔고 프로세스는 살아 있음». 길 닫힘이 보안 목표라 충분하다. 프로세스까지 내리려면 호스트 launchd 1줄(`compose ps tunnels` 10분 unhealthy → `compose stop gateway worker`) · 도커 소켓 마운트(autoheal) 금지.

### 이미지 전달
두 호스트 다 arm64 → 이 맥 1회 빌드 → `docker save <5개> | zstd | ssh mini 'zstd -d | docker load'`(레지스트리 0). 크기 [확인 필요: 첫 빌드 실측]. mini 빌드안은 next build 수 분 + 70초 천장 폴링이 다시 필요해 택하지 않는다.

## 6. 하루 절차 (꼭 답할 것 6)

**오빠 손 = 매일 0회.** 이 맥 launchd(`com.byz.db-key-daily` · **08:07 · 20:07 하루 2회** · SA byz-local-dev · 전용 `CLOUDSDK_CONFIG` · gcloud 587 고정):
0. 실행 잠금(DA r2 새 발견 5): `mkdir ~/.byz-db-key.lock` 원자 잠금 — launchd 실행과 수동 `! bash /tmp/h<N>` 이 겹치면 뒤의 것은 «이미 진행 중» 으로 끝난다. 잠금은 끝에 해제(비정상 종료 대비 30분 지난 잠금은 stale 로 간주).
1. `instances stop byz-db-fwd`(동기 · `timeout 70` · 7초 룰 안) → 상태 폴링 5초×12(≤ 60초)로 **`TERMINATED`** 확인(작업이 70초를 넘기면 작업 ID 를 `operations describe` 로 추적 · TERMINATED 가 아니면 start 하지 않고 FAIL) → `instances start byz-db-fwd`(동기 · RUNNING 확인 ≤ 40초). ★이미 RUNNING 이어도 건너뛰지 않는다 — 가동 주기를 새로 만드는 것이 목적(DA r1 #1).★
2. `describe` 로 `scheduling.maxRunDuration`·(있으면) `terminationTime`·`lastStartTimestamp` 기록 — «마지막 기동 시각이 이번 회차» 인 것이 갱신 증거.
3. mini 복구 확인(재접속은 mini 가 스스로 · §7 h2): `ssh mini '<venv python> -c "psycopg SELECT 1 (DSN 은 mini 의 0600 파일에서 읽음 · 값 출력 0)"'` 가 **20초 안에** 성공. 실패면 `launchctl kickstart -k gui/<uid>/com.byz.iap-tunnel-db` 1회 뒤 재확인(최대 +30초).
4. 결과 → `~/Library/Logs/byz-db-key.log` 1줄(회차 · 단절 초 · 상태) + 실패 시 알림센터(osascript) + tts-say 1문장 + mbox `[FAIL]` 1통(슬랙 경로 [확인 필요: hermes desk]).

단절 예산(DA r2 새 발견 6 · 오빠 수용 «회당 1~2분» = **≤ 120초**): 정지→TERMINATED ≤ 60초 + start→RUNNING+socat 기동 ≤ 40초 + 첫 `SELECT 1` 성공 ≤ 20초 = 120초. 실측이 예산을 넘기면 h3 는 FAIL 로 기록하고 오빠께 보고한다 [확인 필요: e2-micro COS 의 실제 정지·기동 초]. 러너 회차 시각과 겹치지 않게 08:07·20:07 고정.
스케줄 산술: 08:07 기동 → 만료 22:07 · 20:07 기동 → 만료 익일 10:07. 예약 간격 12시간 · 만료 여유 2시간. 예약 1회를 놓치면(이 맥 꺼짐) 만료 뒤 다음 예약까지 약 10시간 닫힘 = 설계 의도.
합격 조건(DA r1 #1 · r2 #6): **이틀 동안 예약 실행 4회** 모두 «단절 ≤ 120초 · 매회 `SELECT 1` 복구» (로그 4줄).

## 7. 도입 순서 최소안 (꼭 답할 것 7)

오빠 손 **5번**(DB 길 3 + 도커 2). 각 h 는 DRY 모드 + 되돌림 줄 + 만든 자원 목록(원장) 출력.

| # | 어디서 | 하는 일 | 닫는 증거 | 되돌림 |
|---|---|---|---|---|
| h1 | 이 맥 gcloud | 내부 고정 IP 예약(`byz-db-fwd-ip`) → `byz-db-fwd` 생성(e2-micro · COS · socat 컨테이너 · `--max-run-duration=14h --instance-termination-action=STOP --no-restart-on-failure` · 태그 db-fwd) → 방화벽 1줄 → IAP 조건식 1줄 확장(원본 조건식을 파일로 보존) · 만든 자원 4개를 원장 줄로 출력 | `describe` 에 `maxRunDuration.seconds=50400`·`instanceTerminationAction=STOP`(비면 **중단·되돌림**) · 조건식 diff · 첫날 22:07 전후 자동 TERMINATED 관찰 | VM·방화벽·예약 IP 삭제(HIL) · 조건식 원본 복원 |
| h2 | mini | ① 살아 있는 역방향 포워딩 `ssh -R` 종료 + 정본 h 에 `FWD_DB=0` 스위치 ② launchd `com.byz.iap-tunnel-db`(기존 `run-tunnel.sh byz-db-fwd 38309 38309` 재사용 · KeepAlive true · ThrottleInterval 30 — 지금 LLM 터널과 같은 꼴 · **LaunchAgent 라 byz 로그인 세션이 필요** = 지금 LLM·STT 터널과 같은 의존이고 mini 는 자동 로그인 GUI 세션 상주) + 감독 루프(`pg_isready` 연속 5회 실패 → 터널 종료 → launchd 재기동) ③ fail-closed 증명: 이 맥 stop → mini **기존 세션·신규 연결 모두 실패** → start → 손 없이 `SELECT 1` 성공 ④ 복구 시험 3종(DA r2 r1#9): 유휴 1시간 뒤 쿼리 · VM 재기동 뒤 쿼리 · mini 재부팅 뒤 쿼리 — 전부 손 0 ⑤ 러너 1회차 | mini 38309 소유 pid = mini gcloud · 시험 3종 + fail-closed 두 방향 증거 | plist 제거 · `FWD_DB` 복원 · **네이티브 서버 재기동(`h-mini-byz-server-run.sh`)으로 원래 연결 복원** |
| h3 | 이 맥 | launchd `com.byz.db-key-daily`(§6 · 08:07·20:07) · 1회 수동 실행 · 이틀 로그 | 예약 4회 통과(단절 ≤ 120초 · 매회 `SELECT 1`) | plist 제거 |
| h4 | mini | `brew install colima docker docker-compose` · 전용 프로필 `byz-test` + LaunchAgent `com.byz.colima-byz-test` · 설치 전 `brew list`·`docker images`(있다면) 를 원장에 기록 · RSS 실측 | `docker --context colima-byz-test info` · 재부팅 뒤 자동 기동 · RSS | `colima delete -p byz-test`(그 프로필만) · LaunchAgent 제거 · brew 패키지는 이번에 새로 깐 것만 제거 |
| h5 | 이 맥 → mini | 사전조건(네이티브 stop · 38312/13/14 0 LISTEN · 38309 소유 = mini launchd gcloud) → 이미지 5개 빌드(라벨 `byz.test=1`·태그 `${SHA}`)·save → mini load(load 전 `docker images` 목록을 원장에 기록) → `compose up -d` → gateway 컨테이너에서 `SELECT 1` · health 200 · RSS | `SELECT 1` · health · RSS 표 | `compose down` · 라벨 `byz.test=1` 이미지만 rm(load 전 목록에 있던 것은 안 지움) · 네이티브 서버 재기동 |

h1~h3 로 **골 축(시험 이관)의 남은 의존이 닫힌다**. h4·h5 는 그 뒤.

## 8. 오빠 결정 (쪽지 #3309 · 2026-10-26 · 확정)

1. **열쇠 창 = 14시간 · 하루 2회 끄고 다시 켜기**(08:07 · 20:07 · 하루 두 번 1~2분 DB 단절 수용). «이 맥 없으면 즉시 불가» 가 아니라 «창(최대 14시간)이 끝나면 불가» 임을 오빠가 수용. (IAM 시간 조건 안은 이 맥에 IAM 쓰기 권한을 얹어야 해서 채택하지 않음.)
2. **이 맥 자신의 DB 터널은 그대로**(`com.byz.loom-pg-tunnel` 유지 · 포워더로 옮기지 않음). 도커 세트를 이 맥에서 돌릴 때 `IAP_DB_TARGET` 만 이 맥 값으로 둔다(§5-③ 표).

## 9. 확인 필요 목록

- [확인 필요] `create-with-container` + `--max-run-duration` + `STOP` 이 e2-micro 표준 VM 에서 생성 통과 · `maxRunDuration.seconds=50400` 반환 · 첫날 자동 TERMINATED 실측 — h1. 안 되면 중단.
- [확인 필요] 정지 요청→TERMINATED 실측 지연(목표 ≤ 60초) · 기동→첫 `SELECT 1`(목표 ≤ 60초) · TERMINATED 뒤 기존 세션 실패 확인 — h2 ③.
- [확인 필요] IAM 시간 조건 안의 기존 IAP 세션 재평가 주기(2안에만 해당).
- [확인 필요] mini 전용 콜리마 프로필 RSS — h4. 이미지 5개 크기·`google/cloud-sdk:slim` arm64 태그 — h5.
- [확인 필요] 실패 알림 슬랙 경로.

## 10. DA

r1(codex · gpt-6.1-sol · `docs/multihost/da/da-20261026-132658-26400.out`) = **HOLD**(차단 4 · 중요 9) → 전부 반영 → r2(`da-20261026-133723-36821.out`) = **HOLD**(r1 13건 중 해소 7 · 부분 6 · 새 발견 6 = 차단 2 · 중요 4) → 전부 반영(§11 둘째 표) → r3 요청. DA 카운터: 보류 2회(r1 차단은 r2 에서 전부 해소 확인 · r2 차단 2건은 도커 쪽 새 문제 — 같은 문제의 2회 보류가 아님 · 하드 룰 14 경계는 master 판단).

## 11. DA r1 HOLD 반영표

| # | 지적(요약) | 반영 |
|---|---|---|
| 1 차단 | RUNNING 이면 건너뛰어 26시간 시계가 갱신 안 됨 → 48시간째 22시간 공백 | 하루 절차 = **stop → start**(새 주기) · `instances update` 에 플래그 없음을 확인(가동 중 갱신 불가) · 합격 = 예약 2회 통과 (§1·§6) |
| 2 차단 | 공유 이름공간 127.0.0.1 바인딩은 포트 공개로 못 닿음 | 서버는 컨테이너 안 0.0.0.0(이미지 기본) · 호스트 공개는 127.0.0.1 한정 (§5-③) |
| 3 차단 | `env_file: [${…}]` YAML 오류 | 따옴표 + `:?` · env_file 자체를 파일 secret 으로 교체 |
| 4 중요 | `$VAR` 치환 위치 · C1c 거부 조건 소실 | `$$VAR` · 거부 조건 보존 · BYZ_SHA 명시 전달 |
| 5 차단 | `nc -z` 는 로컬 소켓만 봄 · on-failure 가 안 돎 · 8001 미검사 | `pg_isready` + curl 8000·8001 감독 루프 · 연속 3회 실패 → 자식 kill → exit 1 → restart · 사이드카 이미지에 postgresql-client 포함 |
| 6 중요 | 정지 요청 = 즉시 절단 단정 | 보장을 «STOPPED 이후 신규·기존 전달 불가» 로 고침 · 허용 지연 ≤ 90초 목표 [확인 필요] · 기존/신규 각각 시험 (§4) |
| 7 중요 | 26시간은 원문 «즉시 불가» 와 다름 | 요구 정의를 «최근 재기동에 따라 DB 길만 창 길이 허용» 으로 명시 · 14시간 ×2 비교표 · 오빠 결정 1 로 (§4·§8) |
| 8 중요 | 포워더 유일 길 증명 없음 · 정본 29행이 DB 항상 포함 · 열린 ssh -R 잔존 | `FWD_DB=0` 스위치 · h2 ① 에서 기존 ssh -R 종료 · mini 자격 1개 확인 · STOPPED 상태 기존+신규 실패 시험 (§3) |
| 9 중요 | compute 권한 0·무인 재연결 단정 · KeepAlive 조건 | 실측 근거(mini SA 바인딩 1개로 이미 인스턴스 이름 터널 가동 중 · 전용 CLOUDSDK_CONFIG · gcloud 587 고정 · KeepAlive true·Throttle 30 = 기존 `run-tunnel.sh`) + 감독 루프로 «살아 있지만 불통» 을 종료로 바꿈 · 합격 = 재기동 뒤 실제 DB 응답 (§1·§7 h2) |
| 10 중요 | net 재생성·재부팅 복구·포트 충돌 | 세트 통째 운용 · `--force-recreate` · `restart: unless-stopped` · 콜리마 brew services · h5 사전조건 네이티브 stop (§5-③) |
| 11 중요 | 비밀이 env·inspect·gcloud 저장소에 남음 | 파일 secret + 컨테이너 안 읽기 · gcloud 저장소 tmpfs · «디스크 0600 보관은 허용·0 은 후속» 을 명시 (§5-③ 비밀 취급) |
| 12 중요 | Compute 만료 실패를 게스트 shutdown 으로 대체 · terminationTime 미검증 · --async | 대체 삭제 · 실패 = 중단 · `maxRunDuration`·`terminationTime` 필드 합격 조건 · `--no-restart-on-failure` · 동기 호출 + 폴링 (§3·§6·§7) |
| 13 중요 | 예약 IP 되돌림 없음 · colima delete 범위 · 이미지 rm 범위 | 예약 IP 해제 · 전용 프로필만 삭제 · `byz-*:${SHA}` 태그만 · 각 h 가 만든 자원 목록 출력 (§7) |

### DA r2 HOLD 반영표

| # | 지적(요약) | 반영 |
|---|---|---|
| r1#5 부분 | `pg_isready` 는 인증·SQL 성공 증명이 아님 · curl 상태코드·제한시간 없음 | 복구 합격 = 실제 DSN `SELECT 1`(h2·h5·일일 3단계) · `pg_isready` 는 감독 신호만 · curl `-sf -m 5`(2xx) (§5-③·§5-④·§6) |
| r1#9 부분 | 로그인 세션 의존 · 인증 쿼리 복구 시험 없음 | LaunchAgent 의존 명시(기존 터널과 같음) · 복구 시험 3종(유휴·VM 재기동·mini 재부팅) + `SELECT 1` (§7 h2 ④) |
| r1#10 부분 · 새 1 차단 | h5 «383xx 0 LISTEN» 이 h2 의 상주 38309 와 충돌 | 사전조건을 38312·38313·38314 로 특정 · 38309 는 소유 pid 확인 조건 (§5-③ 운용 규칙 · §7 h5) |
| r1#12 부분 | `terminationTime` 필수 근거 없음 | 합격 = `maxRunDuration.seconds=50400` + STOP + 첫날 실측 만료 · `terminationTime` 은 기록만 (§3·§7 h1) |
| r1#13 부분 | 태그만으로 기존 이미지 구분 불가 · 네이티브 복원 없음 | 라벨 `byz.test=1` + load 전 목록 원장 · 되돌림에 네이티브 서버 재기동 (§7 h2·h4·h5) |
| 새 2 중요 | 전용 프로필 자동 기동 미연결 · 컨텍스트 미고정 | LaunchAgent `com.byz.colima-byz-test` · `DOCKER_CONTEXT=colima-byz-test` · 재부팅 합격 조건 (§5-③) |
| 새 3 중요 | 파일 secret 의 셸 읽기 형식 계약 없음 · 고정값 덮어쓰기 | 형식 계약 4개(`NAME='값'` · 허용 목록 · 고정 이름 제외 · `sh -n`) + command 가 고정값을 뒤에 다시 export (§5-③) |
| 새 4 차단 | 로컬 세트 DB 길이 결정 2 와 안 맞음(호스트 터널에 컨테이너가 못 닿음) | 로컬 세트도 사이드카가 포워더로 IAP(byz-local-dev 무조건 바인딩 실측) · 네이티브 터널은 그대로 · 길 두 개 공존 명시 · `SELECT 1` 합격 (§5-③) |
| 새 5 중요 | 상태 이름 `STOPPED` 오류 · 작업 추적·실행 잠금 없음 | `TERMINATED` 로 정정 · `operations describe` 추적 · mkdir 잠금 (§4·§6) |
| 새 6 중요 | 단절 산술 불일치(210초 · 7×13=91) · «공백 없이» 모순 · 예약 2회 | 예산 60+40+20=120초 · 폴링 5초×12 · 합격 «단절 ≤ 120초 · 매회 복구» · 이틀 4회 · 스케줄 산술(22:07·10:07 · 여유 2시간) (§1·§6) |
