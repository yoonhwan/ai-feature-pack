# 인덱스: 아침 매거진 ② eli5 쉬운 판 HTML 1장 — 템플릿 + JSON 칸 (판정 354 · codex 좌석)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: #885 추가 단위 → 판정 354(planner#8 → master#12 발주 · 보강 #61131 · 설계 design/harness/DESIGN-magazine-full-detail-20261008.md)
- 상태: 대기
- 좌석: codex(`--agent codex` · 시각 작업 = GPT 좌석 규칙)
- 선행: DA 사전검증 APPROVE(아래) · ①② 나노와 병행(접점 = build 함수 시그니처 · detail 픽스처)
- 시험 입력: detail 픽스처(설계 §3 모양 — 자기 시험에 복사) · 가짜 LLM 명령(고정 JSON 출력 스크립트) — 네트워크 0
- 기준값: eli5 판 0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: C(배포 발행 — 슬랙) + 6-b(오빠 피드백 반영) + 원문 7(나노 3석 병행). 핵심 한 줄: 판정 354 오빠 원문 「하네스마스터 아침 매거진 추가 요청 — 완성 pdf 를 풀디테일로」 + 보강(#61131) 「①풀 디테일 PDF + ②eli5 HTML」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오빠가 아침에 «읽기만 해도 바로 이해되는» 1장짜리 HTML 매거진을 원한다(보강 #61131: 첫 화면 「오늘의 결정사항」 박스 · 단위별 그림 설명 1~3줄 · 재미 요소 = 비유·아이콘 · 과장 0 · 번호 각주표 맨 끝). eli5 스킬(`~/.claude/plugins/cache/claude-community/eli5/<버전>/skills/eli5/SKILL.md` · 가장 높은 버전 · 없으면 raise)의 본문을 프롬프트에 넣고, LLM 은 «JSON 칸만» 채운다: `{"units":[{"ref","icon","analogy","lines":[1~3]}]}`(headline·decided 칸 없음 — DA r1 F3). 형식 검사(어긋나면 Eli5Error · 보조 필터일 뿐 의미 검증 아님): ref 는 model.detail.units[].path 에 실재·중복 0 · icon 은 허용 목록(약 20개 이모지 고정) · 줄 ≤ 80자 · 숫자·sha 금지 · 상태·권한 단어 차단 목록(완료·해결·승인·배포·결정·전부·모두·필요 없·안전 등 모듈 상수). ★영역 분리가 과장 방지의 본체★: 사실 영역(LLM 0) = 머리말 템플릿(닫힌 일 N건·결정 M건·오빠 몫 K건) · 결정 박스(왼쪽 오빠 몫 = model.mbox.hil 그대로 · 오른쪽 이미 결정된 것 = 판정 N + verdicts[].line scrub) · 단위 카드의 제목·팀·상태 칩·닫는 증거 칩(sha 앞 10자)·원문 줄(why 첫 문장). AI 풀이 영역 = 단위 카드 안 별도 상자(머리 「AI 풀이 — 정본은 옆 원문 줄」 · 흐린 배경·기울임) 에만 LLM 비유 1줄 + 풀이 1~3줄. 화면 바닥 1줄 「AI 풀이는 형식만 검사했어요 · 결정·상태는 PDF·원문이 정본」. HTML 은 템플릿 1개(인라인 CSS · 외부 스크립트·글꼴 0 · 모바일 폭)에 값만 넣고 전부 html.escape — LLM 이 쓴 HTML 은 싣지 않는다. 시각 디자인(색·배치·아이콘 크기·카드 모양)이 이 카드의 몫이다. 호출 = `magazine_summary.run_cmd`(요약과 같은 헤드룸 cc 경로).

## 사전검증
- 소환: 예
- DA: design/harness/DA-magazine-fulldetail-20261008.md

## 조사 근거
- `scripts/harness-install/slack-mirror/magazine_summary.py:87` run_cmd(cmd, prompt, timeout) · `:104` summarize_model — 같은 LLM 경로와 실패 문구 방식.
- `scripts/harness-install/slack-mirror/magazine_emit.py` — html.escape 원칙(미검증 mbox 본문 · <script> 무력화).
- `scripts/harness-install/slack-mirror/magazine_render.py:151` render · `_notes` — 각주표 notes 모양(dict[int, (종류, 제목, 상태)]).
- 설계 §5 · §9 시험 7.

## 구현 범위 (이 목록만 — 닫힌 목록)
1. `scripts/harness-install/slack-mirror/magazine_eli5.py` 신규 — `build(model, notes, cmd) -> str` · `class Eli5Error(RuntimeError)` · 프롬프트·JSON 검사·템플릿 채우기.
2. `scripts/harness-install/slack-mirror/magazine_eli5_template.html` 신규.
3. 시험 `tests/scripts/test_magazine_eli5.py` 신규(설계 §9 7 전부).
4. 기존 `scripts/harness-install/slack-mirror/magazine_summary.py`(run_cmd) · `scripts/harness-install/slack-mirror/magazine_render.py`(notes 모양)는 import 만 — 수정 0.

커밋은 자기 브랜치, **push 금지**. **금지**: 다른 매거진 모듈 수정 · 실 LLM·실 슬랙 호출을 시험에 넣기 · ~/.hermes 설치.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `python3 -m pytest tests/scripts/test_magazine_eli5.py -q` rc=0.
- 픽스처 + 가짜 LLM 으로 만든 HTML 1개를 Chrome 폭 390px·1280px 스크린샷 2장(경로 복붙) — 첫 화면에 결정 박스 2칸이 보여야 함.
- 실 LLM 1회(픽스처 모델 · 기본 DEFAULT_CMD): 검사 통과 여부 + 생성 HTML 경로 복붙(실패면 Eli5Error 문구 복붙).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 이유 칸에 가운뎃점 금지): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/test_magazine_eli5.py -q rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: f51e3c53d5e2d50b21192352bbbf369037ea85c0 (카드 작성 시점 · spawn 때 갱신)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#10 · 판정 354). spawn 은 master 판단(--agent codex) · DA APPROVE 전 lint 실패가 정상.
- 정본 영향 없음: 하네스 슬랙 키트 eli5 모듈·템플릿·시험만이고 docs/architect 제품 정본 변경 없음.
- 2026-10-08 09:27 — 대기→진행 · 좌석 byz-harness-nano-magazine-eli5-html#0
- 2026-10-08 — 반송 r2(arch#10 #61262 · 설계 §5-b · DA §r2 APPROVE): 실자료 72단위 한 번 호출이 차단 단어·timeout 으로 전체 실패 → 12개 묶음·단위별 보이는 생략·AI 풀이 0건일 때만 Eli5Error.
- 2026-10-08 — 반송 r3(arch#11 #61342 · 실측 묶음당 63~140초 · 한도 400초에서 AI 61/72 · 생략 11 · 230.6초): 호출 실패 36 = 90초 한도 초과 → TIMEOUT 90→180 + 시험 174행만. 단위별 생략은 §5-b 계약대로.
- 2026-10-08 — r3 완료(d5595d3e32 · TIMEOUT 180) · arch#11 재현: 시험 46·128 passed · 실자료 HTML 사실 카드 72 · AI 풀이 67 · 생략 칩 5 · 바닥 줄 일치 → 판정서 §49 초안.
세트: d5595d3e32d94d880ca81f30fd9f7663c726ed8f · 시험: python3 -m pytest tests/scripts/test_magazine_eli5.py -q rc=0 · 이슈: 0
- 2026-10-08 10:18 — 진행→완성 · 좌석 byz-harness-nano-magazine-eli5-html#0 · DA design/harness/OPS-VERDICTS-20261006.md#§49
