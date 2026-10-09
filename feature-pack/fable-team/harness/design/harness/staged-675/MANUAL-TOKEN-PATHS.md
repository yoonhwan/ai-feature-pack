# 수동 토큰 경로 폐지 후보 목록 (판정 675 · 목록만 — 바꾸는 것은 별 단위, master/arch 선택)

> 범위: 추적 문서·스킬 중 «현역 안내»만. 옛 기록(완성 카드·DA 판정문·HANDOFF·VERDICT·evidence·orders·archive)은 제외.
> 검색: `git grep -E "get-token\.sh|byz_admin_token_dev|byz_org_admin_token_dev|오빠 발급|오빠가 토큰"` + `grep -r ~/.claude/skills ~/.claude/rules`(홈 스킬·규칙은 해당 0건 — 멍청한짓 원장 1행은 기록이라 제외).
> 구분: ⓐ«사람이 토큰을 복사해 넘기라»는 안내 = 폐지 대상 · ⓑ«get-token.sh 로 비밀번호를 쳐 직접 로그인»(개인 시험 계정) = 별개 흐름이라 유지 검토.

| # | 파일:행 | 현 문구(요약) | 구분 | 바꿀 문구(안) |
|---|---|---|---|---|
| 1 | design/cfo/GUIDE-ops-console-access-tour-20260929.md:238 | 「B2B 시험용 로그인 토큰 1개(오빠 발급 · 수명 ≈1h · `.fable-team/secrets/byz_admin_token_dev` 같은 600 파일)」 | ⓐ | 「`bash <루트>/.fable-team/bin/ft-op-token.sh <email>` 로 새로 발급(cred 없으면 `--init` 1회만 사람 손)」 |
| 2 | .claude/skills/byz-e2e/docs/api-test.md:9,15 | 「get-token.sh — 로그인 → `$BYZ_TOKEN`」 · `source … <email> <password>` | ⓑ | 운영(dev) 계정은 `ft-op-token.sh` 안내 1줄 추가 · 개인 시험 계정은 유지 |
| 3 | .claude/skills/byz-e2e/scripts/api-test.sh:3,15 · byz-ops/scripts/api-test.sh:3,15 · byz-test/scripts/api-test.sh:3,15 | 「전제: source get-token.sh 로 `$BYZ_TOKEN` 설정」 안내 echo | ⓑ | 위와 같음(같은 사본 3개 — 한 번에) |
| 4 | .claude/skills/byz-ops/SKILL.md:112 | 부속 `scripts/ops/get-token.sh` (로그인 → `$BYZ_TOKEN`) | ⓑ | `ft-op-token.sh` 병기 |
| 5 | .claude/skills/byz-ops/scripts/credit-seed.sh:64,177 | 리포 루트의 get-token.sh 를 `source` 해 토큰 발급 | ⓑ | 코드 호출부 — 바꾸려면 시험 필요(이 카드 밖) |
| 6 | .claude/skills/byz-test/SKILL.md:11,23,32,41 | get-token.sh 로 로그인 → 토큰 → API 호출 | ⓑ | `ft-op-token.sh` 병기 |
| 7 | docs/ops/loom-operations-runbook.md:94 | `source scripts/ops/get-token.sh <email> <password>` | ⓑ | 운영 계정이면 `ft-op-token.sh` 안내 |
| 8 | design/cfo/inbox/07-서울-PG-라이브-조회-관측.md:76,112 | 같은 명령 + `BYZ_E2E_LOGIN_*` 변수 | 카드(진행 중이면 현역) | 카드 담당(cfo)이 판단 |

참고: `scripts/ops/get-token.sh:41`(토큰 끝 20자 화면 출력)은 별도 요청 R33·#915 소관 — 이 카드와 무관.
