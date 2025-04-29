import re
import os

COLOR_CSS_PATH = "/home/sakib/.cache/wal/colors.css"
STARSHIP_COLOR_PATH = "/home/sakib/.cache/wal/colors-kitty.css" 
TEMPLATE_PAIRS = [
    {
        'template': "/home/sakib/Scripts/Pywal_Template/template_gtk.css",
        'output': "/home/sakib/.config/gtk-3.0/colors.css"
    },
    {
        'template': "/home/sakib/Scripts/Pywal_Template/template_gtk.css",
        'output': "/home/sakib/.config/gtk-4.0/colors.css"
    },
    {
        'template': "/home/sakib/Scripts/Pywal_Template/template_starship.toml",
        'output': "/home/sakib/.config/starship.toml",
        'color_source': 'starship'
    },
    {
        'template': "/home/sakib/Scripts/Pywal_Template/qt_template.conf",
        'output': "/home/sakib/.config/qt6ct/colors/matugen.conf"
    },
    {
        'template': "/home/sakib/Scripts/Pywal_Template/qt_template.conf",
        'output': "/home/sakib/.config/qt5ct/colors/matugen.conf"
    }
]

def parse_colors(css_path, is_starship=False):
    variables = {}
    with open(css_path, 'r') as f:
        content = f.read()
    
    if is_starship:
        # Match 'color0 = 'color0'' and replace with actual hex
        for match in re.finditer(r'(\bcolor\d+\b)\s*=\s*[\'"]?(color\d+)[\'"]?', content):
            key, ref = match.groups()
            if ref in variables:
                variables[key] = variables[ref]  # Replace with actual hex
        return variables  # Return early to avoid overwriting valid colors

    # Regular CSS parsing (unchanged)
    root_match = re.search(r':root\s*{([^}]*)}', content, re.DOTALL)
    if root_match:
        for match in re.finditer(r'--color(\d+)\s*:\s*(#[0-9a-fA-F]+);', root_match.group(1)):
            variables[f'color{match.group(1)}'] = match.group(2).lower()
        
        variables['current_line'] = variables.get('color7')
        variables['green'] = variables.get('color2')

    return variables

def process_template(template_path, variables, output_path, is_starship=False):
    try:
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        
        with open(template_path, 'r') as f:
            content = f.read()
        
        if is_starship:
            # Improved regex to replace 'colorX' correctly
            processed = re.sub(
                r"\b(color\d+|current_line|green)\b|'(color\d+)'",
                lambda m: variables.get(m.group(1) or m.group(2), m.group(0)),
                content
            )
        else:
            processed = re.sub(
                r'var\(--([\w-]+)\)',
                lambda m: variables.get(m.group(1), f'var(--{m.group(1)})'),
                content
            )
        
        with open(output_path, 'w') as f:
            f.write(processed)
    
    except KeyError as ke:
        print(f"Missing color variable: {ke}")
    except Exception as e:
        print(f"Error processing {template_path}: {str(e)}")


def main():
    if not os.path.exists(COLOR_CSS_PATH):
        print(f"Error: Main color file missing: {COLOR_CSS_PATH}")
        return
    
    # Load colors
    main_colors = parse_colors(COLOR_CSS_PATH)
    starship_colors = None
    
    # Load Starship colors if available
    if os.path.exists(STARSHIP_COLOR_PATH):
        starship_colors = parse_colors(STARSHIP_COLOR_PATH, is_starship=True)
    else:
        print("Using main colors for Starship")
        starship_colors = main_colors
    
    for pair in TEMPLATE_PAIRS:
        is_starship = 'starship.toml' in pair['output']
        colors_to_use = starship_colors if is_starship else main_colors
        
        if not os.path.exists(pair['template']):
            print(f"Missing template: {pair['template']}")
            continue
            
        try:
            process_template(
                pair['template'],
                colors_to_use,
                pair['output'],
                is_starship=is_starship
            )
            print(f"Success: {pair['output']}")
            
        except Exception as e:
            print(f"Failed {pair['output']}: {str(e)}")

if __name__ == "__main__":
    main()
