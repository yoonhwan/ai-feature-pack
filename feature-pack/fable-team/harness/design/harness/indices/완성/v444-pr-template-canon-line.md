# 인덱스: PR 템플릿에 «정본» 줄과 «Closes / Refs» 자리 — 랜딩 PR 이 정본 diff 를 같이 싣도록 (판정 444 · 440 설계 r2 §4 순서 3)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 444(오빠 컨펌 · planner#11 #63243 · master#16 #63247) · 판정 440 설계 r2 DA APPROVE
- 상태: 대기
- 선행: 없음 — origin/main 최신에서 브랜치(판정 444 ② · 템플릿은 ops/main-base 와 main 이 같은 바이트) · v444 다른 두 카드와 파일 겹침 0(동시 진행 가능)
- 시험 입력: 없음(문서 1파일) — 렌더 확인은 `gh pr create --dry-run` 없이 파일 diff 로
- 기준값: 지금 템플릿 = 「Closes #」 첫 줄 + 완료 5항 + 로컬 검증 · 정본 자리 0 · 부분 PR(Refs) 자리 0 · 최근 랜딩 5건 Closes 연결 0(440 설계 §1-2)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」.
골의 축: C(업그레이드·반영 — 카드도 Closes 도 없는 직접 PR 의 정본 책임 자리). 핵심 한 줄: 모든 랜딩 PR 본문에 정본 줄 1개와 Closes/Refs 자리를 둔다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
판정 440 설계 r2 는 정본을 «그 변경과 같은 PR» 안에 싣기로 했고, 기계 검사는 카드 완성 이동과 Issue 최종 닫기 두 문에서만 돈다. 카드도 Closes 도 없는 PR 이 바로 merge 되면 기계 검사가 없으므로 그 PR 의 정본 책임은 랜딩한 팀 master 에게 있고, 그 자리가 PR 템플릿이다. 템플릿에 세 가지를 더한다: ①정본 줄 1개 — `정본: docs/architect/<파일>.md §<절>`(이 PR 이 고친 절) 또는 `정본 영향 없음: <이유 ≥10자>` ②첫 줄 규약에 부분 PR 꼴 — 큰 Issue 의 일부면 `Refs #N`(Closes 없음은 오류 아님 · 최종 닫는 PR 만 `Closes #N`) ③완료 항목을 6항으로 — 「정본:」 체크 줄(Issue 닫기 코멘트에 `정본: <X>#<절>@<랜딩 sha>` 로 옮겨 적는다는 안내). 검사는 템플릿이 하지 않는다(사람·좌석이 채우고 검사는 두 문이 한다).

## 사전검증
- 소환: 아니오
- 면제: 판정 440 설계 r2 DA APPROVE(DA 파일 §4 · #63184) 의 §2-3 표 3행 그대로 · 문서 1파일 · 검사·동작 변경 0 — arch 서명 byz-harness-arch-claude#15

## 조사 근거
- `.github/PULL_REQUEST_TEMPLATE.md:1` 「Closes #」 첫 줄 · `.github/PULL_REQUEST_TEMPLATE.md:3` 규약 주석(정본 = ISSUE-TRANSITIONS) · `.github/PULL_REQUEST_TEMPLATE.md:8` 완료 5항 목록.
- `design/harness/DESIGN-landing-canon-440-20261008.md:66` §2-3 한계(카드·Closes 없는 직접 PR = 랜딩 master 책임 · 템플릿 정본 줄) · `design/harness/DESIGN-landing-canon-440-20261008.md:99` §6-3 부분 PR `Refs #N`.

## 구현 범위 (닫힌 목록)
1. `.github/PULL_REQUEST_TEMPLATE.md` 만:
   - 첫 줄 `Closes #` 유지 + 주석에 「큰 Issue 의 일부면 이 줄을 `Refs #N` 으로(최종 닫는 PR 만 Closes)」 1문장.
   - `## 요약` 아래에 `## 정본` 절: `정본: docs/architect/<파일>.md §<절>` / `정본 영향 없음: <이유 ≥10자>` 두 줄 중 하나를 남기라는 자리표시 + 주석 1줄(「worker/·gateway/·shared/ 를 바꿨는데 영향 없음이면 왜 절이 안 바뀌는지를 이유에」).
   - 완료 5항 → 6항: 「- [ ] 정본:」 줄 추가 + 절 제목·안내 문구의 「5항」 → 「6항」 · 「Issue 닫기 코멘트엔 `정본: <X>#<절>@<랜딩 sha>`」 안내.
   - 파일 40줄 이하 유지.

커밋은 자기 브랜치, **push 금지**. **금지**: 다른 파일 수정 · 검사 스크립트·CI 수정 · 템플릿을 여러 개로 나누기(`PULL_REQUEST_TEMPLATE/` 디렉터리 0).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- diff = `.github/PULL_REQUEST_TEMPLATE.md` 1파일 · 위 세 자리 실재(arch 대조) · 「5항」 글자 0(전부 6항).
- 카드 증거 줄 형식(필수 · 문서 전용 꼴 · 없으면 반송): `세트: <40hex> · 시험: 없음(문서) — PR 템플릿 1파일 문서 · 실행 경로 0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 팀 master 들에 1줄 공지(「랜딩 PR 본문 정본 줄 필수 · 부분 PR 은 Refs」).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: cb0d313486ef2652dfcd2d94c27fbd64e8e888dc (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#15 · 판정 444 · master #63247).
- 정본 영향 없음: PR 템플릿 문서만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 16:51 — 대기→진행 · 좌석 byz-harness-nano-v444-pr-template-canon-line#0
세트: 7e1250a3758a7125324b97e9b7396758c3523f52 · 시험: git diff --check origin/main HEAD rc=0 · 이슈: 0
- 2026-10-08 17:19 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§63
