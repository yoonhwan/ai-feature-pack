# HANDOFF — byz-harness-master-claude#24 → #25 (2026-10-10 · ctx 400k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: A(모니터·오빠 요청) + B(개선요청 접수·협의) + C(업그레이드·커밋·push·반영) + 원문 5(머신 독립 배분).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`byz-planner-master-claude#20` · tmux 실측)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id 보고). 전임 크론 `928fa905` 는 세션 종속이라 후계가 새로 건다. BOOT 23조항(`~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md`) 먼저. 좌석표 교체: 루트에서 `bash .fable-team/bin/ft-seat-retire.sh byz-harness-master-claude#24 byz-harness-master-claude#25 --seats .fable-team/seats-harness.json`.★

## 지금 상태 (한 줄)
**하네스는 휴식 — 열린 단위 0 · 하네스 나노 0석.** 마지막 틱 실측: 모든 좌석 IDLE(ft-seat-status turn) · planner#20 pane 에 오빠 선택 화면(`Enter to select`) 20:20Z 부터 열려 있음(오빠 답 대기 · 하네스가 입력 넣지 않음).

## 이번 세션(#24)에 끝낸 것 (전부 origin/main · 설치 cmp OK · 판정서 §115·§116)
- **R70** cherry 게이트 tip==feat HEAD 경로 PASS + spawn `--cherry-override` — PR 1150 `02b45e8832` (§115)
- **R71** spawn ②-0 게이트 첫 인자 INFO_BASE(`--base` sha 여도 «브랜치 없음» 0) — PR 1151 `c1e5ef8912` (§116)
- **R73** v65 drift 94건 = 루트 옛 `.fable-team/bin`(19파일) 기준 · 실 라이브 `v6-realtime-live/.fable-team/bin` DIFF 0 — 실측으로 닫힘(코드 0)
- 그래픽스 팀 집행 도구 역할: 원격 보존 push + nano-close — g678(3 브랜치)·g1153·g1160 나노 전부 닫힘(브랜치 삭제 0) · g678 은 비표준 `--wt/--branch` 모드.
- 좌석표 갱신: `_master` #24 · `_hil_route` planner#20 (harness·graphics 둘 다) · graphics `_master` #1.
- 다음 번호: 판정서 §117 · 요청 원장 R74 · planner 판정 번호 781~.

## 열린 일 (순서)
1. **휴식 유지** — 요청이 오면 그때 착수(planner#20 · 그래픽스 팀장 `byz-graphics-master-claude#1` · v65 master/arch).
2. **R72**(접수만 · 착수 0): spawn `--recheck` 가 판정문의 «정확한 sha» 를 CUR_HEAD 와 대조 → 공용 feat 에 문서 커밋이 들어올 때마다 어긋남. 설계 방향 = 판정문에 `recheck_sha:` 칸 + 그 sha..CUR_HEAD 에 `_chg` 필터 재사용(arch#25 판단). 착수 조건 = R71 닫힘 뒤 · 오빠/planner 지시 때.
3. 별 후보(착수 0): 루트 `.fable-team/bin`(19파일 옛 폴더) 정리/통일 · spawn 233줄(200줄 한도 초과 부채) · merge-tree 충돌 경로 전부 design/ 이면 ①검사 살리기 · 이월(R54·55·56·57·61 · GCE BREACH 2건 · 판정 621 cairn 합치기 · 판정 601 fixture).
4. **하네스 arch**: `byz-harness-arch-claude#25` 가 ctx 400k 경고로 휴식 중(크론 삭제 · 스냅샷 `design/harness/HANDOFF-harness-arch-25-20261010.md` af77e12401). 다음 하네스 설계 요청이 오면 그때 후계 `#26` 을 그 스냅샷으로 열고 `#24` 정리(keep-last-2).

## 현역 좌석 (이름은 승계로 바뀐다 — 보내기 전 `ft-harness-info.sh seats`·tmux 실측)
planner `byz-planner-master-claude#20` · harness arch `byz-harness-arch-claude#25`(휴식) · 하네스 DA 세션 없음(필요하면 새로 열기 · 명부 행 `seats-harness.json` 잔존) · 그래픽스 팀장 `byz-graphics-master-claude#1`(arch·DA·나노 0석 · 명부 arch/DA 행 잔존).

## 운영 규칙·함정 (이번 세션 실측 — 이전 인계서 #23→#24 의 병합 절차·훅 항목도 그대로 유효)
- **환경**: `cd .worktrees/harness-ops && source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM='byz-harness-master-claude#<본인>'` → `$FT_BIN`(=라이브 `v6-realtime-live/.fable-team/bin`). 그래픽스 도구는 `source ../../.fable-team/bin-graphics/graphics-env.sh` 추가.
- ★**추적 사본(`scripts/fable-team-bin/…`)이나 루트 `.fable-team/bin` 으로 spawn/close 를 돌리지 않는다** — 라이브 사본만(드리프트 가드 REJECT 의 원인 · R73 · 그래픽스 팀장도 같은 함정).
- **나노 닫기**: 증거 줄 «이슈» 칸은 `0` 또는 카드 경로만(`#번호` 거부) · 세트 sha = «나노 워크트리 HEAD» 와 같아야 함(main 랜딩 sha 아님) · 나노 워크트리가 등록 브랜치가 아니면 ③ REJECT → 되돌린 뒤 3분 지나야 통과 · 카드 `## 결과` 절 필수 · 명부 `index` 경로가 진행/ 인데 카드가 완성/ 에 있으면 ⑥ 카드 못 찾음 → 명부 경로 고쳐 재시도 · 비표준 브랜치명은 `--wt <경로> --branch <이름>`.
- **원격 보존 push**: 나노 브랜치가 fast-forward 인지 `merge-base --is-ancestor` 확인 → `git push origin refs/heads/<b>:refs/heads/<b>`(★zsh 에서 `$b:refs` 는 수정자로 해석되니 브랜치명을 풀어 쓴다★) · 삭제 0 · `.serena` 0 확인.
- **판정 739(오빠)**: GitHub Actions 한도 소진 — main 에 문서 커밋을 하나씩 push 하지 않고 모아서 push(코드 랜딩 때 같이 또는 묶음 1회) · CI·CD 재실행 반복 0. ops 커밋은 현재 `origin/main` 보다 610개 앞(push 금지 브랜치 `ops/main-base`).
- **fan-out 가드**: 같은 내용을 두 좌석에 연달아 send 하면 BLOCKED FANOUT — 한 좌석(master)에 보내고 전달을 맡긴다.
- **틱 판단**: planner pane 에 `Submit answers` 와 `Enter to select` «둘 다» 검사(하나만 보면 인터뷰 상태 오판) · 인터뷰가 열려 있으면 입력 넣지 않고 «오빠 할 일» 로만 보고. 쉬는 좌석의 «정지 N분» 은 정상.
- **보고**: 오빠 보고 틀 = 결론 1줄 → 오빠 할 일 → 바뀐 것 → 근거 + PR 번호는 맨 아래 표. 휴식 중 틱은 1~3줄.

## 환경
워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops`(ops/main-base · push 금지). mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`(★발주문이 v6-realtime-live 쪽 mbox.sh 경로를 줘도 정본 경로로 recv★). 판정서 `design/harness/OPS-VERDICTS-20261006.md` · 요청 원장 `design/harness/REQUEST-LEDGER.md` · 이전 인계서 `design/harness/HANDOFF-harness-master-23-to-24-20261009.md`.
