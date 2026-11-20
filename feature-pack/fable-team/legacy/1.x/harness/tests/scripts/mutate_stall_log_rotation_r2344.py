"""r2344 변이 8개(나노 m1~m5 + 카드 cm3~cm5) — 고친 _read_mailbox_log 를 한 군데씩 망가뜨린 사본을 만든다(반례 ①~⑪ 이 그 변이를 잡는지 본다).

사용: python3 mutate_stall_log_rotation_r2344.py <출력폴더>
→ <출력폴더>/m1..m5/ = bin 폴더 통째 사본(ft_stall_detect.py 1개만 다르고 나머지는 같은 글자)
시험: R2344_BIN=<출력폴더>/mN pytest ../tests/scripts/test_stall_log_rotation_r2344.py
"""
import shutil
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[2] / "kit/fable-team/bin/ft_stall_detect.py"

CHAIN = '    return [path] + [path.with_name(f"{path.name}.{i}") for i in range(1, keep + 1)]'
STOP = "        if outside:\n            break  # 창 밖을 만났다 = 사슬 끝"
HB = "                if hb and (best is None or ts > best):"
MISSING = "            continue  # r2344 — 지금 로그든 사본이든 «없으면» 그 번호만 건너뛰고 다음을 본다(회전은 잠금 밖에서 replace 뒤 open 이라 그 틈에 지금 로그가 없다 · 다 없으면 큐만 = 판정 불가 아님 · DA H1 · 메모 2)"
BROKEN_INC = "                broken += bad"

MUTATIONS = {
    "m1": ("G1 사본 사슬 없음(원본 꼴 — 지금 로그 1개만)", CHAIN, "    return [path]"),
    "m2": ("G2 창 밖에서 멈추지 않고 다음 사본을 연다", STOP, "        if outside:\n            continue  # MUT"),
    "m3": ("G1 사본을 .1 하나만 읽는다", "range(1, keep + 1)", "range(1, 2)"),
    "m4": ("G1 사슬 끝 번호가 하나 모자람(.3 누락)", "range(1, keep + 1)", "range(1, keep)"),
    "m5": ("G3 심박 아닌 줄도 심박으로 센다", HB, "                if ts is not None and (best is None or ts > best):"),
    # 카드 동결 변이(DA H2) — 나노 이름과 별개로 카드 M3·M4·M5 를 그대로 만든다.
    "cm3": ("카드 M3 없는 사본에서 사슬을 끊는다(continue→break)", MISSING, "            break  # MUT: 없는 사본 = 사슬 끝"),
    "cm4": ("카드 M4 지금 로그가 없으면 거기서 끝난다", MISSING, '            if cur == path:\n                return "", None, 0, 0\n            continue'),
    "cm5": ("카드 M5 사본의 깨진 줄 수를 버린다", BROKEN_INC, "                broken += bad if cur == path else 0"),
}


def main(argv: list[str]) -> int:
    out = Path(argv[1])
    src = SRC.read_text(encoding="utf-8")
    for name, (why, old, new) in MUTATIONS.items():
        if src.count(old) != 1:
            print(f"FAIL {name} — 대조 글자가 {src.count(old)}개({why})")
            return 1
        d = out / name
        shutil.rmtree(d, ignore_errors=True)  # 사본 폴더 = ft-stall-scan.sh·옆 모듈까지 통째(판정 함수만 다르다)
        _ = shutil.copytree(SRC.parent, d, ignore=shutil.ignore_patterns("__pycache__"))
        _ = (d / "ft_stall_detect.py").write_text(src.replace(old, new), encoding="utf-8")
        print(f"{name} {why}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
