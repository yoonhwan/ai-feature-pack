# r769 증거 — press 게이트 로컬 갈래 «팀 선언 포트 슬롯» + 부하 게이트

브랜치: nano/r769-press-gate-team-port-slot · base origin/main 70e392cb(카드 base_sha 832500c1 와 상이 — 발주문 명령대로 origin/main)
정본: kit/fable-team/bin/ft-press-gate.sh == harness/bin/ft-press-gate.sh (cmp0) · skill/scripts 사본은 다른 판이라 안 건드림

## 커밋
70ed3cd9 [feature] r769b press 게이트 부하 게이트 — 5분 평균 load ≥ 60(FT_PRESS_LOAD_MAX) 이면 시작 REJECT + 원인 상위 3
6a2bac71 [feature] r769 press 게이트 로컬 갈래 — 팀 선언 포트 슬롯(FT_PRESS_PORTS > FT_PORT_BASE > 기본 8080·8081·3001)
70e392cb [fix] r746 루트 연결 파일 .py 를 python 본문으로 (1.1.218)
008e5095 [fix] 묶음 착지 r755 r756 (1.1.217)

## 시험
```
test_press_gate_team_port_slot_r769.sh: rc=0 (24 PASS · ALL PASS (18))
test_press_gate_load_gate_r769.sh: rc=0 (9 PASS · ALL PASS (6))
test_press_gate_dev_target_r634.sh: rc=0 (70 PASS · REAL-STATE-GUARD PASS 실 상태 그대로 roots=repo:/Users/yoonhwan/Pr)
test_press_permit.sh: rc=0 (35 PASS · REAL-STATE-GUARD PASS 실 상태 그대로 roots=repo:/Users/yoonhwan/Pr)
test_press_role_bts_gate.sh: rc=0 (25 PASS · REAL-STATE-GUARD PASS 실 상태 그대로 roots=repo:/Users/yoonhwan/Pr)
test_press_baseline_check.sh: rc=0 (21 PASS · REAL-STATE-GUARD PASS 실 상태 그대로 roots=repo:/Users/yoonhwan/Pr)
test_nano_spawn_body_press.sh: rc=0 (31 PASS · ALL PASS)
```

## 완료 조건 대조(카드 §구현 범위·§시험 입력)
- ⓐ 빨강(포트 갈래 이전 판 bae6e035d) 슬롯 선언에도 «worker 리스너 없음(:8081)» → 재현 PASS
- ⓑ FT_PORT_BASE 슬롯 3개 실제 리스너(python http.server) → chk 3/3 pid · 갈래 줄 «FT_PORT_BASE=N → gateway N · worker N+1 · 화면 N+2»
- ⓒ FT_PRESS_PORTS 가 FT_PORT_BASE 보다 우선(스텁 호출 기록으로 확인)
- ⓓ 둘 다 없음 = 기본 8080·8081·3001 · 기본 로그 /tmp/byz-worker.log · 기본 SSE 8443 · 기존 출력 바이트 동일(갈래 줄 1줄만 추가)
- ⓔ 반쪽 선언(로그만·SSE만) = 막힘 + «슬롯 선언 회차는 worker 로그·SSE health 주소도 지정»
- ⓕ 잘못된 값(abc·80·70000·3칸 아님·비숫자·65534+2) = 막힘 · 리스너 접촉 0
- ⓖ 변이 2종(worker chk 8081 고정 → ⓑ 죽음 · 반쪽 검사 삭제 → ⓔ 죽음)
- ⓗ 기존 test_press_gate_dev_target_r634.sh 전부 PASS(dev 갈래 출력 불변)
- ⓘ 실 서버·실 8080/8081/3001 접촉 0(슬롯 회차 출력에 그 포트 문자열 0)
- 부하 게이트(r769b · master #146551): 높음→REJECT+상위 3 · 낮음→통과 · 임계 env · 잘못된 값 막힘

## press 필요
- 없음 — 단위·캡처만(이 카드는 press 미발사 · 나노는 쏘지 않는다). 실사건(room tester 러너 발사 PASS · 슬롯 포트 갈래 줄 포함)은 master·tester 좌석 소관.
- 단 부하 게이트가 실 트래픽에서 오탐이 아닌지는 **실 press 회차**에서만 확인된다 — 그 관측은 tester 좌석 회차에 붙인다(필요 시 `press 필요: 부하 게이트 줄이 실회차 출력에 찍히는지`).
