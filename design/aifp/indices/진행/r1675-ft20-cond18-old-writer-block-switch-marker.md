# 인덱스: r1675-ft20-cond18-old-writer-block-switch-marker — 끝: 팀마다 «2.0 전환 표식» 1파일이 생기면 그 팀 데이터에 쓰는 1.x 도구가 쓰기 전에 멈춘다(rc3 · 이유 1줄). 그때 들어온 새 입력은 버리지 않고 보류 폴더에 바이트 그대로 남는다. 표식 쓰기·지우기는 도구 1개의 동사 2개이고, 실 팀에 쓰는 것은 전환 h(오빠 D) 뒤 master 만 한다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8340 (byz-agents · team:harness-ops)
- 이식: BYZ design/harness/indices/대기/ 같은 이름 카드(06e1016a55) → aifp design/aifp/indices/대기/ · 바꾼 것 = ledger 경로(팩 안 GOAL-harness.md 사본) · 대상 경로(팩 실재 경로로 고침) · 선행 해소 · 나노 = pi · 수용 기준·인수 조건 = 원문 그대로
- 나노: pi 에이전트(aifp #3869 ① «나노 = pi»)
- 지시: 오빠 «움직임 없는것. 카드없는것 배정해서 뚫어»(QA#6 #284589 ①) → master-pi#197 #284592 ① · #284604(칸 2 추가: 팩 파일 owner · 인수 조건)
- 근거(arch-pi#298 · 2026-11-11 · 읽기만): TABLE-ft20-conditions-12-18-done-arch286-20261111.md 18행 «r1615(새 · 구 writer 차단 + 두 팀 전환 + 설치본 실제 재개 checker)» = 제안 번호뿐 · 카드 파일 0 · ROUTE-ft20-complete-land-migrate-20261109.md §4 단계 6 «새 입력 보존 → 구 writer·이중 실행 차단 → 전환 → checker» · 팩 origin/main ft2/tools/legacy_guard.py = ft2 소스가 1.x 를 부르는지 보는 정적 검사뿐 · 실행 중 1.x 쓰기 차단 장치 0 · r1614(완성) = 설치·전환·되돌림 도구(설치 루트 밖 쓰기 0 · 팀 runtime 은 안 건드림)
- 원인 1줄: 2.0 으로 옮긴 팀에 1.x 도구가 계속 쓰면 같은 일이 두 곳에 기록된다. 그런데 «이 팀은 옮겼다» 를 1.x 도구가 읽을 표식이 없다
- 실사건: 없음 — 전환 전(조건 18 «전환 뒤» · 두 팀 전환 h 미발급)
- 기준값: 지금 = 전환 표식 0 · 1.x 쓰기 도구의 전환 확인 0 · 보류 폴더 0
- 중복 확인: 대기·진행 «writer·전환·switch·legacy» 대조 — r1614(설치 도구 · 완성 · 팀 데이터 쓰기 0) · r1498(대기 · 팀 종료·부팅 1명령 · 좌석 수명 축) · r1630(완성 · 원본 목록 읽기만) → 같은 카드 0 · TABLE 제안 번호 r1615 의 «구 writer 차단» 몫 = 이 카드(전환 실행·checker 몫은 r1677)
- 끝: 팩 PR 1장(전환 표식 도구 1 + 1.x 쓰기 입구 가드 + 시험 1파일) → 설치 h(master) · 실 팀 표식 쓰기 = 전환 h(오빠 D) 뒤 master
- 묶음 판정: 1건 — 표식과 가드는 한 계약의 양쪽이라 나누지 않는다 · 전환 실행 checker 는 r1677 로 뗀다(관측자 독립)
- 겹침 대조: r1674(진행 · ft-seat-retire.sh PI ADAPTER) → 이 카드가 retire 머리에 가드 1줄을 더하면 같은 파일 · r1674 착지 뒤 그 위에서(선행) · r1670(진행 · ft-nano-close*.sh) → 닫기 도구는 쓰기 입구 표에 넣지 않는다(닫기는 전환 뒤에도 옛 좌석 정리용) · 겹침 1(순서로 해소)
- 제안서: 없음 — 고칠 안 1개(표식 + 입구 가드)라 제안서 불필요
- 상태: 대기 · 2026-11-11 · arch-pi#298 카드 초안(#284592 ①) · 2026-11-11 aifp 이식(byz-aifp-arch-pi#0 · #3869 ①)
- 설치: 있음 — 팩 원본 → 라이브 bin 설치 h(master) · 나노는 설치하지 않는다(r1672)
- 선행: r1674 착지됨(팩 356c4327 · PR #917 · 설치 h8260 · master #3869 회신 기준) → 해소 · 실 표식 쓰기는 조건 16 실 설치(r1614 ⓖ) + 전환 h(오빠 D) 뒤
- 시험 입력: 임시 데이터 루트(가짜 seats-<팀>.json · indices · mailbox.jsonl) · 팀 2개(전환한 팀 · 안 한 팀) · 실 데이터 루트·실 명부·실 우편함 쓰기 0 · 사례 70초 · 회차 7분 · sleep 0
- 수용 기준:
  - ⓐ 표식 도구 `ft-team-switch.sh mark <팀> --h <번호> | unmark <팀> --h <번호> | status [<팀>]` · 표식 = `<데이터 루트>/.fable-team/state/ft20-switch/<팀>.json`(team · switched_at · h · by) · mark 는 이미 있으면 rc2 «이미 전환» · unmark 는 표식을 `<팀>.json.unmarked-<ts>` 로 rename(지우기 0) · --h 없으면 rc2
  - ⓑ 쓰기 입구 가드 1함수: 표식이 있는 팀의 데이터에 쓰려 하면 쓰기 전에 «REJECT 팀 <팀> 은 2.0 전환됨(<switched_at> · h<번호>) — 1.x 쓰기 0» 1줄 + rc3 · 표식 없는 팀 = 지금 동작 그대로 · 표식 파일을 못 읽음(깨진 JSON·권한) = «판정 불가» rc3(쓰기 0 · 하드 룰 20)
  - ⓒ 쓰기 입구 표: 나노가 먼저 팩 legacy/1.x/harness/bin 에서 seats-*.json · design/*/indices/ · mailbox.jsonl 에 쓰는 도구를 뽑아 표 1장(도구 · 쓰는 자리 · 팀 결정 방법)으로 arch 에 보낸다 → arch 확인 뒤 가드를 넣는다 · 후보 = mbox.sh(send·ring·handover · 받는 좌석의 팀) · ft-index-move.sh · ft-nano-spawn.sh · ft-seat-retire.sh · ft-successor-open.sh · 닫기 도구(ft-nano-close·ft-seat-close)는 표에서 뺀다
  - ⓓ 새 입력 보존: mbox send 가 ⓑ 로 막히면 본문을 `<데이터 루트>/.fable-team/state/ft20-switch/<팀>.held/<ts>-<from>.txt` 에 바이트 그대로 남기고 그 경로를 REJECT 줄에 적는다 · 보류 파일 쓰기 실패 = rc3 + «보류 실패» (조용한 유실 0)
  - ⓓ 범위: «바이트 그대로» = mbox_guard 정규화(ALIAS 머리 바꿈·첫 줄 교체) 뒤 본문이다. 보낸 원문 바이트와 다를 수 있다(arch 인수 #3921 ④)
  - ⓔ 회귀: 표식 0 일 때 test_seat_retire*.sh · mbox 시험 · index-move 시험 FAIL 줄이 앞 판과 같다(늘어난 FAIL 0)
- 변이(나노 · 사본에서만): M1 가드의 표식 확인 삭제 → 전환 팀 쓰기 사례가 rc0 으로 새서 FAIL · M2 보류 쓰기 삭제 → ⓓ 보류 파일 0 으로 FAIL · M3 깨진 표식을 «없음» 으로 침 → 판정 불가 사례 FAIL
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 2(표식 지우기 0 · rename 만 · 실 표식 = 전환 h) · 하드 룰 20 · 하드 룰 22 · docs/rules/no_silent_fallback.md
- 팩 파일 owner: harness 팀(legacy/1.x/harness/bin · kit 짝 · 시험) · 새 도구 ft-team-switch.sh 도 harness · ft2/ 쪽 쓰기 0(2.0 코어 owner = harness 그대로)
- 인수 조건(aifp·feature 팀이 구현·DA·착지를 받을 때): ① 이 카드 lint OK 판 + base_sha · ② ⓒ 쓰기 입구 표는 harness arch 확인 1통을 받은 뒤 가드 착수 · ③ 시험은 임시 데이터 루트만(실 .fable-team 쓰기 0 · 사본 경로 인자로) · ④ push·PR·설치 = harness master 집행 · DA = 받은 팀 DA 가능(판정문은 BYZ docs/da-278062 에 같은 꼴로) · ⑤ 실 표식 쓰기 0(전환 h 뒤 harness master)
- 대상(쓰기 = 나노 · 팩 1곳): feature-pack/fable-team/legacy/1.x/harness/bin/ft-team-switch.sh(새) · ⓒ 표의 도구 머리(가드 1줄씩 · mbox.sh 원본 = legacy/1.x/harness/comm/mbox.sh) · legacy/1.x/harness/kit/fable-team/bin 같은 사본(kit 에 comm/mbox.sh 짝 없음 · mbox 짝은 ⓒ 표에서 나노가 확인) · 새 시험 legacy/1.x/harness/tests/test_team_switch_guard_r1675.sh · ★나노 쓰기 금지★ 라이브 설치 · 실 데이터 루트 · ft2/
- 크기: 도구 ≤80줄 · 가드 함수 ≤20줄 + 입구마다 1줄 · 시험 ≤150줄
- 정본 영향 없음: 1.x 도구 가드 · 정본 문서 변경 0
- 배정: 좌석 aifp-ft-nano-r1675-ft20-cond18-old-writer-block-switc#0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」 · 골의 축: 4(하네스 운영 정리 — 끝난 일은 남지 않고, 좌석은 정한 순서로 열린다) · 이 카드의 증거 = 사례 ⓐ~ⓔ + 변이 3/3 + 설치 뒤 표식 0 상태 회귀 rc0 · 조건 18 «구 writer 차단» 칸의 장치.

## 배경 (한 단락)
ft 2.0 조건 18 은 두 팀(harness·planner)을 2.0 으로 옮긴 뒤 1.x 쪽 쓰기를 막고 새 세션에서 실제로 이어 가는 것이다. 설치 도구(r1614)는 설치 루트만 다루고 팀 데이터는 건드리지 않는다. 그래서 전환한 팀에 1.x 도구가 계속 쓰는 것을 막는 장치가 없다. 이 카드는 팀 단위 표식 1파일과 1.x 쓰기 입구의 가드로 그 자리를 채운다. 막힌 입력은 보류 폴더에 남겨 잃지 않는다.

## 고칠 안 1개
- 팀 전환 표식 1파일 + 1.x 쓰기 입구 가드(쓰기 전 rc3) + 막힌 쪽지 보류.

## 구현 범위 (나노 1 · 팩 가지 → 설치 h)
- 산출: ⓒ 쓰기 입구 표 1통(arch) → 팩 가지 1커밋 · RUN 줄(단계별 초) · arch 1통
- 입구 후보(팩 실재): `feature-pack/fable-team/legacy/1.x/harness/bin/ft-seat-retire.sh` · `feature-pack/fable-team/legacy/1.x/harness/bin/ft-index-move.sh` · `feature-pack/fable-team/legacy/1.x/harness/bin/ft-nano-spawn.sh` · `feature-pack/fable-team/legacy/1.x/harness/bin/ft-successor-open.sh` · `feature-pack/fable-team/legacy/1.x/harness/comm/mbox.sh`
- 새 파일: `feature-pack/fable-team/legacy/1.x/harness/bin/ft-team-switch.sh` · `feature-pack/fable-team/legacy/1.x/harness/tests/test_team_switch_guard_r1675.sh`

## 범위 밖
- 실 팀 표식 쓰기(전환 h) · 2.0 쪽 보류 입력 가져오기 · 닫기 도구 · ft2/ 코드 · 전환 뒤 checker(r1677)

## 완료 조건
- ⓐ~ⓔ · 변이 3/3 · 설치 h

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| 표식 도구 동사·rename | 사례 ⓐ |
| 쓰기 전 멈춤 · 판정 불가 | 사례 ⓑ |
| 쓰기 입구 표 | 사례 ⓒ(표 1통 + 입구마다 사례 1) |
| 새 입력 보존 | 사례 ⓓ |
| 표식 0 회귀 | 사례 ⓔ |

## 상태
- base_sha: 816fa5e412a75e3e5801a642f8a9eb1fc39dbb98 (spawn 2026-11-11)
- 2026-11-11 · arch-pi#298 카드 초안(#284592 ①) · 대기
- 2026-11-11 18:30 — 대기→진행 · 좌석 aifp-ft-nano-r1675-ft20-cond18-old-writer-block-switc#0
- [배정 불명] 불명(scope 표 없음 opengateway/deepseek/deepseek-v4.1-flash-ultrafast)
- 2026-11-11 18:39 — ⓐ~ⓔ 구현·시험 완료(나노) · 브랜치 nano/r1675-ft20-cond18-old-writer-block-switc
- ⓒ 표 = harness arch #285137 → 보정 5줄 #3917 수신(arch 확인 완료): ①mbox 팀 판정 3갈래(없음=INFO 통과 · 깨짐/2개 이상=rc3) ②index-move 팀 = 카드 경로 우선 ③nano-spawn = env 팀 + 카드 팀 둘 다 ④retire = 쓰기 대상 명부 전부 ⑤successor-open OK · 누락 입구 3 추가(role-spawn · tick-team) + 제외 2 사유(ft_model_swap.py = ft-successor-open·mbox 로 위임이라 그 두 가드가 덮음 · ft-nano-spawn-undo.sh = spawn 되돌림/정리 계열)
- 세트: c4798b91e31fd61374e6cba3c76125a250dd2f0d · 시험: bash tests/test_team_switch_guard_r1675.sh (27 passed · 변이 3/3 · 재진입 lint rc=0) rc=0 · 이슈: 0
- 회귀(표식 0): test_seat_retire.sh 177P 3F · test_seat_retire_dead_pi_r1674.sh 39P 0F · test_index_move_rule_line.sh 17P 0F · test_mbox_bridged_send_r1562.sh 12P 1F — 앞 판 대비 늘어난 FAIL 0(줄 목록 동일 · kit-bin-sync 는 동기화로 PASS 로 줄었다)
- RUN: 표식 도구·lib 1회 작성 → 시험 27사례 2초 · 변이 3종 2초 · 회귀 4종 48/3/3/45초 · 합계 1회차 약 2분
- press 0(단위·임시 데이터 루트 시험만 · 실 .fable-team·실 우편함 쓰기 0) · 설치 h 필요(라이브 bin 에 ft20-switch-lib.sh + ft-team-switch.sh 짝 = master 집행)
- 2026-11-11 18:47 — arch 인수 보류 3건(#3922) 보정 → 세트: 628bfc2f32dae3edfadd521bd873067505ce2537 · 시험: bash tests/test_team_switch_guard_r1675.sh (29 passed · 변이 3/3 · 재진입 lint rc=0) rc=0 · 이슈: 0
- 보정 ① 보류 파일 = 이름에 순번 + noclobber(같은 초 2통 2파일 · 앞 본문 보존) ② retire = --seats/FT_SEATS_JSON 을 줘도 쓰기 대상 명부 전부 검사(r465 `_*` 칸 포함) ③ 입구 = 호출 1줄(팀 판정은 ft20_guard_move·spawn·retire·roster·seat) · successor-open = retire 와 같은 판정 · ft20_team_of_seat 삭제
- 2026-11-11 19:05 — DA HOLD(#3927) 대응 → 세트: d3a11910c125fbb3640ea83fa4125e3030ef9a16 · 시험: bash tests/test_team_switch_guard_r1675.sh (32 passed · 변이 3/3 · 재진입 lint rc=0) rc=0 · 이슈: 0
- R1(동작) 명부에 없는 옛 좌석 retire = R282② 가 이름의 팀 명부에 새 행을 쓴다 → ft20_guard_retire 가 «쓰기 대상 명부 전부 + 이름의 팀 명부(옛 이름 lint 실패면 후계 이름 팀)» 로 판정 · DA 재현 스크립트 rc=3 · 명부 불변 · 사례 ⓒ⑥ 추가
- R2(회귀) lib 부재 WARN 제거 → «표식 0 = 무출력(지금 동작 그대로) · 표식 있으면 rc3 판정 불가» 로 7개 입구 통일 · test_index_move_mv_fail_reason.sh F 1→0 · 사례 2 추가 · kit 8파일 재동기화(bin=kit)
- 회귀 표(앞 판 816fa5e4 F / 새 판 F · 초): test_seat_retire.sh 3/3(43초 · ⑧ 뗀 판 1/1 · 12/14초) · ⑧test_ft_tick_master_seat 4/4 · ⑧test_role_spawn_name 4/4 · ⑧test_kit_bin_sync 0/0 · test_seat_retire_dead_pi_r1674 0/0 · test_mbox_bridged_send_r1562 1/1(50/53초) · test_index_move_mv_fail_reason 0/0 · test_index_move_rule_line 0/0 · test_index_move_archive_r1000 2/2 · test_nano_team_env 11/11 · test_r1043_role_default_model 4/4 · test_role_spawn_ft_root_r1404 0/0 — 늘어난 FAIL 0(DA 가 못 본 두 시험은 ⑧을 떼어 12~14초로 쪼개 FAIL 줄 완전 동일 확인 · 동시 4개 실행은 서로 간섭해 FAIL 을 만들어 전부 직렬)
- 2026-11-11 19:11 — DA 재판정 HOLD 중 R3(ⓓ) 대응 → 세트: 8f6226f92ba34af7604c3d91be990ca8ccc00ba7 · 시험: bash tests/test_team_switch_guard_r1675.sh (33 passed · 변이 3/3 · 재진입 lint rc=0) rc=0 · 이슈: 0
- R3 lib 없는 설치본(표식 있음)에서 막힌 mbox 본문이 사라졌다 → 팀 판정 불가라 <팀>.held 대신 <데이터루트>/.fable-team/state/ft20-switch/_unjudged.held/<ts>-<from>-<pid>-01.txt 에 같은 꼴(noclobber·순번)로 남기고 경로를 REJECT 줄에 적는다 · 쓰기 실패면 rc3 + «보류 실패(보류 폴더 쓰기 0)» · 사례 ⓓ 추가
- 크기 상한 준수: ft-team-switch 80줄(80) · 가드 함수 20줄(20) · 시험 134줄(150) · 회귀 10종 직렬 재실행 — 앞 판 F 와 동일(seat_retire 3 · dead_pi 0 · mbox_bridged 1 · mv_fail_reason 0 · rule_line 0 · archive_r1000 2 · nano_team_env 11 · r1043 4 · role_spawn_ft_root 0 · tick_master 4)
- 회귀(표식 0) 2회차: test_seat_retire.sh 177P 3F(50초) · test_seat_retire_dead_pi_r1674.sh 39P 0F(2초) · test_index_move_rule_line.sh 17P 0F(5초) · test_mbox_bridged_send_r1562.sh 12P 1F(52초) — 1회차와 FAIL 줄 목록 동일(늘어난 FAIL 0 · 200줄 미달 FAIL 은 이 파일의 앞 판부터 있던 것)
- 2026-11-11 19:15 — 착지: PR #926(head 8f6226f92ba34af7604c3d91be990ca8ccc00ba7 · CLOSED = ft-merge-land) → 팩 main cec9ec255eafe7b3113079689525d50b77db6cb4 · feature-pack 트리 = 세트 8f6226f9 와 같음(diff 0) · 설치 h = harness 대기(planner 설치 HIL · «INSTALLED» 오면 설치 cmp0·실사건 뒤 완성 이동) · 카드 칸 = 진행 그대로
