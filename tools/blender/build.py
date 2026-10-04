"""Builds the game's models in Blender and exports them to assets/models/.

Run from the repository root (Blender is not on PATH; see docs/models.md):
    blender -b --factory-startup --python tools/blender/build.py -- [name ...]
With names, only those models are rebuilt and the catalogues are left alone.
"""

import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
for module in ("monsters", "loot", "decor"):
    try:
        importlib.import_module(module).main(set(args))
    except ModuleNotFoundError as error:
        if error.name != module:
            raise
