# 인덱스: R63 발주 템플릿에 «측정 조작 금지» 1줄 고정 — ft-role-spawn BODY(전 역할) + ft-nano-spawn BODY (원장 R63 · 오빠 절대지침 · master#19 쪽지 #66467 · planner 쪽지 #66455)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R63(우선 높음 · v423c 반송서 뒤 최우선)
- 상태: 대기
- 선행: 없음 (BOOT 20 조항 = master#19 추가 완료)
- 시험 입력: spawn 스크립트 정적 검사 + `ft-role-spawn.sh --dry-run` 의 BODY 줄 — tmux·mbox 송신·네트워크 0
- 기준값: origin/main 78f80f82fe 에서 `scripts/fable-team-bin/ft-role-spawn.sh` BODY(57·59·61행)와 `scripts/fable-team-bin/ft-nano-spawn.sh` BODY(225행)에 «임의 Redis 쓰기·말풍선 DOM 주입 금지» 문장 0 — 후계·나노 좌석이 첫 발주문에서 그 규칙을 못 본다(BOOT 20 은 읽어야만 보인다). 두 파일 모두 키트 사본(`scripts/harness-install/fable-team/bin/`)과 cmp 동일.
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터·오빠 요청 — 오빠 절대지침 「임의 레디스랑 말풍선 dom 밀어넣기를 절대 하지 말라」 를 «읽지 않아도 보이는» 첫 발주문에 건다). 핵심 한 줄: 모든 새 좌석의 첫 발주문에 측정 조작 금지 1줄이 있다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오빠 절대지침(10-09): 시험·측정에서 임의 Redis 쓰기(redis-cli SET·HSET·XADD·PUBLISH 등 제품 키 직접 주입)와 말풍선 DOM 주입(재생 하네스·/dev/bubble-replay·appendChild)으로 만든 결과는 증거가 아니다. 실제로 #887(재생 페이지 측정)·#889(재생 하네스 유입)·#996(redis-cli PUBLISH 로 room SSE 흉내) 판정이 무효 후보가 됐다. BOOT 20 조항과 전역 하드 룰 11 은 이미 있다. 그러나 BOOT 는 좌석이 읽어야 보이고, 고스트 서제스천(BOOT 17)·크론(BOOT 16) 선례처럼 첫 발주문 BODY 에 1줄 박아야 «안 읽어도» 보인다. 이 카드는 그 1줄을 두 spawn 스크립트의 BODY 에 넣고 시험으로 고정한다. 가드 훅(차단)은 별도 조사(`design/harness/SURVEY-r63-injection-guard-hook-20261009.md` · 집행 0)이고 이 카드 밖.

## 사전검증
- 소환: 아니오
- 면제 사유: 발주문 고정 문구 1줄 추가(BOOT 16·17 선례와 같은 꼴) · 동작 변경 0 · 문구는 BOOT 20 의 요약 — 구현 DA 없음 · arch 재현으로 닫는다 — arch 서명 byz-harness-arch-claude#20

## 조사 근거 (origin/main 78f80f82fe · arch#20)
- `scripts/fable-team-bin/ft-role-spawn.sh`(107줄): 57행 BODY 기본 · 59행 master|arch 크론 문장(BOOT 16) · 61행 전 역할 고스트 문장(BOOT 17) · 64행 `--dry-run` 이 `BODY …` 를 출력(관측점).
- `scripts/fable-team-bin/ft-nano-spawn.sh`(230줄 · 기존 200줄 초과): 225행 `^BODY=` 한 줄(press 금지·Serena 읽기만·Bash 실행만 문장 포함) · `--dry-run` 은 BODY 를 출력하지 않는다(166행에서 먼저 종료) → 정적 grep 이 관측점.
- 시험: `tests/harness/test_role_spawn_name.sh`(83줄 · 74-81행 R21 고스트 문장 검사 꼴) · `tests/harness/test_nano_spawn_body_press.sh`(38줄 · `^BODY=` 줄 정확히 1개 검사 · 음성 대조 꼴).

## 구현 범위 (닫힌 목록)
고정 문구(글자 그대로 · 백틱 0):
`★측정 조작 금지(오빠 절대지침) — 임의 Redis 쓰기(redis-cli SET·HSET·XADD·PUBLISH 등 제품 키 직접 주입)·말풍선 DOM 주입(재생 하네스·/dev/bubble-replay·appendChild)으로 만든 결과는 증거 아님 · 측정은 trusted 클릭 + 기존 e2e 러너의 실제 음성 경로만 · 격리 Redis 픽스처 시험은 별개 · 이미 썼으면 [HIL] 로 올림 (BOOT 20)★`
1. `scripts/fable-team-bin/ft-role-spawn.sh`: 61행 바로 뒤에 `BODY="$BODY <고정 문구>"` 1줄(전 역할 · case 0).
2. `scripts/fable-team-bin/ft-nano-spawn.sh`: 225행 `^BODY=` 줄 «안»에 press 금지 문장 바로 뒤로 고정 문구 삽입(새 줄 0 — `^BODY=` 1개 유지 · 줄 수 230 유지).
3. 키트 사본 2개(`scripts/harness-install/fable-team/bin/ft-role-spawn.sh` · `…/ft-nano-spawn.sh`)를 추적본과 cmp 동일하게 복사.
4. `tests/harness/test_role_spawn_name.sh`: R63 블록 — 전 역할(master·arch·tester·checker·pm·da 중 시험이 이미 쓰는 역할 목록 그대로) `--dry-run` BODY 줄에 「측정 조작 금지」·「/dev/bubble-replay」·「BOOT 20」 셋 다 포함. 200줄 이하.
5. `tests/harness/test_nano_spawn_body_press.sh`: `check_body` 에 같은 셋 포함 검사 + 음성 대조 1줄(그 문구를 sed 로 지운 복사본 → FAIL). 200줄 이하.
6. 기존 시험 PASS: 위 2개 · `tests/harness/test_kit_bin_sync.sh` · `bash -n` 4파일.
커밋은 자기 브랜치, **push 금지**. **금지**: 라이브 FT_BIN(`v6-realtime-live/.fable-team/bin`) 쓰기 · BOOT·전역 CLAUDE.md 수정(이미 됨) · 가드 훅 작업(조사 카드 몫).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · 키트 cmp 동일.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_role_spawn_name.sh rc=0 · 이슈: 0` (+ `bash tests/harness/test_nano_spawn_body_press.sh rc=0` 은 결과 보고에 함께).
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN 2파일에 설치 복사(cp+cmp) — 다음 spawn 부터 적용.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: f170944ff2d057d49c0582201474f90482faef81 (spawn 2026-10-09)
- 2026-10-09 01:2x — 대기/ 생성 (byz-harness-arch-claude#20 · 원장 R63 · master#19 쪽지 #66467).
- 정본 영향 없음: 하네스 spawn 템플릿·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 01:07 — 대기→진행 · 좌석 byz-harness-nano-r63-spawn-body-no-injection#0

## 결과 (나노 RESULT · master#20 옮김 2026-10-09)
세트: 0bc7d3b6a94b0515a327e41a84b7cb5cdddde9af · 시험: bash tests/harness/test_role_spawn_name.sh rc=0 · 이슈: 0
정본 영향 없음: 하네스 spawn 템플릿·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 01:19 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§91
