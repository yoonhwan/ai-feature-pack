# r874 단계 1 — ft-tick 6데몬 실측 표 (읽기 전용 · kill·launchctl 변경 0)

- 측정: 2026-10-25 01:20~01:28 KST · 좌석 byz-harness-nano-r874-ft-tick-six-daemons-load#0 · 실행본 LIVE 1.1.230
- 도구: `launchctl list` · `plutil` · `log show`(launchd) · `/tmp/ft-tick*.log` · ps 표본 2초×90회(191초) · load 31/42/42

## 결론 3줄

1. **-9 는 부하·메모리·틱 내부 시간 초과가 아니다** — 설치 뒤 `launchctl kickstart -k` 재기동이 SIGTERM 을 보내고, **5초 안에 안 끝나면 launchd 가 SIGKILL**. 근거 줄 원문은 ①.
2. 5초를 넘긴 이유 = bash 는 **앞단 자식이 도는 동안 TERM trap 을 미룬다**. 메인 데몬은 한 바퀴 내내 `ft-wt-sweep.sh` 에 묶여(표본 90 중 쉼 0) 늘 «자식 실행 중» 이라 늘 -9.
3. 6데몬 겹침은 실재하지만 작다(트리 CPU 합 약 5% · 1코어 기준). 겹치는 곳 = `live_snapshot` 전 명부 훑기 ×5 · `leak_watch` ps 스냅샷 ×5. **load 31~62 의 주원인은 ft-tick 이 아니다.**

## ① -9 원인

| 항목 | 값 |
|---|---|
| 종료 신호 | SIGKILL · 보낸 쪽 launchd[1] |
| 근거 줄 원문 | `01:06:34.635 [gui/501/com.byz.ft-tick-ops [35261]:] Service did not exit 5 seconds after SIGTERM. Sending SIGKILL.` · `01:06:34.637 … exited due to SIGKILL \| sent by launchd[1], ran for 1196668ms` |
| | `01:06:39.650 [gui/501/com.byz.ft-tick [40154]:] Service did not exit 5 seconds after SIGTERM. Sending SIGKILL.` · `… exited due to SIGKILL \| sent by launchd[1], ran for 1196673ms` |
| SIGTERM 보낸 쪽 | 01:06:24 cfo → :26 feature → :29 knowledge → :34 ops → :39 메인 = plist 파일 이름 정렬 순. `ft_live_install_check.py:202 restart_scan` 이 같은 정렬로 `RESTART <label> — launchctl kickstart -k …` 줄을 만들고 master 가 설치 뒤 그 줄을 실행 · kakao 는 KakaoBot 사본이라 대상 밖(로그상 재시작 0) |
| 같은 꼴 반복 | 00:46:29~45 에도 같은 순서 · 그때 feature·knowledge·메인 간격 5초(-9) · ops 0.7초(정상) |
| 정상 종료한 데몬 | `/tmp/ft-tick-{cfo,feature,knowledge}.log` 에 `ft-tick stopped` 줄 있음(trap 이 돈 것) · ops·메인은 그 줄 없음 |
| 틱 안 시간 초과 장치 | 없음 — ft-tick.sh 머리 주석 «워치독을 갖지 않는다» · 루프 = `pass; sleep 60` |
| 메모리(RSS) | 데몬 트리 최대 24~58 MB · jetsam·메모리 로그 줄 0 → 원인 아님 |
| plist | 6개 모두 KeepAlive true · ThrottleInterval 5 · ExitTimeOut 키 없음 |

## ② 한 바퀴가 하는 일 · 소요 · 겹침

| 데몬 | 명부 | 쉼(sleep만) 표본 | 한 바퀴 소요(표본) | 트리 CPU 평균 | 트리 RSS 최대 | 주로 도는 자식 |
|---|---|---|---|---|---|---|
| com.byz.ft-tick(메인) | seats.json | **0 / 90** | **2.4~9.5분** (wt-sweep 로그 00:58:41·01:01:07·01:10:37·01:16:44·01:25:54 간격) | 1.7% | 24 MB | `ft-wt-sweep.sh` 84/90 표본 (WT_SWEEP 켜진 데몬은 메인 하나) |
| ft-tick-ops | seats-ops.json | 60 / 90 | 4·26·34초 | 0.8% | 44 MB | ft-seat-status.sh · mbox send · ft-autonomy.sh |
| ft-tick-cfo | seats-cfo.json | 55 / 90 | 17·58초 | 0.8% | 47 MB | ft-seat-status.sh 94 · ft_seat_jsonl_index.py |
| ft-tick-feature | seats-feature.json | 69 / 90 | 12·15·17초 | 1.0% | 58 MB | ft-seat-status.sh |
| ft-tick-knowledge | seats-knowledge.json | 66 / 90 | 6·21·24초 | 1.0% | 39 MB | ft-seat-status.sh · mbox send |
| ft-tick-kakao | KakaoBot seats.json | 90 / 90 | 0 | 0.0% | 6 MB | 없음(KakaoBot 사본) |

- 간격: 루프 60초(바퀴 끝 → sleep 60) · 데몬마다 독립 시작이라 엇갈림 장치 없음.
- 좌석 범위 필터: 좌석 단위 훑기(stall·idle_watch·idle_long·dead_seat·fire)는 **자기 명부만** 본다 → 같은 좌석을 겹쳐 훑지 않는다.
- **겹치는 곳 2개**
  - `live_snapshot` (ft-tick.sh:602) — 300초마다 «같은 폴더의 모든 명부»(13개 · claude 행 89)를 훑는다. 주석은 «틱 여러 개가 같은 상태 폴더를 쓰면 하나만 돈다» 인데 **plist 5개가 FT_TICK_STATE_DIR 를 팀별로 줘서 stamp 가 5벌** → 같은 89행 스냅샷을 5데몬이 각각(실측 stamp: 메인 01:19:37 · ops 01:22:45 · cfo 01:26:05).
  - `leak_watch` → `ft-leak-watch.sh` 가 데몬마다 ps 전체 스냅샷 1회/바퀴 ×5.
- tmux: `pane_of` 가 좌석마다 `tmux list-panes -a` 1회(실측 5회 18 ms — 비용 작음) · capture-pane 은 fire·stall 의 대상 좌석만.
- git: 틱 본체는 기동 1회(rev-parse)뿐 · git 부하는 메인의 `ft-wt-sweep.sh` 안(`shell_scan` 600초마다 워크트리 398개 × `git ls-tree` · 계획 1건 상한 120초 · 바퀴 상한 90초는 «다음 계획 시작 전» 에만 검사).

## ③ 고침안 비교 (async_io_and_connections 비교표 규칙 — 부하·메모리 열)

| 안 | 무엇 | -9 없어지나 | 부하 | 메모리 | 위험 |
|---|---|---|---|---|---|
| ⓐ 엇갈림 | 데몬별 시작 지연 + 잠금 1개로 동시 전체 스캔 0 | **아니오** — kickstart 는 데몬마다 SIGTERM 을 보내고, 메인은 wt-sweep 중이면 여전히 5초 초과 | 겹침 시점만 분산 · 총량 같음(live_snapshot ×5 그대로) | 같음(데몬 6) | 잠금 교착 · 잠금 대기 중 TERM 도 미뤄짐 |
| ⓑ 1데몬 묶기 | 팀 명부 목록을 한 루프가 순회 | **아니오(단독으로는)** — 한 바퀴가 팀 수만큼 길어져 TERM 미룸이 더 길어짐 | live_snapshot·leak_watch 중복 ×5 → ×1 | 데몬 트리 5개분(약 150~200 MB) 감소 | 한 팀 실패가 전체 정지 · plist 5개 정리 = master 설치 |
| ⓒ (실측으로 추가) TERM 즉시 응답 | 바퀴 본체를 배경 자식으로 돌리고 `wait`(trap 이 끼어들 수 있는 대기) · trap 이 자식 프로세스 묶음을 끊고 바로 종료 · `sleep` 도 `sleep & wait` · 바퀴 상한(하드 룰 12 · 70초 천장) 넘으면 ERROR 1줄 | **예** — trap 이 5초 안에 돈다 | 같음 | 같음 | 끊긴 자식(wt-sweep 계획 중간)이 다음 바퀴에 이어서 도는지 확인 필요(계획은 «재실행 안전» 주석 · run.lock 은 pid 죽음 판정으로 걷힘) |

- 추천(나노 의견 · 확정은 arch): **ⓒ + ⓑ 의 중복 2곳만 걷기(live_snapshot stamp 를 공용 폴더로)** — -9 를 없애는 것은 ⓒ 뿐이고, 묶기·엇갈림은 -9 와 무관한 소량 부하 문제.
- 범위 밖(arch 판단용 메모): 메인 바퀴가 분 단위인 것 자체는 `ft-wt-sweep.sh`(shell_scan 398×git · 계획 120초) 몫 — 카드 §범위 밖 «틱이 하는 일 자체» 에 걸리는지 arch 판정 필요.

## 기준값 (단계 2 비교용)

- 종료 코드: 메인 -9 · ops -9 · 나머지 0 (01:2x `launchctl list`)
- ft-tick.sh 프로세스: 루트 6(kakao 포함) + 바퀴 중 자식
- load: 01:22 31/42/42 (카드 기준 62)
