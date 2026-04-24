# MineNet - CC:Tweaked remote mining turtle manager

MineNet is an MVP remote mining system for CC:Tweaked with:

- Central server computer
- Turtle auto-registration over Rednet
- GPS-based position reporting
- Turtle colors and IDs
- Status heartbeat tracking
- Branch mining job queue
- Drop-off and fuel point configuration
- Basic collision avoidance through movement reservations
- Shared map updates from turtle inspections
- Optional attached monitor status view

## Install

Copy the `minenet` folder to the root of each computer/turtle.

On the central computer:

```lua
shell.run("/minenet/server.lua")
```

On each mining turtle:

```lua
shell.run("/minenet/turtle.lua")
```

For autostart, create `/startup.lua`:

```lua
shell.run("/minenet/server.lua") -- server
```

or:

```lua
shell.run("/minenet/turtle.lua") -- turtle
```

## Required setup

1. Place working GPS hosts in your world.
2. Give server and turtles wireless modems.
3. Start the server first.
4. In the server UI, set:
   - drop-off point
   - fuel point
   - mining area min/max
5. Generate branch jobs.
6. Start turtles.

## Security

Rednet is not secure. Change the default token in `/minenet/data/config.json` on the server before adding turtles.

## Notes

This is a first working foundation, not the final optimized swarm miner. The next improvements should be A* routing, better heading detection/calibration, chunk-safe scheduling, richer map monitor drawing, and a proper installer that can fetch files over HTTP/Pastebin.
