# 인덱스: 카드 lint ⑦사전검증 ⑧조사 근거 — 팀 env 스위치(FT_CARD_REQUIRE_PREVERIFY=1)일 때만
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의). 핵심 한 줄: 원장 R16 — feature master#0 #59567 · 오빠 「arch da 기획 안하고 바로 나노」「조사나 기획 안하고 구현」 — DA 사전검증·조사 근거 없는 카드로 구현 나노가 열렸다. 설계 = design/teams/harness/PLAN-r16-preverify-lint-and-i855-da-20261007.md (A).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
대상은 키트 `scripts/harness-install/fable-team/bin/ft-index-lint.sh`(67행 · 추적본 scripts/fable-team-bin 에는 사본이 없다 · 라이브 RT 와 지금 cmp 동일 — 라이브 설치는 master). 현 검사: ①골 3줄 바이트 ②필수 6절(22행 SECTIONS) ③골좌표 「…」 20자+ 가 원장에 실재 ④배경 .md 인용 ≤ FT_INDEX_MAX_CITES ⑤구현 범위·완료 조건 비지 않음 ⑥구현 범위 경로 1개 이상 실재. 절 본문은 25행 `section_body <파일> <절 이름>` 로 읽는다. ft-nano-spawn.sh 65행이 spawn 때 이 lint 를 부르고 실패면 REJECT 하며, 팀 env(bin-<팀>/<팀>-env.sh)는 그 «전»에 source 된다 → env 스위치가 lint 에 닿는다. 전용 시험 파일은 아직 없다.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. [structure] 먼저(별도 커밋): ⑥의 «경로 실재» 판정을 함수 하나로 추출(동작 무변화 · 기존 출력 바이트 그대로).
2. [feature] `scripts/harness-install/fable-team/bin/ft-index-lint.sh`: `FT_CARD_REQUIRE_PREVERIFY=1` 일 때만 —
   - ⑦ 「## 사전검증」 절 필수. 본문에 「소환: 예」 또는 「소환: 아니오」 1줄 필수. 예 → `DA: <판정문 경로>[#§N]` 줄 + 그 경로가 실재(카드 워크트리 루트 기준 또는 절대경로) + 그 파일에서 «마지막» APPROVE/HOLD/REJECT 단어가 APPROVE(DA 판정 형식은 APPROVE·HOLD·REJECT 셋뿐 — 단어 경계로 뽑는다). 아니오 → `면제: <사유 10자+> — arch 서명 <좌석명>` 줄 + 좌석명을 ft-name-lint.sh 로 검사해 PASS 이고 역할 토막 = arch. 하나라도 아니면 REJECT(사유 1줄씩).
   - ⑧ 「## 조사 근거」 절 필수 + `경로:줄` 1개 이상 — 1의 함수로 경로 실재 + 줄 번호 ≤ 그 파일 줄 수(내용 대조 0).
   - 스위치가 없거나 1 이 아니면 지금 동작·출력 바이트 그대로.
3. `tests/harness/test_index_lint.sh`(신규 · 임시 리포): 스위치 꺼짐 — 기존 OK 카드 OK · 기존 REJECT 사례(골 줄 불일치 1개) 그대로 · 스위치 켜짐 — ⑦ 절 없음 REJECT · 소환 줄 없음 REJECT · 소환 예 + 판정문 없음 REJECT · 판정문 마지막 판정 HOLD(앞에 APPROVE 있어도) REJECT · 마지막 APPROVE OK · 소환 아니오 + 면제 사유 9자 REJECT · arch 아닌 좌석 서명(nano) REJECT · arch 서명 OK · ⑧ 절 없음 REJECT · 없는 경로 REJECT · 줄 번호 > 파일 길이 REJECT · 정상 OK.
커밋은 자기 브랜치, **push 금지**. **금지**: 라이브 FT_BIN·bin-feature 쓰기(env 1줄 추가는 master) · ft-nano-spawn 변경 · 팀 이름 하드코딩 · 다른 검사(①~⑥) 동작 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_index_lint.sh` rc=0 · 기존 `tests/harness/test_*.sh` 는 base 와 같은 결과(base 에서 이미 실패하던 kit_bin_sync·regress_pack 은 그 행만 같으면 무관) · `bash -n` OK.
- ★카드 증거 줄 필수★: 이 파일 「상태」 절에 `세트: <sha> · 시험: <파일> rc=<n> · 이슈: 0` 1줄 + 스위치 켠 dry 출력 2줄(REJECT 1 · OK 1) 복붙 — 없으면 닫지 않는다.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 3f98a8fc3370b78208f298883c7940012353a9ae (spawn 2026-10-07)
- base: 최신 origin/main.
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#6 · 원장 R16 · master#9 #59587).
- 정본 영향 없음: 하네스 lint·시험만 — docs/architect 제품 정본 변경 없음. feature 카드 견본 문구(⑦⑧ 절)는 arch 초안 → master 설치 별건.
- 2026-10-07 19:15 — 대기→진행 · 좌석 byz-harness-nano-r16-lint-preverify#0
- 세트: ebf5e9089f4790524c8da5f8474515795ab4fc5e · 시험: bash tests/harness/test_index_lint.sh rc=0 · 이슈: 0
  - 스위치 켠 dry REJECT: `REJECT bad.md (ledger=design/L.md)` / `  - 절 없음: 사전검증 (⑦)` / `  - 절 없음: 조사 근거 (⑧)`
  - 스위치 켠 dry OK: `OK ok.md (ledger=design/L.md)`
  - 커밋: 01c5e8a7df [structure] · 6eec09b8f0 [feature] · 695e3bff8c [docs] · ebf5e9089f [fix] last_verdict 단어 경계·PASS 삭제 · 기존 tests/harness/test_*.sh 25종 rc=0(최초 실행 시점) · test_index_lint PASS 28 · fail=0
  - 설계 선택: ⑧ 인용은 «전부» 유효해야 통과(스펙 「1개 이상」보다 엄격)
- 2026-10-07 19:26 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§32
