# HANDOFF — byz-harness-master-claude#25 → #26 (2026-10-10 · ctx 420k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: A(모니터·오빠 요청)+B(개선요청 접수·협의)+C(업그레이드·커밋·push·반영)+원문 5(머신 독립 배분).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`byz-planner-master-claude#21` · tmux 실측 후 `ft-harness-info.sh seats`)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id 보고). 전임 크론 `cdc1cbc9` 는 세션 종속이라 후계가 새로 건다. BOOT 23조항 먼저. 좌석표 교체: 루트에서 `bash .fable-team/bin/ft-seat-retire.sh byz-harness-master-claude#25 byz-harness-master-claude#26 --seats .fable-team/seats-harness.json`.★

## 지금 상태 (한 줄)
**R80 카드 준비 완료 — 나노 spawn 이 첫 집행.** 나머지 R74~R79 는 전부 main(`61384daf80`)·라이브 설치·마감(CLOSEOUT 정본 `design/harness/CLOSEOUT-harness-r74-r79-20261010.md`) · 하네스 나노 0석.

## 열린 일 (순서)
1. **R80 (v65 arch#197 · 쪽지 #71758 · R76 후속)**: `byz_proposal_publish.py` 가 이미 r0~r2 스레드가 있는 제안서를 「승인 — 판정 N」 기록 발행하면 두 경로(--revision 없음 / r3)가 서로 막힘. arch#26 안: 새 플래그 0 · 승인 상태 + `--revision rN` 허용(R76 금지 3줄 제거) · 기록 rN 첫 줄 «*제안서 <key> rN · 기록 판정 N*» · `_root_ts` 원격 찾기에 기록 r0 줄 추가 · 시험 5건. 카드 `design/harness/indices/대기/r80-proposal-publish-record-revision.md`(ops bc48f39695 · lint OK). 집행: `source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM='byz-harness-master-claude#26' && bash $FT_BIN/ft-nano-spawn.sh <카드> --agent claude --model 'claude-sonnet-5-5[1m]' --effort high --from 'byz-harness-master-claude#26' --base origin/main` → 나노 산출 시험 재실행 → ★설치 전 diff: 라이브 `~/.hermes/scripts/byz_proposal_publish.py`·`proposal_text.py` 가 main 과 다름(R76 설치본 · arch 실측) — 라이브 vs main 키트 diff 먼저 확인★ → DA(`byz-harness-da-codex#1` · 필요 시) → 설치(.bak·cmp) → main 랜딩(push 승인값 필요) → arch#197 에 결과 1줄. 이 카드는 `- 제안서:` 줄이 «없음 — 도구 결함 수정(R76 후속)» (R77 게이트: 2026-10-11 이후 새 카드부터 의무).
2. **후보(착수 0)**: R78 매거진 시험 5건(collect_decisions 4·summary 1 — 낡음 vs 결함 판별) · R72 spawn --recheck `recheck_sha:` 칸 · 루트 `.fable-team/bin` 옛 폴더 정리 · ft-nano-spawn 236줄(200줄 한도 부채) · loom 사후 Issue 7건(issues master 몫).
3. **묶음 push 대기(판정 739)**: ops/main-base 로컬 커밋(원장 R79·R80·CLOSEOUT·카드 증거 줄 등)은 push 금지 브랜치라 코드 랜딩 때 land 브랜치로 옮겨 같이 올린다(방법: 이번 PR 1178 = `git worktree add .worktrees/harness-land-… -b land/… origin/main` → nano 브랜치 merge → 문서 `git show ops/main-base:<f> > <f>` → 로컬 시험 → push → `gh pr create --body-file` → `gh pr checks` 별 명령 → `gh pr merge --squash` 별 명령 → tree 대조). push 는 오빠 명시 승인값 때만(planner#21 경유 [HIL]).

## 이번 세션(#25)에 끝낸 것 — 전부 main `61384daf80`(PR 1178) · 마감 정본 CLOSEOUT
R74 매거진 크기 상한(건당 3줄+위치1줄·절당 20건·경보선 1,500줄) · R75 zombie-clean keep-last-2(하한 2·세대 #N 정렬) + 문서 3곳 정정(판정 820) · R76 제안서 «기록» 발행 · R77 «오빠가 본 승인» 게이트(제안=GitHub Issue·approved 라벨·인터뷰 훅·라벨 5종 · 판정 826) · R79 GCE 가드 «의도된 정지»(CCU VM 2대 · ops-guard 로컬 적용 · BREACH.md 없음) · 좌석표 `_master` #25 · `_hil_route` planner#21 · 다음 번호: 판정서 §117 · 요청 원장 R81 · planner 판정 836~.

## 운영 규칙·함정 (이번 세션 실측)
- **환경**: `cd .worktrees/harness-ops && source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM=…` → `$FT_BIN`(=`v6-realtime-live/.fable-team/bin` 라이브). mbox 정본 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`(발주문이 다른 경로를 줘도 정본으로 recv).
- ★**DA(codex) 좌석은 `recv` 출력이 CCR(headroom 압축 참조)로 접혀 읽지 못한다**★ → 발주문을 `/tmp/mbox/<파일>.md` 로 쓰고 `tmux send-keys -l` 로 「파일을 sed -n 1,10p → 11,20p … 나눠 읽기」 지시 + 별도 호출 Enter · 판정은 mbox send.
- ★`ft-role-spawn.sh da` 는 v65 DA 행을 교체해 버린다 — 하네스 DA 는 `zsh -lc 'tmuxc open <wt> --name byz-harness-da-codex#N --agent codex --model gpt-6.1-sol --effort low'`★ · bounded DA: 2회 HOLD 면 중단(3차는 planner 허가 — 판정 832 사례).
- ★키트 `install-magazine.sh` 는 R76 설치본(byz_proposal_publish.py)을 옛 버전으로 덮어쓴다 → 바뀐 파일만 개별 cp(.bak + cmp)★.
- ★라이브 bin 을 main 키트와 다르게 설치하면 드리프트 가드가 전 팀 nano-close·spawn 을 REJECT → 항상 «main 랜딩 → 라이브 cp → `ft-live-bin-drift-check.sh --bin $FT_BIN --repo <리포> --ref origin/main`»★.
- **나노 닫기**: 증거 줄 `세트: <40hex> · 시험: … rc=<n> · 이슈: 0` 을 카드 `## 결과` 에 append → `ft-nano-close.sh <좌석> --result <카드> --recv <seq> --cherry-override "<사유>"`(squash 랜딩은 cherry 불일치 → 파일별 `git diff <nano>:<f> origin/main:<f>` 동일 확인 후 사유로 우회) → KILLED(브랜치 보존) · 워크트리 정리는 cwd 프로세스로 skipped 가능(sweep 재시도).
- **gh**: `unset GH_TOKEN` · PR 본문은 Write 로 파일 → `--body-file` · 체크 확인과 merge 는 별 명령. Tank 라벨·Issue 쓰기 = `ft-gh-as-tank.sh … --apply`.
- **tmux 입력**: 남의 pane ❯ 뒤 글자 = 고스트 서제스천(BOOT 17). 인터뷰 열려 있으면(`Submit answers`·`Enter to select`) 입력 금지 — 보고만. 틱 시 planner#21 에 선택 화면이 오래 열려 있으면 «오빠 할 일» 로 올린다.
- **보고**: 오빠 보고 틀 = 결론 1줄 → 오빠 할 일 → 바뀐 것 → 근거 + 번호는 맨 끝(PR·Issue 는 각주 표). 휴식 중 틱은 1~3줄.
- **zsh**: `$B:path` 는 수정자로 해석 · `$F`(여러 줄)는 단어 분리가 안 된다 → 파이프 + `xargs`.

## 현역 좌석
planner `byz-planner-master-claude#21`(#20 은 증류됨) · harness arch `byz-harness-arch-claude#26`(Opus 5.5 · 휴식 · R80 카드까지 완료) · arch#25(옛 계보 · 휴식) · DA `byz-harness-da-codex#1`(gpt-6.1-sol low · 대기) · 그래픽스 팀장 `byz-graphics-master-claude#1` · 나노 0석 · loom 현역 `byz-loom-master-claude#12` · v65 arch `byz-v65-arch-claude#197`.
