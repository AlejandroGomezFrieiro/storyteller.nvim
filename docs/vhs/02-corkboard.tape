Output docs/assets/02-corkboard.gif

Set Shell "bash"
Set FontSize 18
Set Width 1000
Set Height 560
Set TypingSpeed 35ms
Set Theme "Catppuccin Frappe"

Type "nvim -u docs/vhs/demo-init.lua docs/vhs/demo/chapters/01_the_harbor.md"
Enter
Sleep 2s
Type ":Story corkboard"
Enter
Sleep 4s
Type ":qa!"
Enter