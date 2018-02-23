# base things off the latest LTS Ubuntu Release (16.04)
FROM ubuntu:16.04
MAINTAINER Michael Kjellman <kjellman@apple.com>

# do base updates via apt for whatever is already installed
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update

# need to add apt repo with ubuntu 3.6 as it's not available by default
# in the stock ubuntu 16.04 apt repos (seems a questionable python 3.5 is all you get)
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common
RUN add-apt-repository ppa:jonathonf/python-3.6
 
# install our python depenedncies and some other stuff we need
# libev4 libev-dev are for the python driver
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y git-core python2.7 python3.6 python3.6-venv python3.6-dev net-tools vim man libev4 libev-dev wget gcc

# solves warning: "jemalloc shared library could not be preloaded to speed up memory allocations"
RUN apt-get install -y --no-install-recommends libjemalloc1

# because we're using ubuntu 16.04 lts, there isn't a pip module for python 3.6 in apt
# we need to bootstrap it ourselves manually
RUN wget https://bootstrap.pypa.io/get-pip.py
RUN python3.6 get-pip.py
RUN rm -f /usr/local/bin/python3
RUN rm -f /usr/local/bin/pip3
RUN ln -s /usr/bin/python3.6 /usr/local/bin/python3
RUN ln -s /usr/local/bin/pip /usr/local/bin/pip3

RUN wget https://github.com/Yelp/dumb-init/releases/download/v1.2.1/dumb-init_1.2.1_amd64.deb
RUN dpkg -i dumb-init_1.2.1_amd64.deb

# as we only need the requirements.txt file from the dtest repo, let's just get it from GitHub as a raw asset
# so we can avoid needing to clone the entire repo just to get this file
# RUN git clone --single-branch --depth 1 https://github.com/apache/cassandra-dtest.git ~/cassandra-dtest
# ADD https://raw.githubusercontent.com/apache/cassandra-dtest/master/requirements.txt /opt
ADD https://raw.githubusercontent.com/mkjellman/cassandra-dtest/dtests_on_pytest_v2/requirements.txt /opt
RUN chmod 0644 /opt/requirements.txt

# now setup python via viraualenv with all of the python dependencies we need according to requirements.txt
RUN pip3 install virtualenv
RUN pip3 install --upgrade wheel

# next we'll add java to our image.. unfortunately, Oracle prevents their Java distributions
# from being included into a Docker image due to a provision in their license that the 
# license agreement much be manually accepted by a human when the JDK is downloaded.
# So, instead I've built custom OpenJDK builds for both JDK7 and JDK8 from the current 
# OpenJDK Mercurial branches. I did this because it's always a box of chocolates when
# you take other random OpenJDK builds from apt repos/the web -- so with these I know exactly
# what they were built off of and I have confidence that C* will run cleanly with these builds.

# upgrade dtests still run C* 2.0 which needs JDK7, so yes, we need a JDK7 build still
ADD resources/openjdk7u82-cassandra-b02.tar.gz /usr/local 

# openjdk 8
ADD resources/openjdk8u154-cassandra-b02.tar.gz /usr/local

# get Ant 1.10.1 (explicitly downloading it cuz who know's what version is in the apt repo)
# due to the way ADD works in docker right now, we have to specify a .tar.gz artifact in git
# and can't specify the url (ADD with a url will just essentially do what COPY does and put
# the unexpanded tar.gz into the destination dir). But we don't want to use COPY as we can't
# remove the file later from other layers.. so for now let's just check in a static copy
# of the .tar.gz.. sigh
ADD resources/apache-ant-1.10.1-bin.tar.gz /usr/local

# setup our user -- if we don't do this docker will default to root and Cassandra will fail to start
# as we appear to have a check that the user isn't starting Cassandra as root
RUN apt-get install sudo && \
    adduser --disabled-password --gecos "" cassandra && \
    echo "cassandra ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/cassandra && \
    chmod 0440 /etc/sudoers.d/cassandra

# fix up permissions on the cassandra home dir
RUN chown -R cassandra:cassandra /home/cassandra

# switch to the cassandra user... we are all done running things as root
USER cassandra
ENV HOME /home/cassandra
WORKDIR /home/cassandra

# Add enviornment variables for Ant and Java and add them to the PATH
RUN echo 'export ANT_HOME=/usr/local/apache-ant-1.10.1' >> /home/cassandra/.bashrc
RUN echo 'export JAVA_HOME=/usr/local/openjdk8u154-cassandra-b02' >> /home/cassandra/.bashrc
RUN echo 'export PATH=$PATH:$ANT_HOME/bin:$JAVA_HOME/bin' >> /home/cassandra/.bashrc

# run pip commands and setup virtualenv (note we do this after we switch to cassandra user so we 
# setup the virtualenv for the cassandrauser and not the root user by acident)
RUN virtualenv --python=python3.6 --no-site-packages env
RUN chmod +x env/bin/activate
RUN /bin/bash -c "source ~/env/bin/activate && pip3.6 install Cython && pip3.6 install -r /opt/requirements.txt && pip3.6 freeze --user"

# we need to make SSH less strict to prevent various dtests from failing when they attempt to
# git clone a given commit/tag/etc
# upgrading node1 to github:apache/18cdd391ec27d16daf775f928902f5a421c415e3
# git@github.com:apache/cassandra.git github:apache/18cdd391ec27d16daf775f928902f5a421c415e3
# 23:47:08,993 ccm INFO Cloning Cassandra...
# The authenticity of host 'github.com (192.30.253.112)' can't be established.
# RSA key fingerprint is SHA256:nThbg6kXUpJWGl7E1IGOCspRomTxdCARLviKw6E5SY8.
# Are you sure you want to continue connecting (yes/no)? 
RUN mkdir ~/.ssh
RUN echo 'Host *\n UserKnownHostsFile /dev/null\n StrictHostKeyChecking no' > ~/.ssh/config
RUN chown cassandra:cassandra ~/.ssh
RUN chown cassandra:cassandra ~/.ssh/config
RUN chmod 600 ~/.ssh/config

# mark "/tmp" as a volume so it will get mounted as an ext4 mount and not 
# the stupid aufs/CoW stuff that the actual docker container mounts will have.
# we've been seeing 3+ minute hangs when calling sync on an aufs backed mount
# so it greatly makes tests flaky as things can hang basically anywhere
VOLUME ["/tmp"]
