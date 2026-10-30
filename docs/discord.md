# Sending to Discord

dawlings can play what you choose -- the master out, any tracks, the inputs you are monitoring,
the room's own sounds -- into whatever Discord voice channel you are in. A bot of your own does
it: it follows you into a voice channel, plays there as a member of its own, and leaves when you
do. Your microphone is not touched, and everyone in the channel can turn the bot up or down
for themselves.

The controls are in the session panel (M), under DISCORD: the switch, a tick for each source, a
level and a meter, and a line saying what the bot is doing.

It needs the built-in engine (`-- --built-in`), Linux with PipeWire or PulseAudio, Node.js, and
the source checkout.

## Setting it up, once

1. **Make the bot.** Go to <https://discord.com/developers/applications>, choose **New
   Application** and give it a name, for example "dawlings". Open **Bot**, choose **Reset Token**
   and copy the token. Nothing under "Privileged Gateway Intents" is needed.
2. **Invite it to your server.** Open **OAuth2 → URL Generator**, tick the `bot` scope, then the
   **Connect** and **Speak** permissions (under Voice). Open the URL it makes, and pick your server.
3. **Find your own user id.** In Discord, open Settings → Advanced and turn on **Developer
   Mode**. Then right-click your own name and choose **Copy User ID**.
4. **Tell dawlings.** Make `~/.config/dawlings/discord.json`:

   ```json
   { "token": "the bot token", "user_id": "your user id" }
   ```

   and run `chmod 600 ~/.config/dawlings/discord.json`. The token is a password for the bot: it
   never goes in the repo. `DAWLINGS_DISCORD_TOKEN` and `DAWLINGS_DISCORD_USER` in the
   environment work too.
5. **Install its packages**, once per checkout: `cd tools/discord_bridge && npm install`.

## Using it

Join a voice channel, open the session panel (M) and turn on **Send to my Discord voice
channel**. The bot comes into your channel within a few seconds. Tick what it plays:

- **Master out** -- the whole mix, after the master fader.
- **Whatever I am monitoring** -- every track whose input you are monitoring, live, even when
  nothing is recording.
- **The room** -- the gear's clicks, knocks and castors.
- **Track N** -- that track alone, after its fader and mute.

Ticked sources are added together. If you tick the master and a track, that track is heard
twice. **Level** sets the send for the whole channel.

The sound goes into a sink of its own, `dawlings to Discord`, which nobody on this machine
hears. You can also route anything else into it with a patchbay (pavucontrol, qpwgraph).

## How it works

`core/audio/discord_feed.gd` taps each chosen bus at the end of its chain. It applies the bus's
fader and mute itself, mixes the taps on a thread, and plays the result with `pacat` into a
null sink (`dawlings_discord`). `tools/discord_bridge/bridge.mjs` is the bot. It uses discord.js
and @discordjs/voice, with DAVE end-to-end encryption. It reads the sink's monitor with `parec`,
follows its owner's voice state across every server it is in, and exits when the game closes its
stdin. It reports one JSON line per change on stdout, which the panel shows.
