Output docs/assets/18-metasheet.gif
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
Type ":Story metasheet"
Enter
Sleep 3s
# One row per scene, one writable column per field — :s is a bulk edit too.
Type "/Black water"
Enter
Sleep 500ms
Type ":s/outline/draft/"
Enter
Sleep 1200ms
Type ":w"
Enter
Sleep 2500ms
# Revert the cell to leave the demo project untouched.
Type "/Black water"
Enter
Sleep 400ms
Type ":s/draft/outline/"
Enter
Sleep 1000ms
Type ":w"
Enter
Sleep 2500ms
Hide
Type ":qa!"
Enter
