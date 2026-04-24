# MineNet clean v2 for CC:Tweaked / CraftOS

A clean rebuilt MineNet package for remote mining turtles.

## What is included

- Live central server dashboard on the main computer screen.
- Optional attached monitor status list.
- Turtle auto-registration with persistent ID and color.
- Rednet protocol with shared token field.
- GPS/position-aware turtle navigation.
- Server-side movement reservations to reduce turtle collisions.
- Branch mining job assignment from the server.
- Drop-off routing when inventory is full.
- Smart fuel handling:
  - Turtles first refuel from their own inventory.
  - Preferred fuel is coal, charcoal, coal blocks, lava buckets, and blaze rods.
  - Turtles predict whether they have enough fuel for a route plus margin.
  - If a fuel station is configured and reachable, turtles route there and suck fuel from the configured side.
  - If the turtle cannot refuel or reach the fuel station, it enters `out_of_fuel` and waits for the player to insert coal/fuel.
- Status alerts for `out_of_fuel`, `fuel_station_empty`, and `inventory_full`.
- Simple live map data from turtle movement/tunnel updates.
- Terminal map/list toggle with Y-layer controls.

## Files

```text
/minenet/
  server.lua      central computer manager
  turtle.lua      turtle worker client
  protocol.lua    rednet message helpers
  storage.lua     persistent table storage
  config.lua      default config and loader
  util.lua        shared helpers
  nav.lua         turtle movement/GPS/reservations
  fuel.lua        smart fuel logic
```

## Clean install on central computer

Copy the `minenet` folder to a disk, place the disk in a disk drive, then run:

```lua
delete /minenet
copy disk/minenet /minenet
cd /minenet
server.lua
```

Optional installer:

```lua
copy disk/installers/install_server.lua install_server.lua
install_server.lua
cd /minenet
server.lua
```

## Clean install on each turtle

```lua
delete /minenet
copy disk/minenet /minenet
cd /minenet
turtle.lua
```

On first run the turtle asks for its heading:

```text
0 = north / -Z
1 = east  / +X
2 = south / +Z
3 = west  / -X
```

## Server controls

The server shows the live dashboard directly on the terminal.

```text
1  Set base/home position
2  Set drop-off stand position and chest side
3  Set fuel station stand position and chest side
4  Set mining start, heading, branch length, spacing, and tunnel height
5  Show add-turtle instructions
G  Start/stop automatic mining
P  Pause/resume turtles
R  Recall turtles to drop-off/base
V  Toggle status list/map view
[  Move map Y-layer down
]  Move map Y-layer up
S  Save data
Q  Quit server
```

## Important station setup

For both drop-off and fuel station, configure the position where the turtle should stand, not the chest block itself.

Example fuel station:

- Turtle stand position: `100,64,100`
- Heading: `1` if the turtle must face east toward the chest
- Side: `front` unless the fuel chest is above or below the turtle

## Fuel behavior

The turtle checks fuel before routes and before every move.

When low:

1. It tries to refuel from inventory.
2. If still low and fuel station is configured/reachable, it routes to fuel station.
3. If the fuel chest is empty, it reports `fuel_station_empty`.
4. If it cannot move safely, it reports `out_of_fuel` and waits until the player inserts fuel.

The server dashboard shows fuel amount, fuel item count, inventory percent, position, job, and alert.

## Notes

- A wireless modem is required on the server and turtles.
- GPS must be available for reliable positioning.
- Rednet is not secure by itself. Change the token in `/minenet/data/config.tbl` once the system is installed if you play on a shared server.
- This is still intentionally conservative: turtles dig simple branch tunnels and use a Manhattan route planner. The server collects map data for future path optimization.
