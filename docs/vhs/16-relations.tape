Output docs/assets/16-relations.gif
Require nvim
Require storyteller-lsp

Set Shell "bash"
Set Theme "Catppuccin Frappe"
Set FontSize 18
Set Width 1000
Set Height 620
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
Type ":Story relations"
Enter
Sleep 4s
# Walk the cast and add a new edge live.
Type "j"
Sleep 800ms
Type "j"
Sleep 800ms
Type "a"
Sleep 800ms
Type "Penelope"
Enter
Sleep 500ms
Enter
Sleep 1500ms
Hide
Type ":qa!"
Enter
