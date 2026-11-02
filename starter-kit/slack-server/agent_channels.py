"""슬랙 채널 이름 → 어느 직원을 부를지 정하는 표.

슬랙에 `#제안서` 채널을 만들고 거기서 말을 걸면 staff1 이 대답하게 하려면
아래 표에 `"제안서": "staff1"` 을 넣으면 됩니다.

DM(1:1 대화)으로 말을 걸면 DEFAULT_AGENT 가 받습니다.
문장 맨 앞에 `@staff2` 처럼 쓰면 그 직원이 받습니다.
"""

CHANNELS = {
    # staff1
    "staff1": "staff1",
    "직원1": "staff1",

    # staff2
    "staff2": "staff2",
    "직원2": "staff2",

    # staff3
    "staff3": "staff3",
    "직원3": "staff3",

    # staff4
    "staff4": "staff4",
    "직원4": "staff4",

    # staff5
    "staff5": "staff5",
    "직원5": "staff5",

    # 🎨 내 채널 이름을 여기 추가하세요. 예)
    # "주간보고": "staff1",
    # "회의록":   "staff2",
    # "집계":     "staff3",
}

# 어느 채널인지 모를 때 받아줄 직원
DEFAULT_AGENT = "staff1"


def resolve_agent(channel_name: str, text: str = "") -> str:
    """채널 이름과 문장을 보고 담당 직원을 정한다."""
    if channel_name:
        low = channel_name.lower().lstrip("#")
        if low in CHANNELS:
            return CHANNELS[low]

    # "@staff2 뭐 해줘" 처럼 이름을 찍어 부른 경우
    stripped = text.strip()
    for prefix in ("@", "/"):
        if stripped.startswith(prefix):
            first = stripped[1:].split(None, 1)[0].lower()
            if first in CHANNELS:
                return CHANNELS[first]

    return DEFAULT_AGENT
