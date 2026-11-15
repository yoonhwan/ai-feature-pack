# 설계 — 행 H card_stage 의 git 이 7초를 넘어 카드가 완성/ 으로 안 간다 (aifp-ft-arch-pi#17 · 2026-11-16)

- 발주: 팀장 #18 aifp 5382(행 G · I · H 차례) · 바탕 = `orders/SWEEP-FIX-table-20261116.md` §H
- 상태: 설계 r2(팀장 #18 aifp 5410 ④ · DA#11 REJECT 1/3 반영 · 반례 전문 `.fable-team/state/team-main/aifp-ft/DA-pH-r1-reject-310176.md` · r1 sha256 a9f838c7…) · r2 에서 바뀐 곳 = §3 규칙 3 · 4 · 새 규칙 8 · 9 · hook 문단 · 시험 ㊱차~파 · 변이 M59~M61 · Q2 · DA 재판정 전 · 카드 전 · 구현 = 나노 1석 · 코드 0(이 문서는 읽기 실측만 · `git worktree add` 실측 0)
- 옮김: 2026-11-16 · aifp-ft-nano-ft2-card-stage-no-worktree#0 이 구현하며 `.fable-team/state/team-main/aifp-ft/orders/DESIGN-pH-card-stage-git-7s-20261116.md`(r2 · sha256 ee7461b0…b3c2)를 이 자리로 옮겼다(내용 손 0) · 구현 = `feature-pack/fable-team/ft2/adapters/pi/card_stage.py` · 시험 = `feature-pack/fable-team/ft2/tests/test_card_stage_no_worktree.py` · 카드 = `design/aifp/indices/진행/ft2-card-stage-no-worktree.md`
- 기준판: 팩 origin/main 92c2dac2 · `feature-pack/fable-team/ft2/adapters/pi/card_stage.py`(136줄 · 마지막 고침 6d428738 r1891)
- 시험 번호 ㊱ · 변이 M47~M50 · M59~M61

## 1. 실측과 근거 (읽기만 · 11-16 01:4x)

| 본 것 | 값 |
|---|---|
| 사건 근거 | chatbot 팀장 #58 보고 1통뿐(BYZ 309786 본문): «card_stage 2.0.62 rc3 git 시간초과 2회 · worktree add 단계 7초 상한 · BYZ 등록 worktree 445개 · 잔존 0» |
| keeper 로그 | 11-16 로그에 card_stage 실행 줄 0(낱말이 든 5줄은 카드 이름 `r1884-card-stage-…` 다). 원문 줄은 로그에 없다(팀장 5382 답) |
| 도구가 내는 글 | 시간 초과면 `판정 불가 git 시간초과` 뿐이다. 어느 git 명령인지 적지 않는다(`main` 131~132줄 · `stage` 99줄) |
| BYZ 리포 | `.git` 14G · loose object 236,711개 · pack 28개 · 등록 worktree 455줄(그중 prunable 17) |
| `git worktree list` | 0.36 · 0.23 · 0.21초(3회) |
| `git status --porcelain -uno` | 0.41 · 0.08초 |
| 임시 index 에 `git read-tree <ref>`(리포 쓰기 0 · /tmp 파일만) | origin/main(58,900 파일) 0.09 · 0.10초 · origin/ops/main-base(35,134 파일) 0.06 · 0.10초 |

- «worktree add 단계» 는 보고에 적힌 말이다. 도구 출력으로는 단계를 가를 수 없다 [확인 필요: 실제로 넘은 명령 — 아래 1번 고침이 들어가야 다음 사건에서 보인다].
- 읽기 명령은 모두 0.5초 안이다. 느린 것은 쓰기 쪽(worktree 등록 · checkout · fetch · push)으로 좁혀진다. 어느 것인지는 재지 않았다(쓰기 실측 금지).

## 2. 원인

1. `git()`(21~23줄)은 모든 git 호출에 7초를 쓴다. 한 번 실행에 git 을 14회쯤 부른다: fetch 1 · show 2 · ls-tree 2 · worktree add · sparse-checkout · checkout · mv · commit · push · rev-parse · worktree remove.
2. 그중 6회는 임시 worktree 때문에 있다(add · sparse-checkout · checkout · mv · commit · remove). worktree add 와 remove 는 리포의 worktree 등록(455개)을 읽고 쓴다. checkout 은 작업 폴더에 파일을 푼다.
3. 시간 초과가 나면 어느 명령인지 남기지 않는다. `TimeoutExpired` 를 `stage` 와 `main` 이 뭉뚱그려 받는다.
4. 실패하면 rc 3 으로 끝난다. 다시 돌리는 것은 부른 쪽 몫이다. 리포가 느린 동안은 다시 돌려도 같은 곳에서 멈춘다.

## 3. 고침

| # | 자리 | 규칙 |
|---|---|---|
| 1 | `git()` | 시간 초과면 명령 이름을 넣어 올린다: `Unsure("git <하위 명령> 시간초과 <상한>초")`. worktree 는 `worktree add` 처럼 둘째 낱말까지 적는다. 출력 = `판정 불가 git worktree add 시간초과 7초` |
| 2 | `stage()` | 임시 worktree 를 쓰지 않는다. 임시 index 파일로 커밋을 만든다(아래 순서). 작업 폴더 · worktree 등록 · checkout 0 |
| 3 | 2번의 순서 | ⓪ **시도 시작에 부모를 고정한다**: `rev-parse <ref>^{commit}` 으로 commit SHA `P` 하나를 얻는다. 아래 모든 단계는 가지 이름 대신 `P` 만 쓴다 ① 임시 폴더에 `GIT_INDEX_FILE` 을 둔다 ② `read-tree P` ③ `show P:<옛 경로>` 로 본문을 읽어 `restate` 로 고친다 ④ `hash-object -w --stdin` 으로 새 blob ⑤ `update-index --force-remove <옛 경로>` · `update-index --add --cacheinfo 100644,<blob>,<새 경로>` ⑥ `write-tree` ⑦ `commit-tree <tree> -p P -m "[docs] <카드> 2.0 완성 폴더(ft2 done)"` ⑧ 자기 검사(8번) ⑨ `push origin <커밋>:<가지>` |
| 4 | push 거절 | rebase 를 버린다. `fetch` 1회 뒤 **새 `P` 와 카드 고르기 · 카드 원문을 한 묶음으로 다시 고정한다**: `card()` 를 새 `P` 에서 다시 돌린다. 그 끝에 이미 완성/ 이면 `NOOP … 이미 완성` rc 0 으로 끝낸다. 아니면 3번 ①~⑨ 를 1회 다시 한다. 또 거절이면 지금처럼 `판정 불가 push 결과 불명` |
| 5 | 상한 | 호출마다 7초 그대로다. push 의 «7초 + 재시도 1» 도 그대로다. 늘리지 않는다 |
| 6 | 정리 | 임시 폴더만 지운다(`TemporaryDirectory`). `worktree remove` 와 «정리 실패 · 등록 잔존» 줄(109~114줄)은 없어진다 |
| 7 | 그대로 | `done_at` · `restate` · rc 뜻(0 STAGED · NOOP / 1 REJECT / 3 판정 불가) · 커밋 글 · 출력 꼴 `STAGED <카드> <frm>→완성 <sha>` · push 때 도는 pre-push hook |
| 8 | 자기 검사(push 전) | `diff-tree -r --no-renames --name-status P <커밋>` 이 정확히 2줄이어야 한다 = `D <옛 경로>` 와 `A <새 경로>`. 새 경로는 `/indices/완성/` 밑 `.md` 다. 아니면 `판정 불가 card_stage 커밋 범위 밖 <줄 수>줄` rc 3 · push 0 |
| 9 | `card()` 의 판독 기준 | `card()` 가 읽는 `show` · `ls-tree` 도 가지 이름이 아니라 시도 시작에 고정한 SHA 로 읽는다(`land.REFS` 두 가지를 각각 SHA 로 고정 · 고른 가지의 SHA 가 3번의 `P`). push 대상 가지 이름만 이름으로 남는다 |

- 3번으로 git 호출 수는 비슷하다(14회쯤 · r2 에서 `rev-parse` · `diff-tree` 가 늘었다). 수가 아니라 종류가 바뀐다: worktree 등록 쓰기 2회 · checkout 1회가 없어지고 index 한 파일 읽기 · 쓰기로 바뀐다. `read-tree` 는 실측 0.1초다.
- ④ 는 리포 object 폴더에 blob 1개를, ⑥⑦ 은 tree 와 commit 을 쓴다. push 가 실패하면 그 object 는 어느 가지에도 안 달린 채 남는다(다음 gc 가 치운다). 지금 방식도 같은 object 를 남긴다.
- 커밋 작성자 · 시각은 지금처럼 그 리포 git 설정을 따른다(`commit-tree` 도 같은 설정을 읽는다).
- 부모 고정이 필요한 까닭(r2 · DA R1): r1 은 `read-tree <ref>` 와 `commit-tree -p <ref>` 를 가지 이름으로 불렀다. 그 사이에 다른 card_stage 가 push 하고 fetch 하면 이름이 가리키는 끝이 R0 에서 R1 로 바뀐다. tree 는 R0 기준인데 부모는 R1 이 된다. push 는 fast-forward 라 성공하고 다른 카드의 이동을 되돌린다. `P` 를 한 번만 얻어 끝까지 쓰면 tree 와 부모가 같은 commit 이다. 원격 끝이 `P` 가 아니면 push 가 거절되고 4번으로 간다.
- hook(r2 · 읽기 실측): BYZ `core.hooksPath` = `.fable-team/githooks`. `commit-tree` 는 pre-commit · commit-msg 를 돌리지 않는다. pre-commit(99줄)이 하는 검사는 셋이다.

| pre-commit 검사 | 카드 이동 커밋에 걸리는가 | r2 가 지키는 법 |
|---|---|---|
| 공유 index 커밋 차단(7~33줄) | 안 걸린다. 임시 index 를 쓴다(`--only` 와 같은 꼴) | 3번 ① |
| 증거 로그 차단(35~58줄 · design/ 밑 staged `*.log`) | 8번이 지킨다. 커밋이 넣는 파일은 완성/ 밑 `.md` 1개뿐이다 | 8번 자기 검사 |
| 카드 상한(60~94줄 · 대기/ 밑 «새» 카드) | 8번이 지킨다. 넣는 경로가 완성/ 이라 대상이 아니다(hook 주석 63줄 «이동 · 완성은 검사 0») | 8번 자기 검사 |

- commit-msg 는 v65 위임이고 문서만인 `[docs]` 커밋을 면제한다(DA 판독). 커밋 글 머리 `[docs]` 는 7번으로 그대로다.
- pre-push hook 은 `git push` 가 돌리므로 지금과 같다.
- 그래서 hook 확인을 PR 한 줄로 미루지 않는다. 카드 이동이 hook 검사 범위 밖이라는 것을 8번이 실행 때마다 확인한다.
- 느린 원인이 fetch 나 push 면 2번으로는 안 고쳐진다. 그때는 1번이 그 명령을 보여 준다. 그 뒤 판단은 따로 한다(Q1).

### 고르지 않은 길

| 길 | 버린 까닭 |
|---|---|
| worktree add 만 상한 25초 | 넘은 명령이 worktree add 인지 확인되지 않았다. 느린 호출을 기다리기보다 없앤다. 훑기 표 §H 의 ⓑ |
| 실패하면 도구 안에서 다시 돌림 | 느린 리포에서 같은 곳에 또 걸린다. 하드 룰 12(7초 + 재시도 1)는 push 에만 이미 있다 |
| 끝난 worktree 455개를 이 카드에서 정리 | 운영 손이다(지우기 = HIL). 범위 밖 |
| BYZ 리포 gc(loose object 23만 개) | 운영 손이다(범위 밖 · 팀장에 1줄로 알림) |

## 4. 시험 (나노 · 지금 시험 파일에 사례 추가 또는 새 파일 `tests/test_card_stage_no_worktree.py` · 임시 bare 원격 + 임시 clone · 네트워크 0 · sleep 0)

| # | 사례 | 기대 |
|---|---|---|
| ㊱가 | 진행/ 카드 1장 · done 있음 | rc 0 `STAGED … 진행→완성 <sha>` · 원격 가지 끝 = 그 sha · 완성/ 에 카드(머리 `- 상태: 완성` · `## 상태` 끝 1줄) · 진행/ 에 없음 · 그 밖 파일 변화 0(부모 tree 와 대조) |
| ㊱나 | ㊱가 실행 앞뒤 `git worktree list` | 줄 수 같음 · 실행 중 부른 git 인자에 `worktree` 0(가짜 git 래퍼가 인자를 적음) |
| ㊱다 | 대기/ 카드(r1889 꼴) | `STAGED … 대기→완성` |
| ㊱라 | 가짜 git 이 `read-tree` 에서 상한을 넘김 | rc 3 `판정 불가 git read-tree 시간초과 7초` · 원격 변화 0 |
| ㊱마 | push 1회 거절(원격에 다른 커밋이 먼저 들어감) | fetch 1 · 새 끝에서 다시 만든 커밋 push · rc 0 · 원격 끝의 부모 = 먼저 들어간 커밋 |
| ㊱바 | push 2회 거절 | rc 3 `판정 불가 push 결과 불명 …` |
| ㊱사 | push 시간 초과 2회 | rc 3 `판정 불가 push 결과 불명`(지금과 같음) |
| ㊱아 | 이미 완성/ 에 있음 · done 없음 | `NOOP … 이미 완성` rc 0 · `REJECT done 없음` rc 1(지금과 같음) |
| ㊱자 | ㊱가 를 한 번 더 | `NOOP` rc 0 · 커밋 0 |
| ㊱차 | 다른 카드 동시 실행: A 가 `read-tree` 를 끝낸 뒤(가짜 git 래퍼가 그 자리에서 멈춤) B 가 다른 카드를 옮겨 push 하고 A 의 리포에 fetch 까지 됨 → A 를 이어 감 | A 의 첫 push 거절 → 새 끝에서 다시 → rc 0 · 원격 끝에 두 카드 모두 완성/ · 두 카드 모두 옛 폴더에 없음 · A 커밋의 부모 = B 커밋 |
| ㊱카 | 같은 카드 경쟁: A 가 `read-tree` 를 끝낸 뒤 B 가 같은 카드를 옮겨 push · fetch | A push 거절 → 새 끝에서 `card()` 다시 → `NOOP … 이미 완성` rc 0 · A 커밋 0 · 원격의 그 카드 `## 상태` 끝 줄 1개(두 번 안 붙음) |
| ㊱타 | 가짜 git 이 `write-tree` 뒤 tree 에 다른 파일 변화 1개를 섞음(자기 검사 대역) | rc 3 `판정 불가 card_stage 커밋 범위 밖 3줄` · push 0 · 원격 변화 0 |
| ㊱파 | 실행 중 부른 git 인자 전부(가짜 래퍼 기록) | `read-tree` · `show` · `ls-tree` · `commit-tree -p` 의 대상이 모두 40자 SHA · 가지 이름은 `fetch` · `rev-parse` · `push` 에만 |
| M47 | `stage` 를 worktree 방식으로 되돌림 | ㊱나 FAIL |
| M48 | 시간 초과 글에서 명령 이름을 뺌 | ㊱라 FAIL |
| M49 | 거절 뒤 다시 만들지 않고 같은 커밋을 다시 push | ㊱마 FAIL |
| M50 | `--force-remove` 를 뺌(옛 경로가 남음) | ㊱가 FAIL(진행/ 에 카드 남음) |
| M59 | `commit-tree -p` 와 `show` 를 가지 이름으로 되돌림(부모 고정 뺌) | ㊱차 FAIL(B 의 카드가 옛 폴더로 되돌아감) · ㊱파 FAIL |
| M60 | 거절 뒤 `card()` 를 다시 돌리지 않음(앞 카드 경로 · 원문 재사용) | ㊱카 FAIL |
| M61 | 자기 검사(8번)를 뺌 | ㊱타 FAIL |

회귀: r1859 · r1884 · r1889 · r1891 card_stage 시험. worktree 정리 사례(r1891 «add 끊김 정리» · «정리 실패 등록 잔존»)는 길이 없어지므로 사례 이름을 PR 본문에 적고 ㊱나 로 바꾼다. 실행 = `python3.11 -m pytest`.

## 5. 닫는 증거

1. 고친 커밋(팩 main 착지 sha) + 설치 판.
2. 설치 뒤 chatbot 팀장이 멈췄던 카드(C-k8) 완성 이동을 다시 집행한 출력 1줄 = `STAGED …` 또는 `판정 불가 git <명령> 시간초과 7초`(명령 이름이 보임).
3. 2번이 `STAGED` 면 BYZ `git worktree list` 줄 수가 실행 앞뒤로 같다는 1줄.

## 6. DA 에게 묻는 것

- Q1. 넘은 명령을 확인하지 못한 채 worktree 를 없애는 것. 대안 = 1번(명령 이름 드러냄)만 먼저 착지하고 다음 사건의 원문을 본 뒤 2번을 한다(카드 2장 · 사건 1회를 더 기다림).
- Q2. hook 을 건너뛰는 대신 8번 자기 검사(커밋 변화 = D 1줄 + 완성/ 밑 `.md` A 1줄)로 pre-commit 세 검사의 범위 밖임을 실행 때마다 확인하는 것으로 충분한가.
- Q3. push 거절 때 rebase 대신 새 끝에서 다시 만드는 것(카드 1장 옮기기라 충돌 판단이 «옛 경로가 그 끝에 아직 있나» 하나로 준다. 없으면 `NOOP`).

## 7. 다른 행과 겹침 · 운영 손

- `card_stage.py` 를 만지는 다른 카드 0(B · C · D+F · E · G · I 대상 파일 대조).
- 팀장에 넘길 운영 줄: BYZ 리포 loose object 236,711개 · pack 28개 · prunable worktree 17개. gc 와 worktree 정리는 사람 승인 뒤 집행이다.
