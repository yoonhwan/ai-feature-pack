# 인덱스: 제안서 흐름 ② 도구 3개(카드·슬랙 발행·승인 확인) + magazine_slack 인자화 + 시험 (판정 352)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 352(planner#8 → master#12 발주 · 설계 design/teams/harness/DESIGN-proposal-flow-20261008.md)
- 상태: 대기
- 선행: DA 사전검증 APPROVE(아래) · 문서 나노(proposal-docs)는 선행 아님 — 템플릿 칸은 설계 §2 문자로 가짜 제안서를 만들어 시험
- 시험 입력: 임시 팀 env 디렉터리 · 가짜 제안서 md · 매거진 가짜 Slack 서버(tests/scripts/_magazine_fakes.py) — 실 슬랙 0
- 기준값: 제안서 도구 0 · 매거진 시험 전체 통과 상태(이 카드 뒤에도 그대로여야 함)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(요청 접수 → 사용자 협의 → 개선: 컨펌 게이트) + C(랜딩) + 원문 7(나노 2석 병행). 핵심 한 줄: 판정 352 오빠 원문 「내가 이런식으로 요청하면 나노워커 돌려 기획 및 제안서 작업하고 내가 제안서 읽고 컨펌」 · 「컨펌하면 이슈로 등록하는 과정을 하네스마스터 발주해 추가 랜딩」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오빠가 정한 제안서 흐름(판정 352: 자료 → 팀 나노 제안서 → 슬랙 발행 → 오빠 컨펌 → 승인일 때만 Issue → 구현)을 돕는 도구 3개를 만든다. ①`ft-proposal-card.sh` — 팀 이름·slug·오빠 원문·자료 링크로 그 팀 `design/<팀>/indices/대기/proposal-<slug>.md` 카드를 만든다(팀 env 는 `.fable-team/bin-<팀>/<팀>-env.sh` · ft-nano-spawn.sh:19 와 같은 규칙). ②`byz_proposal_publish.py` — 제안서 md 의 머리줄·결론·오빠가 결정할 것·되돌림 칸을 그대로 뽑아 슬랙 기존 채널에 뿌리 글(첫 줄 `*제안서 <팀>/<slug>*` 정확 일치) + 스레드에 md 첨부, 수정본(rN)은 같은 스레드 답글(첫 줄 `*제안서 <팀>/<slug> rN*` 정확). rN 마다 단계 상태 posting→posted→done 과 «글 쓰기 전 원격 정확 첫 줄 확인·채택», posting+표식 없음 = ERROR·exit 1, posted = 첨부만 재시도(DA HOLD-P2 · 설계 §3 «상태·표식»). 요약 LLM 은 쓰지 않는다. ③`ft-proposal-register.sh` — «제안서 Issue 등록 진입점»: 제안서를 1회 읽어 머리줄 `승인 — 판정 <N>`·Issue 번호 없음·`## 검증` 칸 있음을 확인한 «같은 실행 안에서» 본문을 만들고 Tank 래퍼 create → label 을 부른다. 확인 실패면 Tank 호출 0(DA HOLD-P1). 슬랙 업로드는 매거진 모듈 `magazine_slack.py` 를 재사용하되 content-type 을 인자로 받게 1곳 넓히고, 뿌리 글 찾기를 «정확한 첫 줄» 일반 함수로 뺀다 — 매거진 동작·시험은 그대로. 도구는 키트 bin(scripts/harness-install/fable-team/bin)에 넣지 않는다(드리프트 검사 BLOCK 회피 · 설계 §3).

## 사전검증
- 소환: 예
- DA: design/teams/harness/DA-proposal-flow-20261008.md

## 조사 근거
- 설계 §1 상태 머리줄 · §2 템플릿 칸 · §3 도구 표·배치 · §7 시험 1~4.
- `scripts/harness-install/slack-mirror/magazine_slack.py:46` `find_root` · `:69` `upload_pdf` · `_send_bytes` 의 `Content-Type: application/pdf` 고정.
- `scripts/harness-install/slack-mirror/install-magazine.sh:30` — 복사 목록(REQUIRED)에 `byz_proposal_publish.py` 추가 지점.
- `scripts/harness-install/fable-team/bin/ft-nano-spawn.sh:19` — 팀 env 찾는 규칙(카드 경로의 팀 → bin-<팀>/<팀>-env.sh · 없으면 REJECT).
- `scripts/harness-install/fable-team/bin/ft-index-lint.sh:47` — 사전검증 면제 줄 형식(「면제: <사유> — arch 서명 <좌석명>」 · 좌석 역할 arch).

## 구현 범위 (이 목록만 — 닫힌 목록)
1. `scripts/harness-install/proposal/ft-proposal-card.sh` · `scripts/harness-install/proposal/ft-proposal-register.sh` 신규(Tank 명령은 `FT_TANK_CMD` 로 바꿀 수 있게 — 시험용).
2. `scripts/harness-install/slack-mirror/byz_proposal_publish.py` 신규 · `scripts/harness-install/slack-mirror/magazine_slack.py` 인자화(`_send_bytes(..., content_type)` · `upload_file` · `find_first_line` · 기존 `upload_pdf`·`find_root` 는 1줄 위임) · `scripts/harness-install/slack-mirror/install-magazine.sh` 복사 목록에 1개 추가.
3. 시험 `tests/harness/test_proposal_card.sh` · `tests/harness/test_proposal_register.sh` · `tests/scripts/test_proposal_publish.py`(설계 §7 1~3 · ★장애 주입 전부★).

커밋은 자기 브랜치, **push 금지**. **금지**: 키트 bin·.fable-team/bin 추가·수정 · 매거진 상태기계(magazine_publish.py)·CLI 수정 · 실 슬랙 게시 · ~/.hermes 설치.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_proposal_card.sh` rc=0 · `bash tests/harness/test_proposal_register.sh` rc=0 · `python3 -m pytest tests/scripts/test_proposal_publish.py tests/scripts/test_magazine_render.py tests/scripts/test_magazine_summary.py tests/scripts/test_magazine_publish.py tests/scripts/test_magazine_git.py tests/scripts/test_magazine_cli.py tests/scripts/test_magazine_pdf.py -q` rc=0(매거진 회귀 0).
- `byz_proposal_publish.py <가짜 제안서> --dry-run` 1회: 뿌리 글 텍스트 stdout 복붙.
- 장애 주입 출력 줄 복붙: register 「Tank 호출 0회」 5종 + 「create 1·label 1」 1종 · publish r1 「답글 추가 0」 3종 + 「불명 ERROR」 1종.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/test_proposal_publish.py -q rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: cf1bc2e5321ebc4c000a5530ae54f81da8929585 (spawn 2026-10-08)
- 2026-10-08 — DA HOLD-1 r1 반영(arch#9): check → register 진입점 · rN 단계 상태·표식 · 시험 장애 주입.
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#9 · 판정 352 · 설계 DESIGN-proposal-flow-20261008.md). spawn 은 master 판단 · DA APPROVE 전 lint 실패가 정상.
- 정본 영향 없음: 하네스 도구·슬랙 키트 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 09:16 — 대기→진행 · 좌석 byz-harness-nano-proposal-tools#0
- 2026-10-08 — 완료 독립 검증 (arch#10 · 판정서 §47 초안) — 나노 4bf44359e4(반송 r1: 머리 상태 줄 2개 거부): 시험 96 passed · 셸 2종 ALL PASS · register 확인 실패 Tank 0회 · publish 장애 5종 · 독립 주입 7종 거부.
세트: 4bf44359e495b6d70f4696dcc1066fdb5e251366 · 시험: python3 -m pytest tests/scripts/test_proposal_publish.py -q rc=0 · 이슈: 0
- 2026-10-08 09:33 — 진행→완성 · 좌석 byz-harness-nano-proposal-tools#0 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§47
