# 1v1 Tag

A standalone take on the fan-made 1v1 chase mode: one **Hunter** chases one **Runner**.
Each match is two rounds and the players swap roles after the first one. Whoever survives
longer as the Runner wins.

This is an early **prototype**: grey boxes and capsules, no perks, no objectives. It exists
to find out whether the chase is fun.

## How to play it

1. Download **Godot 4.7** (the standard version, not .NET) from https://godotengine.org/download.
   It's a single program; no installer needed.
2. Download this project: on the GitHub page click the green **Code** button, then
   **Download ZIP**, and unzip it somewhere.
3. Open Godot. In the Project Manager click **Import**, pick the `project.godot` file in the
   folder you unzipped, then click **Import & Edit**.
4. Press **F5** (or the ▶ play button at the top right) to run the game.

### Play alone against a bot
Under **Play alone against a bot**, click **I'm the Runner** or **I'm the Hunter**. The computer
plays the other side. Each round shows your time; press **Enter** to play another round
(you keep the same role) or **Esc** for the menu.

- The bot Hunter chases you, swings when close, vaults windows and breaks barricades in its way.
- The bot Runner loops windows and barricades, fast vaults, and drops barricades on you.

### Play both sides on one PC
1. In Godot's top menu choose **Debug → Customize Run Instances...**
2. Tick **Enable Multiple Instances** and set the count to **2**, then close the window.
3. Press **F5**. Two game windows open.
4. In one window click **Host a game**. In the other, leave the address as `127.0.0.1` and click **Join**.
5. Click inside a window to control that player. Press **Esc** to free the mouse.

### Play with a friend
The host clicks **Host a game** and tells the friend the IP address shown on screen. The friend
types it in and clicks **Join**. On the same home network this works straight away. Over the
internet, the host has to forward **UDP port 7777** on their router for now (an easier way is planned).

## Controls

| Key | What it does |
| --- | --- |
| W A S D | Move (the Runner walks unless sprinting) |
| Shift (hold) | Sprint (Runner) |
| Ctrl or C (hold) | Crouch (Runner) |
| Mouse | Look around |
| Space or E | Drop a barricade, vault a window or barricade, break a barricade |
| Left click | Swing (Hunter). Tap for a short lunge, hold to lunge further |
| Esc | Pause menu (the match keeps going) |
| Enter | Rematch / play again |

## Rules in this prototype

The chase copies Dead by Daylight's mechanics as closely as we can (not its art, names or perks).

**Runner**
- Third person, with the camera over the right shoulder. Walks at 2.26 m/s, sprints at 4.0 m/s with Shift, crouches at 1.13 m/s.
- Two hits take the Runner down: Healthy → Injured → Downed. Each hit gives a short speed burst.
- **Vaults** come in three speeds. Sprinting straight at a window for a moment gives a **fast** vault. Sprinting without enough run-up or at an angle gives a **medium** one. Walking or standing gives a **slow** one.
- Fast vaults are loud: the Hunter sees a yellow **!** where it happened, even through walls.
- Vault the same window 3 times and it gets **blocked** (red) for 15 seconds.
- Drop a **barricade** to block a gap. Dropping it on the Hunter **stuns** them.
- Sprinting leaves orange **scratch marks** that only the Hunter sees. An injured Runner also leaves **blood**.
- A **heartbeat** plays when the Hunter is within 32 m and gets faster and louder as they come closer.

**Hunter**
- First person, 4.6 m/s (115% of the Runner's sprint). Casts a **red stain** on the ground in front of them that the Runner can see.
- **Lunge**: click to swing with a short lunge, or hold to lunge further. Hits within about 2.2 m.
- After a hit the Hunter **wipes** the blade (2.7 s, slowed). After a miss they **recover** (1.5 s, slowed).
- **Bloodlust**: after 15, 25 and 35 seconds of continuous chase the Hunter gets faster (+0.2, +0.4, +0.6 m/s). It resets on a hit, a stun, breaking a barricade, or losing the Runner for 8 seconds.
- Vaults windows slowly (1.7 s). Can't vault barricades; breaks them instead (2.6 s).

A round ends when the Runner is downed, or after 5 minutes.

All of these numbers live in `tuning.tres`. Double-click it in Godot's FileSystem panel to change them.

## How the code is laid out

| File | What it does |
| --- | --- |
| `scripts/main.gd` | Main menu (bot match, host, join) |
| `scripts/game.gd` | Rounds, hits, barricades and who wins; the host decides these |
| `scripts/player.gd` | Movement, cameras, swinging and vaulting |
| `scripts/arena.gd` | Builds the greybox map |
| `scripts/barricade.gd` | One barricade (up, down, broken) |
| `scripts/bot.gd` | The computer opponent |
| `scripts/effects.gd` | Scratch marks, blood, noise alerts, heartbeat |
| `scripts/hud.gd` | On-screen text and the pause menu |
| `scripts/net.gd` | Hosting and joining (Godot's built-in ENet networking) |
| `scripts/tuning.gd` | The list of tunable numbers |
