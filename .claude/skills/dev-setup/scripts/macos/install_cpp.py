"""macOS C++/CMake installer."""

import os
import subprocess
from pathlib import Path
from typing import Optional

from _common import (
    PlatformInstaller, ToolSpec,
    write_status, write_header, command_exists, get_command_output,
    extract_version, run_cmd, detect_os,
    install_package, add_to_path, refresh_path_env,
    get_thirdparty_dir,
)


class CppInstaller(PlatformInstaller):
    platform_name = "C++/CMake"

    def __init__(self, project_root: Path, check_only: bool = False):
        super().__init__(project_root, check_only)
        self.tools = [
            ToolSpec(
                name="CMake", cmd="cmake", min_version="3.20",
                package_specs={"brew": "cmake"},
            ),
            ToolSpec(
                name="Ninja", cmd="ninja", min_version="1.10",
                package_specs={"brew": "ninja"},
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
                package_specs={"brew": "cppcheck"},
            ),
            ToolSpec(
                name="GTest (vcpkg)",
                cmd="",
                install_func="_install_gtest",
            ),
        ]

    def _process_tool(self, tool: ToolSpec) -> None:
        """Override for tools with special check logic."""
        if tool.name == "vcpkg":
            self._check_vcpkg(tool)
        elif tool.name == "GTest (vcpkg)":
            self._check_gtest(tool)
        else:
            super()._process_tool(tool)

    def _check_vcpkg(self, tool: ToolSpec) -> None:
        write_status("CHECK", "vcpkg 확인 중...")
        tp = get_thirdparty_dir(self.project_root)
        vcpkg_exe = tp / "vcpkg" / "vcpkg"
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
        bootstrap = vcpkg_dir / "bootstrap-vcpkg.sh"
        ok = run_cmd(["bash", str(bootstrap), "-disableMetrics"])

        if ok:
            add_to_path(str(vcpkg_dir))
            write_status("OK", "vcpkg 설치 완료")
            return True
        write_status("FAIL", "vcpkg 부트스트랩 실패")
        return False

    def _check_gtest(self, tool: ToolSpec) -> None:
        write_status("CHECK", "GTest (vcpkg) 확인 중...")
        test_dir = self.project_root / "test"
        if not test_dir.exists():
            write_status("SKIP", "GTest — test/ 디렉토리 없음 (설치 불필요)")
            self.result.add("SKIP", "GTest")
            return
        tp = get_thirdparty_dir(self.project_root)
        vcpkg_exe = tp / "vcpkg" / "vcpkg"
        if not vcpkg_exe.exists():
            write_status("FAIL", "GTest — vcpkg가 설치되지 않아 설치 불가")
            self.result.add("FAIL", "GTest")
            return
        r = subprocess.run([str(vcpkg_exe), "list", "gtest"],
                           capture_output=True, text=True)
        if r.returncode == 0 and "gtest" in r.stdout:
            write_status("SKIP", "GTest 이미 설치됨 (vcpkg)")
            self.result.add("SKIP", "GTest")
            return
        if self.check_only:
            write_status("FAIL", "GTest 없음 (vcpkg install 필요)")
            self.result.add("FAIL", "GTest")
            return
        ok = self._install_gtest()
        self.result.add("OK" if ok else "FAIL", "GTest")

    def _install_gtest(self) -> bool:
        tp = get_thirdparty_dir(self.project_root)
        vcpkg_exe = tp / "vcpkg" / "vcpkg"
        if not vcpkg_exe.exists():
            write_status("FAIL", "vcpkg가 없어 GTest를 설치할 수 없습니다")
            return False
        write_status("INSTALL", "GTest 설치 중 (vcpkg)...")
        ok = run_cmd([str(vcpkg_exe), "install", "gtest"])
        if ok:
            write_status("OK", "GTest 설치 완료")
        else:
            write_status("FAIL", "GTest 설치 실패")
        return ok

    def _install_llvm(self) -> bool:
        ok = install_package({"brew": "llvm"}, "LLVM")
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
        vcpkg_exe = tp / "vcpkg" / "vcpkg"
        if vcpkg_exe.exists():
            write_status("OK", f"vcpkg: {vcpkg_exe}")
        else:
            write_status("FAIL", "vcpkg: 찾을 수 없음")
