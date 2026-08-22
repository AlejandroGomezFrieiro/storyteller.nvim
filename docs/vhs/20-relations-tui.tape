Output docs/assets/20-relations-tui.gif

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
# Tab 5: the Relations canvas — cards as nodes, edges as kinds, unresolved
# names as ghost nodes.
Type "5"
Sleep 2500ms
# j/k walks focus; h/l steps directionally; Tab toggles the inspector pane.
Type "l"
Sleep 800ms
Type "j"
Sleep 800ms
Type "Tab"
Sleep 2000ms
# a adds an edge (target prompt), x removes one — both staged until S.
Hide
Type "q"
Sleep 500ms
Show
Sleep 500ms
