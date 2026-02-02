import sys
import subprocess
import os
import argparse
import re

def get_tes3cmd_path():
    """
    Determines the path to tes3cmd.exe, assuming it is in the 
    same directory as this script.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    # Adjust extension if on Linux/Mac (e.g. just "tes3cmd")
    return os.path.join(script_dir, "tes3cmd.exe")

def parse_openmw_cfg(cfg_path):
    """
    Parses openmw.cfg and returns a list of data directories.
    """
    data_dirs = []
    # Regex to capture content inside quotes: data="C:\Path\To\Mod"
    # Handles variations in whitespace.
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
                # Normalize slashes for the current OS
                path = os.path.normpath(path)
                if os.path.isdir(path):
                    data_dirs.append(path)
    
    return data_dirs

def scan_for_plugins(data_dirs):
    """
    Scans the provided data directories for .esm and .esp files.
    Returns a list of full file paths.
    """
    plugin_files = []
    # Extensions we care about
    valid_exts = ('.esm', '.esp')

    for d in data_dirs:
        try:
            # OpenMW expects plugins at the root of the data folder, 
            # so we use os.listdir instead of os.walk to avoid scanning unrelated subfolders.
            for filename in os.listdir(d):
                if filename.lower().endswith(valid_exts):
                    full_path = os.path.join(d, filename)
                    plugin_files.append(full_path)
        except OSError as e:
            print(f"Warning: Could not access directory '{d}': {e}")

    return plugin_files

def run_tes3cmd_on_file(plugin_path):
    """
    Runs tes3cmd on a single file and returns the output.
    """
    tes3cmd = get_tes3cmd_path()
    
    cmd = [
        tes3cmd, 
        "dump", 
        "--type", "crea", 
        "--type", "npc_", 
        "--flag", "persistent", 
        "--format", "%id%", 
        plugin_path
    ]

    try:
        # Using cp1252 for standard Morrowind encoding
        result = subprocess.run(
            cmd, 
            capture_output=True, 
            text=True, 
            encoding='cp1252', 
            errors='replace'
        )
        return result.stdout
    except Exception as e:
        print(f"Error processing {os.path.basename(plugin_path)}: {e}")
        return ""

def parse_ids(raw_text):
    """
    Parses raw output, strips quotes, returns a set of IDs.
    """
    ids = set()
    lines = raw_text.splitlines()

    for line in lines:
        line = line.strip()
        if not line:
            continue
        
        # Strip quotes if present
        if line.startswith('"') and line.endswith('"') and len(line) > 1:
            line = line[1:-1]
            
        ids.add(line)
    return ids

def to_lua_lookup_table(id_set):
    """
    Generates the final Lua table string.
    """
    if not id_set:
        return "{}"
        
    sorted_ids = sorted(list(id_set))
    
    lua_str = "{\n"
    for obj_id in sorted_ids:
        safe_id = obj_id.replace('"', '\\"')
        lua_str += f'    ["{safe_id}"] = true,\n'
    lua_str += "}"
    return lua_str

def main():
    parser = argparse.ArgumentParser(description="Scan OpenMW load order for persistent actors.")
    parser.add_argument("cfg_path", help="Path to your openmw.cfg file.")
    args = parser.parse_args()

    # Check for tes3cmd existence first
    if not os.path.exists(get_tes3cmd_path()):
        print("Error: tes3cmd.exe not found in script directory.")
        sys.exit(1)

    print(f"--- Parsing Config: {args.cfg_path} ---")
    data_dirs = parse_openmw_cfg(args.cfg_path)
    print(f"Found {len(data_dirs)} data directories.")

    print("\n--- Scanning for Plugins ---")
    plugins = scan_for_plugins(data_dirs)
    print(f"Found {len(plugins)} ESM/ESP files.")

    all_persistent_ids = set()

    print("\n--- Processing Files ---")
    for i, plugin in enumerate(plugins, 1):
        filename = os.path.basename(plugin)
        print(f"[{i}/{len(plugins)}] Parsing: {filename} ...", end="\r")
        
        raw_output = run_tes3cmd_on_file(plugin)
        file_ids = parse_ids(raw_output)
        
        # Update our master set
        all_persistent_ids.update(file_ids)

    print(f"\n\nDone! Found {len(all_persistent_ids)} unique persistent IDs.")

    # Generate Output
    lua_output = to_lua_lookup_table(all_persistent_ids)
    
    # Print to console (or redirect to file)
    print("\n--- Lua Output ---\n")
    print(lua_output)
    
    # Helper to save automatically
    output_file = "persistent_ids.lua"
    with open(output_file, "w", encoding='utf-8') as f:
        f.write("return " + lua_output)
    print(f"\n(File saved to {output_file})")

if __name__ == "__main__":
    main()