"""Validate bundled data and captured client requests/responses against source contracts.

Install test dependencies: python -m pip install -r client/tests/requirements.txt
Run from any directory: python client/tests/validate_contracts.py [--fixtures file.json]
This validator never edits /contracts or /data and never fetches remote schemas.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.parse import urljoin

import yaml
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012


ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = ROOT / "contracts"


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", type=Path, help="JSON emitted by headless_tests.gd")
    args = parser.parse_args()
    registry = Registry()
    for path in (CONTRACTS / "schemas").glob("*.json"):
        schema = read_json(path)
        resource = Resource.from_contents(schema, default_specification=DRAFT202012)
        registry = registry.with_resource(path.as_uri(), resource)
        registry = registry.with_resource(schema["$id"], resource)
    api = yaml.safe_load((CONTRACTS / "openapi.yaml").read_text(encoding="utf-8-sig"))
    api_uri = (CONTRACTS / "openapi.yaml").as_uri()
    registry = registry.with_resource(
        api_uri, Resource.from_contents(api, default_specification=DRAFT202012)
    )
    checked = 0

    def api_schema(value):
        """Keep component references rooted at OpenAPI, not at a detached subschema."""
        if isinstance(value, dict):
            return {
                key: urljoin(api_uri, item) if key == "$ref" else api_schema(item)
                for key, item in value.items()
            }
        if isinstance(value, list):
            return [api_schema(item) for item in value]
        return value

    def validate(label: str, value, schema: dict) -> None:
        nonlocal checked
        errors = sorted(
            Draft202012Validator(
                schema, registry=registry, format_checker=FormatChecker()
            ).iter_errors(value),
            key=lambda error: str(list(error.absolute_path)),
        )
        if errors:
            detail = "\n".join(
                f"  {list(error.absolute_path)}: {error.message}" for error in errors
            )
            raise AssertionError(f"{label} failed schema validation:\n{detail}")
        checked += 1
        print(f"PASS {label}")

    merged = {}
    for path in sorted((ROOT / "data").glob("*.json")):
        source = read_json(path)
        schema_path = (path.parent / source["$schema"]).resolve()
        validate(path.name, source, {"$ref": schema_path.as_uri()})
        content = {key: value for key, value in source.items() if key != "$schema"}
        merged.update({"economy": content} if path.stem == "economy" else content)

    bundle = read_json(ROOT / "client" / "data" / "bundle.json")["data"]
    validate("bundled game data", bundle, {"$ref": (CONTRACTS / "schemas" / "game-data.schema.json").as_uri()})
    # The export bundle keeps source text so its canonical hash agrees with the server.
    assert bundle == merged, "Bundled balance data differs from read-only /data; rebuild it."

    strings = read_json(ROOT / "client" / "localization" / "strings.json")
    assert isinstance(strings, dict), "The centralized strings catalog must be an object."

    if args.fixtures:
        fixture = read_json(args.fixtures)
        for index, save in enumerate(fixture.get("saves", [])):
            validate(f"save {index}", save, {"$ref": (CONTRACTS / "schemas" / "save.schema.json").as_uri()})
        for case in fixture.get("api", []):
            operation = api["paths"][case["path"]][case["method"].lower()]
            if "request" in case:
                schema = operation["requestBody"]["content"]["application/json"]["schema"]
                validate(f"{case['method']} {case['path']} request", case["request"], api_schema(schema))
            response = operation["responses"][str(case["status"])]
            if "$ref" in response:
                response = api["components"]["responses"][response["$ref"].split("/")[-1]]
            if "content" in response:
                schema = next(iter(response["content"].values()))["schema"]
                validate(f"{case['method']} {case['path']} {case['status']}", case["body"], api_schema(schema))
            else:
                assert not case["body"], f"{case['status']} must have no response body"
    print(f"Validated {checked} contract documents.")


if __name__ == "__main__":
    main()
