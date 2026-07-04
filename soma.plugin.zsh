# soma — a tiny SomaFM player for zsh / oh-my-zsh
#
#   soma play <station>   start a station in the background (Tab-completes)
#   soma stop             stop playback
#   soma track            show the current track
#   soma love             save the current track to your loved list
#   soma loved            show your loved tracks
#   soma list             list all stations
#   soma update           refresh the cached station list
#
# Config (override before the plugin loads, or in ~/.zshrc):
#   SOMA_CACHE          where state/cache live (default: $XDG_CACHE_HOME/soma)
#   SOMA_CHANNELS_URL   station list endpoint
#   SOMA_REFRESH_DAYS   auto-refresh the station list after N days (default 7)
#   SOMA_MPG123_OPTS    extra args for mpg123 (e.g. "-o dummy" for no audio)
#   SOMA_TIMEOUT        seconds before mpg123 gives up on a stalled stream (default 30; 0 = forever)
#   SOMA_LOVED          file for your loved-tracks list (default: $XDG_DATA_HOME/soma/loved)

: ${SOMA_CACHE:=${XDG_CACHE_HOME:-$HOME/.cache}/soma}
: ${SOMA_CHANNELS_URL:=https://somafm.com/channels.json}
: ${SOMA_REFRESH_DAYS:=7}
: ${SOMA_MPG123_OPTS:=}
: ${SOMA_TIMEOUT:=30}
: ${SOMA_LOVED:=${XDG_DATA_HOME:-$HOME/.local/share}/soma/loved}

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
  if curl -fsSL -A "soma-zsh-plugin (https://codeberg.org/mvexel/omz-soma-plugin)" \
      "$SOMA_CHANNELS_URL" -o "$SOMA_JSON.tmp"; then
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

# True if $1 is a live process actually running mpg123. Guards against a stale
# PID file (after a reboot or a sleep/wake that killed the stream) whose number
# now belongs to nothing, or to some unrelated process that reused it.
_soma_is_mpg123() {
  local pid=$1 comm
  [[ -n $pid ]] || return 1
  if [[ -r /proc/$pid/comm ]]; then
    comm=$(<"/proc/$pid/comm")
  else
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || return 1
  fi
  [[ ${comm:t} == mpg123 ]]
}

# Print the PID if our tracked mpg123 is alive; otherwise clean up state and fail.
_soma_running_pid() {
  [[ -f "$SOMA_PID" ]] || return 1
  local pid; pid=$(<"$SOMA_PID")
  if _soma_is_mpg123 "$pid"; then
    print -r -- "$pid"
    return 0
  fi
  rm -f "$SOMA_PID" "$SOMA_CUR"
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
  nohup mpg123 --timeout "$SOMA_TIMEOUT" ${=SOMA_MPG123_OPTS} -@ "$url" >"$SOMA_LOG" 2>&1 </dev/null &!
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
    print -ru2 -- "soma: nothing playing"
  fi
}

# Parse the artist/title from the last ICY StreamTitle mpg123 logged.
# Prints the track string; fails with no output if none is available yet.
_soma_current_track() {
  local line t
  [[ -f "$SOMA_LOG" ]] || return 1
  line=$(grep -a "StreamTitle=" "$SOMA_LOG" 2>/dev/null | tail -1)
  [[ -n $line ]] || return 1
  t=${line#*StreamTitle=\'}
  if [[ $t == *\'\;StreamUrl=* ]]; then
    t=${t%\'\;StreamUrl=*}
  else
    t=${t%\'*}
  fi
  [[ -n $t ]] || return 1
  print -r -- "$t"
}

_soma_track() {
  if ! _soma_running_pid >/dev/null; then
    print -ru2 -- "soma: nothing playing"; return 1
  fi
  local t
  t=$(_soma_current_track) || { print -r -- "♪ buffering…"; return 0; }
  print -r -- "♪ $t"
}

# Append the currently-playing track to the loved list as a ts/id/title/track TSV row.
_soma_love() {
  if ! _soma_running_pid >/dev/null; then
    print -ru2 -- "soma: nothing playing"; return 1
  fi
  local id title track
  track=$(_soma_current_track) || {
    print -ru2 -- "soma: no track info yet (still buffering?)"; return 1
  }
  [[ -f "$SOMA_CUR" ]] && id=$(<"$SOMA_CUR")
  [[ -n $id && -f "$SOMA_JSON" ]] && \
    title=$(jq -r --arg id "$id" '.channels[]|select(.id==$id)|.title' "$SOMA_JSON" 2>/dev/null)
  : ${title:=$id}
  local entry="$id"$'\t'"$title"$'\t'"$track"
  if [[ -f "$SOMA_LOVED" ]]; then
    local last; last=$(tail -1 "$SOMA_LOVED" 2>/dev/null)
    if [[ ${last#*$'\t'} == "$entry" ]]; then
      print -r -- "♥ already loved: $track"; return 0
    fi
  fi
  local ts
  zmodload zsh/datetime 2>/dev/null && ts=$(strftime '%F %T' $EPOCHSECONDS) || ts=$(date '+%F %T')
  mkdir -p "${SOMA_LOVED:h}"
  print -r -- "$ts"$'\t'"$entry" >> "$SOMA_LOVED"
  print -r -- "♥ loved: $track  (${title})"
}

# Show the loved-tracks list, oldest first.
_soma_loved() {
  if [[ ! -s "$SOMA_LOVED" ]]; then
    print -r -- "soma: no loved tracks yet  (play something and run: soma love)"
    return 0
  fi
  local ts id title track
  while IFS=$'\t' read -r ts id title track; do
    printf '  %s  ♥ %s  [%s]\n' "$ts" "$track" "${title:-$id}"
  done < "$SOMA_LOVED"
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
  soma love             save the current track to your loved list
  soma loved            show your loved tracks
  soma list             list all stations
  soma update           refresh the station list

  If you enjoy listening to SomaFM, please consider a donation. Any amount helps!"
}

soma() {
  emulate -L zsh
  # local here + dynamic scoping: visible to every helper, gone when soma returns
  local SOMA_JSON SOMA_PID SOMA_LOG SOMA_CUR
  _soma_paths
  local cmd=${1:-}
  (( $# )) && shift
  case $cmd in
    play)       _soma_play "$@" ;;
    stop)       _soma_stop ;;
    track)      _soma_track ;;
    love)       _soma_love ;;
    loved)      _soma_loved ;;
    list|ls)    _soma_list ;;
    update|refresh) _soma_fetch && print -r -- "soma: station list updated" ;;
    ""|help|-h|--help) _soma_usage ;;
    *) print -ru2 -- "soma: unknown command: $cmd"; _soma_usage; return 1 ;;
  esac
}
