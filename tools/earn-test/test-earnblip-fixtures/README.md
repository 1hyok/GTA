# Saved minimap fixtures

These four PNGs are unscaled crops of existing 1920x1080 screenshots, rectangle `(20, 860, 310, 1050)`. No new game input or capture was performed. Originals were under `C:/Users/rlfjr/AppData/Local/Temp/claude/` on 2026-09-27.

| Original filename | Original SHA-256 |
| --- | --- |
| `arcade-stair-stop1.png` | `a3ea8f00c103eacfdde5cd36b783a3650d78ac66b4a69305729067e6e91ee144` |
| `arcade-stair-mct-current.png` | `14bdcae2d6afab1f5736a530ef97e0393c2cdcfae14eb132ed115700c44bab5f` |
| `arcade-mct-feedback-state.png` | `da8fb0c8f9472e39d49f349fa44b2e08b7ea83ab93b9892500ee703bbe0a2fbb` |
| `arcade-route-spawn.png` | `bac813d09cadcab0e4a0053febd62ac9a33f735e6a3449267fade5e975d76620` |

`arcade-stair-stop1`: MCT at screen (221.5, 980.5), no laptop.
`arcade-stair-mct-current`: MCT at (112.5, 983), laptop at (210, 901).
`arcade-mct-feedback-state`: laptop at (147, 1001), no MCT.
`arcade-route-spawn`: laptop at (237, 947), no MCT.
Coordinates identify the white screen component center, not the whole icon center.

Two synthetic negative fixtures derive from the MCT in `arcade-stair-mct-current`: `clipped-mct.png` places its 25x26 icon crop partly beyond the left edge; `screen-only.png` keeps only its upper 12 rows without an identifiable lower body. Neither may be classified as a computer type.

The classifier distinguishes the narrow MCT monitor stem with bright sides from the laptop's wide dark lower body and bright center touchpad. Screen height alone overlaps (both can be 7 pixels). Unknown or edge-clipped computer shapes are rejected. This is evidence for these saved 1920x1080 frames, not a claim of coverage for every icon animation, resolution, or overlap.

Four additional cases translate the complete real MCT and laptop sprites to the left edge in memory. Both must retain their type and report direction with the distance sentinel 999; neither may become the other computer type. This keeps valid edge navigation while rejecting genuinely clipped shapes. There are 16 cases in total.

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/earn-test/test-earnblip.ps1` from the repository. The test extracts the actual pure pixel functions from `EarnCore.ahk`, decodes PNGs to BGRA, and checks both classification and coordinates without game/window/input APIs.


## 17:09 MCT false negative correction

Three additional real minimap crops retain the same `(20, 860, 310, 1050)` crop rectangle:

| Original filename | Original SHA-256 |
| --- | --- |
| `arcade-fresh-route-end.png` | `f00e41c83528bd3a2f1a61ab8652ffeb17a75481892f9d01024e05265936c55f` |
| `arcade-fresh-route-state.png` | `fcc73ba91793929efd3b5ceddc791b497c58804b44b5f05c3548af26f13cdfef` |
| `arcade-face-resume-result.png` | `9941e9aca93cdd5ebcc0576a3ff5a53add261cee0eb18188f0119e3f1383f4b0` |

In `arcade-fresh-route-end`, the MCT screen is x=225..236, y=968..974. Its horizontal midpoint 230.5 rounds to 231, placing one of the five sampled stem pixels on an antialiased border (RGB maximum 143..159). Requiring all five pixels below 70 rejected the visible MCT. Requiring four of five dark pixels tolerates that one border pixel; two qualifying rows and bright gaps on both sides remain mandatory. Laptop, screen-only, clipped, and complete edge controls remain unchanged.

The added frame expectations are MCT (230.5,971) / laptop (114.5,1027) in `arcade-fresh-route-end`; MCT (73.5,879) / laptop (163,971) in `arcade-fresh-route-state`; no MCT / laptop (172,984) in `arcade-face-resume-result`. Total: 22 screenshot checks. These positions are white-screen component centers.


## Close MCT beside the player arrow

`arcade-stair-approach.png` is the same unscaled minimap crop from the 17:21:15 screenshot. Original SHA-256: `4fe602dc541d8bfe1633dd064cbc654d189303bc5484786d32e21dfa93ca996f`.

Its MCT white screen occupies x=166..178, y=997..1004, centered at (172,1000.5), only about 9.18 pixels from the fixed arrow origin. The old +/-10-pixel exclusion removed most of that screen. Removing the location exclusion lets screen density and lower-body structure reject arrows instead.

This frame also has dim MCT stem gaps because the minimap is translucent. Gap pixel pairs at three successive stem rows are (54,173), (123,94), (168,170), while the stem is mostly 2..8. Requiring both gaps >=100 yielded only one qualifying row. The classifier now requires each gap to exceed the mean of the dark stem samples by 40, with an absolute minimum of 45. It still requires two matching stem rows, at least four dark center samples per row, and rejects the laptop's wide dark body.

`arrow-only.png` contains only the actual player-arrow rectangle (minimap crop coordinates 135,135 through 152,157) from `arcade-route-spawn.png`, on a neutral gray field, at its original position. Both MCT and laptop detection must reject it. The close MCT frame must detect MCT and reject laptop. Total: 26 checks, including the prior 22 controls.
