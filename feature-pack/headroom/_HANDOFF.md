# headroom-pack — 핸드오프 (총정리)

> 2026-06-08. headroom feature-pack 퍼블릭 docs + 사용자 레벨 토글 스킬 패키징 완료.

## 무엇을 만들었나 (파일 목록)

### Task A — 퍼블릭 docs (`feature-pack/headroom/`)
- `README.md` — 외부 공유용. headroom 정의 → 왜(carry/re-prefill 비용, rate-limit) → 멘탈모델 3종(3-zone / 캐시vs압축 / 프리필 타이밍) → 설치 → 사용(fail-open 래퍼 + `/stats`) → 어디에 강한가 → **정직한 한계**(단발 0%, 긴 세션만, 디버깅 retrieve 주의). 수치는 공유본 기준(83.7% / 0% / 25~30%, cache_bust=0, 1h 캐시).
- `SSOT.md` — 내부 SSOT 12섹션의 퍼블릭 변환판. 민감정보 0건(스캔 통과).

### Task B — 사용자 레벨 토글 (`~/.claude/skills/headroom/`, `~/.headroom/`)
- `~/.claude/skills/headroom/SKILL.md` — `/headroom on|off|status` + "헤드룸 켜/꺼/상태" 트리거. 영어 frontmatter + 한국어 본문.
- `feature-pack/headroom/SKILL.md` — **위 스킬의 복사본**. 피처팩과 '같이 오픈'되도록 동봉(설치 시 `~/.claude/skills/headroom/`로 배치). 본 복사본 포함 폴더 전체 민감정보 0건.
- `~/.headroom/enabled-projects.json` — 신규 생성. 활성 프로젝트 root 절대경로 **배열**(영구 레지스트리). 초기값 `[]`.
- `~/.headroom/claude-hr.sh` — **레지스트리 인식형으로 업데이트**. 기존엔 무조건 8790 경유였으나, 이제 `enabled-projects.json`을 읽어 **현재 프로젝트가 등록 + 프록시 health OK** 일 때만 경유. 미등록/프록시다운/파싱실패 = 직결(fail-open).
- **canonical root 해석 (워크트리 라우팅 버그 수정)** — 4곳(래퍼 + on/off/status) 모두 프로젝트 root를 `git rev-parse --path-format=absolute --git-common-dir`의 dirname으로 판정. `--show-toplevel`은 워크트리별 경로를 반환해 메인 root 등록과 매칭 실패(워크트리 작업 시 라우팅 누락) → canonical root는 **메인+모든 워크트리를 동일 root로 매핑**하므로 한 번 `on`하면 워크트리 전체 커버. 실제 워크트리에서 E2E 매칭 통과.

### Task C
- `_HANDOFF.md` — 이 파일.

## 토글 스킬 사용법 (3줄)
1. `/headroom on` — 현재 프로젝트(git root)를 레지스트리에 등록 → 영구 활성. 프록시 미기동이면 기동 명령 안내(자동 기동 안 함).
2. `/headroom off` — 레지스트리에서 제거 → 영구 비활성. 프록시 프로세스는 안 건드림(타 프로젝트 공유).
3. `/headroom status` — 현재 프로젝트 on/off + 프록시 health + `/stats`의 `cache_bust_count`(0 확인) 요약. 실행은 `claude-hr` 래퍼(`alias claude-hr='~/.headroom/claude-hr.sh'`).

## 검증 결과
- 민감정보 스캔(내부 코드네임·절대경로 패턴) → **0건** (SKILL.md 복사본 포함 전체 폴더).
- 래퍼 레지스트리 로직: 미등록→직결 / 등록→경유 / 멱등성(중복 on→1건) / off→복구 **모두 통과**.

## 다음 액션
- **프록시 상시화 결정** — `headroom install apply --preset persistent-service` + LaunchAgent 적용 여부. 단독 상시화 금지, fail-open 래퍼와 반드시 함께.
- **멀티 에이전트 swarm 크루 적용** — crew 컨테이너 spawn 시 `ANTHROPIC_BASE_URL=http://host.docker.internal:8790` 전파(이미지 무수정). resume cold prefill이 강타깃.
- **rate-limit A/B** — `/api/oauth/usage` 폴러로 압축 on/off의 한도 소모 속도 실측(PoC 2단계).

## 미해결
- **swarm 크루 세션 모델 확인** — 크루가 작업 단위 간 컨텍스트를 이어가나(=재prefill 폭식 확정, headroom 강타깃) vs fresh-per-task(이득 제한적). 적용 전 선결 확인 필요.
- warm cache_read가 구독 한도에 0.1x로 카운트되는지 풀 중량인지 비공개(cache_create는 명백히 풀).
