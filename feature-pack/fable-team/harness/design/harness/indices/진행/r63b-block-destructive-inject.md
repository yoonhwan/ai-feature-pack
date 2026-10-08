# 인덱스: R63 가드 ㉠ block-destructive 세 번째 블록 — 명령줄의 임의 Redis 쓰기·bubble-replay URL 차단 (원장 R63 · 판정 589 · master#19 쪽지 #66546)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R63(우선 높음 · 판정 589 오빠 직접 지시 · ㉡ `r63c-evidence-inject-scan` 다음)
- 상태: 대기
- 선행: `r63c-evidence-inject-scan` 랜딩(순서 = 판정 589)
- 시험 입력: 키트 훅에 PreToolUse JSON 만 넣어 종료코드를 본다(`tests/harness/test_block_destructive.sh` 꼴 · 명령 실행 0 · 홈 훅 0)
- 기준값: origin/main 78f80f82fe 의 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh`(= 홈 `~/.claude/hooks/block-destructive.sh` cmp 동일 · 180줄)의 PATTERN(18행)·STAGE_PATTERN(171행)에 Redis 쓰기 동사·`/dev/bubble-replay` 0 → `redis-cli PUBLISH …`·`curl …/dev/bubble-replay` 가 그대로 실행된다.
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터·오빠 요청 — 오빠 절대지침 「임의 레디스랑 말풍선 dom 밀어넣기를 절대 하지 말라」 를 장치로) + C(배포·반영 — 키트 템플릿 = 전 머신 설치본). 핵심 한 줄: 명령줄에서 직접 치는 주입은 실행 전에 막히고, 정상 읽기·정리·기존 러너·픽스처는 하나도 안 막힌다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
전역 PreToolUse(Bash) 훅 `block-destructive.sh` 는 판정 466 의 `judge()`(python)로 명령을 구간으로 나눠 «글 싱크»(echo·printf·정본 mbox 송신·git commit·grep·대입·heredoc 본문) 글자를 뺀 `EFFECTIVE` 를 만들고(145행) 그것에 PATTERN 을 grep 한다(147행). 그 뒤 STAGE_PATTERN(파괴는 아니지만 되돌리기 어려운 `git add .`) 블록이 선례로 있다. 이 카드는 같은 파일에 세 번째 블록 INJECT 를 넣는다 — ★반드시 `EFFECTIVE` 를 본다★(STAGE 처럼 `$CMD` 원문을 보면 쪽지 본문·grep 패턴 글자로 막힌다 · 판정 466 이 고친 오탐 15건/일 재발). 홈 훅은 추적 밖이라 ★추적본 = 키트 템플릿★ 이고 홈 설치는 랜딩 뒤 master 집행이다.

## 사전검증
- 소환: 아니오 (설계 = 조사 `design/harness/SURVEY-r63-injection-guard-hook-20261009.md` §2·§5 + 판정 589 조건)
- 구현 DA: ★예 1회★ — 전 좌석·전 프로젝트 Bash 에 걸리는 훅(오탐 = 전 팀 마비). 질문 고정: Q1 대조표 오탐 0 · Q2 위반 차단 · Q3 `EFFECTIVE` 기준(글 싱크 통과) · Q4 기존 PATTERN·STAGE 시험 회귀 0. bounded(새 요구 0).

## 조사 근거 (origin/main 78f80f82fe · arch#20)
- `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh`: 18행 PATTERN · 24-144행 judge · 145행 EFFECTIVE · 147-152행 PATTERN 차단 · 171-178행 STAGE(원문 `$CMD`) · 셔뱅 `#!/bin/bash`(3.2).
- `tests/harness/test_block_destructive.sh`(138줄 · `/bin/bash "$HOOK"` 로 셔뱅 그대로 · 차단 ≥52 · 통과 ≥18).
- 등록: `~/.claude/settings.json` PreToolUse matcher `Bash` → `bash ~/.claude/hooks/block-destructive.sh`.

## 구현 범위 (닫힌 목록)
1. 키트 템플릿 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh` 에 INJECT 블록 1개(PATTERN 블록 뒤 · STAGE 앞 · `EFFECTIVE` 대상 · `grep -qiE`):
   - `redis-cli` 뒤 같은 구간에 상태 생성 동사 `SET SETEX SETNX MSET HSET HMSET HSETNX XADD PUBLISH LPUSH RPUSH SADD ZADD APPEND INCR INCRBY`(단어 경계 — `GET setting`·`--pattern 'x:set*'` 은 안 맞게) · `/dev/bubble-replay`.
   - 차단 문구(stderr): 「🚫 측정 조작 차단 — 임의 Redis 쓰기·말풍선 DOM 주입(오빠 절대지침 · BOOT 20 · 전역 하드 룰 11)」 + 명령 + 「측정은 trusted 클릭 + 기존 e2e 러너만 · 정당한 운영 쓰기는 파일에 쓰고 사람이 ! 로 실행」 · `exit 2`.
   - bash 3.2 호환(`/bin/bash`): 빈 배열·`declare -A`·`${x,,}` 0.
2. 새 시험 `tests/harness/test_block_destructive_inject.sh`(200줄 이하 · `test_block_destructive.sh` 의 run/expect 꼴 · `/bin/bash "$HOOK"`) — 대조표 아래 + 변이 대조.
3. 대조표 산출 `design/harness/evidence/r63b-block-destructive-inject/TABLE.md` — 행마다 명령 · 기대 rc · 실제 rc.
4. 기존 시험 PASS: `tests/harness/test_block_destructive.sh`(회귀 0) · `bash -n` 템플릿.
커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.claude/hooks/` 쓰기·settings.json 수정(설치 = master) · PATTERN·STAGE·judge 변경.

### 대조표 (시험이 1행 = 1검사로 고정)
| # | 명령 | 기대 |
|---|---|---|
| B1 | `redis-cli PUBLISH room_events:r1 '{"t":1}'` | 2 |
| B2 | `redis-cli -p 6380 SET k v` | 2 |
| B3 | `docker exec byz-redis redis-cli HSET k f v` | 2 |
| B4 | `bash -c "redis-cli XADD s '*' a b"` | 2 |
| B5 | `curl -s 'http://127.0.0.1:3001/dev/bubble-replay?scenario=static'` | 2 |
| B6 | `python3 - <<'EOF'` + `page.goto('http://x/dev/bubble-replay')` + `EOF` | 2 |
| P1 | `redis-cli GET k` · `redis-cli HGETALL k` · `redis-cli --scan --pattern 'stt:*'` · `redis-cli GET setting` | 0 |
| P2 | `redis-cli DEL k` · `redis-cli FLUSHDB` | 0 |
| P3 | `python -m pytest tests/shared/prompts -q`(isolated_redis 픽스처) | 0 |
| P4 | `python3 tests/e2e/realtime_multi_e2e.py --help`(기존 러너) | 0 |
| P5 | `curl -s http://127.0.0.1:8080/health` (일반 curl) | 0 |
| P6 | 정본 mbox send 본문에 「redis-cli SET」·「/dev/bubble-replay」 글자 | 0 |
| P7 | `grep -n 'redis-cli PUBLISH' f` · `echo "/dev/bubble-replay"` · `git commit -m "redis-cli SET 금지"` | 0 |
| M1 | 변이: INJECT 블록이 `EFFECTIVE` 대신 `$CMD` 를 보게 바꾼 복사본 | P6·P7 FAIL |
| M2 | 변이: INJECT 블록 제거 복사본 | B1·B5 FAIL |

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · 기존 `test_block_destructive.sh` rc=0 · 구현 DA 판정문 APPROVE.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_block_destructive_inject.sh rc=0 · 이슈: 0` (+ 대조표 경로).
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다.
- ★랜딩 뒤 master 집행(카드 밖 · 판정 589 planner 조건)★:
  1. 원본 백업 `cp ~/.claude/hooks/block-destructive.sh ~/.claude/hooks/block-destructive.sh.bak-r63b-<날짜>`.
  2. 키트 템플릿 → 홈 설치(cp+cmp).
  3. 셔뱅 인터프리터 그대로(`/bin/bash`) 홈 설치본으로 대조표 B1·P1·P5·P6 재생(JSON 주입 · 명령 실행 0).
  4. 적용 뒤 «첫 도구 호출» 실측 — 평범한 Bash 1회(rc 0) + 다른 좌석 1곳의 다음 Bash 정상 확인.
  5. ★오탐 1건이면 즉시 원복★(백업 cp · 원복 사실 + 오탐 명령을 원장에 기록 · 카드 반송).
  6. 완료 보고 = 대조표 경로 + 랜딩 sha 1줄.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 5dc3218cf3a457dd6f082aa91744d0c1d8c34061 (spawn 2026-10-09)
- 2026-10-09 01:3x — 대기/ 생성 (byz-harness-arch-claude#20 · 원장 R63 · 판정 589 · master#19 쪽지 #66546).
- 정본 영향 없음: 하네스 훅 템플릿·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 01:26 — 대기→진행 · 좌석 byz-harness-nano-r63b-block-destructive-inject#0

## 결과 (나노 RESULT r3 · master#20 옮김 2026-10-09)
세트: 9c4ef5fb79ff5308373b27a163304ae021ae6051 · 시험: bash tests/harness/test_block_destructive_inject.sh rc=0 · 이슈: 0
정본 영향 없음: 하네스 훅 템플릿·시험만 — docs/architect 제품 정본 변경 없음.
