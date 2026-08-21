Output docs/assets/17-synopsis.gif
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
Type ":Story synopsis"
Enter
Sleep 3s
# Write a synopsis under the first scene heading; :w stores it as YAML.
Type "/The warning"
Enter
Sleep 500ms
Type "o"
Sleep 300ms
Type "A letter arrives too late to matter."
Escape
Sleep 800ms
Type ":w"
Enter
Sleep 2500ms
# Remove it again to leave the demo project untouched.
Type "/too late to matter"
Enter
Sleep 400ms
Type "dd"
Sleep 600ms
Type ":w"
Enter
Sleep 2500ms
Hide
Type ":qa!"
Enter
