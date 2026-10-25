# r911 (h) 정리 계획 — 읽기 전용 · 실행은 planner/오빠 (나노 워크트리 밖 폴더 해제 = HIL)

> 근거: 판정 2354(끝난 브랜치 보관 이동 표준승인) · 판정 2745(main 과 파일 단위 내용이 같으면 끝) · r444(판정기·보관 도구) · r895(삭제 계획 «잃는 것 없이»)
> 이 파일은 «목록» 이다. 나노는 아무것도 지우지 않았다(삭제·이동 0).

## 1. 조건 (셋 다 참일 때만 후보)

| # | 조건 | 재는 법 |
|---|---|---|
| ⓐ | 가지가 FINISHED(E0 ∧ E3 ∧ (E1·E2 ∨ **E1f**)) | `bash feature-pack/fable-team/harness/bin/ft-finished-check.sh <가지> --repo <리포>` 첫 줄 |
| ⓑ | 그 가지의 폴더가 미커밋 0 | 같은 출력의 `E0 ok` (폴더 없으면 «폴더 없음» = 참) |
| ⓒ | 좌석 0 · 폴더를 cwd 로 쓰는 프로세스 0 | 같은 출력의 `E3 ok` |

★폴더 해제(삭제)는 이 도구들 몫이 «아니다»★ — `ft-branch-archive.sh` 는 refs/heads → refs/archive 만 옮기고 폴더는 안 건드린다. 폴더 정리는 `ft-wt-sweep.sh`(계획 = `ft-nano-close.sh` 생성물)이고, **나노 워크트리 밖 폴더 해제는 HIL**(메모 «non-nano worktree removal = HIL»).

## 2. 목록 (표본 12 · 2026-10-25 15:2x · 반송 r3 판정기)

| 가지 | E1f | 폴더 | 판정 | 폴더 해제 후보? |
|---|---|---|---|---|
| `nano/m5-solo-release-await-psid-recheck` | ok files=1 | **없음** | FINISHED | ✗ — 폴더 없음(가지만 다음 sweep 이 보관 이동) |
| `nano/c-brain-k12-wire-plan-json` | ok files=9 | **없음** | FINISHED | ✗ — 같음 |
| `nano/m5-solo-hook-unmount-reset-press-release-r2` | ok files=23 | **없음** | FINISHED | ✗ — 같음 · 표 직후 이미 `refs/archive` 로 이동됨 |
| `nano/ccu-redis-commandstats-capture` | ok files=7 | **없음** | FINISHED | ✗ — 같음 |
| `nano/g2309-stt-selector-no-external-names` | ok files=8 | 있음(clean) | ACTIVE(E3 no — 좌석 살아 있음) | ✗ — 좌석이 닫힌 뒤 다시 잰다 |
| (그 밖 7개) | no/none | — | ACTIVE·ORPHAN | ✗ |

⇒ **지금 실행할 폴더 해제 후보 0건** — 새로 «끝남» 이 된 4건은 **폴더가 이미 없다**. 즉 이 카드가 새로 만드는 것은 «브랜치 목록 정리» 이고(도구 자동 · 삭제 0), 폴더 삭제 목록은 늘지 않는다.

## 3. 전수로 넓히는 명령 (planner/오빠 · 읽기 전용이라 안전)

```
R=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents
for b in $(git -C "$R" for-each-ref --format='%(refname:short)' 'refs/heads/nano/'); do
  bash feature-pack/fable-team/harness/bin/ft-finished-check.sh "$b" --repo "$R" | head -1
done | grep '^FINISHED' | sort > /tmp/r911-finished.txt
```
- `FINISHED` 줄이 나온 가지는 다음 sweep 이 `refs/archive` 로 옮긴다(도구 자동 · 삭제 0).
- 폴더까지 지우는 것은 `ft-wt-sweep --launchd`(계획 실행)이고, 나노 워크트리 밖이면 HIL 로 올린다.

## 4. 되돌림

- 가지: `git branch <이름> refs/archive/<이름>` (커밋은 보관 ref 가 쥔다)
- 폴더: `git worktree add <경로> <가지>`
