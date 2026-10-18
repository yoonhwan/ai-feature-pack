# 전 팀 공지 문구 — 병합 방식 변경 (R230 · 판정 1875)

> 병합(#1656 등) 뒤 master 가 각 팀 master 에 1통 보내고 슬랙에 게시한다. 문안은 인덱스 `r230-head-sync-and-merge-gate.md` «전 팀 공지 문안» 그대로.

```
[하네스 공지 · 병합 방식 변경 · 판정 1875]
이제 main 병합은 GitHub 병합 버튼(gh pr merge)이 아니라 도구로만 합니다: ft-merge-land.sh <PR 번호>.
이유: 검사한 내용과 실제로 main 에 들어간 내용이 달라지는 틈(병합 순간 main 이 움직이면 생김)을 git 서버가 막게 하려고.
할 일: ①PR 만들기·리뷰·CI 는 그대로 ②병합 승인 값을 받은 뒤 master 가 ft-merge-land.sh 실행 ③도구가 «main 포함 안 됨» 으로 거절하면 ft-head-sync.sh 로 브랜치를 최신화한 뒤 다시.
gh pr merge 는 훅이 막습니다. 막혔을 때 우회하지 말고 harness master 에 알려 주세요.
```

실행 형태: `ft-merge-land.sh <PR 번호> --approve-sha <PR head 40hex>` (승인 sha 없으면 실행 0 · 자율 ON 이면 `approve-merge` 승인 파일도 필요).
