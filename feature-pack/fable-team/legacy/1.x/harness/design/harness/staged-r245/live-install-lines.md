# R245 상시 로드 줄 초안 — 병합 ≠ 끝 (홈 설치는 master · 이 파일은 초안뿐)

> 근거: 오빠 원문 «증류됐는데 이전방보는거자나 능동형 대응 안되자나» · «하네스팀 질책하라고» (2026-10-15) · 원장 R245.
> 강제 장치(이 단위가 만든 것): `ft-live-install-check.sh`(키트→라이브 대조) · `ft-merge-land.sh` 착지 `INSTALL` 줄 · `ft-index-move-install.sh`(카드 완성 이동 거절) · `ft-index-lint.sh`(`- 설치:` 줄 필수) · `ft-install-pending.sh`(뉴스 1줄).

## ⓐ COMM-GUIDE-BOOT.md — 새 조항 (번호 36 — 카드 지정 · 35 가 비어 있으면 master 가 맞춤)

```
36. **병합 ≠ 끝 — 하네스 키트 병합 단위는 라이브 설치까지가 완료다**(2026-10-15 오빠 «증류됐는데 이전방보는거자나 능동형 대응 안되자나» · R245): `scripts/harness-install/` 를 바꾼 병합은 `bash <루트>/scripts/fable-team-bin/ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` 가 `OK` 이고 카드 `- 실사건: <무엇> · <증거 mbox #N | 경로:줄 | ledger 키>` 줄이 있어야 닫힌다. 착지 출력에 `INSTALL PENDING`·`INSTALL ERROR`·`INSTALL-PENDING` 이 보이면 그 턴에 설치(master)하거나 [HIL]. 카드 완성 이동(`ft-index-move.sh`)이 `- 설치: 있음` 카드의 어긋남·실사건 없음을 거절한다. 하네스 카드는 머리에 `- 설치: 있음|없음` 필수(린트).
```

## ⓑ main-team-governance.md §6 (master 손 = 집행) — 끝에 1줄 추가

```
- ★병합 뒤 집행 = 설치까지★(R245 · 2026-10-15): 하네스 키트 병합은 `ft-merge-land.sh` 출력의 `INSTALL` 줄이 `OK` 일 때만 끝. `PENDING`/`ERROR` 면 같은 턴에 설치(`ft-live-install.sh` · `slack-mirror/install-*.sh` · 홈 훅 cp -p · plist 재적재)하고 `ft-live-install-check.sh --range` 로 재확인 + 실사건 1회를 카드 `- 실사건:` 에 기록한 뒤 완성 이동. 뉴스의 `설치 대기 N 병합` 줄이 0 이 될 때까지 닫지 않는다.
```

## ⓒ 하네스 카드 틀 (머리줄) — 1줄 추가

```
- 설치: 있음|없음   ← 하네스 키트(`scripts/harness-install/`)·도구(`scripts/fable-team-bin/`)·훅·데몬을 바꾸면 «있음». 있음 카드는 완성 이동 때 ①`--landed <병합 전..착지>` ②라이브 대조 OK ③`- 실사건: <무엇> · <증거>` 줄을 요구한다.
- 실사건: (설치 있음 카드만 — 병합·설치 뒤 master 기재)
```
