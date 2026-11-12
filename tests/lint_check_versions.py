#!/usr/bin/env python3
"""Check that source-build versions agree before building a release.

Compare operator/operator/Cargo.toml's package.version with the Containerfile's
shared VERSION default, the final bundle image version label, and TAG in both
bundle pipelines. Missing or mismatched values make the test fail.

This reads checkout files only; it does not build or inspect registry images.
Catalog versions are excluded because their bundle nudges can lag the source.

Requires Python 3.11+ and PyYAML.
On Fedora: sudo dnf install python3-pyyaml
Run: python3 tests/lint_check_versions.py
"""

from pathlib import Path
import shlex
import sys
import tomllib

import yaml

ROOT = Path(__file__).resolve().parents[1]


def instructions(filename):
    text = (ROOT / filename).read_text().replace("\\\n", " ")
    for line in text.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) == 2 and parts[0].upper() in ("FROM", "ARG", "LABEL"):
            yield parts[0].upper(), shlex.split(parts[1], comments=True)


def runtime_version():
    defaults = []
    for instruction, words in instructions("Containerfile"):
        if instruction == "FROM":
            break
        if instruction == "ARG" and words[0].partition("=")[0] == "VERSION":
            defaults.append(words[0].partition("=")[2])
    if len(defaults) != 1 or not defaults[0]:
        raise ValueError("Containerfile: expected one top-level ARG VERSION=<version>")
    return defaults[0]


def bundle_version():
    version = None
    in_stage = False
    for instruction, words in instructions("Containerfile.bundle"):
        if instruction == "FROM":
            in_stage, version = True, None
        elif instruction == "LABEL" and in_stage:
            for word in words:
                name, separator, value = word.partition("=")
                if name == "version" and separator:
                    version = value
    return version


def main():
    with (ROOT / "operator/operator/Cargo.toml").open("rb") as stream:
        expected = tomllib.load(stream)["package"]["version"]
    if not isinstance(expected, str) or not expected:
        raise ValueError("operator/operator/Cargo.toml: expected a literal package.version")

    checks = [
        ("Containerfile global ARG VERSION", runtime_version(), expected),
        ("Containerfile.bundle final-stage LABEL", bundle_version(), expected),
    ]

    for event in ("push", "pull-request"):
        filename = f".tekton/confidential-cluster-operator-bundle-{event}.yaml"
        pipeline = yaml.safe_load((ROOT / filename).read_text())
        build_args = [param["value"] for param in pipeline["spec"]["params"]
                      if param["name"] == "build-args"]
        if len(build_args) != 1 or not isinstance(build_args[0], list):
            raise ValueError(f"{filename}: expected one build-args array")
        tags = [arg[4:] for arg in build_args[0] if isinstance(arg, str) and arg.startswith("TAG=")]
        if len(tags) != 1 or not tags[0]:
            raise ValueError(f"{filename}: expected one nonempty TAG= argument")
        # Upstream strips a leading 'v' from TAG to compute OLM_VERSION.
        checks.append((f"{filename} TAG", tags[0].removeprefix("v"), expected))

    errors = [f"{location}: {actual!r}; expected {required!r}"
              for location, actual, required in checks if actual != required]
    if errors:
        print("Version mismatches:\n  " + "\n  ".join(errors), file=sys.stderr)
        return 1
    print(f"Source version check passed: {expected} ({len(checks)} declarations).")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, yaml.YAMLError) as error:
        sys.exit(f"Version check failed: {error}")
