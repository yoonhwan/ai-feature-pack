# r1981 — relay 의 스냅샷(원문 복사·전문 읽기) · mbox_ops.relay 가 부른다 · 200줄 규칙 분리(동작 변경 0).
from mbox_conf import *


def snapshot(to, frm, path, summary):
    """원문을 RELAY_DIR 에 복사하고 (복사본 경로, 전문) 을 돌려준다 · 파일 없음·빈 요약 = exit 1."""
    if not os.path.isfile(path):
        sys.stderr.write("NO_SUCH_FILE %s\n" % path); sys.exit(1)
    if not summary.strip():
        sys.stderr.write("EMPTY_SUMMARY 요약 3~5줄은 보내는 사람이 쓴다.\n"); sys.exit(1)
    os.makedirs(RELAY_DIR, exist_ok=True)
    safe = re.sub(r'[^A-Za-z0-9._#-]', '_', os.path.basename(path))
    base = os.path.join(RELAY_DIR, "%s-%s-to-%s-" % (time.strftime("%Y%m%dT%H%M%S"), frm, to))
    # ★같은 이름이면 «덮어쓰지 않고» 새 자리를 만든다★ — 초 단위 타임스탬프라 같은 초에 같은
    # from→to 로 같은 파일명을 보내면 앞 스냅샷이 파괴돼, 먼저 보낸 포인터가 «나중 내용»을
    # 가리킨다. 스냅샷이 안 남으면 relay 는 경로만 보내는 것과 다를 게 없다.
    dest, n = base + safe, 1
    while os.path.exists(dest):
        n += 1
        dest = "%s%d-%s" % (base, n, safe)
    shutil.copyfile(path, dest)
    # 판정 재료에 «전문» 을 넣는다(r660 · DA⑥ r1 ⓑ③) — 요약 1줄에 여러 줄 전문을 붙여 h 결과 예외를 통과하는 길 0.
    try:
        with open(dest, encoding="utf-8", errors="replace") as f:
            full = f.read()
    except OSError:
        full = ""
    return dest, full
