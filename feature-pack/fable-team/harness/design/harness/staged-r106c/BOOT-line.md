# 스테이징 — COMM-GUIDE-BOOT.md 10번 줄 옆 지침 1줄 (R106c · 승격은 master · 아카이브 선복사 뒤 교체)

> 대상: `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 10번(버전 정합) 바로 아래 새 줄. 번호 재매김 없이 `10-a.` 로 단다.
> 강제: `scripts/harness-install/fable-team/templates/hooks/press-runner-gate.sh` (PreToolUse Bash · 설치 = `~/.claude/hooks/` cp + settings.json 등록 — master, press 창 밖).

10-a. **press 러너 실행 = tester·checker 좌석 + `FT_PRESS_CARD=<카드>` 기준선 + 기존 러너 + poller** (오빠 R15·R4): 나노·master 금지. 러너(`realtime_multi_e2e.py`) 실행 Bash 는 훅이 먼저 `ft-press-gate.sh` 를 돌려 막히면 deny 한다 — ★훅이 게이트를 대신 부르므로 같은 회차에 `ft-press-gate.sh` 를 손으로 또 부르지 않는다(허가·BTS 골격이 두 번 발급돼 ⑧ 이 막힌다)★. 읽기(grep·cat·git·sed -n·rg)는 대상 아님.
