# PLAN — RELEASE 0.4 집행 + Issue 816 트리아지 (arch#7 안 · 2026-10-07)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골 축: 원문 1 C(배포·반영) + 원문 5(머신 독립 배분 — 이 Mac 의 라이브 = 키트 sha 하나).

## 결론
**816 = 범위를 좁혀 채택.** 「라이브 = main 키트 1:1」 은 지금 «덮어쓰기 한 번»으로 닫을 수 있다. 라이브에만 있는 변경이 0이라는 것을 이력으로 증명했기 때문이다(아래 실측). 설계서의 ⓪ 「라이브를 main 에 채택」 단계는 필요 없어졌다. ②③ 「드리프트 검사·어긋남 BLOCK」은 나노 카드 1장으로 낸다. ⑤ 「FT_BIN 을 v65 워크트리 밖으로 이전」은 별건(완성 후)으로 뗀다.

## 실측 (2026-10-07 · origin/main 16201f18ea)
- 라이브 `.worktrees/v6-realtime-live/.fable-team/bin`(38개) vs 키트 `scripts/harness-install/fable-team/bin`(73개): 같음 33 · 다름 5 · 키트에만 35 · 라이브에만 0. press 게이트 2파일은 R9 로 이미 같음.
- ★다른 5개는 전부 «정본의 옛판»이다 — 라이브 파일 blob 이 git 이력의 추적본 blob 과 바이트까지 같다★:
  | 파일 | 라이브 = 이 커밋의 추적본 |
  |---|---|
  | ft-nano-close.sh | bc87df1302 |
  | ft-nano-spawn.sh | 3928822c16 |
  | ft-nano-slots.sh | 3928822c16 |
  | ft-nano-evidence-check.sh | 3928822c16 |
  | ft-role-spawn.sh | 5663d3f9ce |
  → 덮어써도 잃는 변경 0. 10-04 의 «라이브가 더 최신»은 그 뒤 추적본이 전부 따라잡아 해소됐다.
- 라이브 소비자: 팀 env 6장의 FT_BIN · launchd `com.byz.ft-tick`·`com.byz.ft-tick-cfo`(ft-tick.sh — 키트와 같음) · v65 좌석의 직접 호출.
- 새 nano-close 의 팀 env 자동 로드는 `byz-<팀>-nano-` 이름에만 걸린다. v65 나노는 `ft-v65-temp-` 이름이라 기본값으로 돈다. ROOT 는 git common dir(리포 루트)이라 `bin-<팀>` 을 찾는다 → v65 무영향.

## 이유 3줄
1. 라이브에만 있는 줄이 0이면 «먼저 채택»은 빈 단계다. 덮어쓰기 + 되돌림 tar 가 가장 짧은 길이다.
2. 손 cp 를 반복하면 오늘처럼 다시 어긋난다(5개가 그렇게 뒤처졌다). 그래서 «다르면 막는 검사»(②③)가 1:1 을 «유지»하는 장치다.
3. ⑤ 이전은 env 6장 + plist 2개 + launchd 재적재를 건드리는 큰 단계다. 1:1 이 지켜지면 위치는 문제가 아니다. 단 v6-realtime-live 워크트리를 정리하는 순간 하네스가 같이 죽으므로, 그 전에는 반드시 해야 한다 → 「완성 후 · v65 마감 전 선행」으로 적는다.

## 집행 순서 (master)
1. 창: press 0 · 진행 중 나노 spawn/close 0 확인 · 팀 master 들에 1줄(「라이브 하네스 도구 교체 — 끝나면 알림」).
2. 백업: `tar -cf .fable-team/state/live-bin-pre-0.4-1007.tar -C .worktrees/v6-realtime-live/.fable-team bin`.
3. 교체: `cp -p scripts/harness-install/fable-team/bin/* .worktrees/v6-realtime-live/.fable-team/bin/`(origin/main 체크아웃 기준 · 지우기 0 — 라이브에만 있는 파일이 없으므로 rm 불필요).
4. 확인: `diff -rq` 키트 bin ↔ 라이브 bin(.bak*·__pycache__ 제외) = 0줄 · 대표 셋 `ft-nano-close.sh`·`ft-press-gate.sh` SELFTEST 류 1회 · launchd ft-tick 다음 틱 로그 1줄 정상.
5. 되돌림: tar 풀기 1줄.
6. RELEASE-0.4.md 「이 Mac」 행 = `install.sh --machine MacBook-Pro`(dry-run) 의 kit_sha + diff 0줄 → 「반영됨」.
7. 816 코멘트: «⓪ 불요(실측 표) · 1:1 집행 sha · ②③ 카드 · ⑤ 완성 후 분리» → planner 컨펌 경로(issues master)로 816 범위 축소 승인.

## 카드 후보 (승인 뒤 arch 가 씀 · 나노 1장)
- `ft-live-bin-drift-check.sh` — 키트 bin ↔ FT_BIN(라이브)을 cmp 해서 다르면 목록 + exit 1. ft-tick(10분)에 «경고 1줄»로 걸고, ft-nano-spawn·close 입구에서는 «BLOCK»(어긋난 도구로 나노를 열고 닫지 않음). 시험 = mktemp 두 폴더.

## 완성 전/후
- 완성 전(하네스 골 원문 1 C): 1~7 집행 · 드리프트 검사 카드.
- 완성 후: ⑤ FT_BIN 을 `~/.fable-team/<팀>/bin`(install.sh DEST)으로 이전 — 단 v6-realtime-live 워크트리 정리보다 «먼저».
