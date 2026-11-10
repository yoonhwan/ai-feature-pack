# 인덱스: 공용 격리 Redis fixture 기동 대기 단축 — _v65_l6_redis._serve 소켓 대기 + kill (판정 438 · 설계 §2 안 가)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 438(오빠 「ci가 이렇게 시간을 먹는 것을 해결해야지 로컬 pytest 돌리면 원인 바로 나오자나?」 · planner REQ-436b · master #63022)
- 상태: 대기
- 선행: 없음(origin/main 최신에서 브랜치)
- 시험 입력: CI 와 같은 경로·인자의 로컬 pytest(아래) — tests/ 전체 금지 · 실제 GitHub Actions 실행 0
- 기준값: CI Python Test 21.0분(Run tests 19:14 · 1~5s 426개 11.2분) · arch 샘플 12파일 70테스트 88.79초(최장 setup 2.72초) → 실험 플러그인으로 3.38초 · 70 passed 동일

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: C(업그레이드·반영 — 전 트랙 랜딩 경로 속도·비용 · 판정 436 후속). 핵심 한 줄: 테스트마다 새 Redis 를 띄우는 격리는 그대로 두고, 소켓이 생기기 전 ping 이 부르는 redis-py 재시도 백오프(1~2초)만 없앤다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`tests/worker/unit/_v65_l6_redis.py` 의 `_serve` 는 테스트마다 redis-server 를 unix socket 으로 띄우고 곧바로 `client.ping()` 을 친다. 소켓 파일이 아직 없으면 redis-py 7.4 의 기본 재시도(`ExponentialWithJitterBackoff(base=1, cap=10)`)가 ping 한 번 «안에서» 0~1초 이상 잠들어, 테스트마다 setup 이 1~2초 걸린다(204파일이 이 fixture 를 import · CI 1~5s 대 426개 11.2분의 정체). redis-server 자체는 10~17ms 에 소켓을 연다. 그래서 «소켓 파일이 생길 때까지 짧게 폴링한 뒤 ping» 하면 재시도에 들어가지 않는다. 정리도 `terminate()+wait()` 0.12초 대신 `kill()` 로 줄인다 — 서버 인자가 `--save '' --appendonly no` 라 디스크에 쓸 것이 없다. 격리 의미(테스트마다 새 서버)·서버 인자·fixture 이름·`--rename-command CLIENT ''` 판은 그대로다. 설계 정본 design/teams/harness/DESIGN-pytest-speed-438-20261008.md §1~§3.

## 사전검증
- 소환: 아니오
- 면제: 격리 의미 무변경(테스트마다 새 서버 유지) · 판정 438 planner 「DA 사전 1회는 격리 의미가 바뀌는 안만」 · arch 실측 전후 70테스트 동일 통과 — arch 서명 byz-harness-arch-claude#14

## 조사 근거
- `tests/worker/unit/_v65_l6_redis.py:14` `_serve` · `:22`~`:31` ping 루프(소켓 대기 없음) · `:33`~`:35` teardown terminate+wait · `:38`~`:49` 같은 이름 `redis` fixture 이중 정의(뒤 판이 이김 — 이 카드는 무변경 · 관찰만).
- `design/teams/harness/DESIGN-pytest-speed-438-20261008.md` §1 실측 표(재시도 객체 `_base: 1, _cap: 10` · 소켓 생성 0.009~0.017초 · 샘플 88.79 → 3.38초).
- `.github/workflows/ci.yml` Python Test 의 pytest 경로·인자(로컬 측정은 이것과 같게).

## 구현 범위 (닫힌 목록 · 1파일)
1. `tests/worker/unit/_v65_l6_redis.py` `_serve` 만:
   - ping 전에 소켓 파일 대기: `process.poll()` 이 None 인 동안 `os.path.exists(socket)` 를 2ms 간격으로 최대 1000회(≈2초) 확인 · 프로세스가 먼저 죽으면 지금 문구 그대로 RuntimeError · 상한 초과도 지금 문구 그대로 RuntimeError(조용한 폴백 0).
   - 소켓 확인 뒤 `await client.ping()` 1회(실패 = 그대로 raise).
   - teardown: `process.terminate()` → `process.kill()` (wait timeout 5 그대로).
2. 서버 인자 · fixture 이름 · 두 fixture 정의 · 다른 파일 변경 0.

커밋은 자기 브랜치(`[fix] 격리 Redis fixture — 소켓 대기 후 ping · kill 정리 (판정 438)` · 본문에 Why/What/Verify/Impact) · **push 금지**. **금지**: 이중 정의 정리 · session 범위 서버(안 나 · 기각) · xdist·slow 마커(측정 게이트 뒤 별 카드) · fakeredis · tests/ 전체 실행.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 로컬 전·후(같은 머신 · 같은 경로 · `LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1` · `timeout 2400`): `uv run pytest tests/gateway/unit tests/worker/unit tests/infrastructure/gpu --ignore-glob='*_red.py' --ignore-glob='*_red_*.py' -q -p no:cacheprovider --durations=20` — 전(main) · 후(나노 HEAD) 각 1회 · RESULT 에 총 시간·passed/failed 수·durations 상위 20 표 복붙 · ★passed/failed 수 전후 동일★(다르면 반송 — 어느 테스트인지 목록).
- `ruff check tests/worker/unit/_v65_l6_redis.py` 0.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: uv run pytest tests/worker/unit -q -p no:cacheprovider rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): PR CI Python Test 잡 분 전(21.0)·후 1줄 → planner 회신 · ≤6분이면 판정 438 닫힘 · >6분이면 설계 §3-3(라·다 결정)으로.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: e3556432ae795b1f192299dda15838356794780b (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#14 · 판정 438 설계 r1 §3-1 · master #63022).
- 정본 영향 없음: 테스트 fixture 만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 15:43 — 대기→진행 · 좌석 byz-harness-nano-v438-l6-redis-fixture-fast#0
세트: 7280f7cf5a7b7e47703ae6ac99685286dd37e4a4 · 시험: uv run pytest tests/worker/unit/test_v65_unsealed_terminal.py tests/worker/unit/test_v65_l6_pair_boundaries.py -q -p no:cacheprovider rc=0 · 이슈: 0
- 2026-10-08 16:38 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§62
