# dev-setup: Windows 공통 유틸리티
# 사용법: . "$PSScriptRoot\_common.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:LOG_PREFIX = "[dev-setup]"

function Write-Status {
    param(
        [ValidateSet("OK", "INSTALL", "SKIP", "FAIL", "CHECK")]
        [string]$Status,
        [string]$Message
    )
    $colors = @{ OK = "Green"; INSTALL = "Cyan"; SKIP = "Yellow"; FAIL = "Red"; CHECK = "Gray" }
    Write-Host "[$Status] " -ForegroundColor $colors[$Status] -NoNewline
    Write-Host $Message
}

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Test-MinVersion {
    param(
        [string]$Command,
        [string]$VersionArg = "--version",
        [string]$MinVersion,
        [string]$VersionPattern = '(\d+\.\d+[\.\d]*)'
    )
    if (-not (Test-CommandExists $Command)) { return $false }
    try {
        $output = & $Command $VersionArg 2>&1 | Out-String
        if ($output -match $VersionPattern) {
            $current = [version]$Matches[1]
            $required = [version]$MinVersion
            return $current -ge $required
        }
    } catch {}
    return $false
}

function Install-WithWinget {
    param(
        [string]$PackageId,
        [string]$DisplayName
    )
    if (-not (Test-CommandExists "winget")) {
        Write-Status "FAIL" "winget을 사용할 수 없습니다"
        return $false
    }
    Write-Status "INSTALL" "$DisplayName 설치 중 (winget)..."
    try {
        winget install --id $PackageId --accept-source-agreements --accept-package-agreements --silent
        if ($LASTEXITCODE -eq 0) {
            Write-Status "OK" "$DisplayName 설치 완료"
            return $true
        }
    } catch {}
    Write-Status "FAIL" "$DisplayName 설치 실패"
    return $false
}

function Install-WithChoco {
    param(
        [string]$PackageName,
        [string]$DisplayName
    )
    if (-not (Test-CommandExists "choco")) {
        Write-Status "FAIL" "choco를 사용할 수 없습니다"
        return $false
    }
    Write-Status "INSTALL" "$DisplayName 설치 중 (choco)..."
    try {
        choco install $PackageName -y --no-progress
        if ($LASTEXITCODE -eq 0) {
            Write-Status "OK" "$DisplayName 설치 완료"
            return $true
        }
    } catch {}
    Write-Status "FAIL" "$DisplayName 설치 실패"
    return $false
}

function Add-ToPath {
    param([string]$Path)
    if ($env:PATH -notlike "*$Path*") {
        $env:PATH = "$Path;$env:PATH"
        [Environment]::SetEnvironmentVariable("PATH", "$Path;$([Environment]::GetEnvironmentVariable('PATH', 'User'))", "User")
        Write-Status "OK" "PATH에 추가: $Path"
    }
}

function Test-AdminPrivilege {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-PathEnv {
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$userPath;$machinePath"
}

# 전체 인수 저장
$script:AllArgs = $args

function Get-ProjectRoot {
    # --project-root 인수가 있으면 사용, 없으면 git root, 없으면 현재 디렉토리
    for ($i = 0; $i -lt $script:AllArgs.Count; $i++) {
        if ($script:AllArgs[$i] -eq "--project-root" -and $i + 1 -lt $script:AllArgs.Count) {
            return $script:AllArgs[$i + 1]
        }
    }
    try {
        $gitRoot = git rev-parse --show-toplevel 2>$null
        if ($gitRoot) { return $gitRoot }
    } catch {}
    return (Get-Location).Path
}

function Get-ThirdpartyDir {
    $root = Get-ProjectRoot
    $dir = Join-Path $root "thirdparty"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

# --check-only 인수 처리
$script:CheckOnly = $args -contains "--check-only"
