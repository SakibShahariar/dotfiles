import os

CONF_PATH = "/home/sakib/.config/mpv/script-opts/uosc.conf"
COLOR_PY_PATH = "/home/sakib/.config/mpv/color.py"
BACKUP_EXT = ".bak"

def get_new_color():
    """Get first line from color.py and remove # characters"""
    try:
        with open(COLOR_PY_PATH, 'r') as f:
            line = f.readline().rstrip('\n')
            return line.replace('#', '')  # Remove all # characters
    except FileNotFoundError:
        raise FileNotFoundError(f"Color file {COLOR_PY_PATH} not found")

def validate_and_update_config(new_color_line):
    """Validate config and perform update"""
    color_lines = []
    modified_lines = []
    
    with open(CONF_PATH, 'r') as f:
        for line in f:
            stripped = line.lstrip()
            if stripped.startswith('color='):
                color_lines.append(line)
                # Preserve indentation and replace content
                modified_lines.append(line.replace(line.strip(), new_color_line, 1))
            else:
                modified_lines.append(line)

    # Validation checks
    if len(color_lines) == 0:
        raise ValueError("No line starting with 'color=' found in config")
    if len(color_lines) > 1:
        raise ValueError(f"Multiple ({len(color_lines)}) 'color=' lines found")
    
    # Create backup
    os.rename(CONF_PATH, CONF_PATH + BACKUP_EXT)
    
    # Write updated config
    with open(CONF_PATH, 'w') as f:
        f.writelines(modified_lines)
    
    return len(color_lines)

def main():
    try:
        new_color = get_new_color()
        print(f"Processed color line: {new_color}")
        replacements = validate_and_update_config(new_color)
        print(f"Successfully updated color value (replaced {replacements} line)")
        print(f"Original config backed up as {CONF_PATH + BACKUP_EXT}")
    except Exception as e:
        print(f"Error: {str(e)}")
        exit(1)

if __name__ == "__main__":
    main()
