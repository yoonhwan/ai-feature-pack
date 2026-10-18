# R247 상시 로드 줄 초안 — 승인 뒤 main 병합만 했으면 재승인 0 (홈 설치는 master · 이 파일은 초안뿐)

> 근거: 판정 1917(오빠 승인 규칙 «승인 sha + main merge 만 → 동일승인») · 원장 R247 · v65 #95458 재결속 반복.
> 강제 장치(이 단위가 만든 것): `ft-approval-equiv.sh`(+`ft_approval_equiv.py`) · `ft-merge-land.sh` 가 head != 승인 sha 일 때 게이트 뒤 호출 · 키트 사본 `scripts/harness-install/fable-team/bin/`.

## ⓐ main-team-governance.md — 병합 승인 절(§7) 끝에 1줄

```
- **승인 세트 A 뒤 main 병합만 했으면 재승인 요청 0 (R247 · 판정 1917)**: `ft-merge-land.sh <PR> --approve-sha <A>` 는 PR head 가 A 와 달라도 «A 가 조상 · A..head 는 main 병합 커밋뿐 · main 대비 자기 변경이 A 때와 같음 · head 트리 == A+main 깨끗한 병합» 이면 착지 출력에 `EQUIV approve=<A> head=<S>` 를 찍고 같은 승인으로 진행한다. 그 밖(일반 커밋 1개라도 · 충돌 해소 · 다른 브랜치 병합 · rebase)은 `NOT-EQUIV` REJECT → 새 세트 승인을 받는다. 자율 ON 의 승인 파일은 계속 A 로 찾는다.
```

## ⓑ 재승인 요청을 만들기 전 자가 점검 (팀 master·나노)

`bash <FT_BIN>/ft-approval-equiv.sh <A> <지금 head> --repo <리포>` 가 `EQUIV` 면 오빠께 재승인을 묻지 않는다(착지 도구가 같은 대조를 한다). 이 도구는 main 을 fetch 하지 않으므로 먼저 `git fetch origin main`.
