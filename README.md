# Local Genome Browser

Recipe to make a local UCSC Genome Browser instance for debugging HAL / Snake Tracks

## Why?

I want to patch the part of the [HAL API](https://github.com/ComparativeGenomicsToolkit/hal) that serves the Snake Tracks Track Hubs on the Genome Browser. The only way to test this in practice is to rebuild the Browser, linking to the updated HAL.  I had a tough time doing this in my Ubuntu desktop.

## Challenges

* Building the [Kent Source](https://github.com/ucscGenomeBrowser/kent) on Ubuntu 22.04 isn't easy. As far as I can tell it wants older versions openssl and mysql then are available from `apt` in this OS.  It also wants to write output binaries in various system-level places.  Linking in HAL (which is optional in general but necessary for me) only complicates matters.
* Running the Browser itself is nontrivial, requiring the setup of an Apache web server, mySQL database, and various data files needed to get a mirror going.
* Track hubs (which I need to debug) must be specified via HTTP URL, but my usual public hubs are too slow to be used from my home network.

## Idea

* Use Docker to make a virtual environment where the Browser builds and runs okay (I'm using `ubuntu:18.04`)
* Use the [Genome Browser in the Cloud (GBIC)](https://genome.ucsc.edu/goldenpath/help/gbic.html) script to easily set up a browser (in the Docker container) using pre-compiled binaries
* Build the source within the container, linking in a modified HAL as needed, and overwrite only the pertinent binaries in the GBIC installation

## Instructions

### Build the Docker image

Most of the action happens within the [Dockerfile](./Dockerfile). To build the Docker image, you need to first download the `browserSetup.sh` script and copy it into this repo.  I'd like to just include it here, but it's not open source (though it is free for non-commercial use). Ex. (assuming you downloaded the script to `~/Downloads`:

```
git clone https://github.com/glennhickey/local-browser.git
cd local-browser
cp ~/Downloads/browserSetup.sh .
```

In order to get this working at all in Docker, I had to add `service start mysql` on line `1146` of the `browserSetup.sh` script.  ie change

```
   echo2
   echo2 The Mysql server was installed and therefore has an empty root password.
   echo2 Trying to set mysql root password to the randomly generated string '"'$MYSQLROOTPWD'"'

   # now set the mysql root password
   if $MYSQLADMIN -u root password $MYSQLROOTPWD; then
```
to
```
   echo2
   echo2 The Mysql server was installed and therefore has an empty root password.
   echo2 Trying to set mysql root password to the randomly generated string '"'$MYSQLROOTPWD'"'

   # hack
   service mysql start
   
   # now set the mysql root password
   if $MYSQLADMIN -u root password $MYSQLROOTPWD; then

```

Finally, I had issues with the mySQL database when building the container on my own machine (`Docker version 20.10.25, build 20.10.25-0ubuntu1~22.04.1`) so I built it on mustard.prism (`Docker version 24.0.5, build ced0996`) where it seemed to work OK:

```
docker build . -t quay.io/glennhickey/local-browser:latest
docker push
```

### Download the hub

Make sure to download the track hub (ie from `hal2assemblyhub.py`) locally.  Below, I assume it's copied into the `local-browser` folder but it can be anywhere so long as its accessible to Docker via `docker run -v`.

### Start the Browser Container Locally

On my Desktop, I start the container with

```
docker run -it --name browser-test -p 8000:80 -v $(pwd):/data quay.io/glennhickey/local-browser:latest bash
```

Then inside the container, I start three services.  The apache server on port 80, accessible from outside the container on 8000, the mysql server, and a simple webserver to give the hub a URL, in this case on port 9000.

For the latter, I use Ruby because it supports HTTP Range Requests and runs fine on Ubuntu:18.04.

```
service apache start
service mysql start
cd /data
ruby -rwebrick -e'WEBrick::HTTPServer.new(:Port => 9000, :DocumentRoot => Dir.pwd).start'
```

### Start the Local Browser

Visit `127.0.0.1:8000` in a Web Browser.  Click `My Data` on the top then `Track Hubs`.  The screen will go blank for a few minutes the first time you do this as the GBIC installation apparently needs to pull in some files when loading this page the first time.

Eventually the menu will come up.  Click `Connected Hubs` on the middle tab near the top.  Paste in the URL for your local hub, where the path is relative to /data.  For example, `0.0.0.0:9000/test-hub/hub.txt`).

Important: if your hub has a reference that is not hg38 but the Browser still recognizes, you may be in trouble. In my case, I wanted to use `hs1` as a reference but was unable to as the Browser expected but couldn't find a bunch of local hub files in `/gbdb`).  I worked around this by renaming `hs1` to `human`.

### Updating HAL

Right now, the browser is running 100% from the GBIC installation. Everything compiled in the Docker image is ignored.  To swap in a local HAL repo (let's assume it's installed in `/home/hickey/dev/hal`), run from `local-browser/` (note: `browser-test` was specified using `--name` above):

```
cp -r /home/hickey/dev/hal/blockViz .
docker exec -it browser-test bash -c 'mv /hive/groups/browser/hal/build/hal.2020-12-18/hal/blockViz /hive/groups/browser/hal/build/hal.2020-12-18/hal/blockViz.bak ; cp -r /data/blockViz  /hive/groups/browser/hal/build/hal.2020-12-18/hal ; cd /hive/groups/browser/hal/build/hal.2020-12-18/hal/ ;  export PATH=/hive/groups/browser/hal/build/hdf5-1.12.0/local/bin:$PATH && export ENABLE_UDC=1 && export KENTSRC=/kent/src && make -j8 ; cd /kent && cd src ; make clean ; make -j8 libs ; cd hg ; make -j8 ; cd ../utils ; make -j8 ; cp /usr/local/apache/cgi-bin-docker/hg* /usr/local/apache/cgi-bin/'
```

This will patch the `blockViz` directory in the container's HAL, rebuild that HAL, rebuild the container's Browser linking to the patched HAL, then copy over the binaries into the GBIC browser's cgi-bin.  Once it's done, your browser (that you connected to above at `127.0.0.1:8000`) will use the new HAL the next time you refresh or click anything.

You might get a "FreeType" related error the first time you do this.  If that happens, run

```
docker exec -it browser-test bash -c "sed -i /usr/local/apache/cgi-bin/hg.conf -e 's/freeType=on/freeType=off/g'"
```