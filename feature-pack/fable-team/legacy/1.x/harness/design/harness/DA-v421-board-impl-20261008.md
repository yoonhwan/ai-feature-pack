# DA — v421-board(+496) 구현 재확인 (1회 · 10분 · arch#17 · 2026-10-08)

- 세트: 브랜치 `nano/v421-board` 커밋 `8437480164`(r2 · 반송 반영) ← `caf26c1b83`(r1) · 워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-v421-board`
- 카드: `design/teams/harness/indices/대기/v421-board.md`(완료 조건 「구현 DA 가 재확인」) · 반송서 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r21/REJECT-v421-board-r1.md`
- arch 재현(#17): `git archive 8437480164 scripts tests/harness tools/comm-canonical` → `test_board.sh` rc=0 · PASS 63 · `test_kit_bin_sync.sh` rc=0 · 사본 7개 cmp 같음 · ruff 0 · 최대 126줄 · 변경 파일 = ft-board*·ft_board_*·test_board 만.
- 질문 둘만(범위 고정 · 설계 재심 0):
  - I1 슬랙 렌더에서 «입력 유래» 문자열(카드·판정·Issue 제목 · 트리 줄 글 · 판정 oppa_todo · 명부 `_label` · 인박스 줄 · 결정 자리 사유)이 전부 제목 필터(`ft_board_render.py:22-30`)를 거치는가 — 거치지 않는 것이 있으면 최종 단언(`:120-122`)이 다시 보드 전체를 raise 한다(r1 반송과 같은 꼴). 반례 1개(파일:줄)로.
  - I2 `snapshot` 의 «카드만 바뀐 두 번째 changes 1건 + snap 전→후»와 496 불변식(축 계수 + 미연결 = 폴더 수 · 기본·full)이 코드와 시험으로 성립하는가.
- 판정은 아래 「## 판정」 절에(모델·provider 두 줄 · APPROVE / HOLD(반례 1개 · 파일:줄)).

## 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

I1 HOLD — 입력 유래 결정 자리 사유 d['decision']이 Omit 없이 바로 출력돼 최종 단언이 보드 전체를 raise합니다(ft_board_render.py:115, :120-122; 원천 ft_board_collect.py:117). 고정 HEAD 8437480164에서 외부 호출 없는 최소 dict `{teams:[],issues:[],verdicts:[],decision:'확인 불가(byz-planner-Q3 tmux 세션 없음)'}`를 render(...,'slack')에 전달해 ValueError(Q3 잔존)를 독립 재현했습니다. 추가로 Omit의 대체 ref 자체가 미검사라 `Omit(True)('답장 안내','reply-cleanup')`은 금지 문자열 reply를 그대로 남깁니다(같은 render 파일:30); 입력 ID/좌석 이름/판정 teams도 최종 출력 경계에서 검사해야 합니다.
I2 APPROVE(코드·시험 내용 확인) — snapshot은 직전 파일을 쓰기 전에 읽고 카드 상태 변화를 diff에 넣어 snap 전→후와 changes를 반환합니다(ft_board_snapshot.py:45-48, :69-81). test_board.sh:151-158이 카드만 이동한 changes 정확히 1건+hash 전→후를 단언하며, :104-119가 카드 폴더 전체 대비 축+미연결 계수 및 full 카드 보존을 확인합니다. tree fold의 first-seen·미연결 경로도 일치합니다(ft_board_tree.py:50-63, :83-99).

전체 shell 시험은 이번 한정 검토에서 독립 재실행하지 않았습니다(시험에 prune/fixture 삭제 경로 포함); arch PASS63·키트/ruff 결과는 보고 증거입니다. 독립 재현은 위 순수 Python 렌더 호출뿐이며 슬랙/gh/tmux/라이브 쓰기 0. 반송은 I1 입력 사유/식별자까지 포함한 출력 필터 누락에 한정합니다.

HOLD

## r2 요청 (arch#17 · I1 만 · 10분 · HOLD 면 bounded 종료 → planner)
- 세트: `bd4032c4e4`(r3 · 반송서 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r21/REJECT-v421-board-r2.md` 반영 — 필드별 Omit 삭제 · 슬랙 최종 출력 한 곳에서 고정 줄 외 전 줄 부분 치환 `〔문구 생략〕` · 끝 줄 `문구 생략 n곳`).
- arch 재현(#17): `git archive bd4032c4e4 …` → `test_board.sh` rc=0 PASS 64 · kit sync rc=0 · 사본 cmp · ruff 0 · 범위 밖 파일 0 · 당신의 r1 반례 `render({teams:[],issues:[],verdicts:[],decision:'확인 불가(byz-planner-Q3 tmux 세션 없음)'}, 'slack')` → rc 정상 · `결정 자리: 확인 불가(byz-planner-〔문구 생략〕 tmux 세션 없음)` · 끝 줄 `문구 생략 1곳` · 출력 전체 REPLY_ASK 0.
- 질문: I1 — 슬랙 출력에서 입력 유래 문자열이 치환을 건너뛰어 최종 단언을 다시 raise 시키는 경로가 남았는가(고정 줄 판정이 입력으로 속을 수 있는가 포함). 반례 1개(파일:줄) 또는 APPROVE. I2 재심 0.

## r2 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

I1 APPROVE — 고정 HEAD bd4032c4e4에서 decision은 :110, 모든 section 데이터 줄은 :114-117의 최종 scrub을 거칩니다(ft_board_render.py). 고정 줄 제외는 입력 문자열 내용으로 판별하지 않고 코드가 직접 만드는 머리/section 제목 위치뿐이라 입력이 고정 줄을 흉내 내도 필터를 건너뛰지 않습니다. 치환 문자열과 생략 수 표시에는 금지 패턴이 없어 최종 단언 재발 경로를 확인하지 못했습니다.
r1 decision 반례 및 reply ID·머리표/개행 모방·Q번호를 순수 Python으로 독립 재현: 5 probes passed, 출력 REPLY_ASK 0·생략 1곳 표시 확인. I2 재심 없음(기존 코드/시험 내용 APPROVE 유지). shell 시험 PASS64·키트/ruff는 arch 보고이며 이번 재검에서 독립 재실행하지 않았습니다. 외부 호출·발송·라이브 쓰기 0.

APPROVE
