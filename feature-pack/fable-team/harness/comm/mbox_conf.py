# mbox.py 의 env 상수 — 위치와 무관한 값만(정본 자리·CANON 은 mbox.py 가 정한다) · 200줄 규칙 분리.
import sys, os, re, json, time, fcntl, hashlib, shutil, glob

MAX_PER_TO = int(os.environ.get("FT_MBOX_RING") or 10)
# 세션명 allowlist — 세션명이 doorbell 명령 문자열에 삽입되므로 하드 거부(명령 삽입 원천 차단).
NAME_RE = re.compile(r'^[A-Za-z0-9._#-]+$')


def role_key(name):
    """★우편함 키 = 역할 이름(r1116 · 판정 2777)★ — 세션 번호 «#N» 은 표시만. byz-planner-desk-claude#78 → byz-planner-desk-claude.
    옛 번호·새 번호·번호 없는 역할 이름이 한 우편함이라 승계(증류·재부팅) 때 인계 장치 없이 후계 첫 recv 에 그대로 보인다."""
    return re.sub(r"#\d+$", "", name or "")

# ── 발신 규율 물리 가드 (COMM-GUIDE §1.5) ──────────────────────────────
# 홍수는 사용자 입력을 막고, ring(MAX_PER_TO) 상한을 넘긴 메시지를 조용히 유실시킨다.
# ★2026-09-05 — 길이는 «발신 차단»이 아니라 «수신 절단» 기준이다★
#   상한으로 send 를 실패시켰더니 사람이 배운 것은 relay 가 아니라 `--force` 였다:
#   실측(2026-09-05) 정본 큐 51건 중 ★16건(31%)이 700자 초과★인데 relay 형식은 ★0건★.
#   차단은 규율을 «가르치지 못했고», 대신 «막히면 --force» 라는 우회를 가르쳤다.
#   ⇒ ①send 는 길이로 막지 않는다 ②700자를 넘으면 전문을 파일에 «먼저» 박는다
#     ③recv 가 잘라 읽고 전문 경로를 함께 준다.
#   받는 쪽 컨텍스트는 그대로 보호되고(태우는 것은 «읽는 쪽»이다), 보내는 쪽은 아무것도
#   잃지 않는다. relay 는 여전히 최선이다 — 사람이 쓴 요약은 기계 절단이 못 만든다.
MAX_BODY = int(os.environ.get("FT_MBOX_MAX_BODY") or 700)        # 본문 «절단» 기준(3~5줄)
FANOUT_WIN = int(os.environ.get("FT_MBOX_FANOUT_WINDOW") or 600)  # 동일 본문 다중 좌석 판정 창(초)
RATE_N = int(os.environ.get("FT_MBOX_RATE_N") or 5)               # from당 발신 건수
RATE_WIN = int(os.environ.get("FT_MBOX_RATE_WINDOW") or 60)       # 그 창(초)
# ★2026-09-02 재발신 쿨다운★ — 큐잉은 «가져가기» 방식이므로 pending 동안 재발신 금지.
# N초 경과 후 1회 허용(재발신이 기록을 갱신하므로 자연히 «1회씩»). 그 전엔 pane 캡처로 확인.
RESEND_COOL = int(os.environ.get("FT_MBOX_RESEND_COOLDOWN") or 300)
EXEMPT_CAP = int(os.environ.get("FT_MBOX_EXEMPT_CAP") or 1000)    # 회신 면제 행 보존 상한(가드 로그 전체) — 넘으면 새 면제를 내주지 않는다(fail-closed)
RECV_LIMIT = int(os.environ.get("FT_MBOX_RECV_LIMIT") or 5)       # recv 기본 표시 건수
RELAY_DIR = os.environ.get("FT_MBOX_RELAY_DIR") or "/tmp/mbox"    # 긴 본문의 정본 자리
# ★2026-09-06 — 전문 파일은 «시간»으로 자른다★
#   bodies/<seq>.txt 는 행이 recv 로 소비돼도 남는다. 그래야 하는 이유가 있다 —
#   그 경로는 보고서·인계 문서에 «인용»되어 3~4일 뒤에 열린다(실측). 소비 시점에
#   지우면 그 인용이 죽는다. ⇒ ★«소비 여부»가 아니라 «시간»이 기준이다★.
#   14일 근거: 좌석 수명 실측 median 2.6일 · p90/max 4.2일 → p90 의 3배 여유.
#   비용은 건당 4KB(gitignore 아래)라 여유를 크게 잡는 편이 싸다.
BODIES_TTL_DAYS = int(os.environ.get("FT_MBOX_BODIES_TTL_DAYS") or 14)
BODIES_PRUNE_EVERY = 3600   # 청소 주기(초) — 매 send 마다 listdir 하지 않는다.
# ★보낸 행의 «추가 전용» 사본 (2026-10-04 · Slack 미러 입력 · D1)★
#   mailbox.jsonl 은 consume-on-read 라 recv 하면 행이 사라지고, ring 은 오래된 행을 버린다.
#   읽는 쪽(미러)이 짧은 보고를 놓치지 않으려면 «보낸 모든 행» 이 남는 파일이 따로 필요하다.
#   큐 동작은 건드리지 않는다. 한도 초과 시 .1 로 한 번 회전해 최대 2×한도로 묶는다(무한 증가 0).
SENT_LOG = "mailbox.log.jsonl"
SENT_LOG_MAX_BYTES = int(os.environ.get("FT_MBOX_LOG_MAX_BYTES") or 5 * 1024 * 1024)
# ★회전본 «벌 수» (r553)★ — 한 벌만 남기면 바쁜 날 보관이 약 10시간이라 매거진 24시간 창의
#   앞부분이 사라진다(10-20 08:00 MagazineError 실측: 실 하루 12.5MB). 밀어 보관하면 파일
#   하나의 크기는 그대로라 send 비용은 안 늘고 «더 오래된 벌이 남는» 것만 달라진다.
SENT_LOG_KEEP = max(1, int(os.environ.get("FT_MBOX_LOG_KEEP") or 3))
