# 설계 대조 — 기존 메모리·진화 구현 3종 (hermes · nanoclaw · xclaw) → ft-lessons/ft-evolve

> 2026-11-06 r1436. 오빠 지적: «진화론 메모리와 지침 정리 업그레이드 xclaw, hermes, nanoclaw 제대로 레포 확인해서 한거 맞아? 이렇게 빨리 끝난다고?»
> 1차(r1433·r1434)에는 `~/.hermes/memories/` 파일 3개와 레포 이름만 보고 스캐폴드를 만들었다. **레포 구현을 읽지 않았다.** 이 문서는 그 뒤 실제 코드·문서를 읽고 맞춘 결과다.

## 읽은 것 (경로 · 근거)

| 시스템 | 실제 파일 | 읽은 내용 |
|---|---|---|
| hermes | `~/.hermes/installs/3782703e4002b00b/…/workspace/tools/memory_tool.py` (485줄) | 「MEMORY.md = agent notes · USER.md = user profile. 둘 다 세션 시작 시 **FROZEN 스냅샷**으로 시스템 프롬프트에 들어간다. 세션 중 쓰기는 디스크에만 닿고 프롬프트는 바뀌지 않는다(prefix cache 보존). 단일 `memory` 툴: add/patch/remove + batch operations」 |
| hermes | 같은 폴더 `memory_tool_store.py` (700줄) | `§` 구분자 엔트리 · char 예산(모델 무관) · `atomic_write_text`(temp+rename) · **drift 가드**(round-trip 안 되면 .bak 저장 후 쓰기 거부 = 무음 유실 방지) · **주입 스캔**(`_scan_memory_content`, strict — 메모리가 세션을 넘어 살아남으므로) · 실패 분류 메트릭 |
| hermes | `~/.hermes/cron_migration_prompts/daily-memory-maintenance.md` | 매일 23:00 메모리 정비 크론: 오늘 `memory/YYYY-MM-DD.md` 확인 → 정리 → 중요 내용 `MEMORY.md` 반영 → Slack 보고 |
| nanoclaw | `feature-pack/nanoclaw/README.md` · `skill/SKILL.md` | Memory = `groups/{name}/memory/` 에 **3분류**: `directives.md`(지침) · `mistakes.md`(실수) · `achievements.md`(성과). 그룹 = 페르소나, 매 태스크 컨테이너, SQLite + Redis 미러 |
| xclaw 아카이브 | `~/Project/xclaw-legacy-archive/docs/nanoclaw-analysis/nanoclaw-deep-analysis.md` | 세대 진화 = **in-place mutation + `CLAUDE.md.gen-{N}` 버전 파일**(폴더 복사·이름변경은 SQLite FK 를 깨서 금지) · `conversations/` 아카이브가 진화 입력 · Phase 2 에서 구현 |

## 채택한 축 (코드에 반영)

| 축 | 출처 | ft 반영 |
|---|---|---|
| 세션 시작 1회 FROZEN 스냅샷(중간 쓰기는 파일만) | hermes `memory_tool.py` | `ft-lessons.sh snapshot` — 3계층을 예산(기본 2048B) 안에서 1회 출력, 쓰기 0 |
| 엔트리 3분류 | nanoclaw `memory/{directives,mistakes,achievements}.md` | `add … --kind directive\|mistake\|achievement` → 줄 앞 `[D]/[M]/[A]` 태그 |
| 원자적 쓰기(temp+rename) | hermes `atomic_write_text` | `atomic_write()` — append 도 전문 재작성으로 바꿔 반쪽 파일 0 |
| drift 가드 | hermes `_drift_error` | 상한의 2배를 넘으면 `.drift-<시각>.bak` 저장 후 rc1 «손편집 drift» |
| 주입·유출 스캔 | hermes `_scan_memory_content`(strict) | `INJECT` 6패턴 — 메모리에 들어가면 세션을 넘어 살아남으므로 저장 전 REJECT |
| 세대 = in-place + `gen-N` | xclaw 아카이브 딥분석 | `ft-evolve.sh --apply` → `state/evolution/gen-<NNN>.md` 누적(폴더 이동·이름변경 0) |
| 하루 1회 정비 창 | hermes 23:00 daily-memory-maintenance | `--gate` 하루 1회(기존 00:10 ft-issues-daily 끝) — **새 크론 0** |

## 버린 축 (의도)

| 축 | 왜 안 넣었나 |
|---|---|
| LLM 이 메모리를 스스로 반영(hermes 23:00 크론의 판단 단계) | 발주 상한 «LLM 호출 ≤1» · 좌석 LESSONS 는 팀장·사람이 승격 판단(잘못된 일반화가 전 좌석에 퍼지는 것을 막는다). 후보만 모으고 반영은 사람 |
| SQLite + Redis 미러(nanoclaw) | fable-team 은 파일이 계약(추적·diff·복구). DB 는 좌석 통신에 이미 mbox jsonl 이 있다 |
| 폴더 복사로 세대 교체 | FK·참조가 깨진다(xclaw 실패 사례 그대로). in-place + 버전 파일만 |
| 임베딩/벡터 검색 | 지금 규모(좌석 수십 · 파일 수 KB)에서 검색 이득 < 유지비용. 필요해지면 그때 |

## 남은 것

- hermes `daily-memory-maintenance` 의 «일별 파일 → 장기 반영» 자리에 해당하는 ft 쪽 단계는 아직 «사람 판단» 뿐이다. 자동 반영이 필요해지면 `ft-evolve --apply` 뒤에 «좌석 LESSONS 초안 append» 를 붙인다(지금은 후보 파일까지만).
- nanoclaw `conversations/`(진화 입력 아카이브)에 해당하는 축 = 우리는 세션 jsonl 이 이미 그 역할(측정·증류)을 한다. 별도 아카이브를 만들지 않았다.
