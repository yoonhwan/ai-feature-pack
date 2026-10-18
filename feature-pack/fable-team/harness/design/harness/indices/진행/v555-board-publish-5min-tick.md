# 인덱스: v555 보드 발행 5분 틱 — launchd 5분 · 변화 있을 때만 같은 뿌리 글 chat.update · 새 글 0 · 변화 없으면 스냅샷·호출 0 (판정 555 ② · master#19 쪽지 #65802)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 555 ②(master#19 쪽지 #65802 · 「보드 발행을 5분 틱에 신설 · 같은 뿌리 chat.update 만 · 새 글 0 · 변화 없으면 호출 0」)
- 상태: 대기
- 선행: v423b 랜딩 뒤(순서만 · 파일 겹침 0) · v423a(§83 · #1014) 랜딩 완료 — `ft-board-publish.sh`·`ft_board_root.py` 위에 얹는다
- 시험 입력: 기존 `tests/harness/test_board_publish.sh` 의 임시 FT_ROOT + 스텁 FT_BOARD_BIN + 가짜 슬랙 base — 실제 슬랙 호출 0
- 기준값: (arch#19 실측 · 실제 루트 읽기 전용 23:4x) ①지금 주기 호출자 0 — `ft-news-tick.sh`(origin/main 49줄)·launchd 8개·`bin-planner/` 어디에도 `ft-board-publish` 호출 없음 · 발행은 23:11 수동 1회(`state/board/2026-10-08/published.txt` 2,913B) ②스냅샷 1장 378KB(v65 축 entries 716) — 지금 꼴로 5분 틱이면 288장/일 ≈ **109MB/일** · `prune` 은 명시 명령만 ③23:10:59 → 23:11:20 두 스냅샷의 차이는 «정지 N분» 숫자·좌석 working·pending/unreported 수 → 21초 만에 hash 가 바뀐다 ④뿌리 글 본문에도 `⚠정지 4분(턴 끝 23:06)` 꼴(⓪ 팀 줄)과 머리 시각 `[상태] 메인팀 보드 23:11` 이 들어가 «매 틱 변화»로 읽힌다.
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: C(배포 발행(슬랙) — 보드가 사람 손 없이 주기 발행). 핵심 한 줄: 5분마다 돌되 «뿌리 글이 실제로 바뀔 때만» 스냅샷 1장 + chat.update 1회, 아니면 아무것도 안 쓴다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
v423a(§83)로 `scripts/fable-team-bin/ft-board-publish.sh` 가 «스냅샷 먼저 → 하루 1 뿌리 글 update + 변화 답글 → 날짜 동결»을 하게 됐지만 부르는 곳이 없어 보드가 수동 1회에 멈춰 있다. 그대로 5분 틱에 걸면 두 가지가 터진다: ①`ft-board-publish.sh:21` 이 매번 `snapshot` 을 불러 378KB 를 쓰고(분 단위 숫자 때문에 hash 가 항상 다름 · 하루 109MB · 삭제 경로 = 명시 `prune` 뿐) ②`:37` 이 변화와 무관하게 매번 `update` 를 불러 슬랙 chat.update 를 288회/일 친다. 이 카드는 발행 스크립트 앞에 «바뀜 판정»을 두어(뿌리 글을 먼저 만들고, 분 숫자·머리 시각만 지운 꼴로 직전 발행본과 비교) 같으면 스냅샷·호출 0 으로 끝내고, 다르면 지금 경로 그대로 간다. 답글 실패(rc 3) 뒤 복구는 표식 파일로 다음 틱에 1회 더 부른다. 주기 실행은 launchd 5분 plist 템플릿으로(설치는 master).

## 사전검증
- 소환: 아니오
- 면제 사유: 발행 경로·스냅샷 형식·뿌리 글 렌더 변경 0 — 앞에 «안 부를 조건» 하나를 더할 뿐이라 실패 꼴이 «덜 발행»(다음 변화 때 따라잡음) · 새 글 생성 경로 0 · 구현 DA 는 완료 조건에 없음(실패 = 발행 0 + rc) — arch 서명 byz-harness-arch-claude#19
- ★스냅샷 보존 = 판정 558 ③ ⓐ 확정(master#19 쪽지 #65914)★: 날짜 첫 발행 때 `ft-board.py prune --days 7` 자동 1회 — 바뀜 판정으로 쓰기가 줄어도 좌석 작업중↔정지 전환만으로 하루 수십~백여 장(×378KB)이 남으므로 삭제 경로를 틱에 둔다(무한 증가 = 완성 전 결함). 구현 범위 4 포함.

## 조사 근거 (origin/main b4ce4ab0a5 · arch#19)
- `scripts/fable-team-bin/ft-board-publish.sh:21-22` snapshot 먼저 · `:23-29` render → `ft_board_root.py root` → body.txt · `:31-33` 변화 답글 · `:36-39` update + published.txt · `:42-51` 날짜 동결. 52줄.
- `scripts/fable-team-bin/ft_board_snapshot.py:64-81` snapshot(매 호출 쓰기 · 「입력이 직전과 같아도 막지 않는다」) · `:84-89` prune.
- `scripts/fable-team-bin/ft-news-tick.sh` — board 호출 없음(§83 「호출부 교체」 대상이 없었다).
- launchd 템플릿 꼴: `scripts/harness-install/slack-mirror/com.byz.ft-magazine.plist.template`.
- 시험 `tests/harness/test_board_publish.sh`(152줄).

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-board-publish.sh` — `:21` snapshot «앞»에 바뀜 판정(새 env `FT_BOARD_ONLY_CHANGED=1` 일 때만 · 기본 0 = 지금 동작 그대로 · 수동 발행은 항상 발행):
   - render → `ft_board_root.py root` 를 먼저 만들어 `$TMP/body.txt`(지금 `:23-29` 를 위로 옮김 · 출력 동일).
   - 정규화 = 첫 줄의 `HH:MM` 삭제 + `정지 [0-9]+분` → `정지 N분`(그 밖 글자 그대로). `$SD/$DAY/published.txt` 를 같은 정규화로 비교.
   - 같고 ∧ `$SD/$DAY/reply_pending` 표식 없음 → `echo "ft-board-publish: 변화 없음 — 스냅샷·발행 0"` 후 exit 0. published.txt 없음(날짜 첫 발행) = 다름.
   - 다르면 지금 경로 그대로(snapshot → 답글 → update → published.txt → 동결). update rc=3 이면 `reply_pending` 표식 생성, rc=0 이면 삭제.
2. 키트 사본 `scripts/harness-install/fable-team/bin/ft-board-publish.sh` 같은 바이트.
3. launchd 템플릿 `scripts/harness-install/slack-mirror/com.byz.ft-board-publish.plist.template`(새 파일 · `com.byz.ft-magazine.plist.template` 꼴) — StartInterval 300 · env `FT_BOARD_ONLY_CHANGED=1` · 로그 `/tmp/byz-ft-board-publish.log`. 설치·load 는 master(카드 밖).
4. (판정 558 ③ ⓐ) 바뀜 판정 통과 뒤 «날짜 첫 발행»(published.txt 없음)에서 `"$BOARD" prune --days 7` 1회 · 실패 = 기록만(발행 rc 불변).
5. 시험 `tests/harness/test_board_publish.sh` 에 추가(또는 200줄 넘으면 새 `tests/harness/test_board_publish_tick.sh`):
   - ⓐ ONLY_CHANGED=1 · 같은 본문 2회 → 2회째 snapshot 호출 0 · update 호출 0 · rc 0 · 「변화 없음」.
   - ⓑ 분 숫자·머리 시각만 다름 → 호출 0. ⓒ 카드 상태 1개 다름 → snapshot 1 + update 1.
   - ⓓ update rc=3 → reply_pending 생성 → 다음 틱 본문 같아도 update 1회 → rc 0 이면 표식 삭제.
   - ⓖ 날짜 첫 발행 → 스텁 BOARD 에 `prune --days 7` 1회 · prune 실패 주입 → 발행 rc 불변 + 기록 1줄 · 같은 날 2번째 발행 → prune 0.
   - ⓔ ONLY_CHANGED 미설정 → 같은 본문이어도 지금처럼 update(수동 발행 동작 불변). ⓕ 날짜 첫 발행 → 다름으로 취급.
   - 기존 시험 전부 PASS(`tests/harness/test_board_publish.sh` · `tests/harness/test_kit_bin_sync.sh` · `tests/harness/test_board.sh`).
커밋은 자기 브랜치, **push 금지**. **금지**: 실제 슬랙 호출 · `ft_board_render.py`·`ft_board_root.py`·`ft_board_snapshot.py` 수정(렌더·스냅샷 형식 불변) · 새 슬랙 글(post) 경로 · launchd load·라이브 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 시험 rc=0(위 5) · `bash -n` · 사본 cmp · 새·고친 파일 200줄 이하 · `plutil -lint` 템플릿(치환 전 자리표시자 외 형식 OK).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_board_publish.sh rc=0 · 이슈: 0`.
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp+cmp · plist 설치·load · 첫 1시간 관찰 = update 호출 수 · 스냅샷 장수 · 「변화 없음」 줄 수 · err `msg_too_long` 0.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 7a13b099e92422c7f0d18c7bdd4a83e3ab4032c9 (spawn 2026-10-09)
- 2026-10-08 23:5x — 판정 558 ③ ⓐ 반영(스냅샷 보존 7일 자동 prune 확정 · 구현 범위 4 · 시험 ⓖ) — byz-harness-arch-claude#19.
- 2026-10-08 23:4x — 대기/ 생성 (byz-harness-arch-claude#19 · 판정 555 ② · master#19 쪽지 #65802 · 기준값 실측 위).
- 범위 밖(별 카드 후보 · 판정 555 ② 「①②③ 빠짐은 뿌리 요약 3줄로 대체 검토」): 뿌리 글에 ①완성 트리·②세션 트리·③큐 요약 3줄을 넣는 일은 `ft_board_root.py` 렌더 변경이라 이 카드(발행 주기)와 분리한다 — 지금 뿌리 글 2,913B · 상한 3,500B 라 3줄(줄당 ~150B) 여유는 있음. arch 권고 = 이 카드 랜딩·1시간 관찰 뒤 별 카드.
- 정본 영향 없음: 하네스 발행 스크립트·launchd 템플릿·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 00:15 — 대기→진행 · 좌석 byz-harness-nano-v555-board-publish-5min-tick#0
- 2026-10-09 — 완료 증거(arch r2 재현·서명 · DA 없음): 세트: c31bac8052a827a86b222599b0e7fe9286b014d3 · 시험: bash tests/harness/test_board_publish_tick.sh rc=0 · 이슈: 0
- 정본 영향 없음: 하네스 보드 발행 스크립트·launchd 템플릿·시험만 — docs/architect 제품 정본 변경 없음.
