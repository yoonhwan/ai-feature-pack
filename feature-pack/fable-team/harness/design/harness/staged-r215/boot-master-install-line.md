# staged-r215 — master 라이브 설치 한 줄 (상시 로드 줄 초안 · 원장 R215 처리 칸)

> 반영 위치(승격은 master·오빠 몫): `~/.claude/skills/fable-team/references/main-team-governance.md` §6 «master 손 = 검증된 파일의 설치 복사» 아래 한 줄 + COMM-GUIDE-BOOT 15번 끝.

## 상시 로드 줄 초안 (governance §6 · BOOT 15)

★master 라이브 설치 = `bash <루트>/.worktrees/harness-ops/scripts/fable-team-bin/ft-live-install.sh --bin <루트>/.worktrees/v6-realtime-live/.fable-team/bin --repo <루트> --ref <병합 sha> [--dry-run]` 한 줄★ — cp/mv 손 설치 0 · 오빠 `! bash /tmp/h<N>` 0. `--ref` 는 origin/main 의 조상(병합된 sha)만 받는다. 끝줄이 `OK 이미 일치` 또는 `INSTALLED n=… bak=…` 이면 끝(rc 0) · `ERROR`/`DRIFT` 면 그 줄 그대로 상위에 보고. 게이트(orchestration-gate)는 풀지 않는다 — 추적된 도구를 `bash` 로 부르면 통과한다.

- 첫 설치(라이브 bin 에 도구가 아직 없을 때)는 리포 경로로 돌린다 — 키트 사본이 라이브에 들어가면 다음부터 `<라이브 bin>/ft-live-install.sh` 로도 돈다.
- 백업 = `<라이브 bin>/../state/live-install/bak-<ref12>-<시각>.tar` (되돌림: `tar -xf <bak> -C <라이브 bin>`) · MISSING 으로 새로 생긴 파일은 직접 지운다.
- EXTRA(키트에 없는 라이브 파일)는 지우지 않고 `KEEP-EXTRA <이름>` 줄만 낸다.
- 새 권한 0: governance §6 에 이미 있는 «검증된 파일의 설치 복사» 를 도구 1개로 묶은 것이다.

## 원장 R215 행 처리 칸 (REQUEST-LEDGER.md R215 행의 마지막 두 칸에 붙일 문장)

처리: 구현 10-15 — `ft-live-install.sh`(키트 + 리포 `scripts/fable-team-bin/`) · 시험 `tests/harness/test_live_install.sh` · 게이트 무변경(기각: «게이트가 cp 를 통과» — 훅은 셸 변수를 못 펼침) · 병합 sha 와 첫 라이브 설치 OK 줄은 병합 뒤 master 가 채운다.
