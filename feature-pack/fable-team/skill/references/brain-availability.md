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

## 2. 대체 추천표 (미가용 시 인터뷰에서 제시)

| 기본 배정 | 1순위 대체 | 2순위 대체 | 비고 |
|-----------|-----------|-----------|------|
| DA 브레인: codex gpt-5.5 xhigh | **claude-opus-4-6 high** (Agent/Workflow 직접) | gemini (`gemini -p`, 있으면) | 대체 시 **author-review 프로바이더 분리가 깨짐** → implementer와 다른 모델 계열 유지가 최소 조건 (implementer=opus4.6이면 DA=sonnet-4-6 high로 조정) |
| implementer의 codex/cursor 위임 | 위임 없이 claude implementer가 직접 구현 | — | 템플릿의 위임 문단을 제거하고 설치 |
| planner: fable5 | claude-opus-4-6 max | claude-sonnet-5 high (Workflow) | fable5 미가용(요금제 등) 시. 두뇌 역할이므로 가용한 최상위 모델 |
| tester: sonnet5 | claude-sonnet-4-6 high | — | Workflow→Agent 경로로 바꾸면 4.6은 effort 함정도 없음 |

## 3. 인터뷰 반영 규칙

- 프로브 결과를 표로 보여주고, 미가용 브레인이 배정된 역할마다 **추천 대체안을 기본 선택지로** 제시 (열린 질문 금지).
- DA를 claude로 대체한 경우: 템플릿 `{{DA_BRAIN_MODEL}}`에 claude 모델을 넣고, codex exec 문단 대신 "너 자신이 판정 브레인이다" 문단으로 치환 (`ft-da-claude.md.tpl` 사용).
- 대체 구성은 설치 기록(`<대상>/.fable-team/install.json`)에 `substitutions` 필드로 남긴다 — 이후 codex가 설치되면 재인터뷰로 승격 가능함을 고지.

## 4. 설치 기록 형식

```json
{
  "installed_at": "YYYY-MM-DD",
  "target": "user | project:<path>",
  "prefix": "ft",
  "brains": {"planner": "claude-fable-5/max", "da": "codex gpt-5.5/xhigh", "...": "..."},
  "substitutions": [{"role": "da", "wanted": "codex", "used": "claude-opus-4-6/high", "reason": "codex MISSING"}],
  "availability": {"codex": true, "cursor-agent": false, "gemini": false}
}
```
