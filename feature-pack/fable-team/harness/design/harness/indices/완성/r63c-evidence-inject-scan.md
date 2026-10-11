# 인덱스: R63 가드 ㉡ 증거 검사(차단 없음) — 증거에 인용된 스크립트의 임의 Redis 쓰기·말풍선 DOM 주입 흔적을 찾아 «보이게» (원장 R63 · 판정 589 · master#19 쪽지 #66546)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R63(우선 높음 · 판정 589 오빠 직접 지시 · ㉡ 먼저 → ㉠ `r63b-block-destructive-inject`)
- 상태: 대기
- 선행: 없음
- 시험 입력: 임시 폴더 픽스처 스크립트 + origin/main 실파일 2개(기존 러너 · 재생 측정 스크립트) — 네트워크·Redis·브라우저 0
- 기준값: origin/main 78f80f82fe 에 증거 스크립트를 주입 패턴으로 훑는 도구 0. 실제 사고 3건(#887 `design/feature/evidence/multilingual-linebreak-impl-20261008/run.py:20,27` 의 `page.goto('/dev/bubble-replay')` · #889 재생 하네스 유입 · #996 시험 스크립트 안 `redis-cli PUBLISH room_events:…`)은 전부 «스크립트 파일 안»이라 명령줄 훅(㉠)이 못 본다(조사 `design/harness/SURVEY-r63-injection-guard-hook-20261009.md` §결론).
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터·오빠 요청 — 오빠 절대지침 「임의 레디스랑 말풍선 dom 밀어넣기를 절대 하지 말라」 를 선언이 아니라 장치로). 핵심 한 줄: 닫히는 카드가 인용한 측정 스크립트에 주입 흔적이 있으면 닫는 순간 화면에 뜬다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오빠 절대지침(10-09 · BOOT 20 · 전역 하드 룰 11): 시험·측정에서 임의 Redis 쓰기(redis-cli SET·HSET·XADD·PUBLISH 등 제품 키 직접 주입)와 말풍선 DOM 주입(재생 하네스·/dev/bubble-replay·appendChild)으로 만든 결과는 증거가 아니다. 사고는 전부 «측정 스크립트 파일 안»에서 났다. 이 카드는 ①그 파일들을 패턴으로 훑는 도구 1개를 만들고 ②카드를 닫는 도구(`ft-index-move.sh` 진행→완성)가 카드에 인용된 증거·시험 경로를 그 도구로 훑어 결과를 «출력만» 하게 한다 — 이동 종료코드·차단 0(판정 589 «차단 없음»). 차단(명령줄)은 다음 카드 ㉠ 몫.

## 사전검증
- 소환: 아니오
- 면제 사유: 차단 0 · 종료코드 불변 · 출력 추가만(닫기 도구는 결과를 보여 주기만) — 구현 DA 없음 · arch 재현으로 닫는다 — arch 서명 byz-harness-arch-claude#20

## 조사 근거 (origin/main 78f80f82fe · arch#20)
- `scripts/fable-team-bin/ft-index-move.sh`(114줄): 28-46행 진행→완성(--da 판정문 검사·정본 게이트) · 48행~ 슬랙 답글 · 이동은 그 뒤.
- 대조 실파일: 기존 러너 `tests/e2e/realtime_multi_e2e.py`(trusted 클릭 `Input.dispatchMouseEvent` — `dispatchEvent(` 와 다른 글자) · 격리 픽스처 `tests/shared/prompts/_real_redis.py:30` `isolated_redis` · 위반 실례 `design/feature/evidence/multilingual-linebreak-impl-20261008/run.py`.

## 구현 범위 (닫힌 목록)
1. 새 도구 `scripts/fable-team-bin/ft-evidence-inject-scan.sh <파일|폴더>...` (+ 키트 사본 `scripts/harness-install/fable-team/bin/` cmp 동일 · 200줄 이하 · 셔뱅 `#!/usr/bin/env bash`):
   - 대상: 인자 파일 + 폴더 안 `*.py *.sh *.js *.mjs *.ts` (그 밖 확장자·바이너리 0).
   - 패턴(대소문자 무시 · 줄 단위): ⓐ `redis-cli` 뒤 같은 줄에 상태 생성 동사 `SET SETEX SETNX MSET HSET HMSET HSETNX XADD PUBLISH LPUSH RPUSH SADD ZADD APPEND INCR INCRBY`(앞뒤 공백·따옴표·줄끝 경계) ⓑ 클라이언트 쓰기 호출 `.hset( .hmset( .xadd( .publish( .lpush( .rpush( .sadd( .zadd(` ⓒ `/dev/bubble-replay` ⓓ `appendChild` · `innerHTML\s*=` · `dispatchEvent\(`(★`dispatchMouseEvent` 는 안 맞는다★).
   - 허용(SUSPECT 아님): 읽기 동사(GET·HGETALL·KEYS·SCAN·XINFO·XRANGE·TTL·DBSIZE·INFO)·정리 동사(DEL·UNLINK·FLUSHDB). ⓑ 가 `isolated_redis` 를 import/호출하는 파일 안이면 `NOTE`(격리 픽스처 — BOOT 20 «별개»).
   - 출력: 걸린 줄마다 `SUSPECT <파일>:<줄> <ⓐ|ⓑ|ⓒ|ⓓ> <그 줄 앞 80자>` / `NOTE …` · 끝에 `INJECT-SCAN files=<N> suspect=<K> note=<J>` 1줄. SUSPECT 가 1개 이상이면 그 요약 줄을 `<FT_ROOT>/.fable-team/state/inject-scan.log` 에 시각과 함께 1줄 append.
   - 종료코드: 0 = 훑음 끝(SUSPECT 유무 무관 — 차단 도구 아님) · 1 = 인자 경로 없음(`MISSING <경로>` · 조용히 0 금지) · 2 = 인자 0.
2. `scripts/fable-team-bin/ft-index-move.sh`(+ 키트 사본): 진행→완성 이동 «직전»에 카드 본문에서 실재하는 경로 중 `design/**/evidence/**`·`tests/**`·`*.py`·`*.sh` 를 뽑아 1 의 도구로 훑고 출력을 그대로 보인다. ★이동 종료코드·REJECT 판정 불변★ · 도구 실행 실패 = stderr `ERROR inject-scan rc=<n>` 1줄(보이게) + 이동 계속. 줄 수 증가 10줄 이하.
3. 시험 `tests/harness/test_evidence_inject_scan.sh`(200줄 이하): 대조표 아래.
4. 기존 시험 PASS: `tests/harness/test_index_move_slack.sh` · `tests/harness/test_index_move_canon_landed.sh` · `tests/harness/test_kit_bin_sync.sh` · `bash -n` 4파일.
커밋은 자기 브랜치, **push 금지**. **금지**: 차단·REJECT 추가 · `ft-press-gate.sh` 수정 · 라이브 FT_BIN 쓰기 · 홈 훅 작업(㉠ 몫).

### 대조표 (시험이 1행 = 1검사로 고정)
| # | 입력 | 기대 |
|---|---|---|
| 1 | 픽스처 `.sh` 에 `redis-cli -p 6379 PUBLISH room_events:r1 '{}'` | SUSPECT ⓐ |
| 2 | 픽스처 `.sh` 에 `docker exec byz-redis redis-cli HSET k f v` | SUSPECT ⓐ |
| 3 | 픽스처 `.py` 에 `page.goto(f'{BASE}/dev/bubble-replay?scenario=static')` | SUSPECT ⓒ |
| 4 | 픽스처 `.js` 에 `el.appendChild(bubble)` · `.py` 에 `r.xadd("s", {...})` | SUSPECT ⓓ · ⓑ |
| 5 | 픽스처: `redis-cli GET k` · `redis-cli --scan --pattern 'stt:*'` · `redis-cli DEL k` · `redis-cli FLUSHDB` · `curl -s http://127.0.0.1:8080/health` | SUSPECT 0 |
| 6 | 픽스처 `.py` 에 `from tests.shared.prompts._real_redis import isolated_redis` + `client.hset(...)` | NOTE 1 · SUSPECT 0 |
| 7 | 실파일 `tests/e2e/realtime_multi_e2e.py` | SUSPECT 0 (기존 러너 오탐 0) |
| 8 | 실파일 `design/feature/evidence/multilingual-linebreak-impl-20261008/run.py` | SUSPECT ≥ 1 (ⓒ) |
| 9 | 없는 경로 | rc=1 · `MISSING` |
| 10 | 임시 카드(증거 줄에 #3 픽스처 경로) 진행→완성(판정문 스텁) | SUSPECT 줄 출력 · 이동 rc=0 · 카드 완성/ 으로 이동 |
| 11 | 변이: ⓒ 패턴 제거 복사본 | #3 FAIL (음성 대조) |

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · 키트 cmp 동일.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_evidence_inject_scan.sh rc=0 · 이슈: 0`.
- 결과 보고에 대조표 11행의 실측 값(기대/실제) 표를 붙인다.
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN 에 2파일 설치 복사(cp+cmp).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 5dc3218cf3a457dd6f082aa91744d0c1d8c34061 (spawn 2026-10-09)
- 2026-10-09 01:3x — 대기/ 생성 (byz-harness-arch-claude#20 · 원장 R63 · 판정 589 · master#19 쪽지 #66546).
- 정본 영향 없음: 하네스 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 01:19 — 대기→진행 · 좌석 byz-harness-nano-r63c-evidence-inject-scan#0

## 결과 (나노 RESULT · master#20 옮김 2026-10-09)
세트: 2cbf28f0cf82034f5967b0c141cfd3220f0b7ae0 · 시험: bash tests/harness/test_evidence_inject_scan.sh rc=0 · 이슈: 0
정본 영향 없음: 하네스 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 01:29 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§92
