# DJ popularity fixtures

Both images are cropped from observed 1920x1080 game screenshots. They contain only the popularity UI.

- `nightclub-home-95.png`: crop `(728,135,878,78)` from `earn-current-ceo.png`, captured 2026-10-03 08:05:38 KST. The Home bar samples 164 bright pixels out of 172, which rounds to 95%.
- `mct-popularity-92.png`: crop `(325,435,390,55)` from `earn-ceo-clean-mct.png`, captured 2026-10-03 08:07:07 KST. The old MCT sampler reads 113/123, which rounds to 92%.

The captures are 89 seconds apart. They establish different displayed values, not whether caching or a popularity change caused the difference. DJ spending uses the Home value after confirming its `Nightclub Popularity` text. The MCT value remains diagnostic only.

`Images/Earn/1920x1080/nc_popularity_home.png` is the `(743,160,259,28)` text crop from the Home capture. Pixels whose minimum RGB channel is below 220 are magenta, matching the existing transparent-template convention.

`test-earntasks.ps1` checks the template against both saved regions, then executes the production bar sampler and Home reader using these saved pixels. No window, screenshot or game input is used.

`bunker-supply-full.png` is the `(653,367,940,33)` Supplies Level crop from the Steam recording at 2026-10-12 23:57:44 KST. The recording was played continuously from 23:57:24 to 23:57:57 before extraction. It shows full internal supplies while the preceding MCT card displayed an empty supplies bar. The label template retains white text from `(664,368,192,30)` with minimum RGB channel 200. `test-bunker-supply.ps1`, invoked by `test-earntasks.ps1`, checks the template, saved full and partial bar pixels, unrelated screens, and input guards with all desktop operations stubbed.
