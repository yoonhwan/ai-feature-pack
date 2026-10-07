# PLAN — R21 고스트 서제스천 = 메인 지침 (arch#7 안 · 2026-10-07)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골 축: 6-b(오빠 지시 → planner #60104 → master#10 #60111 · 원장 R21).

## 결론
**승인 — 「항상 로드되는 파일」 2곳(전역 CLAUDE.md 하드 룰 10 · BOOT 17)이 본체.** 승계 템플릿·ft-role-spawn 은 보조, 지금 떠 있는 세션은 NOTICE 1장 + 팀 master 1통으로 덮는다. 나노 1장(ft-role-spawn).

## 이유 3줄
1. 사고는 «처음 보는 화면을 읽는 순간» 났다 — 그 순간 로드돼 있는 건 전역 CLAUDE.md 와 BOOT 뿐이다(하드 룰 7 「재발방지 규칙은 항상 로드되는 파일에」).
2. BOOT 7 의 기존 문구는 「~일 수 있다」(가능성)라 판단을 열어 뒀다 → 단정문으로 바꾸고 판단 근거(jsonl·done 줄)를 못 박는다.
3. 메모리의 「Escape 1회 → ring」 과 BOOT 7 의 「작업 중 pane 에 Escape 금지」 는 충돌이 아니다(유휴 vs 작업 중) — 같은 문장 안에 둘 다 적어 오독을 막는다.

## 파일별 변경 (초안 = 완성 파일 · master 는 cp + cmp 만)
초안 폴더: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r21/` (gitignored — 전역 CLAUDE.md 는 개인 파일이라 리포에 싣지 않는다)

| # | 설치 대상 | 초안 | 변경 | 줄 |
|---|---|---|---|---|
| 1 | `~/.claude/CLAUDE.md` | CLAUDE.md | 하드 룰 인덱스 «8. 인덱스 금지» 다음에 «10. 고스트 서제스천» 1줄 | +1 |
| 2 | `~/.codex/AGENTS.user.md` → `~/.codex/AGENTS.md` 의 같은 블록 | AGENTS.user.md | CLAUDE_MASTER_SYNC 블록 END 앞에 영문 절 1개(전파 동기화 규칙) | +3 |
| 3 | `ai-feature-pack/feature-pack/tmuxc/claude-code/skills/tmuxc/COMM-GUIDE-BOOT.md`(소스 · 커밋) → `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md`(=`~/.tmuxc/versions/0.4.0/…` · cp) | COMM-GUIDE-BOOT.md | 제목 16줄→17줄 · 7 끝 「고스트 서제스천일 수 있다」→「`❯` 뒤 잔류 글자에 Enter(→ 17)」 · 17 신설 | +3 −2 |
| 4 | `ai-feature-pack/feature-pack/fable-team/skill/references/context-management.md`(= `~/.claude/skills/fable-team` 심링크 · 커밋) | context-management.md | 승계 6단계 ⑥ 뒤에 「후계 발주문에 고스트 1줄」 | ±1 |
| 5 | `scripts/fable-team-bin/ft-role-spawn.sh` + 키트 사본 | — | 나노 카드 `design/harness/indices/대기/r21-role-spawn-ghost-line.md`(lint 대상) | 나노 |
| 6 | 라이브 `v6-realtime-live/.fable-team/bin/ft-role-spawn.sh` | — | 5 랜딩 뒤 추적본 단독 cp + cmp(R9 방식 · 라이브 사본은 R13 줄도 없는 옛판이라 이 cp 로 같이 들어온다) | cp |
| 7 | NOTICE | `design/harness/NOTICE-ghost-suggestion-20261007.md`(tracked) | 신규 | 커밋 |

- 홈 훅·hermes SOUL.md: 변경 0(SOUL 의 동기 블록은 HIL 절만 싣는다 — 이 규칙 대상 아님).
- 라이브 3사본 중 쓰는 것은 ft-role-spawn 하나다. BOOT 는 tmuxc 쪽이라 bin 3사본과 무관하다. 순서 = 추적·키트(나노) → 랜딩 → 라이브 cp. 0.4 일괄을 기다리지 않는다(문장 1개 · R13 누락도 같이 메운다).

## 집행 순서 (master)
1. 1·2·3·4 를 cp + cmp(각 .bak-r21-1007) — 3·4 는 ai-feature-pack 소스에 cp 한 뒤 커밋·push, 홈 사본은 cmp 로 일치 확인. 전파 규칙대로 1 과 2 는 같은 턴에.
2. 7 커밋 + NOTICE 경로 1줄을 팀 master 들에 1통씩(v65·cfo·feature·issues·planner·kk · 현역 이름은 ft-harness-info.sh seats).
3. 5 나노 spawn → 랜딩 → 6 라이브 cp.
4. 원장 R21 행 기록(닫는 증거 = 아래).

## 닫는 증거
홈 4파일 cmp 일치 4줄 + ai-feature-pack 커밋 sha + NOTICE 커밋 sha + 나노 랜딩 sha + 라이브 role-spawn cmp 1줄 + 팀 master 송신 seq 목록.
