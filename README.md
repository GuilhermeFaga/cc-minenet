# MineNet clean v5

MineNet is a CC:Tweaked mining turtle coordinator with a central server, turtle status UI, fuel/drop-off stations, collision reservations, logs, recall, and hard reset.

## Major v5 changes

- Predictive fuel safety: turtles estimate fuel needed to reach the refuel chest plus a safety margin before moving or continuing mining.
- Manual one-coal recovery: if a turtle is out of fuel, inserting enough fuel to reach the refuel station lets it resume and go refuel.
- Shared volume wall mining: configure a bottom-left-front block, mining direction, width, height, and depth. Turtles split the current wall into vertical column jobs and mine together on the same wall.
- Depth barrier: the server waits for all columns in the current wall layer before assigning the next wall layer.
- Existing logging, recall, hard reset, station locks, and live dashboard from v4 are retained.

## Install

Auto install:
```sh
wget https://raw.githubusercontent.com/GuilhermeFaga/cc-minenet/main/install.lua install
install
```

Central computer:

```sh
delete /minenet
copy disk/minenet /minenet
cd /minenet
server.lua
```

Turtle:

```sh
delete /minenet
copy disk/minenet /minenet
cd /minenet
turtle.lua
```

## Mining area setup

On the server, press `4`.

Set the bottom-left-front block of the volume. When you are facing the mining direction:

- width extends to the right across the wall
- height extends upward
- depth extends forward into the wall

For example, width `8`, height `3`, depth `64` means the turtles mine an 8x3 wall, then the next 8x3 wall one block deeper, until 64 layers are done.

## Fuel setup

Set fuel station with `3`. Enter the position where the turtle should stand, not the chest block. Then enter the heading the turtle should face to interact with the chest.

Turtles now keep enough fuel to reach the fuel chest plus `fuel_margin` before continuing work. Default margin is 120.

## Controls

- `1` base/home
- `2` drop-off station
- `3` fuel station
- `4` mining volume config
- `G` start/stop mining
- `P` pause/resume
- `R` recall all
- `H` hard reset; type RESET to confirm
- `V` map/list view
- `S` save
- `Q` quit

## Logs

Turtle logs are stored in:

```text
/minenet/logs/turtle_ID.log
```
