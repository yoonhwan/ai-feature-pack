# aifp 팀 폴더 (design/aifp · r1311 · 판정 3294 Q3 ①)

- 카드 폴더 = `design/aifp/indices/{대기,진행,완성}` — 상태 = 폴더(대기 → 진행 → 완성).
- 정본 명단 = `design/TEAMS.md` 이 리포 1행(aifp). 좌석 명부 = `.fable-team/seats-aifp.json`(gitignore 영역 · 추적 0).
- 왜 이 자리인가: BYZ 처럼 카드 폴더를 «추적 영역» 에 두어야 배정 감시(`ft-card-assign-watch`)가 git ref 로 카드를 셀 수 있다(Q3 ② = gitignore 영역은 ref 로 못 읽음).
- 설치(기계 쪽: roots.tsv 행 · stalls-scan plist · bin shim · 우편 다리)는 BYZ 하네스의 `design/harness/h-r1311-aifp-root/h-r1311-aifp-root-install.sh` 가 한다(드라이런 기본 · `FT_H_LIVE=1` 이 라이브 · `--revert` 되돌림).
