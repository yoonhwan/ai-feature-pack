# lessons — 팀별·좌석별 기억 (jsonl + 개수 상한 + 밀어내기)

설치(`install.sh --apply`)가 `<프로젝트>/.fable-team/state/lessons/` 를 만들고 자리만 잡는다(파일이 이미 있으면 손대지 않는다).

| 자리 | 상한 | 누가 읽나 | 언제 |
|---|---|---|---|
| `state/lessons/seat/<좌석>.jsonl` | **100항목** | 그 좌석만 | 부팅 1회 `snapshot` |
| `state/lessons/team/<팀>.jsonl` | **100항목** | 팀 좌석 전부 | 부팅 1회 `snapshot` |
| `state/lessons/global.md.lock` | — | 락만 | 전역 다이제스트(`~/.claude/rules/dumb-time-digest.md`, 2,048B) |
| `state/evolution/` | 하루 1회 | 팀장 | `ft-evolve.sh --gate` · `LATEST` 고정 포인터 |

## 왜 개수 상한인가
바이트 상한만 두면 «몇 줄이 들어가는지»가 줄 길이에 따라 널뛴다. 그래서 **파일 = 개수(100)** · **로드 = 바이트(snapshot 2,048B)** 두 겹이다.
파일이 100항목이어도 프롬프트는 2KB 만 실린다. 넘치면 **오래된 것부터** `<이름>.archive.jsonl` 로 밀려난다 — **삭제가 아니라 이동**이다(삭제 HIL).

## 항목 형식 (1줄 = 1항목)
```json
{"ts":"2026-11-06T17:20","kind":"directive|mistake|achievement|experiment","text":"...","pin":false,"expires":"2026-11-20"}
```
- `kind` = nanoclaw 3분류(directive/mistake/achievement) + `experiment`(실험). 실험은 기본 14일 뒤 아카이브.
- `pin:true` = 밀어내기·TTL 면제(영구 기억).
- `text` ≤ 200자. 주입·유출 유도 문장은 저장 전 REJECT.
- 이미 있는 선례 = mbox 큐의 `trim(rows, keep_n)`(개수 상한 + 등급 우선 밀어내기 · r912). 여기선 등급 대신 `pin`.

## 명령
`ft-lessons.sh init` · `add <seat|team> <이름> "1줄" [--kind …] [--pin]` · `list` · `pin|unpin` · `evict` · `snapshot [--budget 2048]` · `check` · `migrate`(옛 md → jsonl)
