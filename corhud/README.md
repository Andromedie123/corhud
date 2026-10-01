# CorHUD

An Ashita v4 ImGui addon for Corsair: how many Quick Draw cards you're
carrying, and what your own Phantom Rolls and Wild Card actually landed at, in three
small always-on-top windows instead of scrolling chat text.

## Installation

Place the `corhud` folder into your Ashita `addons` directory, then in game:

```
/addon load corhud
```

Add that line to your `default.txt` (or job-specific script) to load it
automatically.

## What it shows

### Cards window
Live counts of every card Quick Draw can consume - the eight elemental
cards. Loose cards are read from the inventory proper only, since that
is the only place Quick Draw can consume them from; card cases count
from the inventory and the satchel, the way ninhud tracks tools and
toolbags. Cards or cases parked in the safe, storage or locker are
ignored. Each row shows the card icon, the loose card count, and then
the count of the matching quiver-style card case (e.g. `Fire Card
Case`) in parentheses with the case icon. Counts use ninhud's colour
coding: yellow when running low (12 or fewer loose cards, 3 or fewer
cases), red when you're out.

The footer shows the total card count and the total number of cases.
Either line can be hidden separately (see Settings).

### Rolls window
Whenever you land one of your own Phantom Rolls, an entry appears with:
- who the roll is on - `You` for rolls you cast on yourself, the member's
  name for rolls on party members
- the roll name, the number you rolled (or **BUST!** if you went over 11),
  and the roll's `L:lucky`/`U:unlucky` call-out pair, colour-coded to match
  the LUCKY/UNLUCKY tags
- the actual bonus that roll gives, using the selected Phantom Roll+ table
- whether the result was **LUCKY!**, **UNLUCKY!**, or neither
- a countdown clock showing the time left on the roll

When several members hold the same roll, their rows merge into one
(tTimers-style): `Evoker's Roll [2]` with the roll info once and the
soonest-expiring member's countdown - just the `[N]` count, no member
names. Busts always keep their own row. Death clears a member's rolls
with them (the entity-update and 0x029 death channels tTimers watches),
so a dead member stops counting toward the `[N]`.

Each member keeps their own entries, so the same roll up on two members
at once merges into one counted row (see above), and a member's row
clears the moment their roll fades - the addon diffs the party buff
snapshots (0x076) and your own effect snapshots (0x063) against each
roll's status icon, matches
the "loses the effect of X Roll" chat lines per name, and falls back to
the detected duration plus a short grace. A successful Double-Up updates
the roll's number and bonus in place without resetting the countdown
(Double-Up keeps the roll's original expiry). The game caps any one
member at two rolls; a third roll on them evicts their oldest, and the
tracker mirrors that. A bust cancels the roll on the member it landed on
and tracks the Bust debuff on you, clearing when Fold removes it or the
game reports it wearing off.

The **Track rolls** setting (tTimers-style dropdown) picks whose rolls
the window follows: **Self Only** (the default - your own rolls, with
the Phantom Roll+ bonus tables), **Party** (any Corsair in your party),
or **Alliance** (any alliance member). Rolls another Corsair cast are
attributed to their recipient the same way, but their bonus falls back
to the base tables and their countdown uses the base 5:00 - their
Phantom Roll+ gear and Winning Streak merits can't be read from here.
Alliance members' fades rely on the countdown/grace timeout since their
buff snapshots aren't sent to you.

Your Winning Streak merit level is auto-detected so the countdown uses
the real roll duration - 5:00 base plus 0:20 per merit. It is picked up
from the server's own merit menu packet (0x08C) whenever you open the
Merit Points menu, and also read from the client's merit points list in
memory at load, so the countdown is right from your first roll; the
roll-duration measurement below cross-checks it and keeps it correct.
The detected value is saved per character.

Fold and Snake Eye recast timers can also sit at the top of the window
(`Fold: 12:30  Snake Eye: Ready`). Their recast is merit-dependent
(15:00 base, reduced per merit) and is read from the client's own
ability recast timers - the same source tTimers uses - so merit-reduced
recasts show automatically with no configuration. The window stays
visible whenever Fold or Snake Eye are merited (detected from your own
ability use and the merit menu packet), so the timers stay on screen
even with no rolls active. Turn them off with the
**Show Fold/Snake Eye timers** setting.

An entry clears itself the moment the game reports that roll's effect
ended - from the party/self effect snapshots or the chat message, so a
fade never waits for the countdown to reach zero. If every channel is
missed (e.g. the member is out of range, or a disconnect), the entry
also auto-clears just past the auto-detected roll duration, so nothing
gets stuck.

Using Fold removes the oldest tracked bust first, matching HorizonXI's
Fold behavior. The tracker also recognizes Fold's action packet and chat
message.

Click **Show Reference** to expand a static table of every roll's lucky
number, unlucky number, the Horizon value at a Double-Up 11, and what it
buffs - handy for picking a roll without alt-tabbing to a wiki.

### Wild Card popup
When you use Wild Card, a popup briefly shows the 1-6 result, corresponding
effect, and two-hour recast timer. It stays hidden until the next Wild Card
result is received.

## Commands

| Command | Effect |
|---|---|
| `/corhud` or `/ch` | Toggle the settings window |
| `/corhud cards` | Toggle the Cards window on/off |
| `/corhud rolls` | Toggle the Rolls window on/off |
| `/corhud wildcard` | Toggle the Wild Card window on/off |
| `/corhud clear` | Forget tracked rolls, the Wild Card result, and the detected merits |
| `/corhud merits` | Debug: print the client's merit list from memory |
| `/corhud rollpackets` | Debug: dump the recent roll action packets (hex + parsed target blocks) |

## Settings

Opened with `/corhud`. Lets you show/hide each window, toggle the
Fold/Snake Eye recast timers, hide the card total or card case lines,
set each window's background opacity, pick a text style (none / outline
/ drop shadow) so the HUD stays readable even at 0.00 opacity, and
scale the HUD text. The windows can also just be dragged to reposition;
each position is remembered per character.

Phantom Roll+ is detected automatically from equipped HorizonXI gear:
**Luzaf's Fang** (ear) and **Corsair's Culottes** (legs) each provide
`Phantom Roll +1`, and stack together for the current `Phantom Roll +2`
cap.

## Notes

- Roll tracking follows your own rolls by default; the **Track rolls**
  setting extends it to every Corsair in the party or alliance (the same
  three-way choice tTimers' buff tracker makes). Each entry is attributed
  to the party member who received the roll - from the action packet's
  applied-message target block, not the caster's dice block - and clears
  when that member's roll fades (per the party buff snapshots, the same
  packets the timers addon watches). Rolls other Corsairs cast show the
  base bonus tables and a 5:00 countdown, since their Phantom Roll+ gear
  and Winning Streak merits can't be read.
- Winning Streak comes from the server's merit menu packet (0x08C)
  whenever the Merit Points menu is opened, and is also read from the
  client's merit points list at load (the same memory walk the Horizon
  timers fork does, offset 0x28A44 - retail tTimers' 0x2CFF4 points
  elsewhere on this client build), so the countdown is right from the
  first roll. As a cross-check it also watches the status effect
  packets (0x063) for *your own* roll effects appearing and expiring,
  and only accepts a measured duration that lands exactly on the
  5:00 + 0:20-per-merit ladder - a real measurement always overrides
  the merit-list read. Rolls that end early (Fold, bust, overwrite,
  zoning) never count, and neither do rolls another Corsair lands on
  you.
- Card tracking looks items up by name, not item id, so it isn't tied to
  any one server's item database.
- Phantom Roll+ tables use the HorizonXI main-job values published on the
  linked roll pages. Only verified values are included; missing `+2`
  values remain pending future wiki updates or in-game measurement
  (Gallant's Roll +2 was measured in-game).
- Wild Card's six outcomes follow Horizon's update patch notes; Corsair
  roll reference values follow the HorizonXI wiki pages:
  https://horizonffxi.wiki/Corsair
  https://horizonffxi.wiki/Hunter's_Roll
  https://horizonffxi.wiki/Chaos_Roll
