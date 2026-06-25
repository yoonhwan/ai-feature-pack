# cairn 훅 설치

git 훅(자동 lineage 캡처):

    ln -s ../../scripts/hooks/post-merge    .git/hooks/post-merge
    ln -s ../../scripts/hooks/post-checkout .git/hooks/post-checkout

baton/tmuxc 연동(execution_ref/session_ref)은 각 도구의 wt-create / 세션생성 훅에서 cairn을 호출:

    cairn link <node> --execution-ref <worktree>
    cairn link <node> --session-ref <session>
    cairn link <node> --merge-back-to <node>

reconcile(주기/수동): 활성 worktree에 없는 execution_ref를 가진 노드를 orphan 후보로 보고.

    cairn reconcile
