"""cal_read.py — 네이버 캘린더 일정을 본다. (읽기만 한다)

  py -3 naver-calendar/cal_read.py                 이번 주 (월~일)
  py -3 naver-calendar/cal_read.py --today         오늘
  py -3 naver-calendar/cal_read.py --days 14       오늘부터 14일
  py -3 naver-calendar/cal_read.py --from 2026-11-10 --to 2026-11-14
  py -3 naver-calendar/cal_read.py --calendar "내 캘린더" --json

🔒 비밀번호는 어디에도 찍지 않는다.
"""
from __future__ import annotations

import json
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cal_common import CalDAV, CalError, KoArgumentParser, die, fmt_when, load_config, week_range   # noqa: E402


def _day(s: str) -> datetime:
    try:
        return datetime.strptime(s, "%Y-%m-%d")
    except ValueError:
        die(f"날짜는 2026-11-10 처럼 적어 주세요 ({s})", 2)


def main() -> int:
    ap = KoArgumentParser(prog="cal_read.py", description="네이버 캘린더 일정을 봅니다. 일정을 바꾸지 않습니다.")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--today", action="store_true", help="오늘 일정")
    g.add_argument("--days", type=int, metavar="N", help="오늘부터 N일")
    g.add_argument("--from", dest="frm", metavar="YYYY-MM-DD", help="시작 날짜 (--to 와 함께)")
    ap.add_argument("--to", metavar="YYYY-MM-DD", help="끝 날짜 (그날 포함)")
    ap.add_argument("--calendar", metavar="이름", help="이 이름이 들어간 캘린더만")
    ap.add_argument("--json", action="store_true", help="JSON 으로 (직원이 다시 쓸 때)")
    args = ap.parse_args()

    t = date.today()
    t0 = datetime(t.year, t.month, t.day)
    if args.today:
        start, end, label = t0, t0 + timedelta(days=1), "오늘"
    elif args.days:
        start, end, label = t0, t0 + timedelta(days=args.days), f"오늘부터 {args.days}일"
    elif args.frm:
        start = _day(args.frm)
        end = (_day(args.to) if args.to else start) + timedelta(days=1)
        label = f"{start:%Y-%m-%d} ~ {end - timedelta(days=1):%Y-%m-%d}"
    else:
        start, end = week_range()
        label = f"이번 주 ({start:%m/%d}~{end - timedelta(days=1):%m/%d})"

    try:
        dav = CalDAV(load_config())
        cals = dav.calendars()
        if args.calendar:
            cals = [c for c in cals if args.calendar in c["name"]]
            if not cals:
                die(f"「{args.calendar}」 이 들어간 캘린더가 없습니다 → cal_check.py 로 캘린더 이름을 보세요", 1)
        rows = []
        for c in cals:
            for e in dav.events(c["href"], start, end):
                rows.append({**e, "calendar": c["name"]})
    except CalError as e:
        die(e)

    rows.sort(key=lambda e: e["start"] if isinstance(e["start"], datetime) else datetime(e["start"].year, e["start"].month, e["start"].day))
    if args.json:
        out = [{"calendar": e["calendar"], "when": fmt_when(e), "summary": e["summary"], "location": e["location"],
                "start": e["start"].isoformat(), "end": e["end"].isoformat() if e["end"] else None, "all_day": e["all_day"]}
               for e in rows]
        print(json.dumps({"range": label, "count": len(out), "events": out}, ensure_ascii=False, indent=2))
        return 0
    print(f"📅 네이버 캘린더 · {label} · {len(rows)}개")
    for e in rows:
        loc = f"  @{e['location']}" if e["location"] else ""
        print(f"  {fmt_when(e)}  {e['summary'] or '(제목 없음)'}{loc}  [{e['calendar']}]")
    if not rows:
        print("  (일정 없음)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
