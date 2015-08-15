#!/bin/bash
# author: Chang Ting-Hao
# Apache L. 2.0
. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.
##
copy-feats --htk-in=true scp:data/Aurora2.TR.Clean90/tmp.scp ark,scp:data/Aurora2.TR.Clean90/feats.ark,data/Aurora2.TR.Clean90/feats.scp
copy-feats --htk-in=true scp:data/Aurora2.TR.CleanDev10/tmp.scp ark,scp:data/Aurora2.TR.CleanDev10/feats.ark,data/Aurora2.TR.CleanDev10/feats.scp
copy-feats --htk-in=true scp:data/Aurora2.TR.Multi90/tmp.scp ark,scp:data/Aurora2.TR.Multi90/feats.ark,data/Aurora2.TR.Multi90/feats.scp
copy-feats --htk-in=true scp:data/Aurora2.TR.MultiDev10/tmp.scp ark,scp:data/Aurora2.TR.MultiDev10/feats.ark,data/Aurora2.TR.MultiDev10/feats.scp

for test in $(for i in A1 A2 A3 A4 B1 B2 B3 B4 C1 C2; do for j in C +20 +15 +10 +5 +0 -5; do echo Aurora2.TS.$i$j; done; done); do
	echo $test
	copy-feats --htk-in=true scp:data/${test}/tmp.scp ark,scp:data/${test}/feats.ark,data/${test}/feats.scp
done
