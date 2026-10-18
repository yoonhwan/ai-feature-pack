# 조사 — R63 측정 조작 가드 훅 후보 (byz-harness-arch-claude#20 · 2026-10-09 · 읽기 전용 · 집행 0)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: A(모니터·오빠 요청 — 오빠 절대지침 「임의 레디스랑 말풍선 dom 밀어넣기를 절대 하지 말라」 를 선언이 아니라 장치로).

## 결론 (먼저)
- **Bash 훅만으로는 실제 사고 3건 중 1건 정도만 잡힌다.** 사고 대부분이 «스크립트 파일 안»(`run.py` 의 `page.goto('/dev/bubble-replay')` · 시험 스크립트 안 `redis-cli PUBLISH`)이라, 훅이 보는 명령줄은 `python run.py`·`bash cell.sh` 뿐이다.
- **권고 = 2층**: ①`block-destructive.sh` 에 세 번째 블록(직접 명령줄의 Redis «상태 생성» 동사 + `/dev/bubble-replay` URL) — 판정 466 글 싱크 파서 재사용 ②증거 검사(press 결과·카드 증거 줄에 인용된 스크립트를 패턴 grep → 걸리면 REJECT/[HIL]) — 실제 사고 경로를 막는 쪽은 ②다.
- 쓰기(Write/Edit) 훅은 비권고(아래 3 — 오탐이 커서 «경고 목록»으로 자란다).

## 1. 기존 `block-destructive.sh` 와의 관계
- 위치: `~/.claude/hooks/block-destructive.sh`(180줄) = 키트 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh`(cmp 동일) · 등록 `~/.claude/settings.json` PreToolUse matcher `Bash` · 시험 `tests/harness/test_block_destructive.sh`.
- 구조: `judge()`(python · 판정 466) 가 명령을 구간으로 나눠 «글 싱크»(echo·printf·정본 mbox 송신·git commit·grep·대입·heredoc 본문) 글자를 빼고 `EFFECTIVE` 를 만든다 → `PATTERN`(파괴) grep → 그 뒤 `STAGE_PATTERN`(git add . — «파괴는 아니지만 되돌리기 어려움») 블록.
- ★선례 = STAGE_PATTERN★: 파괴가 아닌 규율도 같은 훅에 별 블록·별 문구로 들어가 있다. 새 블록을 같은 파일에 두면 ①글 싱크 파서를 공유해 «쪽지·문서에 redis-cli SET 을 글자로 쓴» 경우(이 조사 같은 글)가 통과하고 ②설치·키트 동기화 경로가 하나로 끝난다. 별 훅 파일로 빼면 파서를 복제해야 한다(판정 466 이 고친 오탐 15건/일이 되살아날 위험).
- 주의: STAGE_PATTERN 은 지금 `EFFECTIVE` 가 아니라 `$CMD` 원문을 본다 — 새 블록은 반드시 `EFFECTIVE` 를 봐야 한다(안 그러면 쪽지 본문 글자로 막힘).

## 2. 후보 패턴 (Bash · `EFFECTIVE` 기준 · 대소문자 무시)
| 후보 | 패턴 꼴 | 막는 것 | 판단 |
|---|---|---|---|
| Redis 상태 생성 동사 | `redis-cli` 뒤 같은 구간에 `SET`·`SETEX`·`MSET`·`HSET`·`HMSET`·`XADD`·`PUBLISH`·`LPUSH`·`RPUSH`·`SADD`·`ZADD`·`APPEND` (단어 경계) — `docker exec … redis-cli …` 포함 | 직접 주입(#996 꼴을 명령줄로 친 경우) | 권고 |
| 재생 페이지 URL | `/dev/bubble-replay` (curl·open·python -c·node -e 인자) | 재생 페이지 직접 호출 | 권고 |
| `appendChild`·`dispatchEvent`·`innerHTML` | 명령줄 글자 | — | **비권고** — FE 코드·시험에서 정상 사용이 대부분 · 명령줄에 나올 일은 `node -e` 정도라 잡는 것보다 오탐이 크다 |
| 파이썬 클라이언트 `.hset(`·`.xadd(` | 명령줄 `python -c` 인자 | 인라인 주입 | 보류 — `python -c` 인라인은 드물고, 파일이면 안 보인다(②로) |

**허용(막으면 안 되는 것)**:
- 읽기 동사 `GET`·`HGETALL`·`KEYS`·`SCAN`·`XINFO`·`XRANGE`·`TTL`·`DBSIZE`·`INFO` — byz-ops·ccu 프로브(`design/ccu/tools/redis_*_probe.py`)·press 전 잔여 키 확인이 쓴다.
- 정리 동사 `DEL`·`UNLINK`·`FLUSHDB` — press 전 게이트(CLAUDE.md «leftover keys decided (keep/flush)»)가 요구하는 정리다. 주입이 아니므로 이 블록에서 막지 않는다(`FLUSHALL` 을 파괴로 볼지는 별 판단 — 지금 PATTERN 에 없음).
- **격리 Redis 픽스처**: `tests/shared/prompts/_real_redis.py` `isolated_redis(tmp_path)` 는 pytest 안에서 python 클라이언트로 임시 포트 redis 를 쓴다 → 명령줄에 `redis-cli` 가 안 나오므로 **훅이 볼 일이 없다(오탐 0)**. `isolated_redis_url`(tests/e2e/token_synthetic_positive_control.py)도 python 인자 — 같음. 포트·환경변수로 «격리면 허용» 을 판별하는 예외는 두지 않는다(예외 플래그 = 우회로 · 훅 주석 «예외가 자라면 아무것도 안 막는다»).
- 정당한 운영 쓰기가 필요하면 기존 관행대로 «파일에 쓰고 사람이 `!` 로 실행» — 훅 문구에 그 길을 적는다.

## 3. Write/Edit 훅 (쓰기 시점) — 비권고
- 시험 스크립트를 «만드는» 순간 잡을 수 있지만, `/dev/bubble-replay` 는 `clients/web/app/dev/bubble-replay/page.tsx`(제품 dev 페이지 자체)·설계 문서·이 조사에도 나온다 → 경로 제한(`tests/e2e/**`·`design/**/evidence/**`)을 걸어도 문서·판정문 인용과 구분이 안 된다. 경고만 내면 아무도 안 본다(무시되는 경고 = 소음).

## 4. 증거 검사 (권고 ② — 실제 사고 경로)
- 관측점: press 산출(tester·checker 결과) · 카드 증거 줄 · 판정 요청서가 인용한 스크립트 경로.
- 동작: 그 스크립트 파일들을 `redis-cli[^\n]*\b(SET|HSET|XADD|PUBLISH|…)\b|/dev/bubble-replay|appendChild|dispatchEvent` 로 grep → 걸리면 «측정 조작 의심» 으로 REJECT + [HIL](쓴 키·주입 경로·회차·그 결과로 낸 판정 — BOOT 20 문장 그대로). 여기서는 `appendChild` 도 넣는다 — 대상이 «측정에 쓴 스크립트» 로 좁혀져 오탐이 작다.
- 붙일 자리 후보: `ft-press-gate.sh`(press 허가 발급 전 러너·인자 확인 — 러너가 기존 `tests/e2e/realtime_multi_e2e.py` 가 아니면 이미 거부하는지 먼저 확인 필요) · master 의 증거 줄 수락 단계(카드 lint). 어느 쪽이 맞는지는 다음 카드에서 그 두 스크립트를 읽고 정한다.

## 5. 적용 범위
- 훅 ①: 전역(`~/.claude/settings.json` · 전 프로젝트 · 전 좌석). 근거 = 전역 하드 룰 11 이 이미 전역. BYZ 고유 글자(`/dev/bubble-replay`)는 다른 프로젝트에서 나올 일이 없어 부작용 0. 키트 템플릿 → 각 머신 설치(골 축 C) 경로는 기존 block-destructive 와 같다.
- 내부 오류 처리: 기존과 같이 `judge` 실패 = 원문 전체에 패턴(fail-closed). 새 블록도 같은 `EFFECTIVE` 를 쓰므로 별도 처리 0.
- master·planner 좌석 포함(예외 0). codex·cursor 좌석은 Claude 훅을 안 탄다 → ②가 그 빈자리를 메운다.

## 6. 다음 카드 제안 (오빠/planner 컨펌 뒤)
1. `r63b-block-destructive-inject` — 세 번째 블록(2 의 «권고» 두 줄 · `EFFECTIVE` 기준) + `test_block_destructive.sh` 에 양성(직접 SET/PUBLISH/XADD · `docker exec … redis-cli HSET` · `curl …/dev/bubble-replay`) · 음성(GET·SCAN·DEL·FLUSHDB · mbox 본문/echo/grep 패턴 글자 · `python -m pytest`(isolated_redis)) + 변이 대조. 구현 DA 1회(훅 = 전 좌석 영향).
2. `r63c-evidence-injection-lint` — 4 의 증거 검사 · 붙일 자리 결정 포함.

## 근거 (실측 · origin/main 78f80f82fe)
- `~/.claude/hooks/block-destructive.sh:18`(PATTERN) · `:24-144`(judge · 글 싱크) · `:145-151`(EFFECTIVE 계산·PATTERN grep) · `:171-178`(STAGE_PATTERN · `$CMD` 원문).
- 재생 페이지 사용처: `design/feature/evidence/multilingual-linebreak-impl-20261008/run.py:20,27` · `fonts.py:9`(전부 `page.goto` — 명령줄엔 안 나옴).
- 격리 픽스처: `tests/shared/prompts/_real_redis.py:30` `isolated_redis` · `tests/shared/prompts/_freeze_helpers.py:35`.
- 오빠 원문·사례: 메모리 `feedback_no_arbitrary_redis_or_bubble_dom_injection`(#887·#889·#996).
