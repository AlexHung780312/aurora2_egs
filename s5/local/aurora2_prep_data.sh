#!/bin/bash

# 原本光碟是big, 這份用little
endian=little
tmpdir=`pwd`/data/local/data
[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

if [ $# != 1 ]; then
  echo "Usage: ./local/aurora2_prep_data.sh [options] <aurora2_dir>";
  exit 1;
fi

aurora2=$1
mkdir -p $tmpdir
rootdir=$aurora2/SPEECHDATA

[ -z `which sox` ] && echo "need to install sox. eg: sudo apt-get install sox"

# clean condition
dir=data/Aurora2.TR.Clean
echo $dir
mkdir -p $dir
[ -f $dir/wav.scp ] && rm $dir/wav.scp;
[ -f $dir/utt2spk ] && rm $dir/utt2spk;
[ -f $dir/text ] && rm $dir/text;
for f in `find $rootdir/TRAIN/CLEAN -name '*.08'`; do
  uttr=`basename -s .08 ${f}`;
  key="Aurora2.TR.Clean_${uttr}";
  spk=`echo ${uttr} | awk 'BEGIN{FS="_";}{print $1;}'`
  text=`echo ${uttr} | awk 'BEGIN{FS="_";}{print $2;}' | sed 's/[A,B]//g' | sed -e 's/\(.\)/\1 /g'`
  echo "$key sox --endian $endian -r 8000 -b 16 -t raw -e signed-integer $f -t wav --endian little - |" >> $dir/wav.scp
  echo "$key $spk" >> $dir/utt2spk
  echo "$key $text" >> $dir/text
done

# multi condition
dir=data/Aurora2.TR.Multi
echo $dir
mkdir -p $dir
[ -f $dir/wav.scp ] && rm $dir/wav.scp;
[ -f $dir/utt2spk ] && rm $dir/utt2spk;
[ -f $dir/text ] && rm $dir/text;
for d in `ls -d $rootdir/TRAIN/CLEAN{1,2,3,4}` `ls -d $rootdir/TRAIN/* | grep -v CLEAN`; do
for f in `find $d -name '*.08'`; do
  uttr=`basename -s .08 ${f}`;
  key="Aurora2.TR.Clean_${uttr}";
  spk=`echo ${uttr} | awk 'BEGIN{FS="_";}{print $1;}'`
  text=`echo ${uttr} | awk 'BEGIN{FS="_";}{print $2;}' | sed 's/[A,B]//g' | sed -e 's/\(.\)/\1 /g'`
  echo "$key sox --endian $endian -r 8000 -b 16 -t raw -e signed-integer $f -t wav --endian little - |" >> $dir/wav.scp
  echo "$key $spk" >> $dir/utt2spk
  echo "$key $text" >> $dir/text
done
done

# test
for t in A B C; do
  for n in 1 2 3 4; do
    [ "$t" == "C" ] && [ $n -ge 3 ] && break;
    dir=data/Aurora2.TS.${t}${n}C
    echo $dir;
    mkdir -p $dir
    [ -f $dir/wav.scp ] && rm $dir/wav.scp;
    [ -f $dir/utt2spk ] && rm $dir/utt2spk;
    [ -f $dir/text ] && rm $dir/text;
    wavdir="$rootdir/TEST${t}/CLEAN${n}"
    for f in `find ${wavdir} -name '*.08'`; do
      uttr=`basename -s .08 ${f}`;
      key=`echo Aurora2.TS.${t}${n}C_${uttr} | sed 's/\+//g'`;
      spk=`echo ${uttr} | awk 'BEGIN{FS="_";}{print $1;}'`
      text=`echo ${uttr} | awk 'BEGIN{FS="_";}{print $2;}' | sed 's/[A,B]//g' | sed -e 's/\(.\)/\1 /g'`
      echo "$key sox --endian $endian -r 8000 -b 16 -t raw -e signed-integer $f -t wav --endian little - |" >> $dir/wav.scp
      echo "$key $spk" >> $dir/utt2spk
      echo "$key $text" >> $dir/text
    done

    for snr in -5 +0 +5 +10 +15 +20; do
      dir=data/Aurora2.TS.${t}${n}${snr}
      echo $dir;
      mkdir -p $dir
      [ -f $dir/wav.scp ] && rm $dir/wav.scp;
      [ -f $dir/utt2spk ] && rm $dir/utt2spk;
      [ -f $dir/text ] && rm $dir/text;
      wavdir=`echo $rootdir/TEST${t}/N${n}_SNR${snr} | sed 's/\+//g'`
      for f in `find ${wavdir} -name '*.08'`; do
      	uttr=`basename -s .08 ${f}`;
        key=`echo Aurora2.TS.${t}${n}${snr}_${uttr} | sed 's/\+//g'`;
        spk=`echo ${uttr} | awk 'BEGIN{FS="_";}{print $1;}'`
        text=`echo ${uttr} | awk 'BEGIN{FS="_";}{print $2;}' | sed 's/[A,B]//g' | sed -e 's/\(.\)/\1 /g'`
        echo "$key sox --endian $endian -r 8000 -b 16 -t raw -e signed-integer $f -t wav --endian little - |" >> $dir/wav.scp
        echo "$key $spk" >> $dir/utt2spk
        echo "$key $text" >> $dir/text
      done
    done
  done
done

# spk2utt and fix order
for d in `ls -d data/Aurora2*`; do
  ./utils/utt2spk_to_spk2utt.pl $d/utt2spk > $d/spk2utt
  ./utils/fix_data_dir.sh $d
done
echo "Data preparation succeeded"
