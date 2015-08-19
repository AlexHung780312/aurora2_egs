#!/bin/bash

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.
##
stage=-2
no_cmvn=false
training=Clean
tr=${training}90
cv=${training}Dev10
aurora2=/usr/local/corpus/aurora2
# 原本的光碟是"big", 這份是"little"
endian=little
#training=Multi
#training_dev=MultiDev10
[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

if [ $stage -le -2 ]; then
./local/aurora2_prep_data.sh --endian $endian $aurora2 || exit 1;
fi
if [ $stage -le -1 ]; then
for s in Aurora2.TR.Clean Aurora2.TR.Multi $(for i in A1 A2 A3 A4 B1 B2 B3 B4 C1 C2; do for j in C +20 +15 +10 +5 +0 -5; do echo Aurora2.TS.$i$j; done; done); do
  # 抽mfcc特徵
  steps/make_mfcc.sh --nj 8 data/${s} exp/make_mfcc/${s} data/${s}/data || exit 1;
  # 求cmvn mean var
  steps/compute_cmvn_stats.sh --fake data/${s} exp/make_mfcc/cmvn_${s} data/${s}/data || exit 1;
done
# 分割
  ./utils/subset_data_dir_tr_cv.sh --cv-utt-percent 10 data/Aurora2.TR.Clean data/Aurora2.TR.Clean90 data/Aurora2.TR.CleanDev10
  ./utils/subset_data_dir_tr_cv.sh --cv-utt-percent 10 data/Aurora2.TR.Multi data/Aurora2.TR.Multi90 data/Aurora2.TR.MultiDev10

# make fbank features
# 沒有執行CNN,用不到
#mkdir -p data-fbank
#for s in Aurora2.TR.Clean Aurora2.TR.Multi $(for i in A1 A2 A3 A4 B1 B2 B3 B4 C1 C2; do for j in C +20 +15 +10 +5 +0 -5; do echo Aurora2.TS.$i$j; done; done); do
#  cp -r data/${s} data-fbank/${s}
#  steps/make_fbank.sh --nj 8 \
#    data-fbank/${s} exp/make_fbank/${s} data-fbank/${s}/data-fbank || exit 1;
#done
fi

if [ $stage -le 0 ]; then
# no_cmvn表示特徵已經正規化，不需要kaldi重新計算cmvn
  if $no_cmvn; then
  for s in Aurora2.TR.Clean90 Aurora2.TR.CleanDev10 Aurora2.TR.Multi90 Aurora2.TR.MultiDev10 $(for i in A1 A2 A3 A4 B1 B2 B3 B4 C1 C2; do for j in C +20 +15 +10 +5 +0 -5; do echo Aurora2.TS.$i$j; done; done); do
    steps/compute_cmvn_stats.sh --fake data/${s} exp/make_mfcc/cmvn_${s} data/${s}/data
  done
  fi
fi
if [ $stage -le 1 ]; then
steps/train_mono.sh --boost-silence 1.25 --nj 8  \
  data/Aurora2.TR.${training} data/lang exp/mono0a_${training} || exit 1; # 產生exp/mono0a_Clean or Multi
fi

if [ $stage -le 2 ]; then
steps/align_si.sh --boost-silence 1.25 --nj 8  \
   data/Aurora2.TR.${training} data/lang exp/mono0a_${training} exp/mono0a_${training}_ali || exit 1;

steps/train_deltas.sh --boost-silence 1.25 \
    1500 10000 data/Aurora2.TR.${training} data/lang exp/mono0a_${training}_ali exp/tri1_${training} || exit 1;
fi

if [ $stage -le 3 ]; then
steps/align_si.sh --nj 8 \
  data/Aurora2.TR.${training} data/lang exp/tri1_${training} exp/tri1_${training}_ali || exit 1;
steps/train_deltas.sh  \
  2000 15000 data/Aurora2.TR.${training} data/lang exp/tri1_${training}_ali exp/tri2a_${training} || exit 1;
fi

# LDA-MLLT
if [ $stage -le 4 ]; then
steps/train_lda_mllt.sh \
   --splice-opts "--left-context=3 --right-context=3" \
   2500 20000 data/Aurora2.TR.${training} data/lang exp/tri1_${training}_ali exp/tri2b_${training} || exit 1;
fi

if [ $stage -le 5 ]; then
  utils/mkgraph.sh data/lang exp/tri2b_${training} exp/tri2b_${training}/graph || exit 1;
fi

if [ $stage -le 6 ]; then
# 對資料
steps/align_si.sh  --nj 8 \
  --use-graphs true data/Aurora2.TR.${tr} data/lang exp/tri2b_${training} exp/tri2b_${tr}_ali || exit 1;
# 對dev
steps/align_si.sh  --nj 8 \
  data/Aurora2.TR.${cv} data/lang exp/tri2b_${training} exp/tri2b_${cv}_ali_dev || exit 1;
fi

echo "Now begin train DNN systems on ${training} data"

#RBM pretrain
if [ $stage -le 7 ]; then
[ -d exp/tri3a_${training}_dnn_pretrain ] && rm -r exp/tri3a_${training}_dnn_pretrain
[ -d exp/tri3a_${training}_dnn ] && rm -r exp/tri3a_${training}_dnn
dir=exp/tri3a_${training}_dnn_pretrain
[ ! -d $dir ] && mkdir -p $dir/log
$cuda_cmd $dir/log/pretrain_dbn.log \
  steps/nnet/pretrain_dbn.sh --nn-depth 4 --hid-dim 512 --rbm-iter 3 data/Aurora2.TR.${training} $dir
fi

dir=exp/tri3a_${training}_dnn
ali=exp/tri2b_${tr}_ali
ali_dev=exp/tri2b_${cv}_ali_dev
feature_transform=exp/tri3a_${training}_dnn_pretrain/final.feature_transform
dbn=exp/tri3a_${training}_dnn_pretrain/4.dbn
if [ $stage -le 8 ]; then
  $cuda_cmd $dir/_train_nnet.log \
    steps/nnet/train.sh --feature-transform $feature_transform --dbn $dbn --hid-layers 0 --learn-rate 0.008 \
    data/Aurora2.TR.${tr} data/Aurora2.TR.${cv} data/lang $ali $ali_dev $dir || exit 1;
fi

if [ $stage -le 9 ]; then
  dnndir=exp/tri3a_${training}_dnn
  for test in $(for i in A1 A2 A3 A4 B1 B2 B3 B4 C1 C2; do for j in C +20 +15 +10 +5 +0 -5; do echo Aurora2.TS.$i$j; done; done); do
    echo $test
  # dnn
  steps/nnet/decode.sh --nj 4 --acwt 0.10 --use-gpu yes --config conf/decode_dnn.config \
    exp/tri2b_${training}/graph data/$test $dnndir/decode_$test || exit 1;  #error rate
done

fi
rm result.txt
# print wer%
for x in $dnndir/decode*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh >> result.txt; done
exit 0;


