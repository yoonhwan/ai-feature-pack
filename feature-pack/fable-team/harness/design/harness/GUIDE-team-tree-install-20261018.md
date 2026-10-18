# 팀장 1장 — 팀 폴더 표준(트리 r2) 설치·착지 절차 (하네스 arch#82 · 2026-10-18 · 오빠 지시 desk #107777 «각 팀장들 하네스랑 통신하고 완전 설치 랜딩 템플릿 받아 설치 업데이트»)

골 원문(하네스): 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골좌표: A6 골 5 «전팀 지침과 프로젝트 폴더 기준 재기동» — 오빠가 10-17 데스크에서 컨펌한 팀 폴더 트리 r2 를 ★모든 팀이 자기 폴더에 실제로 깐다★. 도구는 이미 main 에 있고(r318a · 51f9d81b90) 라이브에 설치돼 있다 — 팀장은 아래 번호대로만 치면 된다.

## 0. 이 한 장이 주는 것

- 팀 폴더 모양(트리 r2): `design/<팀>/` 아래 `README.md` · `GOAL-<팀>.md` · `GUIDE-<팀>.md` · `STATE.md` · `plans/` · `indices/{inbox,대기,진행,완성}/` · `orders/` · `reviews/` · `evidence/` · `closeout/` · `archive/`
- 도구 2개(라이브 경로 = `<루트>/.fable-team/bin/`): `ft-team-scaffold.sh <팀>`(없는 칸만 만든다 · 있는 파일은 절대 안 건드림 · 두 번 쳐도 같다) · `ft-team-map-lint.sh <팀>`(README 의 «파일 지도» 표와 실제 파일을 대조)
- 팀 명단 정본 `design/TEAMS.md` · 좌석 구성 정본 `design/TEAMSET.md` · 팀 설정 정본 = 명부 `.fable-team/seats-<팀>.json` 의 `_doc` · `_tree_version` · `_tree`
- 루트 = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` · 아래 명령은 전부 ★자기 팀 워크트리★에서 친다(루트에서 치지 않는다 · 착지는 자기 브랜치 → 자기 팀 착지 경로).

## 1. 팀장이 치는 순서 (번호대로 · 한 단계씩 결과 확인)

1. **내 팀이 명단에 있나 본다.**
   ```
   grep -n "design/<팀>/" <워크트리>/design/TEAMS.md
   ```
   한 줄 나오면 2 로. 안 나오면 `design/TEAMS.md` 표 끝에 한 줄 추가(형식은 바로 위 행과 같게 · `| <팀> | \`design/<팀>/\` | byz-<팀>-master-claude | 현역 |`) 하고 그 변경을 같은 커밋에 넣는다. ★v65 는 폴더가 `design/v65/` · 명부가 `seats.json`★ 이라 행을 그렇게 적는다.
   새 팀이면 `design/TEAMSET.md` 표 2 에도 행 1줄을 넣는다(`| <팀> | 3 | 0 | 없음 |` — 순서 = 나노 상한 · tester 허용 수 · arch 상시 여부 · 값은 팀 master 가 정한다). TEAMS.md 에만 있고 TEAMSET 에 없으면 착지 뒤 검사가 ERROR 다. 확인: `bash <루트>/scripts/fable-team-bin/ft-team-upgrade.sh --check-teams` → `OK teams=<N>`.

2. **미리 보기(쓰기 0).**
   ```
   bash <루트>/.fable-team/bin/ft-team-scaffold.sh --dry-run <팀>
   ```
   `WOULD-CREATE design/<팀>/…` 줄들 + `OK dry-run would-create=N`. `REJECT` 가 나오면 그 한 줄이 이유다(명단 없음 → 1 로 · 팀 폴더가 심볼릭 링크 → 하네스에 쪽지). 이미 있는 파일은 목록에 안 나온다 — 정상.

3. **실제로 만든다.**
   ```
   bash <루트>/.fable-team/bin/ft-team-scaffold.sh <팀>
   ```
   `CREATE …` + `OK created=N`. 2 의 N 과 같아야 한다. 틀(GOAL·GUIDE·STATE·README)은 자리표시만 들어 있다 — 내용은 4·5 에서 채운다.

4. **골 파일을 채운다 — `design/<팀>/GOAL-<팀>.md`.** 팀 골 «원문» 만 복붙(오빠 승인 문장 · 요약 금지 · 진행 상태는 쓰지 않는다 · 수정은 오빠 승인 때만). 팀 골이 아직 글로 없으면 planner 원장(`design/planner/PLAN-oppa-ledger.md`)의 그 팀 줄을 그대로 옮기고 «출처: planner 원장 <날짜>» 1줄.

5. **상태·지침을 채운다.** `STATE.md` = 재개용 요약 1장(지금 하는 단위 · 열린 카드 폴더 링크 · 좌석 정본은 명부를 가리키기만) · `GUIDE-<팀>.md` = 이 팀만의 규칙(전역·프로젝트 CLAUDE.md 는 링크만 · 복사 금지). 비워 두면 안 되고 «없음 — <이유>» 라도 쓴다.

6. **바닥에 흩어진 파일을 지도에 올리거나 칸으로 옮긴다.**
   ```
   bash <루트>/.fable-team/bin/ft-team-map-lint.sh <팀>
   ```
   `ERR`(지도에 있는데 파일 없음) 은 0 이어야 한다. `WARN`(지도에 없는 바닥 파일) 은 정리 후보 — ★이번 착지에서는 옮기지 않는다★(이동은 다음 단계 구조 커밋 · 하네스 r318b 꼴). 도구가 경로를 박아 쓰는 현역 원장(요청 원장·랜딩 원장 등)은 README «파일 지도» 표에 «현역 원장» 으로 한 줄 등록하면 WARN 에서 빠진다. ★지도 표의 첫 칸은 백틱으로 감싼 경로(`` `STATE.md` ``)로 적어야 인식된다★ — 백틱 없이 적은 행은 «지도 밖 바닥 파일» 로 센다.

7. **명부 설정 3칸을 채운다 — `.fable-team/seats-<팀>.json`(v65 는 `seats.json`).** 파일 맨 위 메타에 다음 3키(이미 있으면 값만 확인):
   - `"_doc"`: 이 팀이 뭘 하는 팀인지 1~2문장
   - `"_tree_version"`: `"1.0.0"` (팀 폴더 틀 버전 · 명부 자체 `_version` 과 별개 · 다음 틀 개정 때 하네스가 일괄 올린다 — R368)
   - `"_tree"`: 재개 때 먼저 여는 파일 1개 경로 — 기본 `design/<팀>/STATE.md`
   JSON 이 깨지지 않았는지: `python3 -c 'import json;json.load(open(".fable-team/seats-<팀>.json"))'` 가 조용히 끝나면 OK. ★명부는 좌석 도구가 읽는 파일이라 이 3키 밖은 손대지 않는다.★

8. **구조 커밋 1개로 묶어 착지한다(Tidy First · 행위 변경 0).**
   ```
   git -C <워크트리> add design/<팀> design/TEAMS.md design/TEAMSET.md
   git -C <워크트리> diff --cached --stat
   git -C <워크트리> commit -m "[structure] <팀> 팀 폴더 표준(트리 r2) 적용 — scaffold created=N · TEAMS.md·TEAMSET 행"
   ```
   ★명부(`.fable-team/seats-<팀>.json`)는 gitignore(`.fable-team/` · 공용 루트의 라이브 파일)라 `git add` 하면 fatal 이다 — 커밋에 넣지 않는다.★ 7 의 3키 도장은 라이브 명부에 직접 쓴 것으로 끝이고(`ft-team-upgrade.sh <팀>` 이 `_tree_version` 을 찍는다), 커밋에는 안 들어간다. `design/TEAMSET.md` 는 새 팀일 때만 add 한다(기존 팀이면 변경 0).
   `--stat` 에 ★기존 파일의 수정 줄이 0★ 이어야 한다(새 파일 추가 + TEAMS.md·TEAMSET 행 1줄씩만). 다른 작업 변경과 섞지 않는다 — 섞였으면 커밋 전에 뺀다. push·main 착지는 팀의 평소 착지 경로(planner «[착지 차례]» 뒤) 그대로.

9. **하네스에 완료 1통(mbox).** 수신자 = 하네스 명부 `.fable-team/seats-harness.json` 의 `_master` 현역(승계로 번호가 바뀐다 · `ft-harness-info.sh seats` 로 확인) · 내용 = `[팀 폴더 표준 적용 · <팀>] 커밋 <sha10> · created=N · map-lint ERR=0 WARN=M · 명부 3키 OK`. 하네스는 이 보고로 전 팀 적용표를 채우고, 다음 틀 개정은 명부 `_tree_version` 으로 일괄 패치한다(`ft-team-upgrade.sh --all` · R368 · main 0d94a216c1).

## 2. 자주 걸리는 것 (한 줄씩)

- `REJECT <팀> 은 design/TEAMS.md 명단에 없는 팀이다` → 1 번. 명단이 먼저다.
- `REJECT 팀 폴더가 심볼릭 링크` → 폴더가 링크면 틀을 안 만든다 — 하네스 master 에 쪽지(링크를 실제 폴더로 바꾸는 건 구조 커밋 별건).
- `SKIP … 실제 위치가 design/<팀>/ 밖(링크)` → 그 하위 칸이 링크라 건너뜀 — 그대로 두고 쪽지에 적는다.
- 틀 파일이 이미 있어 `created=0` → 정상. 4·5·7 만 하면 된다.
- 바닥 파일이 수백 개(WARN 많음) → 이번 커밋에서 옮기지 않는다. «이동 구조 커밋» 은 다음 단계(하네스 r318b 가 선례).
- 이 1장 밖의 질문(틀 내용 바꾸고 싶다 · 칸을 더 두고 싶다) → 하네스 요청 원장 행(개선요청) — 임의로 틀을 바꾸지 않는다.

- 새 팀을 «처음부터 끝까지» 친 실제 출력(scaffold created=14 · 명부 3키 · upgrade STAMP/SKIP · check-teams · map-lint · 커밋)은 하네스 도그푸딩 카드 `design/harness/indices/완성/r373-harness-dogfood-new-team-landing-scenario.md` «시나리오 기록» 절에 원문으로 있다 — 막히면 그 절과 대조한다(R373 · 시험 팀 zz-dogfood).

## 3. 정본 (이 장은 복사본이다 — 어긋나면 아래가 이긴다)

- 트리 r2 오빠 컨펌: `design/harness/SLACK-r318-tree-r2-20261017.md` · 설계 `design/harness/DESIGN-r318-team-folder-standard-20261017.md` · DA `design/harness/DA-r318-team-root-20261017.md`
- 도구 추적본: `scripts/fable-team-bin/ft-team-scaffold.sh` · `ft-team-map-lint.sh` · 틀 `scripts/harness-install/fable-team/templates/team/`
- 명단·구성: `design/TEAMS.md` · `design/TEAMSET.md`(메타 키 `_doc` `_tree_version` `_tree` 는 표 1 아래 «명부 메타 키» 줄)
- 후속: R368 ★착지 완료 main 0d94a216c1★(전 팀 일괄 패치 도구 `ft-team-upgrade.sh [--all|<팀>]` · TEAMS↔TEAMSET 일치 검사 `--check-teams` · 13팀 명부 `_tree_version` 1.0.0 STAMP 됨 — 카드 `design/harness/indices/완성/r368-*`) · R369(승계·부팅 본문에 팀 정본 목록 강제 — 카드 `design/harness/indices/대기/r369-*`)
