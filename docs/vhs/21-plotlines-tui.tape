Output docs/assets/21-plotlines-tui.gif

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
# Tab 4: Plotlines — one lane per track card, attached scenes in manuscript
# order with stage pills, unreached stages as ghosts.
Type "4"
Sleep 2500ms
# p overlays the read-only plot grid (stages × tracks).
Type "p"
Sleep 2000ms
Type "p"
Sleep 800ms
# v cycles Lanes → Threads → Auto; threads group setup/payoff keys.
Type "v"
Sleep 2000ms
Type "v"
Sleep 1500ms
# i sets the stage of the focused scene (staged until S).
Hide
Type "q"
Sleep 500ms
Show
Sleep 500ms
