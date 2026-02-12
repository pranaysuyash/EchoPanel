#!/usr/bin/env python3
"""
Discover Hugging Face candidates beyond the pinned manifest.

Generates a receipt with ranked model candidates for:
- INT-008 topic/entity extraction (GLiNER + token classification)
- INT-009 embedding generation (feature extraction / sentence similarity)
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from huggingface_hub import HfApi


DEFAULT_RECEIPT_DIR = Path("docs/audit/artifacts")


@dataclass(frozen=True)
class Candidate:
    model_id: str
    track: str
    downloads: int
    likes: int
    pipeline_tag: str | None
    sha: str | None
    gated: Any
    private: bool
    rationale: list[str]
    score: float

    def to_dict(self) -> dict[str, Any]:
        return {
            "model_id": self.model_id,
            "track": self.track,
            "downloads": self.downloads,
            "likes": self.likes,
            "pipeline_tag": self.pipeline_tag,
            "sha": self.sha,
            "gated": self.gated,
            "private": self.private,
            "rationale": self.rationale,
            "score": round(self.score, 3),
        }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Discover HF model candidates for EchoPanel tracks")
    parser.add_argument(
        "--track",
        choices=["int008", "int009", "all"],
        default="all",
        help="Candidate track to discover",
    )
    parser.add_argument("--limit", type=int, default=20, help="Max candidates per track")
    parser.add_argument("--receipt", type=Path, default=None, help="Optional explicit receipt path")
    return parser.parse_args()


def _receipt_path(explicit: Path | None) -> Path:
    if explicit:
        explicit.parent.mkdir(parents=True, exist_ok=True)
        return explicit
    DEFAULT_RECEIPT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return DEFAULT_RECEIPT_DIR / f"hf-candidate-discovery-{stamp}.json"


def _score(downloads: int, likes: int, bonuses: float = 0.0, penalties: float = 0.0) -> float:
    # Log-scaling keeps large repos from dominating too hard.
    base = math.log10(max(downloads, 1)) + 0.25 * math.log10(max(likes, 1))
    return base + bonuses - penalties


def _discover_int008(api: HfApi, limit: int) -> list[Candidate]:
    rows: dict[str, Candidate] = {}

    def add_from(model, rationale: list[str], bonuses: float = 0.0, penalties: float = 0.0) -> None:
        model_id = model.id
        downloads = int(model.downloads or 0)
        likes = int(model.likes or 0)
        pipeline_tag = model.pipeline_tag
        sha = getattr(model, "sha", None)
        gated = getattr(model, "gated", None)
        private = bool(getattr(model, "private", False))
        score = _score(downloads, likes, bonuses=bonuses, penalties=penalties)
        candidate = Candidate(
            model_id=model_id,
            track="int008",
            downloads=downloads,
            likes=likes,
            pipeline_tag=pipeline_tag,
            sha=sha,
            gated=gated,
            private=private,
            rationale=rationale,
            score=score,
        )

        existing = rows.get(model_id)
        if existing is None or candidate.score > existing.score:
            rows[model_id] = candidate

    for model in api.list_models(search="gliner", sort="downloads", limit=80, full=True):
        mid = (model.id or "").lower()
        if "gliner" not in mid:
            continue
        add_from(model, rationale=["gliner-family", "topic-entity-extraction"], bonuses=0.8)

    for model in api.list_models(filter="token-classification", sort="downloads", limit=120, full=True):
        mid = (model.id or "").lower()
        if "gliner" in mid:
            continue
        if not any(k in mid for k in ["ner", "entity", "token"]):
            continue
        penalty = 0.0
        if any(k in mid for k in ["medical", "openmed", "pharma", "oncology"]):
            penalty += 0.4
        add_from(model, rationale=["token-classification", "ner-family"], penalties=penalty)

    ranked = sorted(rows.values(), key=lambda x: x.score, reverse=True)
    return ranked[:limit]


def _discover_int009(api: HfApi, limit: int) -> list[Candidate]:
    rows: dict[str, Candidate] = {}

    embed_keywords = [
        "embed",
        "embedding",
        "bge",
        "gte",
        "e5",
        "minilm",
        "nomic",
        "jina",
        "arctic-embed",
        "qwen3-embedding",
    ]

    def add_from(model, rationale: list[str], bonuses: float = 0.0, penalties: float = 0.0) -> None:
        model_id = model.id
        downloads = int(model.downloads or 0)
        likes = int(model.likes or 0)
        pipeline_tag = model.pipeline_tag
        sha = getattr(model, "sha", None)
        gated = getattr(model, "gated", None)
        private = bool(getattr(model, "private", False))
        score = _score(downloads, likes, bonuses=bonuses, penalties=penalties)
        candidate = Candidate(
            model_id=model_id,
            track="int009",
            downloads=downloads,
            likes=likes,
            pipeline_tag=pipeline_tag,
            sha=sha,
            gated=gated,
            private=private,
            rationale=rationale,
            score=score,
        )
        existing = rows.get(model_id)
        if existing is None or candidate.score > existing.score:
            rows[model_id] = candidate

    for model in api.list_models(filter="feature-extraction", sort="downloads", limit=200, full=True):
        mid = (model.id or "").lower()
        if not any(k in mid for k in embed_keywords):
            continue
        penalty = 0.0
        if any(k in mid for k in ["8b", "7b", "large", "xl"]):
            penalty += 0.3
        add_from(model, rationale=["feature-extraction", "embedding-family"], penalties=penalty)

    for model in api.list_models(filter="sentence-similarity", sort="downloads", limit=200, full=True):
        mid = (model.id or "").lower()
        if not any(k in mid for k in embed_keywords):
            continue
        penalty = 0.0
        if any(k in mid for k in ["8b", "7b", "large", "xl"]):
            penalty += 0.3
        add_from(model, rationale=["sentence-similarity", "embedding-family"], penalties=penalty)

    ranked = sorted(rows.values(), key=lambda x: x.score, reverse=True)
    return ranked[:limit]


def main() -> int:
    args = _parse_args()
    api = HfApi()

    tracks: list[str]
    if args.track == "all":
        tracks = ["int008", "int009"]
    else:
        tracks = [args.track]

    results: dict[str, list[dict[str, Any]]] = {}
    if "int008" in tracks:
        results["int008"] = [row.to_dict() for row in _discover_int008(api, limit=args.limit)]
    if "int009" in tracks:
        results["int009"] = [row.to_dict() for row in _discover_int009(api, limit=args.limit)]

    receipt = {
        "type": "hf_candidate_discovery",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "track": args.track,
        "limit": args.limit,
        "results": results,
    }
    out = _receipt_path(args.receipt)
    out.write_text(json.dumps(receipt, indent=2, sort_keys=True), encoding="utf-8")

    print(f"Wrote receipt: {out}")
    for track, rows in results.items():
        print(f"\n{track.upper()} ({len(rows)} candidates)")
        for idx, row in enumerate(rows[:10], start=1):
            print(
                f"{idx:>2}. {row['model_id']} "
                f"(downloads={row['downloads']}, likes={row['likes']}, score={row['score']})"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
