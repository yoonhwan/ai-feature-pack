# Issue 816 코멘트 문안 (arch#7 · 2026-10-07 · master#10 #60035 요청)

> 아래 «---» 사이를 그대로 코멘트로 붙인다. 위·아래 메모는 붙이지 않는다.

---
## 실측 갱신 (2026-10-07 · byz-harness-arch-claude#7) — 방향이 바뀌었다

10-04 본문·정정 코멘트는 «라이브가 대체로 더 최신»이었다. **오늘은 반대다 — 다른 5개는 모두 키트 쪽 커밋이 라이브 파일보다 새롭다.**

비교 대상: 키트 `scripts/harness-install/fable-team/bin`(origin/main d84e49ed93) ↔ 라이브 `.worktrees/v6-realtime-live/.fable-team/bin`(gitignored 사본 · 팀들이 실제 실행하는 FT_BIN).

| 구분 | 수 | 내용 |
|---|---|---|
| 같음 | 33 | 라이브 38개 중 |
| 다름 | 5 | 아래 표 |
| 키트에만 있음 | 35 | 라이브에 없음 — ft-harness-info · ft-name-lint · ft-land · ft-hil-ask/answer · ft-issue-* 4 · ft-gh-as-tank · ft-tank-verify · ft-press-permit · ft-seat-live · ft-tmux-* 5 · ft-lib · ft-mbox.sh/.py · mbox-v2 외 |
| 라이브에만 있음 | 0 | |

다른 5개:
| 파일 | 키트 줄 / 마지막 커밋 | 라이브 줄 / 파일 시각 | 라이브에만 있는 줄 |
|---|---|---|---|
| ft-nano-close.sh | 498 / 10-07 19:21 | 383 / 10-03 14:10 | 18 |
| ft-nano-spawn.sh | 214 / 10-07 14:04 | 186 / 10-03 01:40 | 9 |
| ft-nano-slots.sh | 98 / 10-07 13:32 | 83 / 10-02 23:49 | 12 |
| ft-nano-evidence-check.sh | 48 / 10-07 14:04 | 40 / 10-02 23:51 | 6 |
| ft-role-spawn.sh | 103 / 10-07 19:21 | 100 / 10-07 17:46 | 위치 이동 + 1줄 |

- 「라이브에만 있는 줄」은 diff 의 `>` 줄 수다. 키트가 고친 줄의 옛 모양일 수 있어서, 라이브가 키트의 부분집합이라고 단정하지 않는다. → 설계서 ⓪ 「파일별 방향 판정표」가 여전히 첫 단계다.
- 실제 영향 1건(확인됨): 라이브 `ft-role-spawn.sh` 에는 R13 줄(master·arch 후계 첫 발주에 「CronCreate 10분 체크 틱」 지시)이 없다. 라이브 FT_BIN 으로 후계를 열면 BOOT 16 크론 지시가 빠진다.
- 실제 영향 후보: 라이브 `ft-nano-close.sh` 에는 팀 env 자동 로드(R14·R18)와 `FT_NANO_WT_PREFIX` 가 없다. 그래서 FT_BIN 경로로 닫는 팀은 지금도 env 를 손으로 넣어야 한다.
- ft-press-gate.sh 는 오늘 «같음»에 들어가 있다. 키트와 라이브가 둘 다 옛판(1fe22000)이라서다. 추적본 새 판(57a36d6a · #834 ⑥)은 PR 869 랜딩 뒤 키트·라이브에 함께 들어간다.

FT_BIN 소비자(오늘 실측): 팀 env 6장(harness·feature·cfo·issues·kk·planner) + launchd `com.byz.ft-tick` · `com.byz.ft-tick-cfo` plist(ft-tick.sh — 키트와 같음).

제안: 트리아지를 재개한다. 순서는 설계서 그대로 ⓪ 방향 판정표 → ① 설치 스크립트 → ② 드리프트 검사 → … 로 하고, 착수는 PR 869 랜딩 뒤. 하네스 골 «완성 전»(원문 1 배포·반영).
---

## 메모 (붙이지 않음)
- 실측 명령: `git archive origin/main scripts/harness-install/fable-team/bin` → 라이브 디렉터리와 파일별 cmp. `.bak*`·`__pycache__` 제외.
- 문안 속 번호는 PR 869·#834 두 개. 오빠께 보고할 때는 각주 표에 넣는다(지침 10-07).
