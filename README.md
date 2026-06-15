# soma

Play [SomaFM](https://somafm.com/) (and stop) streams in the background with `mpg123`. 
Has tab completion for every station and a current track command. Survives terminal sessions.

```console
$ soma play groovesalad
▶ Groove Salad  (pid 104180)
$ soma track
♪ Sounds From The Ground - Anniesland
$ soma stop
■ stopped
```

## Requirements

- [`mpg123`](https://www.mpg123.de/) — playback
- `curl` and [`jq`](https://jqlang.github.io/jq/) — fetch/parse the station list

> Playback uses each station's **MP3** stream (mpg123 decodes MP3, not AAC).
> All SomaFM channels offer an MP3 stream, so every station is playable.

## Usage

| Command | Description |
|---|---|
| `soma play <station>` | Start a station in the background (`<Tab>` completes station ids) |
| `soma stop` | Stop playback |
| `soma track` | Show the current track |
| `soma status` | Show what's playing (also the bare `soma`) |
| `soma list` | List all stations (`id`, title, genre) |
| `soma update` | Refresh the cached station list |

Playback is detached (`nohup`), so it keeps going after you close the terminal,
and `soma stop` works from any shell. Running `soma play` again switches stations.

The track shown by `soma track` is parsed from the ICY metadata `mpg123` emits,
so it reflects exactly what *you* are hearing.

## Configuration

Set these before the plugin loads to change the (sane) default behavior.

| Variable | Default | Purpose |
|---|---|---|
| `SOMA_CACHE` | `$XDG_CACHE_HOME/soma` (`~/.cache/soma`) | Where cache + state files live |
| `SOMA_CHANNELS_URL` | `https://somafm.com/channels.json` | Station list endpoint |
| `SOMA_REFRESH_DAYS` | `7` | Auto-refresh the station list after N days |
| `SOMA_MPG123_OPTS` | _(empty)_ | Extra args passed to `mpg123` (e.g. `-o dummy` for no audio, `-a <device>`) |

State files under `$SOMA_CACHE`: `channels.json` (station cache), `soma.pid`
(running player), `now.log` (mpg123 output, parsed for the current track),
`current` (active station id).
