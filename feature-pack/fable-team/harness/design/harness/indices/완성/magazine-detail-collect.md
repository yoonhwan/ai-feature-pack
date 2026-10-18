# 인덱스: 아침 매거진 풀 디테일 ① 수집 — 구조 모델 새 칸 detail (판정 354)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: #885 추가 단위 → 판정 354(planner#8 → master#12 발주 · 설계 design/teams/harness/DESIGN-magazine-full-detail-20261008.md)
- 상태: 대기
- 선행: DA 사전검증 APPROVE(아래) · ②③ 나노와 병행(접점 = 설계 §3 detail 스키마)
- 시험 입력: 임시 git 리포(2 ref) · 가짜 mbox jsonl · 가짜 gh(subprocess 대체) — 네트워크 0
- 기준값: 구조 모델 11칸 · detail 칸 0 · 매거진 시험 전체 통과(이 카드 뒤에도 그대로)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: C(배포 발행 — 슬랙) + 6-b(오빠 피드백 반영) + 원문 7(나노 3석 병행). 핵심 한 줄: 판정 354 오빠 원문 「하네스마스터 아침 매거진 추가 요청 — 완성 pdf 를 풀디테일로」 + 보강(#61131) 「①풀 디테일 PDF + ②eli5 HTML」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
아침 매거진 PDF 를 «풀 디테일»(24시간 창의 전체 내용 · 요약·절단 0)로 만들기 위해, 기존 구조 모델 11칸은 그대로 두고 새 칸 `detail` 하나를 채우는 수집 모듈을 만든다. 칸 이름·모양은 설계 §3 코드 블록 그대로(②③ 나노와의 계약 — 바꾸지 않는다). 소스는 설계 §2: 여러 ref(`MAGAZINE_REFS` · 기본 origin/main,ops/main-base,origin/feat/v6-realtime-live)의 git 기록만 읽고(작업 트리 0) — 창 안에 완성/ 으로 옮겨진 카드(배경·골좌표·상태 증거 줄·DA 경로), OPS-VERDICTS 의 추가된 § 절 전문, 창 끝 진행/·대기/ 카드, REQUEST-LEDGER 의 닫히지 않은 행, 마지막 줄 HOLD/REJECT 인 DA 파일, NANO-LEDGER 닫힘 줄, BRIEFING·CLOSEOUT 전문, 머지 커밋 본문 전문. mbox 사본에서는 planner 발신 판정 쪽지의 «처음 것» 원문 + relay 전문 파일(/tmp/mbox · 없으면 null) + 「되돌림」 줄. gh 에서는 닫은 이슈의 마지막 댓글. `$BYZ_ROOT/state/*/BREACH.md` 전문. 실패는 전부 MagazineError(반쪽 결과 0 · 없는 ref 도 raise).

## 사전검증
- 소환: 예
- DA: design/teams/harness/DA-magazine-fulldetail-20261008.md

## 조사 근거
- `scripts/harness-install/slack-mirror/magazine_collect.py:16` — collect() 가 11칸을 조립하는 곳(detail 칸 1줄 추가 지점).
- `scripts/harness-install/slack-mirror/magazine_collect_git.py` — git 실패 = MagazineError · `git fetch origin main` + `git log origin/main` 만 쓰는 원칙(작업 트리 0).
- `scripts/harness-install/slack-mirror/magazine_collect_mbox.py:94` — collect_mbox · PREFIX_RE · planner 발신 판정 줄(VERDICT_RE) — D3 는 같은 규칙에 «본문 전문»만 더한다.
- `scripts/harness-install/slack-mirror/magazine_collect_gh.py` — gh 읽기 전용 · LIMIT raise 원칙.
- 설계 §1 절 표 · §2 소스 매핑 · §3 스키마 · §9 시험 1·2.

## 구현 범위 (이 목록만 — 닫힌 목록)
1. `scripts/harness-install/slack-mirror/magazine_collect_detail.py` 신규(git 소스 D1·D2·D4·D6·D7·부록) · 200줄 넘으면 `magazine_collect_open.py` 로 D6 분리.
2. `scripts/harness-install/slack-mirror/magazine_collect_decisions.py` 신규(D3) · `scripts/harness-install/slack-mirror/magazine_collect_gh.py` 에 닫은 이슈 마지막 댓글 함수 1개 · `scripts/harness-install/slack-mirror/magazine_collect.py` 에 detail 칸 조립 + `refs`·BYZ_ROOT 인자.
3. 시험 `tests/scripts/test_magazine_collect_detail.py` · `tests/scripts/test_magazine_collect_decisions.py` · `tests/scripts/_magazine_fakes.py` 에 `DETAIL_FIXTURE`(설계 §3 모양 1벌).

커밋은 자기 브랜치, **push 금지**. **금지**: render·pdf·publish·slack·CLI 수정 · 실 슬랙·실 gh 쓰기 · ~/.hermes 설치.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `python3 -m pytest tests/scripts/test_magazine_collect_detail.py tests/scripts/test_magazine_collect_decisions.py tests/scripts/test_magazine_collect_mbox.py tests/scripts/test_magazine_collect_git.py tests/scripts/test_magazine_collect_gh.py -q` rc=0.
- 실자료 1회: `collect("2026-10-08", …)` 의 detail 칸별 건수 출력 복붙(units · verdict_sections · decisions · open.cards · open.requests · holds · breaches · seats_closed · appendix) — 0 인 칸은 이유 1줄.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 이유 칸에 가운뎃점 금지): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/test_magazine_collect_detail.py -q rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: f51e3c53d5e2d50b21192352bbbf369037ea85c0 (카드 작성 시점 · spawn 때 갱신)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#10 · 판정 354). spawn 은 master 판단 · DA APPROVE 전 lint 실패가 정상.
- 정본 영향 없음: 하네스 슬랙 키트 수집 모듈·시험만이고 docs/architect 제품 정본 변경 없음.
- 2026-10-08 09:27 — 대기→진행 · 좌석 byz-harness-nano-magazine-detail-collect#0
- 2026-10-08 — 완료 독립 검증 (arch#10 · 판정서 §48 초안) — 나노 fe1ff62a56(반송 r1: merge_bodies 881→35): 시험 96 passed · 실자료 31초 · units 72 · merges 35=본문 35.
세트: fe1ff62a565f32a32d6ce947a9464cc61f525f59 · 시험: python3 -m pytest tests/scripts/test_magazine_collect_detail.py -q rc=0 · 이슈: 0
- 2026-10-08 09:46 — 진행→완성 · 좌석 byz-harness-nano-magazine-detail-collect#0 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§48
