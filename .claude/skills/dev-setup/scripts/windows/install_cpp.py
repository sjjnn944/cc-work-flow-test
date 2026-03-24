import os
import subprocess
import sys
from pathlib import Path
from typing import Optional

from _common import (
    PlatformInstaller, ToolSpec, InstallResult,
    write_status, write_header, command_exists, get_command_output,
    extract_version, check_min_version, run_cmd, detect_os,
    install_package, add_to_path, refresh_path_env,
    get_thirdparty_dir, find_kit_version,
)


class CppInstaller(PlatformInstaller):
    platform_name = "C++/CMake"

    def __init__(self, project_root: Path, check_only: bool = False):
        super().__init__(project_root, check_only)
        self.tools = [
            ToolSpec(
                name="MSVC Build Tools",
                cmd="",  # Special check in pre_install
                install_func="_install_msvc",
            ),
            ToolSpec(
                name="CMake", cmd="cmake", min_version="3.20",
                package_specs={"winget": "Kitware.CMake", "choco": "cmake",
                               "apt": "cmake", "dnf": "cmake", "brew": "cmake"},
            ),
            ToolSpec(
                name="Ninja", cmd="ninja", min_version="1.10",
                package_specs={"winget": "Ninja-build.Ninja", "choco": "ninja",
                               "apt": "ninja-build", "dnf": "ninja-build", "brew": "ninja"},
            ),
            ToolSpec(
                name="vcpkg", cmd="",
                install_func="_install_vcpkg",
            ),
            ToolSpec(
                name="clang-format", cmd="clang-format",
                install_func="_install_llvm",
            ),
            ToolSpec(
                name="clang-tidy", cmd="clang-tidy",
                install_func="_install_llvm",
            ),
            ToolSpec(
                name="cppcheck", cmd="cppcheck",
                package_specs={"winget": "Cppcheck.Cppcheck", "choco": "cppcheck",
                               "apt": "cppcheck", "dnf": "cppcheck", "brew": "cppcheck"},
            ),
        ]
        if detect_os() == "windows":
            self.tools.insert(4, ToolSpec(
                name="Windows SDK", cmd="",
                install_func="_install_windows_sdk",
            ))
            self.tools.insert(5, ToolSpec(
                name="WDK", cmd="",
                install_func="_install_wdk",
            ))

    def _process_tool(self, tool: ToolSpec) -> None:
        """Override for tools with special check logic."""
        if tool.name == "MSVC Build Tools":
            self._check_msvc(tool)
        elif tool.name == "vcpkg":
            self._check_vcpkg(tool)
        elif tool.name == "Windows SDK":
            self._check_windows_sdk(tool)
        elif tool.name == "WDK":
            self._check_wdk(tool)
        else:
            super()._process_tool(tool)

    def _check_msvc(self, tool: ToolSpec) -> None:
        write_status("CHECK", "MSVC Build Tools 확인 중...")
        if detect_os() != "windows":
            write_status("SKIP", "MSVC Build Tools — Windows 전용")
            return
        vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / \
                  "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
        has_msvc = False
        if vswhere.exists():
            r = subprocess.run(
                [str(vswhere), "-products", "*",
                 "-requires", "Microsoft.VisualCpp.Tools.HostX64.TargetX64"],
                capture_output=True, text=True,
            )
            has_msvc = bool(r.stdout.strip())
        if has_msvc:
            write_status("SKIP", "MSVC Build Tools 이미 설치됨")
            self.result.add("SKIP", "MSVC Build Tools")
        elif self.check_only:
            write_status("FAIL", "MSVC Build Tools 없음")
            self.result.add("FAIL", "MSVC Build Tools")
        else:
            ok = install_package(
                {"winget": "Microsoft.VisualStudio.2022.BuildTools"},
                "MSVC Build Tools 2022",
            )
            self.result.add("OK" if ok else "FAIL", "MSVC Build Tools")

    def _install_msvc(self) -> bool:
        return install_package(
            {"winget": "Microsoft.VisualStudio.2022.BuildTools"},
            "MSVC Build Tools 2022",
        )

    def _check_vcpkg(self, tool: ToolSpec) -> None:
        write_status("CHECK", "vcpkg 확인 중...")
        tp = get_thirdparty_dir(self.project_root)
        vcpkg_exe = tp / "vcpkg" / ("vcpkg.exe" if detect_os() == "windows" else "vcpkg")
        if vcpkg_exe.exists():
            write_status("SKIP", f"vcpkg 이미 존재: {vcpkg_exe}")
            self.result.add("SKIP", "vcpkg")
        elif self.check_only:
            write_status("FAIL", f"vcpkg 없음 ({vcpkg_exe})")
            self.result.add("FAIL", "vcpkg")
        else:
            ok = self._install_vcpkg()
            self.result.add("OK" if ok else "FAIL", "vcpkg")

    def _install_vcpkg(self) -> bool:
        tp = get_thirdparty_dir(self.project_root)
        vcpkg_dir = tp / "vcpkg"
        if not vcpkg_dir.exists():
            write_status("INSTALL", "vcpkg 클론 중...")
            if not run_cmd(["git", "clone", "https://github.com/microsoft/vcpkg.git",
                            str(vcpkg_dir)]):
                write_status("FAIL", "vcpkg 클론 실패")
                return False

        write_status("INSTALL", "vcpkg 부트스트랩 중...")
        if detect_os() == "windows":
            bootstrap = vcpkg_dir / "bootstrap-vcpkg.bat"
            ok = run_cmd([str(bootstrap), "-disableMetrics"])
        else:
            bootstrap = vcpkg_dir / "bootstrap-vcpkg.sh"
            ok = run_cmd(["bash", str(bootstrap), "-disableMetrics"])

        if ok:
            add_to_path(str(vcpkg_dir))
            write_status("OK", "vcpkg 설치 완료")
            return True
        write_status("FAIL", "vcpkg 부트스트랩 실패")
        return False

    def _check_windows_sdk(self, tool: ToolSpec) -> None:
        write_status("CHECK", "Windows SDK 확인 중...")
        inc_base = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / \
                   "Windows Kits" / "10" / "Include"
        sdk_ver = find_kit_version(inc_base, "um/windows.h")
        if sdk_ver:
            write_status("SKIP", f"Windows SDK 이미 설치됨: {sdk_ver}")
            self.result.add("SKIP", "Windows SDK")
        elif self.check_only:
            write_status("FAIL", "Windows SDK 없음")
            self.result.add("FAIL", "Windows SDK")
        else:
            ok = self._install_windows_sdk()
            self.result.add("OK" if ok else "FAIL", "Windows SDK")

    def _install_windows_sdk(self) -> bool:
        return install_package(
            {"winget": "Microsoft.WindowsSDK.10.0.26100",
             "choco": "windows-sdk-10-version-2004-all"},
            "Windows SDK",
        )

    def _check_wdk(self, tool: ToolSpec) -> None:
        write_status("CHECK", "WDK 확인 중...")
        inc_base = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / \
                   "Windows Kits" / "10" / "Include"
        wdk_ver = find_kit_version(inc_base, "km/ntddk.h")
        if wdk_ver:
            write_status("SKIP", f"WDK 이미 설치됨: {wdk_ver}")
            self.result.add("SKIP", "WDK")
        elif self.check_only:
            write_status("FAIL", "WDK 없음")
            self.result.add("FAIL", "WDK")
        else:
            ok = self._install_wdk()
            self.result.add("OK" if ok else "FAIL", "WDK")

    def _install_wdk(self) -> bool:
        return install_package(
            {"winget": "Microsoft.WindowsWDK.10.0.26100",
             "choco": "windowsdriverkit11"},
            "WDK",
        )

    def _install_llvm(self) -> bool:
        os_name = detect_os()
        if os_name == "windows":
            ok = install_package({"winget": "LLVM.LLVM"}, "LLVM")
        elif os_name == "macos":
            ok = install_package({"brew": "llvm"}, "LLVM")
        else:
            ok = install_package(
                {"apt": ["clang-tidy", "clang-format"],
                 "dnf": ["clang-tools-extra"],
                 "pacman": ["clang"]},
                "LLVM tools",
            )
        if ok:
            refresh_path_env()
        return ok

    def verify(self) -> None:
        for cmd in ("cmake", "ninja", "clang-format", "clang-tidy", "cppcheck"):
            if command_exists(cmd):
                ver = extract_version(get_command_output([cmd, "--version"]))
                write_status("OK", f"{cmd}: {ver or 'found'}")
            else:
                write_status("FAIL", f"{cmd}: 찾을 수 없음")

        # vcpkg
        tp = get_thirdparty_dir(self.project_root)
        vcpkg_exe = tp / "vcpkg" / ("vcpkg.exe" if detect_os() == "windows" else "vcpkg")
        if vcpkg_exe.exists():
            write_status("OK", f"vcpkg: {vcpkg_exe}")
        else:
            write_status("FAIL", "vcpkg: 찾을 수 없음")

        if detect_os() == "windows":
            inc_base = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / \
                       "Windows Kits" / "10" / "Include"
            sdk = find_kit_version(inc_base, "um/windows.h")
            wdk = find_kit_version(inc_base, "km/ntddk.h")
            write_status("OK" if sdk else "FAIL",
                         f"Windows SDK: {sdk or '찾을 수 없음'}")
            write_status("OK" if wdk else "FAIL",
                         f"WDK: {wdk or '찾을 수 없음'}")
