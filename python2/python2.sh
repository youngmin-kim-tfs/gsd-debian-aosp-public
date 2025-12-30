apt install -y build-essential \
               libreadline-dev libbz2-dev libsqlite3-dev libssl-dev \
               zlib1g-dev \
               wget curl

wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tgz

tar zxvf Python-2.7.18.tgz
cd Python-2.7.18

OUT=$(pwd)/python2
./configure --prefix=${OUT} --enable-optimization
make
make install

tar czvf python2.tgz python2
mv python2.tgz ../
