<#
  env_check.ps1 — 「에이전트팀 만들기 과정」 출발선 자동 점검 + 자동 설치

  무엇을 하나 (2026-09-07 개정 — "묻지 않고 설치한다")
    0) 파워셸 스크립트 실행을 허용한다 → 어느 창에서든 claude 한 단어로 부를 수 있다
    1) Node.js · Git · Claude Code 가 없으면 winget 으로 그 자리에서 설치한다 (묻지 않음)
    2) Python 은 있어도 무조건 3.14 를 설치한다. 낮은 버전이 깔려 있어도 그 자리에서 올라간다.
       py 실행기의 기본을 3.14 로 고정한다 (PY_PYTHON / PY_PYTHON3)
    3) 파이썬 꾸러미(slack-bolt·slack-sdk·aiohttp·python-dotenv·claude-agent-sdk·playwright)를
       3.14 에 설치하고, 실제로 불러와지는지 확인한다
    4) Claude Code 로그인 창을 띄운다 (로그인은 본인이 직접)
    5) 슬랙 열쇠 3개(xoxb- · xapp- · 멤버 ID)를 붙여넣게 하고 .env 에 BOM 없이 저장한 뒤
       실제로 슬랙에 통하는지 확인하고, 서버를 한 번 켜서 "준비 완료" 까지 본다
    6) 결과 체크리스트를 검은 창과 HTML(환경점검_결과.html)로 보여준다

  실행
    환경점검.bat 더블클릭  ← 이게 전부입니다
    (직접)  powershell -NoProfile -ExecutionPolicy Bypass -File env_check.ps1

  옵션 (강사·테스트용)
    -SkipInstall      자동 설치 안 함
    -SkipLogin        로그인 창 안 띄움
    -SkipSlack        슬랙 열쇠 입력·확인 건너뜀
    -NoServerTest     서버 첫 기동 시험 안 함
    -OptionalLogins   네이버 블로그 로그인 창도 띄움 (기본은 안 띄움 — 수업 중 카드로 진행)
    -NoBrowser        HTML·안내 페이지 안 열음
    -NoPause          끝나고 Enter 대기 안 함
    -Yes              (호환용) 남아 있는 Enter 대기를 건너뜀
    -PretendMissing   테스트용 — 특정 항목을 "없는 것"으로 가정
                      예) -PretendMissing node,git,claude-login
    -SlackOnly        슬랙 열쇠 넣기·연결 시험·서버 기동·자동시작만 (슬랙열쇠_넣기.bat)
    -MailOnly         메일 연결만 (메일_연결.bat · 부록 B-2)
    -Mail             전체 점검 중에 메일 연결도 묻기 (기본은 묻지 않음)

  2026-11-02: 한 줄 설치는 -SkipSlack 으로 부른다 — 설치 중에는 아무것도 묻지 않고,
              슬랙 열쇠는 「슬랙 ①②」를 마친 뒤 슬랙열쇠_넣기.bat 으로 따로 넣는다.

  🔒 이 파일은 .env 의 열쇠 값을 화면에 찍지 않습니다. 붙여넣을 때도 별표(*)로 가립니다.
  🔒 로그인은 항상 사람이 직접 합니다. 비밀번호를 대신 입력하지 않습니다.
#>
[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [switch]$SkipLogin,
    [switch]$SkipSlack,
    [switch]$NoServerTest,
    [switch]$OptionalLogins,
    [switch]$NoBrowser,
    [switch]$NoPause,
    [switch]$Yes,
    [switch]$SlackOnly,
    [switch]$MailOnly,
    [switch]$Mail,
    [string[]]$PretendMissing = @()
)

# ── 0. 콘솔 준비 ──────────────────────────────────────────────
$ErrorActionPreference = 'Continue'
# -File 로 넘어오면 "node,git" 이 한 덩어리로 들어오므로 콤마를 잘라 준다
$PretendMissing = @($PretendMissing | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
try { $null = & "$env:ComSpec" /c chcp 65001 } catch {}
try {
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    [Console]::InputEncoding  = [Text.Encoding]::UTF8
} catch {}
try { $Host.UI.RawUI.WindowTitle = '에이전트팀 만들기 — 환경 점검' } catch {}

$KIT    = Split-Path -Parent $MyInvocation.MyCommand.Path
$COURSE = Split-Path -Parent $KIT
$USERHOME = $env:USERPROFILE
$REPORT = Join-Path $KIT '환경점검_결과.html'
$STARTED = Get-Date

$OKM = [char]0x2705   # ✅
$NOM = [char]0x274C   # ❌
$WRN = [char]0x26A0   # ⚠

# ── 1. 도우미 ────────────────────────────────────────────────
function Write-Step([string]$t) { Write-Host ''; Write-Host "  ▶ $t" -ForegroundColor Magenta }
function Write-Info([string]$t) { Write-Host "     $t" -ForegroundColor DarkGray }
function Write-Warn([string]$t) { Write-Host "     $WRN $t" -ForegroundColor Yellow }

function Ask-YesNo([string]$q, [bool]$default = $true) {
    if ($Yes) { return $true }
    $hint = '[y/N]'; if ($default) { $hint = '[Y/n]' }
    $a = Read-Host "  ? $q $hint"
    if ([string]::IsNullOrWhiteSpace($a)) { return $default }
    return $a.Trim().ToLower().StartsWith('y')
}

function Wait-Enter([string]$msg) {
    if ($Yes) { return }
    $null = Read-Host "  ⏎ $msg (Enter)"
}

function Invoke-Cmd {
    # cmd.exe 로 한 줄을 실행해 출력·종료코드를 돌려준다. 멈추면 시간 초과로 끊는다.
    param([string]$Line, [int]$TimeoutSec = 30)
    $tmp = [IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $env:ComSpec -ArgumentList "/d /s /c `"$Line 2>&1`"" `
                -RedirectStandardOutput $tmp -NoNewWindow -PassThru
        # PowerShell 5.1 함정: Handle 을 먼저 읽어두지 않으면 ExitCode 가 $null 로 나온다.
        $null = $p.Handle
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            return @{ ok = $false; code = -2; out = '(시간 초과)' }
        }
        $out = ''
        try { $out = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8).Trim() } catch {}
        $code = $p.ExitCode
        if ($code -eq $null) {
            # 그래도 비면 출력으로 판정 (cmd 의 "인식되지 않습니다" 메시지가 없으면 성공으로 본다)
            $code = 1
            if ($out -and $out -notmatch 'is not recognized|인식되지 않|not found|찾을 수 없') { $code = 0 }
        }
        return @{ ok = ($code -eq 0); code = $code; out = $out }
    } catch {
        return @{ ok = $false; code = -1; out = "$_" }
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

function Run-Live {
    # 설치처럼 오래 걸리는 명령은 화면에 그대로 흘려보낸다 (진행 상황이 보여야 기다린다).
    param([string]$Line, [int]$TimeoutSec = 900)
    try {
        $p = Start-Process -FilePath $env:ComSpec -ArgumentList "/d /s /c `"$Line`"" -NoNewWindow -PassThru
        $null = $p.Handle
        if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill() } catch {}; return -2 }
        return $p.ExitCode
    } catch { Write-Warn "실행 실패: $_"; return -1 }
}

function First-Line([string]$s) { if (-not $s) { return '' }; return ($s -split "`r?`n")[0].Trim() }

function Get-Ver([string]$text) {
    if ($text -match '(\d+)\.(\d+)(?:\.(\d+))?') {
        $patch = 0; if ($Matches[3]) { $patch = $Matches[3] }
        return [version]('{0}.{1}.{2}' -f $Matches[1], $Matches[2], $patch)
    }
    return $null
}

function Has-Cmd([string]$name) {
    $c = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    return $null
}

function Refresh-Path {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $extra = @("$env:USERPROFILE\.local\bin", "$env:APPDATA\npm", "$env:LOCALAPPDATA\Programs\Python\Launcher")
    $env:Path = (@($m, $u) + $extra) -join ';'
}

function Open-Url([string]$url) {
    if ($NoBrowser) { Write-Info "(브라우저 생략) $url"; return }
    try { Start-Process $url } catch { Write-Warn "열 수 없음: $url" }
}

function Open-NewWindow([string]$title, [string]$cmdline, [string]$workdir = $KIT) {
    # 사람이 직접 조작해야 하는 명령(로그인 등)은 별도 검은 창에 띄운다.
    if ($SkipLogin) { Write-Info "(로그인 창 생략) $cmdline"; return }
    try {
        Start-Process -FilePath $env:ComSpec -ArgumentList "/k title $title && $cmdline" -WorkingDirectory $workdir
    } catch { Write-Warn "창을 열 수 없음: $_" }
}

# ── 2. 결과 저장소 ───────────────────────────────────────────
$script:Results = New-Object System.Collections.ArrayList

function Set-Result {
    param([string]$Id, [string]$Name, [string]$Group, [bool]$Ok, [string]$Detail,
          [string]$Fix = '', [string]$Url = '')
    if ($PretendMissing -contains $Id) { $Ok = $false; $Detail = "(테스트) 없는 것으로 가정 — $Detail" }
    $row = [pscustomobject]@{ Id=$Id; Name=$Name; Group=$Group; Ok=$Ok; Detail=$Detail; Fix=$Fix; Url=$Url }
    $i = -1
    for ($k = 0; $k -lt $script:Results.Count; $k++) { if ($script:Results[$k].Id -eq $Id) { $i = $k } }
    if ($i -ge 0) { $script:Results[$i] = $row } else { $null = $script:Results.Add($row) }
    # 선택 항목은 없어도 수업이 되므로 빨간 ❌ 대신 노란 ⚠ 로 보인다 (2026-11-02)
    $mark = $NOM; $color = 'Red'
    if ($Group -eq '선택') { $mark = $WRN; $color = 'Yellow' }
    if ($Ok) { $mark = $OKM; $color = 'Green' }
    Write-Host ("  {0}  {1}" -f $mark, $Name) -ForegroundColor $color
    if ($Detail) { Write-Host ("        └ {0}" -f $Detail) -ForegroundColor DarkGray }
    return $Ok
}
function Get-Result([string]$Id) { foreach ($r in $script:Results) { if ($r.Id -eq $Id) { return $r } }; return $null }
function Is-Ok([string]$Id) { $r = Get-Result $Id; return ($r -and $r.Ok) }

# ── 3. 개별 검사 ─────────────────────────────────────────────
function Check-Internet {
    foreach ($h in 'claude.ai', 'nodejs.org', 'www.google.com') {
        try {
            $c = New-Object Net.Sockets.TcpClient
            $ar = $c.BeginConnect($h, 443, $null, $null)
            $done = $ar.AsyncWaitHandle.WaitOne(3000)
            if ($done -and $c.Connected) { $c.Close(); return (Set-Result 'internet' '인터넷 연결' '기본' $true "$h 연결됨") }
            $c.Close()
        } catch {}
    }
    Set-Result 'internet' '인터넷 연결' '기본' $false 'Wi-Fi/랜선을 확인하세요 — 설치와 로그인 모두 인터넷이 필요합니다'
}

function Check-Disk {
    try {
        $drive = Get-PSDrive -Name $KIT.Substring(0, 1) -ErrorAction Stop
        $gb = [math]::Round($drive.Free / 1GB, 1)
        Set-Result 'disk' '디스크 여유 3GB 이상' '기본' ($gb -ge 3) "$($drive.Name): 드라이브 여유 ${gb}GB (설치 1.6GB + 스타터킷 0.7GB)"
    } catch { Set-Result 'disk' '디스크 여유 3GB 이상' '기본' $true '확인 불가 — 건너뜁니다' }
}

function Check-Node {
    $r = Invoke-Cmd 'node -v'
    if (-not $r.ok -or -not $r.out) {
        return (Set-Result 'node' 'Node.js 22 이상' '필수' $false '설치 안 됨' 'nodejs.org 에서 LTS 설치' 'https://nodejs.org/ko/download')
    }
    $v = Get-Ver $r.out
    $ok = ($v -ne $null -and $v.Major -ge 22)
    $d = (First-Line $r.out); if (-not $ok) { $d += ' → 22 이상 필요. nodejs.org 에서 LTS 를 덮어 설치' }
    Set-Result 'node' 'Node.js 22 이상' '필수' $ok $d 'nodejs.org 에서 LTS 설치' 'https://nodejs.org/ko/download'
}

function Check-Npm {
    $r = Invoke-Cmd 'npm -v'
    $ok = ($r.ok -and $r.out -and (Get-Ver $r.out) -ne $null)
    $d = 'Node.js 를 깔면 같이 들어옵니다'; if ($ok) { $d = 'npm ' + (First-Line $r.out) }
    Set-Result 'npm' 'npm (Claude Code 설치용)' '필수' $ok $d 'Node.js 다시 설치' 'https://nodejs.org/ko/download'
}

function Check-Python {
    # 수업 표준은 Python 3.14 (py -3.14). 다른 버전이 같이 깔려 있어도 상관없다 — 우리는 3.14 만 쓴다.
    $r = Invoke-Cmd 'py -3.14 -V'
    if ($r.ok -and $r.out -match 'Python 3\.14') {
        $script:PY = 'py -3.14'
        return (Set-Result 'python' 'Python 3.14 (수업 표준)' '필수' $true "$(First-Line $r.out) (py -3.14)")
    }
    $exe = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python314\python.exe'
    if (Test-Path $exe) {
        $r = Invoke-Cmd "`"$exe`" -V"
        if ($r.ok -and $r.out -match 'Python 3\.14') {
            $script:PY = "`"$exe`""
            return (Set-Result 'python' 'Python 3.14 (수업 표준)' '필수' $true "$(First-Line $r.out) — py 실행기 없이 직접 경로로 씁니다")
        }
    }
    $script:PY = $null
    $d = '설치 안 됨'
    foreach ($probe in 'py -3 -V', 'python -V') {
        $r2 = Invoke-Cmd $probe
        if ($r2.ok -and $r2.out -match 'Python') { $d = "$(First-Line $r2.out) 만 있음 → 3.14 를 새로 깝니다"; break }
    }
    Set-Result 'python' 'Python 3.14 (수업 표준)' '필수' $false $d 'winget install --exact --id Python.Python.3.14' 'https://www.python.org/downloads/windows/'
}

function Check-Pip {
    if (-not $script:PY) { return (Set-Result 'pip' 'pip (파이썬 꾸러미 설치 도구)' '필수' $false 'Python 먼저') }
    $r = Invoke-Cmd "$($script:PY) -m pip --version"
    $ok = ($r.ok -and $r.out -match 'pip')
    $d = 'pip 이 없습니다 → Python 재설치'; if ($ok) { $d = First-Line $r.out }
    Set-Result 'pip' 'pip (파이썬 꾸러미 설치 도구)' '필수' $ok $d
}

function Check-Git {
    $r = Invoke-Cmd 'git --version'
    $ok = ($r.ok -and $r.out -match 'git version')
    $d = '설치 안 됨'; if ($ok) { $d = First-Line $r.out }
    Set-Result 'git' 'Git' '필수' $ok $d 'git-scm.com 에서 설치 (기본값으로 Next 만)' 'https://git-scm.com/download/win'
}

function Check-Claude {
    Refresh-Path
    $exe = Has-Cmd 'claude'
    if (-not $exe) { $exe = Has-Cmd 'claude.exe' }
    if (-not $exe) { $exe = Has-Cmd 'claude.cmd' }
    if (-not $exe) {
        foreach ($c in @("$env:USERPROFILE\.local\bin\claude.exe", "$env:APPDATA\npm\claude.cmd")) { if (Test-Path $c) { $exe = $c } }
    }
    if ($exe) {
        $r = Invoke-Cmd "`"$exe`" --version" 40
        $d = First-Line $r.out; if (-not $d) { $d = $exe }
        return (Set-Result 'claude' 'Claude Code 설치' '필수' $true $d)
    }
    Set-Result 'claude' 'Claude Code 설치' '필수' $false '설치 안 됨' 'winget install --exact --id Anthropic.ClaudeCode' 'https://code.claude.com/docs/en/setup'
}

function Check-ClaudeVersion {
    # claude.ai 커넥터(구글 캘린더·지메일·드라이브)가 터미널에 도구로 넘어오는 것은 2.1.46 판부터다.
    # 그 전 판은 커넥터를 붙여도 터미널이 모른다 — 강의장 "구글 연결이 안 돼요"의 첫째 원인 (2026-09-08).
    if (-not (Is-Ok 'claude')) { return (Set-Result 'claude-ver' 'Claude Code 최신판 (구글 커넥터 지원)' '필수' $false 'Claude Code 먼저 설치') }
    $r = Invoke-Cmd 'claude --version' 40
    $line = First-Line $r.out
    $ok = $false; $d = "판을 읽지 못함: $line"
    if ($line -match '(\d+)\.(\d+)\.(\d+)') {
        $v = [version]("$($Matches[1]).$($Matches[2]).$($Matches[3])")
        $ok = ($v -ge [version]'2.1.46')
        $d = "v$v"; if (-not $ok) { $d = "v$v — 2.1.46 이상이어야 구글 커넥터가 붙습니다" }
    }
    Set-Result 'claude-ver' 'Claude Code 최신판 (구글 커넥터 지원, 2.1.46 이상)' '필수' $ok $d 'claude update' 'https://code.claude.com/docs/en/setup'
}

function Check-ClaudeLogin([switch]$Quiet) {
    if (-not (Is-Ok 'claude')) {
        if ($Quiet) { return $false }
        return (Set-Result 'claude-login' 'Claude Code 로그인 (claude.ai 유료 계정)' '필수' $false 'Claude Code 먼저 설치' '' 'https://claude.ai/')
    }
    $r = Invoke-Cmd 'claude auth status' 40
    $logged = $false; $d = '로그인 안 됨'
    try {
        $j = $r.out | ConvertFrom-Json
        if ($j.loggedIn -eq $true) {
            $logged = $true
            $d = "로그인됨"
            if ($j.email) { $d += " — $($j.email)" }
            if ($j.subscriptionType) { $d += " ($($j.subscriptionType))" }
        }
    } catch {
        if ($r.out -match '"loggedIn"\s*:\s*true') { $logged = $true; $d = '로그인됨' }
    }
    if ($Quiet) { return $logged }
    Set-Result 'claude-login' 'Claude Code 로그인 (claude.ai 유료 계정)' '필수' $logged $d 'claude auth login' 'https://claude.ai/'
}

function Check-PyPackages {
    $req = @('slack_bolt', 'slack_sdk', 'aiohttp', 'dotenv', 'claude_agent_sdk')
    if (-not (Is-Ok 'python')) {
        Set-Result 'pypkg' '파이썬 꾸러미 5개 (slack-bolt·slack-sdk·aiohttp·python-dotenv·claude-agent-sdk)' '필수' $false 'Python 먼저'
        Set-Result 'playwright' 'playwright 패키지 (블로그·이미지 스킬용)' '선택' $false 'Python 먼저'
        return
    }
    $tmp = Join-Path $env:TEMP 'wd_envcheck_mods.py'
    @'
import importlib.util as u
mods = ["slack_bolt","slack_sdk","aiohttp","dotenv","claude_agent_sdk","playwright"]
print(" ".join(m + "=" + ("O" if u.find_spec(m) else "X") for m in mods))
'@ | Set-Content -Path $tmp -Encoding ASCII
    $r = Invoke-Cmd "$($script:PY) `"$tmp`"" 40
    Remove-Item $tmp -ErrorAction SilentlyContinue
    $missing = @(); $have = @{}
    foreach ($tok in ($r.out -split '\s+')) {
        if ($tok -match '^(\w+)=(O|X)$') { $have[$Matches[1]] = ($Matches[2] -eq 'O') }
    }
    foreach ($m in $req) { if (-not $have[$m]) { $missing += $m } }
    if ($have.Count -eq 0) {
        Set-Result 'pypkg' '파이썬 꾸러미 5개 (slack-bolt·slack-sdk·aiohttp·python-dotenv·claude-agent-sdk)' '필수' $false "확인 실패: $(First-Line $r.out)"
        Set-Result 'playwright' 'playwright 패키지 (블로그·이미지 스킬용)' '선택' $false '확인 실패'
        return
    }
    $d = '5개 모두 설치됨'; if ($missing.Count) { $d = '빠짐: ' + ($missing -join ', ') }
    Set-Result 'pypkg' '파이썬 꾸러미 5개 (slack-bolt·slack-sdk·aiohttp·python-dotenv·claude-agent-sdk)' '필수' ($missing.Count -eq 0) $d "py -3.14 -m pip install -r slack-server\requirements.txt"
    $pd = 'pip install playwright'; if ($have['playwright']) { $pd = '설치됨' }
    Set-Result 'playwright' 'playwright 패키지 (블로그·이미지 스킬용)' '선택' ([bool]$have['playwright']) $pd 'py -3.14 -m pip install playwright'
}

function Check-Folders {
    # 빈 폴더는 ZIP·깃허브에 실리지 않는다. 폴더는 없으면 그냥 만들어 주고, 파일 두 개만 진짜로 본다.
    foreach ($d in @('.claude\agents', '.claude\skills', 'workspace\inbox', 'workspace\memory', 'workspace\결과물')) {
        $dp = Join-Path $KIT $d
        if (-not (Test-Path $dp)) { try { $null = New-Item -ItemType Directory -Path $dp -Force } catch {} }
    }
    $need = @('.claude\agents', '.claude\skills', 'workspace\inbox', 'workspace\memory', 'slack-server\server.py', '점검.py')
    $missing = @($need | Where-Object { -not (Test-Path (Join-Path $KIT $_)) })
    $d = "정상 — $KIT"; if ($missing.Count) { $d = '없음: ' + ($missing -join ', ') + ' — 스타터킷 압축을 다시 푸세요' }
    Set-Result 'folders' '스타터킷 폴더 구조' '필수' ($missing.Count -eq 0) $d
}

function Check-MyData {
    # 표준 설치(C:\AgentOffice\01_KIT\starter-kit)면 두 단계 위가 회사 건물 — 그 안의 MyData\ 를 센다
    $root = Split-Path -Parent $COURSE
    $base = Join-Path $root 'MyData'
    if ((Split-Path -Leaf $COURSE) -ne '01_KIT' -or -not (Test-Path $base)) {
        Set-Result 'mydata' '내 양식 (보고서 3·회의록 3, 비식별)' '선택' $false 'MyData 폴더 없음 — 표준 설치가 아니면 건너뜁니다'
        return
    }
    $n = @{}
    foreach ($k in 'Report','Minutes','Track','Skill') {
        $n[$k] = @(Get-ChildItem -LiteralPath (Join-Path $base $k) -File -ErrorAction SilentlyContinue).Count
    }
    $ok = ($n['Report'] -ge 3) -and ($n['Minutes'] -ge 3)
    $d = "보고서(Report) $($n['Report'])개 · 회의록(Minutes) $($n['Minutes'])개 · 직무 문서(Track) $($n['Track'])개 · 내 스킬(Skill) $($n['Skill'])개 — $base"
    if ($n['Skill'] -gt 0) { $d += ' / 쓰던 스킬이 있으니 부록 카드 A-3 을 A-4 보다 먼저 돌리세요' }
    Set-Result 'mydata' '내 양식 (보고서 3·회의록 3, 비식별)' '선택' $ok $d "$base 에 비식별 사본을 넣으세요 (선택 · 부록 A)"
}

function Check-SlackEnv {
    # 🔒 값은 절대 화면에 찍지 않는다. 키 이름과 앞머리(xoxb-/xapp-)만 본다.
    $env_ = Join-Path $KIT 'slack-server\.env'
    $fix = '교안 슬랙 ①② 쪽대로 열쇠를 받아 두고 슬랙열쇠_넣기.bat 을 실행해 붙여넣습니다'
    $url = 'https://api.slack.com/apps'
    if (-not (Test-Path $env_)) {
        $stray = @(Get-ChildItem (Join-Path $KIT 'slack-server') -Filter '.env.*' -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.env.example' })
        $d = '.env 파일이 아직 없습니다'
        if ($stray.Count) { $d = ".env 대신 $($stray[0].Name) 로 저장돼 있습니다 — 확장자를 지우세요" }
        return (Set-Result 'slack' '슬랙 열쇠 3개 (.env — 봇·앱·멤버 ID)' '필수' $false $d $fix $url)
    }
    $vals = @{}
    foreach ($line in (Get-Content $env_ -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $l = $line -replace '^﻿', ''
        if ($l.Trim().StartsWith('#') -or $l -notmatch '=') { continue }
        $k, $v = $l -split '=', 2
        $vals[$k.Trim().ToUpper()] = $v
    }
    $problems = @()
    foreach ($pair in @(@('SLACK_BOT_TOKEN', 'xoxb-'), @('SLACK_APP_TOKEN', 'xapp-'))) {
        $key = $pair[0]; $head = $pair[1]
        if (-not $vals.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($vals[$key])) { $problems += "$key 비어 있음"; continue }
        $raw = $vals[$key]; $v = $raw.Trim()
        if ($v.StartsWith('"') -or $v.StartsWith("'") -or $v.EndsWith('"') -or $v.EndsWith("'")) { $problems += "$key 따옴표 지우세요"; continue }
        if ($raw -ne $v) { $problems += "$key 앞뒤 공백 지우세요"; continue }
        if (-not $v.StartsWith($head)) {
            $other = 'xoxb-'; if ($head -eq 'xoxb-') { $other = 'xapp-' }
            if ($v.StartsWith($other)) { $problems += "$key 자리에 $other 가 들어갔습니다 (둘이 바뀜)" } else { $problems += "$key 는 $head 로 시작해야 합니다" }
        }
    }
    $own = ''; if ($vals.ContainsKey('OWNER_USER_ID')) { $own = $vals['OWNER_USER_ID'].Trim().Trim('"').Trim("'") }
    if (-not $own) { $problems += 'OWNER_USER_ID(내 멤버 ID) 비어 있음' }
    elseif ($own -notmatch '^[UW][A-Z0-9]{8,}$') { $problems += 'OWNER_USER_ID 는 U 로 시작하는 멤버 ID 여야 합니다' }
    $d = '열쇠 3개 모양 정상 (값은 확인하지 않습니다)'; if ($problems.Count) { $d = $problems -join ' / ' }
    Set-Result 'slack' '슬랙 열쇠 3개 (.env — 봇·앱·멤버 ID)' '필수' ($problems.Count -eq 0) $d $fix $url
}

function Check-VSCode {
    $p = Has-Cmd 'code'
    if (-not $p) { foreach ($c in @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe", "$env:ProgramFiles\Microsoft VS Code\Code.exe")) { if (Test-Path $c) { $p = $c } } }
    $d = '없어도 실습됩니다 (약 350MB)'; if ($p) { $d = $p }
    Set-Result 'vscode' 'VS Code' '선택' ([bool]$p) $d 'code.visualstudio.com' 'https://code.visualstudio.com/'
}

function Check-Chrome {
    $p = $null
    foreach ($c in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) { if (Test-Path $c) { $p = $c } }
    $d = '네이버 블로그 임시저장이 실제 Chrome 을 씁니다'; if ($p) { $d = $p }
    Set-Result 'chrome' 'Google Chrome (네이버 블로그 임시저장용)' '선택' ([bool]$p) $d 'google.com/chrome' 'https://www.google.com/chrome/'
}

function Check-NaverLogin {
    $state = Join-Path $KIT 'naver-blog\.naver-state.json'
    $ok = Test-Path $state
    $d = '아직 로그인 안 함'; if ($ok) { $d = '세션 파일 있음 (.naver-state.json)' }
    Set-Result 'naver-login' '네이버 블로그 로그인 (블로그 스킬)' '선택' $ok $d 'py -3.14 naver-blog\naver_draft.py login --blog-id 내아이디' 'https://blog.naver.com/'
}

# ── 4. 고치기 (설치·로그인) — 2026-09-07: 묻지 않고 바로 한다 ──
function Fix-ExecutionPolicy {
    # 파워셸이 .ps1 실행을 막아 두면 파워셸 창에서 `claude` 가 "이 시스템에서 스크립트를 실행할 수 없습니다"로 죽는다.
    # (npm 으로 깔린 claude 는 파워셸에서 claude.ps1 을 먼저 집기 때문) 그래서 사용자 범위로 한 번 풀어 둔다.
    $name = '파워셸 스크립트 실행 허용 (어느 창에서든 claude 한 단어)'
    try {
        $cur = Get-ExecutionPolicy -Scope CurrentUser
        if ($cur -notin 'RemoteSigned', 'Unrestricted', 'Bypass') {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
        }
        $eff = Get-ExecutionPolicy
        $ok = ($eff -in 'RemoteSigned', 'Unrestricted', 'Bypass')
        $d = "적용됨 (CurrentUser=RemoteSigned, 실제 적용=$eff)"
        if (-not $ok) { $d = "회사 정책(그룹 정책)이 $eff 로 고정 — 파워셸 대신 CMD 창을 쓰면 그대로 됩니다" }
        Set-Result 'execpolicy' $name '기본' $ok $d
    } catch {
        Set-Result 'execpolicy' $name '기본' $false "바꾸지 못함 — CMD 창에서는 그대로 됩니다 ($($_.Exception.Message))"
    }
}

function Install-WithWinget([string]$id, [string]$label, [string]$override = '', [switch]$Force) {
    Write-Info "winget 으로 $label 설치 중… (몇 분 걸립니다. 이 창을 닫지 마세요)"
    $wargs = @('install', '--exact', '--id', $id, '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity')
    if ($Force) { $wargs += '--force' }
    if ($override) { $wargs += @('--override', $override) }
    try { & winget @wargs | Out-Host } catch { Write-Warn "winget 실패: $_" }
    Refresh-Path
}

function Fix-Programs {
    $todo = @()
    if (-not (Is-Ok 'node')) { $todo += @{ id = 'OpenJS.NodeJS.LTS'; label = 'Node.js LTS'; ov = '' } }
    if (-not (Is-Ok 'git'))  { $todo += @{ id = 'Git.Git';           label = 'Git';         ov = '' } }
    if ($todo.Count -eq 0) { return }
    Write-Step "빠진 프로그램 $($todo.Count)개를 지금 설치합니다: $(($todo | ForEach-Object { $_.label }) -join ', ')"
    if ($SkipInstall) { Write-Info '(-SkipInstall) 자동 설치 생략'; return }
    if (-not (Has-Cmd 'winget')) {
        Write-Warn 'winget 이 없어 자동 설치가 안 됩니다. 다운로드 페이지를 엽니다 — 설치 후 환경점검을 다시 실행하세요.'
        foreach ($t in $todo) { $r = $null; switch ($t.label) { 'Node.js LTS' { $r = Get-Result 'node' } 'Git' { $r = Get-Result 'git' } }; if ($r -and $r.Url) { Open-Url $r.Url } }
        return
    }
    foreach ($t in $todo) { Install-WithWinget $t.id $t.label $t.ov }
    Write-Info '설치 후 다시 확인합니다'
    if (-not (Is-Ok 'node')) { Check-Node | Out-Null; Check-Npm | Out-Null }
    if (-not (Is-Ok 'git'))  { Check-Git | Out-Null }
}

function Fix-Python {
    # 대표 결정(2026-09-07): 파이썬은 있어도 무조건 설치한다. 낮은 버전이 깔려 있으면 그 자리에서 3.14 가 올라간다.
    # 3.14 가 이미 있으면 winget 이 "이미 설치됨"으로 몇 초 만에 끝난다.
    if ($SkipInstall) { Write-Info '(-SkipInstall) Python 설치 생략'; return }
    Write-Step 'Python 3.14 설치 — 있어도 다시 확인해서 최신으로 맞춥니다 (묻지 않습니다)'
    $had314 = (Is-Ok 'python')
    if (-not (Has-Cmd 'winget')) {
        if ($had314) { Write-Info 'winget 이 없지만 3.14 가 이미 있어 그대로 씁니다'; return }
        Write-Warn 'winget 이 없어 자동 설치가 안 됩니다. python.org 를 엽니다 — 설치 첫 화면 맨 아래 "Add python.exe to PATH" 를 켜세요.'
        Open-Url 'https://www.python.org/downloads/windows/'
        return
    }
    $ov = '/quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_pip=1 Include_test=0'
    # 3.14 가 이미 있으면 그대로 두고(수업 중 켜져 있는 파이썬을 제자리에서 갈아끼우면 깨질 수 있다),
    # 없거나 낮은 버전만 있으면 --force 로 새로 깐다.
    Install-WithWinget 'Python.Python.3.14' 'Python 3.14' $ov -Force:(-not $had314)
    # py 실행기의 기본을 3.14 로 고정 — 이후 py / py -3 / 안전장치(hooks) 전부 3.14 로 돈다.
    foreach ($k in 'PY_PYTHON', 'PY_PYTHON3') {
        try { [Environment]::SetEnvironmentVariable($k, '3.14', 'User') } catch {}
        Set-Item -Path "Env:$k" -Value '3.14'
    }
    Check-Python | Out-Null
    Check-Pip | Out-Null
    if (Is-Ok 'python') { Write-Info 'py 실행기 기본 = 3.14 (PY_PYTHON / PY_PYTHON3). 새 창부터 py -3 도 3.14 입니다.' }
}

function Fix-Claude {
    if (Is-Ok 'claude') { return }
    if ($SkipInstall) { Write-Info '(-SkipInstall) Claude Code 설치 생략'; return }
    Write-Step 'Claude Code 설치 (묻지 않습니다)'
    if (Has-Cmd 'winget') {
        Install-WithWinget 'Anthropic.ClaudeCode' 'Claude Code'
        Check-Claude | Out-Null
        if (Is-Ok 'claude') { return }
    }
    Write-Info '공식 설치 스크립트(claude.ai/install.ps1)로 다시 시도합니다'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-Expression (Invoke-RestMethod -Uri 'https://claude.ai/install.ps1' -UseBasicParsing)
    } catch { Write-Warn "공식 설치 스크립트 실패: $_" }
    Refresh-Path
    Check-Claude | Out-Null
    if (Is-Ok 'claude') { return }
    if (Is-Ok 'npm') {
        Write-Info '마지막으로 npm 으로 설치합니다 (약 610MB)'
        $null = Run-Live 'npm install -g @anthropic-ai/claude-code' 900
        Refresh-Path
        Check-Claude | Out-Null
    }
    if (-not (Is-Ok 'claude')) { Write-Warn '자동 설치가 전부 막혔습니다. 회사 보안 정책이면 개인 노트북으로 진행하세요.' }
}

function Fix-ClaudeVersion {
    if ((Is-Ok 'claude-ver') -or -not (Is-Ok 'claude')) { return }
    if ($SkipInstall) { Write-Info '(-SkipInstall) Claude Code 업데이트 생략'; return }
    Write-Step 'Claude Code 를 최신판으로 올립니다 (묻지 않음, 1분 안팎)'
    $r = Invoke-Cmd 'claude update' 240
    Check-ClaudeVersion | Out-Null
    if (Is-Ok 'claude-ver') { return }
    if (Has-Cmd 'npm') {
        Write-Info 'claude update 로 안 올라가 npm 으로 다시 설치합니다'
        $null = Invoke-Cmd 'npm install -g @anthropic-ai/claude-code@latest' 300
        Refresh-Path
        Check-ClaudeVersion | Out-Null
    }
    if (-not (Is-Ok 'claude-ver')) { Write-Warn 'Claude Code 를 올리지 못했습니다. 검은 창에서 claude update 를 직접 실행해 보세요.' }
}

function Fix-ClaudeLogin {
    if ((Is-Ok 'claude-login') -or -not (Is-Ok 'claude')) { return }
    if ($SkipLogin) { Write-Info '(-SkipLogin) 로그인 생략'; return }
    Write-Step 'Claude Code 로그인 — 새 창과 브라우저가 열립니다'
    Write-Info '브라우저에서 claude.ai 계정(유료 구독)으로 로그인하고, 코드가 나오면 검은 창에 붙여넣으세요.'
    Write-Info '이 창은 로그인이 끝나는 걸 자동으로 감지합니다 (최대 10분).'
    Open-NewWindow 'Claude-Code-로그인' 'claude auth login'
    $deadline = (Get-Date).AddMinutes(10)
    $logged = $false
    while ((Get-Date) -lt $deadline) {
        if (Check-ClaudeLogin -Quiet) { $logged = $true; break }
        Write-Host -NoNewline '.' -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
    }
    Write-Host ''
    if (-not $logged) { Write-Warn '10분 안에 로그인이 확인되지 않았습니다. 로그인 후 환경점검을 다시 실행하세요.' }
    Check-ClaudeLogin | Out-Null
}

function Fix-PyPackages {
    if (-not $script:PY) { return }
    if ($SkipInstall) { Write-Info '(-SkipInstall) 꾸러미 설치 생략'; return }
    $req = Join-Path $KIT 'slack-server\requirements.txt'
    if (-not (Test-Path $req)) { Write-Warn "requirements.txt 가 없습니다: $req"; return }
    Write-Step '파이썬 꾸러미 설치 — 매번 확인해서 빠진 것만 채웁니다 (묻지 않습니다)'
    $null = Run-Live "$($script:PY) -m pip install --disable-pip-version-check -r `"$req`" playwright pandas openpyxl matplotlib python-docx pypdf" 900
    Check-PyPackages | Out-Null
    if (-not (Is-Ok 'pypkg')) {
        Write-Warn '꾸러미가 아직 빠져 있습니다. 한 번 더 시도합니다.'
        $null = Run-Live "$($script:PY) -m pip install --disable-pip-version-check --upgrade pip" 300
        $null = Run-Live "$($script:PY) -m pip install --disable-pip-version-check -r `"$req`" playwright pandas openpyxl matplotlib python-docx pypdf" 900
        Check-PyPackages | Out-Null
    }
    if (-not (Is-Ok 'pypkg')) { Write-Warn '꾸러미 설치가 끝나지 않았습니다. 인터넷·백신을 확인하고 환경점검을 다시 실행하세요.' }
}

function Read-Secret([string]$label, [string]$head) {
    # 값은 별표로 가려서 받는다. 화면 공유 중에도 안전하다.
    while ($true) {
        $s = Read-Host "  ? $label — $head 로 시작하는 값을 붙여넣고 Enter (나중에 하려면 s)" -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
        try { $v = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $v = $v.Trim().Trim('"').Trim("'")
        if ($v.ToLower() -eq 's') { return $null }
        if (-not $v) { Write-Warn '비어 있습니다. 다시 붙여넣으세요 (붙여넣기 = 마우스 오른쪽 클릭)'; continue }
        if ($v.StartsWith($head)) { Write-Info "받음: $($v.Substring(0, [Math]::Min(8, $v.Length)))… ($($v.Length)자)"; return $v }
        $other = 'xapp-'; if ($head -eq 'xapp-') { $other = 'xoxb-' }
        if ($v.StartsWith($other)) { Write-Warn "$other 로 시작하는 값입니다 — 다른 열쇠를 붙여넣으셨어요. $head 열쇠를 넣어주세요." }
        else { Write-Warn "$head 로 시작해야 합니다. 앞뒤가 잘렸는지 확인하세요." }
    }
}

function Fix-Slack([switch]$Force) {
    # -Force : 열쇠 모양이 맞아도 다시 묻는다. 모양만 맞고 값이 틀린 열쇠를 고칠 길이 없던 문제 (2026-11-03)
    if ((Is-Ok 'slack') -and -not $Force) { return }
    if ($SkipSlack -or $SkipLogin) { Write-Info '(-SkipSlack) 슬랙 열쇠 입력 생략'; return }
    $srv = Join-Path $KIT 'slack-server'
    $envf = Join-Path $srv '.env'
    Write-Step '슬랙 열쇠 넣기 — 교안 슬랙 ①② 쪽에서 받아 둔 값을 교안과 같은 순서로 붙여넣습니다'
    Write-Info '붙여넣기는 마우스 오른쪽 클릭. 값은 별표(*)로 가려지고 .env 파일에만 저장됩니다.'
    Write-Info '아직 못 받았으면 s 를 치고 Enter — 나중에 슬랙열쇠_넣기.bat 을 실행하면 이 자리부터 다시 묻습니다.'
    # 2026-11-02: 교안이 앱 토큰(xapp)을 먼저 받으므로 묻는 순서도 앱 → 봇
    $appT = Read-Secret '① 앱 토큰 SLACK_APP_TOKEN' 'xapp-'
    if (-not $appT) { Write-Info '슬랙은 나중에. 교안 슬랙 ①② 쪽대로 받아 오세요.'; return }
    $bot = Read-Secret '② 봇 토큰 SLACK_BOT_TOKEN' 'xoxb-'
    if (-not $bot) { Write-Info '슬랙은 나중에.'; return }
    $owner = ''
    while ($true) {
        $owner = (Read-Host '  ? ③ 내 멤버 ID OWNER_USER_ID — U 로 시작하는 값 (슬랙 앱 → 내 프로필 → ⋯ 더보기 → 멤버 ID 복사)').Trim().Trim('"').Trim("'")
        if ($owner -match '^[UW][A-Z0-9]{8,}$') { break }
        Write-Warn 'U 로 시작하는 9자 이상 영문·숫자여야 합니다 (이메일·이름이 아니라 "멤버 ID 복사" 값)'
    }
    # ④ 내 이름 — 2026-09-14 추가.
    # 직원이 대표를 남의 이름으로 부른 사고의 근본 해결책. 사람이 직접 친 값이라
    # 파일이 깨질 일도, 슬랙의 영문 프로필 이름을 잘못 옮길 일도 없다.
    $ownerName = ''
    while ($true) {
        $ownerName = (Read-Host '  ? ④ 내 이름 OWNER_NAME — 직원들이 나를 부를 이름 (한글, 예: 홍길동)').Trim().Trim('"').Trim("'")
        if (-not $ownerName) { Write-Warn '이름이 없으면 직원이 나를 "대표님" 이라고만 부릅니다. 그래도 되면 한 번 더 Enter.'
                               $ownerName = (Read-Host '  ? ④ 내 이름 (그냥 Enter 치면 건너뜁니다)').Trim()
                               if (-not $ownerName) { break } }
        if ($ownerName -match '[가-힣]') { break }
        Write-Warn '한글 이름으로 적어 주세요. 영문 이름은 직원이 한글로 옮기다 틀립니다.'
    }
    $body = "# 슬랙 열쇠 — 환경점검이 $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm')) 에 저장. 비밀번호와 같습니다. 남에게 주지 마세요.`n" +
            "SLACK_BOT_TOKEN=$bot`nSLACK_APP_TOKEN=$appT`nOWNER_USER_ID=$owner`n"
    if ($ownerName) { $body += "OWNER_NAME=$ownerName`n" }
    try {
        [IO.File]::WriteAllText($envf, $body, (New-Object System.Text.UTF8Encoding($false)))   # BOM 없이
        Write-Info ".env 저장됨 (BOM 없음): $envf"
    } catch { Write-Warn ".env 저장 실패: $_"; return }
    Check-SlackEnv | Out-Null
}

function Test-SlackLive {
    # 열쇠 모양이 맞아도 값이 틀릴 수 있다. 실제로 슬랙에 물어본다 (값은 출력하지 않는다).
    if (-not (Is-Ok 'slack')) { return }
    if (-not (Is-Ok 'pypkg') -or -not $script:PY) { Set-Result 'slack-live' '슬랙 열쇠가 실제로 통한다' '필수' $false '파이썬 꾸러미 먼저'; return }
    $chk = Join-Path $KIT 'slack-server\slack_check.py'
    if (-not (Test-Path $chk)) { Set-Result 'slack-live' '슬랙 열쇠가 실제로 통한다' '필수' $false 'slack_check.py 가 없습니다 — 스타터킷 다시 설치'; return }
    Write-Step '슬랙에 실제로 물어봅니다 (열쇠 값은 화면에 나오지 않습니다)'
    $r = Invoke-Cmd "$($script:PY) `"$chk`"" 60
    $lines = @($r.out -split "`r?`n" | Where-Object { $_.Trim() })
    foreach ($l in $lines) { Write-Info $l }
    $d = ($lines | Select-Object -Last 1); if (-not $d) { $d = '응답 없음' }
    Set-Result 'slack-live' '슬랙 열쇠가 실제로 통한다' '필수' $r.ok $d '틀린 열쇠를 다시 받아 슬랙열쇠_넣기.bat 을 다시 실행'
}

function Test-Server {
    # 서버를 한 번 켜서 "준비 완료" 까지 보고 끈다. 수강생이 처음 보는 성공 화면이 이것이다.
    if ($NoServerTest) { return }
    if (-not (Is-Ok 'slack-live')) { Set-Result 'server' '슬랙 서버 첫 기동 (준비 완료)' '필수' $false '열쇠 확인 먼저'; return }
    $srv = Join-Path $KIT 'slack-server'
    $exeLine = Invoke-Cmd "$($script:PY) -c `"import sys;print(sys.executable)`"" 30
    $pyexe = First-Line $exeLine.out
    if (-not ($pyexe -and (Test-Path $pyexe))) { Set-Result 'server' '슬랙 서버 첫 기동 (준비 완료)' '필수' $false '파이썬 실행 파일을 찾지 못함'; return }
    Write-Step '슬랙 서버를 한 번 켜 봅니다 (최대 90초, 끝나면 자동으로 끕니다)'
    $out = [IO.Path]::GetTempFileName(); $err = [IO.Path]::GetTempFileName()
    $p = $null; $ok = $false; $d = '90초 안에 "준비 완료" 가 뜨지 않음'
    try {
        $p = Start-Process -FilePath $pyexe -ArgumentList '-u', '-X', 'utf8', 'server.py' -WorkingDirectory $srv -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
        $null = $p.Handle
        $deadline = (Get-Date).AddSeconds(90)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            # 2026-11-03: 서버가 출력 파일을 열고 있어 ReadAllText 는 늘 '사용 중' 으로 실패했다(빈 문자열 → 90초 뒤 ❌).
            #   공유 읽기로 연다. -u 는 출력이 버퍼에 묶이지 않게 한다.
            $txt = ''
            foreach ($f in @($out, $err)) {
                try { $fs = [IO.File]::Open($f, 'Open', 'Read', 'ReadWrite'); $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); $txt += $sr.ReadToEnd(); $sr.Close() } catch {}
            }
            if ($txt -match '준비 완료') { $ok = $true; $d = ($txt -split "`r?`n" | Where-Object { $_ -match '준비 완료' } | Select-Object -First 1).Trim(); break }
            if ($txt -match '❌|Error|Traceback') { $d = (($txt -split "`r?`n" | Where-Object { $_ -match '❌|Error' } | Select-Object -First 1)); if (-not $d) { $d = '오류로 종료' }; break }
            if ($p.HasExited) { $d = "서버가 바로 꺼짐 (종료코드 $($p.ExitCode))"; break }
            Write-Host -NoNewline '.' -ForegroundColor DarkGray
        }
        Write-Host ''
    } catch { $d = "실행 실패: $_" }
    finally {
        if ($p -and -not $p.HasExited) { try { $p.Kill() } catch {} }
        Remove-Item $out, $err -ErrorAction SilentlyContinue
    }
    $agents = @(Get-ChildItem (Join-Path $KIT '.claude\agents') -Filter '*.md' -ErrorAction SilentlyContinue).Count
    if ($ok -and $agents -eq 0) { $d += ' — 직원은 아직 0명(모듈 1에서 만듭니다)' }
    Set-Result 'server' '슬랙 서버 첫 기동 (준비 완료)' '필수' $ok $d 'slack-server 폴더에서 py -3 -X utf8 server.py 를 켜고 메시지를 읽으세요'
}

function Enable-Autostart {
    # 슬랙 서버가 로그온 때마다 저절로 뜨게 등록한다.
    # 이게 없으면 수강생이 검은 창을 닫거나 PC 를 껐다 켤 때마다 직원들이 조용히 사라지고,
    # 터미널에서 py -3 -X utf8 server.py 를 다시 쳐야 한다. 2026-09-20 신설.
    if ($NoServerTest) { return }
    # 2026-10-05: 서버 첫 기동이 실패해도 등록은 한다. 등록을 건너뛰면 PC 를 껐다 켤 때
    #   아무것도 뜨지 않고, 수강생은 그 사실을 다음 수업에서야 안다. 감시기가 10초마다
    #   다시 시도하니 열쇠를 고치는 순간부터 저절로 뜬다.
    $serverUp = Is-Ok 'server'
    $ps1 = Join-Path $KIT 'slack-server\autostart.ps1'
    if (-not (Test-Path -LiteralPath $ps1)) { Set-Result 'autostart' 'PC 켤 때 슬랙 서버 자동 시작' '필수' $false 'autostart.ps1 이 없습니다 — 스타터킷 다시 설치'; return }
    Write-Step '이제 PC 를 켤 때마다 슬랙 서버가 저절로 뜨도록 등록합니다'
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 -Enable -Quiet 2>&1 | ForEach-Object { Write-Info $_ }
    } catch { Write-Warn "등록 중 오류: $_" }
    $pidFile = Join-Path $KIT 'slack-server\logs\server.pid'
    $ok = $false; $d = '자동시작 등록에 실패했습니다'
    $reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
    if ($reg -and $reg.GplatformStarterkitServer) {
        $sid = $null
        if (Test-Path -LiteralPath $pidFile) { $sid = (Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1) -as [int] }
        if ($sid -and (Get-Process -Id $sid -ErrorAction SilentlyContinue)) { $ok = $true; $d = "등록 완료 — 지금도 켜져 있습니다 (PID $sid)" }
        elseif ($serverUp) { $ok = $true; $d = '등록 완료 — 다음에 PC 를 켜면 뜹니다' }
        else { $ok = $true; $d = '등록은 됐습니다 — 다만 서버가 아직 안 떴습니다. 슬랙 열쇠 3개를 확인하고 환경점검을 다시 돌리면 그때부터 저절로 뜹니다' }
    }
    Set-Result 'autostart' 'PC 켤 때 슬랙 서버 자동 시작' '필수' $ok $d '스타터킷 폴더의 자동시작_켜기.bat 을 눌러 주세요'
}

function Fix-OptionalLogins {
    if ($SkipLogin -or -not $OptionalLogins) { return }
    if (-not ((Is-Ok 'python') -and (Is-Ok 'playwright') -and (Is-Ok 'chrome'))) { return }
    if (-not (Is-Ok 'naver-login')) {
        $script_ = Join-Path $KIT 'naver-blog\naver_draft.py'
        if (Test-Path $script_) {
            $bid = Read-Host '  ? 네이버 블로그 아이디 (blog.naver.com/뒤에 오는 것, 비우면 건너뜀)'
            if (-not [string]::IsNullOrWhiteSpace($bid)) {
                Open-NewWindow 'Naver-Blog-로그인' "$($script:PY) `"$script_`" login --blog-id $($bid.Trim())" (Split-Path $script_)
                Wait-Enter '크롬 창에서 네이버 로그인을 마치고 "[OK]" 가 뜨면'
                Check-NaverLogin | Out-Null
            }
        }
    }
}

function Check-MailEnv {
    # 🔒 값은 절대 화면에 찍지 않는다. 키 이름이 있는지만 본다.
    $envf = Join-Path $KIT 'mail\.env'
    if (-not (Test-Path (Join-Path $KIT 'mail\mail_check.py'))) { return }
    if (-not (Test-Path $envf)) { return (Set-Result 'mail' '메일 연결 (네이버·다음·지메일 앱 비밀번호)' '선택' $false 'mail\.env 가 아직 없습니다 (부록 B-2 · 수업 뒤 선택)' '메일_연결.bat 을 실행해 앱 비밀번호를 붙여넣습니다' 'https://mail.naver.com/') }
    $vals = @{}
    foreach ($line in (Get-Content $envf -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $l = $line -replace '^﻿', ''
        if ($l.Trim().StartsWith('#') -or $l -notmatch '=') { continue }
        $k, $v = $l -split '=', 2
        $vals[$k.Trim().ToUpper()] = $v.Trim()
    }
    $missing = @(@('MAIL_PROVIDER', 'MAIL_USER', 'MAIL_APP_PASSWORD') | Where-Object { -not $vals.ContainsKey($_) -or -not $vals[$_] })
    $d = "$($vals['MAIL_PROVIDER']) $($vals['MAIL_USER']) (비밀번호는 확인하지 않습니다)"; if ($missing.Count) { $d = ($missing -join ', ') + ' 비어 있음' }
    Set-Result 'mail' '메일 연결 (네이버·다음·지메일 앱 비밀번호)' '선택' ($missing.Count -eq 0) $d '메일_연결.bat 을 실행해 앱 비밀번호를 붙여넣습니다' 'https://mail.naver.com/'
}

function Fix-Mail {
    # 메일은 선택이다. 슬랙 열쇠처럼 별표로 받아 mail\.env 에만 저장한다. s 면 건너뛴다.
    # 2026-11-02: 설치·환경점검에서는 묻지 않는다. 메일_연결.bat(-MailOnly) 또는 -Mail 일 때만.
    if (-not ($Mail -or $MailOnly)) { return }
    if ($SkipLogin) { return }
    if (-not (Test-Path (Join-Path $KIT 'mail\mail_check.py'))) { return }
    # 2026-11-04: 이미 연결돼 있으면 바꿀지 묻는다 (지메일 → 네이버 등). 그냥 Enter 면 그대로.
    if (Is-Ok 'mail') {
        $cur = ((Get-Result 'mail').Detail -replace '\s*\(비밀번호는 확인하지 않습니다\)', '').Trim()
        $ans = (Read-Host "  ? 지금 $cur 이(가) 연결돼 있습니다. 다른 메일로 바꿀까요? (y = 바꾸기 / 그냥 Enter = 그대로)").Trim().ToLower()
        if ($ans -ne 'y') { return }
        Write-Info '새 메일로 다시 묻습니다. 끝까지 넣으면 예전 연결은 새 것으로 바뀝니다 (메일 연결은 한 계정만 기억합니다).'
    }
    $envf = Join-Path $KIT 'mail\.env'
    Write-Step '메일 연결 (선택) — 메일을 직원이 읽게 합니다. 앱 비밀번호는 교안 부록 B-2 대로 미리 받아 둡니다'
    Write-Info '연습은 개인 메일로 합니다. 회사 메일은 회사 승인을 받은 뒤에만 custom 으로 연결합니다.'
    Write-Info '네이버: 메일 → 환경설정 → POP3/IMAP 에서 IMAP 켜기 → 네이버 보안 → 2단계 인증 → 애플리케이션 비밀번호'
    Write-Info '다음: 메일 → 설정 → IMAP/SMTP 사용 → 카카오계정 2단계 인증 → 앱 비밀번호   /   지메일: 구글 계정 → 보안 → 앱 비밀번호'
    $prov = ''
    while ($true) {
        $prov = (Read-Host '  ? 어느 메일인가요 — naver / daum / gmail / custom(회사 메일) 중 하나 (나중에 하려면 s)').Trim().ToLower()
        if ($prov -eq 's') { Write-Info '메일은 나중에. 수업 뒤 부록 카드 B-2 로 다시 할 수 있습니다.'; return }
        if ($prov -in @('naver', 'daum', 'gmail', 'custom')) { break }
        Write-Warn 'naver, daum, gmail, custom 중 하나를 영문으로 적어 주세요 (회사 메일이 구글 워크스페이스면 gmail)'
    }
    # 2026-11-03: 회사 메일 — 서버 주소를 받는다. 회사 승인이 먼저.
    $custom = ''
    if ($prov -eq 'custom') {
        Write-Warn '회사 메일은 회사 승인이 먼저입니다 — IMAP 접속 허용, 메일 본문을 Claude 가 읽는 것, 발송은 사람이 하는 것까지.'
        Write-Info '서버 주소는 회사 IT 에 물어보세요. 마이크로소프트 365(아웃룩)는 이 방식으로 연결되지 않습니다.'
        $ok = (Read-Host '  ? 회사 승인을 받았나요 (y / n)').Trim().ToLower()
        if ($ok -ne 'y') { Write-Info '승인 뒤에 메일_연결.bat 을 다시 실행하세요. 연습은 개인 메일로 합니다.'; return }
        $imapH = ''
        while (-not $imapH) {
            $imapH = (Read-Host '  ? 받는 메일 서버 IMAP 주소 (예: imap.회사도메인)').Trim().Trim('"').Trim("'")
            if ($imapH -match '(^|\.)(office365|outlook)\.com$') { Write-Warn '마이크로소프트 365 는 연결되지 않습니다. 개인 메일로 연습하세요.'; return }
        }
        $imapP = (Read-Host '  ? IMAP 포트 (모르면 그냥 Enter = 993)').Trim()
        $smtpH = (Read-Host '  ? 보내는 메일 서버 SMTP 주소 (읽기만 할 거면 그냥 Enter)').Trim().Trim('"').Trim("'")
        $smtpP = ''
        if ($smtpH) { $smtpP = (Read-Host '  ? SMTP 포트 (모르면 그냥 Enter = 465, 587 도 됩니다)').Trim() }
        $custom = "MAIL_IMAP_HOST=$imapH`nMAIL_IMAP_PORT=$imapP`nMAIL_SMTP_HOST=$smtpH`nMAIL_SMTP_PORT=$smtpP`n"
    }
    $user = ''
    while ($true) {
        $user = (Read-Host '  ? 메일 주소 전체 (예: hong@naver.com)').Trim().Trim('"').Trim("'")
        if ($user -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') { break }
        Write-Warn '@ 가 들어간 메일 주소 전체를 적어 주세요'
    }
    $pw = ''
    while ($true) {
        $s = Read-Host '  ? 앱 비밀번호 (로그인 비밀번호가 아닙니다) — 붙여넣고 Enter (나중에 하려면 s)' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
        try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $pw = $pw.Trim().Trim('"').Trim("'")
        if ($pw.ToLower() -eq 's') { Write-Info '메일은 나중에.'; return }
        if ($pw.Length -ge 8) { break }
        Write-Warn '너무 짧습니다. 앱 비밀번호를 다시 붙여넣으세요 (붙여넣기 = 마우스 오른쪽 클릭)'
    }
    $body = "# 메일 열쇠 — 환경점검이 $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm')) 에 저장. 비밀번호와 같습니다. 남에게 주지 마세요.`n" +
            "MAIL_PROVIDER=$prov`nMAIL_USER=$user`nMAIL_APP_PASSWORD=$pw`nMAIL_ALLOW_EXTERNAL=0`n" + $custom
    try {
        [IO.File]::WriteAllText($envf, $body, (New-Object System.Text.UTF8Encoding($false)))   # BOM 없이
        Write-Info "mail\.env 저장됨 (BOM 없음)"
    } catch { Write-Warn "mail\.env 저장 실패: $_"; return }
    Check-MailEnv | Out-Null
}

function Test-MailLive {
    # 앱 비밀번호가 실제로 통하는지 메일 서버에 물어본다 (값은 출력하지 않는다).
    if (-not (Is-Ok 'mail')) { return }
    if (-not (Is-Ok 'python') -or -not $script:PY) { return }
    $chk = Join-Path $KIT 'mail\mail_check.py'
    if (-not (Test-Path $chk)) { return }
    Write-Step '메일 서버에 실제로 로그인해 봅니다 (비밀번호는 화면에 나오지 않습니다)'
    $r = Invoke-Cmd "$($script:PY) `"$chk`"" 60
    $lines = @($r.out -split "`r?`n" | Where-Object { $_.Trim() })
    foreach ($l in $lines) { Write-Info $l }
    $d = ($lines | Select-Object -Last 1); if (-not $d) { $d = '응답 없음' }
    Set-Result 'mail-live' '메일 로그인이 실제로 통한다' '선택' $r.ok $d 'mail\README.md 의 오류 3가지를 보고 앱 비밀번호를 다시 받습니다'
}

# ── 5. 결과 HTML ─────────────────────────────────────────────
$WD_SYMBOL_B64 = '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'

function Html([string]$s) { return [System.Net.WebUtility]::HtmlEncode($s) }

function Write-Report {
    # 2026-11-03: 교안과 같은 디자인(청록 · 유리 카드 · 밝은/어두운 화면)으로 바꿈
    $req = @($script:Results | Where-Object { $_.Group -ne '선택' })
    $opt = @($script:Results | Where-Object { $_.Group -eq '선택' })
    $reqOk = @($req | Where-Object { $_.Ok }).Count
    $optOk = @($opt | Where-Object { $_.Ok }).Count
    $allOk = ($reqOk -eq $req.Count)
    $verdict = '아직 준비가 덜 됐습니다'
    $verdictSub = '빨간 줄만 고치면 됩니다. 고치는 법은 그 줄에 적혀 있습니다.'
    $verdictClass = 'bad'; $verdictIcon = '!'
    if ($allOk) { $verdict = '출발 준비 완료'; $verdictSub = '이제 슬랙에서 AI 에게 「안녕」 을 보내 보세요.'; $verdictClass = 'good'; $verdictIcon = '✓' }
    $pct = 0; if ($req.Count) { $pct = [int](100 * $reqOk / $req.Count) }

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append(@"
<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>환경 점검 결과</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Gowun+Dodum&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
:root{--bg:#e9f3f1;--blob-a:#9fdccc;--blob-b:#b9d4f2;--blob-c:#f4dcb8;--ink:#16302c;--ink-soft:#4b6661;--glass:rgba(255,255,255,.62);--glass-line:rgba(255,255,255,.75);--edge:rgba(22,48,44,.12);--accent:#0f7f6c;--accent-ink:#fff;--accent-soft:rgba(15,127,108,.12);--good:#15803d;--good-soft:rgba(21,128,61,.12);--bad:#c2410c;--bad-soft:rgba(194,65,12,.11);--warn:#b45309;--warn-soft:rgba(180,83,9,.10);--shadow:0 10px 30px rgba(22,48,44,.10);--font:"Gowun Dodum","Malgun Gothic","맑은 고딕",sans-serif;--mono:"IBM Plex Mono",Consolas,monospace}
@media (prefers-color-scheme:dark){:root{--bg:#0d1c1b;--blob-a:#1f5c52;--blob-b:#1e3a5c;--blob-c:#4a3a22;--ink:#e3f1ee;--ink-soft:#9bb8b2;--glass:rgba(24,46,44,.62);--glass-line:rgba(255,255,255,.10);--edge:rgba(227,241,238,.12);--accent:#4fd1b5;--accent-ink:#06201b;--accent-soft:rgba(79,209,181,.14);--good:#5fd38a;--good-soft:rgba(95,211,138,.14);--bad:#fb8a5c;--bad-soft:rgba(251,138,92,.14);--warn:#f5a454;--warn-soft:rgba(245,164,84,.12);--shadow:0 10px 30px rgba(0,0,0,.35)}}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;background:var(--bg);color:var(--ink);font-family:var(--font);line-height:1.6;font-size:15px}
body::before{content:"";position:fixed;inset:-20%;z-index:-1;background:radial-gradient(40% 35% at 15% 10%,var(--blob-a),transparent 70%),radial-gradient(35% 30% at 90% 25%,var(--blob-b),transparent 70%),radial-gradient(40% 35% at 60% 95%,var(--blob-c),transparent 70%);filter:blur(30px);opacity:.75}
.wrap{max-width:880px;margin:0 auto;padding:28px 16px 64px}
.top{display:flex;flex-wrap:wrap;align-items:baseline;gap:6px 12px;margin-bottom:22px}
.eyebrow{font-size:13px;letter-spacing:.08em;color:var(--accent)}
.when{margin-left:auto;font-size:13px;color:var(--ink-soft)}
h1{margin:0 0 4px;font-size:clamp(26px,5vw,36px);font-weight:400;letter-spacing:-.01em}
.lede{margin:0 0 22px;color:var(--ink-soft);font-size:14px;word-break:break-all}
.glass{background:var(--glass);border:1px solid var(--glass-line);border-radius:22px;box-shadow:var(--shadow);backdrop-filter:blur(18px) saturate(1.3);-webkit-backdrop-filter:blur(18px) saturate(1.3)}
.verdict{display:flex;align-items:center;gap:16px;padding:20px 22px;margin-bottom:26px}
.badge{flex:none;width:52px;height:52px;border-radius:50%;display:grid;place-items:center;font-size:26px;color:#fff}
.verdict.good .badge{background:var(--good)} .verdict.bad .badge{background:var(--bad)}
.verdict .t{font-size:21px}
.verdict .s{color:var(--ink-soft);font-size:14px}
.score{margin-left:auto;text-align:right;flex:none}
.score .n{font-family:var(--mono);font-size:22px;color:var(--accent)}
.score .l{font-size:12px;color:var(--ink-soft)}
.bar{height:6px;border-radius:6px;background:var(--edge);margin-top:6px;overflow:hidden;width:120px}
.bar i{display:block;height:100%;background:var(--accent)}
h2{font-size:14px;font-weight:400;letter-spacing:.06em;color:var(--accent);margin:26px 4px 10px}
.list{padding:6px 0;overflow:hidden}
.row{display:grid;grid-template-columns:34px 1fr;gap:4px 12px;padding:14px 18px;border-top:1px solid var(--edge)}
.row:first-child{border-top:0}
.mark{width:28px;height:28px;border-radius:50%;display:grid;place-items:center;font-size:15px;margin-top:1px}
.ok .mark{background:var(--good-soft);color:var(--good)}
.no .mark{background:var(--bad-soft);color:var(--bad)}
.opt .mark{background:var(--warn-soft);color:var(--warn)}
.name{font-size:15.5px}
.detail{grid-column:2;color:var(--ink-soft);font-size:14px;word-break:break-word}
.fix{grid-column:2;margin-top:6px;padding:8px 12px;border-radius:10px;background:var(--bad-soft);font-size:14px}
.opt .fix{background:var(--warn-soft)}
.fix a{color:var(--accent);word-break:break-all}
.next{margin-top:30px;padding:20px 22px}
.next h3{margin:0 0 8px;font-size:16px;font-weight:400;color:var(--accent)}
.next ol{margin:0;padding-left:20px}
.next li{margin:4px 0}
.next b{font-weight:400;font-family:var(--mono);font-size:13.5px;background:var(--accent-soft);padding:1px 6px;border-radius:6px}
.foot{margin-top:14px;font-size:12px;color:var(--ink-soft)}
@media (max-width:560px){.verdict{flex-wrap:wrap}.score{margin-left:68px;text-align:left}}
@media print{body::before{display:none}.glass{box-shadow:none;backdrop-filter:none;border-color:#ccc}}
</style></head><body><div class="wrap">
<div class="top"><span class="eyebrow">클로드코드 업무자동화과정 · 환경 점검</span><span class="when">$($STARTED.ToString('yyyy-MM-dd HH:mm'))</span></div>
<h1>출발선 점검 결과</h1>
<p class="lede">$(Html $env:COMPUTERNAME) · $(Html $KIT)</p>
<div class="glass verdict $verdictClass"><span class="badge">$verdictIcon</span><div><div class="t">$verdict</div><div class="s">$verdictSub</div></div>
<div class="score"><div class="n">$reqOk/$($req.Count)</div><div class="l">필수 통과 · 선택 $optOk/$($opt.Count)</div><div class="bar"><i style="width:$pct%"></i></div></div></div>
"@)

    foreach ($grp in @(@('필수 — 모두 통과해야 수업을 시작할 수 있습니다', $req), @('선택 — 없어도 실습은 되지만, 집에서 스킬을 쓰려면 필요합니다', $opt))) {
        if (-not $grp[1].Count) { continue }
        $null = $sb.Append("<h2>$($grp[0])</h2><div class=`"glass list`">")
        foreach ($r in $grp[1]) {
            $cls = 'no'; $m = '✕'
            if ($r.Group -eq '선택') { $cls = 'opt'; $m = '!' }
            if ($r.Ok) { $cls = 'ok'; $m = '✓' }
            $fix = ''
            if (-not $r.Ok -and ($r.Fix -or $r.Url)) {
                $fix = '<div class="fix">→ ' + (Html $r.Fix)
                if ($r.Url) { $fix += " <a href=`"$($r.Url)`" target=`"_blank`" rel=`"noopener`">$(Html $r.Url)</a>" }
                $fix += '</div>'
            }
            $null = $sb.Append("<div class=`"row $cls`"><span class=`"mark`">$m</span><div class=`"name`">$(Html $r.Name)</div><div class=`"detail`">$(Html $r.Detail)</div>$fix</div>")
        }
        $null = $sb.Append('</div>')
    }

    if ($allOk) {
        $next = '<li>슬랙 앱에서 AI 와 1:1 대화를 열고 <b>안녕</b> → 내 이름으로 대답하면 성공입니다.</li>' +
                '<li><b>팀 소개</b> 를 보내면 직원들이 각자 이름·아이콘으로 인사합니다.</li>' +
                '<li>직원을 새로 만들거나 고친 뒤에는 <b>자동시작_켜기.bat</b> 을 더블클릭해 서버를 다시 켭니다.</li>'
    } else {
        $next = '<li>슬랙 줄만 빨간색이면 정상입니다. 교안 <b>슬랙 ①②</b> 로 열쇠를 받은 뒤 <b>슬랙열쇠_넣기.bat</b> 을 더블클릭합니다.</li>' +
                '<li>다른 빨간 줄이 있으면 그 줄의 안내대로 고치고 <b>환경점검.bat</b> 을 다시 더블클릭합니다.</li>' +
                '<li>주황색(!) 은 선택 항목이라 없어도 수업이 됩니다. 메일은 부록 B-2 의 <b>메일_연결.bat</b> 으로 따로 합니다.</li>'
    }
    $null = $sb.Append(@"
<div class="glass next"><h3>다음 할 일</h3><ol>$next</ol>
<div class="foot">이 점검은 열쇠 값을 화면에 보여 주거나 이 파일에 저장하지 않습니다. 로그인은 항상 본인이 직접 합니다. · 지플랫폼</div></div>
</div></body></html>
"@)
    [IO.File]::WriteAllText($REPORT, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
}

# ── 6. 실행 ──────────────────────────────────────────────────
Write-Host ''
Write-Host '  ┌──────────────────────────────────────────────────┐' -ForegroundColor Magenta
Write-Host '  │   에이전트팀 만들기 과정 — 출발선 자동 점검·설치   │' -ForegroundColor Magenta
Write-Host '  └──────────────────────────────────────────────────┘' -ForegroundColor Magenta
Write-Info "스타터킷: $KIT"
if ($PretendMissing.Count) { Write-Warn "테스트 모드 — 없는 것으로 가정: $($PretendMissing -join ', ')" }

$script:PY = $null

if ($SlackOnly) {
    # 슬랙열쇠_넣기.bat — 설치는 이미 끝났다고 보고 슬랙 부분만 한다
    try { $Host.UI.RawUI.WindowTitle = '에이전트팀 만들기 — 슬랙 열쇠 넣기' } catch {}
    Write-Step '1/3 준비 확인 (파이썬 · 꾸러미 · 폴더)'
    Check-Python | Out-Null
    if (-not $script:PY) { Check-Pip | Out-Null }
    Check-PyPackages | Out-Null
    Check-Folders | Out-Null
    if (-not (Is-Ok 'python') -or -not (Is-Ok 'pypkg')) { Write-Warn '설치가 덜 끝났습니다. 환경점검.bat 을 먼저 실행하세요.' }
    Write-Step '2/3 슬랙 열쇠 넣기 · 연결 시험'
    Check-SlackEnv | Out-Null
    if ((Is-Ok 'slack') -and -not $Yes) {
        Write-Info '열쇠가 이미 들어 있습니다. 그대로 쓰려면 Enter, 새 열쇠로 바꾸려면 y.'
        if (Ask-YesNo '열쇠를 새로 넣을까요?' $false) { Fix-Slack -Force | Out-Null }
    } else { Fix-Slack | Out-Null }
    Test-SlackLive | Out-Null
    # 모양은 맞는데 슬랙이 거절하면 그 자리에서 다시 넣게 한다. 예전에는 다시 실행해도 묻지 않고 지나가 같은 ❌ 만 반복됐다.
    if ((Is-Ok 'slack') -and -not (Is-Ok 'slack-live') -and -not $Yes) {
        Write-Warn '열쇠가 슬랙에 통하지 않습니다. 바로 위 NG 줄이 어느 열쇠가 틀렸는지 알려 줍니다.'
        if (Ask-YesNo '지금 열쇠를 다시 넣을까요?' $true) { Fix-Slack -Force | Out-Null; Test-SlackLive | Out-Null }
    }
    Write-Step '3/3 슬랙 서버 첫 기동 · 자동시작 등록'
    Test-Server | Out-Null
    Enable-Autostart | Out-Null
} elseif ($MailOnly) {
    # 메일_연결.bat — 부록 B-2
    try { $Host.UI.RawUI.WindowTitle = '에이전트팀 만들기 — 메일 연결' } catch {}
    Write-Step '메일 연결 (부록 B-2 · 선택)'
    Check-Python | Out-Null
    if (-not $script:PY) { Check-Pip | Out-Null }
    Check-MailEnv | Out-Null
    Fix-Mail
    Test-MailLive
} else {
if ($SkipSlack) { Write-Info '이 프로그램은 묻지 않고 설치합니다. 사람이 할 일은 로그인 창이 뜨면 로그인하는 것뿐입니다.' }
else { Write-Info '이 프로그램은 묻지 않고 설치합니다. 사람이 할 일은 로그인과 슬랙 열쇠 붙여넣기뿐입니다.' }

Write-Step '0/6 준비 — 파워셸 실행 허용'
Fix-ExecutionPolicy | Out-Null

Write-Step '1/6 기본 확인'
Check-Internet | Out-Null
Check-Disk | Out-Null

Write-Step '2/6 프로그램 — 없으면 설치, 파이썬은 항상 3.14 로'
Check-Node | Out-Null
Check-Npm | Out-Null
Check-Git | Out-Null
Fix-Programs
Check-Python | Out-Null
Fix-Python
if (-not $script:PY) { Check-Pip | Out-Null }
Check-Claude | Out-Null
Fix-Claude
Check-ClaudeVersion | Out-Null
Fix-ClaudeVersion
Check-VSCode | Out-Null
Check-Chrome | Out-Null

Write-Step '3/6 Claude Code 로그인'
Check-ClaudeLogin | Out-Null
Fix-ClaudeLogin

Write-Step '4/6 파이썬 꾸러미'
Check-PyPackages | Out-Null
Fix-PyPackages

Write-Step '5/6 스타터킷 · 슬랙 열쇠 · 서버 첫 기동'
Check-Folders | Out-Null
Check-MyData | Out-Null
Check-SlackEnv | Out-Null
Fix-Slack | Out-Null
Test-SlackLive | Out-Null
Test-Server | Out-Null
Enable-Autostart | Out-Null

Write-Step '6/6 선택 항목 (메일 연결 · 네이버 블로그 로그인)'
Check-MailEnv | Out-Null
Fix-Mail
Test-MailLive
Check-NaverLogin | Out-Null
Fix-OptionalLogins
}

# ── 7. 최종 체크리스트 ───────────────────────────────────────
Write-Host ''
Write-Host '  ══════════════════ 체크리스트 ══════════════════' -ForegroundColor Magenta
$req = @($script:Results | Where-Object { $_.Group -ne '선택' })
$opt = @($script:Results | Where-Object { $_.Group -eq '선택' })
Write-Host '  [필수]' -ForegroundColor White
foreach ($r in $req) { $m = $NOM; $c = 'Red'; if ($r.Ok) { $m = $OKM; $c = 'Green' }; Write-Host "  $m $($r.Name)" -ForegroundColor $c; if (-not $r.Ok) { Write-Host "        └ $($r.Detail)" -ForegroundColor DarkGray; if ($r.Fix) { Write-Host "        └ 고치기: $($r.Fix)" -ForegroundColor Yellow } } }
Write-Host '  [선택]' -ForegroundColor White
foreach ($r in $opt) { $m = $WRN; $c = 'Yellow'; if ($r.Ok) { $m = $OKM; $c = 'Green' }; Write-Host "  $m $($r.Name)" -ForegroundColor $c }
$reqOk = @($req | Where-Object { $_.Ok }).Count
$optOk = @($opt | Where-Object { $_.Ok }).Count
Write-Host '  ─────────────────────────────────────────────────' -ForegroundColor Magenta
if ($reqOk -eq $req.Count) {
    Write-Host "  🎉 필수 $reqOk/$($req.Count) 전부 통과 · 선택 $optOk/$($opt.Count) — 출발 준비 완료! 창을 새로 열고 claude 를 부르세요." -ForegroundColor Green
} else {
    Write-Host "  필수 $reqOk/$($req.Count) 통과 · 선택 $optOk/$($opt.Count) — ❌ 표시된 것만 고치고 다시 실행하세요." -ForegroundColor Yellow
}
$slackLeft = @($req | Where-Object { -not $_.Ok -and $_.Id -in 'slack', 'slack-live', 'server' })
$otherLeft = @($req | Where-Object { -not $_.Ok -and $_.Id -notin 'slack', 'slack-live', 'server', 'autostart' })
if ($slackLeft.Count -and -not $otherLeft.Count -and -not $SlackOnly) {
    Write-Host '  👉 슬랙 줄만 ❌ 면 정상입니다. 교안 「슬랙 ①②」로 열쇠를 받은 뒤 아래 파일을 더블클릭하세요.' -ForegroundColor Cyan
    Write-Host "     $(Join-Path $KIT '슬랙열쇠_넣기.bat')" -ForegroundColor Cyan
}

try { Write-Report; Write-Info "결과 파일: $REPORT"; if (-not $NoBrowser) { Start-Process $REPORT } } catch { Write-Warn "HTML 저장 실패: $_" }
Write-Info ("소요 {0:n0}초" -f ((Get-Date) - $STARTED).TotalSeconds)

if (-not $NoPause) { $null = Read-Host '  창을 닫으려면 Enter' }
if ($reqOk -eq $req.Count) { exit 0 } else { exit 1 }
