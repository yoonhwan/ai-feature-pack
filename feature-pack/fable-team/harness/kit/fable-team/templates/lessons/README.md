# lessons 템플릿 — 팀별 메모리 시드

설치(`install.sh --apply`)가 `<프로젝트>/.fable-team/state/lessons/` 를 만들고 아래를 배치한다(이미 있으면 손대지 않는다).

| 자리 | 상한 | 누가 읽나 | 언제 |
|---|---|---|---|
| `state/lessons/seat/<좌석>.md` | 2,048B | 그 좌석만 | 부팅 1회 스냅샷 |
| `state/lessons/team/<팀>.md` | 4,096B | 팀 좌석 전부 | 부팅 1회 스냅샷 |
| `state/lessons/global.md.lock` | — | 락만 | 전역 다이제스트(=`~/.claude/rules/dumb-time-digest.md`, 2,048B) 잠금 |
| `state/evolution/` | — | 팀장 | 하루 1회 게이트(`ft-evolve.sh --gate`) · `LATEST` 고정 포인터 |

- 팀 이름은 `seats-<팀>.json` · `design/teams/<팀>/` · `state/team-main/<팀>/` 에서 유도한다.
- 기억은 **부팅 1회 고정 스냅샷**이다(hermes 방식). 세션 중 `add` 는 파일에만 쓰고 프롬프트를 바꾸지 않는다 — prefix cache 를 지킨다.
- 대조 근거 = `docs/design-memory-evolution-repos-20261106.md`.
