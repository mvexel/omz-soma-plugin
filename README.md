# soma

A SomaFM player plugin for zsh and fish — works with plain zsh, oh-my-zsh, zinit,
antidote, fisher, or any plugin manager.
Play [SomaFM](https://somafm.com/)
(and stop) streams in the background with `mpg123`.
Has tab completion for every station and a current track command.
Survives terminal sessions.

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

## Install

### Zsh

Plain zsh — clone anywhere, then in `~/.zshrc`:

```zsh
fpath=(/path/to/omz-soma-plugin $fpath)   # before compinit (tab completion)
source /path/to/omz-soma-plugin/soma.plugin.zsh
```

Oh-my-zsh — clone into `$ZSH_CUSTOM/plugins/soma`
and add `soma` to `plugins=(...)`.
Other plugin managers: point them at the repo;
there is nothing framework-specific.

### Fish

Plain fish — clone anywhere, then in `~/.config/fish/config.fish`:

```fish
set -p fish_function_path /path/to/omz-soma-plugin/functions
set -p fish_complete_path /path/to/omz-soma-plugin/completions
```

With [Fisher](https://github.com/jorgebucaran/fisher):

```fish
fisher install /path/to/omz-soma-plugin
```

## Usage

| Command               | Description                                                       |
| --------------------- | ----------------------------------------------------------------- |
| `soma play <station>` | Start a station in the background (`<Tab>` completes station ids) |
| `soma stop`           | Stop playback                                                     |
| `soma track`          | Show the current track                                            |
| `soma love`           | Save the currently-playing track to your loved list               |
| `soma loved`          | Show your loved tracks                                            |
| `soma list`           | List all stations (`id`, title, genre)                            |
| `soma update`         | Refresh the cached station list                                   |

Playback is detached, so it keeps going after you close the terminal.
`soma stop` works from any shell.
Running `soma play` again switches stations.

`soma love` appends the currently playing track to your personal,
local loved-tracks list.
`soma loved` shows you the tracks you've loved.

## Configuration

Set these before the plugin loads to change the (sane) default behavior.

| Variable            | Default                                                   | Purpose                                                                             |
| ------------------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `SOMA_CACHE`        | `$XDG_CACHE_HOME/soma` (`~/.cache/soma`)                  | Where cache + state files live                                                      |
| `SOMA_CHANNELS_URL` | `https://somafm.com/channels.json`                        | Station list endpoint                                                               |
| `SOMA_REFRESH_DAYS` | `7`                                                       | Auto-refresh the station list after N days                                          |
| `SOMA_TIMEOUT`      | `30`                                                      | Seconds before `mpg123` gives up on a stalled stream and exits (`0` = wait forever) |
| `SOMA_MPG123_OPTS`  | _(empty)_                                                 | Extra args passed to `mpg123` (e.g. `-o dummy` for no audio, `-a <device>`)         |
| `SOMA_LOVED`        | `$XDG_DATA_HOME/soma/loved` (`~/.local/share/soma/loved`) | File holding your loved-tracks list (TSV)                                           |

State files under `$SOMA_CACHE`: `channels.json` (station cache), `soma.pid`
(running player),
`now.log` (mpg123 output, parsed for the current track), `current`
(active station id).

Loved tracks are stored separately at `$SOMA_LOVED`
(default `~/.local/share/soma/loved`),
one tab-separated `timestamp · id · title · track` row per love,
so they outlive a cache wipe.
