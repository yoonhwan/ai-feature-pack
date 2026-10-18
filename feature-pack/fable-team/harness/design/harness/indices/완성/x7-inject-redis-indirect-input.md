# 인덱스: 가드 ㉠(INJECT) 빈틈 X7 계열 — redis-cli 가 명령을 치환·heredoc·stdin·파이프·xargs 로 받는 쓰기 차단 (판정 595 후속 · master#21 쪽지 #67070)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 595 후속(master#21 #67070 「설치 직후 별 카드 · 같은 블록」 · fp595 DA r1 이 «설치 전 열린 blocker» 로 지목)
- 상태: 대기
- 선행: `fp595-inject-post-sink` 랜딩 + 홈 설치(이 카드 base = 그 랜딩 뒤 origin/main)
- 시험 입력: 키트 훅에 PreToolUse JSON 만 넣어 종료코드를 본다(명령 실행 0 · 홈 훅 0)
- 기준값: origin/main 키트 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh` 의 `INJECT_REDIS` 는 «redis-cli 뒤 옵션 다음 첫 토큰 = 쓰기 동사 + 인자» 만 본다 → 아래 Y1~Y8 이 전부 rc=0(arch#22 실측 · 쓰기 동사가 argv 밖에서 들어온다).
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(오빠 절대지침 「임의 레디스 쓰기 금지」 장치의 빈틈 닫기) + C(키트 = 전 머신 설치본). 핵심 한 줄: redis-cli 가 쓰기 명령을 argv 밖(치환·heredoc·stdin·파이프·xargs)에서 받는 꼴은 막히고, GET 류 읽기·출력 파이프·글자 인용은 그대로 통과한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
전역 PreToolUse(Bash) 훅 `block-destructive.sh` 의 INJECT 블록(R63b · `# INJECT-BEGIN`~`END`)은 검사 사본 `CHK`(판정기가 글 싱크를 뺀 글자에서 검색·게시 구간 제거 + 따옴표 제거)에 `INJECT_PATTERN` 을 grep 한다. `INJECT_REDIS` 는 redis-cli 뒤 옵션들 다음 «첫 토큰이 쓰기 동사이고 인자가 1개 이상» 일 때만 맞는다. 그래서 동사가 치환 `$(…)`·백틱·heredoc(`<<`)·here-string(`<<<`)·파일 stdin(`<`)·파이프(`… | redis-cli`)·`xargs` 로 들어오면 전부 통과한다(fp595 DA r1 의 X7 = 그 중 치환 꼴). 이 카드는 같은 블록의 `INJECT_PATTERN` 에 대안 4개를 한 줄로 더한다. 판정기·PATTERN·STAGE 는 손대지 않는다.

## 사전검증
- 소환: 아니오 — arch#22 프로토타입 실측(아래)으로 설계 확정.
- 구현 DA: ★예 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료★ — 전 좌석 Bash 훅. 질문 고정: Q1 Y 행 전부 2 · Q2 Q 행 + 기존 대조표 통과 행 전부 0 · Q3 기존 시험 세 개 회귀 0 · Q4 bash 3.2 호환(정규식 안 백틱·`$(` 이스케이프 포함).

## 설계 (닫힌 목록)
`INJECT_PATTERN="$INJECT_REDIS|/dev/bubble-replay"` 바로 다음 줄에 대안 4개 추가(ERE · `grep -qiE` · 따옴표 제거 뒤 `CHK` 기준):
1. 파이프 수신: `[|][[:space:]]*([^|;&]*[[:space:]])?redis-cli` — redis-cli(또는 `docker exec -i c redis-cli`)가 파이프 «뒤». 출력 파이프(`redis-cli … | head`)는 안 맞는다.
2. 입력 리다이렉트: `redis-cli[^;&|]*<` — 같은 구간의 `<`·`<<`·`<<<`(`2>`·`>` 는 안 맞는다).
3. xargs 공급: `xargs[^;&|]*redis-cli`.
4. 동사 자리 치환: `INJECT_REDIS` 와 같은 옵션 접두 + `[[:space:]]+([$][(]|\`)` — 옵션 다음 첫 토큰이 `$(`·백틱. (`redis-cli GET $(cat key)` 처럼 동사 뒤 치환은 안 맞는다.)
- ★함정 2(arch 실측)★: 큰따옴표 안 ERE 에서 `\|` 는 macOS grep 에서 빈 대안처럼 굴어 모든 명령이 막힌다 → `[|]` 로 쓴다. 백틱은 `` \` `` 로 이스케이프(안 하면 대입 순간 명령 치환).
- 참고 구현(arch 프로토타입 · 1줄 추가): `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r22/x7/proto-hook.sh` 46행 · 재현 `python3 /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r22/x7/probe_x7.py <훅>`.

## 조사 근거 (arch#22 실측 · origin/main 키트 · 2026-10-09)
- 키트: Y 8행 전부 rc=0(BAD 8) · Q 4행 rc=0.
- 프로토(키트 + 1줄): Y 8 = 2 · Q 4 = 0(BAD 0) · `tests/harness/test_block_destructive_inject.sh` rc=0 · `tests/harness/test_block_destructive.sh` rc=0(`BD_HOOK=` 지정).
- 첫 시도에서 `\|`·이스케이프 없는 백틱으로 Q·기존 시험이 전부 깨졌다(위 함정 2) — 변이 대조로 남긴다.

## 구현 범위 (닫힌 목록)
1. 키트 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh` INJECT 블록에 위 1줄(+ 주석 1줄). 판정기 `scripts/harness-install/fable-team/templates/hooks/block-destructive-judge.py`·PATTERN·STAGE 변경 0.
2. 시험 `tests/harness/test_block_destructive_inject_post.sh`(fp595 가 만든 파일 · 200줄 넘으면 새 파일 `tests/harness/test_block_destructive_inject_x7.sh`)에 Y·Q 행 + 변이 M5(추가 줄 제거 → Y1·Y6 FAIL) · M6(`[|]` 를 `\|` 로 바꾼 복사본 → Q 행 FAIL).
3. 대조표 `design/teams/harness/evidence/r63b-block-destructive-inject/TABLE.md` 에 Y·Q 행 추가.
커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.claude/hooks/` 쓰기·settings.json 수정(설치 = master).

## 대조표 추가 행 (1행 = 1검사 · 명령 전문은 probe_x7.py · 표 안 임시 경로는 예시 글자)
| # | 명령 | 기대 |
|---|---|---|
| Y1 | `redis-cli $(cat <<'EOF'`⏎`SET k v`⏎`EOF`⏎`)` (= X7) | 2 |
| Y2 | ``redis-cli `printf 'SET k v'` `` | 2 |
| Y3 | `redis-cli <<'EOF'`⏎`SET k v`⏎`EOF` | 2 |
| Y4 | `redis-cli <<< 'SET k v'` | 2 |
| Y5 | `redis-cli --pipe <` data.txt | 2 |
| Y6 | `printf 'SET k v' \| redis-cli` | 2 |
| Y7 | `echo 'HSET k f v' \| redis-cli -p 6380` | 2 |
| Y8 | `echo k \| xargs redis-cli SET` | 2 |
| Q1 | `redis-cli GET $(cat key.txt)` | 0 |
| Q2 | `redis-cli --scan --pattern 'x:*' \| head` | 0 |
| Q3 | `grep -n 'redis-cli <<' docs/a.md` | 0 |
| Q4 | `echo 'printf SET \| redis-cli 는 금지'` | 0 |

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · 기존 `tests/harness/test_block_destructive.sh`·`tests/harness/test_block_destructive_inject.sh` rc=0 · `/bin/bash -n` 훅 · 구현 DA 판정문 APPROVE.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_block_destructive_inject_post.sh rc=0 · 이슈: 0` (+ 대조표 경로).
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다.
- ★랜딩 뒤 master 집행(카드 밖)★: 홈 백업 → 키트 훅 홈 cp+cmp → `/bin/bash` 홈 설치본에 Y1·Y6·Q2·P6 JSON 재생 → 첫 도구 호출 실측 + 다른 좌석 1곳 → 오탐 1건이면 즉시 원복 + 원장 기록.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 483ba4ec67869e84a3a9a88b344090244ae1e158 (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#22 · 판정 595 후속 · master#21 #67070). spawn = fp595 홈 설치 직후.
- 정본 영향 없음: 하네스 훅 템플릿·시험·대조표만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 05:47 — 대기→진행 · 좌석 byz-harness-nano-x7-inject-redis-indirect-input#0

## 결과 (나노 RESULT #67093 + r1·r2 반송 · arch#22 서명 · master#21 옮김 2026-10-09)
세트: 90c9c7db39b357418c29e41dcd88b82132c3bfc5 · 시험: bash tests/harness/test_block_destructive_inject_post.sh rc=0 · 이슈: 0
정본 영향 없음: 하네스 훅 템플릿·시험·대조표만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 06:14 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§101
