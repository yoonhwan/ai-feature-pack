#!/usr/bin/env python3
"""파일 기반 세션 메시지 큐 — ★정본 1부★ (.claude/fable-team/bin/mbox.py, 2026-09-03).

╔══════════════════════════════════════════════════════════════════════════════╗
║ ★★ 이 파일을 git 에 커밋하지 마라 ★★  (직관과 반대다. 그래서 여기 적는다)      ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ 이 파일이 «추적되지 않는» 것은 사고가 아니라 이 배치의 ★작동 원리★ 다.          ║
║                                                                              ║
║ git 은 브랜치를 갈아탈 때 untracked 파일을 지우지 않는다. 반대로 ★추적본이      ║
║ 되는 순간★ 그 파일이 없는 브랜치로 전환하면 git 이 «정리»해 버리고, 이 파일을    ║
║ 가리키는 워크트리 심링크 3개가 ★전부 dangling★ 이 되어 ★mbox 가 전면 정지★     ║
║ 한다. 좌석 사이의 모든 발주·보고가 그 순간 끊긴다.                              ║
║                                                                              ║
║ 실측(2026-09-03) — 이 위험이 가설이 아닌 이유:                                 ║
║   · 루트 워킹트리는 고정돼 있지 않다. reflog 관측 24.6일 중 ★비-main 이 73%★   ║
║     (17.9일), 최장 연속 8.6일. 브랜치 전환 6회.                                ║
║   · 그런데도 오늘 mbox 는 멀쩡했다 — untracked 였기 때문이다.                   ║
║   · `git ls-tree` 로 확인한 4개 브랜치 전부에 이 파일이 ★없다★.                ║
║     (양성대조: 같은 명령이 .claude/hooks/orchestration-gate.sh 는 잡았다.)      ║
║                                                                              ║
║ .gitignore 에 `.claude/fable-team/` 을 넣어 물리적으로도 막아 두었다 —          ║
║ 주석은 규율이고, 규율만으로는 안 지켜진다는 것이 오늘 하루의 결론이다.           ║
║                                                                              ║
║ 사라졌을 때의 복구본: state/mbox-seq/mbox.py.canon  ← ★링크 대상이 아니다★.     ║
║ 실행 진입점은 여전히 이 파일 하나뿐이고, 그쪽은 순수 백업이다. 둘은 갈릴 수     ║
║ 있으므로, 복원할 때 조용히 덮어쓰지 말고 ★다르면 경고★ 해야 한다.               ║
╚══════════════════════════════════════════════════════════════════════════════╝

각 워크트리 .fable-team/{bin,comm}/ 의 mbox.py·ft-mbox.py 는 이 파일을 가리키는 «심링크» 다.
사본을 두면 같은 결함이 사본마다 따로 살아남는다 — 2026-09-03 seq 재사용이 3사본에 각각 있었고,
하나만 구버전으로 남겨도 오염이 계속된다는 것을 반박실험으로 확인했다(RECON-seq-reuse-20260903.md).
 LIFO·per-to ring·fcntl.flock·consume-on-read·to==me grep.
v6-realtime-live mbox.py 계승 + 팩 추가분: FT_MBOX_DIR 경로 주입·세션명 allowlist·READ 출력·from 필터.

★2026-08-25 — 우편함이 «셋으로 갈라져» 메시지가 유실되던 것을 고친다★
이전: 데이터 경로가 «cwd 기준»이라, 같은 스크립트를 불러도 부른 사람의 cwd 에 따라 다른
우편함을 썼다 — 보낸 쪽과 받는 쪽이 서로 다른 파일을 보는 사고가 실제로 났다.
지금: ★send 는 «정본» 하나에만 쓰고, recv/peek 는 «정본+레거시»를 전부 읽는다(union)★.
union 을 두는 이유 — 경로를 «순간에» 바꾸면 바꾸기 직전 큐잉된 메시지가 옛 파일에 남아
★아무도 안 읽는다★. 레거시가 전부 0행이 되면 그때 걷어낸다(그 판단은 별도).
"""
import os, sys; sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))   # 모듈 = 이 파일의 «실제» 폴더 — 링크 폴더를 sys.path 에 넣고 import 해도 찾게(DA r1 Q2) · CANON 은 아래에서 링크 위치(abspath)로 정한다
from mbox_conf import *


def _repo_root(start):
    """★정본 자리를 «유도»한다 — 하드코딩 금지★.

    이 파일 위쪽의 `.fable-team` 을 찾고, 그 부모가 `.worktrees/<x>` 면 리포 루트는 두 단계
    위다. ★워크트리 «안»이 아니라 «밖»을 정본으로 잡는 이유★: 워크트리는 정리되면 사라지고,
    그날 그 안의 우편함을 쓰던 세션이 전부 끊긴다.
    """
    d = os.path.abspath(start)
    while d != os.path.dirname(d):
        if os.path.basename(d) == ".fable-team":
            parent = os.path.dirname(d)
            # ★워크트리 깊이를 «1» 로 가정하지 않는다★ (2026-09-03 실측)
            #   브랜치명에 슬래시가 있으면 `.worktrees/feat/loom-pack-layer` 처럼 두 단계다.
            #   조부모만 보면 그 경우 `.worktrees` 를 못 만나 ★자기 워크트리 «안»을 정본으로
            #   잡고 별도 우편함을 판다★ — 실측: loom-pack-layer 사본의 CANON 이 루트가 아니라
            #   `.worktrees/feat/loom-pack-layer/.fable-team/comm` 이었다. 에러가 안 나고
            #   send/recv 는 성공하므로 그 좌석만 조용히 아무에게도 안 닿는다.
            a = parent
            while a != os.path.dirname(a):
                if os.path.basename(a) == ".worktrees":
                    return os.path.dirname(a)
                a = os.path.dirname(a)
            return parent
        d = os.path.dirname(d)
    # ★F4: `.fable-team` 조상이 없으면 정본을 «유도할 수 없다» — 조용히 만들지 않는다.
    #   예전엔 `os.path.abspath(start)` 를 돌려줬다. 그러면 스크립트 «옆»에
    #   `.fable-team/comm` 을 파고 send 가 QUEUED 로 정상 종료한다 — ★아무도 안 읽는
    #   우편함★ 이 생기고, 보낸 쪽은 성공했다고 믿는다(무증상 유실).
    return None


_ROOT = _repo_root(os.path.dirname(os.path.abspath(__file__)))
# ★명시가 추론을 이긴다★ — env 로 준 FT_MBOX_DIR 은 그대로 존중한다(이전엔 래퍼가 덮어썼다).
# ★F4: env 도 조상도 없으면 fail-loud — 스크립트 디렉토리 «안»에 우편함을 만들지 않는다.
CANON = os.environ.get("FT_MBOX_DIR") or (os.path.join(_ROOT, ".fable-team", "comm") if _ROOT else None)
if not CANON:
    sys.stderr.write("NO_MAILBOX_ROOT: .fable-team 조상 없음 — FT_MBOX_DIR 를 지정하라\n")
    sys.exit(2)

# ★seq 의 정본은 파일 «내용» 이 아니다★ (2026-09-03 신설).
#   그전엔 `max(파일에 남은 seq) + 1` 이었다. 그런데 recv 가 읽은 행을 «파일에서 지우므로»
#   가장 큰 번호가 소비되면 파일 max 가 «내려가고», 다음 send 가 ★같은 번호를 다시 쓴다★.
#   doorbell 이 매 send 마다 recv 를 부르는 구조라 상시 일어난다.
#   ★피해가 조용한 이유★: 발주를 「#1258 참조」로 지칭하는데 그 번호가 다른 메시지를
#   가리켜도 «번호가 존재하므로» 에러가 안 난다. 틀린 참조가 무증상으로 쌓인다.
#   격리 재현(2026-09-03): send·recv 를 섞은 30건 중 ★7건이 중복 발급★ 됐고,
#   소비 없이 동시 send 24건은 ★중복 0★ 이었다 — 즉 원인은 경합이 아니라 «소비» 다.
#   ring 로테이션 단독으로는 max 가 안 내려간다(15건 중 10건만 남아도 max=15 유지).
_SEQCTR = os.path.join(CANON, ".mbox-seq")
# 부트스트랩 하한. ★전수 실측(2026-09-03) — 우편함·아카이브 6곳 전부★ 의 max 가 1556
# 이었다(루트 1180 / 루트 아카이브 1260 / v6 워크트리 1556 / v6 아카이브 1532).
SEQ_FLOOR = int(os.environ.get("FT_MBOX_SEQ_FLOOR") or 1600)

os.makedirs(CANON, exist_ok=True)

# 분리 모듈(같은 폴더 — 이 파일이 링크면 «실제» 폴더에서 import 된다).
# ★정본 자리는 이 파일 위치(__file__)로만 정해 묶어 준다★ — 모듈 위치로 정하면 링크 설치(.claude/fable-team/bin)에서 .fable-team 조상이 없어 NO_MAILBOX_ROOT.
import mbox_store, mbox_guard, mbox_lineage, mbox_ops
for _m in (mbox_store, mbox_guard, mbox_lineage, mbox_ops):
    _m.CANON = CANON
mbox_store._ROOT, mbox_store._SEQCTR, mbox_store.SEQ_FLOOR = _ROOT, _SEQCTR, SEQ_FLOOR
mbox_guard._GUARD = os.path.join(CANON, ".mbox-guard.json")
from mbox_store import _load, _save, _check_name, _next_seq          # mbox.<이름> 호환(시험)
from mbox_guard import _guard_log, _reply_exempt, _guard_verdict, _guard_record
from mbox_ops import send, relay, recv, peek


if __name__ == "__main__":
    a = sys.argv[1:]
    force = "--force" in a
    show_all = "--all" in a
    a = [x for x in a if x not in ("--force", "--all")]
    if not a: sys.exit("usage: mbox {send <to> <from> <body> [--force]"
                       "|relay <to> <from> <file> <summary>"
                       "|recv <me> [<from>] [--all]|peek <me>|holder <name>}")
    c = a[0]
    if c == "send": send(a[1], a[2], " ".join(a[3:]), force)
    elif c == "relay": relay(a[1], a[2], a[3], " ".join(a[4:]))
    elif c == "recv": recv(a[1], a[2] if len(a) > 2 else None, None if show_all else RECV_LIMIT)
    elif c == "peek": peek(a[1])
    elif c == "holder":   # doorbell·ring 대상 = 그 역할 현역 세션(r1116 R7) — 이름 규칙 밖이면 받은 이름 그대로
        h = mbox_lineage.holder(a[1]); print(h if NAME_RE.match(h) else a[1])
    else: sys.exit("unknown cmd")
