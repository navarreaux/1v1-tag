# 1v1 Tag

A standalone take on the fan-made 1v1 chase mode: one **Hunter** chases one **Runner**.
Each match is two rounds and the players swap roles after the first one. Whoever survives
longer as the Runner wins.

This is an early **prototype** with a bright, cartoony subway-yard look (rounded characters, toon shading and ink outlines) (a teen Runner in street clothes, a police-officer Hunter with a baton), no perks, no objectives. It exists
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

- The bot Hunter chases you, swings when close and vaults windows. At a knocked-over trash can it works out whether kicking it away or running around is quicker, and does that.
- The bot Runner loops windows and trash cans, fast vaults, and knocks trash cans over on you.

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
| Space | Knock over a trash can, vault a window, vault a knocked-over trash can (hold Shift to vault fast), kick a trash can away |
| F5 (vs bot) | Dev: stand every trash can back up and unblock every window |
| F6 (vs bot) | Dev: freeze or unfreeze the bot in place |
| Left click | Swing (Hunter). Tap for a short lunge, hold to lunge further |
| Esc | Pause menu (the match keeps going) |
| Enter | Rematch / play again |

## Rules in this prototype

The chase copies Dead by Daylight's mechanics as closely as we can (not its art, names or perks).

**Maps.** After you pick your role against the bot, pick a map. Online games use Rotten Fields.

**Rotten Fields** is laid out like Dead by Daylight's Rotten Fields: a grid of 16 m cells inside a stepped outer wall, 96 x 128 m at its widest (packed about as tightly as The Last Stop). Cells around the edge hold tiles at clock positions: wall pairs at 12 and 3, T walls, a bent wall at 4, the one long wall at 6 (it's very strong, so there's only one), and big train loops (a train car with a trash can at its end) at 1, 7 and 10. A shack sits in the very middle with a T wall above it and a trash can wall below. The other cells are sparse **filler**: shipping containers, street lamps and trash cans between two short containers. Every trash can stands in a gap between two solid things, so it can always be looped. Both players start at the **depot**, a very strong Runner building in the top-left corner: a corridor runs all the way around a solid block inside, with a trash can across one side, so it loops safely until the Hunter kicks that can away. The Runner starts inside and the Hunter about 22 m away. When the chase begins, the Runner gets a **3 second head start** before the Hunter can move.

**The Last Stop** is a compact 80 x 80 m abandoned roadside service station: a 5 x 5 grid of 16 m cells, plus one sticking out on the right. The **service station** fills the middle-top four cells: a fenced forecourt with entrances on the west and south, a pump island under a canopy, a shop with a trash can between it and the fence, and one window in the east fence. Strong long walls sit on opposite edges (B and V), short walls at D, N and T, a shack at F and a trash can loop at R. The rest is filler with weak trash cans, container scrap yards that break sight lines, low drainage curbs in the corners and open escape lanes. The Runner starts inside the station; the Hunter starts in the open lane to the west.

Both players can **slide along walls** at full speed: if you run into a wall at less than 45°, you keep your speed and glide along it instead of slowing down.

**Changing direction costs speed**, as in Dead by Daylight. Swing your movement keys from forward to back, or left to right, and you drop to 30% speed (40% for the Hunter), then build back up over about half a second. Anything up to a quarter turn is free: rolling from W through W+A to A (or snapping straight from W to A) keeps all your speed. Turning the camera is free. So spamming left and right is slow, and moving with intent is fast.

**Runner**
- Third person, with the camera behind and over the right shoulder so the Runner sits left of center, and an 87° horizontal field of view, like Dead by Daylight. Walks at 2.26 m/s, sprints at 4.0 m/s with Shift, crouches at 1.13 m/s.
- Two hits take the Runner down: Healthy → Injured → Downed. Each hit gives a short speed burst.
- **Window vaults** come in three speeds, as in Dead by Daylight. A **fast** vault (0.5 s) needs you to have been sprinting at the window, from straight on up to 55° off, for at least 0.5 s (about 2 m of run-up). Anything over 80% of sprint speed counts as sprinting. Sprinting without that gives a **medium** vault (0.9 s). Walking gives a **slow** one (1.5 s).
- There's no fixed cooldown between vaults, but every vault starts that 0.5 s count over.
- Going straight back over the window you just vaulted needs 50% longer (0.75 s) of sprinting at it to be fast.
- **Trash cans**: hurdle a knocked-over can fast (0.6 s) if you hold Shift while pressing Space, slow (2.2 s) if you don't.
- Fast and medium vaults are loud: the Hunter sees a yellow **!** where it happened, even through walls. Slow vaults are silent.
- Vault the same window 3 times and it gets **blocked** (red) for 30 seconds. If 30 seconds pass between two of those vaults, the count starts over.
- A standing **trash can** sits in the middle of a 3 m gap, with room to run past it on either side. Knock it over to block the gap: it falls and leans at 45° against the structure on the other side. Knocking it onto the Hunter **stuns** them (they stagger, so you can see it). It takes a moment: you stand still for 0.35 s, and you can't vault that can for 1 s after.
- Sprinting leaves orange **scratch marks** that only the Hunter sees. An injured Runner also leaves **blood**.
- A **heartbeat** plays when the Hunter is within 32 m and gets faster and louder as they come closer.

**Hunter**
- First person, 4.6 m/s (115% of the Runner's sprint). Casts a **red stain** on the ground in front of them that the Runner can see.
- **Lunge**: click to swing with a short lunge, or hold to lunge further. Hits within about 2.2 m.
- After a hit the Hunter **wipes** the blade (2.7 s, slowed). After a miss they **recover** (1.5 s, slowed).
- **Bloodlust**: after 15, 25 and 35 seconds of continuous chase the Hunter gets faster (+0.2, +0.4, +0.6 m/s). It resets on a hit, a stun, kicking a trash can away, or losing the Runner for 8 seconds.
- Vaults windows slowly (1.7 s). Can't vault trash cans; kicks them away for good instead (2.34 s, with a wind-up the Runner can see).

A round ends when the Runner is downed, or after 5 minutes.

All of these numbers live in `tuning.tres`. Double-click it in Godot's FileSystem panel to change them.

## How the code is laid out

| File | What it does |
| --- | --- |
| `scripts/main.gd` | Main menu (bot match, host, join) |
| `scripts/game.gd` | Rounds, hits, trash cans and who wins; the host decides these |
| `scripts/player.gd` | Movement, cameras, swinging and vaulting |
| `scripts/body_model.gd` | The cartoony people (outfits, hats, the Runner's backpack) and their walk, run, crouch, vault and downed animations |
| `scripts/arena.gd` | Builds the map: the grid of cells, the corner depot, tiles, filler |
| `scripts/barricade.gd` | One trash can (standing, knocked over, kicked away) |
| `scripts/bot.gd` | The computer opponent |
| `scripts/effects.gd` | Scratch marks, blood, noise alerts, heartbeat |
| `scripts/hud.gd` | On-screen text and the pause menu |
| `scripts/net.gd` | Hosting and joining (Godot's built-in ENet networking) |
| `scripts/tuning.gd` | The list of tunable numbers |
