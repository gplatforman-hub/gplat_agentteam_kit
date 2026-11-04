"""cal_common.py — 네이버 캘린더(CalDAV) 공통 부품.

파이썬 기본 기능만 쓴다 (따로 설치할 것 없음).
열쇠는 naver-calendar/.env 의 NAVER_CAL_USER · NAVER_CAL_APP_PASSWORD (캘린더_연결.bat 이 만든다).
🔒 비밀번호는 어디에도 찍지 않는다.
"""
from __future__ import annotations

import argparse
import base64
import os
import re
import socket
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

# 윈도우 콘솔이 cp949 라서 ✅ 같은 글자에서 죽는 것을 막는다.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

HERE = Path(__file__).resolve().parent          # 스타터킷/naver-calendar
ENV_FILE = HERE / ".env"
DEFAULT_URL = "https://caldav.calendar.naver.com"
TIMEOUT = 30   # 초
NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav"}
PW_HINT = "네이버 → 내정보 → 보안설정 → 2단계 인증 관리 → 애플리케이션 비밀번호 생성"


# ── 오류 ──────────────────────────────────────────────────────
class CalError(Exception):
    """사람에게 보여줄 한국어 한 줄. reason(무엇이 잘못됐나) + fix(어떻게 하나)."""

    def __init__(self, reason: str, fix: str = ""):
        super().__init__(reason)
        self.reason = reason
        self.fix = fix

    def line(self) -> str:
        return f"{self.reason} → {self.fix}" if self.fix else self.reason


def die(e: CalError | str, code: int = 1) -> None:
    msg = e.line() if isinstance(e, CalError) else str(e)
    print(f"[calendar] {msg}", file=sys.stderr, flush=True)
    sys.exit(code)


class KoArgumentParser(argparse.ArgumentParser):
    """도움말·오류가 한국어로 나오는 ArgumentParser."""

    def __init__(self, *a, **k):
        k.setdefault("add_help", False)
        super().__init__(*a, **k)
        self.add_argument("-h", "--help", action="help", help="이 도움말을 보여주고 끝냅니다")
        self._optionals.title = "옵션"
        self._positionals.title = "인자"

    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        self.exit(2, f"[calendar] 인자 오류: {message}\n")


# ── .env ──────────────────────────────────────────────────────
def _parse_env_file(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    try:
        text = path.read_text(encoding="utf-8-sig", errors="replace")   # 메모장 BOM 대비
    except Exception:
        return out
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        if k:
            out[k] = v
    return out


class CalConfig:
    """user / app_password / url. 🔒 repr 에도 비밀번호는 안 나온다."""

    def __init__(self, user: str, app_password: str, url: str):
        self.user = user
        self.app_password = app_password
        self.url = url.rstrip("/")

    def __repr__(self) -> str:
        return f"CalConfig(user={self.user!r}, url={self.url!r}, app_password=***)"


def load_config() -> CalConfig:
    vals = _parse_env_file(ENV_FILE) if ENV_FILE.is_file() else {}
    for k in ("NAVER_CAL_USER", "NAVER_CAL_APP_PASSWORD", "NAVER_CAL_URL"):
        if os.environ.get(k):
            vals[k] = os.environ[k]
    if not vals:
        raise CalError("naver-calendar\\.env 가 아직 없습니다", "캘린더_연결.bat 을 실행하세요")
    user = vals.get("NAVER_CAL_USER", "").strip()
    pw = vals.get("NAVER_CAL_APP_PASSWORD", "").strip().replace(" ", "")
    if not user or not pw:
        raise CalError("naver-calendar\\.env 에 아이디나 앱 비밀번호가 비어 있습니다", "캘린더_연결.bat 을 다시 실행하세요")
    return CalConfig(user, pw, vals.get("NAVER_CAL_URL", "").strip() or DEFAULT_URL)


# ── CalDAV ────────────────────────────────────────────────────
class _AuthFail(Exception):
    pass


class CalDAV:
    """아주 작은 CalDAV 손님. PROPFIND · REPORT · PUT 만 쓴다."""

    def __init__(self, cfg: CalConfig):
        self.cfg = cfg
        self.user_used = ""      # 실제로 통한 로그인 이름 (아이디 또는 아이디@naver.com)
        self._auth = ""

    # 로그인 이름 후보: 적힌 그대로, 그리고 @ 앞부분
    def _login_ids(self) -> list[str]:
        u = self.cfg.user
        ids = [u]
        if "@" in u:
            ids.append(u.split("@", 1)[0])
        else:
            ids.append(u + "@naver.com")
        return ids

    def _send(self, method: str, url: str, body: str | None, depth: str | None, auth: str,
              ctype: str = "application/xml; charset=utf-8", extra: dict | None = None):
        for _ in range(6):   # 이사(301·302·307·308)를 직접 따라간다 — urllib 은 PROPFIND 를 안 따라간다
            data = body.encode("utf-8") if body is not None else None
            req = urllib.request.Request(url, data=data, method=method)
            req.add_header("Authorization", "Basic " + auth)
            req.add_header("User-Agent", "gplat-starterkit-calendar/1.0")
            if body is not None:
                req.add_header("Content-Type", ctype)
            if depth is not None:
                req.add_header("Depth", depth)
            for k, v in (extra or {}).items():
                req.add_header(k, v)
            try:
                with urllib.request.urlopen(req, timeout=TIMEOUT, context=ssl.create_default_context()) as r:
                    return r.status, r.headers, r.read().decode("utf-8", errors="replace"), url
            except urllib.error.HTTPError as e:
                if e.code in (301, 302, 307, 308) and e.headers.get("Location"):
                    url = urllib.parse.urljoin(url, e.headers["Location"])
                    continue
                if e.code == 401:
                    raise _AuthFail()
                text = ""
                try:
                    text = e.read().decode("utf-8", errors="replace")[:200]
                except Exception:
                    pass
                raise CalError(f"캘린더 서버가 {e.code} 로 거절했습니다 ({method} {urllib.parse.urlparse(url).path})",
                               "잠시 뒤 다시 해 보고, 계속되면 이 줄을 진행자에게 보여 주세요" + (f" — {text}" if text and e.code != 404 else ""))
            except (urllib.error.URLError, socket.timeout, TimeoutError, ssl.SSLError, ConnectionError) as e:
                raise CalError(f"캘린더 서버에 닿지 않습니다 ({urllib.parse.urlparse(url).hostname}: {getattr(e, 'reason', e)})",
                               "인터넷 연결·회사 방화벽을 확인하세요")
        raise CalError("캘린더 서버가 주소를 너무 여러 번 옮겼습니다", "진행자에게 이 줄을 보여 주세요")

    def request(self, method: str, url: str, body: str | None = None, depth: str | None = None, **kw):
        """로그인 이름 후보를 차례로 써 본다. 통한 이름은 기억해 다음부터 그것만 쓴다."""
        if self._auth:
            try:
                return self._send(method, url, body, depth, self._auth, **kw)
            except _AuthFail:
                raise CalError("로그인이 거절됐습니다 (아이디 또는 앱 비밀번호)", "앱 비밀번호를 새로 만들어 캘린더_연결.bat 으로 다시 넣으세요 · " + PW_HINT)
        for uid in self._login_ids():
            auth = base64.b64encode(f"{uid}:{self.cfg.app_password}".encode("utf-8")).decode("ascii")
            try:
                res = self._send(method, url, body, depth, auth, **kw)
            except _AuthFail:
                continue
            self._auth, self.user_used = auth, uid
            return res
        raise CalError("로그인이 거절됐습니다 (아이디 또는 앱 비밀번호)",
                       "2단계 인증을 켠 뒤 받은 「애플리케이션 비밀번호」 인지 확인하세요 (평소 비밀번호는 안 됩니다) · " + PW_HINT)

    # ── 찾아가기: 주인(principal) → 캘린더 집(home) → 캘린더들 ──
    def _propfind_href(self, url: str, prop: str, parent: str) -> str:
        body = (f'<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
                f'<d:prop><{prop}/></d:prop></d:propfind>')
        _, _, text, final = self.request("PROPFIND", url, body, "0")
        try:
            root = ET.fromstring(text)
        except ET.ParseError:
            return ""
        el = root.find(f".//{parent}/d:href", NS)
        return urllib.parse.urljoin(final, el.text.strip()) if el is not None and el.text else ""

    def principal(self) -> str:
        for start in (self.cfg.url + "/", self.cfg.url + "/.well-known/caldav"):
            href = self._propfind_href(start, "d:current-user-principal", "d:current-user-principal")
            if href:
                return href
        raise CalError("캘린더 서버에서 내 자리를 찾지 못했습니다 (current-user-principal 없음)", "진행자에게 이 줄을 보여 주세요")

    def home(self) -> str:
        p = self.principal()
        href = self._propfind_href(p, "c:calendar-home-set", "c:calendar-home-set")
        if not href:
            raise CalError("내 캘린더 목록 위치를 찾지 못했습니다 (calendar-home-set 없음)", "진행자에게 이 줄을 보여 주세요")
        return href

    def calendars(self) -> list[dict]:
        """[{href, name}] — 일정(VEVENT)을 담는 캘린더만."""
        home = self.home()
        body = ('<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
                '<d:prop><d:resourcetype/><d:displayname/><c:supported-calendar-component-set/></d:prop></d:propfind>')
        _, _, text, final = self.request("PROPFIND", home, body, "1")
        out = []
        for resp in ET.fromstring(text).findall("d:response", NS):
            href = resp.findtext("d:href", default="", namespaces=NS).strip()
            if resp.find(".//d:resourcetype/c:calendar", NS) is None:
                continue
            comps = [c.get("name", "").upper() for c in resp.findall(".//c:supported-calendar-component-set/c:comp", NS)]
            if comps and "VEVENT" not in comps:
                continue
            name = (resp.findtext(".//d:displayname", default="", namespaces=NS) or "").strip() or href.rstrip("/").rsplit("/", 1)[-1]
            out.append({"href": urllib.parse.urljoin(final, href), "name": name})
        return out

    def events(self, cal_href: str, start: datetime, end: datetime) -> list[dict]:
        """start~end(내 PC 시각) 사이 일정."""
        body = ('<?xml version="1.0" encoding="utf-8"?><c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
                '<d:prop><c:calendar-data/></d:prop><c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">'
                f'<c:time-range start="{_utc(start)}" end="{_utc(end)}"/></c:comp-filter></c:comp-filter></c:filter></c:calendar-query>')
        _, _, text, final = self.request("REPORT", cal_href, body, "1")
        out, need = [], []
        for resp in ET.fromstring(text).findall("d:response", NS):
            data = resp.findtext(".//c:calendar-data", default="", namespaces=NS)
            if data.strip():
                out.extend(parse_ics(data))
            else:
                href = resp.findtext("d:href", default="", namespaces=NS).strip()
                if href:
                    need.append(href)
        # 네이버는 이 검색에 일정 주소만 주고 내용(calendar-data)은 안 준다 → 주소로 내용을 한 번 더 받는다
        if need:
            mg = ('<?xml version="1.0" encoding="utf-8"?><c:calendar-multiget xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
                  '<d:prop><d:getetag/><c:calendar-data/></d:prop>' + "".join(f"<d:href>{h}</d:href>" for h in need) + '</c:calendar-multiget>')
            try:
                _, _, t2, _ = self.request("REPORT", cal_href, mg, "1")
                for el in ET.fromstring(t2).iter("{urn:ietf:params:xml:ns:caldav}calendar-data"):
                    if el.text:
                        out.extend(parse_ics(el.text))
            except (CalError, ET.ParseError):
                for h in need:   # 묶음으로 안 되면 하나씩
                    _, _, t3, _ = self.request("GET", urllib.parse.urljoin(final, h))
                    out.extend(parse_ics(t3))
        out.sort(key=lambda e: _sort_key(e["start"]))
        return out


# ── 시간 · iCalendar ──────────────────────────────────────────
def _utc(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _sort_key(v) -> datetime:
    return v if isinstance(v, datetime) else datetime(v.year, v.month, v.day)


def week_range(today: date | None = None) -> tuple[datetime, datetime]:
    """이번 주 월요일 0시 ~ 다음 주 월요일 0시 (내 PC 시각)."""
    d = today or date.today()
    mon = datetime(d.year, d.month, d.day) - timedelta(days=d.weekday())
    return mon, mon + timedelta(days=7)


def _parse_dt(prop: str, value: str):
    """DTSTART;TZID=Asia/Seoul:20261104T090000 → datetime (내 PC 시각). VALUE=DATE → date."""
    value = value.strip()
    if "VALUE=DATE" in prop.upper() or re.fullmatch(r"\d{8}", value):
        return datetime.strptime(value[:8], "%Y%m%d").date()
    if value.endswith("Z"):
        return datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc).astimezone().replace(tzinfo=None)
    return datetime.strptime(value[:15], "%Y%m%dT%H%M%S")   # TZID 가 붙은 값은 그 시각 그대로 (한국 시각 기준)


def _unescape(s: str) -> str:
    return s.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\")


def parse_ics(text: str) -> list[dict]:
    lines: list[str] = []
    for raw in text.replace("\r\n", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    out, cur = [], None
    for ln in lines:
        if ln == "BEGIN:VEVENT":
            cur = {"summary": "", "location": "", "uid": "", "start": None, "end": None}
        elif ln == "END:VEVENT" and cur is not None:
            if cur["start"] is not None:
                cur["all_day"] = not isinstance(cur["start"], datetime)
                out.append(cur)
            cur = None
        elif cur is not None and ":" in ln:
            prop, value = ln.split(":", 1)
            name = prop.split(";", 1)[0].upper()
            try:
                if name == "SUMMARY":
                    cur["summary"] = _unescape(value)
                elif name == "LOCATION":
                    cur["location"] = _unescape(value)
                elif name == "UID":
                    cur["uid"] = value
                elif name == "DTSTART":
                    cur["start"] = _parse_dt(prop, value)
                elif name == "DTEND":
                    cur["end"] = _parse_dt(prop, value)
            except ValueError:
                pass
    return out


def fmt_when(e: dict) -> str:
    WD = "월화수목금토일"
    s = e["start"]
    if e.get("all_day"):
        return f"{s:%m/%d}({WD[s.weekday()]}) 종일"
    t = f"{s:%m/%d}({WD[s.weekday()]}) {s:%H:%M}"
    if isinstance(e.get("end"), datetime):
        t += f"~{e['end']:%H:%M}"
    return t
