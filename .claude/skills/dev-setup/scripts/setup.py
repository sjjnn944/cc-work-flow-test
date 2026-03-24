#!/usr/bin/env python3
"""
DLP Project Cross-Platform Dev Environment Setup Script

Main entry point that detects the OS and dispatches to OS-specific installers.

Usage:
    python tools/setup.py --platform cpp,springboot
    python tools/setup.py --platform react --check-only
    python tools/setup.py --all
    python tools/setup.py --all --check-only
"""

import argparse
import sys
from pathlib import Path

from _common import (
    BUILD_VERIFY_PLATFORMS,
    InstallResult,
    THIN_INSTALLERS,
    detect_os,
    verify_build_sample,
    write_header,
    write_status,
)


def _get_platform_installers() -> dict:
    """Import OS-specific installers based on detected OS."""
    os_name = detect_os()

    if os_name == "windows":
        from windows import (
            CppInstaller,
            SpringBootInstaller,
            GoInstaller,
            RustInstaller,
        )
    elif os_name == "macos":
        from macos import (
            CppInstaller,
            SpringBootInstaller,
            GoInstaller,
            RustInstaller,
        )
    else:
        from linux import (
            CppInstaller,
            SpringBootInstaller,
            GoInstaller,
            RustInstaller,
        )

    installers = {
        "cpp": CppInstaller,
        "springboot": SpringBootInstaller,
        "go": GoInstaller,
        "rust": RustInstaller,
    }
    installers.update(THIN_INSTALLERS)
    return installers


def main():
    parser = argparse.ArgumentParser(
        description="DLP Project Cross-Platform Dev Environment Setup",
    )
    parser.add_argument(
        "--project-root",
        help="Project root directory (default: auto-detect)",
    )
    parser.add_argument(
        "--platform",
        help="Comma-separated platform list (e.g., cpp,springboot,react)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Install all supported platforms",
    )
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="Check installation status only, do not install",
    )
    args = parser.parse_args()

    # Build installer registry
    platform_installers = _get_platform_installers()

    # Determine project root
    if args.project_root:
        project_root = Path(args.project_root).resolve()
    else:
        # scripts/setup.py → dev-setup/scripts/ → project root
        project_root = Path(__file__).resolve().parent.parent.parent.parent.parent

    if not project_root.exists():
        print(f"[FAIL] Project root not found: {project_root}")
        sys.exit(1)

    # Determine platforms
    if args.platform and args.all:
        print("[FAIL] --platform과 --all은 동시에 사용할 수 없습니다.")
        sys.exit(1)

    if args.platform:
        platforms = [p.strip().lower() for p in args.platform.split(",")]
        invalid = [p for p in platforms if p not in platform_installers]
        if invalid:
            print(f"[FAIL] Unknown platforms: {', '.join(invalid)}")
            print(f"  Available: {', '.join(platform_installers.keys())}")
            sys.exit(1)
    elif args.all:
        platforms = list(platform_installers.keys())
    else:
        available = ", ".join(platform_installers.keys())
        print("[FAIL] --platform 또는 --all을 지정해야 합니다.")
        print()
        print("사용법:")
        print(f"  python tools/setup.py --platform cpp,springboot   # 특정 플랫폼")
        print(f"  python tools/setup.py --all                       # 전체 플랫폼")
        print(f"  python tools/setup.py --platform cpp --check-only # 확인만")
        print()
        print(f"지원 플랫폼: {available}")
        sys.exit(1)

    # Print header
    os_name = detect_os()
    print(f"\n{'='*60}")
    print(f"  dev-setup: {'확인' if args.check_only else '설치'} 모드")
    print(f"  OS: {os_name}")
    print(f"  프로젝트 루트: {project_root}")
    print(f"  대상 플랫폼: {', '.join(platforms)}")
    print(f"{'='*60}")

    # Run installers
    all_results: list[tuple[str, InstallResult]] = []

    for platform in platforms:
        installer_cls = platform_installers[platform]
        installer = installer_cls(project_root, check_only=args.check_only)
        result = installer.run()
        all_results.append((platform, result))

        # Build sample verification (after install, not in check-only mode)
        if not args.check_only and platform in BUILD_VERIFY_PLATFORMS:
            write_header(f"{platform} 빌드 검증")
            for verify_platform in BUILD_VERIFY_PLATFORMS[platform]:
                verify_build_sample(verify_platform, project_root)

    # Final summary
    print(f"\n{'='*60}")
    print("  설치 결과 요약")
    print(f"{'='*60}")

    total_ok = 0
    total_fail = 0
    total_skip = 0

    for platform, result in all_results:
        ok = result.total_ok
        fail = result.total_fail
        skip = len(result.skip)
        total_ok += ok
        total_fail += fail
        total_skip += skip
        status = "OK" if fail == 0 else "FAIL"
        write_status(status,
                     f"{platform}: 성공 {ok} / 실패 {fail} / 건너뜀 {skip}")

    print(f"\n  합계: 성공 {total_ok} / 실패 {total_fail} / 건너뜀 {total_skip}")
    print(f"{'='*60}")

    sys.exit(1 if total_fail > 0 else 0)


if __name__ == "__main__":
    main()
