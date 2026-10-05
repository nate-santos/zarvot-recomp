#!/usr/bin/env python3
"""Drive suyu's AOT static recompiler over its MCP server.

The exporter is a modal Qt dialog with no CLI. Two calls are needed:

  1. trigger_ui_action{action=export_game} opens GameExportDialog and calls
    dialog.exec(), which blocks that MCP handler until the dialog closes. A
    timeout is permitted only for this dialog-open call.
  2. trigger_ui_action{action=aot_test_export} finds the dialog via
     QApplication::activeModalWidget() and drives a real export past the file
    pickers. Current source schedules this work and returns acceptance first.

Step 2 works because exec() spins a nested event loop, so the TCP server keeps
accepting connections while the dialog is up.

Export runs on the GUI thread and may take minutes. An accepted request is not
export success: poll get_aot_export_status and verify generated artifacts.

  python scripts/export-recomp.py --rom <file> --out <directory> --backend hybrid source
"""

import argparse
import json
import os
import pathlib
import socket
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from mcp import rpc  # noqa: E402

# No committed default: set MK8R_ROM/MK8R_OUT, or pass --rom/--out. A title
# whose 64-bit build ships only in an update has to be exported from the update
# package rather than the cartridge, since an update replaces the ExeFS whole.
ROM = os.environ.get("MK8R_ROM", "")
OUT = os.environ.get("MK8R_OUT", "")


def request_action(args, *, allow_modal_timeout=False, wait=10.0):
    """Accept only a successful action, except the blocking dialog-open call."""
    try:
        response = rpc("tools/call", {"name": "trigger_ui_action", "arguments": args}, timeout=wait)
    except (TimeoutError, socket.timeout):
        if allow_modal_timeout:
            return "dialog call timed out (expected); export action must still succeed"
        raise RuntimeError("Export action timed out; inspect export status before retrying")
    if response.get("error"):
        raise RuntimeError(json.dumps(response["error"]))
    result = response.get("result", {})
    if result.get("isError"):
        raise RuntimeError(json.dumps(result))
    for block in result.get("content", []):
        if block.get("type") == "text":
            try:
                value = json.loads(block["text"])
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict) and value.get("success") is True:
                return "action accepted (export completion still pending)"
            if isinstance(value, dict) and value.get("success") is False:
                raise RuntimeError(value.get("error", "Export action rejected"))
    raise RuntimeError("Export action returned no explicit success response")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("format", nargs="?", choices=("source", "build"), default="source")
    parser.add_argument("--rom", default=ROM)
    parser.add_argument("--out", default=OUT)
    parser.add_argument("--backend", choices=("static", "hybrid", "dynarmic"),
                        help="select explicitly instead of inheriting the dialog setting")
    args = parser.parse_args()
    rom, out = args.rom, args.out
    if not rom or not out:
        print("set MK8R_ROM and MK8R_OUT, or pass --rom/--out")
        return 2
    rom = str(pathlib.Path(rom).resolve())
    out = str(pathlib.Path(out).resolve())
    if not pathlib.Path(rom).is_file():
        parser.error("--rom must name an existing local game file")
    pathlib.Path(out).mkdir(parents=True, exist_ok=True)

    print(f"rom    : {rom}")
    print(f"out    : {out}")
    print(f"format : {args.format}")
    print(f"backend: {args.backend or 'dialog setting'}")

    print("\n[1/2] opening GameExportDialog ...")
    print("     ", request_action({"action": "export_game"}, allow_modal_timeout=True, wait=3.0))

    time.sleep(3)

    print("[2/2] triggering aot_test_export ...")
    export_args = {"action": "aot_test_export", "rom_path": rom,
                   "output_dir": out, "format": args.format}
    if args.backend:
        export_args["backend"] = args.backend
    print("     ", request_action(export_args))

    print("\nExport is running on suyu's GUI thread. Watch progress with:")
    print("  python scripts/mcp-call.py get_aot_export_status")
    return 0


if __name__ == "__main__":
    sys.exit(main())
