# r413 master 집행 순서 (나노는 push 0)

나노 커밋: 02b4449b3e3d65030ddc35be939b56970e2e30df · 브랜치 `nano/r413-worktree-stale-bin-copy-shim-instal` · base origin/main cfb975e1 · 팩 워크트리 `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/r413-stale-bin-copy`

0. (운영 · 카드 밖 · 지금 가능 · 착지와 무관) 공유 루트 shim 설치
   `bash /Users/yoonhwan/Project/ai-feature-pack/.worktrees/harness-live/feature-pack/fable-team/harness/install.sh --apply --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live`
   → `SHIM n · MOVED m · UNKNOWN k` · 그 cwd 에서 `bash .fable-team/bin/ft-nano-close.sh --help` drift OK 확인 → v65 master 에 «nano-close 가능» 1줄
   (나노가 dry-run 만 실측: rc0 · 쓰기 0)
1. push + PR: `git -C <팩 워크트리> push -u origin nano/r413-worktree-stale-bin-copy-shim-instal` → `gh pr create --base main` (제목 = 커밋 첫 줄)
2. 착지 뒤 설치: `bash <팩>/harness/install.sh --apply --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` → `ft-live-install-check.sh --range <병합 전 main>..<착지 sha> --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents`
   — 이제 워크트리 옛 사본이 `STALE-COPY` 로 보인다(v6-live 는 0 에서 고쳤으면 빠짐 · loom-domain-hierarchy · c-level-planning · cfo-ops · cfo-pg · cfo-pgvec 는 같은 install 명령 · 각 팀 master 통지)
3. 실사건 2(3b): v6-live cwd `bash .fable-team/bin/ft-seat-close.sh byz-v65-tester-claude#69 --reason "판정 2341 팀장 하나만" --verdict 2341` → `CLOSED-ROLE …`
4. 별도 고침 단위(이 카드 밖 · base cfb975e1 에서도 같은 실패): `preexisting-fails.txt` 5종 — r385 뒤 픽스처 인자(--kit·--path·FT_HARNESS_ROOT) 미갱신 추정

press 필요: 없음(하네스 도구 · 오디오 경로 0)
