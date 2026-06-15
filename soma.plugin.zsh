# soma — a tiny SomaFM player for zsh / oh-my-zsh
#
#   soma play <station>   start a station in the background (Tab-completes)
#   soma stop             stop playback
#   soma track            show the current track
#   soma status           show what's playing  (also: bare `soma`)
#   soma list             list all stations
#   soma update           refresh the cached station list
#
# Config (override before the plugin loads, or in ~/.zshrc):
#   SOMA_CACHE          where state/cache live (default: $XDG_CACHE_HOME/soma)
#   SOMA_CHANNELS_URL   station list endpoint
#   SOMA_REFRESH_DAYS   auto-refresh the station list after N days (default 7)
#   SOMA_MPG123_OPTS    extra args for mpg123 (e.g. "-o dummy" for no audio)

: ${SOMA_CACHE:=${XDG_CACHE_HOME:-$HOME/.cache}/soma}
: ${SOMA_CHANNELS_URL:=https://somafm.com/channels.json}
: ${SOMA_REFRESH_DAYS:=7}
: ${SOMA_MPG123_OPTS:=}

_soma_paths() {
  SOMA_JSON="$SOMA_CACHE/channels.json"
  SOMA_PID="$SOMA_CACHE/soma.pid"
  SOMA_LOG="$SOMA_CACHE/now.log"
  SOMA_CUR="$SOMA_CACHE/current"
}

_soma_need() {
  local t miss=0
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || { print -ru2 -- "soma: missing required tool: $t"; miss=1; }
  done
  return $miss
}

_soma_fetch() {
  _soma_need curl jq || return 1
  mkdir -p "$SOMA_CACHE"
  if curl -fsSL "$SOMA_CHANNELS_URL" -o "$SOMA_JSON.tmp"; then
    mv -f "$SOMA_JSON.tmp" "$SOMA_JSON"
    return 0
  fi
  rm -f "$SOMA_JSON.tmp"
  print -ru2 -- "soma: failed to fetch station list from $SOMA_CHANNELS_URL"
  return 1
}

# Ensure the station list exists; refresh it if older than SOMA_REFRESH_DAYS.
_soma_ensure_json() {
  [[ -f "$SOMA_JSON" ]] || { _soma_fetch; return; }
  zmodload -F zsh/stat b:zstat 2>/dev/null || return 0
  zmodload zsh/datetime 2>/dev/null || return 0
  local -a st
  zstat -A st +mtime "$SOMA_JSON" 2>/dev/null || return 0
  (( EPOCHSECONDS - st[1] > SOMA_REFRESH_DAYS * 86400 )) && _soma_fetch
  return 0
}

# Print the PID if a tracked mpg123 is alive; otherwise clean up and fail.
_soma_running_pid() {
  [[ -f "$SOMA_PID" ]] || return 1
  local pid; pid=$(<"$SOMA_PID")
  [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null && { print -r -- "$pid"; return 0; }
  rm -f "$SOMA_PID"
  return 1
}

_soma_stop_quiet() {
  local pid i
  pid=$(_soma_running_pid) || return 0
  kill "$pid" 2>/dev/null
  for i in {1..10}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  kill -9 "$pid" 2>/dev/null
  rm -f "$SOMA_PID"
}

_soma_play() {
  _soma_need mpg123 jq curl || return 1
  local id=$1
  if [[ -z $id ]]; then
    print -ru2 -- "soma: usage: soma play <station>   (try: soma list, or press Tab)"
    return 1
  fi
  _soma_ensure_json || return 1
  if ! jq -e --arg id "$id" '.channels[]|select(.id==$id)' "$SOMA_JSON" >/dev/null 2>&1; then
    print -ru2 -- "soma: unknown station '$id'  (run: soma list)"
    return 1
  fi
  local url title
  url=$(jq -r --arg id "$id" \
    '.channels[]|select(.id==$id)|.playlists|(map(select(.format=="mp3")) + .)|.[0].url' "$SOMA_JSON")
  if [[ -z $url || $url == null ]]; then
    print -ru2 -- "soma: no mp3 stream available for '$id' (mpg123 can't play AAC)"
    return 1
  fi
  _soma_stop_quiet
  mkdir -p "$SOMA_CACHE"
  : > "$SOMA_LOG"
  nohup mpg123 ${=SOMA_MPG123_OPTS} -@ "$url" >"$SOMA_LOG" 2>&1 </dev/null &!
  print -r -- "$!" > "$SOMA_PID"
  print -r -- "$id" > "$SOMA_CUR"
  title=$(jq -r --arg id "$id" '.channels[]|select(.id==$id)|.title' "$SOMA_JSON")
  print -r -- "▶ ${title:-$id}  (pid $!)"
}

_soma_stop() {
  if _soma_running_pid >/dev/null; then
    _soma_stop_quiet
    print -r -- "■ stopped"
  else
    print -r -- "soma: nothing playing"
  fi
}

# Extract the artist/title from the last ICY metadata line mpg123 logged.
_soma_track() {
  if ! _soma_running_pid >/dev/null; then
    print -r -- "soma: nothing playing"; return 1
  fi
  local line t
  [[ -f "$SOMA_LOG" ]] && line=$(grep -a "StreamTitle=" "$SOMA_LOG" 2>/dev/null | tail -1)
  if [[ -z $line ]]; then print -r -- "♪ buffering…"; return 0; fi
  t=${line#*StreamTitle=\'}
  if [[ $t == *\'\;StreamUrl=* ]]; then
    t=${t%\'\;StreamUrl=*}
  else
    t=${t%\'*}
  fi
  print -r -- "♪ ${t:-unknown}"
}

_soma_status() {
  local pid id title
  if pid=$(_soma_running_pid); then
    [[ -f "$SOMA_CUR" ]] && id=$(<"$SOMA_CUR")
    [[ -n $id && -f "$SOMA_JSON" ]] && \
      title=$(jq -r --arg id "$id" '.channels[]|select(.id==$id)|.title' "$SOMA_JSON" 2>/dev/null)
    print -r -- "▶ ${title:-$id} [${id:-?}]  (pid $pid)"
    _soma_track
  else
    print -r -- "■ not playing"
  fi
}

_soma_list() {
  _soma_need jq || return 1
  _soma_ensure_json || return 1
  jq -r '.channels[] | [.id, .title, .genre] | @tsv' "$SOMA_JSON" \
    | while IFS=$'\t' read -r id title genre; do
        printf '  %-18s %-28s %s\n' "$id" "$title" "$genre"
      done
}

_soma_usage() {
  print -r -- "soma — SomaFM player
  soma play <station>   start a station in the background (Tab to complete)
  soma stop             stop playback
  soma track            show the current track
  soma status           show what's playing
  soma list             list all stations
  soma update           refresh the station list"
}

soma() {
  emulate -L zsh
  _soma_paths
  local cmd=${1:-}
  (( $# )) && shift
  case $cmd in
    play)       _soma_play "$@" ;;
    stop)       _soma_stop ;;
    track)      _soma_track ;;
    status|"")  _soma_status ;;
    list|ls)    _soma_list ;;
    update|refresh) _soma_fetch && print -r -- "soma: station list updated" ;;
    help|-h|--help) _soma_usage ;;
    *) print -ru2 -- "soma: unknown command: $cmd"; _soma_usage; return 1 ;;
  esac
}
