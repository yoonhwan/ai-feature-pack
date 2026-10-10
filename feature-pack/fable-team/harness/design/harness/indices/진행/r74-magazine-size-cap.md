# 인덱스: 아침 매거진 2부 색인형 + 크기 상한 (R74 · 판정 806 · 채택 판정 812 A안)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R74(planner#20 쪽지 #71258 · 판정 806 · master#25 발주 #71274 · 오빠 채택 판정 812 = A안 · planner #71300)
- 상태: 대기
- 선행: 없음
- 제안서: design/harness/PROPOSAL-magazine-size-cap-20261010.md (§3 A안 상한표가 정본)
- 시험 입력: 기존 fixture `tests/scripts/_magazine_detail_fixture.py`·`_magazine_fakes.py`·`_magazine_eli5_kit.py` 로 만든 가짜 모델 — 실 슬랙·실 LLM·실 매거진 파일 0
- 기준값: 10-10 호 md 12,401줄(2부 12,124줄 · D4 6,141줄) · PDF 339쪽 · 쉬운 판 47쪽(카드 41장) — 상한 없음

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
골의 축: B 「메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의」 + C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행(슬랙) 수신해 반영」. 오빠 직접 요청 판정 806 · 채택 판정 812 · 배포 발행 대상 = 슬랙 아침 매거진.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
아침 매거진(매일 08:00 슬랙 발행)의 2부 «풀 디테일»은 10-08 설계가 «전문 그대로 · 상한 없음»으로 정해서, 전날 일한 양에 비례해 커진다(10-10 md 12,401줄 · PDF 339쪽). 사람이 못 읽고, 좌석이 읽으면 컨텍스트가 터진다. 오빠가 A안을 채택했다(판정 812): 2부 한 건은 «제목 + 3줄 + 원문 위치», 한 절은 40건까지, 넘친 것은 «외 N건 — 원문 위치» 한 줄로 보이게 남기고(소리 없이 버리지 않음 · #0 RULE), 파일 전체에는 마지막 경보선(넘으면 raise)을 둔다. 쉬운 판은 단위 카드 12장까지, 나머지는 제목 목록. 1부 요약판은 바꾸지 않는다. 상한 숫자는 제안서 §3 표가 정본이다.

## 사전검증
- 소환: 아니오
- 면제: 오빠 채택 판정 812 의 상한표를 그대로 옮기는 렌더 단계 변경(수집·발행·1부 무변화) · 시험으로 닫음 — arch 서명 byz-harness-arch-claude#26

## 조사 근거 (live `~/.hermes/scripts/` == `origin/main` 추적본 `scripts/harness-install/slack-mirror/` — cmp SAME 확인 2026-10-10)
- `scripts/harness-install/slack-mirror/magazine_render_full.py:25` `_body`(전문 그대로) · `:33` `_d1_units` · `:41` `_d2_verdict_sections` · `:48` `_decision`(본문 + relay 전문) · `:62` `_d4_main`(머지마다 커밋 본문 전문) · `:70` `_d5_issues` · `:79` `_d6_open` · `:113` `_appendix` · `:117`~`:121` `SECTIONS` · `:136` `render_full`.
- `scripts/harness-install/slack-mirror/magazine_eli5.py:53` `_units` · `:125`~`:137` `build`(모든 단위에 LLM 풀이 + 카드).
- `scripts/harness-install/slack-mirror/byz_morning_magazine.py:84`~`:97` `make_files`(md 쓰기 · PDF 쪽수 `pages`) · `:108` `report_failure`.
- 설계 원문 `design/harness/DESIGN-magazine-full-detail-20261008.md` §1 「잘라내기·요약 0」 · §4 「쪽 수 상한 없음」 — 이 카드가 판정 812 로 뒤집는다.

## 구현 범위 (닫힌 목록 · 추적본에서 수정 · 나노 브랜치는 origin/main 기준)
1. `scripts/harness-install/slack-mirror/magazine_render_full.py` — 2부 상한.
   - 한 건 본문(`_body` 를 쓰는 곳 전부 + D6 `tail`)은 비어 있지 않은 줄 3줄까지 싣는다. 넘으면 4번째 줄 자리에 `… 원문: <위치>` 한 줄을 넣는다.
   - 원문 위치는 이렇게 쓴다: D1 = 카드 경로 · D2 = 판정서 경로 + `§N` · D3 = relay 전문 경로(없으면 「쪽지 원문」) · D4 = 커밋 sha 앞 10자 · D5 = 이슈 `N번` · D6 = 카드 경로 · BREACH·부록 = 파일 경로.
   - 한 절(D1~D7·부록)은 40건까지 싣는다. 넘으면 그 절 끝에 `외 N건 — 원문: <위치 목록 또는 원문 위치>` 한 줄. N 은 실제로 빠진 건수와 같아야 한다.
   - 상한 숫자는 모듈 상수(`ITEM_LINES = 3` · `SECTION_ITEMS = 40`)로 둔다. 200줄을 넘으면 같은 폴더 새 모듈 `magazine_render_cap.py` 로 상한 함수만 옮긴다.
2. `scripts/harness-install/slack-mirror/magazine_eli5.py` — `build` 에서 단위 앞 12개(`ELI5_CARDS = 12`)만 LLM 풀이(`explain`)와 카드를 만든다. 나머지는 카드 아래 «그 밖의 닫힌 일 N건» 제목 목록(LLM 0)으로 둔다. `stats.total` 은 전체 단위 수 그대로, 풀이 대상 수는 따로 적는다.
3. `scripts/harness-install/slack-mirror/byz_morning_magazine.py` — `make_files` 에서 md 1,500줄 또는 120 KB 초과, 또는 풀 디테일 PDF 40쪽 초과면 raise 한다(`MagazineSizeError` · 메시지에 실제 값과 상한). 기존 실패 경로(`report_failure` → 슬랙 실패 알림)를 그대로 탄다.
4. 시험 `tests/scripts/test_magazine_size_cap.py`(새 파일):
   - ①큰 가짜 모델(머지 200 · 판정 300 · 열린 카드 250 · 본문 각 50줄)로 렌더하면 md 1,000줄 이하이고, 각 절에 `외 N건` 줄이 있고 N 이 정확하고, 어떤 한 건도 본문 3줄 + 원문 위치 1줄을 넘지 않는다.
   - ②작은 모델(모든 절 40건 이하 · 본문 3줄 이하)은 변경 전 코드 출력과 md 바이트가 같다. 변경 전 출력은 시험 안에서 origin/main 판 함수로 만들거나 고정 골든 파일로 둔다.
   - ③쉬운 판: 단위 41개 → 카드 12장 + 제목 목록 29줄 · 가짜 LLM 호출 대상 12개.
   - ④경보선: md 상한을 넘게 만든 입력(상수를 시험에서 낮춰서)이면 `MagazineSizeError`.
   - ⑤기존 `tests/scripts/test_magazine_*.py` 와 `tests/harness/test_magazine_*.sh` 전부 PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 1부 요약판(`render()`) 변경 · 수집 모듈(`magazine_collect_*.py`) 변경 · 실 매거진 파일(`~/.hermes/magazine/`) Read·생성 · 실 슬랙·실 LLM 호출 · 라이브 `~/.hermes/scripts` 직접 수정 · `TIMEOUT` 값 변경(별 건).
범위 밖(이 카드 아님): 제안서 §4 의 좌석 읽기 차단 훅. live `~/.claude/hooks/boot-read-gate.sh` 와 추적본(`scripts/harness-install/fable-team/templates/hooks/boot-read-gate.sh`)이 지금 서로 다르다(origin/main 기준 cmp DIFF). 차이를 먼저 맞춘 뒤 별 카드로 연다.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `python3 -m pytest tests/scripts/ -q -k magazine` rc=0 · `bash tests/harness/test_magazine_install_list.sh` · `bash tests/harness/test_magazine_plist.sh` PASS · `ruff check` 변경 파일 0 · 변경 파일 전부 200줄 이하.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/ -q -k magazine rc=0 · 이슈: 0`.
- 새 모듈을 만들었으면 설치 목록(`test_magazine_install_list.sh` 가 보는 목록)에 넣는다.
- 랜딩 뒤 master 집행(카드 밖): 라이브 `~/.hermes/scripts/` 해당 파일 `.bak-r74-<날짜>` 백업 → `cp` → `cmp` · `--dry-run`(재첨부 없이 생성만) 1회로 md 줄 수·PDF 쪽수 확인 · 다음 08:00 호의 md 줄 수·PDF 쪽수를 planner 에 1줄.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 991160ae970c5e6c85133a2b0eb48baae1484750 (spawn 2026-10-10)
대기 — 오빠 채택 판정 812(A안) · master spawn 대기
- 슬랙: C0C6MJGRR89 1791589528.196299

## 결과
(닫을 때 증거 줄)
- 2026-10-10 08:50 — 대기→진행 · 좌석 byz-harness-nano-r74-magazine-size-cap#0
세트: 9b2e0cd8454dbe1e6d53421c3beca61b14e706bc · 시험: .venv/bin/python -m pytest tests/scripts/test_magazine_size_cap.py tests/scripts/test_magazine_render_full.py tests/scripts/test_magazine_pdf.py tests/scripts/test_magazine_eli5.py -q rc=0 · 이슈: 0
- 2026-10-10 — 닫힘: 커밋 75415b2b9a+361f5b8e19[test]+9b2e0cd845 · 73 passed(마스터 재실행) · 라이브 설치 .bak-r74r1-1010 · 10-10 규모 md 1,316줄 · main 랜딩 PR 1178 61384daf80
