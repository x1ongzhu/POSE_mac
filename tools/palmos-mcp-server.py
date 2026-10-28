#!/usr/bin/env python3
"""Dependency-free stdio MCP bridge for the Palm OS Emulator macOS app."""

import json
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import sys
import time
import uuid


VERSION = "2025-11-25"
NAME = "palmos-emulator"
SOCKET_DIR = Path(os.environ.get("PALM_OS_MCP_DIR", "~/Library/Application Support/Palm OS Emulator/MCP")).expanduser()


def tool(name, description, properties=None, required=None):
    return {
        "name": name,
        "description": description,
        "inputSchema": {
            "type": "object",
            "properties": properties or {},
            "required": required or [],
            "additionalProperties": False,
        },
    }


INSTANCE = {"instance_id": {"type": "integer", "description": "Process ID from palm_list_instances; optional when only one window is open."}}
PATH = {"path": {"type": "string", "description": "Absolute local filesystem path."}}

TOOLS = [
    tool("palm_list_instances", "List running Palm OS Emulator windows and their process IDs."),
    tool("palm_open_emulator", "Open a new isolated Palm OS Emulator window; optionally boot a ROM and install a PRC/PDB.",
         {"rom_path": {"type": "string", "description": "Optional absolute ROM path."},
          "install_path": {"type": "string", "description": "Optional absolute PRC/PDB path."}}),
    tool("palm_status", "Get ROM, device, session, UI readiness and screen size.", INSTANCE),
    tool("palm_wait_ready", "Wait until Palm OS can accept app installation and UI actions.",
         {**INSTANCE, "timeout_seconds": {"type": "integer", "minimum": 1, "maximum": 180}}, []),
    tool("palm_screenshot", "Return the current Palm display as a PNG image; coordinates use its top-left origin.", INSTANCE),
    tool("palm_tap", "Tap a pixel on the Palm display.",
         {**INSTANCE, "x": {"type": "integer"}, "y": {"type": "integer"}}, ["x", "y"]),
    tool("palm_pen", "Hold or release the stylus at a pixel. Repeated down actions draw a stroke.",
         {**INSTANCE, "x": {"type": "integer"}, "y": {"type": "integer"},
          "action": {"type": "string", "enum": ["down", "up"]}}, ["x", "y", "action"]),
    tool("palm_type_text", "Type Latin-1 and common punctuation into the focused Palm field.",
         {**INSTANCE, "text": {"type": "string", "maxLength": 4096}}, ["text"]),
    tool("palm_press_key", "Press a Palm navigation or editing key.",
         {**INSTANCE, "key": {"type": "string", "enum": ["backspace", "enter", "tab", "left", "right", "up", "down"]}}, ["key"]),
    tool("palm_hardware_button", "Press Palm hardware button 0-7 (0-3 app keys, 4-5 rocker, 7 HotSync).",
         {**INSTANCE, "button": {"type": "integer", "minimum": 0, "maximum": 7}}, ["button"]),
    tool("palm_install", "Install a PRC/PDB file; launch a successful PRC install by default.",
         {**INSTANCE, **PATH, "launch": {"type": "boolean", "default": True}}, ["path"]),
    tool("palm_launch_app", "Launch an already installed Palm application using its PRC file header.",
         {**INSTANCE, **PATH}, ["path"]),
    tool("palm_load_rom", "Load a ROM and start its automatically detected device.",
         {**INSTANCE, **PATH}, ["path"]),
    tool("palm_start", "Start the selected window's ROM or saved session.", INSTANCE),
    tool("palm_list_sessions", "List saved sessions in the emulator resource library, including device and active state.", INSTANCE),
    tool("palm_open_session", "Open a saved session by its path from palm_list_sessions.",
         {**INSTANCE, **PATH}, ["path"]),
    tool("palm_rename_session", "Rename a saved session in the resource library; .img is retained.",
         {**INSTANCE, **PATH, "name": {"type": "string", "description": "New session name without .img."}},
         ["path", "name"]),
    tool("palm_import_session", "Import a local .img session into the emulator resource library.",
         {**INSTANCE, **PATH}, ["path"]),
    tool("palm_duplicate_session", "Save and duplicate the running session, then continue in the copy.", INSTANCE),
    tool("palm_export_session", "Export a saved session to a new absolute path; refuses to overwrite an existing file.",
         {**INSTANCE, **PATH, "destination_path": {"type": "string", "description": "New absolute path for the exported .img file."}},
         ["path", "destination_path"]),
    tool("palm_delete_session", "Move a saved session to the macOS Trash by its path from palm_list_sessions.",
         {**INSTANCE, **PATH}, ["path"]),
    tool("palm_stop", "Save and stop the selected emulator window.", INSTANCE),
    tool("palm_quit", "Save and close the selected emulator app instance.", INSTANCE),
    tool("palm_reset", "Soft reset the selected Palm device.", INSTANCE),
    tool("palm_save", "Save the current session and mounted card.", INSTANCE),
    tool("palm_hot_sync", "Press the Palm HotSync button; a desktop sync service may be required.", INSTANCE),
    tool("palm_set_network", "Enable or disable native Palm network redirection.",
         {**INSTANCE, "enabled": {"type": "boolean"}}, ["enabled"]),
]


def control(sock_path, command, *, timeout=20, **arguments):
    request = json.dumps({"command": command, **arguments}, ensure_ascii=False).encode() + b"\n"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(timeout)
        connection.connect(str(sock_path))
        connection.sendall(request)
        response = bytearray()
        while b"\n" not in response:
            block = connection.recv(65536)
            if not block:
                raise RuntimeError("Palm OS Emulator closed the control connection")
            response.extend(block)
            if len(response) > 12_000_000:
                raise RuntimeError("Palm OS Emulator response is too large")
    value = json.loads(response.split(b"\n", 1)[0])
    if not value.get("ok"):
        raise RuntimeError(value.get("error", "Palm control request failed"))
    return value["result"]


def list_instances():
    instances = []
    for path in sorted(SOCKET_DIR.glob("instance-*.sock")):
        try:
            instances.append(control(path, "status", timeout=5))
        except (OSError, RuntimeError, ValueError, KeyError):
            continue
    return instances


def selected_socket(arguments):
    instances = list_instances()
    if "instance_id" in arguments:
        chosen = next((item for item in instances if item["instance_id"] == arguments["instance_id"]), None)
        if chosen is None:
            raise ValueError(f"No running instance with ID {arguments['instance_id']}; call palm_list_instances")
        return SOCKET_DIR / f"instance-{chosen['instance_id']}.sock"
    if len(instances) != 1:
        ids = [item["instance_id"] for item in instances]
        raise ValueError(f"Expected one emulator window, found {len(instances)} ({ids}); pass instance_id")
    return SOCKET_DIR / f"instance-{instances[0]['instance_id']}.sock"


def app_bundle_path():
    if "PALM_OS_APP_PATH" in os.environ:
        return Path(os.environ["PALM_OS_APP_PATH"]).expanduser().resolve()
    source = Path(__file__).resolve()
    bundled = source.parent.parent.parent
    if bundled.suffix == ".app":
        return bundled
    return source.parent.parent / "dist" / "Palm OS.app"


def call_tool(name, arguments):
    if not isinstance(arguments, dict):
        raise ValueError("Tool arguments must be an object")
    if name == "palm_list_instances":
        return {"instances": list_instances()}
    if name == "palm_open_emulator":
        app = app_bundle_path()
        if not app.is_dir():
            raise ValueError(f"App bundle not found: {app}")
        with (app / "Contents" / "Info.plist").open("rb") as info_file:
            if plistlib.load(info_file).get("CFBundleIdentifier") != "org.cloudpilot.mac":
                raise ValueError(f"Not a Palm OS Emulator app bundle: {app}")
        token = str(uuid.uuid4())
        before = {}
        for path in SOCKET_DIR.glob("instance-*.sock"):
            try:
                before[path] = path.stat().st_ino
            except OSError:
                pass
        command = ["/usr/bin/open", "-n", str(app), "--args", "--new-window", "--mcp-launch-token", token]
        for option, key in (("--rom", "rom_path"), ("--install", "install_path")):
            if key in arguments:
                path = Path(arguments[key]).expanduser().resolve()
                if not path.is_file():
                    raise ValueError(f"File not found: {path}")
                command.extend((option, str(path)))
        launch = subprocess.run(command, capture_output=True, text=True)
        if launch.returncode:
            raise RuntimeError(f"Could not open Palm OS Emulator: {launch.stderr.strip() or launch.stdout.strip()}")
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            for path in sorted(SOCKET_DIR.glob("instance-*.sock")):
                try:
                    if before.get(path) == path.stat().st_ino:
                        continue
                    instance = control(path, "status", timeout=2)
                    if instance.get("launch_token") == token and instance.get("window_ready"):
                        return {"instance": instance}
                except (OSError, RuntimeError, ValueError, KeyError):
                    continue
            time.sleep(0.25)
        raise TimeoutError(f"App opened, but its MCP control socket did not become ready within 90 seconds; check {SOCKET_DIR} and the app's stderr")
    sock_path = selected_socket(arguments)
    if name == "palm_wait_ready":
        timeout = arguments.get("timeout_seconds", 60)
        if not isinstance(timeout, int) or not 1 <= timeout <= 180:
            raise ValueError("timeout_seconds must be 1-180")
        deadline = time.monotonic() + timeout
        while True:
            result = control(sock_path, "status")
            if result["ready_for_install"]:
                return result
            if not result["running"]:
                raise RuntimeError("Palm OS is stopped; call palm_start or palm_load_rom first")
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Palm OS did not become ready within {timeout} seconds: {result['message']}")
            time.sleep(0.25)
    if name == "palm_pen":
        if arguments.get("action") not in ("down", "up"):
            raise ValueError("action must be down or up")
        return control(sock_path, "pen_down" if arguments["action"] == "down" else "pen_up",
                       x=arguments["x"], y=arguments["y"])
    commands = {
        "palm_status": "status", "palm_screenshot": "screenshot", "palm_tap": "tap",
        "palm_type_text": "type_text", "palm_press_key": "press_key",
        "palm_hardware_button": "hardware_button", "palm_install": "install",
        "palm_launch_app": "launch_app", "palm_load_rom": "load_rom",
        "palm_start": "start", "palm_list_sessions": "list_sessions",
        "palm_open_session": "open_session", "palm_rename_session": "rename_session",
        "palm_import_session": "import_session",
        "palm_duplicate_session": "duplicate_session", "palm_export_session": "export_session",
        "palm_delete_session": "delete_session", "palm_stop": "stop", "palm_quit": "quit", "palm_reset": "reset",
        "palm_save": "save", "palm_hot_sync": "hot_sync", "palm_set_network": "set_network",
    }
    if name not in commands:
        raise ValueError(f"Unknown tool: {name}")
    payload = {key: value for key, value in arguments.items() if key != "instance_id"}
    if name == "palm_install" and "launch" not in payload:
        payload["launch"] = True
    return control(sock_path, commands[name], **payload)


def mcp_response(request):
    method = request.get("method")
    request_id = request.get("id")
    if request_id is None:
        return None
    try:
        if method == "initialize":
            result = {"protocolVersion": VERSION, "capabilities": {"tools": {"listChanged": False}},
                      "serverInfo": {"name": NAME, "version": "1.0.0"},
                      "instructions": "Open Palm OS Emulator first. Use palm_list_instances, then pass instance_id when multiple windows are open. Call palm_wait_ready before installing applications."}
        elif method == "tools/list":
            result = {"tools": TOOLS}
        elif method == "tools/call":
            params = request.get("params") or {}
            try:
                value = call_tool(params.get("name"), params.get("arguments") or {})
                if params.get("name") == "palm_screenshot":
                    result = {"content": [
                        {"type": "text", "text": f"Palm screen {value['width']}x{value['height']}"},
                        {"type": "image", "data": value["data"], "mimeType": value["mime_type"]},
                    ]}
                else:
                    result = {"content": [{"type": "text", "text": json.dumps(value, ensure_ascii=False)}]}
            except (OSError, RuntimeError, ValueError, KeyError, TypeError, TimeoutError) as exc:
                result = {"content": [{"type": "text", "text": str(exc)}], "isError": True}
        elif method == "ping":
            result = {}
        else:
            return {"jsonrpc": "2.0", "id": request_id,
                    "error": {"code": -32601, "message": f"Method not found: {method}"}}
        return {"jsonrpc": "2.0", "id": request_id, "result": result}
    except Exception as exc:
        return {"jsonrpc": "2.0", "id": request_id,
                "error": {"code": -32603, "message": str(exc)}}


def main():
    for line in sys.stdin.buffer:
        try:
            request = json.loads(line)
            response = mcp_response(request)
        except (ValueError, TypeError) as exc:
            response = {"jsonrpc": "2.0", "id": None,
                        "error": {"code": -32700, "message": str(exc)}}
        if response is not None:
            sys.stdout.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
