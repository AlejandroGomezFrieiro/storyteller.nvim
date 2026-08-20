Output docs/assets/07-lsp-completion.gif
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
Type "Go"
Sleep 1s
Type "The Gr"
Sleep 1s
Ctrl+Space
Sleep 8s
Escape
Type "/storyteller: scene"
Enter
Sleep 2s
Type "o"
Type "s"
Ctrl+Space
Sleep 8s
Escape
Type "/status: outline"
Enter
Sleep 2s
Type "o"
Type "status: d"
Ctrl+Space
Sleep 8s
Escape
Type "/chars:"
Enter
Sleep 2s
Type "o"
Type "chars: O"
Ctrl+Space
Sleep 8s
Escape
Hide
Type ":qa!"
Enter
