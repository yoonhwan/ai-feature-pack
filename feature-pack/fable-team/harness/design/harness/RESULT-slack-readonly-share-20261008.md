# RESULT: 슬랙 = 읽기 전용 공유판 — 답장 요구 0 · 첫 줄 머리표 4종 · 결정 자리 = 현역 planner 세션 이름

골 축: 하네스 C(배포 발행(슬랙) 수신해 반영) + A(오빠 요청 즉시 검토). 인덱스 `design/harness/indices/진행/slack-readonly-share.md` · 설계 `design/harness/DESIGN-slack-readonly-share-20261008.md` §4-r2 · 판정 497.
오빠 원문 한 줄: 「거기서 자꾸 답하라는데 … 작업상황·이슈보고·변경내용·상태를 공유하고 hil이나 인터뷰가 있으면 정확히 어느 세션으로 가거나 플래너 정확한 세션을 알려주는 공유를 중점으로」

세트: dc4ad4176bb50280832df6e166798532369f7c7d · 시험: bash tests/harness/test_slack_readonly_share.sh rc=0 · 이슈: 0

## 산출 (브랜치 `nano/slack-readonly-share` · push 안 함)

| 커밋 | 종류 | 내용 |
|---|---|---|
| `015dba85f5` | [structure] | 제안서 글 `first_line`·`text_of` → `proposal_text.py` (동작 동일 · `byz_proposal_publish.py` 가 정확히 200줄이라 자리 확보) |
| `dc4ad4176b` | [feature] | 아래 표 전부 |

| 구현 범위 항목 | 파일 | 한 일 |
|---|---|---|
| 1 공용 계약 | `mirror_share.py`(새) | `live_planner`(사유 5종) · `share_guard`(A + A-r3 정규식) · `strip_head`/`tag`/`first_line_is` · `decision_line` · `share_lines`(what/todo 교정) |
| 2 표시 | `mirror_lib.py` | `format_row` 머리표·`(요약 문구 교정)`·결정 자리 줄(멘션은 이 줄에만)·`root_text` 머리표·전문 블록 머리 줄 |
| | `mirror_questions.py` | `선택지(참고):` 한 줄 · 답하는 법·질문 번호 삭제 · 보드 `[상태] 결정 대기 N건 — 결정 자리: …` · `planner 전달됨 N건` · 옛 보드 글도 찾아 제자리 갱신 |
| | `mirror_summary.py` · `magazine_summary.py` | 프롬프트 문구 · LLM 3줄 검사 · 결정적 3번째 줄 `결정 대기는 M건이에요 — 결정 자리: …` |
| | `resume_block.py` · `byz_github_slack_mirror.py` | 「다음」 칸 `결정 대기` · FACT 문구 · 사건별 머리표(열림·hil=이슈보고, 머지·닫힘=변경내용) |
| | `byz_mbox_slack_mirror.py` | `format_gap` `[상태]` · 선택지 · 명부 경로 유도(`--planner-seats`) |
| | `magazine_slack.py` · `magazine_block.py` · `magazine_reattach.py` · `byz_morning_magazine.py` | 뿌리·실패·재첨부 `[상태]` · `결정 대기 N건 — 결정 자리` · find 3함수 머리표 무시 비교 |
| | `proposal_text.py` · `byz_proposal_publish.py` | `[작업상황]` · `결정할 것:` + 결정 자리 줄 · 값 교정 · find 머리표 무시 |
| | `byz_thread_post.py` | 시작·진행 `[작업상황]` · 결과 `[변경내용] [결과] …` · repair/find 머리표 무시 |
| 3 inbound | `mirror_inbound.py` | `resolve`(`@planner` → 현역) · `sent_names` · `migrate_planner`(B-r3) · `planner_seat`(`_hil_route` 읽기) 삭제 |
| | `mirror_plan.py` | 수신자 `@planner` · 되묻기 2문구 삭제 |
| | `byz_slack_mbox_inbound.py` | 매 패스 `@planner` 해석 · 확인 불가 = 건너뜀+알림 1회 · 토큰 `slack:{ts}:@planner` · 빈 수신자 finished 금지 · 이관 호출 |
| 4 시험 | `tests/harness/test_slack_readonly_share.sh`(새) | PASS 91 |
| (범위 보강) | `install.sh` · `install-github.sh` · `install-inbound.sh` · `install-magazine.sh` · github plist | 새 모듈을 복사 목록에 추가(빠지면 라이브 `ModuleNotFoundError`) · github `--planner-seats` |

## 시험 값 (2026-10-08)
- `bash tests/harness/test_slack_readonly_share.sh` rc=0 · PASS 91 · FAIL 0 (슬랙 API·실제 tmux·실제 LLM 0 — 가짜 tmux 스텁·가짜 요약기·가짜 history)
- 기존 7종 PASS: signature 3 · index_move_slack 14 · magazine_plist 18 · proposal_register 59 · proposal_register_r2 38 · proposal_card 31 · slack_post_guard 29
- `ruff check scripts/harness-install/slack-mirror/` 0 · 고친 파일 전부 200줄 이하(최대 `byz_slack_mbox_inbound.py` 189 · `mirror_lib.py` 195)
- 변이 대조: `share_guard` 를 항상 통과시키면 새 시험 16 FAIL
- 설치 키트: 각 installer 의 복사 목록만 담은 빈 디렉터리에서 `byz_mbox_slack_mirror` · `byz_github_slack_mirror` · `byz_slack_mbox_inbound` · `byz_morning_magazine` · `byz_proposal_publish` · `byz_thread_post` import 6/6 OK

### 기존 단언 변경 1건 (diff — 단언을 지우지 않고 새 문구로)
`tests/harness/test_slack_mirror_signature.sh:53`
```
- need("hil", hil["text"], "<@U0AC2JF0M7D>", "다음: 오빠 판정", "(github #9 hil)", "링크: https://github.com/o/r/pull/9")
+ need("hil", hil["text"], "<@U0AC2JF0M7D>", "결정 자리:", "다음: 결정 대기", "(github #9 hil)", "링크: https://github.com/o/r/pull/9")
```

### 가짜 HIL 카드 1장 — 렌더 결과 전문 (첫 줄 머리표 + `결정 자리:` + 답장 요구 0)
```
[이슈보고] 배포 방식을 정해야 해요
A 와 B 중 하나를 정해요
<@U0AC2JF0M7D> 결정 자리: byz-planner-master-claude#12 (그 세션이 인터뷰를 띄웁니다) · 질문 올린 좌석: byz-x#1
↳ 이어가기 · Issue 없음 · 카드 없음 · 담당 byz-x#1 · 정본 bodies/7.txt@mbox
↳ 다음: 결정 대기 · 재개: tmuxc resume byz-x#1
선택지(참고): 1) A 로 간다 2) B 로 간다
링크: https://github.com/o/r/issues/7
```
(가짜 명부 `_master`=#12, `_hil_route`=#11 → #12 사용. 같은 카드를 세션 없음으로 돌리면 `결정 자리: 확인 불가(planner 현역 세션: 세션 없음) — 하네스 master 에 알림` — 대체 이름 0.)

### B-r3 fixture 4 (+1) 출력 — 현역 `_master` = `byz-planner-master-claude#12`
```
FIXTURE 옛 이름 pending → 현역 1회: recips=['@planner'] done={'@planner': 'byz-planner-master-claude#12'} attempt={'@planner': ['byz-planner-master-claude#12']} sends=['byz-planner-master-claude#12'] finished=True
FIXTURE 옛 이름 첫 시도 뒤 crash(attempt 1 · marker 있음) → 재발송 0: recips=['@planner'] done={'@planner': 'byz-planner-master-claude#11'} attempt={'@planner': ['byz-planner-master-claude#11']} sends=[] finished=True
FIXTURE 옛 이름 첫 시도 뒤 crash(attempt 1 · marker 없음) → 현역 1회: recips=['@planner'] done={'@planner': 'byz-planner-master-claude#12'} attempt={'@planner': ['byz-planner-master-claude#11', 'byz-planner-master-claude#12']} sends=['byz-planner-master-claude#12'] finished=True
FIXTURE 옛 이름 이미 done → 재발송 0: recips=['@planner'] done={'@planner': 'byz-planner-master-claude#11'} attempt={'@planner': ['byz-planner-master-claude#11']} sends=[] finished=True
FIXTURE 다른 팀 질문 좌석 이관 0: recips=['byz-cfo-master-claude#53', '@planner'] done={'byz-cfo-master-claude#53': True, '@planner': 'byz-planner-master-claude#12'} attempt={'@planner': ['byz-planner-master-claude#12']} sends=['byz-planner-master-claude#12'] finished=True
```
이관은 멱등(두 번째 호출이 바꾸는 것 0 — fixture 마다 확인).

## 설계와 다르게 한 곳 · 판단한 곳 (DA 확인 요청)
1. **`(요약 문구 교정)` 표시는 메시지당 1개**(첫 줄 끝) — what·todo 둘 다 교정돼도 1개. 설계 문구 「줄 끝 1개」 를 그렇게 읽었다.
2. **GitHub 요약 실패 경로(`plain=True`)는 검사 제외** — 그 경로의 원문 첫 문장은 `이슈 N 열렸어요 — <제목>` 이라 제목이 사실이다(설계 A 「GitHub 제목은 제외」). 요약(LLM) 성공 경로의 what 은 검사한다.
3. **명부 경로는 «경로»만 유도, 이름은 매번 조회**: mbox 미러 = `mailbox` 상위 `seats-planner.json` · inbound = `--seats-file` 폴더의 `seats-planner.json` · 매거진 = `repo_root/.fable-team/seats-planner.json` · 제안서 CLI = `resume_script` 상위 · GitHub 미러 = 새 `--planner-seats`(설치기가 `BYZ_ROOT` 에서 채움). 직접 지정은 env `MIRROR_PLANNER_SEATS`, tmux 명령은 `MIRROR_TMUX`.
4. **질문 좌석 = 현역 planner 인 경우** 같은 좌석에 두 번 보내지 않는다(`@planner` 를 보낸 이름으로 done 처리) — 옛 코드의 `planner != seat` 비교를 역할 표식 아래서 유지.
5. 옛 inbound 원장의 `ask`(되묻기) 미게시 항목은 더 이상 게시하지 않는다(문구가 답장 요구).

## 남은 것 (master 소관 — 카드 밖)
- **설치**: 라이브 `~/.hermes/scripts/` cp + cmp. 새 파일 2개(`mirror_share.py` · `proposal_text.py`)는 installer 가 복사한다. **`install-github.sh` 는 이제 `BYZ_ROOT=<리포 루트>`(또는 `MIRROR_PLANNER_SEATS`)가 필요하다** — 없으면 exit 1(조용한 기본값 0).
- launchd 미러 3종(mbox·github·inbound) 재기동 · 매거진은 다음 08:00 반영 · 실측 1건(새 HIL 카드 문구 캡처).
- 옛 보드 글(`답을 기다리는 질문 …`)은 첫 갱신 때 같은 글이 `[상태] 결정 대기 …` 로 제자리 갱신된다(새 글 0).
- **press 필요: 없음** — 슬랙 문구·수신자 해석만 바꿨고 오디오 경로는 건드리지 않았다. 라이브 슬랙 캡처 1건은 위 설치 뒤 master 가 본다.
- FE Next.js 이슈(에러 오버레이·console.error): 해당 없음 — 프런트 변경 0.
- 정본 영향 없음: 하네스 슬랙 미러 스크립트·시험만 — `docs/architect` 제품 정본 변경 없음.
