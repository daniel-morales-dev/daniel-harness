# Config helpers for dh_data tools
import os
from pathlib import Path


def get_harness_dir():
    return Path(os.environ.get("DANIEL_HARNESS_CONFIG_DIR", "~/.config/daniel-harness")).expanduser()


def load_yaml(path):
    import yaml
    with open(path) as f:
        return yaml.safe_load(f)


def find_profile(connections, profile_id):
    for p in connections.get("profiles", []):
        if p.get("id") == profile_id:
            return p
    return None
