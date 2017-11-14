FROM ubuntu:16.04

RUN apt-get update
RUN apt-get install -y git-core npm python python-pip python-dev ant ant-optional net-tools vim man

RUN pip install virtualenv

RUN git clone --single-branch --depth 1 https://github.com/apache/cassandra-dtest.git ~/cassandra-dtest

RUN virtualenv --python=python2 --no-site-packages venv
RUN source venv/bin/activate
RUN pip install -r ~/cassandra-dtest/requirements.txt
RUN pip freeze

