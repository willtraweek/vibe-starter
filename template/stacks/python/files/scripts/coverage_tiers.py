"""Independent global and tier line/branch gates; stdlib only (TESTING.md).

Config lives in [tool.coverage_tiers.*]. Empty tiers require allow_empty=true.
Branchless code has no branch percentage; measured lines still meet the floor.
--ratchet REF forbids lowering floors/targets or removing existing tier members;
renaming, moving or deleting one means listing its old path in the tier's `retired`.
"""

import argparse
import json
import math
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
GLOBAL_MINIMUM = 90.0
COUNTERS = ("covered_lines", "num_statements", "covered_branches", "num_branches")


def load_tiers(text: str | None = None) -> dict[str, Any]:
    if text is None:
        text = (ROOT / "pyproject.toml").read_text(encoding="utf-8")
    return tomllib.loads(text).get("tool", {}).get("coverage_tiers", {})


def valid_path(path: Any) -> bool:
    return (
        isinstance(path, str)
        and path.startswith("src/")
        and path.endswith(".py")
        and "\\" not in path
        and all(part not in ("", ".", "..") for part in path.split("/"))
    )


def validate(tiers: Any, *, check_files: bool = True) -> list[str]:
    if not isinstance(tiers, dict) or not tiers:
        return ["coverage_tiers must be a nonempty table"]
    errors: list[str] = []
    owner: dict[str, str] = {}
    for key, tier in tiers.items():
        if key == "global":
            errors.append("global is reserved for the global floor, not a tier name")
        if not isinstance(tier, dict):
            errors.append(f"{key}: tier must be a table")
            continue
        allowed = {"title", "minimum", "target", "include", "allow_empty", "retired"}
        if set(tier) - allowed:
            errors.append(f"{key}: unknown tier keys: {sorted(set(tier) - allowed)}")
        minimum, target = tier.get("minimum"), tier.get("target")
        if not all(type(n) in (int, float) and math.isfinite(n) for n in (minimum, target)):
            errors.append(f"{key}: minimum and target must be finite numbers")
        elif not 0 <= minimum <= target <= 100:
            errors.append(f"{key}: need 0 <= minimum <= target <= 100")
        if not isinstance(tier.get("title"), str) or not tier["title"].strip():
            errors.append(f"{key}: title must be a nonempty string")
        if type(tier.get("allow_empty", False)) is not bool:
            errors.append(f"{key}: allow_empty must be boolean")
        members = tier.get("include")
        retired = tier.get("retired", [])
        if not isinstance(retired, list):
            errors.append(f"{key}: retired must be an array")
            retired = []
        seen: set[str] = set()
        for path in retired:
            if not valid_path(path):
                errors.append(f"{key}: retired must name canonical src/*.py files: {path!r}")
            elif path in seen or (isinstance(members, list) and path in members):
                errors.append(f"{key}: {path} is listed twice across include and retired")
            else:
                seen.add(path)
        if not isinstance(members, list):
            errors.append(f"{key}: include must be an explicit array")
            continue
        if not members and tier.get("allow_empty") is not True:
            errors.append(f"{key}: empty include requires allow_empty = true")
        for path in members:
            if not valid_path(path):
                errors.append(f"{key}: include must name canonical src/*.py files: {path!r}")
                continue
            if check_files and (
                not (ROOT / path).is_file()
                or not (ROOT / path).resolve().is_relative_to(ROOT.resolve())
            ):
                errors.append(f"{key}: include {path!r} is not a file within the project")
            if path in owner:
                errors.append(f"{path}: duplicate membership in {owner[path]!r} and {key!r}")
            owner[path] = key
    return errors


def counters(summary: Any, label: str, errors: list[str]) -> dict[str, int] | None:
    if not isinstance(summary, dict) or any(
        type(summary.get(key)) is not int or summary[key] < 0 for key in COUNTERS
    ):
        errors.append(f"{label}: missing or invalid coverage counters")
        return None
    if (
        summary["covered_lines"] > summary["num_statements"]
        or summary["covered_branches"] > summary["num_branches"]
    ):
        errors.append(f"{label}: covered counters exceed totals")
        return None
    return {key: summary[key] for key in COUNTERS}


def measure(tiers: dict[str, Any], report: Any) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    measured: dict[str, Any] = {}
    if not isinstance(report, dict):
        return measured, ["coverage report must be an object"]
    meta = report.get("meta")
    if not isinstance(meta, dict) or meta.get("branch_coverage") is not True:
        errors.append("coverage.json has no branch data; enable branch = true")
    files = report.get("files")
    if not isinstance(files, dict) or not files:
        return measured, [*errors, "coverage report files must be a nonempty object"]
    metrics: dict[str, dict[str, int]] = {}
    for path, entry in files.items():
        summary = entry.get("summary") if isinstance(entry, dict) else None
        value = counters(summary, str(path), errors)
        if value is not None:
            metrics[path] = value
    global_value = counters(report.get("totals"), "global", errors)
    if global_value is not None:
        if global_value["num_statements"] == 0:
            errors.append("global: no measurable statements")
        if len(metrics) == len(files) and any(
            global_value[key] != sum(value[key] for value in metrics.values()) for key in COUNTERS
        ):
            errors.append("global: counters disagree with per-file sums")
        measured["global"] = global_value
    for key, tier in tiers.items():
        if not tier["include"]:
            measured[key] = None  # validate() requires explicit allow_empty.
            continue
        total = dict.fromkeys(COUNTERS, 0)
        for path in tier["include"]:
            if path not in files:
                errors.append(f"{key}: {path} is not in the coverage report")
                continue
            value = metrics.get(path)
            if value is None:
                continue
            if value["num_statements"] == 0:
                errors.append(f"{key}: {path} has no measurable statements")
            for counter in COUNTERS:
                total[counter] += value[counter]
        measured[key] = total
    return measured, errors


def check(tiers: dict[str, Any], measured: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for key, value in measured.items():
        if value is None:
            continue
        floor = GLOBAL_MINIMUM if key == "global" else tiers[key]["minimum"]
        for metric, hit, count in (
            ("line", "covered_lines", "num_statements"),
            ("branch", "covered_branches", "num_branches"),
        ):
            if value[count] and 100 * value[hit] < floor * value[count]:
                actual = 100 * value[hit] / value[count]
                errors.append(f"{key}: {metric} {actual:.2f}% is below its minimum {floor}%")
    return errors


def percentage(value: dict[str, int], hit: str, total: str) -> str:
    return f"{100 * value[hit] / value[total]:.2f}%" if value[total] else "n/a (branchless)"


def report_markdown(tiers: dict[str, Any], measured: dict[str, Any]) -> str:
    lines = ["| Tier | Line | Branch | Minimum | Target |", "|---|---|---|---|---|"]
    for key, value in measured.items():
        tier = tiers.get(key, {"title": "Global", "minimum": GLOBAL_MINIMUM, "target": 100})
        line = branch = "n/a (explicitly empty)"
        if value is not None:
            line = percentage(value, "covered_lines", "num_statements")
            branch = percentage(value, "covered_branches", "num_branches")
        lines.append(
            f"| {tier['title']} | {line} | {branch} | {tier['minimum']}% | {tier['target']}% |"
        )
    return "\n".join(lines) + "\n"


def git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=False)


def ratchet(tiers: dict[str, Any], ref: str) -> list[str]:
    # rev-parse first: it also refuses a ref that git would read as an option.
    if git("rev-parse", "--verify", "--quiet", ref + "^{commit}").returncode:
        return [f"cannot read pyproject.toml at {ref}: unknown revision"]
    # A base that predates the tier table (the project's first PR) has no floors to
    # keep. Only a confirmed absence counts: an unreadable tree still fails.
    listed = git("ls-tree", "--name-only", ref, "--", "pyproject.toml")
    if listed.returncode:
        return [f"cannot read pyproject.toml at {ref}: {listed.stderr.strip()}"]
    if not listed.stdout.strip():
        print(f"coverage-tiers: no pyproject.toml at {ref}; nothing to ratchet against")
        return []
    shown = git("show", f"{ref}:pyproject.toml")
    if shown.returncode:
        return [f"cannot read pyproject.toml at {ref}: {shown.stderr.strip()}"]
    tool = tomllib.loads(shown.stdout).get("tool", {})
    if not isinstance(tool, dict):
        return [f"base config: [tool] at {ref} is not a table"]
    if "coverage_tiers" not in tool:
        print(f"coverage-tiers: no [tool.coverage_tiers] at {ref}; nothing to ratchet against")
        return []
    old_tiers = tool["coverage_tiers"]
    errors = validate(old_tiers, check_files=False)
    if errors:
        return [f"base config: {error}" for error in errors]
    for key, old in old_tiers.items():
        new = tiers.get(key)
        if new is None:
            errors.append(f"{key}: tier removed since {ref}")
            continue
        for field in ("minimum", "target"):
            if new[field] < old[field]:
                errors.append(f"{key}: {field} lowered from {old[field]} to {new[field]}")
        # A reviewed migration lists the old path in `retired`; any other removal fails.
        removed = set(old["include"]) - set(new["include"]) - set(new.get("retired", []))
        if removed:
            errors.append(
                f"{key}: existing members removed since {ref}: {sorted(removed)} "
                "(to rename, move or delete one, list its old path in the tier's retired)"
            )
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Independent line/branch coverage gates.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--validate", action="store_true")
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--report", action="store_true")
    mode.add_argument("--ratchet", metavar="REF")
    parser.add_argument("--input", default="coverage.json")
    args = parser.parse_args(argv)
    if args.ratchet is not None and not args.ratchet.strip():
        parser.error("--ratchet needs a git ref")
    try:
        tiers = load_tiers()
        errors = validate(tiers)
        if not errors and args.ratchet is not None:
            errors = ratchet(tiers, args.ratchet)
        elif not errors and (args.check or args.report):
            report = json.loads((ROOT / args.input).read_text(encoding="utf-8"))
            measured, errors = measure(tiers, report)
            if not errors and args.report:
                print(report_markdown(tiers, measured), end="")
                return 0
            if not errors:
                errors = check(tiers, measured)
    except (OSError, ValueError, TypeError, AttributeError, OverflowError, RecursionError) as exc:
        errors = [f"cannot load valid configuration/report: {exc}"]
    for error in errors:
        print(f"coverage-tiers: FAIL {error}", file=sys.stderr)
    print(f"coverage-tiers: {'FAILED' if errors else 'ok'}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
