# RELEASE <버전> — <제목> (<날짜> · 축 C)

골 축: C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행 수신해 반영」 · 닫는 증거 = 이 1장 + 머신별 「반영됨」 행.

## 변경
| # | 변경 | Issue | sha |
|---|---|---|---|
| 1 | <무엇을 바꿨나 — 파일·동작 한 줄> | #<번호> | <sha10> |

효과: <사용자가 보는 변화 한 단락>

## 설치 명령 (머신별)
키트 변경이면 해당 머신의 리포에서:
1. `git pull origin main`
2. `bash scripts/harness-install/fable-team/install.sh --machine <머신> --apply`
3. 확인: 부팅 보고의 `machine=<머신>` · `kit_sha=<sha12>` 가 이 RELEASE 의 값과 같은가.

## 시험 (로컬 검증)
<명령과 결과 — `bash -n`, install.sh 빈 홈 1회 등>

## 머신별 반영
값을 모르면 «미확인». 「반영됨」 행은 그 머신의 부팅 보고 값이 있을 때만 쓴다.

| 머신 | 상태 | sha |
|---|---|---|
| 이 Mac | 반영됨 <machine> <sha> | <sha10> |
| jarvis | 미반영 | |
| byzs-mac-mini | 미확인 | |
