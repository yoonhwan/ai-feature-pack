# DA 요청 — 판정 623 슬랙 팀별 하루 뿌리 글 + 이슈 시작·끝 목록 (arch#23 · 2026-10-09 · ★설계 DA 1회 · 착수 전★ · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료 · arch 서명)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 고정 대상
- 설계 카드 `design/teams/harness/indices/대기/slack623-team-roots.md`(설계 1~8 · 시험 T1~T8) · 기준 코드 origin/main `scripts/harness-install/slack-mirror/` (`mirror_deliver.py` `Deliverer.thread_ts`·`send` · `mirror_lib.py` `thread_key`·`root_text` · `byz_github_slack_mirror.py` `_item` · `byz_mbox_slack_mirror.py` · `mirror_questions.py` · `byz_slack_mbox_inbound.py`).
- 오빠 원문: 「메인팀별 하는일을 하나 공유 … 세부 작업과 상태 메세지를 팀별 이슈 … 하위 스레드로 … 팀별 이슈인덱스 시작과 끝을 알수있게」.
- 실측: 채널 24시간 뿌리 글 207 중 이슈 하나당 뿌리 글 196(키 `#N` 마다 `root_text`).

## 질문 (bounded · 새 요구 금지)
- **Q1 팀 판정 누락 0**: 라벨·좌석 이름 판정 + `기타` + 「팀 라벨 없음」 + 조회 실패 경로가 모든 글을 어느 뿌리 글엔가 넣는가 · 날짜 경계(KST 08:00).
- **Q2 HIL 답글 라우팅**: HIL 질문만 이슈 키 뿌리 글로 남기는 설계 5가 `mirror_questions`·inbound 의 «스레드 1 = 질문 키 1» 가정을 지키는가 · 팀 스레드에 오빠가 답글을 달 때 생기는 일.
- **Q3 목록 정합**: `chat.update` 로 상태 파일에서 통째로 다시 그리는 설계가 실패·재시작·동시 두 프로세스(GitHub·mbox 미러가 같은 팀 뿌리 글을 고침)에서 틀리거나 지워지지 않는가.
- 범위 밖: 매거진·보드·제안서·카드 단위 스레드 · 이슈 생성 경로.

## 판정문
`design/teams/harness/DA-slack623-team-roots-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD(HOLD 면 «설계 몇 번을 어떻게» 1줄) · 끝 줄 APPROVE 또는 HOLD.

## r2 (설계 DA r1 HOLD Q2·Q3 → arch 정정 · 카드 «설계 r2» 절)
- r2-A Q2: `key`(질문·close 계약) 와 `post_key`(게시 스레드) 분리 · HIL 은 post_key=원래 key(등록·게시 thread_ts 동일) · 팀 스레드 오빠 답글 = planner 만(좌석 추정 0) · 시험 T5a~c.
- r2-B Q3: 이벤트 id 멱등 상태 + 공용 flock 1개 안에서 읽기→반영→원자 저장→팀·planner 전체 다시 그림·update · 스레드 맵 잠금과 중첩 0 · resume 조기 반환 뒤에도 반영 단계 항상 실행 · 저장 실패 raise · 시험 T9~T11.
- 질문: **Q2·Q3 이 r2 로 닫히는가만**(새 요구 금지). 판정문 = 같은 DA 파일 «r2» 절 · 끝 줄 APPROVE|HOLD. 2번째 HOLD 면 리뷰 종료 · arch 서명.
