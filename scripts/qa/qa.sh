#!/bin/zsh
# On-screen QA driver for VibeCheck. Build first: scripts/qa/build.sh. Run as .build/qa/qa <command>.
#
#   qa item <Name>            centre "x y" of the "VibeCheck <Name>" menu bar item (Vibe, CPU, Agents, Keep Awake…)
#   qa click X Y              click; refuses (exit 3, "PAUSE") if the cursor moved since our last action
#   qa move X Y               move only (hover, chart scrubbing); same guard
#   qa key CODE [mods]        key press, mods like cmd or ctrl-alt-cmd; same guard
#   qa reset                  forget the last cursor position (after the owner has used the Mac)
#   qa front                  name of the frontmost app (clicks land on whatever is in front!)
#   qa deck                   "id x y w h" of the open deck panel (layer 101), empty when closed
#   qa shot NAME [ID]         capture the deck (or window ID) only, to NAME.png in the current folder
#   qa press LABEL            AXPress the VibeCheck element whose description/title is LABEL (no mouse, no focus)
#   qa select TEXT            select the sidebar row containing TEXT (Settings panes), via accessibility
#   qa tree                   VibeCheck's accessibility tree (labels VoiceOver reads)
#   qa windows                VibeCheck's windows: id, layer, on-screen, frame, title
#
# Rules: capture single windows (never the whole screen); prefer press/select over clicks; check
# `qa front` before any click into a normal window; if anything says PAUSE, stop and ask the owner.
DIR=${0:A:h}
STATE=$DIR/.cursor
PID() { pgrep -f /Applications/VibeCheck.app/Contents/MacOS/VibeCheck | head -1; }
here() { $DIR/pos | sed -E 's/^\(([-0-9.]+), ([-0-9.]+)\).*/\1 \2/' | awk '{printf "%d %d", $1, $2}'; }
guard() {
  [ -f $STATE ] || return 0
  local now=$(here) last=$(cat $STATE)
  set -- ${=now} ${=last}
  local dx=$(( $1 - $3 )) dy=$(( $2 - $4 ))
  if [ ${dx#-} -gt 3 ] || [ ${dy#-} -gt 3 ]; then echo "PAUSE: cursor moved ($last -> $now); someone is using the Mac"; exit 3; fi
}
remember() { here > $STATE; }
case $1 in
  item) osascript -e "tell application \"System Events\" to tell process \"VibeCheck\" to get {position, size} of (first menu bar item of menu bar 1 whose description starts with \"VibeCheck $2\")" 2>/dev/null \
          | tr -d ' ' | awk -F, '{printf "%d %d\n", $1+$3/2, $2+$4/2}' ;;
  click) guard; $DIR/click $2 $3; sleep 0.15; remember ;;
  move) guard; $DIR/click $2 $3 move; sleep 0.15; remember ;;
  key) guard; $DIR/key $2 $3; remember ;;
  reset) rm -f $STATE ;;
  front) osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' ;;
  deck) $DIR/wins | awk '$3=="101" && $5=="true" {print $1, $8, $9, $10, $11; exit}' ;;
  shot) id=${3:-$($DIR/wins | awk '$3=="101" && $5=="true" {print $1; exit}')}
        [ -z "$id" ] && { echo "no window"; exit 1; }; screencapture -x -o -l $id "$2.png" && echo "$2.png" ;;
  press) $DIR/axpress $(PID) "$2" ;;
  select) $DIR/axselect $(PID) "$2" ;;
  tree) $DIR/axdump $(PID) ;;
  windows) $DIR/wins ;;
  *) sed -n '2,21p' $0 ;;
esac
