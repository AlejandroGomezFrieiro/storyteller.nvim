# VHS Demos

The tapes in this directory generate the GIFs embedded in the README and user
guide. They use [Charmbracelet VHS](https://github.com/charmbracelet/vhs),
`demo-init.lua`, and the small Markdown project in `demo/`, so they run without
a personal Neovim configuration.

From the repository root:

```bash
nix develop
vhs docs/vhs/01-corkboard.tape
vhs docs/vhs/02-scrivenings.tape
vhs docs/vhs/03-targets.tape
vhs docs/vhs/storyteller.tape
```

The output paths are declared inside each tape. Regenerate all assets after a
visual or workflow change before publishing documentation.
