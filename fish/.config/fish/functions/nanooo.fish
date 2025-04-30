# ~/.config/fish/functions/nanooo.fish
function nanooo
    set -l current_dir (pwd)

    while true
        # Selecting directories (limit depth 1)
        set -l file_dir (fd --type d --max-depth 1 --hidden --follow --exclude '.git' --exclude 'node_modules' . $current_dir \
            | sed "s|^$current_dir/||" \
            | sort \
            | fzf --height=40% --border --prompt "📁 $current_dir > " --preview 'ls -la '$current_dir'/{}')

        # If no directory was selected, break the loop
        if test -z "$file_dir"
            break
        end

        # Update current_dir based on the selected directory
        set current_dir (realpath $current_dir/$file_dir)  # Fixing path with realpath
    end

    # Searching for files in the selected directory
    set -l files (fd --type f --max-depth 1 --hidden --follow --exclude '.git' --exclude 'node_modules' . $current_dir)

    # If files exist in the current directory
    if test -n "$files"
        # Display files for selection
        set -l file (echo "$files" | sed "s|^$current_dir/||" | fzf --height=40% --border --prompt "📝 $current_dir > " --preview 'bat --style=numbers --color=always '$current_dir'/{} || cat '$current_dir'/{}')

        # If a file is selected, open it in nano
        if test -n "$file"
            nano "$current_dir/$file"
        end
    else
        echo "No files found in this directory."
    end
end
