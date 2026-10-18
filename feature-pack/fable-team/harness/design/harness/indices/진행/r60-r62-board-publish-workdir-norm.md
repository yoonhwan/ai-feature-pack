# 인덱스: R60+R62 보드 발행 — launchd 템플릿 WorkingDirectory(R60) + 바뀜 판정 정규화 누락(R62 · 매 틱 발행) (원장 R60·R62 · master#19 쪽지 #66304·#66445)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R60(우선 낮음 · 라이브 해결됨) + R62(우선 보통 · 스냅샷 ~109MB/일) — 같은 파일군이라 한 카드(master#19 쪽지 #66445)
- 상태: 대기
- 선행: v555 랜딩(완료 · PR 1034 · 56961d392a)
- 시험 입력: 템플릿 정적 검사(plutil) + `ft-board-publish.sh` 의 `norm()` 에 고정 본문 쌍을 넣는 시험 — launchd load·실제 gh·Slack 호출 0
- 기준값: ①R60 — v555 첫 가동 2틱 render 실패(`gh issue list` 「not a git repository」 · cwd=/) → 라이브 plist 에 `WorkingDirectory=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` 추가 후 복구(master#19 실측) · 템플릿 `scripts/harness-install/slack-mirror/com.byz.ft-board-publish.plist.template` 에는 그 키 없음. ②R62 — 2026-10-09 가동 뒤 `/tmp/byz-ft-board-publish.log` 「변화 없음」 0회 · 발행(update) 매 틱 · 스냅샷 폴더 11장 3.7MB(01:3x 기준). arch#20 실측: 25초 간격 두 render 를 지금 `norm()`(머리 시각·`정지 N분` 만 지움)으로 비교해도 다름 — 다른 칸은 ⓐ`원 쪽지 뒤 12분`→`13분` ⓑ`(턴 끝 00:58)`→`(턴 끝 01:09)` ⓒ`작업중`↔`정지 N분` ⓓ`확인 불가(첫 턴 전)`→`정지 N분` ⓔ`정지(3분+) 2`→`3`.
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: C(배포·반영 — 라이브에서 손으로 고친 값이 키트 템플릿에 없으면 «전 환경 설치» 때 재발) + A(모니터 — 보드가 시계 숫자 때문에 매 틱 다시 올라가면 «진짜 바뀜» 이 안 보이고 스냅샷이 무한히 쌓인다). 핵심 한 줄: 라이브 plist 와 템플릿이 같은 키를 갖고, 보드는 상태가 실제로 바뀐 틱에만 다시 올라간다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
보드 발행(`scripts/fable-team-bin/ft-board-publish.sh` · 69줄)은 ①launchd 5분 틱으로 돈다 — 템플릿에 `WorkingDirectory` 가 없으면 cwd=/ 라 `ft_board_env.py:59-61` 의 `gh issue list`(리포 지정 없음)가 실패해 발행 0(R60 · 라이브는 손으로 복구됨). ②`FT_BOARD_ONLY_CHANGED=1` 이면 뿌리 글을 `norm()`(30행 · 머리 시각·`정지 N분` 숫자만 지움)으로 직전 발행본과 비교해 같으면 스냅샷·발행 0 — 그런데 좌석 칸(`scripts/fable-team-bin/ft_board_seat.py:53,57,65,69,147`)에는 분마다 바뀌는 조각이 더 있어 매 틱 «다름» 이 된다(R62). 이 카드는 템플릿 키 1개를 넣고, `norm()` 이 «비교 키에서만» 그 조각들을 정규화하게 한다 — ★발행 본문·렌더·스냅샷 형식은 그대로★. 정지 3분 넘김(`⚠`)과 `정지(3분+) N` 수·완료 선언 seq·증거 유무는 «진짜 바뀜» 이라 남긴다.

## 사전검증
- 소환: 아니오
- 면제 사유: 템플릿 키 1개(라이브에서 같은 값 검증됨) + 비교 키 정규화(발행 본문 불변 · 실패 꼴 = 덜 발행 · 새 글 경로 0) — 구현 DA 없음 · arch 재현으로 닫는다 — arch 서명 byz-harness-arch-claude#20

## 조사 근거 (origin/main 78f80f82fe · arch#20)
- `scripts/fable-team-bin/ft-board-publish.sh:30` `norm() { sed -E '1s/[0-9]{2}:[0-9]{2}//; s/정지 [0-9]+분/정지 N분/g' "$1"; }` · 32-36행 비교.
- 좌석 칸 문자열: `ft_board_seat.py:53` `작업중`/`작업중(pane)` · `:57` `대기열 있음(턴 끝 HH:MM)` · `:65` `[⚠]정지 N분(턴 끝 HH:MM)` · `:69` ` · 완료 선언 #seq(HH:MM · 증거 있음|없음)` · `:142-147` ⓪ 열 `정지(3분+) a | 완료 선언 b(… · 원 쪽지 뒤 N분)`. 첫 턴 전 좌석 = `확인 불가(첫 턴 전)`.
- 템플릿 `scripts/harness-install/slack-mirror/com.byz.ft-board-publish.plist.template`(22줄) · 시험 `tests/harness/test_board_publish_tick.sh`(164줄 · ⓘ 가 템플릿 값 검사).

## 구현 범위 (닫힌 목록)
1. (R60) 템플릿에 `<key>WorkingDirectory</key><string>__BYZ_ROOT__</string>` 1줄(그 밖 키 변경 0).
2. (R62) `scripts/fable-team-bin/ft-board-publish.sh` `norm()` 에 규칙 추가(비교 키 전용 · 순서 고정 · sed -E):
   - `원 쪽지 뒤 [0-9]+분` → `원 쪽지 뒤 N분`
   - `\(턴 끝 [0-9]{2}:[0-9]{2}\)` → `(턴 끝 *)` · `\(턴 끝 확인 불가\)` 도 `(턴 끝 *)`
   - (턴 끝 규칙 «뒤»에) `⚠정지 N분(턴 끝 *)` → `⚠STALL`(★먼저★ — 3분 넘김은 남긴다) → 그다음 `정지 N분(턴 끝 *)` → `활동` · `작업중(\(pane\))?` → `활동` · `확인 불가\(첫 턴 전\)` → `활동` (정지 칸은 턴 끝 괄호까지 한 덩어리로 바꾼다 — 작업중 칸엔 턴 끝이 없어서, 괄호를 남기면 `활동` ↔ `활동(턴 끝 *)` 이 다름으로 남는다 · arch#20 실측)
   - 그대로 남김(진짜 바뀜): `⚠` 유무 · `정지\(3분\+\) [0-9]+` · `완료 선언 [0-9]+` · `완료 선언 #seq(HH:MM · 증거 …)` · 진행·큐 수 · 카드 제목.
   + 키트 사본 `scripts/harness-install/fable-team/bin/ft-board-publish.sh` cmp 동일. 스크립트 줄 수 증가 5줄 이하.
3. 시험(`tests/harness/test_board_publish_tick.sh` 에 추가 · 200줄 넘으면 새 파일 `tests/harness/test_board_publish_norm.sh`):
   - ⓙ R60: 템플릿 `WorkingDirectory` = `__BYZ_ROOT__` 이고 `EnvironmentVariables.FT_ROOT` 와 같은 자리표시자(어긋나면 FAIL) · `plutil -lint` OK.
   - ⓚ R62 같음 쌍(norm 후 동일이어야 함): arch 실측 ⓐ~ⓓ 꼴 쌍 4개(`원 쪽지 뒤 12분`↔`13분` · `(턴 끝 00:58)`↔`(턴 끝 01:09)` · `작업중`↔`정지 2분(턴 끝 01:09)` · `확인 불가(첫 턴 전)`↔`정지 0분(턴 끝 01:09)`).
   - ⓛ R62 다름 쌍(norm 후 달라야 함): `정지 2분(…)`↔`⚠정지 4분(…)` · `정지(3분+) 2`↔`3` · `완료 선언 0`↔`완료 선언 1(…)` · `증거 없음`↔`증거 있음` · 진행 수 `진행 1`↔`진행 2`.
   - ⓜ 발행 본문 불변: 같은 입력에서 `body.txt`(발행되는 글)가 수정 전과 바이트 동일(norm 은 비교에만).
   - 변이: `⚠` 선처리 규칙을 빼면 ⓛ 첫 쌍 FAIL · 턴 끝 규칙을 빼면 ⓚ 둘째 쌍 FAIL.
4. 기존 시험 PASS: `tests/harness/test_board_publish_tick.sh` · `tests/harness/test_board_publish.sh` · `tests/harness/test_kit_bin_sync.sh` · `bash -n` · `/bin/bash` 로도 `norm` 동작 동일(launchd 인터프리터 = 템플릿 `/opt/homebrew/bin/bash` 지만 수동 실행 대비).
커밋은 자기 브랜치, **push 금지**. **금지**: `ft_board_env.py`·`ft_board_seat.py`·`ft-board.py` 수정(렌더 불변) · launchd load·라이브 plist 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · `plutil -lint` OK · 키트 cmp 동일.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_board_publish_tick.sh rc=0 · 이슈: 0`.
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다.
- 랜딩 뒤 master 집행(카드 밖): ① 라이브 FT_BIN `ft-board-publish.sh` cp+cmp ② 라이브 plist 와 템플릿 치환본 키 대조 1회(`plutil -p` 두 개 · 차이 0 — 재로드 불필요) ③ 첫 1시간 관찰(12틱 · 원장 1줄): 「변화 없음」 줄 수 > 0 · 스냅샷 장수 증가 = 발행 수 · 발행된 틱마다 diff 가 ⓛ 꼴(진짜 바뀜)인지 1회 확인.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 4c81fa97ad6d313d956a98028e85201ef0cc505d (spawn 2026-10-09)
- 2026-10-09 00:4x — 대기/ 생성 (byz-harness-arch-claude#19 · 원장 R60 · master#19 쪽지 #66304 · 라이브 plist 실측: WorkingDirectory = BYZ 루트).
- 2026-10-09 01:4x — 제안 규칙을 실측 render 2개에 적용: 남은 차이 = `완료 선언 0↔1`·`⚠` 좌석 수 등 진짜 바뀜만.
- 2026-10-09 01:4x — R62 묶음 · 파일 이름 변경(r60-board-plist-workdir → r60-r62-board-publish-workdir-norm) · 25초 간격 render 2회 실측으로 정규화 누락 칸 5종 확정 (byz-harness-arch-claude#20 · master#19 쪽지 #66445).
- 정본 영향 없음: 하네스 launchd 템플릿·발행 비교 키·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 01:29 — 대기→진행 · 좌석 byz-harness-nano-r60-r62-board-publish-workdir-norm#0

## 결과 (나노 RESULT · master#20 옮김 2026-10-09)
세트: e329aad0d3e6d711bd525209da970d094101f8dd · 시험: bash tests/harness/test_board_publish_tick.sh rc=0 · 이슈: 0
정본 영향 없음: 하네스 발행 스크립트·launchd 템플릿·시험만 — docs/architect 제품 정본 변경 없음.
