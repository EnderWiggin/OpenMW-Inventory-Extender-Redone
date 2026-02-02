import sys
import subprocess
import os
import argparse

def get_tes3cmd_path():
    """
    Determines the path to tes3cmd.exe, assuming it is in the 
    same directory as this script.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(script_dir, "tes3cmd.exe")

def run_tes3cmd(plugin_path):
    """
    Runs tes3cmd.exe with the specified arguments:
    dump --type crea --type npc_ --flag persistent --format %id%
    """
    tes3cmd = get_tes3cmd_path()
    
    if not os.path.exists(tes3cmd):
        print(f"Error: Could not find '{tes3cmd}'.")
        print("Please place tes3cmd.exe in the same directory as this script.")
        sys.exit(1)

    # Command construction
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
        # Run command and capture stdout
        # using cp1252 to match standard Morrowind file encoding
        result = subprocess.run(
            cmd, 
            capture_output=True, 
            text=True, 
            encoding='cp1252', 
            errors='replace'
        )
        
        if result.returncode != 0:
            # tes3cmd often returns non-zero on minor warnings, so we print stderr 
            # but proceed if we actually got output.
            if not result.stdout:
                print(f"Error running tes3cmd:\n{result.stderr}")
                sys.exit(1)
            
        return result.stdout
        
    except Exception as e:
        print(f"Failed to execute subprocess: {e}")
        sys.exit(1)

def parse_ids(raw_text):
    """
    Parses the raw lines from tes3cmd.
    Removes surrounding quotes if present.
    """
    cleaned_ids = []
    lines = raw_text.splitlines()

    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        # Check if the line is wrapped in quotes (e.g., "galtis guvron")
        # and strip them if so.
        if line.startswith('"') and line.endswith('"') and len(line) > 1:
            line = line[1:-1]
            
        cleaned_ids.append(line)
        
    # Sort for cleaner output
    cleaned_ids.sort()
    return cleaned_ids

def to_lua_lookup_table(id_list):
    """
    Generates a Lua table where keys are IDs and values are true.
    Example: { ["galtis guvron"] = true, ... }
    """
    if not id_list:
        return "{}"
        
    lua_str = "{\n"
    for obj_id in id_list:
        # Escape double quotes in the ID if they exist (rare, but safe)
        safe_id = obj_id.replace('"', '\\"')
        lua_str += f'    ["{safe_id}"] = true,\n'
    lua_str += "}"
    return lua_str

def main():
    parser = argparse.ArgumentParser(description="Generate Lua lookup table for Persistent NPCs/Creatures.")
    parser.add_argument("filename", help="Path to the .esp or .esm file to parse.")
    args = parser.parse_args()

    # 1. Run tes3cmd
    print(f"Scanning {args.filename} for persistent actors...")
    raw_output = run_tes3cmd(args.filename)
    
    # 2. Parse IDs
    ids = parse_ids(raw_output)
    print(f"Found {len(ids)} persistent records.")
    
    # 3. Generate Lua
    lua_output = to_lua_lookup_table(ids)
    
    # 4. Print Result
    print("\n--- Lua Output ---\n")
    print(lua_output)
    
    # Optional: Write to file
    # with open("persistent_ids.lua", "w") as f:
    #     f.write("return " + lua_output)

if __name__ == "__main__":
    main()