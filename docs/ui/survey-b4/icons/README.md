# Vector assets: B4 BackfeedPageWide

UI icons are 24×24, round caps and joins, `#16325C`; recolour them with `.foregroundStyle`. Use the SF Symbol in the second column.

| File | SF Symbol | Used for |
|---|---|---|
| `ui-camera.svg` | `camera` | empty photo slot (26 pt, `#1F6FB5`) |
| `ui-check.svg` | `checkmark` | green check on a filled slot / selected level card (stroke 3) |
| `ui-close.svg` | `xmark` | clear a photo (stroke 3, white on a dark circle) |
| `ui-chevron-left.svg` / `ui-chevron-right.svg` | `chevron.left` / `chevron.right` | previous / next step buttons |

## Illustrations (placeholders, not app assets)
| File | What |
|---|---|
| `photo-lv-mdp-ct.svg` | sample photo for slot 1 (LV): MDP-1 with the CT spot marked (teal dashed box) |
| `photo-lv-ct-label.svg` | sample photo for slot 2 (LV) |
| `photo-hv-pole.svg` | sample photo for slots 1–2 (HV): pole after the PEA meter |
| `photo-placeholder-scene.svg` | generic sample photo (slots 3–4) |

In the app these slots show the user's real photos. The teal dashed box is how the board shows where the user marks the spot.

## Reference crops (framing only; the app renders these from code)
| File | What |
|---|---|
| `sld-crop-lv.svg` / `sld-crop-hv.svg` | the part of `SingleLineLayout` to show in `ส่วนที่เปลี่ยนใน SLD` (LV: viewBox 50 30 760 330; HV: viewBox 60 790 880 270 in the board's SLD coordinates) |
| `a2-crop-lv.svg` / `a2-crop-hv.svg` | the A2 site image cropped around the `กันย้อน` mark |
