# 인덱스: r1339-card-assign-pointer-stale-folder — 끝: 배정 감시(ft_card_assign_watch.py orders())가 발주서 «- 카드:» 경로 토큰이 카드 경로 집합에 없을 때, 같은 팀 카드 칸에 «같은 파일 이름» 카드가 있으면 칸 이름만 낡은 포인터로 본다 — 열린 칸(대기·진행)에 있으면 연결(행 0) · 닫힌 칸(완성·아카이브)에 있으면 사유 «닫힌 카드»(«카드 없는 발주» 수에서 빼고 머리에 «닫힌 카드 발주 N» 칸) · 어디에도 없으면 지금처럼 «없는 경로» · 우선 낮음
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8374 (SecondWindStudio/byz-agents · harness#203 발급)
- 이식: 원본 = harness#203 전문 /tmp/mbox/20261111T214546-byz-harness-master-pi#203-to-aifp-ft-master-pi#5-r1339-card-assign-pointer-stale-folder.md(BYZ origin/main 4ee8346c38 design/harness/indices 에 같은 이름 파일 0) → aifp design/aifp/indices/대기/ · 바꾼 것 = ledger·대상·시험 경로(legacy/1.x 이동 625fbdfc) · 원인 줄 번호 · lint 필수 절 3개(배경·구현 범위·완료 조건)를 본문 내용으로 채움 · 나머지 원문 그대로 · 1.x 그대로 수정(harness 답 · 선례 r1699 PR #941) (aifp #3972 · #3974)
- 지시: master#153 #230844(«후속 후보 = 카드 1장 대기 칸 · 우선 낮음 · r1329 판정문 뒤»)
- 근거: r1329 착지 뒤 측정(arch#213 · design/harness/indices/진행/r1329-card-assign-pointer-path-token.md:88) — 작업트리 164곳 발주서 카드 줄 900 중 «없는 경로» 860 = 다른 칸으로 옮겨진 카드 826 + 어디에도 없음 34 · 예 graphics inbox/tester/03-g1087-credits-sub2-impl-capture.md:16 → 포인터 «진행/» · 카드는 «완성/»
- 원인 1줄: feature-pack/fable-team/legacy/1.x/harness/bin/ft_card_assign_watch.py:522(origin/main · 작성 때 live 1.1.255 :512) 판정이 «토큰 ∈ allpaths(대기|진행|완성 전체 경로)» 하나뿐 — 카드가 칸을 옮기면(ft-index-move) 발주서 포인터의 칸 이름이 그대로 낡아 «없는 경로» 로 센다 · 발주서를 따라 고치는 도구 없음
- 끝: 팩 가지 1 · 시험 rc0 · 기준판 FAIL · 변이 FAIL · 착지 · 설치 cmp0 · 실사건 = 설치 뒤 status 머리 «카드 없는 발주 N» 이 설치 전보다 줄고 «닫힌 카드 발주 M» 칸 원문 1줄(같은 판본 비교)
- 묶음 판정: «규칙 한 줄로 끝나나» = 아니오 — 826줄을 손으로 고치는 것은 13팀 발주 작성자 몫이고 카드 이동마다 다시 낡는다 · 읽는 쪽 1곳(:512)과 머리 칸 1개
- 겹침 대조: r1329(완성 예정 · 같은 함수 · 포인터 «토큰 추출» · 이 카드는 «추출한 토큰의 칸 이름 낡음» = 다른 끝 줄) · r1287(완성 · 단위 대체값) · r1325(같은 파일 · 다른 함수)
- 제안서: 없음 — 판정 1곳 · 되돌림 = revert 1커밋
- 상태: 완성
- 착지: 0e8997f92502e3bbefd5c8e42c4c56bd85451180(팩 main · PR #949)
- 설치: 있음 — /Users/yoonhwan/.claude/fable-team/live/<LIVE_BIN 최신 sort -V>/bin/ft_card_assign_watch.py ← 팩 harness/bin 판 cmp0(kit 같은 판)
- 선행: 없음(팩 origin/main · r1329 착지 85e198b6 위)
- 시험 입력: r1329 시험 틀(임시 리포 · TEAMS.md 1행 · 카드 폴더 · 발주 폴더 · 2시간 지난 생성 커밋) · 발주서 5벌(아래 S1~S5) · 네트워크 0 · 자기 재호출 0 · ulimit -u 2000 + timeout 70 · cwd = /
- 기준값: 작업트리 측정 «없는 경로» 860 중 칸만 다름 826(r1329 카드 :88)
- 재실측(aifp-ft-arch-pi#0 · 2026-11-11 · 읽기만): origin/main feature-pack/fable-team/legacy/1.x/harness/bin/ft_card_assign_watch.py:522 판정 = «ptr not in allpaths → 없는 경로» 그대로 · «닫힌 카드» 갈래·머리 칸 0 · :519 r1329 토큰 추출은 있음 · 숫자(826/860) 재측정 = BYZ 루트에서 master(aifp 루트 status = «배정 감시 판정 불가 · 카드 루트 표 없음»)
- 규칙: 없음 — 배정 감시 읽기 결함
- 대상: 팩 feature-pack/fable-team/legacy/1.x/harness/bin/ft_card_assign_watch.py(orders() 판정 · 머리 칸) · feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin/ft_card_assign_watch.py(같은 판) · 시험 feature-pack/fable-team/legacy/1.x/harness/tests/test_card_assign_pointer_stale_folder_r1339.sh(신설 · 100644)
- 정본 영향 없음: 하네스 배정 감시 판정 — 제품 정본 0
- 2026-11-11 20:19 — arch 인수 보류 1 보정(닫힌 카드 = 화면 줄만) · 세트: cea1c5d933972959605e87d5fe1ba9f8f4df6ddb · 시험: bash tests/test_card_assign_pointer_stale_folder_r1339.sh (17 passed — S6 닫힌 카드만 = rc0 · tick 0통 · K 0 · 변이 4/4) rc=0 2초 · 회귀 test_card_assign* 14종 FAIL 수 기준판 0241f6f4 와 동일 · 바꾼 것 = closed_pointer 술어로 rc·tick 경보·stamps K 에서 제외(화면 줄·머리 칸 유지)
- 2026-11-11 20:05 — 나노 구현 완료(A1~A5) · 세트: d51b47d852a400135d1016fda58e5a179b8c9957 · 시험: bash tests/test_card_assign_pointer_stale_folder_r1339.sh (13 passed — S1~S5 · 기준판 0241f6f4 고정 sha 에서 S1·S2·S3 «없는 경로» 재현 · 변이 3/3) rc=0 5초(새 1초 · 기준판 0초 · 변이 2초) · 회귀 test_card_assign_pointer_path_token_r1329.sh 13P0F 2초 · test_card_assign* 14종 FAIL 수 기준판 0241f6f4 와 동일(기존 2F·5F·4F 그대로) · 이슈: #8374
- 배정: 대기(석 · 2026-11-02T20:21:40)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 1(팀 멈춤을 사람보다 기계가 먼저 본다 — 배정 감시 경보가 진짜 미연결만 센다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 cmp0 + 실사건(머리 원문).

## 배경 (한 단락)
배정 감시는 발주서 «- 카드:» 경로가 카드 경로 집합에 있는지만 본다. 카드가 칸을 옮기면(ft-index-move) 발주서 경로의 칸 이름은 그대로 남는다. 그래서 옮겨진 카드도 «없는 경로» 로 세고, «카드 없는 발주» 경보가 진짜 미연결보다 크게 나온다(11-02 측정 «없는 경로» 860 중 칸만 다름 826). 이 카드는 같은 팀 카드 칸에서 같은 파일 이름을 찾아 낡은 포인터를 가른다.

## 계약
- A1 토큰 ∈ allpaths = 지금 그대로(연결)
- A2 토큰 ∉ allpaths ∧ 같은 팀 카드 칸(대기·진행)에 같은 파일 이름 = 연결(행 0)
- A3 토큰 ∉ allpaths ∧ 같은 팀 닫힌 칸(완성·아카이브/*)에만 같은 파일 이름 = 사유 «닫힌 카드» · «카드 없는 발주» 수 제외 · 머리 «닫힌 카드 발주 N»
- A4 어디에도 없음 = «없는 경로» 그대로 · 빈 값 = «포인터 없음» 그대로 · 긴급 판정(«카드 긴급 줄 없음»)은 A2 로 찾은 실제 경로로 대조
- A5 같은 파일 이름이 열린 칸 둘 이상 = 연결(어느 쪽이든 열린 카드) · 다른 팀 칸의 같은 이름은 보지 않는다

## 반례 집합
- S1 포인터 «진행/x.md» · 카드 대기/x.md → 행 0(기준판 «없는 경로»)
- S2 포인터 «진행/x.md» · 카드 완성/x.md → «닫힌 카드» 1행 · 머리 «닫힌 카드 발주 1» · «카드 없는 발주» 0
- S3 포인터 «진행/x.md» · 카드 아카이브/2026-10/x.md → S2 와 같음
- S4 포인터 «진행/y.md» · 어디에도 없음 → «없는 경로» 그대로
- S5 포인터 «진행/x.md» · 다른 팀 대기/x.md 만 → «없는 경로»(A5)
- 변이 1: A2 제거 → S1 FAIL · 변이 2: A3 를 연결로 → S2 FAIL · 변이 3: 팀 제한 제거 → S5 FAIL

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| A1 토큰 ∈ allpaths = 그대로 연결 | 회귀 r1329 시험 |
| A2 열린 칸 같은 파일 이름 = 연결 | S1 · 변이 1 |
| A3 닫힌 칸에만 = «닫힌 카드» | S2 · S3 · 변이 2 |
| A4 어디에도 없음 = «없는 경로» 그대로 | S4 |
| A5 다른 팀 칸은 보지 않음 | S5 · 변이 3 |

## 구현 범위 (나노 1 · 팩 base origin/main)
1. feature-pack/fable-team/legacy/1.x/harness/bin/ft_card_assign_watch.py orders()(:502~522) A1~A5 + 머리 «닫힌 카드 발주 N» 칸(:536 머리 줄) · kit 사본 같은 판(cmp0)
2. 시험 신설 feature-pack/fable-team/legacy/1.x/harness/tests/test_card_assign_pointer_stale_folder_r1339.sh(100644 · S1~S5 · 변이 3 · 틀 = feature-pack/fable-team/legacy/1.x/harness/tests/test_card_assign_pointer_path_token_r1329.sh · 루트 cwd · ulimit -u 2000 · timeout 70) + 회귀 r1329 시험(단계별 초)

## 완료 조건
- 나노: S1~S5 rc0 · 기준판(origin/main + 새 시험) S1·S2·S3 FAIL · 변이 1 → S1 FAIL · 변이 2 → S2 FAIL · 변이 3 → S5 FAIL · bin·kit cmp0 · 시험 100644
- master: 착지 → 설치 cmp0 → 실사건(BYZ 루트 status 머리 «카드 없는 발주 N» 감소 + «닫힌 카드 발주 M» 칸 원문 1줄 · 같은 판본 비교) → 완성

## 범위 밖
- 발주서 포인터를 자동으로 고쳐 쓰기(쓰기 0) · 낡은 inbox 발주서 정리(팀 몫)

## 상태
- 2026-11-02T19:0x 대기 — arch#213 작성(master#153 #230844 · r1329 측정 :88) · 우선 낮음 · 다음 = master Issue · 사전 DA 면제 후보(읽기 판정 1곳 · 쓰기 0)
- 2026-11-02T19:1x 번호 r1338 → r1339(arch#212 r1338-heavy-slot 이 먼저 push · 번호 겹침)
- 2026-11-11T21:5x 대기 — aifp 사본(aifp-ft-arch-pi#0 · master #3972·#3974 · 실측 #3971): 경로 legacy/1.x · 원인 줄 :522 · 배경·구현 범위·완료 조건 절 채움 · Issue #8374
