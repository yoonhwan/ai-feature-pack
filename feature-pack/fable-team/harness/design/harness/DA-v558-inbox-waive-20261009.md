# v558 구현 DA — r1
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 7a6d8f4152 · 고정 Q1~Q2 · 라이브 79건 집행 제외.

- Q1 APPROVE — cmd_waive는 판정번호 사유를 검증하고 선택 좌석 계보 qpath의 잠금 안에서 전체 early/hit 목록을 먼저 계산한 뒤 mark 있음·아직 열림·ts<cut인 줄에만 waived를 한 번 저장합니다(ft-inbox.py:134-147). reported 쓰기 0, 경계 이후/mark 없음/기존 닫힘은 제외됩니다. aware-naive 충돌·깨진 cutoff/행 ts는 저장 전에 예외이며 main은 waive 오류 rc2로 반환합니다(:189-190). 메모리 대역으로 정상·무판정·깨진 cutoff·aware cutoff/naive 행·깨진 후속 행의 5 시나리오를 독립 확인(오류 시 write 호출 0).
- Q2 APPROVE — waived 없음/None에서는 술어가 옛 식과 정확히 같습니다(ft_inbox_core.py:77-80); mark×7분류×reported×absent/null 56조합을 독립 대조했습니다. group_closed는 여전히 all이므로 면제+열린 줄 묶음은 열린 채 남고 show/archive/보드가 같은 술어를 소비합니다(:83-84; 시험 test_inbox_waive.sh:107-111). 다른 명령의 추가 TypeError catch는 rc1로 유지되고 기존 처리 분기·술어 사용처는 변경되지 않았습니다(ft-inbox.py:189-190).

독립 검증은 고정 SHA의 함수 정의를 메모리 큐·write 대역에 적용한 5+56 cases이며 실제 큐·archive·보드·훅 설치 쓰기 0. arch의 shell 42 PASS/기존64·23·71 및 라이브 복사본79 결과는 보고 증거이며 독립 전체 재실행으로 주장하지 않습니다. 면제 없는 show/archive 골든과 혼합 그룹 fixture도 코드로 확인했습니다.
기존 판정번호 문자열/명시 호출 계약의 구현 승인입니다. 실제 planner 큐 면제·랜딩·등록·설치는 master 책임으로 분리합니다.

APPROVE
