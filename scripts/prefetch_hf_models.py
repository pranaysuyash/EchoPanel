#!/usr/bin/env python3
"""
Prefetch pinned Hugging Face models into the local cache.

Use this before a subscription window ends to maximize local availability.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from huggingface_hub import snapshot_download


DEFAULT_MANIFEST = Path("server/config/hf_model_manifest.json")
DEFAULT_RECEIPT_DIR = Path("docs/audit/artifacts")


@dataclass
class ModelSpec:
    model_id: str
    revision: str
    group: str
    gated: bool
    prefetch: bool

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "ModelSpec":
        return cls(
            model_id=str(payload["id"]),
            revision=str(payload["revision"]),
            group=str(payload.get("group", "default")),
            gated=bool(payload.get("gated", False)),
            prefetch=bool(payload.get("prefetch", True)),
        )


def _load_manifest(path: Path) -> list[ModelSpec]:
    data = json.loads(path.read_text(encoding="utf-8"))
    models = [ModelSpec.from_dict(entry) for entry in data.get("models", [])]
    return [model for model in models if model.prefetch]


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prefetch pinned Hugging Face models")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument(
        "--group",
        action="append",
        default=[],
        help="Filter by model group. Repeat for multiple groups.",
    )
    parser.add_argument(
        "--model",
        action="append",
        default=[],
        help="Filter by exact model id. Repeat for multiple models.",
    )
    parser.add_argument("--cache-dir", type=Path, default=None)
    parser.add_argument("--token-env", default="ECHOPANEL_HF_TOKEN")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--receipt", type=Path, default=None)
    return parser.parse_args()


def _select_models(
    models: list[ModelSpec],
    groups: set[str],
    model_ids: set[str],
) -> list[ModelSpec]:
    selected = []
    for model in models:
        if groups and model.group not in groups:
            continue
        if model_ids and model.model_id not in model_ids:
            continue
        selected.append(model)
    return selected


def _make_receipt_path(explicit: Path | None) -> Path:
    if explicit:
        explicit.parent.mkdir(parents=True, exist_ok=True)
        return explicit
    DEFAULT_RECEIPT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return DEFAULT_RECEIPT_DIR / f"hf-prefetch-receipt-{stamp}.json"


def main() -> int:
    args = _parse_args()
    if not args.manifest.exists():
        print(f"Manifest not found: {args.manifest}", file=sys.stderr)
        return 2

    models = _load_manifest(args.manifest)
    selected = _select_models(models, set(args.group), set(args.model))
    if not selected:
        print("No models matched selection criteria.")
        return 0

    token = os.getenv(args.token_env) or os.getenv("HF_TOKEN")
    receipt_rows: list[dict[str, Any]] = []

    print(f"Selected {len(selected)} model(s) from {args.manifest}")
    for model in selected:
        started_at = time.perf_counter()
        row: dict[str, Any] = {
            "model_id": model.model_id,
            "revision": model.revision,
            "group": model.group,
            "gated": model.gated,
            "status": "planned" if args.dry_run else "pending",
        }

        if args.dry_run:
            print(f"[DRY-RUN] {model.model_id}@{model.revision} ({model.group})")
            receipt_rows.append(row)
            continue

        if model.gated and not token:
            row["status"] = "skipped"
            row["error"] = f"Missing token env ({args.token_env} or HF_TOKEN) for gated model"
            receipt_rows.append(row)
            print(f"[SKIP] {model.model_id}: gated and no token found")
            continue

        try:
            path = snapshot_download(
                repo_id=model.model_id,
                revision=model.revision,
                token=token,
                cache_dir=str(args.cache_dir) if args.cache_dir else None,
            )
            elapsed_ms = (time.perf_counter() - started_at) * 1000
            row["status"] = "downloaded"
            row["cache_path"] = path
            row["elapsed_ms"] = round(elapsed_ms, 1)
            print(f"[OK] {model.model_id} ({elapsed_ms:.1f}ms)")
        except Exception as exc:  # pragma: no cover - network/runtime dependent
            elapsed_ms = (time.perf_counter() - started_at) * 1000
            row["status"] = "error"
            row["elapsed_ms"] = round(elapsed_ms, 1)
            row["error"] = str(exc)
            print(f"[ERR] {model.model_id}: {exc}")
        receipt_rows.append(row)

    receipt_path = _make_receipt_path(args.receipt)
    receipt = {
        "type": "hf_prefetch_receipt",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "manifest": str(args.manifest),
        "token_env": args.token_env,
        "dry_run": args.dry_run,
        "results": receipt_rows,
    }
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True), encoding="utf-8")
    print(f"Wrote receipt: {receipt_path}")

    has_errors = any(row["status"] == "error" for row in receipt_rows)
    return 1 if has_errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
