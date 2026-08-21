Output docs/assets/11-annotations.gif
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
# Capture a note from a visual selection over the prose.
Type "/Odysseus watched"
Enter
Sleep 500ms
Type "Vj"
Sleep 500ms
Type ":Story note Sharpen the harbor reveal"
Enter
Sleep 1500ms
# Review everything in notes/annotations.md.
Type ":Story annotations"
Enter
Sleep 5s
Hide
Type ":qa!"
Enter
