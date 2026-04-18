FROM docker.io/rocker/r-ver:4.5.0

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest
ARG NODE_MAJOR=20

# System tooling (Anthropic's reference set) + system libs for R packages
# used by this repo (ncdf4, fields, lintr).
RUN apt-get update && apt-get install -y --no-install-recommends \
    less \
    git \
    procps \
    sudo \
    fzf \
    man-db \
    unzip \
    gnupg2 \
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    aggregate \
    jq \
    nano \
    vim \
    wget \
    curl \
    ca-certificates \
    libnetcdf-dev \
    libhdf5-dev \
    libudunits2-dev \
    libuv1-dev \
    libxml2-dev \
    libssl-dev \
    libcurl4-openssl-dev \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Node.js via NodeSource (rocker base has no Node).
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI (not in Ubuntu noble's default archives as a new enough version).
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        > /etc/apt/trusted.gpg.d/githubcli.gpg \
 && echo "deb https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create the `node` user (rocker base has no equivalent).
RUN groupadd --gid 1001 node \
 && useradd --uid 1001 --gid node --shell /bin/bash --create-home node \
 && mkdir -p /usr/local/share/npm-global \
 && chown -R node:node /usr/local/share

# Persist bash history.
RUN mkdir /commandhistory \
 && touch /commandhistory/.bash_history \
 && chown -R node:node /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude /home/node/.cache/R \
 && chown -R node:node /workspace /home/node/.claude /home/node/.cache

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) \
 && wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
 && dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
 && rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Install the R packages the scripts use, plus renv (for anyone who wants
# to run `renv::restore()` manually against the committed renv.lock).
RUN R -q -e 'install.packages(c("renv","ncdf4","testthat","fields","abind","MASS","lintr"), repos = "https://cloud.r-project.org")'

# Switch to non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

ENV SHELL=/bin/bash
ENV EDITOR=nano
ENV VISUAL=nano

# Rewrite SSH GitHub URLs to HTTPS so `git clone` (used by Claude Codes plugin
# marketplace installer) doesnt need SSH keys we havent mounted.
RUN git config --global url."https://github.com/".insteadOf "git@github.com:"

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh \
 && echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall \
 && chmod 0440 /etc/sudoers.d/node-firewall
USER node
