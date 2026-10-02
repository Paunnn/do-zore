# Art sources

Source material for the painted kafana. Godot ignores this folder (`.gdignore`); the
game-ready layers in `client/assets/art` are cut from it by `tools/art/build_painted.py`.

| File | What it is | Made with |
|------|------------|-----------|
| `painted/kafana_original.png` | First text-to-image painting of the room | Z-Image Turbo (Apache-2.0) |
| `painted/kafana_tables.png` | The same room with a stray floor prop removed | FLUX.1 Kontext [dev] edit |
| `painted/kafana_empty.png` | The room with every table and chair removed | FLUX.1 Kontext [dev] edit |
| `painted/musician_motion.mp4` | 2.5 s image-to-video clip of the accordion player | Wan 2.2 I2V (Apache-2.0) |

All three models were run through Hugging Face Spaces. Check each model licence before a
commercial release; FLUX.1 Kontext [dev] ships under the FLUX.1 [dev] Non-Commercial License,
so confirm its terms for generated outputs (or regenerate those two edits with another model).

The vector sprites (guests, drinks, icons) in `client/assets/sprites` are generated from
code by `tools/art/build_sprites.py`; there is no separate source for them.

## How the painted layers are made

- The video frames and the table image are registered onto the empty room with SIFT
  features, so every layer lines up pixel for pixel in the 1080 px wide world.
- The musician's moving pixels (bellows, arms, head) become a feathered mask; the first
  frame is baked into the backdrop and all 41 frames go into `musician_sheet.webp`, which the
  game plays back and forth while a song is on.
- One table is cut out by differencing the furnished and empty rooms, then split into three
  layers (`table_back`, `table_front`, `table_rests`) so guests can sit between the chairs and
  the tablecloth.
- The floor below the painting is a seamless tile taken from the painted floor.
- `layout.json` records the musician rectangle, stage, table size and every lantern and bulb
  position for the glow effects.
