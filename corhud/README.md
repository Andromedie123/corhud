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
- the roll name, the number you rolled (or **BUST!** if you went over 11),
  and the roll's `L:lucky`/`U:unlucky` call-out pair, colour-coded to match
  the LUCKY/UNLUCKY tags
- the actual bonus that roll gives, using the selected Phantom Roll+ table
- whether the result was **LUCKY!**, **UNLUCKY!**, or neither
- a countdown clock showing the time left on the roll

Busts stay tracked too - the bust debuff on you lasts 5 minutes, and its
entry clears the moment FFXI reports the bust wearing off. Your rolls
are tracked up to the number you can genuinely hold at once - five at
the base duration, up to seven with 5/5 Winning Streak - so rolls you
keep up on different groups of players while rotating parties all stay
visible.

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

An entry clears itself the moment FFXI reports you've lost that roll's
effect. If that message is ever missed (e.g. a disconnect), it also
auto-clears just past the auto-detected roll duration, so nothing gets
stuck.

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

- Roll tracking only follows rolls **you** cast, not rolls other
  Corsairs in your party land on you.
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
