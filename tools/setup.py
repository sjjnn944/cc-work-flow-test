#!/usr/bin/env python3
"""Thin wrapper — delegates to .claude/skills/dev-setup/scripts/setup.py."""

import subprocess
import sys
from pathlib import Path

SCRIPTS_DIR = (
    Path(__file__).resolve().parent.parent
    / ".claude" / "skills" / "dev-setup" / "scripts"
)

sys.exit(
    subprocess.call(
        [sys.executable, str(SCRIPTS_DIR / "setup.py")] + sys.argv[1:],
        cwd=str(SCRIPTS_DIR),
    )
)
