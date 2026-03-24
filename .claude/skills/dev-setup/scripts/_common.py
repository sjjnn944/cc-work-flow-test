#!/usr/bin/env python3
"""
dev-setup shared code — utilities, base classes, thin installers, and build verification.

Extracted from tools/setup.py for modular reuse by platform-specific installer scripts.
"""

import ctypes
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


__all__ = [
    # Constants
    "_USE_COLOR",
    "_COLORS",
    # Utility functions
    "write_status",
    "write_header",
    "command_exists",
    "get_command_output",
    "extract_version",
    "version_gte",
    "check_min_version",
    "run_cmd",
    "detect_os",
    "detect_linux_pkg_manager",
    "install_package",
    "add_to_path",
    "refresh_path_env",
    "get_thirdparty_dir",
    "find_jdk",
    "find_msbuild",
    "get_java_major_version",
    # Base classes
    "ToolSpec",
    "InstallResult",
    "PlatformInstaller",
    # Thin installer classes
    "ReactInstaller",
    "DjangoInstaller",
    "NestJSInstaller",
    "DotNetInstaller",
    "THIN_INSTALLERS",
    "BUILD_VERIFY_PLATFORMS",
    # Build sample verification
    "get_skill_root",
    "verify_build_sample",
    "find_kit_version",
]


# =============================================================================
# [1] Common Utilities
# =============================================================================

# ANSI colors (disabled on Windows without VT support)
_USE_COLOR = sys.stdout.isatty() and (
    sys.platform != "win32" or os.environ.get("WT_SESSION")  # Windows Terminal
    or os.environ.get("TERM_PROGRAM")
)

_COLORS = {
    "OK": "\033[0;32m",
    "INSTALL": "\033[0;36m",
    "SKIP": "\033[0;33m",
    "FAIL": "\033[0;31m",
    "CHECK": "\033[0;37m",
    "HEADER": "\033[0;35m",
    "NC": "\033[0m",
}


def write_status(status: str, message: str) -> None:
    """Print a status message with color."""
    if _USE_COLOR:
        color = _COLORS.get(status, "")
        nc = _COLORS["NC"]
        print(f"{color}[{status}]{nc} {message}")
    else:
        print(f"[{status}] {message}")


def write_header(title: str) -> None:
    """Print a section header."""
    if _USE_COLOR:
        print(f"\n{_COLORS['HEADER']}=== {title} ==={_COLORS['NC']}")
    else:
        print(f"\n=== {title} ===")


def command_exists(cmd: str) -> bool:
    """Check if a command is available in PATH."""
    return shutil.which(cmd) is not None


def get_command_output(cmd: list[str], timeout: int = 30) -> Optional[str]:
    """Run a command and return its stdout+stderr, or None on failure."""
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout,
            shell=(sys.platform == "win32" and cmd[0] in ("npm", "pnpm", "nest", "tsc")),
        )
        output = (result.stdout + " " + result.stderr).strip()
        return output if output else None
    except Exception:
        return None


def extract_version(text: str) -> Optional[str]:
    """Extract a version string (x.y.z) from text."""
    if not text:
        return None
    m = re.search(r"(\d+\.\d+[\.\d]*)", text)
    return m.group(1) if m else None


def version_gte(current: str, minimum: str) -> bool:
    """Compare version strings: current >= minimum."""
    def parts(v: str) -> list[int]:
        return [int(x) for x in v.split(".")]
    try:
        c, m = parts(current), parts(minimum)
        # Pad to same length
        while len(c) < len(m):
            c.append(0)
        while len(m) < len(c):
            m.append(0)
        return c >= m
    except (ValueError, TypeError):
        return False


def check_min_version(cmd: str, version_arg: str, min_version: str) -> bool:
    """Check if a command exists and meets the minimum version."""
    if not command_exists(cmd):
        return False
    output = get_command_output([cmd, version_arg])
    ver = extract_version(output)
    if not ver:
        return False
    return version_gte(ver, min_version)


def run_cmd(cmd: list[str], description: str = "", **kwargs) -> bool:
    """Run a command, return True on success."""
    # On Windows, npm/pnpm/nest/tsc need shell=True due to .ps1/.cmd wrappers
    cmd0 = Path(cmd[0]).stem.lower() if os.sep in cmd[0] or "/" in cmd[0] else cmd[0].lower()
    use_shell = sys.platform == "win32" and cmd0 in ("npm", "pnpm", "nest", "tsc", "gradle", "gradlew")
    defaults = {"shell": use_shell}
    defaults.update(kwargs)
    try:
        result = subprocess.run(cmd, **defaults)
        return result.returncode == 0
    except Exception as e:
        if description:
            write_status("FAIL", f"{description}: {e}")
        return False


def detect_os() -> str:
    """Detect OS: 'windows', 'linux', 'macos'."""
    if sys.platform == "win32":
        return "windows"
    elif sys.platform == "darwin":
        return "macos"
    else:
        return "linux"


def detect_linux_pkg_manager() -> str:
    """Detect Linux package manager: 'apt', 'dnf', 'pacman', or 'unknown'."""
    for pm in ("apt-get", "dnf", "pacman"):
        if command_exists(pm):
            return "apt" if pm == "apt-get" else pm
    return "unknown"


def install_package(specs: dict, display_name: str) -> bool:
    """Install a package using the appropriate OS package manager.

    specs keys: 'winget', 'choco', 'apt', 'dnf', 'pacman', 'brew'
    Values can be str or list[str] (for multiple packages).
    """
    os_name = detect_os()

    if os_name == "windows":
        # Try winget first, then choco
        if "winget" in specs and command_exists("winget"):
            write_status("INSTALL", f"{display_name} 설치 중 (winget)...")
            pkg = specs["winget"]
            ok = run_cmd(
                ["winget", "install", "--id", pkg,
                 "--accept-source-agreements", "--accept-package-agreements", "--silent"],
            )
            if ok:
                write_status("OK", f"{display_name} 설치 완료")
                return True
        if "choco" in specs and command_exists("choco"):
            write_status("INSTALL", f"{display_name} 설치 중 (choco)...")
            pkg = specs["choco"]
            ok = run_cmd(["choco", "install", pkg, "-y", "--no-progress"])
            if ok:
                write_status("OK", f"{display_name} 설치 완료")
                return True
        write_status("FAIL", f"{display_name} 설치 실패")
        return False

    elif os_name == "macos":
        if "brew" in specs and command_exists("brew"):
            write_status("INSTALL", f"{display_name} 설치 중 (brew)...")
            pkg = specs["brew"]
            pkgs = [pkg] if isinstance(pkg, str) else pkg
            ok = run_cmd(["brew", "install"] + pkgs)
            if ok:
                write_status("OK", f"{display_name} 설치 완료")
                return True
        write_status("FAIL", f"{display_name} 설치 실패")
        return False

    else:  # linux
        pm = detect_linux_pkg_manager()
        if pm in specs:
            write_status("INSTALL", f"{display_name} 설치 중 ({pm})...")
            pkg = specs[pm]
            pkgs = [pkg] if isinstance(pkg, str) else pkg
            if pm == "apt":
                ok = run_cmd(["sudo", "apt-get", "update", "-qq"]) and \
                     run_cmd(["sudo", "apt-get", "install", "-y", "-qq"] + pkgs)
            elif pm == "dnf":
                ok = run_cmd(["sudo", "dnf", "install", "-y", "-q"] + pkgs)
            elif pm == "pacman":
                ok = run_cmd(["sudo", "pacman", "-S", "--noconfirm", "--needed"] + pkgs)
            else:
                ok = False
            if ok:
                write_status("OK", f"{display_name} 설치 완료")
                return True
        write_status("FAIL", f"{display_name} 설치 실패")
        return False


def add_to_path(path: str) -> None:
    """Add a directory to PATH (persistent + current process)."""
    if not path or path in os.environ.get("PATH", ""):
        return

    os.environ["PATH"] = path + os.pathsep + os.environ.get("PATH", "")

    os_name = detect_os()
    if os_name == "windows":
        try:
            import winreg
            key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Environment", 0,
                                 winreg.KEY_ALL_ACCESS)
            try:
                current, _ = winreg.QueryValueEx(key, "PATH")
            except FileNotFoundError:
                current = ""
            if path not in current:
                new_path = path + ";" + current if current else path
                winreg.SetValueEx(key, "PATH", 0, winreg.REG_EXPAND_SZ, new_path)
            winreg.CloseKey(key)
            # Broadcast WM_SETTINGCHANGE
            _send_setting_change()
        except Exception:
            pass
    elif os_name == "macos":
        _append_to_shell_rc(path, "$HOME/.zshrc")
    else:
        _append_to_shell_rc(path, "$HOME/.bashrc")

    write_status("OK", f"PATH에 추가: {path}")


def _append_to_shell_rc(path: str, rc_file: str) -> None:
    """Append export PATH line to shell rc file."""
    rc = os.path.expandvars(rc_file)
    line = f'export PATH="{path}:$PATH"'
    try:
        existing = Path(rc).read_text() if Path(rc).exists() else ""
        if path not in existing:
            with open(rc, "a") as f:
                f.write(f"\n{line}\n")
    except Exception:
        pass


def _send_setting_change() -> None:
    """Broadcast WM_SETTINGCHANGE on Windows."""
    if sys.platform != "win32":
        return
    try:
        HWND_BROADCAST = 0xFFFF
        WM_SETTINGCHANGE = 0x001A
        SMTO_ABORTIFHUNG = 0x0002
        result = ctypes.c_ulong()
        ctypes.windll.user32.SendMessageTimeoutW(
            HWND_BROADCAST, WM_SETTINGCHANGE, 0, "Environment",
            SMTO_ABORTIFHUNG, 5000, ctypes.byref(result),
        )
    except Exception:
        pass


def refresh_path_env() -> None:
    """Refresh PATH from system environment (Windows only)."""
    if sys.platform != "win32":
        return
    try:
        import winreg
        machine_key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                                     r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment")
        machine_path, _ = winreg.QueryValueEx(machine_key, "Path")
        winreg.CloseKey(machine_key)

        user_key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Environment")
        try:
            user_path, _ = winreg.QueryValueEx(user_key, "PATH")
        except FileNotFoundError:
            user_path = ""
        winreg.CloseKey(user_key)

        os.environ["PATH"] = user_path + ";" + machine_path
    except Exception:
        pass


def get_thirdparty_dir(project_root: Path) -> Path:
    """Get (and create) the thirdparty directory."""
    d = project_root / "thirdparty"
    d.mkdir(parents=True, exist_ok=True)
    return d


def find_jdk(min_major: int = 17) -> Optional[str]:
    """Auto-detect JDK installation path and return JAVA_HOME.

    Reuses the same logic as build.py.
    """
    # 1. Check existing JAVA_HOME
    java_home = os.environ.get("JAVA_HOME")
    if java_home:
        javac = Path(java_home) / "bin" / ("javac.exe" if sys.platform == "win32" else "javac")
        if javac.exists():
            return java_home

    # 2. Filesystem search
    search_versions = [f"jdk-{v}*" for v in range(21, min_major - 1, -1)]

    if sys.platform == "win32":
        program_files = os.environ.get("ProgramFiles", r"C:\Program Files")
        search_roots = [
            Path(program_files) / "Eclipse Adoptium",
            Path(program_files) / "Microsoft",
            Path(program_files) / "Java",
            Path(program_files) / "Zulu",
        ]
    elif sys.platform == "darwin":
        search_roots = [Path("/usr/local/opt")]
        search_versions = [f"openjdk@{v}" for v in range(21, min_major - 1, -1)]
    else:
        search_roots = [Path("/usr/lib/jvm")]
        search_versions = [f"java-{v}*" for v in range(21, min_major - 1, -1)]

    for ver_pattern in search_versions:
        for root in search_roots:
            if not root.exists():
                continue
            for match in sorted(root.glob(ver_pattern), reverse=True):
                javac_name = "javac.exe" if sys.platform == "win32" else "javac"
                if (match / "bin" / javac_name).exists():
                    return str(match)

    return None


def find_msbuild() -> Optional[str]:
    """Find MSBuild.exe via vswhere (Windows only)."""
    if sys.platform != "win32":
        return None

    vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / \
              "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
    if not vswhere.exists():
        return None

    try:
        result = subprocess.run(
            [str(vswhere), "-latest", "-products", "*",
             "-requires", "Microsoft.Component.MSBuild",
             "-find", "MSBuild\\**\\Bin\\MSBuild.exe"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0 and result.stdout.strip():
            msbuild = result.stdout.strip().splitlines()[0]
            if Path(msbuild).exists():
                return msbuild
    except Exception:
        pass
    return None


def get_java_major_version(java_exe: str = "java") -> int:
    """Get the major version of a Java executable."""
    output = get_command_output([java_exe, "-version"])
    if output:
        m = re.search(r'version "(\d+)', output)
        if m:
            return int(m.group(1))
    return 0


# =============================================================================
# [2] ToolSpec & PlatformInstaller Base
# =============================================================================

@dataclass
class ToolSpec:
    """Specification for a single tool to check/install."""
    name: str                    # Display name, e.g., "CMake"
    cmd: str                     # Command to check, e.g., "cmake"
    min_version: str = ""        # Minimum version, e.g., "3.20"
    version_arg: str = "--version"
    package_specs: dict = field(default_factory=dict)
    install_func: Optional[str] = None  # Custom install method name


class InstallResult:
    """Tracks install results for reporting."""

    def __init__(self):
        self.ok: list[str] = []
        self.skip: list[str] = []
        self.fail: list[str] = []

    def add(self, status: str, name: str, detail: str = "") -> None:
        entry = f"{name}: {detail}" if detail else name
        if status == "OK":
            self.ok.append(entry)
        elif status == "SKIP":
            self.skip.append(entry)
        else:
            self.fail.append(entry)

    @property
    def total_ok(self) -> int:
        return len(self.ok)

    @property
    def total_fail(self) -> int:
        return len(self.fail)


class PlatformInstaller:
    """Base class for platform-specific installers.

    Template method pattern: pre_install -> check/install tools -> post_install
    """

    platform_name: str = ""
    tools: list[ToolSpec] = []

    def __init__(self, project_root: Path, check_only: bool = False):
        self.project_root = project_root
        self.check_only = check_only
        self.result = InstallResult()

    def run(self) -> InstallResult:
        """Execute the full install pipeline."""
        write_header(f"{self.platform_name} 개발 환경 설치")

        self.pre_install()

        for tool in self.tools:
            self._process_tool(tool)

        self.post_install()

        # Verification summary
        write_header("설치 검증")
        self.verify()

        return self.result

    def _process_tool(self, tool: ToolSpec) -> None:
        """Check and optionally install a single tool."""
        write_status("CHECK", f"{tool.name} 확인 중...")

        # Check if already installed with sufficient version
        if tool.min_version and tool.cmd:
            if check_min_version(tool.cmd, tool.version_arg, tool.min_version):
                ver = extract_version(get_command_output([tool.cmd, tool.version_arg]))
                write_status("SKIP", f"{tool.name} 이미 설치됨: {ver}")
                self.result.add("SKIP", tool.name, ver or "")
                return
        elif tool.cmd and command_exists(tool.cmd):
            ver = extract_version(get_command_output([tool.cmd, tool.version_arg]))
            write_status("SKIP", f"{tool.name} 이미 설치됨" + (f": {ver}" if ver else ""))
            self.result.add("SKIP", tool.name, ver or "")
            return

        # Not installed
        if self.check_only:
            msg = f"{tool.name} 없음"
            if tool.min_version:
                msg += f" ({tool.min_version}+ 필요)"
            write_status("FAIL", msg)
            self.result.add("FAIL", tool.name)
            return

        # Install
        if tool.install_func:
            ok = getattr(self, tool.install_func)()
        elif tool.package_specs:
            ok = install_package(tool.package_specs, tool.name)
            if ok:
                refresh_path_env()
        else:
            write_status("FAIL", f"{tool.name}: 설치 방법 없음")
            ok = False

        if ok:
            self.result.add("OK", tool.name)
        else:
            self.result.add("FAIL", tool.name)

    def pre_install(self) -> None:
        """Override for platform-specific pre-install steps."""
        pass

    def post_install(self) -> None:
        """Override for platform-specific post-install steps (build verification etc.)."""
        pass

    def verify(self) -> None:
        """Override for platform-specific verification summary."""
        for tool in self.tools:
            if tool.cmd and command_exists(tool.cmd):
                ver = extract_version(get_command_output([tool.cmd, tool.version_arg]))
                write_status("OK", f"{tool.cmd}: {ver or 'found'}")
            elif tool.cmd:
                write_status("FAIL", f"{tool.cmd}: 찾을 수 없음")


# =============================================================================
# [3] Thin Installer Classes (no OS-specific branching)
# =============================================================================

class ReactInstaller(PlatformInstaller):
    platform_name = "React/Vite"

    def __init__(self, project_root: Path, check_only: bool = False):
        super().__init__(project_root, check_only)
        self.tools = [
            ToolSpec(
                name="Node.js", cmd="node", min_version="18.0",
                package_specs={"winget": "OpenJS.NodeJS.LTS", "choco": "nodejs-lts",
                               "apt": "nodejs", "dnf": "nodejs", "brew": "node"},
            ),
            ToolSpec(name="npm", cmd="npm", install_func="_install_npm"),
        ]

    def _install_npm(self) -> bool:
        write_status("FAIL", "npm이 Node.js 설치에 포함되지 않았습니다. Node.js를 재설치하세요.")
        return False

    def verify(self) -> None:
        for cmd_info in [("node", "--version"), ("npm", "--version")]:
            cmd, arg = cmd_info
            if command_exists(cmd):
                ver = extract_version(get_command_output([cmd, arg]))
                write_status("OK", f"{cmd}: {ver or 'found'}")
            else:
                write_status("FAIL", f"{cmd}: 찾을 수 없음")


class DjangoInstaller(PlatformInstaller):
    platform_name = "Django/Python"

    def __init__(self, project_root: Path, check_only: bool = False):
        super().__init__(project_root, check_only)
        self.tools = [
            ToolSpec(
                name="Python", cmd="python", min_version="3.11",
                package_specs={"winget": "Python.Python.3.11", "choco": "python311",
                               "apt": "python3", "dnf": "python3", "brew": "python@3.11"},
            ),
            ToolSpec(name="poetry", cmd="poetry", install_func="_install_poetry"),
            ToolSpec(name="ruff", cmd="ruff", install_func="_install_pip_tool_ruff"),
            ToolSpec(name="mypy", cmd="mypy", install_func="_install_pip_tool_mypy"),
            ToolSpec(name="Black", cmd="black", install_func="_install_pip_tool_black"),
        ]

    def post_install(self) -> None:
        # Upgrade pip if python was just installed
        if not self.check_only and command_exists("python"):
            run_cmd(["python", "-m", "pip", "install", "--upgrade", "pip", "--quiet"],
                    description="pip upgrade")

    def _install_poetry(self) -> bool:
        if not command_exists("pip") and not command_exists("python"):
            write_status("FAIL", "pip이 없어 poetry를 설치할 수 없습니다")
            return False
        write_status("INSTALL", "poetry 설치 중 (pip)...")
        pip_cmd = "pip" if command_exists("pip") else "python -m pip"
        if pip_cmd == "pip":
            ok = run_cmd(["pip", "install", "poetry", "--quiet"])
        else:
            ok = run_cmd(["python", "-m", "pip", "install", "poetry", "--quiet"])
        if ok:
            refresh_path_env()
            if not command_exists("poetry"):
                # Add Python scripts dir to PATH
                output = get_command_output(
                    ["python", "-c", "import sysconfig; print(sysconfig.get_path('scripts'))"]
                )
                if output and Path(output.strip()).exists():
                    add_to_path(output.strip())
            if command_exists("poetry"):
                write_status("OK", "poetry 설치 완료")
                return True
        write_status("FAIL", "poetry 설치 실패")
        return False

    def _pip_install(self, package: str, display: str) -> bool:
        if not command_exists("python"):
            write_status("FAIL", f"python이 없어 {display}를 설치할 수 없습니다")
            return False
        write_status("INSTALL", f"{display} 설치 중...")
        ok = run_cmd(["python", "-m", "pip", "install", package, "--quiet"])
        if ok:
            write_status("OK", f"{display} 설치 완료")
        return ok

    def _install_pip_tool_ruff(self) -> bool:
        return self._pip_install("ruff", "ruff")

    def _install_pip_tool_mypy(self) -> bool:
        return self._pip_install("mypy", "mypy")

    def _install_pip_tool_black(self) -> bool:
        return self._pip_install("black", "Black")

    def verify(self) -> None:
        for cmd_info in [("python", "--version"), ("pip", "--version"),
                         ("poetry", "--version"), ("ruff", "--version"),
                         ("mypy", "--version"), ("black", "--version")]:
            cmd, arg = cmd_info
            if command_exists(cmd):
                ver = extract_version(get_command_output([cmd, arg]))
                write_status("OK", f"{cmd}: {ver or 'found'}")
            else:
                write_status("FAIL", f"{cmd}: 찾을 수 없음")


class NestJSInstaller(PlatformInstaller):
    platform_name = "NestJS"

    def __init__(self, project_root: Path, check_only: bool = False):
        super().__init__(project_root, check_only)
        self.tools = [
            ToolSpec(
                name="Node.js", cmd="node", min_version="18.0",
                package_specs={"winget": "OpenJS.NodeJS.LTS", "choco": "nodejs-lts",
                               "apt": "nodejs", "dnf": "nodejs", "brew": "node"},
            ),
            ToolSpec(name="pnpm", cmd="pnpm", install_func="_install_pnpm"),
            ToolSpec(name="@nestjs/cli", cmd="nest", install_func="_install_nest_cli"),
            ToolSpec(name="TypeScript", cmd="tsc", install_func="_install_typescript"),
        ]

    def _install_pnpm(self) -> bool:
        if not command_exists("npm"):
            write_status("FAIL", "npm이 없어 pnpm을 설치할 수 없습니다")
            return False
        write_status("INSTALL", "pnpm 설치 중 (npm)...")
        ok = run_cmd(["npm", "install", "-g", "pnpm"],
                     shell=(sys.platform == "win32"))
        if ok:
            refresh_path_env()
            write_status("OK", "pnpm 설치 완료")
        return ok

    def _install_nest_cli(self) -> bool:
        pm = "pnpm" if command_exists("pnpm") else "npm"
        if not command_exists(pm):
            write_status("FAIL", f"{pm}이 없어 @nestjs/cli를 설치할 수 없습니다")
            return False
        write_status("INSTALL", f"@nestjs/cli 설치 중 ({pm})...")
        if pm == "pnpm":
            ok = run_cmd(["pnpm", "add", "-g", "@nestjs/cli"],
                         shell=(sys.platform == "win32"))
        else:
            ok = run_cmd(["npm", "install", "-g", "@nestjs/cli"],
                         shell=(sys.platform == "win32"))
        if ok:
            refresh_path_env()
            write_status("OK", "@nestjs/cli 설치 완료")
        return ok

    def _install_typescript(self) -> bool:
        pm = "pnpm" if command_exists("pnpm") else "npm"
        if not command_exists(pm):
            write_status("FAIL", f"{pm}이 없어 TypeScript를 설치할 수 없습니다")
            return False
        write_status("INSTALL", f"TypeScript 설치 중 ({pm})...")
        if pm == "pnpm":
            ok = run_cmd(["pnpm", "add", "-g", "typescript"],
                         shell=(sys.platform == "win32"))
        else:
            ok = run_cmd(["npm", "install", "-g", "typescript"],
                         shell=(sys.platform == "win32"))
        if ok:
            refresh_path_env()
            write_status("OK", "TypeScript 설치 완료")
        return ok

    def verify(self) -> None:
        for cmd_info in [("node", "--version"), ("pnpm", "--version"),
                         ("tsc", "--version")]:
            cmd, arg = cmd_info
            if command_exists(cmd):
                ver = extract_version(get_command_output([cmd, arg]))
                write_status("OK", f"{cmd}: {ver or 'found'}")
            else:
                write_status("FAIL", f"{cmd}: 찾을 수 없음")
        if command_exists("nest"):
            ver = extract_version(get_command_output(["nest", "--version"]))
            write_status("OK", f"nest: {ver or 'found'}")
        else:
            write_status("FAIL", "nest: 찾을 수 없음")


class DotNetInstaller(PlatformInstaller):
    platform_name = "ASP.NET Core"

    def __init__(self, project_root: Path, check_only: bool = False):
        super().__init__(project_root, check_only)
        self.tools = [
            ToolSpec(name=".NET SDK 8.0", cmd="", install_func="_install_dotnet"),
            ToolSpec(name="dotnet-ef", cmd="", install_func="_install_dotnet_ef"),
        ]

    def _process_tool(self, tool: ToolSpec) -> None:
        if tool.name == ".NET SDK 8.0":
            self._check_dotnet()
        elif tool.name == "dotnet-ef":
            self._check_dotnet_ef()
        else:
            super()._process_tool(tool)

    def _check_dotnet(self) -> None:
        write_status("CHECK", ".NET SDK 확인 중...")
        has_net8 = False
        if command_exists("dotnet"):
            output = get_command_output(["dotnet", "--list-sdks"])
            if output and "8." in output:
                has_net8 = True
        if has_net8:
            ver = extract_version(get_command_output(["dotnet", "--version"]))
            write_status("SKIP", f".NET SDK 8.x 이미 설치됨: {ver}")
            self.result.add("SKIP", ".NET SDK", ver or "")
        elif self.check_only:
            write_status("FAIL", ".NET SDK 8.0 없음")
            self.result.add("FAIL", ".NET SDK")
        else:
            ok = self._install_dotnet()
            self.result.add("OK" if ok else "FAIL", ".NET SDK")

    def _install_dotnet(self) -> bool:
        ok = install_package(
            {"winget": "Microsoft.DotNet.SDK.8", "choco": "dotnet-sdk",
             "apt": "dotnet-sdk-8.0", "dnf": "dotnet-sdk-8.0", "brew": "dotnet@8"},
            ".NET SDK 8.0",
        )
        if ok:
            refresh_path_env()
        return ok

    def _check_dotnet_ef(self) -> None:
        write_status("CHECK", "dotnet-ef 확인 중...")
        has_ef = False
        if command_exists("dotnet"):
            output = get_command_output(["dotnet", "tool", "list", "--global"])
            if output and "dotnet-ef" in output:
                has_ef = True
        if has_ef:
            write_status("SKIP", "dotnet-ef 이미 설치됨")
            self.result.add("SKIP", "dotnet-ef")
        elif self.check_only:
            write_status("FAIL", "dotnet-ef 없음")
            self.result.add("FAIL", "dotnet-ef")
        else:
            ok = self._install_dotnet_ef()
            self.result.add("OK" if ok else "FAIL", "dotnet-ef")

    def _install_dotnet_ef(self) -> bool:
        if not command_exists("dotnet"):
            write_status("FAIL", ".NET SDK가 없어 dotnet-ef를 설치할 수 없습니다")
            return False
        write_status("INSTALL", "dotnet-ef 설치 중...")
        ok = run_cmd(["dotnet", "tool", "install", "--global", "dotnet-ef"])
        if not ok:
            # Maybe already installed — try update
            ok = run_cmd(["dotnet", "tool", "update", "--global", "dotnet-ef"])
        if ok:
            refresh_path_env()
            dotnet_tools = os.path.join(os.path.expanduser("~"), ".dotnet", "tools")
            if os.path.exists(dotnet_tools):
                add_to_path(dotnet_tools)
            write_status("OK", "dotnet-ef 설치 완료")
        return ok

    def verify(self) -> None:
        if command_exists("dotnet"):
            ver = extract_version(get_command_output(["dotnet", "--version"]))
            write_status("OK", f"dotnet: {ver or 'found'}")
        else:
            write_status("FAIL", "dotnet: 찾을 수 없음")
        if command_exists("dotnet-ef"):
            ver = extract_version(get_command_output(["dotnet-ef", "--version"]))
            write_status("OK", f"dotnet-ef: {ver or 'found'}")
        else:
            # Check in ~/.dotnet/tools
            ef_path = Path(os.path.expanduser("~")) / ".dotnet" / "tools" / \
                      ("dotnet-ef.exe" if sys.platform == "win32" else "dotnet-ef")
            if ef_path.exists():
                write_status("OK", f"dotnet-ef: {ef_path}")
            else:
                write_status("FAIL", "dotnet-ef: 찾을 수 없음")


# Thin installers (no OS-specific branching) -- available directly from _common
THIN_INSTALLERS = {
    "react": ReactInstaller,
    "django": DjangoInstaller,
    "nestjs": NestJSInstaller,
    "dotnet": DotNetInstaller,
}

# Build verification platforms
BUILD_VERIFY_PLATFORMS = {
    "cpp": ["cpp", "driver"],
    "springboot": ["springboot"],
    "react": ["react"],
}


# =============================================================================
# [4] Build Sample Verification
# =============================================================================

def get_skill_root() -> Path:
    """Get the dev-setup skill root directory.

    _common.py lives in scripts/, so parent.parent = dev-setup/.
    """
    return Path(__file__).resolve().parent.parent


def find_kit_version(inc_base: Path, marker_file: str) -> Optional[str]:
    """Find the latest Windows Kit version that contains marker_file.

    Module-level function extracted from CppInstaller._find_kit_version so that
    _verify_driver (and any other caller) can use it without importing CppInstaller.
    """
    if not inc_base.exists():
        return None
    for d in sorted(inc_base.iterdir(), reverse=True):
        if d.is_dir() and (d / marker_file).exists():
            return d.name
    return None


def verify_build_sample(platform: str, project_root: Path) -> bool:
    """Verify build by compiling a sample project."""
    skill_root = get_skill_root()
    sample_dir = skill_root / "assets" / "samples" / platform
    if not sample_dir.exists():
        write_status("SKIP", f"빌드 검증 샘플 없음: {platform}")
        return True

    temp_dir = Path(tempfile.gettempdir()) / f"dev-setup-verify-{platform}"
    try:
        if temp_dir.exists():
            shutil.rmtree(temp_dir)
        shutil.copytree(sample_dir, temp_dir)

        if platform == "cpp":
            return _verify_cpp(temp_dir)
        elif platform == "springboot":
            return _verify_springboot(temp_dir)
        elif platform == "react":
            return _verify_react(temp_dir)
        elif platform == "driver":
            return _verify_driver(temp_dir)
        else:
            write_status("SKIP", f"빌드 검증 미지원 플랫폼: {platform}")
            return True
    except Exception as e:
        write_status("FAIL", f"빌드 검증 중 오류: {e}")
        return False
    finally:
        if temp_dir.exists():
            shutil.rmtree(temp_dir, ignore_errors=True)


def _verify_cpp(temp_dir: Path) -> bool:
    """Verify C++/CMake build."""
    write_status("CHECK", "CMake + C++ 빌드 테스트...")
    if not command_exists("cmake"):
        write_status("FAIL", "cmake 명령을 찾을 수 없습니다")
        return False

    build_dir = temp_dir / "build"
    gen_args = ["cmake", "-S", str(temp_dir), "-B", str(build_dir)]
    if command_exists("ninja"):
        gen_args.extend(["-G", "Ninja"])

    if not run_cmd(gen_args):
        write_status("FAIL", "CMake configure 실패")
        return False
    write_status("OK", "CMake configure 성공")

    if not run_cmd(["cmake", "--build", str(build_dir)]):
        write_status("FAIL", "CMake 빌드 실패")
        return False
    write_status("OK", "CMake 빌드 성공")

    # Find and run executable
    for f in build_dir.rglob("build_verify*"):
        if f.is_file() and (f.suffix in (".exe", "") or not f.suffix):
            output = get_command_output([str(f)])
            if output and "Build verification passed!" in output:
                write_status("OK", 'build_verify 실행 성공: "Build verification passed!"')
                return True
    write_status("FAIL", "빌드 결과 실행 파일을 찾을 수 없음")
    return False


def _verify_springboot(temp_dir: Path) -> bool:
    """Verify Spring Boot build."""
    write_status("CHECK", "Spring Boot 빌드 테스트...")

    # JDK auto-detect
    jdk_bin = None
    java_home = os.environ.get("JAVA_HOME", "")
    javac_name = "javac.exe" if sys.platform == "win32" else "javac"
    java_name = "java.exe" if sys.platform == "win32" else "java"

    if java_home and (Path(java_home) / "bin" / javac_name).exists():
        jdk_bin = str(Path(java_home) / "bin")
    else:
        jdk_path = find_jdk(17)
        if jdk_path:
            jdk_bin = str(Path(jdk_path) / "bin")
            os.environ["JAVA_HOME"] = jdk_path

    javac_cmd = os.path.join(jdk_bin, javac_name) if jdk_bin else ("javac" if command_exists("javac") else None)
    java_cmd = os.path.join(jdk_bin, java_name) if jdk_bin else "java"

    if command_exists("gradle"):
        write_status("CHECK", "Gradle + JDK 빌드 테스트...")
        if not run_cmd(["gradle", "wrapper", "--quiet"], cwd=str(temp_dir)):
            write_status("FAIL", "Gradle wrapper 생성 실패")
            return False
        gradlew = str(temp_dir / ("gradlew.bat" if sys.platform == "win32" else "gradlew"))
        if not run_cmd([gradlew, "build", "--quiet"], cwd=str(temp_dir)):
            write_status("FAIL", "Gradle 빌드 실패")
            return False
        class_path = temp_dir / "build" / "classes" / "java" / "main"
        if not class_path.exists():
            write_status("FAIL", f"빌드 출력 디렉토리 없음: {class_path}")
            return False
        write_status("OK", "Gradle 빌드 성공")
    elif javac_cmd:
        write_status("CHECK", "javac 빌드 테스트 (Gradle 미설치, javac fallback)...")
        out_dir = temp_dir / "build" / "classes"
        out_dir.mkdir(parents=True, exist_ok=True)
        source = temp_dir / "src" / "main" / "java" / "verify" / "BuildVerify.java"
        if not run_cmd([javac_cmd, "-d", str(out_dir), str(source)]):
            write_status("FAIL", "javac 컴파일 실패")
            return False
        class_path = out_dir
        write_status("OK", "javac 컴파일 성공")
    else:
        write_status("FAIL", "gradle, javac 모두 찾을 수 없습니다")
        return False

    # Run verification
    output = get_command_output([java_cmd, "-cp", str(class_path), "verify.BuildVerify"])
    if output and "Build verification passed!" in output:
        write_status("OK", 'java -cp 실행 성공: "Build verification passed!"')
        return True
    write_status("FAIL", f"빌드 결과 실행 실패: {output}")
    return False


def _verify_react(temp_dir: Path) -> bool:
    """Verify React/Vite build."""
    write_status("CHECK", "React/Vite 빌드 테스트...")
    if not command_exists("npm"):
        write_status("FAIL", "npm 명령을 찾을 수 없습니다")
        return False

    use_shell = sys.platform == "win32"
    write_status("INSTALL", "npm install 실행 중...")
    if not run_cmd(["npm", "install"], cwd=str(temp_dir), shell=use_shell):
        write_status("FAIL", "npm install 실패")
        return False
    write_status("OK", "npm install 성공")

    if not run_cmd(["npm", "run", "build"], cwd=str(temp_dir), shell=use_shell):
        write_status("FAIL", "npm run build 실패")
        return False

    if (temp_dir / "dist" / "index.html").exists():
        write_status("OK", "React/Vite 빌드 성공 (dist/index.html 생성)")
        return True
    write_status("FAIL", "빌드는 성공했으나 dist/index.html을 찾을 수 없음")
    return False


def _verify_driver(temp_dir: Path) -> bool:
    """Verify WDK driver build (Windows only)."""
    if sys.platform != "win32":
        write_status("SKIP", "WDK 드라이버 빌드 — Windows 전용")
        return True

    write_status("CHECK", "WDK 드라이버 빌드 테스트 (MSBuild)...")

    msbuild = find_msbuild()
    if not msbuild:
        write_status("FAIL", "MSBuild를 찾을 수 없습니다")
        return False

    # Check WDK — uses module-level find_kit_version instead of CppInstaller._find_kit_version
    inc_base = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / \
               "Windows Kits" / "10" / "Include"
    wdk_ver = find_kit_version(inc_base, "km/ntddk.h")
    if not wdk_ver:
        write_status("FAIL", "WDK가 설치되어 있지 않습니다")
        return False

    vcxproj = temp_dir / "build-verify.vcxproj"
    if not vcxproj.exists():
        write_status("FAIL", "build-verify.vcxproj 샘플 없음")
        return False

    ok = run_cmd([msbuild, str(vcxproj), f"/p:Configuration=Release",
                  "/p:Platform=x64", f"/p:WindowsTargetPlatformVersion={wdk_ver}",
                  "/v:minimal"])
    if not ok:
        write_status("FAIL", "WDK 드라이버 MSBuild 실패")
        return False

    sys_file = temp_dir / "build" / "build-verify.sys"
    if sys_file.exists():
        write_status("OK", "WDK 드라이버 빌드 성공 (build-verify.sys 생성)")
        return True
    write_status("FAIL", "빌드는 성공했으나 build-verify.sys를 찾을 수 없음")
    return False
