# ✨ General Setup
# --------------------------------------------------------
# Aliases and Editor Setup
alias nano='micro' 
export MICRO_TRUECOLOR=1
set -gx EDITOR micro
set -g fish_greeting ""

# 🧩 Custom Path Modification
# --------------------------------------------------------
# Clear the previous PATH (if any)
set -e PATH

# Set the correct PATH including ~/Scripts first, followed by system directories
set -Ux PATH $PATH ~/Scripts /usr/bin /usr/local/bin /home/sakib/.local/bin /home/sakib/.cargo/bin /usr/local/sbin ~/sbin

set -Ux QT_SCALE_FACTOR 0.8
set -Ux QT_QPA_PLATFORM wayland
set -Ux QT_QPA_PLATFORMTHEME qt5ct
set -Ux QT_QPA_PLATFORMTHEME_QT6 qt6ct      

set -x GOPATH (go env GOPATH)
set -x GOBIN $GOPATH/bin
set -x PATH $PATH $GOBIN

set -gx PATH /home/sakib/hellwal $PATH

# Starship Initialization (Prompt)
starship init fish | source

# 🚀 Zoxide Setup for Fast Directory Navigation
# --------------------------------------------------------
zoxide init fish | source

# 🔧 Cargo Environment
# --------------------------------------------------------
# source $HOME/.cargo/env

# Sudo override to use micro instead of nano
function sudo
    if test $argv[1] = 'nano'
        command sudo micro $argv[2..-1]
    else
        command sudo $argv
    end
end

# Typewriter effect for text output
function typewrite
    for arg in $argv
        for i in (seq (string length $arg))
            echo -n (string sub -s $i -l 1 $arg)
            sleep 0.01
        end
    end
    echo ""
end

# Yazi with custom current working directory
function y
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file="$tmp"
    if set cwd (command cat -- "$tmp"); and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
end

# FZF-based file search
function fzf_files
    set file (fzf)
    if test -n "$file"
        micro $file
    end
end
bind \cf 'fzf_files'  # Bind Ctrl+F to trigger fzf_files

# 🛠️ Aliases
# --------------------------------------------------------
# 🛠️ System Utilities
alias weather='curl wttr.in'
alias re='doas dnf remove'
alias in='doas dnf install'
# alias cp='rsync -a --progress'
alias grub_refresh="doas grub2-mkconfig -o /boot/grub2/grub.cfg"
alias grub_edit="doas nano /etc/default/grub"
# alias cd="z"
alias remove="doas dnf autoremove"
alias ss="./Scripts/Hellwall/theme_sync.fish"

# 🎨 Editor & Configuration
alias fe="micro ~/.config/fish/config.fish"
alias fr="source ~/.config/fish/config.fish"
alias kk='kitty @ set-colors --all ~/.config/kitty/colors.conf'
alias ke="micro ~/.config/kitty/kitty.conf"

# 🧑‍💻 Git & Dotfiles
alias dotgit="git --git-dir=$HOME/.dotfiles_repo/ --work-tree=$HOME"

# 📦 Miscellaneous
alias anime="fastanime --icons --fzf --preview anilist"
alias starwars="telnet towel.blinkenlights.nl"
alias clock="tty-clock -c -C 2"
alias yy="yazi"
alias yys="doas yazi"
alias ff="fastfetch"
alias rr="random-wallpaper-matugen.fish"
alias rw="matugen-picker.fish"
alias disk="dysk"
alias ask="lumo"

# 🖥️ File Management
alias ls='lsd -a $argv'
alias fzf_files="fzf"

# 🖥️ Interactive Session
# --------------------------------------------------------
if status is-interactive
    fastfetch --config ~/.config/fastfetch/pre.jsonc
end
