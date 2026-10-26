「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스에 tailscale 연결, cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영」(오빠 2026-10-21)
「사실 이거 콜리마 도커 세트로 박싱해서 보내면 되는거 아닌가」 · 「로컬도 마찬가지로 운영하고」(오빠 2026-10-26)
골의 어느 축: «시험 이관» 의 서버 묶음(redis·gateway·worker·web)을 mini 와 이 맥에서 같은 세트로 운영하는 방식.

# 카드 둘 — 콜리마 도커 세트 (초안 · DA 전 · **카드 하나(DB 길)가 승인·설치된 뒤** 별도 설계+DA)

작성: aifp-multihost-arch-claude#2 · 2026-10-26 · master #3311 지시로 `DESIGN-db-expiring-credential-colima-20261026.md` 에서 분리. 상태 = **초안**(DA r2 의 도커 쪽 지적 6건은 반영돼 있으나 이 카드 자체의 DA 는 아직 0회).
의존: 카드 하나 `DESIGN-db-key-vm-cycle-20261026.md` 의 h1~h3 완료(포워더 VM 이 있어야 사이드카 터널 목적지가 생긴다).

## 0. 결론(정직하게)
- 도커 박싱은 **DB 길 문제를 풀어 주지 않는다**(별개). 컨테이너도 «IAP 터널 → 포워더 VM → 10.2.0.10» 길이 똑같이 필요하다.
- **메모리는 더 든다**: 이 맥 실측 콜리마 VM 본체 RSS 1,477MB(설정 8GiB · 컨테이너 19개). mini 전용 프로필 3GiB → 본체 0.8~1.2GB [확인 필요] + 서버 약 600MB ≈ 1.5~1.8GB(네이티브의 2.5~3배). mini 여유 64%(약 10GB)라 감당은 된다.
- 이득 = 테스트 분리(`compose down` 1줄 소거) · 재현성(이미지 태그 = 시험 sha) · 두 호스트 같은 세트 · mini 빌드 0(이 맥 빌드 → `docker save` 전송).
- **서버 묶음만 박싱 · 러너·Chrome(CDP 9333·마이크)·BlackHole·tts-say 는 호스트 네이티브**(컨테이너는 macOS 오디오·화면을 못 건드림).

## 1. 구성 원칙
- 서비스들이 네트워크 이름공간 하나를 공유(`network_mode: service:net`) → 컨테이너 안에서 서로를 `127.0.0.1:포트` 로 본다 → 정본 `loom_dsn.sh` 의 DSN 재작성 규칙·`REDIS_URL` 등 **네이티브 env 그대로**. 웹 번들의 `NEXT_PUBLIC_*`(127.0.0.1:38312) 도 두 호스트 같은 포트라 이미지 하나.
- 호스트에서 들어오는 포트는 컨테이너 안 **0.0.0.0 바인딩**(이미지 기본) · 호스트 공개는 `127.0.0.1:38312/38313/38314` 만.
- 터널 = 세트 안 사이드카(`tunnels`) · 열쇠·DSN = **파일 secret**(컨테이너 설정·`docker inspect` 에 안 남음) · gcloud 자격 저장소 tmpfs.
- 세트는 통째로만(`up -d`/`down` · `net` 변경 시 `--force-recreate`) · `restart: unless-stopped`.
- **mini 한정 규칙**: 전용 콜리마 프로필 `byz-test` + LaunchAgent `com.byz.colima-byz-test` + `DOCKER_CONTEXT=colima-byz-test` · h5 사전조건 «38309 소유 = mini launchd gcloud».
- **로컬(이 맥) 전환 절차(DA r3 조건 6)**: ① `server.sh` 네이티브 서버 정지 ② 공개 포트 38312·38313·38314 0 LISTEN 확인(38309 는 이 맥 `com.byz.loom-pg-tunnel` 소유 그대로 · 검사 조건 아님) ③ 컨텍스트 = 기존 `colima`(기본 프로필 · 전용 프로필 안 만듦) ④ SA = `byz-local-dev` 키 파일 ⑤ `compose up -d` → gateway 컨테이너 `SELECT 1`(포워더 경유) ⑥ 되돌림 = `compose down` + `server.sh` 재기동(네이티브는 기존 ssh 터널로 복귀).
- 감독 루프의 HTTP 검사는 `curl -sf` 가 아니라 **상태 코드를 받아 200~299 인지 직접 비교**(`curl -s -m 5 -o /dev/null -w '%{http_code}'` · DA r3 조건 7 — `-f` 는 3xx 를 통과시킨다).
- **로컬(이 맥) 세트의 DB 길**: 네이티브 터널은 그대로(오빠 결정 2) · 컨테이너는 호스트 127.0.0.1 에 못 닿으므로 로컬 세트도 사이드카가 포워더로 IAP(byz-local-dev 무조건 바인딩 실측) → 이 맥엔 길 두 개 공존(네이티브 = ssh 터널 · 도커 = 포워더 창에 종속).
- 비밀 디스크 보관: SA 키·DSN 은 호스트 0600 보관 **허용**(지금도 SA 키는 그렇게 · 네이티브 h 도 임시 env 파일) · «디스크 0» 은 후속 «DB 자격 자체 만료».

## 2. compose 제안 (r3 시점 · 원본 파일 §5-③ 와 같음)
`docs/multihost/compose/byz-test.compose.yml` — 서비스 `net`·`tunnels`(aifp 얇은 이미지: cloud-sdk slim + postgresql-client + curl · 감독 루프 30초 `pg_isready -t 5` + `curl -sf -m 5` 8000·8001 · 연속 5회 실패 → exit 1)·`redis`·`web`·`gateway`·`worker`(aifp 얇은 이미지: `FROM byz-worker` + `scripts/ops/deploy_standing_replacement_gate.py` · `V6_C1C_TA_ENABLED=1` 거부 보존 · `$$VAR`). 전문은 원본 파일 §5-③ 코드 블록(분리 시점 그대로 유효).
호스트별 값 1파일(`compose/host.<host>.env`): `BYZ_SHA` · `WORKER_LANE` · `BYZ_SA_KEY` · `BYZ_ENV_FILE` · `IAP_DB_TARGET=byz-db-fwd:38309` · `TUNNELS_IMG_TAG` · `DOCKER_CONTEXT`.
secret 파일 형식 계약: POSIX sh 가 `.` 로 읽는 `NAME='값'`(`'` → `'\''`) · 이름 허용 목록 = 정본 `KEYS` + DSN 2개 + `WORKER_ENV_SPEC` · compose 고정 이름(`PORT`·`REDIS_URL`·`APP_ENV`·…)은 파일에 넣지 않고 command 가 뒤에 다시 export · `sh -n` 검사 · 값 출력 0.

## 3. 도입 순서 (오빠 손 2번 · 카드 하나 뒤)
| # | 어디서 | 하는 일 | 닫는 증거 | 되돌림 |
|---|---|---|---|---|
| h4 | mini | `brew install colima docker docker-compose` · 전용 프로필 `byz-test`(2 CPU · 3GiB · 30GB) + LaunchAgent · 설치 전 `brew list`·`docker images` 원장 기록 · RSS 실측 | `docker --context colima-byz-test info` · 재부팅 뒤 자동 기동 · RSS | `colima delete -p byz-test`(그 프로필만) · LaunchAgent 제거 · 이번에 새로 깐 brew 패키지만 제거 |
| h5 | 이 맥 → mini | 사전조건(네이티브 stop · 38312/13/14 0 LISTEN · 38309 소유 = mini launchd gcloud) → 이미지 5개 빌드(라벨 `byz.test=1` · 태그 `${SHA}`)·save → mini load(load 전 목록 원장) → `compose up -d` → gateway 컨테이너에서 `SELECT 1` · health 200 · RSS | `SELECT 1` · health · RSS 표 | `compose down` · 라벨 `byz.test=1` 이미지만 rm · 네이티브 서버 재기동 |

## 4. 이 카드가 DA 받기 전 채울 것
- mini 전용 프로필 RSS 실측 · 이미지 5개 크기 · `google/cloud-sdk:slim` arm64 태그 고정.
- `network_mode: service:net` + 파일 secret + 전용 프로필 복구를 **이 맥에서 먼저 1회 올려** 동작 증거(DA r2 질문 ③ «전체 동작 미입증»).
- 이 카드의 DA r1(카드 하나 승인 뒤).

## 5. DA 이력(원본 파일 기준)
r2 새 발견 중 도커 소속 = 차단 2(h5 포트 사전조건 · 로컬 세트 DB 길) + 중요 2(프로필 자동기동 · secret 형식) → 위 §1~§3 에 반영. 이 카드 자체 DA = 0회.
