# PLAN — R29 squash 랜딩 뒤 나노 닫기: «squash 된 PR 역사»를 superseded 증거로 (2026-10-08 · byz-harness-arch-claude#12)

## 골 원문 (GOAL-harness.md 복붙)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: 6-b(개선요청 접수·협의). 원장 R29(feature master#3 #62204 · planner#9 승인 조건 ③ · master#14 #62205).

## §1 실측 (사례 byz-feature-nano-f-guest-jwt-impl-s1#0 · 브랜치 nano/f-guest-jwt-impl-s1 · 2026-10-08 13:4x)
`ft-nano-cherry-gate.sh origin/main nano/f-guest-jwt-impl-s1` = REJECT(merge-tree 충돌 rc=1 + 「tip 내용이 origin/main 역사에 없는 경로」 20+ · git cherry «+» 79개 중 코드 커밋 11).
| 사실 | 값 |
|---|---|
| «+» 커밋이 건드린 경로 | 73 (design/ 52 · 코드 21) |
| 코드 21 중 나노 tip blob == main blob | 19 |
| 다른 2 | gateway/infrastructure/auth/sse_identity.py · gateway/routes/sse/v1/rooms.py — main 쪽이 앞섬(구형 user_id 처리를 sse_identity 로 이동한 리팩터) |
| 그 2 의 나노 blob 이 어디 있나 | PR #905 브랜치 feat/guest-jwt-896-stage1 의 96b67fdda9(나노 내용 그대로) → 같은 PR 의 b52a55dc6a([structure] 파일 길이 예산 리팩터)가 고침 → PR head b52a55dc6a 를 squash 해 main cef86d391a(#905) |
| design/ 52 | feature 문서 줄기(feature-main) 파일 — main 에 아직 안 간 문서. 코드 아님 |

## §2 왜 깨지나 (feature master 질문 ①)
게이트의 superseded 증거 = «나노 tip blob 이 merge-base..main 구간에 새 blob 으로 있었다». squash 랜딩은 PR 의 «최종» 트리만 main 에 남긴다 — PR 안에서 나노 내용 뒤에 커밋이 더 있으면(리뷰 수정·리팩터) 나노 blob 은 main 역사에 한 번도 안 나타난다. 그래서 «상위집합인데 증거 없음» → REJECT. 문서 경로(design/)도 같은 검사에 섞여 REJECT 목록을 채운다(코드 «+» 커밋이 문서도 같이 건드리면 그 문서 경로까지 superseded 검사 대상).

## §3 안 r1 — 전용 플래그 `--squashed-pr <N> --reason "<사유>"` (DA HOLD-SQ1·SQ2 교정 · 자동 통과 철회)
DA §2 반례: PR 중간에 나노 내용 P1 → 같은 PR 이 P0 로 되돌림 → 문서만 squash 면 «MERGED·mergeCommit 일치·중간 blob 존재» 가 다 참인데 main 에 P1 은 없다. PR 중간 blob 은 «최종 반영»의 충분조건이 아니고, 리팩터가 나노 내용을 «의미상 보존»했는지는 git blob 으로 자동 증명되지 않는다. 그래서 기계는 «사실 확인 + 명백한 미반영 거부»까지만 하고, 의미 보존은 사람이 사유로 표명한다(기존 --override 와 같은 원장 · 증거 표가 붙은 좁은 우회).
1. PR 사실 확인(기계): `gh pr view N --json state,mergeCommit,headRefOid` → state=MERGED ∧ mergeCommit=S ∧ S 가 merge-base..FEAT 에 있음 · H 없으면 `git fetch origin pull/N/head` · 하나라도 실패 = REJECT.
2. 코드 경로마다 분류(기계 · (mode,type,blob) 함께 비교):
   - 같음: 나노 tip == FEAT HEAD(mode·blob 동일) → 통과 칸.
   - PR 안에서 고쳐짐: 나노 tip (mode,blob) 이 merge-base(H,FEAT)..H 구간에 새 blob 으로 있고 ∧ S 의 그 경로 != 분기 시점(merge-base(NANO,FEAT)) 의 그 경로(= 되돌림 아님) ∧ S 의 그 경로가 존재(= 제거 아님) → «사람 표명 필요» 칸.
   - 되돌림·제거·PR 에 없음 → REJECT 칸(플래그로도 통과 불가 · 기존 --override 만).
3. REJECT 칸 0 일 때만 플래그 통과: 경로별 표(같음 n · PR 안에서 고쳐짐 경로 목록 + 그 경로를 바꾼 PR 커밋 sha·제목)를 출력하고, 기존 override 원장(cherry-gate-override.log)에 `kind=squashed-pr pr=#N head=<H8> squash=<S8> paths=<목록> reason=<사유>` 1행 + ERROR 로그(#0 규칙 예외 3조건 = 플래그·ERROR 로그·보이는 출력). 사유 빈 문자열 = REJECT.
4. ★문서 WARN 은 «문서 파일 종류»만 (SQ2)★: 혼합 커밋 안에서 WARN 으로 낮출 수 있는 경로 = `design/` 아래 확장자 md·html·png·jpg·jpeg·svg·pdf 만. design/ 아래 sql·sh·py·json·yaml·toml·기타·확장자 없음 = 코드 칸(위 2 분류 대상). NUL-safe 완독 뒤 분류.
5. 플래그 없이 돌면 지금 동작 그대로(자동 통과 추가 0) — 단 4 의 문서 종류 분리는 기존 superseded REJECT 목록에서 «문서 종류» 경로를 WARN 으로 옮기는 것뿐이라 플래그 없이도 적용.

이번 사례 적용 예상: 코드 21 = 같음 19 + PR 안에서 고쳐짐 2(96b67fdda9 → b52a55dc6a 리팩터 · S 의 경로 ≠ 분기 시점 · 제거 아님) → `--squashed-pr 905 --reason "<feature master 사유>"` 로 통과 + 원장 1행. design/ 52 중 문서 종류는 WARN · 그 밖 종류가 있으면 코드 칸.

## §4 범위 (나노 1장)
- `scripts/fable-team-bin/ft-nano-cherry-gate.sh`(+ 키트 사본): ②의 PR 구간 탐색 함수(gh 조회는 env `FT_CHERRY_GH` 로 주입 가능 — 시험용 가짜) · design/ WARN 분리. 파일 151줄 → 200 넘으면 PR 탐색을 `ft-nano-cherry-pr.sh`(source 전용)로 분리.
- 시험 `tests/harness/test_cherry_gate_squash.sh`(임시 리포 + 가짜 gh): ①PR 안 나노 내용 → 후속 리팩터 → squash · 플래그 없음 → REJECT(지금과 같음) ②같은 사례 + `--squashed-pr N --reason x` → PASS + 원장 1행 + 경로 표 ③★DA 반례: PR 중간 P1 → head 에서 P0 되돌림 · 문서만 squash → 플래그 있어도 REJECT★ ④★PR head 에서 그 코드 경로 제거 → REJECT★ ⑤mergeCommit 불일치·state CLOSED·gh 실패 → REJECT ⑥사유 빈 문자열 → REJECT ⑦mode 만 다름(100644→100755) → 같음 아님 ⑧혼합 커밋 미랜딩 design/x.md → WARN 통과 · ★design/rag/sql/x.sql·design/x/run.sh 미랜딩 → REJECT★ ⑨기존 cherry 게이트 시험 PASS.

## §5 사전검증 (r1 · DA HOLD 1 → 교정 1)
- 소환: 예 — 닫기 게이트의 통과 길을 넓히는 변경이라 거짓 통과 반례를 DA 가 본다(§3-4·§3-3 이 대상).
