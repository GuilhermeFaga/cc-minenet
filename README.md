# MineNet CC:Tweaked MVP fixed build

This package uses a flat `/minenet` module layout and `require("protocol")`, so it works when files are installed directly under `/minenet`.

## Disk layout

Copy this to a ComputerCraft disk:

```
minenet/
  server.lua
  turtle.lua
  protocol.lua
  storage.lua
  config.lua
  util.lua
  nav.lua
installers/
  install_server.lua
  install_turtle.lua
```

## Install central computer

```
copy disk/minenet /minenet
cd /minenet
server.lua
```

Or run:

```
disk/installers/install_server.lua
```

## Install turtle

```
copy disk/minenet /minenet
cd /minenet
turtle.lua
```

Or run:

```
disk/installers/install_turtle.lua
```

## Requirements

- Wireless modem on server and turtles.
- GPS network available for turtles.
- Mining turtle for mining actions.
- Optional monitor attached to the server.

## Setup

On the server, use the menu to set:

1. Base point
2. Dropoff point
3. Fuel point
4. Mining start point and heading
5. Branch length

Then start turtles. They auto-register and receive branch jobs.

## Notes

The shared token defaults to `change-me` in `/minenet/data/config.json`. Change it on the server before deploying many turtles.
