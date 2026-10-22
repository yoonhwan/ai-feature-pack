골 원문(오빠 2026-10-21): 「… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스 … 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 … 멀티 인스턴스(네트워크) 기능을 구축」
골의 어느 축: «시험 이관» — 발주서 트랙 2-3 «첫 회차 계획». 근거 실측 = `measured-mini-e2e-prereq-20261022.md`(pi · 막힘 4/8).

# mini 시험 이관 — 첫 회차 계획 (2026-10-22)

## 한 줄
mini 의 Chrome·BlackHole 은 준비돼 있고, 막힌 건 «러너 코드 없음 · Chrome 디버그 포트 없음 · 서버 위치 미정 · 마이크 권한 미확인» 4가지다. 서버 위치만 오빠 결정이고 나머지는 h 두 장 + 오빠 손 두 번이다.

## 막힌 4가지 → 푸는 법 (누가)
| 막힘 | 푸는 법 | 누가 | 원격 쓰기 |
|---|---|---|---|
| ① BYZ 러너 코드 없음 | 이 맥 BYZ-Agents 에서 러너가 import 하는 파일만(`tests/e2e/` + 헬퍼) rsync → mini `~/Project/BYZ-e2e/` · 전용 venv(`~/Project/BYZ-e2e/.venv`, brew python3.13 — 시스템 python 3.9 는 websockets 16·러너 문법과 어긋남)에 websockets·pyjwt | h 1장 (pi 초안) | 쓰기 있음 → 오빠 `!` |
| ② Chrome 디버그 포트 없음 | 기존 29 프로세스는 **사람 손**으로 종료 후 README §1.2 명령(`--remote-debugging-port=9333 --user-data-dir=/tmp/chrome-byz-debug`, headed)으로 재기동 | 오빠 손 1회 (mini 앞) | — |
| ③ 서버 위치 | 아래 «결정» | 오빠 결정 | — |
| ④ 마이크 권한(TCC) | mini 터미널 앞에서 `mini-audio-check.sh`(이미 -37.3 dB 로 신호 확인) + Chrome 의 마이크 허용 팝업 1회 | 오빠 손 (②와 같은 자리에서) | — |

## 결정 1건 — 서버를 어디서 띄우나
| 안 | 내용 | 장점 | 위험 |
|---|---|---|---|
| A (추천) | 이 맥에서 FE·gateway·worker 를 띄우고 mini 의 러너가 tailnet 주소(`BYZ_WEB_BASE`·`BYZ_GATEWAY_BASE`)로 접속 | mini 메모리 여유 356MB 라 서버를 못 올림 → 서버는 이 맥, 오디오·Chrome 은 mini | 이 맥 FE·gateway 를 tailnet 에 열어야 함(0.0.0.0 바인드 → 노출면 확인 필요) · 지금 이 맥엔 3001/8080 리스너 0 |
| B | mini 에 서버까지 로컬 기동 | 네트워크 의존 0 | mini 자원 빠듯(free ~356MB·swap 320/2048MB) → 상주 시 멈출 위험 |

## 첫 회차 순서 (A 안 기준 · 증거 = 러너 원문 출력만)
1. [오빠 `!` h] mini 에 러너 코드 배치 + websockets.
2. [오빠 mini 앞] Chrome 정리·CDP 9333 재기동·마이크 허용·`mini-audio-check.sh` 재확인.
3. [이 맥] 서버 스택을 «검증된 한 세트(같은 HEAD)» 로 기동 — 포트는 로컬 규칙 38301~38399 레인지 · 러너 기본값 3015/8080 이 아니므로 `BYZ_WEB_BASE`·`BYZ_GATEWAY_BASE`·`BYZ_WEB_PORT` 를 환경변수로 명시(`.env` 수정 0).
4. [mini] 러너 실행: `BYZ_WEB_BASE=… BYZ_GATEWAY_BASE=… CDP_PORT=9333 .venv/bin/python tests/e2e/realtime_multi_e2e.py …` — 클릭은 러너의 `_real_click`(trusted `Input.dispatchMouseEvent`)만.
5. 닫는 증거: 러너가 «마이크 버튼 trusted 클릭 → 녹음 시작 → STT 최종본 1건» 까지 간 원문 로그 줄 + mini 에서 돌았다는 호스트명 줄. 이게 D9 «마이크 확정 회차» 이자 «시험 이관 1회 성공».

## 지키는 것
- 하드 룰 11: 임의 Redis 쓰기·말풍선 DOM 주입 0 — 증거는 실제 음성 경로뿐. 위반 회차는 무효.
- 오디오 E2E 는 시스템 전역 장치 하나라 «같은 기계» 에서 동시 불가 — mini 는 별개 장치라 이 맥의 오디오 시험과 병행 가능(이점). 단 이 맥에서 같은 서버 세트를 두 시험이 동시에 쓰지 않도록 순번.
- 비밀: `BYZ_E2E_JWT_SECRET` 은 op develop 볼트에서만 · 값 출력 0.
- 하네스 소유 파일 편집 0 · 원격 쓰기는 오빠 `!` h 로만.

## 아직 모르는 것 (다음 실측)
- 이 맥 포트가 tailnet 쪽에서 닿는지(방화벽·바인드) — A 안 결정 뒤 읽기 전용 확인.
- 러너 import 폐쇄(어떤 파일까지 옮겨야 하나) — pi 에게 발주.

## 추가 발견 (pi 폐쇄 실측 · 2026-10-22)
- 러너 폐쇄 = 16파일(loom_domain.py·시나리오 jsonl 61KB 포함). 3rd-party = websockets·PyJWT. 비밀: `_load_e2e_jwt_secret` 가 `REPO/.env` 를 직접 파싱 → `.env` 는 옮기지 않고 `BYZ_E2E_JWT_SECRET` 환경변수(op develop)로만 준다.
- ★발화 주입 경로 도구가 mini 에 없다★: `sag`·`tts-say`·`sox` 부재(`say`·`afplay` 는 있음). 첫 회차에서 TTS 로 음성을 만들어 BlackHole 로 흘리려면 이 3종(또는 `say` 로 대체 가능한지 러너 코드 확인)이 필요 → 별도 승인 h. 판정은 «러너가 `say` 만으로 도는 옵션이 있나» 먼저.
- 도메인 풀(`shared/prompts/composable/domains`)은 서버 쪽 자산 → A 안(서버=이 맥)이면 자동 해결.
