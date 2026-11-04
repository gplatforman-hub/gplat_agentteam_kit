<#
  connect.ps1 — 네이버 캘린더 연결 (캘린더_연결.bat 이 부른다)

  1) 이미 연결돼 있으면 바꿀지 묻는다 (그냥 Enter = 그대로 두고 확인만)
  2) 메일을 네이버로 연결해 두었으면 그 아이디·앱 비밀번호를 같이 쓸지 묻는다
  3) 아니면 아이디와 앱 비밀번호(별표)를 받아 naver-calendar\.env 에 BOM 없이 저장한다
  4) cal_check.py 로 실제로 로그인해 캘린더 목록과 이번 주 일정 수를 본다 (읽기만)

  🔒 비밀번호는 화면·기록 어디에도 찍지 않는다.
#>
param([switch]$NoPause)

$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = '에이전트팀 만들기 — 네이버 캘린더 연결' } catch {}
$HERE = Split-Path -Parent $MyInvocation.MyCommand.Path
$KIT = Split-Path -Parent $HERE
$envf = Join-Path $HERE '.env'
$mailEnv = Join-Path $KIT 'mail\.env'

function Read-EnvFile([string]$Path) {
    $vals = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $vals }
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $l = $line -replace '^﻿', ''
        if ($l.Trim().StartsWith('#') -or $l -notmatch '=') { continue }
        $k, $v = $l -split '=', 2
        $vals[$k.Trim().ToUpper()] = $v.Trim()
    }
    return $vals
}

function Done {
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host '창을 닫으려면 Enter') }
    exit $script:code
}

function Run-Check {
    Write-Host ''
    Write-Host '▶ 네이버 캘린더에 실제로 로그인해 봅니다 (읽기만 · 비밀번호는 화면에 나오지 않습니다)' -ForegroundColor Magenta
    & py -3 (Join-Path $HERE 'cal_check.py')
    $script:code = $LASTEXITCODE
    if ($script:code -eq 0) {
        # 직원용 스킬을 .claude\skills\naver-calendar 에 넣는다 (Claude 는 .claude 를 못 고치므로 여기서)
        $src = Join-Path $HERE 'skill\SKILL.md'
        $dstDir = Join-Path $KIT '.claude\skills\naver-calendar'
        try {
            New-Item -ItemType Directory -Force $dstDir | Out-Null
            Copy-Item -LiteralPath $src -Destination (Join-Path $dstDir 'SKILL.md') -Force
            Write-Host '  직원용 스킬을 .claude\skills\naver-calendar 에 넣었습니다'
        } catch { Write-Host "  ! 스킬 복사 실패: $_" -ForegroundColor Yellow }
        Write-Host '  ✅ 연결됐습니다. Code 탭은 새 세션, 슬랙은 새 대화 를 보낸 뒤 「이번 주 네이버 캘린더 일정 알려 줘」 처럼 말하면 됩니다.' -ForegroundColor Green
    } else {
        Write-Host '  ❌ 위 줄의 → 뒤 안내대로 고친 뒤 캘린더_연결.bat 을 다시 실행하세요.' -ForegroundColor Yellow
    }
}

$script:code = 1
Write-Host ''
Write-Host '▶ 네이버 캘린더 연결 (부록 · 선택)' -ForegroundColor Magenta
Write-Host '   필요한 것: 네이버 「애플리케이션 비밀번호」 — 내정보 → 보안설정 → 2단계 인증 관리 → 애플리케이션 비밀번호 생성'
Write-Host '   연습은 개인 계정으로 합니다.'

# 1) 이미 연결돼 있으면
$cur = Read-EnvFile $envf
if ($cur['NAVER_CAL_USER'] -and $cur['NAVER_CAL_APP_PASSWORD']) {
    $ans = (Read-Host "  ? 지금 $($cur['NAVER_CAL_USER']) 이(가) 연결돼 있습니다. 다른 계정으로 바꿀까요? (y = 바꾸기 / 그냥 Enter = 그대로)").Trim().ToLower()
    if ($ans -ne 'y') { Run-Check; Done }
}

$user = ''; $pw = ''
# 2) 메일을 네이버로 연결해 두었으면 같이 쓰기
$mail = Read-EnvFile $mailEnv
if ($mail['MAIL_PROVIDER'] -eq 'naver' -and $mail['MAIL_USER'] -and $mail['MAIL_APP_PASSWORD']) {
    $ans = (Read-Host "  ? 메일에 연결한 네이버 계정 $($mail['MAIL_USER']) 의 앱 비밀번호를 같이 쓸까요? (y = 같이 / 그냥 Enter = 새로 넣기)").Trim().ToLower()
    if ($ans -eq 'y') { $user = $mail['MAIL_USER']; $pw = $mail['MAIL_APP_PASSWORD'] }
}

# 3) 새로 받기
if (-not $user) {
    while ($true) {
        $user = (Read-Host '  ? 네이버 아이디 (예: hong 또는 hong@naver.com · 나중에 하려면 s)').Trim().Trim('"').Trim("'")
        if ($user.ToLower() -eq 's') { Write-Host '  캘린더는 나중에.'; $script:code = 0; Done }
        if ($user -match '^[A-Za-z0-9._-]+(@naver\.com)?$') { break }
        Write-Host '  ! 네이버 아이디만, 또는 아이디@naver.com 으로 적어 주세요' -ForegroundColor Yellow
    }
    while ($true) {
        $s = Read-Host '  ? 애플리케이션 비밀번호 12자리 — 붙여넣고 Enter (마우스 오른쪽 클릭 = 붙여넣기 · 나중에 하려면 s)' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
        try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $pw = ($pw.Trim().Trim('"').Trim("'")) -replace '\s', ''
        if ($pw.ToLower() -eq 's') { Write-Host '  캘린더는 나중에.'; $script:code = 0; Done }
        if ($pw.Length -ge 8) { break }
        Write-Host '  ! 너무 짧습니다. 애플리케이션 비밀번호를 다시 붙여넣으세요' -ForegroundColor Yellow
    }
}

$body = "# 네이버 캘린더 열쇠 — 캘린더_연결.bat 이 $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm')) 에 저장. 비밀번호와 같습니다. 남에게 주지 마세요.`n" +
        "NAVER_CAL_USER=$user`nNAVER_CAL_APP_PASSWORD=$pw`n"
try {
    [IO.File]::WriteAllText($envf, $body, (New-Object System.Text.UTF8Encoding($false)))   # BOM 없이
    Write-Host '  naver-calendar\.env 저장됨'
} catch {
    Write-Host "  ! naver-calendar\.env 저장 실패: $_" -ForegroundColor Yellow
    Done
}
$pw = $null; $body = $null
Run-Check
Done
