# PLAN — byzs-mac-mini 키트 0.4 설치 (arch#8 판단 · 2026-10-08 · master#11 #60780)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골 축: C(전 환경 설치) + 원문 5(머신 독립 배분의 첫 걸음) · 닫는 증거 = RELEASE-0.4.md 「반영됨 byzs-mac-mini <kit_sha>」 행.

## 결론
**수정 승인.** 5단계 그대로 가되 «복사 원본»만 바꾼다: 워크트리 키트 폴더가 아니라 **랜딩된 sha 의 `git archive`** 로 만든 깨끗한 묶음을 쓴다.

## 이유 3줄
1. 워크트리 키트 폴더에는 git 밖 파일이 섞여 있다 — 실측 `find scripts/harness-install/fable-team -type f` = 107 · `git ls-files` = 105 · 차이 = `bin/__pycache__/*.pyc` 2개. install.sh 는 `find bin templates -type f` 전부를 복사·해시하므로(install.sh:34) scp -r 원본이면 .pyc 가 원격에 가고 kit_sha 가 «랜딩본과 다른 값»이 된다 → 머신끼리 sha 를 대조할 수 없다.
2. `git archive <sha>` 묶음은 추적 파일만 담아 어느 머신에서 풀어도 kit_sha 가 같다 — RELEASE 의 「kit_sha」 칸이 처음으로 «머신 간 비교 가능한 값»이 된다(원문 5).
3. 나머지(설치 위치·되돌림·좌석 0·훅/틱 미설치)는 master 안 그대로가 맞다 — install.sh 는 DEST 복사만 한다(install.sh:6·30).

## 수정된 5단계
1. 로컬: `git -C <리포> archive --format=tar --prefix=fable-team-kit/ origin/main scripts/harness-install/fable-team | tar -x -C <scratch>` → `bash <scratch>/fable-team-kit/scripts/harness-install/fable-team/install.sh --machine byzs-mac-mini`(dry-run) 의 `files=104 kit_sha=<값>` 기록(install.sh 자신은 목록 밖이라 추적 105 − 1 = 104). origin/main sha 도 같이 적는다. arch 사전 실측(origin/main 28466c89b8): `files=104 kit_sha=b8549a53585e` — 그 뒤 키트 랜딩(R15T 등)이 있으면 값이 바뀐다.
2. 같은 묶음을 tar 1개로 `scp` → 원격 `~/.fable-team-kit-0.4-tmp/` 에 풀기(신규 디렉터리).
3. 원격: `bash ~/.fable-team-kit-0.4-tmp/…/install.sh --machine byzs-mac-mini --apply` → 출력의 kit_sha 가 1번 값과 같아야 한다(다르면 중단).
4. 확인: 원격 `diff -rq ~/.fable-team/harness <풀린 키트>` 0줄 · 원격 `/bin/bash -n` 전부 OK · 훅 줄은 `absent`(원격에 ~/.claude 훅 없음 — 정상, 이번 범위 아님).
5. 되돌림: 원격 신규 두 디렉터리(`~/.fable-team`·`~/.fable-team-kit-0.4-tmp`) 삭제 — 실행 시점에 HIL(master 안 그대로). tmp 는 설치 원본이라 지우지 않고 둔다(재검증용).

## bash 3.2 위험 (질문 답)
- **install.sh 자체: 위험 없음** — `+=`(3.1+) · `<<<` · `$'\n'` · `set -o pipefail` 전부 3.2 지원. 실측: 이 Mac `/bin/bash` 3.2.57 로 키트 bash 스크립트 87개 `bash -n` 전부 통과(FAIL 0). bash 4 전용 구문 grep(`declare -A`·`mapfile`·`${x,,}`·`&>>`·`|&`) = 코드 0건(걸린 2곳은 python 문자열 안).
- **운용 시 위험(이번 설치엔 무관 · 좌석을 돌리기 전 별건)**: 키트 52개가 `#!/usr/bin/env bash` 라 이 Mac 에선 homebrew bash 5 로, mac-mini 에선 3.2 로 돈다. `bash -n` 은 문법만 본다 — 3.2 런타임 차이(대표: `set -u` 아래 빈 배열 `"${a[@]}"` = bash 4.4 미만 unbound 오류)는 실행해야 드러난다. mac-mini 에서 좌석을 돌리기 «전»에 ①homebrew bash 설치 여부 결정 또는 ②3.2 런타임 시험 묶음 — 원문 5(머신 독립 운용) 단계의 선행 조건으로 적는다.

## RELEASE-0.4 행 (설치 뒤 master 기입 꼴)
`| byzs-mac-mini | 반영됨 <날짜> — 키트만(훅·틱·좌석 0) · git archive origin/main@<sha12> · files=104 · diff -rq 0줄 · /bin/bash 3.2 -n 전부 OK · 백업 없음(신규 설치) · 되돌림 = 신규 두 디렉터리 삭제(HIL) | kit_sha <값> |`
