# dev-setup: Go 개발 환경 설치 (Windows)
# 설치 항목: Go toolchain (1.21+), golangci-lint, GOPATH 설정

. "$PSScriptRoot\_common.ps1"

function Install-GoEnvironment {
    Write-Host "`n=== Go 개발 환경 설치 ===" -ForegroundColor Magenta

    # --- Go toolchain ---
    Write-Status "CHECK" "Go 확인 중..."
    if (Test-MinVersion "go" "version" "1.21") {
        $v = & go version 2>&1
        Write-Status "SKIP" "Go 이미 설치됨: $v"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "Go 1.21+ 없음"
    } else {
        if (-not (Install-WithWinget "GoLang.Go" "Go")) {
            Install-WithChoco "golang" "Go"
        }
        Refresh-PathEnv
    }

    # --- GOPATH 설정 ---
    Write-Status "CHECK" "GOPATH 확인 중..."
    $gopath = [Environment]::GetEnvironmentVariable("GOPATH", "User")
    if ($gopath) {
        Write-Status "SKIP" "GOPATH 이미 설정됨: $gopath"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "GOPATH 미설정"
    } else {
        $defaultGopath = "$env:USERPROFILE\go"
        [Environment]::SetEnvironmentVariable("GOPATH", $defaultGopath, "User")
        $env:GOPATH = $defaultGopath
        Add-ToPath "$defaultGopath\bin"
        Write-Status "OK" "GOPATH 설정: $defaultGopath"
    }

    # --- golangci-lint ---
    Write-Status "CHECK" "golangci-lint 확인 중..."
    if (Test-CommandExists "golangci-lint") {
        $v = & golangci-lint --version 2>&1 | Select-Object -First 1
        Write-Status "SKIP" "golangci-lint 이미 설치됨: $v"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "golangci-lint 없음"
    } else {
        if (Test-CommandExists "go") {
            Write-Status "INSTALL" "golangci-lint 설치 중 (go install)..."
            go install github.com/golangci-lint/golangci-lint/cmd/golangci-lint@latest
            Refresh-PathEnv
            if (Test-CommandExists "golangci-lint") {
                Write-Status "OK" "golangci-lint 설치 완료"
            } else {
                # GOPATH/bin이 PATH에 없는 경우 직접 추가
                $gopathBin = if ($env:GOPATH) { "$env:GOPATH\bin" } else { "$env:USERPROFILE\go\bin" }
                Add-ToPath $gopathBin
                if (Test-Path "$gopathBin\golangci-lint.exe") {
                    Write-Status "OK" "golangci-lint 설치 완료 ($gopathBin)"
                } else {
                    Write-Status "FAIL" "golangci-lint 설치 실패"
                }
            }
        } else {
            Write-Status "FAIL" "Go가 설치되지 않아 golangci-lint를 설치할 수 없습니다"
        }
    }

    # --- 검증 요약 ---
    Write-Host "`n=== 설치 검증 ===" -ForegroundColor Magenta
    if (Test-CommandExists "go") {
        $v = & go version 2>&1
        Write-Status "OK" "go: $v"
    } else {
        Write-Status "FAIL" "go: 찾을 수 없음"
    }
    if (Test-CommandExists "golangci-lint") {
        $v = & golangci-lint --version 2>&1 | Select-Object -First 1
        Write-Status "OK" "golangci-lint: $v"
    } else {
        Write-Status "FAIL" "golangci-lint: 찾을 수 없음"
    }
    $gp = [Environment]::GetEnvironmentVariable("GOPATH", "User")
    if ($gp) {
        Write-Status "OK" "GOPATH: $gp"
    } else {
        Write-Status "FAIL" "GOPATH: 미설정"
    }
}

Install-GoEnvironment
