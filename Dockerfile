# haven't had any luck building kent from ubuntu 22.04, so roll back to 18.04 which seems to work
FROM ubuntu:18.04

# Copy over the browserSetup.sh script
# note we've hacked it to add a "service mysql start" on line 1146
RUN mkdir -p /work
COPY . /work

# Make a Genome Browser in the Cloud base install
ENV DEBIAN_FRONTEND noninteractive
RUN cd work && bash browserSetup.sh -b install || true
RUN cd work && bash browserSetup.sh -b minimal hg38 || true

# these are needed to build kent
RUN apt-get update && apt-get install -y build-essential git libssl-dev libpng-dev uuid-dev libmysqlclient-dev rsync libcurl4-openssl-dev wget

# set up hdf5 where the browser expects it
RUN mkdir -p /hive  mkdir -p /hive/groups ; mkdir -p /hive/groups/browser ; mkdir -p /hive/groups/browser/hal ; mkdir -p /hive/groups/browser/hal/build ; mkdir -p /hive/groups/browser/hal/build/hdf5-1.12.0 ; mkdir -p /hive/groups/browser/hal/build/hdf5-1.12.0/local 
RUN cd /hive && wget -q https://github.com/HDFGroup/hdf5/archive/refs/tags/hdf5-1_10_2.tar.gz && tar -zxf hdf5-1_10_2.tar.gz && cd hdf5-hdf5-1_10_2 && ./configure --enable-cxx --enable-static --disable-parallel --disable-shared --prefix=/hive/groups/browser/hal/build/hdf5-1.12.0/local && make -j 8 && make install

# set up hal where the browser expects it
RUN mkdir -p /hive/groups/browser/hal/build/hal.2020-12-18 ; cd /hive/groups/browser/hal/build/hal.2020-12-18 && git clone https://github.com/ComparativeGenomicsToolkit/sonLib.git && cd sonLib && make -j8
RUN export PATH=/hive/groups/browser/hal/build/hdf5-1.12.0/local/bin:$PATH && cd /hive/groups/browser/hal/build/hal.2020-12-18 && git clone https://github.com/ComparativeGenomicsToolkit/hal.git && cd hal && make -j8

# the kent makefiles have a bunch of hardcoded output paths.  make them here or the build will fail
ENV USER docker
RUN mkdir -p /usr/local ; mkdir -p /usr/local/apache ; mkdir -p /usr/local/apache/cgi-bin-${USER} ; mkdir -p /root/bin ; mkdir -p /root/bin/x86_64

# the make instructions are from https://genome.ucsc.edu/goldenpath/help/mirrorManual.html#local-git-repository-aka-quotthe-source-treequot
# we play with inc/ocmmon.mk a bit too in order to enable HAL
RUN git clone https://github.com/ucscGenomeBrowser/kent.git && cd kent && git checkout -t -b beta origin/beta
RUN sed -i /kent/src/inc/common.mk -e '0,/ifeq (${IS_HGWDEV},yes)/! {0,/ifeq (${IS_HGWDEV},yes)/ s/ifeq (${IS_HGWDEV},yes)/ifeq (yes,yes)/}' -e 's/ -Werror//g'
RUN sed -i /kent/src/inc/common.mk -e 's#HDF5LIBDIR=${HDF5DIR}/local/lib#HDF5LIBDIR=${HDF5DIR}/local/lib\n    L+=${HALLIBS}#g'
RUN cd /kent && cd src ; make clean ; make -j8 libs ; cd hg ; make -j8 ; cd ../utils ; make -j8


# to serve the file, go in the docker container with docker exec -it <id from docker ps> bash
# then install the server
# credit https://gist.github.com/willurd/5720255
RUN apt-get install -y ruby

# then run the server with
# ruby -rwebrick -e'WEBrick::HTTPServer.new(:Port => 9000, :DocumentRoot => Dir.pwd).start'

# you can then pass the hub in the browser, with relative path to where ruby was run from, ex
# http://0.0.0.0:9000/<relative path to hub.txt>

# important, you must also start up the browser in the docker image with
# service apache2 start
# service mysql start
# and don't forget to use something like -p 8000:80 to set the port for the browser (127.0.0.1:8000)

