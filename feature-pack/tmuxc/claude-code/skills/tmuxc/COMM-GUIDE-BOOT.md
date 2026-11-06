# COMM-GUIDE-BOOT — 부팅 필수 17줄 (인덱스판 · 상시 로드 ≤2KB)

> 전문 `COMM-GUIDE.md`는 통째로 읽지 않는다. 절 지도 = `COMM-GUIDE-INDEX.md`(절→줄범위 → `Read offset/limit≤200`). 여기 17줄이 «읽기 전 계약» 전부다.

1. Serena 은퇴 · 탐색=`ci` · grep=로그·문구만 · ci 불가=[긴급] 1통 → 복구까지 rg+Read.
2. 부팅 보고 = 세션명·모델+창·ci 가부 + `adhd=`·`cron=`·`launchd=` → 보고 전 착수 0.
3. 발주=mbox 큐+창 1줄 · 재발주는 `ring <최초 seq>` · send 반복 0 · 3초 busy 확인.
4. mbox: `send <to> <me> "본문"`(3~5줄) · `recv` · `peek` · `relay` · master 로는 집행·사람판정 2종만.
5. 포맷 `[{from}->{to}] 내용` · 화살표는 ASCII `->`.
6. tmux 폴백(쪽지 불가 시)만 · `-l`/`Enter` 별도 호출 · 3회 도달검증 · 보냈다≠도착했다.
7. 금지: prefix 없음 · agent 미실행 pane send(`pgrep -P`=0) · 작업 중 Escape · `❯` 잔류 글자 Enter.
8. «안 보내고 대기» 금지 — 회신은 send 로 마감 · 하위 좌석 질문툴 금지(→`[HIL]`) · 대기 전 3확인.
9. `i-have-adhd` = master·arch·pm·DA·desk · implementer·tester·checker·analyst 0.
10. press 전 버전정합: 기동 > 최신커밋 · redis keep/flush 명시 · hot reload 불신.
11. 설계=architect → DA 반박 → checker 확인 · 산출물 tracked.
12. cmd 세션이면 «Command Code 특이사항» 절만 추가 Read(부팅 3항 다름).
13. 이름 `byz-<팀>-<역할>-<에이전트>#N` · 발신 전 `ft-harness-info.sh seats` 로 현역 확인.
14. 조회 `ft-harness-info.sh map|rules|seats|requests` · 이슈는 오빠 컨펌 전 착수 0.
15. master 손 = 집행만 · 코드·시안·증거 줄 직접 편집 0(코드=나노·설계=arch).
16. 부팅 턴에 15분 틱 1개 · 틱마다 `[정리]` 1통 = 심박 · 20분 끊기면 `[멈춤]`.
17. 남의 pane `❯` 글자 = 자동완성(근거 0) · 판정은 jsonl·`✻ … done` · 유휴 깨우기=Escape 1회→`ring`.
