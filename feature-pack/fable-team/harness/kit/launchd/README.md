# kit/launchd — launchd 잡 템플릿 (프로세스 정책 표)

`process type` 은 plist 한 키다. 키가 없으면 launchd 가 spawn type 을 `daemon`(배경)으로 잡고, 부하가 큰 구간에 그 잡을 늦춘다.
7초 상한으로 판정하는 잡이 늦춰지면 «판정 불가» rc≠0 이 나고, 그 로그가 «잡이 죽었다»로 읽힌다.
같은 원인을 잡마다 한 장씩 고쳐 온 것이 네 번째(r683 board-publish · r1282 stall-scan · r1340 resource-watch · r1377 이 카드)라서 표 하나로 정한다.

## 표 (정본 = r1377-ft-launchd-processtype-table 카드 · design/harness/indices/)

| Label | 값 |
|---|---|
| com.byz.ft-board-publish | Interactive |
| com.byz.ft-stall-scan(·-aifp·-kakao) | Interactive |
| com.byz.ft-planner-decisions | Interactive |
| com.byz.ft-idle-wake | Interactive |
| com.byz.ft-news-planner | Interactive |
| com.byz.ft-news-desk | Interactive |
| com.byz.ft-news-brief | Interactive |
| com.byz.ft-resource-watch | Interactive |
| com.byz.ft-tick(·-cfo·-feature·-kakao·-knowledge·-ops) | Interactive |
| com.byz.ft-magazine-model · com.byz.ft-magazine | Interactive |
| com.byz.ft-leak-reap | Background |
| com.byz.ft-secret-scan | Background |
| com.byz.ft-wt-sweep | Background |
| com.byz.ft-weekly-review | Background |
| com.byz.ft-postboot-measure | Background |

## 규칙

- 판정 잡: 외부 호출 상한(7초 꼴)을 넘으면 그 회차 결과를 버리거나 rc≠0 을 내는 잡 + 주기 ≤ 30분, 또는 시각이 고정된 발행 잡 = `Interactive`.
- 큰 디스크·리포를 훑는 정리·측정 잡 = `Background` 를 «명시» 한다(키 없음과 다르다).
- `Adaptive` 는 XPC 전용이라 쓰지 않는다.
- 새 잡을 만들 때: 템플릿에 `<key>ProcessType</key><string>값</string>` 한 줄을 넣고 이 표에 한 행을 더한다.

## 점검

`ft-launchd-check.sh` 가 `~/Library/LaunchAgents` 의 잡 plist 를 훑어 키가 빠진 것을 한 줄로 보인다.

```
WARN 예약 <Label> ProcessType 없음 — 부하 때 배경 감속(r1377 표)
판정 불가 <경로> plutil rc=<n>        # plist 자체를 못 읽음(키 «없음» 으로 세지 않는다)
```

값이 표와 같은지는 `ft-launchd-check.sh` 가 보지 않는다(템플릿 렌더 시험 `tests/test_launchd_processtype_r1377.sh` 가 본다).
