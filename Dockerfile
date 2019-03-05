FROM nvidia/cuda:9.0-cudnn7-devel-ubuntu16.04

# RUN apt-get update && \
#     apt-get upgrade -y
#
# RUN apt-get update && \
#     apt-get upgrade -y && \
#     apt-get update && \
#     apt-get install -y && \
#         apt-transport-https \
#         ca-certificates \
#         software-properties-common

RUN apt-get -y update && apt-get -y upgrade

RUN apt-get -y install apt-transport-https ca-certificates software-properties-common

RUN apt-cache policy git-all && \
    apt-get update && \
    apt-get install -y git

RUN echo "deb http://repos.mesosphere.io/ubuntu/ xenial main" > /etc/apt/sources.list.d/mesosphere.list && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv E56151BF && \
    echo "deb http://deb.nodesource.com/node_6.x xenial main" > /etc/apt/sources.list.d/nodesource.list && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv 68576280

RUN echo "deb http://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1604/x86_64 /" > /etc/apt/sources.list.d/nvidia-ml.list

RUN add-apt-repository -y ppa:jonathonf/python-3.6

RUN apt-get -y update

RUN apt-get -y install libffi-dev \
  libcurl4-openssl-dev \
  libssl-dev \
  wget \
  curl \
  openssh-server \
  mesos \
  nodejs \
  rsync \
  screen \
  vim  && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir /root/.ssh && chmod 700 /root/.ssh

ADD waitForKey.sh /usr/bin/waitForKey.sh

RUN chmod 777 /usr/bin/waitForKey.sh

RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh && \
    bash Miniconda3-latest-Linux-x86_64.sh -b && \
    rm Miniconda3-latest-Linux-x86_64.sh && \
    /root/miniconda3/bin/conda create -n py36 python==3.6.7 && \
    echo ". /root/miniconda3/etc/profile.d/conda.sh && /root/miniconda3/bin/conda activate py36" > /root/.bashrc && \
    echo ". /root/.bashrc && bash -c" > /root/miniconda3/bin/entrypoint.sh
ENV PATH /root/miniconda3/envs/py36/bin:$PATH
ENV PYTHONPATH /root/miniconda3/envs/py36/lib/python3.6/site-packages

# The stock pip is too old and can't install from sdist with extras
RUN pip install --upgrade pip setuptools virtualenv awscli protobuf ipython

RUN /root/miniconda3/bin/conda create -n s3am python=2.7.15 && \
    /root/miniconda3/envs/s3am/bin/python -m pip install --upgrade pip && \
    /root/miniconda3/envs/s3am/bin/pip install s3am==2.0 && \
    ln -s /root/miniconda3/envs/s3am/bin/s3am /usr/local/bin/

ENV PATH $PATH:/usr/local/cuda/bin
ENV CUDA_HOME /usr/local/cuda
ENV LD_LIBRARY_PATH /usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:$LD_LIBRARY_PATH
RUN /root/miniconda3/bin/conda install -n py36 pytorch-nightly cudatoolkit=9.0 -c pytorch
RUN /root/miniconda3/bin/conda install -n py36 google-sparsehash -c bioconda
RUN /root/miniconda3/bin/conda install -n py36 -c anaconda pillow
RUN pip install torchnet torchviz

RUN git clone https://github.com/facebookresearch/SparseConvNet.git && \
    sed -i "s%torch.cuda.is_available()%True%g" SparseConvNet/setup.py
WORKDIR SparseConvNet
RUN python setup.py install && python examples/hello-world.py
WORKDIR /
RUN rm -r SparseConvNet

# Install statically linked version of docker client
RUN curl https://download.docker.com/linux/static/stable/x86_64/docker-18.06.1-ce.tgz          | tar -xvzf - --transform='s,[^/]*/,,g' -C /usr/local/bin/          && chmod u+x /usr/local/bin/docker

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
RUN rm -r toilsrc
RUN ln -s /root/miniconda3/envs/py36/bin/_toil_mesos_executor /usr/local/bin/
RUN ln -s /root/miniconda3/envs/py36/bin/_toil_worker /usr/local/bin/
RUN ln -s /root/miniconda3/envs/py36/bin/toil /usr/local/bin/

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

ENTRYPOINT ["sh", "/root/miniconda3/bin/entrypoint.sh"]
