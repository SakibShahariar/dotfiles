# Matugen Generated Colors for Fish Shell
set -g matugen_primary '#b7cea0'
set -g matugen_on_primary '#243515'
set -g matugen_surface '#131411'
set -g matugen_on_surface '#e4e2dd'
set -g matugen_error '#ffb4ab'

# Apply colors to Fish core syntax highlighting
set -g fish_color_normal $matugen_on_surface
set -g fish_color_command $matugen_primary --bold
set -g fish_color_keyword $matugen_primary
set -g fish_color_quote $matugen_on_primary
set -g fish_color_redirection $matugen_on_surface
set -g fish_color_end $matugen_on_surface
set -g fish_color_error $matugen_error
set -g fish_color_param $matugen_on_surface
set -g fish_color_comment $matugen_on_surface --italics
set -g fish_color_selection --background=$matugen_primary
set -g fish_color_search_match --background=$matugen_primary
set -g fish_color_operator $matugen_primary
set -g fish_color_escape $matugen_primary
set -g fish_color_autosuggestion $matugen_on_surface

# Pager colors (tab completion menus)
set -g fish_pager_color_progress $matugen_primary
set -g fish_pager_color_prefix $matugen_primary --bold
set -g fish_pager_color_completion $matugen_on_surface
set -g fish_pager_color_description $matugen_on_surface
