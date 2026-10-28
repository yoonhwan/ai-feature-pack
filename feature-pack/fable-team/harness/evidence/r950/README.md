# r950 증거 — 위성 나노 남김(park) 시한 · 고아 계획(reap)

카드: design/harness/indices/진행/r950-sat-nano-park-expiry-reap-plan.md (BYZ-Agents harness-ops)
팩 브랜치: nano/r950-sat-nano-park-expiry-reap-plan (base = 팩 origin/main 643d2bfe)
바뀐 파일: feature-pack/fable-team/harness/bin/{ft_sat_nano.py, ft_sat_gate.py} + kit/fable-team/bin 짝 사본 2 + 이 시험 1
  (ft_sat_rt.py·ft-sat-nano.sh·기존 시험 0줄 수정)

## 왜
위성 팀장이 나노를 «남기기» 로 정할 수 있는데 남긴 나노에 시한이 없으면 mini 의 상한 3 자리를 영영 차지한다.
그래서 남김 = 30분(연장 1회 · 총 60분) 시한을 명부에 적고, 만료 뒤 sweep 1회가 기존 close 경로로 닫는다.
명부 밖 세션·오래된 OPEN 은 도구가 지우지 않고 «지울 계획 파일»(.sh.hil)만 남겨 사람 판단으로 넘긴다(kill 0).

## 명령 추가(r950)
    park <slug> <분> [--extend]   남김 시한 · 분 = 1~30 · 연장은 PARKED 줄에 1회뿐 · 총 60분 상한 · 원격 호출 0
    park --sweep                  만료(expire_epoch ≤ 지금) 지난 PARKED 만 · 기존 close 경로(조회→kill 확인→장부 삭제)
                                  성공 = 원장 close 1줄 «만료 자동 닫음» · 실패 = 명부 «닫기 실패» + 원장 close 1줄 «닫기 실패: …»(상태 유지 · 다음 sweep 재시도)
    reap                          명부 ↔ mini tmux ls 대조 → <상태 폴더>/reap-<시각>.sh.hil 1장만 씀 · kill 0
                                  후보 = 명부 밖 byz-satnano-nano-* · 끝난 지 60분 넘은 OPEN
상한(ⓒ): gate.LIVE = OPENING + OPEN + PARKED — 남김도 자리를 차지하므로 상한에 센다.

## 시험 = tests/test_sat_nano_r950.sh (원격 대역 · 실 mini 0 · 실 tmux 0 · FT_NOW 고정)
| 칸 | 무엇을 보나 |
|---|---|
| ⓐ | park 30 → 명부 PARKED·만료 = 지금+30분 · 만료 전 sweep 닫힘 0 · 만료 뒤 sweep = close 경로 1회 + 원장 «만료 자동 닫음» 1줄 + 장부 줄 삭제 |
| ⓑ | 연장 1회 OK(총 60분) · 2회째 rc2 · 31분 이상 rc2 · 0분 rc2 · OPEN 에 --extend rc2 · 없는 slug rc2(원격 0) |
| ⓒ | PARKED 도 상한 3 에 셈 — 남긴 둘 + 열린 하나 → 4번째 open rc8 · 원격 0 |
| ⓓ | reap = 계획 파일만 · kill 0 · 명부 밖 세션 + 오래된 OPEN · 후보 0 = 파일 0 · 원격 조회 실패 rc5 |
| ⓔ | 닫기 실패 → 명부 «닫기 실패» + 원장 1줄 + 장부 유지 · 다음 sweep 재시도로 닫힘(조용한 성공 0) |
| ⓕ | 기존 시험 test_sat_nano_r949.sh ALL PASS (그 안에서 r902 · test_satellite_rosters · 공용 pytest 가 함께 돈다) |
| ⓖ | 변이 4종 = 만료 검사 끔 → ⓐ / 연장 횟수 검사 끔 → ⓑ / 총 시한 60분 검사 끔(60→90) → ⓑ / reap 이 kill 하게 → ⓓ (칸 이름 단언) |
| 정적 | 짝 사본 cmp0 4종 · /bin/bash -n |

## 파일
- 01-red.txt   : 구현 전(하위명령 없음) = ⓐ~ⓔ 빨강 · r902 는 초록 (빨강 먼저 증거)
- 02-green.txt : 중간 초록 회차(부하 변동으로 ⓕ 가 perf 시험 1건에서 흔들린 회차)
- 03-green.txt : 변이·ⓐ~ⓔ 초록 · ⓕ 는 공용 perf 시험(1MB 200ms)이 부하 50~80 에서 실패한 회차
- 04-green.txt : ⓐ~ⓔ·ⓖ 초록 회차
- 07-green.txt : 반송 r1 반영 회차(ⓑ 총 60분 칸 + ⓖ 변이 4종) — ⓕ 는 r949 안의 r902 ⓡ-1(쪽지 intent 창 · 시간 의존)로 빨강
- 08-noF.txt   : 반송 r1 이 지시한 «ⓕ 뺀» 회차 = FT_R950_SKIP_F=1 timeout 70 → ALL PASS · 단계별 초 칸 ⓐ~ⓔ 1초 · ⓖ 1초 · 총 2초

## 최종 증거 줄의 출처 = 08-noF.txt (ⓕ 는 알려진 한계로 분리 · arch#171 r1 판정: 기준판 origin/main 도 같은 자리에서 멈춘다)

## 알려진 한계
- 공용 시험 tests/scripts/test_ft_secret_shapes.py 의 `*_one_mb_under_200ms*` 는 «벽시계 200ms 상한» 이라
  이 맥의 부하(load average 20~80 · 다른 좌석 claude 세션 다수)에 따라 흔들린다 — 이 카드가 건드린 파일이 아니다
  (ft_secret_shapes.py·시험 파일 diff 0줄). 부하가 낮은 창에서 ALL PASS 확인.
- test_satellite_rosters.sh ⓗ-2 는 살아 있는 spawn 정지·좌석 상태를 읽어 같은 이유로 흔들린다(이 카드 파일 무관).
- reap 은 mini 기본 tmux 서버만 본다(기록 소켓 세션은 대상 아님) — 실제 kill 은 사람 판단(HIL).
- sweep 을 부르는 주기(위성 팀장 틱 10분)는 이 카드 범위 밖이다(planner 지침 소관).
