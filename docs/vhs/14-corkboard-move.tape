Output docs/assets/14-corkboard-move.gif
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
# Move the second card through the story order: past the chapter boundary.
Type "/The choice"
Enter
Sleep 500ms
Type "J"
Sleep 1500ms
# :w applies the reorder to the Markdown files atomically.
Type ":w"
Enter
Sleep 2500ms
# Move it back and apply again — the board is the editor, :w is the commit.
Type "/The choice"
Enter
Sleep 500ms
Type "K"
Sleep 1500ms
Type ":w"
Enter
Sleep 2500ms
Hide
Type ":qa!"
Enter
