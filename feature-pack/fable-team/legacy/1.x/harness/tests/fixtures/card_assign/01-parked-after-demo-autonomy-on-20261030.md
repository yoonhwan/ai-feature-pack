# arch 발주 01 — 시연 뒤 재개 목록 착수 (자율 ON A2 · 범위 S3)

골 원문(3줄 · 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골좌표: 1 — 하네스팀 랜딩부터 (골의 어느 축: 카드 착지 → 라이브 설치 · 이 목록은 «랜딩할 카드 만들기»)

## 상황
- 시연 끝(판정 2835) · 자율 ON A2 · 범위 S3(24h · 병합 30 · 하루 15 · docs,code · code 10 · 외부 DA APPROVE 카드만 · h356 15:52) · planner#177 #201460.
- 정본 목록 = `design/harness/PARKED-after-demo-20261030.md`(§1 대기 카드 4 · §2 후보 · §3 r1153 설치 보류 · §4 진행 25장 · r1098). 옛 arch#180·#181 은 닫힘 — 너는 새 좌석이라 이 파일이 전부다.
- 근거 쪽지 번호는 PARKED §2 «근거» 칸에 있다. 쪽지 원문 = `.fable-team/comm/bodies/<seq>.txt`.

## 할 일 (순서)
1. **r1157 먼저**: 대기 칸 카드 확인(Issue #5004 줄 반영 끝) → master 에 «spawn 요청» 1통. 착지하면 r1098 세트 줄 재시험 → «닫힘 추가» 로 완성 요청(진행 25장도 사건 오면 같은 방식).
2. **대기 4장**(r1149·r1155·r1156·r1157): spawn lint(`FT_CARD_REQUIRE_PREVERIFY=1`) 4/4 OK 였다 — 다시 돌려 확인 후 master 에 spawn 요청(master 가 `ft-nano-spawn.sh`).
3. **후보 7건 카드화**(대기 칸 · lint OK 까지 · Issue 번호는 master 가 발급 → 카드 «- Issue:» 줄은 arch):
   ① ft-launchd-check 경보 수신자 → harness master (planner 결정 #200328 · 코드 = ft-launchd-check.sh 25행)
   ② ft-hil-notify «mbox send rc≠0» (h351·h353 · h 안 S 값 승계 전 좌석)
   ③ 승계 새 좌석이 [인계]를 받고도 안 깸 (v65 #258·ops #73 · harness #199383 doorbell=skipped)
   ④ ft-nano-spawn 이 나노 base 를 spawn 한 좌석 cwd HEAD 로 굽음 (lecture · l89 닫기 막힘)
   ⑤ 실행 중 press 가 있을 때 retire/reap 보류 (v65 tester#100)
   ⑥ ft-da-codex.sh «판정 불가 rc=3» (본문에 VERDICT 있는데도 · feature arch#68)
   ⑦ **새**: `ft-autonomy on` 이 «시작 장부 쓰기 실패 · planner 팀 폴더를 못 풀었다(FT_ROOT=.worktrees/v6-realtime-live)» 로 rc1(h350·h356 · 자율 상태는 ON) — desk #201456
   각 후보: 원인은 코드·로그로 직접 확인(근거는 PARKED 에 있고 «미확인» 표시가 남은 칸이 네 몫) → 카드 §구현 범위·§완료 조건 · 시험은 «동작 반례 먼저».
4. 순서 권고: ①(수신자) · ②(h 결과 알림) · ③(승계) 은 전 팀에 닿는 알림 길이라 먼저 · ④⑤⑥⑦ 은 그 뒤. 크기가 큰 카드는 쪼갠다(시험 단독 70초 · 한 회차 7분 상한).

## 지킬 것
- master 는 코드·카드 증거 줄 직접 편집 0 · 카드·판정문·원인 규명·설계 = 너. DA 소환 결정도 너(카드당 호출 상한 3 · 동작 반례 0 이면 바로 착지 — 전역 하드 룰 14·21).
- 자율 S3: code 카드는 «외부 DA APPROVE» 가 있어야 착지 · 병합 30·하루 15·code 10 한도 — 카운터 줄은 master 가 `ft-autonomy.sh scope-status` 로 붙인다.
- 나노 동시 3석 · 부하 28 아래만 spawn(master 몫) · 브랜치·워크트리 삭제는 HIL.
- BYZ 공용 우편 도구(mbox_ops.py 등) 설치는 r1153 묶음 — 설치 신호는 planner 가 이미 «시연 끝» 으로 열었는지 master 에 물어서 확인(없으면 master 가 planner 에 질문).
- 보고 = master 에 mbox `[정리]` (카운터 줄은 따로 한 줄 · 본문에 «오빠 결정 대기» 같은 낱말 쓰지 않는다 = [HIL] 오승격). 오빠께 묻는 일은 master 경유 → planner#177.

## 첫 보고(부팅 5단계 ⑤)
세션명 / 모델·창 / ci 가부 / ①의 골 대조 한 줄 + 위 1번 r1157 상태.
