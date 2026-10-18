# DESIGN — 판정 438 CI Python Test 속도 (19분 → 6분 이하) · r1 (2026-10-08 · byz-harness-arch-claude#14)

## 골 원문 (GOAL-harness.md 복붙)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: C(업그레이드·반영 — 전 트랙 랜딩 경로 속도·비용 · 판정 436 후속). 오빠 원문(판정 438): 「ci가 이렇게 시간을 먹는 것을 해결해야지 로컬 pytest 돌리면 원인 바로 나오자나?」. 입력: planner REQ-436b(/tmp/mbox/…REQ-436b-pytest-speed-20261009.md) · master #63022.

## §1 발생 위치 실측 (arch · 로컬 · 리포 코드 무변경)
| 사실 | 값 | 근거 |
|---|---|---|
| CI Run tests | 19:14 · 7,773 테스트 직렬 · 분포 <1s 7,873개 4.4분 · 1~5s 426개 11.2분 · ≥5s 9개 3.6분 | planner · CI run 37733592718 |
| 1~5s 의 정체 | 공용 fixture `tests/worker/unit/_v65_l6_redis.py` 의 «setup» — 테스트마다 redis-server 기동 | planner · arch 샘플 상위 10개 전부 setup 1.82~2.72s |
| ★setup 이 느린 진짜 이유★ | redis-server 기동이 아니다(소켓 생성 0.009~0.017초). 소켓 파일이 생기기 «전»에 `client.ping()` → redis-py 7.4 기본 `Retry(ExponentialWithJitterBackoff(base=1, cap=10))` 가 연결 실패 1회마다 0~1초+ 대기 → setup 1~2초 | 로컬 프로브(`Redis(unix_socket_path=…).connection_pool.connection_kwargs['retry']` = `{_base: 1, _cap: 10}`) · 소켓 대기 후 ping 0.010~0.018초 |
| 정리(teardown) | `terminate()+wait()` 0.12초 / 테스트 | 로컬 프로브 |
| ★후보 가 실측★ | 같은 12파일 70테스트: ★88.79초 → 3.38초(26배) · 70 passed 동일★ · 최장 setup 2.72초 → 0.04초 | 실험 플러그인(scratchpad · `_serve` 교체만 · 리포 무변경) |
| ≥5s 는 다른 원인 | fixture 무관 «call» CPU — test_vad_carryover_e210_replay_v65.py control_c_true 31.0·30.9초 · stall_rule 9.1·8.4초 / test_credit_writer_term_registry.py 파라미터마다 2.7초(모듈 범위 소스 위에서 탐지기 전체 실행) · 가 적용 전후 103.6 → 100.4초(변화 없음) | 로컬 같은 2파일 전후 |
| 부수 발견 | `_v65_l6_redis.py` 가 이름 `redis` fixture 를 두 번 정의 — 뒤의 `--rename-command CLIENT ''` 판이 항상 이김 → import 하는 204파일 전부 CLIENT 막힌 서버를 받는다(앞 정의는 죽은 코드) | 소스 :38~:49 |
| fixture 사용 범위 | import 204파일(F401) | git grep |
| xdist | 미설치(pyproject·uv.lock 0) | git grep |

## §2 안 비교 (부하·메모리 필수)
| 안 | 내용 | 예상 Run tests | 부하(CPU·프로세스) | 메모리 | 격리 의미 | DA | 닫는 사건 |
|---|---|---|---|---|---|---|---|
| ★가★ | `_serve` 2곳: ①소켓 파일 생길 때까지 2ms 폴링 후 ping(재시도 백오프 0) ②teardown `kill()`(save·aof 꺼져 잃을 것 0) | 19.2 → ≈8분(1~5s 대 11.2분 → ≈0.5분 · <1s 대 안의 지터분 추가 감소 = 상한 추정) | 지금과 같음(테스트당 redis-server 1개 · 수명만 짧아짐) · sleep 대기 제거 | 같음(동시 redis 1개 ≈ 수 MB) | ★무변경★ — 테스트마다 새 서버 | 불필요 | 로컬 같은 경로 전후 --durations=20 · PR CI 분 |
| 나 | session 1회 기동 + 테스트마다 FLUSHALL(planner 처방 1) | 가 대비 추가 이득 ≈0.05초×N(수십 초) | 서버 1개 | 최소 | ★변경★ — 상태 누수·rename-command 판 공유·Lua 스크립트 캐시 공유 | 필요 | — |
| 다 | pytest-xdist `-n auto`(ubuntu-latest 4 vCPU) | 가 뒤 ≈8분 / ≈3 → ≈3분 | CPU 4배 동시 · 워커당 redis 동시 최대 4 | python 워커 4 × 수백 MB(≈1.5~2 GB · 러너 16 GB 안) | 테스트 간 «동시 실행» 이 새로 생김(/tmp·env·모듈 전역·`requires_real_redis` 는 이미 제외) | 필요(동시성) | uv.lock 추가 · 경로 충돌 0 시험 |
| 라 | e210 replay 4 + term_registry 를 `@pytest.mark.slow` → PR CI 제외 · 수동/야간만 | −≈3분 | 감소 | 감소 | 무변경 · 단 ★PR 커버리지 이동★(e210 회귀가 야간에야 잡힘) | 불필요 · ★커버리지 결정 필요★ | 마커 + ci.yml `-m "not slow"` |

- 나 는 기각: 가 가 같은 이득의 95% 이상을 격리 무변경으로 얻는다(남는 차이 수십 초) — 격리 의미를 바꿀 이유가 사라짐. planner 처방 1 의 목적(기동 비용 제거)은 가 로 달성.
- 다·라 는 가 의 PR CI 실측 뒤에만 판단(아래 §3).

## §3 순서 (arch 결정)
1. **가** — 나노 1장(카드 `대기/v438-l6-redis-fixture-fast.md`). DA 없음(격리 무변경 · 판정 438 planner 「DA 는 격리 의미가 바뀌는 안만」). 부수 발견(이중 정의)은 이 카드에서 건드리지 않고 관찰 기록(어느 테스트가 CLIENT 있는 서버를 기대했는지 모름 → 이름 분리는 별 카드 후보).
2. **측정 게이트** — 가 랜딩 뒤 첫 PR 의 Python Test 잡 분. ≤6분이면 끝. 
3. >6분이면: **라**(커버리지 이동 — planner 가 오빠 판정으로 결정 · 대상은 e210 control_c_true 2개만으로 줄이는 안 포함) 와 **다**(xdist · 사전 DA 1회) 중 planner 결정. 기대값: 가+라 ≈5분 run + 잡 준비 ≈1.8분 = ≈7분(6분 넘을 수 있음) · 가+다 ≈3분 run → 잡 ≈5분. ★6분 목표를 «확실히» 넘기려면 다 가 필요할 가능성이 높다(추정)★.

## §4 닫는 증거 (판정 438 그대로)
- 로컬 전·후: CI 와 같은 경로·인자(`uv run pytest tests/gateway/unit tests/worker/unit tests/infrastructure/gpu --ignore-glob='*_red.py' --ignore-glob='*_red_*.py'` · `LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1` · timeout 래퍼) `--durations=20` 전후 표 + 총 시간.
- PR CI Python Test 분 전·후 1줄(전 = 21.0분 · planner 실측).
- 로컬 실행 주의: tests/ 전체 금지(static_v4_guard 리포 복제 274G 사고) · CI 경로만.

## §5 남는 위험
- 소켓 폴링 상한(500×2ms = 1초) 을 넘는 느린 러너면 「did not start」 로 «보이게» 실패(raise · 조용한 폴백 0) — 지금의 100×(백오프) 대기보다 짧다 → 상한은 나노가 2초(1000회)로 두는 것을 권장.
- `kill()` 은 redis 가 디스크에 쓸 것이 없을 때만 안전 — 지금 인자 `--save '' --appendonly no` 가 그 조건(카드에 고정).
