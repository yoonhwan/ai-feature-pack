# r468 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 가지 `nano/r468-team-rename-tool-concierge-to-chatb` push → PR (나노 push 금지) → 병합 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 = origin/main(457f34fc · r474 착지 뒤) 위. 파일 = bin·kit 짝(cmp 0) 4: 새 `ft-team-rename.sh` · 새 `ft_team_rename.py` · `ft-tick.sh` · `team-tick-env.tsv`
   + 새 시험 `tests/test_team_rename.sh` + 고친 시험 `tests/test_team_tick_unify.sh`(concierge → chatbot) + CHANGES 1절 · manifest 1.1.32 + 증거 `evidence/r468/`.
   ★병행 가지가 먼저 착지해 1.1.32 를 쓰면 착지 순서대로 다음 번호로 바꾼다★. ★r475(대기 · 이동 파일 7 수정 예정)와 파일 겹침 0 — 이 가지는 `ft_team_move*.py` 를 import 만 한다★.
2. 되돌림 준비(설치 전): LIVE_BIN `ft-tick.sh`·`team-tick-env.tsv` 각각 `cp -p <LIVE_BIN>/<f>{,.bak-r468}`(새 파일 2 는 없음 = 되돌림 시 삭제).
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>`
   → 4 파일 `cmp <키트>/fable-team/bin/<f> <LIVE_BIN>/<f>` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK
   → 메인 틱 재기동(새 `renamed_watch` 적재 · install 출력 `RESTART` 줄대로 `launchctl kickstart -k`).
4. 실사건 1(계획 §7 ③ · 닫는 증거) — ★선행 = 계획 §5 ①(concierge-main 쌍둥이 정리·main 착지 · concierge master 몫)★:
   ⓐ 전체 체크아웃 워크트리(★sparse 나노 워크트리는 design/teams 가 빠져 «원본 폴더 없음» BLOCK — 실측★)에서 가지 `land/team-rename-chatbot`(origin/main 위):
      `FT_REPO_ROOT=<그 워크트리> bash <LIVE_BIN>/ft-team-rename.sh --plan concierge chatbot` → `PLAN-END blockers=0` 확인(BLOCK 있으면 멈춤 — 점유 = 그 좌석 cwd 옮기기)
   ⓑ `… --apply concierge chatbot` → `RENAMED concierge → chatbot commit=<sha>` · `AFTER 옛 자리 잔여 0` · `SNAPSHOT <경로>`(되돌림 = `--revert <그 경로>`)
   ⓒ `… --verify chatbot` → `VERIFY ERR=0`(WARN = 남은 «concierge» 글자 목록 — 워크트리 이름 concierge-main·파일 이름 GOAL-concierge.md 등은 보존 대상)
   ⓓ main PR 1(오빠 approve 1) → 착지 → `_cards_wt`(concierge-main)가 못 받아 `_move_pending` 인 행은, 새 라이브 루트 `chatbot-main` 을 main 에서 만들고 명부 `_cards_wt` 를 고친 뒤 `--apply concierge chatbot` 다시 = RESYNC.
   ⓔ 계획 §6 grep 세트(tmux · 명부 · TEAMS/TEAMSET · 폴더 · .fable-team · launchd · seat-resume) — 좌석 교대(§4) 뒤.
5. 뒤 일(arch 손 · 착지 뒤): `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 13 끝에 «팀 이름 바꾸기 = `ft-team-rename.sh --plan/--apply <옛> <새>`(명단·폴더·명부·env·저장 참조 한 번 · 좌석은 successor-open 교대 · r468)» 1줄.

## 편차·범위 밖 (나노 판단 · 근거)
- ① 받음 판정: 명부 경로 칸은 이동 도구와 같은 규칙(store_base 워크트리에 `design/teams/<새>/` 가 있으면 새 경로 · 없으면 `_move_pending`)을 따랐다 — 카드 «`_tree` 새 경로» 는 받은 기준에서만 바로 쓰이고, 실 리포의 `_cards_wt=concierge-main` 은 못 받은 상태라 ④ⓓ RESYNC 가 마무리한다(못 받은 워크트리에 없는 경로를 쓰면 보드 collect 가 «_tree 파일 없음» 으로 죽는다 — r475 실측).
- ② 본문 치환은 카드대로 패턴 2(`design/teams/<옛>/` · `byz-<옛>-`)뿐 — 옛 꼴 `design/<옛>/` 글자·«<옛> 팀» 말은 팀 폴더 본문에서 안 바꾼다(verify WARN 으로 보임). 명부 `_doc`·env 값만 STORE 패턴(명부 파일·env 폴더·나노 접두·워크트리 접두·활성 태그·원장 경로 옛 꼴·틱 라벨·«<옛> 팀»·바뀐 파일 이름)을 쓴다.
- ③ env 의 `FT_NANO_LEDGER_WT=…/concierge-main`·`FT_NANO_FEAT=feat/concierge-main` = 워크트리·가지 이름(보존 · 계획 §5) → 그대로 · verify WARN. 원장 파일 이름(`NANO-LEDGER-concierge.md`·`GOAL-concierge.md`)도 폴더 안 파일 이름이라 그대로(경로 폴더만 새 꼴).
- ④ 명부 `_master`·`_arch` 등 좌석 이름 칸과 행 이름은 바꾸지 않는다 — 교대(ft-seat-retire)가 새 좌석으로 갈아 끼운다.
- ⑤ 기존 실패(이 단위와 무관 · origin/main 457f34fc 사본에서 같은 FAIL): `test_team_move_roundtrip.sh` 3(ⓒ 꼴3 env 없음 · ⓑ' 쌍둥이) · `test_live_snapshot_all_rosters.sh` 1(dry-run) · `test_team_tick_unify.sh` 1(ⓖ H2 --script wt/scripts) — `evidence/r468/existing-tests.txt` · 수리 카드 필요(나노 범위 밖).
