Output docs/assets/15-snapshot-diff.gif
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

# Snapshots are git commits; give the demo project its own throwaway
# repository so the recording never touches the real one.
Hide
Type "git -C docs/vhs/demo init -q 2>/dev/null; git -C docs/vhs/demo config user.email demo@storyteller; git -C docs/vhs/demo config user.name Demo"
Enter
Type "nvim -u docs/vhs/demo-init.lua docs/vhs/demo/chapters/01_the_harbor.md"
Enter
Sleep 3s
Show
Type ":Story snapshot before revision"
Enter
Sleep 2500ms
Type "Go"
Sleep 300ms
Type "The gulls went quiet first."
Sleep 1200ms
Type ":Story diff"
Enter
Sleep 4s
Hide
Type ":qa!"
Enter
