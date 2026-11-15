# 인덱스: ci-test-base-sha-pin — 끝: ci search 시험(test_ci_search_nonascii_panic.sh)의 «기준판 대조» 블록이 고정한 기준판 1개와 견준다 · main 에서 시험 전체 rc 0 · 기능 검사 글자 0 바뀜
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8655 (byz-agents · 팀장 aifp-ft-master-pi#21 등록 BYZ 311724) — 팀장 판단·발주 aifp 5720 · 발견 나노 aifp 5681 (a) · DA 311592 «기준판 고정은 별도 회귀 fixture 보수» · arch 실측 aifp 5716
- 제안서: 없음 — 시험 fixture 보수(제품 코드 0) · 설계는 이 카드 «계약»·«반례 표» 가 전부
- 근거: 실측 2026-11-16 05:08~05:12(aifp-ft-arch-pi#20 · 루트 checkout main · 읽기만) — 아래 «실측» 절
- 원인 1줄: 블록이 기준판을 `git rev-parse origin/main` 으로 잡는다(시험 파일 659줄) · 고침이 main 에 착지하면 기준판이 고친 판이 되어 «기준판 … 통과 — FAIL 이어야» 가 난다
- 앞 카드: design/aifp/indices/진행/ci-search-test-files.md(착지 cf0d4052 · PR #1332 · 완료 조건 1 = 이 결함 때문에 «알려진 한계» 로 닫음) · 완성/ci-search-yaml-panic.md · ci-search-ascii-md-panic · ci-search-nonascii-panic
- 상태: 대기
- 설치: 없음 — 시험 파일과 시험 fixture 만 바뀐다(라이브 사본·심링크 대상 ci 변경 0)
- 선행: 없음(팩 origin/main 017fe2cf · ci-search-test-files 착지 cf0d4052 포함)
- 시험 입력: 시험이 이미 쓰는 것 그대로(가짜 probe · RG_BIN 대역 · 임시 폴더 · HOME·TMPDIR 격리) + 새 fixture 파일 1개(기준판 ci 사본) · sleep 0 · 네트워크 0 · 실 probe 0 · git 호출 0(기준판 블록)
- 기준값: 지금 main 에서 `bash feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh` = rc 1 · 294 검사 · 실패 16 · 11초 → 목표 = rc 0 · 실패 0 · 마지막 줄 `PASS`
- 규칙: 없음
- 규칙 상세: 하드 룰 22(시험 1개 70초) · 하드 룰 19(우리 도구가 만드는 파일은 일반 파일)
- 대상: 팩 feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh(«기준판 대조» 블록 머리 5줄 안팎) · 새 fixture feature-pack/code-intel/tests/fixtures/ci-base-97528b12 · 새 시험 feature-pack/code-intel/tests/test_ci_base_pin.sh
- 정본 영향 없음: 시험 파일·시험 fixture 만 · 제품 코드(skill/scripts/ci)·스킬 문서·정본 문서 변경 0
- 크기: 시험 1파일 5줄 안팎 · fixture 1파일(454줄 사본) · 새 시험 1파일 · PR 1개
- 배정: 대기(DA · 2026-11-16T05:12)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
6 — 하네스 운영 정리. 하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: A(모니터·요청 — 코드 탐색 도구 ci 의 회귀 시험이 main 에서 rc 0 이라, 다음 ci 고침의 «새 실패» 를 rc 로 가릴 수 있다). 이 카드의 증거 = 착지 sha + main 에서 시험 전체 rc 0 원문.

## 배경 (한 단락)
이 시험은 «고치기 전 판(기준판)에서는 지정 검사가 FAIL 한다» 를 함께 확인한다. 그런데 기준판을 origin/main 에서 꺼낸다. 카드가 착지하면 origin/main 이 고친 판이 되므로, 그 뒤로는 블록이 늘 실패한다. 앞 세 카드 몫 10줄이 그렇게 남아 있었고, ci-search-test-files 가 착지하자 6줄이 더 늘어 지금 16줄이다. 기능 검사는 실패 0 인데 시험 전체 rc 는 1 이다. 그래서 다음 ci 고침에서 «새 실패» 를 rc 로 가릴 수 없다. 기준판을 고정하면 끝난다.

## 실측 (2026-11-16 · 루트 checkout main · 시험 1회 11초 안팎)
| # | 한 것 | 결과 |
|---|---|---|
| ① | 지금 main 에서 시험 그대로 | rc 1 · `== 요약: 294 검사 · 실패 16 ==` · `기준판 = c419684f…`(그때 origin/main) · 16줄 전부 `FAIL 기준판 <검사> 통과 — FAIL 이어야`(P7·P8·A1·A2·A3·A9·B1·B2·B3·B6·C1·C2·C4·C6·C7·C8) · 그 밖 FAIL 0 |
| ② | 시험 대상 ci 를 14ef74ac 의 부모(8b22d498) 판으로 바꿔 같은 시험(`CI_UNDER_TEST=`) | 블록 앞 기능 검사에서 FAIL 한 검사 이름 = P7·P8·A1·A2·A3·A9·B1·B2·B3·B6·C1·C2·C4·C6·C7·C8 + C10a·C11·C12 · 나머지 P·A4~A8·B4·B5·B7·B8 은 통과(ok 227줄) |
| ③ | ②의 ci blob | `git rev-parse 97528b12:feature-pack/code-intel/skill/scripts/ci` = `8b22d498:…` = cff07f3add33f4fee436223d87daef95459a74ff(같은 blob · 454줄 · 22938바이트 · sha256 f2eb9e1fba04a8773340b9b263e38ec9fb3194387bebe13b90c5e96931a17dbf) |

②가 말하는 것: 블록의 기대 목록(통과 목록 · FAIL 목록 · C 목록)은 지금 글자 그대로 97528b12 판 ci 한 개에 모두 맞는다. 기준판을 여러 개로 나눌 필요가 없다. C10a·C11·C12 는 블록 목록에 없으니 그대로 둔다.

## 판정 (arch · 이유 1줄씩)
- 기준판 = 97528b12 판 ci 1개. 이유: 실측 ②에서 블록의 기대 목록 전부가 그 판에 맞는다.
- 꺼내는 길 = git 이 아니라 fixture 파일. 이유: 나노·arch·DA 는 `git archive` 사본에서 시험을 돌린다. 사본에는 .git 이 없어 `git show <sha>` 가 안 된다(DA 311592 는 이 때문에 임시 git 저장소를 따로 만들었다). 얕은 clone 에서도 그 sha 가 없을 수 있다.
- fixture 가 바뀌지 않았음은 sha256 상수로 확인한다. 이유: 기준판이 슬쩍 바뀌면 블록이 다시 뜻을 잃는다.
- 네 발주와 다른 곳 1: 발주는 «기준판 sha 를 착지 전 sha 로 고정» 이다. 이 카드는 그 sha 의 ci 를 파일로 둔다(sha 는 파일 이름과 주석에 남는다).

## 계약
- B1 기준판 = `feature-pack/code-intel/tests/fixtures/ci-base-97528b12` 1파일 · 내용 = `git show 97528b12:feature-pack/code-intel/skill/scripts/ci` 와 바이트 같음 · mode 100644 일반 파일(시험이 `bash <파일>` 꼴로 부르거나 임시 폴더에 복사해 쓴다)
- B2 블록은 git 을 부르지 않는다 · origin/main 을 읽지 않는다 · 그 줄의 `기준판 = ` 출력은 `기준판 = fixtures/ci-base-97528b12` 로 바뀐다
- B3 블록 시작에서 fixture 의 sha256 을 상수 f2eb9e1f…17dbf 와 견준다 · 다르면 `FAIL 기준판 fixture sha256 다름` 1줄 · 블록의 `bl` 호출 0
- B4 fixture 가 없으면 `FAIL 기준판 fixture 없음` 1줄(조용히 건너뛰지 않는다) · rc 1
- B5 그대로: `bl` 함수 몸 · 통과 목록·FAIL 목록·C 목록의 글자 · 블록 앞 기능 검사(P·A·B·C) 전부 · 변이 절 전부 · `CI_UNDER_TEST` 뜻 · 요약 줄 꼴
- B6 블록 머리 주석 1줄 = 새 검사를 더할 때 기준판 기대(pass·fail)는 이 고정 판에 대해 적는다 · 고정 판을 바꾸려면 목록 전부를 다시 잰다

## 반례 표
| # | 입력 | 기대 | 지금(기준판) |
|---|---|---|---|
| D1 | main checkout 에서 시험 그대로 | rc 0 · `== 요약: 294 검사 · 실패 0 ==` 뒤 `PASS` · `기준판 = fixtures/ci-base-97528b12` | rc 1 · 실패 16 |
| D2 | `git archive` 사본(.git 없음)에서 시험 | D1 과 같음 | `FAIL 기준판 추출 실패` |
| D3 | origin/main 이 다른 커밋을 가리키는 clone | D1 과 같음(블록이 origin/main 을 읽지 않는다) | 가리키는 판에 따라 달라짐 |
| D4 | fixture 파일을 지운 사본 | rc 1 · `FAIL 기준판 fixture 없음` 1줄 · 기능 검사 결과는 그대로 | — |
| D5 | fixture 끝에 1바이트 더한 사본 | rc 1 · `FAIL 기준판 fixture sha256 다름` 1줄 · `bl` 줄 0 | — |
| D6 | fixture 를 지금 판 ci 로 바꾸고 sha256 상수도 맞춘 사본(변이) | rc 1 · `FAIL 기준판 <검사> 통과 — FAIL 이어야` 16줄(= 블록이 살아 있다) | — |
| D7 | `CI_UNDER_TEST=<97528b12 판 ci>` | 기능 검사 FAIL = 실측 ②의 이름 그대로 · 블록은 전부 ok(대상 판과 무관) | 블록도 흔들림 |
| D8 | 착지 커밋의 시험 파일 diff | 바뀐 줄이 «기준판 대조» 블록 머리(659~663줄 근처)와 주석뿐 · 기능 검사·목록·변이 절 diff 0 | — |

범위 밖 입력(하드 룰 18·19): fixture 를 폴더·심링크·권한 000 으로 바꾼 것.

## 변이 (각각 지정 반례가 FAIL 해야 한다)
| # | 변이 | 잡는 반례 |
|---|---|---|
| Y1 | 블록이 다시 origin/main 에서 꺼냄 | D2 · D3 |
| Y2 | sha256 확인 빼기 | D5 |
| Y3 | fixture 없으면 블록 건너뛰기(ok 도 FAIL 도 없음) | D4 |

## 구현 범위 (나노 1 · 팩 base origin/main)
1. feature-pack/code-intel/tests/fixtures/ci-base-97528b12 — `git show 97528b12:feature-pack/code-intel/skill/scripts/ci` 그대로(B1)
2. feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh — «기준판 대조» 블록 머리만(B2~B4·B6) · 다른 줄 손 0
3. 새 시험 feature-pack/code-intel/tests/test_ci_base_pin.sh — D2·D4·D5·D6 을 임시 사본에서 1회씩(각 11초 안팎 · 합 70초 안 · 넘으면 파일을 둘로 쪼갠다) · 변이 Y1~Y3 · 재진입 가드 · timeout 70 · 100644
4. 회귀: feature-pack/code-intel/tests/ 의 나머지 5파일 rc0

## 범위 밖
- 제품 코드 feature-pack/code-intel/skill/scripts/ci
- 기능 검사·변이 절의 글자 · C10a·C11·C12 를 블록 목록에 더하는 일
- 다른 시험 파일의 기준판 대조(같은 꼴이 있으면 새 카드)
- ci-search-test-files 카드 다시 열기(그 카드는 «알려진 한계» 로 닫는다 · 이 카드 착지 뒤 rc 0 원문은 이 카드에 적는다)

## 완료 조건
1. [ ] 나노: D1 원문 = 시험 전체 rc 0 · 검사 수 · 실패 0 · 걸린 초
2. [ ] 나노: 새 시험 test_ci_base_pin.sh rc0 · 걸린 초 · D2·D4·D5·D6 줄
3. [ ] 나노: 변이 Y1~Y3 각각 지정 반례 FAIL(3/3)
4. [ ] 나노: 회귀 5파일 rc0 · 새 파일 2개 100644 · fixture sha256 1줄
5. [ ] arch: 착지 커밋에서 D8 = 시험 파일 diff 가 블록 머리·주석뿐 · fixture blob = cff07f3add33f4fee436223d87daef95459a74ff
6. [ ] 팀장: PR 착지 sha
7. [ ] arch: 착지 뒤 루트 checkout main 에서 시험 1회 = rc 0 · `PASS` 원문 · 걸린 초 · D7 1회
- 나노 끝선(5줄 이내): 바꾼 줄 범위 · 시험 결과 줄·초 · 변이 FAIL 목록 · 설계와 다르게 한 점(없으면 «없음»)

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| B1 fixture 1파일 | D1 · D8 · 조건 5 |
| B2 git·origin/main 0 | D2 · D3 · Y1 |
| B3 sha256 확인 | D5 · Y2 |
| B4 없음 = FAIL 1줄 | D4 · Y3 |
| B5 그대로 | D6 · D7 · D8 |
| B6 주석 | D8 |

## 상태
- base_sha: 017fe2cfc39ff3a3db339c8febbb14393f91d228
- 2026-11-16 05:12 · 대기 — aifp-ft-arch-pi#20 초안(팀장 aifp 5720 · 실측 ①~③) · 다음 = 팀장 PR → DA 설계 → 나노 1석
