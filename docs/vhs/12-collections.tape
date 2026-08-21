Output docs/assets/12-collections.gif
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
# A one-off query lands in the quickfix list: walk matches with j/k, <CR> opens.
Type ":Story collect status:draft"
Enter
Sleep 4s
Type ":Story collections"
Enter
Sleep 4s
Hide
Type ":qa!"
Enter
