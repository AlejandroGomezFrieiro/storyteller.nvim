Output docs/assets/19-tui.gif

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

Show
Type "storyteller-tui docs/vhs/demo"
Enter
Sleep 3s
# Five tabs, one grammar: Tab cycles Dashboard → Corkboard → Timeline →
# Plotlines → Relations; j/k moves within a view.
Tab
Sleep 1500ms
Tab
Sleep 2000ms
# Timeline: t cycles axes, o flips reading/story order, h/l retimes.
Type "t"
Sleep 800ms
Type "o"
Sleep 1500ms
# Plotlines: lanes with stage pills; v switches modes, p the read-only grid.
Tab
Sleep 2000ms
Type "p"
Sleep 1200ms
Type "v"
Sleep 1500ms
# Relations: the character graph with its inspector pane.
Type "Tab"
Sleep 2500ms
# Staging moment: on Corkboard, `a` advances a card's status into the staged
# set (footer shows the pending segment); S applies everything at once.
Type "2"
Sleep 1000ms
Type "a"
Sleep 1000ms
Type "S"
Sleep 1800ms
Hide
Type "q"
Sleep 500ms
Show
Sleep 500ms
