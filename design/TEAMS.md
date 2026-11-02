# 팀 명단 — aifp(이 리포 = ai-feature-pack) 루트의 팀 표 (r1311 · 판정 3184 ② · 3294 Q3 ①)

aifp 는 BYZ 밖 리포라 BYZ 의 `design/TEAMS.md` 에 넣지 않는다(«aifp, kakao 따로이나 시스템은 일반화 랜딩» · 판정 3184 ②). 이 표가 aifp 루트의 명단이고, 도구(`ft_team_lib` · `ft-team-attach` · `mbox` 다리)는 이 표를 읽는다.

| 팀 | 폴더 | 오케 좌석 계열 | 명부 | 상태 |
|---|---|---|---|---|
| aifp | `design/aifp/` | aifp-pi-master-pi | seats-aifp.json | 현역 |

- 좌석 명부 = `.fable-team/seats-aifp.json`(gitignore 영역 · 「명부」 칸이 그 파일 이름을 가리킨다 — r1309 «명부» 열)
- 카드 폴더 = `design/aifp/indices/{대기,진행,완성}`(seats-aifp.json `_cards` · 추적 영역)
- 기계 루트 명부(`~/.claude/fable-team/roots.tsv`)의 aifp 행 · 멈춤 경보 plist(`com.byz.ft-stall-scan-aifp`)는 설치 h(`h-r1311-aifp-root-install.sh`)가 세운다.
