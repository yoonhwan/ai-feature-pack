# 인덱스: ft2-keeper-git-no-lazy-fetch — 끝: ft2 keeper 의 착지 조상 확인·객체 존재 확인 git 호출이 원격 lazy fetch 없이 로컬 객체만 보고 끝난다 · 판정값은 G4 표의 실측 칸대로 그대로다(base 가 두 리포 어디에도 로컬로 없을 때만 지금처럼 원격에 묻는다) · 그 env 는 그 호출의 자식에만 실리고 keeper 가 띄우는 다른 자식으로 새지 않는다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: 없음(초안) — 넘김 byz-harness-master-pi#295 aifp 5867(harness r1979 git 호출 비용 조사 · 착지 d8b863c8 · BYZ Issue 8660 · 카드 후보 A) · 덧 aifp 5869(harness 나노 r2022 가 같은 줄을 고치는 중) · 팀장 aifp-ft-master-pi#22 발주 aifp 5868 · 5870
- 제안서: 없음 — 결함 복구(git 자식의 env 1칸) · 설계 = 이 카드 «계약»·«반례 표»
- 근거: 실측 2026-11-16 08:30(aifp-ft-arch-pi#22 · BYZ .fable-team/state/ft2-keeper/20261116.jsonl · BYZ 루트와 팩 리포에 읽기 명령 4개 · 읽기만) + harness arch#391 실측 BYZ .fable-team/state/team-main/harness/a391/r1979-candidates.log — 아래 «기준값» 절
- 원인 1줄: BYZ 루트는 blob:none partial clone(remote.origin.promisor=true)이다 · keeper 가 그 리포에 «없는 sha»(다른 리포의 착지 sha · 다른 리포의 base_sha)로 `git merge-base --is-ancestor` · `git cat-file -e` 를 물으면 git 이 그 객체를 원격에서 받으려 한다(lazy fetch) · 받지 못하고 6~25초 뒤에야 rc 가 나온다 · keeper 의 git 호출 문(keeper.py `git` → `call`)은 env 를 호출마다 바꿀 길이 없다
- 앞 카드: 진행/ft2-keeper-round-60s(R7 = 로컬 git 상한 25 → 7초 · PR #1397 열림) · harness 대기/r2022-keeper-ancestor-call-7s(조상 확인 3곳 7초 · rc 갈래) · 1.x 선례 r1401(`_ft_landed_git` · ft-team-lib.sh 313줄) · r1783(ft_approval_equiv.py 57줄 · 176줄)
- 앞 카드와의 관계: r2022 가 keeper_land.py 의 착지 고리(:165) · pre_attempt(:182) · keeper_endings.py :65 를 고친다 = 이 카드와 같은 줄이라 r2022 착지 뒤에 그 판 위에서 한다 · keeper 60초 카드의 R7 이 착지하면 lazy fetch 로 7초를 넘는 호출이 «판정 불가 git» 줄로 바뀐다 → 이 카드가 그 줄 수를 줄인다(60초 카드 파일 keeper.py · keeper_report.py · full_alert.py · CONTRACT.md · CASES.md 는 이 카드에서 손 0)
- 상태: 대기
- 설치: 있음 — ft2 판 올림 1회 · 되돌림 = 앞 판으로 판 전환(상태 파일·설정 변화 0)
- 선행: r2022 — harness 카드 r2022-keeper-ancestor-call-7s(BYZ design/harness/indices · 나노 byz-harness-nano-r2022-keeper-ancestor-call-7s#0 일 중 · 같은 줄 keeper_land.py :165 · :182 · keeper_endings.py :65) · 그 착지 판이 나노 base 다
- 시험 입력: 임시 폴더(tmp_path) 안의 실 git 리포 대역 = 로컬 bare 원격(uploadpack.allowFilter) + blob:none partial clone + «느린 upload-pack» 대역(호출마다 기록 1줄 + 3초) · 1.x test_landed_git_no_lazy_r1401.sh 와 같은 꼴 · 가짜 gh · 가짜 시계 0 · 실 원격 0 · 실 리포 0 · 실 runtime 0 · 네트워크 0 · 사례 1개 70초 안
- 기준값: 오늘 00:00~08:30 keeper SLOW-CALL(5초 넘은 호출) 122줄 가운데 `git BYZ-Agents cat-file` 14줄 239.8초 · `git BYZ-Agents merge-base` 8줄 117.5초 → 목표 = 없는 객체를 묻는 호출이 5초를 넘는 줄 0(실측 0.02초)
- 규칙: 없음 — 상시 로드 변경 0(keeper 의 git 자식 env 1칸만 바뀐다)
- 규칙 상세: 하드 룰 12(외부 호출 7초 · 런타임 7초 절대) · 하드 룰 20 · 하드 룰 22
- 대상: 팩 feature-pack/fable-team/ft2/adapters/pi/keeper_land.py(로컬만 보는 git 손 1개 · 쓰는 곳 4줄 · base 존재 확인 3단) · feature-pack/fable-team/ft2/adapters/pi/keeper_endings.py(쓰는 곳 1줄) · 새 시험 feature-pack/fable-team/ft2/tests/test_keeper_git_no_lazy_fetch.py
- 정본 영향 없음: aifp 정본(docs/architect · docs/rules · design 팀 GUIDE·README) 변경 0 · 팩 ft2 계약 문서(CONTRACT.md · CASES.md)도 변경 0 — 판정값·rc 뜻·로그 줄 꼴은 그대로이고 바뀌는 것은 git 자식의 env 1칸뿐이다(사례표는 새 시험 파일 머리 글에 둔다 = 60초 카드가 고치는 두 문서와 겹치지 않게)
- 크기: 코드 2파일(15줄 안팎) · 새 시험 1파일 · PR 1개
- 배정: 대기(DA · 2026-11-16T08:35)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
6 — 하네스 운영 정리. 하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(keeper 한 바퀴가 없는 객체를 원격에서 찾느라 멈추지 않는다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 keeper 로그의 `git BYZ-Agents cat-file`·`merge-base` SLOW-CALL 줄 수 + 같은 work 의 판정 줄 종류가 설치 앞과 같음.

## 배경 (한 단락)
keeper 는 카드의 착지 sha 가 어느 리포의 어느 ref 에 닿았는지를 팩 origin/main → BYZ 두 ref 순서로 묻는다. 착지 sha 가 팩 것이면 BYZ 에는 그 객체가 없고, 반대도 같다. BYZ 루트는 blob 을 나중에 받는 partial clone 이라, git 은 없는 객체를 보면 원격에 달라고 한다. 원격에도 없으니 몇 초 뒤 실패한다. 그 몇 초가 바퀴마다, ref 마다 쌓인다. harness 가 r1979 조사에서 이 비용을 쟀고(6.2~8.2초 → 0.04초), 고칠 줄이 모두 ft2 keeper 라 aifp 로 넘겼다. 1.x 도구는 같은 문제를 `GIT_NO_LAZY_FETCH=1` 로 이미 풀었다(r1401 · r1783). 그 선례는 «존재·조상 확인에만 넣고 blob 이 필요한 조회에는 넣지 않는다» 를 같이 적어 두었다.

## 기준값 (실측 원문 · 2026-11-16 · 읽기만)
| # | 무엇 | 원문 |
|---|---|---|
| 가 | 오늘 keeper 로그(00:00:00~08:30:51 · ROUND 353줄 · OVER 20줄 · SLOW-CALL 122줄) | `b1 git BYZ-Agents cat-file` rc=1 9줄 114.7초(6.1~22.4초) · rc=None 4줄 100.1초(25초 상한) · `b2c git BYZ-Agents cat-file` rc=None 1줄 25초 · `git BYZ-Agents merge-base` rc=None 3줄 75초(b2c 2 · b2f 1) · rc=128 3줄 31.3초(b1 9.2 · 10.6 · b2c 11.5) · rc=0 2줄 11.2초 |
| 나 | 줄 원문 | `06:20:49 SLOW-CALL harness b1 git BYZ-Agents cat-file s=25 rc=None try=1/1` · `06:21:54 SLOW-CALL harness b2f git BYZ-Agents merge-base s=25 rc=None try=1/1` · `06:25:36 SLOW-CALL harness b2c git BYZ-Agents cat-file s=25 rc=None try=1/1` |
| 다 | BYZ 루트 설정 | `remote.origin.promisor=true` · `remote.origin.partialclonefilter=blob:none` · 팩 리포는 두 값 모두 없음(partial clone 아님) · git version 2.52.0 |
| 라 | env 를 준 호출(BYZ 루트 · 없는 sha 0123…4567) | `GIT_NO_LAZY_FETCH=1 git -C <BYZ> cat-file -e <sha>` = rc 1 · 0.02초 / `GIT_NO_LAZY_FETCH=1 git -C <BYZ> merge-base --is-ancestor <sha> origin/main` = rc 128 `fatal: Not a valid commit name …` · 0.02초 |
| 마 | 다른 리포 sha 의 rc(팩 리포 · partial clone 아님) | `git -C <팩> merge-base --is-ancestor <BYZ main sha> origin/main` = rc 128 · `git -C <팩> cat-file -e <그 sha>` = rc 1 → 없는 객체의 조상 확인 rc 는 1 이 아니라 128 이다 |
| 바 | harness 실측(arch#391 · aifp 5867 인용) | lazy fetch 켬 6.2~8.2초 → `GIT_NO_LAZY_FETCH` 0.04초 · ft2 에서 merge-base · cat-file -e 를 부르는 파일 = adapters/pi/keeper_land.py · keeper_endings.py 2개 · GIT_NO_LAZY_FETCH 쓰는 곳 = legacy/1.x 8파일(ft2 0) |

고칠 줄(팩 origin/main 5c978eb9): keeper_land.py :165 `self.git(repo, "merge-base", "--is-ancestor", sha, ref)`(착지 고리 · 리포 3번) · :177 `self.git(repo, "cat-file", "-e", base)` · :182 `self.git(repo, "merge-base", "--is-ancestor", sha, base)` · keeper_endings.py :65 `k.git(tree, "merge-base", "--is-ancestor", sha, "origin/" + base)`. r2022 착지 뒤에는 줄 번호가 바뀐다 = 이 4개 호출을 글자로 찾는다.

r2022 판(팩 PR #1401 · head 6d47494a · 2026-11-16 08:46 대조)의 줄: keeper_land.py :167 착지 고리 조상 확인(`timeout=endings.ANC_S`) · :171 rc 128 일 때의 `cat-file -e sha`(rc 1 = 다음 ref) · :182 base 존재 확인 · :187 옛 착지 조상 확인 · keeper_endings.py :68 PR 착지 조상 확인(rc 0·1 밖 = «판정 불가 · PR 착지 조상 git rc»). r2022 는 «조상 확인 먼저 → rc 128 이면 존재 확인» 순서다. 이 카드는 그 순서를 바꾸지 않는다.

### r2 실측 (2026-11-16 08:47 · aifp-ft-arch-pi#23 · DA HOLD-DESIGN 313081 R1 보정)
재현 = `python3.11 .fable-team/state/team-main/aifp-ft/A23-no-lazy-r2/probe_r2.py`(2.086초 · 결과 probe_r2.json · 같은 폴더 nonpartial.txt). DA probe.py 와 같은 대역(bare 원격 + blob:none single-branch clone + upload-pack 기록)에 짝 리포 1개를 더했다. «지금» = f0db47b9 판 `Landing.pre_attempt` 그대로 · «r2» = G4 의 3단 규칙. 착지 L 의 시각 00:01 · intent.at 00:03.

| # | base 입력 | 지금 판정 · upload-pack | r2 판정 · upload-pack | 같은가 |
|---|---|---|---|---|
| 1 | R1 = 원격의 다른 가지에만 있음 · 짝 리포에 없음 | `""`(진행) · 1 | `""`(진행) · 1 | 같음 |
| 2 | 짝 리포에만 있음(다른 리포 base · 오늘 느린 줄의 꼴) | 옛 착지 줄(attempt 전 · 다른 repo 시각) · 1 | 옛 착지 줄(attempt 전 · 다른 repo 시각) · 0 | 같음 |
| 3 | 원격의 다른 가지에도 있고 짝 리포에도 로컬로 있음 | `""`(진행) · 1 | 옛 착지 줄(attempt 전 · 다른 repo 시각) · 0 | ★다름★ |
| 4 | 로컬에 있음 · 착지가 조상 아님 | `""` · 0 | `""` · 0 | 같음 |
| 5 | 로컬에 있음 · 착지가 조상 | 옛 착지 줄(attempt 전) · 0 | 옛 착지 줄(attempt 전) · 0 | 같음 |
| 6 | 어디에도 없음 | 옛 착지 줄(attempt 전 · 다른 repo 시각) · 1 | 옛 착지 줄(attempt 전 · 다른 repo 시각) · 1 | 같음 |
| 7 | 착지 고리 · 착지 sha 가 원격의 다른 가지에만 있음 | merge-base rc 1(받아 온 뒤) · 1 → 다음 ref | merge-base rc 128 → cat-file rc 1 · 0 → 다음 ref | 같음 |
| 8 | 원격의 다른 가지에만 있음 · 짝 리포에 없음 · 착지가 그 조상 | 옛 착지 줄(attempt 전) · 1 | 옛 착지 줄(attempt 전) · 1 | 같음 |

덧 실측: partial clone 이 아닌 리포(promisor 없음)에서 1번 입력의 `cat-file -e` 는 지금도 rc 1 이다(nonpartial.txt) = 팩 리포에서는 지금도 시각 비교로 간다. BYZ 루트의 객체 저장소에는 팩 root 커밋 edbc3e7c 가 있다(가리키는 ref 0) = 두 리포가 같은 sha 를 가질 수 있다 = 3번 입력은 지어낸 꼴이 아니다.

## 계약
- G1 로컬만 보는 git 손 1개 = keeper_land.py 의 `Landing.git_local(repo, *args, **kw)` · `self.git(repo, *args, **kw)` 를 그대로 부르되 그 호출 동안만 `self.env` 를 `dict(self.env, GIT_NO_LAZY_FETCH="1")` 로 바꿔 끼운다(keeper_next.py :109~113 의 `FT_ROOT` 바꿔 끼우기와 같은 꼴) · argv 는 `git -C <repo> <동사> …` 그대로다(전역 옵션 `--no-lazy-fetch` 를 쓰지 않는다 = 옛 git 에서 rc 129 · keeper 60초 카드의 판독 목록과 SLOW-CALL 줄이 동사를 못 읽게 된다) · 상한·재시도 인자는 부른 쪽이 준 대로 넘긴다(r2022 의 7초 상수)
- G2 쓰는 곳 = 조상 확인과 객체 존재 확인뿐 = 위 4개 호출(+ G3 의 존재 확인 + G4 의 짝 리포 존재 확인) · base 존재 확인의 3단째(G4 ⓒ)만은 `self.git` 그대로다(지금처럼 원격에 묻는다) · 그 밖 git 호출은 손 0: `show`(카드 본문 = blob 이 필요하다 · 넣으면 «없음» 으로 바뀐다) · `log` · `rev-parse` · `config` · `grep` · `ls-tree` · `fetch` · `ls-remote`
- G3 없는 객체 = «그 리포에 없음» 이고 «조상 아님» 과 같은 갈래다 · r2022 판(#1401)의 순서 그대로다: 조상 확인을 `git_local` 로 먼저 한다 → rc 0 조상 · rc 1 조상 아님 · rc 128 이면 `git_local(repo, "cat-file", "-e", sha)` 1회: rc 1 = 없음 → 착지 고리는 다음 ref · PR 착지는 none / 그 밖(None 포함) = r2022 가 정한 «판정 불가» 갈래 · 착지 고리(:167 · :171)는 r2022 가 넣은 두 호출을 `git_local` 로 바꾸기만 한다(호출을 더 넣지 않는다) · PR 착지(:68)는 r2022 판에 rc 128 뒤의 존재 확인이 없으므로 이 카드가 넣는다(없으면 로컬에 없는 mergeCommit 이 none 에서 «판정 불가» 로 바뀐다) · 착지 sha 가 로컬에 없으면 로컬 ref 의 조상일 수 없다(커밋은 blob:none 에서 빠지지 않는다) = 실측 7번
- G4 판정값 그대로 = 아래 표의 «판정» 칸이 env 앞뒤로 같다 · 바뀌는 것은 걸린 초와 upload-pack 호출 수뿐이다 · 예외는 «정한 차이 1칸» 하나다(아래)
- G4 base 존재 확인 3단(r2 · `pre_attempt` 의 `have` 를 정하는 자리): ⓐ `git_local(repo, "cat-file", "-e", base)` → rc 0 = 있음(조상 확인 길) · rc 1 = ⓑ로 · 그 밖 = 지금 글 그대로 «판정 불가 · 옛 착지 대조 cat-file rc» / ⓑ 짝 리포마다 `git_local(짝, "cat-file", "-e", base)` → rc 0 이 하나라도 있으면 = 다른 리포 base 다 → 시각 비교 길(`pre_attempt_time`) · 원격에 묻지 않는다 / ⓒ 짝 어디에도 없으면 `self.git(repo, "cat-file", "-e", base)`(env 없음 = 지금 호출 그대로 · 원격에 묻는다) → 그 rc 로 지금 갈래 그대로(0 = 조상 확인 길 · 1 = 시각 비교 길 · 그 밖 = 판정 불가)
- G4 짝 리포 = `self.pack` · `self.root` 가운데 `repo` 와 git 공통 폴더가 다른 리포(keeper_endings.py `_common` 과 같은 비교 · PR 착지는 `repo` 가 worktree 경로라 글자 비교로는 못 가린다) · 짝이 낡은 리포(`self.stale`)여도 묻는다(로컬 객체가 있다는 사실은 fetch 와 무관하다) · 짝이 없으면(두 리포가 같은 리포) ⓑ 를 건너뛴다
- G4 R1 의도 판정(동결 · DA 313081): 로컬 착지 L · base B 가 원격의 다른 가지에만 있고 짝 리포에 없음 · L 은 B 의 조상 아님 · L 시각 < intent.at → `""`(진행) = 지금 판정 그대로 · ⓒ 가 B 를 받아 온 뒤 조상 확인 rc 1(실측 1번 · upload-pack 1회는 남는다)

| 호출 | 객체 있음 | 객체 없음(env 앞 → 뒤) | 판정 |
|---|---|---|---|
| 착지 고리 조상 확인 | rc 0 조상 · rc 1 조상 아님 | 6~25초 뒤 rc 128 또는 None → G3 존재 확인 rc 1 · 0.02초 | 다음 ref · 세 ref 모두 아니면 «미도달» |
| base 존재 확인 · base 가 짝 리포에 로컬로 있음 | — | 6~25초 뒤 rc 1 또는 None → ⓐ rc 1 · ⓑ rc 0 · 로컬 호출 2회 | 시각 비교 길(`pre_attempt_time` · r1910) · 실측 2번 |
| base 존재 확인 · base 가 두 리포 어디에도 로컬로 없음 | — | ⓐ rc 1 · ⓑ rc 1 → ⓒ 지금 호출 그대로 | 지금과 같은 rc 갈래 · 걸린 초도 지금과 같다 · 실측 1번 · 6번 |
| base 존재 확인 · base 가 그 리포에 로컬로 있음 | ⓐ rc 0 | — | 조상 확인 길 · 실측 4번 · 5번 |
| 옛 착지 조상 확인 | rc 0 옛 줄 · rc 1 진행 | 앞에서 두 객체 모두 있음이 확인됨 | 그대로 |
| PR 착지 | rc 0 착지 · rc 1 none | 받아 온 뒤 rc 1 → rc 128 → G3 존재 확인 rc 1 | none(착지 아님) |

- G5 끝나면 되돌린다 = `git_local` 이 끝난 뒤 `self.env` 는 부르기 전과 같은 객체다(`try … finally`) · `self.git` 이 예외를 올려도(keeper 60초 카드의 끊김 예외) 되돌린다 · 원래 `self.env` 에 `GIT_NO_LAZY_FETCH` 가 있었으면(0 이든 1 이든) 그 호출의 자식만 1 을 보고, 끝난 뒤 원래 값이다
- G6 새지 않는다 = `git_local` 밖에서 keeper 가 띄우는 자식(launch.py Popen · keeper_fetch 자식 · mbox · gh · tmux · 4개 밖 git)의 env 에 `GIT_NO_LAZY_FETCH` 가 없다 · 나노 좌석으로 이 값이 넘어가면 그 좌석의 checkout·diff 가 blob 을 못 받는다
- G7 그대로: 착지 고리의 리포·ref 순서 · 낡은 리포(`self.stale`) 건너뜀 · «미도달»·«판정 불가» 글 · `pre_attempt` 의 rc 갈래 · SLOW-CALL 줄 꼴 · keeper.py(`git` · `call` · `GIT_S`) · fetch 규칙 · r2022 가 정한 상한과 rc 갈래
- 정한 차이 1칸(r2 · 판정 변경 · ★팀장 확인 칸★): base 가 짝 리포에 로컬로 있고, 같은 sha 가 그 리포 원격의 받지 않은 가지에도 있는 입력(실측 3번) · 지금 = git 이 받아 와 조상 확인(L 이 조상 아니면 진행) · r2 = 시각 비교(L 시각 < intent.at 이면 옛 착지 줄) · 의도 판정 = r2 쪽이다: r1910 의 뜻은 «base 가 다른 리포 것이면 시각으로 본다» 이고, 지금 값은 partial clone 의 lazy fetch 가 만든 부수 결과다(partial clone 이 아닌 팩 리포는 같은 입력에서 지금도 시각 비교로 간다 · nonpartial.txt) · 이 칸을 지금 값으로 지키려면 다른 리포 base 마다 원격에 물어야 하고 그러면 오늘 느린 줄 `b1 cat-file` 14줄 239.8초가 그대로 남는다 · r1 의 «알려진 차이 1줄»(«두 길 모두 옛 줄 / 진행을 낸다» 로 넘긴 글)은 지운다 = 그 글은 같은 입력의 분류가 뒤집히는 것을 가렸다

## 반례 표 (실 git 대역 · 느린 upload-pack 기록)
| # | 입력 | 기대 | 지금 |
|---|---|---|---|
| ㊸가 | 루트 대역 = blob:none partial clone · 카드 착지 줄 sha = 그 리포에 없는 sha(팩 대역의 커밋) · 팩 대역 origin/main 에는 아직 없음 | upload-pack 기록 0줄 · 판정 = `(sha, None, "미도달")` 그대로 · 착지 판정 1회 2초 안 | upload-pack 기록 2줄 이상(ref 2개) · 6초 넘음 |
| ㊸나 | intent base_sha = 그 리포에 없고 짝 리포 대역에 로컬로 있는 sha(다른 리포 base) · 착지 sha 는 그 리포 ref 의 조상 | upload-pack 0줄 · ⓐ rc 1 · ⓑ rc 0 → 시각 비교 길 · 결과 = r1910 그대로(착지 시각 < 연 시각 = «옛 착지 줄(attempt 전)» · 아니면 "") | upload-pack 1줄 · 3초 넘음 · 결과는 같음 |
| ㊸다 | 착지 sha 가 팩 대역 origin/main 의 조상(있는 객체) | 판정 = `(sha, "pack:origin/main", "")` 그대로 · upload-pack 0줄 | 같음(회귀 고정) |
| ㊸라 | 착지 sha 가 세 ref 모두에 있지만 조상이 아님(다른 가지 커밋) | 세 번 rc 1 → «미도달» 그대로 · 존재 확인 rc 0 3회 | 같음 |
| ㊸마 | PR 착지(:65) — gh 대역이 준 mergeCommit sha 가 worktree 리포에 없음 | upload-pack 0줄 · none(착지 아님) · [줄 보완] 쪽지 0 | worktree 리포가 partial clone 이면 upload-pack 1줄 |
| ㊸바 | `self.env` 에 `GIT_NO_LAZY_FETCH=0` 이 이미 있음 · ㊸가 입력 | 4개 호출의 자식 env 값 = 1(upload-pack 0줄) · 호출 뒤 `self.env["GIT_NO_LAZY_FETCH"] == "0"` · `self.env` 는 같은 객체 | — |
| ㊸사 | `git_local` 안에서 `self.git` 이 예외를 올림(끊김 예외 대역) | 예외는 그대로 올라감 · `self.env` 에 `GIT_NO_LAZY_FETCH` 없음(되돌림) | — |
| ㊸아 | 한 바퀴: 카드 본문 `git show`(blob 이 로컬에 없음) → 착지 판정 → 열기(Popen 대역) | `show` 는 본문을 읽어 온다(upload-pack 기록 1줄 이상 = lazy fetch 가 살아 있다) · Popen 대역이 본 env 에 `GIT_NO_LAZY_FETCH` 없음 · 4개 밖 git 자식 env 에도 없음 | — |
| ㊸자 | 루트 대역이 낡은 리포(`self.stale`) | 그 리포로는 `git_local` 호출 0 · «판정 불가 · 팩 fetch 실패» 그대로 | 같음 |
| ㊸차 | R1(DA 313081): 착지 L 은 로컬 ref 의 조상 · base B 는 원격 대역의 다른 가지에만 있음 · 짝 리포 대역에 없음 · L 은 B 의 조상 아님 · L 시각 < intent.at | 결과 = `""`(진행) · 글자까지 지금 판과 같음 · upload-pack 1줄(ⓒ) · 호출 순서 = ⓐ rc 1 → ⓑ rc 1 → ⓒ rc 0 → 조상 확인 rc 1 | 같음(회귀 고정 · r1 설계였다면 «옛 착지 줄(attempt 전 · 다른 repo 시각)» 으로 뒤집힘) |
| ㊹가 | ㊸차 와 같되 L 이 B 의 조상(B 를 L 위에 쌓은 다른 가지) | 결과 = «옛 착지 줄(attempt 전) <sha8>» · 지금 판과 같음 · upload-pack 1줄 | 같음(실측 8번) |
| ㊹나 | 정한 차이 1칸: base 가 짝 리포 대역에 로컬로 있고 원격 대역의 받지 않은 가지에도 있음 · L 은 base 의 조상 아님 · L 시각 < intent.at | 결과 = «옛 착지 줄(attempt 전 · 다른 repo 시각) <sha8>» · upload-pack 0줄 | `""`(진행) · upload-pack 1줄 = 이 칸만 판정이 바뀐다(정한 차이) |
| ㊹다 | base 가 어디에도 없는 sha(0123…4567) · 짝 리포에도 없음 | 결과·upload-pack 수가 지금 판과 같음(시각 비교 길 · 1줄) | 같음 |
| ㊹라 | PR 착지에서 `pre_attempt` 를 worktree 경로로 부름 · 그 worktree 가 루트 대역의 worktree · base 는 루트 대역에 로컬로 있음 | ⓐ rc 0 → 조상 확인 길 · 짝 리포 존재 확인 호출 0 · 루트 대역을 짝으로 세지 않는다(공통 폴더가 같다) | — |
| ㊹마 | 짝 리포 대역이 낡은 리포(`self.stale`) · base 는 그 짝에 로컬로 있음 | ⓑ rc 0 → 시각 비교 길 · upload-pack 0줄 | — |

범위 밖 입력(하드 룰 18·19·20): 줄바꿈·탭 든 리포 경로 · 권한 바꾼 .git 폴더 · 주입한 git 실패의 꼴 맞추기 · `GIT_NO_LAZY_FETCH` 를 모르는 옛 git(2.45 앞 = 값이 무시되어 지금과 같게 돈다 · 고치지 않는다).

## 구현 범위 (나노 1 · 팩 base = r2022 착지 뒤 origin/main · DA 설계 승인 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/ft2/tests/test_keeper_git_no_lazy_fetch.py(㊸가~차 · ㊹가~마 · 변이 M98~M105 · 사례표는 파일 머리 글) · 리포 대역은 legacy/1.x/harness/tests/test_landed_git_no_lazy_r1401.sh 의 꼴(bare 원격 + blob:none 클론 + 느린 upload-pack 기록)을 파이썬으로 옮긴다 · 기준판 FAIL 원문(㊸가 · ㊸나 · ㊸마 · ㊹나)을 PR 본문에 붙인다 · ㊸차 · ㊹가 · ㊹다 는 기준판에서도 PASS 다(판정값 회귀 고정)
2. 커밋 2 [fix] — G1~G6 = feature-pack/fable-team/ft2/adapters/pi/keeper_land.py(`git_local` 1개 · 착지 고리 2호출 · 옛 착지 조상 확인의 `self.git` → `self.git_local` · base 존재 확인 = G4 3단) + feature-pack/fable-team/ft2/adapters/pi/keeper_endings.py(PR 착지 조상 확인 `k.git` → `k.git_local` · G3 존재 확인) · keeper.py 손 0 · 다른 keeper_*.py 손 0 · 문서 2파일 손 0
3. 회귀 rc0(파일별 · 각 70초 상한): test_pi_keeper_land_cross_repo_r1910 · test_pi_keeper_land_pre_attempt_r1893 · test_pi_keeper_endings_r1960 · test_pi_keeper_fetch_fresh_r1963 · test_pi_keeper_noland_close_r1841 · test_pi_keeper_land_team_row_any_ref_r2029 · test_pi_keeper_slow_call_r1992 · test_settle_one_path_r2055 · r2022 가 만든 test_pi_keeper_ancestor_7s_r2022
4. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행)

변이: M98 `git_local` 이 env 를 더하지 않음 → ㊸가·㊸나·㊸마 / M99 env 를 `self.env` 에 눌러 쓰고 되돌리지 않음 → ㊸바·㊸아 / M100 `try … finally` 빼기 → ㊸사 / M101 카드 본문 `show` 도 `git_local` 로 → ㊸아(본문 못 읽음) / M102 G3 존재 확인 빼기(없는 객체의 rc 128 을 r2022 갈래로 보냄) → ㊸가(«미도달» 이 아니라 «판정 불가») / M103 base 존재 확인의 ⓑ·ⓒ 를 빼고 ⓐ rc 1 = 곧바로 시각 비교(r1 설계) → ㊸차 · ㊹가 / M104 ⓒ 도 `git_local` 로 → ㊸차 · ㊹가 / M105 짝 리포를 공통 폴더가 아니라 경로 글자로 가림 → ㊹라

## 범위 밖
- harness r1979 후보 B = ssh 연결 재사용(keeper env 한정 · launchd env 면 오빠 컨펌) · 후보 I = 반복 판정 재사용. 둘 다 새 카드다.
- 칸별 git 호출 수·초 로그 1줄(후보 I 의 앞단) = 이 카드에서 하지 않는다. 호출 셈(`tally`)과 ROUND 줄은 keeper.py 에 있고, 진행 중인 keeper 60초 카드(PR #1397 · R10 ROUND 칸)가 같은 자리를 고친다. 60초 카드 착지 뒤 후보 I 카드의 첫 커밋으로 넣는다. 이 카드의 실측은 지금 있는 SLOW-CALL 줄로 한다.
- 착지 순서 = merge-tree 로 팀장이 정한다. keeper.py 는 r2022(상수 1줄)와 keeper 60초 카드(PR #1397)가 같이 고친다. 이 카드는 keeper.py 를 고치지 않는다.
- r2022 의 rc 갈래 자체(없는 객체 rc 128 을 «판정 불가» 로 읽는 문제)를 고치는 일 = harness 몫(팀장에 알림 aifp 5873). r2022 가 그 꼴로 착지하면 이 카드의 G3 가 그 구멍을 메운다.
- fetch · ls-remote · show · grep · ls-tree 의 느림(오늘 SLOW-CALL 의 나머지 줄) · GIT_S 상한 값.

## 완료 조건
1. [ ] 나노: 커밋 1 기준판 FAIL 원문(㊸가 · ㊸나 · ㊸마 · ㊹나) · 기준판 PASS(㊸차 · ㊹가 · ㊹다)
2. [ ] 나노: 새 시험 전체 rc0 · 걸린 초
3. [ ] 나노: 변이 M98~M105 지정 반례 FAIL
4. [ ] 나노: 회귀 rc0(파일별 초)
5. [ ] 팀장: PR 착지 sha · 설치 판
6. [ ] arch: 설치 뒤 읽기 실측 = BYZ keeper 로그 ROUND 200줄 이상 구간에서 `git BYZ-Agents cat-file` · `git BYZ-Agents merge-base` SLOW-CALL 줄 수와 합 초를 기준값 «가» 와 나란히 · rc=1 · rc=128 인 SLOW-CALL 줄(없는 객체를 5초 넘게 물은 줄) 0 · 남은 줄이 있으면 원문과 함께 [ ] 로 둔다
7. [ ] arch: 판정값 그대로 = 설치 앞 1시간과 뒤 1시간에 같이 있는 work 의 판정 줄 종류(착지 · 미도달 · 판정 불가)가 같음 · 다른 work 가 있으면 원문 · «판정 불가 … cat-file rc» 줄이 설치 뒤 늘지 않음

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| G1 로컬만 보는 손 · argv 그대로 | ㊸가 · ㊸다 · M98 |
| G2 쓰는 곳 4개뿐 | ㊸아 · M101 |
| G3 없는 객체 = 없음 갈래 | ㊸가 · ㊸마 · M102 |
| G4 판정값 그대로 | ㊸나 · ㊸다 · ㊸라 · ㊸차 · ㊹가 · ㊹다 |
| G4 base 존재 확인 3단 · 짝 리포 | ㊸나 · ㊸차 · ㊹라 · ㊹마 · M103 · M104 · M105 |
| G4 R1 의도 판정 | ㊸차 · M103 · M104 |
| G4 정한 차이 1칸 | ㊹나 |
| G5 되돌림 · 이미 있는 값 | ㊸바 · ㊸사 · M99 · M100 |
| G6 새지 않음 | ㊸아 · M99 |
| G7 그대로 | ㊸자 · ㊸라 |

## 상태
- 2026-11-16 08:35 · 대기 — aifp-ft-arch-pi#22 초안(팀장 aifp 5868 · 5870 · 넘김 harness#295 aifp 5867 · 5869 · 실측 = BYZ keeper 로그 SLOW-CALL 122줄 · 읽기 명령 4개 · 구현 0) · 선행 r2022(harness 나노 일 중) · 다음 = 팀장 PR merge → DA 설계 → Issue → r2022 착지 뒤 나노 1석
- 2026-11-16 08:55 · 대기 — aifp-ft-arch-pi#23 r2(팀장 aifp 5879 · DA HOLD-DESIGN 1/3 = aifp 5878 · BYZ 313081 R1) · R1 의도 판정 = 진행(지금 값) 동결 · G4 = base 존재 확인 3단(로컬 → 짝 리포 로컬 → 지금처럼 원격) · 정한 차이 1칸(실측 3번 · 팀장 확인 칸) · r1 «알려진 차이 1줄» 지움 · ㊸나 · ㊸차 고침 · ㊹가~마 · M103~M105 더함 · G3 = r2022 판(#1401 6d47494a) 순서로 맞춤 · 실측 = A23-no-lazy-r2/probe_r2.py 8줄(2.086초) · 구현 0 · 다음 = 팀장 PR merge → DA 설계 2/3
