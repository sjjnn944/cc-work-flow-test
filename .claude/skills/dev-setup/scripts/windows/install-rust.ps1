# dev-setup: Rust 개발 환경 설치 (Windows)
# 설치 항목: rustup, rustc, cargo, clippy, rustfmt

. "$PSScriptRoot\_common.ps1"

function Install-RustEnvironment {
    Write-Host "`n=== Rust 개발 환경 설치 ===" -ForegroundColor Magenta

    # --- MSVC Build Tools 확인 (Rust 링커 의존성) ---
    Write-Status "CHECK" "MSVC Build Tools 확인 중..."
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $hasMsvc = (Test-Path $vsWhere) -and (& $vsWhere -products * -requires Microsoft.VisualCpp.Tools.HostX64.TargetX64 2>$null)
    if ($hasMsvc) {
        Write-Status "OK" "MSVC Build Tools 감지됨"
    } else {
        Write-Status "FAIL" "MSVC Build Tools가 없습니다. install-cpp.ps1를 먼저 실행하세요."
        if (-not $script:CheckOnly) {
            Write-Host "  계속 진행합니까? (Y/N) " -NoNewline
            $answer = Read-Host
            if ($answer -ne "Y" -and $answer -ne "y") { return }
        }
    }

    # --- rustup / rustc ---
    Write-Status "CHECK" "rustup 확인 중..."
    if (Test-CommandExists "rustup") {
        $v = & rustc --version 2>&1
        Write-Status "SKIP" "rustup 이미 설치됨 ($v)"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "rustup 없음"
    } else {
        Write-Status "INSTALL" "rustup 다운로드 및 설치 중..."
        $rustupInit = "$env:TEMP\rustup-init.exe"
        try {
            Invoke-WebRequest -Uri "https://win.rustup.rs/x86_64" -OutFile $rustupInit -UseBasicParsing
            & $rustupInit -y --no-modify-path
            if ($LASTEXITCODE -eq 0) {
                Add-ToPath "$env:USERPROFILE\.cargo\bin"
                Refresh-PathEnv
                Write-Status "OK" "rustup 설치 완료"
            } else {
                Write-Status "FAIL" "rustup-init.exe 실행 실패"
                return
            }
        } catch {
            Write-Status "FAIL" "rustup 다운로드 실패: $_"
            return
        } finally {
            Remove-Item $rustupInit -ErrorAction SilentlyContinue
        }
    }

    # --- clippy ---
    Write-Status "CHECK" "clippy 확인 중..."
    if (Test-CommandExists "cargo" -and (& rustup component list 2>&1 | Select-String "clippy.*installed")) {
        Write-Status "SKIP" "clippy 이미 설치됨"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "clippy 없음"
    } else {
        if (Test-CommandExists "rustup") {
            Write-Status "INSTALL" "clippy 추가 중..."
            rustup component add clippy
            Write-Status "OK" "clippy 추가 완료"
        }
    }

    # --- rustfmt ---
    Write-Status "CHECK" "rustfmt 확인 중..."
    if (Test-CommandExists "rustfmt") {
        Write-Status "SKIP" "rustfmt 이미 설치됨"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "rustfmt 없음"
    } else {
        if (Test-CommandExists "rustup") {
            Write-Status "INSTALL" "rustfmt 추가 중..."
            rustup component add rustfmt
            Write-Status "OK" "rustfmt 추가 완료"
        }
    }

    # --- 검증 요약 ---
    Write-Host "`n=== 설치 검증 ===" -ForegroundColor Magenta
    foreach ($cmd in @("rustc --version", "cargo --version", "rustfmt --version")) {
        $c = $cmd.Split(" ")[0]
        $a = $cmd.Split(" ")[1]
        if (Test-CommandExists $c) {
            $v = & $c $a 2>&1 | Select-Object -First 1
            Write-Status "OK" "${c}: $v"
        } else {
            Write-Status "FAIL" "${c}: 찾을 수 없음"
        }
    }
    if (Test-CommandExists "cargo") {
        $clippy = & rustup component list 2>&1 | Select-String "clippy.*installed"
        if ($clippy) { Write-Status "OK" "clippy: 설치됨" } else { Write-Status "FAIL" "clippy: 없음" }
    }
}

Install-RustEnvironment
