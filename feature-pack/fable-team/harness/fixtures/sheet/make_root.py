"""시트 시험용 가짜 FT_ROOT 한 벌 — 원장 5종(seats json · indices 카드 md · index-ledger jsonl · verdicts jsonl · gh-cache json) + 쪽지 본문 사실 픽스처.
usage: make_root.py <빈 디렉터리>   (라이브 원장·tmux·gh 호출 0)
"""
import json
import sys
from pathlib import Path

R = Path(sys.argv[1])
FB = R / ".fable-team"
(FB / "state" / "board").mkdir(parents=True)
(FB / "comm").mkdir(parents=True)


def card(team: str, folder: str, name: str, title: str, body: str = "") -> None:
    p = R / "design" / team / "indices" / folder / f"{name}.md"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(f"# 인덱스: {title}\n{body}", encoding="utf-8")


def seats(key: str, label: str, master: str | None, extra: dict) -> None:
    d = {"_label": label, "_cards": f"design/{key}/indices", **extra}
    if master:
        d["_master"] = master
    (FB / f"seats-{key}.json").write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")


seats("harness", "harness", "h-master#1", {"h-master#1": {"role": "master"},
      "h-nano-a#0": {"role": "nano", "index": "design/harness/indices/진행/job-a.md"},
      "h-nano-b#0": {"role": "nano", "index": "design/harness/indices/진행/job-b.md"}})
seats("loom", "loom", "l-master#1", {"l-master#1": {"role": "master"}})
seats("cfo", "cfo", "c-master#1", {"c-master#1": {"role": "master"}})
(FB / "seats-planner.json").write_text(json.dumps({"_label": "planner", "_master": "p-master#1"}), encoding="utf-8")

card("harness", "진행", "job-a", "내부 도구 시안 3개 고르기",
     "- say: 시안 3개 → 고르기 → 수정\n## 상태\n- 2026-10-12 09:00 — 대기→진행\n- 2026-10-12 10:30 — [완료·휴식] 끝남\n")
card("harness", "진행", "job-b", "현황판 트리 렌더러",
     "## 상태\n- 2026-10-12 09:00 — 대기→진행\n- 2026-10-12 10:40 — DA HOLD 2 (고칠 것)\n")
card("harness", "대기", "wait-x", "다음 일 하나", "- 선행: job-a 가 끝나야 함\n## 골좌표\n사용자 최우선 K4\n")
card("harness", "대기", "after-1", "나중에 할 일", "- 시기: 완성 후\n")
card("loom", "대기", "wait-l", "문서 등록 화면", "")
card("cfo", "대기", "wait-c", "결제 한도 안내", "")
for i in range(7):
    card("cfo", "진행", f"run-{i}", f"결제 작업 {i}", "## 상태\n- 2026-10-12 09:0%d — 대기→진행\n" % i)
card("cfo", "완성", "done-1", "끝난 결제 작업", "")

ledger = [{"ts": "2026-10-12T09:18:10+0900", "ev": "close", "id": "job-old", "da": "x#상태", "seat": "-", "via": "index-move"}]
(FB / "state" / "index-ledger.harness.jsonl").write_text("".join(json.dumps(x) + "\n" for x in ledger), encoding="utf-8")
vds = [{"ev": "new", "n": 901, "ts": "2026-10-12T08:00:00", "title": "열린 판정", "teams": ["harness"], "seq_out": [], "oppa_todo": ""}]
(FB / "state" / "verdicts.jsonl").write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in vds), encoding="utf-8")
(FB / "state" / "board" / "gh-cache.json").write_text("[]", encoding="utf-8")
# 쪽지 본문에만 있는 사실 — 시트가 읽으면 안 된다(시험: 시트 어디에도 안 나옴)
mail = [{"seq": 5001, "ts": "2026-10-12T09:50:00", "to": "p-master#1", "from": "l-master#1",
         "body": "[정정] 쪽지에만 있는 사실 ZZ-QQ-9731 loom 은 이미 닫힘"}]
(FB / "comm" / "mailbox.jsonl").write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in mail), encoding="utf-8")
