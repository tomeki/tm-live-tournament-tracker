# Live Tournament Tracker

An [Openplanet](https://openplanet.dev) plugin for Trackmania that reports your Time Attack results and live race progress to a tournament server ([Genesis Tournament](https://genesis-tournament.tbrissonnet.ovh) by default).

## Features

- One-time pairing with your tournament account (a short pairing code, no password).
- Automatic submission of finish times, with checkpoint splits and respawn count.
- Live race progress (checkpoint count and current time) so the tournament page can follow the race as it happens.
- Attempt counting and your personal best on the current map.

## Installation

1. Install the plugin from the Openplanet plugin manager (or drop the `.op` file into `OpenplanetNext/Plugins/`).
2. The dependency [MLFeed: Race Data](https://openplanet.dev/plugin/mlfeedracedata) is required.

## Usage

1. On the tournament website, open your profile and click **Lier mon compte Trackmania** ("Link my Trackmania account") to get a pairing code.
2. In game, open **Openplanet > Settings > Live Tournament Tracker**, check the **Server address** and paste the code into **Pairing code**.
3. Play in Time Attack: your times are sent automatically. The status window is under **Openplanet > Plugins > Live Tournament Tracker**.

## Data sent

Nothing is sent before pairing. Once paired, the plugin sends to the configured server only:

- at pairing: your Ubisoft account ID and display name;
- the map UID and name;
- finish times, checkpoint splits and respawn count;
- live race progress (checkpoint count and current time) and a signal when a new attempt starts;
- your personal best on the current map.

The pairing token is stored locally in the plugin settings and is never displayed.

## Disclosure

Parts of this plugin were written with the help of an AI assistant (Claude), then reviewed and tested in game by the author.

## License

[MIT](LICENSE)
