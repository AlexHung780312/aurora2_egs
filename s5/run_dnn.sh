#!/bin/bash

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.
##
stage=-2
training=Clean
tr=${training}90
cv=${training}Dev10
feature=mfcc
# 原本的光碟是"big", 這份是"little"
endian=little
#training=Multi
#training_dev=MultiDev10
[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;
#for hid_dim in 128 256 512 1024; do
for hid_dim in 128; do
# RBM pretrain
  if [ $stage -le 1 ]; then
    [ -d exp/mono1a_${training}_dnn_${feature}_pretrain ] && rm -r exp/mono1a_${training}_dnn_${feature}_pretrain${hid_dim}
    dir=exp/mono1a_${training}_dnn_${feature}_pretrain${hid_dim}
    [ ! -d $dir ] && mkdir -p $dir/log
    $cuda_cmd $dir/log/pretrain_dbn.log \
      steps/nnet/pretrain_dbn.sh --delta-opts "--delta-order=2" --nn-depth 6 --hid-dim $hid_dim --rbm-iter 3 ${feature}_data/Aurora2.TR.${training} $dir
  fi
# for layer in `seq 1 6`; do
  for layer in 6; do
    dir=exp/mono1a_${training}_dnn_${feature}_l${layer}d${hid_dim}
    ali=exp/mono1a_${tr}_ali
    ali_dev=exp/mono1a_${cv}_ali
    feature_transform=exp/mono1a_${training}_dnn_${feature}_pretrain${hid_dim}/final.feature_transform
    [ -d $dir ] && rm -r $dir
    dbn=exp/mono1a_${training}_dnn_${feature}_pretrain${hid_dim}/$layer.dbn
    if [ $stage -le 8 ]; then
      $cuda_cmd $dir/log/train_nnet.log \
        steps/nnet/train.sh --feature-transform $feature_transform --delta-opts "--delta-order=2" --dbn $dbn --hid-layers 0 --learn-rate 0.008 \
        ${feature}_data/Aurora2.TR.${tr} ${feature}_data/Aurora2.TR.${cv} data/lang $ali $ali_dev $dir || exit 1;
    fi
    dnndir=exp/mono1a_${training}_dnn_${feature}_l${layer}d${hid_dim}
    if [ $stage -le 9 ]; then
      for test in $(for i in A1 A2 A3 A4 B1 B2 B3 B4 C1 C2; do for j in C +20 +15 +10 +5 +0 -5; do echo Aurora2.TS.$i$j; done; done); do
        # dnn
        steps/nnet/decode.sh --cmd "$decode_cmd" --nj 8 --config conf/decode_dnn.config \
          exp/mono1a_${training}/graph ${feature}_data/$test $dnndir/decode_$test || exit 1;  #error rate
      done
    fi
    [ -f ${feature}_l${layer}d${hid_dim}.result.txt ] && rm ${feature}_l${layer}d${hid_dim}.result.txt
    # print wer%
    for x in `ls -d $dnndir/decode*`; do
      [ -d $x ] && (echo $x && grep WER $x/wer_* | utils/best_wer.sh) >> ${feature}_l${layer}d${hid_dim}.result.txt
    done
  done
done
exit 0;


