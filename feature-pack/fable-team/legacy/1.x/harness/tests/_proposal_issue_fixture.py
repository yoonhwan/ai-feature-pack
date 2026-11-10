#!/usr/bin/env python3
"""_proposal_issue_fixture.py <폴더> <번호> <변형…> — 제안 Issue 시험 픽스처(가짜 gh 가 읽는 JSON) 를 쓴다. 실 gh 0.
  폴더/view-<번호>.json (gh issue view --json 모양) · 폴더/timeline-<번호>.json (gh api --paginate --slurp 모양).
  변형(0개 이상, 기본 = ⓐ 승인 OK): b(ⓑ byz-tank 승인 + 인터뷰 코멘트) · b-nocomment · noapproved · rejected · needsreply · otherauthor · emptysec · nosha · nomarker ·
  otheractor · split(근거 칸이 이어서 코멘트에) · noevent(라벨은 있는데 timeline 에 없음) ·
  oppa-late(승인 뒤 오빠 코멘트) · oppa-early(승인 전 오빠 코멘트) · oppa-nots(시각 없는 오빠 코멘트) · rev-late(승인 뒤 Tank 「r1 변경」 코멘트) · rev-early(승인 전)
  — 승인(approved) 라벨 시각 = APPROVED_AT
"""
import json
import sys
from pathlib import Path

APPROVED_AT = "2026-10-10T03:00:00Z"
SECS = [("결론", "한 줄."), ("오빠가 결정할 것", "질문 1개."), ("배경", "배경 설명."), ("제안", "제안 내용."), ("되돌림", "되돌리는 법."), ("근거", "- 경로:줄 · 커밋 8b64a2dda4")]


def body(v: set[str]) -> str:
    out = [] if "nomarker" in v else ["<!-- byz-proposal-id: harness/proposal-approval-gate -->"]
    out += ["# 제안서 — 시험", "- 상태: 컨펌 대기", ""]
    for k, t in SECS:
        t = "" if (k == "제안" and "emptysec" in v) else ("- 경로:줄 · 근거 문장만" if (k == "근거" and "nosha" in v) else t)
        if k == "근거" and "split" in v:
            break
        out += [f"## {k}", t, ""]
    return "\n".join(out)


def main(a: list[str]) -> int:
    d, num, v = Path(a[0]), int(a[1]), set(a[2:])
    labels = ["proposal"] + ([] if v & {"noapproved"} else ["approved"]) + (["rejected"] if "rejected" in v else []) + (["needs-reply"] if "needsreply" in v else [])
    comments: list[dict[str, object]] = []
    if "split" in v:
        comments.append({"author": {"login": "byz-tank"}, "body": "(이어서 2/2)\n## 근거\n- 경로:줄 · 커밋 8b64a2dda4\n"})
    if "b" in v:
        comments.append({"author": {"login": "byz-tank"}, "body": "[인터뷰 판정 816]\n질문: 승인할까요? 오빠 답: A안"})
    for k, who, text, at in (("oppa-late", "yoonhwan", "여기 수정해 주세요", "2026-10-10T04:00:00Z"), ("oppa-early", "yoonhwan", "좋아요", "2026-10-10T02:00:00Z"), ("oppa-nots", "yoonhwan", "시각 없음", None),
                             ("rev-late", "byz-tank", "r1 변경 — 본문을 이 판으로 고쳤다", "2026-10-10T04:00:00Z"), ("rev-early", "byz-tank", "r1 변경 — 본문을 이 판으로 고쳤다", "2026-10-10T02:00:00Z")):
        if k in v:
            comments.append({"author": {"login": who}, "body": text, **({"createdAt": at} if at else {})})
    actor = "byz-tank" if v & {"b", "b-nocomment"} else ("someone" if "otheractor" in v else "yoonhwan")
    view = {"number": num, "author": {"login": "other" if "otherauthor" in v else "byz-tank"}, "labels": [{"name": x} for x in labels], "body": body(v), "comments": comments}
    ev = [{"event": "labeled", "label": {"name": "proposal"}, "actor": {"login": "byz-tank"}}]
    if "approved" in labels and "noevent" not in v:
        ev.append({"event": "labeled", "label": {"name": "approved"}, "actor": {"login": actor}, "created_at": APPROVED_AT})
    (d / f"view-{num}.json").write_text(json.dumps(view, ensure_ascii=False), encoding="utf-8")
    (d / f"timeline-{num}.json").write_text(json.dumps([ev], ensure_ascii=False), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
