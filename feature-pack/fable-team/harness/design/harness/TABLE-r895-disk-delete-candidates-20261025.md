# 지울 목록 표 — r895 (r2 2026-10-27 01:5x~02:3x 재측정 · 읽기 전용 · 삭제 0)

> 카드 r895 산출 (나) + 범위 추가 #164204(planner#131 #164203 «등록 밖 사본·착지용 워크트리»).
> **r3 2026-10-27 03:1x — DA r1 HOLD 4건 반영**: ①미커밋 >0 인 사본은 «안» 에서 뺀다 ②가지에 붙은 사본(detached 아님)은 «안» 이 아니다 ③끝난 가지 보관 대상은 «카드가 완성/·아카이브/ 에 있음»까지 통과해야 한다 ④스크립트 8개의 금지 호출 정적 검사.
> 크기 숫자(du·kib)는 r2 스냅샷 그대로다 — r3 는 r2 raw 를 `classify.py --replay` 로 다시 분류했을 뿐 재측정하지 않았다(사라짐·쓰는 중 칸도 r2 값 유지). 가지 수만 `landed.sh --branches` 로 다시 읽었다(§4 · for-each-ref 1회 1.4초 · 크기 측정 0).
> 이 표는 «무엇을 지워도 되는가»의 후보다. **지우는 일은 이 카드에서 하지 않았다.** 표준승인 밖은 §6 «오빠 결정 h 초안»에 한 줄씩 묶었다.
> 파일 이름의 날짜는 r1 이름 그대로다(착지·설치 경로 유지). 수치는 r2 재측정이고, r1(10-25) 값과 달라진 자리는 «r1 대비» 로 적었다.
> 전체 행(BYZ 517 · 팩 626) = `evidence/r895/raw/<리포>-candidates.tsv` · 분류 규칙 = `evidence/r895/classify.py` 머리말 · 표 만드는 스크립트 = `evidence/r895/candidates.py`.

## 0. 결론 3줄

1. **표준승인 «안»에서 바로 줄일 수 있는 것 = BYZ 56.8 GiB**(나노 워크트리 37개 33.1 + 등록 사본 87개 23.7 — sweep 조건 충족분) **+ 팩 8.3 GiB**(나노 워크트리 196개 7.5 + 사본 17개 0.8). census 착지 판정을 통과하면 4.4 + 0.9 GiB 가 더 들어온다.
2. **오빠 결정이 필요한 것 = 287.5 GiB 급이 아니라 29.2 GiB.** r1 때 «오빠 결정 400 GiB»로 보였던 큰 덩어리(미착지 228.9 + 미커밋 58.6)는 이 표에서 «지우지 말 것» 이다. 실제 결정 대상은 나노 밖 워크트리 22.4(그중 가지에 붙은 사본 13.0) + 등록 밖 사본 3.9 + 등록 밖 폴더 2.9 다.
3. 새 주범은 **`$TMPDIR` 등록 사본**이다. 실재 326개 62.0 GiB, 주인 세션이 죽은 것 296개, 그중 24h 문턱을 넘은 117개 27.7 GiB 중 **가지에 붙은 사본 12개와 미커밋 1개는 표준승인 밖**이다(detached 이고 미커밋 0 인 것만 sweep 대상). 그렇게 추린 몫 = 104개 24.5 GiB, 그중 BYZ 87개 23.7 + 팩 17개 0.8.

## 1. 열 뜻

| 열 | 뜻 · 잰 방법 |
|---|---|
| 크기 GiB | `du -sk` (항목마다 7초 상한 · 넘으면 «못잼») |
| 주인 좌석 | 그 경로를 cwd 로 쥔 프로세스(`lsof -d cwd`) · tmux 모든 pane 현재 경로. 하나라도 안이면 «쓰는 중» 이라 후보에서 뺀다. 표의 `좌석=` 칸은 tmux 세션 이름을 폴더 이름으로 매칭한 값이라 빈 칸(«없음»)이 «주인 없음»의 증거는 아니다. 확정은 `keep:쓰는중` 분류(cwd 실측)다 |
| 착지 | ①`merge-base --is-ancestor` = 조상 ②가지가 바꾼 파일이 지금 main 과 바이트 같음 = 내용착지(squash) ③바꾼 파일 0 = 변경없음 ④그 밖 = 미착지(다른/바꾼). 스크립트 = `landed.sh` |
| 미커밋 | `status --porcelain -uno` 에서 « D»(작업 트리에서만 지운 줄) 뺀 줄 수. `ft-nano-close` 와 같은 규칙 |
| sparse | `core.sparseCheckout` = true/false (`sparse.sh`). BYZ 비sparse 216개 평균 1.48 GiB vs sparse 300개 평균 0.30 GiB |
| 안/밖 | 안 = 전역 CLAUDE.md HIL 절의 표준승인 경로(나노 워크트리 정리 09-25 · 임시 사본 sweep 판정 1920 · 끝난 가지 보관 이동 판정 2354) · 밖 = 오빠 결정 1줄 |

## 2. 합계 (분류별 · 읽기 전용)

| 분류 | BYZ 개수 · GiB | 팩 개수 · GiB | 안/밖 |
|---|---|---|---|
| 안: nano-close (착지 · 미커밋 0) | 37 · 33.1 | 196 · 7.5 | **안** |
| 안: scratch-sweep (등록 사본 · detached · 미커밋 0) | 111 · 37.0 | 174 · 8.8 | **안** (단 «주인 없음 ∧ 24h» 까지 충족한 것 = 87개 23.7 / 17개 0.8) |
| 안후보: nano-close (census 확인) | 9 · 4.4 | 20 · 0.9 | **안** (census 착지 판정 통과 시) |
| 밖: 나노 밖 워크트리 (가지에 붙은 사본 포함) | 57 · 22.4 | 25 · 1.1 | 밖 |
| 밖: 등록 밖 사본 | 12 · 3.9 | 0 · 0 | 밖 |
| 밖: 미커밋 (실작업물 > 0) | 56 · 58.6 | 4 · 0.1 | 밖 · **지우지 않음** |
| 밖: 미착지 | 206 · 228.9 | 204 · 10.9 | 밖 · **지우지 않음** |
| keep: 쓰는 중 | 26 · 20.5 | 3 · 0.1 | 후보 아님 |
| 사라짐(측정 뒤) | 3 · 0.7 | 0 · 0 | 후보 아님 |
| **합계** | **517 · 409.6** | **626 · 29.5** | |

r1 대비: BYZ 439개 496.2 GiB → 517개 409.6 GiB(개수는 늘고 크기는 줄었다 · 비sparse 대형 워크트리가 닫히고 소형이 늘었다). 팩 465개 17.7 → 626개 29.5.

## 3. BYZ 대표 행 (가장 큰 것 · 전체는 candidates.tsv)

**안: nano-close 37개 33.1 GiB** — 다음 손 = `ft-disk-census.sh --plan` → `ft-wt-sweep.sh`(기존 경로 · 브랜치 보존)

| 경로 | GiB | 주인 좌석 | 착지 sha · 판정 | 미커밋 | sparse |
|---|---|---|---|---|---|
| `…/.worktrees/concierge-c-demo-feedback-recorder` | 1.48 | 좌석=없음 | abc990572f · 조상 | 0 | false |
| `…/.worktrees/knowledge-land-2842-sb3` | 1.43 | 좌석=없음 | 244407cda0 · 변경없음 | 0 | false |
| `…/.worktrees/chatbot-c-k3d-land` | 1.42 | 좌석=없음 | f48cf01372 · 변경없음 | 0 | false |
| `…/.worktrees/v65-m7-test-open-scheduler-r4-first-admissio` | 1.41 | 좌석=없음 | cdee19f555 · 변경없음 | 0 | false |
| `…/.worktrees/v65-ja-contract-land` | 1.41 | 좌석=없음 | 2eb05c40d2 · 변경없음 | 0 | false |
| `…/.worktrees/v65-main-only-red-2fix` | 1.41 | 좌석=없음 | 3052912796 · 변경없음 | 0 | false |

**안후보: census 확인 9개 4.4 GiB** (내 «내용착지» 판정 · census 4단이 통과시키면 안으로 간다)

| 경로 | GiB | 착지 sha · 판정 | 미커밋 |
|---|---|---|---|
| `…/.worktrees/v65-m7-rt-typed-no-translation-flicker-locat` | 1.26 | b6e88fafcf · 내용착지 | 0 |
| `…/.worktrees/v65-m5-corpus-exit-release-census-research` | 1.07 | cb8c707f14 · 내용착지 | 0 |
| `…/.worktrees/ops-nano-ops-tts-zh-no-voice-b` | 0.33 | 045dea307e · 내용착지 | 0 |

**밖: 나노 밖 워크트리 57개 22.4 GiB** — 오빠 결정 1줄(비나노 워크트리 제거 = HIL). r2 의 24개 9.4 GiB 에 **가지에 붙은 `$TMPDIR` 사본 33개 13.0 GiB** 가 더해졌다(detached 가 아니라 sweep 이 못 지운다 · DA r1 #2).

| 경로 | GiB | 주인 좌석 | 착지 sha · 판정 | 미커밋 |
|---|---|---|---|---|
| `…/.worktrees/v65-tester-main` | 3.54 | 좌석=없음(detached) | 7e50c4408b · 조상 | 0 |
| `…/.worktrees/news-ledger-main` | 1.48 | 좌석=없음(detached) | fdb6d26320 · 조상 | 0 |
| `…/.worktrees/planner-arch-main` | 1.45 | 좌석=없음(detached) | ff807b126a · 조상 | 0 |
| `…/.worktrees/feature-close-m8` | 1.45 | 좌석=없음(detached) | 77e8f58e1a · 조상 | 0 |
| `…/.worktrees/v65-inbox-sort` | 0.84 | 좌석=없음 | 99eb381e49 · 내용착지 | 0 |

**밖: 등록 밖 사본 12개 3.9 GiB** (§5 · 쪽지 본문에 이름이 남은 것 0개)

| 경로 | GiB | 착지 sha · 판정 | 미커밋 | 잃는 것 |
|---|---|---|---|---|
| `$TMPDIR/repo-b9b42738-1793028680-45414` | 1.47 | b9b42738e7 · 조상 | 0 | 0 (같은 sha 사본 5개 중 하나) |
| `$TMPDIR/repo-a51e59ec-1792930701-89194` | 0.25 | a51e59ecc5 · 미착지 | 0 | 0 (가지 `archive/nano/ops-alert-gchat-sink` 에 sha 있음) |
| `$TMPDIR/repo-b634f110-1792927000-11027` | 0.24 | b634f11023 · 미착지 | 0 | 0 (가지 `nano/ccu-build-async-poll`) |
| `$TMPDIR/repo-bdb77579-1792905452-81223` | 0.24 | bdb775792a · 미착지 | 0 | 0 (가지 `docs/ops-cleanup-account-2747-20261025`) |
| `$TMPDIR/repo-11ce68f4-1792969355-468` | 0.02 | 11ce68f470 · 미착지 | **48,038** | **있다** · 미커밋(untracked) 4.8만 줄 · 지우지 않음 |

나머지 7개(`repo-1051267d` · `repo-3bf49e53` · `repo-52a99460` · `repo-4e2ff42e` · `repo-ab8adb8c` · `repo-e5de194c` · `repo-b9b42738-…-30617`)는 각 0.24 GiB · 미커밋 0 이고 sha 가 가지나 archive 에 남아 있다.

**밖: 미커밋 56개 58.6 GiB · 미착지 206개 228.9 GiB** — 지우지 않는다. 큰 것만 적어 두면 미커밋 `m1a-implcc32` 4.18 · `loom-domain-hierarchy` 3.44 · `landing-g1087` 2.65, 미착지 `v65-m5-1927-mic-pass-user-exposure` 6.77 · `v65-m7-audit-env-name-generalize-structure` 6.39 · `v65-sb-ctx-diet-remaining-five` 6.37. 이 287.5 GiB 를 줄이는 방법은 삭제가 아니라 «§PLAN ③ 착지 뒤 자동 정리» 로 다시 안으로 옮기는 것이다.

r3 에서 미커밋이 53 → 56개가 된 이유: 등록 사본 가운데 미커밋이 남은 5개가 r2 에서 «안:scratch-sweep» 로 잘못 분류돼 있던 것을 이번에 «밖» 으로 옮겼다(그중 1개는 가지도 붙어 있어 나노 밖 행으로 갔다).

## 4. 브랜치 (판정 2354 «끝난 가지 보관 이동» = 표준승인 안)

| 리포 | heads 전체 | nano/* | archive | 착지(main 조상) nano | 워크트리가 쓰는 것 | 워크트리 없음 | **카드 완성/아카이브 대조 통과(= 보관 이동 대상)** | 카드 진행 중(제외) | 확인 불가 |
|---|---|---|---|---|---|---|---|---|
| BYZ-Agents | 4,150 | 2,351 | 652 | 488 | 30 | 458 | **245** | 61 | 152 |
| ai-feature-pack | 489 | 400 | 8 | 202 | 196 | 6 | **5** | 0 | 1 |

조건 3개를 모두 통과해야 대상이다: ①착지(main 조상) ②어느 워크트리도 안 씀 ③**카드가 `완성/`·`완성후/`·`아카이브/` 에 있음**. 카드 대조는 `landed.sh --branches` 가 한다(카드 파일 이름 = 가지 줄기, 나노 작업 폴더가 이름을 43자에서 자르므로 앞자리 대조, `-rN` 꼬리 무시 · 카드 명단 = `.worktrees/harness-ops/design/*/indices/*`). 카드가 `진행/`·`대기/` 에 있으면 «진행카드» 로 빼고(예: r895 자기 가지 — 카드는 진행 중), 카드를 못 찾으면 확정하지 않고 «확인불가» 로 남긴다. r2 의 «448개» 는 이 ③ 없이 센 값이었고 그 가지 목록도 저장하지 않아 다시 대조할 수 없었다(DA r1 #3 · 확인 불가 1). `landed.sh --branches` 를 2026-10-27 03:1x 에 두 번 돌렸다(1.4초 · for-each-ref + worktree list + 카드 파일 이름 대조 · 크기 측정 0). 같은 날 03:0x 와 03:1x 사이에도 «워크트리 없음»이 454 → 458 로 움직였다 — 가지·워크트리가 살아 움직이므로 이 표는 «읽은 시각의 값» 이다. 원 자료 = `raw/BYZ-Agents-branches-cards.tsv` · `raw/ai-feature-pack-branches-cards.tsv`(458 + 6줄 · 가지마다 완성카드·진행카드·확인불가).

## 5. 임시 사본 · 등록 밖 폴더 · 그 밖 큰 자리

| 자리 | 실측 | 안/밖 |
|---|---|---|
| `$TMPDIR` 등록 사본 | 등록 574줄 · 실재 **326개 62.0 GiB** · 주인 살아 있음 30 · 주인 없음 296 · **24h 넘은 117개 27.7 GiB** — 그중 가지 붙음 12 · 미커밋 1 은 표준승인 밖 → **안은 104개 24.5 GiB(BYZ 87개 23.7 · 팩 17개 0.8)** · cwd 쥔 것 1 | **안** (detached ∧ 미커밋 0 ∧ 주인 없음 ∧ 24h 전부) |
| `$TMPDIR` 등록 밖 사본 | 13개 4.0 GiB (§3) | 밖 |
| `.worktrees/` 등록 밖 폴더 | BYZ **76개 2.9 GiB** · 팩 1개 0.4 MiB · git 꼬리표 없는 것 74 · 쥔 프로세스 0 | 밖 · 큰 둘 = `v65-land-2412 nano` 1.37 GiB · `v65-land-2411 nano` 1.34 GiB(이름에 공백) |
| `~/.claude/projects/` | **62.5 GiB** (r1 58.4) · 상위 = BYZ 루트 13.2 · v6-realtime-live 11.6 · harness-ops 5.6 · c-level-planning 3.5 | 보관 기간 정책 = 오빠 결정 |
| 세션 스크래치 `/private/tmp/claude-501` | **6.0 GiB** · `.git` 가진 사본 324개 | 보관 정책 |
| `BYZ/.baton/archive/` | 4.31 GiB | `baton archive:prune` 만료분 = 안 |
| `$TMPDIR/tmp.*` | 895개 884 MiB | sweep 대상 |
| wt-clean 사람 확인 대기(`.sh.hil`) | **1,401장** (r1 181) · `.sh.done` 0 | 밖 · 묶음 승인 경로 필요(§PLAN ④) |

## 6. 오빠 결정 h 초안 (★등록 0 · 실행 0 — planner 가 `ft-hil.sh --add` 로 만든다★)

표준승인 밖 → 한 줄씩 결정. `worktree remove` 는 `--force` 없이 부른다. 미커밋이 생겼으면 git 이 스스로 거절한다.

```bash
#!/bin/bash
# h 초안 — r895 표준승인 밖 정리 (오빠 결정 · 한 줄씩 켜고 끈다) · 리포 = BYZ-Agents
set -u
B=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents; T=/var/folders/vm/j7_jw8050t553wj5wqlvnmmh0000gn/T
# 결정 1 · 등록 밖 사본 11개(3.9 GiB) — 잃는 것 0(미커밋 0 · sha 가 가지/archive 에 남음)
#   repo-11ce68f4-1792969355-468 는 미커밋 4.8만 줄이 있어 목록에서 뺐다
for d in repo-b9b42738-1793028680-45414 repo-b9b42738-1793028657-30617 repo-a51e59ec-1792930701-89194 \
         repo-b634f110-1792927000-11027 repo-1051267d-1792927934-80381 repo-e5de194c-1792931117-89618 \
         repo-bdb77579-1792905452-81223 repo-ab8adb8c-1792899463-66746 repo-3bf49e53-1792893609-12879 \
         repo-52a99460-1792892582-10474 repo-4e2ff42e-1792892293-47501; do
  [ -z "$(lsof -t +d "$T/$d" 2>/dev/null)" ] || { echo "SKIP 쓰는 중 $d"; continue; }
  git -C "$B" worktree remove "$T/$d" && echo "removed $d"
done
# 결정 2 · 등록 밖 폴더 76개(2.9 GiB · git 꼬리표 없음 · 쥔 프로세스 0) — 잃는 것 = 그 안 ignored 파일
#   목록 = evidence/r895/raw/BYZ-Agents-orphans.tsv · 큰 둘은 이름에 공백이 있다
# rm -rf "$B/.worktrees/v65-land-2412 nano" "$B/.worktrees/v65-land-2411 nano"
# 결정 3 · 나노 밖 워크트리 24개(9.4 GiB · 착지 · 미커밋 0) — 목록 = candidates.tsv 의 «밖:나노 밖 워크트리» 행 · 묶음 1줄
# 결정 3-2 · 가지에 붙은 $TMPDIR 사본 33개(13.0 GiB) — detached 가 아니라 sweep 이 못 지운다(registered · 주인 없음 · 24h 조건은 채웠음) · 브랜치에 sha 가 있으니 잃는 것 0 이지만 «가지에 붙은 사본 제거» 는 표준승인 밖 = 오빠 결정 1줄 · 목록 = candidates.tsv 의 «밖:나노 밖 워크트리» 중 $TMPDIR 행
# 결정 6 · 끝난 가지 보관 이동(판정 2354) — 아래 ③ 조건을 통과한 BYZ 245가지 · 팩 5가지만 대상 · 목록 = evidence/r895/raw/BYZ-Agents-branches-cards.tsv(«완성카드» 행)
#   카드가 진행 중(57)·확인 불가(152)인 가지는 옮기지 않는다 · 가지 삭제 0 · refs/archive 로 ref 만 옮긴다
# 결정 4 · 등록만 남은 워크트리 메타(폴더 없음) — 잃는 것 0
# git -C "$B" worktree prune; git -C /Users/yoonhwan/Project/ai-feature-pack worktree prune
# 결정 5 · caps: 세션 스크래치 6.0 GiB·claude projects 62.5 GiB 보관 기간(30일? 60일?) — 정책 1줄
```

## 7. 원본

- 측정 스크립트(읽기 전용): `evidence/r895/measure.sh` · `scratch.sh` · `landed.sh`(r3 에 `--branches` 추가) · `orphans.sh` · `sparse.sh`(r2 신규) · `classify.py`(r3 에 `--replay` 추가) · `dupstem.py` · `candidates.py`(r2 신규 · 표를 손으로 만들지 않게)
- 시험: `tests/test_r895_disk_survey_readonly.sh` (픽스처 리포에서 «바뀐 파일 0» + 칸 값 + 변이 2 · r2 에서 sparse·candidates 칸, r3 에서 정적 검사·분류 조건·가지 카드 대조를 더했다)
- 원 자료: `evidence/r895/raw/` (BYZ·팩 각각 git.txt · branches.txt · **branches-cards.tsv(r3 신규 · 끝난 가지 후보와 카드 대조)** · worktrees.tsv · landed2.tsv · sparse.tsv · classified.tsv(r3 재분류) · candidates.tsv · classified-summary.txt · dup.tsv · dupstem.tsv · orphans.tsv + scratch-registered/unregistered/summary · scratch-safety.tsv · scratch-owner.txt · extra.txt · stats.txt)
