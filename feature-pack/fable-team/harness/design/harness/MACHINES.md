# MACHINES — 머신 배분표 (하네스 키트가 어느 머신에 어느 버전으로 깔렸나)

골 축: 표 C(업그레이드·배포·머신별 반영) · 원문 5(메인 하네스를 머신들에 독립 배분). 정본 설계: `design/harness/issue-improvement/DESIGN-harness-composition-20261005.md` §3-4.
키트: `scripts/harness-install/fable-team/` · 설치: `install.sh --machine <이름> [--apply]` · 반영 기록은 `RELEASE-<ver>.md` 의 머신별 「반영됨 <machine> <sha>」 행.
값을 모르는 칸은 «미확인» 으로 둔다 — 추측해 채우지 않는다.

| 머신 | 접속 | 역할 | 키트 반영 | 반영 sha | 확인 방법 |
|---|---|---|---|---|---|
| 이 Mac (`MacBook-Pro`) | 로컬 | 메인 하네스 · 모든 팀 세션 | 미확인 (라이브 bin 은 v6-realtime-live 워크트리 gitignored 사본) | 미확인 | `install.sh` 부팅 보고의 `kit_sha` 와 라이브 bin 대조 |
| jarvis | 미확인 | 미확인 (RELEASE-0.1 에 「미반영 · 머신 키트 뒤」 행) | 미반영 | — | 사람 승인 뒤 `install.sh --apply` · 이 카드 범위 밖 |
| byzs-mac-mini | tailscale | 미확인 (오빠 확인 대기) | 미확인 | — | 오빠가 역할을 알려준 뒤 행 갱신 |

## 규칙
- 행을 «반영됨» 으로 바꾸는 증거 = 그 머신에서 돌린 `install.sh` 부팅 보고의 `machine=` · `kit_sha=` 한 줄.
- 원격 머신 접속·설치는 사람 승인 뒤에만 한다.
