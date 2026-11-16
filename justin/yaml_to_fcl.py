#!/usr/bin/env python3
"""Convert a nusystematics ParameterHeader YAML into FHiCL for UpdateReweight.

The UPS fhiclcpp used by cafnusyst only parses FHiCL, so a header produced by
`GenerateSystProviderConfigNuSyst -o <file>.yaml` is translated 1:1 here
(syntax only: same keys, values and ordering). Requires PyYAML.

Usage: yaml_to_fcl.py <input.yaml> <output.fcl>
"""
import sys

import yaml


def fcl_value(v, indent):
    pad = "   " * indent
    if isinstance(v, dict):
        if not v:
            return "{}"
        body = "\n".join(f"{pad}   {k}: {fcl_value(x, indent + 1)}" for k, x in v.items())
        return "{\n" + body + "\n" + pad + "}"
    if isinstance(v, list):
        return "[" + ", ".join(fcl_value(x, indent) for x in v) + "]"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if v is None:
        return "nil"
    s = str(v).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f)
    with open(sys.argv[2], "w") as f:
        f.write(f"// Converted from {sys.argv[1].rsplit('/', 1)[-1]} by justin/yaml_to_fcl.py -- do not edit by hand.\n")
        for k, v in doc.items():
            f.write(f"{k}: {fcl_value(v, 0)}\n")


if __name__ == "__main__":
    main()
