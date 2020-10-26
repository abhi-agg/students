#!/bin/bash -v

# Set GPUs.
# GPUS="0 1 2 3"
GPUS="0"
module load use.own
module load marian/dev-467b15e2
module load fast_align/cab1e9a
module load sentencepiece/0.1.92
module load extract_lex/42fa605
module load parallel/20131222


SRC=pl
TRG=en

set -x

# Add symbolic links to the training files.
test -e corpus.$SRC.gz || exit 1    # e.g. ../../data/train.en.gz
test -e corpus.$TRG.gz || exit 1    # e.g. ../../data/train.es.translated.gz
test -e corpus.aln.gz  || exit 1    # e.g. ../../alignment/corpus.aln.gz
test -e lex.s2t.gz     || exit 1    # e.g. ../../alignment/lex.s2t.pruned.gz
test -e vocab.${SRC}.spm      || exit 1    # e.g. ../../data/vocab.spm
test -e vocab.${TRG}.spm      || exit 1    # e.g. ../../data/vocab.spm

# Validation set with original source and target sentences (not distilled).
test -e devset.$SRC || exit 1
test -e devset.$TRG || exit 1

TMPDIR="/local/$USER"
mkdir -p $TMPDIR

marian \
    --model model.npz -c student.base.yml \
    --train-sets corpus.{$SRC,$TRG}.gz -T $TMPDIR --shuffle-in-ram \
    --guided-alignment corpus.aln.gz \
    --vocabs vocab.${SRC}.spm vocab.${TRG}.spm --dim-vocabs 32768 32768 \
    --max-length 200 \
    --exponential-smoothing \
    --mini-batch-fit -w 9000 --mini-batch 1000 --maxi-batch 1000 --devices $GPUS --sync-sgd --optimizer-delay 2 \
    --learn-rate 0.0003 --lr-report --lr-warmup 16000 --lr-decay-inv-sqrt 32000 \
    --cost-type ce-mean-words \
    --optimizer-params 0.9 0.98 1e-09 --clip-norm 0 \
    --valid-freq 5000 --save-freq 5000 --disp-freq 1000 --disp-first 10 \
    --valid-metrics bleu-detok ce-mean-words \
    --valid-sets devset.{$SRC,$TRG} --valid-translation-output devset.out --quiet-translation \
    --valid-mini-batch 64 --beam-size 1 --normalize 1 \
    --early-stopping 20 \
    --overwrite --keep-best \
    --log train.log --valid-log valid.log
