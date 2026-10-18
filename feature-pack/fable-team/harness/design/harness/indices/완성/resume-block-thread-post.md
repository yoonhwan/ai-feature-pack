# 인덱스: 슬랙 이어가기 블록 + 단일 발행 입구 byz_thread_post + 스레드 장부 (판정 404 ② · 카드 1/2)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 오빠 판정 404·405(planner#9 #62157 · master#14 #62159·#62177)
- 상태: 대기
- 선행: 없음(설계 = design/teams/harness/DESIGN-resume-index-20261008.md · 감사 = design/teams/harness/AUDIT-j404-slack-threads-20261008.md)
- 시험 입력: 기존 tests/scripts/_proposal_fakes.py 가짜 슬랙 API 꼴 + 가짜 jsonl·가짜 tmux(PATH 맨 앞 스텁) — 실제 슬랙 호출 0
- 기준값: 감사 표 — 10-08 공유 스레드 6건 중 결과 답글 1 · 제안서 5건 중 4건 손 발행(뿌리 글 2~3개로 쪼개짐) · 미러 꼬리 = 좌석·#seq·전문 경로뿐(이어가기 칸 0)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A 모니터·오빠 요청 + C 배포 발행·반영. 핵심 한 줄: 오빠 「응답시 바로 세션창에서 이어 진행할수있는 인덱스 일반화」 — 모든 슬랙 단위 글에 같은 이어가기 블록 + 한 스레드.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
슬랙(#byz-planner · C0C6MJGRR89 · yoonhwan 봇)에 올라가는 단위 글이 «시작»만 있고 과정·결과가 없다(감사). 원인은 ①제안서를 나노가 `hermes send` 로 손 발행해 본문·md·html 이 각각 새 뿌리 글이 된 것 ②어느 발행 경로에도 결과 답글 단계가 없는 것. 이 카드는 «한 입구 + 한 스레드 + 고정 꼬리»를 만든다: `resume_block.py`(6칸 블록 생성 · 한 곳), `byz_thread_post.py`(start/progress/result/check/repair · 첨부는 같은 스레드 답글), 장부 `~/.hermes/state/byz_threads.json`(키 = 불변 단위 ID), `ft-resume-cmd.sh`(재개 명령 1줄). 그리고 기존 세 발행 경로(제안서 발행·매거진·mbox 미러)에 블록을 붙인다. 카드 이동 때 자동 발송·CLOSE 금지·손 발행 차단 훅은 카드 2(result-reply-close-gate)다. 설계 정본 §2·§3·§8-b 가 계약이다 — 아래 범위는 그 요약.

## 사전검증
- 소환: 예
- DA: design/teams/harness/DA-resume-index-20261008.md

## 조사 근거
- `scripts/harness-install/slack-mirror/mirror_lib.py:79` `post()` — chat.postMessage(thread_ts 선택). `:44` `api_call` ok=false·네트워크 오류 = raise(이 꼴을 따른다).
- `scripts/harness-install/slack-mirror/mirror_lib.py:189` 미러 꼬리 `[from, #seq, 전문 경로]` — 블록 2줄로 바꿀 자리. `scripts/harness-install/slack-mirror/byz_mbox_slack_mirror.py:141` 호출처.
- `scripts/harness-install/slack-mirror/byz_proposal_publish.py:78` `text_of` 뿌리·rN 글 본문 · `:90` `_root_ts` 상태 파일 root_ts · `:83` `find_reply` 첫 줄 표식으로 재발송 방지(«발행 불명» 처리 — result 재실행에 같은 꼴).
- `scripts/harness-install/slack-mirror/magazine_slack.py:40` `root_text` 매거진 뿌리 글 · `scripts/harness-install/slack-mirror/magazine_publish.py:99` `post_root` 호출.
- `scripts/fable-team-bin/ft-index-move.sh:83` 카드 이동 = 같은 파일 이름 git mv(대기/진행/완성) — 파일 이름이 불변 단위 ID 근거.

## 구현 범위 (닫힌 목록 · 설계 §2·§3·§8-b)
1. `scripts/harness-install/slack-mirror/resume_block.py` 신설: `block(issue, card, seat, canon, next_, resume) -> str` 2줄. 6칸 전부 필수 — None·빈 문자열 = raise(값이 없으면 호출자가 문자 `없음`). `canon` 은 `canon_ref(path)` 가 `<경로>@<git log -1 %h>` 로 만든다 — 미커밋·추적 밖 = raise. 문자열은 `mirror_lib.esc` 로 중화.
2. `scripts/fable-team-bin/ft-resume-cmd.sh <좌석>`(+ 키트 사본 같은 바이트): 설계 §2 ①정확한 tmux 세션 이름 → mbox ring 줄 ②좌석표 행 `session_uuid`·`cwd`·`agent` 와 `~/.claude/projects/<cwd 인코딩>/<uuid>.jsonl` 의 sessionId·cwd 일치 + agent=claude → `cd <cwd> && claude --resume <uuid>`(printf %q 인용) ③그 밖 → stdout `없음(좌석 종료 · 확인된 세션 매핑 없음 — 카드 정본으로 새로 연다)` + rc 3. jsonl 본문 이름 검색 0.
3. `scripts/harness-install/slack-mirror/byz_thread_post.py` 신설 + `thread_ledger.py`(장부 읽기·쓰기 분리 · 각 200줄 이하):
   - 장부 키 = `<팀>/<카드 파일 이름(.md 뺀 것)>` · 값 `{channel, root_ts, kind, card_path, progress, results}` · 파일 없음·JSON 손상 = raise(빈 장부 흡수 0) · `--init` 으로만 빈 장부 생성.
   - `start --card <카드> --team <팀> --text … [--file …] + 블록 인자` — ①카드 상태 절에 `- 슬랙: <channel> · 시도 <ISO>` 기록 ②뿌리 글 1개(첫 줄 표식 `[<단위 ID>]`) ③첨부는 그 스레드 답글 ④카드 줄을 `- 슬랙: <channel> <root_ts>` 로 ⑤장부 기록. 장부에 키 있음 = REJECT(그 ts 출력).
   - `progress --card … --text …` · `result --card … --verdict <판정문#§N> [--landed <sha>]`(결과 1줄 = 판정문 §N 제목 줄 그대로 · 첫 줄 `[결과] <단위 ID>` · 재실행 시 스레드에서 그 표식을 먼저 찾아 있으면 장부만 채움 · results 있으면 재발송 0).
   - `check --card …` rc: 0 = 카드에 `- 슬랙:` 줄 없음(미게시) 또는 결과 있음 · 1 = 게시 대상인데 결과 없음 · 3 = 장부 불명(키 없음·root_ts 없음·장부 손상·카드 줄 «시도»뿐) → 메시지에 repair 안내.
   - `repair --card …` = 설계 §3(카드 줄 root_ts → 장부 · «시도»뿐이면 채널 최근 글에서 `[<단위 ID>]` 검색 1건만 복구 · 0·2건+ = 사람 확인 rc 1).
   - `--legacy-root <ts> --bot hermes|yoonhwan --channel <id>`(result 전용 · 소급 1회용 · hermes 토큰 = ~/.hermes/.env SLACK_BOT_TOKEN · 값 출력 0).
   - kind=report 는 이 도구 인자로 지정 불가(매거진 발행기만 장부 API 로 부여 · 키 `magazine/<날짜>`).
4. 기존 경로에 블록 연결(동작 변경은 꼬리 추가뿐):
   - `scripts/harness-install/slack-mirror/byz_proposal_publish.py`: 뿌리·rN 글 끝에 블록 · 새 인자 `--card`(필수) → 장부에 root_ts 기록 + 카드 `- 슬랙:` 줄(start 와 같은 선기록 순서). 상태 파일·발행 로직 그대로.
   - 매거진(`scripts/harness-install/slack-mirror/magazine_slack.py`): 뿌리 글 끝에 블록(Issue 없음 · 카드 없음 · 담당 = seats-harness.json `_master` · 정본 = 매거진 md@sha · 다음 = 「오빠 할 일 N건」 · 재개 = ft-resume-cmd) + 장부 `magazine/<날짜>` kind=report.
   - 미러: `scripts/harness-install/slack-mirror/mirror_lib.py` 189행 꼬리 → 블록 2줄(담당 = from · 재개 = ft-resume-cmd(from) · 정본 = `bodies/<seq>.txt@mbox` · Issue·카드 = `없음` 고정 · 본문 인용 0).
5. 시험 `tests/scripts/test_thread_post.py`(가짜 슬랙) + `tests/harness/test_resume_cmd.sh`(가짜 tmux·jsonl) — 설계 §8-b 의 I1·I2·I3·report 사례 전부 + 블록 6칸 누락 raise + start 뿌리 글 1개·첨부 같은 스레드 + 기존 `tests/scripts/test_proposal_publish*.py`·`test_byz_mbox_slack_mirror.py`·매거진 회귀 PASS(꼬리 기대값만 갱신).

커밋은 자기 브랜치(structure 분리가 필요하면 분리), **push 금지**. **금지**: 실제 슬랙 호출 · 토큰 값 출력 · 본문 인용으로 Issue·카드 칸 채우기 · jsonl 본문 이름 검색 · 빈 장부 자동 생성 · 라이브 설치 · ft-index-move 변경(카드 2).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `pytest tests/scripts/test_thread_post.py tests/scripts/test_proposal_publish.py tests/scripts/test_proposal_publish_faults.py tests/scripts/test_byz_mbox_slack_mirror.py -q` 통과 · `pytest tests/scripts -k magazine -q` 통과 · `bash tests/harness/test_resume_cmd.sh` rc=0 · `tests/harness/test_kit_bin_sync.sh` PASS · ruff 0 · 새 파일 200줄 이하.
- RESULT 에 가짜 슬랙 로그 발췌: start 1회의 chat.postMessage(뿌리 1) + 첨부 답글(thread_ts = 그 뿌리) 2줄.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: python -m pytest tests/scripts/test_thread_post.py -q rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): install.sh·install-magazine.sh 로 slack-mirror 복사(cmp) · 장부 `--init` 1회 · 라이브 1회 = 다음 제안서·매거진 뿌리 글 꼬리에 블록 2줄.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: b637db62b533e0ef13c044d971616aa3e6318c39 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#12 · 판정 404·405 · 설계 DA HOLD 1 → 교정 1 APPROVE #62213). 카드 2 는 이 카드 랜딩 뒤 spawn.
- 정본 영향 없음: 하네스 슬랙 발행 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 13:33 — 대기→진행 · 좌석 byz-harness-nano-resume-block-thread-post#0
- 2026-10-08 13:52 — 진행→완성 · 좌석 byz-harness-nano-resume-block-thread-post#0 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§55
세트: 15a2081450f4713d007d39a8f6ce9608fe7915bb · 시험: python -m pytest tests/scripts/test_thread_post.py -q rc=0 · 이슈: 0
