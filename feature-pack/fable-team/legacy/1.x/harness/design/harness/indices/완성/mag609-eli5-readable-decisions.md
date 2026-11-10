# 인덱스: 아침 매거진 쉬운 판이 슬랙에서 «그냥 텍스트»로 보이고 결정사항이 번호 덩어리로 묻힘 — 쉬운 판을 PDF 로 붙이고, 첫 장에 핵심 줄·결정 두 박스, 본문 번호 0 (판정 609 · 오빠 직접 지시 10-09 09:2x · planner#15 → master#22 #67313)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 609(오빠 원문 「하네스마스터 발주 매거진이 전혀 eli5 적용 안된 그냥 텍스트 문서임을 공유 핵심과 읽기좋은 내용과 인덱스리스한 문서 작성 결정사항 확실히 노출하도록 개선」)
- 상태: 대기
- 선행: 판정 603(PR 1062 `c3219b677f` · main)
- 시험 입력: 모델 픽스처(`tests/scripts/_magazine_fakes.py` · `tests/scripts/_magazine_detail_fixture.py`)로 `magazine_eli5.build` · `root_text` 를 부른다(LLM 은 가짜 명령 · Slack 게시 0)
- 기준값: 10-09 호(ts 1791504690.518939) 실측 — 쉬운 판 HTML 은 만들어졌고(AI 풀이 124/138) 슬랙에 붙었지만 Slack files.info = `filetype html · mimetype text/plain · preview 있음` → 채널에서 HTML «소스 글자»로 보인다. 쉬운 판 맨 위 「이미 결정된 것」 = 판정 원문 첫 줄 258줄(`판정 96 · [byz-planner-master-claude#9->…] …원문은 PDF D3` 꼴 · 번호·좌석명 그대로). 핵심 줄(요약 3줄)은 슬랙 뿌리 글에만 있고 쉬운 판에는 없다.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: C(배포 발행(슬랙) — 판정 354 「읽기만 해도 이해·빠른 파악·결정사항이 보이는 매거진」이 슬랙에서 실제로 읽히는 형태로 나간다).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
아침 매거진은 판정 354 설계대로 «풀 디테일 PDF + 쉬운 판(eli5) HTML» 한 세트를 슬랙 스레드에 붙인다(`scripts/harness-install/slack-mirror/magazine_publish.py` `publish_day` → `scripts/harness-install/slack-mirror/magazine_attach.py`). 그런데 슬랙은 HTML 파일을 렌더하지 않고 text/plain 미리보기(소스 글자)로 보여 준다 — 오빠가 본 «그냥 텍스트 문서»의 첫 원인이다. 둘째, 쉬운 판 `scripts/harness-install/slack-mirror/magazine_eli5.py` `_decisions` 가 창 안 판정 전부(258)를 원문 첫 줄 80자로 늘어놓아 번호·좌석명이 첫 화면을 덮고, 오빠가 «내린» 결정과 «내려야 할» 결정이 구분돼 보이지 않는다. 셋째, 카드 제목·원문 줄·칩에 판정 번호·R번호·PR 번호·sha 가 그대로 남는다(하드 룰 8 인덱스 금지). 판정 602·603 의 report 모드(형식 미달 경고)와는 무관하다 — 그 단위는 풀 디테일 PDF·뿌리 글에 경고 줄만 더했고 쉬운 판 경로는 손대지 않았다. 풀 디테일 PDF(전 기록)는 그대로 둔다.

## 사전검증
- 소환: ★예 1회(설계 DA · 착수 전) · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료 · arch 서명★ — Q1 슬랙에서 쉬운 판이 «읽히는» 형태인가(PDF 미리보기) · 상태 파일·재첨부 호환 · Q2 결정 두 박스의 출처·필터가 «조용한 누락» 없이 맞는가 · Q3 인덱스 0 검사가 본문에만 걸리고 각주표로 번호가 보존되는가.
- 구현 DA: 아니오(설계 DA 1회 · arch 독립 재현 + 실데이터 dry 로 닫음 — master#22 발주 절차).

## 설계 (닫힌 목록)
1. **쉬운 판 = PDF 로 붙인다**: `scripts/harness-install/slack-mirror/byz_morning_magazine.py` `make_files` 가 쉬운 판 HTML 을 쓴 뒤 기존 `html_to_pdf` 로 `MAGAZINE-YYYYMMDD-eli5.pdf` 를 만들고, `Day.html`(쉬운 판 자리)에 그 PDF 경로를 넘긴다. HTML 파일은 out 폴더에 그대로 남긴다(업로드만 안 함). 쉬운 판 PDF 생성 실패 = 기존 쉬운 판 실패와 같은 경로(경고 줄 + ERROR · 풀 디테일 PDF 는 발행).
   - `scripts/harness-install/slack-mirror/magazine_attach.py`: content-type 을 kind 가 아니라 «파일 확장자»로(`.pdf`→application/pdf · `.html`→text/html). 파일 제목 = kind `pdf` 「아침 매거진 <날짜> 풀 디테일 <rev>」 · kind `html` 「아침 매거진 <날짜> 쉬운 판 <rev>」. 상태 파일 키(`pdf`·`html`)·`--force-file pdf|html`·phase 순서는 그대로(호환).
2. **쉬운 판 첫 장 순서**(`scripts/harness-install/slack-mirror/magazine_eli5_template.html`): ①제목·날짜 ②「오빠가 내려야 할 결정」 박스 ③「오빠가 내린 결정」 박스 ④「24시간 핵심」 3~5줄(= 요약 `summary.lines` 를 그대로 — 새 LLM 호출 0) ⑤닫힌 단위 카드(지금 그대로 + 아래 3) ⑥번호 각주표.
3. **결정 두 박스**(새 파일 `scripts/harness-install/slack-mirror/magazine_eli5_decisions.py`):
   - 「오빠가 내려야 할 결정」 = `model["mbox"]["hil"]`(지금 `오빠 몫` 과 같은 출처) · 0건이면 「지금 기다리는 결정은 없어요」.
   - 「오빠가 내린 결정」 = `model["verdicts"]` 중 원문 첫 줄 «첫 대괄호 머리»(`[ … ]`)에 `오빠` 가 들어간 것만(예 `[판정 345 · 오빠 10-08]`). 나머지(승계 접수·번호 정정·회신 등)는 박스에 안 넣고 박스 끝에 「그 밖의 기록 N건은 풀 디테일 PDF」 1줄(조용한 누락 0).
   - 각 줄은 LLM 1회 묶음 호출로 «쉬운 말 한 줄(70자 이하 · 번호·약어·좌석명 0)»로 다시 쓴다(`scripts/harness-install/slack-mirror/magazine_eli5_batches.py` 의 호출·JSON 검증 방식 재사용 · 금지어 목록은 결정 줄에 적용 안 함). 줄마다 각주 번호 `[n]` 1개 → 각주표에 「판정 N · 원문 첫 줄 80자」. 다시 쓰기 실패(호출 실패·검증 실패) 줄 = 「쉬운 말 풀이 실패 — 원문은 각주 [n]」 + ERROR 로그(조용한 누락 0 · 박스는 그대로 나감).
4. **본문 인덱스 0**(새 함수 · `magazine_eli5_decisions.py` 또는 새 파일 `scripts/harness-install/slack-mirror/magazine_indexless.py`): 쉬운 판 본문(각주표 제외)의 카드 제목·원문 줄에서 `판정 \d+`·`§\d+`·`R\d+`·`#\d+`·`\d+번`·좌석명(`byz-[\w-]+#\d+`)·`[A-Z]\d{1,3}` 축 코드·괄호 안 PR 꼬리를 걷어 내고, 걷어 낸 것은 그 카드의 각주 1줄로 옮긴다. 칩의 sha 10자는 각주로. 렌더 끝에 «본문 인덱스 검사» — 각주표 밖에 위 패턴이 남으면 `Eli5Error`(쉬운 판 실패 경로 · 풀 디테일은 발행).
5. **슬랙 뿌리 글**(`scripts/harness-install/slack-mirror/magazine_slack.py` `root_text`): 안내 문구 「본문은 스레드의 쉬운 판 PDF(먼저 보세요)·풀 디테일 PDF」 · 결정 줄 1줄 「오빠가 내린 결정 N건 · 기다리는 결정 M건 — 쉬운 판 첫 장」. 602·603 경고 줄·이어가기 블록 그대로.
6. 200줄 규칙: 넘는 파일은 나눈다 · 새 파일은 `scripts/harness-install/slack-mirror/install-magazine.sh` REQUIRED 에 추가 + `tests/harness/test_magazine_install_list.sh` 통과.

## 설계 r2 (설계 DA r1 HOLD Q1·Q2·Q3 반영 — 위 설계 1·3·4 를 이 절이 «대체»한다)
- **r2-1 첨부 제목·상태 호환(설계 1 대체)**: kind 키(`pdf`·`html`)·phase·`--force-file` 그대로. 새 제목 = `pdf` 「아침 매거진 <날짜> 풀 디테일 <rev>」 · `html` 「아침 매거진 <날짜> 쉬운 판 <rev>」. ★표식 채택은 «옛 제목(`… PDF <rev>`·`… HTML <rev>`) 또는 새 제목» 둘 중 하나라도 스레드에 있으면 채택(업로드 0)★ — 옛 판 실행이 남긴 sharing/posted/pdf_done 상태에서 이어도 불명 차단이 새로 생기지 않는다. 둘 다 없고 sharing 기록만 있으면 지금처럼 AttachError(불명). 정책: ⓐ같은 날 done = 지금처럼 skip(옛 HTML 그대로) ⓑ옛 판이 HTML 을 이미 붙인 뒤 이어지면 옛 HTML 채택(형식 전환 0) ⓒ`--force`(새 뿌리 글) = 새 형식(쉬운 판 PDF·새 제목) ⓓ`--reattach rN` = 새 형식으로 새 rev(옛 rev 의 HTML 은 스레드에 그대로). content-type 은 확장자로.
- **r2-2 결정 박스 출처·분류 계약(설계 3 대체)**: 판정 줄(`model["verdicts"][*].line` · 수집이 원문 첫 줄 120자로 보관)에서 ★앞머리 전송 접두 `[<보낸이>-><받는이>]`(정규식 `^\s*\[[^\]]*->[^\]]*\]\s*` 를 반복 제거)를 먼저 걷어 낸다★. 그다음 남은 줄의 첫 대괄호 머리에 `오빠` 가 있으면 «오빠 표식 결정»(예 `[판정 345 · 오빠 10-08] …`). 그 밖은 «표식 없는 판정 기록».
  - 박스 제목 = 「오빠가 내린 결정」 + 부제 「판정 머리에 ‘오빠’ 표식이 있는 기록 N건」(분류 기준을 화면에 적는다 — «전부» 라고 쓰지 않는다).
  - «표식 없는 판정 기록» M건 = 박스 끝 1줄 「오빠 표식이 없는 판정 기록 M건 — 끝 각주 목록」 + 각주표 뒤 별 표(번호·원문 첫 줄 · 번호 허용 영역)로 전부 나열(조용한 누락 0).
  - LLM 쉬운 말 한 줄 지시: «원문에 적힌 결정 내용만 옮긴다 · 완료·반영·배포 여부는 원문에 없으면 쓰지 않는다» · 검증 = 70자 이하 + 아래 r2-3 인덱스 검사 통과. 실패 줄 = 「쉬운 말 풀이 실패 — 원문은 각주 [n]」 + ERROR(r1 그대로).
  - 「오빠가 내려야 할 결정」 = `model["mbox"]["hil"]`(r1 그대로) · 같은 쉬운 말 처리.
- **r2-3 인덱스 0 — 토큰·필드·영역(설계 4 대체)**:
  - 토큰(단어 경계 필수 · 이 목록 밖은 손대지 않는다): `판정\s*\d+` · `§\d+` · `(?<![\w-])R\d{1,3}(?![\w.])` · `(?<![\w&])#\d+` · `(?<![\w.])\d+번(?!째)` · 좌석명 `byz-[\w-]+#\d+` · 골 좌표 `(?<![\w-])(?:M[0-7]|K[1-5])(?![\w-])` · 괄호 PR 꼬리 `\(#\d+\)` · 16진 sha `(?<![\w])[0-9a-f]{7,40}(?![\w])`(숫자·글자 둘 다 포함한 것만). 일반 `[A-Z]\d` 패턴은 쓰지 않는다(CO2·B12·UTF8 보존).
  - 적용 필드: 단위 카드 «제목»·«원문 한 줄» 만 걷어 낸다(걷어 낸 토큰은 그 카드 각주 1줄에 원문 그대로 — 오탐이어도 정보 손실 0). 칩의 sha 는 칩에서 빼고 각주로. 결정 줄·핵심 줄은 걷어 내지 않고 «검사만»(LLM 출력이 걸리면 실패 줄 · 요약 줄이 걸리면 그 줄 끝에 각주 번호를 달고 토큰을 각주로).
  - 영역: 렌더가 «본문 문자열»(결정 두 박스·핵심 줄·카드)과 «각주 문자열»(번호 각주표·표식 없는 판정 기록 표)을 따로 만든 뒤 합친다. 인덱스 검사는 본문 문자열에만 건다(DOM 파싱 0). 본문에 토큰이 남으면 Eli5Error(쉬운 판 실패 경로).
- **r2 시험 추가(구현 범위 2·3 에 더함)**: A1 옛 제목 표식 있음 → 채택·업로드 0 · A2 새 제목 → 채택 · A3 둘 다 없음 + sharing → AttachError · A4 `--reattach` 는 html kind 에 PDF·새 제목 · D1 `[a->b] [판정 345 · 오빠 10-08] x` → 오빠 표식 결정 · D2 `[a->b] 승계 접수 …` → 표식 없는 기록 표에 나열 · I1 `CO2 센서 B12 UTF8` 제목 → 그대로 · I2 `판정 602 R63 (#1060) byz-x-claude#3 M5 ab12cd34ef` → 본문 0 · 카드 각주에 전부 · I3 sha 칩 → 각주 · I4 LLM 실패 줄 각주 번호 ↔ 각주표 연결.

## 구현 범위 (닫힌 목록)
1. 위 설계 1~6.
2. 시험(새 파일 `tests/scripts/test_magazine_eli5_decisions.py` · 파일당 120줄 이하 · 넘으면 `tests/scripts/test_magazine_eli5_indexless.py`·`tests/scripts/test_magazine_attach_titles.py` 로 나눔 · r2 시험 A1~A4·D1·D2·I1~I4 포함): E1 내려야 할 결정 2 → 박스 2줄 · 0 → 「없어요」 문장 · E2 내린 결정 = 머리에 `오빠` 있는 것만 + 「그 밖 N건」 줄 · E3 LLM 다시 쓰기 실패 줄 → 실패 문구 + 각주 · ERROR 1줄 · E4 본문 인덱스 검사: 카드 제목 `판정 602 …(#1060)` → 본문엔 번호 0 · 각주표에 남음 · 검사 우회 픽스처(본문에 `R63`)는 Eli5Error · E5 첫 장 순서(내려야 할 → 내린 → 핵심 → 카드).
3. 시험 행 추가: `tests/scripts/test_magazine_eli5.py`(요약 줄 전달) · 첨부 content-type·제목(`tests/scripts/` 의 attach/publish 시험 파일 중 해당 파일 · 없으면 E 파일에) · 뿌리 글 안내·결정 줄.
4. 기존 PASS: `tests/scripts/test_magazine_collect_open.py` · `tests/scripts/test_magazine_malformed_render.py` · `tests/scripts/test_magazine_render_full.py` · `tests/scripts/test_magazine_eli5.py` · `tests/harness/test_magazine_plist.sh` · `tests/harness/test_magazine_install_list.sh`. `tests/scripts -k magazine` 기존 13 실패는 범위 밖 — FAILED 목록이 base 와 같아야 한다(늘면 안 됨).
커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.hermes/` 쓰기·launchd·Slack 게시(시험은 가짜 대상만) · 풀 디테일 PDF 렌더 변경 · 판정 원문 내용 추정(다시 쓰기는 LLM 줄 + 각주 원문 병기).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · arch 독립 재현 + 실데이터 dry-run(쉬운 판 PDF 첫 장에 두 박스·핵심 줄 · 본문 인덱스 검사 통과 · 쉬운 판 PDF 쪽수).
- 카드 증거 줄: `세트: <40hex> · 시험: .venv/bin/python -m pytest --noconftest tests/scripts/test_magazine_eli5_decisions.py rc=0 · 이슈: 0`.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#23 에 `[완료·휴식]` 1통.
- ★랜딩 뒤 master 집행★: install-magazine.sh → 10-09 호 `--force` 재발행 1회 → 슬랙 ts + 쉬운 판 PDF 첫 장 캡처 경로 → planner 보고.

## 원인 확인 기록 (arch#23 · 2026-10-09 · 구현 범위 밖)
- 쉬운 판은 «나갔다»: 상태 파일 10-09 `files.html` = file_id F0C7XBTJKSN · out 폴더 `MAGAZINE-20261009-eli5.html` 221KB · 풋터 「AI 풀이 124/138 · 생략 14(길이 1 · 숫자 1 · 호출 실패 12)」.
- 슬랙 표시: files.info(읽기 전용) — 쉬운 판 `filetype html · mimetype text/plain · preview True` / 풀 디테일 `pdf · application/pdf`. → HTML 은 소스 글자 미리보기.
- 쉬운 판 첫 화면: 「이미 결정된 것」 258줄(그중 머리·본문에 `오빠` 포함 155) · 번호·좌석명·`…원문은 PDF D3` 꼬리.
- report 모드(판정 602·603) 무관: 쉬운 판 경로(`magazine_eli5.build`) 변경 0 · 경고 줄은 풀 디테일·뿌리 글에만.

## 상태
- base_sha: cec1cd82c1b094639ee447440e8d6a38b25ea5dc (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#23 · 판정 609 · master#22 #67313).
- 정본 영향 없음: 하네스 매거진 키트·시험만.
- 2026-10-09 09:47 — 대기→진행 · 좌석 byz-harness-nano-mag609-eli5-readable-decisions#0

## 결과 (나노 RESULT #67554 · arch#23 재현 · 설계 DA r2 APPROVE · master#22 옮김 2026-10-09)
세트: 8dbf61f8a62201ab2042687afd0d9882a76a1f53 · 시험: .venv/bin/python -m pytest --noconftest tests/scripts/test_magazine_eli5_decisions.py rc=0 · 이슈: 0
정본 영향 없음: 하네스 매거진 키트·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 10:32 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§105
