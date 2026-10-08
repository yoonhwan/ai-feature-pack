# DA 요청 — v558 인박스 명시 면제(waived) 구현 검토 (arch#19 · 2026-10-09 · 구현 DA 1회 · bounded 10분 + 정정 10분)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: A(모니터·오빠 요청 — planner 가 읽고 안 올리는 26% · v423b 훅 등록 선행).

## 고정 대상
- 커밋 `7a6d8f4152c74aa48bedd624bc3a61e43f1ede7b`(브랜치 `nano/v558-inbox-waive-backlog` · base origin/main 076f0cc9cd · 5파일 +179 −12):
  `scripts/fable-team-bin/ft_inbox_core.py`(obligation_closed 에 `or line.get("waived") is not None` · 130줄) · `scripts/fable-team-bin/ft-inbox.py`(새 `cmd_waive` · main 분기 · usage · 예외 목록에 TypeError · waive 예외 rc=2 · 192줄) · 키트 사본 2 · 새 `tests/harness/test_inbox_waive.sh`(121줄).
- 카드 `design/harness/indices/진행/v558-inbox-waive-backlog.md`(구현 범위 1~4 · 사전검증 «구현 DA 1회 · Q1~Q2 고정»).
- 증거(arch#19 재현 · origin/main 076f0cc9cd 아카이브 + 나노 diff): test_inbox_waive 42 PASS · test_inbox 64 · test_report_hooks 23 · test_kit_bin_sync 6 · test_board 71 — 전부 rc=0 · 사본 cmp · ruff 0.
  ★독립 변이★: 술어의 waived 항 삭제 → test_inbox_waive FAIL 4(show 잔류 3 · 재실행 멱등 깨짐).
  ★실데이터(라이브 planner 큐 «복사본» · 라이브 원본 md5 불변)★: `waive byz-planner-master-claude#13 --before 2026-10-08T21:38 "판정 558 ④ …"` → `WAIVED 79` · `SKIPPED_NO_MARK 133` · show 334 → 255줄 · 면제 79줄 전부 21:38 이전 · 그중 reported=true 0.

## 질문 (모두 «면제는 판정 번호가 있는 명시 명령으로만 · 면제 없는 줄은 0 변경» 하나의 수락 표로 · 반례는 코드 줄 + 재현 입력)
- **Q1 면제 오적용**: 면제가 ⒜판정 번호 없는 사유 ⒝mark 없는 줄 ⒞다른 좌석(계보) 큐 ⒟`--before` 경계 이후 줄 ⒠이미 닫힌 줄(재기록) ⒡시간대 붙은 `--before`(aware vs naive 비교) · 형식 깨진 ts 줄이 섞인 큐에서 «일부만 쓰고 죽는» 경로로 붙는가. reported 를 true 로 쓰는 경로가 있는가.
- **Q2 면제 없는 줄 불변**: waived 필드가 없는 줄의 obligation_closed · group_closed · show · archive · 보드 미보고 칸(`ft_board_env.py:88` show 줄 수) 결과가 바뀌는 경로가 있는가. 묶음(group)에 면제 줄과 열린 줄이 섞이면 group_closed 가 거짓으로 남는가. 예외 목록에 TypeError 를 넣은 것이 다른 명령의 rc(1)를 바꾸는가.
- 범위 밖(새 요구 금지): 21:38 이전 ⑤⑥·미상 133줄 정리 · v423b 훅 등록 시점 · 미상 분류(R57).

## 판정문
`design/harness/DA-v558-inbox-waive-20261009.md` 에 r1 — Q 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD.
