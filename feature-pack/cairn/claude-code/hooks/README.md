# cairn 훅 설치

git 훅은 프로젝트별 `.git/hooks/`에 연결합니다. `install.sh` 실행 후 전역 설치본의 훅을 연결하세요.

    mkdir -p .git/hooks
    ln -sfn "$HOME/.cairn/current/hooks/post-merge" .git/hooks/post-merge
    ln -sfn "$HOME/.cairn/current/hooks/post-checkout" .git/hooks/post-checkout

검증:

    test -x "$HOME/.cairn/current/hooks/post-merge"
    test -x "$HOME/.cairn/current/hooks/post-checkout"
    test -x "$HOME/.cairn/current/hooks/cairn-auto-progress"
    "$HOME/.cairn/current/hooks/post-merge"
    "$HOME/.cairn/current/hooks/post-checkout"

baton/tmuxc 연동(execution_ref/session_ref)은 각 도구의 wt-create / 세션생성 훅에서 cairn을 호출:

    cairn link <node> --execution-ref <worktree>
    cairn link <node> --session-ref <session>
    cairn link <node> --merge-back-to <node>

reconcile(주기/수동): 활성 worktree에 없는 execution_ref를 가진 노드를 orphan 후보로 보고.

    cairn reconcile

## 자동 진척 후보 훅

`cairn-auto-progress`는 BTS/evidence/verification pass 신호를 감지하면 `.cairn/auto-progress/candidates/`에 완료 후보를 남깁니다.

기본은 원장을 변경하지 않는 후보 생성입니다.

    CAIRN_TASK_ID=t2 CAIRN_VERIFICATION_STATUS=pass \
      "$HOME/.cairn/current/hooks/cairn-auto-progress"

명시적으로 반영하려면 task id와 apply 모드를 함께 지정합니다.

    CAIRN_AUTO_PROGRESS=apply CAIRN_TASK_ID=t2 CAIRN_VERIFICATION_STATUS=pass \
      "$HOME/.cairn/current/hooks/cairn-auto-progress"

안전 경계:

- `CAIRN_TASK_ID`가 없으면 branch의 `t<N>` 또는 단일 `doing` task까지만 후보로 추론합니다.
- 실제 `cairn complete` 반영은 `CAIRN_AUTO_PROGRESS=apply`와 명시 `CAIRN_TASK_ID`가 모두 있을 때만 실행합니다.
- `return_to`가 없는 task는 기존 `cairn complete` 정책대로 차단됩니다. 강제 완료는 `CAIRN_AUTO_PROGRESS_FORCE=1`을 명시해야 합니다.
