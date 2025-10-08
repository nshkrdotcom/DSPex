# Copyright (c) 2025 Lakshya A Agrawal and the GEPA contributors
# https://github.com/gepa-ai/gepa

from typing import Any


def initialize_wandb(wandb_api_key: str | None = None, wandb_init_kwargs: dict[str, Any] | None = None):
    try:
        import wandb  # type: ignore
        if wandb_api_key:
            wandb.login(key=wandb_api_key, verify=True)
        else:
            wandb.login()
    except ImportError:
        raise ImportError("wandb is not installed. Please install it or set use_wandb=False.")
    except Exception as e:
        raise RuntimeError(f"Error logging into wandb: {e}")
    if wandb_init_kwargs is None:
        wandb_init_kwargs = {}
    wandb_run = wandb.init(**wandb_init_kwargs)
    return wandb_run
