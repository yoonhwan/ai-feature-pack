# comm-canonical — 세션간 통신 정본 백업 소스

이 디렉터리는 **백업 소스이지 런타임이 아니다.** 여기 있는 파일을 고쳐도 좌석 통신은 바뀌지 않는다.
실제 좌석 통신은 아래 「런타임 실제 경로」의 추적 밖(untracked) 파일들이 담당한다.
이 디렉터리는 **어떤 심링크의 대상도 아니므로**, 브랜치 전환에 사라져도 통신은 죽지 않는다 — 그래서 추적해도 안전하다.

## 런타임 실제 경로 (정본 1 + 도구 10)

| # | 파일 | 런타임 경로 | 성격 |
|---|------|-------------|------|
| 1 | mbox.py | `.claude/fable-team/bin/mbox.py` | 정본(실파일). 워크트리 경로가 상대 심링크로 이걸 가리킨다 |
| 2 | ft-broadcast.sh | `.worktrees/v6-realtime-live/.fable-team/bin/ft-broadcast.sh` | 도구 |
| 3 | ft-claude-context.sh | `.worktrees/v6-realtime-live/.fable-team/bin/ft-claude-context.sh` | 도구 |
| 4 | ft-context-monitor.sh | `.worktrees/v6-realtime-live/.fable-team/bin/ft-context-monitor.sh` | 도구 |
| 5 | ft-master-tick.sh | `.worktrees/v6-realtime-live/.fable-team/bin/ft-master-tick.sh` | 도구 |
| 6 | ft-pm-tick.sh | `.worktrees/v6-realtime-live/.fable-team/bin/ft-pm-tick.sh` | 도구 |
| 7 | ft-reach-check.sh | `.worktrees/v6-realtime-live/.fable-team/bin/ft-reach-check.sh` | 도구 |
| 8 | ft-seat-status.sh | `.worktrees/v6-realtime-live/.fable-team/bin/ft-seat-status.sh` | 도구 |
| 9 | ft-send-verified.sh | `.worktrees/v6-realtime-live/.fable-team/bin/ft-send-verified.sh` | 도구 |
| 10 | ft-wall-check.sh | `.worktrees/v6-realtime-live/.fable-team/bin/ft-wall-check.sh` | 도구 |
| 11 | ft-wall-read.sh | `.worktrees/v6-realtime-live/.fable-team/bin/ft-wall-read.sh` | 도구 |

> `.gitignore` 의 `.fable-team/` 와 `.claude/fable-team/` 두 줄이 위 경로를 이미 물리 차단한다. **건드리지 마라.**
> 도구 10개는 `v6-realtime-live` 워크트리에만 있다 — 그 워크트리를 정리하면 통신 검증 도구가 통째로 소멸하니 주의.

## 왜 런타임이 untracked 인가 (작동 원리 — 결함 아님)

git 은 브랜치 전환에서 **untracked 파일을 지우지 않는다.** 그래서 루트가 비-main 브랜치인 동안에도 정본이 그대로 살아남아 심링크가 유효하다.
반대로 이 런타임 경로를 **추적본으로 만들면**, 그 파일이 없는 브랜치로 전환할 때 git 이 정리해버려 심링크 3개가 전부 dangling → **mbox 전면 정지**가 된다.
따라서 **런타임 경로를 절대 커밋하지 말고, `.gitignore` 도 고치지 마라.** untracked 인 것이 곧 작동 원리다.

## 복구 절차 (런타임이 사라졌을 때)

리포 루트에서 실행:

```bash
# 정본 mbox.py 복구
cp tools/comm-canonical/mbox.py .claude/fable-team/bin/mbox.py

# 도구 10개 복구
for f in ft-broadcast.sh ft-claude-context.sh ft-context-monitor.sh \
         ft-master-tick.sh ft-pm-tick.sh ft-reach-check.sh \
         ft-seat-status.sh ft-send-verified.sh ft-wall-check.sh ft-wall-read.sh; do
  cp "tools/comm-canonical/$f" ".worktrees/v6-realtime-live/.fable-team/bin/$f"
done

# 실행권한 확인
chmod +x .claude/fable-team/bin/mbox.py .worktrees/v6-realtime-live/.fable-team/bin/ft-*.sh
```

## 드리프트 확인 (자동 반영 안 함 — 사람이 판단)

`check-drift.sh` 는 런타임 vs 백업을 `diff -q` 로 **비교만** 한다. 조용히 덮지 않는다(복사·수정 기능 없음).
드리프트가 잡히면 사람이 보고 어느 쪽이 정답인지 판단한 뒤, 위 복구 절차나 역방향 복사를 **손으로** 실행한다.

```bash
$ bash tools/comm-canonical/check-drift.sh
SAME             mbox.py
SAME             ft-broadcast.sh
...
# 전부 SAME 이면 exit 0. DRIFT / MISSING_RUNTIME / MISSING_BACKUP 가 하나라도 있으면 exit 1.
```

출력 라벨:
- `SAME` — 런타임과 백업이 동일.
- `DRIFT` — 내용이 다름(누가 한쪽만 고쳤다는 신호).
- `MISSING_RUNTIME` — 런타임 파일이 없음(워크트리 정리 등으로 소멸 가능성).
- `MISSING_BACKUP` — 백업 파일이 없음.
