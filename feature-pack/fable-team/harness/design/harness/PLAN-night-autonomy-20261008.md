# PLAN — 하네스 야간 자율 루프 (사람 0 · arch#8 안 · 2026-10-08 · master#11 #60841 · planner #60833)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골 축: C(업그레이드·반영) + 6-b(요청 접수·협의) + 원문 7(쪼개 동시에). 닫는 증거 = 아침 브리핑의 닫힘 단위별 sha·증거 줄.
정지 = 아래 단위가 전부 닫히거나 §3 정지 조건 — 그 밖의 정지 없음(하드 룰 9: 시계 창 없음).

## 1. 사람 0 으로 돌릴 단위 (순서 = 위에서 아래 · 동시 최대 나노 2석)
실측 기준: 2026-10-08 arch#8 (아래 「지금」 칸).

| # | 단위 | 지금 | 할 일 (사람 0 범위) | 크기 | 골 축 | 되돌림 1줄 |
|---|---|---|---|---|---|---|
| 1 | R25 잔여 — 미러 요약 cc 경로 실측 | 설치됨(라이브 = drafts-r25 cmp 동일 · 리포 eaa7cae7df) · 두 미러 재기동됨 · err 마지막 3줄은 설치 전 seq 60821·60824·60827 | 설치 뒤 첫 게시 seq 의 err 로그에 「요약 실패」 새 줄 0 + 슬랙 3줄 요약 ts 1개를 원장 R25 에 기입. 실패면 원인 문구(이제 남는다)만 기록하고 HOLD | 확인 1회 | 6-b · C(슬랙 발행) | `cp -p ~/.hermes/scripts/mirror_summary.py.bak-r25-1008 ~/.hermes/scripts/mirror_summary.py` (kickstart 는 금지선 — 아침에 사람) |
| 2 | R24 — bash 3.2 런타임 | 로컬 실측 끝: 하네스 시험 32개를 bash5·/bin/bash 3.2 로 각각 → 3.2 에서만 실패 1개 = test_tmm_group 18건 · 원인 `scripts/harness-install/tmm/tmm:197` `${n,,}`(bash4 소문자 변환 · 같은 꼴 6곳) · `bash -n` 은 못 잡음(실행 때 bad substitution). test_regress_pack 은 bash5 도 실패(「issue_pack.jsonl 예시 2행」 — 3.2 무관 · 별건) | 나노 1석: tmm 의 `${x,,}` 6곳을 `tr '[:upper:]' '[:lower:]'` 로 교체 + test_tmm_group 을 /bin/bash 3.2 로도 돌리는 줄 추가. 키트(fable-team) 는 3.2 실패 0 이라 손대지 않음 | 나노 1석 · 시험 2회(bash5·3.2) | 원문 5(머신 독립 운용 선행) | 그 나노 커밋 revert 1개 |
| 3 | test_regress_pack 기존 실패 | bash5·3.2 둘 다 FAIL「issue_pack.jsonl 예시 2행」 | 원인 조사만(읽기) — 실데이터가 예시 2행을 넘었는지(시험 기대가 낡음) vs 파일 결함. 결론 1줄 + 카드 초안(대기/). 수정 나노는 결론이 «시험 기대 갱신» 일 때만 | 조사 1회 | 6-b(하네스 감시) | 카드 파일 1장 삭제 없이 «보류» 표기 |
| 4 | launchd 틱 건강 점검 | com.byz.ft-tick 다시 적재됨(pid 43388) · 로그 「no active seat with tick in seats.json」 · cfo·kakao·feature 틱도 적재 | 읽기만: 각 틱 로그 마지막 줄 · drift_watch 줄(「drift:」 0 이 정상) · wt-sweep 줄. 이상이면 원장에 1행 + HOLD(재기동 금지) | 확인 1회 | C(반영 유지) | 쓰기 0 — 되돌림 불요 |
| 5 | 워크트리 정리 계획 | wt-clean/*.sh 0개(앞서 쌓인 4개 처리됨) | 확인만 — 새로 쌓이면 원장 1행(실행은 tick sweep 몫) | 확인 1회 | C | 쓰기 0 |
| 6 | Issue 816 뒷정리 | ②③(드리프트 검사)·0.4 라이브 1:1 랜딩 · ⑤ FT_BIN 이전 = 완성 후 | 816 코멘트 문안 1장(닫힘 증거 표: PR 878 · drift OK@1a577c3aa7 · mac-mini kit_sha 38d57db630ea) 을 drafts 에 작성 — 게시는 Tank 래퍼라 외부 쓰기 → 아침 사람 판단 | 문안 1장 | 6-b · C | 문안 파일만 — 게시 0 |
| 7 | R23 보류 재개 트리거 감시 | 보류(재발 1회 실측 시 카드 r23-tank-rest-path 그대로) | Tank 래퍼 실패 로그·mbox 에서 「GraphQL」 + 같은 시각 다른 쓰기 성공 쌍 검색(읽기). 걸리면 원장 1행 + 아침 브리핑 「결정 대기」 | 검색 1회 | 6-b | 쓰기 0 |
| 8 | 인계 열린 일 — 3사본 기능 어긋남 | 키트에만 ⓪ 생명주기 · 프로젝트에만 master 좌석 모드 · 홈엔 둘 다 없음(HANDOFF-harness-arch-7 열린 일 4) | 표 1장(어느 사본이 무엇을 갖는가 + 맞추는 순서 안)만 — 코드 0 | 표 1장 | C · 원문 5 | 문서 파일만 |

빠진 것(사람 0 으로 안 함): R15 V(cdp_helper PTT 검사 — v65 소관) · SEATBELT 211·single_set_testing 25 정본 충돌(v65·문서 몫 — planner 통지 끝) · mac-mini 운용(bash 3.2 수정 랜딩 뒤 · 원격 쓰기는 금지선).

## 2. 금지선 (전부 0 — 걸리면 그 단위 HOLD)
- 삭제(파일·브랜치·워크트리·Issue) · kill(세션·프로세스 — 이 루프가 띄운 시험 러너 정지는 예외) · force push · `git reset --hard`.
- 원격 머신 쓰기(byzs-mac-mini 등 ssh 쓰기) · 라이브 서비스 재기동(launchctl kickstart·bootstrap·bootout 포함 · 미러·틱·gateway·worker).
- main 병합 중 cd-dev·gateway 경로 변경 · 공유 Redis(6379) 쓰기 · Issue·PR·슬랙 외부 쓰기(문안만 만든다).
- 라이브 FT_BIN cp — 키트 랜딩은 해도 되지만 라이브 반영은 아침 사람(드리프트 검사가 그 사이 spawn·close 를 막는다 → **키트 bin 을 바꾸는 랜딩은 하지 않는다**. 단위 2 의 tmm 은 fable-team bin 밖이라 해당 없음).
- [HIL] 이 필요하면 `scripts/fable-team-bin/ft-hil-ask.sh "<질문>" --options "a|b" --recommend a` 로 원장(design/teams/harness/HIL-LEDGER.md)에 적고 그 단위만 멈춘다 — AskUserQuestion·인터뷰 0.

## 3. 정지 조건 (하나라도 걸리면 루프 전체 정지 → 정지 레디 + 브리핑 작성)
- 같은 단위 HOLD 2회(DA·검증 반려 포함).
- 같은 오류 문구 3회(단위 무관).
- 오케 좌석 ctx 300k(BYZ 증류 경고선).
- 금지선에 닿는 다음 수만 남음(= 할 수 있는 단위 0).

## 4. 아침 브리핑 템플릿 — design/teams/harness/BRIEFING-morning-20261008.md (사람 읽는 틀 · 결론→할 일→바뀐 것→근거)
```
# 아침 브리핑 — 하네스 야간 자율 (byz-harness-master-claude#<N> · 2026-10-08)

## 결론
<닫힌 단위 수 / 전체 8> 닫혔고 <HOLD 수> 개는 멈춰 있습니다. <정지 이유: 전부 닫힘 | 정지 조건 이름>.

## 오빠가 할 일 (질문 1개 · 추천 먼저)
<가장 급한 결정 1개> ① … ② … 추천 ①.

## 바뀐 것 (닫힌 단위)
| 단위 | 무엇이 됐나(사람 말 1줄) | 닫는 증거(sha · 시험 rc · 로그 줄) |
|---|---|---|

## 멈춘 것 (HOLD)
| 단위 | 멈춘 이유 1줄 | 다시 가려면 |
|---|---|---|

## 오빠 결정 대기 (HIL 원장 열린 행 · 금지선에 걸려 아침으로 넘긴 것)
- <HIL-LEDGER #행 · 질문 1줄 · 추천>
- 라이브 반영(kickstart·FT_BIN cp)·외부 게시(816 코멘트 등) 대기 목록

## 근거
커밋 sha 목록 · 판정서 §N · 쪽지 번호(맨 끝에만)
```

## 5. 역할
- planner: 10분 틱으로 하위 pane·mbox 감시 + HIL 원장 열린 행 수집(인터뷰는 아침에 묶어서).
- harness master: 단위 발주·나노 spawn/close·커밋·키트 랜딩 집행 · 정지 조건 판정 · 브리핑 작성.
- harness arch: 단위 2·3 카드 · 단위 6 문안 · 단위 8 표 · 나노 닫힘 문안(판정서 §).
- 나노: 카드 범위만 · push 0.
