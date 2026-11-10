# FACTS — planner 이슈 큐 · v65 대형 리스트 분할 병렬 · 병합 랜딩 실측 (ft-harness-arch#1 요청 · ft-harness-nano#1 실행 · 조각 P5)

> 측정 시각 **2026-10-05 15:27 KST** · 읽기 전용 · 수정 0 · Slack 0.
> 루트 = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` · v65 정본 사본 = `.worktrees/v6-realtime-live`. 산출 위치 = `design/teams/harness/issue-improvement/`.
> 원본 = `design/teams/harness/issue-improvement/facts-raw/Q*.txt`. 표기 **[사실]** = 명령 출력 · **[추측]** = 해석. REQ = mbox #56995.

---

## Q1. v65 대형 리스트 분할 병렬 랜딩 실례 (10-03 main 랜딩)

| 항목 | 값 / 인용(파일:줄) | 사실/추측 |
|---|---|---|
| S 사슬 정의 | `.worktrees/v6-realtime-live/design/v65/20261003/CLOSEOUT-v65-main-landing-20261003.md:33-42` — S1 게이트 차분 · S2 증분 DA⑥ · S3 전체 단위 세트 · S4 깨끗한 병합+재생 · S5 로컬 3버블 · S6 feat push · S7 main push · S8 CD+dev 라이브 · S9 청크 원문 로그 0 · S10 첫 랜딩 CI 새 실패 처분 | [사실] |
| 나노·좌석 | `CHECKLIST-v65-main-landing.md:22-34` — P1 범위3 나노 · P2 시험맞춤 나노 · P3 DA codex · S1/S3 tester#11 · S4 통합 좌석 · S5~ master | [사실] |
| 최종 main sha | `CLOSEOUT…:18` 「origin/main @ **2ccd036b8e**(== origin/feat) — 랜딩 merge 419dc33962(부모 23e37d5621·feat 8b939f1ae7) → S9 f8c815511b → S10 339cee88dc → 복구 2ccd036b8e」 | [사실] |
| 막힌 곳(S10 사고) | `CLOSEOUT…:44-46` 「S10 main merge 339cee88dc 의 트리를 feat 그대로 썼는데 그 사이 main 에 RD_DECISION_ARCH#0 `5410b5bfaa`(16 파일)가 올라와 16 파일이 빠졌다 → force 없이 복구 2ccd036b8e(tree = merge-tree(5410b5bfaa, 0dcbfdd0a3))」 | [사실] |
| 병렬 단위 | `CHECKLIST…:19` 「§2 남은 사슬 (병렬 = 같은 칸 · 순서 = 위→아래)」 | [사실] |

**[사실] `design/v65/LANDING-POOL.md`** — 역할 `:3` 「병렬 규명·완성은 되는데 선후 판단·랜딩 대기열이 master 에게 몰려 밀리고 잊히는 현상 방지 · ★판정(순서 확정)은 arch·master★ — 이 파일은 «재료»만」 · 표 `^|` **42행** · 열 **9**: `산출 sha | 좌석 | 인덱스 | 종류 | 상태 | 선행 조건 | 막고 있는 것 | ⒜feat HEAD 반영 | ⒝인덱스 유무`. 최근 5행 = G2 전환 조건 · G2 재현절차 · G3 census · 별건 2건 · 세션 7개 정리(모두 「인덱스 아직 완성/ 미이동」 류).

**[사실] 나노 랜딩 원장**: `.worktrees/v6-realtime-live/design/v65/archive/NANO-LEDGER-pm1-temp-sessions-full-20261003.md` — **675행**(표 아님 · bullet). 최근 3행 = 「`ft-v65-temp-m7-runner-release-after-and-poller-windo#0` 닫힘(ft-nano-close)」 · 「`…poller-sse-axis-zero-seal-labe#0` 닫힘」 · 「`…press-seq-display-order#1` 닫힘」.
보조 원장 `.fable-team/state/cherry-gate-override.log` — **15행** · 열 = `date | seat | nano | tip | feat | reason`. `.fable-team/state/nano-landing.jsonl` = **없음**.
**[사실] `git log origin/main --since=2026-10-02 --until=2026-10-05`** — 총 **1302** 커밋 · 제목 「랜딩/squash」 **137** · 「S\d」 **41**. 예 5: `73e6972f27`(CCU 램프 마감 #828) · `bd6d0022dc`(#819 CI 복구 #823) · `9ca9a5d1d9`(GitHub→Slack 미러 #822) · `a37e9773dc`(Slack 읽기 미러 #814) · `db18f53a9a`(mbox log 사본 #812).

---

## Q2. 병합·랜딩 실제 절차 (기계)

| 기계 | 항목 | 파일:줄 + 인용 | 사실/추측 |
|---|---|---|---|
| ft-nano-cherry-gate.sh | 입력·모드 | `:12` `usage: <feat-branch> <nano-branch> [--repo <dir>] [--mode land\|close] [--override <사유>]` · 기본 `close`(`:13`) | [사실] |
| ft-nano-cherry-gate.sh | 「+ 커밋 0」 판정 | `:4-5` `git cherry <feat> <nano>` 의 «+» — design/ 밖 경로면 exit 1 · design/ 만이면 WARN exit 0 · «+» 0 = OK | [사실] |
| ft-nano-cherry-gate.sh | override 원장 | `:7` 유일한 사람 우회 `--override "<사유>"` → 「원장 1행」 = `.fable-team/state/cherry-gate-override.log` | [사실] |
| ft-nano-cherry-gate.sh | exit | `:10` `0=통과 · 1=REJECT · 2=usage · ★침묵 통과 0★` | [사실] |
| ft-nano-close.sh ⑤ | 산출물 회수 | `:5` `exit 0 = 닫힘(명부 삭제·원장 append·@zc_v65_active 해제·세션 kill)` · `:10` 「close 는 워크트리 정리 계획을 «생성만»」 | [사실] |
| ft-nano-freshness.sh | 4값 | `:5-6` `0=FRESH · 1=STALE(루트 뒤처짐·겹침0) · 2=STALE-OVERLAP · 3=미랜딩 0 · 4=usage` | [사실] |
| ft-nano-spawn.sh | 미랜딩 REJECT | `:100-109` 「옛 nano 브랜치 충돌 … 미반입이면 REJECT — 옛 브랜치·워크트리 삭제·덮기·재사용 0(판정 arch)」 | [사실] |
| single_set_testing.md §3 | 병합→시험→랜딩 순서 | `:46-59` 「①merge-base≠feat HEAD 판정 ②최신 루트 병합 ③그 세트로 시험 ④이슈 확인 ⑤squash 병합」 | [사실] |
| git-worktree-pitfalls ★5b/5d/7 | | `:101` ★5b 「머지하면 뭐가 지워지나 판정 — merge-tree 만이 정본」 · `:119` ★5d 「merge-tree 는 «머지»를 검증 — «rebase»는 검증하지 않는다」 · `:68` §7 「reset --soft origin/main + restore 콤보 = 미push 로컬 커밋 증발」 | [사실] |
| ~/.claude/rules/closeout-policy.md §5 | 닫기 체크 | `:18` 「닫기 체크: 미커밋 0 · 배포 브랜치 원격 sha 확인 · 정본 push · 좌석 kill(nano-close 경로) · 승계 0」 | [사실] |
| 메모리 S10 | 원문 | `…/memory/feedback_main_merge_commit_tree_must_include_moved_main.md` 「Never build a main merge commit as `commit-tree <feat>^{tree} -p origin/main -p feat` unless `merge-base --is-ancestor origin/main feat` … If main moved, tree=feat drops that commit's files」 | [사실] |
| STRUCTURE §1-4/§2 | 랜딩 집행자 | `.worktrees/v6-realtime-live/design/planner/STRUCTURE-main-satellite.md:70` ⓪ 「§1-4 «메인 직접 처리» 표에 있는 종류 … 메인 · 표의 담당 열이 집행자」 · `:85` 「라이브 버그·회귀 수정 = 영역 소유 메인 오케(v65=#134 · cfo=#52)」 | [사실] |

---

## Q3. planner BOARD 가 지금 큐를 다루는 방식

**[사실] BOARD.md(`.worktrees/v6-realtime-live/design/planner/BOARD.md`, r40 머리·r42 서술)** 절 제목:
`:45` 골 원문 · `:52` 골좌표 복붙 테이블 · `:66` 「1. v65 마무리」 · `:68` 1-A 한 일 · `:80` **1-B 하는 일 = 0 행(좌석 없음·오빠 「정리 중·착수 금지」)** · `:82` 1-C 남은 일 · `:114` 「2. cfo next 로 넘긴 작업」 · `:139` 「3. cfo 메인 작업」 · `:154` 「4. 도구→단계」 · `:164` 「5. 열린 질문」.

| 항목 | 값 | 사실/추측 |
|---|---|---|
| 절별 표 행수 | 1(v65) 40 · 2(cfo next) 22 · 3(cfo 메인) 6 · 4(도구) 8 · 5(열린 질문) 24 · 골 원문 7 | [사실] |
| 상태 어휘 건수 | ✅ 95 · 🔄 14 · ⏳ 36 · ⏸ 3 | [사실] |
| 「오빠 GO」 줄 | **19** (예 `:18` 「planner 직접 집행(오빠 GO …)」 · `:42` 「착수 트리거 = 오빠 GO 가 이 파일 행에 적힌 뒤」) | [사실] |
| GUIDE-planner 3항 | `:10` 「분류 = ⓪ 먼저, 그다음 ①~④ — ⓪ 직접처리표 → ①라이브 깨짐? ②현 단위 중단 없이 가능? ③골 1줄 분리 가능? ④나노 2장 초과? → 위성」 | [사실] |
| GUIDE-planner 4항 | `:11` 「분류 값 1통 = 1 Issue = 1값 → issue-manager(★planner 는 발주하지 않는다★) … 하위 좌석에 절대 직접 안 보냄」 | [사실] |
| LOOP-LEDGER 우선순위 열 | 값 = `①/②/③/④` 계열(① 1 · ② 2 · ③ 6) + 자유서술 — 문서 규칙 = 「①라이브 ②완성 전 골 축 ③완성 전 골 밖 ④완성 후」 | [사실] |
| mbox planner→팀 | `from byz-planner-arch#*` 55 중 「Issue #\d+」 **7** · 「GO」 **8** (예 seq 56643 「★③ 출범 GO★ — ft-v65-master-claude#136」 · 56640 「[부팅 발주 · 오빠 GO #767]」) | [사실] |

**[추측]** BOARD 는 **「우선순위 표」가 아니라 상태 인덱스**(✅/🔄/⏳)로 큐를 표현하고, 실제 우선순위 판정은 issue-manager 의 LOOP-LEDGER ①~④ 로 넘어간 이중 구조다.

---

## Q4. 팀별 「최종 완성 골」 파일

| 팀 | 존재 | 경로 | 축 수(표 행) | 사실/추측 |
|---|---|---|---|---|
| v65 | **Y** | `.worktrees/v6-realtime-live/design/v65/20260909/GOAL-archastra-lst-on-off-completion.md` (151행) | **44** | [사실] |
| cfo | **Y** | `.worktrees/c-level-planning/design/cfo/GOAL-cfo.md` (29행) | **6** | [사실] |
| ccu | **GOAL 없음** | `.worktrees/ccu-stress/design/ccu/GOALMAP-CCU_ARCH-{4,5,6,7}.md` (17~31행 · 각 7~9행) | (GOALMAP 4장) | [사실] |
| kk | **Y** | `.worktrees/v6-realtime-live/design/kk/GOAL-kk.md` (28행) | **7** | [사실] |
| harness | **Y** | `.worktrees/harness-ops/design/teams/harness/GOAL-harness.md` (22행) | **5** | [사실] |
| issues | **Y** | `.worktrees/issue-manager/design/issues/GOAL-issues.md` (20행) | **6** | [사실] |

**[추측]** ccu 만 단일 불변 GOAL 이 없고 좌석별 `GOALMAP-CCU_ARCH-N.md` 4장으로 쪼개져 있다 — ccu 가 메인/위성 경계가 불명확한 트랙이라는 정황과 일치.

---

## 회신 요약

- **못 한 항목**: `nano-landing.jsonl` 는 **없음**(state 에 부재) — 대신 cherry-gate-override.log 로 실측. 그 외 Q1~Q4 전부 실행.
- **사실/추측**: [사실] 약 26항 / [추측] 2항 → **사실 ≈ 93% · 추측 ≈ 7%**.
- **두드러진 3**: ① 10-03 main 랜딩 = **S1~S10 사슬**(CLOSEOUT 정본 · 최종 main `2ccd036b8e` · S10 사고 = main 이 움직여 16 파일 누락 → merge-tree 복구) ② 랜딩 기계 = **cherry-gate(exit 0/1/2 · override 원장 1행) + close⑤ + freshness 4값 + spawn 미랜딩 REJECT** ③ planner BOARD 는 **상태 인덱스**(✅95/🔄14/⏳36) 이고 우선순위는 issue-manager LOOP-LEDGER ①~④ 로 위임.