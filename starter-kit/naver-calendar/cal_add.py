"""cal_add.py — 네이버 캘린더에 일정 하나를 넣는다. 사람이 확인한 뒤에만.

  py -3 naver-calendar/cal_add.py --title "거래처 미팅" --start "2026-11-10 14:00" --minutes 60
      → 넣을 내용만 보여 주고 끝 (아직 넣지 않음)
  py -3 naver-calendar/cal_add.py --title "거래처 미팅" --start "2026-11-10 14:00" --minutes 60 --approved
      → 실제로 넣고, 다시 읽어 들어갔는지 확인

  종일 일정:  --all-day 2026-11-12
  캘린더:     --calendar "내 캘린더" (비우면 「내 캘린더」, 없으면 첫 캘린더)

🔒 고치기·지우기는 하지 않는다 — 사람이 네이버 캘린더에서 한다.
"""
from __future__ import annotations

import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cal_common import CalDAV, CalError, KoArgumentParser, die, fmt_when, load_config   # noqa: E402


def _esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def _utc(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def main() -> int:
    ap = KoArgumentParser(prog="cal_add.py",
                          description="네이버 캘린더에 일정 하나를 넣습니다. --approved 가 없으면 넣을 내용만 보여 줍니다.")
    ap.add_argument("--title", required=True, help="일정 제목")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--start", metavar='"YYYY-MM-DD HH:MM"', help="시작 시각")
    g.add_argument("--all-day", metavar="YYYY-MM-DD", help="종일 일정 날짜")
    ap.add_argument("--minutes", type=int, default=60, help="길이(분). 기본 60")
    ap.add_argument("--location", default="", help="장소")
    ap.add_argument("--memo", default="", help="메모")
    ap.add_argument("--calendar", metavar="이름", help="넣을 캘린더 (기본: 내 캘린더)")
    ap.add_argument("--approved", action="store_true", help="사람이 확인했다 — 실제로 넣는다")
    args = ap.parse_args()

    try:
        if args.all_day:
            day = datetime.strptime(args.all_day, "%Y-%m-%d").date()
            ev = {"start": day, "end": day + timedelta(days=1), "all_day": True}
            dt_lines = [f"DTSTART;VALUE=DATE:{day:%Y%m%d}", f"DTEND;VALUE=DATE:{day + timedelta(days=1):%Y%m%d}"]
        else:
            st = datetime.strptime(args.start, "%Y-%m-%d %H:%M")
            en = st + timedelta(minutes=max(args.minutes, 5))
            ev = {"start": st, "end": en, "all_day": False}
            dt_lines = [f"DTSTART:{_utc(st)}", f"DTEND:{_utc(en)}"]
    except ValueError:
        die('시각은 "2026-11-10 14:00", 날짜는 2026-11-12 처럼 적어 주세요', 2)

    try:
        dav = CalDAV(load_config())
        cals = dav.calendars()
    except CalError as e:
        die(e)
    want = args.calendar or "내 캘린더"
    pick = [c for c in cals if want in c["name"]]
    if args.calendar and not pick:
        die(f"「{args.calendar}」 이 들어간 캘린더가 없습니다 → cal_check.py 로 캘린더 이름을 보세요", 1)
    cal = (pick or cals)[0]

    head = f"[{cal['name']}] {fmt_when(ev)}  {args.title}" + (f"  @{args.location}" if args.location else "")
    if not args.approved:
        print(f"PREVIEW: {head}")
        print("  (아직 넣지 않았습니다 — 사람이 확인하면 같은 명령에 --approved 를 붙여 다시 실행)")
        return 0

    uid = f"{uuid.uuid4()}@gplat-starterkit"
    ics = "\r\n".join([
        "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//gplat starter-kit//naver-calendar//KO", "BEGIN:VEVENT",
        f"UID:{uid}", f"DTSTAMP:{_utc(datetime.now())}", *dt_lines, f"SUMMARY:{_esc(args.title)}",
        *([f"LOCATION:{_esc(args.location)}"] if args.location else []),
        *([f"DESCRIPTION:{_esc(args.memo)}"] if args.memo else []),
        "END:VEVENT", "END:VCALENDAR", ""])
    url = cal["href"].rstrip("/") + "/" + uid.split("@")[0] + ".ics"
    try:
        dav.request("PUT", url, ics, None, ctype="text/calendar; charset=utf-8", extra={"If-None-Match": "*"})
        s = ev["start"] if not ev["all_day"] else datetime(ev["start"].year, ev["start"].month, ev["start"].day)
        back = dav.events(cal["href"], s - timedelta(hours=1), s + timedelta(days=1))
    except CalError as e:
        die(e)
    ok = any(e["summary"] == args.title for e in back)
    print(f"ADDED: {head}" + ("  (다시 읽어 확인함)" if ok else "  (넣었지만 다시 읽기에서 안 보입니다 — 네이버 캘린더 화면에서 확인하세요)"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
