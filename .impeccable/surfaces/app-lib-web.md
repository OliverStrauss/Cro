---
version: 1
slug: "app-lib-web"
primary_target: "app/lib/web"
related_targets: ["app/lib/screens","app/lib/theme.dart","app/lib/widgets"]
---

## Direction contract

THESIS: Cro is not a chat app — it is a station log for messages that fly for days. This
overhaul refuses the rounded-bubble/messaging-app default (the category arrangement every
run of this product would ship, and the one currently making Cro read as generic) and
treats every screen as a logbook/console for tracking a live, real transit.

OWN-WORLD: Radio-log / QSL-card / station-logbook world, wearing the existing CroColors
roles rather than replacing them: Background & Surface = card stock, Ink = logbook type,
Waypoint blue & Deep waypoint = live-signal lines and station markers, Sky tint = pending-
state wash, Delivery amber = the hand-stamped CONFIRMED mark — a Restrained strategy, amber
confined to hairline/stamp moments, never a filled color field. One condensed/mono-leaning
face carries all data (coordinates, distances, timestamps, labels, badges, buttons) at a
single consistent scale everywhere; a plain humanist face carries prose. Components:
hairline-ruled ledger rows, a stamped card module per cro, dotted-outline pending state,
and state read redundantly in line form (solid/dashed/doubled) as well as color.

STORY: A user opens Cro to check the log — where their birds are, which stations (nests,
hubs) are active, whose contact just confirmed. Sending a cro files a new log entry with a
route and timestamp; arrival is a satisfying hand-stamped event, not a silent status flip.

FIRST VIEWPORT: The Map screen is the primary console — full-bleed map, grid-square
coordinate labels set in the mono data face at one consistent size (never ad hoc), nests as
station markers, each in-transit bird as a live dashed/solid line reading its own state, the
floating actions cluster restyled as a compact instrument panel anchored bottom-right that
never overlaps map content or another control.

FORM: Radio Log, candidate 4 of 7 on the grounded list (1 homing-pigeon racing logbook /
ring cards, 2 ornithology field-guide plates, 3 vintage nautical/aeronautical chart, 4 ham
radio QSL card — assigned, 5 natural history specimen card, 6 weather station observation
log, 7 topographic trail map); seed key b1d1a26c. Raised by: emission-line-rail (state also
reads by line form, never color alone), busytown cross-section (one consistent label scale
everywhere — no label outranks another, the direct fix for today's scattered button sizing),
iridescent cloud edge (accent color confined to hairline/edge marks, the text field stays
achromatic and calm).

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review,
the verdict, DESIGN.md, and every shipping raster carrying its provenance.
