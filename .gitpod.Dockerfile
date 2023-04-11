FROM gitpod/workspace-base:latest

### Docker ###
USER root
ENV TRIGGER_REBUILD=4
# https://docs.docker.com/engine/install/ubuntu/
RUN curl -o /var/lib/apt/dazzle-marks/docker.gpg -fsSL https://download.docker.com/linux/ubuntu/gpg \
    && apt-key add /var/lib/apt/dazzle-marks/docker.gpg \
    && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    && install-packages docker-ce docker-ce-cli containerd.io

RUN curl -o /usr/bin/slirp4netns -fsSL https://github.com/rootless-containers/slirp4netns/releases/download/v1.1.12/slirp4netns-$(uname -m) \
    && chmod +x /usr/bin/slirp4netns

RUN curl -o /usr/local/bin/docker-compose -fsSL https://github.com/docker/compose/releases/download/1.29.2/docker-compose-Linux-x86_64 \
    && chmod +x /usr/local/bin/docker-compose

# share env see https://github.com/gitpod-io/workspace-images/issues/472
RUN echo "PATH="${PATH}"" | sudo tee /etc/environment

RUN apt update && apt install fzf -y && apt install bat -y
USER gitpod
RUN mkdir -p ~/.local/bin && ln -s /usr/bin/batcat ~/.local/bin/bat
RUN echo "export PATH=~/.local/bin:/workspace/kafka-docker-playground/scripts/cli:$PATH"  >> ~/.bashrc
RUN echo "source /workspace/kafka-docker-playground/scripts/cli/completions.bash"  >> ~/.bashrc

# Install Confluent Cloud CLI, with shell auto completion
RUN mkdir -p ~/.local/share/bash-completion/
RUN curl -L --http1.1 https://cnfl.io/cli | sudo sh -s -- -b /usr/local/bin && \
    touch ~/.local/share/bash-completion/confluent && \
    confluent completion bash > ~/.local/share/bash-completion/confluent && \
    echo "source ~/.local/share/bash-completion/confluent" >> ~/.bashrc