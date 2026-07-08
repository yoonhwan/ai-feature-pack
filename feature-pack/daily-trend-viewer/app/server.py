#!/usr/bin/env python3
"""트렌드 뷰어 로컬 서버 — 유튜브/쇼츠/릴스 인기 영상과 AI 영상 소식을 제공합니다.
외부 패키지 없이 파이썬 표준 라이브러리만 사용합니다.
실행: python3 server.py  →  http://localhost:28088
"""
import base64
import email.utils
import json
import os
import re
import subprocess
import threading
import time
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, quote

PORT = 28088
# CSRF 방어: 계정 변경 POST는 이 서버 자신에서 열린 페이지의 요청만 허용
ALLOWED_ORIGINS = ("http://127.0.0.1:%d" % PORT, "http://localhost:%d" % PORT)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CACHE_TTL = 3600  # 1시간 캐시 (새로고침 버튼으로 강제 갱신 가능)
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36")

_cache = {}
_cache_lock = threading.Lock()
# 썸네일 프록시 메모리 캐시 (url -> (content_type, bytes))
_img_cache = {}
_img_lock = threading.Lock()
IMG_CACHE_MAX = 600

# ---------------------------------------------------------------- 유튜브
# 카테고리 → 유튜브 검색어 매핑
CATEGORIES = {
    "먹방": "먹방",
    "뷰티/패션": "뷰티 메이크업 패션",
    "브이로그": "브이로그",
    "예능/코미디": "예능 웃긴 영상",
    "영화/드라마": "영화 드라마 리뷰",
    "테크/IT": "테크 리뷰",
    "지식/교육": "지식 교양",
    "여행": "여행",
    "동물": "강아지 고양이",
}
# "전체" 탭은 아래 카테고리들을 합쳐 조회수순으로 재정렬
ALL_MERGE = ["먹방", "브이로그", "예능/코미디", "뷰티/패션", "영화/드라마", "여행"]

# 검색 필터 protobuf: 업로드 날짜 (2=오늘, 3=이번 주, 4=이번 달)
PERIOD_CODE = {"day": 2, "week": 3, "month": 4}

# 검색 결과에 섞여 오는 추천 섹션 영상이 기간 필터를 우회하는 경우를 걸러내기 위한
# 기간별 제외 문구 ("N일 전" 형태의 게시일 텍스트 기준)
PERIOD_EXCLUDE = {
    "day": ("일 전", "주 전", "개월 전", "년 전"),
    "week": ("주 전", "개월 전", "년 전"),
    "month": ("개월 전", "년 전"),
}

# ---------------------------------------------------------------- 인스타그램 릴스
IG_APP_ID = "936619743392459"  # instagram.com 웹이 쓰는 공개 앱 ID
# 인스타그램이 비로그인 API 접근을 전면 차단(require_login)해 실계정 세션 쿠키가 필요합니다.
# 브라우저 로그인 후 개발자도구 > Network > 아무 instagram.com 요청 > Cookie 헤더 값
# 전체를 그대로 넣으세요 (sessionid=...; csrftoken=...; ds_user_id=... 등 포함).
IG_SESSION_COOKIE = os.environ.get("IG_SESSION_COOKIE", "")
ACCOUNTS_FILE = os.path.join(BASE_DIR, "reels_accounts.json")
DEFAULT_IG_ACCOUNTS = [
    "openai", "runwayapp", "pika_labs", "lumalabsai", "midjourney",
    "klingai_official", "heygen_official", "higgsfield.ai", "googledeepmind",
]

# ---- 인스타그램 세션 쿠키 영속 저장소 ----
IG_SESSION_FILE = os.path.join(BASE_DIR, "ig_session.json")
IG_COOKIE_ASSUMED_VALIDITY_DAYS = 90  # 실측 만료 API가 없어 보수적으로 잡은 추정 창 — 라이브 체크(valid)가 우선 신호
_ig_session_lock = threading.Lock()


def _load_ig_session():
    try:
        with open(IG_SESSION_FILE) as f:
            data = json.load(f)
            if isinstance(data, dict) and data.get("cookie"):
                return data
    except (OSError, json.JSONDecodeError):
        pass
    return None


def _save_ig_session(data):
    with open(IG_SESSION_FILE, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


_ig_session = _load_ig_session()


def _current_ig_cookie():
    with _ig_session_lock:
        if _ig_session:
            return str(_ig_session.get("cookie", ""))
    return os.environ.get("IG_SESSION_COOKIE", "")

# ---------------------------------------------------------------- X (트위터)
X_ACCOUNTS_FILE = os.path.join(BASE_DIR, "x_accounts.json")
DEFAULT_X_ACCOUNTS = [
    "OpenAI", "runwayml", "Kling_ai", "GoogleDeepMind", "midjourney",
    "LumaLabsAI", "pika_labs", "heygen_com", "elevenlabsio", "AIatMeta",
]

# ---------------------------------------------------------------- 스레드(Threads)
THREADS_ACCOUNTS_FILE = os.path.join(BASE_DIR, "threads_accounts.json")
DEFAULT_THREADS_ACCOUNTS = [
    "openai", "runway", "google", "meta.ai", "zuck",
]
IG_APP_ID_THREADS = "238260118697367"  # threads.com 웹이 쓰는 공개 앱 ID

# ---------------------------------------------------------------- 틱톡(TikTok)
# tikwm 무료 공개 API가 서명(X-Bogus/msToken)을 대신 처리해 조회수·좋아요·댓글까지 반환합니다.
TIKTOK_ACCOUNTS_FILE = os.path.join(BASE_DIR, "tiktok_accounts.json")
DEFAULT_TIKTOK_ACCOUNTS = [
    "openai", "runwayapp", "krea.ai", "elevenlabs", "sora",
    "zachking", "khaby.lame", "google",
]
TIKWM_BASE = "https://www.tikwm.com/api"
TIKTOK_REGION = "KR"

# ---------------------------------------------------------------- AI 영상 탭
AI_YT_QUERIES = ["AI 영상 제작", "AI 영상 생성", "sora ai video", "runway kling veo"]
NEWS_FEEDS = [
    ("국내", "https://news.google.com/rss/search?q=" +
     quote('AI 영상 생성 OR "AI 비디오" OR 영상생성모델') + "&hl=ko&gl=KR&ceid=KR:ko"),
    ("해외", "https://news.google.com/rss/search?q=" +
     quote('"AI video" model OR Sora OR Runway OR Kling OR Veo') + "&hl=en-US&gl=US&ceid=US:en"),
]
HF_PIPELINES = ["text-to-video", "image-to-video"]
# 이미지 프록시로 가져올 수 있는 호스트 (핫링크/차단 우회용)
IMG_PROXY_ALLOW = (".cdninstagram.com", ".fbcdn.net", ".ytimg.com",
                   ".googleusercontent.com", ".twimg.com",
                   ".tiktokcdn.com", ".tiktokcdn-eu.com", ".tiktokcdn-us.com")


def within_period(published: str, period: str) -> bool:
    if not published:
        return True  # 게시일 정보가 없으면(라이브 등) 통과
    return not any(word in published for word in PERIOD_EXCLUDE.get(period, ()))


def build_search_params(period: str, shorts: bool = False) -> str:
    """정렬=조회수(3) + 필터(업로드날짜, 동영상 타입, 길이) protobuf를 base64로 만듭니다."""
    filters = bytes([0x08, PERIOD_CODE.get(period, 3), 0x10, 0x01])
    if shorts:
        filters += bytes([0x18, 0x01])  # 길이: 4분 미만
    raw = bytes([0x08, 0x03, 0x12, len(filters)]) + filters
    return base64.urlsafe_b64encode(raw).decode()


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """30x redirect를 따라가지 않고 응답을 그대로 반환한다."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

_no_redirect_opener = urllib.request.build_opener(_NoRedirect)


def http_get(url: str, payload=None, headers=None, timeout=15,
             follow_redirects=True):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data)
    req.add_header("User-Agent", UA)
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    opener = urllib.request.urlopen if follow_redirects else _no_redirect_opener.open
    with opener(req, timeout=timeout) as resp:
        return resp.headers.get("Content-Type", ""), resp.read()


def http_json(url: str, payload=None, headers=None, timeout=15):
    _, body = http_get(url, payload, headers, timeout)
    return json.loads(body.decode())


def parse_view_count(text: str) -> int:
    digits = re.sub(r"[^\d]", "", text or "")
    return int(digits) if digits else 0


def rank_items(items, sort_by="views", limit=100):
    """views/likes 키 기준 내림차순 공통 정렬. 키 부재/None은 0 취급."""
    key = "likes" if sort_by == "likes" else "views"
    return sorted(items, key=lambda x: x.get(key) or 0, reverse=True)[:limit]


def _norm_item(platform, raw):
    """플랫폼별 fetcher 출력 dict → 공통 아이템 스키마 매핑."""
    if platform in ("youtube", "shorts"):
        vid = raw.get("id", "")
        return {
            "id": vid,
            "title": raw.get("title", ""),
            "account": raw.get("channel", ""),
            "url": ("https://www.youtube.com/watch?v=" + vid) if vid else "",
            "thumbnail": raw.get("thumbnail", ""),
            "views": raw.get("views", 0),
            "likes": raw.get("likes", 0),
            "comments": 0,
            "createdAt": 0,
            "extra": {k: raw[k] for k in ("published", "viewsText", "length") if raw.get(k)},
        }
    if platform == "reels":
        url = raw.get("url", "")
        sc = url.rsplit("/reel/", 1)[-1].rstrip("/") if "/reel/" in url else ""
        return {
            "id": sc,
            "title": raw.get("title", ""),
            "account": raw.get("account", ""),
            "url": url,
            "thumbnail": raw.get("thumbnail", ""),
            "views": raw.get("views", 0),
            "likes": raw.get("likes", 0),
            "comments": raw.get("comments", 0),
            "createdAt": raw.get("takenAt", 0),
            "extra": {},
        }
    if platform == "tiktok":
        return {
            "id": raw.get("id", ""),
            "title": raw.get("title", ""),
            "account": raw.get("account", ""),
            "url": raw.get("url", ""),
            "thumbnail": raw.get("thumbnail", ""),
            "views": raw.get("views", 0),
            "likes": raw.get("likes", 0),
            "comments": raw.get("comments", 0),
            "createdAt": raw.get("createdAt", 0),
            "extra": {k: raw[k] for k in ("shares", "name") if raw.get(k)},
        }
    if platform == "x":
        url = raw.get("url", "")
        id_str = url.rsplit("/status/", 1)[-1] if "/status/" in url else ""
        return {
            "id": id_str,
            "title": (raw.get("text", "") or "")[:120],
            "account": raw.get("account", ""),
            "url": url,
            "thumbnail": raw.get("media", ""),
            "views": raw.get("views", 0),
            "likes": raw.get("likes", 0),
            "comments": raw.get("replies", 0),
            "createdAt": 0,
            "extra": {k: raw[k] for k in ("retweets", "name", "createdAt") if raw.get(k)},
        }
    if platform == "threads":
        url = raw.get("url", "")
        code = url.rsplit("/post/", 1)[-1] if "/post/" in url else ""
        return {
            "id": code,
            "title": (raw.get("text", "") or "")[:120],
            "account": raw.get("account", ""),
            "url": url,
            "thumbnail": raw.get("media", ""),
            "views": 0,
            "likes": raw.get("likes", 0),
            "comments": raw.get("replies", 0),
            "createdAt": raw.get("createdAt", 0),
            "extra": {k: raw[k] for k in ("reposts",) if raw.get(k)},
        }
    return raw


def cached(key, force, fetch_fn):
    now = time.time()
    with _cache_lock:
        hit = _cache.get(key)
        if hit and not force and now - hit[0] < CACHE_TTL:
            return hit[1], hit[0]
    result = fetch_fn()
    fetched_at = time.time()
    with _cache_lock:
        prev = _cache.get(key)
        if not result and prev is not None:
            # fetch_fn이 빈 결과(None/[])를 반환하면(업스트림 실패) 이전 정상 캐시를 유지합니다.
            return prev[1], prev[0]
        _cache[key] = (fetched_at, result)
    return result, fetched_at


# ================================================================ 유튜브
def extract_videos(node, out):
    """응답 트리를 순회하며 videoRenderer를 수집합니다."""
    if isinstance(node, dict):
        if "videoRenderer" in node:
            v = node["videoRenderer"]
            title = "".join(r.get("text", "") for r in v.get("title", {}).get("runs", []))
            views_text = v.get("viewCountText", {}).get("simpleText", "")
            thumbs = v.get("thumbnail", {}).get("thumbnails", [])
            out.append({
                "id": v.get("videoId", ""),
                "title": title,
                "channel": "".join(r.get("text", "") for r in v.get("ownerText", {}).get("runs", [])),
                "views": parse_view_count(views_text),
                "viewsText": views_text,
                "length": v.get("lengthText", {}).get("simpleText", ""),
                "published": v.get("publishedTimeText", {}).get("simpleText", ""),
                "thumbnail": thumbs[-1]["url"] if thumbs else "",
            })
        for value in node.values():
            extract_videos(value, out)
    elif isinstance(node, list):
        for item in node:
            extract_videos(item, out)


def yt_search(query: str, period: str, shorts: bool):
    payload = {
        "context": {"client": {
            "clientName": "WEB",
            "clientVersion": "2.20250624.01.00",
            "hl": "ko", "gl": "KR",
        }},
        "query": query,
        "params": build_search_params(period, shorts),
    }
    try:
        data = http_json("https://www.youtube.com/youtubei/v1/search", payload)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return []
    videos = []
    extract_videos(data, videos)
    seen, unique = set(), []
    for v in videos:
        if v["id"] and v["id"] not in seen and within_period(v["published"], period):
            seen.add(v["id"])
            unique.append(v)
    return unique


def yt_like_count(video_id: str):
    """youtubei/v1/next로 영상 1개의 좋아요 수를 가져옵니다(검색 API엔 없음)."""
    payload = {"context": {"client": {
        "clientName": "WEB", "clientVersion": "2.20250624.01.00", "hl": "ko", "gl": "KR"}},
        "videoId": video_id}
    try:
        _, body = http_get("https://www.youtube.com/youtubei/v1/next", payload=payload, timeout=10)
        s = body.decode("utf-8", "ignore")
        m = re.search(r"다른 사용자 ([0-9,]+)명", s) or re.search(r"along with ([0-9,]+) other", s)
        return int(m.group(1).replace(",", "")) + 1 if m else 0
    except Exception:
        return 0


def enrich_likes(videos, limit=45):
    """영상 리스트의 복사본에 좋아요 수(likes)를 병렬로 채워 반환합니다. 원본 dict는 변경하지 않습니다."""
    result = [dict(v) for v in videos]
    todo = [v for v in result[:limit] if not v.get("likes")]
    if not todo:
        return result
    with ThreadPoolExecutor(max_workers=12) as pool:
        counts = pool.map(lambda v: yt_like_count(v["id"]), todo)
    for v, c in zip(todo, counts):
        v["likes"] = c
    return result


def merge_yt_searches(queries, period, shorts):
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = pool.map(lambda q: yt_search(q, period, shorts), queries)
    merged, seen = [], set()
    for chunk in results:
        for v in chunk:
            if v["id"] not in seen:
                seen.add(v["id"])
                merged.append(v)
    merged.sort(key=lambda v: v["views"], reverse=True)
    return merged


def _parse_korean_view_count(text):
    """'조회수 118만회', '1.2억회', '3,456회' 등 한국어 축약 조회수를 파싱합니다."""
    if not text:
        return 0
    m = re.search(r"([\d,.]+)\s*억", text)
    if m:
        return int(float(m.group(1).replace(",", "")) * 100_000_000)
    m = re.search(r"([\d,.]+)\s*만", text)
    if m:
        return int(float(m.group(1).replace(",", "")) * 10_000)
    m = re.search(r"([\d,.]+)\s*천", text)
    if m:
        return int(float(m.group(1).replace(",", "")) * 1_000)
    return parse_view_count(text)


def _extract_lockup_videos(node, out):
    """채널 Videos 탭의 lockupViewModel 구조에서 영상 정보를 추출합니다."""
    if isinstance(node, dict):
        lvm = node.get("lockupViewModel")
        if isinstance(lvm, dict) and lvm.get("contentType") == "LOCKUP_CONTENT_TYPE_VIDEO":
            vid = lvm.get("contentId", "")
            meta = (lvm.get("metadata") or {}).get("lockupMetadataViewModel", {})
            title = (meta.get("title") or {}).get("content", "")
            rows = ((meta.get("metadata") or {}).get("contentMetadataViewModel") or {}).get("metadataRows", [])
            views_text, published = "", ""
            for row in rows:
                for part in row.get("metadataParts", []):
                    t = (part.get("text") or {}).get("content", "")
                    if "조회" in t or "view" in t.lower():
                        views_text = t
                    elif "전" in t or "ago" in t.lower():
                        published = t
            thumbs = ((lvm.get("contentImage") or {}).get("thumbnailViewModel") or {}).get("image", {}).get("sources", [])
            out.append({
                "id": vid,
                "title": title,
                "channel": "",
                "views": _parse_korean_view_count(views_text),
                "viewsText": views_text,
                "length": "",
                "published": published,
                "thumbnail": thumbs[-1]["url"] if thumbs else "",
            })
            return
        for value in node.values():
            _extract_lockup_videos(value, out)
    elif isinstance(node, list):
        for item in node:
            _extract_lockup_videos(item, out)


def yt_channel_uploads(handle):
    """채널 핸들(또는 채널 ID)의 업로드 영상 목록을 youtubei/v1/browse로 가져옵니다."""
    ctx = {"client": {
        "clientName": "WEB", "clientVersion": "2.20250624.01.00",
        "hl": "ko", "gl": "KR",
    }}
    # 채널 ID(UC...)면 resolve 불필요
    if handle.startswith("UC") and len(handle) == 24:
        browse_id = handle
    else:
        clean = handle.lstrip("@")
        try:
            data = http_json(
                "https://www.youtube.com/youtubei/v1/navigation/resolve_url",
                payload={"context": ctx,
                         "url": "https://www.youtube.com/@" + clean},
                timeout=12)
            browse_id = data["endpoint"]["browseEndpoint"]["browseId"]
        except Exception:
            return None
    # Videos 탭(최신순) browse
    try:
        data = http_json(
            "https://www.youtube.com/youtubei/v1/browse",
            payload={"context": ctx, "browseId": browse_id,
                     "params": "EgZ2aWRlb3PyBgQKAjoA"},
            timeout=12)
    except Exception:
        return None
    videos = []
    _extract_lockup_videos(data, videos)
    # lockupViewModel에는 ownerText가 없으므로 channel 필드를 handle로 채움
    clean = handle.lstrip("@")
    for v in videos:
        if not v.get("channel"):
            v["channel"] = clean
    return videos


def get_videos(category: str, period: str, shorts: bool, force: bool, enrich: bool = False, query: str = ""):
    def fetch():
        if query:
            queries = [query]
        elif category == "전체":
            queries = [CATEGORIES[c] for c in ALL_MERGE]
        elif category == "AI":
            queries = AI_YT_QUERIES
        else:
            queries = [CATEGORIES.get(category, category)]
        vids = merge_yt_searches(queries, period, shorts)
        if enrich:
            vids = enrich_likes(vids)
        return vids
    return cached(("yt", query or category, period, shorts, enrich), force, fetch)


# ================================================================ 인스타그램 릴스
def load_accounts(path, defaults):
    try:
        with open(path) as f:
            accounts = json.load(f)
            if isinstance(accounts, list) and accounts:
                return accounts
    except (OSError, json.JSONDecodeError):
        pass
    return list(defaults)


def save_accounts(path, accounts):
    with open(path, "w") as f:
        json.dump(accounts, f, ensure_ascii=False, indent=2)


# 계정 목록을 쓰는 소스별 설정 (파일 경로, 기본 계정)
ACCOUNT_SOURCES = {
    "reels": (ACCOUNTS_FILE, DEFAULT_IG_ACCOUNTS),
    "x": (X_ACCOUNTS_FILE, DEFAULT_X_ACCOUNTS),
    "threads": (THREADS_ACCOUNTS_FILE, DEFAULT_THREADS_ACCOUNTS),
    "tiktok": (TIKTOK_ACCOUNTS_FILE, DEFAULT_TIKTOK_ACCOUNTS),
}
# 유튜브 채널 등록 (P3 준비 — 빈 디폴트)
YT_CHANNELS_FILE = os.path.join(BASE_DIR, "yt_channels.json")
ACCOUNT_SOURCES["youtube"] = (YT_CHANNELS_FILE, [])

# 태그 등록 저장소 (③분기 인프라)
YT_TAGS_FILE = os.path.join(BASE_DIR, "yt_tags.json")
REELS_TAGS_FILE = os.path.join(BASE_DIR, "reels_tags.json")
TIKTOK_TAGS_FILE = os.path.join(BASE_DIR, "tiktok_tags.json")
X_TAGS_FILE = os.path.join(BASE_DIR, "x_tags.json")

TAG_SOURCES = {
    "youtube": (YT_TAGS_FILE, list(CATEGORIES.values())),
    "reels": (REELS_TAGS_FILE, ["aivideo", "sora"]),
    "tiktok": (TIKTOK_TAGS_FILE, ["aivideo", "sora"]),
    "x": (X_TAGS_FILE, ["AI"]),
}


def _validate_ig_cookie(cookie):
    """쿠키 유효성을 실제 웹 프로필 API 호출로 확인. (ok, detail) 튜플 반환."""
    test_account = load_accounts(ACCOUNTS_FILE, DEFAULT_IG_ACCOUNTS)[0]
    url = ("https://www.instagram.com/api/v1/users/web_profile_info/?username="
           + quote(test_account))
    headers = {"x-ig-app-id": IG_APP_ID, "Cookie": cookie}
    csrf_match = re.search(r"csrftoken=([^;]+)", cookie)
    if csrf_match:
        headers["X-CSRFToken"] = csrf_match.group(1)
    try:
        http_json(url, headers=headers, timeout=12)
        return True, None
    except urllib.error.HTTPError as e:
        return False, "HTTP %d" % e.code
    except Exception as e:
        return False, str(e)


def fetch_ig_reels(username: str):
    """인스타그램 웹 내부 API로 계정의 최근 릴스를 가져옵니다.

    인스타그램이 비로그인 요청을 전부 require_login으로 차단하므로
    세션 쿠키가 설정된 경우에만 실제 데이터를 받아올 수 있습니다.
    """
    cookie = _current_ig_cookie()
    if not cookie:
        return []
    url = ("https://www.instagram.com/api/v1/users/web_profile_info/?username="
           + quote(username))
    headers = {"x-ig-app-id": IG_APP_ID, "Cookie": cookie}
    csrf_match = re.search(r"csrftoken=([^;]+)", cookie)
    if csrf_match:
        headers["X-CSRFToken"] = csrf_match.group(1)
    try:
        data = http_json(url, headers=headers, timeout=12)
    except Exception:
        return []
    user = (data.get("data") or {}).get("user") or {}
    reels = []
    for edge in (user.get("edge_owner_to_timeline_media") or {}).get("edges", []):
        n = edge.get("node", {})
        if not n.get("is_video"):
            continue
        caps = (n.get("edge_media_to_caption") or {}).get("edges") or []
        title = caps[0]["node"]["text"].split("\n")[0][:120] if caps else ""
        reels.append({
            "account": username,
            "title": title or "(설명 없음)",
            "views": n.get("video_view_count") or 0,
            "likes": (n.get("edge_liked_by") or {}).get("count", 0),
            "comments": (n.get("edge_media_to_comment") or {}).get("count", 0),
            "thumbnail": n.get("thumbnail_src") or "",
            "url": "https://www.instagram.com/reel/%s/" % n.get("shortcode", ""),
            "takenAt": n.get("taken_at_timestamp") or 0,
        })
    return reels


def _parse_ig_tag_media(m, tag):
    if m.get("media_type") != 2:
        return None
    caption = m.get("caption") or {}
    cap_text = caption.get("text", "") if isinstance(caption, dict) else ""
    title = cap_text.split("\n")[0][:120] if cap_text else ""
    image_candidates = (m.get("image_versions2") or {}).get("candidates") or []
    thumb = image_candidates[0]["url"] if image_candidates else ""
    return {
        "account": "#" + tag,
        "title": title or "(설명 없음)",
        "views": m.get("play_count") or m.get("view_count") or 0,
        "likes": m.get("like_count") or 0,
        "comments": m.get("comment_count") or 0,
        "thumbnail": thumb,
        "url": "https://www.instagram.com/reel/%s/" % m.get("code", ""),
        "takenAt": m.get("taken_at") or 0,
    }


def fetch_ig_hashtag(tag: str):
    """인스타그램 해시태그 페이지에서 인기 릴스를 가져옵니다. (세션 쿠키 필요 — fetch_ig_reels와 동일 제약)"""
    cookie = _current_ig_cookie()
    if not cookie:
        return []
    url = "https://www.instagram.com/api/v1/tags/web_info/?tag_name=" + quote(tag)
    headers = {"x-ig-app-id": IG_APP_ID, "Cookie": cookie}
    csrf_match = re.search(r"csrftoken=([^;]+)", cookie)
    if csrf_match:
        headers["X-CSRFToken"] = csrf_match.group(1)
    try:
        data = http_json(url, headers=headers, timeout=12)
    except Exception:
        return []
    root = data.get("data") or {}
    sections = (root.get("top") or {}).get("sections") or []
    sections = sections + ((root.get("recent") or {}).get("sections") or [])
    reels = []
    for sec in sections:
        medias = (sec.get("layout_content") or {}).get("medias") or []
        for item in medias:
            parsed = _parse_ig_tag_media(item.get("media") or {}, tag)
            if parsed:
                reels.append(parsed)
    return reels


def get_reels(force: bool, tag: str = ""):
    accounts = load_accounts(ACCOUNTS_FILE, DEFAULT_IG_ACCOUNTS)

    def fetch():
        if tag:
            return fetch_ig_hashtag(tag)
        with ThreadPoolExecutor(max_workers=6) as pool:
            results = pool.map(fetch_ig_reels, accounts)
        merged = [r for chunk in results for r in chunk]
        merged.sort(key=lambda r: r["views"], reverse=True)
        return merged
    reels, fetched_at = cached(("reels", tuple(accounts), tag), force, fetch)
    return reels, accounts, fetched_at


# ================================================================ X (트위터)
def _find_timeline_entries(node):
    """syndication __NEXT_DATA__에서 timeline entries 리스트를 찾습니다."""
    if isinstance(node, dict):
        tl = node.get("timeline")
        if isinstance(tl, dict) and isinstance(tl.get("entries"), list):
            return tl["entries"]
        for v in node.values():
            r = _find_timeline_entries(v)
            if r:
                return r
    elif isinstance(node, list):
        for v in node:
            r = _find_timeline_entries(v)
            if r:
                return r
    return None


def fetch_x_posts(username: str):
    """트위터 syndication(임베드용, 무인증) API로 계정의 최근 트윗을 참여수와 함께 가져옵니다."""
    url = "https://syndication.twitter.com/srv/timeline-profile/screen-name/" + quote(username)
    try:
        try:
            _, body = http_get(url, headers={"Accept": "text/html"}, timeout=12)
        except urllib.error.HTTPError as e:
            if e.code != 429:
                raise
            # syndication.twitter.com이 urllib의 TLS 핑거프린트를 429로 차단해 curl로 재시도합니다.
            body = subprocess.run(
                ["curl", "-sS", "--max-time", "12", "-A", UA, "-H", "Accept: text/html", url],
                capture_output=True, timeout=17, check=True,
            ).stdout
        html = body.decode("utf-8", "ignore")
        m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
        if not m:
            return []
        data = json.loads(m.group(1))
    except Exception:
        return []
    entries = _find_timeline_entries(data) or []
    posts = []
    for e in entries:
        content = e.get("content", {}) if isinstance(e, dict) else {}
        t = content.get("tweet")
        if not isinstance(t, dict):
            tr = content.get("tweetResult") or {}
            t = tr.get("result") if isinstance(tr, dict) else None
        if not isinstance(t, dict) or t.get("favorite_count") is None:
            continue
        user = t.get("user", {}) if isinstance(t.get("user"), dict) else {}
        media = ""
        for mm in (t.get("mediaDetails") or []):
            if mm.get("media_url_https"):
                media = mm["media_url_https"]
                break
        posts.append({
            "account": username,
            "name": user.get("name", username),
            "text": (t.get("full_text") or t.get("text") or "").strip(),
            "likes": t.get("favorite_count") or 0,
            "replies": t.get("reply_count") or 0,
            "retweets": t.get("retweet_count") or 0,
            "views": int(t.get("views", {}).get("count", 0)) if isinstance(t.get("views"), dict) else 0,
            "media": media,
            "url": "https://x.com/%s/status/%s" % (username, t.get("id_str", "")),
            "createdAt": t.get("created_at", ""),
        })
    return posts


def get_x_posts(force: bool):
    accounts = load_accounts(X_ACCOUNTS_FILE, DEFAULT_X_ACCOUNTS)

    def fetch():
        # syndication은 동시 요청이 많으면 빈 응답을 주므로 동시성을 낮춥니다.
        with ThreadPoolExecutor(max_workers=3) as pool:
            results = pool.map(fetch_x_posts, accounts)
        return [p for chunk in results for p in chunk]
    posts, fetched_at = cached(("x", tuple(accounts)), force, fetch)
    return posts, accounts, fetched_at


# ================================================================ 스레드(Threads)
def _threads_lsd_and_userid(username: str):
    """스레드 프로필 HTML에서 LSD 토큰과 user_id를 함께 얻습니다."""
    lsd = None
    user_id = None
    try:
        # Sec-Fetch-Mode: navigate 없이는 계정 무관 빈 껍데기 HTML만 내려옵니다.
        _, body = http_get("https://www.threads.com/@" + quote(username),
                            headers={"Sec-Fetch-Mode": "navigate"}, timeout=12)
        html = body.decode("utf-8", "ignore")
        m = re.search(r'"LSD",\[\],\{"token":"([^"]+)"', html)
        lsd = m.group(1) if m else None
        m = re.search(r'"user_id":"(\d+)"', html)
        user_id = m.group(1) if m else None
    except Exception:
        pass
    return lsd, user_id


# 스레드 프로필 탭 쿼리의 doc_id는 수시로 바뀌므로, 알려진 후보를 순서대로 시도합니다.
THREADS_DOC_IDS = ["6232751443445612"]


def fetch_threads_posts(username: str):
    lsd, user_id = _threads_lsd_and_userid(username)
    if not lsd or not user_id:
        return []
    from urllib.parse import urlencode
    headers = {
        "X-FB-LSD": lsd, "X-IG-App-ID": IG_APP_ID_THREADS,
        "Sec-Fetch-Site": "same-origin",
        "X-FB-Friendly-Name": "BarcelonaProfileThreadsTabQuery",
        "Content-Type": "application/x-www-form-urlencoded",
    }
    for doc_id in THREADS_DOC_IDS:
        payload = urlencode({
            "lsd": lsd, "doc_id": doc_id,
            "variables": json.dumps({"userID": str(user_id), "__relay_internal__pv__BarcelonaIsLoggedInrelayprovider": False}),
        }).encode()
        req = urllib.request.Request("https://www.threads.com/api/graphql", data=payload)
        req.add_header("User-Agent", UA)
        for k, v in headers.items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=12) as resp:
                data = json.loads(resp.read().decode())
        except Exception:
            continue
        if data.get("errors"):
            continue
        posts = _parse_threads(data, username)
        if posts:
            return posts
    return []


def _parse_threads(data, username):
    posts = []

    def walk(o):
        if isinstance(o, dict):
            if "post" in o and isinstance(o["post"], dict) and o["post"].get("caption") is not None:
                p = o["post"]
                caption = (p.get("caption") or {}).get("text", "") if isinstance(p.get("caption"), dict) else ""
                info = p.get("text_post_app_info", {}) or {}
                imgs = (p.get("image_versions2") or {}).get("candidates") or []
                posts.append({
                    "account": username,
                    "text": caption[:280],
                    "likes": p.get("like_count") or 0,
                    "replies": info.get("direct_reply_count") or 0,
                    "reposts": info.get("repost_count") or 0,
                    "views": 0,
                    "media": imgs[0]["url"] if imgs else "",
                    "url": "https://www.threads.com/@%s/post/%s" % (username, p.get("code", "")),
                    "createdAt": p.get("taken_at") or 0,
                })
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    walk(data)
    return posts


def get_threads_posts(force: bool):
    accounts = load_accounts(THREADS_ACCOUNTS_FILE, DEFAULT_THREADS_ACCOUNTS)

    def fetch():
        with ThreadPoolExecutor(max_workers=5) as pool:
            results = pool.map(fetch_threads_posts, accounts)
        return [p for chunk in results for p in chunk]
    posts, fetched_at = cached(("threads", tuple(accounts)), force, fetch)
    return posts, accounts, fetched_at


# ================================================================ 틱톡(TikTok)
def _tiktok_item(v):
    author = v.get("author", {}) if isinstance(v.get("author"), dict) else {}
    handle = author.get("unique_id", "")
    vid = v.get("video_id", "")
    return {
        "account": handle,
        "name": author.get("nickname", handle),
        "title": (v.get("title") or "").strip() or "(설명 없음)",
        "views": v.get("play_count") or 0,
        "likes": v.get("digg_count") or 0,
        "comments": v.get("comment_count") or 0,
        "shares": v.get("share_count") or 0,
        "thumbnail": v.get("cover") or v.get("origin_cover") or "",
        "url": "https://www.tiktok.com/@%s/video/%s" % (handle, vid),
        "id": vid,
        "createdAt": v.get("create_time") or 0,
    }


def fetch_tiktok_user(handle: str):
    url = "%s/user/posts?unique_id=%s&count=12" % (TIKWM_BASE, quote(handle))
    try:
        d = http_json(url, timeout=15)
    except Exception:
        return []
    vids = (d.get("data") or {}).get("videos") or []
    return [_tiktok_item(v) for v in vids]


def fetch_tiktok_trending():
    url = "%s/feed/list?region=%s&count=20" % (TIKWM_BASE, TIKTOK_REGION)
    try:
        d = http_json(url, timeout=15)
    except Exception:
        return []
    vids = d.get("data") or []
    return [_tiktok_item(v) for v in vids]


def fetch_tiktok_search(keyword: str):
    url = "%s/feed/search?keywords=%s&count=20" % (TIKWM_BASE, quote(keyword))
    try:
        d = http_json(url, timeout=15)
    except Exception:
        return []
    vids = (d.get("data") or {}).get("videos") or []
    return [_tiktok_item(v) for v in vids]


def get_tiktok(force: bool, query: str = ""):
    accounts = load_accounts(TIKTOK_ACCOUNTS_FILE, DEFAULT_TIKTOK_ACCOUNTS)

    def fetch():
        if query:
            return fetch_tiktok_search(query)
        # 트렌딩(전체 인기) + 구독 계정 최신 영상을 합쳐 중복 제거.
        # tikwm 무료 티어의 레이트리밋을 피하려 동시성을 낮춥니다.
        posts = fetch_tiktok_trending()
        with ThreadPoolExecutor(max_workers=3) as pool:
            for chunk in pool.map(fetch_tiktok_user, accounts):
                posts.extend(chunk)
        seen, unique = set(), []
        for p in posts:
            if p["id"] and p["id"] not in seen:
                seen.add(p["id"])
                unique.append(p)
        return unique
    posts, fetched_at = cached(("tiktok", tuple(accounts), query), force, fetch)
    return posts, accounts, fetched_at


# ================================================================ AI 영상 탭
def fetch_news():
    def one(feed):
        label, url = feed
        try:
            _, body = http_get(url, timeout=12)
            root = ET.fromstring(body)
        except Exception:
            return []
        items = []
        for item in root.iter("item"):
            title = item.findtext("title") or ""
            source = item.findtext("source") or ""
            pub = item.findtext("pubDate") or ""
            try:
                ts = email.utils.parsedate_to_datetime(pub).timestamp()
            except (TypeError, ValueError):
                ts = 0
            items.append({"region": label, "title": title, "source": source,
                          "link": item.findtext("link") or "", "ts": ts})
        return items[:25]

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = pool.map(one, NEWS_FEEDS)
    merged = [n for chunk in results for n in chunk]
    merged.sort(key=lambda n: n["ts"], reverse=True)
    return merged[:40]


def fetch_hf_models():
    def one(args):
        pipeline, sort = args
        url = ("https://huggingface.co/api/models?pipeline_tag=%s&sort=%s"
               "&direction=-1&limit=12" % (pipeline, sort))
        try:
            data = http_json(url, timeout=12)
        except Exception:
            return []
        return [{"id": m.get("id", ""), "likes": m.get("likes", 0),
                 "downloads": m.get("downloads", 0), "pipeline": pipeline,
                 "createdAt": m.get("createdAt", "")} for m in data]

    jobs = [(p, s) for p in HF_PIPELINES for s in ("createdAt", "trendingScore")]
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(one, jobs))

    def dedupe(lists):
        seen, out = set(), []
        for chunk in lists:
            for m in chunk:
                if m["id"] not in seen:
                    seen.add(m["id"])
                    out.append(m)
        return out
    latest = dedupe(results[0::2])
    latest.sort(key=lambda m: m["createdAt"], reverse=True)
    trending = dedupe(results[1::2])
    return {"latest": latest[:12], "trending": trending[:12]}


def get_ai_data(force: bool):
    # AI 탭은 '글'(모델·뉴스)만 제공합니다. AI 영상은 유튜브 탭의 'AI' 카테고리로 통합됨.
    def fetch():
        with ThreadPoolExecutor(max_workers=2) as pool:
            news_f = pool.submit(fetch_news)
            models_f = pool.submit(fetch_hf_models)
            return {"news": news_f.result(), "models": models_f.result()}
    return cached(("ai",), force, fetch)


# ================================================================ 기타
def fetch_oembed(url: str):
    """틱톡/유튜브 URL의 oEmbed 메타데이터를 가져옵니다 (CORS 우회용 프록시)."""
    host = urlparse(url).netloc.lower()
    if "tiktok.com" in host:
        endpoint = "https://www.tiktok.com/oembed?url=" + quote(url, safe="")
    elif "youtube.com" in host or "youtu.be" in host:
        endpoint = "https://www.youtube.com/oembed?format=json&url=" + quote(url, safe="")
    else:
        return {"ok": False, "reason": "unsupported"}
    try:
        data = http_json(endpoint, timeout=10)
        return {"ok": True, "title": data.get("title", ""),
                "author": data.get("author_name", ""),
                "thumbnail": data.get("thumbnail_url", "")}
    except Exception:
        return {"ok": False, "reason": "fetch_failed"}


# ================================================================ 랭킹 공통 인프라 (P1)
_VALID_LIMITS = (50, 100, 150, 200)


def _clamp_limit(val):
    try:
        val = int(val)
    except (TypeError, ValueError):
        return 100
    return val if val in _VALID_LIMITS else 100


def _unsupported(platform, scope, sort_by, notice, errors=None):
    """unsupported 응답 헬퍼."""
    return {"platform": platform, "scope": scope, "sortBy": sort_by,
            "support": "unsupported", "notice": notice,
            "items": [], "accountsOrTags": [], "errors": errors or [],
            "fetchedAt": time.time()}


def _rank_yt(scope, sort_by, period, limit, force, shorts=False):
    """YouTube/Shorts 랭킹 어댑터."""
    plat = "shorts" if shorts else "youtube"
    errors = []

    if scope == "accounts":
        if shorts:
            return _unsupported(plat, scope, sort_by,
                                "쇼츠 채널 등록목록 랭킹은 준비 중이에요")
        storage_key = "youtube"
        ch_file, default_ch = ACCOUNT_SOURCES[storage_key]
        channels = load_accounts(ch_file, default_ch)
        if not channels:
            return {"platform": plat, "scope": scope, "sortBy": sort_by,
                    "support": "native", "notice": "",
                    "items": [], "accountsOrTags": [],
                    "errors": [], "fetchedAt": time.time()}
        accts = list(channels)
        ck = ("rank", plat, "accounts", tuple(channels), period)

        def fetch_ch():
            with ThreadPoolExecutor(max_workers=4) as pool:
                results = list(pool.map(yt_channel_uploads, channels))
            merged, seen = [], set()
            for chunk in results:
                if chunk is None:
                    continue
                for v in chunk:
                    if v["id"] and v["id"] not in seen and within_period(v.get("published", ""), period):
                        seen.add(v["id"])
                        merged.append(v)
            return merged

        if sort_by == "likes":
            base, _ = cached(ck, force, fetch_ch)
            if base is None:
                base = []
            items, fat = cached(ck + ("enrich",), force,
                                lambda: enrich_likes(base))
            support = "approx"
            notice = "좋아요 수는 상위 45개만 개별 조회한 근사 순위예요"
        else:
            items, fat = cached(ck, force, fetch_ch)
            support = "native"
            notice = ""

        if items is None:
            items = []
        if not items and channels:
            errors.append({"source": "youtube_browse", "code": "FETCH",
                           "message": "채널 영상을 가져오지 못했어요"})
        ranked = rank_items([_norm_item(plat, v) for v in items], sort_by, limit)
        return {"platform": plat, "scope": scope, "sortBy": sort_by,
                "support": support, "notice": notice,
                "items": ranked, "accountsOrTags": accts,
                "errors": errors, "fetchedAt": fat}

    if scope == "tags":
        storage_key = "youtube"  # shorts도 youtube 저장소 공유
        tags_file, default_tags = TAG_SOURCES[storage_key]
        queries = load_accounts(tags_file, default_tags)
        accts = list(queries)
    else:  # all
        queries = [CATEGORIES[c] for c in ALL_MERGE]
        accts = []

    ck = ("rank", plat, scope, tuple(queries), period)

    if sort_by == "likes":
        base, _ = cached(ck, force,
                         lambda: merge_yt_searches(queries, period, shorts))
        if base is None:
            base = []
        items, fat = cached(ck + ("enrich",), force,
                            lambda: enrich_likes(base))
        support = "approx"
        notice = "좋아요 수는 상위 45개만 개별 조회한 근사 순위예요"
    else:
        items, fat = cached(ck, force,
                            lambda: merge_yt_searches(queries, period, shorts))
        support = "native"
        notice = ""

    if items is None:
        items = []
    ranked = rank_items([_norm_item(plat, v) for v in items], sort_by, limit)
    return {"platform": plat, "scope": scope, "sortBy": sort_by,
            "support": support, "notice": notice,
            "items": ranked, "accountsOrTags": accts,
            "errors": errors, "fetchedAt": fat}


def _rank_reels(scope, sort_by, period, limit, force):
    """릴스 랭킹 어댑터."""
    errors = []
    # 쿠키 상태 점검 (메타 = 캐시 밖 매 호출 계산)
    cookie = _current_ig_cookie()
    if not cookie:
        errors.append({"source": "ig_cookie", "code": "AUTH",
                       "message": "인스타 세션 쿠키가 설정되지 않았어요"})
    elif _ig_session and _ig_session.get("valid") is False:
        errors.append({"source": "ig_cookie", "code": "AUTH",
                       "message": "인스타 세션 쿠키가 만료됐을 수 있어요"})

    if scope == "all":
        # ① 등록태그 pool 병합 결과 top-N 근사 (③과 동일 소스)
        tags_file, default_tags = TAG_SOURCES["reels"]
        tags = load_accounts(tags_file, default_tags)
        ck_all = ("rank", "reels", "tags", tuple(tags))
        def fetch_all():
            with ThreadPoolExecutor(max_workers=4) as pool:
                res = pool.map(fetch_ig_hashtag, tags)
            return [r for chunk in res for r in chunk]
        items, fat = cached(ck_all, force, fetch_all)
        if items is None:
            items = []
        ranked = rank_items([_norm_item("reels", v) for v in items], sort_by, limit)
        return {"platform": "reels", "scope": scope, "sortBy": sort_by,
                "support": "approx",
                "notice": "등록 태그 풀 내 상위 콘텐츠예요 (플랫폼 전체 아님)",
                "items": ranked, "accountsOrTags": tags,
                "errors": errors, "fetchedAt": fat}

    if scope == "accounts":
        accounts = load_accounts(ACCOUNTS_FILE, DEFAULT_IG_ACCOUNTS)
        ck = ("rank", "reels", "accounts", tuple(accounts))
        def fetch():
            with ThreadPoolExecutor(max_workers=6) as pool:
                res = pool.map(fetch_ig_reels, accounts)
            return [r for chunk in res for r in chunk]
        items, fat = cached(ck, force, fetch)
        support, notice, accts = "post", "", accounts
    elif scope == "tags":
        tags_file, default_tags = TAG_SOURCES["reels"]
        tags = load_accounts(tags_file, default_tags)
        ck = ("rank", "reels", "tags", tuple(tags))
        def fetch():
            with ThreadPoolExecutor(max_workers=4) as pool:
                res = pool.map(fetch_ig_hashtag, tags)
            return [r for chunk in res for r in chunk]
        items, fat = cached(ck, force, fetch)
        support, notice, accts = "post", "", tags
    else:
        return _unsupported("reels", scope, sort_by, "알 수 없는 scope", errors)

    if items is None:
        items = []
    ranked = rank_items([_norm_item("reels", v) for v in items], sort_by, limit)
    return {"platform": "reels", "scope": scope, "sortBy": sort_by,
            "support": support, "notice": notice,
            "items": ranked, "accountsOrTags": accts,
            "errors": errors, "fetchedAt": fat}


def _rank_tiktok(scope, sort_by, period, limit, force):
    """틱톡 랭킹 어댑터."""
    errors = []

    if scope == "all":
        ck = ("rank", "tiktok", "all")
        items, fat = cached(ck, force, fetch_tiktok_trending)
        accts = []
    elif scope == "accounts":
        accounts = load_accounts(TIKTOK_ACCOUNTS_FILE, DEFAULT_TIKTOK_ACCOUNTS)
        ck = ("rank", "tiktok", "accounts", tuple(accounts))
        def fetch():
            with ThreadPoolExecutor(max_workers=3) as pool:
                res = pool.map(fetch_tiktok_user, accounts)
            merged, seen = [], set()
            for chunk in res:
                for p in chunk:
                    if p["id"] and p["id"] not in seen:
                        seen.add(p["id"])
                        merged.append(p)
            return merged
        items, fat = cached(ck, force, fetch)
        accts = accounts
    elif scope == "tags":
        tags_file, default_tags = TAG_SOURCES["tiktok"]
        tags = load_accounts(tags_file, default_tags)
        ck = ("rank", "tiktok", "tags", tuple(tags))
        def fetch():
            with ThreadPoolExecutor(max_workers=2) as pool:
                res = pool.map(fetch_tiktok_search, tags)
            merged, seen = [], set()
            for chunk in res:
                for p in chunk:
                    if p["id"] and p["id"] not in seen:
                        seen.add(p["id"])
                        merged.append(p)
            return merged
        items, fat = cached(ck, force, fetch)
        accts = tags
    else:
        return _unsupported("tiktok", scope, sort_by, "알 수 없는 scope")

    if items is None:
        items = []
    ranked = rank_items([_norm_item("tiktok", v) for v in items], sort_by, limit)
    return {"platform": "tiktok", "scope": scope, "sortBy": sort_by,
            "support": "post", "notice": "",
            "items": ranked, "accountsOrTags": accts,
            "errors": errors, "fetchedAt": fat}


def filter_posts_by_tags(posts, tags):
    """포스트 텍스트에서 #태그 매칭으로 필터링 (대소문자 무시)."""
    if not tags:
        return []
    filtered = []
    for p in posts:
        text = p.get("text") or ""
        for tag in tags:
            if re.search(r"#%s\b" % re.escape(tag), text, re.I):
                filtered.append(p)
                break
    return filtered


def _rank_x(scope, sort_by, period, limit, force):
    """X 랭킹 어댑터."""
    errors = []

    # ② 등록계정 pool fetch (all/accounts/tags 모두 이 pool을 소스로 사용)
    accounts = load_accounts(X_ACCOUNTS_FILE, DEFAULT_X_ACCOUNTS)
    ck = ("rank", "x", "accounts", tuple(accounts))
    def fetch():
        with ThreadPoolExecutor(max_workers=3) as pool:
            res = pool.map(fetch_x_posts, accounts)
        return [p for chunk in res for p in chunk]
    items, fat = cached(ck, force, fetch)

    if items is None:
        items = []

    if scope == "tags":
        # ③ 해시태그 후처리 근사
        tags_file, default_tags = TAG_SOURCES["x"]
        tags = load_accounts(tags_file, default_tags)
        filtered = filter_posts_by_tags(items, tags)
        ranked = rank_items([_norm_item("x", v) for v in filtered], sort_by, limit)
        return {"platform": "x", "scope": scope, "sortBy": sort_by,
                "support": "approx",
                "notice": "텍스트 내 #해시태그 후처리 기반 근사치예요",
                "items": ranked, "accountsOrTags": tags,
                "errors": errors, "fetchedAt": fat}

    if scope == "all":
        # ① 등록계정 pool top-N 근사
        ranked = rank_items([_norm_item("x", v) for v in items], sort_by, limit)
        return {"platform": "x", "scope": scope, "sortBy": sort_by,
                "support": "approx",
                "notice": "등록 계정 풀 내 상위 콘텐츠예요 (플랫폼 전체 아님)",
                "items": ranked, "accountsOrTags": accounts,
                "errors": errors, "fetchedAt": fat}

    # scope == "accounts" (②)
    ranked = rank_items([_norm_item("x", v) for v in items], sort_by, limit)
    return {"platform": "x", "scope": scope, "sortBy": sort_by,
            "support": "post", "notice": "",
            "items": ranked, "accountsOrTags": accounts,
            "errors": errors, "fetchedAt": fat}


def _rank_threads(scope, sort_by, period, limit, force):
    """Threads 랭킹 어댑터."""
    errors = []

    if sort_by == "views":
        return _unsupported("threads", scope, sort_by,
                            "Threads는 조회수를 제공하지 않아 조회수 정렬을 지원할 수 없어요")

    if scope == "tags":
        return _unsupported("threads", scope, sort_by,
                            "Threads 태그 랭킹은 지원할 수 없어요")

    # ② 등록계정 pool fetch (accounts/all 모두 이 pool을 소스로 사용)
    accounts = load_accounts(THREADS_ACCOUNTS_FILE, DEFAULT_THREADS_ACCOUNTS)
    ck = ("rank", "threads", "accounts", tuple(accounts))
    def fetch():
        with ThreadPoolExecutor(max_workers=5) as pool:
            res = pool.map(fetch_threads_posts, accounts)
        return [p for chunk in res for p in chunk]
    items, fat = cached(ck, force, fetch)

    if items is None:
        items = []
    ranked = rank_items([_norm_item("threads", v) for v in items], sort_by, limit)

    if scope == "all":
        # ① 등록계정 pool top-N 근사
        return {"platform": "threads", "scope": scope, "sortBy": sort_by,
                "support": "approx",
                "notice": "등록 계정 풀 내 상위 콘텐츠예요 (플랫폼 전체 아님)",
                "items": ranked, "accountsOrTags": accounts,
                "errors": errors, "fetchedAt": fat}

    # scope == "accounts" (②)
    return {"platform": "threads", "scope": scope, "sortBy": sort_by,
            "support": "post", "notice": "",
            "items": ranked, "accountsOrTags": accounts,
            "errors": errors, "fetchedAt": fat}


PLATFORM_ADAPTERS = {
    "youtube": lambda s, sb, p, l, f: _rank_yt(s, sb, p, l, f, shorts=False),
    "shorts": lambda s, sb, p, l, f: _rank_yt(s, sb, p, l, f, shorts=True),
    "reels": _rank_reels,
    "tiktok": _rank_tiktok,
    "x": _rank_x,
    "threads": _rank_threads,
}


def get_ranked(platform, scope="all", sort_by="views", period="week",
               limit=100, force=False):
    """통합 랭킹 진입점 — PLATFORM_ADAPTERS 디스패치 → 응답 dict."""
    adapter = PLATFORM_ADAPTERS.get(platform)
    if not adapter:
        return _unsupported(platform, scope, sort_by, "지원하지 않는 플랫폼이에요")
    return adapter(scope, sort_by, period, limit, force)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("[%s] %s" % (time.strftime("%H:%M:%S"), fmt % args))

    def _send(self, code, body, content_type="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parsed = urlparse(self.path)
        qs = parse_qs(parsed.query)
        force = qs.get("force", ["0"])[0] == "1"

        if parsed.path in ("/", "/index.html"):
            with open(os.path.join(BASE_DIR, "index.html"), "rb") as f:
                self._send(200, f.read(), "text/html; charset=utf-8")
            return

        if parsed.path == "/api/videos":
            category = qs.get("category", ["전체"])[0]
            period = qs.get("period", ["week"])[0]
            shorts = qs.get("shorts", ["0"])[0] == "1"
            enrich = qs.get("enrich", ["0"])[0] == "1"
            query = qs.get("q", [""])[0].strip()
            if not query and category not in ("전체", "AI") and category not in CATEGORIES:
                self._send(400, {"error": "unknown category"})
                return
            videos, fetched_at = get_videos(category, period, shorts, force, enrich, query)
            limit_raw = qs.get("limit", [None])[0]
            cut = _clamp_limit(limit_raw) if limit_raw is not None else 60
            self._send(200, {"videos": videos[:cut], "fetchedAt": fetched_at})
            return

        if parsed.path == "/api/categories":
            self._send(200, {"categories": ["전체", "AI"] + list(CATEGORIES.keys())})
            return

        if parsed.path == "/api/instagram/session":
            with _ig_session_lock:
                sess = dict(_ig_session) if _ig_session else None
            if not sess:
                self._send(200, {"loggedIn": False})
                return
            now = time.time()
            days_since = max(0, int((now - float(sess.get("savedAt", now))) // 86400))
            days_left = max(0, IG_COOKIE_ASSUMED_VALIDITY_DAYS - days_since)
            self._send(200, {
                "loggedIn": True,
                "savedAt": sess.get("savedAt"),
                "daysSinceSaved": days_since,
                "estimatedDaysLeft": days_left,
                "lastCheckedAt": sess.get("lastCheckedAt"),
                "valid": sess.get("valid"),
            })
            return

        if parsed.path == "/api/reels":
            ig_tag = qs.get("tag", [""])[0].strip().lstrip("#")
            reels, accounts, fetched_at = get_reels(force, ig_tag)
            limit_raw = qs.get("limit", [None])[0]
            cut = _clamp_limit(limit_raw) if limit_raw is not None else 80
            self._send(200, {"reels": reels[:cut], "accounts": accounts, "fetchedAt": fetched_at})
            return

        if parsed.path == "/api/x":
            posts, accounts, fetched_at = get_x_posts(force)
            limit_raw = qs.get("limit", [None])[0]
            if limit_raw is not None:
                posts = posts[:_clamp_limit(limit_raw)]
            self._send(200, {"posts": posts, "accounts": accounts, "fetchedAt": fetched_at})
            return

        if parsed.path == "/api/threads":
            posts, accounts, fetched_at = get_threads_posts(force)
            limit_raw = qs.get("limit", [None])[0]
            if limit_raw is not None:
                posts = posts[:_clamp_limit(limit_raw)]
            self._send(200, {"posts": posts, "accounts": accounts, "fetchedAt": fetched_at})
            return

        if parsed.path == "/api/tiktok":
            tt_query = qs.get("q", [""])[0].strip()
            posts, accounts, fetched_at = get_tiktok(force, tt_query)
            limit_raw = qs.get("limit", [None])[0]
            cut = _clamp_limit(limit_raw) if limit_raw is not None else 100
            self._send(200, {"posts": posts[:cut], "accounts": accounts, "fetchedAt": fetched_at})
            return

        if parsed.path == "/api/rank":
            platform = qs.get("platform", [""])[0]
            scope = qs.get("scope", ["all"])[0]
            sort_by = qs.get("sort", ["views"])[0]
            period = qs.get("period", ["week"])[0]
            limit = _clamp_limit(qs.get("limit", ["100"])[0])
            if not platform:
                self._send(400, {"error": "platform parameter required"})
                return
            self._send(200, get_ranked(platform, scope, sort_by, period,
                                       limit, force))
            return

        if parsed.path == "/api/ai":
            data, fetched_at = get_ai_data(force)
            self._send(200, {**data, "fetchedAt": fetched_at})
            return

        if parsed.path == "/api/oembed":
            self._send(200, fetch_oembed(qs.get("url", [""])[0]))
            return

        if parsed.path == "/api/img":
            # 인스타/틱톡 CDN 등 핫링크가 막힌 썸네일을 서버가 대신 받아 전달(메모리 캐시)
            url = qs.get("u", [""])[0]
            parts = urlparse(url)
            host = (parts.hostname or "").lower()
            allowed = any(host == a.lstrip(".") or host.endswith(a)
                          for a in IMG_PROXY_ALLOW)
            if not url.startswith("https://") or "@" in parts.netloc or not allowed:
                self._send(400, {"error": "host not allowed"})
                return
            hit = _img_cache.get(url)
            if hit:
                self._send(200, hit[1], hit[0])
                return
            try:
                ctype, body = http_get(url, timeout=12, follow_redirects=False)
                ctype = ctype or "image/jpeg"
                with _img_lock:
                    if len(_img_cache) > IMG_CACHE_MAX:
                        _img_cache.clear()
                    _img_cache[url] = (ctype, body)
                self._send(200, body, ctype)
            except Exception:
                self._send(502, {"error": "fetch failed"})
            return

        self._send(404, {"error": "not found"})

    def do_POST(self):
        parsed = urlparse(self.path)
        # /api/instagram/session — 세션 쿠키 저장/검증/삭제
        if parsed.path == "/api/instagram/session":
            origin = (self.headers.get("Origin") or "").strip().rstrip("/")
            if origin not in ALLOWED_ORIGINS:
                self._send(403, {"error": "origin not allowed"})
                return
            length = int(self.headers.get("Content-Length", 0))
            try:
                req = json.loads(self.rfile.read(length).decode()) if length else {}
            except json.JSONDecodeError:
                self._send(400, {"error": "invalid json"})
                return
            action = req.get("action")
            global _ig_session
            if action == "clear":
                with _ig_session_lock:
                    _ig_session = None
                    try:
                        os.remove(IG_SESSION_FILE)
                    except OSError:
                        pass
                self._send(200, {"loggedIn": False})
                return
            if action in ("save", "check"):
                with _ig_session_lock:
                    current = dict(_ig_session) if _ig_session else None
                cookie = (req.get("cookie") or "").strip() if action == "save" else (current or {}).get("cookie", "")
                if not cookie:
                    self._send(400, {"error": "cookie required"})
                    return
                valid, detail = _validate_ig_cookie(cookie)
                now = time.time()
                with _ig_session_lock:
                    if action == "save" or _ig_session is None:
                        _ig_session = {"cookie": cookie, "savedAt": now, "lastCheckedAt": now, "valid": valid}
                    else:
                        _ig_session["lastCheckedAt"] = now
                        _ig_session["valid"] = valid
                    _save_ig_session(_ig_session)
                    sess = dict(_ig_session)
                if action == "save":
                    with _cache_lock:
                        for k in [k for k in _cache if k[0] == "reels"]:
                            del _cache[k]
                days_since = max(0, int((now - float(sess["savedAt"])) // 86400))
                days_left = max(0, IG_COOKIE_ASSUMED_VALIDITY_DAYS - days_since)
                self._send(200, {
                    "loggedIn": True, "valid": valid, "detail": detail,
                    "savedAt": sess["savedAt"], "daysSinceSaved": days_since,
                    "estimatedDaysLeft": days_left, "lastCheckedAt": sess["lastCheckedAt"],
                })
                return
            self._send(400, {"error": "unknown action"})
            return

        # /api/{platform}/(accounts|tags) — 구독 계정/태그 추가/삭제
        m = re.match(r"^/api/(reels|x|threads|tiktok|youtube)/(accounts|tags)$", parsed.path)
        if m:
            # CSRF 방어: 브라우저는 POST에 항상 Origin을 붙이므로,
            # Origin이 없거나(비브라우저/구식) 허용 목록 밖이면 거부합니다.
            origin = (self.headers.get("Origin") or "").strip().rstrip("/")
            if origin not in ALLOWED_ORIGINS:
                self._send(403, {"error": "origin not allowed"})
                return
            source = m.group(1)
            kind = m.group(2)  # "accounts" or "tags"
            if kind == "tags":
                if source not in TAG_SOURCES:
                    self._send(400, {"error": "%s does not support tags" % source})
                    return
                path, defaults = TAG_SOURCES[source]
            else:
                if source not in ACCOUNT_SOURCES:
                    self._send(400, {"error": "%s does not support accounts" % source})
                    return
                path, defaults = ACCOUNT_SOURCES[source]
            length = int(self.headers.get("Content-Length", 0))
            try:
                req = json.loads(self.rfile.read(length).decode())
            except json.JSONDecodeError:
                self._send(400, {"error": "invalid json"})
                return
            if not isinstance(req, dict):
                self._send(400, {"error": "invalid request body"})
                return
            action = req.get("action")
            raw_val = req.get("username")
            if not isinstance(raw_val, str) or len(raw_val) > 200:
                self._send(400, {"error": "invalid username"})
                return
            raw = raw_val.strip().lstrip("@")
            if kind == "tags":
                raw = raw.lstrip("#")
            # X는 대소문자 보존, 나머지는 소문자
            username = raw if source == "x" else raw.lower()
            entries = load_accounts(path, defaults)
            if action == "add" and username and username not in entries:
                entries.append(username)
            elif action == "remove" and username in entries:
                entries.remove(username)
            save_accounts(path, entries)
            self._send(200, {kind: entries})
            return
        self._send(404, {"error": "not found"})


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"트렌드 뷰어 실행 중: http://localhost:{PORT}")
    server.serve_forever()
