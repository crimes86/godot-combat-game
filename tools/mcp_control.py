#!/usr/bin/env python3
"""
MCP Bridge Control - Send commands to running Godot game via MCPBridge

Usage:
    python mcp_control.py <command> [args...]

Commands:
    ping                    - Check connection
    take_control            - Take AI control of player
    release_control         - Release control back to human
    state                   - Get current game state (includes facing direction)

    Movement:
    move <x> <y>            - Move in direction (-1 to 1 for each axis)
    move_to <x> <y>         - Move to world position
    stop                    - Stop moving and facing

    Facing (controls attack direction):
    face <x> <y>            - Face towards a world position

    Combat:
    attack                  - Attack in current facing direction
    attack_at <x> <y>       - Face position, then attack
    attack_id <enemy_id>    - Face enemy by ID, then attack
    dodge                   - Dodge roll
    auto_combat             - Auto-fight nearest enemy (auto-facing)
    stop_combat             - Stop auto-combat mode

    Interaction:
    interact                - Interact with nearest object
    teleport <x> <y>        - Teleport to position
    goto_npc <name>         - Move to NPC by name (e.g., "Wanderer")

    Info queries:
    enemies [radius]        - Get nearby enemies with IDs (default: 500)
    items [radius]          - Get nearby items (default: 300)
    npcs [radius]           - Get nearby NPCs (default: 500)
    weakpoints              - Get active weakpoints on enemies
    inventory               - Get player inventory
    quests                  - Get quest status (available, active, completed)
    progress                - Get detailed quest progress with objectives
    screenshot              - Take screenshot, returns path

    Quest actions:
    accept <quest_id>       - Accept an available quest
    turn_in <quest_id>      - Turn in a completed quest
    loot [radius]           - Auto-loot nearby items (default: 100)

    Shop & Equipment:
    shop                    - Browse shop inventory (weapons & armor)
    buy <item_id> [type]    - Buy item (type: weapon/armor, default: weapon)
    equip <slot|item_id>    - Equip item by inventory slot or item ID
    equip_best              - Auto-equip best gear from inventory
    gold [amount]           - Give gold (debug, default: 100)

    Weakpoint interaction:
    click_wp <id>           - Click a weakpoint by ID (from weakpoints list)

    Menu automation:
    menu_state              - Get current menu/scene state
    play_guest              - Click "Play as Guest" on main menu
    enter_world             - Click "Enter World" in Armory

    Campfire/Healing:
    find_campfire [radius]  - Find nearest campfire (default: 500)
    goto_campfire           - Walk to nearest campfire for healing

    Forge items:
    forge_items [type]      - Get forge items (type: shield, weapon, head, etc.)

Examples:
    python mcp_control.py ping
    python mcp_control.py take_control
    python mcp_control.py face 100 200      # Face position (100, 200)
    python mcp_control.py attack            # Attack in that direction
    python mcp_control.py attack_at 100 200 # Face + attack in one command
    python mcp_control.py enemies 300       # Get enemies with their IDs
    python mcp_control.py attack_id 12345   # Attack enemy by ID
    python mcp_control.py auto_combat       # Auto-face + attack nearest
"""

import socket
import json
import sys

HOST = '127.0.0.1'
PORT = 9050
TIMEOUT = 5.0

def send_command(cmd: dict) -> dict:
    """Send a command to MCPBridge and return the response."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(TIMEOUT)
            sock.connect((HOST, PORT))

            # Send command as JSON with newline
            message = json.dumps(cmd) + "\n"
            sock.sendall(message.encode('utf-8'))

            # Read response
            response = b""
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                response += chunk
                if b"\n" in response:
                    break

            # Parse response
            response_str = response.decode('utf-8').strip()
            if response_str:
                return json.loads(response_str)
            return {"error": "Empty response"}

    except ConnectionRefusedError:
        return {"error": "Connection refused - is the game running in debug mode?"}
    except socket.timeout:
        return {"error": "Connection timed out"}
    except Exception as e:
        return {"error": str(e)}

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1].lower()
    args = sys.argv[2:]

    cmd = {}

    if command == "ping":
        cmd = {"action": "ping"}

    elif command == "take_control":
        cmd = {"action": "take_control"}

    elif command == "release_control":
        cmd = {"action": "release_control"}

    elif command == "state":
        cmd = {"action": "get_state"}

    elif command == "move":
        if len(args) < 2:
            print("Usage: move <x> <y>  (values from -1 to 1)")
            sys.exit(1)
        cmd = {"action": "move", "x": float(args[0]), "y": float(args[1])}

    elif command == "move_to":
        if len(args) < 2:
            print("Usage: move_to <x> <y>")
            sys.exit(1)
        cmd = {"action": "move_to", "x": float(args[0]), "y": float(args[1])}

    elif command == "stop":
        cmd = {"action": "stop"}

    elif command == "face":
        if len(args) < 2:
            print("Usage: face <x> <y>  (world position to face)")
            sys.exit(1)
        cmd = {"action": "face", "x": float(args[0]), "y": float(args[1])}

    elif command == "attack":
        cmd = {"action": "attack"}

    elif command == "attack_at":
        if len(args) < 2:
            print("Usage: attack_at <x> <y>  (face position, then attack)")
            sys.exit(1)
        cmd = {"action": "attack", "target_x": float(args[0]), "target_y": float(args[1])}

    elif command == "attack_id":
        if len(args) < 1:
            print("Usage: attack_id <enemy_id>  (get IDs from 'enemies' command)")
            sys.exit(1)
        cmd = {"action": "attack_target", "id": int(args[0])}

    elif command == "dodge":
        cmd = {"action": "dodge"}

    elif command == "interact":
        cmd = {"action": "interact"}

    elif command == "teleport":
        if len(args) < 2:
            print("Usage: teleport <x> <y>")
            sys.exit(1)
        cmd = {"action": "teleport", "x": float(args[0]), "y": float(args[1])}

    elif command == "enemies":
        radius = float(args[0]) if args else 500.0
        cmd = {"action": "get_nearby_enemies", "radius": radius}

    elif command == "items":
        radius = float(args[0]) if args else 300.0
        cmd = {"action": "get_nearby_items", "radius": radius}

    elif command == "screenshot":
        cmd = {"action": "screenshot"}

    elif command == "inventory":
        cmd = {"action": "get_inventory"}

    elif command == "quests":
        cmd = {"action": "get_quests"}

    elif command == "progress":
        cmd = {"action": "quest_progress"}

    elif command == "accept":
        if len(args) < 1:
            print("Usage: accept <quest_id>  (get IDs from 'quests' command)")
            sys.exit(1)
        cmd = {"action": "accept_quest", "quest_id": args[0]}

    elif command == "turn_in":
        if len(args) < 1:
            print("Usage: turn_in <quest_id>  (get IDs from 'quests' command)")
            sys.exit(1)
        cmd = {"action": "turn_in_quest", "quest_id": args[0]}

    elif command == "loot":
        radius = float(args[0]) if args else 100.0
        cmd = {"action": "loot_items", "radius": radius}

    elif command == "shop":
        cmd = {"action": "get_shop"}

    elif command == "buy":
        if len(args) < 1:
            print("Usage: buy <item_id> [type]  (type: weapon or armor, default: weapon)")
            sys.exit(1)
        item_type = args[1] if len(args) > 1 else "weapon"
        cmd = {"action": "buy_item", "item_id": args[0], "item_type": item_type}

    elif command == "equip":
        if len(args) < 1:
            print("Usage: equip <slot_number|item_id>")
            sys.exit(1)
        # Try to parse as int (slot), otherwise treat as item_id
        try:
            slot = int(args[0])
            cmd = {"action": "equip_item", "slot": slot}
        except ValueError:
            cmd = {"action": "equip_item", "item_id": args[0]}

    elif command == "equip_best":
        cmd = {"action": "equip_best"}

    elif command == "gold":
        amount = int(args[0]) if args else 100
        cmd = {"action": "give_gold", "amount": amount}

    elif command == "npcs":
        radius = float(args[0]) if args else 500.0
        cmd = {"action": "get_npcs", "radius": radius}

    elif command == "weakpoints":
        cmd = {"action": "get_weakpoints"}

    elif command == "click_wp":
        if len(args) < 1:
            print("Usage: click_wp <weakpoint_id>  (get IDs from 'weakpoints' command)")
            sys.exit(1)
        cmd = {"action": "click_weakpoint", "id": int(args[0])}

    elif command == "goto_npc":
        if len(args) < 1:
            print("Usage: goto_npc <name>")
            sys.exit(1)
        cmd = {"action": "move_to_npc", "name": args[0]}

    elif command == "auto_combat":
        cmd = {"action": "auto_combat"}

    elif command == "stop_combat":
        cmd = {"action": "stop_combat"}

    # Menu automation
    elif command == "menu_state":
        cmd = {"action": "get_menu_state"}

    elif command == "play_guest":
        cmd = {"action": "click_play_guest"}

    elif command == "enter_world":
        cmd = {"action": "click_enter_world"}

    # Campfire/Healing
    elif command == "find_campfire":
        radius = float(args[0]) if args else 500.0
        cmd = {"action": "find_campfire", "radius": radius}

    elif command == "goto_campfire":
        cmd = {"action": "goto_campfire"}

    # Forge items
    elif command == "forge_items":
        item_type = args[0] if args else ""
        cmd = {"action": "get_forge_items", "type": item_type}

    else:
        print(f"Unknown command: {command}")
        print(__doc__)
        sys.exit(1)

    # Send and print result
    result = send_command(cmd)
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
