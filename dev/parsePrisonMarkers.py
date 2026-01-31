import re
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
    # You can change "tes3cmd.exe" to "tes3cmd" if on Linux/Mac
    return os.path.join(script_dir, "tes3cmd.exe")

def run_tes3cmd(plugin_path):
    """
    Runs tes3cmd.exe with the required arguments and captures the output.
    """
    tes3cmd = get_tes3cmd_path()
    
    if not os.path.exists(tes3cmd):
        print(f"Error: Could not find '{tes3cmd}'.")
        print("Please place tes3cmd.exe in the same directory as this script.")
        sys.exit(1)

    # Command: tes3cmd.exe dump --instance-match "PrisonMarker" <file_path>
    cmd = [
        tes3cmd, 
        "dump", 
        "--instance-match", 
        "PrisonMarker", 
        plugin_path
    ]

    try:
        # Run command and capture stdout. 
        # encoding='cp1252' is common for Morrowind files, but 'utf-8' or 'latin-1' 
        # might be needed depending on your system locale and file contents.
        result = subprocess.run(
            cmd, 
            capture_output=True, 
            text=True, 
            encoding='cp1252', 
            errors='replace'
        )
        
        if result.returncode != 0:
            print(f"Error running tes3cmd:\n{result.stderr}")
            sys.exit(1)
            
        return result.stdout
        
    except Exception as e:
        print(f"Failed to execute subprocess: {e}")
        sys.exit(1)

def parse_tes3_dump(input_text):
    results = []
    
    # State variables
    current_cell_name = None
    current_cell_coords = None
    is_exterior = False
    
    in_object = False
    current_obj_name = None
    
    # Regex for coordinates: (18, 3) or (-2, -9)
    coord_pattern = re.compile(r"Coordinates:\s*\((-?\d+),\s*(-?\d+)\)")

    lines = input_text.splitlines()

    for line in lines:
        line = line.strip()
        
        # 1. New Cell Record Start
        if line.startswith("Record: CELL"):
            current_cell_name = None
            current_cell_coords = None
            is_exterior = False
            in_object = False
            current_obj_name = None
            continue

        # 2. Object Start (*FRMR indicates a reference/object within the cell)
        if line.startswith("*FRMR:"):
            in_object = True
            current_obj_name = None
            continue

        # 3. NAME Fields (Could be Cell Name or Object Name)
        if line.startswith("NAME:"):
            if "Name:" in line:
                name_val = line.split("Name:", 1)[1].strip()
                if in_object:
                    current_obj_name = name_val
                else:
                    current_cell_name = name_val
            continue

        # 4. DATA Fields (Cell Type/Coords or Object Data)
        if line.startswith("DATA:") and not in_object:
            if "(Exterior)" in line:
                is_exterior = True
                match = coord_pattern.search(line)
                if match:
                    x = int(match.group(1))
                    y = int(match.group(2))
                    current_cell_coords = (x, y)
            elif "(Interior)" in line:
                is_exterior = False
            continue

        # 5. DNAM Field (Destination) - Only valid if we are inside a PrisonMarker
        if line.startswith("DNAM:") and in_object:
            if current_obj_name == "PrisonMarker":
                try:
                    destination = line.split("Destination:", 1)[1].strip()
                except IndexError:
                    continue # Skip malformed lines

                entry = {}
                entry["interior"] = destination 
                
                if is_exterior and current_cell_coords:
                    entry["x"] = current_cell_coords[0]
                    entry["y"] = current_cell_coords[1]
                elif current_cell_name:
                    entry["cell"] = current_cell_name
                
                results.append(entry)

    return results

def to_lua_table(data):
    if not data:
        return "{}"
        
    lua_str = "{\n"
    for item in data:
        lua_str += "    {\n"
        if "x" in item and "y" in item:
            lua_str += f"        x = {item['x']},\n"
            lua_str += f"        y = {item['y']},\n"
        elif "cell" in item:
            # Escape quotes in cell names just in case
            safe_cell = item['cell'].replace('"', '\\"')
            lua_str += f"        cell = \"{safe_cell}\",\n"
            
        safe_interior = item['interior'].replace('"', '\\"')
        lua_str += f"        interior = \"{safe_interior}\"\n"
        lua_str += "    },\n"
    lua_str += "}"
    return lua_str

def main():
    parser = argparse.ArgumentParser(description="Extract PrisonMarker data from TES3 plugins via tes3cmd.")
    parser.add_argument("filename", help="Path to the .esp or .esm file to parse.")
    args = parser.parse_args()

    # 1. Run tes3cmd and get raw text
    print(f"Running tes3cmd on {args.filename}...")
    raw_output = run_tes3cmd(args.filename)
    
    # 2. Parse the text
    print("Parsing output...")
    parsed_data = parse_tes3_dump(raw_output)
    
    # 3. Convert to Lua
    lua_output = to_lua_table(parsed_data)
    
    # 4. Print result
    print("\n--- Lua Output ---\n")
    print(lua_output)

if __name__ == "__main__":
    main()