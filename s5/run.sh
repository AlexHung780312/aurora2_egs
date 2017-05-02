#!/bin/bash

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.
##
stage=-2
no_cmvn=false
training=Clean
tr=${training}90
cv=${training}Dev10
aurora2=/share/corpus/aurora2
# 原本的光碟是"big", 這份是"little"
endian=little
#training=Multi
#training_dev=MultiDev10
[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

if [ $stage -le -2 ]; then
./local/aurora2_prep_data.sh --endian $endian $aurora2 || exit 1;
exit 0;
fi
if [ $stage -le -1 ]; then
for s in Aurora2.TR.Clean Aurora2.TR.Multi $(for i in A1 A2 A3 A4 B1 B2 B3 B4 C1 C2; do for j in C +20 +15 +10 +5 +0 -5; do echo Aurora2.TS.$i$j; done; done); do
  # 抽mfcc特徵
  steps/make_mfcc.sh --nj 8 data/${s} exp/make_mfcc/${s} data/${s}/data || exit 1;
  # 求cmvn mean var
  steps/compute_cmvn_stats.sh data/${s} exp/make_mfcc/cmvn_${s} data/${s}/data || exit 1;
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
    if [ -d data/${s} ]; then 
      steps/compute_cmvn_stats.sh --fake data/${s} exp/make_mfcc/cmvn_${s} data/${s}/data
    fi
  done
  fi
fi
if [ $stage -le 1 ]; then
steps/train_mono.sh --cmd "$train_cmd" --nj 8 --totgauss 300 \
  data/Aurora2.TR.${training} data/lang exp/mono0a_${training} || exit 1; # 產生exp/mono0a_Clean or Multi
fi

if [ $stage -le 2 ]; then
steps/align_si.sh --cmd "$train_cmd" --nj 8  \
   data/Aurora2.TR.${training} data/lang_test_tg exp/mono0a_${training} exp/mono0a_${training}_ali || exit 1;
fi
if [ $stage -le 3 ]; then
steps/train_deltas.sh --cmd "$train_cmd" --delta-opts "--delta-order=2" --context-opts "--context-width=1 --central-position=0" \
  20 400 data/Aurora2.TR.${training} data/lang exp/mono0a_${training}_ali exp/mono1a_${training} || exit 1; # 產生exp/mono0a_Clean or Multi
fi
if [ $stage -le 4 ]; then
$mkgraph_cmd exp/mono1a_${training}/log/mkgraph.log \
  utils/mkgraph.sh --mono data/lang_test_tg exp/mono1a_${training} exp/mono1a_${training}/graph || exit 1;
fi
if [ $stage -le 5 ]; then
  for test in $(for i in A1 A2 A3 A4 B1 B2 B3 B4 C1 C2; do for j in C +20 +15 +10 +5 +0 -5; do echo Aurora2.TS.$i$j; done; done); do
    steps/decode.sh --cmd "$decode_cmd" --nj 8 --config conf/decode.config \
      exp/mono1a_${training}/graph data/$test exp/mono1a_${training}/decode_$test || exit 1;
  done
  for x in `ls -d exp/mono1a_${training}/decode_*`; do
    [ -d $x ] && (echo $x && grep WER $x/wer_* | utils/best_wer.sh) >> gmm.result.txt
  done
  exit 0;
fi
if [ $stage -le 6 ]; then
# 對資料
steps/align_si.sh --cmd "$train_cmd" --nj 8  \
   data/Aurora2.TR.${tr} data/lang_test_tg exp/mono0a_${training} exp/mono1a_${tr}_ali || exit 1;
# 對dev
steps/align_si.sh --cmd "$train_cmd" --nj 8  \
   data/Aurora2.TR.${cv} data/lang_test_tg exp/mono0a_${training} exp/mono1a_${cv}_ali || exit 1;
fi
exit 0;

#後面用不到
echo "Now begin train DNN systems on ${training} data"
for hid_dim in 128 256 512 1024; do
#RBM pretrain
if [ $stage -le 7 ]; then
[ -d exp/mono1a_${training}_dnn_pretrain ] && rm -r exp/mono1a_${training}_dnn_pretrain${hid_dim}

dir=exp/mono1a_${training}_dnn_pretrain
[ ! -d $dir ] && mkdir -p $dir/log
$cuda_cmd $dir/log/pretrain_dbn.log \
  steps/nnet/pretrain_dbn.sh --delta-opts "--delta-order=2" --nn-depth $nn_depth --hid-dim $hid_dim --rbm-iter 3 data/Aurora2.TR.${training} $dir
fi

dir=exp/mono1a_${training}_dnn_l${layer}d${hid_dim}
ali=exp/mono1a_${tr}_ali
ali_dev=exp/mono1a_${cv}_ali
feature_transform=exp/mono1a_${training}_dnn_pretrain/final.feature_transform
for layer in `seq 1 6`; do
[ -d exp/mono1a_${training}_dnn ] && rm -r exp/mono1a_${training}_dnn${hid_dim}
dbn=exp/mono1a_${training}_dnn_pretrain/$layer.dbn
if [ $stage -le 8 ]; then
  $cuda_cmd $dir/_train_nnet.log \
    steps/nnet/train.sh --feature-transform $feature_transform --delta-opts "--delta-order=2" --dbn $dbn --hid-layers 0 --learn-rate 0.08 \
    data/Aurora2.TR.${tr} data/Aurora2.TR.${cv} data/lang $ali $ali_dev $dir || exit 1;
fi
dnndir=exp/mono1a_${training}_dnn_l${layer}d${hid_dim}
if [ $stage -le 9 ]; then
  for test in $(for i in A1 A2 A3 A4 B1 B2 B3 B4 C1 C2; do for j in C +20 +15 +10 +5 +0 -5; do echo Aurora2.TS.$i$j; done; done); do
    echo $test
    # dnn
    steps/nnet/decode.sh --cmd "$decode_cmd" --nj 8 --config conf/decode_dnn.config \
        exp/mono1a_${training}/graph data/$test $dnndir/decode_$test || exit 1;  #error rate
  done
fi
[ -f l${nn_depth}d${hid_dim}.result.txt ] && rm l${nn_depth}d${hid_dim}.result.txt
# print wer%
for x in `ls -d $dnndir/decode*`; do
  [ -d $x ] && (echo $x && grep WER $x/wer_* | utils/best_wer.sh) >> l${nn_depth}d${hid_dim}.result.txt
done
done
done
exit 0;


