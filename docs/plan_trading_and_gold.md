# Player trading and uses for gold (plan, jj 2026-11-02)

## Trading between players

**Where:** two players in the same game (co-op, the camp, a raid's antechamber before the gates rise). Click a
player and choose Trade, or `/trade`. Never during a raid once the gates are up.

**The window:** the inventory's iron and gold frame, like the stash and the trade window. Two halves: "You offer"
and "<name> offers", each 4 × 3 of the bag's sockets plus a gold field on a bronze plate. Drag or click items from
your bag in. Both press **Accept**; any change on either side clears both accepts. Then a 3-second **Confirm**
countdown, cancelled by any change. Tooltips show the other side's items in full, the same as your own.

**No duplicates (the trade goes through the server):**
1. On Confirm, each side's offered items and gold go to Nakama as an escrow record. A server RPC writes it, never
   the client, as with the admin role. Each client takes them out of its bag and saves at once (each item already
   has a uid, see SharedStash).
2. The server swaps the two escrows in one step and marks the trade done.
3. Each client pulls what it received, adds it, saves, and acknowledges. A client that crashed pulls it at the next
   start, before any character can be played, the same way the shared stash reconciles.

So an item is always in exactly one place: a bag, the escrow or the other bag. A crash at any point resolves on
the next start. As with saves, a modified game can still lie about what it puts in. Closing that fully needs
server-held inventories.

**Tax:** 5% of the gold in a trade (a gold sink; see below).

## Uses for gold

These earn their place by being useful, not chores. No durability or repair bills.

| # | Use | Cost | Why it's good |
|---|---|---|---|
| 1 | **Raid insurance**: before the gates rise, pay to insure one worn item. If you die it comes home to your stash instead of dropping. | 25% of its value, rising with item level | Takes the edge off losing a favourite, keeps the raid's risk, and gold matters to raiders. The insured item doesn't drop, so no copy appears. |
| 2 | **Reforge with gold**: the bonfire's reforge, gold as well as a Sloth material | Item level × 150 | Materials stay rare; gold gives a steady path to better rolls. |
| 3 | **More stash tabs**: tabs 6–10 | 50k, 100k, 200k, 400k, 800k | A long-term goal that doesn't add power. |
| 4 | **Talent respec**: first one free, then a fee | Level × 200, resets weekly | Experimenting stays cheap; flip-flopping costs a little. |
| 5 | **Dyes**: the archer's and plague doctor's colour schemes, and later every class's | 5k–50k each | Cosmetic, so it never unbalances PvP. |
| 6 | **Gambling** (Tarrow's table): unchanged, and more items to roll | as now | Already there. |
| 7 | **Item upgrade**: normal → magic → rare at the smith (rolls new affixes; can't touch uniques) | Item level × 300 → × 1,200 | Makes a base you like worth investing in. |
| 8 | **Trade tax** | 5% | Keeps gold scarce and stops endless flipping. |
| 9 | **Boats** | as now (1M / 10M) | Already there. |

Recommended first: **1 (insurance)** and **2 (reforge with gold)**. They touch the raid loop directly and are small
to build. Then 3, 4 and 5.
