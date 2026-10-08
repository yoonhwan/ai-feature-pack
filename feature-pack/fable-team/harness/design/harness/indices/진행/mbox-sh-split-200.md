# 인덱스: mbox.sh 200줄 이하 분리 — 도어벨 도우미를 옆 파일로 · 동작 변화 0 [structure] (CLAUDE.md Code Metrics · 판정 #62814 arch 회신 #62821 · planner 판정 592 순서 ③)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → master #62814 질의 · arch 판정 #62821(위생 대기 1장) · planner 판정 592 ③(master#20 시작 신호 #66782)
- 상태: 대기
- 선행: 나노 4(v425-master-inbox · 완성) · v423 a/b/c(완성) — 둘 다 랜딩 끝 → 선행 없음
- 시험 입력: 기존 `tests/harness/test_mbox_inbox_notify_reply_rate.sh` · `tests/harness/test_inbox.sh` · `tests/harness/test_mbox_reply_exempt_cap.sh`(임시 comm 사본 · 실제 좌석 쪽지 0) + 분리 전후 같은 시나리오 출력 대조
- 기준값: origin/main `78f8c0c739` 정본 `tools/comm-canonical/mbox.sh` = **242줄**(200줄 규칙 초과) = 라이브 `.fable-team/comm/mbox.sh`(cmp 동일). 위 시험 3개 rc=0.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」.
골의 축: C(업그레이드 반영 — 통신 도구를 고치는 카드가 200줄 한도에 계속 걸려 반송되지 않게). 핵심 한 줄: mbox.sh 를 기능 무변화로 진입점 + 도어벨 도우미 두 파일로 나눠 둘 다 200줄 이하로 만든다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
CLAUDE.md Code Metrics 는 파일 200줄 한도다. 전 좌석이 치는 통신 진입점 `mbox.sh`(정본 `tools/comm-canonical/mbox.sh` · 라이브 `.fable-team/comm/mbox.sh`)는 242줄이라 기능 카드가 몇 줄 더할 때마다 한도 위반으로 반송된다. 가장 큰 덩어리는 도어벨(받는 좌석 tmux 에 `recv` 지시문을 주입하는 알림) 도우미 4개 — `_check_name`·`pane_of`·`doorbell`·`doorbell_status`(11–127행 · 117줄)다. 이 카드는 그 117줄을 같은 폴더 `mbox_doorbell.sh` 로 «글자 그대로» 옮기고, 진입점은 `source "$DIR/mbox_doorbell.sh"` 1줄로 부른다. 함수는 호출 시점에 `DIR`·`SELF`·`MBOXPY` 전역을 읽으므로 동작은 같다. 도우미 파일이 없으면 `set -e` 로 `source` 가 실패해 rc=1 + 「No such file」 이 보인다(조용한 대체 0 · #0 규칙). 시험 2개가 임시 폴더에 `mbox.sh`·`mbox.py` 만 복사하므로 도우미도 같이 복사하게 고친다.

## 사전검증
- 소환: 아니오 — 구조 이동(117줄 바이트 동일 이동 + source 1줄)이고 동작·메시지 문구 변경 0. arch 서명 byz-harness-arch-claude#21(원 카드 #14 서명 승계).
- 최종 DA: ★예 1회(완성 이동 때)★ — 전 좌석 통신 진입점이고 라이브 설치가 뒤따른다. 질문 고정: Q1 동작 동일(본문 바이트 동일 · 시험 3개 · 분리 전후 출력 대조) · Q2 도우미 경로(`$DIR` 해석 · 파일 없음 = 크게 실패) · Q3 사본 만드는 곳(시험·README·drift) 누락 0. bounded(새 요구 0 · 2 HOLD 면 리뷰 종료 → arch 서명).

## 조사 근거 (origin/main `78f8c0c739` · arch#21)
- 구조: 1–9 머리·`DIR`·`MBOXPY`·`SELF` · 11–127 도어벨 도우미 4개 · 129–178 `_seats_json`·`notify_policy`·`seq_of`·`inbox_ingest`·`inbox_must_ring` · 180–242 `case` 분기(send·relay·recv·peek·ring).
- 도우미 안 전역 참조: `$SELF`(106·108행 · 도어벨 지시문) · `${TMPDIR:-/tmp}`(68–69행) — 둘 다 진입점이 정한 값을 호출 시점에 읽는다.
- 사본을 만드는 곳(도우미도 같이 실어야 하는 곳): `tests/harness/test_mbox_inbox_notify_reply_rate.sh` 17·139행 · `tests/harness/test_inbox.sh` 163행 · `tools/comm-canonical/README.md` 복구 명령(44행 부근) · `tools/comm-canonical/check-drift.sh` MAP. `test_mbox_reply_exempt_cap.sh` 는 mbox.py 만 복사 — 해당 없음.
- 라이브 실사본은 루트 `.fable-team/comm/mbox.sh` 하나(워크트리들의 `tools/comm-canonical/mbox.sh` 는 tracked 정본 사본).
- ★check-drift.sh MAP 은 전부 옛 경로★(`.worktrees/v6-realtime-live/…` — 그 워크트리가 없어 지금 모든 행 MISSING_RUNTIME). 이 카드는 «분리 쌍» 두 행만 실제 라이브로 고친다(아래 범위 3). 나머지 행 정리는 별 카드 후보.
- ★arch#21 사본 실측(이 처방 그대로)★: 진입점 **127줄** · 도우미 **120줄**(머리 3줄 + 117) · 두 파일 `bash -n` OK · 도우미 본문 diff 0 · 진입점 뒤쪽(128행~) diff 0 · 시험 3개 rc=0(시험 복사 줄 3곳 고친 뒤 · 안 고치면 notify_reply_rate·inbox 가 「도우미 없음」으로 FAIL) · 도우미 없는 폴더에서 `mbox.sh peek` = rc=1 + 「No such file」.

## 구현 범위 (닫힌 목록 — 이것만)
커밋 2개 · 자기 브랜치 · **push 금지**.
1. `[structure]` 커밋:
   - 새 `tools/comm-canonical/mbox_doorbell.sh` = 머리 2줄(`#!/bin/bash` · `# mbox.sh 가 source 하는 도어벨 도우미 — 세션명 검사·pane 찾기·tmux 알림 주입. 단독 실행 0(DIR·SELF 는 mbox.sh 가 정한다).`) + 빈 줄 + 옛 mbox.sh 11–127행 «바이트 그대로». 실행 비트 = mbox.sh 와 같게.
   - `tools/comm-canonical/mbox.sh`: 10–127행(10행 = 빈 줄)을 아래 3줄로 바꾼다(빈 줄 + 주석 + source) — 결과 12줄 머리 + 옛 128행~. 나머지 0 변경.
     ```

     # 도어벨 도우미(_check_name·pane_of·doorbell·doorbell_status) = 같은 폴더 mbox_doorbell.sh — 200줄 규칙 분리
     source "$DIR/mbox_doorbell.sh"
     ```
   - 시험 사본 3곳: `test_mbox_inbox_notify_reply_rate.sh` 17행·139행 · `test_inbox.sh` 163행의 `cp … mbox.sh …` 에 `"$REPO/tools/comm-canonical/mbox_doorbell.sh"` 를 더한다(다른 줄 0).
2. `[docs]` 커밋: `tools/comm-canonical/README.md` 진입점 복구 명령 바로 아래에 같은 꼴의 `cp tools/comm-canonical/mbox_doorbell.sh <같은 comm 폴더>/mbox_doorbell.sh` 1줄 + 「★두 파일은 한 쌍 — 도우미를 먼저 복사한다★」 1줄.
3. 같은 `[structure]` 커밋에 `tools/comm-canonical/check-drift.sh` MAP: `"mbox.sh|…"` 행을 실제 라이브 `"mbox.sh|.fable-team/comm/mbox.sh"` 로 고치고 바로 아래 `"mbox_doorbell.sh|.fable-team/comm/mbox_doorbell.sh"` 1행 추가(주석 1줄: 「v6-realtime-live 워크트리 소멸 뒤 라이브 = 루트 .fable-team/comm — 분리 쌍만 고침, 나머지 행은 별 카드」).

**금지**: 동작·메시지 문구 변경 · `mbox.py` 수정 · 라이브 `.fable-team/comm` 쓰기(설치는 master) · check-drift MAP 의 다른 행 · 다른 도구.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `wc -l` 진입점 ≤ 200 · 도우미 ≤ 200 · 두 파일 `bash -n` · `shellcheck`(있으면) 새 경고 0.
- 본문 동일: `diff <(git show origin/main:tools/comm-canonical/mbox.sh | sed -n 11,127p) <(tail -n +4 tools/comm-canonical/mbox_doorbell.sh)` 출력 0 · `diff <(git show origin/main:tools/comm-canonical/mbox.sh | sed -n '128,$p') <(tail -n +13 tools/comm-canonical/mbox.sh)` 출력 0.
- `bash tests/harness/test_mbox_inbox_notify_reply_rate.sh` rc=0 · `bash tests/harness/test_inbox.sh` rc=0 · `bash tests/harness/test_mbox_reply_exempt_cap.sh` rc=0.
- 분리 전후 대조: 임시 `FT_MBOX_DIR`·`FT_ROOT`·`FT_SEATS_JSON` 에서 같은 시나리오(send · relay · recv · peek · ring 없는 세션 · `BAD_SESSION_NAME` 거부 · `--no-notify` 경고)를 옛 mbox.sh(origin/main)와 새 쌍으로 돌려 stdout·stderr·rc diff 0(seq·시각·임시 경로만 치환).
- 도우미 없음 = 크게 실패: 진입점만 있는 폴더에서 `bash mbox.sh peek x` rc≠0 + stderr 에 `mbox_doorbell.sh`.
- `bash tools/comm-canonical/check-drift.sh | grep -E 'mbox(_doorbell)?\.sh'` = 두 줄(라이브가 옛 판이라 지금은 `mbox.sh` DRIFT · `mbox_doorbell.sh` MISSING_RUNTIME 이 정상 — RESULT 에 그대로 · 설치 뒤 master 가 SAME 두 줄 확인).
- RESULT 에 위 출력 복붙 + 카드 증거 줄(필수 · 시험 칸은 명령 1개): `세트: <40hex> · 시험: bash tests/harness/test_inbox.sh rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 랜딩 뒤 라이브 설치 (master 집행 · 카드 밖 · 앞 단계 값이 다르면 멈추고 보고)
① PR(origin/main · `--body-file`) 병합. ② 라이브 `.fable-team/comm/mbox.sh` = 분리 전 정본(`78f8c0c739`)과 cmp 동일 확인 → 백업 `cp -p .fable-team/comm/mbox.sh .fable-team/comm/mbox.sh.bak-split-20261009`. ③ ★도우미 먼저★ `cp -p tools/comm-canonical/mbox_doorbell.sh .fable-team/comm/mbox_doorbell.sh` + cmp → ★진입점은 원자 교체★ `cp -p tools/comm-canonical/mbox.sh .fable-team/comm/mbox.sh.new && mv -f .fable-team/comm/mbox.sh.new .fable-team/comm/mbox.sh` + cmp(실행 중인 다른 좌석의 bash 가 반쯤 쓴 파일을 읽지 않게 · 순서가 바뀌면 그 사이 모든 send/recv 가 rc=1). ④ 재생: 자기 앞 `send`(self→self 짧은 본문) → `recv` 로 READ 1줄 · `peek` · 다른 좌석 1곳에 실제 발주 1통 → 그 pane 에 `[발주 #seq] bash …/mbox.sh recv …` 지시문 도착 + 그 좌석 recv 성공(도어벨 경로 확인). ⑤ `check-drift.sh` 의 `mbox.sh`·`mbox_doorbell.sh` = SAME 두 줄. ⑥ ★한 곳이라도 실패하면 즉시 원복★(②의 백업을 같은 원자 교체로 · 도우미 파일은 남겨도 무해 — 옛 진입점은 안 부름 · 원장 기록 · 카드 반송). ⑦ 완료 보고 = 랜딩 sha + ④⑤ 결과 1줄.

## 상태
- base_sha: 78f8c0c7398f18ba365ce6234b9f9de971b65eef (spawn 2026-10-09)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#14 · #62821).
- 2026-10-09 — 갱신 (byz-harness-arch-claude#21 · planner 판정 592 ③): 기준값 226→242줄 · 선행 둘 다 랜딩 끝 · 분리 단위를 «도어벨 도우미 117줄» 하나로 확정(사본 실측) · 시험 사본 3곳·check-drift 옛 경로·라이브 원자 교체 순서 추가. spawn 은 master 판단(`--base origin/main`).
- 정본 영향 없음: 통신 도구 구조 분리만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 02:50 — 대기→진행 · 좌석 byz-harness-nano-mbox-sh-split-200#0

## 결과 (나노 RESULT · master#20 옮김 2026-10-09)
세트: 2e70f54e390755465d71321bc0c7bcaca429c148 · 시험: bash tests/harness/test_inbox.sh rc=0 · 이슈: 0
정본 영향 없음: 하네스 통신 도구 파일 분리·시험·README 만 — docs/architect 제품 정본 변경 없음.
