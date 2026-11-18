"""ft2 card_verdict (r2176) — card_stage --da 판정문 글을 얻는 한 곳.
작업 트리 파일을 먼저 읽는다 · 통과면 거기서 끝(git 0 · V1). 통과가 아니고 경로가 카드 리포 안(realpath)이면
시도 시작에 고정한 SHA 를 refs 순서(ops/main-base → main)로 `<sha>:<리포 상대 경로>` 를 읽어 같은 judge 를 한다 · 처음 통과가 이긴다(V2).
«경로 없음» = `ls-tree <sha> -- <경로>` rc0·빈 출력뿐 · 그 밖의 git 실패·시간 초과·UTF-8 아님 = 판정 불가(V5) · 리포 밖 = git 0(V6).
"""
import os


def inside(byz, path):
    """판정문 경로의 카드 리포 상대 경로 · 리포 밖(또는 리포 폴더 자체) = None. git 호출 0."""
    rel = os.path.relpath(os.path.realpath(path), os.path.realpath(byz))
    return None if rel == os.curdir or rel == os.pardir or rel.startswith(os.pardir + os.sep) else rel


def verdict(path, judge, byz, sha, refs, run, unsure):
    """(사유 | None, 출처 | None) · judge(본문) = 통과 None · 거절 사유 · 출처 = "<가지> <sha 10자>"(git 으로 통과했을 때만).
    통과 없음 = 파일 사유(V4 ⓐ) → 처음 경로가 있던 가지 사유(ⓑ) → 판정 불가 FileNotFoundError(ⓒ)."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except FileNotFoundError:
        text = None
    except (OSError, UnicodeDecodeError) as exc:
        raise unsure("판정문 읽기 %s" % type(exc).__name__) from None
    first = [] if text is None else [judge(text)]
    if first == [None]:
        return None, None
    rel = inside(byz, path) if sha else None
    for ref in refs if rel else ():
        try:
            if not run(byz, "ls-tree", sha[ref], "--", rel).strip():
                continue
            why = judge(run(byz, "show", "%s:%s" % (sha[ref], rel)))
        except UnicodeDecodeError:
            raise unsure("판정문 읽기 UnicodeDecodeError") from None
        if why is None:
            return None, "%s %s" % (ref, sha[ref][:10])
        first = first or [why]
    if not first:
        raise unsure("판정문 읽기 FileNotFoundError")
    return first[0], None
