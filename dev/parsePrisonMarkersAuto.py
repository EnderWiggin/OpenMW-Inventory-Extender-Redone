import sys
import subprocess
import os
import argparse
import re

def get_tes3cmd_path():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(script_dir, "tes3cmd.exe")

def parse_openmw_cfg(cfg_path):
    """
    Parses openmw.cfg to find data directories.
    """
    data_dirs = []
    # Regex for data="C:\Path"
    data_pattern = re.compile(r'^data\s*=\s*["\'](.+?)["\']', re.IGNORECASE)

    if not os.path.exists(cfg_path):
        print(f"Error: Could not find config file at: {cfg_path}")
        sys.exit(1)

    with open(cfg_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            match = data_pattern.match(line)
            if match:
                path = match.group(1)
                path = os.path.normpath(path)
                if os.path.isdir(path):
                    data_dirs.append(path)
    return data_dirs

def get_unique_plugins(data_dirs):
    """
    Scans data directories for plugins. 
    Handles overrides: if the same filename exists in multiple dirs, 
    the one from the directory listed later (assumed higher priority) is used.
    """
    plugin_map = {} # { "Morrowind.esm": "C:/Path/To/Morrowind.esm" }
    valid_exts = ('.esm', '.esp')

    for d in data_dirs:
        try:
            for filename in os.listdir(d):
                if filename.lower().endswith(valid_exts):
                    # This assignment automatically handles overrides 
                    # by replacing the entry if found in a later folder.
                    plugin_map[filename] = os.path.join(d, filename)
        except OSError:
            continue
            
    return plugin_map

def run_tes3cmd(plugin_path):
    """
    Runs: tes3cmd dump --instance-match "PrisonMarker" <file>
    """
    tes3cmd = get_tes3cmd_path()
    if not os.path.exists(tes3cmd):
        print(f"Error: {tes3cmd} not found.")
        sys.exit(1)

    cmd = [
        tes3cmd, 
        "dump", 
        "--instance-match", 
        "PrisonMarker", 
        plugin_path
    ]

    try:
        result = subprocess.run(
            cmd, 
            capture_output=True, 
            text=True, 
            encoding='cp1252', 
            errors='replace'
        )
        return result.stdout
    except Exception as e:
        print(f"Error running tes3cmd on {os.path.basename(plugin_path)}: {e}")
        return ""

def parse_prison_markers(raw_text):
    """
    Parses the text output from tes3cmd into a list of dictionaries.
    """
    results = []
    
    # State
    current_cell_name = None
    current_cell_coords = None
    is_exterior = False
    in_object = False
    current_obj_name = None
    
    coord_pattern = re.compile(r"Coordinates:\s*\((-?\d+),\s*(-?\d+)\)")

    lines = raw_text.splitlines()

    for line in lines:
        line = line.strip()
        
        # New Cell Record
        if line.startswith("Record: CELL"):
            current_cell_name = None
            current_cell_coords = None
            is_exterior = False
            in_object = False
            current_obj_name = None
            continue

        # Object/Reference Record
        if line.startswith("*FRMR:"):
            in_object = True
            current_obj_name = None
            continue

        # NAME Field
        if line.startswith("NAME:"):
            if "Name:" in line:
                val = line.split("Name:", 1)[1].strip()
                if in_object:
                    current_obj_name = val
                else:
                    current_cell_name = val
            continue

        # DATA Field
        if line.startswith("DATA:") and not in_object:
            if "(Exterior)" in line:
                is_exterior = True
                match = coord_pattern.search(line)
                if match:
                    current_cell_coords = (int(match.group(1)), int(match.group(2)))
            elif "(Interior)" in line:
                is_exterior = False
            continue

        # DNAM (Destination) - The payload we want
        if line.startswith("DNAM:") and in_object:
            if current_obj_name == "PrisonMarker":
                try:
                    dest = line.split("Destination:", 1)[1].strip()
                    entry = { "interior": dest }
                    
                    if is_exterior and current_cell_coords:
                        entry["x"] = current_cell_coords[0]
                        entry["y"] = current_cell_coords[1]
                    elif current_cell_name:
                        entry["cell"] = current_cell_name
                    
                    results.append(entry)
                except IndexError:
                    pass

    return results

def generate_lua_script(master_table):
    """
    Generates the Lua script string from the master dictionary.
    """
    lua = "local PrisonMarkers = {}\n\n"
    
    for filename, markers in master_table.items():
        if not markers:
            continue
            
        lua += f"PrisonMarkers['{filename}'] = {{\n"
        
        for m in markers:
            lua += "    {\n"
            if "x" in m and "y" in m:
                lua += f"        x = {m['x']},\n"
                lua += f"        y = {m['y']},\n"
            elif "cell" in m:
                safe_cell = m['cell'].replace('"', '\\"')
                lua += f"        cell = \"{safe_cell}\",\n"
            
            safe_dest = m['interior'].replace('"', '\\"')
            lua += f"        interior = \"{safe_dest}\"\n"
            lua += "    },\n"
            
        lua += "}\n\n"
    
    lua += "return PrisonMarkers\n"
    return lua

def main():
    parser = argparse.ArgumentParser(description="Generate Lua PrisonMarkers table from OpenMW load order.")
    parser.add_argument("cfg_path", help="Path to openmw.cfg")
    args = parser.parse_args()

    # 1. Parse Config
    print(f"Reading config: {args.cfg_path}")
    data_dirs = parse_openmw_cfg(args.cfg_path)
    
    # 2. Map Plugins (Resolving paths)
    print("Scanning data directories...")
    plugin_map = get_unique_plugins(data_dirs)
    print(f"Found {len(plugin_map)} unique plugins.")

    master_data = {}

    # 3. Process Plugins
    count = 0
    total = len(plugin_map)
    
    for filename, full_path in plugin_map.items():
        count += 1
        print(f"[{count}/{total}] Parsing {filename}...", end="\r")
        
        raw_output = run_tes3cmd(full_path)
        markers = parse_prison_markers(raw_output)
        
        if markers:
            master_data[filename] = markers

    print("\n\nExtraction complete.")
    
    # 4. Generate Lua
    lua_output = generate_lua_script(master_data)
    
    # 5. Save
    out_file = "PrisonMarkers.lua"
    with open(out_file, "w", encoding='utf-8') as f:
        f.write(lua_output)
        
    print(f"Successfully saved to {out_file}")

if __name__ == "__main__":
    main()