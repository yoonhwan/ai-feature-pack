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
ACCOUNTS_FILE = os.path.join(BASE_DIR, "reels_accounts.json")
DEFAULT_IG_ACCOUNTS = [
    "openai", "runwayapp", "pika_labs", "lumalabsai", "midjourney",
    "klingai_official", "heygen_official", "higgsfield.ai", "googledeepmind",
]

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


def cached(key, force, fetch_fn):
    now = time.time()
    with _cache_lock:
        hit = _cache.get(key)
        if hit and not force and now - hit[0] < CACHE_TTL:
            return hit[1], hit[0]
    result = fetch_fn()
    fetched_at = time.time()
    with _cache_lock:
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
    """영상 리스트에 좋아요 수(likes)를 병렬로 채웁니다. 이미 채워진 항목은 건너뜁니다."""
    todo = [v for v in videos[:limit] if not v.get("likes")]
    if not todo:
        return videos
    with ThreadPoolExecutor(max_workers=12) as pool:
        counts = pool.map(lambda v: yt_like_count(v["id"]), todo)
    for v, c in zip(todo, counts):
        v["likes"] = c
    return videos


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
            enrich_likes(vids)
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


def fetch_ig_reels(username: str):
    """인스타그램 웹 내부 API(무인증)로 계정의 최근 릴스를 가져옵니다."""
    url = ("https://www.instagram.com/api/v1/users/web_profile_info/?username="
           + quote(username))
    try:
        data = http_json(url, headers={"x-ig-app-id": IG_APP_ID}, timeout=12)
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


def get_reels(force: bool):
    accounts = load_accounts(ACCOUNTS_FILE, DEFAULT_IG_ACCOUNTS)

    def fetch():
        with ThreadPoolExecutor(max_workers=6) as pool:
            results = pool.map(fetch_ig_reels, accounts)
        merged = [r for chunk in results for r in chunk]
        merged.sort(key=lambda r: r["views"], reverse=True)
        return merged
    reels, fetched_at = cached(("reels", tuple(accounts)), force, fetch)
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
        _, body = http_get(url, headers={"Accept": "text/html"}, timeout=12)
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
    """스레드 프로필 페이지에서 LSD 토큰을, 인스타 API에서 user_id를 얻습니다."""
    lsd = None
    try:
        _, body = http_get("https://www.threads.com/@" + quote(username), timeout=12)
        m = re.search(r'"LSD",\[\],\{"token":"([^"]+)"', body.decode("utf-8", "ignore"))
        lsd = m.group(1) if m else None
    except Exception:
        pass
    user_id = None
    try:
        info = http_json(
            "https://www.instagram.com/api/v1/users/web_profile_info/?username=" + quote(username),
            headers={"x-ig-app-id": IG_APP_ID}, timeout=12)
        user_id = (info.get("data") or {}).get("user", {}).get("id")
    except Exception:
        pass
    return lsd, user_id


# 스레드 프로필 탭 쿼리의 doc_id는 수시로 바뀌므로, 알려진 후보를 순서대로 시도합니다.
THREADS_DOC_IDS = [
    "25073444226023094", "7451607104958938", "23996318550159868",
    "9925907010825989", "26286467210919721",
]


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


def get_tiktok(force: bool):
    accounts = load_accounts(TIKTOK_ACCOUNTS_FILE, DEFAULT_TIKTOK_ACCOUNTS)

    def fetch():
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
    posts, fetched_at = cached(("tiktok", tuple(accounts)), force, fetch)
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
            self._send(200, {"videos": videos[:60], "fetchedAt": fetched_at})
            return

        if parsed.path == "/api/categories":
            self._send(200, {"categories": ["전체", "AI"] + list(CATEGORIES.keys())})
            return

        if parsed.path == "/api/reels":
            reels, accounts, fetched_at = get_reels(force)
            self._send(200, {"reels": reels[:80], "accounts": accounts, "fetchedAt": fetched_at})
            return

        if parsed.path == "/api/x":
            posts, accounts, fetched_at = get_x_posts(force)
            self._send(200, {"posts": posts, "accounts": accounts, "fetchedAt": fetched_at})
            return

        if parsed.path == "/api/threads":
            posts, accounts, fetched_at = get_threads_posts(force)
            self._send(200, {"posts": posts, "accounts": accounts, "fetchedAt": fetched_at})
            return

        if parsed.path == "/api/tiktok":
            posts, accounts, fetched_at = get_tiktok(force)
            self._send(200, {"posts": posts[:100], "accounts": accounts, "fetchedAt": fetched_at})
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
        # /api/{reels|x|threads}/accounts — 구독 계정 추가/삭제
        m = re.match(r"^/api/(reels|x|threads)/accounts$", parsed.path)
        if m:
            # CSRF 방어: 브라우저는 POST에 항상 Origin을 붙이므로,
            # Origin이 없거나(비브라우저/구식) 허용 목록 밖이면 거부합니다.
            origin = (self.headers.get("Origin") or "").strip().rstrip("/")
            if origin not in ALLOWED_ORIGINS:
                self._send(403, {"error": "origin not allowed"})
                return
            source = m.group(1)
            path, defaults = ACCOUNT_SOURCES[source]
            length = int(self.headers.get("Content-Length", 0))
            try:
                req = json.loads(self.rfile.read(length).decode())
            except json.JSONDecodeError:
                self._send(400, {"error": "invalid json"})
                return
            action = req.get("action")
            raw = (req.get("username") or "").strip().lstrip("@")
            # X는 대소문자 보존, 인스타/스레드는 소문자
            username = raw if source == "x" else raw.lower()
            accounts = load_accounts(path, defaults)
            if action == "add" and username and username not in accounts:
                accounts.append(username)
            elif action == "remove" and username in accounts:
                accounts.remove(username)
            save_accounts(path, accounts)
            self._send(200, {"accounts": accounts})
            return
        self._send(404, {"error": "not found"})


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"트렌드 뷰어 실행 중: http://localhost:{PORT}")
    server.serve_forever()
