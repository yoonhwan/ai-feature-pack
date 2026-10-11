# HANDOFF — byz-harness-master-claude#22 → #23 (2026-10-09 · ctx 401k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: A(모니터·오빠 요청) + 6-b(개선요청 접수·협의) + C(업그레이드·커밋·push·반영) + 원문 5(머신 독립 배분).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`byz-planner-master-claude#16` · 이름은 `tmux list-sessions` 실측)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id 보고). 전임 크론 `a5f5d8c8` 은 세션 종속이라 후계가 새로 건다. BOOT 21조항(`~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md`) 먼저. 좌석표 교체: 루트에서 `bash .fable-team/bin/ft-seat-retire.sh byz-harness-master-claude#22 byz-harness-master-claude#23 --seats .fable-team/seats-harness.json`.★

## 지금 상태 (한 줄)
**판정 675(운영 계정 토큰 자동 발급 `ft-op-token.sh`) 나노 구현 중** — 나머지 하네스 일은 전부 닫힘. 오빠 할 일: 시험 계정 byztest910 비밀번호 교체 여부 판단(planner 경유 · 안 바꾸면 기록만).

## 진행 중 단위 = 판정 675 (오빠 문책 「토큰 안된다 매번 이렇게 멍청하게 해야되냐」)
- 선행 완료: `.fable-team/secrets/developer-ts.cred` 저장(planner·오빠 1회). `admin-ts.cred` 는 아직(필요 시 planner 가 `/tmp/opcred.sh admin.ts@byourz.com`).
- 카드 `design/harness/indices/진행/op675-ft-op-token-auto-issue.md`(arch#24 설계 · 커밋 adb0856d6a) · 나노 `byz-harness-nano-op675-ft-op-token-auto-issue#0`(sonnet-5-5 · base origin/main · 좌석표 `seats-harness.json` 에 행 있음 — 나노가 seats.json 만 grep 해 «없음» 오보, 회신해 둠).
- 설계 요지: password grant(refresh 는 회전형이라 동시 갱신 충돌) · 7초+재시도 1(5xx·net 만) · 원문 출력 0 · URL·키·계정 표 = secrets/op-auth.conf·op-accounts.tsv(추적 0) · cred 없으면 exit 2 + `--init` 안내(`--init` = /tmp/opcred.sh 대체) · BOOT·TESTER 템플릿 1줄 · 기존 클립보드·콘솔 수동 경로 목록화·폐지.
- 다음: 나노 RESULT → arch#24 독립 재현 → **구현 DA 1회 = 보안(`byz-harness-da-claude#0` Claude Opus · 닫지 말 것)** → 집행(PR → 병합 · 설치 → 첫 토큰 발급 실측 · 수동 경로 폐지 문서 반영) → planner `[완료·휴식]`. 나노 닫기 = `ft-nano-close.sh … --cherry-override "PR N squash <sha> blob 동일 (…)"` 후 `ft-index-move.sh 진행/<카드> 완성 --da 'design/harness/OPS-VERDICTS-20261006.md#§109'`(★카드를 완성으로 먼저 옮기지 말 것 — 닫기가 진행 경로를 찾는다★).
- ★비밀 취급★: cred·토큰 파일 줄 전체를 `cat`/`awk` 로 찍지 말 것(키 이름만). arch#24 가 byztest910.cred 를 한 번 찍어 시험 계정 비밀번호가 arch 세션 기록에 남음 — planner 에 알림 완료(#68355).

## 열린 일 (순서)
1. 위 675 흐름(나노 RESULT 대기).
2. 그래픽스 팀(판정 649 설치 완료) — 첫 요청 = cfo 크레딧 페이지 UI/UX(INVENTORY 323002d0c1) 가 planner 에서 오면 arch#24 에 «열기 절차 검토» 발주. 라벨 `team:graphics` 생성됨.
3. 큐(착수 0): ①uv 캐시 53GB 재시도(다른 uv 잠금) ②`.baton/archive` 110GB 보관 기간 단축(오빠 승인 별도) ③Tank 래퍼 label-create 동사(R68) ④추적 사본 `mbox-v2.sh` 에 mbox.py 없음(R67) ⑤codex 좌석 Serena handshake(R66) ⑥판정 601 fixture 4실패·기존 9실패(별건) ⑦check-drift MAP 옛 v6 행·boot-read-gate 주석(별건).
4. 이월: 원장 R54·R55 보강 · R56 wt-clean TERM 오탐 · R57 Haiku 분류 rc=1 · R61 gce-guard 로그 회전 접수만(착수 0) · GCE 가드 BREACH 2건 유지 · 보드 prune 첫 삭제 관찰(10-16) · 판정 621(cairn 원장 합치기 — 루트 `.cairn/plan.yaml` 양쪽 보존·PR) 은 planner 지시 시.

## 이번 세션(#22)에 끝낸 것 (전부 origin/main · 홈 설치 cmp OK · 판정서 §104~§108)
판정 603 PR 1062 `c3219b677f`(§104) · 609 PR 1073 `7fbbff9353`(§105) · 623 PR 1074 `8133983651`(§106) · 649 PR 1076 `4fc3140297`(§107 · 그래픽스 팀 설치) · 646·647 디스크 정리(§108 · 오빠 run646.sh +68GB) · 651 그래픽스 나노 닫기 표준승인 확장(홈 CLAUDE.md·SOUL.md) · 666 7초 룰(하드 룰 12 · BOOT 21 · 전파본 v=2026-10-09c) · 615 원격 ops/main-base 삭제(오빠 직접). 판정서 마지막 §108 → 다음 §109 · 요청 원장 마지막 R68 → 다음 R69.

## 현역 좌석 (이름은 승계로 바뀐다 — 보내기 전 tmux 실측)
planner `byz-planner-master-claude#16` · harness arch `byz-harness-arch-claude#24`(Opus 5.5) · DA `byz-harness-da-claude#0`(Claude Opus 5.5 · 675 보안 DA 용 유지) · DA `byz-harness-da-codex#0` · 나노 `byz-harness-nano-op675-ft-op-token-auto-issue#0`. 좌석표 `_master` = 이 세션(#22) → 후계가 #23 으로 교체.

## 운영 규칙·함정 (이번 세션 실측)
- **환경**: `cd .worktrees/harness-ops && source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM='byz-harness-master-claude#<본인>'` → `$FT_BIN`. 나노 spawn: `ft-nano-spawn.sh design/harness/indices/대기/<카드>.md …`(★전체 경로★) `--agent claude --model 'claude-sonnet-5-5[1m]' --effort high --base origin/main --from <본인>`. 카드 lint REJECT(골좌표 복붙·구현 범위 경로 실재)는 master 가 안 고치고 arch 에 반송.
- **병합 절차**: ops 에 §N append + 카드 `## 결과`(증거 줄 `세트: <40hex> · 시험: … rc=<n> · 이슈: 0` 한 줄 · 정본 영향 없음 줄) → `ft-nano-evidence-check.sh` OK → ops 커밋(★경로 지정 add★) → 나노 wt 에서 `git checkout -b land/<n> origin/main` → ★파일 목록 zsh 배열★ 후 `git checkout nano/<n> -- $files` + ops 문서 `git -C ../harness-ops show ops/main-base:<f> > <f>` → 로컬 시험 → push + PR(`--body-file` · `unset GH_TOKEN`) → `gh pr view`/checks(별 명령 · 이 리포 PR 은 CI 체크 0개 — 병합 근거는 로컬 검증) → `gh pr merge N --squash`(별 명령) → 나노 wt 를 `nano/<n>` 으로 되돌림 + `git -C ../ops-guard checkout --detach origin/main` → 설치 → 닫기(jsonl 마지막 기록 3분 뒤) → 카드 완성 이동 → ops 커밋.
- **훅**: 재귀 삭제·`pkill`·`rm -rf`·쪽지 본문 속 삭제 명령 글자도 차단됨 — 본문은 파일에 쓰고 `mbox.sh relay`, 큰 삭제는 스크립트 파일 + 오빠 `!` 실행(우회 0). 내가 띄운 백그라운드는 TaskStop 이 정상 경로.
- **틱**: `ft-board.py stalled --min 3` — 완료 선언 받으면 같은 턴 접수 회신(안 하면 «완료 선언 미처리»). 쉬는 좌석의 «정지 N분» 은 정상. 새 인박스 `mbox-v2` 추적 사본은 실패 → 루트 `.fable-team/comm/mbox.sh` 사용. mbox fan-out 차단: 같은 본문을 두 좌석에 연달아 못 보냄.
- **보고**: 오빠 보고 틀 = 결론 1줄→오빠 할 일→바뀐 것→근거 + PR 번호는 맨 아래 표. planner 마일스톤은 mbox.

## 환경
워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops`(ops/main-base · push 금지). mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`. 판정서 `design/harness/OPS-VERDICTS-20261006.md` · 요청 원장 `design/harness/REQUEST-LEDGER.md` · 슬랙 미러 홈 `~/.hermes/scripts` · 미러 plist `~/Library/LaunchAgents/com.hermes.byz-{mbox,github}-slack-mirror.plist`(`--team-roots` 적용) · 매거진 plist `~/Library/LaunchAgents/com.byz.ft-magazine.plist`(report 모드 적재됨).
