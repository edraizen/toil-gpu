FROM nvidia/cuda:10.0-cudnn7-devel-ubuntu16.04

RUN apt-get -y update && apt-get -y upgrade

RUN apt-get -y install apt-transport-https ca-certificates software-properties-common

RUN echo "deb http://repos.mesosphere.io/ubuntu/ xenial main"         > /etc/apt/sources.list.d/mesosphere.list         && apt-key adv --keyserver keyserver.ubuntu.com --recv E56151BF         && echo "deb http://deb.nodesource.com/node_6.x xenial main"         > /etc/apt/sources.list.d/nodesource.list         && apt-key adv --keyserver keyserver.ubuntu.com --recv 68576280

RUN add-apt-repository -y ppa:jonathonf/python-3.6

RUN apt-get -y update

RUN apt-get -y install libffi-dev python3.6 python3.6-dev python-dev python3-dev python-pip python3-pip libcurl4-openssl-dev libssl-dev wget curl openssh-server mesos=1.0.1-2.0.94.ubuntu1604 nodejs rsync screen tmux vim  && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir /root/.ssh &&         chmod 700 /root/.ssh

ADD waitForKey.sh /usr/bin/waitForKey.sh

RUN chmod 777 /usr/bin/waitForKey.sh

RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
RUN bash Miniconda3-latest-Linux-x86_64.sh -b
ENV PATH=/root/anaconda/bin:$PATH

# The stock pip is too old and can't install from sdist with extras
RUN pip install --upgrade pip==9.0.1

# Default setuptools is too old
RUN pip install --upgrade setuptools==36.5.0

# Include virtualenv, as it is still the recommended way to deploy pipelines
RUN pip install --upgrade virtualenv==15.0.3

# Install s3am (--never-download prevents silent upgrades to pip, wheel and setuptools)
RUN virtualenv --never-download /home/s3am         && /home/s3am/bin/pip install s3am==2.0         && ln -s /home/s3am/bin/s3am /usr/local/bin/

RUN pip install awscli --upgrade

# Install statically linked version of docker client
RUN curl https://download.docker.com/linux/static/stable/x86_64/docker-18.06.1-ce.tgz          | tar -xvzf - --transform='s,[^/]*/,,g' -C /usr/local/bin/          && chmod u+x /usr/local/bin/docker

# Fix for Mesos interface dependency missing on ubuntu
RUN pip install protobuf==3.0.0

# Fix for https://issues.apache.org/jira/browse/MESOS-3793
ENV MESOS_LAUNCHER=posix

# Fix for `screen` (https://github.com/BD2KGenomics/toil/pull/1386#issuecomment-267424561)
ENV TERM linux

# Run bash instead of sh inside of screen
ENV SHELL /bin/bash
RUN echo "defshell -bash" > ~/.screenrc

# An appliance may need to start more appliances, e.g. when the leader appliance launches the
# worker appliance on a worker node. To support this, we embed a self-reference into the image:
ENV TOIL_APPLIANCE_SELF edraizen/toil-gpu:latest

RUN mkdir /var/lib/toil

ENV TOIL_WORKDIR /var/lib/toil

RUN git clone https://github.com/edraizen/toil.git toilsrc
WORKDIR toilsrc
RUN pip install .[all]
WORKDIR /
WORKDIR rm -r toilsrc

# We intentionally inherit the default ENTRYPOINT and CMD from the base image, to the effect
# that the running appliance just gives you a shell. To start the Mesos master or slave
# daemons, the user # should override the entrypoint via --entrypoint.

RUN echo '[ ! -z "$TERM" -a -r /etc/motd ] && cat /etc/motd' >> /etc/bash.bashrc         && printf '\n\
This is the Toil appliance. You can run your Toil script directly on the appliance.\n\
Run toil <workflow>.py --help to see all options for running your workflow.\n\
For more information see http://toil.readthedocs.io/en/latest/\n\
\n\
Copyright (C) 2015-2018 Regents of the University of California\n\
\n\
Version: edraizen/toil-gpu:latest\n\
\n\
' > /etc/motd

RUN apt-get -y update && apt-get -y upgrade

RUN conda install pytorch-nightly cudatoolkit=9.0 -c pytorch
RUN conda install google-sparsehash -c bioconda
RUN conda install -c anaconda pillow

RUN git clone https://github.com/facebookresearch/SparseConvNet.git
WORKDIR SparseConvNet
RUN sed -i "s%torch.cuda.is_available()%True%g" setup.py
RUN bash build.sh

WORKDIR /
