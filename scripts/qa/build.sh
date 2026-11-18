#!/bin/zsh
# Compiles the QA helpers into .build/qa (ignored by git). Re-run after editing any .swift here.
set -e
cd "${0:A:h}"
OUT=../../.build/qa
mkdir -p $OUT
for f in *.swift; do
  name=${f:r}
  if [ ! -x $OUT/$name ] || [ $f -nt $OUT/$name ]; then swiftc -O $f -o $OUT/$name; fi
done
cp -f qa.sh $OUT/qa && chmod +x $OUT/qa
echo "QA tools in .build/qa: $(ls $OUT | tr '\n' ' ')"
