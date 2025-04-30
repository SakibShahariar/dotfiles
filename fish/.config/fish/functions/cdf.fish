function cdf
    set -l current_dir (pwd)

    while true
        set -l subdirs (
            fd . $current_dir --type d --max-depth 1 --hidden --follow --exclude '.git' --exclude 'node_modules' \
            | grep -v "^$current_dir\$" \
            | while read -l fullpath
                echo (basename $fullpath)
            end \
            | sort \
            | fzf --height=40% --border --prompt "📁 $current_dir > " --preview 'ls -la '$current_dir'/{}'
        )

        if test -z "$subdirs"
            break
        end

        set current_dir "$current_dir/$subdirs"
        cd $current_dir
    end
end
