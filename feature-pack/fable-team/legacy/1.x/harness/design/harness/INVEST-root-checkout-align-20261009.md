# 조사 — 루트 체크아웃 정렬 (판정 578 · 읽기 전용 · 집행 0)

작성: byz-harness-master-claude#19 · 2026-10-09 · 루트 = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` (브랜치 main)

## 결론 1줄
루트 main 을 읽는 launchd 잡은 **가드 1개(`com.byz.gce-guard-check`, 매시)뿐**이라 «가드 전용 origin/main 추적 워크트리로 이전»(안 1)이 작고 되돌리기 쉽다. 루트 정렬(안 2)은 로컬 전용 246 커밋 보존이 선행이라 크다.

## ① 루트 경로로 도는 launchd 잡 (실측 · plist 파싱)
| 잡 | 루트의 «추적 코드»를 읽나 | 비고 |
|---|---|---|
| **com.byz.gce-guard-check** (3600초) | **예** — `<루트>/scripts/ops/gce-guard-check.sh` | 루트 main 이 origin 보다 18,487 뒤 → PR 1035(3f6414e070) 축 ⑧ 이 안 실림. 로컬 파일은 origin 판과 8+/21− 차이 |
| com.byz.ft-tick-cfo · -ops · -loom · -feature | 아니오 — `<루트>/.fable-team/bin-*/ft-tick.sh` (git 추적 0 · 설치물) | 루트 정렬과 무관 |
| com.byz.ft-board-publish (300초) | 아니오 — 스크립트는 `v6-realtime-live/.fable-team/bin`, 루트는 cwd·FT_ROOT(상태 폴더)만 | |
| com.hermes.byz-mbox-slack-mirror · slack-mbox-inbound · github-slack-mirror | 아니오 — `.fable-team/comm`·seats json(설치물·상태) | |
| com.byz.ft-tick · dev.byz.v6-rate-limit-resume(-once) | 워크트리(v6-realtime-live) | |
| ai.hermes.gateway(-zion) · com.byz.ft-magazine | env 에 루트 경로만 | |

## ② 로컬 전용 246 커밋 · 미커밋 2
- 246 전부 **2026-09-23 이후 정지 시점의 로컬 커밋**(merge-base `4b4641339b` · 09-01). 127 = cairn 원장(`set-note`·`set-status`·`add-task`), 나머지 대부분 원장·`design/` 문서(변경 경로 상위: design/evidence 13,156 · design/v65 4,229 · shared/prompts 902 · .cairn/plan.yaml 229). **비문서(코드 경로) 커밋 15개** — `git cherry` 기준 15개 모두 origin/main 에 같은 patch 가 이미 있음(`+` 0 · 예: comm-canonical 백업 갱신·GCE 배너 fix 류) → 코드 유실 위험 낮음. 나머지 231(원장·문서)만 origin 에 없는 로컬 전용.
- 미커밋: 추적 수정 2(`.claude/skills/byz-ops/scripts/tunnels.sh` +9/−4 · `.serena/project.yml` +42/−14 — serena 는 자동 변경 노이즈) · 비추적 `.beads/hooks/*.old`·`.cairn/.lock`.
- 위험: 원장·문서 231 커밋(`.cairn/plan.yaml` 등)은 **origin 에 없음** — 정렬 때 그냥 reset 하면 소실.

## ③ 안 2개 + 되돌림
**안 1 — 가드를 origin/main 추적 워크트리로 이전 (권고)**
1. `git worktree add .worktrees/ops-guard origin/main`(detached) — 심링크 불필요(가드는 gcloud·기존 인증만 사용 — 확인 필요 1: 스크립트가 source 하는 루트 상대 경로 유무).
2. `com.byz.gce-guard-check.plist` 의 ProgramArguments 를 `…/.worktrees/ops-guard/scripts/ops/gce-guard-check.sh` 로 · `WorkingDirectory` 동일 · **EnvironmentVariables 에 `GCE_GUARD_OUT=<루트>/state/gce-op-model/gce-guard-check.last.log`** 추가(상태 연속성) · `launchctl bootout/bootstrap`.
3. 이후 PR 랜딩마다 그 워크트리를 `git checkout --detach origin/main`(훅/틱 1줄 — 갱신 주체 정해야 함).
- 되돌림: plist 를 원경로로 복원 + bootstrap · 워크트리 삭제는 HIL.
- 영향: 루트 main 은 그대로(정지) — 다른 사용처(사람이 루트에서 여는 스크립트)는 여전히 옛판.

**안 2 — 루트 main 을 origin/main 에 정렬**
1. 선행 보존: 현재 main 을 `backup/root-main-20230923-stop` 류 브랜치로 push 또는 `git bundle` — 246 커밋·원장 보존(HIL: 브랜치 생성은 비파괴).
2. 미커밋 2 처리(tunnels.sh 변경이 origin 에 이미 있는지 대조 → 없으면 별 브랜치).
3. `git reset --hard origin/main` 또는 신규 clone — **파괴적 · 09시 오빠 큐**.
- 되돌림: 보존 브랜치/번들에서 복원(`git reset --hard backup/…`) — 보존 전에는 되돌림 불가.
- 영향: 루트를 읽는 모든 사용처가 한 번에 최신(가드 포함) · `.cairn` 원장 상태는 보존본에서 별도 이관 필요.

## 확인 필요 2건 (집행 전)
1. `gce-guard-check.sh` 가 같은 폴더·루트 상대 경로의 다른 파일을 source 하는지→ **확인됨**: source 는 없으나 `ROOT=$(git rev-parse --show-toplevel)`(스크립트 폴더 기준)이라 **워크트리로 옮기면 상태 경로가 `<워크트리>/state/gce-op-model/`로 바뀐다**(BREACH.md·BREACH.ledger·.runkeys·last.log). 세션 시작 배너(루트 BREACH.md)와 어긋나므로 안 1 은 `GCE_GUARD_OUT=<루트>/state/gce-op-model/gce-guard-check.last.log`(스크립트가 이 env 를 지원 — OUT·ledger·breach 가 그 폴더로 따라감)을 plist EnvironmentVariables 에 같이 넣어야 한다. `_LAUNCHD_LOG` 는 `$ROOT` 기준이라 별도 확인.
2. ~~비문서 15 커밋의 origin 반영~~ → 확인됨(위 ②).

집행 0: 루트 브랜치·launchd 변경 없음.
