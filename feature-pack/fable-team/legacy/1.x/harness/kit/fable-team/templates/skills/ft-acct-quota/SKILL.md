---
name: ft-acct-quota
description: cliproxy OAuth 계정(claude·codex·gemini)의 쿼터·복구 시각·남은 시간을 표로 보여준다. 계정 몇 장이 살아있는지, 언제 풀리는지, 어느 파일이 중복 슬롯인지 확인할 때 쓴다. 트리거 - 계정, 쿼터, 한도, 리밋, 복구, 남은 시간, 몇 장, quota, rate limit, usage, reset, 계정 정리, 중복 계정.
---

# ft-acct-quota — 계정 쿼터·복구 표

## 언제 쓰나
- "계정 몇 장 살아있어?", "언제 풀려?", "리밋 언제 끝나?"
- 새 계정 추가·중복 정리 후 상태 확인
- 재개 시점 결정(가장 빨리 풀리는 계정이 언제인지)

## 실행
```bash
ft-acct-quota                 # 표 (파일·5h·주간·리셋·남은시간·비고)
ft-acct-quota --timeline      # 복구 시각 순 (남은 시간 포함)
ft-acct-quota --json          # 기계 판독
ft-acct-quota --provider codex
ft-acct-quota --no-net        # 파일 값만 (네트워크 0)
```

## 읽는 법
| 열 | 의미 |
|---|---|
| `5h` / `주간` | 사용률 %. 100% = 소진 |
| `5h 리셋` / `주간 리셋` | `MM-DD HH:MM` (KST) |
| `남은` | `3d 18h` = 복구까지 남은 시간. `복구됨` = 이미 지남 |
| `tier/plan` | `max_20x` · `max_5x` · `pro` · `plus` · `prolite` |
| `비고` | `DISABLED`(파일 비활성) · `중복슬롯(유지=…)` · `usage endpoint 없음` |

## 판정 규칙 (2026-11-06 실측으로 배운 것)
1. **중복 판정은 `account_uuid` 만으로 하지 않는다.** 같은 사람이 개인 org(20x)와 팀 org(5x)를 각각 구독하면 쿼터가 **별개**다. 실제로 같은 uuid 2장이 리셋 시각·tier 가 달랐다.
2. codex 는 같은 `account_id` 에 pro/plus/prolite 파일이 겹치면 **중복슬롯**이다. 유지 우선순위 = pro > plus > prolite.
3. `refresh_token` 해시가 다른 중복은 rotation 으로 한쪽이 죽는다. 같은 구독의 중복이면 1장만 남기고 `disabled: true`.
4. gemini(antigravity)는 usage endpoint 가 없다 — 파일 존재만 표시한다.

## 데이터 출처
- 파일 = `~/.cli-proxy-api/{claude,codex,antigravity}-*.json` (`FT_AUTH_DIR` 로 변경)
- claude = `GET api.anthropic.com/api/oauth/usage` + `/profile`
- codex = `GET chatgpt.com/backend-api/wham/usage` (`chatgpt-account-id` 헤더)
- 네트워크 = 계정당 1회 · 7초 상한 · 읽기만(파일 수정 0)
