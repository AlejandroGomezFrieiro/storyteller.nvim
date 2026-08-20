Output docs/assets/06-lsp-create-card.gif
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
Type "nvim -u docs/vhs/demo-init.lua docs/vhs/demo/chapters/02_the_crossing.md"
Enter
Sleep 3s
Show
Type "/Charybdis"
Enter
Sleep 1s
Type "ve"
Sleep 1s
Type " lc"
Sleep 5s
Hide
Type ":qa!"
Enter
