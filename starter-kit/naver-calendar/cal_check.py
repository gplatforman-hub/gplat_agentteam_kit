"""cal_check.py — 네이버 캘린더가 연결되는지 본다. (읽기만 한다. 일정을 넣거나 고치지 않는다)

  py -3 naver-calendar/cal_check.py

  잘 되면   OK: 네이버 캘린더 아이디 — 캘린더 2개 (내 캘린더, 기념일) · 이번 주 일정 3개   (종료 코드 0)
  안 되면   FAIL: 원인 → 해결                                                        (종료 코드 1)

--detail 을 붙이면 찾아간 서버 위치(비밀번호 아님)와 이번 주 일정 제목까지 보여준다.
🔒 비밀번호는 어디에도 찍지 않는다.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cal_common import CalDAV, CalError, KoArgumentParser, fmt_when, load_config, week_range   # noqa: E402


def main() -> int:
    ap = KoArgumentParser(prog="cal_check.py",
                          description="네이버 캘린더에 로그인해 캘린더 목록과 이번 주 일정 수를 봅니다. 일정을 바꾸지 않습니다.")
    ap.add_argument("--detail", action="store_true", help="서버 위치와 이번 주 일정 제목까지 보여줍니다")
    args = ap.parse_args()

    try:
        cfg = load_config()
        dav = CalDAV(cfg)
        cals = dav.calendars()
        if not cals:
            print(f"FAIL: 네이버 캘린더 {dav.user_used} — 로그인은 됐지만 일정 캘린더가 없습니다 → 네이버 캘린더에서 캘린더를 하나 만들어 보세요")
            return 1
        start, end = week_range()
        per = []
        for c in cals:
            try:
                per.append((c, dav.events(c["href"], start, end)))
            except CalError as e:
                per.append((c, None))
                if args.detail:
                    print(f"  ! {c['name']}: {e.line()}")
    except CalError as e:
        print(f"FAIL: {e.line()}")
        return 1

    n = sum(len(ev) for _, ev in per if ev)
    names = ", ".join(c["name"] for c in cals)
    print(f"OK: 네이버 캘린더 {dav.user_used} — 캘린더 {len(cals)}개 ({names}) · 이번 주 일정 {n}개")
    if args.detail:
        print(f"  로그인 이름: {dav.user_used}  (적힌 값: {cfg.user})")
        for c, ev in per:
            print(f"  [{c['name']}] {c['href']}")
            for e in ev or []:
                print(f"     {fmt_when(e)}  {e['summary']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
