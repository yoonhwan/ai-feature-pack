# CLOSEOUT — 하네스팀 랜딩 · 레포 분리 끝선 6/6 완성 (2026-10-19)

> 오빠 원문(2026-10-19 00:5x): «자 그럼 우리 하네스 정리한 것은 ai-feature-team 에 남기고 완성으로 기록하고.»
> 기록자: byz-harness-master-claude#72 · 발주 = desk #109684 · 원본 끝선 표 = BYZ-Agents `design/harness/GOAL-harness.md`(4e2e3b8145)

## 골 원문

- A6 골 4: «하네스팀 랜딩부터»
- «하내스팀 설치부터 사용해서 버그및개선 반영해» «그다음은 플랜팀이고» «그리고 전체설치» (판정 2262)
- «패블팀 로컬설치파일들과 융합하는게 좋갰는데 패치랑 버저닝 그리고 산출물관리 편하게» (판정 2270·2271)

## 끝선 6/6 — 단계별 상태와 닫는 증거

| # | 단계 | 카드 | 닫는 증거 | 상태 |
|---|---|---|---|---|
| ① | 경로 치환 + 이동 점유 검사 | r382b + r382d | BYZ main r382d `c261ed6f0c`(#1923) · r382b `0e894be3e2`(#1924) | 닫힘 |
| ② | 12팀 이동 | r383 | BYZ main r392 `e080ee5b78`(#1929) · 이동 `2635a56b8a`(#1927) · r391 `711199fd62`(#1928) · teamset OK 9 · ERR 4 = arch 좌석 없음(경로 무관) | 닫힘 (판정 2294) |
| ③ | 팩 합치기 | r384 | ai-feature-pack #49 MERGED `c545a5d4c2` · 파일 1832 sha256 일치 · 이력 246=246 | 닫힘 |
| ④ | 실행 위치 전환 | r385 | 팩 #50 `4153139d` · #52 `8cfb7582` · #53 `dbf4518c` · LIVE_BIN → `~/.claude/fable-team/live/1.1.3/bin` · install-check OK n=270 · drift OK · 실제 쪽지 가드 통과(mbox #109635) | 닫힘 (판정 2299·2300) |
| ⑤ | BYZ 쪽 삭제(비가역) | r386 | BYZ main `70c8e7c203`(#1930) · 팩 #51 `4770e0b4` · 골 표 rc0 · install-check OK n=270 | 닫힘 (판정 2301) |
| ⑥ | 설치 후 지속 개선·확인 지원 | 지원 루프 + R393~R399 | master 틱 지원 루프 줄 · R393~R399 큐 7행 등록(5271acc4a9 · 착수 0) · [하네스 설치 완료 · 지원 모드] 통지 | 닫힘 (판정 2297a) |

완성 조건(판정 2274): r386 main 착지 sha `70c8e7c203` + ai-feature-pack fable-team 병합 sha `c545a5d4c2`·`4770e0b4` + 라이브 install-check OK + 팀 ft-teamset-check(OK 9 · ERR 4 = arch 좌석 없음).

## 배포 상태

- 하네스 정본 = 이 레포 `feature-pack/fable-team/harness/` · main `4770e0b4`
- 라이브 설치 = `~/.claude/fable-team/live/1.1.3/bin` (원본 = 팩 워크트리 `.worktrees/harness-live` · 가지 `harness/live` · 갱신은 ff 만 → `install.sh --apply`)
- BYZ-Agents 쪽 하네스 사본 삭제 = main `70c8e7c203`

## 나중에 볼 것

**다른 트랙 랜딩 때**
- 팀 재개 첫 착지마다 head-lag WARN 0 + 그 팀 cwd `ft-teamset-check` OK 확인 (지원 루프)
- teamset ERR 4팀(concierge·feature·graphics·room) = 재개 때 arch 좌석 먼저

**완성 후**
- 설치본 결함 2 (r385 r4 · 1.1.4): `ft_board_env.ft_root` 가 git 밖 설치본에서 실패(나노 닫기 사건 원장) · `ft_live_install_check` 가 `--repo BYZ` 에서 하네스 루트 밖 ERROR(카드 이동)
- 전체 지도 PENDING 5: zombie-clean R364 판 미설치 · launchd 3(ft-head-lag·ft-idle-wake·iap-tunnel) 미적재
- 개선 큐 R393~R399 (착수 0)

## 다시 여는 법

1. 이 파일과 BYZ-Agents `design/harness/GOAL-harness.md` 끝선 표를 읽는다.
2. 이 레포 최신 main 에서 새 가지 → 수정 → PR → 병합.
3. `harness/live` ff → `install.sh --apply` → 루트 shim `ft-goal-table.sh` rc0 + `ft-live-install-check` OK 를 실제로 1회 돌려 본다.
4. 되돌림 1줄: `printf '%s\n' '<옛 bin 경로>' > <BYZ 루트>/.fable-team/LIVE_BIN`
