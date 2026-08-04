import os
import sys
from pathlib import Path

_hooks_dir = str(Path(__file__).resolve().parent.parent / "scripts")
if _hooks_dir not in sys.path:
    sys.path.insert(0, _hooks_dir)
