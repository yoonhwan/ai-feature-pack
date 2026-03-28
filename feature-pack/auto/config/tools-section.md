### 🔬 AutoResearch (자율 실험 루프 스킬)

- **스킬**: `/auto` (순수 스킬, 외부 CLI 없음)
- **기반**: Karpathy AutoResearch 패턴
- **용도**: 타깃 파일 1개를 자율적으로 수정→실행→평가→commit/revert 반복하여 최적화

**주요 명령어:**
```bash
/auto            # 전체 흐름 (setup → baseline → 목표 → 자율주행)
/auto setup      # autoresearch/ 폴더 초기화만
/auto 2h         # 2시간 자율주행
/auto resume     # 기존 브랜치에서 이어서
/auto report     # 결과 리포트만 생성
/auto update     # upstream 클론 git pull
```

**에이전트 자동 발동:**
- "auto", "autoresearch", "자율 실험", "오토리서치"
- "실험 루프", "experiment loop", "자율주행 리서치"
- "베이스라인 돌려", "baseline run"

**핵심 규칙:**
1. **타깃 파일 1개만 수정** — 다른 파일 절대 건드리지 않음
2. **실험 전 commit** — 안전한 롤백을 위해 수정 후 즉시 커밋
3. **실패 시 즉시 revert** — `git reset --hard HEAD~1`
4. **전용 브랜치** — `autoresearch/{tag}` 브랜치에서만 작업
5. **results.tsv는 untracked** — git에 추가하지 않음

**프로젝트 구조:**
```
{프로젝트}/autoresearch/
  upstream/        ← karpathy/autoresearch 클론 (참조용)
  program.md       ← 에이전트 지시서
  prepare.py       ← 고정 인프라
  <target>.py      ← 에이전트가 수정할 파일 (1개)
  results.tsv      ← 실험 결과 (untracked)
```
