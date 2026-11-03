"""mail_draft.py — 메일을 '임시보관함'에 저장한다. 보내지 않는다.

  py -3.14 mail/mail_draft.py --to hong@naver.com --subject "제목" --body-file 초안.md
      → 메일함의 임시보관함에 초안으로 넣는다. 끝나면  DRAFT: 임시보관함 / 제목  한 줄.

  --to 주소        받는 사람 (여러 번 가능)
  --cc 주소        참조 (여러 번 가능)
  --body 텍스트    본문 글 (--body-file 과 둘 중 하나)
  --body-file 파일 본문이 든 파일 (UTF-8)

보내는 것이 아니므로 SMTP 에는 붙지 않는다. 받는 사람에게는 아무것도 가지 않는다.
메일 앱(지메일·네이버·다음)에서 임시보관함을 열어 고친 뒤 사람이 직접 보낸다.
🔒 비밀번호는 어디에도 찍지 않는다.

2026-11-03 슬랙의 팀장이 처음 만든 것을 킷에 넣으며 보완: 폴더 이름의 IMAP 한글 표기(수정 UTF-7)를
풀어서 찾고 보여 준다 — 네이버처럼 \\Drafts 표시가 없고 폴더 이름이 한글인 메일함도 찾게.
"""
from __future__ import annotations

import base64
import imaplib
import re
import sys
import time
from email.message import EmailMessage
from email.utils import formatdate, make_msgid, parseaddr
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mail_common import KoArgumentParser, MailError, connect_imap, die, load_config   # noqa: E402

# 특수 용도 표시(\Drafts)로 못 찾을 때 비교할 이름 (풀어 쓴 글자, 대소문자 무시)
FALLBACK_NAMES = ("[gmail]/임시보관함", "[gmail]/drafts", "임시보관함", "임시 보관함", "drafts", "draft", "inbox.drafts")
_LIST_RE = re.compile(r'\((?P<flags>[^)]*)\)\s+(?:"[^"]*"|NIL)\s+(?P<name>"(?:[^"\\]|\\.)*"|\S+)$')


def mutf7_decode(s: str) -> str:
    """IMAP 폴더 이름 표기(&...-)를 사람이 읽는 글자로. '[Gmail]/&x4TV0LzQ-' → '[Gmail]/임시보관함'."""
    def one(m: re.Match) -> str:
        b = m.group(1)
        if not b:
            return "&"
        b = b.replace(",", "/")
        b += "=" * (-len(b) % 4)
        try:
            return base64.b64decode(b).decode("utf-16-be")
        except Exception:
            return m.group(0)
    return re.sub(r"&([A-Za-z0-9+,]*)-", one, s)


def find_drafts_folder(M: imaplib.IMAP4_SSL) -> tuple[str, str]:
    """(서버에 보낼 이름, 사람이 읽는 이름). \\Drafts 표시가 먼저, 없으면 흔한 이름."""
    typ, data = M.list()
    found: list[tuple[str, str]] = []
    if typ == "OK":
        for raw in data or []:
            if not raw:
                continue
            line = raw.decode("utf-8", errors="replace") if isinstance(raw, bytes) else str(raw)
            m = _LIST_RE.search(line.strip())
            if not m:
                continue
            name = m.group("name")
            if name.startswith('"'):
                name = name[1:-1].replace('\\"', '"')
            pretty = mutf7_decode(name)
            if "\\drafts" in m.group("flags").lower():
                return name, pretty
            found.append((name, pretty))
    for cand in FALLBACK_NAMES:
        for name, pretty in found:
            if pretty.lower() == cand:
                return name, pretty
    raise MailError("임시보관함 폴더를 찾지 못했습니다",
                    "메일 웹에서 임시보관함이 있는지, IMAP 에서 그 폴더가 보이게 설정돼 있는지 확인하세요")


def main() -> int:
    ap = KoArgumentParser(
        prog="mail_draft.py",
        description="메일을 임시보관함에 저장합니다. 보내지 않습니다.")
    ap.add_argument("--to", action="append", default=[], metavar="주소", required=True, help="받는 사람 (여러 번 가능)")
    ap.add_argument("--subject", required=True, metavar="제목", help="제목")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--body", metavar="텍스트", help="본문 글")
    g.add_argument("--body-file", metavar="파일", help="본문이 든 파일 (UTF-8, .md/.txt)")
    ap.add_argument("--cc", action="append", default=[], metavar="주소", help="참조 (여러 번 가능)")
    args = ap.parse_args()

    to = [a.strip() for a in args.to if a.strip()]
    cc = [a.strip() for a in args.cc if a.strip()]
    bad = [a for a in to + cc if "@" not in parseaddr(a)[1]]
    if bad:
        die(MailError(f"받는 사람 주소 모양이 아닙니다: {', '.join(bad)}", "hong@naver.com 처럼 @ 가 들어간 주소로"))
    subject = args.subject.strip()
    if not subject:
        die(MailError("제목이 비어 있습니다", "--subject 에 제목을 넣으세요"))

    if args.body_file:
        p = Path(args.body_file)
        if not p.is_file():
            die(MailError(f"본문 파일이 없습니다: {p}", "경로를 확인하세요"))
        body = p.read_text(encoding="utf-8-sig", errors="replace")
    else:
        body = args.body or ""
    if not body.strip():
        die(MailError("본문이 비어 있습니다", "--body 또는 --body-file 에 내용을 넣으세요"))

    try:
        cfg = load_config()
    except MailError as e:
        die(e)
        return 1

    msg = EmailMessage()
    msg["From"] = cfg.user
    msg["To"] = ", ".join(to)
    if cc:
        msg["Cc"] = ", ".join(cc)
    msg["Subject"] = subject
    msg["Date"] = formatdate(localtime=True)
    msg["Message-ID"] = make_msgid()
    msg.set_content(body)

    try:
        M = connect_imap(cfg)
        try:
            folder, pretty = find_drafts_folder(M)
            typ, _ = M.append(f'"{folder}"', "\\Draft", imaplib.Time2Internaldate(time.time()), msg.as_bytes())
            if typ != "OK":
                die(MailError(f"임시보관함({pretty})에 저장하지 못했습니다", "메일 웹에서 폴더 상태를 확인하세요"))
        finally:
            try:
                M.logout()
            except Exception:
                pass
    except MailError as e:
        die(e)
        return 1
    except Exception as e:
        die(MailError(f"저장하는 중 실패했습니다 ({type(e).__name__}: {str(e)[:120]})", "잠시 뒤 다시 시도하세요"))
        return 1

    print(f"DRAFT: {pretty} / {subject}  (보내지 않았습니다 — 메일 앱 임시보관함에서 고쳐 직접 보내세요)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
