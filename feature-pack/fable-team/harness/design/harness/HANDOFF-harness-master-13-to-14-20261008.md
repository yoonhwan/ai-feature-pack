# HANDOFF — byz-harness-master-claude#13 → #14 (2026-10-08 · ctx 400k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: C(업그레이드·커밋·push·배포 발행·반영) + 6-b(개선요청 접수·협의) + 원문 5(머신 독립 배분) + 원문 7(쪼개 동시에).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항(세션명/모델·창/Serena) + i-have-adhd 를 현역 planner(`ft-harness-info.sh seats` · 지금 byz-planner-master-claude#9)에 mbox 보고 → 같은 턴에 CronCreate 10분 틱(보고에 cron=job id) — 없으면 착수 0.★ BOOT 17조항(~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md) 먼저. 오빠 보고 = 결론→할 일→바뀐 것→근거 + PR·Issue 번호는 맨 아래 각주 표.

## 지금 상태 (한 줄)
★아침 매거진·제안서 도구·세트 발주 도구·ops/loom 팀 설치 전부 main 랜딩 끝(PR 888·890·893·898) · 열린 일 = 판정 357 제안서 업그레이드 구현.

## 이번 세션(#13)에 끝낸 것 (전부 main 병합 · 홈 설치 완료)
- 판정서 §47~§52 집행: 제안서 도구 3개(§47) · 매거진 풀디테일 ①수집(§48) ②렌더/발행(§50) ③쉬운 판 eli5(§49) · 세트 발주 도구 ft-sets.sh(§51) · 제안서 카드 골 줄(R26 §52).
- PR 888(main 6b77553d39) · 890(fd25e1a76b, 도구 통합) · 893(299767bef7, 메인 팀 ops·loom 정본 docs) · 898(a8388b53ac, R26).
- install-magazine.sh(복사만, --load 없이) main 키트로 2회 실행 — 내일 08:00 호부터 풀디테일 PDF+쉬운 판. 홈 설치: governance 팀 표 §1-1·harness-map·context-management(.bak-1008-sets/-r372).
- 개선요청 R20(cfo-env.sh 골 줄 파일·설치) · R26(ft-proposal-card.sh CFO 카드·설치+goal-lines-cfo.txt 4줄) 완료 · R21 접수(arch 안 대기).
- 판정 370·372: 메인 팀 ops·loom 하네스 설치 완료 — 팀마다 .worktrees/<t>-main(feat/<t>-main)·seats-<t>.json·bin-<t>/·com.byz.ft-tick-<t>(둘 다 running)·master#0(Sonnet 5.5)·arch#0(Opus 5.5) 개설. DA 는 공유 byz-harness-da-codex#0 사용 허가 해 줌(ops·loom 둘 다).
- 나노 전부 닫힘(proposal-tools·detail-collect·render-publish·eli5-html·set-dispatch-tools·proposal-card-goal-lines).

## 열린 일 (순서)
1. **판정 357 제안서 흐름 업그레이드(구현 전)**: arch#11 DESIGN r2 = design/harness/DESIGN-proposal-flow-20261008.md «# r2» 절(미커밋 — 이 스냅샷 커밋에 같이 넣음). DA HOLD-1 교정 반영 후 재검 relay #61813 대기(공유 da-codex#0 대기열). APPROVE 오면 → arch 가 나노 카드(대기/) 작성 → `ft-nano-spawn.sh … --model 'claude-sonnet-5-5[1m]'`(`. <루트>/.fable-team/bin-harness/harness-env.sh; export FT_NANO_FEAT=ops/main-base`; `zsh -lc` 로) → 나노 보고 → master 독립 검증(.venv pytest·ruff·shellcheck·200줄) → arch 재현 §53 → 판정서 append → ft-index-move → 명부 index 치환 → cherry-pick → 나노 닫기(유휴 3분 필요, REJECT 면 잠시 뒤 재시도) → 랜딩 PR → 홈 파일 있으면 cp. 내용: ①Issue 본문=제안서 전문(60k 초과 분할) ②proposal_eli5.py+템플릿 ③「## 실험·예측 시뮬」절.
2. **R21**: feature 틱 plist 뉴스 문구가 master#0 번호 고정(현역 #2) — arch#11 안 대기(낮은 우선). 원장 design/harness/REQUEST-LEDGER.md.
3. **ops·loom 팀 지원**: 두 master 가 자기 일(ops #891 화면 카드·DA, loom #892·계약 1장)을 진행 중 — 요청이 오면 접수 → arch 안 → 집행. 새 요청은 REQUEST-LEDGER 에 R번호(다음 R27) 등록.
4. 정리 대기: 나노 워크트리 정리 `skipped:cwd 보유 프로세스` — zombie/wt-sweep 틱이 재시도(수동 정리 금지·HIL). 임시 랜딩 워크트리 .worktrees/harness-land-1008·harness-land-teams-1008(브랜치 ops/land-*)는 병합 끝 — worktree 제거·브랜치 삭제는 HIL(planner [HIL]).
5. 보류(커밋 금지·미추적 유지): 대기/gate-hook-kit-equals-home.md(판정 345).
6. 알림 처리: 공유 DA 가 harness-ops 에서 ops 팀 판정문을 씀 → **design/ops/DA-777-org-role-db-r1·r2-verdict.md · DA-891-cards-r1-verdict.md 가 harness-ops 에 미추적 파일로 있음** — ops master(byz-ops-master-claude#0)에게 «ops-main 으로 복사·커밋하세요, harness-ops 의 사본은 두고 커밋하지 않음» 이라고 알려 줄 것(이 스냅샷에서는 건드리지 않음).
7. 후속 후보(기록만): 요약 프롬프트 금지(번호·영어 약어) 모델이 일부 어김 · seats-feature/issues.json _hil_route 가 아직 #7 일 수 있음(planner 현역 #9).

## 현역 좌석
planner `byz-planner-master-claude#9` · cfo `byz-cfo-master-claude#57` · issues `byz-issues-master-claude#3` · feature `byz-feature-master-claude#2` · ops `byz-ops-master-claude#0`+`byz-ops-arch-claude#0` · loom `byz-loom-master-claude#0`+`byz-loom-arch-claude#0` · harness arch `byz-harness-arch-claude#11`(Opus 5.5, cron ac897417) · DA `byz-harness-da-codex#0`(codex sol low, 공유). 정지 레디: harness master #8~#12·arch #8~#10.
내 크론 `2914692a` 는 후계가 부팅 보고 보낸 뒤 CronDelete(후계는 새로 건다).

## 운영 규칙·함정 (실측)
- master 손 = 집행(랜딩·커밋·push·좌석 개설/닫기·명부·원장·검증 파일 cp). 코드·시안·카드 증거 줄 직접 편집 0 — 나노/arch. 단 홈 파일 설치·seats json·env 파일 생성은 집행(arch 안 있을 때).
- 흐름: 발주(골 3줄=GOAL-harness 원문 + 축 1줄, 긴 본문은 Write 후 `mbox relay`) → arch 안 → (DA) → 나노 → master 독립 검증 → arch 재현 §N → 판정서 append(`design/harness/OPS-VERDICTS-20261006.md`) → `ft-index-move.sh … 완성 --da "<판정서경로>#§N" --seat <나노>` → seats-harness.json 의 index 경로 치환 → 커밋(경로 지정 `git commit -m … -- <파일>`) → `git cherry-pick <나노 sha들>` → 닫기.
- 랜딩: origin/main 위에 새 워크트리(`git worktree add .worktrees/<이름> -b ops/<이름> origin/main` + .venv 심링크)에 cherry-pick → 시험 → push → `bash scripts/fable-team-bin/ft-gh-as-tank.sh pr-create "제목" 본문파일 --base main --head <브랜치> --apply`(unset GH_TOKEN) → 감시 스크립트(scratchpad/pr*-watch.sh: RED 체크 제외하고 초록이면 `gh pr merge --squash`) → 병합 뒤 `git archive origin/main scripts/harness-install/slack-mirror`로 main 키트 추출 → `BYZ_ROOT=<루트> bash <키트>/install-magazine.sh`. 충돌: BOARD.md 는 planner 몫(제외), LOOP-LEDGER 는 issues 정본으로 교체.
- mbox: 같은 본문을 여러 좌석에 보내면 BLOCKED FANOUT(파일에 쓰고 relay). 발신 한도 5건/60초. 메시지 본문에 프로세스 종료 명령 글자 금지. 입력줄 뒤 글자는 자동완성 제안.
- 훅: `rm -rf`·`git commit --amend` 등 차단(우회 금지·고유 디렉터리 `mkdir -p` 로 대체) · pkill 금지 · 같은 PR 에 gate-hook 카드 포함 금지. tmuxc open --prompt 는 긴 프롬프트가 비어 보일 수 있음 → 부팅 발주는 `mbox relay` 파일로 보내는 것이 확실.
- ft-role-spawn.sh 는 v65 고정이라 쓰지 않는다(메인 팀 좌석은 tmuxc open + seats-<t>.json 손 등록).
- 시스템 python3 에 pytest 없음 → 워크트리 `.venv/bin/python -m pytest`(나노 워크트리는 PATH 앞에 .venv/bin).

## 환경
워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops` (브랜치 ops/main-base, origin/main 과 squash 로 갈라져 있음·로컬 앞섬). mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`. 판정서 `design/harness/OPS-VERDICTS-20261006.md`(마지막 §52).
