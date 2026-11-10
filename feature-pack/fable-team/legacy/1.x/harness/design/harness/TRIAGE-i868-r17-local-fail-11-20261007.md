# TRIAGE — Issue 868 (원장 R17) 로컬 pytest 묶음 기존 실패 11건 (arch#7 안 · 2026-10-07)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골 축: 원문 6-b(planner A-21 요청 접수 → 트리아지 값 제안).

## 결론
**결함 0 — 11건 전부 «로컬 묶음 환경이 CI 와 다른 것»이다(Redis 없음 4 · jsdom 없음 7).** 시험·제품 코드 수정 0. 868 은 아래 증거로 닫고, 로컬 재현 레시피 보강 1줄을 하네스 원장 새 행으로 남긴다.

## 실측 (이 세션 · harness-ops HEAD = origin/main 과 코드 동일 — gateway·worker·shared·tests diff 는 tests/harness 1파일뿐)
| 회차 | 환경 | 결과 |
|---|---|---|
| ① 재현 | `.env` 없음(BYZ_TEST_SKIP_DOTENV=1) · REDIS_PORT=9 · 워크트리에 clients/web/node_modules 없음 | **11 failed, 40 passed** — 868 의 11건과 이름까지 일치 |
| ② Redis 4건 | 일회용 redis-server :38391(save·aof 끔 · 시험 뒤 정지 확인) · REDIS_HOST=localhost | test_gpu_vm_control·test_cleanup_auth·test_loom_contract_terminal_surfaces **44 passed, 0 failed** |
| ③ jsdom 7건 | scratch 트리에 시험 파일 + scripts/debug 복사 · clients/web/node_modules → 루트 node_modules 심링크 | test_poller_dom_order_version_capture **7 passed** |

## 건별 원인
| 시험 | 건수 | 실패 줄 | 원인 |
|---|---|---|---|
| test_poller_dom_order_version_capture | 7 | `Cannot find module …/harness-ops/clients/web/node_modules/jsdom` | 워크트리에 web 의존성이 없다. CI 는 `npm ci --ignore-scripts`(ci.yml «Install web deps (jsdom …)» 단계)로 깐다. |
| test_gpu_vm_control (stop 2건) | 2 | `ConnectionRefusedError ('127.0.0.1', 9)` · auth.py:189 dispatch | 미들웨어 경로가 실제 Redis 에 닿는다. CI 는 services.redis 6379. |
| test_cleanup_auth | 1 | 같은 거부 · redis_session_repository.py:142 get_ccu | 같음 |
| test_loom_contract_terminal_surfaces | 1 | live_gpu_fence.py:63 _connect · worker/main.py:427 lifespan → Redis 거부 | 같음 |

## 이유 3줄
1. 실패 줄이 전부 «연결 거부(포트 9)» 또는 «jsdom 모듈 없음» 이고, 그 둘만 채우면 같은 코드에서 51건 전부 통과한다.
2. REDIS_PORT=9 는 라이브 6379(v6-realtime-live dev = 운영 데이터)를 지키려고 «일부러» 막은 값이다 — 이 4건이 실패하는 것은 그 격리가 작동한다는 뜻이지 결함이 아니다.
3. 시험을 고치는 안(4건을 Redis 목으로 · jsdom 없으면 skip)은 반려 — skip 은 CI 에서 npm ci 가 깨질 때 침묵 통과를 만든다(#0 RULE), 목 전환은 범위 밖 제품 시험 변경.

## 제안 값 (planner → 오빠 컨펌용)
- **868 처리** = 닫기 · 사유 「결함 0 · 로컬 환경 차이(Redis 4·jsdom 7)」 · 닫는 증거 = 위 ①②③ 결과 3줄.
  - 868 요건의 「feat·main 둘 다」 중 이번 실측은 main 동일 코드 1벌이다. feat(feat/v6-realtime-live) 회차가 필요하면 같은 레시피로 1회 더(작업 크기: pytest 2회).
- **하네스 원장 새 행(낮은 우선)** = 로컬 CI 재현 레시피 보강 — 「REDIS_PORT=9」 대신 «일회용 redis-server 자유 포트(383xx)» + 워크트리 clients/web/node_modules 심링크(워크트리 규칙의 심링크 목록에 추가). 그래야 다음 로컬 묶음이 같은 11건을 다시 「기존 실패」로 들고 오지 않는다.

## 함정 (이번 실측)
- 전역 `redis-cli` 는 다른 docker 컨테이너(vectoragent-redis)로 alias 돼 있다 — 일회용 redis 확인은 `lsof -ti:<포트> -sTCP:LISTEN` 으로.
