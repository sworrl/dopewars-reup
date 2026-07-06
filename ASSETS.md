# Asset status

Every image in the game is currently AI-generated. This file tracks each asset group, how it was
made, and whether it still needs a human-made replacement. Fonts are licensed typefaces, not AI.

**How the art was made:** Google Imagen 4 Ultra (`imagen-4.0-ultra-generate-001`), called from the
`drugwars-reup/tools/gen_*.py` scripts. Full-resolution outputs live in `assets/generated/`; the
downscaled versions the game ships are in `assets/sprites/`. The art direction is documentary and
anti-glorification: sealed evidence bags for product, worn gear, desaturated rust-belt tone. The
game does not depict or glamorize drug use.

| Asset group | Count | Source | Generator | Status |
|---|---|---|---|---|
| Class portraits | 10 | Imagen 4 Ultra | `gen_class_portraits.py` | AI-generated, wants real art |
| Drug icons, personal amount | 10 | Imagen 4 Ultra | `gen_item_icons.py` | AI-generated, wants real art |
| Drug icons, mid amount | 10 | Imagen 4 Ultra | `gen_item_tiers.py` | AI-generated, wants real art |
| Drug icons, bulk amount | 10 | Imagen 4 Ultra | `gen_item_tiers.py` | AI-generated, wants real art |
| Transport icons | 8 | Imagen 4 Ultra | `gen_transport_icons.py` | AI-generated, wants real art |
| Phone models | 6 | Imagen 4 Ultra | `gen_phone_art.py` | AI-generated, wants real art |
| App / launcher icon | 1 | Imagen 4 Ultra | one-off prompt | AI-generated, wants real art |
| Menu background | 1 | Imagen 4 Ultra | one-off prompt | AI-generated, wants real art |
| Loading / boot art | 1 | Imagen 4 Ultra | `gen_boot_art.py` | AI-generated, wants real art |
| Cosmetic catalog | 100 defined | none yet | pending | No art yet, needs to be made |
| Fonts (Big Shoulders Display, Plus Jakarta Sans) | 4 files | Google Fonts, SIL OFL | n/a | Licensed typefaces, not AI |

**Totals:** 57 AI-generated images in the shipping game, plus 100 cosmetic items defined in the
backend that have no art yet.

When a human-made asset replaces an AI one, change its row to "Human art by <name>" and record the
artist in the credits. Keep this table current as art lands.
