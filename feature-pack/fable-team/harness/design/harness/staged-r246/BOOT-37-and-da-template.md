# R246 상시 로드 줄 초안 (master 가 설치 — 이 파일은 초안, 설치는 `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 에 master 손)

> 골 좌표: 하네스 GOAL 표 A 모니터 + 설치 · 원장 R246 (오빠 «디스크가 미친듯 계속 부족한데? 머신 점검이랑 어디가 누적되는지»).
> 강제 장치(린트·등록 도구·경보)는 이 브랜치에 있다: `ft-tmp-trap-lint.sh` · `ft-scratch-repo.sh` · `ft-disk-alarm.sh`.

## BOOT 새 조항 37 (원문 초안 — 한 줄)

37. **임시 사본은 만들면 지운다**(2026-10-15 오빠 «디스크가 미친듯 계속 부족한데?» · 원장 R246): 셸에서 `mktemp -d` 를 쓰면 같은 파일에 `trap 'rm -rf "$변수"' EXIT` 를 둔다(`ft-tmp-trap-lint.sh <파일>` 이 없으면 REJECT) · 저장소를 통째로 복사하지 않는다 — 사본이 필요하면 `ft-scratch-repo.sh <sha>` 로 만들고 끝나면 `ft-scratch-repo.sh --done <경로>` · 파일 한두 개만 볼 땐 `git show <sha>:<경로>` · 주인 없는 사본은 `ft-scratch-repo.sh --report`(삭제 0)로 센다. 디스크 여유 <50Gi 경고·<30Gi 긴급 쪽지는 planner 로 간다(`ft-disk-alarm.sh`).

## 검토(DA) 발주 템플릿에 넣을 한 줄

- 임시 저장소 사본이 필요하면 `ft-scratch-repo.sh <sha>` 로 만들고 끝나면 `--done` 으로 지운다 — 통째 복사·`mktemp -d` 뒤 정리 누락 금지(BOOT 37).

## 설치 메모 (master)

- 병합 뒤 FT_BIN `ft-live-install.sh` + drift-check OK(키트 `scripts/harness-install/fable-team/bin/` 사본 3개 포함).
- 주인 없는 사본 24시간 뒤 자동 삭제 = 오빠 승인(판정 1920): `ft-scratch-repo.sh --sweep` 이 하루 1회(`ft-disk-alarm` 이 호출) — ★첫 1회는 목록 보고만(실삭제 0, 표식 `scratch-sweep.armed`)★, 그 뒤부터 자동 삭제. 대상은 되살릴 수 있는 사본만(등록 사본 중 주인 세션 없는 것 · 내 소유 `tmp.*` 24h 지난 것 · 어떤 프로세스의 cwd 도 아닌 것). 목록 로그 `.fable-team/state/scratch-sweep.log`. 표준승인 행(전역 CLAUDE.md 파괴 작업 절)에 «임시 사본 sweep» 추가는 master 몫.
