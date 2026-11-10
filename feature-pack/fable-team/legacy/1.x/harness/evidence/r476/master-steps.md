# r476 master-steps — opencode 좌석 모델 = 세션 env (tmuxc 0.4.1 · fable-team 1.1.35)

카드 `design/harness/indices/진행/r476-opencode-seat-model-via-config-env-not-flag.md` · 나노 byz-harness-nano-r476-opencode-seat-model-via-config-env-#0

## 가지 1
| 리포 | 가지 | 내용 |
|---|---|---|
| ai-feature-pack | `nano/r476-opencode-seat-model-via-config-env-` (워크트리 `.worktrees/nano-r476-opencode-model-env` · base origin/main 22fb0b6a) | tmuxc `core/bin/tmuxc`·VERSION·manifest·README·test 2 + ft-nano-spawn 짝(PLAN via=) + CHANGES 1절 + manifest 1.1.35 |
| BYZ-Agents | 같은 이름 가지 | 커밋 0 |

## 순서
1. 팩 PR → main 착지(master). 착지 전 `bash feature-pack/tmuxc/test/test_tmuxc_opencode_model.sh` ALL PASS · `bash feature-pack/tmuxc/test/verify.sh` `tmuxc verify OK`.
2. fable-team 키트 설치: `bash feature-pack/fable-team/harness/install.sh --apply --project <BYZ 공용 루트>` → LIVE_BIN = `~/.claude/fable-team/live/1.1.35/bin` · `ft-nano-spawn.sh` cmp0.
3. tmuxc 설치 — ★`feature-pack/tmuxc/install.sh` 를 그대로 돌리지 않는다★: 그 설치기는 `~/.claude/skills/tmuxc` 를 새 버전 폴더의 `claude-code/` 로 다시 거는데, 팩 `COMM-GUIDE-BOOT.md`(8.4KB · 17조항)가 라이브 0.4.0 판(26.8KB · 33조항 · 직접 편집 누적)보다 옛 판이라 전 좌석 부팅 지침이 되돌아간다. 대신 1줄(버전 폴더 복사 → 실행 파일만 교체 → current 전환):
   `cp -Rp ~/.tmuxc/versions/0.4.0 ~/.tmuxc/versions/0.4.1 && cp <팩>/feature-pack/tmuxc/core/bin/tmuxc ~/.tmuxc/versions/0.4.1/core/bin/tmuxc && cp <팩>/feature-pack/tmuxc/core/VERSION ~/.tmuxc/versions/0.4.1/core/VERSION && ln -sfn ~/.tmuxc/versions/0.4.1 ~/.tmuxc/current && cmp <팩>/feature-pack/tmuxc/core/bin/tmuxc ~/.tmuxc/current/core/bin/tmuxc`
   — 홈 대상 = `~/.tmuxc/versions/0.4.1/core/bin/tmuxc`·`core/VERSION` + `~/.tmuxc/current` 심링크(`~/.local/bin/tmuxc`·`~/.claude/skills/tmuxc` 는 current 를 따라감 · BOOT 는 라이브 판 그대로 복사됨) · 되돌림 = `ln -sfn ~/.tmuxc/versions/0.4.0 ~/.tmuxc/current`(0.4.0 폴더 손대지 않음 = .bak 역할).
   확인: `tmuxc open "$PWD" --name R476_SMOKE --agent opencode --model opencode/deepseek-v4.1-flash-free --dry-run` → `command=opencode --auto` + `env=OPENCODE_CONFIG_CONTENT={"model":"opencode/deepseek-v4.1-flash-free"}`.
4. 실사건 1: `ft-nano-spawn <카드> --agent opencode --model opencode/deepseek-v4.1-flash-free`(또는 `--tier search`) 1석 → REACHED · 그 좌석 세션의 model 칸 = ID(`sqlite3 -readonly ~/.local/share/opencode/opencode.db "select data from session_message where session_id='<ses_…>'"` 에서 `"model":{"id":"deepseek-v4.1-flash-free","providerID":"opencode"}`) · `ft-nano-close` → `OC-REAPED … left=0` → 카드 `- 실사건:` 줄.
5. 착지 뒤 arch 손: `COMM-GUIDE-BOOT.md` 41 끝 「opencode 좌석 모델 = tmuxc 가 env 로 심는다(`--model` 플래그 0 · r476)」 1줄(라이브 판에).

## 시험(나노 실행 · 세트 = 이 가지 HEAD)
- `tmuxc/test/test_tmuxc_opencode_model.sh` ALL PASS · `tmuxc/test/verify.sh` OK.
- `harness/tests/test_nano_spawn_{tier,reuse_info,teamset_cap}.sh` rc0 · `tests/scripts/test_nano_spawn_*.py` 43 passed.
- `test_nano_spawn_body_press.sh` rc2(FAILED=2 ⓒ node_modules) — `$HERE/../../.gitignore` 가 팩 배치에 없음 · 이 단위 무관(PLAN·opencode 참조 0) · ★수정 단위 필요(판정 1395)★.

## 범위 밖(별 카드 후보)
- tmuxc `snapshot_resume_cmd` opencode 분기 `--model` 합성 — 이제 argv 에 모델이 없어 스냅샷 모델 0 → restore 는 기본 모델로 뜸(기동 실패 아님).
- 팩 `tmuxc/claude-code/skills/tmuxc/COMM-GUIDE-BOOT.md` 를 라이브 판으로 역반영 — 되기 전까지 tmuxc `install.sh` 직접 실행 금지.
