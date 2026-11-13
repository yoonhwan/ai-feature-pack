# 설계 1쪽 — ci search yaml 파일 probe panic (aifp-ft-arch-pi#3 · 2026-11-13)

> 발주: aifp-ft-master-pi#10 aifp 4352 · 발주서 `.fable-team/state/team-main/aifp-ft/orders/ci-search-yaml-panic-20261113.md` · Issue byz-agents#8521 · 발견 ops arch#107 BYZ 297089 · 정지 예외 planner#291 aifp 4348 · 하드 룰 12·16
> 카드: `design/aifp/indices/대기/ci-search-yaml-panic.md` · 앞 카드: `design/aifp/indices/진행/ci-search-ascii-md-panic.md`(착지 97528b12 · PR #1087 · 설계 `design/aifp/arch-ci-search-ascii-md-panic-20261113.md`)

## 1. 실측 (2026-11-13 22:2x · 팩 origin/main dab75a5e · 설치본 `~/.local/bin/ci` = origin/main 판과 cmp 같음 · probe-code 0.6.0)

cwd = BYZ `.worktrees/ops-lead`(b4d6a5fa33 · yaml 158 · md 20086 · 전체 48556) · `ci search "consent gate" . --max 3` · `/usr/bin/time -p timeout 25`

| 경로 | rc | real(초) | panic 경고 | 버린 줄 |
|---|---|---|---|---|
| 지금 판(md 만 probe 에서 뺌) | 0 | 8.75 · 팀장 9.0 | 1 · `src/language/yaml.rs:232:53` | 2 |
| yaml 도 뺀 실험 사본(`/tmp` 복사본에서 probe 인자에 `-i '*.yml' -i '*.yaml'` 만 더함 · 팩 손 0) | 0 | 6.77 · 5.74 · 6.69 · 6.83(4회) | 0 | 0 |
| 같은 실험 사본 · 비ASCII 질의 `동의 gate` | 0 | 5.96 | 0 | 0 |
| yaml rg 절만 따로(`rg -F -m1 -e consent -e gate -g '*.yml' -g '*.yaml'`) | 0 | 0.42 | — | 17줄 |

- panic 자리 = `src/language/yaml.rs:232` = probe 의 yaml 청커(입력 단계). 앞 카드의 markdown.rs:240 과 같은 꼴(다중 바이트 파일을 바이트로 자름)이다.
- 원인 1줄: 앞 카드는 probe 에서 md 만 뺐다. yaml 은 여전히 probe 청커로 가서, 다중 바이트가 든 yaml 에서 panic 한다.
- 위험 1줄: yaml 을 빼도 이 리포는 5.7~6.8초다. 7초 끝 기준과 여유가 0.2~1.3초뿐이다. 남은 시간은 probe 가 md·yaml 밖 파일 약 2.8만 개를 BM25 로 읽는 몫(sys 37~43초 · 병렬)이다. 이 카드는 panic 만 고친다. 속도를 더 줄이는 일은 범위 밖이다(아래 §6).

## 2. 길 선택지

| 길 | 내용 | panic | 7초 | 다음 panic 언어 | 잃는 것 |
|---|---|---|---|---|---|
| (가) | yaml 을 md 옆에 따로 하드코딩: probe `-i '*.yml' -i '*.yaml'` 3곳 · yaml rg 절 1개 더 | 0 | 실측 5.7~6.8초 | 또 같은 손질 3~4곳 | 절이 2개(md·yaml)로 늘어 코드 중복 |
| (나) 추천 | probe 에서 뺄 확장자를 목록 1개로 묶음(`md yml yaml`). probe `-i`·rg 절 `-g`·폴백 rg `-g '!…'` 를 모두 이 목록에서 만든다 | 0 | 실측 5.7~6.8초(rg 절에 yaml 더해도 0.4초) | 목록에 낱말 1개 | rg 절 머리·[info] 문구가 바뀌어 앞 카드 시험 5곳(P7·P8·A1·A2·A3 [info] 검사)·머리 검사 기대를 고쳐야 함(삭제 0) |
| (다) | 실행 중 panic 자리(`src/language/<x>.rs`)를 읽어 다음 호출부터 그 언어 자동 제외 | 첫 호출은 그대로 panic | 첫 호출 8.8초 | 손 0 | 상태 파일이 필요함(발주서 «상태 파일 0 이면 비추천») · 언어 이름 ↔ 확장자 대응표가 또 필요 · 비추천 |

- 추천 = (나). 이유: 같은 꼴 panic 이 두 번째다(md → yaml). 목록 1개면 세 번째는 낱말 1개로 끝난다. 실측으로 panic 0 · 7초 안이다. 상태 파일이 없다.

## 3. 설계 ((나) 기준 · 구현 = 나노)

- Y1 목록 1개: `_PROBE_SKIP=(md yml yaml)`(search 갈래 안 · 스크립트 상수). 환경 변수로 열지 않는다(시험·운영 차이 0).
- Y2 probe 호출 2곳(1단계 · OR 재시도)은 목록에서 `-i '*.<x>'` 를 만들어 넘긴다. 지금 `-i '*.md'` 하드코딩 2곳을 지운다.
- Y3 rg 절 = 지금 md rg 절을 넓힌 것 1개. glob = 목록마다 `-g '*.<x>'` · 나머지(`-F` 낱말별 `-e` · `-m 1` · RG_BIN · 상한 min(CI_RG_TIMEOUT,25) · 실패면 절 0 + `[warn] … rg 실패 rc=<N>` · rc 1→0 보정 · OR 재시도 전 확보)는 앞 카드 K2~K4 그대로.
- Y4 panic 폴백 rg 는 목록마다 `-g '!*.<x>'` (앞 카드 C4 를 목록으로 넓힘 · 겹침 0).
- Y5 문구: rg 절 머리 `== markdown·yaml (rg 폴백 · probe panic 회피) ==` · stderr `[info] markdown·yaml 은 rg 로 분리 검색(probe panic 회피)` · rg 실패 경고 `[warn] markdown·yaml rg 실패 rc=<N>`. 머리·문구는 목록에서 만들지 않고 고정 글자로 둔다(시험이 글자로 본다).
- Y6 그대로: panic 판정(C1·K7) · probe 상한 min(CI_TIMEOUT,25)(K6) · 출력 보류(C8) · OR 재시도 조건(D6) · `_cut160` · sym/refs/outline/ast 갈래 · SKILL.md.

## 4. 반례 (동결 · 시험 = 기존 `feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh` 에 덧붙임 · 가짜 probe · 실 probe 0 · sleep 0)

| 번호 | 입력 | 기대 |
|---|---|---|
| B1 | ASCII 질의 + yaml 히트(cfg.yaml 에 다중 바이트 줄) · 가짜 probe 정상 hit | probe 인자에 `-i '*.md' -i '*.yml' -i '*.yaml'` 셋 다(인자 기록) · stdout = probe 출력 → 빈 줄 → `== markdown·yaml (rg 폴백 · probe panic 회피) ==` 절에 cfg.yaml 줄 · panic 경고 0 · rc 0 |
| B2 | 비ASCII 질의 + yaml 히트 | B1 과 같은 꼴 · rc 0 |
| B3 | md + yaml 둘 다 히트(doc.md · cfg.yml) | rg 절 1개 안에 두 파일 · 절 머리 1번 · `--max` 안에서 자름 |
| B4 | yaml·md 없는 fixture · 정상 hit | rg 절 없음 · stdout = probe 출력 그대로 · `[info]` 1줄 · rc 0 |
| B5 | 가짜 probe 정상 nohits rc 1 · 히트 0 | rc 1 · 표지 0 · 절 없음 |
| B6 | 가짜 probe panic rc 134 · fixture 에 cfg.yaml | 앞 카드 C2 폴백 · 폴백 rg 인자에 `-g '!*.md' -g '!*.yml' -g '!*.yaml'` · yaml 줄은 rg 절에만 1번(겹침 0) |
| B7 | 가짜 timeout(PATH 앞 · 실행 대상 구분 · probe 만 즉시 rc 124) | 앞 카드 A7 그대로(stdout 0줄 · rc 124 · 기록된 상한 25) |
| B8 | 확장자 `.YAML`(대문자) · `.yml.bak` | `.YAML` 은 [확인 필요: probe `-i` 대소문자] 나노가 실측해 끝선에 적음 · `.yml.bak` 은 목록 밖(probe 그대로) |
| B9 | 앞 카드 시험 전체 | 검사 175 그대로 PASS(문구 바뀐 검사는 기대 글자만 고침 · 삭제 0) |

- 변이(나노가 잡혀야 함): X1 목록에서 yml 빼기(B1·B3 FAIL) · X2 폴백 rg `!` glob 을 md 만(B6 FAIL) · X3 rg 절 glob 을 md 만(B1 FAIL) · X4 probe 인자를 md 하드코딩으로 되돌림(B1 FAIL).
- 기준판(origin/main ci) FAIL 기대: B1·B2·B3·B6.
- 파일 이름 줄바꿈·탭 = 범위 밖(하드 룰 18).

## 5. 닫는 증거 (발주서 ② 그대로)

1. 재현 명령 `cd ~/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/ops-lead && ci search "consent gate" . --max 3` → panic 경고 0 · 버린 줄 0 · real 7초 안 · rc 정직(0 결과 / 1 0건) · 최종 구현 전체 명령 1회의 real·rc·panic·버린 줄 기록 · 추가 확인은 사유 1줄과 함께 1회까지 · 실행한 결과 전부 보존 · 7초를 넘은 결과를 빼고 통과시키지 않음 · 한 번이라도 7초 넘으면 완료 조건 미충족 · 설계 §1 실험 5.74~6.83초는 실험 사본 값 · 최종 증거 아님.
2. 앞 카드 재현 `cd ~/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops-m175 && ci search "request register" . --max 3` → 앞 카드 끝 기준 그대로.
3. 시험 rc 0 · 기준판 B1·B2·B3·B6 FAIL · 변이 X1~X4 4/4 FAIL · 회귀 3파일 rc 0 · 앞 카드 검사 175 PASS.

## 6. 범위 밖

- probe 바이너리(외부 · upstream yaml.rs·markdown.rs 신고 별건)
- probe 검색 속도 자체(md·yaml 밖 2.8만 파일 BM25 · 6~7초) — 7초 여유가 더 필요하면 새 카드
- 다른 언어 청커의 같은 꼴 panic(나오면 목록 낱말 1개 · 새 카드)
- sym/refs/outline/ast 갈래 · SKILL.md 문구
