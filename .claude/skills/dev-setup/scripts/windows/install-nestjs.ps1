# dev-setup: NestJS 개발 환경 설치 (Windows)
# 설치 항목: Node.js LTS (18+), pnpm, @nestjs/cli, TypeScript

. "$PSScriptRoot\_common.ps1"

function Install-NestJsEnvironment {
    Write-Host "`n=== NestJS 개발 환경 설치 ===" -ForegroundColor Magenta

    # --- Node.js LTS ---
    Write-Status "CHECK" "Node.js 확인 중..."
    if (Test-MinVersion "node" "--version" "18.0") {
        $v = & node --version 2>&1
        Write-Status "SKIP" "Node.js 이미 설치됨: $v"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "Node.js 18+ 없음"
    } else {
        if (-not (Install-WithWinget "OpenJS.NodeJS.LTS" "Node.js LTS")) {
            Install-WithChoco "nodejs-lts" "Node.js LTS"
        }
        Refresh-PathEnv
    }

    # --- pnpm ---
    Write-Status "CHECK" "pnpm 확인 중..."
    if (Test-CommandExists "pnpm") {
        $v = & pnpm --version 2>&1
        Write-Status "SKIP" "pnpm 이미 설치됨: $v"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "pnpm 없음"
    } else {
        if (Test-CommandExists "npm") {
            Write-Status "INSTALL" "pnpm 설치 중 (npm)..."
            npm install -g pnpm
            Refresh-PathEnv
            if (Test-CommandExists "pnpm") {
                Write-Status "OK" "pnpm 설치 완료"
            } else {
                Write-Status "FAIL" "pnpm 설치 실패"
            }
        } else {
            Write-Status "FAIL" "npm이 없어 pnpm을 설치할 수 없습니다"
        }
    }

    # --- @nestjs/cli ---
    Write-Status "CHECK" "@nestjs/cli 확인 중..."
    if (Test-CommandExists "nest") {
        $v = & nest --version 2>&1 | Select-Object -First 1
        Write-Status "SKIP" "@nestjs/cli 이미 설치됨: $v"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "@nestjs/cli 없음"
    } else {
        if (Test-CommandExists "pnpm") {
            Write-Status "INSTALL" "@nestjs/cli 설치 중 (pnpm)..."
            pnpm add -g @nestjs/cli
            Refresh-PathEnv
            if (Test-CommandExists "nest") {
                Write-Status "OK" "@nestjs/cli 설치 완료"
            } else {
                Write-Status "FAIL" "@nestjs/cli 설치 실패"
            }
        } else {
            Write-Status "FAIL" "pnpm이 없어 @nestjs/cli를 설치할 수 없습니다"
        }
    }

    # --- TypeScript ---
    Write-Status "CHECK" "TypeScript 확인 중..."
    if (Test-CommandExists "tsc") {
        $v = & tsc --version 2>&1
        Write-Status "SKIP" "TypeScript 이미 설치됨: $v"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "TypeScript 없음"
    } else {
        if (Test-CommandExists "pnpm") {
            Write-Status "INSTALL" "TypeScript 설치 중 (pnpm)..."
            pnpm add -g typescript
            Refresh-PathEnv
            if (Test-CommandExists "tsc") {
                Write-Status "OK" "TypeScript 설치 완료"
            } else {
                Write-Status "FAIL" "TypeScript 설치 실패"
            }
        } else {
            Write-Status "FAIL" "pnpm이 없어 TypeScript를 설치할 수 없습니다"
        }
    }

    # --- 검증 요약 ---
    Write-Host "`n=== 설치 검증 ===" -ForegroundColor Magenta
    foreach ($entry in @("node --version", "pnpm --version", "tsc --version")) {
        $c = $entry.Split(" ")[0]
        $a = $entry.Split(" ")[1]
        if (Test-CommandExists $c) {
            $v = & $c $a 2>&1 | Select-Object -First 1
            Write-Status "OK" "${c}: $v"
        } else {
            Write-Status "FAIL" "${c}: 찾을 수 없음"
        }
    }
    if (Test-CommandExists "nest") {
        $v = & nest --version 2>&1 | Select-Object -First 1
        Write-Status "OK" "nest: $v"
    } else {
        Write-Status "FAIL" "nest: 찾을 수 없음"
    }
}

Install-NestJsEnvironment
