# r464 master-steps — 설치기 plist 교체: bootstrap 재시도 · 실패면 직전 plist 원복 · LIVE_BIN 전환 뒤로 (집행 순서 · master)

카드 `design/harness/indices/진행/r464-install-plist-swap-bootstrap-retry-and-live-bin-switch-isolation.md` · 나노 byz-harness-nano-r464-install-plist-swap-bootstrap-retry-#0

## 가지 1
| 리포 | 가지 | 내용 |
|---|---|---|
| ai-feature-pack | `nano/r464-install-plist-swap-bootstrap-retry-` (워크트리 `.worktrees/r464-plist-bootstrap-retry` · base origin/main d8305edb → ff d56b9c0e) | `harness/install.sh` `boot_retry`·`plist_restore` + plist_sync 교체 블록 + plist_sync 를 LIVE_BIN 전환·githooks 뒤로 + 마지막 줄 `INSTALLED <ver> · PLIST ok/ERROR` · 시험 r464ⓐ~ⓔ · CHANGES 1절 · manifest 1.1.27 |
| BYZ-Agents | 같은 이름 가지 | 커밋 0 |

## 순서
1. 팩 PR → main 착지(push·PR·`ft-merge-land` = master). 착지 전 `bash feature-pack/fable-team/harness/tests/test_live_install_check_plist_env.sh` rc0(39 PASS).
2. 설치(★이 설치가 새 설치기로 도는 첫 번째 = 실사건 후보★): `bash feature-pack/fable-team/harness/install.sh --apply --project <BYZ 공용 루트>` → 끝 줄 `INSTALLED 1.1.27 · PLIST ok`(또는 `· PLIST ERROR` + 위 `PLIST RESTORED` 줄) · LIVE_BIN = `~/.claude/fable-team/live/1.1.27/bin` · cmp0.
   - 1.1.27 은 inbox 경로가 바뀌므로 미러 plist 는 «다름» → 교체가 실제로 돈다: `PLIST applied com.hermes.byz-mbox-slack-mirror (retry=<n> · 되돌림 = …plist.bak-1.1.27 · kickstart)`.
3. 실사건 1 확인: 위 `PLIST applied …(retry=N)` 또는 `PLIST RESTORED` 줄 원문 + `launchctl list | grep byz-mbox-slack-mirror` pid 실재 + `sed -n 1p <BYZ>/.fable-team/LIVE_BIN` = 1.1.27 → 카드 `- 실사건:` 줄.
4. 착지 뒤 arch 손: r426 카드 «상태» 에 «후속 r464(bootstrap 재시도·원복·전환 분리)» 1줄.

## 기존 시험(같은 설치 계열) — base d56b9c0e 와 대조
- `test_installed_root.sh` rc0(22) · `test_live_install_check_shim.sh` rc0(15).
- 빨강 3 = base d56b9c0e 에서도 PASS/FAIL 줄 같음(이 단위 무관 · r457 master-steps 에 이미 적힌 같은 3건 · ★여전히 수정 단위 없음 — 판정 1395 «기존 RED 아님 → 수정 단위»★):
  - `test_live_install.sh`: drift-check `STALE-COPY`(r413) rc3 → ⓐⓑ FAIL + 줄 60 `bak` 미바인딩.
  - `test_live_install_check.sh` ⑥: 구현 범위 `scripts/harness-install/` 언급 + 없음 → REJECT 기대인데 OK.
  - `test_live_install_check_tip.sh` ⓕ ×2: `ft-index-move-install --landed B` 가 «하네스 루트가 --repo 밖» ERROR.

## 편차
- 카드 §1 ⓒ «함수 끝에 rc1»: 함수는 `PLIST_FAIL=1` 만 세우고, rc1 은 설치 맨 끝(`INSTALLED … · PLIST ERROR` 뒤)에서 낸다 — 라벨이 여럿이어도 나머지 라벨을 끝까지 돌린다.
- kickstart 실패도 같은 원복 틀(카드 §4 «같은 되돌림 틀로 묶음»). 원복은 bootstrap 만(kickstart 0 — 원래 적재 상태로 되돌림 · RunAtLoad=false 라벨도 있음).
- 원복본 bootstrap 도 실패하면 `ERROR: plist 원복본 bootstrap 도 실패 … 손 복구 = launchctl bootstrap gui/<uid> '<plist>'`(시험 ⓑ').
- 재시도: 3회 · 사이 `sleep 1` · 6초 지나면 더 시도하지 않음(7초 룰). 시험 ⓔ 실측 첫~마지막 bootstrap 2s.
- render 실패(`ERROR: plist 렌더 실패`)는 그대로 `exit 1` — 이제 LIVE_BIN 전환 뒤라 코드 전환은 끝난 상태.

press 필요: 없음(설치기 단위 시험 + 실 머신 dry-run).
