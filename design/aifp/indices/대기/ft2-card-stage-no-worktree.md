# 인덱스: ft2-card-stage-no-worktree — 끝: card_stage 가 임시 worktree 없이 임시 index 로 카드 이동 커밋을 만든다 · 시간 초과 글에 git 명령 이름이 나온다 · 동시 실행이 남의 카드 이동을 되돌리지 않는다 · 호출 상한 7초는 그대로다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8647 — 등록 planner#324 aifp 5423(답 BYZ 310344 · 팀장 aifp-ft-master-pi#18 발주 aifp 5421 · 5410 ④ · 5382 행 H)
- 제안서: 없음 — 결함 복구(새 흐름 0) · 설계 = .fable-team/state/team-main/aifp-ft/orders/DESIGN-pH-card-stage-git-7s-20261116.md(r2 sha256 ee7461b0…b3c2 · DA 대행 byz-harness-da-codex#11 APPROVE-DESIGN BYZ 310291 · 전문 .fable-team/state/team-main/aifp-ft/DA-pH-r2-approve-310291.md · 앞 판 r1 REJECT BYZ 310176 = 가지 이름을 두 번 읽어 tree 와 부모가 어긋나는 반례 → 닫힘) · 착지 PR 에서 feature-pack/fable-team/design/ 로 옮긴다
- 근거: 사건 = chatbot 팀장 #58 보고 1통(BYZ 309786 «card_stage 2.0.62 rc3 git 시간초과 2회 · worktree add 단계 7초 상한 · BYZ 등록 worktree 445개 · 잔존 0») · 실측 2026-11-16(aifp-ft-arch-pi#17 · BYZ 리포 읽기만) — .git 14G · loose object 236,711개 · pack 28개 · 등록 worktree 455줄(prunable 17) · 읽기 명령(worktree list · status · 임시 index read-tree)은 모두 0.5초 안 · 쓰기 쪽(worktree add · checkout · fetch · push)은 재지 않음 · 넘은 명령이 무엇인지는 도구 출력으로 가를 수 없음 [확인 필요: 실제로 넘은 명령 — G1 이 들어간 뒤 다음 사건에서 보임]
- 원인 1줄: git() 이 모든 호출에 7초를 쓰는데 한 번 실행에 14회쯤 부르고 그중 6회가 임시 worktree(등록 455개를 읽고 씀 · checkout) 때문에 있다 · 시간 초과 글에 명령 이름이 없다
- 앞 카드: r1859(카드 폴더 단계 이동) · r1884(main 기준 팀 카드 이동) · r1889(대기/ 원본도 완성/ 으로) · r1891(팩 6d428738 · 임시 worktree sparse + add 끊김 정리)
- 상태: 대기
- 설치: 있음 — ft2 판 올림 1회 · 되돌림 = 앞 판으로 판 전환(상태 파일·설정 변화 0)
- 선행: 없음
- 시험 입력: 임시 bare 원격 + 임시 clone(tmp_path) · 가짜 git 래퍼(인자 기록 · 사례가 정한 자리에서 멈춤·상한 넘김·tree 섞기) · sleep 0 · 네트워크 0 · 실 리포 쓰기·읽기 0 · 사례 1개 70초 안
- 기준값: 기준판 = 한 번 실행에 git worktree 호출 2회 + checkout 1회 · 시간 초과 글 `판정 불가 git 시간초과` → 목표 = worktree·checkout 호출 0 · 시간 초과 글 `판정 불가 git <명령> 시간초과 7초`
- 규칙: 없음 — 상시 로드 변경 0
- 규칙 상세: 하드 룰 12(호출 1회 7초 + 재시도 1 · 늘리지 않음) · 하드 룰 20 · 하드 룰 22
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/card_stage.py(136줄 · 마지막 고침 6d428738 · git() · card() · stage()) · 새 시험 feature-pack/fable-team/ft2/tests/test_card_stage_no_worktree.py · 정본 자리 = 팩의 이 파일 1곳이다 · chatbot 팀이 돌린 것은 그 설치판 ~/.claude/fable-team/ft2/versions/2.0.62/adapters/pi/card_stage.py(팩 origin/main 과 바이트 같음 · 2026-11-16 대조) · BYZ 리포에 tracked card_stage.py 는 0개(git ls-files 대조)
- 정본 영향 없음: CONTRACT 변경 0 · rc 뜻·출력 꼴·커밋 글 그대로(G7)
- 크기: 코드 1파일 · 새 시험 1파일 · 문서 1파일(설계 옮김) · PR 1개
- 배정: 없음

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(하네스 운영 정리 — 끝난 카드가 느린 리포에서도 완성/ 으로 가고 막히면 어느 명령인지 보인다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 chatbot 팀장이 멈췄던 카드 완성 이동을 다시 집행한 출력 1줄 + 그 앞뒤 BYZ git worktree list 줄 수.

## 배경 (한 단락)
card_stage 는 끝난 카드를 완성/ 폴더로 옮기는 커밋을 만들어 push 한다. 지금은 임시 worktree 를 만들고 그 안에서 checkout·mv·commit 을 한다. BYZ 리포는 등록 worktree 가 455개이고 object 가 많아서 그 단계가 7초 상한을 넘었다는 보고가 왔다. 도구는 `판정 불가 git 시간초과` 만 내서 어느 명령이 넘었는지 알 수 없다. 느린 호출을 더 기다리지 않고 없앤다. 임시 index 파일 하나로 같은 커밋을 만든다. 첫 설계는 가지 이름을 두 번 읽어 동시 실행에서 남의 카드 이동을 되돌릴 수 있었다. 그래서 시도마다 부모 SHA 하나를 고정한다.

## 계약
- G1 시간 초과 글 = git() 이 시간 초과면 `Unsure("git <하위 명령> 시간초과 <상한>초")` · worktree 처럼 둘째 낱말이 있는 명령은 둘째 낱말까지 · 출력 꼴 `판정 불가 git read-tree 시간초과 7초`
- G2 stage() 는 임시 worktree 를 쓰지 않는다 · 작업 폴더·worktree 등록·checkout 0 · 임시 폴더의 `GIT_INDEX_FILE` 로 커밋을 만든다
- G3 순서 = ⓪ 시도 시작에 `rev-parse <ref>^{commit}` 으로 부모 SHA `P` 하나를 고정 · 아래는 가지 이름 대신 `P` 만 쓴다 ① 임시 index ② `read-tree P` ③ `show P:<옛 경로>` 본문을 restate 로 고침 ④ `hash-object -w --stdin` ⑤ `update-index --force-remove <옛 경로>` · `update-index --add --cacheinfo 100644,<blob>,<새 경로>` ⑥ `write-tree` ⑦ `commit-tree <tree> -p P -m "[docs] <카드> 2.0 완성 폴더(ft2 done)"` ⑧ 자기 검사(G8) ⑨ `push origin <커밋>:<가지>`
- G4 push 거절 = rebase 0 · fetch 1회 뒤 새 `P` · 카드 고르기 · 카드 원문을 한 묶음으로 다시 고정(card() 를 새 `P` 에서 다시 돌림) · 그 끝에 이미 완성/ 이면 `NOOP … 이미 완성` rc 0 · 아니면 G3 ①~⑨ 1회 다시 · 또 거절이면 지금처럼 `판정 불가 push 결과 불명`
- G5 상한 = 호출마다 7초 · push 의 «7초 + 재시도 1» 그대로 · 늘리지 않는다
- G6 정리 = 임시 폴더만(TemporaryDirectory) · `worktree remove` 와 «정리 실패 · 등록 잔존» 줄은 없어진다
- G7 그대로 = done_at · restate · rc 뜻(0 STAGED·NOOP / 1 REJECT / 3 판정 불가) · 커밋 글 · 출력 꼴 `STAGED <카드> <frm>→완성 <sha>` · push 때 도는 pre-push hook
- G8 자기 검사(push 전) = `diff-tree -r --no-renames --name-status P <커밋>` 이 정확히 2줄 = `D <옛 경로>` 와 `A <새 경로>` · 새 경로는 `/indices/완성/` 밑 `.md` · 아니면 `판정 불가 card_stage 커밋 범위 밖 <줄 수>줄` rc 3 · push 0
- G9 card() 의 판독 기준 = card() 가 부르는 show·ls-tree 도 시도 시작에 고정한 SHA 로 읽는다(land.REFS 두 가지를 각각 SHA 로 고정 · 고른 가지의 SHA 가 G3 의 `P`) · 가지 이름은 fetch·rev-parse·push 에만 남는다

## 인수 칸 (DA BYZ 310291 해석 · 구현 시험에 그대로 반영)
- ㊱카 «A 커밋 0» = 원격에 추가되는 A 커밋 0 이다 · A 는 첫 push 전에 commit-tree 를 이미 1회 불렀으므로 로컬에 어느 가지에도 안 달린 커밋 1개는 허용한다 · 확인하는 것 = NOOP 재시도에서 새 commit-tree 호출 0 + 원격의 그 카드 `## 상태` 끝 줄 1개
- G8 의 경로 대조 = `--no-renames` 로 이동을 D/A 2줄로 고정하고 한글 경로는 git 의 경로 quoting 을 풀거나 `-z` 로 읽어 실제 경로와 비교한다 · 맞아야 하는 것 = 정확한 `D <고른 옛 경로>` 1줄과 `A <그에 대응하는 완성 경로>` 1줄 · 줄 수만 세어 다른 경로를 통과시키면 불합격
- hook 승인 범위(DA): 알려진 BYZ pre-commit 세 검사(공유 index · 증거 로그 · 대기/ 새 카드 상한)에 대한 동작 반례 0 · 다른 저장소의 임의 hook 까지 지킨다는 승인은 아니다

## 구현 범위 (나노 1 · 팩 base origin/main 최신)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_card_stage_no_worktree.py(㊱가~파 13칸 · M47~M50 · M59~M61) · 기준판 FAIL 원문(㊱나·㊱라·㊱차·㊱타·㊱파)을 PR 본문에 붙인다
2. 커밋 2 [fix] — G1~G9 = feature-pack/fable-team/ft2/adapters/pi/card_stage.py(git() · card() · stage()) · 다른 파일 손 0
3. 커밋 3 [docs] — 설계 1쪽을 feature-pack/fable-team/design/ 로
4. 회귀 rc0: test_card_stage_r1859.py · test_card_stage_main_ref_r1884.py · test_card_stage_from_waiting_r1889.py · test_card_stage_sparse_r1891.py · r1891 의 worktree 정리 사례(«add 끊김 정리» · «정리 실패 등록 잔존»)는 길이 없어지므로 사례 이름을 PR 본문에 적고 ㊱나 로 바꾼다
5. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

## 범위 밖
- 끝난 worktree 455개(prunable 17) 정리 · BYZ 리포 gc(loose object 23만 개) = 운영 손(지우기 = HIL · 팀장에 1줄로 넘김)
- 상한을 25초로 올리는 길 · 도구 안에서 통째로 다시 돌리는 길(버린 길 · 설계 §3)
- 느린 원인이 fetch·push 인 경우(G2 로는 안 고쳐짐 · G1 이 그 명령을 보여 준 뒤 따로 판단)
- 알려진 한계(DA BYZ 310291): 실제 worktree add 지연 원인과 설치 뒤 성능은 아직 실측하지 않았다 · push 가 실패하면 blob·tree·commit object 가 가지에 안 달린 채 남는다(다음 gc 가 치움 · 지금 방식도 같음)

## 완료 조건
1. [ ] 나노: 커밋 1 기준판 FAIL 원문
2. [ ] 나노: 새 시험 전체 rc0 · 걸린 초
3. [ ] 나노: 변이 M47 → ㊱나 FAIL · M48 → ㊱라 FAIL · M49 → ㊱마 FAIL · M50 → ㊱가 FAIL · M59 → ㊱차·㊱파 FAIL · M60 → ㊱카 FAIL · M61 → ㊱타 FAIL
4. [ ] 나노: 회귀 rc0 · 바꾼 r1891 사례 이름
5. [ ] arch: 인수 칸 원문 확인 = ㊱카 가 commit-tree 호출 수와 원격 상태 줄을 따로 세는가 · G8 대조가 한글 경로를 실제 경로로 비교하는가(㊱타 + 한글 폴더 이름 사례)
6. [ ] 팀장: PR 착지 sha · 설치 판
7. [ ] 팀장: 설치 뒤 chatbot 팀장이 멈췄던 카드(C-k8) 완성 이동 재집행 출력 1줄 = `STAGED …` 또는 `판정 불가 git <명령> 시간초과 7초` · STAGED 면 BYZ git worktree list 줄 수가 앞뒤로 같다는 1줄

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| G2·G3·G7 임시 index 로 이동 | ㊱가 진행/ 카드 1장 · done 있음 → rc 0 `STAGED … 진행→완성 <sha>` · 원격 가지 끝 = 그 sha · 완성/ 에 카드(머리 `- 상태: 완성` · `## 상태` 끝 1줄) · 진행/ 에 없음 · 그 밖 파일 변화 0 / ㊱다 대기/ 카드 → `STAGED … 대기→완성` / M50 |
| G2·G6 worktree 0 | ㊱나 실행 앞뒤 `git worktree list` 줄 수 같음 · 부른 git 인자에 worktree 0 / M47 |
| G1·G5 시간 초과 글 | ㊱라 가짜 git 이 read-tree 에서 상한 넘김 → rc 3 `판정 불가 git read-tree 시간초과 7초` · 원격 변화 0 / ㊱사 push 시간 초과 2회 → rc 3 `판정 불가 push 결과 불명` / M48 |
| G4 push 거절 | ㊱마 1회 거절 → fetch 1 · 새 끝에서 다시 만든 커밋 push · rc 0 · 원격 끝의 부모 = 먼저 들어간 커밋 / ㊱바 2회 거절 → rc 3 `판정 불가 push 결과 불명 …` / M49 |
| G7 NOOP·REJECT 그대로 | ㊱아 이미 완성/ → `NOOP … 이미 완성` rc 0 · done 없음 → `REJECT done 없음` rc 1 / ㊱자 ㊱가 를 한 번 더 → NOOP rc 0 · 커밋 0 |
| G3 ⓪·G9 부모 고정 | ㊱차 다른 카드 동시 실행(A 가 read-tree 뒤 멈춤 · B 가 다른 카드를 push · A 리포에 fetch) → A 첫 push 거절 → 새 끝에서 다시 → rc 0 · 두 카드 모두 완성/ · 옛 폴더에 없음 · A 커밋의 부모 = B 커밋 / ㊱파 read-tree·show·ls-tree·commit-tree -p 의 대상이 모두 40자 SHA · 가지 이름은 fetch·rev-parse·push 에만 / M59 |
| G4 거절 뒤 card() 다시 | ㊱카 같은 카드 경쟁 → A push 거절 → 새 끝에서 card() 다시 → `NOOP … 이미 완성` rc 0 · 원격 추가 A 커밋 0 · NOOP 재시도 commit-tree 0 · 원격의 그 카드 `## 상태` 끝 줄 1개 / M60 |
| G8 자기 검사 | ㊱타 가짜 git 이 write-tree 뒤 tree 에 다른 파일 변화 1개를 섞음 → rc 3 `판정 불가 card_stage 커밋 범위 밖 3줄` · push 0 · 원격 변화 0 / M61 |

## 상태
- 2026-11-16 · aifp-ft-arch-pi#18 씀(aifp 5421 · 승계 5424) · 대기 · 설계 r2 = DA 대행 APPROVE-DESIGN(BYZ 310291) · 선행 없음 · Issue #8647(aifp 5423)
