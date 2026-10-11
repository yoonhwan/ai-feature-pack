# DESIGN — R49 질문 보드: 바이트 상한 + 닫는 사건을 planner 인박스로 (byz-harness-arch-claude#17 · 2026-10-08 · master#17 결정 #64702)

## 골 원문 (GOAL-harness 복붙)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: C(배포 발행(슬랙) — 발행물이 거부돼 멈춤) + A(모니터). 원장 R49.

## §1 실측 (2026-10-08 21:1x · 라이브 `~/.hermes`)
| 사실 | 값 | 근거 |
|---|---|---|
| 증상 | mbox 미러 `chat.update ok=false: msg_too_long` 473회 · inbound 6회 · 종료코드 1 반복(슬랙 공유판 설치 전부터) | `~/.hermes/logs/byz_mbox_slack_mirror.err` · `byz_slack_mbox_inbound.err` |
| ★슬랙 실제 거부선★ | 마지막 성공 board_text = 2107자 / **3909 UTF-8 바이트** · 지금 렌더 = 2208자 / **4073 바이트** → 거부선은 3909~4073 바이트 사이(약 4000 바이트로 추정 · 한글 1자 = 3바이트라 글자 수로는 안 보임) | 저장소 `meta.board_text` 와 `render_board` 재계산 |
| 보드 형태 | 평문 `text` 1개(blocks 0) · 열린 질문 «전부»를 한 줄에 이어 붙임(`mirror_questions.py:117-127`) | 코드 |
| 열린 질문 | open 36 · delivered 0 · resolved 1 · 나이 4~17시간 · 질문 좌석 대부분 이미 승계된 옛 이름(cfo#53·#56·#57·#60 …) | 저장소 |
| ★닫는 사건 부재★ | 수명 = add(HIL 카드) → `set_delivered`(슬랙 답장) → `close`(같은 key·같은 좌석 «이름»의 다음 보고 · `delivered_for` 가 state=delivered 만 봄 · `mirror_questions.py:111-114`). 슬랙이 읽기 전용이 된 뒤 delivered 가 생기지 않고, 승계로 좌석 이름이 바뀌면 close 도 안 맞는다 → 무한 증가 | 코드 · 판정 497 |
| planner 인박스 | `ft-inbox.sh`(#929) — 큐 `<FT_ROOT>/.fable-team/state/inbox/<계보>.jsonl` · `show <좌석>` = 정본 술어 obligation_closed 가 거짓인 줄만 · `ingest <seq>` 멱등(이미 있으면 SKIP) | `ft-inbox.py` 머리말 |
| 질문 ↔ 인박스 | 열린 36건 중 인박스 `byz-planner-master-claude.jsonl` 에 있는 것 9(전부 mark 없음) · 나머지 27 = 인박스 도입(seq ≈63200) 전 질문 | 실측 |

## §2 안
### A. 보드 = 건수 + 결정 자리 + 가장 오래된 5건 + 바이트 상한
- 첫 줄: `[상태] 결정 대기 N건 — 결정 자리: <live_planner>`(지금 그대로).
- 목록: 열린 질문을 `asked_at` 오름차순(가장 오래된 것 먼저)으로 최대 5줄 · 줄 = `키 요지(40자) (분)`(지금 줄 형식 그대로) · 남으면 `… 외 n건`.
- `planner 전달됨 M건` 줄도 같은 규칙(최대 5 + 외 n).
- ★상한 = UTF-8 바이트 3500★(거부선 ~4000 의 여유 12%): 줄을 하나씩 붙이며 `len(text.encode("utf-8"))` 로 재고, 다음 줄이 3500 을 넘기면 그 줄부터 `… 외 n건` 으로 접는다. 첫 줄 자체가 3500 을 넘으면(결정 자리 사유가 비정상적으로 김) 첫 줄을 바이트 경계에서 자르고 `…` — 어떤 입력에도 보드 글 ≤ 3500 바이트(불변식).
- 보드에서 빠진 질문은 저장소에서 지우지 않는다(정보 삭제 0 · master 조건).

### B. 닫는 사건 = planner 인박스 정본 술어 (무한 증가를 끊는 쪽)
- 미러 «패스당 1회»(`byz_mbox_slack_mirror.run_pass` 시작 · inbound 도 같은 함수 1회) `mq.close_from_inbox(qpath, inbox_bin, planner_name)`:
  1. 적재: 열린 질문 seq 중 인박스 큐(`<FT_ROOT>/.fable-team/state/inbox/<계보(planner_name)>.jsonl`)에 없는 것을 `ft-inbox.sh ingest <seq>` 로 넣는다(멱등 · 정리 책임을 planner 인박스로 넘김 — 27건 1회 이관 포함).
  2. 판정: `ft-inbox.sh show <planner_name>` 출력의 seq 집합 = 안 닫힌 것. 큐 파일에 «있고» show 에 «없는» seq 만 `close()`(tombstone resolved 로).
  3. 큐 파일에 없는 seq(ingest 실패 · 다른 계보 수신 행 등)는 닫지 않고 `인박스 밖 k건` 을 보드 첫 줄 끝에 붙인다(조용한 정리 0).
- 술어 재구현 0 — 닫힘 판단은 `show` 출력만 쓴다(판정 421·425 계약). 큐 파일은 «있는가»만 읽는다.
- 기존 닫힘 경로(delivered + 같은 key·좌석 다음 보고)는 그대로 둔다 — 두 경로 중 먼저 오는 쪽이 닫는다(close 는 멱등).
- 실패: `planner_name` 이 None(live_planner 확인 불가) · `ft-inbox.sh` rc≠0 · 큐 파일 JSON 오류 → 그 패스는 닫기 0 · stderr `ERROR:` 1줄 · 보드 첫 줄 끝에 `정리 확인 불가(<사유>)` — 명시 플래그 대신 «로그 + 보이는 표시» 이고 보드 갱신·다른 카드 발행은 계속(#0 RULE 예외 조건 중 ERROR 로그·보이는 경고 2개 충족 · 처리 자체는 하지 않으므로 대체 결과 0).

### C. 인자·설치
- 새 인자 `--inbox-bin`(ft-inbox.sh 절대 경로) — mbox 미러·inbound 둘 다. 없으면 시작 시 exit 1(조용한 기본값 0 · `install-github.sh` BYZ_ROOT 선례). installer 2종(`install.sh`·`install-inbound.sh`)이 plist 에 채운다(값은 master 집행 때 FT_BIN 경로).

### D. 부하·메모리 (async_io 규칙의 두 열)
| 항목 | 부하 | 메모리 |
|---|---|---|
| 지금 | 실패하는 chat.update 가 패스마다 1회(5초 주기 · 473회) + 종료코드 1 → launchd 재기동 | 보드 문자열 ~4KB · 저장소 14KB 계속 증가 |
| 안 | 패스당 `ft-inbox.sh show` 1회 + 신규 적재 seq 수만큼 `ingest`(이관 1회 뒤 0~1) · python 기동 ~수십 ms · 보드 글이 같으면 API 0(지금 규칙) | 보드 ≤ 3500 바이트 고정 · 저장소 open 은 닫힘으로 줄고 resolved tombstone(seq→ts) 만 남음 |

## §3 구현 단위 (카드 1장 · 나노 1 · v421 랜딩 뒤 spawn)
- 파일: `scripts/harness-install/slack-mirror/mirror_questions.py`(render_board 상한·5건·외 n · close_from_inbox — 200줄 넘으면 `mirror_board.py` 로 분리) · `byz_mbox_slack_mirror.py`·`byz_slack_mbox_inbound.py`(패스당 1회 호출 · `--inbox-bin`) · `install.sh`·`install-inbound.sh`·plist 템플릿.
- 시험 `tests/harness/test_question_board.sh`(가짜 ft-inbox 스텁 · 가짜 큐 파일 · 슬랙 API 0):
  ①열린 질문 36건(실측 길이의 한글 요지) → 보드 ≤ 3500 바이트 · 가장 오래된 5줄 + `… 외 31건` ②한 줄이 긴 경우·결정 자리 사유가 긴 경우에도 ≤ 3500 ③큐에 있고 show 에 없는 seq → close(resolved) · show 에 있는 seq → open 유지 ④큐에 없는 seq → ingest 1회 호출 · 다음 패스 ingest 0(멱등) ⑤ingest 실패 seq → 닫지 않음 + `인박스 밖 1건` ⑥스텁 rc=1 · planner None · 큐 JSON 오류 각각 → 닫기 0 + `정리 확인 불가(<사유>)` + stderr ERROR + 보드 갱신은 진행 ⑦패스당 show 호출 수 = 1 ⑧`--inbox-bin` 없으면 exit 1 ⑨기존 시험(`test_slack_readonly_share.sh` 외 7종) PASS.
- 랜딩 뒤 master: 라이브 설치 + `--inbox-bin` 기입 · 미러 재기동 · err 로그 msg_too_long 증가 0 확인 · 보드 1회 캡처(바이트 수 함께).

## §4 범위 밖
- planner 가 인박스 27+9건을 실제로 mark 하는 일(planner 몫 — 보드는 그동안 «결정 대기 N건 · 오래된 5»로 보인다).
- resolved tombstone 정리(seq→ts 작은 dict · 지금 1건) — 완성 후.

## §5 DA 질문 (사전 1회 · 10+10분)
- Q1 바이트 상한 3500 + 접기가 «어떤 입력에도 ≤ 3500»을 보장하는가(첫 줄 과대·멀티바이트 경계 포함)?
- Q2 닫힘을 «큐에 있음 ∧ show 에 없음»으로 두는 것이 정본 술어 재구현 0 이면서 잘못 닫기(다른 계보·ingest 실패·show 실패)를 막는가?
- Q3 실패 시 «닫기 0 + ERROR + 보드 표시 + 갱신 계속»이 #0 RULE(조용한 대체 0)과 맞는가?
- Q4 27건을 planner 인박스에 1회 적재하는 것이 «정리 책임 이관»으로 적정한가(인박스 소음 · 이미 처리된 옛 HIL 이 섞임)?

## §2-r2 DA r1 교정 (Q1·Q2 HOLD · Q3·Q4 APPROVE) — §2 와 다르면 이 절이 이긴다
### A-r2. 바이트 예산 = «실제 게시 문자열 전체» 기준 (Q1)
- 잴 대상 = `chat.update`/`post` 에 넘기는 최종 `text`(이스케이프 `lib.esc` 뒤 · 줄바꿈 · 첫 줄 끝 경고(`인박스 밖 k건` · `정리 확인 불가(<사유>)`) · 두 목록(결정 대기 · planner 전달됨) · 접기 표식 `… 외 n건` 전부 포함).
- 절차(`fit_board(parts, cap=3500)`): ①첫 줄(머리 + 경고 suffix)을 만든다 → 그 자체가 `cap − 3`(`…` 3바이트) 을 넘으면 UTF-8 경계에서 `cap − 3` 바이트로 자르고(`encode()[:n].decode("utf-8", "ignore")`) `…` 를 붙인다 — 그 경우 목록 0. ②목록 줄을 오래된 순으로 후보에 넣을 때마다 «그 줄 + 남은 수에 대한 `… 외 n건` 줄» 을 함께 붙인 전체 문자열을 재서 ≤ cap 일 때만 채택(접기 표식 예산을 미리 포함). ③두 목록은 결정 대기 먼저, 전달됨은 남은 예산으로 같은 규칙. ④마지막에 `len(text.encode()) ≤ cap` 단언 — 거짓이면 raise(도달 불가 · 조용한 자르기 0).
- 시험 추가: 최종 바이트 3499·3500·3501 경계 픽스처(3501 쪽은 한 줄이 접혀 ≤ 3500) · 첫 줄만으로 3500 초과(경고 사유 김) → 정확히 ≤ 3500 + `…` · 3바이트 한글이 경계에 걸림(깨진 문자 0 — `decode` 성공) · 두 목록 + 경고 2종 동시 · `&<>` 이스케이프로 길어지는 요지 · 단언 대상 = 슬랙 스텁이 받은 실제 `text`.

### B-r2. show 파싱 계약 — `미닫힘=` 필드만, fail-closed (Q2)
- `ft-inbox.sh show <planner_name>`(비compact)의 정상 출력은 둘 중 하나뿐이다(`ft-inbox.py:70-89`): ①정확히 한 줄 `EMPTY` = 안 닫힌 것 없음(빈 집합) ②줄마다 `^\[[^\]]+\] \S+ seq=[0-9,]+ 미닫힘=([0-9,]*) from=` 꼴.
- 안 닫힌 seq 집합 `U` = 모든 줄의 `미닫힘=` 값 합집합(`seq=` 는 그룹 전체라 쓰지 않는다 — 혼합 그룹(닫힌 A·열린 B)에서 A 는 닫히고 B 는 남는다). `group_closed` 로 줄 자체가 빠진 그룹의 seq 는 U 에 없으므로 닫힌다.
- fail-closed: rc≠0 · 출력 비어 있음 · `EMPTY` 외 줄 중 하나라도 위 정규식 불일치 · `미닫힘=` 값이 숫자 아님 → 그 패스 닫기 0 + `정리 확인 불가(show 출력 해석 실패)` + stderr ERROR(§2 B 실패 경로와 같은 처리 · Q3 APPROVE 범위).
- 닫기 조건은 그대로: 큐 파일(`<계보(planner_name)>.jsonl`)에 seq 가 «있고» ∧ seq ∉ U. 다른 계보 큐로 ingest 된 행은 닫지 않고 `인박스 밖` 으로 남긴다(DA Q4 조건).
- 시험 추가: 혼합 그룹 `seq=10,11 미닫힘=11` → 10 닫힘 · 11 open ┃ `EMPTY` → 큐에 있는 열린 질문 전부 닫힘 ┃ rc=0 인데 빈 출력 / 깨진 줄 1개 섞임 / `미닫힘=x` → 닫기 0 + 경고 ┃ 첫 seq 만 뽑는 잘못된 파서로 바꾸면 FAIL(변이 대조 1건).
