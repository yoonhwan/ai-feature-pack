# REQ — tmux 세션명 현황 · tmuxc/tmm 이름 처리 · 이름에 기대는 스크립트 실측 (ft-harness-arch#1 → ft-harness-nano#1 · 2026-10-05 · 조각 P6)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
>
> 골의 축: 표 A(모니터) — 세션 이름이 일관돼야 명부·모니터가 이름만 보고 팀·역할·계보를 안다. 발주 = ops#2 ORDER-session-naming(#57004).

읽기 전용 · 이름 변경·kill 0 · Slack 0. 산출 `design/harness/issue-improvement/FACTS-session-naming-20261005.md`(표 4개 · [사실]/[추측] · 「파일:줄」 또는 명령 1줄) + 원본 `facts-raw/N*.txt`. 측정 시각(KST) 1줄.

## N1. tmux 세션 전수 — 이름 패턴 분류
`tmux list-sessions -F '#{session_name}\t#{session_created}\t#{session_attached}'` 전부 → 패턴별 묶음: `ft-<팀>-<역할>#N` · `ft-<팀>-temp-<slug>#N` · `FB_<팀>#N` · `<팀>_<역할>#N`(CFO_·CCU_·DATA_) · `byz-<팀>-<역할>#N` · `repro-*` · KakaoBot · airag · tmm · 기타. 각 묶음 = 건수 + 예 2개. **같은 팀인데 두 문법인 경우** 따로 표(예: v65 = `ft-v65-*` vs cfo = `FB_CFO`+`CFO_*`).
+ 각 세션의 `@zc_v65_active` 등 user option: `tmux show-options -t <s> | grep '^@'` 로 태그 종류·건수.

## N2. tmuxc 가 이름을 만드는 방식
`~/.claude/skills/tmuxc/` 안 스크립트(`tmuxc` 본체 · open 서브커맨드): `--name` 처리 · 자동명 생성 규칙(기본 접두·`#N` 증가 로직·`--like`) · 이름 유효 문자 제한 · 중복 시 동작 — 「파일:줄」 + 1줄 인용. `#` 가 tmux target 문법과 충돌하는 처리(`=` 접두 등)가 있나.

## N3. tmm 이 이름을 읽는 방식
`tmm` 실체 위치(`which tmm` · 심링크 target) · 이름에서 카테고리/팀/역할을 뽑는 정규식·접두 표 · HUMAN/BLOCK 표시 판정에 쓰는 것(이름? pane 내용?) · `tmm ss`·`tmm h` 가 보는 필드 — 「파일:줄」.

## N4. 이름에 기대는 스크립트·규칙
`grep -rn` 대상: `.worktrees/v6-realtime-live/.fable-team/bin/*.sh` · `.fable-team/bin-*/*.sh` · `~/.claude/skills/zombie-clean/**` · `.fable-team/comm/mbox.sh` · `hooks/*.sh`(orchestration-gate · context-distill-gate) · `.fable-team/seats*.json` 의 `_lineage`/접두 키.
찾을 것: ①`ft-v65-temp` 같은 **리터럴 접두**(단위 3-4 「v65 리터럴 21/39」와 대조) ②`#N` 계보 파싱(keep-last-2 · `_replaced_by`) ③역할 추출(`-master-`·`-arch-`·`-da-`·`-nano-`·`-tester-`) ④`@zc_*` 태그 이름. 각 = 「파일:줄」 1줄 인용 · 서로 **어긋나는 가정**(한 스크립트는 `ft-` 접두 요구 · 다른 스크립트는 `FB_` 허용 등) 목록.

회신 mbox 3줄: 경로 · 못 한 항목 · 사실/추측 비율. 커밋 0.
