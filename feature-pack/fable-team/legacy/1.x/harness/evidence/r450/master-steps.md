# r450 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 가지 `nano/r450-nano-close-suspended-flag-unfinishe` push → PR (나노 push 금지) → 병합 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 = origin/main(7e8791d3 · r444 착지 뒤) 위. 파일 = bin·kit 짝(cmp 0) 2: `ft-nano-close.sh` + 새 `ft-nano-suspended-check.sh` · 새 시험 `tests/test_nano_close_suspended.sh` · 증거 `evidence/r450/`.
   ★버전 번호·CHANGES 머리는 이 가지에 안 넣었다★(r447·r448·r449 병행 가지 충돌 방지) — 착지 순서대로 master 가 다음 번호. 문안 = 아래 «CHANGES 절».
   파일 겹침: r448 도 `ft-nano-close.sh` 1줄(reap 호출 · 자리 다름) — 늦게 착지하는 쪽이 main 병합 뒤 `bash tests/test_nano_close_suspended.sh` 재실행.
2. 되돌림 준비(설치 전): `cp -p <LIVE_BIN>/ft-nano-close.sh{,.bak-r450}` (새 `ft-nano-suspended-check.sh` 는 되돌림 시 삭제).
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>`
   → `cmp <키트>/fable-team/bin/ft-nano-close.sh <LIVE_BIN>/ft-nano-close.sh` = 0 · 같은 cmp `ft-nano-suspended-check.sh` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
4. 실사건 1(닫는 증거 · loom master 손): 막혔던 명령의 `--cherry-override "…"` 를 `--suspended "팀 정지(판정 2365) …"` 로 바꿔 1회 —
   `ft-nano-close.sh 'byz-loom-nano-loom-1442-retired-revision-body-30d-purg#0' --result design/loom/indices/진행/loom-1442-….md --recv 111588 --suspended "팀 정지(판정 2365) · 시험 905 passed / 4 failed + 4 errors(PRICELIST-nike 파일 없음 · 변경 밖)"`
   → 출력 `CLOSED byz-loom-nano-loom-1442-…#0 suspended=1 reason=… set=2f902a9e02…` · 카드 «## 상태» 끝줄 `중단: … · 세트 2f902a9e02… · <날짜> · 재개 = planner 발주 뒤 새 세션(브랜치 nano/loom-1442-… 보존)` · NANO-LEDGER 행 `suspended=1` · `git branch --list 'nano/loom-1442-*'` 1.
   (나노 워크트리에 미커밋이 있으면 close 가 먼저 `[wip] nano close <좌석>` 커밋 → set = 그 HEAD — 2f902a9e02 가 아니어도 정상.)
5. 뒤 일(arch 손 · 착지 뒤): tmuxc `COMM-GUIDE-BOOT.md` 15 «세션만 닫기» 절에 «미완·정지 나노 = `ft-nano-close --suspended "<사유>"`(⑥ 면제 · 카드 중단 끝줄 · 브랜치 보존 · r450)» 1줄 · `DESIGN-finished-cleanup-rules-20261019.md` 에 «미완 가지 닫기 경로» 1줄.

## 동작 요약 (카드 §구현 범위 대조)
- 인자 `--suspended "<사유>"`: 빈 값·공백·여러 줄 = usage 2 · `--superseded-by`·`--cherry-override` 와 동시 = usage 2(순서 무관) · 인자 없으면 동작 불변(rc=1 증거 줄 = 기존 ⑥ REJECT).
- ⑥ 자리: `elif SUSP` — 카드·좌석 워크트리·검사 스크립트 실재를 보고, 앞 조건 전부 통과 ∧ 실작업물 미커밋이면 `[wip] nano close <좌석>` 커밋(.serena/project.yml 은 HEAD 로 · ' D' 는 담지 않음 · 실패 = REJECT 닫힘 0 · `--wt/--branch` 모드는 WIP 0 이라 기존 ⓔ REJECT) → `ft-nano-suspended-check.sh` 검사만.
- ⑤: `--override "suspended: <사유>"` 자동 전달(superseded 와 같은 자리 · cherry 원장 1행).
- 모든 조건 통과 뒤(명부·원장·세션 변경 «전») `--apply` 로 카드 중단 줄(멱등) — 쓰기 실패 = REJECT.
- 원장 행 ` · suspended=1 reason=<사유> set=<HEAD>` · 출력 `CLOSED[-ABSENT] <좌석> suspended=1 reason=<사유> set=<HEAD>` · 브랜치 삭제 0 · 워크트리 정리 = 기존 계획 경로 그대로.

## 편차·범위 밖 (나노 판단 · 근거)
- ① 미커밋 처리: 카드 ⓒ «기존 [wip] 경로가 먼저 커밋» — 기존 [wip] 은 «세션 kill 뒤» 정리 계획 안에서만 돈다(⑥ 보다 늦다). 그래서 close 안에 같은 규칙의 작은 `_susp_wip`(13줄)을 두고 «앞 조건 전부 통과일 때만» 커밋한다 — REJECT 될 닫기에서 HEAD 를 움직이지 않으려고.
- ② 검사 스크립트의 미커밋 판정은 `.serena/project.yml`·' D'(지우다 만 흔적)를 뺀다 — close 의 기존 기본 경로와 같은 기준.
- ③ 역할 무관(superseded 와 같음): 카드를 못 찾으면 REJECT.
- 범위 밖(카드 4): 재개 도구 · 정지 좌석 자동 닫기 · 브랜치 refs/archive 이동.

## CHANGES 절 (착지 번호를 붙여 머리에)

## 2026-10-19 — 미완·정지 나노를 닫는 길: `ft-nano-close.sh --suspended "<사유>"` — ⑥ 만 면제 · 카드 «중단» 끝줄 · 브랜치 보존 (1.1.<N>)

카드 r450 · master 111726 · loom master 111718 «미완 나노 닫는 길이 있나». 팀 정지(판정 2365)로 구현 중 멈춘 loom #1442 나노는 시험 rc=1 이라 ⑥ 증거 줄로 못 닫고, 대체 카드가 없어 `--superseded-by` 도 못 써서 세션·워크트리를 쥔 채 멈춰 있었습니다(거짓 rc=0 금지).

- **ft-nano-close.sh**: 인자 `--suspended "<사유>"`(빈 값·여러 줄·`--superseded-by`·`--cherry-override` 동시 = usage 2) · ⑥ 자리 = 새 검사 · 실작업물 미커밋은 먼저 `[wip] nano close <좌석>` 커밋(실패 = REJECT) · ⑤ 에 `--override "suspended: <사유>"` · 원장 행 `suspended=1 reason=… set=…` · 출력 `CLOSED <좌석> suspended=1 reason=<사유> set=<HEAD>` · 브랜치 삭제 0 · 인자 없으면 동작 불변. bin·kit 짝 cmp0.
- **ft-nano-suspended-check.sh**(새): `<카드> --wt <워크트리> --reason "<사유>" [--apply]` — HEAD(브랜치 위 40hex)·미커밋 0 · `--apply` 면 카드 «## 상태» 끝에 `중단: <사유> · 세트 <HEAD> · <날짜> · 재개 = planner 발주 뒤 새 세션(브랜치 <이름> 보존)`(같은 세트면 0 · 멱등) · 출력 `SUSPENDED-OK card=… set=…`.
- **시험**: `test_nano_close_suspended.sh` ⓐ~ⓖ ALL PASS rc0(옛 close 로 돌리면 FAILED 17 — `evidence/r450/red-old-close.txt`) · 기존 `test_nano_close_*.sh` 5 rc0. 증거 `harness/evidence/r450/test.txt`.
