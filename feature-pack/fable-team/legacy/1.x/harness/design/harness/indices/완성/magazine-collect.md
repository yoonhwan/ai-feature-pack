# 인덱스: 아침 매거진 ① 창 계산 + 자료 6종 수집 → 구조 모델 (판정 347)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 347(planner#8 → master#12 발주 · 설계 design/teams/harness/DESIGN-morning-magazine-20261008.md)
- 상태: 대기
- 선행: DA 사전검증 APPROVE(아래)
- 시험 입력: 가짜 mbox jsonl · 임시 git 리포 + 가짜 origin · PATH 가짜 gh — 네트워크·실 mbox·실 GitHub 0
- 기준값: 지금 매거진 코드 0 · 이 Mac 실측 창(10-07 08:00~10-08 08:00) = mbox 2801건 · main first-parent 35건 · Issue 열림 18·닫힘 18 · PR 병합 35

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: C(배포 발행 — 슬랙) + 원문 7(쪼개 동시에 — 매거진 나노 2석 병행). 핵심 한 줄: 판정 347 오빠 원문 「아침. 8시마다. 전날부터아침까지한 24시간 작업정리. 매거진. 발행. 슬랙. 전송메세지요약 및 pdf발행. 반복작업등록」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오빠가 «매일 아침 8시에 전날 8시부터 24시간 작업을 한 장으로 정리해 슬랙·PDF 로 발행»을 지시했다(판정 347). 설계(design/teams/harness/DESIGN-morning-magazine-20261008.md)는 두 덩이로 쪼갰고, 이 카드는 앞 덩이 «창 계산 + 자료 수집»이다. 결과물은 설계 §8 의 «구조 모델» dict 하나이며, 그 칸 이름은 뒤 덩이(magazine-publish 나노)와의 계약이라 바꾸지 않는다. 자료는 6종: ①main first-parent 머지(git) ②Issue 열림·닫힘(gh 읽기) ③판정 번호(planner 좌석 쪽지 본문의 「판정 N」) ④mbox 쪽지(`.fable-team/comm/mailbox.log.jsonl` · 10-04 부터 추가 전용 · ts 는 tz 없는 KST 문자열) ⑤BRIEFING·CLOSEOUT 추가 문서 ⑥좌석 승계·신규(쪽지 from 이름의 #N). 실패는 전부 raise(BYZ #0 RULE) — 자료 하나라도 못 모으면 반쪽 결과를 돌려주지 않는다. 깨진 JSON 줄만 «세어서 보이게» 건너뛴다. 설계 §1 표가 칸별 수집 명령·형식·실패 처리의 정본이다.

## 사전검증
- 소환: 예
- DA: design/teams/harness/DA-magazine-20261008.md

## 조사 근거
- `scripts/harness-install/slack-mirror/install.sh:15` — mbox 사본 경로 `$ROOT/.fable-team/comm/mailbox.log.jsonl`(미러와 같은 입력).
- `scripts/harness-install/slack-mirror/mirror_lib.py:44` — `api_call` 의 «ok=false·네트워크 오류 = raise» 방식을 수집 오류(`MagazineError`)에도 그대로 따른다.
- 설계 §1 표(자료 6종) · §8 구조 모델 · §9 시험 1~4.
- mbox 사본 실측: 첫 줄 seq 56632 ts 2026-10-04T16:38:03 · 4298줄 · 깨진 줄 0 · 키 = body·from·seq·to·ts.
- gh 읽기 실측: `gh issue list --repo SecondWindStudio/byz-agents --state all --search "created:2026-10-06T23:00:00Z..2026-10-07T23:00:00Z" --json number` → 18.
- 판정 번호는 파일 원장이 없다(BOARD 머리줄에도 «판정 N» 형식 없음) — 쪽지 본문이 유일한 출처.
- 루트 체크아웃은 옛 브랜치라 작업 트리 파일을 읽지 말고 `git log/show origin/main` 만 쓴다.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/harness-install/slack-mirror/magazine_window.py` — `window(date: str | None, now: datetime) -> (D, start, end)` · KST · ★`date=None`(예약) = 마지막으로 닫힌 08:00 의 날짜(now<08:00 이면 어제) · `date` 명시인데 end>now 면 raise★ + `skipped_days(last_published: str | None, D) -> list[str]`(설계 §1 D 고르기 · DA HOLD-M2 교정).
2. `scripts/harness-install/slack-mirror/magazine_collect.py` — `collect(date, *, repo, gh_repo, mailbox) -> dict`(§8 칸 그대로) · `MagazineError`. 200줄 넘으면 `magazine_collect_mbox.py` 로 mbox·좌석 부분을 나눈다.
3. 시험 `tests/scripts/test_magazine_window.py` · `test_magazine_collect_mbox.py` · `test_magazine_collect_git.py` · `test_magazine_collect_gh.py`(설계 §9 1~4).

(같은 폴더 기존 파일 `scripts/harness-install/slack-mirror/mirror_lib.py` 는 읽기·import 만 — 수정 0.)

커밋은 자기 브랜치, **push 금지**. **금지**: 미러 모듈(mirror_*.py·byz_*_mirror.py) 수정 · 실 mbox·실 GitHub 를 시험에서 읽기 · ~/.hermes 설치 · launchd.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `python3 -m pytest tests/scripts/test_magazine_window.py tests/scripts/test_magazine_collect_mbox.py tests/scripts/test_magazine_collect_git.py tests/scripts/test_magazine_collect_gh.py -q` rc=0.
- 실측 1회(읽기 전용): `python3 -c` 로 `collect("2026-10-08", …)` 를 이 Mac 실자료에 돌려 칸별 건수 1줄 — 기준값과 대조(mbox 2801 · merges 35 · 열림 18 · 닫힘 18 근처 · 다르면 이유 1줄).
- RESULT 에 위 두 출력 복붙.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/test_magazine_collect_mbox.py -q rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 78fa5d908f81be4dc87f932f4d7ef70a26ad6de7 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#9 · 판정 347 · 설계 DESIGN-morning-magazine-20261008.md). spawn 은 master 판단 · DA APPROVE 전 lint 실패가 정상.
- 정본 영향 없음: 하네스 슬랙 키트 신규 모듈·시험 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 08:35 — 대기→진행 · 좌석 byz-harness-nano-magazine-collect#0
- 2026-10-08 — 완료 독립 검증 (arch#9 · 판정서 §43 초안) — 나노 0216631058: 신규 9파일(수집 5·시험 4 · 기존 파일 0 · 최대 113줄) · pytest 33 passed · 구조 모델 키 = 설계 §8 그대로 · 실자료 재실행 mbox 2801·HIL 8·깨진 줄 0·머지 35·열림 18·닫힘 18·판정 36·문서 2 · 잠 깸 창(10-09 07:30 → D=10-08) · 수동 미래 창 raise · 음성 대조(PATH 비움 → MagazineError).
세트: 0216631058c3877b557698cfd2938e9f8c05e20b · 시험: python3 -m pytest tests/scripts/test_magazine_collect_mbox.py -q rc=0 · 이슈: 0
- 2026-10-08 08:43 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§43
