# dev-setup: Spring Boot 개발 환경 설치 (Windows)
# 설치 항목: JDK 17 (Microsoft OpenJDK), JAVA_HOME 설정, Gradle wrapper 확인

$script:_myArgs = $args
. "$PSScriptRoot\_common.ps1"
# dot-source 후 $args가 소실되므로 재설정
$script:AllArgs = $script:_myArgs
$script:CheckOnly = $script:_myArgs -contains "--check-only"

# 설치 모드일 때만 관리자 권한 승격 요청 (--check-only 시에는 불필요)
if (-not $script:CheckOnly) {
    Request-AdminElevation
}

function Find-JdkInstallPath {
    # winget list에서 실제 설치 경로 확인 시도
    if (Test-CommandExists "winget") {
        try {
            $wingetOutput = winget list --id Microsoft.OpenJDK.17 2>&1 | Out-String
            if ($wingetOutput -match 'Microsoft\.OpenJDK\.17') {
                Write-Status "CHECK" "winget에서 OpenJDK 17 설치 확인됨"
            }
        } catch {}
    }

    # 파일시스템에서 실제 경로 탐색
    $candidates = @(
        "${env:ProgramFiles}\Microsoft\jdk-17*",
        "${env:ProgramFiles}\Eclipse Adoptium\jdk-17*",
        "${env:ProgramFiles}\Java\jdk-17*"
    )
    foreach ($pattern in $candidates) {
        $found = Get-Item $pattern -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending |
                 Select-Object -First 1
        if ($found) { return $found }
    }
    return $null
}

function Remove-OldJdkFromPath {
    param([string]$Scope)  # "Machine" or "User"
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", $Scope)
    if (-not $currentPath) { return }

    $oldPatterns = @('*\jdk1.8*', '*\jdk-1.8*', '*\jre1.8*', '*\Java\jdk1.8*')
    $entries = $currentPath -split ';'
    $cleaned = @()
    $removed = @()
    foreach ($entry in $entries) {
        $shouldRemove = $false
        foreach ($pattern in $oldPatterns) {
            if ($entry -like $pattern) {
                $shouldRemove = $true
                break
            }
        }
        if ($shouldRemove) {
            $removed += $entry
        } else {
            $cleaned += $entry
        }
    }
    if ($removed.Count -gt 0) {
        $newPath = ($cleaned | Where-Object { $_ -ne '' }) -join ';'
        [Environment]::SetEnvironmentVariable("PATH", $newPath, $Scope)
        foreach ($r in $removed) {
            Write-Status "OK" "PATH에서 이전 JDK 제거 ($Scope): $r"
        }
    }
}

function Install-SpringBootEnvironment {
    Write-Host "`n=== Spring Boot 개발 환경 설치 ===" -ForegroundColor Magenta

    # --- JDK 17 ---
    Write-Status "CHECK" "JDK 17 확인 중..."
    $hasJava17 = $false
    if (Test-CommandExists "java") {
        try { $javaVer = & java -version 2>&1 | Out-String } catch { $javaVer = "$_" }
        if ($javaVer -match '(?:version "17|openjdk version "17)') {
            $hasJava17 = $true
        }
    }

    if ($hasJava17) {
        Write-Status "SKIP" "JDK 17 이미 설치됨"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "JDK 17 없음"
    } else {
        if (-not (Install-WithWinget "Microsoft.OpenJDK.17" "Microsoft OpenJDK 17")) {
            Install-WithChoco "microsoft-openjdk17" "Microsoft OpenJDK 17"
        }
        Refresh-PathEnv
    }

    # --- JAVA_HOME 설정 (Machine 스코프) ---
    Write-Status "CHECK" "JAVA_HOME 확인 중..."
    # Machine 스코프 우선 확인, 없으면 User 스코프도 확인
    $javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if (-not $javaHome) {
        $javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
    }
    if ($javaHome -and (Test-Path $javaHome)) {
        Write-Status "SKIP" "JAVA_HOME 이미 설정됨: $javaHome"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "JAVA_HOME 미설정"
    } else {
        $found = Find-JdkInstallPath
        if ($found) {
            # Machine 스코프로 JAVA_HOME 설정 (관리자 권한 활용)
            [Environment]::SetEnvironmentVariable("JAVA_HOME", $found.FullName, "Machine")
            $env:JAVA_HOME = $found.FullName
            Write-Status "OK" "JAVA_HOME 설정 (Machine): $($found.FullName)"

            # 이전 JDK 1.8 경로 정리
            Remove-OldJdkFromPath -Scope "Machine"
            Remove-OldJdkFromPath -Scope "User"

            # Machine PATH에 %JAVA_HOME%\bin 추가
            $jdkBin = "$($found.FullName)\bin"
            $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            if ($machinePath -notlike "*$jdkBin*") {
                [Environment]::SetEnvironmentVariable("PATH", "$jdkBin;$machinePath", "Machine")
                Write-Status "OK" "Machine PATH에 추가: $jdkBin"
            }

            # 현재 세션에도 반영
            $env:PATH = "$jdkBin;$env:PATH"
            Refresh-PathEnv

            # 다른 프로세스(Explorer, 새 터미널 등)에 환경변수 변경 브로드캐스트
            Send-SettingChange
        } else {
            Write-Status "FAIL" "JDK 17 경로를 찾을 수 없습니다. 수동으로 JAVA_HOME을 설정하세요."
        }
    }

    # --- Gradle ---
    Write-Status "CHECK" "Gradle 확인 중..."
    if (Test-CommandExists "gradle") {
        try { $v = & gradle --version 2>&1 | Out-String } catch { $v = "$_" }
        if ($v -match '(\d+\.\d+[\.\d]*)') {
            Write-Status "SKIP" "Gradle 이미 설치됨: $($Matches[1])"
        } else {
            Write-Status "SKIP" "Gradle 이미 설치됨"
        }
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "Gradle 없음"
    } else {
        if (-not (Install-WithWinget "Gradle.Gradle" "Gradle")) {
            Install-WithChoco "gradle" "Gradle"
        }
        Refresh-PathEnv
    }

    # --- 빌드 검증 ---
    if (-not $script:CheckOnly) {
        Write-Host "`n=== 빌드 검증 ===" -ForegroundColor Magenta
        $skillRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Test-BuildSample -Platform "springboot" -SkillRoot $skillRoot
    }

    # --- 검증 요약 ---
    Write-Host "`n=== 설치 검증 ===" -ForegroundColor Magenta
    if (Test-CommandExists "java") {
        try { $v = & java -version 2>&1 | Select-Object -First 1 } catch { $v = "$_" }
        $vStr = "$v"
        if ($vStr -match '17[\.\d]') {
            Write-Status "OK" "java: $v"
        } else {
            Write-Status "FAIL" "java: JDK 17이 아닙니다 — $v"
        }
    } else {
        Write-Status "FAIL" "java: 찾을 수 없음"
    }
    if (Test-CommandExists "javac") {
        try { $v = & javac -version 2>&1 | Select-Object -First 1 } catch { $v = "$_" }
        Write-Status "OK" "javac: $v"
    } else {
        Write-Status "FAIL" "javac: 찾을 수 없음"
    }
    # Machine 스코프 우선, User 스코프 폴백
    $jh = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if (-not $jh) { $jh = [Environment]::GetEnvironmentVariable("JAVA_HOME", "User") }
    if ($jh -and (Test-Path $jh)) {
        Write-Status "OK" "JAVA_HOME: $jh"
    } elseif ($jh) {
        Write-Status "FAIL" "JAVA_HOME: 경로 존재하지 않음 — $jh"
    } else {
        Write-Status "FAIL" "JAVA_HOME: 미설정"
    }
}

Install-SpringBootEnvironment
