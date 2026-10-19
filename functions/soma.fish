# soma — a tiny SomaFM player for fish
#
#   soma play <station>   start a station in the background (Tab-completes)
#   soma stop             stop playback
#   soma track            show the current track
#   soma love             save the current track to your loved list
#   soma loved            show your loved tracks
#   soma list             list all stations
#   soma update           refresh the cached station list
#
# Config (override before the plugin loads, or in ~/.config/fish/config.fish):
#   SOMA_CACHE          where state/cache live (default: $XDG_CACHE_HOME/soma)
#   SOMA_CHANNELS_URL   station list endpoint
#   SOMA_REFRESH_DAYS   auto-refresh the station list after N days (default 7)
#   SOMA_MPG123_OPTS    extra args for mpg123 (e.g. "-o dummy" for no audio)
#   SOMA_TIMEOUT        seconds before mpg123 gives up on a stalled stream (default 30; 0 = forever)
#   SOMA_LOVED          file for your loved-tracks list (default: $XDG_DATA_HOME/soma/loved)

function _soma_init_defaults
    if not set -q SOMA_CACHE; or test -z "$SOMA_CACHE"
        if set -q XDG_CACHE_HOME; and test -n "$XDG_CACHE_HOME"
            set -g SOMA_CACHE "$XDG_CACHE_HOME/soma"
        else
            set -g SOMA_CACHE "$HOME/.cache/soma"
        end
    end
    if not set -q SOMA_CHANNELS_URL; or test -z "$SOMA_CHANNELS_URL"
        set -g SOMA_CHANNELS_URL "https://somafm.com/channels.json"
    end
    if not set -q SOMA_REFRESH_DAYS; or test -z "$SOMA_REFRESH_DAYS"
        set -g SOMA_REFRESH_DAYS 7
    end
    if not set -q SOMA_MPG123_OPTS
        set -g SOMA_MPG123_OPTS ""
    end
    if not set -q SOMA_TIMEOUT; or test -z "$SOMA_TIMEOUT"
        set -g SOMA_TIMEOUT 30
    end
    if not set -q SOMA_LOVED; or test -z "$SOMA_LOVED"
        if set -q XDG_DATA_HOME; and test -n "$XDG_DATA_HOME"
            set -g SOMA_LOVED "$XDG_DATA_HOME/soma/loved"
        else
            set -g SOMA_LOVED "$HOME/.local/share/soma/loved"
        end
    end
end

function _soma_need
    set -l miss 0
    for t in $argv
        if not command -q "$t"
            printf 'soma: missing required tool: %s\n' "$t" >&2
            set miss 1
        end
    end
    return $miss
end

function _soma_fetch
    _soma_need curl jq; or return 1
    mkdir -p "$SOMA_CACHE"
    if curl -fsSL -A "soma-zsh-plugin (https://codeberg.org/mvexel/omz-soma-plugin)" \
            "$SOMA_CHANNELS_URL" -o "$SOMA_JSON.tmp"
        mv -f "$SOMA_JSON.tmp" "$SOMA_JSON"
        return 0
    end
    rm -f "$SOMA_JSON.tmp"
    printf 'soma: failed to fetch station list from %s\n' "$SOMA_CHANNELS_URL" >&2
    return 1
end

# Ensure the station list exists; refresh it if older than SOMA_REFRESH_DAYS.
function _soma_ensure_json
    if not test -f "$SOMA_JSON"
        _soma_fetch
        return $status
    end
    set -l mtime (stat -c %Y "$SOMA_JSON" 2>/dev/null; or stat -f %m "$SOMA_JSON" 2>/dev/null)
    set -l now (date +%s 2>/dev/null)
    if test -n "$mtime" -a -n "$now"
        if test (math "$now - $mtime") -gt (math "$SOMA_REFRESH_DAYS * 86400")
            _soma_fetch
        end
    end
    return 0
end

# True if $1 is a live process actually running mpg123. Guards against a stale
# PID file (after a reboot or a sleep/wake that killed the stream) whose number
# now belongs to nothing, or to some unrelated process that reused it.
function _soma_is_mpg123
    set -l pid $argv[1]
    test -n "$pid"; or return 1
    set -l comm
    if test -r "/proc/$pid/comm"
        read -l comm < "/proc/$pid/comm"
    else
        set comm (ps -o comm= -p "$pid" 2>/dev/null); or return 1
    end
    test (path basename -- (string trim -- "$comm")) = mpg123
end

# Print the PID if our tracked mpg123 is alive; otherwise clean up state and fail.
function _soma_running_pid
    test -f "$SOMA_PID"; or return 1
    set -l pid
    read -l pid < "$SOMA_PID"
    if _soma_is_mpg123 "$pid"
        printf '%s\n' "$pid"
        return 0
    end
    rm -f "$SOMA_PID" "$SOMA_CUR"
    return 1
end

function _soma_stop_quiet
    set -l pid (_soma_running_pid); or return 0
    kill "$pid" 2>/dev/null
    for i in (seq 10)
        kill -0 "$pid" 2>/dev/null; or break
        sleep 0.1
    end
    kill -9 "$pid" 2>/dev/null
    rm -f "$SOMA_PID"
end

function _soma_play
    _soma_need mpg123 jq curl; or return 1
    set -l id $argv[1]
    if test -z "$id"
        printf 'soma: usage: soma play <station>   (try: soma list, or press Tab)\n' >&2
        return 1
    end
    _soma_ensure_json; or return 1
    if not jq -e --arg id "$id" '.channels[]|select(.id==$id)' "$SOMA_JSON" >/dev/null 2>&1
        printf "soma: unknown station '%s'  (run: soma list)\n" "$id" >&2
        return 1
    end
    set -l url (jq -r --arg id "$id" \
        '.channels[]|select(.id==$id)|.playlists|(map(select(.format=="mp3")) + .)|.[0].url' "$SOMA_JSON")
    if test -z "$url" -o "$url" = null
        printf "soma: no mp3 stream available for '%s' (mpg123 can't play AAC)\n" "$id" >&2
        return 1
    end
    _soma_stop_quiet
    mkdir -p "$SOMA_CACHE"
    true > "$SOMA_LOG"
    set -l opts (string split -n ' ' -- $SOMA_MPG123_OPTS)
    nohup mpg123 --timeout "$SOMA_TIMEOUT" $opts -@ "$url" >"$SOMA_LOG" 2>&1 </dev/null &
    set -l pid $last_pid
    disown $pid 2>/dev/null
    printf '%s\n' "$pid" > "$SOMA_PID"
    printf '%s\n' "$id" > "$SOMA_CUR"
    set -l title (jq -r --arg id "$id" '.channels[]|select(.id==$id)|.title' "$SOMA_JSON")
    test -n "$title"; or set title "$id"
    printf '▶ %s  (pid %s)\n' "$title" "$pid"
end

function _soma_stop
    if _soma_running_pid >/dev/null
        _soma_stop_quiet
        printf '■ stopped\n'
    else
        printf 'soma: nothing playing\n' >&2
    end
end

# Parse the artist/title from the last ICY StreamTitle mpg123 logged.
# Prints the track string; fails with no output if none is available yet.
function _soma_current_track
    test -f "$SOMA_LOG"; or return 1
    set -l line (grep -a "StreamTitle=" "$SOMA_LOG" 2>/dev/null | tail -1)
    test -n "$line"; or return 1
    set -l t (string replace -r "^.*?StreamTitle='" '' -- "$line")
    if string match -q "*';StreamUrl=*" -- "$t"
        set t (string replace -r "(.*)';StreamUrl=.*" '$1' -- "$t")
    else
        set t (string replace -r "(.*)'.*" '$1' -- "$t")
    end
    test -n "$t"; or return 1
    printf '%s\n' "$t"
end

function _soma_track
    if not _soma_running_pid >/dev/null
        printf 'soma: nothing playing\n' >&2
        return 1
    end
    set -l t (_soma_current_track); or begin
        printf '♪ buffering…\n'
        return 0
    end
    printf '♪ %s\n' "$t"
end

# Append the currently-playing track to the loved list as a ts/id/title/track TSV row.
function _soma_love
    if not _soma_running_pid >/dev/null
        printf 'soma: nothing playing\n' >&2
        return 1
    end
    set -l track (_soma_current_track); or begin
        printf 'soma: no track info yet (still buffering?)\n' >&2
        return 1
    end
    set -l id
    test -f "$SOMA_CUR"; and read -l id < "$SOMA_CUR"
    set -l title
    if test -n "$id" -a -f "$SOMA_JSON"
        set title (jq -r --arg id "$id" '.channels[]|select(.id==$id)|.title' "$SOMA_JSON" 2>/dev/null)
    end
    test -n "$title"; or set title "$id"
    set -l entry (printf '%s\t%s\t%s' "$id" "$title" "$track")
    if test -f "$SOMA_LOVED"
        set -l last (tail -1 "$SOMA_LOVED" 2>/dev/null)
        set -l last_entry (string replace -r '^[^\t]*\t' '' -- "$last")
        if test "$last_entry" = "$entry"
            printf '♥ already loved: %s\n' "$track"
            return 0
        end
    end
    set -l ts (date '+%F %T')
    mkdir -p (path dirname -- "$SOMA_LOVED")
    printf '%s\t%s\n' "$ts" "$entry" >> "$SOMA_LOVED"
    printf '♥ loved: %s  (%s)\n' "$track" "$title"
end

# Show the loved-tracks list, oldest first.
function _soma_loved
    if not test -s "$SOMA_LOVED"
        printf 'soma: no loved tracks yet  (play something and run: soma love)\n'
        return 0
    end
    while IFS=\t read -r -l ts id title track
        set -l label "$title"
        test -n "$label"; or set label "$id"
        printf '  %s  ♥ %s  [%s]\n' "$ts" "$track" "$label"
    end < "$SOMA_LOVED"
end

function _soma_list
    _soma_need jq; or return 1
    _soma_ensure_json; or return 1
    jq -r '.channels[] | [.id, .title, .genre] | @tsv' "$SOMA_JSON" \
        | while IFS=\t read -r -l id title genre
            printf '  %-18s %-28s %s\n' "$id" "$title" "$genre"
        end
end

function _soma_usage
    printf '%s\n' "soma — SomaFM player
  soma play <station>   start a station in the background (Tab to complete)
  soma stop             stop playback
  soma track            show the current track
  soma love             save the current track to your loved list
  soma loved            show your loved tracks
  soma list             list all stations
  soma update           refresh the station list

  If you enjoy listening to SomaFM, please consider a donation. Any amount helps!"
end

function soma --description "SomaFM player"
    _soma_init_defaults
    set -g SOMA_JSON "$SOMA_CACHE/channels.json"
    set -g SOMA_PID "$SOMA_CACHE/soma.pid"
    set -g SOMA_LOG "$SOMA_CACHE/now.log"
    set -g SOMA_CUR "$SOMA_CACHE/current"

    set -l cmd $argv[1]
    set -l args $argv[2..-1]

    switch "$cmd"
        case play
            _soma_play $args
        case stop
            _soma_stop
        case track
            _soma_track
        case love
            _soma_love
        case loved
            _soma_loved
        case list ls
            _soma_list
        case update refresh
            _soma_fetch; and printf 'soma: station list updated\n'
        case '' help -h --help
            _soma_usage
        case '*'
            printf 'soma: unknown command: %s\n' "$cmd" >&2
            _soma_usage
            return 1
    end
end
