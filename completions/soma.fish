# Completion for the `soma` SomaFM player plugin in fish.

function __fish_soma_stations
    set -l cache_dir "$SOMA_CACHE"
    if test -z "$cache_dir"
        if set -q XDG_CACHE_HOME; and test -n "$XDG_CACHE_HOME"
            set cache_dir "$XDG_CACHE_HOME/soma"
        else
            set cache_dir "$HOME/.cache/soma"
        end
    end
    set -l cache "$cache_dir/channels.json"
    test -r "$cache"; or return 0
    command -q jq; or return 0
    jq -r '.channels[] | "\(.id)\t\(.title)"' "$cache" 2>/dev/null
end

complete -c soma -f

complete -c soma -n __fish_use_subcommand -a play -d 'start a station in the background'
complete -c soma -n __fish_use_subcommand -a stop -d 'stop playback'
complete -c soma -n __fish_use_subcommand -a track -d 'show the current track'
complete -c soma -n __fish_use_subcommand -a love -d 'save the current track to your loved list'
complete -c soma -n __fish_use_subcommand -a loved -d 'show your loved tracks'
complete -c soma -n __fish_use_subcommand -a list -d 'list all stations'
complete -c soma -n __fish_use_subcommand -a ls -d 'list all stations'
complete -c soma -n __fish_use_subcommand -a update -d 'refresh the station list'

complete -c soma -n '__fish_seen_subcommand_from play' -a '(__fish_soma_stations)'
