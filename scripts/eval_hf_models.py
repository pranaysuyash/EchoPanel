#!/usr/bin/env python3
"""
Run quick hosted-inference latency probes for Hugging Face model candidates.

The script is intentionally lightweight: it measures request latency and basic
output shape so model choices can be made quickly before local integration.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from huggingface_hub import InferenceClient


DEFAULT_MANIFEST = Path("server/config/hf_model_manifest.json")
DEFAULT_RECEIPT_DIR = Path("docs/audit/artifacts")

def _load_local_dotenv_defaults() -> None:
    """Best-effort `.env` loader (does not override explicit env vars)."""
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if not env_path.is_file():
        return
    try:
        for raw in env_path.read_text(errors="ignore").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[len("export ") :].strip()
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip()
            v = v.strip()
            if not k or not v:
                continue
            if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
                v = v[1:-1]
            os.environ.setdefault(k, v)
    except Exception:
        return


@dataclass
class EvalSpec:
    model_id: str
    revision: str
    task: str
    payload: str


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Hosted inference quick-eval for HF candidates")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--token-env", default="ECHOPANEL_HF_TOKEN")
    parser.add_argument("--group", action="append", default=[])
    parser.add_argument("--model", action="append", default=[])
    parser.add_argument("--requests", type=int, default=3)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--receipt", type=Path, default=None)
    return parser.parse_args()


def _load_specs(path: Path, groups: set[str], model_ids: set[str]) -> list[EvalSpec]:
    data = json.loads(path.read_text(encoding="utf-8"))
    specs: list[EvalSpec] = []
    for entry in data.get("models", []):
        if groups and entry.get("group") not in groups:
            continue
        if model_ids and entry.get("id") not in model_ids:
            continue
        eval_cfg = entry.get("eval")
        if not eval_cfg:
            continue
        specs.append(
            EvalSpec(
                model_id=str(entry["id"]),
                revision=str(entry["revision"]),
                task=str(eval_cfg["task"]),
                payload=str(eval_cfg["input"]),
            )
        )
    return specs


def _make_receipt_path(explicit: Path | None) -> Path:
    if explicit:
        explicit.parent.mkdir(parents=True, exist_ok=True)
        return explicit
    DEFAULT_RECEIPT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return DEFAULT_RECEIPT_DIR / f"hf-eval-receipt-{stamp}.json"


def _run_task(client: InferenceClient, task: str, payload: str) -> Any:
    if task == "feature_extraction":
        return client.feature_extraction(payload)
    if task == "token_classification":
        return client.token_classification(payload)
    if task == "text_classification":
        return client.text_classification(payload)
    raise ValueError(f"Unsupported eval task: {task}")


def _output_shape(task: str, output: Any) -> dict[str, Any]:
    if task == "feature_extraction":
        if isinstance(output, list) and output and isinstance(output[0], list):
            return {"kind": "matrix", "rows": len(output), "cols": len(output[0])}
        if isinstance(output, list):
            return {"kind": "vector", "length": len(output)}
        return {"kind": type(output).__name__}
    if task in {"token_classification", "text_classification"} and isinstance(output, list):
        return {"kind": "list", "length": len(output)}
    return {"kind": type(output).__name__}


def main() -> int:
    _load_local_dotenv_defaults()
    args = _parse_args()
    if not args.manifest.exists():
        print(f"Manifest not found: {args.manifest}", file=sys.stderr)
        return 2

    specs = _load_specs(args.manifest, set(args.group), set(args.model))
    if not specs:
        print("No evaluation specs matched selection criteria.")
        return 0

    token = os.getenv(args.token_env) or os.getenv("HF_TOKEN")
    if not token and not args.dry_run:
        print(f"Warning: no token found in {args.token_env} or HF_TOKEN; trying unauthenticated inference.")

    print(f"Evaluating {len(specs)} model(s) with {args.requests} request(s) each")
    results: list[dict[str, Any]] = []
    for spec in specs:
        row: dict[str, Any] = {
            "model_id": spec.model_id,
            "revision": spec.revision,
            "task": spec.task,
            "status": "planned" if args.dry_run else "pending",
        }

        if args.dry_run:
            print(f"[DRY-RUN] {spec.model_id} task={spec.task}")
            results.append(row)
            continue

        client = InferenceClient(model=spec.model_id, token=token)
        latencies_ms: list[float] = []
        sample_shape: dict[str, Any] | None = None
        errors: list[str] = []
        for _ in range(args.requests):
            start = time.perf_counter()
            try:
                output = _run_task(client, spec.task, spec.payload)
                elapsed_ms = (time.perf_counter() - start) * 1000
                latencies_ms.append(elapsed_ms)
                if sample_shape is None:
                    sample_shape = _output_shape(spec.task, output)
            except Exception as exc:  # pragma: no cover - network/runtime dependent
                errors.append(str(exc))

        if latencies_ms:
            row["status"] = "ok" if not errors else "partial"
            row["request_count"] = args.requests
            row["success_count"] = len(latencies_ms)
            row["error_count"] = len(errors)
            row["p50_ms"] = round(statistics.median(latencies_ms), 1)
            row["p95_ms"] = round(max(latencies_ms), 1)
            row["sample_shape"] = sample_shape
            if errors:
                row["errors"] = errors[:2]
            print(f"[OK] {spec.model_id}: p50={row['p50_ms']}ms p95={row['p95_ms']}ms")
        else:
            row["status"] = "error"
            row["errors"] = errors[:3] or ["No successful requests"]
            print(f"[ERR] {spec.model_id}: {row['errors'][0]}")
        results.append(row)

    receipt_path = _make_receipt_path(args.receipt)
    receipt = {
        "type": "hf_eval_receipt",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "manifest": str(args.manifest),
        "requests_per_model": args.requests,
        "dry_run": args.dry_run,
        "results": results,
    }
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True), encoding="utf-8")
    print(f"Wrote receipt: {receipt_path}")

    has_errors = any(row["status"] == "error" for row in results)
    return 1 if has_errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
