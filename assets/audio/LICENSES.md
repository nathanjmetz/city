# Audio sources and licenses

| Files | Source | License |
| --- | --- | --- |
| `ui/*.ogg` | Made in code by `tools/audio/make_assets.py` ("Front Porch" style: wooden mallets and plucked guitar) | Our own work |
| `world/car_engine.ogg`, `world/transformer.ogg` | Made in code by `tools/audio/make_assets.py` | Our own work |
| `world/rail/*.ogg` (Nathan P5 horn, EMD 645 diesel, crossing bell) | Made in code by `tools/rail/rail_sounds.py` | Our own work |
| `world/birds_day.ogg` | [Birds singing in garden.ogg](https://commons.wikimedia.org/wiki/File:Birds_singing_in_garden.ogg) by ezwa | Public domain |
| `world/crickets_night.ogg` | [Pterophylla camellifolia singing.wav](https://commons.wikimedia.org/wiki/File:Pterophylla_camellifolia_singing.wav) by peterwchen (common true katydid, Naperville, Illinois) | CC BY 4.0 |
| `world/leaves.ogg` | [Rustling leaves (Gravity Sound).wav](https://commons.wikimedia.org/wiki/File:Rustling_leaves_(Gravity_Sound).wav) by Gravity Sound | CC BY 4.0 |
| `world/corn_field.ogg` | [Meadow (Gravity Sound).wav](https://commons.wikimedia.org/wiki/File:Meadow_(Gravity_Sound).wav) by Gravity Sound | CC BY 4.0 |
| `world/wind_high.ogg` | [Wind in forest (Gravity Sound).wav](https://commons.wikimedia.org/wiki/File:Wind_in_forest_(Gravity_Sound).wav) by Gravity Sound | CC BY 4.0 |
| `world/rooftop_hvac.ogg` | [Resident air-conditioned out door unit.ogg](https://commons.wikimedia.org/wiki/File:Resident_air-conditioned_out_door_unit.ogg) by Ranch9613 | CC0 |
| `world/industry_hum.ogg` | [WWS Graindryer.ogg](https://commons.wikimedia.org/wiki/File:WWS_Graindryer.ogg) by Work With Sounds / Linköping University | CC BY 4.0 |
| `world/traffic_far.ogg` | [Highway from bridge center.ogg](https://commons.wikimedia.org/wiki/File:Highway_from_bridge_center.ogg) by stephan | Public domain |

The recorded loops are cut, made seamless, turned to mono and levelled by
`tools/audio/field_recordings.py` (that is the only change made to them).
CC BY recordings are also credited in the game, under Credits in the pause
menu (`scripts/audio/sound_credits.gd`). Only public domain, CC0 and CC BY
sources are used: never share-alike or non-commercial.

Music is made separately by the project owner: `music/theme.ogg` (title screen and menus) and `music/gameplay/*.ogg` (in town) are by metzguy, made with Suno and converted to Ogg Vorbis.

## Sound picker options (`web/sfx/`)

The options in the pause menu's Sound picker are cut from two CC0 (public
domain) sources by `tools/audio/make_candidates.py`, and listed with their
source in `web/sfx/candidates.json`. They are served next to the browser build
and downloaded only when played. CC0 needs no credit; they are credited anyway.

- [Kenney](https://kenney.nl) audio packs: Interface Sounds, UI Audio, Impact Sounds, Casino Audio, RPG Audio, Music Jingles (CC0).
- [Versilian Community Sample Library](https://github.com/sgossner/VCSL) by Sam Gossner: glockenspiel, marimba, vibraphone, concert harp, hand chimes, tubular bells, wood block (CC0).
