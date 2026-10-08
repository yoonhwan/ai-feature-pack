# 인덱스: ft-index-move --da 절-카드 대조 — §N 정확 일치 + 그 절에 카드 이름 실재 (R37 · master 실례 #63005)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R37(master#15 #63005 고백 · arch 제안 #63013 · master 접수 #63022 · 우선 낮음)
- 상태: 대기
- 선행: 카드 2(result-reply-close-gate) 의 ft-index-move 슬랙 단계 랜딩(같은 파일 · 그 뒤 HEAD 에서 브랜치)
- 시험 입력: 임시 git 리포 + 카드 픽스처 + 판정문 픽스처(§5 · §57 · §58 절 · 카드 이름 있음/없음) — 실제 indices·판정서 쓰기 0
- 기준값: master 가 v436 카드를 `--da …#§60`(카드2 판정 절)으로 완성 이동 → 통과(절에 「닫힘」 글자만 확인). 또 절 찾기가 `index($0, s)` 라 `§5` 가 `§57`·`§58` 헤더에도 걸림(접두 충돌 · 소스 :30)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 6-b(개선요청 접수 — master 실례에서 나온 R37). 핵심 한 줄: 카드를 닫는 판정 인용이 «그 카드를 닫은 절» 일 때만 완성 이동을 허용한다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
ft-index-move.sh 의 진행→완성 문은 `--da <판정문>#§N` 을 받아 ①파일 실재 ②§N 을 포함한 `## ` 헤더 절 실재 ③그 절에 「닫힘」/「CLOSE」 글자 — 셋만 본다. 그래서 다른 카드를 닫은 절을 인용해도 통과한다(master 실례: v436 → §60). 또 절 찾기가 «포함» 비교라 `§5` 를 주면 `§57`·`§58` 헤더도 같은 절로 잡혀 엉뚱한 본문의 「닫힘」으로 통과할 수 있다. 이 카드는 두 가지만 막는다: 절 번호는 «정확 일치»(§N 뒤가 숫자가 아님), 그 절 본문(헤더 포함)에 이동하는 카드 파일 이름(확장자 뺀 basename)이 글자로 있어야 한다. 판정서 초안 꼴(design/harness 판정서 §58~§61)은 이미 절 끝에 `진행→완성: ft-index-move.sh …/<카드>.md` 줄을 싣고 있어 지금 쓰는 경로는 그대로 통과한다. 다른 팀의 과거 판정 절이 카드 이름을 안 실었을 수 있어서, 바꾸기 전에 지금 완성/ 카드들의 기록된 DA 인용을 새 규칙으로 «재판정만» 해 통과율을 RESULT 에 낸다(되돌림 판단용 · 이미 닫힌 카드는 안 움직임).

## 사전검증
- 소환: 아니오
- 면제: 검사 문 1곳 강화(통과 조건 축소만 · 새 동작 0) · 기존 경로 재판정 표로 영향 확인 · master 접수 #63022 — arch 서명 byz-harness-arch-claude#14

## 조사 근거
- `scripts/fable-team-bin/ft-index-move.sh:27`~`:32` DA 검사(파일·절·닫힘 글자) · `:30` awk `index($0,s)>0` 포함 비교(접두 충돌).
- `scripts/fable-team-bin/ft-index-move.sh:93` close 원장 행(`id`·`da`) · `:103` 카드 끝 이동 로그 줄 `· DA <인용>` — 재판정 입력.

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-index-move.sh`(+ `scripts/harness-install/fable-team/bin/ft-index-move.sh` 사본) 진행→완성 DA 검사:
   - 절 찾기 = `## ` 헤더 안의 `§N` 이 정확 일치(`§N` 바로 뒤가 숫자가 아님 · 예 `§5` ≠ `§57`). `§` 없는 절 이름(예 `HOLD-I1`)은 지금처럼 포함 비교 유지.
   - 절 본문(헤더 줄 포함)에 카드 basename(`.md` 뺀 이름)이 없으면 REJECT 「<판정문>#§N 은 <카드> 를 닫은 절이 아니다(절에 카드 이름 없음) — 이동 0」.
   - 파일 200줄 이하 유지(넘으면 DA 검사를 `ft-index-move-da.sh` 로 분리 · 같은 두 사본).
2. 재판정 스크립트 없이 시험 안에서: 시험 `tests/harness/test_index_move_da_binding.sh` — ①다른 카드 절 인용 REJECT · 파일 위치 불변 ②`§5` 인용 시 `§57` 절로 통과 0 ③카드 이름 있는 정확 절 = 통과 ④기존 index-move 시험·`test_index_move_slack.sh`·`test_kit_bin_sync.sh` PASS.
3. RESULT 에 재판정 표(읽기만): harness-ops 의 `design/*/indices/완성/*.md` 카드 끝 `· DA <인용>` 줄을 새 규칙으로 판정한 «통과 n / 거부 n · 거부 목록(카드 · 인용 · 사유)» — 파일 이동·수정 0.

커밋은 자기 브랜치, **push 금지**. **금지**: 완성 카드 재이동·수정 · 판정서 수정 · 예외 목록·opt-out 환경변수(게이트 우회 길 0) · 슬랙 단계 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_index_move_da_binding.sh` rc=0 · 기존 index-move 시험·`test_index_move_slack.sh`·`test_kit_bin_sync.sh` PASS · 사본 cmp · bash -n.
- RESULT 에 재판정 표 — 거부 n>0 이면 arch 가 목록을 보고 «판정 절에 카드 이름을 싣는 규칙» 을 해당 팀 판정 꼴에 넣을지 판정(랜딩 전).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_index_move_da_binding.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp · `ft-live-bin-drift-check.sh` OK.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#14 · R37 · master #63022 · 우선 낮음).
- 정본 영향 없음: 하네스 카드 이동 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 — ★합침★ → `design/harness/indices/대기/v444-index-move-canon-landed.md`(같은 파일 · 판정 444 · byz-harness-arch-claude#15) — 이 카드는 spawn 하지 않는다.
- 2026-10-08 18:13 — 대기→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§64
