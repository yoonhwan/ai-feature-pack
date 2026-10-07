# 인덱스: Issue 855 — pytest 가 리포 루트 .env 를 읽지 않게 (로컬 = CI 조건) · 시험 격리 5건
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의). 핵심 한 줄: 원장 R12 · Issue 855(planner#5 #59290 · 오빠 판정 harness-ops · 완성 전) — 로컬 CI 묶음 실패 5건(GPU status 3 · pulse carry 2), GitHub CI 는 green. 원인 규명 = arch#5 #59295(아래 배경).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`shared/config/settings.py` 는 import 시 49행 `load_env_file(override=False)` 로 리포 루트 `.env`(APP_ENV=local → ENV_FILE_MAP 「.env」)를 읽는다. CI 러너엔 .env 가 없어 green, 로컬 워크트리엔 .env 심링크가 있어 실환경 값이 시험에 샌다. 실측(arch#5 · origin/main 01bfc82454 사본 · Redis 죽은 포트 9): ①`tests/gateway/unit/test_gpu_uptime.py` 3건 — APP_ENV=local + DEV_GPU_STATUS_URL 이 있으면 `gateway/routes/api/v1/gpu.py` 63~70행 `_dev_proxy_base_url()` 3중 게이트가 열려 FakeRedis 대신 prod status API 를 HTTP 로 읽는다(.env 없이 30 passed · 그 두 값만 주면 정확히 3 FAILED). ②`tests/worker/unit/test_pulse_consumer_carry_integration.py` 2건 — .env 를 붙이면 기대 {'en':'Hello'} 대신 실제 번역 문장이 6초 걸려 나온다 → 어떤 키가 FakeGraph 를 우회해 실 번역·LLM 경로를 연다(★실 과금 가능★ · 단일 변수 V6_LST·V6_AUTHORITATIVE_STT_MODE·APP_ENV 로는 재현 안 됨 · 키 미확정). 선례: `tests/_live_gpu_guard.py`(루트 conftest 가 적재 · 라이브 vLLM env 를 127.0.0.1:9 로 덮는 M7 가드) — 같은 «루트 conftest 에서 프로세스 전역으로 막는» 방식. CI 명령 = `.github/workflows/ci.yml` 145행(`uv run pytest tests/gateway/unit tests/worker/unit tests/infrastructure/gpu --ignore-glob='*_red.py' --ignore-glob='*_red_*.py'` · job env REDIS_HOST·REDIS_PORT·PAYMENT_MODE=local_mock).

## 구현 범위 (이 넷만 — 닫힌 목록)
1. `shared/config/settings.py` `load_env_file`: env `BYZ_TEST_SKIP_DOTENV=1` 이면 load_dotenv 를 부르지 않고 `(app_env, env_filename + " (skipped: BYZ_TEST_SKIP_DOTENV)", False)` 반환 — 기존 Startup Diagnostics 출력에 그대로 보인다(무음 0). ★`"pytest" not in sys.modules` 인데 스위치가 켜져 있으면 RuntimeError★(제품 프로세스에서 설정이 조용히 안 읽히는 경로 0 · #0 RULE). 스위치 없으면 지금 동작 그대로(반환 모양 무변화).
2. `tests/conftest.py`: 첫 import «앞»(모듈 docstring 바로 다음)에 `os.environ["BYZ_TEST_SKIP_DOTENV"] = "1"`(강제) + 이유 주석 2줄(Issue 855 · CI 는 .env 없음). 앱 모듈이 이보다 먼저 settings 를 import 하지 않는지 RESULT 에 확인 방법·결과 1줄(예: 시험 출력의 「ENV_FILE: .env (skipped…)」 줄).
3. 방어(셸 env 에 같은 값이 export 돼 있어도 깨지지 않게): `tests/gateway/unit/test_gpu_uptime.py` 의 해당 3건이 쓰는 픽스처에서 `DEV_GPU_STATUS_URL` delenv + gpu 모듈 `_dev_proxy_cache = None`·`_dev_proxy_ts = 0.0` 리셋. pulse 2건: 실 번역 경로를 여는 키를 ★코드 대조로만★ 확정(실 호출 실행 금지) → 그 시험 픽스처에서 delenv · 확정 못 하면 후보 목록을 RESULT 에.
4. 시험 `tests/gateway/unit/test_settings_dotenv_skip.py`(신규): 스위치 켜짐 → load_dotenv 호출 0(monkeypatch 로 기록) + 반환 3번째 False + 파일명에 「skipped」 · 스위치 꺼짐 + 임시 .env 경로 → 호출 1 · subprocess `python -c "import shared.config.settings"`(env BYZ_TEST_SKIP_DOTENV=1 · pytest 미적재) → 종료코드≠0 + stderr 에 RuntimeError.
커밋은 자기 브랜치, **push 금지**. **금지**: 스위치 외 settings 동작 변경 · APP_ENV 기본값 변경 · gpu.py·pulse 제품 코드 변경 · 라이브 Redis(6379 = v6-realtime-live dev 컨테이너) 접촉 · ★수정 전 .env 붙인 pulse 실행(실 과금 경로) 0회★.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 수정 전 RED: 같은 브랜치 수정 전 커밋에서 `test_gpu_uptime.py` 만 APP_ENV=local + DEV_GPU_STATUS_URL=http://127.0.0.1:9 로 3 FAILED 출력 복붙(pulse 는 RED 실행 금지 — arch#5 실측으로 대체).
- 수정 후: .env 심링크가 있는 이 워크트리에서 CI 명령(ci.yml 145행 그대로) + env PAYMENT_MODE=local_mock · REDIS_HOST=localhost · REDIS_PORT=9 · LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1 + 타임아웃 래퍼 + 대칭 deselect 3(struct3[finalized] · TestHostEnter · selfhost_warms_qwen_vllm) → ★855 5건 PASS★ · 그 밖의 실패가 있으면 «Redis 연결 거부로만 깨지는 시험» 목록 + 같은 명령을 .env 없는 사본(git archive)에서 돌린 실패 집합과 «동일» 함을 표로(= 남은 차이는 CI 의 Redis 서비스뿐).
- `ruff check` 변경 파일 OK · 신규 시험 rc=0.
- ★수락 경계(정정 계약 · DA-i855-20261007.md §5·§7 APPROVE · arch#6 2026-10-07)★: ⓐ스위치는 «프로세스 전역»이다 — tests/conftest.py 를 적재·import 하는 pytest 프로세스 전부에 적용되며, tests.conftest 를 import 하는 tests/ 밖 conftest(실례 design/v65/20260930/repro/conftest.py:15)는 «의도된 opt-in 공유»로 수락한다(시험 파일 단위 격리 보장 아님). ⓑ그 pytest 가 띄운 자식 프로세스는 BYZ_TEST_SKIP_DOTENV·PYTEST_CURRENT_TEST 두 env 를 물려받아 .env 를 건너뛴다(수락된 한계 · 자식이 둘 중 PYTEST_CURRENT_TEST 를 지우고 스위치만 남기면 RuntimeError — 시험 test_settings_dotenv_skip 이 그 경로를 고정). ⓒtests.conftest 를 적재하지도, 스위치를 물려받지도 않는 별개 pytest·제품 프로세스에는 닿지 않는다.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: ad7481bc1ab549c7aabb738bedbef85b9836847c (spawn 2026-10-07)
- base: 최신 origin/main.
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#6 · 원장 R12 · Issue 855 · 원인 arch#5 #59295).
- 정본 영향: 제품 파일 1개(shared/config/settings.py · pytest 전용 스위치) — docs/architect 정본 변경 없음. settings 변경이라 DA 소환 권고(스위치가 제품 프로세스에서 켜질 경로 0 인지).
- 정본 영향 없음: docs/architect 에 .env 적재(load_env_file·ENV_FILE_MAP·load_dotenv) 서술이 0건이고(git grep 실측 · DDD_ARCHITECTURE.md:183 은 파일 트리의 settings.py 이름뿐) 바뀐 것은 pytest 프로세스에서만 켜지는 시험 격리 스위치라 제품 런타임 동작·설계 서술이 그대로다 (arch#6 2026-10-07)
- 2026-10-07 18:34 — 대기→진행 · 좌석 byz-harness-nano-i855-test-dotenv-isolation#0
- 게이트 증거(나노 2026-10-07): 세트: 215f52056ab552c578f1f535ccf06f0d6b3b4cfb · 시험: ci.yml 145행 CI 묶음 + 대칭 deselect 3(.env 심링크 있음) 수정 후 첫 전체 실행 rc=1(7471 passed·27 failed: 16=내 가드가 자식 인터프리터에서 터진 회귀→PYTEST_CURRENT_TEST 추가로 수정 · 남은 11은 재실행 rc=1 11 failed, .env 없는 git archive 사본과 실패 집합 동일 · 전체 재실행은 master 대조 중이라 안 함) · 855 5건 대상 시험 PASS(gpu_uptime 포함 12 · pulse carry 11) · 이슈: 0
- RED 2 vs 3: 카드의 «gpu 3건»은 test_gpu_uptime 단독이 아니다 — 수정 전 base(ad7481bc1a)에서 APP_ENV=local+DEV_GPU_STATUS_URL=http://127.0.0.1:9 로 gpu 관련 8파일을 돌리면 dev-proxy 때문에 test_gpu_uptime 2건(test_status_reports_uptime_when_warm·test_status_zero_uptime_when_cold) + test_gpu_auto_warmup_toggle::test_status_reports_auto_warmup_false_when_key_absent 1건 = 3 FAILED(Redis·시계 의존 아님 · 같은 원인 gpu.py _dev_proxy_base_url). 세 번째 건은 다른 파일이고, 수정 후엔 conftest 스킵으로 통과(27 failed 목록에 없음). 같은 실행의 test_gpu_vm_control 2건은 Redis 거부(855 밖).
- 세트: 215f52056ab552c578f1f535ccf06f0d6b3b4cfb · 시험: bash -c 'pytest tests/gateway/unit/test_gpu_uptime.py tests/gateway/unit/test_settings_dotenv_skip.py tests/worker/unit/test_pulse_consumer_carry_integration.py' rc=0 · 이슈: 0
- 2026-10-07 19:27 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§31
