# 인덱스: ft2-new-card-hold — 끝: 설정 파일 1개(state/NEW_CARD_HOLD.json)가 있으면 전 팀 keeper 가 새 카드를 넣지 않는다 · settle·닫기·이어 열기·사람 손 발주·팀장 개설은 그대로다 · 팀별 PAUSED 손 조치가 필요 없다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8632 — 등록 planner#323 aifp 5348(팀장 aifp-ft-master-pi#17 발주 aifp 5310 ① · 5334 · 5346 · planner 5337 «지금 판에선 정지 아님 · 우선 낮춤»)
- 제안서: 없음 — 설정 1곳 추가(새 흐름 0) · 설계 = .fable-team/state/team-main/aifp-ft/orders/DESIGN-p1-new-card-hold-20261116.md(sha256 189777aa…7956 · DA 대행 byz-harness-da-codex#11 APPROVE-DESIGN aifp 5339 · 고칠 칸 0) · 착지 PR 에서 feature-pack/fable-team/design/ 로 옮긴다
- 근거: 실측 2026-11-16(aifp-ft-arch-pi#16 · BYZ keeper 로그 원문 · 읽기만) — 전 팀 정지가 11-15 23:44 에 풀린 뒤 keeper fill 이 harness 에 r2057·r2058·r2064 를 넣음(journal harness 2852~2854 · NEXT harness fill:r2064-…) · 지금 막는 손 조치 = harness state/harness-tick/PAUSED(팀 틱 전체를 멈추는 다른 뜻의 파일)
- 근거 덧(harness 문제 목록 A · r2078 넘겨받음 · harness#288 aifp 5376 «harness 쓰기 0» · 팀장 #18 aifp 5378): BYZ .fable-team/state/team-main/harness/HANDOFF-pi378-to-next-20261116.md 1절 ⓑ — 11-15 17:09 harness 팀장이 13팀 state/<팀>-tick/PAUSED 를 손으로 만듦(이유 = keeper 가 ALL_STOP 을 안 읽음 · BYZ #307983·#307987·#307990 = 인용 · 원문 대조 안 함) · 23:44 전 팀 정지 해제 뒤에도 남아 keeper fill 0(gates :50~53 은 PAUSED 면 줄 없이 False) · 지금 실측(aifp-ft-arch-pi#17 · 읽기만) = 팀 PAUSED 0개 · 14팀이 PAUSED.bak-322-20261115T23… 또는 bak-323 으로 옮겨짐 · 이 카드가 맡는 몫 = 손 PAUSED 를 만들 까닭을 없앰(H1~H3)
- 원인 1줄: keeper_next.gates() 가 보는 것은 팀별 CLOSE-NEXT.enabled·팀별 PAUSED·SPAWN_HOLD·ACCT_PAUSE·나노 상한뿐이다 · «지금은 새 카드를 넣지 않는 기간» 을 말하는 전 팀 설정이 없다
- 앞 카드: r1913(fill) · r1939(fill 꽉 참) · r2055(ALL_STOP 판독 꼴) · r1871(닫기 뒤 다음 카드)
- 상태: 대기
- 설치: 있음 — ft2 판 올림 1회 · 설정 파일 두기·치우기 = planner master 집행(이 카드 밖) · 되돌림 = 앞 판으로 판 전환(파일이 있어도 옛 판은 읽지 않음)
- 선행: ft2-launch-failed-end 착지(keeper_next.py 를 같이 만짐 · 그 위에서 시작) · 우선 낮춤(planner 5337)
- 시험 입력: 임시 루트(tmp_path) · 시험 안에서 만든 journal·카드·설정 파일 · 가짜 tmux·가짜 mbox · 가짜 clock · sleep 0 · 네트워크 0 · 실 runtime 쓰기·읽기 0 · 사례 1개 70초 안
- 기준값: 기준판 = 설정 파일이 있어도 fill submit 1 → 목표 = submit 0 · journal 줄 수 그대로 · NEW-CARD-HOLD 1줄
- 규칙: 없음 — 상시 로드 변경 0(설정 파일 사용법 1줄은 CONTRACT 에)
- 규칙 상세: 하드 룰 20 · 하드 룰 22 · no_silent_fallback(깨진 파일 = 보류 + 판정 불가 1줄)
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper_next.py(fill pick · 닫기 뒤 pick · 판독 함수) · 새 시험 feature-pack/fable-team/ft2/tests/test_new_card_hold.py · 문서 ft2/contracts/keeper-settle/CONTRACT.md
- 정본 영향 있음: CONTRACT.md 에 «새 카드 보류 설정» 절 1개(자리·꼴·막는 것·안 막는 것·풀기) = 같은 PR(나노)
- 크기: 코드 1파일 · 새 시험 1파일 · 문서 1파일 · PR 1개
- 배정: 대기(선행 · 2026-11-16T01:12)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(하네스 운영 정리 — 새 카드를 넣지 않는 기간을 설정 1곳으로 정한다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설정 파일을 둔 뒤 keeper 로그의 팀별 NEW-CARD-HOLD 줄 + 그 시각 뒤 전 팀 journal 의 새 accept keeper-next 줄 0.

## 배경 (한 단락)
keeper 는 빈 나노 칸이 있으면 대기 카드를 스스로 넣는다(fill). 닫기 뒤에도 다음 카드를 고른다. 이것을 전 팀에서 한 번에 멈추는 설정이 없다. 전체 정지(ALL_STOP)는 닫기·정리·깨움까지 멈추고, 팀별 PAUSED 는 그 팀 틱 전체를 멈춘다. 2.0 완료 전처럼 «새 카드만 넣지 않는» 기간에는 팀마다 손으로 PAUSED 를 둬야 했다. 설정 파일 1개로 keeper 의 카드 고르기 두 곳만 막는다. «2.0 완료» 는 기계가 판정하지 않는다. 사람이 둔 파일이 기준이다.

## 계약
- H1 설정 자리 = `<데이터 루트>/.fable-team/state/NEW_CARD_HOLD.json` 1개(전 팀 공통) · 꼴 `{"reason": "<10자 이상>", "by": "<좌석>", "at": "<시각>", "until": "<사람이 읽는 조건>"}`
- H2 판독 = keeper 바퀴당 1회 · 없음 = 열림 · 있음 = 보류 · 깨짐(빈 파일·JSON 아님·reason 없음) = 보류 + `판정 불가` 1줄
- H3 막는 곳 = `fill()` 의 새 pick · 닫기 뒤 다음 카드 pick 두 곳뿐 · 닫기 영수(close_receipt)는 지금처럼 쓰고 다음 카드만 «다음 없음» 길
- H4 안 막는 것 = 이미 연 열기 잇기(fill_open reconcile) · settle · 착지 complete · 닫기 · 깨움 · 사람 손 ft2 submit/assign/deliver
- H5 드러냄 = 팀마다 `NEW-CARD-HOLD <팀> <reason> · until <until>` 1줄(값이 바뀔 때만) · 풀리면 `NEW-CARD-OPEN <팀>` 1줄
- H6 풀기 = 파일을 `NEW_CARD_HOLD.released-<시각>` 으로 이름 바꿈(ALL_STOP 과 같은 손)
- H7 경계: 이 파일을 읽는 곳은 keeper_next.py 뿐 · ft-successor-open.sh·팀장 열기 길·ft-nano-spawn.sh·tmuxc open 은 읽지 않는다 · 보류 중에도 팀장 개설·승계·사람 손 나노 개설은 지금과 같다
- H8 그대로: gates() 본문(복구 launch 가드가 같이 씀) · ALL_STOP · 팀별 PAUSED · intake

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · ft2-launch-failed-end 착지 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_new_card_hold.py(㉗가~사 · M14·M15) · 기준판 FAIL 원문(㉗가·㉗나·㉗라·㉗바)을 PR 본문에 붙인다
2. 커밋 2 [fix] — H1~H6 = feature-pack/fable-team/ft2/adapters/pi/keeper_next.py(판독 함수 1 · fill pick 앞 · 닫기 뒤 pick 앞) · gates() 본문 손 0 · 다른 파일 손 0
3. 커밋 3 [docs] — feature-pack/fable-team/ft2/contracts/keeper-settle/CONTRACT.md «새 카드 보류 설정» 절 · 설계 1쪽을 feature-pack/fable-team/design/ 로
4. 회귀 rc0: test_pi_keeper_next_card_r1871.py · r1913·r1939 fill 시험 · test_settle_one_path_r2055.py
5. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

## 범위 밖
- 설정 파일을 실제로 두고 치우는 일(planner master 집행) · harness PAUSED 치우기(harness 팀장)
- «2.0 완료» 자동 판정
- 전 팀 정지 해제와 팀 PAUSED 의 관계(해제가 남은 팀 PAUSED 를 함께 풀거나 «N팀 남음» 으로 드러내는 일 · gates() 의 PAUSED 줄 없는 False) = 범위 밖 · 까닭: 이 카드는 keeper_next.py 의 새 설정 판독만 넣고 H8 로 gates() 본문·ALL_STOP·팀별 PAUSED 를 그대로 둔다 · 해제 손은 1.x ft_all_stop.py off(harness 몫 · HANDOFF-pi378 1절 판단 = stdout·재개 통지에 «N팀 남음» 1줄 · 지우기 0)
- thresholds.env 키(버린 길 · 읽는 곳이 4곳이라 1곳이 아님)

## 완료 조건
1. [ ] 나노: 커밋 1 기준판 FAIL 원문
2. [ ] 나노: 새 시험 전체 rc0 · 걸린 초
3. [ ] 나노: 변이 M14 → ㉗가·㉗바 FAIL · M15 → ㉗나 FAIL
4. [ ] 나노: 회귀 rc0
5. [ ] 팀장: PR 착지 sha · 설치 판
6. [ ] 팀장: 설정 파일을 둔 뒤 keeper 로그 NEW-CARD-HOLD 줄 + 전 팀 journal 새 accept keeper-next 줄 0 원문

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| H2·H3 fill 을 막는다 | ㉗가 설정 파일 있음 · 빈 나노 칸 · 대기 카드 1 → fill submit 0 · journal 줄 수 그대로 · NEW-CARD-HOLD 1줄(둘째 바퀴 0줄) / M14 |
| H3 닫기 뒤 pick 을 막는다 | ㉗나 설정 파일 있음 · 나노 닫기 1 → 닫기 영수 1 · 다음 카드 배정 0 / M15 |
| H4 이어 열기는 그대로 | ㉗다 설정 파일 있음 · fill_open 에 잇는 열기 1 → reconcile 그대로 진행 |
| H2 깨진 파일 = 보류 | ㉗라 빈 파일·JSON 아님 → fill 0 · 판정 불가 1줄 |
| H2 없음 = 열림 | ㉗마 파일 없음 → 지금 동작과 같음(fill 1장) |
| H1 전 팀 1곳 | ㉗바 두 팀 · 파일 1개 → 두 팀 모두 fill 0 / M14 |
| H7 팀장 개설은 안 막는다 | ㉗사 설정 파일 있음 · 팀장 개설 1회(ft-successor-open.sh · tmux·쪽지 대역) → 파일 없을 때와 같은 rc·출력 + 팩에서 NEW_CARD_HOLD 를 참조하는 실행 파일 = keeper 쪽뿐(문자열 검색 1회) |

## 상태
- 2026-11-16 · aifp-ft-arch-pi#17 근거 덧 + 범위 밖 1줄(aifp 5378 · harness 목록 A 의 PAUSED 갈래 판단 = 범위 밖 · 계약·시험 변경 0)
- 2026-11-16 · aifp-ft-arch-pi#16 초안(aifp 5346) · 대기 · DA 대행 APPROVE-DESIGN(5339) · 우선 낮춤(planner 5337)
