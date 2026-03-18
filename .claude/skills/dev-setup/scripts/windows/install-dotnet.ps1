# dev-setup: .NET 개발 환경 설치 (Windows)
# 설치 항목: .NET SDK 8.0, dotnet-ef (EF Core tools)

. "$PSScriptRoot\_common.ps1"

function Install-DotNetEnvironment {
    Write-Host "`n=== .NET 개발 환경 설치 ===" -ForegroundColor Magenta

    # --- .NET SDK 8.0 ---
    Write-Status "CHECK" ".NET SDK 확인 중..."
    $hasNet8 = $false
    if (Test-CommandExists "dotnet") {
        $sdks = & dotnet --list-sdks 2>&1 | Out-String
        if ($sdks -match '8\.') {
            $hasNet8 = $true
        }
    }

    if ($hasNet8) {
        $v = & dotnet --version 2>&1
        Write-Status "SKIP" ".NET SDK 8.x 이미 설치됨: $v"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" ".NET SDK 8.0 없음"
    } else {
        if (-not (Install-WithWinget "Microsoft.DotNet.SDK.8" ".NET SDK 8.0")) {
            Install-WithChoco "dotnet-sdk" ".NET SDK 8.0"
        }
        Refresh-PathEnv
    }

    # --- dotnet-ef ---
    Write-Status "CHECK" "dotnet-ef 확인 중..."
    $hasEf = $false
    if (Test-CommandExists "dotnet") {
        $tools = & dotnet tool list --global 2>&1 | Out-String
        if ($tools -match 'dotnet-ef') {
            $hasEf = $true
        }
    }

    if ($hasEf) {
        Write-Status "SKIP" "dotnet-ef 이미 설치됨"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "dotnet-ef 없음"
    } else {
        if (Test-CommandExists "dotnet") {
            Write-Status "INSTALL" "dotnet-ef 설치 중..."
            dotnet tool install --global dotnet-ef
            if ($LASTEXITCODE -eq 0) {
                Refresh-PathEnv
                # dotnet tools 경로 추가
                $dotnetToolsPath = "$env:USERPROFILE\.dotnet\tools"
                if (Test-Path $dotnetToolsPath) {
                    Add-ToPath $dotnetToolsPath
                }
                Write-Status "OK" "dotnet-ef 설치 완료"
            } else {
                # 이미 설치된 경우 업데이트 시도
                dotnet tool update --global dotnet-ef
                if ($LASTEXITCODE -eq 0) {
                    Write-Status "OK" "dotnet-ef 업데이트 완료"
                } else {
                    Write-Status "FAIL" "dotnet-ef 설치/업데이트 실패"
                }
            }
        } else {
            Write-Status "FAIL" ".NET SDK가 없어 dotnet-ef를 설치할 수 없습니다"
        }
    }

    # --- 검증 요약 ---
    Write-Host "`n=== 설치 검증 ===" -ForegroundColor Magenta
    if (Test-CommandExists "dotnet") {
        $v = & dotnet --version 2>&1
        Write-Status "OK" "dotnet: $v"
        Write-Host ""
        Write-Host "  설치된 SDK 목록:" -ForegroundColor Gray
        & dotnet --list-sdks 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    } else {
        Write-Status "FAIL" "dotnet: 찾을 수 없음"
    }
    $toolsPath = "$env:USERPROFILE\.dotnet\tools\dotnet-ef.exe"
    if (Test-Path $toolsPath) {
        $v = & dotnet-ef --version 2>&1 | Select-Object -First 1
        Write-Status "OK" "dotnet-ef: $v"
    } elseif (Test-CommandExists "dotnet-ef") {
        $v = & dotnet-ef --version 2>&1 | Select-Object -First 1
        Write-Status "OK" "dotnet-ef: $v"
    } else {
        Write-Status "FAIL" "dotnet-ef: 찾을 수 없음"
    }
}

Install-DotNetEnvironment
