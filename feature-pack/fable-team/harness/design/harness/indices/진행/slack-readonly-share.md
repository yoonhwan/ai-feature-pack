# 인덱스: 슬랙 = 읽기 전용 공유판 — 답장 요구 문구 0 · 첫 줄 머리표 4종 · 결정 자리 = 현역 planner 세션 이름(live_planner) · inbound 역할 수신자 @planner (오빠 발주 master#17 #64368 · 판정 497 · 나노 1)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 오빠 발주(master#17 #64368) · 판정 497(r3 스팟 1회 · master #64454)
- 상태: 대기
- 선행: 없음(origin/main 의 `scripts/harness-install/slack-mirror/` 만 고친다)
- 시험 입력: 임시 디렉터리(가짜 `seats-planner.json` · 가짜 inbound 원장 · 가짜 질문 저장소) + 가짜 tmux 스텁(env 로 `has-session` 결과 고정) + 가짜 LLM(요약 함수에 고정 JSON 주입) + 가짜 history(첫 줄 검색용 메시지 목록) — 슬랙 API·실제 tmux·실제 LLM 호출 0
- 기준값: 답장 요구 문구 13(설계 §2) · 결정 자리 = 명부 `_hil_route` 하드코딩(낡은 #11 실측 · `mirror_inbound.py:50-57`) · HIL 카드 「담당」 = 질문 올린 좌석만(`resume_block.py:73`) · `recips=[]` 이면 finished(`byz_slack_mbox_inbound.py:104-113`) · 10-04 이후 slack→mbox 전달 3건

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」.
골의 축: C(배포 발행(슬랙) 수신해 반영) + A(오빠 요청 즉시 검토 — 오빠 원문 「거기서 자꾸 답하라는데 어차피 들을것도 아니고 반영될것도 아니니 작업상황·이슈보고·변경내용·상태를 공유하고 hil이나 인터뷰가 있으면 정확히 어느 세션으로 가거나 플래너 정확한 세션을 알려주는 공유를 중점으로」). 핵심 한 줄: 슬랙에 «답하라»는 글을 내보내지 않고, 결정이 필요한 글에는 지금 살아 있는 planner 세션 이름을 적는다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
슬랙 미러(`scripts/harness-install/slack-mirror/` = 라이브 `~/.hermes/scripts/`)는 9종 메시지를 내보내는데 13곳이 「이 스레드에 답해 주세요」·「Q3 답」·「확인해 주세요」 같은 답장 요구를 쓴다. 오빠는 슬랙에서 답하지 않고(10-04 이후 3건), 결정은 planner 세션의 인터뷰로 한다. 그래서 ①모든 슬랙 글의 첫 줄을 `[작업상황]`·`[이슈보고]`·`[변경내용]`·`[상태]` 중 하나로 시작하고 ②답장 요구 문구를 «내보내기 직전» 결정적 정규식 검사로 막고(LLM 프롬프트만 믿지 않음 · 막히면 대체 문구 + `(요약 문구 교정)` 표시) ③결정이 필요한 글에 `결정 자리: <현역 planner 세션 이름>` 1줄을 싣는다. 현역 이름은 `seats-planner.json` 의 `_master` 를 매번 읽고 tmux 로 살아 있는지 확인한다(하드코딩·`_hil_route` 읽기 0 · 확인 불가면 사유를 그대로 싣고 대체 이름 0 = #0 RULE). 슬랙→mbox inbound 도 같은 함수로 수신자를 정하되, 원장에는 이름 대신 역할 표식 `@planner` 를 저장해 승계 뒤 미전달 건도 현역에게 간다(기존 원장의 옛 planner 이름 항목은 1회 이관 · 이미 보낸 건 재발송 0). 정본 설계 = `design/harness/DESIGN-slack-readonly-share-20261008.md` — ★§4-r2(A·B·C·A-r3·B-r3·D)가 §4·§5 를 이긴다★.

## 사전검증
- 소환: 예
- DA: `design/harness/DA-slack-readonly-share-20261008.md` — r1 HOLD(Q1·Q2·Q3 · Q4 APPROVE) → r2 HOLD(Q1·Q2 잔여 · Q3·Q4 APPROVE) → 판정 497 r3 스팟 1회 → «## r3 판정» APPROVE(A-r3·B-r3 잔여 종료 · byz-harness-da-codex#0 #64467) — arch 서명 byz-harness-arch-claude#17

## 조사 근거
- 설계 `design/harness/DESIGN-slack-readonly-share-20261008.md` §1(9종 생성 위치) · §2(13 문구 파일:줄) · §3(낡은 이름) · §4-r2 A(share_guard·적용 지점·대체·전문 예외·매거진 결정적 줄) · B(@planner·사유 5종·unfinished·토큰·빈 수신자·되묻기 삭제) · C(머리표 행렬·strip_head) · A-r3(정규식 완결 · `\b` 금지 이유) · B-r3(기존 원장 이관 규칙·fixture 4) · D(파일 추가).
- 실측 줄(origin/main = 이 워크트리 사본): `scripts/harness-install/slack-mirror/mirror_inbound.py:50` planner_seat(`_hil_route` 읽음) · `scripts/harness-install/slack-mirror/resume_block.py:73` 담당 = from · `scripts/harness-install/slack-mirror/byz_slack_mbox_inbound.py:104` all(done) — 빈 recips 참 · `scripts/harness-install/slack-mirror/byz_slack_mbox_inbound.py:125` 미완료 재개 루프(B-r3 이관 자리) · `scripts/harness-install/slack-mirror/mirror_lib.py:184` what 요약/first_sentence · `scripts/harness-install/slack-mirror/mirror_plan.py:26` 되묻기 · `scripts/harness-install/slack-mirror/mirror_questions.py:54` 답하는 법 · `scripts/harness-install/slack-mirror/magazine_slack.py:56` find_first_line.
- 줄 수(origin/main): `mirror_lib.py` 192 · `byz_proposal_publish.py` 200 · `byz_thread_post.py` 191 · `byz_mbox_slack_mirror.py` 191 · `byz_slack_mbox_inbound.py` 178 — 200줄 넘으면 새 모듈로 뺀다(아래 1).

## 구현 범위 (닫힌 목록 · 정본 `scripts/harness-install/slack-mirror/` 만 · 아래 파일 이름은 전부 이 디렉터리 안)
1. 새 모듈 `scripts/harness-install/slack-mirror/mirror_share.py`(공용 계약 · `scripts/harness-install/slack-mirror/mirror_lib.py` 가 192줄이라 여기에 둔다): `live_planner() -> (이름|None, 사유)`(사유 5종: 명부 없음·JSON 오류·_master 없음·tmux 실행 실패·세션 없음 · 명부 경로·tmux 명령은 env 로 주입 가능) · `share_guard(s) -> str|None`(`REPLY_ASK` = 설계 A 의 정규식 + A-r3 의 `확인해\s*주` · `(?<![A-Za-z0-9])Q\d+(?!\d)` · 대소문자 무시) · `strip_head(line)`(`^\[(작업상황|이슈보고|변경내용|상태)\] ` 제거) · `decision_line()`(`결정 자리: <이름> (그 세션이 인터뷰를 띄웁니다) · 질문 올린 좌석: <from>` / 확인 불가 문구).
2. 표시 쪽: `mirror_lib.py`(format_row 머리표·what/todo/first_sentence 에 share_guard·대체·`(요약 문구 교정)`·결정 자리 줄·멘션은 결정 자리 줄이 있을 때만 · format_full 머리 줄 · root_text 머리표) · `mirror_questions.py`(선택지 `선택지(참고):` · 답하는 법 줄 0 · 보드 제목·행) · `mirror_summary.py`·`magazine_summary.py`(프롬프트 문구 + deterministic_lines 3번째 줄) · `resume_block.py`·`byz_github_slack_mirror.py`(FACT·`다음:` 줄) · `byz_mbox_slack_mirror.py`(format_gap) · `magazine_slack.py`·`magazine_block.py`·`magazine_reattach.py`(첫 줄 머리표 · find 3함수 strip_head 비교) · `byz_proposal_publish.py`·`byz_thread_post.py`(첫 줄 머리표 · 결정할 것 → 결정 자리 줄 · 첫 줄 검색 strip_head) — 머리표는 설계 §4-r2 C 행렬 그대로.
3. inbound 쪽: `mirror_inbound.py`(수신자 = live_planner · `_hil_route` 읽기 삭제) · `mirror_plan.py`(planner 대신 `@planner` · 되묻기 2문구 삭제 → 원문 그대로 + 해석 실패 1줄) · `byz_slack_mbox_inbound.py`(`_deliver` 가 매 패스 `@planner` 해석 · None 이면 건너뜀(done 아님)+`planner_missing_notified` 1회 · 토큰 `slack:{ts}:@planner` · `attempt["@planner"]` 보낸 이름 목록 · 빈 recips finished 금지+알림 · run_pass 미완료 재개 직전 B-r3 1회 이관 · marker_seen 옛·새 토큰 둘 다).
4. 시험 새 `tests/harness/test_slack_readonly_share.sh`(함수 직접 호출 · 네트워크 0): 설계 §5 시험 ①~⑦ + §4-r2 A·B·C·A-r3·B-r3 가 추가한 시험 전부 — 특히 ①13 문구 출력 0(grep: `답하는 법`·`답해 주세요`·`다시 답해`·`확인해 주세요`·질문 번호) ②가짜 요약 `{"what":"전문을 확인해 주세요","todo":null}` → 교정 표시 ③`Q3`·`Q3에 대해`·`(질문Q12)` 교정 · `FAQ3` 통과 ④live_planner 사유 5종 각각 + 살아 있음 ⑤`_hil_route` 가 달라도 `_master` 사용 ⑥9종+실패·재첨부·inbound 알림 첫 줄 머리표 ⑦머리표 없는 옛 첫 줄과 새 첫 줄이 같은 글로 찾아짐(가짜 history) ⑧inbound: 사유 5종 → 전달 0·unfinished·알림 1회 → 다음 패스 현역 생김 → 1회 전달 · 첫 시도 뒤 이름 변경 → 중복 0 · 빈 recips finished 0 · 원문 바이트 보존 ⑨B-r3 fixture 4(옛 이름 pending→현역 1회 · crash+marker 있음→재발송 0 · crash+marker 없음→현역 1회 · 다른 팀 질문 좌석 이관 0).
5. 기존 시험 PASS: `test_slack_mirror_signature.sh` · `test_index_move_slack.sh` · `test_magazine_plist.sh` · `test_proposal_register.sh` · `test_proposal_register_r2.sh` · `test_proposal_card.sh` · `test_slack_post_guard.sh`(기존 단언이 옛 문구에 묶여 있으면 새 문구로 고치고 RESULT 에 그 diff 를 적는다 — 단언을 지우는 것 0).

커밋은 자기 브랜치, **push 금지**. **금지**: 라이브 `~/.hermes/scripts/` 설치·launchd 재기동(master) · 슬랙 API 호출·실제 발송 · 실제 명부·inbound 원장·질문 저장소 쓰기 · inbound 데몬 끄기·질문 저장소 폐기(설계 §6 오빠 판단) · `_hil_route` 키 삭제(읽기만 끊는다) · 휴면 3종·제품 운영 웹훅 2종 수정(설계 §1 범위 밖).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_slack_readonly_share.sh` rc=0 · 위 5 의 기존 시험 전부 PASS · `ruff check scripts/harness-install/slack-mirror/` 0 · 고친 파일 전부 200줄 이하.
- RESULT 에 ★가짜 HIL 카드 1장의 렌더 결과 전문(첫 줄 머리표 + `결정 자리:` 줄 + 답장 요구 0)★ 과 ★B-r3 fixture 4 출력★ 복붙 — 구현 DA 가 재확인.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_slack_readonly_share.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 `~/.hermes/scripts/` cp + cmp · launchd 미러 3종(mbox·github·inbound) 재기동 · 매거진은 다음 08:00 반영 · 실측 1건(새 HIL 카드 1개 문구 캡처).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 2d051b06b7fbb2b659d8a08c01d68a0c7f5d6d86 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#17 · 설계 §4-r2 · DA r3 APPROVE #64467 · 판정 497).
- 정본 영향 없음: 하네스 슬랙 미러 스크립트·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 20:39 — 대기→진행 · 좌석 byz-harness-nano-slack-readonly-share#0
