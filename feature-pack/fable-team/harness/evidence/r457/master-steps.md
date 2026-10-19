# r457 master-steps — plist 갱신은 git 공용 루트 설치에서만 (집행 순서 · master)

카드 `design/harness/indices/진행/r457-install-plist-sync-only-at-git-common-root.md` · 나노 byz-harness-nano-r457-install-plist-sync-only-at-git-comm#0

## 가지 1
| 리포 | 가지 | 내용 |
|---|---|---|
| ai-feature-pack | `nano/r457-install-plist-sync-only-at-git-comm` (워크트리 `.worktrees/r457-plist-common-root` · base origin/main fec5d3b3) | `harness/install.sh` 공용 루트 판정 + plist_sync 첫 줄 SKIP · `ft_plist_env.py` render 공용 루트 검사(bin·kit 짝) · `ft_live_install_check.py` `plist_root` + plist-env 대조·HINT 루트(bin·kit 짝) · 시험 r457ⓐ~ⓔ · CHANGES 1절 |
| BYZ-Agents | 같은 이름 가지 | 커밋 0 |

## 순서
1. 팩 PR → main 착지(push·PR·`ft-merge-land` = master). 착지 전 `bash feature-pack/fable-team/harness/tests/test_live_install_check_plist_env.sh` rc0(32 PASS).
2. 설치: `bash feature-pack/fable-team/harness/install.sh --apply --project <BYZ 공용 루트>` → `OK plist-env com.hermes.byz-mbox-slack-mirror`(plist 변경 0) · LIVE_BIN cmp0(`cmp <팩>/harness/kit/fable-team/bin/ft_plist_env.py <LIVE_BIN>/ft_plist_env.py` · `ft_live_install_check.py` 같음).
3. 실사건 1(설치 뒤): `cksum ~/Library/LaunchAgents/com.hermes.byz-mbox-slack-mirror.plist` → `bash <팩>/harness/install.sh --apply --project <BYZ 공용 루트>/.worktrees/v6-realtime-live` 1회 → 출력에
   `SKIP plist-env com.hermes.byz-mbox-slack-mirror (--project 가 git 공용 루트 아님: 루트=<BYZ 공용 루트> — plist 는 루트 설치에서만)` · cksum 전후 같음 · `plutil -extract EnvironmentVariables.FT_ROOT raw <plist>` = 루트 → 카드 `- 실사건:` 줄.
   (나노 사전 관측 = 같은 두 명령의 `--dry-run` · 읽기만 · `evidence/r457/real-dry-run.txt`)
4. 착지 뒤 arch 손: r426 카드 «상태» 에 «후속 r457(워크트리 --project 는 plist 0)» 1줄.

## 기존 시험(같은 설치 계열) — base fec5d3b3 `git archive` 판과 대조
- `test_installed_root.sh` rc0(22) · `test_live_install_check_shim.sh` rc0(15).
- 빨강 3 = base 에서도 같은 FAIL(이 단위 파일 무관 · 새 수정 단위 후보 — 판정 1395):
  - `test_live_install.sh`: 임시 루트 `.fable-team/bin` 이 drift-check `STALE-COPY`(r413)로 rc3 → ⓐⓑ FAIL + 줄 60 `bak` 미바인딩.
  - `test_live_install_check.sh` ⑥: 구현 범위 `scripts/harness-install/` 언급 + 없음 → REJECT 기대인데 OK.
  - `test_live_install_check_tip.sh` ⓕ: `ft-index-move-install --landed B` 가 «하네스 루트가 --repo 밖» ERROR.

## 편차
- 카드 §1 SKIP 줄의 «라벨»: 관리 라벨이 여럿이어도 1줄(라벨 공백 나열) — 지금 관리 라벨 1개라 `SKIP plist-env com.hermes.byz-mbox-slack-mirror (…)`.
- `COMMON` 은 `pwd -P` 로 정규화(macOS `/var` ↔ `/private/var` 오판 0).
- install-check: HINT 만이 아니라 plist-env 대조 루트도 공용 루트(`plist_root`) — 워크트리 `--project` 로 돌리면 렌더기가 새로 거절해 ERROR 가 나므로 둘을 같은 함수로.
- 렌더기 판정은 `.git` 폴더 = 공용 루트 · `.git` 파일 = 워크트리 · 없음 = git 밖(외부 호출 0). git 밖 `--project` 는 이제 ERROR(이전엔 그 폴더를 FT_ROOT 로 렌더 — 카드 ⓔ «새 통과 0»).

press 필요: 없음(설치기 단위 시험 + 실 머신 dry-run).
