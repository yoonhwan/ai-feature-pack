# 인덱스: R63 ㉡ 후속 — ft-index-move 완성 이동 때 증거 검사가 카드 글의 `tests/**` 를 `tests/` 로 잘라 폴더 통째로 훑음(files=2374 · suspect=1216 소음) (원장 R63 · master#20 쪽지 #66610)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R63(㉡ 후속 · 우선 보통 — 차단 0 이라 피해는 소음뿐이지만 소음이 진짜 SUSPECT 를 묻는다)
- 상태: 대기
- 선행: `r63c-evidence-inject-scan` 랜딩(완료 · PR 1043 · main 4c81fa97ad)
- 시험 입력: 임시 리포 + 임시 카드(글에 `tests/**`·`design/**/evidence/**`·실파일 경로·증거 폴더 경로) — 네트워크 0
- 기준값: 라이브 `ft-index-move.sh` 가 r63c 카드 완성 이동 때 `INJECT-SCAN files=2374 suspect=1216`(master#20 실측). arch#20 재현: r63c 카드에서 뽑힌 경로 = 실파일 4 + ★`tests/`(폴더 · 파일 2695)★ — 카드 «구현 범위» 의 `` `tests/**` `` 가 토큰 정규식 `[A-Za-z0-9_./-]+` 에서 `*` 앞에서 잘려 `tests/` 가 되고 `^tests/` 에 맞아 폴더째 넘어간다(`scripts/fable-team-bin/ft-index-move.sh:75`).
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터·오빠 요청 — 오빠 절대지침 감시 장치가 소음 1216줄이면 진짜 주입 흔적이 안 보인다). 핵심 한 줄: 닫을 때 훑는 것은 카드가 «이름으로 가리킨» 파일과 증거 폴더뿐이다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
§92(r63c)로 `ft-index-move.sh` 는 진행→완성 이동 직전에 카드 본문의 경로 토큰을 뽑아 `ft-evidence-inject-scan.sh` 로 훑고 결과를 «출력만» 한다(차단 0). 지금 토큰 거르기(75행)는 «실재하면» 파일·폴더를 가리지 않고 넘긴다 — 그래서 카드 글의 일반 표기 `tests/**`·`design/**/…` 가 최상위 폴더로 잘려 리포 시험 전체가 훑이고, 시험 파일들은 패턴 글자를 정당하게 품고 있어 SUSPECT 가 천 줄 넘게 뜬다. 이 카드는 거르기만 좁힌다: 실재하는 «파일» 은 그대로, «폴더» 는 특정 증거 폴더(`design/<…>/evidence/<이름>`)일 때만. 그리고 검사 도구·그 시험 자신(패턴 글자를 정의하는 파일)은 뺀다.

## 사전검증
- 소환: 아니오
- 면제 사유: 출력 전용 경로의 입력 거르기 축소(차단·종료코드 불변) — 구현 DA 없음 · arch 재현으로 닫는다 — arch 서명 byz-harness-arch-claude#20

## 조사 근거 (main 4c81fa97ad · arch#20)
- `scripts/fable-team-bin/ft-index-move.sh:74-77`: `SCAN_PATHS` = `grep -oE '[A-Za-z0-9_./-]+' "$SRC" | grep -E '^design/.*/evidence/|^tests/|\.(py|sh)$' | sort -u` 중 `[ -e "$WT/$p" ]`.
- r63c 카드 재현: FILE 4(`scripts/fable-team-bin/ft-index-move.sh` · `tests/e2e/realtime_multi_e2e.py` · `tests/harness/test_kit_bin_sync.sh` · `tests/shared/prompts/_real_redis.py`) + DIR `tests/`(2695 파일).
- 시험 `tests/harness/test_evidence_inject_scan.sh`(95줄 · 대조표 10행 = 완성 이동 출력).

## 구현 범위 (닫힌 목록)
1. `scripts/fable-team-bin/ft-index-move.sh` 75행 거르기(+ 키트 사본 cmp 동일 · 줄 수 증가 3줄 이하):
   - 실재하는 «파일»(`-f`) = 지금 조건(`^design/.*/evidence/|^tests/|\.(py|sh)$`)에 맞으면 넘김.
   - 실재하는 «폴더»(`-d`) = `^design/.+/evidence/[^/]+/?$`(증거 폴더 «하나») 일 때만 넘김 — `tests/`·`tests/harness/`·`design/`·`design/x/evidence/` 자체는 0.
   - 제외: `scripts/fable-team-bin/ft-evidence-inject-scan.sh` · `scripts/harness-install/fable-team/bin/ft-evidence-inject-scan.sh` · `tests/harness/test_evidence_inject_scan.sh` · `tests/harness/test_block_destructive_inject.sh`(패턴 글자를 정의·시험하는 파일 — 늘 SUSPECT).
2. `tests/harness/test_evidence_inject_scan.sh` 에 행 추가(200줄 이하):
   - ⑫ 임시 카드 글에 `` `tests/**` `` · `` `design/**/evidence/**` `` · `tests/harness/` → 그 셋으로는 훑는 파일 0(`files=` 가 카드의 실파일 수와 같음).
   - ⑬ 임시 카드에 증거 폴더 `design/x/evidence/run1`(픽스처 · 위반 스크립트 1개) → 그 폴더 훑음 · SUSPECT 1.
   - ⑭ 임시 카드에 `tests/harness/test_evidence_inject_scan.sh` 인용 → 제외(훑는 파일 0).
   - 변이: 폴더 조건을 옛 «실재하면» 으로 되돌리면 ⑫ FAIL.
3. 기존 시험 PASS: `tests/harness/test_evidence_inject_scan.sh`(①~⑪) · `tests/harness/test_index_move_slack.sh` · `tests/harness/test_index_move_canon_landed.sh` · `tests/harness/test_kit_bin_sync.sh` · `bash -n`.
커밋은 자기 브랜치, **push 금지**. **금지**: 차단·REJECT 추가 · `ft-evidence-inject-scan.sh` 수정 · 라이브 FT_BIN 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · 키트 cmp 동일.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_evidence_inject_scan.sh rc=0 · 이슈: 0`.
- 결과 보고에 r63c 카드(`design/harness/indices/완성/r63c-evidence-inject-scan.md`)로 뽑히는 경로 목록 전/후 1줄씩(전 = 파일 4 + `tests/` · 후 = 파일 4 · 제외 대상이면 그만큼 적음).
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN `ft-index-move.sh` cp+cmp · 다음 완성 이동 1회의 `INJECT-SCAN files=` 값이 카드 인용 파일 수 수준인지 확인.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 1f8c7b5740c113aa3c1bf7e95f3cc9a82bb11f80 (spawn 2026-10-09)
- 2026-10-09 02:0x — 대기/ 생성 (byz-harness-arch-claude#20 · 원장 R63 · master#20 쪽지 #66610 관찰 · r63c 카드 재현으로 원인 확정).
- 정본 영향 없음: 하네스 닫기 도구 입력 거르기·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 01:40 — 대기→진행 · 좌석 byz-harness-nano-r63d-index-move-scan-paths#0

## 결과 (나노 RESULT · master#20 옮김 2026-10-09)
세트: 14cd2d03f9522fb4404ae4c79cd683052a2b7ece · 시험: bash tests/harness/test_evidence_inject_scan.sh rc=0 · 이슈: 0
정본 영향 없음: 하네스 도구·시험만 — docs/architect 제품 정본 변경 없음.
