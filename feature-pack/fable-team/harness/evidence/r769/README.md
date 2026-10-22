# r769 증거 — press 게이트 로컬 갈래 «팀 선언 포트 슬롯» + 부하 게이트

브랜치: nano/r769-press-gate-team-port-slot · base origin/main 70e392cb(카드 base_sha 832500c1 와 상이 — 발주문 명령대로 origin/main)
정본: kit/fable-team/bin/ft-press-gate.sh == harness/bin/ft-press-gate.sh (cmp0) · skill/scripts 사본은 다른 판이라 안 건드림

## 커밋
eb56d728 [fix] r769 r2 반송 — 숫자 env 엄격 검사 함수 2(_int_port · _decimal) + 10진 강제 산술
9744f8bb [docs] r769 증거 갱신 — r1 반송 반영·다시 볼 시각·한계
e144943d [feature] r769 부하 REJECT 출력에 «지금 load · 기준 · 다시 볼 시각» 1줄(거절 = 기다림 신호)
25a5a07a [fix] r769 r1 반송 반영 — 슬롯 갈래는 press 전용 변수만(FT_PRESS_PORT_BASE) · 일반 FT_PORT_BASE 무시 · 부하 시험 보강
1edba7dd [feature] r769b press 게이트 부하 게이트 — 5분 평균 load ≥ 60(FT_PRESS_LOAD_MAX) 이면 시작 REJECT + 원인 상위 3
6a2bac71 [feature] r769 press 게이트 로컬 갈래 — 팀 선언 포트 슬롯(FT_PRESS_PORTS > FT_PORT_BASE > 기본 8080·8081·3001)

## 시험
```
test_press_gate_numeric_env_r769.sh: rc=0 (15 PASS · ALL PASS (11))
test_press_gate_team_port_slot_r769.sh: rc=0 (26 PASS · ALL PASS (18))
test_press_gate_load_gate_r769.sh: rc=0 (13 PASS · ALL PASS (9))
test_press_gate_dev_target_r634.sh: rc=0 (71 PASS · ALL PASS)
test_press_permit.sh: rc=0 (36 PASS · ALL PASS)
test_press_role_bts_gate.sh: rc=0 (26 PASS · ALL PASS)
test_press_baseline_check.sh: rc=0 (23 PASS · ALL PASS)
test_nano_spawn_body_press.sh: rc=0 (32 PASS · ALL PASS)
```

## 완료 조건 대조(카드 §구현 범위·§시험 입력)
- ⓐ 빨강(포트 갈래 이전 판 bae6e035d) 슬롯 선언에도 «worker 리스너 없음(:8081)» → 재현 PASS
- ⓑ FT_PRESS_PORT_BASE 슬롯 3개 실제 리스너(python http.server) → chk 3/3 pid · 갈래 줄 «FT_PRESS_PORT_BASE=N → gateway N · worker N+1 · 화면 N+2»
- ⓒ FT_PRESS_PORTS 가 FT_PRESS_PORT_BASE 보다 우선(스텁 호출 기록으로 확인)
- ⓓ 둘 다 없음 = 기본 8080·8081·3001 · 기본 로그 /tmp/byz-worker.log · 기본 SSE 8443 · 기존 출력 바이트 동일(갈래 줄 1줄만 추가)
  ★FT_PORT_BASE=38341 을 export 한 채(lecture 꼴)여도 기본 갈래 — 일반 FT_PORT_BASE 는 읽지 않는다★
- ⓔ 반쪽 선언(로그만·SSE만) = 막힘 + «슬롯 선언 회차는 worker 로그·SSE health 주소도 지정»
- ⓕ FT_PRESS_PORT_BASE 잘못된 값(abc·80·70000·3칸 아님·비숫자·65534+2) = 막힘 · 리스너 접촉 0
- ⓖ 변이 2종(worker chk 8081 고정 → ⓑ 죽음 · 반쪽 검사 삭제 → ⓔ 죽음)
- ⓗ 기존 test_press_gate_dev_target_r634.sh 전부 PASS(dev 갈래 출력 불변)
- ⓘ 실 서버·실 8080/8081/3001 접촉 0(슬롯 회차 출력에 그 포트 문자열 0)
- 부하 게이트(r769b · master #146551): 높음→REJECT+상위 3 · 낮음→통과 · 임계 env · 잘못된 값 막힘 · 못 읽음=⚠ 건너뜀 · 변이(FAIL=1 삭제)로 rc 판정 근거 확인

## press 필요
- 없음 — 단위·캡처만(이 카드는 press 미발사 · 나노는 쏘지 않는다). 실사건(room tester 러너 발사 PASS · 슬롯 포트 갈래 줄 포함)은 master·tester 좌석 소관.
- 단 부하 게이트가 실 트래픽에서 오탐이 아닌지는 **실 press 회차**에서만 확인된다 — 그 관측은 tester 좌석 회차에 붙인다(필요 시 `press 필요: 부하 게이트 줄이 실회차 출력에 찍히는지`).

## r1 반송 반영(arch 146939 · DA⑥ r1 HOLD)
- 슬롯 갈래 = press 전용 변수만: `FT_PRESS_PORTS` > `FT_PRESS_PORT_BASE`(+0/1/2) > 기본 · ★일반 `FT_PORT_BASE` 는 읽지 않음★
  (실측 근거: `.fable-team/bin-lecture/lecture-env.sh` 가 `export FT_PORT_BASE=38341` — 그대로 읽으면 lecture press 가 «반쪽 선언» 으로 막힌다)
- lecture 꼴 회귀 시험: `FT_PORT_BASE=38341` export 된 채 돌려도 «포트 갈래: 기본» · 접촉 포트 = 8080/8081/3001 만 · 차이 = 갈래 줄 + 부하 줄
- 부하 시험 보강: 세계를 «나머지 검사 전부 통과(dev 갈래)» 로 고정 → rc=1 의 원인을 부하 게이트로 특정 · 고부하 분기 `FAIL=1` 만 지운 변이 = rc 0 이지만 ✗ 줄 남음(ⓐ 단언이 죽인다)
- 부하 못 읽음(sysctl·/proc 둘 다 없음) = «⚠ … 건너뜀» 1줄 + 다른 검사 결과 그대로(rc 0) · 오타 «건너뜀» 수정

## master 추가 지시(146971 · planner 2681)
- 임계 60 변경 0 · 고부하 REJECT 출력에 «지금 load · 기준(FT_PRESS_LOAD_MAX) · 다시 볼 시각(HH:MM · +10분)» 1줄 — 거절 = 기다림 신호
- 시험 1개: 그 3요소가 한 줄에 있는지

## 한계(범위 밖 · master 에 알림)
- 부하 게이트는 dev 갈래에도 걸린다(클라이언트·오디오는 로컬이라 의도) · 임계 60 은 오빠 지시값
- 로그·SSE 값의 «주인» 검사 없음(값 존재만 본다 — 남의 팀 로그를 지정해도 형식이 맞으면 통과)

## r2 반송 반영(arch 147324 · DA⑥ r2 HOLD · master 결정 B)
- 숫자 env 검사가 변수마다 `case` 로 흩어져 같은 종류 구멍 2개(017620 앞 0 = 8진 8080 · 60..0 점 개수 무제한) → **함수 2개를 게이트 안 한 곳**으로:
  `_int_port` = `^[1-9][0-9]{3,4}$` 이고 1024~65535 만 rc0(앞 0·부호·공백·빈 값 = rc1) · `_decimal` = `^[0-9]+(\.[0-9]+)?$` 만 rc0
- `_port_bad` 삭제 → `_int_port`(FT_PRESS_PORTS 각 칸 · FT_PRESS_PORT_BASE · 파생 +1/+2) · 산술은 `$((10#$FT_PRESS_PORT_BASE + 1))`(검사 뒤라도 10진 강제)
- LOAD_MAX = `_decimal`(실패 = ✗ + FAIL=1 그대로)
- 시험 `test_press_gate_numeric_env_r769.sh` ⓟ~ⓢ 11/11 — **빨강 먼저**: 변이 2종(앞 0 검사 삭제 → 017620 통과 재현 · 점 개수 검사 삭제 → «✓ 100 < 60..0» 재현)으로 단언이 변이를 죽이는지 확인 · 스텁만(실 포트 접촉 0)
- ★같은 부류 남음(이 카드 범위 밖)★: `FT_PRESS_DEV_BUDGET`(50·180행 · r634 기존 입력)은 아직 `case`/산술 직접 사용 — 별 카드 대상.
- 빈 값 = «선언 안 한 것»(기본값) — 검사 함수는 빈 값을 받지 않고, 호출측 `${VAR:-기본}` 이 먼저 처리한다.
