# Vendored Godot benchmark reference

Source: https://github.com/godotengine/godot-benchmarks

Pinned commit: `ef3a94f131552c9c5aa040c985185de705068eda`.
Downloaded from that commit's raw files on 2026-09-06. Files listed below are
unmodified, including the icon and MIT license. `.gdignore` and this provenance
file are local additions. Preserve upstream files when modifying the comparison;
update the pin, attribution and hashes together for an intentional upstream bump.

| Local file | Upstream path | SHA-256 |
| --- | --- | --- |
| benchmark.gd | benchmark.gd | CE20298BB7AFD66CB3C42FEA0320BAC589CFEAF1BBCE637A600DE2AE1CD486B6 |
| tween.gd | benchmarks/animation/tween.gd | CF1A6ED1EED43CDEC96F951BA05230984E172021F7C4FF6AB23F2BA5A4F10FB2 |
| manager.gd | manager.gd | C4BAE1EFEA609A3F9F8CCF04DBEB69EFE193E0FAFF09E2B301B8C966099DD535 |
| project.godot | project.godot | E942995C87024BFDC22C5FD9B599D4C8E4B653D2AB05F23787F74C16B197AFB7 |
| icon.png | icon.png | A81C3855361A5228DDA64B26ED148B31DD3A73F6126D6DBB96CCABB0C8DDA62A |
| LICENSE.md | LICENSE.md | E7D6B4C3460C7ECF0CEEE89329FA45EF40E13D9B0753AE5A5F1D0CD7024C0662 |

`benchmark.gd`, `tween.gd`, `icon.png` and `LICENSE.md` are copied into an isolated
host by `test/runners/run_godot_tween_comparison.ps1`. `manager.gd` and
`project.godot` are reference material for the timing equations and settings;
they are not executed by the local runner. The local runner's timing logic is
adapted from this manager; its curve workloads derive from `tween.gd`.

The original copyright notices and MIT grant are retained in
[LICENSE.md](LICENSE.md). These vendored development tests are not addon runtime
dependencies and are outside the release package's addon-only content.
