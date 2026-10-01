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
- The bot Runner runs for the far side of walls, vaults windows, and drops barricades on you.

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
| W A S D | Move |
| Mouse | Look around |
| E or Space | Drop a barricade, vault a window or barricade, break a barricade |
| Left click | Swing (Hunter only) |
| Esc | Pause menu (the match keeps going) |
| Enter | Rematch (host, after a match) |

## Rules in this prototype

- The Runner is blue and seen from behind (third person). The Hunter is red and sees through their own eyes (first person).
- The Hunter is a bit faster (4.6 m/s vs 4.0 m/s), so the Runner has to use walls, windows and barricades.
- Two hits take the Runner down: Healthy → Injured → Downed. Getting hit gives the Runner a short speed burst.
- A barricade dropped on the Hunter stuns them. The Hunter can break dropped barricades; the Runner can vault them.
- Both players can vault windows, but the Hunter is much slower at it.
- A round ends when the Runner is downed, or after 5 minutes.

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
| `scripts/hud.gd` | On-screen text and the pause menu |
| `scripts/net.gd` | Hosting and joining (Godot's built-in ENet networking) |
| `scripts/tuning.gd` | The list of tunable numbers |
