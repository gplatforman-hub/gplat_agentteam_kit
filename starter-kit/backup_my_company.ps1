<#
  Learner backup tool.
  Backs up authored work only. Never includes .env, tokens, login profiles, or dependencies.
  ASCII source is intentional for Windows PowerShell 5 compatibility.
#>
[CmdletBinding()]
param([string]$OutputDir = '')

$ErrorActionPreference = 'Stop'
$kit = [IO.Path]::GetFullPath($PSScriptRoot)

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $kitParent = Split-Path -Parent $kit
    $candidateRoot = Split-Path -Parent $kitParent
    if ((Split-Path -Leaf $kitParent) -eq '01_KIT') {
        $OutputDir = Join-Path $candidateRoot '04_LEARNER_BACKUP'
    } else {
        $OutputDir = Join-Path $kit 'backup'
    }
}

$output = [IO.Path]::GetFullPath($OutputDir)
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$zip = Join-Path $output "My_AI_Company_$stamp.zip"
$stage = Join-Path ([IO.Path]::GetTempPath()) ("wd-backup-" + [guid]::NewGuid().ToString('N'))

$items = @(
    @{ Source = (Join-Path $kit 'workspace'); Destination = 'workspace' },
    @{ Source = (Join-Path $kit '.claude\agents'); Destination = '.claude\agents' },
    @{ Source = (Join-Path $kit '.claude\skills'); Destination = '.claude\skills' },
    @{ Source = (Join-Path $kit 'slack-server\personas.py'); Destination = 'slack-server\personas.py' },
    @{ Source = (Join-Path $kit 'slack-server\agent_channels.py'); Destination = 'slack-server\agent_channels.py' },
    @{ Source = (Join-Path $kit 'README.md'); Destination = 'README.md' }
)

$null = New-Item -ItemType Directory -Path $stage -Force
$null = New-Item -ItemType Directory -Path $output -Force

try {
    foreach ($item in $items) {
        if (-not (Test-Path -LiteralPath $item.Source)) { continue }
        $target = Join-Path $stage $item.Destination
        $parent = Split-Path -Parent $target
        if ($parent) { $null = New-Item -ItemType Directory -Path $parent -Force }
        Copy-Item -LiteralPath $item.Source -Destination $target -Recurse -Force
    }

    @(
        'RESTORE MY AI COMPANY',
        '1. Install a clean starter-kit on the new PC.',
        '2. Close the Slack server.',
        '3. Extract this ZIP.',
        '4. Copy workspace and .claude into the installed starter-kit; allow overwrite.',
        '5. Recreate slack-server/.env and sign in again. Secrets and login state are intentionally not backed up.'
    ) | Set-Content -LiteralPath (Join-Path $stage 'RESTORE.txt') -Encoding ASCII

    $forbidden = @(Get-ChildItem -LiteralPath $stage -File -Force -Recurse | Where-Object {
        $_.Name -in @('.env', '.agent_session.json', '.naver-state.json') -or $_.Extension -eq '.pyc'
    })
    if ($forbidden.Count -gt 0) { throw 'Backup safety check failed: forbidden private file found.' }

    $archiveItems = @(Get-ChildItem -LiteralPath $stage -Force | Select-Object -ExpandProperty FullName)
    if ($archiveItems.Count -eq 0) { throw 'No authored files were found to back up.' }
    Compress-Archive -LiteralPath $archiveItems -DestinationPath $zip -CompressionLevel Optimal
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    $count = @(Get-ChildItem -LiteralPath $stage -File -Force -Recurse).Count
    Write-Host ''
    Write-Host 'Backup succeeded.' -ForegroundColor Green
    Write-Host "Files: $count"
    Write-Host "ZIP: $zip"
    Write-Host "SHA-256: $hash"
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
