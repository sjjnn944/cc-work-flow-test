# dev-setup: Django 개발 환경 설치 (Windows)
# 설치 항목: Python 3.11+, poetry

. "$PSScriptRoot\_common.ps1"

function Install-DjangoEnvironment {
    Write-Host "`n=== Django 개발 환경 설치 ===" -ForegroundColor Magenta

    # --- Python 3.11+ ---
    Write-Status "CHECK" "Python 확인 중..."
    if (Test-MinVersion "python" "--version" "3.11") {
        $v = & python --version 2>&1
        Write-Status "SKIP" "Python 이미 설치됨: $v"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "Python 3.11+ 없음"
    } else {
        if (-not (Install-WithWinget "Python.Python.3.11" "Python 3.11")) {
            Install-WithChoco "python311" "Python 3.11"
        }
        Refresh-PathEnv
        # pip 업그레이드
        if (Test-CommandExists "python") {
            Write-Status "INSTALL" "pip 업그레이드 중..."
            python -m pip install --upgrade pip --quiet
            Write-Status "OK" "pip 업그레이드 완료"
        }
    }

    # --- poetry ---
    Write-Status "CHECK" "poetry 확인 중..."
    if (Test-CommandExists "poetry") {
        $v = & poetry --version 2>&1 | Select-Object -First 1
        Write-Status "SKIP" "poetry 이미 설치됨: $v"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "poetry 없음"
    } else {
        if (Test-CommandExists "pip") {
            Write-Status "INSTALL" "poetry 설치 중 (pip)..."
            pip install poetry --quiet
            Refresh-PathEnv
            # pip install이 PATH에 없는 경우 Scripts 경로 추가
            if (-not (Test-CommandExists "poetry")) {
                $pythonScripts = & python -c "import sysconfig; print(sysconfig.get_path('scripts'))" 2>&1
                if ($pythonScripts -and (Test-Path $pythonScripts)) {
                    Add-ToPath $pythonScripts
                }
            }
            if (Test-CommandExists "poetry") {
                Write-Status "OK" "poetry 설치 완료"
            } else {
                Write-Status "FAIL" "poetry 설치 실패. PATH를 확인하세요."
            }
        } else {
            Write-Status "FAIL" "pip이 없어 poetry를 설치할 수 없습니다"
        }
    }

    # --- Django (선택적 전역 설치 안내) ---
    Write-Status "CHECK" "Django 설치 방식 안내..."
    Write-Host "  Django는 프로젝트별로 poetry를 통해 설치하세요:" -ForegroundColor Gray
    Write-Host "  > poetry new myproject && cd myproject && poetry add django" -ForegroundColor Gray

    # ═══════════════════════════════════════
    # 정적 분석 도구 설치
    # ═══════════════════════════════════════

    # --- ruff ---
    Write-Status "CHECK" "ruff 확인 중..."
    if (Test-CommandExists "ruff") {
        Write-Status "SKIP" "ruff 이미 설치됨"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "ruff 없음"
    } else {
        Write-Status "INSTALL" "ruff 설치 중..."
        python -m pip install ruff 2>&1 | Out-Null
        Write-Status "OK" "ruff 설치 완료"
    }

    # --- mypy ---
    Write-Status "CHECK" "mypy 확인 중..."
    if (Test-CommandExists "mypy") {
        Write-Status "SKIP" "mypy 이미 설치됨"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "mypy 없음"
    } else {
        Write-Status "INSTALL" "mypy 설치 중..."
        python -m pip install mypy 2>&1 | Out-Null
        Write-Status "OK" "mypy 설치 완료"
    }

    # --- Black ---
    Write-Status "CHECK" "Black 확인 중..."
    if (Test-CommandExists "black") {
        Write-Status "SKIP" "Black 이미 설치됨"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "Black 없음"
    } else {
        Write-Status "INSTALL" "Black 설치 중..."
        python -m pip install black 2>&1 | Out-Null
        Write-Status "OK" "Black 설치 완료"
    }

    # --- 검증 요약 ---
    Write-Host "`n=== 설치 검증 ===" -ForegroundColor Magenta
    if (Test-CommandExists "python") {
        $v = & python --version 2>&1
        Write-Status "OK" "python: $v"
    } else {
        Write-Status "FAIL" "python: 찾을 수 없음"
    }
    if (Test-CommandExists "pip") {
        $v = & pip --version 2>&1 | Select-Object -First 1
        Write-Status "OK" "pip: $v"
    } else {
        Write-Status "FAIL" "pip: 찾을 수 없음"
    }
    if (Test-CommandExists "poetry") {
        $v = & poetry --version 2>&1 | Select-Object -First 1
        Write-Status "OK" "poetry: $v"
    } else {
        Write-Status "FAIL" "poetry: 찾을 수 없음"
    }
    if (Test-CommandExists "ruff") {
        $v = & ruff --version 2>&1 | Select-Object -First 1
        Write-Status "OK" "ruff: $v"
    } else {
        Write-Status "FAIL" "ruff: 찾을 수 없음"
    }
    if (Test-CommandExists "mypy") {
        $v = & mypy --version 2>&1 | Select-Object -First 1
        Write-Status "OK" "mypy: $v"
    } else {
        Write-Status "FAIL" "mypy: 찾을 수 없음"
    }
    if (Test-CommandExists "black") {
        $v = & black --version 2>&1 | Select-Object -First 1
        Write-Status "OK" "black: $v"
    } else {
        Write-Status "FAIL" "black: 찾을 수 없음"
    }
}

Install-DjangoEnvironment
