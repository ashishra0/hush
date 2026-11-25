#!/bin/bash
# Seeds a throwaway database and captures Hush windows (never touches your real tasks).
# usage: scripts/screenshots.sh <light|dark> <outdir> <HUSH_OPEN list, e.g. outline,capture,popover>
# Needs build/Hush.app (scripts/bundle.sh), sqlite3, and Screen Recording permission for your terminal.
set -u
APP="$(cd "$(dirname "$0")/.." && pwd)/build/Hush.app/Contents/MacOS/Hush"
DB=$2/qa.sqlite; mkdir -p $2; rm -f $DB*
HUSH_DB_PATH=$DB $APP & P=$!; sleep 2; kill $P; wait $P 2>/dev/null
N=$(date +%s); Y=$((N-86400)); W=$((N-3*86400))
sqlite3 $DB "
INSERT INTO task(id,parentId,position,title,note,createdAt) VALUES (10,NULL,1,'Work','',$N),(11,10,0,'Launch v1.2','',$N),(12,11,0,'Release notes','',$N),(13,12,0,'Draft headline and three bullets','',$N),(14,12,1,'Screenshots for the changelog','Light and dark versions of the outline and capture. Export at 2x.',$N),(15,11,1,'QA pass','',$N),(16,10,1,'Book 1:1 with Sam','',$N),(17,1,0,'Send Ana the Q4 deck before standup','',$N),(18,10,2,'A very long task title that keeps going to check how wrapping behaves when the text is much wider than the column allows','',$N);
INSERT INTO task(id,parentId,position,title,createdAt,collapsed) VALUES (20,NULL,2,'Personal',$N,1),(21,20,0,'Renew passport',$N,0);
INSERT INTO task(id,parentId,position,title,createdAt,completedAt) VALUES (30,10,9,'Freeze strings',$N,$N),(31,10,9,'Reply to the recruiter',$N,$N-600),(32,20,9,'Pick up dry cleaning',$N,$N-1200),(33,10,9,'Ship onboarding copy',$Y,$Y),(34,20,9,'Call Mum',$W,$W);"
HUSH_DB_PATH=$DB HUSH_OPEN=$3 $APP -appearance $1 -showMomentum YES & P=$!; sleep 3
swift -e 'import CoreGraphics; let l = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String:Any]]; for w in l where (w["kCGWindowOwnerPID"] as? Int) == Int(CommandLine.arguments[1])! { let b = w["kCGWindowBounds"] as! [String:Any]; if (b["Width"] as! Double) > 60 && (b["Height"] as! Double) > 40 { print(w["kCGWindowNumber"]!, Int(b["Width"] as! Double), Int(b["Height"] as! Double)) } }' $P 2>/dev/null | while read id w h; do screencapture -x -o -l$id $2/$1-$id-${w}x$h.png; echo $2/$1-$id-${w}x$h.png; done
kill $P
