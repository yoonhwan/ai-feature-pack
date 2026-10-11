# 인덱스: R59 Tank 래퍼 comment-edit — byz-tank 가 쓴 Issue 코멘트만 수정 · 작성자 다르면 raise · 수정 전 원문 보관 (원장 R59 · 판정 564 · issues#6 쪽지 65989)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R59(판정 564 · 우선 높음 · R58·v558 보다 앞 순서)
- 상태: 대기
- 선행: 없음
- 시험 입력: 기존 `tests/harness/test_gh_as_tank.sh` 와 같은 꼴 — 임시 폴더 + PATH 맨 앞 가짜 gh(호출 인자·stdin 기록) · 실제 GitHub 호출 0
- 기준값: issues#6 이 자기(byz-tank) 코멘트의 정본 줄을 고치려다 `gh-issue-author-guard.sh` 에 막힘(쓰기용 `gh api …/issues/comments` 차단 · 우회 0 · 쪽지 65989) — 래퍼에 코멘트 수정 동작이 없다(origin/main `ft-gh-as-tank.sh` 182줄 · 동작 10종에 comment-edit 없음).
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 6-b(메인 오케 개선요청 — issues 팀 R59). 핵심 한 줄: Tank 가 쓴 코멘트는 Tank 이름으로만 고친다 — 남의 코멘트·조회 실패·보관 실패면 수정 시도 0.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
모든 Issue 쓰기는 `scripts/fable-team-bin/ft-gh-as-tank.sh`(Tank 봇 토큰 · 기본 dry-run · `--apply` 때만 실행 · 토큰 주인 byz-tank 확인)로만 나가고, 직접 `gh api` 쓰기는 `gh-issue-author-guard.sh` 훅이 막는다. 래퍼에는 Issue 본문 수정(`edit` — 수정 «전» 원문 보관 뒤에만 수정)은 있지만 «코멘트» 수정이 없어 issues 팀이 자기 코멘트의 정본 줄을 못 고친다. 이 카드는 `comment-edit <comment_id> <본문파일>` 을 더한다: ①GitHub API 로 코멘트를 읽어 작성자(`user.login`)가 Tank 인지 확인(아니면 exit 1 · 폴백 0) ②원문을 `edit` 와 같은 보관 폴더에 저장한 «뒤에만» ③`PATCH repos/<repo>/issues/comments/<id>` 로 본문 교체 ④응답 본문이 파일과 같은지 확인. 래퍼가 이미 182줄이라 본체는 새 스크립트에 두고 래퍼는 `create` 가 `ft-issue-create-pair.sh` 에 넘기듯 토큰 확인 뒤 위임만 한다. 가드 훅은 바꾸지 않는다(래퍼 경유는 이미 통과 · 직접 `gh api` 쓰기 차단은 그대로).

## 사전검증
- 소환: 아니오
- 면제 사유: 새 쓰기 경로이지만 범위가 «Tank 작성 코멘트 1개» 로 닫혀 있고 실패 꼴은 전부 «수정 시도 0»(작성자 불일치·조회 실패·보관 실패 = exit 1) · 기존 `edit` 의 보관 규약을 그대로 따름 · 가드 변경 0 · 구현 DA 없음 — arch 독립 재현으로 닫는다 — arch 서명 byz-harness-arch-claude#19

## 조사 근거 (origin/main 73d9c25819 · arch#19)
- `scripts/fable-team-bin/ft-gh-as-tank.sh:2-26` 머리말(동작 목록) · `:34` usage · `:46-122` 동작별 인자 검사 · `:124-132` dry-run · `:135-139` 토큰·주인 확인 · `:141-143` create 위임(토큰을 env 로 넘김) · `:144-163` edit 보관 규약(`FT_ISSUE_EDIT_BAK_DIR` 또는 git common dir 루트 `.fable-team/state/issue-edit-bak/`) · `:177-180` 되돌림 출력. 182줄.
- `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh:4-6` 차단 목록(쓰기용 `gh api …/issues/…/comments`) · 래퍼 경유 통과 — 변경 0.
- 시험 `tests/harness/test_gh_as_tank.sh`(286줄 · 가짜 gh `:14`).

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. 새 `scripts/fable-team-bin/ft-gh-tank-comment-edit.sh <comment_id> <본문파일>` — 토큰은 env `FT_TANK_TOK` 로만 받는다(인자·출력 0 · 없으면 exit 2). env `FT_ISSUE_REPO`·`FT_TANK_LOGIN`·`FT_ISSUE_EDIT_BAK_DIR` 는 래퍼와 같은 이름·기본값.
   - ⓐ `gh api repos/$REPO/issues/comments/<id>` → `user.login`·`body`·`html_url`. 실패·빈 응답·JSON 해석 실패 = exit 1(수정 시도 0).
   - ⓑ `user.login` ≠ Tank → `REJECT 코멘트 작성자가 byz-tank 가 아니다(작성자=…)` exit 1.
   - ⓒ 원문 보관 `<BAKDIR>/comment<id>-<UTC시각>.body.md`(래퍼 `edit` 와 같은 폴더 규칙) — 실패 = exit 1(수정 시도 0).
   - ⓓ 수정 = 본문 파일을 python `json.dumps({"body": …})` 로 감싸 `gh api -X PATCH repos/$REPO/issues/comments/<id> --input -`(본문을 `-f`/`-F` 인자로 넘기지 않는다 — 형 변환·길이 문제). 응답 `body` 가 파일 내용과 다르면 exit 1.
   - ⓔ 성공 출력 `OK as=byz-tank comment-edit <id> — <html_url> bak=<파일>` + 되돌림 1줄(`… comment-edit <id> <bak 파일> --apply`). 200줄 이하.
2. `scripts/fable-team-bin/ft-gh-as-tank.sh`: 머리말·usage 에 `comment-edit <comment_id> <본문파일>` · case 에 인자 검사(id 정수 · 파일 실재 · 2개) · dry-run 출력 `DRY as=byz-tank comment-edit <id> <파일>` · 토큰·주인 확인(`:135-139`) 뒤 `FT_TANK_TOK="$TOK" bash "$HERE/ft-gh-tank-comment-edit.sh" "$@"; exit $?`. 200줄 이하 유지(늘린 줄 수 RESULT 에 명시).
3. 키트 사본 `scripts/harness-install/fable-team/bin/` 의 두 파일 같은 바이트 · 755.
4. 새 시험 `tests/harness/test_gh_tank_comment_edit.sh`(가짜 gh · `test_gh_as_tank.sh` 꼴):
   - ⓐ dry-run → gh 호출 0 · DRY 줄. ⓑ 작성자 byz-tank → GET 1 · PATCH 1(stdin JSON 의 body = 파일 내용 · 따옴표·줄바꿈·백틱 포함 본문) · 보관 파일 = 원문 · OK 줄 + 되돌림 줄.
   - ⓒ 작성자 다른 계정 → PATCH 0 · exit 1. ⓓ GET 실패 → PATCH 0 · exit 1. ⓔ 보관 폴더 쓰기 불가 → PATCH 0 · exit 1.
   - ⓕ 토큰 없음 → exit 2 · gh 호출 0. ⓖ 토큰 주인 ≠ byz-tank → exit 1 · comment GET 0. ⓗ 응답 body ≠ 파일 → exit 1.
   - ⓘ 출력·로그 어디에도 토큰 값 0. ⓙ 인자 오류(id 비정수 · 파일 없음 · 인자 수) → exit 2.
   - 기존 `tests/harness/test_gh_as_tank.sh` · `tests/harness/test_kit_bin_sync.sh` PASS.
커밋은 자기 브랜치, **push 금지**. **금지**: 가드 훅 수정 · 실제 GitHub 호출 · PR 리뷰 코멘트(`pulls/comments`) 수정 경로 · 작성자 확인 생략 옵션 · 라이브 `.fable-team/` 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 시험 rc=0(위 4) · `bash -n` · 사본 cmp · 755 · 두 스크립트 200줄 이하.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_gh_tank_comment_edit.sh rc=0 · 이슈: 0`.
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp+cmp(두 파일) → issues#6 에 랜딩 sha + 사용법 1줄 통지 → issues#6 의 첫 실제 수정 1회 결과(OK 줄 · bak 파일) 회수.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 45d9d91d4529e8cd20dd63c8a4a30225d73d5556 (spawn 2026-10-08)
- 2026-10-08 23:5x — 대기/ 생성 (byz-harness-arch-claude#19 · 원장 R59 · 판정 564 · master#19 쪽지 #65997).
- 정본 영향 없음: 하네스 Tank 래퍼·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 23:51 — 대기→진행 · 좌석 byz-harness-nano-r59-tank-comment-edit#0
- 2026-10-08 23:5x — 완료 증거(arch 재현·서명): 세트: 6fa90c8524e939e62361a698448baf7d64458321 · 시험: bash tests/harness/test_gh_tank_comment_edit.sh rc=0 · 이슈: 0
- 정본 영향 없음: 하네스 gh 래퍼·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 23:58 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§86
