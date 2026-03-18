# dev-setup: C++ 개발 환경 설치 (Windows)
# 설치 항목: MSVC Build Tools 2022, CMake, Ninja, vcpkg, clang-format

. "$PSScriptRoot\_common.ps1"

function Install-CppEnvironment {
    Write-Host "`n=== C++ 개발 환경 설치 ===" -ForegroundColor Magenta

    # --- MSVC Build Tools ---
    Write-Status "CHECK" "MSVC Build Tools 확인 중..."
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $hasMsvc = (Test-Path $vsWhere) -and (& $vsWhere -products * -requires Microsoft.VisualCpp.Tools.HostX64.TargetX64 2>$null)
    if ($hasMsvc) {
        Write-Status "SKIP" "MSVC Build Tools 이미 설치됨"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "MSVC Build Tools 없음"
    } else {
        Install-WithWinget "Microsoft.VisualStudio.2022.BuildTools" "MSVC Build Tools 2022"
    }

    # --- CMake ---
    Write-Status "CHECK" "CMake 확인 중..."
    if (Test-MinVersion "cmake" "--version" "3.20") {
        Write-Status "SKIP" "CMake $(& cmake --version 2>&1 | Select-String '\d+\.\d+\.\d+') 이미 설치됨"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "CMake 3.20+ 없음"
    } else {
        if (-not (Install-WithWinget "Kitware.CMake" "CMake")) {
            Install-WithChoco "cmake" "CMake"
        }
        Refresh-PathEnv
    }

    # --- Ninja ---
    Write-Status "CHECK" "Ninja 확인 중..."
    if (Test-MinVersion "ninja" "--version" "1.10") {
        Write-Status "SKIP" "Ninja $(& ninja --version 2>&1) 이미 설치됨"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "Ninja 1.10+ 없음"
    } else {
        if (-not (Install-WithWinget "Ninja-build.Ninja" "Ninja")) {
            Install-WithChoco "ninja" "Ninja"
        }
        Refresh-PathEnv
    }

    # --- vcpkg ---
    Write-Status "CHECK" "vcpkg 확인 중..."
    $thirdpartyDir = Get-ThirdpartyDir
    $vcpkgPath = Join-Path $thirdpartyDir "vcpkg"
    $vcpkgExe  = Join-Path $vcpkgPath "vcpkg.exe"
    if (Test-Path $vcpkgExe) {
        Write-Status "SKIP" "vcpkg 이미 존재: $vcpkgExe"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "vcpkg 없음 ($vcpkgExe)"
    } else {
        Write-Status "INSTALL" "vcpkg 클론 및 부트스트랩 중..."
        if (-not (Test-Path $vcpkgPath)) {
            git clone https://github.com/microsoft/vcpkg.git $vcpkgPath
        }
        & "$vcpkgPath\bootstrap-vcpkg.bat" -disableMetrics
        if (Test-Path $vcpkgExe) {
            Add-ToPath $vcpkgPath
            Write-Status "OK" "vcpkg 설치 완료: $vcpkgExe"
        } else {
            Write-Status "FAIL" "vcpkg 부트스트랩 실패"
        }
    }

    # --- clang-format (optional, part of LLVM) ---
    Write-Status "CHECK" "clang-format 확인 중..."
    if (Test-CommandExists "clang-format") {
        Write-Status "SKIP" "clang-format 이미 설치됨"
    } elseif ($script:CheckOnly) {
        Write-Status "FAIL" "clang-format 없음 (optional)"
    } else {
        Write-Status "INSTALL" "clang-format 설치 중 (LLVM)..."
        Install-WithWinget "LLVM.LLVM" "LLVM (clang-format)"
        Refresh-PathEnv
    }

    # --- 검증 요약 ---
    Write-Host "`n=== 설치 검증 ===" -ForegroundColor Magenta
    foreach ($tool in @("cmake --version", "ninja --version", "clang-format --version")) {
        $cmd = $tool.Split(" ")[0]
        $arg = $tool.Split(" ")[1]
        if (Test-CommandExists $cmd) {
            $ver = & $cmd $arg 2>&1 | Select-Object -First 1
            Write-Status "OK" "${cmd}: $ver"
        } else {
            Write-Status "FAIL" "${cmd}: 찾을 수 없음"
        }
    }
    $verifyVcpkgPath = Join-Path (Get-ThirdpartyDir) "vcpkg\vcpkg.exe"
    if (Test-Path $verifyVcpkgPath) {
        Write-Status "OK" "vcpkg: $verifyVcpkgPath"
    } else {
        Write-Status "FAIL" "vcpkg: 찾을 수 없음"
    }
}

Install-CppEnvironment
