# 인덱스: 제안서 발행기 — 기존 스레드가 있는 승인 제안서를 «기록 rN» 답글로 발행 (R80 · R76 후속)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R80(master#25 발주 #71760 · 재현 v65 arch#197 · R76 후속)
- 상태: 대기
- 선행: 없음
- 제안서: 없음 — 도구 결함 수정(R76 후속)
- 시험 입력: 기존 가짜 슬랙 fixture(`tests/scripts/_proposal_fakes.py` `make_md(status=…)` · `slack` · `t` · `pub`) — 실 슬랙 0
- 기준값: r0~r2 스레드가 있는 제안서를 `- 상태: 승인 — 판정 N` 으로 바꾸면 ①`--revision` 없이 = `check_pinned` 가 「r0 은 <hash> 원문으로 진행됨 — 바뀐 원문은 다음 rN(--revision)」 raise ②`--revision r3` = `run` 이 「기록 제안서는 rN 없음 — 새 제안서로」 rc 1 → 두 길이 서로 막는다(재현 입력 = v65 lst-loud 제안서 r3(경로는 증거 폴더) 30a4d5938e · dry-run · 판정 841 오탐 처리(게이트 «재현 입력» 구분은 R81))

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
골의 축: B 「메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의」 + C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행(슬랙) 수신해 반영」. v65 arch#197 이 올린 도구 결함 · R76 후속.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
R76 은 «승인 — 판정 N» 제안서를 «기록»으로 발행하게 했지만, 스레드가 없는 제안서(r0)만 생각하고 «기록 제안서는 rN 없음» 으로 막았다. 실제로는 초안·컨펌 대기로 r0~r2 를 올린 뒤 승인된 제안서가 대부분이다. 그 제안서는 r0 원문이 이미 고정돼 있어 r0 으로는 못 올리고(원문 고정 검사), rN 으로는 R76 의 금지에 걸린다. 이 카드는 «승인 + `--revision rN`» 을 허용해 기존 스레드에 «기록 rN» 답글을 단다. 답글 첫 줄은 `*제안서 <key> rN · 기록 판정 N*` 이고, 본문은 R76 기록 글과 같다(결정 자리 줄 0 · 「결정할 것: 없음 — 판정 N 으로 승인됨」). 스레드가 없는 승인 제안서의 r0 기록 발행은 지금 그대로다. 새 플래그는 만들지 않는다(상태 줄 + `--revision` 이 이미 뜻을 다 말한다).

## 사전검증
- 소환: 아니오
- 면제: R76 이 넣은 금지 1곳 제거 + 첫 줄 함수 1곳(rN 포함) + 뿌리 글 원격 찾기 1곳(일반 r0 줄 다음 기록 r0 줄) · 기존 흐름은 기존 시험 전부 PASS 로 닫음 — arch 서명 byz-harness-arch-claude#26

## 조사 근거 (기준 = origin/main 61384daf80 추적본 · 라이브 `~/.hermes/scripts` 의 두 파일은 main 과 다르다 — 설치 때 diff 확인)
- `scripts/harness-install/slack-mirror/byz_proposal_publish.py:171`~`:173` 기록 + rN 금지 · `:87`~`:94` `_root_ts`(원격 찾기는 일반 r0 첫 줄만) · `:105` `check_pinned` · `:103` 첫 줄 만들기(`first_line(key, rev, record)`).
- `scripts/harness-install/slack-mirror/proposal_text.py:17`~`:20` `first_line` — record 면 rev 를 무시해 기록 r0 과 기록 rN 의 첫 줄이 같아진다(중복 게시 방지 찾기가 서로를 채택할 수 있다).
- `scripts/harness-install/slack-mirror/proposal_files.py:25`~`:27` `check_pinned`(바꾸지 않음).
- `tests/scripts/test_proposal_publish.py:72`~`:79` 「기록 + rN 거부」 시험 — 이 카드가 뒤집는다.

## 구현 범위 (닫힌 목록 · 나노 브랜치는 origin/main 기준)
1. `scripts/harness-install/slack-mirror/proposal_text.py` `first_line`: record 면 r0 = `*제안서 {key} · 기록 판정 {N}*`(지금 그대로) · rN = `*제안서 {key} {rev} · 기록 판정 {N}*`. 머리표는 지금처럼 `작업상황`.
2. `scripts/harness-install/slack-mirror/byz_proposal_publish.py`:
   - `:171`~`:173` 금지 3줄을 지운다.
   - `_root_ts`: 원격 찾기를 일반 r0 줄(`first_line(key, "r0")`)로 먼저 하고, 없으면 기록 r0 줄(`first_line(key, "r0", record)`)로 한 번 더 한다. `record` 는 인자로 받는다. 둘 다 없으면 지금처럼 「뿌리 글 없음」 raise.
   - 파일이 200줄을 넘으면 늘어난 줄만큼 `proposal_text.py` 로 옮긴다(새 파일 0).
3. 시험(`tests/scripts/test_proposal_publish.py`):
   - ①`test_record_proposal_with_revision_is_refused_before_any_post` 를 지운다.
   - ②새 시험: r0(컨펌 대기) · r1 · r2(수정 요청) 발행 → 같은 파일을 `승인 — 판정 351` 로 바꿔 `--revision r3` → 같은 스레드 답글 1개 · 첫 줄 `*제안서 <KEY> r3 · 기록 판정 351*` · 「결정 자리」 줄 0 · md·html 첨부 2 · 같은 r3 재실행 skip(게시 추가 0).
   - ③새 시험: 같은 상황에서 `--revision` 없이 → 지금처럼 원문 고정 raise(「다음 rN(--revision)」 안내) · 게시 0.
   - ④새 시험: 스레드 없는 승인 제안서 + `--revision r1` → 「뿌리 글 없음」 raise · 게시 0.
   - ⑤새 시험: 기록 r0 으로 시작한 스레드(뿌리 = 기록 r0 줄) + 상태 파일 없음 + `--revision r1` → 원격에서 기록 r0 뿌리를 찾아 그 스레드에 답글.
   - ⑥기존 시험 전부 PASS(`test_proposal_publish.py` · `test_proposal_publish_faults.py` · `test_thread_post.py`).

커밋은 자기 브랜치, **push 금지**. **금지**: 새 CLI 플래그 · `check_pinned`·상태 파일 모양 변경 · 초안·컨펌 대기·수정 요청 글 모양 변경 · 실 슬랙 · 라이브 `~/.hermes/scripts` 직접 수정.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `python3 -m pytest tests/scripts/test_proposal_publish.py tests/scripts/test_proposal_publish_faults.py tests/scripts/test_thread_post.py -q` rc=0 · `ruff check` 변경 파일 0 · 두 파일 200줄 이하.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/test_proposal_publish.py tests/scripts/test_proposal_publish_faults.py tests/scripts/test_thread_post.py -q rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 `~/.hermes/scripts/{byz_proposal_publish.py,proposal_text.py}` `.bak-r80-<날짜>` 백업 → 추적본 `cp` → `cmp`(지금 라이브 두 파일은 main 과 바이트가 다르다(2026-10-10 실측) — 설치 전에 그 차이가 무엇인지 `diff` 로 먼저 본다) · 재현 제안서로 `--revision r3 --dry-run` 1회(첫 줄 확인) · v65 arch#197 에 1줄.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 61384daf8015ab9f4d9dd52f506f0aca3ed5aff1 (spawn 2026-10-10)
대기 — master spawn 대기

## 결과
(닫을 때 증거 줄)
- 2026-10-10 11:08 — 대기→진행 · 좌석 byz-harness-nano-r80-proposal-publish-record-revision#0
세트: 4a55bf0dd5696d0b7ef16cb23f8c0f8395d30da1 · 시험: python3 -m pytest tests/scripts/test_proposal_publish.py tests/scripts/test_proposal_publish_faults.py tests/scripts/test_thread_post.py -q rc=0 · 이슈: 0
- 2026-10-10 — 닫힘: 커밋 4a55bf0dd5[fix] · 52 passed(마스터 재실행) · ruff 0 · 라이브 설치 .bak-r80-<ts> + cmp OK(R77 미설치분 동반) · 재현 r3 dry-run 첫 줄 «*제안서 v65/lst-loud-evidence-cap r3 · 기록 판정 837*» · main 랜딩 PR 1182 a3cbe3ba92 (판정 843)
