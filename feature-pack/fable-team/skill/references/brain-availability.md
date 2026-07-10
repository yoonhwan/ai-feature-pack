# 브레인 가용성 체크 & 대응 모델 추천 (설치 인터뷰 §0)

codex·cursor 등 외부 agent-cli가 없는 환경이 있다. **설치 인터뷰 시작 전에 반드시 가용성을 실측**하고, 없는 브레인은 아래 추천표로 대체를 제안한다 (추측 금지 — 실행 결과만 신뢰).

## 1. 가용성 프로브 (설치 시 1회 실행)

```bash
# CLI 존재 (alias 포함 — 비대화 셸에서 alias는 안 풀리므로 zsh -ic로 확인)
for c in codex cursor-agent gemini opencode; do
  printf '%s: ' "$c"; zsh -ic "command -v $c" >/dev/null 2>&1 && echo OK || echo MISSING
done
```

- `codex`가 OK여도 **인증까지 확인**: 프로브 1회 실행 (`npx -y @openai/codex exec --skip-git-repo-check "PONG만 출력" < /dev/null`, 타임아웃 120초). 실패 = 미가용 처리.
- `cursor-agent`는 `cursor-agent status`로 로그인 확인. (주의: `cursor` IDE 바이너리와 다름)
- claude 계열(sonnet/opus/fable)은 현재 세션이 곧 증거 — 별도 체크 불필요.

### 1-1. claude effort 표준(high) 수락 프로브 (D1)

대체 후보로 확정된 claude 모델은 1회 실측(`claude -p --model <m> --effort high` 한 줄 질의 `< /dev/null`) 후 결과를 **4상태로 분류**해 처리한다:

- ⓐ **success** → 그 effort로 확정
- ⓑ **400 `level ... not supported`** → 한 단계 하위 effort(medium) 강등 재시도 — effort 강등은 이 오류 유형에서만(high 거부는 이례 — 발생 시 기록·보고)
- ⓒ **model-unavailable·auth 오류** → effort 문제가 아니므로 강등 금지, **사다리 다음 단으로 하강**
- ⓓ **budget·rate-limit 등 일시 오류** → 판단 보류·재시도(강등·하강 모두 금지)

확정 결과를 `install.json.effort_ceilings`에 기록(FT 업데이트 시 재프로브 생략).

## 2. 재선택 제시표 (미가용 시 인터뷰에서 남은 choices 제시)

> **자동 폴백 금지** — 미가용 발생 시 `BRAIN_UNAVAILABLE <role> <model> <사유>` 1줄 보고 → AskUserQuestion으로 남은 choices를 재제시 → 사용자 선택 후 state.md 갱신.

| 역할 | 기본 choices | 미가용 시 재제시 후보 | 비고 |
|------|-------------|---------------------|------|
| planner | **fable-5/high**, **codex-5.6-sol/high**(→ft-planner-x) | 남은 choice 재제시. 둘 다 미가용이면 **claude-sonnet-5/high** 또는 **claude-opus-4-6/high** 제안 | 두뇌 역할 — 가용 최상위 모델 우선 |
| DA (ft-da) | **codex-5.6-sol/high**, **grok-4.6/high** | 남은 choice 재제시. 둘 다 미가용이면 **claude-opus-4-6/high** (Agent 직접) 제안 — author-review 분리 유지 필수(implementer와 동일 모델 금지) |
| DA2 (ft-da2) | **grok-4.6/high**, **codex-5.6-sol/high** (da의 반대편) | 남은 choice 재제시. da와 이종 조합 유지 권장 |
| analyst | **opus-4-6/high** (고정) | 미가용 시 **sonnet-5/high** 제안 | ask:false — 자동 선택, 질문 없음 |
| implementer | **opus-4-8/high** (고정) | 미가용 시 **opus-4-6/high** 유지 보고 후 사용자 결정 | ask:false |
| tester | **sonnet-5/high** (고정) | 미가용 시 **sonnet-4-6/high** 제안 (Workflow→Agent 경로 전환) | ask:false |
| 오케스트레이터 | **fable-5** 또는 **sonnet-5** (ultracode — 세션 시작 시 사용자 직접 선택) | 세션 모델이므로 재제시 불가 — 다른 세션에서 재트리거 안내 | 자동 폴백 아님 |

## 3. 인터뷰 반영 규칙

- 프로브 결과를 표로 보여주고, 미가용 브레인이 배정된 역할마다 **남은 choices를 재제시** (열린 질문 금지, 자동 대체 금지).
- DA를 claude로 대체한 경우: 템플릿 `{{DA_BRAIN_MODEL}}`에 claude 모델을 넣고, codex exec 문단 대신 "너 자신이 판정 브레인이다" 문단으로 치환 (`ft-da-claude.md.tpl` 사용).
- planner=codex 선택 시: `ft-planner-x.md.tpl` 드라이버를 설치하고 `ft-planner.md`는 비활성(선택 조합에서 제외).
- DA에 grok-4.6 선택 시: `ft-da-cursor.md.tpl` 드라이버를 설치.
- 선택 구성은 설치 기록(`<대상>/.fable-team/install.json`)에 기록하고 state.md `brains:` 라인에도 세션 선택으로 write-through — 이후 브레인이 추가 설치되면 다음 세션 스텝1에서 재선택 가능함을 고지.

## 4. 설치 기록 형식

```json
{
  "installed_at": "YYYY-MM-DD",
  "target": "user | project:<path>",
  "prefix": "ft",
  "brains": {"planner": "claude-fable-5/high", "da": "codex gpt-5.5/xhigh", "...": "..."},
  "substitutions": [{"role": "da", "wanted": "codex", "used": "claude-opus-4-6/high", "reason": "codex MISSING"}],
  "effort_ceilings": {"claude-sonnet-5": "<probe_result>"},
  "availability": {"codex": true, "cursor-agent": false, "gemini": false}
}
```
