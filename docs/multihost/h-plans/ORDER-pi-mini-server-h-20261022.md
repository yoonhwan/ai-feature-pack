골 원문(오빠 2026-10-21): 「… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스 … 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 … 멀티 인스턴스(네트워크) 기능을 구축」
골의 어느 축: «시험 이관» — 오빠 결정 B안(서버를 mini 에서). 계획 정본 `docs/multihost/PLAN-mini-e2e-round1-20261022.md` §3·§4-2.

# 발주 — pi: ① 서버 최소 키 이름 목록(읽기) ② h-mini-byz-server.sh 초안 (실행 0)

작업 폴더 `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan` · 산출 2개: `docs/multihost/measured-byz-server-env-20261022.md`, `docs/multihost/h-plans/h-mini-byz-server.sh`. BYZ 원본 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` 는 **읽기만**. 틀 = `h-mini-e2e-setup.sh`(ssh mini 별칭 · rc 규칙 · 대화형 0 · 외부 호출 단건 70초 천장 · 비밀 값 출력 0).

## ① 최소 키 이름 목록 (값은 절대 읽지도 쓰지도 않는다 — 이름만)
`gateway/config.py` · `worker/` 설정 · `clients/web` 의 환경변수 사용처를 읽어, 러너(`realtime_multi_e2e.py`)가 «실시간 통역 1회차(마이크 → STT 최종본 1건)» 를 돌리는 데 **반드시 필요한 환경변수 이름만** 뽑는다. 표: 이름 · 쓰는 곳(파일:줄) · 없으면 어떻게 되나(기동 실패/기능 비활성/기본값) · 기본값 있는지. 후보: JWT_SECRET · BYZ_E2E_JWT_SECRET · STT/LLM/TTS provider 키 · REDIS_* · NEXT_PUBLIC_* · WEB_CLIENT_URL. `.env.example` 은 읽어도 되지만 **`.env` 는 열지 않는다**(값이 있다). 로그인 계정(BYZ_E2E_LOGIN_*)이 필요한지도 이름으로.

## ② h-mini-byz-server.sh (이 맥에서 오빠가 `! bash /tmp/h<N>` 로 실행하는 단일 스크립트 초안)
1. 사전점검: `ssh mini` user=byz · 디스크 여유 · `memory_pressure` 의 free % 출력 · redis-server·uv·node 존재 · 38301~38399 중 쓸 포트 4개(redis·gateway·worker?·web)가 mini 에서 비어 있는지(`lsof -nP -iTCP:<p> -sTCP:LISTEN`).
2. 코드 반입: 시험할 sha 는 인자(`SHA=`)로 받는다(기본값 없음 — 없으면 rc=2). 이 맥 BYZ 저장소에서 `git clone --depth 1 --no-local file://…` + `git checkout <sha>`(얕은 사본 /tmp 에서만 · 원본 불변) → tar → mini `~/Project/BYZ-Agents/`. 크기를 먼저 출력하고, 용량이 2GB 를 넘으면 rc=2 로 멈춘다. `.env*` 는 사본에서 제외·삭제 확인.
3. 설치: `uv sync`(또는 pyproject 가 요구하는 방식) · `clients/web` `npm ci` + 빌드(외부 호출 단건 70초 천장 — 넘으면 rc=3, 같은 h 재실행이 캐시로 이어감; 빌드는 백그라운드로 돌리고 로그 폴링해도 됨).
4. 기동(전부 38301~38399 포트): 네이티브 Redis(`redis-server --port <p> --save "" --appendonly no --daemonize no` 를 nohup) → gateway(`uvicorn gateway.main:app --host 127.0.0.1 --port <p>`, `--reload` 금지) → worker(`python -m worker.main`) → web(`next start -p <p>`). **`cleanup_stale_port` 가 든 기동 스크립트·Makefile 타깃은 쓰지 않는다.** 키는 **디스크에 쓰지 않고** stdin 으로 흘려 프로세스 env 로만 준다 — 이 단계에서는 ①의 이름 목록을 `KEYS=(…)` 배열로 두고, 값 공급 방식은 두 가지 모드를 둔다: `KEY_SRC=dotenv`(이 맥 BYZ `.env` 에서 그 이름만 골라 흘림 — 값 출력 0) / `KEY_SRC=op`(`OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP" op read … --vault develop` — kskill 금지). 기본값 없음(인자 필수).
5. pid 기록: 이 h 가 연 프로세스 pid 를 mini `~/Project/BYZ-Agents/.h-pids` 에(0600) — 종료/롤백은 그 pid 만.
6. ★필요량 실측★: 기동 60초 뒤 `ps -axo pid,rss,command` 로 위 pid 들의 RSS(MB)를 프로세스별 + 합계로 출력, `memory_pressure` 의 free % 와 함께. 헬스 확인(`curl -s -m 5 …/health` 코드만).
7. 롤백/정지 모드: `ACTION=stop` 이면 `.h-pids` 의 pid 만 종료. 남의 프로세스·Chrome·Redis 6379 건드리기 0.

## 검증 (네가 하는 것까지)
`bash -n` · 참조 경로 `test -e` · `grep -nE 'read |sudo |\[Y/n\]'` 0 · 비밀 echo 0 · `cleanup_stale_port` 사용 0 · 포트가 38301~38399 밖인 값 0 · 외부 호출 70초 초과 0.

## 끝
산출 파일 경로 2개 + 검증 4줄을 `aifp-multihost-master-claude#1` 에 mbox. 좌석은 닫지 말고 대기.
