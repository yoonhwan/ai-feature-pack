# r897 r3 — 빠른 길(fast) 호출 나무 전수 rc 검사 표

근거: DA⑥ r2 판정 HOLD 1 — `evidence/r897-da/REWORK-r897-r3.md` (반례 1 = `judged()` 안 `ct="$(bounded … git log …)"` 의 종료코드 미검사 → 숫자를 찍고 rc128 이면 «판정 끝» → 빠른 길이 24시간 전에 삭제).
규칙: **빠른 길이 부르는 호출의 결과(출력·판정)는 rc0 일 때만 쓴다** — 못 읽음 = 지우기 0(덜 지우는 쪽).

파일: `feature-pack/fable-team/harness/bin/ft-scratch-repo.sh` (줄 번호 = r10.4 판 · `warn_many` 도 같은 `judged()` 를 부른다)

## 1. `--sweep` → `orphans()` → `fast()` — 빠른 길 입구

| # | 함수:줄 | 호출 | 결과를 어떻게 쓰나 | rc 검사 |
|---|---|---|---|---|
| 1 | `orphans:207` | `lsof -w -d cwd -Fpcn` (전체 공통 · 빠른 길 밖) | cwd 보유 판정 | **있음(기존)** — 실패/0줄 = 이번 정리 전체 삭제 0 (r548) |
| 2 | `orphans:212` | `tmux_sessions()` (전체 공통) | 주인 생존 판정 | **있음(기존)** — 실패 = 등록 사본 판정 생략 · 삭제 0 (r444) |
| 3 | `orphans:216` | `grep -Fxq -- "$o"` (주인 대조) | 주인 없음 판정 | **있음(기존 r10)** — rc2(대조 실패) = 지우기 0 |
| 4 | `orphans:224` | `fast "$p"` | 빠른 길 여부 | **있음** — rc0 만 후보(그 밖 = 24시간 규칙으로 후퇴) |
| 5 | `fast:239-241` | `printf`/`cut`(이름 파싱) | 이름꼴 4조건 | 내장·cut — 외부 상태 읽기 아님(실패 = 빈 값 = 조건 불일치 = 후보 0) |
| 6 | `fast:244` | `sha="$(git -C "$p" rev-parse HEAD)"` | HEAD 확인 | **있음** — `|| return 1` |
| 7 | `fast:246` | `git -C "$p" symbolic-ref -q HEAD` | detached 판정 | **있음(r10.3)** — rc=1 «만» detached · rc0·rc≥2 = 후보 0 |
| 8 | `fast:248` | `judged "$p"` | 판정 끝 표식 | **있음** — rc0 만 참 |

## 2. `judged()` 내부 — 이번에 rc 검사를 «전수»로 채운 곳

| # | 함수:줄 | 호출 | 이전 | r10.4 |
|---|---|---|---|---|
| 9 | `judged:131` | `sha="$(git -C "$1" rev-parse HEAD)"` | `|| return 1` | **변경 없음(있음)** |
| 10 | `judged:132` | `git -C "$ROOT" rev-parse -q --verify origin/main` | rc 무시 → 실패 시 `main` 으로 폴백 | **변경 없음** — 폴백값도 «ref 이름» 일 뿐 출력을 쓰지 않고, 바로 아래 `judged:133`(git-dir)·`judged:138`(grep)이 각각 실패를 잡는다(보수) |
| 11 | `judged:133` | `git -C "$ROOT" rev-parse --git-dir` | `|| return 1` | **변경 없음(있음)** |
| 12 | `judged:135-137` | `git -C "$ROOT" merge-base --is-ancestor` | `&& return 0` (rc≥2 도 «조상 아님» 과 구분 없음) | **추가** — rc0 만 «착지» · rc1 = 다음 증거 · **rc≥2 = 못 읽음 → 판정 안 끝남(rc1) + WARN 1줄** |
| 13 | `judged:138-143` | `out="$(bounded … git grep -F -l …)"` | case 0/1/124/그 밖 | **변경 없음(있음)** — 그 밖 = WARN + 판정 안 끝남 |
| 14 | `judged:148-150` | `ct="$(bounded … git log -1 --format=%ct …)"` | **rc 미검사** — 빈 값·비숫자만 걸렀다(숫자 + rc128 = «판정 끝») | **추가(반례 1)** — `rc≠0 = 못 읽음 → 판정 안 끝남(rc1) + WARN 1줄` · 그 뒤에도 숫자 검사 유지 |
| 15 | `judged:152` | `date +%s`(나이 비교) | 내장 clock | 해당 없음 |
| 16 | `warn_many:166` | `judged "$p"` (같은 judged 를 부르는 기존 호출자) | «판정 끝난» 사본 고르기 | **있음** — rc0 만 채택 · 새 뜻(실패 = 판정 안 끝남) = 덜 지우는 쪽 |

## 3. 왜 14번이 «지우는 길» 이었나 (반례 그대로)

`fast` → `judged` → `git log` 가 (a)숫자를 찍고 (b)rc128(예: 트리·객체 못 읽음·인덱스 잠금)이면, 기준판은 그 숫자를 «마지막 커밋 시각» 으로 삼아 `now - oldest ≥ AGE` 를 참으로 만들고 → `judged` rc0 → `fast` rc0 → 후보 → 재확인 통과 시 삭제. 즉 **못 읽음이 «판정 끝» 으로 뒤집혀 24시간 문턱을 건너뛰었다**.

r10.4 는 그 숫자를 rc0 일 때만 쓴다: rc≠0 → WARN `git log 실패(rc=…) · 판정 안 끝남` + rc1 → `fast` rc1 → 24시간 규칙으로 후퇴(등록 24시간 지난 사본만 후보).

## 4. 기존 호출자 회귀 (DA 지시 2)

`judged()` 의 새 뜻(실패 = 판정 안 끝남)은 `warn_many`(judged 사본 고르기)·`--judged` 명령에도 그대로 적용된다 — 둘 다 «덜 지우는 쪽» 이다.
실측: 기존 시험 4종 ALL PASS (`evidence/r897/after-green-r3.txt`). 단 `test_scratch_judged_r645.sh` 의 사본 대역이 **ROOT 저장소 밖의 독립 `git init` 저장소**여서 merge-base 가 rc128(«객체 없음»)로 떨어졌다 — 실사본은 언제나 어떤 저장소의 worktree 이므로 대역을 실사본과 같은 꼴(`git worktree add --detach` + 그 안 커밋)로 고쳤다(`mk_copy` 1곳). 판정 로직은 손대지 않았다.

## 5. 시험 ⓦ (새 칸)

`tests/test_scratch_repo_r897_r10.sh` §ⓦ — 판정 기준 트리에 «사본 sha8 이 적힌 옛(2020) design 문서» 를 만들어 `judged` 가 merge-base 로 끝지 못하고 grep→log 경로를 지나게 한 뒤:

| 칸 | 주입 | 기대 |
|---|---|---|
| 대조 | 없음 | 삭제됨(정상 판정 — 「지우기 0」 이 다른 이유가 아님을 보인다) |
| revparse | 출력 있음 + rc128 | 지우기 0 |
| gitdir | 출력 있음 + rc128 | 지우기 0 |
| mergebase | rc128 | 지우기 0 (고치기 전 판 = **지움** · `before-red-r3.txt`) |
| grep | 출력 있음 + rc128 | 지우기 0 |
| log | **숫자 출력 + rc128** | 지우기 0 (고치기 전 판 = **지움** · 반례 1 재현) |

변이 9(merge-base rc 검사 끔)·변이 10(git log rc 검사 끔) → ⓦ 빨강(`mutants-r3.txt`).
