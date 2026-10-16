"""매거진 지침 시험 공용 — 지침(GUIDE-magazine-20261016 §4) 대로 쓴 원장 견본 + 임시 git 저장소 · 인자 만들기 (실 원장 읽기 0 · 네트워크 0)."""
from pathlib import Path

from _magazine_fakes import FakeMagazineSlack, git

DATE = "2026-10-16"
GOOD = """# 오빠 원장 — 시킨 일 · 하기로 한 일 · 지금 상태 (정본 · planner 관리)

> 매거진(하루 전체)과 뉴스(바뀐 것)는 이 파일 하나에서만 만든다. 칸 규칙 원문 = archive/PLAN-oppa-ledger-full.md 머리(판정 1437).
> 마지막 갱신: 2026-10-16 08:5x · planner#55

**결론**: 9팀 중 6팀이 일하고 있어요. 오빠 차례는 2건이에요.
**눈여겨볼 줄**: 노출된 키, 실시간 통역

---

## 1. 오빠가 시킨 일 — 지금 상태

### 10-16 시키신 일
| 순번 | 시키신 일 | 종류 | 지금 상태 | 발주 쪽지 |
|---|---|---|---|---|
| 1 | 노출된 키 17개 교체 (판정 1753 · 1783) | 코드 | 진행 — 키 이름 규칙 확정 (판정 1786) | 97655 |
| 2 | 실시간 통역 main 합치기 | 코드 | 진행 — 시험 실패 고치는 중 | 97700 |
| 3 | Supabase 메일 링크 | 오빠 확인 | 오빠 확인 대기 | |
| 4 | 전체 정리 절차 | 문서 | 막힘 — 검토 직전 정지 | |
| 5 | 통역 툴바 접기 | 코드 | 완료 — 배포 화면 확인 (판정 1765 · #1612) | |
| 6 | 운영 화면 | 코드 | 진행 — 두 번째 제안서 | |

## 2. 오빠 할 일 (10-16)
- 지금:
  - 명령 한 줄 실행 — 뉴스 자동 발행을 설치해요. `! bash /tmp/h34`
  - 시연 1인 리허설 — 순서표를 받아야 시작해요. (판정 1854)
- 막힌 대기:
  - 키 교체 첫 키 인터뷰 대기
- 다음에 올 것:
  - 키 교체
  - main 합치기 승인
- 진행 중 위험:
  - main 합치기 후보에서 시험 21개가 실패해요. (판정 1816 · #1612)

## 2-1. 발주한 것 (planner → 팀 · 지금 상태)
| 발주 | 받은 팀 | 지금 상태 |
|---|---|---|
| 매거진 개선 | 하네스 | 진행 — 견본 |

## 3. 팀 작업 (10-16)
| 팀 | 지금 하는 것 | 다음 |
|---|---|---|
| 실시간 통역 | main 합치기 시험 고치기 | 검증 → 오빠 승인 |
| 컨시어지 | 쉼 — 해설 확인 대기 | 확인 뒤 음성 재생성 |

## 4. 드러난 문제
- 진행 카드의 상태 표시가 실제와 달라요 — 카드 상태 정리가 먼저예요.
- 오빠 지시가 작업 카드로 이어졌는지 사람이 찾아야 해요. (3e4578339b)

## 5. 완료 보관 (오빠가 매거진에서 «본» 완료 줄)
| 순번 | 시키신 일 | 종류 | 닫는 증거 | 내린 날 |
|---|---|---|---|---|
| 10-15-1 | 가입 메일 | 코드 | main abc1234 | 10-15 |
"""


def make_env(tmp_path: Path, text: str = GOOD) -> tuple[Path, Path]:
    """(tmp, 원장 저장소) — doc.md 를 1커밋으로 둔 임시 저장소 + 가짜 Slack 토큰 파일."""
    repo = tmp_path / "repo"
    repo.mkdir()
    git(repo, "init", "-q", "-b", "main")
    for k, v in (("user.email", "t@t"), ("user.name", "t")):
        git(repo, "config", k, v)
    (repo / "doc.md").write_text(text, encoding="utf-8")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "doc")
    (tmp_path / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-test\n", encoding="utf-8")
    return tmp_path, repo


def commit(repo: Path, text: str) -> None:
    (repo / "doc.md").write_text(text, encoding="utf-8")
    git(repo, "commit", "-qam", "edit")


def argv(env: tuple[Path, Path], mode: str, slack: FakeMagazineSlack | None = None, date: str = DATE) -> list[str]:
    tmp, repo = env
    base = ["--src-repo", str(repo), "--src-sha", "HEAD", "--src-path", "doc.md", "--date", date, "--out-dir", str(tmp / "out"), "--state", str(tmp / "state.json"), mode]
    if slack:
        base += ["--token-file", str(tmp / "tok"), "--slack-base", slack.base, "--channel", "C1"]
    return base


def page_of(env: tuple[Path, Path]) -> str:
    return max((env[0] / "out").glob("MAGAZINE-DOC-*.html"), key=lambda p: p.stat().st_mtime_ns).read_text(encoding="utf-8")
