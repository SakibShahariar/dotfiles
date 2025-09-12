#!/usr/bin/env python3

def update_file_with_normalized_rgb():
    """
    Reads RGB values from a hardcoded file, normalizes them,
    and overwrites the file with the new values.
    """
    file_path = "/home/sakib/.config/colors/search-light.css"
    
    try:
        # Read original values
        with open(file_path, 'r') as f:
            lines = f.readlines()

        new_content = ""
        for line in lines:
            if "foreground" in line or "background" in line:
                parts = line.split('=')
                name = parts[0].strip()
                rgb_values = [int(v.strip()) for v in parts[1].split(',')]
                
                normalized_values = [round(v / 255.0, 4) for v in rgb_values]
                
                new_content += f"{name} = {normalized_values[0]}, {normalized_values[1]}, {normalized_values[2]}\n"
            else:
                new_content += line # Keep other lines if any

        # Overwrite the file with new values
        with open(file_path, 'w') as f:
            f.write(new_content)

    except FileNotFoundError:
        print(f"Error: File not found at {file_path}")
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    update_file_with_normalized_rgb()