"""Linux-specific Rust installer."""

import os
from pathlib import Path

from _common import (
    PlatformInstaller, ToolSpec,
    write_status, write_header, command_exists, get_command_output,
    extract_version, run_cmd, detect_os,
    add_to_path, refresh_path_env,
)


class RustInstaller(PlatformInstaller):
    platform_name = "Rust"

    def __init__(self, project_root: Path, check_only: bool = False):
        super().__init__(project_root, check_only)
        self.tools = [
            ToolSpec(name="rustup", cmd="rustup", install_func="_install_rustup"),
            ToolSpec(name="clippy", cmd="", install_func="_install_clippy"),
            ToolSpec(name="rustfmt", cmd="rustfmt", install_func="_install_rustfmt"),
        ]

    def _process_tool(self, tool: ToolSpec) -> None:
        if tool.name == "clippy":
            self._check_clippy()
        else:
            super()._process_tool(tool)

    def _install_rustup(self) -> bool:
        write_status("INSTALL", "rustup 설치 중...")
        ok = run_cmd([
            "bash", "-c",
            "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y",
        ])
        if ok:
            cargo_bin = os.path.join(os.path.expanduser("~"), ".cargo", "bin")
            add_to_path(cargo_bin)
            write_status("OK", "rustup 설치 완료")
            return True
        write_status("FAIL", "rustup 설치 실패")
        return False

    def _check_clippy(self) -> None:
        write_status("CHECK", "clippy 확인 중...")
        if command_exists("cargo"):
            output = get_command_output(["rustup", "component", "list"])
            if output and "clippy" in output and "installed" in output:
                write_status("SKIP", "clippy 이미 설치됨")
                self.result.add("SKIP", "clippy")
                return
        if self.check_only:
            write_status("FAIL", "clippy 없음")
            self.result.add("FAIL", "clippy")
        else:
            ok = self._install_clippy()
            self.result.add("OK" if ok else "FAIL", "clippy")

    def _install_clippy(self) -> bool:
        if not command_exists("rustup"):
            write_status("FAIL", "rustup이 없어 clippy를 설치할 수 없습니다")
            return False
        write_status("INSTALL", "clippy 추가 중...")
        ok = run_cmd(["rustup", "component", "add", "clippy"])
        if ok:
            write_status("OK", "clippy 추가 완료")
        return ok

    def _install_rustfmt(self) -> bool:
        if not command_exists("rustup"):
            write_status("FAIL", "rustup이 없어 rustfmt를 설치할 수 없습니다")
            return False
        write_status("INSTALL", "rustfmt 추가 중...")
        ok = run_cmd(["rustup", "component", "add", "rustfmt"])
        if ok:
            write_status("OK", "rustfmt 추가 완료")
        return ok

    def verify(self) -> None:
        for cmd_info in [("rustc", "--version"), ("cargo", "--version"),
                         ("rustfmt", "--version")]:
            cmd, arg = cmd_info
            if command_exists(cmd):
                ver = extract_version(get_command_output([cmd, arg]))
                write_status("OK", f"{cmd}: {ver or 'found'}")
            else:
                write_status("FAIL", f"{cmd}: 찾을 수 없음")
        if command_exists("rustup"):
            output = get_command_output(["rustup", "component", "list"])
            has_clippy = output and "clippy" in output and "installed" in output
            write_status("OK" if has_clippy else "FAIL",
                         f"clippy: {'설치됨' if has_clippy else '없음'}")
