"""Linux-specific Go installer."""

import os
from pathlib import Path

from _common import (
    PlatformInstaller, ToolSpec,
    write_status, write_header, command_exists, get_command_output,
    extract_version, run_cmd, detect_os,
    install_package, add_to_path, refresh_path_env,
)


class GoInstaller(PlatformInstaller):
    platform_name = "Go"

    def __init__(self, project_root: Path, check_only: bool = False):
        super().__init__(project_root, check_only)
        self.tools = [
            ToolSpec(
                name="Go", cmd="go", min_version="1.21", version_arg="version",
                package_specs={"apt": "golang", "dnf": "golang"},
            ),
            ToolSpec(name="GOPATH", cmd="", install_func="_setup_gopath"),
            ToolSpec(name="golangci-lint", cmd="golangci-lint",
                     install_func="_install_golangci_lint"),
        ]

    def _process_tool(self, tool: ToolSpec) -> None:
        if tool.name == "GOPATH":
            self._check_gopath()
        else:
            super()._process_tool(tool)

    def _check_gopath(self) -> None:
        write_status("CHECK", "GOPATH 확인 중...")
        gopath = os.environ.get("GOPATH")
        if gopath:
            write_status("SKIP", f"GOPATH 이미 설정됨: {gopath}")
            self.result.add("SKIP", "GOPATH")
        elif self.check_only:
            write_status("FAIL", "GOPATH 미설정")
            self.result.add("FAIL", "GOPATH")
        else:
            self._setup_gopath()

    def _setup_gopath(self) -> bool:
        default = os.path.join(os.path.expanduser("~"), "go")
        os.environ["GOPATH"] = default
        rc_path = os.path.expandvars("$HOME/.bashrc")
        try:
            existing = Path(rc_path).read_text() if Path(rc_path).exists() else ""
            if "GOPATH" not in existing:
                with open(rc_path, "a") as f:
                    f.write(f'\nexport GOPATH="{default}"\n')
        except Exception:
            pass
        add_to_path(os.path.join(default, "bin"))
        write_status("OK", f"GOPATH 설정: {default}")
        self.result.add("OK", "GOPATH")
        return True

    def _install_golangci_lint(self) -> bool:
        if not command_exists("go"):
            write_status("FAIL", "Go가 설치되지 않아 golangci-lint를 설치할 수 없습니다")
            return False
        write_status("INSTALL", "golangci-lint 설치 중 (go install)...")
        ok = run_cmd(["go", "install",
                       "github.com/golangci-lint/golangci-lint/cmd/golangci-lint@latest"])
        if ok:
            refresh_path_env()
            gopath_bin = os.path.join(
                os.environ.get("GOPATH", os.path.join(os.path.expanduser("~"), "go")), "bin"
            )
            if not command_exists("golangci-lint"):
                add_to_path(gopath_bin)
            if command_exists("golangci-lint") or Path(gopath_bin, "golangci-lint").exists():
                write_status("OK", "golangci-lint 설치 완료")
                return True
        write_status("FAIL", "golangci-lint 설치 실패")
        return False

    def verify(self) -> None:
        if command_exists("go"):
            ver = get_command_output(["go", "version"])
            write_status("OK", f"go: {ver}")
        else:
            write_status("FAIL", "go: 찾을 수 없음")
        if command_exists("golangci-lint"):
            ver = extract_version(get_command_output(["golangci-lint", "--version"]))
            write_status("OK", f"golangci-lint: {ver or 'found'}")
        else:
            write_status("FAIL", "golangci-lint: 찾을 수 없음")
        gopath = os.environ.get("GOPATH")
        write_status("OK" if gopath else "FAIL",
                     f"GOPATH: {gopath or '미설정'}")
