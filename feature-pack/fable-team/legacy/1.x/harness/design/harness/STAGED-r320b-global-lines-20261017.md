# R320b — 항상 로드되는 줄 문안 (master 설치용 · 오빠 원문 그대로 · 축약 0)

> 설치 = master 손(cp·편집) · 나노는 문안만. 전역 `~/.claude/CLAUDE.md` 「전파 동기화」 규칙대로 `CLAUDE_MASTER_SYNC` 전파본 2곳을 같은 세션에서 재생성하고 `v=날짜` 를 갱신한다.
> 출처: 오빠 2026-10-17 13:4x(desk) · 판정 2170 · 요청 원장 R320 · 강제 장치 = `ft-stall-scan.sh`(감지·처리) + `ft-penalty.sh`(페널티) + nano·role spawn 의 PENALTY_STOP 거절.

## ① `~/.claude/CLAUDE.md` — 하드 룰 인덱스 맨 끝에 추가

```
14. **정지 세션 0 = 페널티**: «앞으로 한 세션이라도 멈춰 있으면 하네스 전체 정지다. 그냥 일을 하지 마, 안 되면.» «하네스 이거 해결 안 되면 팀셋, 팀틀이랑 완전히 랜딩한 다음에 이거 완전히 해결돼야 다시 잡고 간다. 전 세션 정지 때려.» «안 되면 그냥 … 매번 전 세션 정지 때려서 페널티 주는 거라, 완전히 해결될 때까지 멈춰서 뚫을 때 뚫고 다시 시작하고 하나씩 팀 정정하고 다시 간다» — 감지 = `ft-stall-scan.sh` 4종(a 대기 카드 있는데 master IDLE · b 선언 뒤 IDLE · c 정책 정지 · d 답 기다리며 3분+) · 처리 = 감지한 그 턴(보고만 하고 끝내기 0) · 페널티 = `ft-penalty.sh`(처리 뒤 다음 틱에도 같은 멈춤이면 전 세션 정지 → 해결 확인 → 팀 하나씩 `resume`). (2026-10-17 오빠 판정 2170 · R320b)
```

## ② `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` — 38번째 줄(끝 번호 뒤)에 같은 문장

```
38. **정지 세션 0 = 페널티**(2026-10-17 오빠 판정 2170 · R320b): «앞으로 한 세션이라도 멈춰 있으면 하네스 전체 정지다. 그냥 일을 하지 마, 안 되면.» «하네스 이거 해결 안 되면 팀셋, 팀틀이랑 완전히 랜딩한 다음에 이거 완전히 해결돼야 다시 잡고 간다. 전 세션 정지 때려.» «안 되면 그냥 … 매번 전 세션 정지 때려서 페널티 주는 거라, 완전히 해결될 때까지 멈춰서 뚫을 때 뚫고 다시 시작하고 하나씩 팀 정정하고 다시 간다». 좌석은 멈춘 채 «대기» 보고로 끝내지 않는다 — 막힘은 그 턴에 처리(깨우기·발주·[HIL]). `[페널티]` 쪽지를 받으면 새 발주·spawn 0, 진행 중 도구 호출만 끝내고 멈춘다(복구 담당 harness·planner 팀은 대상 아님 — 재개는 `ft-penalty.sh resume <팀>`). 감지 도구 `ft-stall-scan.sh` · 페널티 `ft-penalty.sh`.
```

## ③ 전파본 2곳 — `~/.codex/AGENTS.md` · `~/.hermes/SOUL.md` 의 `CLAUDE_MASTER_SYNC` 블록 재생성 + `v=<설치 날짜>` 갱신 (codex 는 `~/.codex/AGENTS.user.md` 사본도 같이)

## 설치 순서 (착지 뒤 · master)
1. 라이브 `.fable-team/bin` 에 키트 새 파일 cp + cmp 0: `ft-stall-scan.sh` `ft-penalty.sh` `ft_stall_scan.py` `ft_stall_detect.py` `ft_penalty.py` + 바뀐 `ft-nano-spawn.sh` `ft-role-spawn.sh` `ft_news_ledger.py`.
2. launchd: `launchd/com.byz.ft-stall-scan.plist.template` 렌더(`__FT_BIN__`·`__BYZ_ROOT__`) → `~/Library/LaunchAgents/com.byz.ft-stall-scan.plist` → bootstrap. 먼저 `bash ft-stall-scan.sh --dry-run` 1회로 출력 첫 줄(`stall=N …`)·오탐을 눈으로 본다.
3. 위 ①②③ 3곳 + 전파본 `v=날짜`.
4. `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
