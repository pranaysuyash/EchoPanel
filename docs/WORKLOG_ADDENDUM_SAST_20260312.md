# Worklog Addendum - SAST Remediation - 2026-03-12

## Objective
Track user-reported package-level SAST findings for `EchoPanel`.

## Observed
- `pyproject.toml` declares vulnerable-surface packages or extras tied to the report:
  - `vllm>=0.7.3`
  - `torch==2.5.1`
- `uv.lock` currently includes:
  - `diskcache`
  - `gradio`
  - `ray`
  - `vllm`
  - `torch`

## Next Step
- Completed:
  - Raised dependency floors in `pyproject.toml` to `vllm>=0.10.2` and `torch>=2.6.0` for optional extras that previously pinned `2.5.1`.
  - Re-resolved `uv.lock`, which upgraded:
    - `vllm` `0.7.3` -> `0.11.2`
    - `ray` `2.40.0` -> `2.54.0`
    - `torch` `2.5.1` -> `2.9.0`
    - `gradio` `6.5.1` -> `6.9.0`
  - `diskcache` remained at `5.6.3` because the resolver already selected the latest published release.

## Verification
- `uv lock --upgrade-package vllm --upgrade-package torch --upgrade-package ray --upgrade-package diskcache`
  - Observed: successful lock resolution after selecting the highest `vllm` floor compatible with `fastapi==0.115.6`.
- Constraint note:
  - `vllm>=0.17.1` is incompatible with the repo's pinned FastAPI/Starlette stack because newer `vllm` pulls `model-hosting-container-standards` requiring `starlette>=0.49.1`.
  - A full `uv run` install on this macOS host is not a meaningful verification gate for the upgraded `vllm` graph because it now includes Linux-only CUDA wheels.
