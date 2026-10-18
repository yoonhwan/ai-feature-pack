# RESULT — gh-guard-scope-main-prcreate (2026-10-07)

- 좌석: byz-harness-nano-gh-guard-scope-main-prcreate#0 · 브랜치 `nano/gh-guard-scope-main-prcreate` · 구현 커밋 `d1182064ea` · push 안 함
- 골좌표: 하네스 GOAL 축 6-b / 닫는 증거 «REQUEST-LEDGER 행 + Issue 코멘트 + 반영 sha» — 이 단위의 반영 sha = `d1182064ea`
- `bash tests/harness/test_gh_as_tank.sh` → **PASS 148 · fail=0** · 훅·래퍼·시험 `bash -n` OK · 구현 변경 파일 = 훅·래퍼·시험 3개(실제 GitHub 호출 0 — 가짜 gh · 임시 git 리포)

## 실측 표 — 기대 rc = 실제 rc (시험이 `[ rc == 기대 ]` 로 단언, 전부 일치)

### 리포 범위 (훅)
| 케이스 | 기대 rc | 실제 rc |
|---|---|---|
| ⓐ cwd=SWS · `gh issue comment 5` | 2 | 2 |
| ⓑ cwd=다른 owner · 같은 명령 | 0 | 0 |
| ⓒ cwd=git 아님 / cwd 키 없음 | 0 | 0 |
| ⓓ cwd 다른 owner + `-R SecondWindStudio/byz-agents` | 2 | 2 |
| ⓓ' owner 대소문자 무시 (`secondwindstudio`) | 2 | 2 |
| ⓔ cwd SWS + `-R yoonhwan/x` | 0 | 0 |
| ⓕ `GH_REPO=SecondWindStudio/byz-agents gh issue comment` (cwd 다른 owner) | 2 | 2 |
| ⓖ `gh api repos/yoonhwan/x/issues/1/comments -f body=y` (cwd SWS) | 0 | 0 |
| ⓖ' `gh api repos/SecondWindStudio/…/issues/1/comments` (cwd 다른 owner) | 2 | 2 |
| `gh pr comment 7 --repo yoonhwan/x` (cwd SWS) | 0 | 0 |

### main 보호 (cwd=SWS) — 차단 메시지 「main 삭제·재작성(강제 push·리베이스 후 강제)은 금지 — 오빠 10-07」 포함까지 단언
| 케이스 | 기대 rc | 실제 rc |
|---|---|---|
| `git push origin :main` · `+main` · `+HEAD:main` | 2 | 2 |
| `git push origin --delete main` · `-d refs/heads/main` | 2 | 2 |
| `git push --mirror origin` · `--prune origin` | 2 | 2 |
| `git push origin main -f` (확장 1건 — 강제 + main 대상) | 2 | 2 |
| `git -C <SWS> push origin :refs/heads/main` · 원격 URL(SWS) `+main` | 2 | 2 |
| `gh api -X DELETE …/git/refs/heads/main` · `--method PATCH … -F force=true` · `-X DELETE …/branches/main/protection` | 2 | 2 |
| `gh repo delete SecondWindStudio/byz-agents --yes` | 2 | 2 |
| `git push origin main` · `HEAD:main` · 인자 없는 `git push` | 0 | 0 |
| `git push origin --delete feat/x` · `:feat/x` · `+feat/x` · `-u origin feat/main` | 0 | 0 |
| `gh api -X DELETE …/git/refs/heads/feat/x` · `-X PATCH …/branches/feature` · GET `…/branches/main` | 0 | 0 |
| cwd 다른 owner · `git push origin :main` / `--delete main` | 0 | 0 |
| cwd git 아님 · `git push origin :main` (판정 불가) | 0 | 0 |
| cwd 다른 owner + 원격 URL(SWS) `:main` | 2 | 2 |
| 원격 이름 `upstream`(다른 owner) `:main` · `gh repo delete yoonhwan/x` · `git status` | 0 | 0 |

### 래퍼 pr-create (가짜 gh)
| 케이스 | 기대 rc | 실제 rc | PR 생성 호출 |
|---|---|---|---|
| dry-run `--base/--head` 생략 · `--base dev` 도 출력만 | 0 | 0 | 0 |
| `--apply --base dev` | 2 | 2 | 0 |
| `--apply` head 없음 | 2 | 2 | 0 |
| `--apply` base 없음 | 2 | 2 | 0 |
| 원격 head 조회 실패 | 1 | 1 | 0 |
| 작성자 ≠ byz-tank (URL 출력) | 1 | 1 | 1(생성 뒤 검사) |
| 성공 (Tank 토큰 · 토큰 값 미출력 · 생성 전 branches 조회) | 0 | 0 | 1 |

## 설계 메모
- 확장 1건(master 수용): `-f`/`--force`/`--force-with-lease` + main 대상 refspec 도 main 보호로 차단. 제거하려면 `gh-issue-author-guard.sh` `push_main_reason` 의 `FORCE_FLAGS` 조건 한 줄.
- 기존 케이스의 `-R o/r` · `repos/o/r` 는 `SecondWindStudio/byz-agents` 로 바꿨다(리포 범위가 생겨 `o` 는 통과가 되므로 원 의도 유지).
- 범위 밖(손대지 않음): `~/.claude` 홈 설치(ops) · `block-destructive.sh` · PR 쓰기 명령 확장 · 실제 GitHub 호출.
- 관측: 이 단위 중 `block-destructive.sh` 가 echo 문구 속 push 글자에 오탐 1회(master 가 오탐 판정 · #58524) — 훅 정밀화는 하네스 요청 후보.
