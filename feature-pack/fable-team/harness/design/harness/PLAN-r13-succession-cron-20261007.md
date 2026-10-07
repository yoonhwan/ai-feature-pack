# PLAN — R13 승계 시 체크 크론 미이관 (arch#6 안 · 2026-10-07 · 미커밋)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: 원문 6-b(CFO#54 요청 #59304 접수·개선) — 원장 R13.

## 결론
승인(A·B 수정 승인 · C 승인 = 별도 카드). ★«승계 발주 템플릿» 파일은 하나가 아니다★ — 후계 좌석이 «반드시» 읽는 지점은 BOOT 하나뿐이라 B 가 본체, A 는 경로별 보강.

## 실측 (이 안의 전제 — 바이트로 확인)
1. 승계 진입로는 셋이고 서로 다른 글을 보낸다:
   - ft-role-spawn.sh 95행 BODY(Seatbelt 역할 교체 · SEATBELT-README §2 부팅 5단계로 보냄) — 크론 0.
   - tmuxc SKILL.md 75행 주입문(내가 받은 첫 줄 · 「COMM-GUIDE-BOOT.md(12줄)」) — 크론 0.
   - 오케가 손으로 쓰는 승계 발주문(master#8 → 나 #59336 은 크론 단계가 «있었다» — 손으로 넣었기 때문).
   세 길 모두 BOOT 를 읽힌다 → BOOT 1줄이 모든 길을 덮는다.
2. 승계 6단계 ⑤「뉴스·크론이 후계로 가는지 확인(tick 로그·seats.json _replaced_by)」의 «크론» 은 launchd ft-tick 이다. 세션 CronCreate 는 단계에 없다 — 이름이 같아서 «확인했다» 로 읽힌다(이번 결함의 직접 자리). 같은 문장이 3곳: fable-team SKILL.md 224 · references/context-management.md 108 · templates/rules/orchestration.md 48 (+ 각 키트 사본).
3. 감지 수단 실재: 세션 jsonl 에 tool_use "name":"CronCreate" 가 남는다(이 세션 jsonl grep 2건 실측). Stop 훅 입력에 transcript_path 가 오므로 좌석↔jsonl 매핑 문제 없음.
4. ★BOOT 사본 어긋남(C 축 · 별건 보고)★: 라이브 ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(sha256 앞16 d3a4d632985b04f3) ≠ 키트 ai-feature-pack/feature-pack/tmuxc/claude-code/skills/tmuxc/COMM-GUIDE-BOOT.md(커밋 3493f4a 09-23) — 라이브에만 13·14·15조항 + 2·8조항 수정. 라이브 직접 편집 뒤 키트 역반영 0. 줄 수 표기도 제각각(BOOT 머리 14줄인데 15조항 · boot-read-gate 문구 14줄 · tmuxc SKILL·ft-tmux-spawn 주입문 12줄).
5. ai-feature-pack main 에 미커밋 변경(main-team-governance.md M + .bak 3개 + harness-map.md ??) — master 집행 대기분으로 보임. B 설치 때 같은 리포를 건드리므로 먼저 정리 필요.

## B (본체) — BOOT 16조항 (arch 초안 = 완성본 · master 는 cp+cmp)
- 초안: design/harness/drafts/r13/COMM-GUIDE-BOOT.md (라이브 바이트 + 머리 14→16줄 + 16조항 1줄). 다른 줄 변경 0.
- 16조항 요지: master·planner·arch 는 부팅 보고 그 턴에 CronCreate 10분(recv + 하위 pane 실측 + 오빠 3줄) · 없으면 착수 0 · ft-tick 과 별개 · 부팅 보고에 cron=<job id> · 받는 오케는 빈칸이면 되묻기 · 닫을 때 CronDelete.
- 대상 좌석 범위: master·planner·arch. 나노·tester·checker·DA 는 발주 이벤트로만 움직여 제외(크론을 걸면 오히려 빈 틱 소음).
- 줄 수 영향: BOOT 45→46줄 · 매핑표 무변화(COMM-GUIDE.md 전문 sha16 d64777274c4b371a 그대로 — 전문은 안 바꿈).
- 집행 순서: ①ai-feature-pack 미커밋 정리(master) ②라이브 → 키트 역반영(구조 커밋, 현 라이브 바이트 그대로) ③초안을 라이브·키트 둘 다 cp + cmp ④키트 커밋·push(행위 커밋). ②와 ④는 분리 커밋(Tidy First).
- 되돌림: 라이브 = .bak 복원(설치 전 cp 로 COMM-GUIDE-BOOT.md.bak-1007-r13) · 키트 = revert.

## A (보강) — 경로별 문구 (나노 카드 1장 · BYZ 리포)
1. ft-role-spawn.sh BODY(추적본 scripts/fable-team-bin + 키트 scripts/harness-install/fable-team/bin 같은 바이트 · test_kit_bin_sync): role 이 master·arch 일 때(planner 는 master 역할로 들어감 · pm 은 launchd ft-pm-tick 이 있어 제외) BODY 끝에 「부팅 보고 직후 CronCreate 10분 체크 틱 — 보고에 cron=<job id> (BOOT 16)」 1문장. 다른 role 무변화.
2. 승계 6단계 ⑤ 문구 분리(3곳 × 라이브·키트): 「⑤ 틱이 후계로 가는지(launchd ft-tick · seats.json _replaced_by) + 후계 부팅 보고의 cron=<job id> 확인(세션 크론은 옮겨지지 않는다)」. 이 3곳은 ai-feature-pack 쪽이라 B 와 같은 리포 — B 집행 때 같이 넣는 것을 권고(카드는 BYZ 쪽 1·키트 templates/rules/orchestration.md 만).
3. tmuxc SKILL.md 75행 주입문: 「(12줄)」 → 줄 수 삭제(「COMM-GUIDE-BOOT.md 를」) — 숫자가 계속 어긋나므로 지우는 쪽이 단순. boot-read-gate 문구 「(14줄)」도 같은 처리. ★선택★ — 오빠 결정 불요(문서 오타급), master 판단.
- 구 arch 원장 top10 방지책(「승계 첫 턴 CronCreate 10분」)은 이미 항상 로드되는 dumb-time-ledger 에 있다 — 그런데도 재발(×4)했다. 즉 «항상 로드» 만으로는 안 되고 «보고 칸(cron=)» 으로 «안 쓰면 보고가 안 써지는 형태» 가 필요하다(하드 룰 7 「못 적히는 형태여야 경보」).

## C (감지) — 가능 · 별도 카드 · B 랜딩 뒤
- 수단: Stop 훅 cron-missing-gate(신규). 입력 transcript_path·session_id·stop_hook_active.
  조건 전부 참이면 exit 2 + stderr 1줄(「[cron-gate] 오케 좌석인데 이 세션 CronCreate 0 — BOOT 16」): ①tmux 세션명 역할 토막 ∈ master·planner·arch(ft-name-lint 규칙의 역할 토막) ②transcript 안 마지막 CronCreate tool_use 의 timestamp < 이 claude 프로세스 시작 시각(없음 포함 — resume 로 크론이 사라진 경우도 잡는다) ③stop_hook_active=false ④session_id 당 차단 1회(.fable-team/state/cron-gate/<session_id>) — 2회째부터 stderr 경고만 exit 0.
- 거짓 경보: 닫는 중 세션(CronDelete 뒤) → ②가 마지막 CronCreate 를 보므로 경보 0. 부팅 첫 턴(보고·크론을 같은 턴에 하면 0) · 역할 토막 없는 옛 이름(ft-harness-ops#6 등) → 대상 밖(놓침 · 이름 lint REJECT 좌석이라 별건). 7일 자동 만료는 마감 방침상 좌석 수명 밖이라 무시.
- 놓침 위험: transcript 형식 변경 → 훅은 fail-open + ~/.claude/logs/cron-gate.log 에 error 1줄(#0 RULE: 무음 아님).
- 「오케 jsonl 에 크론 0 이 N분이면 ring」(요청 원안)은 tick 데몬이 좌석↔jsonl 을 매핑해야 해서 무겁다 — Stop 훅이 같은 일을 매핑 없이 한다. ring 안은 반려.
- 설치는 governance ②③(가드 훅·settings.json 등록) — 훅 3사본(홈·프로젝트·키트) 정합 문제(인계문 열린 일 5)와 겹치므로 C 카드 착수 전에 사본 정본 위치부터 정한다.

## 카드 구성 (파일 겹침)
| 카드 | 리포 | 파일 | 겹침 |
|---|---|---|---|
| B (arch 초안 → master cp+cmp) | 라이브 + ai-feature-pack | tmuxc/COMM-GUIDE-BOOT.md (+ 6단계 3곳 권고) | ai-feature-pack 미커밋분과 같은 리포 |
| A 나노 r13-role-spawn-cron | BYZ | ft-role-spawn.sh 2사본 + templates/rules/orchestration.md | ft-role-spawn = role-spawn-byz-default(86d77d5f6a) 다음 판 — base 최신 main |
| C 나노 r13-cron-gate | 라이브 hooks + 키트 templates/hooks + settings | cron-missing-gate.sh 신규 | 훅 사본 정합 행과 겹침 → 그 행 뒤 |
순서: B → A → C. B 만으로 이번 결함(후계가 크론 단계를 못 봄)은 닫힌다. 닫는 증거 = 다음 승계 좌석의 부팅 보고에 cron=<job id> 칸 실재.
