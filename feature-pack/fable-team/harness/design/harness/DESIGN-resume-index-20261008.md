# DESIGN — 슬랙 «이어가기 인덱스» 일반화 + 결과 답글 강제 (판정 404 ② · 2026-10-08 · byz-harness-arch-claude#12)

## 골 원문 (GOAL-harness.md 복붙)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: A 모니터·오빠 요청 + C 배포 발행·반영. 오빠 원문(판정 404): 「응답시 바로 세션창에서 이어 진행할수있는 인덱스 일반화」.
감사(사실 근거): design/harness/AUDIT-j404-slack-threads-20261008.md — 제안서 5건 중 4건 손 발행(hermes send · 뿌리 글 쪼개짐) · 어느 경로에도 결과 답글 단계 없음 · 과정은 미러의 좌석별 스레드로만.

## §1 바꾸는 것 한 줄 (판정 405 전제 5개 반영 · r1)
슬랙에 올라가는 «단위» 글은 전부 한 입구(`byz_thread_post.py`)로 나가고, 모든 글 꼬리에 같은 6칸 블록이 붙고, 카드를 완성으로 옮기려면 그 스레드에 «결과 답글»이 있어야 한다.

## §2 이어가기 블록 (모든 공유 글·답글 꼬리 · 고정 2줄)
```
↳ 이어가기 · Issue #893 · 카드 design/feature/indices/진행/F-guest-qr-jwt-proposal.md · 담당 byz-feature-master-claude#2 · 정본 design/feature/PROPOSAL-guest-qr-jwt-20261008.md@8fe1e678
↳ 다음: 오빠 — 비용 주체 결정(방장/조직/본인) · 재개: bash /…/.fable-team/comm/mbox.sh ring byz-feature-master-claude#2
```
- 6칸(Issue · 카드 · 담당 · 정본 · 다음 · 재개)은 «항상» 찍힌다. 값이 없으면 호출자가 문자 그대로 `없음` 을 넘긴다. 빈 값·None 은 raise(#0 규칙 — 칸을 조용히 빼지 않는다).
- 정본 = `<repo 상대 경로>@<커밋 sha 8>` — 그 파일을 마지막으로 바꾼 커밋(`git log -1 --format=%h -- <path>`). 미커밋이면 raise(슬랙에 미커밋 정본을 걸지 않는다).
- 재개 명령은 `ft-resume-cmd.sh <좌석>` 가 만든다(★교정 1 · DA HOLD-I3★): ①tmux 세션 이름이 정확히 일치하는 세션이 살아 있음 → `bash <루트>/.fable-team/comm/mbox.sh ring <좌석>` ②없음 → 좌석표(seats*.json) 그 좌석 행에 `session_uuid`·`cwd`·`agent` 가 기록돼 있고, `~/.claude/projects/<cwd 인코딩>/<uuid>.jsonl` 이 실재하며 그 jsonl 의 sessionId·cwd 가 행과 같고 agent=claude 일 때만 `cd <cwd> && claude --resume <uuid>`(shlex 인용) ③그 밖(행에 매핑 없음 · 불일치 · 다른 backend) → rc 3 + 칸 값 `없음(좌석 종료 · 확인된 세션 매핑 없음 — 카드 정본으로 새로 연다)`. ★jsonl 본문에서 좌석 이름을 검색하지 않는다★(이름 언급 ≠ 소유권). 매핑 기록(개설·승계 때 행에 session_uuid·cwd 쓰기)은 이 설계 밖 — 없으면 ③으로 «보이게» 떨어진다(closeout 정책 4 「재개 = 정본 읽고 새로 연다」와 같다).
- 블록 생성은 `resume_block.py` 한 곳(slack-mirror 폴더 · 모든 발행 경로가 import). 텍스트는 `esc` 로 중화.

## §3 단일 입구 `byz_thread_post.py` + 스레드 장부
- 장부 `~/.hermes/state/byz_threads.json`(★교정 1 · DA HOLD-I1★): 키 = «불변 단위 ID» `<팀>/<카드 파일 이름(.md 뺀 것)>` — 카드가 대기/진행/완성 폴더를 옮겨도 파일 이름은 그대로라 키가 안 바뀐다. 값 = `{channel, root_ts, kind, card_path(표시용 · 이동 때 갱신), progress:[ts…], results:[ts…]}`. 장부 파일 없음·JSON 손상 = raise(빈 장부로 흡수 0). 저장 실패 = raise.
- ★게시 의도는 tracked 카드에 먼저 남긴다★: `start` 는 원격 게시 «전»에 카드 상태 절에 `- 슬랙: <channel> · 시도 <ISO>` 1줄을 쓰고, 성공 뒤 같은 줄을 `- 슬랙: <channel> <root_ts>` 로 바꾼다. 카드의 이 줄이 «게시 대상» 표식이자 장부 백업이다. `repair --card <카드>` = 카드 줄의 root_ts 로 장부 키 복구(줄이 «시도»뿐이면 채널 최근 글에서 첫 줄 표식 `[<단위 ID>]` 검색 → 1건이면 복구 · 0건/2건 이상이면 사람 확인).
- 명령 3개:
  - `start --card <카드> --text <1~3줄> [--file <첨부>…]` → 뿌리 글 1개 + 첨부는 «그 스레드 답글»로(뿌리 글 쪼개짐 금지 · 감사 2·3·4호 원인). 장부에 root_ts 기록. 같은 카드로 두 번 start = REJECT(이미 있으면 그 ts 출력).
  - `progress --card <카드> --text …` → 같은 스레드 답글 + 블록.
  - `result --card <카드> --text <결과 1줄> [--verdict <판정 N>]` → 첫 줄 `[결과]` 표식 + 블록 · 장부 results 에 ts.
- 모든 명령이 블록 6칸 인자를 받는다(`--issue --seat --canon --next`; 재개는 --seat 로 ft-resume-cmd 호출).
- 제안서 발행(`byz_proposal_publish.py`)은 이미 «같은 스레드 rN»을 지키는 공식 도구 — 바꾸는 것은 ①뿌리 글·rN 글에 블록 추가 ②root_ts 를 장부에도 기록(키 = 제안서 카드 경로 · 인자 `--card` 추가) 두 가지뿐. 발행 로직·상태 파일은 그대로.
- 매거진: 뿌리 글에 블록(Issue 없음 · 카드 없음 · 담당 = 하네스 master · 정본 = 매거진 md@sha · 다음 = 「오빠 할 일 N건」 · 재개 = master ring). 장부 kind=report — 매거진은 보고서라 «결과 답글 강제» 대상이 아니다(오빠 할 일 8건 각각은 자기 단위 스레드에서 닫힌다). ★이 면제는 DA 반박 대상으로 명시★.
- Hermes 미러(mbox → #byz-planner 좌석별 스레드 · ★교정 1 · DA HOLD-I2★): 지금 꼬리(좌석 · #seq · 전문 경로)를 블록 2줄로 바꾼다. 권위 칸은 mbox 행의 «정형 필드»에서만: 담당 = from · 재개 = ft-resume-cmd(from) · 정본 = 전문 경로(`bodies/<seq>.txt` · git 밖이라 @sha 대신 `mbox`). ★Issue·카드 칸 = `없음`★ — mbox 행에 정형 issue·card 필드가 없으므로 본문 속 `#숫자`·경로를 권위 값으로 쓰지 않는다(발주 #seq·PR·참고 이슈·이전 카드 오집 · DA §4). 정형 필드 추가(mbox.sh send --issue/--card)는 이 설계 밖.
- 뉴스 틱: master pane 으로 가는 프롬프트라 슬랙 경로가 아니다 — master 의 뉴스가 mbox 로 나가면 미러 블록이 붙는다. 별도 변경 0.

## §4 과정·결과 답글 자동 + CLOSE 금지 (판정 405 전제 3 「판정·랜딩·닫힘 때 그 스레드에 자동」)
- 자동 지점은 카드 이동 도구 `ft-index-move.sh` 하나(모든 단위가 지나는 문 · 랜딩은 완성 이동 «전»에 끝난다 — closeout 순서). «게시 대상» 판단 = 카드의 `- 슬랙:` 줄 유무(장부 유무가 아니다 · 교정 1):
  - 대기→진행(착수): 카드에 `- 슬랙:` 줄이 있으면 `byz_thread_post.py progress --card <카드> --text "착수 — <좌석>"` 자동 + 장부 card_path 갱신. 실패면 이동 REJECT. 줄이 없으면 아무것도 안 함(슬랙에 안 올라간 단위).
  - 진행→완성(판정·랜딩·닫힘): 카드에 `- 슬랙:` 줄이 있고 kind≠report 면 `byz_thread_post.py result --card <카드> --verdict <--da 의 판정문#§N> [--landed <sha>]` 자동 — 결과 1줄 = 그 판정문 §N 제목 줄 그대로. ★줄은 있는데 장부 키 없음·root_ts 없음(«시도»뿐)·장부 손상 = REJECT 「장부 복구 필요 — byz_thread_post.py repair --card <카드>」★. 발송 실패(rc≠0)도 REJECT. 이미 results 가 있으면 다시 안 보내고 통과(멱등). 결과 원격 성공 뒤 장부 기록 실패 → 재실행 때 스레드에서 `[결과] <단위 ID>` 표식을 먼저 찾아 있으면 장부만 채우고 재발송 0(제안서 발행의 «발행 불명» 처리와 같은 꼴).
  - `--landed <sha>` 는 index-move 의 새 선택 인자 — master 가 랜딩 sha 를 넘기면 결과 줄에 붙는다. 없으면 `랜딩 없음` 을 그대로 찍는다(문서 단위 등).
- 장부 조회·발송은 전부 `byz_thread_post.py`(rc 0/1) — index-move 는 장부 형식을 모른다.
- 슬랙 원격 확인은 평소엔 하지 않는다 — 결과 재실행 표식 확인 · repair · 소급 때만.

## §5 손 발행 차단
- PreToolUse 훅 `slack-post-guard.sh`(키트 templates/hooks + 홈): Bash 명령에 `hermes send` 와 `slack` 대상(`-t slack`·`--to slack:`)이 함께 있으면 deny + 「byz_thread_post.py start|progress|result 를 쓴다」. 그 밖 hermes send(telegram 등)·읽기는 통과.
- 위반 근거가 된 문구(feature 카드 다수의 「슬랙 #byz-agent hermes send」)는 feature master 에 고침 요청 1통(harness 는 남의 카드를 안 고친다).

## §6 채널 — 닫힘 (판정 405 오빠 결정 · master#14 #62177)
단위 스레드 채널 = **#byz-planner(C0C6MJGRR89) 하나** · 봇 = yoonhwan 하나. 제안서·매거진·결과 전부 공식 발행 도구(byz_proposal_publish · 매거진 발행기 · byz_thread_post)로만. 나노·좌석의 손 `hermes send` 슬랙 발행 금지(§5 훅). #byz-agent·hermes 토큰은 §7 소급 1회에만 쓴다.

## §7 첫 적용 — 오늘 스레드 소급 결과 답글 (감사 표 6행 · 사실 = BOARD r55 머리줄 복붙 · planner #62178)
정본: .worktrees/v6-realtime-live/design/planner/BOARD.md 3행(r55 머리줄). 아래 «사실» 칸은 그 줄의 문구를 그대로 옮긴 것이다(추측 0). 결과 답글 1줄은 이 사실 칸을 그대로 쓴다.
| 스레드 | 사실 (BOARD r55 복붙) | 채널·봇 |
|---|---|---|
| 매거진 10-08 (1791417434) | BOARD r55 에 «10-08 호 오빠 할 일 8건» 처리 줄 없음 → kind=report · 결과 답글 대신 블록 답글 1개(담당 = 하네스 master) — 내용 = design/harness/FACTS-j404-magazine-8items-20261008.md 표 그대로(처리됨 7 · 보류 1 「가드 훅 전역 설치」 · BOARD 처리 줄 없음 1 「planner 나노 닫기용 카드 위치」 · planner c460770b90 · DA APPROVE 뒤 사실 칸만 연결) | #byz-planner · yoonhwan(공식 도구) |
| 1호 #887 줄바꿈 (1791419075) | 「판정 355 오빠 승인 · 결정 A=(b) 속성+CSS+크기 규칙 2 · 결정 B=ja auto-phrase 미채택 → feature 구현 카드(#61165) · #887 status:approved」 · 「PR #894 main 6b5bcf0b7b(Vela+#887 r1)」 · 부록 B 「판정 379 … C=(a) · D=(a) · E=(a)」 · 「PR #897 main 7081a505044c(부록 B·게스트 세트)」 | #byz-agent · hermes (1호 뿌리 글이 #byz-agent 라 yoonhwan 봇 불가 → hermes 1회 · master#14 승인 #62192) |
| 2호 vela (1791422239) | 「판정 367 Vela 2.0 = ⓐ 보류 + 재진입 조건 3」 · 「판정 367 Vela 보류 집행 끝(5061f78d3b · 카드 완성 9fc8a504fd · 나노 닫힘)」 · 「PR #894 main 6b5bcf0b7b」 | #byz-agent · hermes |
| 3호 guest-qr-jwt (1791425216) | 「판정 381 오빠 인터뷰(4문 전부 추천안): Q1 방장 지갑 유지 · Q2 게스트 JWT + STRICT 기본 ON(단계 0~3) · 영수증 참조만 · GO = Issue 등록(#168·#172 통합 이관) + 구현 착수」 · 「#896 Guest QR↔JWT 통합 Issue 등록(#168·#172 close)」 · 「PR #897 main 7081a505044c」 · 「#905 main cef86d391a(게스트 JWT 단계 1)」 | #byz-agent · hermes |
| 4호 light-open-models (1791429664) | 「제안서 4호 완성(… 결론 = 24G 한계는 KV 캐시 몫 · 산식 ↔ 운영 실측 0.2% · 서울 G4 없음) → 판정 397 = ⓐ Index-Translate-9B FP8 L4 스팟 측정 1회 + G4 CUD 보류 · GO(등록+착수)」 | #byz-agent · hermes |
| 5호 toss (1791426697 · r2 1791429774) | 「판정 387 토스 사업자 동일 → 추가 MID」 · 「판정 398 = 토스 추가 MID 메일 문안 cfo 초안」 · 「토스 MID 메일 문안 3338ad38ac」 · 「오빠 손 대기 = … 토스 메일 …」 | #byz-planner · yoonhwan(공식 도구) |
- 발송은 나노 산출 도구(`byz_thread_post.py result --legacy-root <ts> --bot hermes|yoonhwan --channel <id>`)로 1회 · 장부에도 기록. hermes 토큰은 이 소급에만(§6).

## §8 나노 분할 (카드 2장 · 순서 고정)
1. `resume-block-thread-post` — resume_block.py · byz_thread_post.py(start/progress/result/check · --legacy-root · --bot) · ft-resume-cmd.sh · 제안서 발행·매거진·미러에 블록 연결 · 시험(가짜 슬랙 API).
2. `result-reply-close-gate` — ft-index-move 완성 lint · slack-post-guard.sh(키트+홈 같은 바이트) · 시험. 1번 랜딩 뒤.
소급 7행은 1번 랜딩 + §6 오빠 값 뒤 master 집행.

## §8-b 교정 1 시험 (DA §3~§5 직접 회귀 · 가짜 슬랙 API·가짜 jsonl)
- I1: start 원격 성공 뒤 장부 쓰기 실패 → 완성 move REJECT · 장부 키 삭제 → 게시 카드 move REJECT(repair 안내) · 대기→진행→완성에서 같은 단위 ID·root_ts 유지 · `- 슬랙:` 줄 없는 카드는 지금처럼 통과 · result 원격 성공 뒤 장부 실패 → 재실행 시 재발송 0.
- I2: 본문 머리 발주 #seq · PR+Issue 혼합 · 이전 카드 인용 · 여러 단위 → 미러 블록 Issue·카드 칸 전부 `없음`.
- I3: 가짜 jsonl A 가 B 를 언급 · B 이전 incarnation · cwd 불일치 · backend 불일치 → 전부 ③ `없음(…)` · 행 매핑 정확 1건 → `cd … && claude --resume …`(공백 경로 인용 확인).
- report: kind=report 는 매거진 발행기만 부여(byz_thread_post 인자로 report 지정 불가) · 키 = `magazine/<날짜>`.

## §9 DA 에 묻는 것 (bounded 10+10분 · 2 HOLD 면 중단)
1. 매거진 kind=report 면제가 «결과 없음»을 다시 가리는가.
2. 장부만 보고 CLOSE 를 막는 것 — 장부 기록 실패·수동 삭제 때 lint 가 «슬랙에 안 올라간 단위»로 오판해 통과시키는 길이 있는가.
3. 미러 블록의 Issue·카드 칸 «본문 첫 인용» 규칙이 틀린 단위를 가리킬 위험 vs `없음` 강제.
4. 재개 명령 ②(jsonl uuid)가 다른 좌석·다른 워크트리 세션을 집을 수 있는가.
