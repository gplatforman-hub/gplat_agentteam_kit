"""점검.py — 모듈이 끝날 때마다 여기서 합격 판정을 받습니다.

사용법 (점검 번호 = 모듈 번호 · 직장인판 8시간):
    py 점검.py 0     ← 출발선 (프로그램이 다 깔렸는지)
    py 점검.py 2     ← 규칙표 (facts.md)
    py 점검.py 3     ← 회의록
    py 점검.py 4     ← 집계
    py 점검.py 5     ← 스킬 (회의록·주간보고)
    py 점검.py 6     ← 직원 팀 · 릴레이
    py 점검.py 7     ← 직무 트랙 (6번째 직원)
    py 점검.py 8     ← 슬랙에서 부르기
    py 점검.py 9     ← 전체 점검
    py 점검.py 10    ← (부록 A) 내 양식

이 파일은 고치지 마세요. 여러분이 만든 것이 규격에 맞는지 확인하는 채점표입니다.
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# 윈도우 콘솔에서 한글·이모지가 깨지지 않도록.
#
# 한국어 윈도우의 검은 창은 기본 코드페이지가 949 다. 거기에 utf-8 로 내보내면
# 글자가 전부 깨진다(cmd·PowerShell 둘 다 똑같이 깨진다 — 셸 문제가 아니라 코드페이지 문제다).
# 그래서 출력 방식을 바꾸기 전에 창의 코드페이지 자체를 65001(UTF-8)로 먼저 바꾼다.
# 이렇게 해두면 수강생이 chcp 65001 을 외우지 않아도 된다.
if sys.platform == "win32":
    try:
        import ctypes
        ctypes.windll.kernel32.SetConsoleOutputCP(65001)
    except Exception:
        pass
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = Path(__file__).resolve().parent
OK, NO = "✅", "❌"


# ── 도우미 ────────────────────────────────────────────────

def run(cmd):
    """명령어를 실행해 첫 줄을 돌려준다. 실패하면 None."""
    exe = shutil.which(cmd[0])
    if exe is None:
        return None
    try:
        out = subprocess.run([exe] + cmd[1:], capture_output=True, text=True, timeout=20)
    except Exception:
        return None
    text = (out.stdout or out.stderr).strip()
    return text.splitlines()[0] if text else None


def major(version_text):
    """'v22.1.0' / 'Python 3.13.1' 에서 앞 숫자 두 개를 뽑는다."""
    m = re.search(r"(\d+)\.(\d+)", version_text or "")
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def agent_files():
    return sorted((ROOT / ".claude" / "agents").glob("*.md"))


def skill_files():
    return sorted((ROOT / ".claude" / "skills").glob("*/SKILL.md"))


def front_matter(path):
    """파일 맨 위 --- 로 둘러싸인 부분에서 key: value 를 읽는다."""
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return {}
    m = re.match(r"^\s*---\s*\n(.*?)\n---", text, re.S)
    body = m.group(1) if m else text[:800]
    found = {}
    for line in body.splitlines():
        kv = re.match(r"\s*([A-Za-z_]+)\s*:\s*(.+?)\s*$", line)
        if kv:
            found[kv.group(1).lower()] = kv.group(2)
    return found


# ── 결과물(인쇄물) 검사 도우미 ─────────────────────────────
# 2026-08-15 추가. "파일이 나왔는지"를 파일 이름만이 아니라 **내용**으로도 판별한다.
# (AI 가 파일 이름을 매번 조금씩 다르게 짓기 때문)
# 2026-10-28 직장인판: 제안서 덱·교재 워크북 → 회의록(.md)·주간보고(.html)

_TEXT_CACHE = {}


def text_of(path):
    """파일 내용을 읽어 캐시한다. 못 읽으면 빈 문자열."""
    key = str(path)
    if key not in _TEXT_CACHE:
        try:
            _TEXT_CACHE[key] = path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            _TEXT_CACHE[key] = ""
    return _TEXT_CACHE[key]


def result_html():
    d = ROOT / "workspace" / "결과물"
    return sorted(d.glob("*.html")) if d.is_dir() else []


def result_files():
    d = ROOT / "workspace" / "결과물"
    return sorted(p for p in d.glob("*") if p.is_file()) if d.is_dir() else []


def minutes():
    """회의록(.md) — 이름에 '회의록' 이 있는 md. 주간보고·집계는 본문에 '할 일'·'담당' 이 있어도 회의록이 아니다."""
    return [p for p in result_files()
            if p.suffix.lower() == ".md" and "회의록" in p.name
            and not any(x in p.name for x in ("주간보고", "집계", "할일_목록"))]


def todo_list():
    p = ROOT / "workspace" / "결과물" / "할일_목록.md"
    return p if p.is_file() else None


def weekly_reports():
    """주간보고 한 장(.html) — '주간보고' 가 들어 있고 A4 판형(794 × 1123 또는 size:A4)인 html"""
    out = []
    for p in result_html():
        t = text_of(p).replace(" ", "")
        a4 = ("794" in t and "1123" in t) or "size:A4" in t
        if a4 and ("주간보고" in p.name or "주간보고" in t):
            out.append(p)
    return out


def weekly_any():
    """주간보고 결과물 전부(.md·.html) — 다시 만들었는지 시각을 볼 때 쓴다"""
    return [p for p in result_files() if "주간보고" in p.name]


def team_name():
    """facts.md 에서 '팀 이름'(없으면 '회사 이름') 값을 뽑는다. 못 찾으면 None."""
    f = ROOT / "workspace" / "memory" / "facts.md"
    if not f.is_file():
        return None
    for key in (r"(?:내\s*)?팀\s*이름", r"회사\s*이름"):
        for line in text_of(f).splitlines():
            m = re.match(r"\s*[-*]?\s*" + key + r"\s*[:：]\s*(.+?)\s*$", line)
            if m:
                v = re.split(r"\s+←", m.group(1))[0].strip().strip("[]").strip()
                if v:
                    return v
    return None


COMMON_SKILLS = {"회의록": ("회의록", "meeting"), "주간보고": ("주간보고", "weekly"),
                 "집계": ("집계", "data-summary", "aggregate"), "취합": ("취합", "data-merge")}
TRACK_SKILLS = {"블로그": ("블로그", "blog"), "제안서": ("제안서", "proposal"),
                "교재": ("교재", "워크북", "workbook"), "기획서": ("기획서", "planning"),
                "예산실적": ("예산", "budget"), "해외답장": ("해외", "overseas")}


def skill_job_dirs(keys):
    """폴더 이름이나 SKILL.md 의 name 에 keys 중 하나가 들어간 스킬 폴더"""
    d = ROOT / ".claude" / "skills"
    if not d.is_dir():
        return []
    hit = []
    for s in d.glob("*"):
        if not s.is_dir() or s.name.startswith("_"):
            continue
        head = (s.name + " " + front_matter(s / "SKILL.md").get("name", "")).lower()
        if any(k.lower() in head for k in keys):
            hit.append(s.name)
    return hit


def offline_ok(files):
    """인터넷 주소를 쓴 파일 이름 목록. 비어 있으면 오프라인에서 열린다."""
    bad = []
    for p in files:
        t = text_of(p)
        if 'src="http' in t or "src='http" in t or 'href="http' in t or "href='http" in t:
            bad.append(p.name)
    return bad


def printable(files):
    """인쇄 설정(@page)이 들어간 파일이 하나라도 있는지"""
    return any("@page" in text_of(p) for p in files)


# ── 모듈별 검사 ────────────────────────────────────────────

def module_0():
    checks = []

    node = run(["node", "-v"])
    checks.append(("Node.js 22 이상", node is not None and major(node)[0] >= 22,
                   node or "설치 안 됨 → nodejs.org 에서 LTS 설치"))

    py = f"{sys.version_info.major}.{sys.version_info.minor}"
    # 수업 표준은 3.14 (환경점검이 무조건 설치). 다른 버전으로 이 파일을 돌리면 여기서 알려준다.
    checks.append(("Python 3.14 (수업 표준)", sys.version_info[:2] == (3, 14),
                   f"현재 {py}" + ("" if sys.version_info[:2] == (3, 14) else " → 환경점검.bat 을 실행하면 3.14 가 깔리고 py 가 3.14 로 고정됩니다")))

    git = run(["git", "--version"])
    checks.append(("Git", git is not None, git or "설치 안 됨 → git-scm.com"))

    claude = shutil.which("claude") or shutil.which("claude.cmd")
    codex = shutil.which("codex") or shutil.which("codex.cmd")
    checks.append(("AI 코딩 도구 (claude 또는 codex)", bool(claude or codex),
                   claude or codex or "둘 중 하나는 설치돼 있어야 합니다"))

    need = [".claude/agents", ".claude/skills", "workspace/inbox", "workspace/memory"]
    missing = [d for d in need if not (ROOT / d).is_dir()]
    checks.append(("스타터킷 폴더 구조", not missing,
                   "정상" if not missing else "없는 폴더: " + ", ".join(missing)))

    # 자동 저장·안전장치 (.claude/settings.json + hooks 2개). 이게 없으면 직원이 한 일이 기록되지 않고
    # 삭제·덮어쓰기도 확인 없이 지나간다.
    hooks = [".claude/settings.json", ".claude/hooks/autosave.py", ".claude/hooks/guard.py"]
    lost = [h for h in hooks if not (ROOT / h).is_file()]
    ok_json = True
    if not lost:
        try:
            import json
            cfg = json.loads((ROOT / ".claude/settings.json").read_text(encoding="utf-8"))
            ok_json = bool(cfg.get("hooks", {}).get("PreToolUse")) and bool(cfg.get("hooks", {}).get("Stop"))
        except Exception:
            ok_json = False
    checks.append(("자동 저장·안전장치 (기록 + 삭제 확인)", not lost and ok_json,
                   "켜져 있음" if not lost and ok_json else
                   ("없는 파일: " + ", ".join(lost) if lost else "settings.json 이 깨졌습니다 → 스타터킷 원본에서 다시 복사")))
    launcher = shutil.which("py")
    checks.append(("py 실행기 (안전장치가 py -3 로 돈다)", launcher is not None,
                   launcher or "py 가 없습니다 → 환경점검.bat 을 다시 실행 (py launcher 포함 설치)"))
    pinned = os.environ.get("PY_PYTHON3", "") == "3.14" or sys.version_info[:2] == (3, 14)
    checks.append(("py 가 3.14 를 가리킨다 (PY_PYTHON3)", pinned,
                   "정상" if pinned else "환경점검.bat 을 다시 실행하면 고정됩니다. 새 창을 열어야 적용됩니다"))

    checks.append(("한글 경로에서 실행 중", True, str(ROOT)))
    return checks


def module_1():
    files = agent_files()
    checks = [("직원이 1명 이상 있다", len(files) >= 1, f"{len(files)}명")]
    checks.append(("직원이 5명 이상 있다", len(files) >= 5, f"{len(files)}명"))

    bad = []
    names = []
    for f in files:
        fm = front_matter(f)
        missing = [k for k in ("name", "description") if k not in fm]
        if missing:
            bad.append(f"{f.name}({','.join(missing)} 없음)")
        if "name" in fm:
            names.append(fm["name"])
    checks.append(("모든 직원 파일에 name·description 이 있다", not bad,
                   "정상" if not bad else " / ".join(bad)))

    dupes = {n for n in names if names.count(n) > 1}
    checks.append(("직원 이름이 서로 겹치지 않는다", not dupes,
                   "정상" if not dupes else "겹침: " + ", ".join(sorted(dupes))))

    # ── 2026-09-04 추가 — 보고서 색이 facts.md 에 있는지 (P1 / P1-B) ──
    # 주간보고(P4)·집계(P9)·트랙 스킬이 전부 이 네 줄을 읽어 칠한다. 없으면 나중에 전부 남색 예시로 나온다.
    facts = ROOT / "workspace" / "memory" / "facts.md"
    ftxt = facts.read_text(encoding="utf-8", errors="ignore") if facts.is_file() else ""
    hexes = {m.upper() for m in re.findall(r"#[0-9A-Fa-f]{6}\b", ftxt)}
    sample = {"#12314B", "#1F5B8E", "#E9A23B", "#EAF1F8"}
    if not facts.is_file():
        hit, why = False, "facts.md 가 없습니다 — 카드 P2 를 붙여넣으세요"
    elif len(hexes) < 3:
        hit, why = False, f"색 hex 가 {len(hexes)}개뿐입니다 — 카드 P2 를 다시 붙여넣으세요 (진한·기본·강조·옅은)"
    elif not (hexes - sample):
        hit, why = True, "예시 남색 그대로입니다 (선택) — 카드 P2-B 로 내 색을 정하면 보고서가 내 색으로 나옵니다"
    else:
        hit, why = True, f"내 보고서 색 {len(hexes)}개 확인 ({', '.join(sorted(hexes))})"
    checks.append(("보고서 색 네 줄이 facts.md 에 있다", hit, why))
    return checks


def module_2():
    files = skill_files()
    # 모듈 5 는 카드 P5(회의록)·P5-d(주간보고)로 스킬을 2개 만든다.
    checks = [("스킬이 2개 이상 있다 (회의록 · 주간보고)", len(files) >= 2, f"{len(files)}개")]

    lack = [job for job, keys in (("회의록", COMMON_SKILLS["회의록"]), ("주간보고", COMMON_SKILLS["주간보고"]))
            if not skill_job_dirs(keys)]
    checks.append(("회의록 스킬과 주간보고 스킬이 둘 다 있다", not lack,
                   "정상" if not lack else "없는 스킬: " + ", ".join(lack) + " — 카드 P5 · P5-d"))

    bad = []
    for f in files:
        fm = front_matter(f)
        missing = [k for k in ("name", "description") if k not in fm]
        if missing:
            bad.append(f"{f.parent.name}({','.join(missing)} 없음)")
    checks.append(("모든 SKILL.md 에 name·description 이 있다", not bad,
                   "정상" if not bad else " / ".join(bad)))

    linked = any("skill" in front_matter(f).get("description", "").lower()
                 or any(k in f.read_text(encoding="utf-8", errors="ignore") for k in ("스킬", "skills/"))
                 for f in agent_files())
    checks.append(("직원 파일에서 스킬을 언급한다", linked,
                   "정상" if linked else "카드 P6-b 로 어느 직원이 어느 스킬을 쓰는지 연결하세요"))

    mn = minutes()
    checks.append(("회의록(.md)이 나왔다", len(mn) >= 1,
                   mn[0].name if mn else
                   "'실습자료/회의메모_01.txt 로 회의록 만들어줘' (카드 P3)"))

    checks.append(("할 일이 할일_목록.md 에 쌓였다", todo_list() is not None,
                   "정상" if todo_list() else
                   "workspace/결과물/할일_목록.md 가 없습니다 — 회의록 스킬의 [작성 원칙] 마지막 줄을 확인하세요"))

    # ── 주간보고 한 장(.html) ──
    wr = weekly_reports()
    checks.append(("주간보고 한 장(.html)이 나왔다", len(wr) >= 1,
                   wr[0].name if wr else
                   "카드 P5-d 의 바로 시켜보기 — .md 와 .html 두 개가 나옵니다"))

    checks.append(("주간보고가 인쇄해서 PDF로 저장된다", printable(wr),
                   "정상 (@page 설정 있음)" if printable(wr) else
                   "주간보고에 @page 인쇄 설정이 없습니다 — 카드 P5-d 를 다시 붙여넣으세요"))

    name = team_name()
    if not wr:
        hit, why = False, "주간보고가 아직 없습니다"
    elif not name:
        hit, why = True, "facts.md 에 '팀 이름:' 줄이 없어 이 검사는 건너뜁니다"
    else:
        hit = any(name in text_of(p) for p in wr)
        why = f"'{name}' 확인" if hit else \
              f"facts.md 의 팀 이름 '{name}' 이 주간보고에 없습니다 — \"주간보고 맨 위 띠에 팀 이름 넣어줘\""
    checks.append(("주간보고에 내 팀 이름이 들어갔다", hit, why))

    bad = offline_ok(wr)
    checks.append(("주간보고가 인터넷 없이 열린다", bool(wr) and not bad,
                   "정상" if wr and not bad else
                   ("주간보고가 아직 없습니다" if not wr else
                    "인터넷 주소를 쓴 파일: " + ", ".join(bad) + " — 오프라인에서 깨집니다")))
    return checks


def module_3():
    facts = ROOT / "workspace" / "memory" / "facts.md"
    checks = [("팀 규약(facts.md)이 있다", facts.is_file(), str(facts.relative_to(ROOT)))]

    size = facts.stat().st_size if facts.is_file() else 0
    checks.append(("팀 규약에 내용이 채워져 있다", size > 200, f"{size} 바이트 (200 이상 필요)"))

    # 2026-09-14 추가 — facts.md 의 인코딩. 메모장에서 'ANSI' 로 저장하면 한글이 깨져
    # 직원이 대표 이름을 못 읽고 엉뚱한 이름을 지어냈다. 바이트 수만으로는 안 잡힌다.
    enc_ok, enc_msg = True, "정상 (UTF-8)"
    if facts.is_file():
        raw = facts.read_bytes()
        try:
            raw.decode("utf-8-sig")
        except UnicodeDecodeError:
            try:
                raw.decode("cp949")
                enc_ok = False
                enc_msg = ("ANSI(CP949)로 저장돼 있습니다 — 메모장에서 열어 '다른 이름으로 저장' → "
                           "인코딩 UTF-8 로 덮어쓰세요")
            except UnicodeDecodeError:
                enc_ok = False
                enc_msg = "글자가 깨져 읽히지 않습니다 — 카드 P2 로 facts.md 를 다시 만드세요"
    checks.append(("팀 규약이 UTF-8 로 저장돼 있다 (한글이 안 깨지는 근거)", enc_ok, enc_msg))

    notes = [p for p in (ROOT / "workspace" / "inbox").rglob("*") if p.is_file()]
    checks.append(("직원끼리 넘긴 쪽지가 1개 이상 있다", len(notes) >= 1,
                   f"{len(notes)}개" if notes else "workspace/inbox 가 비어 있습니다"))

    made = result_files()
    checks.append(("결과물이 2개 이상 쌓였다", len(made) >= 2, f"{len(made)}개"))

    # ── 릴레이 (카드 P6-d) — 회의록대리가 쪽지를 넘긴 뒤 팀장이 주간보고를 다시 만들었는지 ──
    # 쪽지보다 나중에 저장된 주간보고가 있으면 이어받아 다시 만든 것이다.
    mn = minutes()
    checks.append(("회의록이 2개 이상 나왔다 (회의메모_01 · 02)", len(mn) >= 2,
                   f"{len(mn)}개" if mn else "카드 P3 · P6-d 의 회의록이 아직 없습니다"))

    wk = weekly_any()
    if not notes:
        hit, why = False, "쪽지가 아직 없습니다 — 카드 P6-d 첫 상자부터"
    elif not wk:
        hit, why = False, "주간보고가 아직 없습니다 — 카드 P6-d 둘째 상자"
    else:
        first_note = min(p.stat().st_mtime for p in notes)
        newer = [p.name for p in wk if p.stat().st_mtime > first_note]
        hit = bool(newer)
        why = newer[0] if newer else \
              "쪽지 뒤에 다시 만든 주간보고가 없습니다 — 'staff1 불러서 inbox 확인하고 … 주간보고 다시 만들어줘'"
    checks.append(("쪽지를 받은 뒤 주간보고를 다시 만들었다 (릴레이)", hit, why))
    return checks


def check_sleep():
    """윈도우 절전(대기) 설정을 읽는다. 0초 = '해당 없음' = 안 잔다.

    powercfg 출력의 마지막 두 16진수가 각각 AC(전원 연결)·DC(배터리) 값이다.
    글자는 언어마다 다르지만 숫자 자리는 같아서, 한글/영문 윈도우 모두에서 읽힌다.
    """
    try:
        out = subprocess.run(
            ["powercfg", "/q", "SCHEME_CURRENT", "SUB_SLEEP", "STANDBYIDLE"],
            capture_output=True, text=True, timeout=15,
            encoding="cp949", errors="ignore",
        ).stdout
    except Exception:
        return True, "확인 못 함 — 넘어갑니다 (전원 설정에서 직접 '해당 없음' 인지 보세요)"

    vals = re.findall(r"0x([0-9a-fA-F]{8})", out)
    if len(vals) < 2:
        return True, "확인 못 함 — 넘어갑니다 (전원 설정에서 직접 '해당 없음' 인지 보세요)"

    ac, dc = int(vals[-2], 16), int(vals[-1], 16)
    if ac != 0:
        return False, (f"전원 꽂았을 때 {ac // 60}분 뒤 잠듭니다 — 검은 창에 이 한 줄: "
                       "powercfg /change standby-timeout-ac 0")
    if dc != 0:
        return True, (f"정상 (전원 꽂은 동안). 노트북이라 배터리로 쓰면 {dc // 60}분 뒤 잠깁니다 — "
                      "그때도 안 자게 하려면: powercfg /change standby-timeout-dc 0")
    return True, "정상 — 절전 '해당 없음'"


def module_4():
    srv = ROOT / "slack-server"

    # ── 선행 조건 ────────────────────────────────────────────
    # 슬랙이 아무리 잘 붙어도 직원 파일이 없으면 아무도 대답하지 않는다.
    # 예전에는 이걸 안 봐서, 직원 0명인데 모듈 4가 통과하고 나중에 터졌다.
    agents = agent_files()
    checks = [("직원이 5명 이상 있다 (모듈 1 완료)", len(agents) >= 5,
               f"{len(agents)}명" if agents else "0명 — 모듈 1을 먼저 하세요")]

    # `.md.txt` 로 잘못 저장된 파일 잡기. 탐색기가 확장자를 숨기면 눈으로는 구별이 안 된다.
    agents_dir = ROOT / ".claude" / "agents"
    mistyped = [p.name for p in agents_dir.glob("*.md.*")
                if not p.name.startswith("_")] if agents_dir.is_dir() else []
    checks.append(("직원 파일 확장자가 .md 다", not mistyped,
                   "정상" if not mistyped
                   else "이름 끝을 .md 로 고치세요: " + ", ".join(mistyped)))

    checks.append(("slack-server 폴더가 있다", srv.is_dir(), str(srv.relative_to(ROOT))))
    checks.append(("server.py 가 있다", (srv / "server.py").is_file(), "server.py"))

    env = srv / ".env"
    checks.append((".env 파일을 만들었다", env.is_file(),
                   "있음" if env.is_file() else ".env.example 을 복사해서 .env 로 만드세요"))

    # `.env.txt` 로 저장된 경우. `.env` 가 없을 때만 알려주면 된다.
    if not env.is_file():
        stray = [p.name for p in srv.glob(".env.*") if p.name != ".env.example"]
        if stray:
            checks.append((".env 이름이 정확하다", False,
                           "이름 끝의 확장자를 지우세요: " + ", ".join(stray)))

    # 🔒 값은 절대 읽지 않는다. 키 이름이 있는지만 본다.
    # utf-8-sig 로 읽는 이유: 메모장·파워셸로 저장한 .env 는 맨 앞에 안 보이는 표식(BOM)이
    # 붙어서, 그냥 utf-8 로 읽으면 첫 줄 키 이름이 깨진 채로 잡힌다.
    keys = set()
    if env.is_file():
        for line in env.read_text(encoding="utf-8-sig", errors="ignore").splitlines():
            k = line.split("=", 1)[0].strip()
            if k and not k.startswith("#"):
                keys.add(k.upper())
    need = {"SLACK_BOT_TOKEN", "SLACK_APP_TOKEN"}
    checks.append(("슬랙 열쇠 2개를 넣었다", need.issubset(keys),
                   "정상" if need.issubset(keys) else "빠진 항목: " + ", ".join(sorted(need - keys))))

    # 🔒 값의 "모양"만 본다. 값 자체는 화면에 절대 찍지 않는다.
    #    xoxb/xapp 자리 바꿔 넣기·따옴표·앞뒤 공백이 강의장 실패의 대부분이다.
    if env.is_file():
        vals = {}
        for line in env.read_text(encoding="utf-8-sig", errors="ignore").splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                vals[k.strip().upper()] = v

        shape = []
        for key, head in (("SLACK_BOT_TOKEN", "xoxb-"), ("SLACK_APP_TOKEN", "xapp-")):
            raw = vals.get(key)
            if raw is None or not raw.strip():
                continue
            v = raw.strip()
            if v[:1] in "\"'" or v[-1:] in "\"'":
                shape.append(f"{key}: 따옴표를 지우세요")
            elif raw != raw.rstrip() or raw[:1] == " ":
                shape.append(f"{key}: 앞뒤 공백을 지우세요")
            elif not v.startswith(head):
                other = "xapp-" if head == "xoxb-" else "xoxb-"
                hint = f"{other} 을 여기 넣으신 것 같습니다" if v.startswith(other) else f"{head} 로 시작해야 합니다"
                shape.append(f"{key}: {hint}")
        checks.append(("열쇠 모양이 맞다 (xoxb / xapp)", not shape,
                       "정상" if not shape else " / ".join(shape)))

        # 🔒 내 멤버 ID(OWNER_USER_ID). 이게 있어야 직원이 "나"를 알아보고 실행한다.
        #    값은 찍지 않고 모양만 본다 — 슬랙 사용자 ID 는 U(또는 W) 로 시작한다.
        raw = vals.get("OWNER_USER_ID", "")
        v = raw.strip()
        if not v:
            owner_msg = "비어 있음 — 슬랙 앱 → 내 프로필 사진 → 프로필 → ⋯ 더보기 → 멤버 ID 복사"
        elif v[:1] in "\"'" or v[-1:] in "\"'":
            owner_msg = "따옴표를 지우세요"
        elif raw != raw.rstrip() or raw[:1] == " ":
            owner_msg = "앞뒤 공백을 지우세요"
        elif not v[:1].upper() in ("U", "W") or len(v) < 9 or not v.isalnum():
            owner_msg = "U 로 시작하는 멤버 ID 가 아닙니다 (이메일·이름이 아니라 '멤버 ID 복사' 값)"
        else:
            owner_msg = "정상"
        checks.append(("내 멤버 ID 를 넣었다 (OWNER_USER_ID)", owner_msg == "정상", owner_msg))

        # 메모장으로 저장하면 맨 앞에 안 보이는 표식(BOM)이 붙는다. server.py 는 견디지만
        # 다른 도구로 열면 첫 줄을 못 읽으므로 여기서 미리 알려준다.
        try:
            bom = env.read_bytes().startswith(b"\xef\xbb\xbf")
        except Exception:
            bom = False
        checks.append((".env 가 BOM 없이 저장됐다", not bom,
                       "정상" if not bom else "메모장 말고 VS Code 로 다시 저장하세요"))

    log = srv / "logs" / "server.log"
    started = log.is_file() and "running" in log.read_text(encoding="utf-8", errors="ignore").lower()
    checks.append(("서버가 한 번 이상 정상 기동했다", started,
                   "정상" if started else "slack-server 폴더에서 py -3 -X utf8 server.py (환경점검이 한 번 켜 봅니다)"))

    # 2026-09-16 신설 — PC 가 절전으로 넘어가면 검은 창이 살아 있어도 서버는 멈춘다.
    # 창을 안 닫았는데 슬랙이 조용해지는 사고의 가장 흔한 원인인데, 그동안 점검 어디에도
    # 이 항목이 없어서 아무도 원인을 못 짚었다. 화면 꺼짐(모니터)은 상관없고 절전만 문제다.
    ok_sleep, sleep_msg = check_sleep()
    checks.append(("PC 가 절전으로 안 넘어간다 (자리를 비워도 직원이 대답하는 근거)",
                   ok_sleep, sleep_msg))

    # ── 2026-09-08 추가: 강의장에서 실제로 난 세 가지 ─────────────────
    #   ① 직원이 대표를 남의 이름으로 부름  → facts.md 에 내 이름이 있어야 한다
    #   ② 팀장만 대답                        → personas 표시 이름이 직원 파일과 짝이 맞아야 한다
    #   ③ 이모지·캐릭터가 안 생김            → 아이콘이 슬랙 형식으로 바뀌는지, 인사말에 빈칸이 없는지
    try:
        sys.path.insert(0, str(srv))
        import roster  # slack-server/roster.py (엔진)
    except Exception:
        roster = None
    if roster is not None:
        # 2026-09-14: '이름이 있다' 가 아니라 '이름이 한글로 제대로 읽힌다' 를 본다.
        # 파일이 ANSI 로 저장돼 글자가 깨진 경우, 예전에는 "이름을 적으세요" 라는
        # 엉뚱한 안내가 나갔다. 대표는 분명히 적었는데 계속 ❌ 가 떴다.
        if hasattr(roster, "owner_name_detail"):
            name, src, problem = roster.owner_name_detail(ROOT)
        else:
            name, src = roster.owner_name(ROOT)
            problem = ""
        detail = f"정상 ({src})" if name else (problem or "카드 P2 로 이름을 적으세요")
        if name and problem:
            detail = f"{name} — {problem}"
        checks.append(("대표 이름이 한글로 제대로 읽힌다 (직원이 나를 알아보는 근거)",
                       bool(name) and roster.is_hangul(name), detail))
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location("personas_check", srv / "personas.py")
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            personas = getattr(mod, "PERSONAS", {}) or {}
            perr = ""
        except Exception as e:  # noqa: BLE001
            personas, perr = {}, f"{type(e).__name__}: {str(e)[:60]}"
        checks.append(("personas.py 가 읽힌다", not perr,
                       "정상" if not perr else f"personas.py 문법 오류 — {perr}. git checkout slack-server/personas.py 로 되돌리고 카드 P8 다시"))
        if personas:
            agents_keys = set(roster.load_agents(ROOT))
            orphan = [k for k in personas if k not in agents_keys]
            checks.append(("personas 의 키가 직원 파일과 짝이 맞다", not orphan,
                           "정상" if not orphan
                           else "짝이 없는 키: " + ", ".join(orphan) + " — 키(staff1 같은 영어 이름)는 바꾸지 마세요"))
            names = [str(p.get("display_name", "")).strip() for p in personas.values()]
            dup = sorted({n for n in names if names.count(n) > 1})
            default_names = [n for n in names if re.fullmatch(r"직원\d+", n)]
            checks.append(("표시 이름이 서로 다르고 '직원1' 기본값이 아니다", not dup and not default_names,
                           "정상" if not dup and not default_names
                           else ("겹침: " + ", ".join(dup) + " / " if dup else "") +
                                ("아직 기본값: " + ", ".join(default_names) + " → 카드 P8" if default_names else "")))
            bad_icon = [k for k, p in personas.items() if not roster.emoji_ok(p.get("icon_emoji"))]
            checks.append(("아이콘이 슬랙에 뜨는 형식이다 (📄 또는 :page_facing_up:)", not bad_icon,
                           "정상" if not bad_icon else "못 알아듣는 아이콘: " + ", ".join(bad_icon)))
            ph = [k for k, p in personas.items()
                  if roster.intro_placeholders(str(p.get("intro", "")) + str(p.get("intro_class", "")))]
            checks.append(("인사말에 [무엇] 빈칸이 없다 (팀 소개 때 캐릭터가 나오는 근거)", not ph,
                           "정상" if not ph else "빈칸 남음: " + ", ".join(ph) + " → 카드 P8 (인사말까지 채웁니다)"))
    return checks


def module_6():
    out = []
    for n in range(6):
        got = MODULES[n]()
        passed = sum(1 for _, ok, _ in got if ok)
        out.append((f"모듈 {n}", passed == len(got), f"{passed}/{len(got)} 통과"))
    return out


def module_35():
    """부록 A — 내 양식(MyData, 비식별 사본)이 실제로 스킬에 반영됐는지.

    2026-09-14 신설. 그전에는 점검 어디에도 MyData 가 없어서, P17·P18 을 건너뛰거나
    에이전트가 '요약만 하고 스킬을 안 고친' 경우를 아무도 못 잡았다.
    2026-10-28 직장인판: 폴더를 Report(보고서)·Minutes(회의록)·Track(직무 문서)로 바꿈.
    """
    import os
    checks = []
    mydata = Path(os.environ.get("WD_MYDATA", r"C:\AgentOffice\MyData"))
    checks.append(("내 양식 폴더(MyData)가 있다", mydata.is_dir(), str(mydata)))

    counts = {}
    for sub in ("Report", "Minutes", "Track"):
        d = mydata / sub
        counts[sub] = len([f for f in d.glob("*") if f.is_file()]) if d.is_dir() else 0
    filled = [k for k in ("Report", "Minutes") if counts[k] > 0]
    optional = not filled  # 부록 A 는 선택 — 아무것도 안 넣었으면 양식 관련 항목은 정상으로 넘긴다
    checks.append(("내 양식을 넣었다 (보고서·회의록 중 1종 이상, 비식별 사본)",
                   True if optional else len(filled) >= 1,
                   "넣은 것 없음 — 부록 A 는 선택이라 정상입니다" if optional else
                   " · ".join(f"{k} {v}개" for k, v in counts.items())))

    skills = ROOT / ".claude" / "skills"
    sk = [d for d in skills.glob("*") if d.is_dir() and not d.name.startswith("_")] if skills.is_dir() else []
    checks.append(("스킬이 1개 이상 있다", len(sk) >= 1,
                   ", ".join(d.name for d in sk) if sk else "카드 P5 부터 하세요"))

    # 스킬이 MyData 를 1순위로 적어 두었는가 (P18 이 실제로 반영됐다는 근거)
    texts = {}
    for d in sk:
        t = ""
        for f in d.rglob("*.md"):
            try:
                t += f.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                pass
        texts[d.name] = t
    linked = [n for n, t in texts.items() if "MyData" in t]
    checks.append(("스킬이 내 양식 폴더를 참고하라고 적고 있다 (카드 A-4)",
                   True if optional else bool(linked),
                   "양식을 넣지 않아 건너뜁니다" if optional else
                   (", ".join(linked) if linked else "카드 A-4 를 붙여넣어 스킬을 내 양식으로 덮어쓰세요")))

    # 견본 문구가 남아 있으면 내 양식이 아니라 카드 예시로 만든 것이다.
    # 직장인판 카드 예시(홍길동·영업지원팀)와 트랙 카드에 남은 원판 예시를 함께 본다.
    # 내 팀 이름이 마침 예시와 같으면 그 낱말은 빼고 본다.
    mine_team = team_name() or ""
    SAMPLES = tuple(x for x in ("홍길동",)
                    if x != mine_team)
    dirty = sorted({n for n, t in texts.items() if any(x in t for x in SAMPLES)})
    checks.append(("스킬에 견본 문구가 안 남아 있다 (내 것으로 덮어썼다는 근거)",
                   not dirty,
                   "정상" if not dirty else
                   "견본이 남은 스킬: " + ", ".join(dirty) + " — 카드 A-4 를 다시 돌리세요"))

    # 실습자료(가상 회사)로 만든 결과물에는 가상 이름이 들어가는 게 정상이다.
    # 여기서는 카드 예시의 내 이름(홍길동)이 결과물에 그대로 찍혔는지만 본다 — P1 을 예시 그대로 둔 증상.
    bad = [f.name for f in result_files() if "홍길동" in text_of(f)]
    checks.append(("결과물에 예시 이름(홍길동)이 안 들어갔다", not bad,
                   "정상" if not bad else
                   "예시 이름이 들어간 파일: " + ", ".join(bad[:3]) + " — 카드 P2 의 내 이름을 바꾸세요"))

    # ── 2026-09-16 신설 — 이미 쓰던 내 스킬(MyData\Skill) ────────────────
    # 클로드를 써 온 수강생은 이미 자기 스킬이 있다. 그게 정본이고, 수업에서 만든
    # 뼈대 스킬이 그 위를 덮으면 안 된다. 카드 A-3 을 A-4 보다 먼저 돌려야 하는 이유.
    box = mydata / "Skill"
    mine = [f for f in box.glob("*.md")] if box.is_dir() else []
    if not mine:
        checks.append(("쓰던 내 스킬 가져오기 (MyData\\Skill)", True,
                       "넣은 것 없음 — 클로드가 처음이면 정상입니다"))
    else:
        marker = ("MyData\\Skill", "MyData/Skill")
        landed = [n for n, x in texts.items() if any(m in x for m in marker)]
        checks.append((f"쓰던 내 스킬 {len(mine)}개가 실제로 설치됐다 (카드 A-3)",
                       bool(landed),
                       ", ".join(landed) if landed else
                       "설치 안 됨 — 카드 A-3 을 카드 A-4 '보다 먼저' 돌리세요"))

    # 같은 일을 하는 스킬이 둘 이상 살아 있으면 클로드가 그때그때 다른 걸 고른다.
    # ("엉뚱한 스킬이 뜬다" 는 증상의 정체) 밀려난 것은 지우지 말고 _보관 으로 옮긴다.
    # 직장인판: 공통 스킬(회의록·주간보고·집계) + 직무 트랙 스킬.
    # 주간보고 스킬 본문에는 "회의록" 이 재료로 나오므로, 본문이 아니라 폴더 이름과 name 만 본다.
    JOBS = dict(COMMON_SKILLS, **TRACK_SKILLS)
    clash = []
    for job, keys in JOBS.items():
        hit = skill_job_dirs(keys)
        if len(hit) > 1:
            clash.append(f"{job}: " + " / ".join(hit))
    checks.append(("같은 일을 하는 스킬이 둘 이상 살아 있지 않다", not clash,
                   "정상" if not clash else
                   "겹칩니다 — " + " · ".join(clash) +
                   " → 쓰시던 것만 남기고 나머지는 .claude/skills/_보관/ 으로 옮기세요"))
    return checks


# ── 직장인판 8시간: 점검 번호 = 모듈 번호 ─────────────────────────

def _facts():
    return ROOT / "workspace" / "memory" / "facts.md"


def m2():
    """모듈 2 — 규칙표(facts.md)"""
    f = _facts()
    checks = [("규칙표(workspace/memory/facts.md)가 있다", f.is_file(),
               "있음" if f.is_file() else "카드 P2 를 붙여넣으세요")]
    size = f.stat().st_size if f.is_file() else 0
    checks.append(("규칙표에 내용이 채워져 있다", size > 200, f"{size} 바이트 (200 이상 필요)"))
    checks += [c for c in module_3() if "UTF-8" in c[0]]
    try:
        sys.path.insert(0, str(ROOT / "slack-server"))
        import roster
        name, src, problem = roster.owner_name_detail(ROOT)
        ok = bool(name) and roster.is_hangul(name)
        checks.append(("내 이름이 한글로 제대로 읽힌다 (## 대표 (나) 아래 - 이름:)", ok,
                       f"{name} ({src})" if ok else (problem or "카드 P2 의 내 이름 칸을 채우세요")))
    except Exception as e:  # noqa: BLE001
        checks.append(("내 이름이 읽힌다", False, f"이름을 읽지 못했습니다 — {type(e).__name__}"))
    checks += [c for c in module_1() if "색" in c[0]]
    # 카드 P2-c — 복사본만 정리하고 원본은 그대로 둔다
    tidy = ROOT / "workspace" / "결과물" / "폴더정리"
    subs = [p for p in tidy.iterdir() if p.is_dir()] if tidy.is_dir() else []
    dup = tidy / "_중복의심"
    moved = [p for p in dup.rglob("*") if p.is_file()] if dup.is_dir() else []
    src = ROOT / "실습자료" / "어지러운_폴더"
    kept = len([p for p in src.iterdir() if p.is_file()]) if src.is_dir() else 0
    checks.append(("어지러운 폴더를 복사본으로 정리했다 (카드 P2-c)", len(subs) >= 3,
                   f"하위 폴더 {len(subs)}개" if subs else "workspace/결과물/폴더정리 가 없습니다 — 카드 P2-c"))
    checks.append(("같은 파일을 지우지 않고 _중복의심 에 모았다", len(moved) >= 1,
                   f"{len(moved)}개" if moved else "workspace/결과물/폴더정리/_중복의심 이 비어 있습니다 — 카드 P2-c"))
    checks.append(("원본 폴더는 그대로다 (실습자료/어지러운_폴더 24개)", kept == 24,
                   f"{kept}개" if kept != 24 else "정상"))
    return checks


def m3():
    """모듈 3 — 회의록"""
    mn = minutes()
    checks = [("회의록(.md)이 나왔다 — 이름에 '회의록'", len(mn) >= 1,
               mn[0].name if mn else "카드 P3 — 저장 이름에 '회의록' 이 들어가야 합니다")]
    checks.append(("할 일이 할일_목록.md 에 쌓였다", todo_list() is not None,
                   "정상" if todo_list() else "카드 P3 의 '할일_목록.md 에도 쌓아 줘' 줄을 확인하세요"))
    return checks


def m4():
    """모듈 4 — 집계"""
    agg = [p for p in result_files() if "집계" in p.name]
    kinds = {p.suffix.lower() for p in agg}
    checks = [("집계 엑셀(.xlsx)이 나왔다", ".xlsx" in kinds, "정상" if ".xlsx" in kinds else "카드 P4 — 이름에 '집계'")]
    checks.append(("차트(.png)가 나왔다", ".png" in kinds, "정상" if ".png" in kinds else "카드 P4 의 차트 줄"))
    checks.append(("요약(.md)이 나왔다", ".md" in kinds, "정상" if ".md" in kinds else "카드 P4 의 요약 줄"))
    return checks


def m5():
    """모듈 5 — 스킬 (회의록·주간보고) + 주간보고 한 장"""
    files = skill_files()
    checks = [("스킬이 2개 이상 있다 (meeting-notes · weekly-report)", len(files) >= 2, f"{len(files)}개")]
    lack = [job for job in ("회의록", "주간보고") if not skill_job_dirs(COMMON_SKILLS[job])]
    checks.append(("회의록 스킬과 주간보고 스킬이 둘 다 있다", not lack,
                   "정상" if not lack else "없는 스킬: " + ", ".join(lack) + " — 카드 P5 · P5-d"))
    bad, nonascii = [], []
    for f in files:
        fm = front_matter(f)
        miss = [k for k in ("name", "description") if k not in fm]
        if miss:
            bad.append(f"{f.parent.name}({','.join(miss)} 없음)")
        elif not re.fullmatch(r"[a-z0-9][a-z0-9-]*", fm["name"].strip().strip("'\"")):
            nonascii.append(f"{f.parent.name}(name: {fm['name']})")
    checks.append(("모든 SKILL.md 맨 위에 name·description 이 있다", not bad, "정상" if not bad else " / ".join(bad)))
    checks.append(("스킬 name 이 영어 소문자·하이픈이다 (/ 메뉴로 부르려면)", not nonascii,
                   "정상" if not nonascii else "고칠 것: " + ", ".join(nonascii) + " — \"name 을 영어 소문자로 바꿔줘\""))
    checks += [c for c in module_2() if c[0].startswith("주간보고")]
    return checks


def m6():
    """모듈 6 — 직원 5명 · 스킬 연결 · 릴레이"""
    checks = [c for c in module_1() if "색" not in c[0]]
    checks += [c for c in module_2() if c[0].startswith("직원 파일에서")]
    checks += [c for c in module_3() if c[0].startswith(("직원끼리", "회의록이 2개", "쪽지를 받은"))]
    return checks


def m7():
    """모듈 7 — 직무 트랙 (6번째 직원 + 트랙 스킬)"""
    agents = agent_files()
    six = ROOT / ".claude" / "agents" / "staff6.md"
    checks = [("직원이 6명 이상 있다 (staff6)", six.is_file() and len(agents) >= 6,
               f"{len(agents)}명" if six.is_file() else "카드 P7 — staff6.md 가 없습니다")]
    track = [n for keys in TRACK_SKILLS.values() for n in skill_job_dirs(keys)]
    other = []
    d = ROOT / ".claude" / "skills"
    if d.is_dir():
        common = {n for keys in COMMON_SKILLS.values() for n in skill_job_dirs(keys)}
        other = [x.name for x in d.glob("*") if x.is_dir() and not x.name.startswith("_")
                 and x.name not in common and x.name not in track and x.name != "예시-스킬"]
    got = track + other
    checks.append(("내 트랙 스킬이 1개 이상 있다", bool(got),
                   ", ".join(got) if got else "직무트랙 카드 하나 또는 카드 P7-b 로 스킬을 만드세요"))
    linked = six.is_file() and ("skills/" in text_of(six) or "스킬" in text_of(six))
    checks.append(("6번째 직원 파일이 트랙 스킬을 쓴다고 적고 있다", linked,
                   "정상" if linked else "카드 P7 의 3번 줄 — staff6.md 본문에 스킬 연결 한 줄"))
    return checks


def m9():
    out = []
    for n in (0, 2, 3, 4, 5, 6, 7, 8):
        got = MODULES[n]()
        passed = sum(1 for _, ok, _ in got if ok)
        out.append((f"모듈 {n} — {TITLES[n]}", passed == len(got), f"{passed}/{len(got)} 통과 — py 점검.py {n} 로 자세히"))
    return out


MODULES = {0: module_0, 2: m2, 3: m3, 4: m4, 5: m5, 6: m6, 7: m7, 8: module_4, 9: m9,
           10: module_35}

TITLES = {0: "출발선 맞추기", 2: "규칙표", 3: "회의록", 4: "집계", 5: "스킬",
          6: "직원 팀 · 릴레이", 7: "직무 트랙", 8: "슬랙에서 부르기", 9: "전체 점검",
          10: "(부록) 내 양식"}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in [str(i) for i in MODULES]:
        print("사용법: py 점검.py <모듈 번호 0, 2~9 · 부록 10(내 양식) · 11(사무실)>")
        print("  예)  py 점검.py 3")
        return 2

    n = int(sys.argv[1])
    print()
    print(f"  모듈 {n} — {TITLES[n]}")
    print("  " + "─" * 46)

    results = MODULES[n]()
    for label, ok, detail in results:
        print(f"  {OK if ok else NO}  {label}")
        if not ok or n == 0:
            print(f"        └ {detail}")

    passed = sum(1 for _, ok, _ in results if ok)
    total = len(results)
    print("  " + "─" * 46)
    if passed == total:
        print(f"  🎉 {total}개 전부 통과! 다음 모듈로 넘어가세요.")
    else:
        print(f"  {passed}/{total} 통과 — ❌ 표시된 것만 고치면 됩니다.")
    print()
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
