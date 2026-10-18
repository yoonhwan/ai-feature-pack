# 인덱스: CI Python Test 병렬화 — pytest-xdist `-n auto --dist loadgroup` + 공유 Redis 모듈 한 그룹 + 가려진 공유 Redis 시험 db15 실행 (판정 446 · 설계 r2 · 판정 438 6분 목표)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 446(planner#11 #63292 · master#16 #63294) · 판정 438 다음 수(설계 438 §3-3 안 다)
- 상태: 대기
- 선행: 없음 — origin/main 최신에서 브랜치(판정 438 랜딩 5785530bea 포함 · ci.yml 은 main 이 ops/main-base 보다 19줄 앞)
- 시험 입력: ★일회용 Redis 격리 컨테이너★ 안에서 CI 경로 pytest 직렬 vs `-n 4`(아래 구현 범위 1) — 개발 Redis(호스트 127.0.0.1:6379) 접속 0 · 실제 GitHub Actions 실행은 PR 1회만
- 기준값: PR #935 CI Python Test 잡 8m53s = 준비 1m27s + Run tests 7m01s + V5 focused 18s(run 37743465246) · 6분 잡 = Run tests ≤ 약 4m10s

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(오빠 요청 즉시 검토 — 「ci가 이렇게 시간을 먹는 것을 해결해야지」) + C(업그레이드·반영). 핵심 한 줄: CI Python Test 를 병렬로 돌려 6분 안에 넣되, 병렬화가 어떤 시험도 «안 돌게» 만들지 않았음을 nodeid 상태표로 보인다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
CI Python Test 의 Run tests 단계는 한 프로세스로 7분 돈다. pytest-xdist 로 워커 여러 개에 나누면 줄어든다. 위험은 «테스트끼리 같은 것을 동시에 만지는» 경우뿐인데 arch·DA 대조 결과 격리 Redis(테스트마다 새 서버 · uuid 소켓)·고정 포트(포트 0)·/tmp 는 이미 안전하고, 남는 것은 공유 Redis 127.0.0.1:6379(db15·db0)에 직접 또는 간접(헬퍼 `lst_handoff_cases`→`lst_leaf_cases`/`lst_source_cases`→`lst_runtime_cases`)으로 붙는 모듈이다. 이 모듈들은 `pytest.mark.xdist_group("shared_redis_6379")` 로 묶어 `--dist loadgroup` 아래 한 워커에서 직렬로 돈다. 공유 Redis 시험 대부분은 이미 `requires_real_redis` 마커로 기본 런에서 빠지므로(병렬화가 그 목록을 바꾸면 안 된다) 실제 묶을 것은 마커 없이 수집되는 것들이다. DA 가 지적한 함정: «직렬·병렬 실패 집합이 같다» 만으로는, 둘 다 같은 이유(예 CI 에 `LST_TEST_REDIS_URL` 없음 → fixture RuntimeError)로 아예 안 돈 시험을 놓친다. 그래서 비교는 nodeid 하나하나의 상태(passed·failed·error·skipped)와 수집·deselected 수로 하고, 환경 때문에 가려진 공유 Redis 시험은 CI env 에 `LST_TEST_REDIS_URL: redis://localhost:6379/15` 를 넣어 실제로 passed 로 «돈» 것을 보인다. 공유 Redis 고정 URL 중 db0 도 있으므로(`test_lst_handoff_claim.py`) 로컬 비교는 반드시 일회용 Redis 컨테이너 안에서 한다 — 개발 Redis 는 라이브다.

## 사전검증
- 소환: 예
- DA: design/teams/harness/DA-xdist-446-20261008.md

## 조사 근거
- `.github/workflows/ci.yml:145` Run tests 명령(ops/main-base 사본 줄 · origin/main 은 155줄) · env REDIS_HOST/PORT·PAYMENT_MODE · `LST_TEST_REDIS_URL` 없음.
- `pyproject.toml:83` dev extra(pytest·pytest-asyncio · xdist 없음) — CI 는 `uv sync --frozen --all-extras`.
- `tests/worker/unit/conftest.py:26` `requires_real_redis` deselect(마커가 붙은 공유 Redis 시험은 기본 런 제외).
- `tests/worker/unit/lst_runtime_cases.py:45` `LST_TEST_REDIS_URL` 없으면 RuntimeError(db15 강제) · `tests/worker/unit/test_lst_handoff_claim.py:21` db0 고정 URL.
- `design/teams/harness/DESIGN-xdist-446-20261008.md:44` §6 r2 완료 조건(nodeid 상태표 · 6-2 가려진 시험 · 6-3 CI).

## 구현 범위 (닫힌 목록)
1. ★로컬 비교 환경(일회용 · 리포 파일 아님)★: `docker run --rm --network none` 컨테이너(ubuntu 또는 python:3.12 + `redis-server` + uv) 안에서 워크트리 «사본» 을 마운트하고 컨테이너 안 `127.0.0.1:6379` 에 redis-server 를 띄워 CI 와 같은 경로를 돈다. env = `REDIS_HOST=localhost REDIS_PORT=6379 PAYMENT_MODE=local_mock LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1` · `UPDATE_GOLDEN` 미설정을 RESULT 에 기록. 컨테이너를 못 띄우면 ★호스트에서 돌리지 말고★ 멈춰 보고(개발 Redis 쓰기 0).
2. `pyproject.toml` dev extra 에 `pytest-xdist` + `uv.lock` 갱신(`uv lock` · 다른 패키지 버전 변화 0 확인).
3. 공유 6379 모듈 표지: CI 경로(`tests/gateway/unit` · `tests/worker/unit` · `tests/infrastructure/gpu`)에서 수집되고 `requires_real_redis` 가 아닌, 127.0.0.1:6379 / `LST_TEST_REDIS_URL` 에 직접 또는 위 헬퍼 경유로 닿는 «테스트 모듈» 마다 `pytestmark = pytest.mark.xdist_group("shared_redis_6379")`(기존 pytestmark 있으면 리스트로 합침 · 헬퍼 `*_cases.py` 자체가 아니라 import 하는 테스트 모듈에). 대상 목록과 찾은 방법을 RESULT 에.
4. `.github/workflows/ci.yml` Run tests: `-n auto --dist loadgroup` 추가(`-v --tb=short` 유지) · 설계 §6-2 조건이 맞으면(가려진 nodeid 의 원인 = `LST_TEST_REDIS_URL` 미설정) 같은 단계 env 에 `LST_TEST_REDIS_URL: redis://localhost:6379/15`. V5 focused·RED observe 잡 무변경.
5. RESULT(`design/teams/harness/RESULT-xdist-446-<날짜>.md`): ①컨테이너 안 직렬 vs `-n 4 --dist loadgroup` 각 `--junitxml` 에서 뽑은 nodeid 상태표 diff(0 이어야 함) + 수집·deselected 수 ②`-n 4` 2회 반복 같은 표(★제한된 관측 · flake 부재 증명 아님★) ③기존 실패 원인별 표(직렬·병렬 같은 원인) ④가려졌던 공유 Redis nodeid 목록 → db15 env 뒤 passed ⑤`-v` 출력에서 공유 모듈 nodeid 전부 `@shared_redis_6379` 접미 ⑥워커 crash 0 ⑦벽시계 직렬·병렬.

커밋은 자기 브랜치, **push 금지**. **금지**: 호스트 개발 Redis(127.0.0.1:6379) 접속하는 실행 · 새 skip/deselect/xfail 추가 · 테스트 본문 수정(마커 줄 외) · `requires_real_redis` 목록 변경 · CI 재실행 반복(판정 436 — PR 은 master 가 1회 push).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- RESULT ①~⑦ 전부 · ①diff 0 · ⑥crash 0 · ⑤공유 모듈 전부 그룹 안.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: <컨테이너 안 -n 4 --dist loadgroup pytest 명령> rc=<n> · 이슈: 0` — rc 가 기존 실패 때문에 0 이 아니면 RESULT ③ 표와 같은 원인만인지 이슈 칸이 아니라 RESULT 에.
- 랜딩 뒤 master 집행(카드 밖): PR 1회 → CI Python Test 잡 시간 + 로그 「created: N/N workers」 실측 → planner 회신(≤6분 = 판정 438 닫힘 · >6분 = 라 재개 판단). 되돌림 = 1커밋 revert.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: cb0d313486ef2652dfcd2d94c27fbd64e8e888dc (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#15 · 판정 446 · master #63294 · 사전 DA r1 HOLD(Q3) → r2 APPROVE #63367).
- 정본 영향 없음: CI 설정·테스트 마커·dev 의존성만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 16:52 — 대기→진행 · 좌석 byz-harness-nano-v446-ci-pytest-xdist#0

세트: b7c0600dd0dda82a58b9e5e52801f0fe1e4f1bc9 · 시험: python3 -I /private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-v446-ci-pytest-xdist/0393d7e8-694d-4606-b86b-c066afd13241/scratchpad/tools/xdist_diff.py /private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-v446-ci-pytest-xdist/0393d7e8-694d-4606-b86b-c066afd13241/scratchpad/m_serial/junit.xml /private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-v446-ci-pytest-xdist/0393d7e8-694d-4606-b86b-c066afd13241/scratchpad/m_par_n4/junit.xml rc=0 · 이슈: 0
- 2026-10-08 17:46 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§67
