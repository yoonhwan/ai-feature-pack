# DESIGN r1 — 세트 발주 원장 (파일 기반 큰 작업 발주) (판정 359 ②)

> byz-harness-arch-claude#10 · 2026-10-08 · 발주 master#13 #61244·#61268 · 조사 표 `SURVEY-file-based-dispatch-20261008.md`(05d5a0e0ec)
> 오빠 원문(판정 359): 「cfo 축 하네스 파일기록 이런 큰작업은 세션이관에 메모리되고 상태를 바로 파악하고 이슈매니저와 협의하는 파일기반 발주 · 하네스 매니저 발주 업그레이드 · 메인팀들은 이런게 필요하다 · 기존 이 역할의 파일이나 구조가 있는지 먼저 파악 개선」
> issues master#3 의견(#61246): SETS 정본 한 장 · LOOP-LEDGER 마지막 칸 「세트=<이름>」 · Issue 본문 「세트: <이름>」 · SETS → Issue 단방향.

## ★골 원문 (GOAL-harness.md 복붙)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: 6-b(개선요청 → 협의 → 개선) + planner 골 원문 2(팀 배정·운영 · 연결 관리 정리). 닫는 증거: 첫 적용(CFO 7세트)이 SETS.md 7행 + 발주 파일 1장으로 들어가고, cfo master 후계가 첫 턴 골 대조 보고에 «세트 상태 1줄»을 낸 기록 1회 + 랜딩 main sha.

## §0 결론
- 새 층은 **«세트»(여러 Issue·여러 카드를 묶은 큰 작업) 하나만** 더한다. 카드(작은 일)·LOOP-LEDGER(건별)·각 팀 오빠 지시 원장은 그대로 둔다.
- 파일 2종: ①**세트 원장 `design/issues/SETS.md` 한 장**(전 팀 · 쓰는 손 = issues master 하나) ②**발주 본문 `design/<발주 팀>/orders/ORDER-<판정>-<팀>-<slug>.md`**(지금 /tmp relay 로 가던 전문 — 쓰는 손 = 발주자). mbox 는 «파일 경로 + 1줄»만.
- 한 장 vs 팀별 → **한 장**: 요구 3(팀 × 세트 × 상태 × Issue)이 파일 그대로 뷰가 되고, issues master 가 이미 LOOP-LEDGER 단독 기록자라 쓰는 손이 하나(여러 브랜치 동시 편집 충돌 0). 팀별의 장점(승계 때 자기 파일만)은 조회 도구의 팀 필터로 대신한다.
- 상태 변경 = «요청 id 가 붙은 왕복»(DA HOLD-S1 교정 · §3-b): 팀 master 가 자기 팀 `design/<팀>/orders/SET-REQUESTS.md` 에 요청 줄을 먼저 쓰고(미적용) mbox 로 보냄 → issues master 가 행 갱신·커밋 뒤 「적용 id · 원장 commit」 회신 → 팀이 그 줄에 적용 commit 을 적음. 회신 전엔 조회 도구가 «pending» 으로 보인다. 팀은 SETS.md 를 직접 고치지 않는다.
- 조회 = 새 도구 `scripts/harness-install/sets/ft-sets.sh [팀]`(키트 bin 밖 — 드리프트 BLOCK 회피 · 제안서 도구와 같은 자리 규칙). 승계: 승계 스냅샷·부팅 발주·골 대조 보고에 «세트 1줄» 고정 칸.
- Issue 본문 「세트:」 줄은 Tank 래퍼 edit(원장 R10 · 미구현)이 선행 → **이번 단위는 라벨 `set:<팀>-<이름>`(래퍼 label 있음)만**. 본문 줄은 R10 랜딩 뒤 같은 원장에서 일괄(완성 후 아님 — R10 뒤 바로 · 정본에 순서로 적음).

## §1 SETS.md 형식 (정본 — 칸 이름 고정)
```
# 세트 원장 — 큰 작업 발주 (쓰는 손 = issues master · 행 갱신만 · 정본 docs/rules/set_dispatch.md)
| 세트 | 팀 | 상태 | 골 축 | 닫는 사건 | Issue | 발주 | 판정 | 적용 id | 갱신 |
|---|---|---|---|---|---|---|---|---|---|
| cfo/s2-close-bundle | cfo | 진행 | 골 4줄 중 운영툴 | 종결 6건 close + 증거 표 커밋 | #… #… | byz-agents@<sha10>:design/planner/orders/ORDER-358-cfo-sets.md#s2 | 358 | cfo-s2-01 | 10-08 09:34 issues#3 |
```
- `발주` 칸 = «리포 @ commit sha : 리포 상대경로 # 절 앵커»(DA HOLD-S2 교정 · 절대경로는 칸에 쓰지 않는다). `적용 id` = 이 행에 마지막으로 반영된 요청 id(§3-b · 같은 id 재처리 = 회신만).
- 세트 이름 `<팀>/<s번호>-<slug>`(`^[a-z0-9]+/s[0-9]+-[a-z0-9-]{3,40}$`) · 상태 5종 `발주 | 진행 | 보류 — <사유> | 닫힘 — <증거> | 폐기 — 판정 N` · Issue 칸 = 공백 구분 `#N` 목록(없으면 `-`).
- 행 삭제 0(닫혀도 남김) · 한 세트 = 한 행 · 같은 Issue 가 두 세트에 있으면 `ft-sets.sh --check` 가 경고(실패 아님 — 세트가 겹칠 수 있음은 오빠 몫 판단).

## §2 발주 파일 형식
- 경로 `design/<발주 팀>/orders/ORDER-<판정>-<대상 팀>-<slug>.md`(planner 발주면 `design/planner/orders/`).
- 머리: 골 3줄(«대상 팀» 골 파일 복붙 — 발주자 골 아님 · 이번 판정 359 발주가 v65 골을 단 사고 방지) · 「골의 어느 축인가」 1줄 · 오빠 원문 · 판정 번호 · 세트 표(세트 이름 · 포함 Issue · 닫는 사건 · 착수 여부) · 금지선.
- ★발주 식별자(DA HOLD-S2 교정)★ = `byz-agents@<commit sha>:<리포 상대경로>#<앵커>`. 발주자는 파일 커밋 → **보호 ref** `refs/orders/<판정>-<대상 팀>` 를 그 commit 에 건다(`git update-ref` · 로컬 · 되돌림 = `git update-ref -d`) → mbox 에 «식별자 + 1줄»(절대경로는 같은 머신 편의 힌트로만 덧붙임). relay(/tmp) 는 쓰지 않는다.
- 받는 쪽은 `git -C $BYZ_ROOT show <sha>:<경로>` 로 읽고(같은 경로의 이후 개정본을 읽지 않음) 회신에 «읽은 sha» 를 적는다. `git cat-file -e <sha>:<경로>` 실패 = «미전달» ERROR(정상 읽기로 취급 0).
- 보존: 발주 «내용»이 main 에 도달하기 전엔 보호 ref 를 지우지 않는다 — squash 랜딩은 SHA 가 바뀌므로 «조상 여부»가 아니라 `git show origin/main:<경로>` 가 발주 commit 의 같은 경로와 바이트 동일한지로 판정(DA §r1 주의 ③) · SETS.md 의 발주 칸 sha 는 원본 그대로 두고 랜딩 sha 를 갱신 칸에 덧붙인다 — 워크트리·브랜치 정리는 «발주 보존 완료»가 아니다(기존 삭제 HIL 은 그대로). 랜딩 뒤 보호 ref 정리는 그 팀 CLOSEOUT 단계.
- ★수락 범위★: 같은 git 객체 저장소를 쓰는 좌석(이 머신의 루트+워크트리 전부)까지. 다른 머신 수신은 «완성 후 아님 · 후속 단위» — 보호 ref 를 승인된 원격 ref 로 올리는 게이트(객체 가용성 확인)는 원문 5(머신 독립) 단위에서 정한다. 그 전까지 다른 머신 좌석에 세트 발주 0.

## §3 흐름 (누가 무엇을)
| 단계 | 누가 | 하는 일 |
|---|---|---|
| 1 판정 | planner ↔ 오빠 | 세트 묶음 판정 N |
| 2 발주 파일 | planner | §2 파일 커밋 → mbox(대상 팀 master + issues master) 「경로 + 1줄」 |
| 3 원장 행 | issues master | SETS.md 행 추가(상태 발주) + 포함 Issue 에 라벨 `set:<팀>-<s번호>` + LOOP-LEDGER 해당 행 마지막 칸 끝 「세트=<이름>」 |
| 4 착수·진행 | 대상 팀 master | 세트 착수 때 issues master 에 「→ 진행」 1줄 · 카드·나노는 지금 체계 그대로(카드 머리 `- 세트:` 줄 1개 추가 — lint 는 선택 칸) |
| 5 닫힘 | 대상 팀 master → issues master | 「→ 닫힘 · 증거」 요청 → issues master 가 증거 확인 → 그 행 Issue 칸 일괄 close → ★전부 CLOSED 확인 뒤에만★ `닫힘 — <증거> · close N/N` · 일부 실패면 `보류 — close 실패 #N` (행 갱신만으로 close 완료 취급 0) → 적용 회신 |

### §3-b 상태 요청 왕복 (DA HOLD-S1 교정)
- 요청 id = `<팀>-<s번호>-<2자리 순번>`(예 `cfo-s2-01`). 팀 master 는 «보내기 전» `design/<팀>/orders/SET-REQUESTS.md` 에 한 줄 추가·커밋: `- <id> · <세트> · <전 상태> → <새 상태> · 증거 <sha|Issue> · 보냄 seq <n> · 적용 -`.
- mbox 본문: `[SET-REQ <id>] <세트> <전>→<새> · 증거 … · 요청 파일 byz-agents@<sha>:design/<팀>/orders/SET-REQUESTS.md`.
- issues master 판정 순서(DA §r1 주의 ①): **먼저** 행의 적용 id 가 이미 <id> 면(재요청·승계 재처리) 갱신 0 + 같은 ACK 재회신(중복 효과 0 · 전 상태 검사보다 우선) → 아니면 행의 현재 상태가 «전 상태»와 다를 때 적용 0 + 「불일치 <id> · 지금 <상태>」 회신 → 같으면 행 갱신(적용 id = <id>)·커밋 → 회신 `[SET-ACK <id>] <세트> → <새> · 원장 <commit sha>`. 스캔은 각 팀 `SET-REQUESTS.md` 의 «그 팀 작업 트리 최신본»을 읽는다(DA 주의 ②).
- 팀 master 는 ACK 받은 그 턴에 요청 줄 `적용 -` → `적용 <commit sha>` 로 고친다.
- 처리 시간·재알림(한 가지 절차): issues master 는 체크 크론 틱(10분)마다 전 팀 `SET-REQUESTS.md` 의 `적용 -` 줄을 스캔해 처리 · 팀 master 는 보낸 뒤 2틱(20분) 안에 ACK 가 없으면 `{mbox} ring <issues master> <최초 seq>` 1회 + 다음 틱에도 없으면 planner 에 `[SET-REQ 정체 <id>]` 1줄.
- 승계: issues master 후계는 첫 턴에 전 팀 `SET-REQUESTS.md` 의 `적용 -` 줄 ↔ SETS.md 적용 id 대조 → 남은 것 처리(위 중복 규칙). 팀 master 후계는 자기 팀 `적용 -` 줄을 골 대조 보고 «세트 1줄»에 pending 으로 적는다.

## §4 승계 자동 로드 (요구 2)
- `references/context-management.md` 승계 6단계 ①스냅샷에 고정 줄: `- 열린 세트: bash <루트>/scripts/harness-install/sets/ft-sets.sh <팀> 출력 붙임`.
- 승계 발주 템플릿(골 3줄 다음)에 1줄: `세트: ft-sets.sh <팀> — 골 대조 보고에 «세트 진행 a · 발주 b · 보류 c» 1줄`.
- `references/harness-map.md` 에 행 1개(「큰 작업 발주·세트 상태 | SETS.md · ORDER-*.md · ft-sets.sh | design/issues/ · design/<팀>/orders/」).
- 홈 파일 2개(context-management · harness-map)는 리포 사본이 없다 → tracked 초안 `design/teams/harness/drafts/set-dispatch/…` → master cp 설치(제안서 흐름 governance 와 같은 절차).

## §5 조회 도구 `ft-sets.sh` (요구 3)
- `ft-sets.sh [팀]` — SETS.md 를 읽어 표 출력(팀 필터 · 상태 순 진행 → 발주 → 보류 → 닫힘) + 끝줄 「세트 진행 a · 발주 b · 보류 c · 닫힘 d」.
- 원장 위치: **한 곳 고정** `FT_SETS_FILE`(정본 = issues master 작업 트리의 `design/issues/SETS.md` 절대경로 · map 에 1행) — 없으면 rc≠0 · 다른 경로로 넘어가기 0(DA HOLD-S1 «오래된 우선 경로» 교정).
- 출력 머리 1줄 = `원장 <경로> @ <그 파일 마지막 commit sha10> · 미커밋 변경 <있음|없음>`. 팀 필터면 그 팀 `SET-REQUESTS.md` 의 `적용 -` 줄을 «pending» 으로, 적용 commit 이 원장 현재 commit 의 조상이 아니면 «stale(원장이 적용 commit 보다 뒤)» 로 따로 보인다.
- `--check`: 형식 검사(이름 정규식 · 상태 5종 · `발주` 칸 `git cat-file -e <sha>:<경로>` · 보호 ref 존재 · Issue 겹침 경고) rc≠0 이면 사유.
- 읽기 전용 · 원격 0.

## §6 첫 적용 (CFO 7세트 · 판정 358)
1. planner 가 `design/teams/harness/drafts/file-dispatch/ORDER-358-cfo-sets-relay-20261008.md`(회수본 · 05d5a0e0ec)를 §2 형식으로 옮겨 `design/planner/orders/ORDER-358-cfo-sets.md` 커밋.
2. issues master 가 SETS.md 7행 + 라벨 + LOOP-LEDGER 「세트=」.
3. planner BOARD 에 링크 1줄(「세트 원장 = design/issues/SETS.md · ft-sets.sh」).
4. cfo master 다음 승계(또는 지금 좌석의 다음 골 대조)에서 «세트 1줄» 실측 1회 = 닫는 증거.

## §7 나노 1석 · 구현 범위
- 카드 `indices/대기/set-dispatch-tools.md`(Sonnet 5.5): `scripts/harness-install/sets/ft-sets.sh` 신규 · `docs/rules/set_dispatch.md` 정본(§1~§5 요약 · 자동 로드 아님) · `design/issues/SETS.md` 빈 원장(머리+빈 표) · 홈 초안 2개(context-management · harness-map 행) · 시험 `tests/harness/test_ft_sets.sh` · `tests/harness/test_set_requests.sh` · `design/<팀>/orders/SET-REQUESTS.md` 빈 틀(형식 머리 1줄 · 첫 적용 팀 cfo 1개).
- 원장 행 기입(§6)은 나노가 아니라 issues master·planner 몫(쓰는 손 규칙).

## §8 시험 목록
1. `test_ft_sets.sh` — 임시 git 리포 + SETS.md: 팀 필터 · 상태 정렬 · 끝줄 건수 · 원장 없음 → rc≠0(다른 경로로 안 넘어감) · 머리줄 commit·미커밋 표시 · `--check`: 이름 틀림·상태 6번째 값 → rc≠0 · ★S2★ 발주 칸 sha:경로로 정확 본문 읽기(같은 경로 이후 개정본과 다름 확인) · 없는 sha → rc≠0 「미전달」 · 보호 ref 없음 → rc≠0 · 같은 Issue 두 세트 → 경고 rc=0 · ★S1★ SET-REQUESTS `적용 -` 줄 → pending 표시 · 적용 commit 이 원장 commit 조상 아님 → stale 표시.
2. `test_set_requests.sh`(문서 절차를 가짜 로컬 기록으로 대조) — ①요청 READ 뒤 반영 전 중단 → 후계 스캔이 `적용 -` 줄을 찾아 처리 ②반영·커밋 뒤 회신 전 중단 → 재요청 = 갱신 0 + 같은 ACK(적용 id 같음) ③전 상태 불일치 → 적용 0 · ④close 일부 실패 → 행 `보류 — close 실패` · 「닫힘」 아님. (issues master 처리 단계는 `ft-sets.sh apply <id>` 같은 도구가 아니라 정본 절차 — 시험은 SETS·SET-REQUESTS 파일 상태를 보는 검사기 `ft-sets.sh` 의 판정만 고정)
3. 홈 초안 diff: context-management 1줄 · harness-map 1행 추가뿐(제거 0).

## §9 금지선 · 되돌림
- 원격 쓰기 0(라벨·LOOP-LEDGER 는 issues master 가 §6 에서) · 키트 bin 추가 0 · 기존 원장(BOARD·USER-ORDERS·ORDERS-oppa·LOOP-LEDGER 열) 구조 변경 0.
- 되돌림: PR revert + 홈 파일 2개 `.bak-1008-sets` 복원 · 라벨 `set:*` 은 남아도 무해(제거는 issues master 손으로).

## §10 DA 소환 판단
- r1(DA HOLD-1 · DA-set-dispatch-20261008.md): S1 = 요청 id 왕복(§3-b · SET-REQUESTS 선기록 · ACK+원장 commit · 적용 id 중복 0 · 2틱 재알림 · 승계 스캔 · 닫힘 = close 전부 확인 뒤) + 원장 한 곳 고정·머리줄 commit·pending/stale 표시(§5) · S2 = 발주 식별자 sha:상대경로 + 보호 ref + cat-file 미전달 ERROR + 수락 범위 = 같은 객체 저장소(다른 머신 = 원문 5 단위)(§2). 같은 범위 교정 1회.

**소환함(사전검증 1회 · 10분+10분 · 2 HOLD 면 중단)**. 볼 곳 2: ①쓰는 손 하나(issues master) + 팀은 mbox 1줄로 상태 변경 — 이 경로에서 상태가 «조용히» 안 바뀌는 구멍(쪽지 유실·issues master 부재)이 있는가, 닫는 사건이 보이는가 ②발주 파일을 /tmp relay 대신 «자기 브랜치 커밋 + 절대경로»로 읽게 하는 것이 승계·머신 독립에서 relay 보다 실제로 낫나(랜딩 전 브랜치 삭제·워크트리 정리 때 유실 경로).
