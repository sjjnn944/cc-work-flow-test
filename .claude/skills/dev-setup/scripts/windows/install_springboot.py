import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Optional

from _common import (
    PlatformInstaller, ToolSpec, InstallResult,
    write_status, write_header, command_exists, get_command_output,
    extract_version, check_min_version, run_cmd, detect_os,
    install_package, add_to_path, refresh_path_env,
    find_jdk, get_java_major_version, _send_setting_change,
)


class SpringBootInstaller(PlatformInstaller):
    platform_name = "Spring Boot"

    def __init__(self, project_root: Path, check_only: bool = False):
        super().__init__(project_root, check_only)
        self.tools = [
            ToolSpec(name="JDK 17+", cmd="", install_func="_install_jdk"),
            ToolSpec(name="Gradle", cmd="", install_func="_install_gradle"),
        ]

    def _process_tool(self, tool: ToolSpec) -> None:
        if tool.name == "JDK 17+":
            self._check_jdk()
        elif tool.name == "Gradle":
            self._check_gradle()
        else:
            super()._process_tool(tool)

    def _check_jdk(self) -> None:
        write_status("CHECK", "JDK 17+ 확인 중...")
        min_major = 17

        # Check PATH java
        has_jdk = False
        if command_exists("java"):
            major = get_java_major_version("java")
            if major >= min_major:
                has_jdk = True

        # Fallback: filesystem search
        jdk_path = find_jdk(min_major)
        if jdk_path:
            jmajor = get_java_major_version(
                str(Path(jdk_path) / "bin" / ("java.exe" if sys.platform == "win32" else "java"))
            )
            if jmajor >= min_major:
                has_jdk = True

        if has_jdk and command_exists("java") and get_java_major_version("java") >= min_major:
            major = get_java_major_version("java")
            write_status("SKIP", f"JDK {major} 이미 설치됨 (PATH)")
            self.result.add("SKIP", "JDK", str(major))
        elif has_jdk:
            write_status("CHECK", "JDK 17+ 설치됨 (PATH 우선순위 문제)")
            self.result.add("SKIP", "JDK", "installed, PATH issue")
        elif self.check_only:
            write_status("FAIL", "JDK 17+ 없음")
            self.result.add("FAIL", "JDK")
            return
        else:
            self._install_jdk()

        # Set JAVA_HOME
        self._setup_java_home(min_major)

    def _install_jdk(self) -> bool:
        ok = install_package(
            {"winget": "Microsoft.OpenJDK.17", "choco": "microsoft-openjdk17",
             "apt": "openjdk-17-jdk", "dnf": "java-17-openjdk-devel",
             "brew": "openjdk@17"},
            "JDK 17",
        )
        if ok:
            refresh_path_env()
        return ok

    def _setup_java_home(self, min_major: int) -> None:
        """Set JAVA_HOME environment variable."""
        write_status("CHECK", "JAVA_HOME 확인 중...")

        # Check current JAVA_HOME validity
        java_home = os.environ.get("JAVA_HOME", "")
        if java_home and Path(java_home).exists():
            java_exe = Path(java_home) / "bin" / ("java.exe" if sys.platform == "win32" else "java")
            if java_exe.exists() and get_java_major_version(str(java_exe)) >= min_major:
                os.environ["JAVA_HOME"] = java_home
                write_status("SKIP", f"JAVA_HOME 설정됨: {java_home}")
                return

        if self.check_only:
            write_status("FAIL", f"JAVA_HOME 미설정 또는 JDK {min_major}+ 아님")
            return

        # Find and set
        jdk_path = find_jdk(min_major)
        if jdk_path:
            os.environ["JAVA_HOME"] = jdk_path
            if sys.platform == "win32":
                try:
                    import winreg
                    key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,
                                         r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
                                         0, winreg.KEY_ALL_ACCESS)
                    winreg.SetValueEx(key, "JAVA_HOME", 0, winreg.REG_SZ, jdk_path)
                    winreg.CloseKey(key)
                    jdk_bin = str(Path(jdk_path) / "bin")
                    add_to_path(jdk_bin)
                    _send_setting_change()
                except PermissionError:
                    # Try user scope
                    try:
                        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Environment",
                                             0, winreg.KEY_ALL_ACCESS)
                        winreg.SetValueEx(key, "JAVA_HOME", 0, winreg.REG_SZ, jdk_path)
                        winreg.CloseKey(key)
                    except Exception:
                        pass
                except Exception:
                    pass
            else:
                rc = "$HOME/.zshrc" if sys.platform == "darwin" else "$HOME/.bashrc"
                rc_path = os.path.expandvars(rc)
                try:
                    existing = Path(rc_path).read_text() if Path(rc_path).exists() else ""
                    if "JAVA_HOME" not in existing:
                        with open(rc_path, "a") as f:
                            f.write(f'\nexport JAVA_HOME="{jdk_path}"\n')
                except Exception:
                    pass

            write_status("OK", f"JAVA_HOME 설정: {jdk_path}")
            refresh_path_env()
        else:
            write_status("FAIL", f"JDK {min_major}+ 경로를 찾을 수 없음")

    def _check_gradle(self) -> None:
        write_status("CHECK", "Gradle 확인 중...")
        gradle_cmd = self._find_gradle()
        if gradle_cmd:
            ver = extract_version(get_command_output([gradle_cmd, "--version"]))
            write_status("SKIP", f"Gradle 설치됨: {ver or 'found'}")
            self.result.add("SKIP", "Gradle", ver or "")
        elif self.check_only:
            write_status("FAIL", "Gradle 없음")
            self.result.add("FAIL", "Gradle")
        else:
            ok = self._install_gradle()
            self.result.add("OK" if ok else "FAIL", "Gradle")

    def _find_gradle(self) -> Optional[str]:
        """Find gradle command."""
        if command_exists("gradle"):
            return "gradle"
        if sys.platform == "win32":
            # Check user-local install
            gradle_dir = Path(os.environ.get("USERPROFILE", "")) / "gradle"
            if gradle_dir.exists():
                for bat in sorted(gradle_dir.rglob("gradle.bat"), reverse=True):
                    if bat.parent.name == "bin":
                        add_to_path(str(bat.parent))
                        return str(bat)
        return None

    def _install_gradle(self) -> bool:
        # Try choco first on Windows
        if detect_os() == "windows":
            if command_exists("choco"):
                ok = install_package({"choco": "gradle"}, "Gradle")
                if ok:
                    refresh_path_env()
                    return True
            # Manual download fallback
            return self._install_gradle_manual("8.5")
        else:
            return install_package(
                {"apt": "gradle", "dnf": "gradle", "brew": "gradle"},
                "Gradle",
            )

    def _install_gradle_manual(self, version: str) -> bool:
        """Download and install Gradle manually."""
        gradle_dir = Path(os.environ.get("USERPROFILE", os.path.expanduser("~"))) / "gradle"
        extract_dir = gradle_dir / f"gradle-{version}"
        gradle_bat = extract_dir / "bin" / ("gradle.bat" if sys.platform == "win32" else "gradle")

        if gradle_bat.exists():
            add_to_path(str(extract_dir / "bin"))
            write_status("SKIP", f"Gradle {version} already installed")
            return True

        import urllib.request
        zip_url = f"https://services.gradle.org/distributions/gradle-{version}-bin.zip"
        zip_path = Path(tempfile.gettempdir()) / f"gradle-{version}-bin.zip"

        write_status("INSTALL", f"Gradle {version} 다운로드 중...")
        try:
            gradle_dir.mkdir(parents=True, exist_ok=True)
            urllib.request.urlretrieve(zip_url, str(zip_path))
            write_status("OK", "다운로드 완료")

            write_status("INSTALL", "압축 해제 중...")
            with zipfile.ZipFile(str(zip_path), "r") as zf:
                zf.extractall(str(gradle_dir))
            zip_path.unlink(missing_ok=True)

            if gradle_bat.exists():
                add_to_path(str(extract_dir / "bin"))
                refresh_path_env()
                write_status("OK", f"Gradle {version} 설치 완료")
                return True
            write_status("FAIL", "Gradle 바이너리를 찾을 수 없음")
            return False
        except Exception as e:
            write_status("FAIL", f"Gradle 수동 설치 실패: {e}")
            return False

    def verify(self) -> None:
        java_exe = "java"
        java_home = os.environ.get("JAVA_HOME", "")
        if java_home:
            candidate = Path(java_home) / "bin" / ("java.exe" if sys.platform == "win32" else "java")
            if candidate.exists():
                java_exe = str(candidate)
        major = get_java_major_version(java_exe)
        if major >= 17:
            ver_out = get_command_output([java_exe, "-version"])
            first_line = ver_out.split("\n")[0] if ver_out else ""
            write_status("OK", f"java: {first_line}")
        elif command_exists("java"):
            write_status("FAIL", "java: JDK 17+ 아님")
        else:
            write_status("FAIL", "java: 찾을 수 없음")

        # javac
        javac = "javac"
        if java_home:
            candidate = Path(java_home) / "bin" / ("javac.exe" if sys.platform == "win32" else "javac")
            if candidate.exists():
                javac = str(candidate)
        if command_exists(javac) or Path(javac).exists():
            ver = extract_version(get_command_output([javac, "-version"]))
            write_status("OK", f"javac: {ver or 'found'}")
        else:
            write_status("FAIL", "javac: 찾을 수 없음")

        # JAVA_HOME
        jh = os.environ.get("JAVA_HOME", "")
        if jh and Path(jh).exists():
            write_status("OK", f"JAVA_HOME: {jh}")
        else:
            write_status("FAIL", f"JAVA_HOME: {'경로 없음: ' + jh if jh else '미설정'}")

        # Gradle
        gradle_cmd = self._find_gradle()
        if gradle_cmd:
            ver = extract_version(get_command_output([gradle_cmd, "--version"]))
            write_status("OK", f"gradle: {ver or 'found'}")
        else:
            write_status("FAIL", "gradle: 찾을 수 없음")
