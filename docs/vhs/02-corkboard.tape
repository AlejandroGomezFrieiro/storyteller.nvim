Output docs/assets/02-corkboard.gif
Require nvim
Require storyteller-lsp

Set Shell "bash"
Set Theme "Catppuccin Frappe"
Set FontSize 18
Set Width 1000
Set Height 560
Set Padding 20
Set Margin 18
Set MarginFill "#1e1e2e"
Set BorderRadius 12
Set WindowBar Colorful
Set CursorBlink false
Set Framerate 60
Set PlaybackSpeed 1.0
Set TypingSpeed 45ms

Hide
Type "nvim -u docs/vhs/demo-init.lua docs/vhs/demo/chapters/01_the_harbor.md"
Enter
Sleep 3s
Show
Type ":Story corkboard"
Enter
Sleep 4s
# The board is an editable projection: cycle a card's status (staged).
Type "jja"
Sleep 2500ms
# Re-render from disk to discard the staged edit.
Type "R"
Sleep 1500ms
Hide
Type ":qa!"
Enter
