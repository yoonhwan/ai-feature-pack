# fable-team ft 2.0 (ft2/)

ft 2.0 의 새 뼈대다. 2.0 활성 소스는 이 폴더 안에서만 쓴다.
정본 PLAN §2.0.0 3항: «2.0 활성 소스·파일 구조는 새로 작성한다. 격리된 1.x 도구는 실행·import·자동 fallback 의존 대상으로 쓰지 않는다.»

## 폴더 책임 (폴더 하나 = 책임 하나)

| 폴더 | 책임 | PR |
|---|---|---|
| `core/` | 좌석·쪽지·발주 같은 2.0 공통 코어. 실행 환경 차이를 모른다 | PR② |
| `contracts/` | 카드·계약·시험 대응표의 2.0 계약 정의 | PR② |
| `contracts/models/` | 모델 표 3개(model-scope·model-fallback·provider-of-model) 정본 자리 — `tools/models.py` 가 읽는다 | PR② |
| `adapters/slack/` | Slack 수신·발행 어댑터 | PR③ |
| `adapters/codex/` | Codex 실행 어댑터 | PR④ |
| `adapters/pi/` | Pi 실행 어댑터 · 호출자 좌석 열기(`launch.py`) | PR④ |
| `doctor/` | 설치·환경 진단 | PR④ |
| `tools/` | 검사기·보조 도구 | 공통 |
| `tests/` | ft2 시험 | 공통 |

## 1.x 의존 금지

- `ft2/` 의 어떤 파일도 1.x 경로·도구를 실행·import·source 하지 않는다.
- 검사 패턴: `legacy/1.x` · `harness/bin` · `harness/kit` · `LIVE_BIN` · `.fable-team/bin`.
- 검사 확장자: `.py` `.sh` `.ts` `.js` `.json`. `*.md` 는 산문이라 허용한다.
- 코드 파일 주석도 검사한다. 주석 처리된 1.x 경로는 다음 사람이 되살린다.

## 검사기

```bash
python3 feature-pack/fable-team/ft2/tools/legacy_guard.py          # ft2/ 자기검사
python3 feature-pack/fable-team/ft2/tools/legacy_guard.py <폴더>   # 다른 트리 검사
```

종료 코드: `0` = 위반 0 · `1` = 위반 있음(`<파일>:<줄>: <패턴>` 1줄씩) · `2` = 사용법·경로 오류.

## 한계

문자열 검사다. 동적으로 조립한 경로는 못 잡는다. 동적 조립은 리뷰와 DA 가 본다.
