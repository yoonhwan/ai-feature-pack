# BOOT 16 planner 승계 한정 문장 초안 (R209 · 판정 1795) — 홈 설치는 master

`~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 16 «체크 크론» 항목의 «★planner 승계 좌석 한정(R125 …)★» 문장 바로 뒤에 아래를 붙인다.

> ★planner 승계 좌석 한정(R209 · 판정 1795)★: 부팅 보고에 `news=<마지막 게시 HH:MM>` 칸을 넣는다(`.fable-team/state/news-publish/<오늘>/published.txt` 수정 시각 · 오늘 없으면 어제). 지금 시각과 3시간 넘게 벌어졌으면 그 턴에 원인 1줄(원장 커밋 0 / 게시 실패 rc / 스냅샷 오래됨 — `/tmp/byz-ft-news-planner.log` 마지막 줄)을 같이 적는다. 받는 master 는 `news=` 칸이 비면 그 턴에 되묻는다.

근거: 뉴스 방아쇠가 planner 세션 크론에 묶여 승계마다 끊겼다(10-13 15:00 뒤). 방아쇠는 이제 launchd `com.byz.ft-news-planner` 이고, 이 칸은 «끊김을 승계 첫 턴에 사람이 보게» 하는 안전망이다.
