# r449 master 집행 순서 (나노 산출 · 팩 가지 nano/r449-evidence-log-commit-gate-and-untrac · BYZ 가지 nano/r449-evidence-log-commit-gate-and-untrac)

순서가 중요하다 — **게이트(설치)가 먼저, untrack PR 이 뒤**(재유입 0). 착지 순서 = r448 뒤(`ft-merge-land.sh` 겹침 · 자리 다름).

1. **팩 PR → main 착지** (팩 가지 2커밋: `d8a84a8111` feature · `44568b8a24` fix). manifest 1.1.17 — r448 이 먼저 1.1.17 을 쓰면 착지 때 1.1.18 로 올리고 CHANGES 머리 숫자만 고친다.
2. **설치**: `bash <하네스>/install.sh --apply --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents`(공용 루트 — `core.hooksPath` 가 `<공용 루트>/.fable-team/githooks` 절대경로).
   - 기대 출력: `GITHOOKS copied=1 same=0 dest=…/.fable-team/githooks` · 옛 pre-commit 은 `pre-commit.bak-1.1.17`.
   - 확인: `cmp <하네스>/kit/fable-team/githooks/pre-commit <공용 루트>/.fable-team/githooks/pre-commit` → 0 · `cmp <LIVE_BIN>/ft-evidence-lib.sh <하네스>/kit/fable-team/bin/ft-evidence-lib.sh` → 0.
   - 되돌림: `cp -p <공용 루트>/.fable-team/githooks/pre-commit.bak-1.1.17 <공용 루트>/.fable-team/githooks/pre-commit`.
3. **BYZ untrack PR → main** (BYZ 가지 `1d2768074c` · base 643bf03512 · 614 D + .gitignore + docs/rules/e2e_testing.md). main 이 움직였으면 착지 전 그 tip 위에서 `ft-evidence-untrack.sh --dry-run <워크트리>` 로 새로 들어온 로그가 있는지 보고 있으면 같은 가지에 1회 더(나노 재발주). PR 본문엔 `Refs`(카드 · Issue 없음).
4. **실사건 ⓑ**(PR 착지 뒤): `git ls-tree -r origin/main --name-only -- design | (. <LIVE_BIN>/ft-evidence-lib.sh; ft_evidence_filter) | wc -l` → **0**. 카드식 `grep -E '\.(log|out|nohup)$|guard|poller'` 은 md·json·py 설계 문서(이름에 guard·poller)를 세므로 0 이 아니다 — 판정식으로 센다.
5. **실사건 ⓐ**(설치 뒤 · 다음 발생 때): 어느 좌석이든 `git add -f design/…/x.log && git commit` → stderr `EVIDENCE-LOG-GATE: 증거 로그 1 staged — git rm --cached design/…/x.log · 요약은 SUMMARY-*.md` 1줄(쪽지 또는 jsonl) 을 카드 `- 실사건:` 줄에.
6. arch 손: tmuxc `COMM-GUIDE-BOOT.md` 10-a press 절에 «증거 = 요약 md 1장만 tracked · 로그 add 는 pre-commit 이 REJECT(r449)» 1줄.

## 편차 (arch 확인 요청)
- 판정식 집합 = 614개 303.2 MB(카드 955/360.8 MB). 뺀 것: 이름에 guard·poller 든 **md 203 · json 211 · py 17 · sh 5**(설계 문서·도구·intent 파일 — 카드 ⓑ 가 guard.sh 통과를 요구) · 이름 없는 `*.jsonl` 202개(results·values 측정표 — 원장이 가리킴). 넓히려면 `ft-evidence-lib.sh` 한 줄 + BYZ `.gitignore` 줄을 같이.
- BYZ `.gitignore` 의 옛 `!design/evidence/**/*.log`(2026-08-05 «verdict-binding») 재포함 줄을 뺐다 — 지금 그 경로의 tracked `.log` 는 0 이라 이번 614 에는 영향 0 이지만, 두면 앞으로 design/evidence 의 `.log` 가 `??` 로 떠 add 를 부르고 pre-commit 이 거절하는 «규칙끼리 충돌» 이 남는다.
- 기존 실패(이 단위 밖 · 별 카드): `test_live_install_check.sh` 19 FAIL · `test_live_install_check_tip.sh` 13 FAIL — base 7e8791d3 에서 같은 수(r385 재배치 뒤 픽스처가 옛 `scripts/harness-install` 경로).
