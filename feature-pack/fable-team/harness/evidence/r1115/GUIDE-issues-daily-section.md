# GUIDE-issues.md 에 넣을 절 «일일 표» (초안 — 확정 = issues master · 열 이름·우선순위 규칙 정본)

> 자리 = `design/teams/issues/GUIDE-issues.md` 끝 절. 이 파일은 **초안**이다 — 나노는 `design/teams/` 가 없는
> 스파스 워크트리에서 작업했고, 카드 §완료 조건이 «가이드 절 = issues master» 로 되어 있어 경로만 만들지 않았다.
> 옮길 때 아래 블록을 그대로 붙이고 열 이름만 issues master 판단으로 고친다.

---

## 일일 표 (매일 00:10 · 장치가 쓴다)

하루 1회 launchd(`com.byz.ft-issues-daily`)가 열린 Issue 전부를 읽어 표 1장을 쓰고, planner master·issues master 에
쪽지 2통(본문 다름)을 보낸다. **장치는 읽기만 한다** — 라벨·배정·닫기·코멘트 쓰기 0.

- 표 파일: `design/teams/issues/daily/TABLE-daily-<YYYYMMDD>.md` (장치가 폴더째 만든다 · 커밋은 issues master 아침)
- 만드는 도구: `ft-issues-daily.sh [--dry-run] [--date YYYYMMDD]`
- 경보: 표가 00:40 까지 없거나 «판정 불가» 면 harness master 에 1통(하루 1회) = `ft-issues-daily-check.sh`

### 열 이름 (고정)

| 절 | 줄 | 뜻 | 결정하는 사람 |
|---|---|---|---|
| ① 머리 | `열린 총수` · `상태별(approved·status:proposal-pending·needs-triage·라벨 없음·그 밖)` · `합:` 검산 · `어제 대비` | 한 이슈 = 한 칸(approved → proposal-pending → needs-triage → 라벨 없음 → 그 밖 첫 일치) | — (값) |
| ② 정리 | `새로 열린(24h)` · `닫힌(24h)` · `7일+ 정체(갱신일 기준)` · `중복 후보(제목 정규화 같음)` | «후보» 만 — 판정 낱말 금지 | — (값) |
| ③ 분류 | `작성 경로`(① 기획 세션 · ② 세션 에이전트 · ③ 오빠 GitHub · ④ 사내 멤버 · 미분류) · `라벨: type/t team/없음` | ft-issue-classify 규칙 재사용 | — (값) |
| ④ 우선순위 후보 | `축`(ⓐ~ⓔ) · `제목` · `근거` | 축 순서 = ⓐ 오빠 지시·priority → ⓒ proposal-pending → ⓑ type:bug+본문 재현 → ⓓ 7일+ 정체 → ⓔ 나머지 | planner |
| ⑤ 팀 배정 후보 | `팀 후보` · `근거` | `team:*` 없는 것만 · 키워드 후보에 «(후보)» 표기 · 라벨 쓰기 0 | issues master |
| ⑥ 닫기 후보 | 번호 + 제목 | 닫기 8항이 코멘트로 다 있는 것만 · **실행 판정 = `ft-issue-close-check.sh <#>`** | issues master |

규칙 세 줄:
1. **ⓒ 를 ⓑ 보다 앞에 둔다** — proposal-pending 은 게이트 앞이라 어느 목록에도 안 실려 묻힌다(판정 2776 · #3807 사고).
2. **«후보» 낱말만 쓴다** — 표는 판정하지 않는다. 확정·승인 같은 낱말은 표에 쓰지 않는다.
3. **0 으로 숨기지 않는다** — 못 읽으면 «판정 불가», 정지·동결이면 «건너뜀(사유)» 로 적는다(하드 룰 20).

### 아침 집행 루틴 (사람 3줄)

1. 표 ⑥ 닫기 후보 → `ft-issue-close-check.sh <#>` 로 실제 판정 → 통과만 닫는다.
2. 표 ⑤ 팀 후보 → `team:*` 라벨을 붙인다(장치는 안 붙인다).
3. 표 ④ ⓒ(proposal-pending)와 ⓓ(7일+ 정체) → 우선순위 재판정 · 표 파일을 커밋한다.
