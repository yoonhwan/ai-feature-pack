골 원문(오빠 2026-10-21): 「… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스 … 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 … 멀티 인스턴스(네트워크) 기능을 구축」
골의 어느 축: «시험 이관» — 발주서 트랙 2-3 «첫 회차 계획». 오빠 결정(2026-10-22 AskUserQuestion): e2e 서버 = «Mac mini 에서 띄움»(B안). 근거 실측 = `measured-mini-e2e-prereq-20261022.md` · `measured-runner-closure-20261022.md` · `measured-runner-tts-path-20261022.md`.

# mini 시험 이관 — 첫 회차 계획 (B안: 서버·러너·Chrome 전부 mini) (2026-10-22)

## 한 줄
B안에서는 mini 에 BYZ 서버(gateway·worker·web·Redis)까지 올라가므로 «메모리 여유 · BYZ 코드 반입 · 키 주입» 3가지가 새 관건이다. 메모리는 처음 걱정(356MB)과 달리 여유가 있어 보이지만(아래 실측) Chrome 이 크게 차지하고 있어 오빠 손 정리가 필요하다.

## 1. 필요량 표 (메모리)
### 1-1. mini 현황 — 실측 (ssh mini, 읽기 전용, 2026-10-22)
| 항목 | 값 | 뜻 |
|---|---|---|
| 전체 RAM | 16GB | |
| `memory_pressure` | «System-wide memory free percentage: 77%» | 압박 없음 — 앞서 본 «free 356MB» 는 `Pages free` 한 칸(캐시·비활성 제외)만 센 오해 |
| 회수 가능 페이지 | free 4,461 + inactive 378,728 + speculative 15,196 + purgeable 13,730 = 412,115쪽 × 16KB ≈ **6.4GB** | 새 프로세스가 쓸 수 있는 양(회수 포함) |
| Chrome | **54 프로세스 · RSS 합 ≈ 7.8GB**(공유 메모리 중복 계산이라 실제는 더 작음) | 가장 큰 덩어리 → 정리 대상 1순위(오빠 손) |
| 그 밖 상주 | hermes 482MB · headroom(python3.14) 425MB · claude 2개 ≈ 636MB · cliproxy | 건드리지 않는다 |
| swap | 2GB 중 약 320MB 사용 | 여유 |
| 디스크 | 59GB 여유 | node_modules·venv 충분 |
| 도구 | redis-server ✅(brew) · uv ✅ · node 25.8 ✅ · git ✅ · docker/colima ❌ · gh ❌ · op ❌ | Redis 는 컨테이너 말고 네이티브로 |

### 1-2. 서버 세트 필요량 — ★추정(미실측)★
이 맥에는 지금 BYZ 서버가 떠 있지 않아(프로세스 확인) «같은 세트의 RSS 합» 을 지금은 못 잰다. 아래는 일반적 범위이며 **측정값이 아니다**. 실측은 서버 기동 h 가 끝에 `ps` 로 프로세스별 RSS 표를 찍어 mini 에서 직접 낸다(§4-2).
| 구성원 | 추정 RSS | 비고 |
|---|---|---|
| gateway(uvicorn) | 0.2~0.4GB | `--reload` 없이 기동 |
| worker(python -m worker.main) | 0.3~0.7GB | LangGraph·SDK |
| web(Next.js) | dev(`next dev --turbopack`) 1~2GB / 빌드 후 `next start` 0.3~0.5GB | 빌드 때 일시 2~3GB |
| Redis(네이티브) | ~0.02GB | |
| Chrome 1개(CDP 9333, 전용 프로필) | 1~1.5GB | 기존 Chrome 정리 뒤 새로 |
| 러너(python) | ~0.1GB | |
| **합계** | **약 2~3GB(web 빌드 후 start) · 최대 4~5GB(dev)** | 회수 가능 6.4GB 안 — 단 기존 Chrome 7.8GB 가 그대로면 압박 |
→ 결론(추정): **들어간다 — 단 기존 Chrome 을 정리하고 web 은 dev 대신 빌드 후 `next start`** 가 안전하다. 모자라면 닫을 순서: ① 기존 Chrome(오빠 손) ② 그래도 모자라면 web 만 이 맥에서 띄워 mini 가 접속(부분 A안).

## 2. BYZ 코드 반입 — git 자격 없이
mini 에는 GitHub 키가 없고(`~/.ssh` github 0) `gh`·`op` 도 없다. → **이 맥에서 «시험할 sha» 의 얕은 사본을 만들어 전송**하고 mini 에서 풀어 쓴다. 자격 증명이 mini 에 남지 않고 시험은 그 sha 로 고정된다(같은 HEAD 한 세트 규칙).
- 이 맥 BYZ 저장소 `.git` 이 6.9GB 라 전체 bundle 은 크다 → `git clone --depth 1 --no-local file://<repo>` 로 얕은 사본 → tar 전송. h 초안에서 크기를 실측한다.
- 시험할 sha 는 오빠(또는 상위)가 지정. 이 계획은 고르지 않는다.
- h378 은 «러너 16파일만» 배치(`~/Project/BYZ-e2e`)인데 B안에서는 전체 repo 안의 러너를 쓴다. h378 의 venv(python3.13)·websockets·pyjwt 준비는 유효하나 러너 파일 사본은 쓰지 않는다(이미 발급된 h 는 그대로).

## 3. 키(비밀) 주입 — 값 복사·출력 0
- `.env*` 는 옮기지도 심링크하지도 않는다. 값은 **mini 디스크에 쓰지 않고** 서버 프로세스 환경변수로만 준다(stdin 으로 받아 기동).
- ★출처 문제(오빠 결정)★: op **develop 볼트에는 BYZ 서버용 provider 키 묶음이 없다**(실측: 항목 31개 중 BYZ 는 시연 계정 로그인 + `BYZ-Agents(localhost)` 로그인 2개 — 필드 notesPlain/password/username 뿐). 서버 기동에 필요한 키(JWT_SECRET·STT/LLM/TTS provider 등)의 실제 출처는 이 맥 BYZ `.env` 뿐이다. 선택지: ① 이 맥 `.env` 에서 «필요한 키 이름만» 골라 기동 h 가 stdin 으로 주입(값은 화면·로그·mini 디스크 0) ② 오빠가 필요한 키를 op develop 에 먼저 등록하고 h 가 `op` 로 읽어 주입(하드 룰 15 에 더 충실, 오빠 손 추가). 필요한 «키 이름 목록» 은 코드에서 최소 세트를 뽑아 확정(pi 발주).
- 하드 룰 11: 임의 Redis 쓰기·말풍선 DOM 주입 0. Redis 는 mini 로컬 네이티브 인스턴스(제품 키를 사람이 만져 넣지 않는다).

## 4. 고친 첫 회차 순서 (B안)
1. [오빠 `!`] h375→h376→h377 (OCI·mini 운용) · h378(러너 venv 준비) → h379(tts-say). 이미 발급.
2. [pi 초안 → 상위 검수 → 오빠 `!`] ★서버 반입·기동 h★: 얕은 사본 전송 → `uv sync`(Python) → `npm ci` + 빌드(web) → 네이티브 Redis 기동 → gateway·worker·web 기동 → ★프로세스별 RSS 표 출력(필요량 실측)★. 포트는 **38301~38399 레인지**(기본 6379/8080/3015 금지) · `cleanup_stale_port` 계열 기동 스크립트 사용 금지(`uvicorn`/`next start` 를 직접) · 이 h 가 연 pid 만 pid 파일로 기록.
3. [오빠 mini 앞, 한 자리 · sudo 불필요] 기존 Chrome 54프로세스 정리 → CDP 9333 전용 프로필 새 Chrome 기동(README §1.2) · 마이크 허용 팝업 1회 · 출력 기본값 BlackHole 2ch/Multi-Output.
4. [mini] 러너 실행: 로그인 셸 + `PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"` + `BYZ_WEB_BASE`·`BYZ_GATEWAY_BASE`(127.0.0.1:<레인지 포트>)·`CDP_PORT=9333` + 러너 venv python. 클릭은 러너의 `_real_click`(trusted `Input.dispatchMouseEvent`)만. 러너 기본 포트(3015/8080)가 아니므로 BASE 변수 필수.
5. 닫는 증거: 러너가 «마이크 버튼 trusted 클릭 → 녹음 시작 → STT 최종본 1건» 까지 간 원문 로그 줄 + `hostname`=mini 줄 + §4-2 의 RSS 표. 이게 D9 «마이크 확정 회차» 이자 «시험 이관 1회 성공».
6. 정리: 서버·Redis 종료는 위 pid 파일의 pid 만(남의 프로세스 0).

## 5. 지키는 것
- 오디오 E2E 는 장치 하나 → mini 안에서 동시 1회차. 이 맥 오디오 시험과는 별개 장치라 병행 가능.
- 서버·러너·FE 는 같은 sha 한 세트에서만. 비밀 값 출력 0 · 하네스 소유 파일 편집 0 · mini 설치·기동은 전부 오빠 `!` h.

## 6. TTS 경로 결론 (pi · `measured-runner-tts-path-20261022.md`)
- 발화 엔진은 러너 CLI `--engine say|sag` 하나뿐이고 `say` 엔진도 내부에서 `tts-say` 를 부른다 → mini 에 `tts-say` 하나면 된다(sag·sox 불필요: RMS 게이트는 `afconvert` 우선). 소리는 `afplay` = 시스템 기본 출력 → 출력 기본값 BlackHole/Multi-Output 이 조건. → h379.
- 도메인 풀은 서버 쪽 자산이라 B안(서버 = mini 의 repo 사본)에서 사본에 포함돼 자동 해결.
