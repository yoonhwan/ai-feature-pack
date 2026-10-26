「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스에 tailscale 연결, cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영」(오빠 2026-10-21)
「DB 경로: 읽기 전용 검증부터」(오빠 2026-10-25)
골의 어느 축: «시험 이관(mini 러너)» 의 남은 의존 하나 = mini 서버가 DB 에 닿는 길(지금은 이 맥의 역방향 포워딩 38309 에 걸려 있음) + 서버 묶음을 어떻게 mini 로 보내 운영하나.

# 설계 — 만료 열쇠(이 맥이 하루 1회 열어 주는 DB 길) + 콜리마 도커 세트(mini 와 이 맥 같은 묶음)

작성: aifp-multihost-arch-claude#2 (Fable 5.1 팀 좌석) · 2026-10-26 · 발주 #3305(= `ORDER-arch-db-expiring-colima-20261026.md`)
조사 = 읽기 전용만(gcloud 읽기 · ssh mini 읽기 · BYZ 리포 읽기). 쓰기·원격 변경·키 값 출력 0. 커밋·push 는 master 집행.
오빠 지시 원문 5줄은 발주서 §오빠 지시 원문 그대로 따른다(「이 맥이 키」·「만료를 넣고 하루 1회 적용·부팅」·「콜리마 도커 세트로 박싱」·「로컬도 마찬가지」·「패블팀 좌석」).

## 0. 결론 (첫 줄)

**가능하다. 조건부가 아니라 «그대로 가능»이다.** 열쇠는 «포워더 VM 을 이 맥이 매일 켜고, VM 은 최대 가동 시간이 지나면 Google 이 스스로 끈다» 로 건다. 이 맥이 꺼져 있으면 다음날 VM 이 안 켜지고, mini 는 DB 에 못 닿는다(닫힘 쪽으로 실패). 도커 박싱은 DB 길과 **별개 문제**다. 도커는 «같은 세트를 두 호스트에서 운영» 과 «깨끗한 정리» 를 주지만 **메모리는 더 든다**(이 맥 실측: 콜리마 VM 본체 RSS 1,477MB). 그래서 둘을 한 설계에 담되 **DB 길 → 도커 순서**로 들어간다.

## 1. 가능/불가 판정과 이유 (꼭 답할 것 1)

**가능.** 근거 3개(전부 오늘 읽기 전용 실측).
- 열쇠를 걸 자리가 이미 있다: 이전 안의 «새 VM byz-db-fwd + 방화벽 1 + IAP 조건 1»(`VERIFY-db-path-20261025.md`)에서 mini 의 DB 길은 **포워더 VM 하나에만** 걸린다. 그 VM 이 꺼지면 길 전체가 끊긴다.
- Google 이 만료를 강제하는 수단이 gcloud 에 있다: `--max-run-duration`(«VM 이 마지막으로 켜진 때부터 상대 시간» · 도움말 658행) + `--instance-termination-action=STOP`(도움말 546행 · 표준 VM 의 자동 종료에 쓰인다 · `create-with-container` 도움말에도 같은 플래그 8곳). mini 가 어떻게 해도 이 시계는 못 만진다(mini 의 SA 는 IAP 터널 권한뿐 · compute 권한 0).
- 이 맥이 매일 켤 권한이 이미 있다: 이 맥의 SA `byz-local-dev` 에 `roles/compute.instanceAdmin.v1`(프로젝트 IAM 실측). 새 권한 추가 0 으로 `instances start` 가 된다.

트레이드오프(오빠 원문 1 「느리고 절차가 복잡」): 하루 1회 켜기는 자동(launchd)이라 손은 0 이고, 느린 곳은 «VM 기동 30~60초 + mini 터널 재접속» 하루 한 번뿐이다.

## 2. 만료를 «어디에» 거는지 — 후보 5안 비교 (꼭 답할 것 2)

안 이름으로 부른다(약어 0).

| 안 | 무엇을 매일 하나 | 만료 강제 주체(mini 가 어겨도 막히나) | 이 맥이 꺼져 있으면 | 하루 발급 실패 시 | 필요한 권한·변경(추가만?) | 되돌림 |
|---|---|---|---|---|---|---|
| **VM 하루 부팅** (추천) | 이 맥이 `instances start byz-db-fwd`. VM 은 `--max-run-duration=26h`·`STOP` 으로 스스로 꺼짐 | **Google(Compute)**. mini 는 VM 을 못 켬·못 늘림. 기존 TCP 연결도 VM 정지와 함께 끊긴다(가장 센 절단) | 다음 기동 없음 → 26시간 안에 닫힘 | 닫힘(안전한 쪽) | 이전 안 3가지 + VM 생성 플래그 2개. 이 맥 쪽 새 IAM 0(`instanceAdmin.v1` 보유) | VM 삭제(HIL) · 또는 플래그 제거로 상시 VM 으로 환원 |
| **IAM 시간 조건** | 이 맥이 mini SA 의 IAP 조건식에 `request.time < timestamp("내일")` 을 매일 갱신 | **Google(IAM)**. 단 ★이미 열려 있는 IAP 터널 세션이 만료 뒤에도 잠시 살아 있을 수 있다 [확인 필요: IAP 가 기존 세션을 재평가하는 주기]★ | 조건이 만료 → 새 연결 거부 | 닫힘 | 이 맥의 자동화 자격에 **프로젝트 IAM 쓰기 권한**(setIamPolicy)이 필요 — `byz-local-dev` 에 없다 → 강한 권한을 이 맥에 «추가»해야 한다 | 조건식 복원 |
| **단기 토큰 전달** | 이 맥이 mini SA 의 액세스 토큰(기본 1시간 · `--lifetime` 으로 최대 12시간)을 만들어 mini 로 전달 | Google(토큰 만료) | 토큰 만료 → 닫힘 | 닫힘 | 이 맥 계정에 `serviceAccountTokenCreator` · 12시간 넘기려면 조직 정책 변경 필요 → **«하루 1회» 가 구조적으로 안 된다**(최대 12시간) | 토큰은 그냥 만료 |
| **하루 키 교체** | 이 맥이 만료일(26시간) 박힌 X.509 공개키를 SA 에 업로드하고 개인키를 mini 로 전달 · 어제 키 삭제 | Google(키 만료) [확인 필요: 업로드 키의 유효기간이 인증서 만료를 따르는지 h 시험에서 `validBeforeTime` 확인] | 키 만료 → mini 의 **LLM·STT 터널까지** 전부 닫힘(범위가 DB 보다 넓다) | 닫힘 | 이 맥 계정에 `serviceAccountKeyAdmin` · mini 쪽 키 교체 자동화(ssh 쓰기) 매일 | 상시 키로 환원 |
| **DB 자격 자체 만료** (Cloud SQL IAM DB 인증 또는 비번 회전) | mini 의 DB 로그인 자체를 하루짜리로 | Google(Cloud SQL) | 닫힘 | 닫힘 | ★DB 쪽 변경★: 실측 `cloudsql.iam_authentication` 플래그 없음(databaseFlags 비어 있음) · 사용자 4명 전부 BUILT_IN. 켜려면 인스턴스 재시작 + DSN 교체 + Secret Manager 값 교체(gateway·worker 의 정본 `loom_dsn.sh` 롤 계약까지 건드림). 오빠 원문 «이번 일은 길» 과 어긋난다 | 플래그 끄기(재시작) |

판정: **VM 하루 부팅**을 1안으로 한다. 이유는 (1) 강제 주체가 Google 이고 절단이 가장 세다 (2) 이 맥에 새 권한을 «주지 않는다» (3) 오빠 원문 2 「이 맥에서 받아서 적용해 부팅해주고」 그대로다. **IAM 시간 조건**은 2안(VM 없이 IAM 만으로 닫고 싶을 때)이나 이 맥에 IAM 쓰기 권한을 얹는 값을 치른다. **DB 자격 자체 만료**는 «길» 다음 단계(후속)로 남긴다.

## 3. 이전 안(새 VM byz-db-fwd + 방화벽 1 + IAP 조건 1)과의 관계 (꼭 답할 것 3)

**그 3가지 위에 얹힌다. 포워더 없이는 안 된다.**
- 이유: Cloud SQL 은 사설 IP(10.2.0.10)뿐이고(실측 `ipv4Enabled: false`), IAP 는 VPC 안 VM 의 포트로만 들어간다. 그래서 VPC 안에 «mini 를 위해 5432 로 넘겨 주는 자리» 가 하나 필요하다. 후보는 포워더 VM(이전 안 ⓐ) 아니면 GPU VM 에 얹기(이전 안 ⓑ · COS 읽기 전용·서비스 VM 위험으로 권하지 않음). 열쇠를 «VM 켜고 끄기» 로 거는 이상 **전용 VM 이 곧 열쇠 구멍**이 된다. GPU VM 은 끌 수 없으니 ⓑ 는 이 설계와 양립하지 않는다.
- 바뀌는 것은 VM 생성 1줄의 플래그 2개뿐: `--max-run-duration=26h --instance-termination-action=STOP`. 방화벽 1줄(35.235.240.0/20 → tcp:38309 · 대상 태그 `db-fwd`)·IAP 조건 1줄(`destination.ip == <포워더 IP> && destination.port == 38309` 추가)은 이전 안 그대로다.
- 포워더 IP 는 정지·재기동에도 바뀌지 않게 **내부 고정 IP 예약**(서브넷 `byz-agents-subnet-dev` 10.0.0.0/24 · 실측) — IAP 조건식의 `destination.ip` 가 흔들리지 않는다.
- 포워더 구현: e2-micro · COS · 컨테이너 1개(`alpine/socat` `TCP-LISTEN:38309,fork,reuseaddr TCP:10.2.0.10:5432`) · ssh 불필요 · 디스크 쓰기 0. `create-with-container` 가 `--max-run-duration` 을 받는지 도움말에 플래그가 있음을 봤다(8곳) [확인 필요: 실제 생성 시 플래그 조합 오류 없음 — h1 DRY 에서 확인].
- 안전망(2중): startup-script 에 `shutdown -h +1560`(26시간) 1줄을 같이 넣는다. Google 쪽 시계가 혹시 안 먹어도 VM 자신이 끈다.

## 4. «이 맥이 열쇠» 보안 성질 — 현재 vs 설계 (꼭 답할 것 4)

| 항목 | 현재(이 맥 역방향 포워딩 38309) | 설계(VM 하루 부팅) |
|---|---|---|
| mini 가 DB 에 닿는 조건 | 이 맥이 켜져 있고 + h 가 연 `ssh -R` 이 살아 있을 때(한 번 열면 며칠이고 산다 · 10-22 실측은 죽기도 함) | 포워더 VM 이 켜져 있을 때 = 이 맥이 최근 26시간 안에 켜 준 때 |
| mini 침해 시 공격자가 얻는 것 | 127.0.0.1:38309 + mini 가 가진 DSN → DB 전부(읽기·쓰기 · 롤 권한만큼). 유효 시간 = 포워딩이 살아 있는 동안(상한 없음) | mini 의 SA 키 + DSN → 같은 DB 권한. **유효 시간 상한 26시간**, 이 맥이 다음날 안 켜 주면 끝 |
| 즉시 차단 방법 | 이 맥에서 그 ssh pid kill(h ACTION=stop) | 이 맥에서 `instances stop byz-db-fwd` 1줄(기존 연결까지 즉시 절단) + 다음날 켜지 않기 |
| 이 맥이 꺼져 있으면 | 포워딩이 죽는다(즉시 닫힘) | 26시간 안에 닫힘(그날은 열려 있다) ← 오빠가 받아들일 폭. 더 좁히려면 `--max-run-duration` 을 14h 로 하고 하루 2회 켠다(launchd 2줄) |
| 이 맥 쪽에 새로 생기는 권한 | 0 | 0(`instanceAdmin.v1` 이미 보유). 더 좁히려면 후속: VM 단위 커스텀 역할(start·get 만) |
| mini 가 이 맥으로 되돌아올 길 | 0(포워딩은 이 맥이 시작) | 0 |
| DB 자격(DSN) 자체 | mini 에 상시 | 같다(이 설계는 «길» 만 만료) → 후속 «DB 자격 자체 만료» 로 좁힌다 |

요약: 「이 맥이 없으면 mini 는 아무것도 못 한다」 를 DB 에 대해 **하루 단위**로 지킨다. 현재보다 «유효 시간 상한» 과 «1줄 즉시 차단» 이 생기고, «이 맥 꺼짐 = 즉시 닫힘» 은 «26시간 안 닫힘» 으로 느슨해진다. 이 느슨함이 오빠 원문 1 의 트레이드오프다.

## 5. 도커 세트 (꼭 답할 것 5)

### 5-① 도커 박싱이 DB 길 문제를 풀어 주나
**아니다. 별개다.** 컨테이너도 DB 에 닿으려면 똑같이 «IAP 터널 → 포워더 VM → 10.2.0.10» 길이 필요하다. 도커가 주는 것은 길이 아니라 «터널을 세트 안 사이드카로 넣어 서버 4개와 한 묶음으로 켜고 끄기» 다(5-④).

### 5-② 리소스 효율·테스트 분리 비교 (정직하게)

| 항목 | 지금(네이티브 · uv·npm·brew redis) | 콜리마 도커 세트 |
|---|---|---|
| 상주 메모리(mini 16GB) | 서버 4프로세스 RSS 합 약 600MB(발주서 사실) · mini 여유 64%(오늘 실측) | 콜리마 VM 본체 + 컨테이너. **이 맥 실측: VM 본체 RSS 1,477MB**(설정 8GiB · 컨테이너 19개 활성). mini 는 설정 3GiB 로 시작 → 본체 약 0.8~1.2GB [확인 필요: mini 에서 실측] + 컨테이너 안 서버 약 600MB(같은 코드) ≈ **1.5~1.8GB. 네이티브의 2.5~3배** |
| CPU | 네이티브 | VM 경유(Virtualization.Framework · 체감 작음) |
| 테스트 분리 | mini 홈에 venv·node_modules·.h-pids 가 쌓인다 · 포트·pid 추적이 h 스크립트 몫(stop 로직 60줄) | `docker compose down` 한 줄로 세트 전체 소거 · 이미지 sha 가 곧 시험 코드 sha · 두 호스트가 **같은 이미지** |
| 설치·빌드 | mini 가 rsync 받아 uv sync·next build(수 분 · 70초 천장 때문에 백그라운드+폴링) | 이 맥에서 1회 빌드 → `docker save` 로 전송 → mini 는 `load` 만(빌드 0) |
| macOS 오디오·화면 | 호스트 네이티브 | **컨테이너 불가** — Chrome(CDP 9333·마이크)·BlackHole·tts-say·러너는 그대로 호스트 네이티브 |

판정: «리소스 효율» 은 도커의 이득이 **아니다**(메모리가 는다). 이득은 «테스트 분리·재현성·두 호스트 같은 세트·정리 1줄» 이다. mini 여유 64%(약 10GB)라 1.8GB 는 감당된다. **서버 묶음만 박싱, 러너·브라우저는 호스트 네이티브** 로 가른다(발주서 판정 요구 — 확정).

### 5-③ 같은 compose · 달라지는 값은 한곳
핵심 수: **서비스 5개가 네트워크 이름공간 하나를 공유**한다(`network_mode: service:net`). 그러면 컨테이너 안에서도 지금 네이티브와 똑같이 `127.0.0.1:38311/38312/38313/38314/38309/8000/8001` 이 보인다 → **env 값을 네이티브와 한 글자도 바꾸지 않는다**(정본 `loom_dsn.sh` 가 DSN 을 `127.0.0.1:$LOOM_PG_TUNNEL_PORT` 로 바꾸는 규칙 그대로 먹는다). 웹 번들에 빌드 때 박히는 `NEXT_PUBLIC_*`(127.0.0.1:38312) 도 두 호스트가 같은 포트라 **이미지 하나**로 된다.

제안 파일(aifp 쪽 `docs/multihost/compose/` 에 둘 것 · BYZ 리포 편집 0 · 이미지 빌드는 BYZ 의 기존 Dockerfile 3개를 그대로 쓴다):

```yaml
# docs/multihost/compose/byz-test.compose.yml  (제안 · 두 호스트 공통 · 포트 38301~38399 만)
name: byz-test
services:
  net:                      # 네트워크 이름공간 소유자 · 바깥으로 여는 포트는 여기서만
    image: alpine:3.20
    command: ["sleep","infinity"]
    ports:
      - "127.0.0.1:38312:38312"   # gateway (러너·Chrome 은 같은 호스트)
      - "127.0.0.1:38314:38314"   # web
      - "127.0.0.1:38313:38313"   # worker health (gateway WORKER_HEALTH_URL)
  tunnels:                  # 열쇠 사이드카: IAP 터널 3개(DB 38309 · LLM 8000 · STT 8001)
    image: google/cloud-sdk:slim       # arm64 있음 [확인 필요: 태그 고정]
    network_mode: "service:net"
    secrets: [sa_key]
    environment:
      CLOUDSDK_CORE_PROJECT: byz-agents-484214
      CLOUDSDK_COMPUTE_ZONE: asia-northeast3-a
    command: ["bash","/opt/tunnels.sh"]   # activate-service-account --key-file /run/secrets/sa_key → start-iap-tunnel ×3 (--local-host-port 127.0.0.1:포트) · 하나라도 죽으면 exit 1
    volumes: ["./tunnels.sh:/opt/tunnels.sh:ro"]
    restart: on-failure
    healthcheck: { test: ["CMD","sh","-c","nc -z 127.0.0.1 38309 && nc -z 127.0.0.1 8000"], interval: 30s, timeout: 5s, retries: 3 }
  redis:
    image: redis:7-alpine
    network_mode: "service:net"
    command: ["redis-server","--port","38311","--save","","--appendonly","no"]
  web:
    image: byz-web:${BYZ_SHA}
    network_mode: "service:net"
    environment: { PORT: "38314", HOSTNAME: "127.0.0.1" }
  gateway:
    image: byz-gateway:${BYZ_SHA}
    network_mode: "service:net"
    env_file: [${BYZ_ENV_FILE}]           # 이 맥 h 가 stdin 대신 0600 임시 파일로 만들고 up 뒤 지운다(값 출력 0)
    environment: { PORT: "38312", REDIS_URL: "redis://127.0.0.1:38311/0", WORKER_HEALTH_URL: "http://127.0.0.1:38313" }
    depends_on: { tunnels: { condition: service_healthy }, redis: { condition: service_started } }
    command: ["uvicorn","gateway.main:app","--host","127.0.0.1","--port","38312"]
  worker:
    image: byz-worker:${BYZ_SHA}
    network_mode: "service:net"
    env_file: [${BYZ_ENV_FILE}]
    environment: { PORT: "38313", APP_ENV: local, REDIS_URL: "redis://127.0.0.1:38311/0", WORKER_LANE: "${WORKER_LANE:-flagoff}" }
    depends_on: { tunnels: { condition: service_healthy } }
    command: ["bash","-c","if [ \"$WORKER_LANE\" = dev ]; then python scripts/ops/deploy_standing_replacement_gate.py approve-build-local --build-sha $BYZ_SHA --redis-url $REDIS_URL && exec python -m worker.c2c_act_entrypoint --c2c-act-dev; else exec python -m worker.main; fi"]
secrets:
  sa_key: { file: "${BYZ_SA_KEY}" }        # 호스트 0400 파일 → 컨테이너 /run/secrets/sa_key (env 아님)
```

달라지는 값은 **호스트별 env 파일 하나**(`compose/host.mini.env` · `compose/host.mac.env`)에만 둔다:

| 이름 | mini | 이 맥(로컬) | 뜻 |
|---|---|---|---|
| `BYZ_SHA` | 3c250223d1 | 같음 | 시험 코드 = 이미지 태그 |
| `WORKER_LANE` | flagoff / dev | 같음 | 레인 스위치(기존 h 와 같은 이름) |
| `BYZ_SA_KEY` | `~/.config/byz/sa.json`(byz-mini-tunnel) | `~/.config/byz/sa.json`(byz-local-dev) | 열쇠 파일 경로 |
| `BYZ_ENV_FILE` | up 때 h 가 만든 임시 경로 | 같음 | 비밀 env(DSN 2개 포함 · 값 출력 0) |
| `IAP_DB_TARGET` | `byz-db-fwd 38309` | 같음(이 맥도 포워더로 옮길지는 §8 결정 2) | tunnels.sh 가 읽는 터널 목적지 |

주의 2개(지금 코드 사실): ⓐ `worker.Dockerfile` 은 `scripts/rag/` 만 싣는다 → dev 레인의 `scripts/ops/deploy_standing_replacement_gate.py` 가 이미지에 없다. 해법 = BYZ 파일 편집 없이 **aifp 쪽 얇은 Dockerfile**(`FROM byz-worker:${SHA}` + `COPY scripts/ops/deploy_standing_replacement_gate.py`) 1장. ⓑ `gateway.Dockerfile` 은 `--host 0.0.0.0` 이 기본 CMD 라 compose `command` 로 127.0.0.1 로 덮는다(위 반영).

### 5-④ 열쇠는 사이드카인가 주입인가 · 만료 시 세트가 스스로 닫히나
- **터널 = 세트 안 사이드카(`tunnels`)** 로 둔다. 이유: 세트 하나가 «켜면 길도 같이 열리고 끄면 같이 닫힌다». 호스트 launchd 터널을 쓰면 컨테이너에서 `host.docker.internal` 로 가야 해서 env 가 네이티브와 달라진다.
- **열쇠 파일 = compose secrets(파일 마운트 0400)**, env 주입 아님(`docker inspect` 에 값이 안 보인다).
- **만료 시 동작(정직하게)**: 포워더 VM 이 꺼지면 `tunnels` 의 DB 터널 프로세스가 죽고 → `tunnels.sh` 가 exit 1 → `restart: on-failure` 로 재시도만 반복 · healthcheck unhealthy. **gateway·worker 는 compose 가 자동으로 멈춰 주지 않는다**(`depends_on` 은 기동 순서만 본다). 그들은 DB 오류를 내며 떠 있다 = «길은 닫혔고 프로세스는 살아 있음». 길이 닫힌 것이 보안 목표이므로 이것으로 충분하다. 프로세스까지 내리고 싶으면 호스트 launchd 1줄(`docker compose ps tunnels` 가 10분 unhealthy 면 `compose stop gateway worker`)을 둔다 — 도커 소켓을 컨테이너에 넘기는 방식(autoheal)은 쓰지 않는다.

### 이미지 전달 방식
두 호스트 다 arm64(이 맥 콜리마 aarch64 · mini arm64 실측) → **이 맥에서 1회 빌드 → `docker save … | zstd | ssh mini 'zstd -d | docker load'`**(tailscale · 레지스트리 0 · mini 빌드 0). mini 에서 빌드하는 안은 next build 수 분 + 70초 천장 폴링이 다시 필요해 택하지 않는다. 이미지 크기는 [확인 필요: 첫 빌드 때 실측 · gateway·worker 는 python slim + requirements.lock 이라 1GB 대 추정].

## 6. 하루 1회 절차 (꼭 답할 것 6)

**오빠 손 = 매일 0회.** 이 맥 launchd(`com.byz.db-key-daily` · 08:07 · SA byz-local-dev · 비대화)가 한다:
1. `gcloud compute instances start byz-db-fwd` (이미 RUNNING 이면 건너뜀 · 7초 룰: start 요청은 즉시 반환 · RUNNING 폴링 7초×8).
2. `ssh mini 'launchctl kickstart -k gui/<uid>/com.byz.iap-tunnel-db'` — mini 터널 즉시 재접속(KeepAlive 가 있으면 생략 가능).
3. 확인: `ssh mini 'nc -z 127.0.0.1 38309'` + 이 맥에서 `scheduling.terminationTime` 읽어 «다음 자동 정지 시각» 을 로그에 적는다.
4. 결과 → `~/Library/Logs/byz-db-key.log` 1줄 + 실패면 macOS 알림(osascript) + tts-say 1문장 + mbox 로 멀티호스트 master 에 `[FAIL]` 1통(슬랙 경로는 hermes 데스크 연결 뒤 [확인 필요]).

자동화 불가 지점: 없음. 단 **이 맥이 꺼져 있던 날**은 아무도 안 켜므로 그날 mini DB 는 닫힌다 — 이것이 설계 의도다. 수동 복구는 `! bash /tmp/h<N>`(같은 스크립트 1회).
손이 1회 필요한 때: 첫 설치 때 fail-closed 증명(§7 h1 끝에 «stop → mini 38309 거부 → start → 통과» 를 한 번 보인다).

## 7. 도입 순서 최소안 (꼭 답할 것 7)

오빠 손 **5번**(DB 길 3 + 도커 2). 순서대로 1줄씩 · 각 h 는 DRY 모드 + 되돌림 줄 포함.

| # | 어디서 | 하는 일 | 닫는 증거 | 되돌림 |
|---|---|---|---|---|
| h1 | 이 맥 gcloud | 내부 고정 IP 예약 → `byz-db-fwd` 생성(e2-micro · COS · socat 컨테이너 · `--max-run-duration=26h --instance-termination-action=STOP` · 태그 db-fwd · startup-script 자체 종료 1줄) → 방화벽 1줄 → `byz-mini-tunnel` IAP 조건식 1줄 확장 | `describe` 에 `terminationTime` 있음 · 조건식 diff | VM·방화벽 삭제(HIL) · 조건식 복원 |
| h2 | mini(ssh 쓰기) | launchd `com.byz.iap-tunnel-db`(자체 SA 로 `start-iap-tunnel byz-db-fwd 38309 --local-host-port 127.0.0.1:38309`) → `h-mini-byz-server-run.sh` 의 역방향 포워딩에서 38309 제거(FWD 는 빈 목록) → fail-closed 증명(이 맥에서 stop → mini 거부 → start → 통과) | mini `38309 LISTEN` 소유 pid = mini 자체 gcloud · 러너 1회차 통과 | plist 제거 · FWD 목록 복원 |
| h3 | 이 맥 | launchd `com.byz.db-key-daily` 설치(§6) · 1회 수동 실행 | 로그 1줄 + 다음 정지 시각 | plist 제거 |
| h4 | mini(brew) | `brew install colima docker docker-compose` · `colima start --cpu 2 --memory 3 --disk 30` · 메모리 실측 | `docker info` · RSS | `colima delete` |
| h5 | 이 맥 → mini | 이미지 3개(+worker 얇은 1장) 빌드·save → mini load → `compose up` → health 200 · RSS 합 | health · RSS 표 | `compose down` · 이미지 rm |

h1~h3 가 끝나면 **골 축(시험 이관)의 남은 의존이 닫힌다**. h4·h5 는 운영 방식 개선이라 그 뒤여도 된다.

## 8. 오빠가 정할 것 (쉬운 말 · 2개)

1. **열쇠 방식**: «VM 하루 부팅»(추천 · 이 맥 권한 추가 0 · 끊김이 가장 셈 · 이 맥 꺼진 날은 최대 26시간 열려 있음) 으로 갈까요, «IAM 시간 조건»(VM 은 상시 · 대신 이 맥에 IAM 쓰기 권한을 새로 얹음) 으로 갈까요? → 추천은 VM 하루 부팅. 창을 더 좁히려면 14시간 2회로.
2. **이 맥 자신의 DB 터널도 포워더로 옮길까요?** 지금 이 맥은 GPU VM 을 거치는 ssh 터널(`com.byz.loom-pg-tunnel`)을 쓴다. 옮기면 ssh 가 사라지고 길이 하나로 모이지만, 포워더가 꺼진 시간엔 이 맥도 DB 를 잃는다. → 추천은 «지금은 두고, 도커 세트(h5)를 이 맥에서도 돌릴 때 같이».

(도커 박싱 자체는 결정이 아니라 순서다: DB 길 뒤에 한다. 메모리가 2.5~3배 드는 것을 알고 가는 조건.)

## 9. 확인 필요 목록 (지어내지 않은 것)

- [확인 필요] `create-with-container` 에서 `--max-run-duration` + `--instance-termination-action=STOP` 조합이 표준(e2-micro) VM 에 그대로 먹는지 — h1 DRY 에서 확인. 안 먹으면 startup-script 자체 종료 1줄이 단독 안전망.
- [확인 필요] 정지 뒤 `start` 가 `terminationTime` 을 새로 계산하는지(도움말 «마지막으로 켜진 때부터» 가 근거) — h1 뒤 describe 로 확인.
- [확인 필요] IAM 시간 조건을 쓸 경우 IAP 가 «이미 열린 세션» 을 언제 끊는지(2안에만 해당).
- [확인 필요] mini 콜리마 VM 본체 RSS(설정 3GiB 기준) — h4 에서 실측.
- [확인 필요] `google/cloud-sdk:slim` arm64 태그 고정값 · 이미지 3개 크기 — h5 첫 빌드 때.
- [확인 필요] 실패 알림의 슬랙 경로(hermes desk) — 지금은 알림센터+tts-say+mbox 까지만 확정.

## 10. DA 권고

IAM·방화벽·VM 생성이 들어가므로 **DA 1회 권장**(architect 판단 · 소환은 master 가 좌석으로). 반박 질문 후보 3개: ① «VM 정지» 가 mini 의 기존 DB TCP 연결을 정말 즉시 끊는가(포워더 socat 이 죽으면 끊긴다 — 근거는 VM 정지 = 프로세스 종료) ② 26시간 창이 오빠 원문 1 의 «이 맥 없으면 아무것도 못 함» 을 충분히 지키는가(하루 2회 14시간 안과 비교) ③ 네트워크 이름공간 공유(`network_mode: service:net`)가 콜리마에서 포트 공개·healthcheck 와 충돌하지 않는가.
