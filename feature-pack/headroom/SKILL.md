---
name: headroom
description: Claude Code 프록시 라우팅 토글 (headroom 압축 · cliproxy 멀티계정 각각 on/off). "/headroom on", "/headroom off", "/headroom status", "헤드룸 켜", "헤드룸 꺼", "cliproxy 켜", "프록시 상태", "라우팅 확인" 요청 시 실행. 두 레이어를 독립 제어하며 자동 활성화하지 않는다.
---

# headroom — 프록시 라우팅 토글

Claude Code 가 어느 프록시를 경유할지 **레이어별로** 켜고 끈다.

| 레이어 | 포트 | 얻는 것 |
|---|---|---|
| **headroom** | 8790 | 컨텍스트 압축 (code-aware). upstream 은 plist 로 cliproxy 고정 |
| **cliproxy** | 8317 | 멀티계정 OAuth 회전 + cloak + 프로토콜 변환 |

## 라우팅 매트릭스

| headroom | cliproxy | `ANTHROPIC_BASE_URL` |
|---|---|---|
| on | on | `http://localhost:8790` — 압축 → 회전 → 구독 |
| off | on | `http://127.0.0.1:8317` — 회전 → 구독, 압축 생략 |
| off | off | unset — Anthropic 직결 |
| **on** | **off** | ⛔ **불가**. headroom LaunchAgent 의 `--anthropic-api-url` 이 `127.0.0.1:8317` 에 고정돼 cliproxy 를 우회할 수 없다. 래퍼가 exit 78 로 거부한다 |

## 명령

모든 조작은 래퍼의 `route` 서브커맨드로 한다. **직접 JSON 을 편집하지 않는다.**

```bash
HR=~/.headroom/claude-hr.sh

$HR route status                    # 현재 프로젝트 유효값 + 프로세스 실상태
$HR route headroom on|off           # 이 프로젝트만
$HR route cliproxy on|off
$HR route headroom on --global      # 전 프로젝트 기본값
$HR route reset [--global]          # 프로젝트 오버라이드 제거 / default 초기화
```

- `/headroom on` → `route headroom on` (압축까지 태움)
- `/headroom off` → `route headroom off` (cliproxy 만 남음 — 멀티계정은 유지)
- `/headroom status` → `route status`

## 상태 파일

`~/.headroom/routing.json` 하나가 SSOT.

```json
{
  "default":  { "headroom": false, "cliproxy": true },
  "projects": { "/abs/project/root": { "headroom": true, "cliproxy": true } }
}
```

- 프로젝트 항목이 있으면 그것, 없으면 `default`.
- 워크트리는 `git --git-common-dir` 기준으로 **본 프로젝트 root 하나로 접힌다** — 워크트리마다 따로 등록할 필요 없다.
- 1회성 오버라이드: `HEADROOM_ROUTE=0|1` · `CLIPROXY_ROUTE=0|1` env (설정보다 우선).

레거시 `enabled-projects.json` · `disabled-projects.json` · `always-route` 는 **더 이상 읽지 않는다** (2026-08-29 스위처 개편).

## 정책

- **fail-closed**: 경유가 요청됐는데 해당 프록시가 죽어 있으면 직결로 몰래 새지 않고 exit 69 로 거부한다. 조용한 폴백은 과금 경로를 바꿔놓고 아무도 모르게 만든다.
- **모델 프리플라이트**: `--model` 이 cliproxy 카탈로그에 없으면 기동 전에 stderr 로 경고한다 (차단은 안 함). 예: `claude-opus-5[1m]` 은 카탈로그에 없고 `claude-opus-5`(200K) 만 있다.
- 글로벌 `ANTHROPIC_BASE_URL` 정적 export 는 금지 — 프록시가 죽으면 전 세션이 동시 마비된다. 이 래퍼 경유로만 설정한다.
- 실행 중인 세션은 env 가 이미 고정돼 있어 **재시작해야** 반영된다.

## 진단

스택 자체(프로세스·OAuth·계정 회전·cloak)의 문제는 이 스킬이 아니라 `headroom-cliproxy` 스킬의 `doctor.sh` 로 본다.
