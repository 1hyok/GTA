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
