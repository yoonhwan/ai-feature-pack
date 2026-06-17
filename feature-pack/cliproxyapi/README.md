# 🔗 cliproxyapi (headroom + CLIProxyAPI)

**Claude/Codex/Gemini 구독을 API처럼 쓰는 로컬 프록시 스택** — Hermes·Slack·Discord 게이트웨이 연동 포함.

```
Hermes (cc-cloak 패치)
  → headroom :8790      컨텍스트 압축
  → CLIProxyAPI :8317   OAuth 멀티계정 + cloak
  → 구독 plan (extra usage 회피)
```

## 왜 쓰나

- **구독 한도**로 Claude/Codex/Gemini 사용 (API 키 과금 대신)
- **멀티계정 round-robin** (cliproxy)
- **긴 세션 토큰 절약** (headroom 압축)
- Hermes 게이트웨이에서 `400 extra usage` 방지 (tool name cloak + UA 제어)

## 의존성

| 항목 | 필수 | 비고 |
|------|:----:|------|
| [headroom](../headroom/) | ✅ | 별도 피처팩 — upstream 체인 |
| Hermes | 선택 | `patches/hermes-cc-cloak.patch` |
| OAuth 구독 | ✅ | 사용자가 대시보드에서 로그인 |

## 구성

```
cliproxyapi/
├── INSTALL.md              ← 에이전트 원샷 설치 (핵심)
├── README.md               ← 이 파일
├── SKILL.md                ← 운영·진단 스킬
├── scripts/doctor.sh       ← 스택 진단 (--fix)
├── references/playbook.md  ← 설치·트러블슈팅 정본
└── patches/
    └── hermes-cc-cloak.patch
```

## 빠른 시작

```bash
git clone https://github.com/yoonhwan/ai-feature-pack.git
# 에이전트에게:
# "feature-pack/cliproxyapi/INSTALL.md 읽고 설치해줘"
```

사용자가 직접 하는 것: **대시보드 OAuth만** (`http://127.0.0.1:8317/management.html`, key: `hermes-mgmt-key`).

검증:

```bash
bash feature-pack/cliproxyapi/scripts/doctor.sh
```

## 지원 환경

- **macOS arm64** — playbook 기준 (Intel/Linux는 바이너리·LaunchAgent 경로 조정)
- `python3.12+`, `curl`, `git`

## 상세

- 플레이북: `references/playbook.md` (§6 400 트러블슈팅, §10 게이트웨이, §11 Discord)
- headroom 설치: `../headroom/README.md`
