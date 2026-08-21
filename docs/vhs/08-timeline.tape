Output docs/assets/08-timeline.gif
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
Type ":Story timeline"
Enter
Sleep 4s
# The timeline is a table projection: J shifts the row's day cell (+1).
Type "3j"
Sleep 500ms
Type "J"
Sleep 2500ms
# Re-render from disk to discard the staged edit.
Type "R"
Sleep 1500ms
Hide
Type ":qa!"
Enter
