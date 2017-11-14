# base things off the latest LTS Ubuntu Release (16.04)
FROM ubuntu:16.04

# do base updates via apt for whatever is already installed
RUN apt-get update

# install our python depenedncies and some other stuff we need
RUN apt-get install -y git-core python python-pip python-dev net-tools vim man

# stop pip from bitching that it's out of date - looks like LTS is still publishing 8.1.1 as latest
RUN pip install --upgrade pip

# as we only need the requirements.txt file from the dtest repo, let's just get it from GitHub as a raw asset
# so we can avoid needing to clone the entire repo just to get this file
# RUN git clone --single-branch --depth 1 https://github.com/apache/cassandra-dtest.git ~/cassandra-dtest
ADD https://raw.githubusercontent.com/apache/cassandra-dtest/master/requirements.txt /opt

# now setup python via viraualenv with all of the python dependencies we need according to requirements.txt
RUN pip install virtualenv

RUN virtualenv --python=python2 --no-site-packages venv
RUN /bin/bash -c "source venv/bin/activate"
RUN pip install -r /opt/requirements.txt
RUN pip freeze

# next we'll add java to our image.. unfortunately, Oracle prevents their Java distributions
# from being included into a Docker image due to a provision in their license that the 
# license agreement much be manually accepted by a human when the JDK is downloaded.
# So, instead I've built custom OpenJDK builds for both JDK7 and JDK8 from the current 
# OpenJDK Mercurial branches. I did this because it's always a box of chocolates when
# you take other random OpenJDK builds from apt repos/the web -- so with these I know exactly
# what they were built off of and I have confidence that C* will run cleanly with these builds.
 
# upgrade dtests still run C* 2.0 which needs JDK7, so yes, we need a JDK7 build still 
COPY resources/openjdk7u82-cassandra-b02.tar.gz /tmp/
RUN tar -zxvf /tmp/openjdk7u82-cassandra-b02.tar.gz -C /usr/local
RUN rm /tmp/openjdk7u82-cassandra-b02.tar.gz

# openjdk 8
COPY resources/openjdk8u154-cassandra-b02.tar.gz /tmp/
RUN tar -zxvf /tmp/openjdk8u154-cassandra-b02.tar.gz -C /usr/local
RUN rm /tmp/openjdk8u154-cassandra-b02.tar.gz

# get Ant 1.10.1 (explicitly downloading it cuz who know's what version is in the apt repo)
ADD http://apache.mirrors.pair.com/ant/binaries/apache-ant-1.10.1-bin.tar.gz /tmp/
RUN tar -zxvf /tmp/apache-ant-1.10.1-bin.tar.gz -C /usr/local
RUN rm /tmp/apache-ant-1.10.1-bin.tar.gz

# add our python script we use to merge all the individual .xml files genreated by surefire 
# from the unit tests and nosetests for the dtests into a single consolidated test results file
COPY resources/merge_junit_results.py /opt

