from __future__ import annotations

import os


def _get_bool_env(name: str, default: bool) -> bool:
    val = os.environ.get(name)
    if val is None:
        return default
    return val.strip().lower() in {"1", "true", "yes", "on"}


def _get_int_env(name: str, default: int) -> int:
    val = os.environ.get(name)
    if val is None:
        return default
    try:
        return int(val)
    except ValueError:
        return default


job_timeout: int = _get_int_env("CHIA_TEST_JOB_TIMEOUT", 70)
checkout_blocks_and_plots: bool = _get_bool_env("CHIA_TEST_CHECKOUT_BLOCKS_AND_PLOTS", True)
