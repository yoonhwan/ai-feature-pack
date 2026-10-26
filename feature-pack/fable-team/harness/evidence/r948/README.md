# r948 증거 — 카드 리포 착지 카드의 라이브 전수(--all) 대조 + 거짓 PENDING 3종

카드: BYZ `design/harness/indices/진행/r948-index-move-install-all-project-is-card-repo.md` · 좌석 byz-harness-nano-r948-index-move-install-all-project-is-c#0 · base 팩 origin/main 66340101

## 고친 곳 (짝 사본 bin ↔ kit/fable-team/bin cmp0)

| # | 파일 | 무엇 |
|---|---|---|
| 1 | ft-index-move-install.sh | 카드 리포 착지 갈래 `CARG=(--all --project <카드 리포 공용 루트>)` · 루트 = `git rev-parse --path-format=absolute --git-common-dir` 의 부모(ft_git_capped 7초 · 실패 = REJECT) |
| 4 | ft_live_install_check.py `live_path` | 지도 패턴 접두를 폴더(마지막 /)까지만 자른다 — `fable-team/templates/scope-*.tsv` 가 `classes-pack.tsv`·`ddl-record.tsv` 로 풀리던 오류 |
| 5 | ft_live_install_check.py `plist_items` → `loaded_instances`·`label_items` | Label `접두-__X__` = 적재 목록의 `접두-<숫자>` 인스턴스 전부 대조 · 0개 = `NOTLOADED 접두<숫자>` · `launchctl list` 실패 = ERROR |
| 6 | kit/LIVE-MAP.tsv | `launchd/com.byz.ft-head-lag.plist.template` skip 행 |

## 6 판정 (실측 2026-10-26)

- (a) kit 에 두 템플릿은 있다(kit/launchd/). 그러나 install.sh `launchd_sync` 는 «설치된 것만» 다시 렌더하고 새로 깔지 않는다(r538 · test_install_launchd_render.sh 가 `SKIP launchd com.byz.ft-head-lag (설치 안 됨` 을 고정). = install.sh 설치 대상 아님.
- (b) ft-head-lag.sh 는 ft-news-tick.sh:44(`--summary`)·ft-merge-land.sh:111(`--event`)가 직접 부른다 — `.fable-team/state/head-lag.json` 10-26 17:46 갱신. → **기대 목록에서 뺌**(skip 행).
- ft-idle-wake.sh 는 launchd 말고 부르는 곳이 없다(kit bin·slack-mirror·hooks · LaunchAgents·crontab 0). `.fable-team/state/idle-wake.log` 마지막 줄 2026-10-25T07:12:26 · plist 없음. → 거짓 PENDING 아님 = **실제 어긋남이라 NOTLOADED 그대로**(master 몫: 다시 설치하거나 은퇴 결정).

## 라이브 대조 (읽기 전용 · FT_BIN=live/1.1.251 · `--all --project <BYZ 루트>`)

| 판 | 결과 |
|---|---|
| live 1.1.251(옛) | PENDING n=5 — MISSING scope-classes-pack·scope-ddl-record · NOTLOADED ft-head-lag·ft-idle-wake·iap-tunnel |
| 이 가지(지도 = origin/main) | PENDING n=2 — NOTLOADED ft-head-lag·ft-idle-wake |
| 이 가지 + `--map` 이 가지 지도 | PENDING n=1 — NOTLOADED com.byz.ft-idle-wake |

STALE-COPY 3 은 이 시각 실측에 안 나왔다(카드 밖 · planner 통지 몫).

## 시험

- `test_r948_live_all_project.sh` — ⓐⓑⓒ(게이트 인자) · ⓕ(이름 그대로) · ⓖ(접두-숫자 2개 LOADED · 0개 NOTLOADED · 목록 실패 ERROR) · ⓗ(head-lag skip · idle-wake NOTLOADED 유지) · 변이 5(project-off→ⓐ · worktree-path→ⓒ · name-strip→ⓕ · exact-label→ⓖ · skip 행 삭제→ⓗ) = 13 PASS · 원문 `test_r948_live_all_project.sh.txt`
- 인접: `adjacent.txt`
