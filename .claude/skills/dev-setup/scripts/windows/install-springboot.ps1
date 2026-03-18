# dev-setup: Spring Boot 개발 환경 설치 (Windows)
# 설치 항목: JDK 17 (Microsoft OpenJDK), JAVA_HOME 설정, Gradle wrapper 확인

. "$PSScriptRoot\_common.ps1"

function Install-SpringBootEnvironment {
    Write-Host "`n=== Spring Boot 개발 환경 설치 ===" -ForegroundColor Magenta

    # --- JDK 17 ---
    Write-Status "CHECK" "JDK 17 확인 중..."
    $hasJava17 = $false
    if (Test-CommandExists "java") {
        $javaVer = & java -version 2>&1 | Out-String
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

    # --- JAVA_HOME 설정 ---
    Write-Status "CHECK" "JAVA_HOME 확인 중..."
    $javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
    if ($javaHome -and (Test-Path $javaHome)) {
        Write-Status "SKIP" "JAVA_HOME 이미 설정됨: $javaHome"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "JAVA_HOME 미설정"
    } else {
        # Microsoft OpenJDK 17 기본 경로 탐색
        $candidates = @(
            "${env:ProgramFiles}\Microsoft\jdk-17*",
            "${env:ProgramFiles}\Eclipse Adoptium\jdk-17*",
            "${env:ProgramFiles}\Java\jdk-17*"
        )
        $found = $null
        foreach ($pattern in $candidates) {
            $found = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { break }
        }
        if ($found) {
            [Environment]::SetEnvironmentVariable("JAVA_HOME", $found.FullName, "User")
            $env:JAVA_HOME = $found.FullName
            Add-ToPath "$($found.FullName)\bin"
            Write-Status "OK" "JAVA_HOME 설정: $($found.FullName)"
        } else {
            Write-Status "FAIL" "JDK 17 경로를 찾을 수 없습니다. 수동으로 JAVA_HOME을 설정하세요."
        }
    }

    # --- Gradle wrapper ---
    Write-Status "CHECK" "Gradle wrapper 확인 중..."
    $wrapperJar = ".\gradle\wrapper\gradle-wrapper.jar"
    if (Test-Path $wrapperJar) {
        Write-Status "SKIP" "Gradle wrapper 이미 존재: $wrapperJar"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "Gradle wrapper 없음 (프로젝트 루트에서 실행하세요)"
    } else {
        Write-Status "INSTALL" "Gradle wrapper 다운로드 중..."
        $wrapperDir = ".\gradle\wrapper"
        New-Item -ItemType Directory -Force -Path $wrapperDir | Out-Null
        $jarUrl = "https://github.com/gradle/gradle/raw/master/gradle/wrapper/gradle-wrapper.jar"
        try {
            Invoke-WebRequest -Uri $jarUrl -OutFile $wrapperJar -UseBasicParsing
            Write-Status "OK" "Gradle wrapper 다운로드 완료"
        } catch {
            Write-Status "FAIL" "Gradle wrapper 다운로드 실패: $_"
        }
    }

    # --- 검증 요약 ---
    Write-Host "`n=== 설치 검증 ===" -ForegroundColor Magenta
    if (Test-CommandExists "java") {
        $v = & java -version 2>&1 | Select-Object -First 1
        Write-Status "OK" "java: $v"
    } else {
        Write-Status "FAIL" "java: 찾을 수 없음"
    }
    if (Test-CommandExists "javac") {
        $v = & javac -version 2>&1 | Select-Object -First 1
        Write-Status "OK" "javac: $v"
    } else {
        Write-Status "FAIL" "javac: 찾을 수 없음"
    }
    $jh = [Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
    if ($jh) {
        Write-Status "OK" "JAVA_HOME: $jh"
    } else {
        Write-Status "FAIL" "JAVA_HOME: 미설정"
    }
}

Install-SpringBootEnvironment
