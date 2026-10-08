# 인덱스: 아침 매거진 ② 렌더(md·html) + 3줄 요약 + PDF + 슬랙 + CLI·launchd 템플릿 (판정 347)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 347(planner#8 → master#12 발주 · 설계 design/harness/DESIGN-morning-magazine-20261008.md)
- 상태: 대기
- 선행: DA 사전검증 APPROVE(아래) · 수집 나노(magazine-collect)는 선행 아님 — 구조 모델 가짜로 시험
- 시험 입력: 설계 §8 계약 칸으로 만든 가짜 구조 모델 · 가짜 요약 명령 · 로컬 가짜 Slack HTTP 서버 — 실 슬랙·실 LLM 0
- 기준값: 지금 매거진 코드 0 · PDF 도구 실측 = playwright chromium page.pdf 0.9 s 한글 OK(weasyprint 는 pango 없음 · Chrome headless 는 60 s 안 끝남)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: C(배포 발행 — 슬랙) + 원문 7(쪼개 동시에 — 매거진 나노 2석 병행). 핵심 한 줄: 판정 347 오빠 원문 「아침. 8시마다. 전날부터아침까지한 24시간 작업정리. 매거진. 발행. 슬랙. 전송메세지요약 및 pdf발행. 반복작업등록」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오빠가 «매일 아침 8시에 전날 8시부터 24시간 작업을 한 장으로 정리해 슬랙·PDF 로 발행»을 지시했다(판정 347). 설계(design/harness/DESIGN-morning-magazine-20261008.md)는 두 덩이로 쪼갰고, 이 카드는 뒤 덩이다: 설계 §8 «구조 모델» dict 를 받아 ①md·html 을 같은 순서로 그리고(결론→오빠 할 일→바뀐 것→근거→각주표 · 본문 #N 은 전부 각주표에) ②R25 와 같은 cc 요약 경로(`mirror_summary.DEFAULT_CMD`·`SUMMARY_ENV`·`SummaryError` 재사용 · 프롬프트만 새로)로 3줄을 만들고 ③playwright chromium 으로 PDF 를 찍고 ④슬랙 기존 미러 채널에 뿌리 글 + 스레드 PDF 를 올리며 ⑤같은 날 재게시를 막는다 — 뿌리 글 첫 줄 날짜 표식 + 상태 3단계(`posting`→`posted`→`done`) + 게시 «전» 채널 history 표식 확인(있으면 ts 채택) + `posting`인데 표식 없음 = 자동 재게시 0·ERROR·exit 1(설계 §5 · DA HOLD-M1 교정). 요약 실패는 결정적 3줄 + 「(요약 실패: 원인)」 표시 + ERROR 로그(보이는 처리), 그 밖 실패는 전부 raise. md 를 git 에 넣는 방식은 ★오빠 판정 348 로 확정★ — `ops/magazine` 전용 브랜치에만 push(main 0 · force 0) · 예약 모드 = push 켬 · 수동 시험 = `--no-push`. 계약 = 설계 §6 «push 계약».

## 사전검증
- 소환: 예
- DA: design/harness/DA-magazine-20261008.md

## 조사 근거
- `scripts/harness-install/slack-mirror/mirror_summary.py:16` `DEFAULT_CMD` · `:20` `SUMMARY_ENV` — 요약 경로 재사용 지점.
- `scripts/harness-install/slack-mirror/mirror_lib.py:44` `api_call` · `:20` `read_token` · `:39` `esc`.
- `scripts/harness-install/slack-mirror/install.sh:41` `plutil -lint` — 설치 스크립트 패턴.
- 설계 §2 본문 틀 · §3 요약 · §4 PDF 표 · §5 슬랙 · §6 md 위치 · §7 실행·등록 · §9 시험 5~9.
- 슬랙 봇 스코프 실측(auth.test 응답 헤더): chat:write · files:write · files:read 있음.
- `mirror_lib.api_call`·`read_token`·`esc`·`MirrorError` 재사용(ok=false raise 방식 동일). 업로드는 files.getUploadURLExternal → 바이트 POST → files.completeUploadExternal(channel_id·thread_ts).
- launchd 패턴: 미러 install.sh(템플릿 치환 + plutil -lint) · 달력 실행은 StartCalendarInterval(Hour 8 · Minute 0) · RunAtLoad false · KeepAlive 없음.

## 구현 범위 (이 목록만 — 닫힌 목록)
1. `scripts/harness-install/slack-mirror/magazine_render.py` · `magazine_summary.py` · `magazine_publish.py` · `byz_morning_magazine.py`(CLI: --date · --dry-run · --force · --no-push 기본 켬).
2. `scripts/harness-install/slack-mirror/com.byz.ft-magazine.plist.template` · `install-magazine.sh`(복사 + .bak + 치환 + lint · `--load` 일 때만 launchctl · 머리 주석에 재적재 절차).
2b. push(설계 §6 push 계약): 임시 리포 + 가짜 origin 시험으로 ops/magazine 만 push · 워크트리 없음·다른 브랜치·미커밋·push 거부 → raise · `--no-push` 면 git 호출 0 — 시험은 `test_magazine_publish.py` 안에.
3. 시험 `tests/scripts/test_magazine_render.py` · `test_magazine_summary.py` · `test_magazine_publish.py` · `test_magazine_pdf.py` · `tests/harness/test_magazine_plist.sh`(설계 §9 5~9).

(같은 폴더 기존 파일 `scripts/harness-install/slack-mirror/mirror_summary.py`·`scripts/harness-install/slack-mirror/mirror_lib.py` 는 import 만 — 수정 0.)

커밋은 자기 브랜치, **push 금지**. **금지**: 미러 모듈(mirror_*.py·byz_*_mirror.py) 수정 · 실 슬랙 게시 · 실 LLM 호출 · ~/.hermes 설치 · launchctl.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `python3 -m pytest tests/scripts/test_magazine_render.py tests/scripts/test_magazine_summary.py tests/scripts/test_magazine_publish.py tests/scripts/test_magazine_pdf.py -q` rc=0 · `bash tests/harness/test_magazine_plist.sh` rc=0.
- 시험 7 의 장애 주입 4종(응답 유실 · 상태 쓰기 실패 · PDF 실패 · posting+표식 없음) 각각 «다음 실행 뿌리 게시 추가 = 0» 출력 줄 복붙.
- 가짜 구조 모델로 `byz_morning_magazine.py --dry-run` 1회: md·html·PDF 경로 + 슬랙 글 stdout 복붙(게시 0).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/test_magazine_publish.py -q rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- 2026-10-08 — 판정 348 반영(arch#9): §6 push 확정 · 범위 2b 추가(push 계약·시험).
- base_sha: 78fa5d908f81be4dc87f932f4d7ef70a26ad6de7 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#9 · 판정 347 · 설계 DESIGN-morning-magazine-20261008.md). spawn 은 master 판단 · DA APPROVE 전 lint 실패가 정상.
- 정본 영향 없음: 하네스 슬랙 키트 신규 모듈·시험·plist 템플릿 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 08:35 — 대기→진행 · 좌석 byz-harness-nano-magazine-publish#0
- 2026-10-08 — ★반송 r1 (arch#9 · HOLD 1회)★ — 나노 9b4a843abf+33261afc28 은 시험 73 passed · plist ALL PASS 지만 arch 재검에서 2건:
  ①**뿌리 글 표식 오인(재현됨)**: `magazine_slack.find_root` 가 봇 글 첫 줄에 `아침 매거진 YYYY-MM-DD` 가 «들어 있으면» 채택한다. 슬랙 미러(같은 봇 토큰 yoonhwan_bot · 같은 채널 C0C6MJGRR89)의 뿌리 글 「#885 시작 — 아침 매거진 2026-10-08 수동 발행 시험 …」 도 첫 줄에 표식을 담는다 → `find_root` 가 그 ts 를 채택(재현: 가짜 history 1건 → ts=1.0) → 매거진 뿌리 글은 안 나가고 PDF 가 미러 스레드에 붙는다. 오늘 수동 시험 쪽지가 미러로 올라가면 바로 터지는 경로.
  ②**done 확인이 push 뒤**: `byz_morning_magazine.run` 은 수집·LLM 요약·PDF·ops/magazine push 를 다 한 뒤 `publish_day` 안에서 done 을 본다 — 설계 §8 순서(「창 → 상태 읽기(done 이면 끝) → 수집 …」)와 다르고, 이미 발행된 날을 다시 돌리면 요약이 달라 ops/magazine 에 새 커밋이 쌓인다.
  재작업 범위(같은 나노 · 닫힌 목록):
  1. `scripts/harness-install/slack-mirror/magazine_slack.py`: `find_root` 판정을 «첫 줄 == `*아침 매거진 YYYY-MM-DD*`»(root_text 가 쓰는 첫 줄과 정확히 같음)로 바꾼다. 시험: 미러식 첫 줄(`#885 시작 — 아침 매거진 2026-10-08 …`) → None · 정확한 첫 줄 → ts.
  2. `scripts/harness-install/slack-mirror/byz_morning_magazine.py`: `--force` 가 없으면 창(`window`)으로 날짜를 정한 직후 상태가 done 인지 보고, done 이면 수집·요약·PDF·push 없이 `skip` 출력 + rc=0. (`--model-file` 경로도 같은 순서.) 시험: done 상태에서 실행 → collect·summary·git 호출 0.
  3. `tests/scripts/test_magazine_publish.py` 290줄 → 200줄 한도(BYZ CLAUDE.md Code Metrics) — push 시험(138~190행대)을 `tests/scripts/test_magazine_git.py` 로 옮긴다. 구조 변경이라 ①②와 «다른 커밋» `[structure]`.
  닫힘 조건 추가: 위 두 시험 출력 줄 복붙 + 전체 `pytest tests/scripts/test_magazine_*.py -q` rc=0.
- 2026-10-08 — 반송 r1 재작업 통과 (arch#9 재현 · 판정서 §44 초안) — 나노 2389619b4f [structure] 시험 3파일 분리 + 2a820d879e [fix] ①②: 시험 76 passed · plist ALL PASS · 200줄 초과 0 · find_root 미러식 첫 줄 → None · 정확한 첫 줄 → ts · done 이면 수집 전 skip · 실자료 dry-run(요약 명령 실패 주입) → 결정적 3줄 + 「(요약 실패: …)」 + ERROR · md 245줄 · PDF 1쪽(높이 4381pt).
세트: 2a820d879eeaff59de3e174622a2ac216519bb31 · 시험: python3 -m pytest tests/scripts/test_magazine_publish.py -q rc=0 · 이슈: 0
- 2026-10-08 08:55 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§44
