# NEXT — tmm 증류 핸드오프 (2026-09-09 11:50, 세션 692k 에서 증류)

> 다음 세션은 이 폴더(`feature-pack/tmm`)를 cwd 로 열면 CLAUDE.md 가 자동 로드된다. 이 파일은 «어디까지 했고 무엇이 남았나»만.

## 현재 상태 (전부 main 에 푸시됨, 워킹트리 클린)

| 팩 | 버전 | 최신 커밋 | 설치본 |
|---|---|---|---|
| tmm | 0.4.7 | `c9a8fef` | `~/.tmm/current` = 0.4.7 |
| tmuxc | 0.3.2 | `5554895` | `~/.tmuxc/current` = 0.3.2 |
| fable-team `ft-tmux-spawn.sh` | — | `ff61435`+`5554895` | 워크트리 사본 3곳 재배포됨(loom-pack-layer·loom-domain-hierarchy·kakao-agent-bot-planning). `cli-rag` 는 `.fable-team` 미설치 |

## 오늘 한 것 (0.4.0 → 0.4.7)

- **종료 세션 뷰** `^D` / 좌석 뷰 `^A`. 12h 창 `^]`/`^\`, 계보 `^L`. 스캐너 `core/libexec/tmm-dead-scan.py`(claude `agentName`·codex `[A→B]`·cmd `.meta.json`·opencode sqlite ro). 라이브 제외 3중(ps argv uuid·tmux 세션명·mtime 90s). cwd 소실·scratchpad·/tmp 제외.
- **복구** Enter 1건 → attach. `^B` 창 전체 = **5개씩 배치 병렬**(`TMM_RESTORE_BATCH`), 결과 `$RUN/restore-<ts>.log` `ok|fail<TAB>이름<TAB>사유`, 끝나면 실패 목록. 모델 규칙: SNAP 은 스냅샷 argv, 아니면 트랜스크립트 model + high, **fable 제외 전부 `[1m]`**. 부팅 판정에 codex 문구 포함, 비-claude 는 pane 이 셸 아니면 성공.
- **헤더** 4섹션(이동/정렬/화면/상태 · dead: 복구/창/정렬/상태) 색 구분, 우상단 `tmm <VERSION>`, `?` 는 필터·도움말 `^/`. 각 줄 ≤58.
- **레이아웃** 전체 폭(FZF_COLUMNS+FZF_PREVIEW_COLUMNS) ≥120 이면 미리보기 오른쪽 55%(`^O` 75%), 아니면 아래.
- **모델 열** live: argv `--model`/`-c model=`, codex 가 config 기본이면 pane 하단 `gpt-x-y`. dead: 트랜스크립트+[1m] 규칙. 축약 `opus5·1m` `sonn5` `fabl51` `luna` `astra`.
- **tmux 함정 2개 고침**: (1) `new-session -d` 가 창을 80x24 `manual` 로 박아 데스크탑이 붙어도 안 커짐 → tmuxc `create_tmux_session`·tmm 복구·ft-tmux-spawn raw 에 `set -wu window-size`. 살아있던 25좌석은 손으로 풀었음. (2) 공유 스캔 캐시 경합 → 프로세스별 tmp.
- **tmuxc 0.3.2**: codex `--effort`(-c model_reasoning_effort) · `--fast on|off`(-c service_tier=priority|default). 실측 `gpt-5.6-luna high fast`. **ft-tmux-spawn 은 codex 에 `--model` 만 넘긴다**(effort/fast 는 role 기본·config 기본) — 오빠 지시: «effort medium, fast off 기본, 모델만 변경 발주».
- tmuxc 는 tmm 의 **필수 세트**(install.sh 가드·manifest required·doctor).

## 남은 것 / 다음 후보

1. **fable-team 팩에 codex fast/effort 축** — install.json 역할별 설정에 넣고 ft-tmux-spawn 이 `--effort/--fast` 를 넘기게. 오빠 현재 지시는 «기본값 유지, 모델만» 이라 급하지 않음.
2. `cli-rag` 워크트리에 FT 설치되면 SSOT 래퍼가 그대로 깔림 — 별도 조치 불요.
3. 남은 프로브 트랜스크립트(`PROBE_WS#1`, `PROBE_CDX#0`)가 종료 목록에 보임 — `~/.codex/sessions/2026/09/09/rollout-*01a083fe*.jsonl` 등. 오빠가 지우거나 무시.
4. 완료 마커에 날짜 없음(이틀 넘게 방치된 좌석 나이 과소) — 미해결, 낮음.
5. verify (j) 는 dead 뷰 헤더까지 잰다. 새 키 넣을 때 섹션 줄 ≤58 유지.

## 검증 방법 (요약 — 상세는 CLAUDE.md)

- `bash test/verify.sh` (격리 tmux 소켓, 기본 서버 무접촉) → `✅ tmm verify OK`.
- 폰 경로: `ssh -tt mac-mobile-test` + stdin 키 파이프. fzf 는 expect(pty 0x0) 로 못 그린다.
- 격리 TUI 캡처 스크립트 예시는 `/tmp/tmm-tui-drive3.sh` 패턴(PC 160x40 / PHONE 60x24 두 세션).

## 메모리·규칙 반영됨

- `~/.claude/projects/-Users-yoonhwan/memory/termius-mobile-tmuxc.md` (tmm 위치·키·함정)
- `~/.claude/rules/troubleshoot.md` 2026-09-09 항목 2개(SELF 경로·window-size manual)
