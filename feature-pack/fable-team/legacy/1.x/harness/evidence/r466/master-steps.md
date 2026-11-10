# r466 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 가지 `nano/r466-autonomy-on-off-interview-period-an` push → PR (나노 push 금지) → 병합 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 = origin/main(36a43b06 · r479 착지 뒤) 위. ★버전 번호·CHANGES 머리는 이 가지에 안 넣었다★(병행 가지 충돌 방지) — 착지 순서대로 master 가 다음 번호. 문안 = 아래 «CHANGES 절».
   파일 = bin·kit 짝(cmp 0) 8: `ft-autonomy.sh` · `ft-autonomy-scope.sh` · `ft-autonomy-scope-code.sh` · `ft-tick.sh` · `autonomy_scope_classify.py` + 새 `ft-autonomy-level.sh` · `ft-autonomy-interview.sh` · `autonomy_scope_rules.py`
   + 키트 templates 새 3(`autonomy-level.conf` · `scope-classes-pack.tsv` · `scope-ddl-record.tsv`) + 홈 훅 1(`templates/hooks/autonomy-state-guard.sh`) + LIVE-MAP 2행 + 시험 새 2 · 기존 시험 15(머리 1줄 `FT_AUTONOMY_LEVEL=each` — 아래 편차 ②).
2. 되돌림 준비(설치 전): 위 bin 5 · 훅 1 을 `cp -p <파일>{,.bak-r466}` (새 파일 3·templates 3 은 지우면 되돌림 — 단 ft-autonomy.sh 를 옛 판으로 돌리면 level 칸 있는 승인 줄은 «꼴 밖» = 위변조로 읽힌다 → 되돌릴 땐 자율 OFF 상태에서).
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>` → bin 8 · templates 3 `cmp <키트> <LIVE_BIN>/…` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK(templates 2행 새 cmp 대상).
   홈 훅: `cp -p <키트>/fable-team/templates/hooks/autonomy-state-guard.sh ~/.claude/hooks/` → cmp0 (settings.json 등록 변경 0 · ★홈 사본은 지금 r298(approve-scope·autonomy-scope/) 이전 판이다 — 이번 cp 가 그 차이까지 함께 들인다★).
4. 틱 재시작(master 손 · kickstart 1회): ft-tick 을 돌리는 launchd 잡 — expire 뒤 `interview-note` 호출이 새 틱에서만 돈다.
5. 실사건(닫는 증거 · 카드 끝): ①새 자율 1회 = desk 가 오빠 인터뷰(기간·레벨) 답으로 `ft-autonomy-interview.sh --for <N>h --level full` → `! bash /tmp/h<N>` 1줄 → 오빠 실행 →
   `ft-autonomy.sh scope-status` 가 `[범위 승인 S<n> · A<new> · …]` · 다음 OFF 까지 병합 질문 0(autonomy.log `scope-use` 건수 · desk 1줄) ②종류 학습 = loom 1959(FORBID 꼴) 를 오빠 approve-merge → `learned-kinds.tsv` 1행 → 다음 같은 종류(chatbot 이관 PR) `SCOPE-OK … learned=<키>`.
   ★주의★ loom 1959 의 «카드 48장 rename» 은 이번 분류기에서 이미 `move`(R100 · 이름 같음 · 양쪽 docs) = docs 로 통과할 수 있다 — 그러면 종류 학습 실사건은 다음 FORBID 종류에서 잡힌다.
6. 뒤 일(arch 손 · 착지 뒤 · 카드 §정본): `COMM-GUIDE-BOOT.md` 33 끝에 «자율 ON = 인터뷰 1회(기간 + 레벨 full|mid|each · 기본 full) → h 1줄 `ft-autonomy.sh on --for … --level …` 이 범위 승인까지 건다 · 끝 도달·OFF 는 틱이 desk 에 [자율 인터뷰] 1통(r466)» · desk 지침 1줄 «자율 인터뷰 답 → ft-autonomy-interview.sh → h 1줄».

## 동작 요약 (카드 §구현 범위 대조 · 착수 순서 5 → 5b → 5c → 1~4)
- 5 분류기: 경로 분류를 표로(기본 = BYZ 내장 = 옛 PATH_RULES·DOC_RE 그대로 · `--table <tsv>` = 팩 표) · ⓐ 카드 이동 = `R100` ∧ 모드 같음 ∧ 파일 이름 같음 ∧ 양쪽 docs → docs(이름 바뀜 = `rename` · 내용 바뀜 = `move-changed` FORBID) ·
  ⓑ 새 `*.sql` + 적용 기록 줄(`--ddl-records <tsv>` · `-` = 이 PR 추가 줄 · 그 밖 = 리포 경로 · 줄에 그 sql 이름 + `applied` + 판정 번호) → docs · 같은 PR 에 문서 밖 변경 = `FORBID kind=ddl` ·
  ⓒ `scope-approve --repo pack` = 하네스 코드 루트(ft_harness_root)의 git 최상위 · 승인 줄 `repos=byz,pack` 일 때만 · 팩 표 전달 · code 세트 검사(evidence-check·approval-equiv)도 팩 리포.
- 5b 종류 학습: FORBID 출력 = `FORBID kind=<키> <사유>`(키 = ddl·deploy·key·billing·deps·global-rule·delete·copy·type·rename·move-changed·mode·ddl-no-record·repo-outside·secret) → scope-approve 가 `denied.tsv` 1행 →
  오빠 `approve-merge`(같은 잠금 · ON ∧ json level=full) = `learned-kinds.tsv` 1행(같은 종류 재저장 0) → 레벨 full 승인 줄이면 분류기에 `--learned` → 그 종류만 docs(`CLASS docs kind=<키> learned`) · 다른 종류가 섞이면 FORBID 그대로 · secret 은 학습 불가 · `forget-kind <키>` = 오빠 `!` 전용 · `--audit` 이 학습 행 ↔ denied·approve-merge 줄 대조.
- 5c 홈 훅: 인자에 진입 파일(`…/h<N>`)·계획 파일(`*.sh.hil`)이 있으면 본문(진입 파일 `plan=` → 계획 1단)에 같은 판정 · approve-merge 는 자율 ON 이면 허용 + 로그 `hN-approve seat=… file=… plan=…` · OFF·못 읽음 = deny · on|off|forget-kind|approve-scope = 늘 deny · 파일 못 읽음 = 허용 + 로그.
- 1 `on [--level full|mid|each] [--max --daily --code-max]`: 잠금 안 «슬랙 게시 → 모드 줄 → 범위 승인 줄 `… level=<레벨>`» · 게시 실패 = 둘 다 0(rc 1) · 기본표 `templates/autonomy-level.conf`(full = h178 S3 값 + repos=byz,pack · mid = code 0 · each = 승인 줄 0) · 끝 없는 ON 의 범위 = 24h · json `level` 칸 · off·expire 는 레벨 칸 유지 · status 에 `레벨 풀자동 · 범위 S<n>`(full·mid 만).
- 2 재발급: 사건 번호 바뀜 ∧ 마지막 승인 줄 level ∈ {full,mid} ∧ 지금 json level 같음 → scope-approve 가 잠금 안에서 `S<n+1> A<new>`(같은 max·daily·classes·codemax·repos · until = 지금 ON 끝) + stderr `SCOPE-RENEWED` · 정지·each·옛 줄 = 기존 AUTOSTOP.
- 3 틱: `autonomy_expire` 가 `EXPIRED A<N>` 뒤 `ft-autonomy.sh interview-note A<N> expire` · off 는 스스로 1통 · 받는 이 = planner 명부 `_desk` · 머리 `[자율 인터뷰]` + 골 표 블록(ft-goal-table.sh render) · 같은 사건·종류 10분 중복 억제 · planner 명부 없는 환경 = 대상 아님.
- 4 `ft-autonomy-interview.sh`: 값 검사 = `ft-autonomy.sh on-check`(on 과 같은 판정 · 쓰기 0) → 계획 파일 `<state>/autonomy-on-<시각>-<레벨>.sh.hil` → `ft-hil.sh --add` → `! bash /tmp/h<N>` 1줄(60자 넘으면 REJECT).

## 편차·범위 밖 (나노 판단 · 근거)
- ① 새 파일 `ft-autonomy-level.sh`·`autonomy_scope_rules.py`(카드 «키트 4 + 새 interview 1» 밖): `ft-autonomy.sh` 200줄 시험 · 분류기 200줄 시험이 있어 몸통을 옮겼다(동작 = 카드 그대로).
- ② `--level` 생략 = full(오빠 «기본 풀자동») 이라 `on` 이 슬랙에 게시한다 — 레벨과 무관한 기존 시험 15개가 실 슬랙(~/.hermes 토큰)에 닿지 않게 머리에 `export FT_AUTONOMY_LEVEL=each`(env = «생략 때 기본 레벨»만 바꿈 · 운영 env 엔 없음).
- ③ each 레벨 status 는 옛 꼴 그대로(레벨 칸 0) — 기존 status 꼴 시험·훅 머리 대조를 안 깨려고. each 는 `scope-status` 가 `[범위 승인 없음 · 건마다 확인]`.
- ④ 재발급은 «scope-approve 때» 한다(scope-status 는 읽기 전용 — 쓰지 않고 `· 레벨 full 재발급 대상` 으로 보인다).
- ⑤ 팩 분류표에 `manifest.json`(docs)·`kit/`·`bin/`·`install.sh`·`tests/`(code)·`CHANGES.md`·`evidence/`·`*.md`(docs) · 그 밖 `repo-outside` FORBID — manifest 는 카드 목록에 없지만 모든 팩 PR 에 들어가 docs 로 넣었다.
- ⑥ secret 종류는 학습 불가(오빠 승인 1회로 «비밀 꼴 줄» 이 다음부터 자동 통과하면 안 돼서) — 승인 자체는 그대로 된다(approve-merge 출력 `LEARN-SKIP`).
- ⑦ DDL 기록표 기본 2행 = 이 PR 추가 줄 + `design/teams/planner/PLAN-oppa-ledger.md` — 「같은 PR 의 기록 줄」은 좌석이 쓸 수 있는 글이라 신뢰도가 낮다(카드 원문대로 넣음 · 빼려면 표에서 `-` 행 삭제).
- 범위 밖(카드 7): autonomy-merge-guard · ft-proxy-decide · 슬랙 질문 카드 UI · 라이브 설치 자동화 · 쪽지 가드·desk 글 차단.

## 시험
- 새 `bash harness/tests/test_autonomy_level.sh` → 65 passed rc=0 (ⓐ 8 · ⓑ 4 · ⓒ 3 · ⓓ 9 · ⓔ 7 · ⓕ 6 · ⓖ 3 · ⓚ 13 · 정적 12 — bash 3.2 -n · 짝 cmp · 200줄 · 600/300 0).
- 새 `bash harness/tests/test_autonomy_scope_pack.sh` → 13 passed rc=0 (ⓙ 팩 리포·팩 표·code 세트 검사 팩 리포·repos 밖 REJECT).
- `test_autonomy_scope_classify.sh` 71 rc0(ⓗ 4 · ⓘ 6 · ⓙ 4 · ⓚ 5 추가 · 옛 FORBID 머리 단언 = `FORBID kind=<키> <옛 사유>` 로) · `test_autonomy_hooks.sh` 184 rc0(ⓛ 20 추가) ·
  `test_autonomy_scope.sh` 134 · `core` 194 · `preflight` 113 · `kinds_1675` 109 · `merge_equiv` 13 · `merge_land` 49 · `merge_land_equiv` 41 · `merge_land_state_dir` 8 · `merge_land_off_approval` 14 ·
  `proxy_decide_r188` 61 · `verdict_row` 30 · `arch_required_gate` 25 · `harness_root` 74 · `evidence_log_gate` 54 · `live_install_check_shim` 15 · `live_install_check_plist_env` 39 · `kit_bin_sync` 6 — 전부 rc0(core 는 아래 기존 RED 1 뿐).
- ★기존 RED(origin/main 36a43b06 기준 사본에서 같은 실패 · 이 가지 무관)★: `test_autonomy_core` 1(팩 리포에 BYZ `shared/config/external_call.py` 없음) · `test_autonomy_hooks_layout` 6(ⓛ0·3·3b·4·6·7 — 같은 6건) ·
  `test_team_literal_paths2` 18 · `test_live_install_check` 1 · `test_live_install_check_tip` 2 · `test_teamset_gitref` 3(comm 폴더 없음).
- py_compile 2 · ruff 0 · bash -n(/bin/bash 3.2) 6 · `ft-tmp-trap-lint.sh` PASS 3 · 짝 cmp 0 8.

## CHANGES 절 (착지 번호를 붙여 머리에)
### <버전> — r466 자율 레벨(full·mid·each) + 범위 승인 함께 걸기 · 레벨 재발급 · 자율 인터뷰 · 분류기 확장(이동·DDL 기록·팩 PR) · 종류 학습 · 훅 hN 투시
- `ft-autonomy.sh on --level full|mid|each`(기본 full) 가 같은 잠금 안에서 모드 줄과 레벨별 범위 승인 줄을 함께 쓴다 — 자율을 다시 켤 때마다 범위가 끊겨 병합마다 오빠께 가던 일이 끝난다. 끝 도달·OFF 는 desk 에 `[자율 인터뷰]` 1통 → `ft-autonomy-interview.sh` → `! bash /tmp/h<N>` 1줄.
- 범위 승인 분류기: 카드 폴더 이동(내용 동일) = docs · 적용 기록 있는 새 sql = docs · 팩 저장소 PR(`--repo pack` · 승인 줄 `repos=byz,pack`) · FORBID 마다 종류 키 → 오빠가 한 번 승인한 종류는 레벨 full 에서 다음부터 자동(secret 제외 · `forget-kind` 로 빼기).
- 홈 훅 `autonomy-state-guard.sh` 가 `/tmp/h<N>`·`*.sh.hil` 안 명령도 본다 — 자율 ON 중 desk 의 병합 승인 h 는 허용 + 로그, on/off/forget-kind/approve-scope 는 늘 막음. 단계 = `harness/evidence/r466/master-steps.md`.
