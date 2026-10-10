# Playing dawlings with friends (1.0 test build)

Thanks for trying it. This is an early build, so tell us what breaks, what confuses you and what
you enjoyed.

## Running it

- **Windows:** unzip, and run `dawlings.exe` in the `dawlings` folder. Windows may warn about an unknown publisher; choose
  "More info", then "Run anyway".
- **Linux:** unzip, then in the `dawlings` folder run `chmod +x dawlings.x86_64` and start it.

It opens on a demo song you can play, mix and record over, using its own built-in engine. No
other music software is needed. Headphones are best if you're going to record.

- **Moving around:** WASD walks. Right-drag looks. Click and drag the gear. Hover over anything
  to see what it does.
- **The session panel:** press M. That's where you host, join, choose your microphone and keys,
  and hear the shared mix.

## Playing together over the internet

One person **hosts** and everyone else **joins** them.

**The host:**

1. Press M, then choose **Host a session**.
2. Make your computer reachable, in either of these ways:
   - **Easiest, Tailscale:** everyone installs Tailscale (free) and joins the same tailnet. Give
     your friends your Tailscale address (100.x.y.z). Nothing else is needed.
   - **Or port forwarding:** on your router, forward **UDP 7332** (the session) and **UDP 7334**
     (the mix's audio) to your computer. Then give your friends your public IP address (search
     "what is my IP").
3. Tick **Ask for a code** if you want only people with the code to get in.

**Everyone joining:**

1. Press M, type the host's address in the address box, and press **Join**.
2. Turn on **Hear the mix**, unless you're in the same room as the host's speakers.

On the same home network you don't need any of the above: the host shows up in the panel by
itself.

## What to try

- Play the demo, loop the chorus (drag along the top band of the timeline), and turn up the
  faders.
- Record your keys or your microphone onto a track while someone else plays.
- Add a plugin from the rack, rename a track, drop and rename markers on the tape deck.
- Save the project (Ctrl+S). It's a `.dawproject` file, which other DAWs (Bitwig, Studio One,
  Cubase) can open.

## When something goes wrong

Tell us what you did just before. The log is at:

- **Windows:** `%APPDATA%\Godot\app_userdata\dawlings\logs\godot.log`
- **Linux:** `~/.local/share/godot/app_userdata/dawlings/logs/godot.log`
