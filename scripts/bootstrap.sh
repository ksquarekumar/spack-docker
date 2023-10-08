#!/bin/bash
##
## # Copyright © 2023 krishnakumar <ksquarekumar@gmail.com>.
## #
## # Licensed under the Apache License, Version 2.0 (the "License"). You
## # may not use this file except in compliance with the License. A copy of
## # the License is located at:
## #
## # https://github.com/ksquarekumar/jupyter-docker/blob/main/LICENSE
## #
## # or in the "license" file accompanying this file. This file is
## # distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
## # ANY KIND, either express or implied. See the License for the specific
## # language governing permissions and limitations under the License.
## #
## # This file is part of the jupyter-docker project.
## # see (https://github.com/ksquarekumar/jupyter-docker)
## #
## # SPDX-License-Identifier: Apache-2.0
## #
## # You should have received a copy of the APACHE LICENSE, VERSION 2.0
## # along with this program. If not, see <https://apache.org/licenses/LICENSE-2.0>
##
set -eux

# shellcheck source=/dev/null
source /etc/environment

# globals
SCRIPTNAME=$0
APP_ROOT="$(dirname "$(dirname "$(readlink -fm "${SCRIPTNAME}")")")"
export SPACK_RELEASE=${SPACK_RELEASE:-"tags/v0.20.2"}

APT_SOURCES_FILE="/etc/apt/sources.list"
APT_FAST_CONF_FILE="/etc/apt-fast.conf"
KERNEL_OPTS_SCRIPT="/${APP_ROOT}/scripts/tune_kernel_opts.py"
export HADOLINT_VERSION=${HADOLINT_VERSION:-"2.12.0"}
export JAVA_VERSION=${JAVA_VERSION:-"openjdk-19"}
export NPM_CACHE_DIR="${HOME}/.cache/npm-cache"
export YARN_CACHE_DIR="${HOME}/.cache/yarn-cache"

# options
export MAXIMUM_MIRRORS=${MAXIMUM_MIRRORS:-4}
export DEBIAN_FRONTEND="noninteractive"

PHASE="installing base packages for setup..."
echo "${PHASE}"
(apt-get update -o Acquire::CompressionTypes::Order::=gz -q > /dev/null \
  && apt-get install -y -q \
    --no-install-suggests \
    --no-install-recommends \
    python3-full \
    python-is-python3 \
    python3-distutils \
    python3-venv \
    python3-pip \
    python3-openssl \
    python3-dev \
    python3-dotenv \
    python3-psutil \
    python3-joblib \
    python3-regex \
    python3-tqdm \
    python3-rich \
    python3-click \
    python3-cffi \
    python3-cffi-backend \
    glances \
    wget \
    sudo \
    procps \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    tzdata \
    fontconfig \
    locales) || (echo "failed ${PHASE}" && exit 1)

# Set the release name variable
if command -v lsb_release > /dev/null; then
  echo "lsb_release found, using distribution release..."
  # shellcheck disable=SC2005
  RELEASE_CODENAME="$(echo "$(lsb_release --codename)" | awk '{print $2}')"
else
  echo "lsb_release not found, exiting(!)" && exit 1
fi

# install apt-smart package
if command -v pip > /dev/null; then
  echo "system pip found, installing apt-smart and glances package(s)..."
  (pip install --no-cache-dir --upgrade -q apt-smart "glances[all]") || exit 1
else
  echo "pip not found, installing python3-pip, exiting(!)" && exit 1
fi

# Fetch the list of Ubuntu mirrors and measure download speeds
# shellcheck disable=SC2016
PHASE="searching for fastest package source mirror(s)..."
echo "${PHASE}"

GET_BEST_MIRRORS="$(apt-smart -l -x "*coganng*" -x "*ports*" -x "*heanet*")"
FASTEST_MIRRORS=$(echo "${GET_BEST_MIRRORS}" | tr '\n' ', ' | cut -d ',' -f "1-${MAXIMUM_MIRRORS}")

printf "fastest package source mirrors:\n%s" "${GET_BEST_MIRRORS}"
printf "updating %s with fastest package source mirrors:\n%s" "${APT_SOURCES_FILE}" "${GET_BEST_MIRRORS}"

if [[ -f "$APT_SOURCES_FILE" ]]; then
  (cp "$APT_SOURCES_FILE" "$APT_SOURCES_FILE.bak") || exit 1
  (echo '' > "$APT_SOURCES_FILE") || exit 1
  # Set the IFS to a comma to split the string into an array
  IFS=',' read -ra FASTEST_MIRRORS_ARRAY <<< "$FASTEST_MIRRORS"
  (for SELECTED_MIRROR in "${FASTEST_MIRRORS_ARRAY[@]}"; do
    {
      echo "deb ${SELECTED_MIRROR} ${RELEASE_CODENAME} main restricted"
      echo "deb ${SELECTED_MIRROR} ${RELEASE_CODENAME} universe"
      echo "deb ${SELECTED_MIRROR} ${RELEASE_CODENAME} multiverse"
      echo "deb ${SELECTED_MIRROR} ${RELEASE_CODENAME}-updates main restricted"
      echo "deb ${SELECTED_MIRROR} ${RELEASE_CODENAME}-updates universe"
      echo "deb ${SELECTED_MIRROR} ${RELEASE_CODENAME}-updates multiverse"
      echo "deb ${SELECTED_MIRROR} ${RELEASE_CODENAME}-backports main restricted universe multiverse"
      echo "deb ${SELECTED_MIRROR} ${RELEASE_CODENAME}-security main restricted"
      echo "deb ${SELECTED_MIRROR} ${RELEASE_CODENAME}-security universe"
      echo "deb ${SELECTED_MIRROR} ${RELEASE_CODENAME}-security multiverse"
    } >> "$APT_SOURCES_FILE"
  done) || (echo "failed ${PHASE}" && exit 1)
else
  echo "Error: $APT_SOURCES_FILE not found, exiting(!)" && exit 1
fi
printf "successfully updated %s with fastest package source mirrors" "${APT_SOURCES_FILE}"

# Refresh the package cache and install apt-fast
PHASE="installing & configuring apt-fast package manager..."
echo "${PHASE}"
(add-apt-repository ppa:apt-fast/stable -y \
  && apt-get update -o Acquire::CompressionTypes::Order::=gz -q > /dev/null \
  && apt-get install -y -q --no-install-suggests --no-install-recommends apt-fast \
  && echo debconf apt-fast/maxdownloads string 16 | debconf-set-selections \
  && echo debconf apt-fast/dlflag boolean true | debconf-set-selections \
  && echo debconf apt-fast/aptmanager string apt | debconf-set-selections \
  && echo debconf apt-fast/downloadbefore boolean false | debconf-set-selections) || (echo "failed ${PHASE}" && exit 1)

# Update the apt-fast.conf file with the fastest mirrors
printf "updating apt-fast configuration at %s with fastest mirrors" "${APT_FAST_CONF_FILE}..."
printf "updating apt-fast mirrors to: %s in file: %s" "${FASTEST_MIRRORS}" "${APT_FAST_CONF_FILE}"
if [[ -f "$APT_FAST_CONF_FILE" ]]; then
  sed -i.bak s#'MIRRORS=\(.*\)'#"MIRRORS=( '${FASTEST_MIRRORS}' )#g" "${APT_FAST_CONF_FILE}" || ( echo "failed to edit ${APT_FAST_CONF_FILE}, exiting" && exit 1 )
else
  echo "Error: ${APT_FAST_CONF_FILE} not found, exiting(!)" && exit 1
fi

# do in-place system upgrade
printf "performing distribution-upgrade for %s %s kernel: %s version: %s codename: %s..." "$(uname -o)" "$(uname -m)" "$(uname -r)" "$(uname -v)" "${RELEASE_CODENAME}"
apt-fast update -o Acquire::CompressionTypes::Order::=gz -q > /dev/null \
  && apt-fast upgrade -y -q

# prep for future installables
PHASE="creating directories for installable packages..."
echo "${PHASE}"
/bin/bash -c "${KERNEL_OPTS_SCRIPT}"
# shellcheck source=/dev/null
source /etc/environment
printf "+ OMP_NUM_THREADS: %s" "${OMP_NUM_THREADS}"
(mkdir -p /etc/apt/keyrings \
  && mkdir -p /opt/jupyter \
  && mkdir -p /var/lock/apache2 \
    /var/run/apache2 \
    /var/run/sshd \
    /var/log/supervisor \
  && chmod -R 0777 /opt \
  && install -m 0755 -d /etc/apt/keyrings) || (echo "failed ${PHASE}" && exit 1)

# register addtional package sources
PHASE="registering addtional package sources..."
echo "${PHASE}"
# shellcheck source=/dev/null
(curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [trusted=yes signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor -o /etc/apt/keyrings/yarnpkg.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/yarnpkg.gpg] https://dl.yarnpkg.com/debian/ rc main" | tee /etc/apt/sources.list.d/yarn.list \
  && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
  && chmod a+r /etc/apt/keyrings/docker.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
  && curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list \
  && curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | tee /etc/apt/trusted.gpg.d/ngrok.asc > /dev/null && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | tee /etc/apt/sources.list.d/ngrok.list \
  && apt-fast update -o Acquire::CompressionTypes::Order::=gz -q > /dev/null) || (echo "failed ${PHASE}" && exit 1)

# install requisite packages
PHASE="installing required packages..."
echo "${PHASE}"
(apt-fast install -y -q \
  --no-install-suggests \
  --no-install-recommends \
  nix \
  gfortran \
  apache2 \
  fuse3 \
  fuse2fs \
  supervisor \
  ssh \
  ssh-askpass \
  ssh-tools \
  sshfs \
  openssh-server \
  openssh-client \
  openssh-client-ssh1 \
  checkinstall \
  python3-pkgconfig \
  cmake \
  clang-15 \
  llvm-15 \
  llvm-15-linker-tools \
  llvm-15-runtime \
  unzip \
  zip \
  lzma \
  cron \
  htop \
  aria2 \
  tmux \
  zsh \
  axel \
  pkg-config \
  ncdu \
  "${JAVA_VERSION}-jre" \
  pax-utils \
  glib-networking \
  glib-networking-common \
  glib-networking-services \
  libaio1 \
  libavahi-glib1 \
  libostree-1-1 \
  libproxy1v5 \
  libslirp0 \
  libsoup2.4-1 \
  libsoup2.4-common \
  libfuse3-3 \
  libxml2 \
  libavformat-extra \
  libavcodec-extra \
  libavdevice58 \
  libavutil56 \
  libavfilter-extra \
  libswscale5 \
  libswresample3 \
  libaio-dev \
  libavformat-dev \
  libavcodec-dev \
  libavdevice-dev \
  libavutil-dev \
  libavfilter-dev \
  libswscale-dev \
  libswresample-dev \
  libfuse-dev \
  libfuse3-dev \
  multimedia-devel \
  expat \
  libuv1 \
  libxext6 \
  libxrender1 \
  libxtst6 \
  libfreetype6 \
  fonts-powerline \
  python3-powerline \
  libxi6 \
  graphviz) || (echo "failed ${PHASE}" && exit 1)

# install nodejs/npm/yarn
PHASE="installinging & configuring nodejs ecosystem..."
echo "${PHASE}"
(apt-fast install -y -q \
  --no-install-suggests \
  --no-install-recommends \
  nodejs \
  yarn \
  && apt-get remove -y -q yarn cmdtest \
  && apt-fast update -o Acquire::CompressionTypes::Order::=gz -q > /dev/null \
  && apt-fast install -y -q \
    --no-install-suggests \
    --no-install-recommends \
    nodejs \
    yarn \
  && npm config set cache "${NPM_CACHE_DIR}" --global \
  && yarn config set cache-folder "${YARN_CACHE_DIR}") || (echo "failed ${PHASE}" && exit 1)

# install docker & co.
PHASE="installing & configuring docker runtime..."
echo "${PHASE}"
(apt-fast install -y -q \
  --no-install-suggests \
  --no-install-recommends \
  crun \
  libyajl2 \
  uidmap \
  pigz \
  dns-root-data \
  dnsmasq-base \
  cgroupfs-mount \
  cgroup-lite \
  dbus-user-session \
  fuse-overlayfs \
  podman \
  conmon \
  buildah \
  golang-github-containers-common \
  golang-github-containers-image \
  golang-github-containernetworking-plugin-dnsname \
  slirp4netns \
  tini \
  catatonit \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  containernetworking-plugins \
  containers-storage \
  docker-buildx-plugin \
  docker-compose-plugin \
  docker-ce-rootless-extras \
  python3-docker \
  python3-dockerpty \
  && /usr/bin/pip3 install podman-compose \
  && (ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || true)) || (echo "failed ${PHASE}" && exit 1)

# install nvidia-docker runtime
PHASE="installing nvidia-docker runtime..."
echo "${PHASE}"
(apt-fast install -y -q \
  --no-install-suggests \
  --no-install-recommends \
  nvidia-container-toolkit \
  && nvidia-ctk runtime configure --runtime=docker \
  && nvidia-ctk runtime configure --runtime=containerd) || (echo "failed ${PHASE}" && exit 1)

# install ngrok
PHASE="installing ngrok..."
echo "${PHASE}"
(apt-fast install -y -q --no-install-suggests --no-install-recommends ngrok) || (echo "failed ${PHASE}" && exit 1)

# configuring git
PHASE="configuring git..."
echo "${PHASE}"
(git config --global credential.helper store \
  && git config --global core.filemode false) || (echo "failed ${PHASE}" && exit 1)

# installing hadolint
PHASE="installing hadolint..."
(cd /tmp \
  && wget "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-x86_64" -O hadolint \
  && mv hadolint /usr/local/bin \
  && chmod +x /usr/local/bin/hadolint
  ) || (echo "failed ${PHASE}" && exit 1)

# installing awscli
PHASE="installing aws-cli-v2..."
echo "${PHASE}"
(cd /tmp \
  && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
  && unzip -q awscliv2.zip \
  && ./aws/install \
  && rm -rf aws awscliv2.zip) || (echo "failed ${PHASE}" && exit 1)

# spack initialization
# main function
function add_spack_to_env() {
  FILE=$1
  FILE_PATH="${HOME}/${FILE}"
  ACTIVATION_PATH="${APP_ROOT}/spack/share/spack/setup-env.sh"
  arr=( "\n# >>> spack initialize >>>" "if [[ -f ${ACTIVATION_PATH} ]]; then" ". ${ACTIVATION_PATH}" "fi" "# <<< spack initialize <<<");
  printf '%s\n' "${arr[@]}" >> "${FILE_PATH}"
}
# caller function
function add_spack_to_envs() {  
  for arg in "$@"; do
  case $arg in
      bash*)
      add_spack_to_env ".bashrc"
      shift
      ;;
      zsh*)
      add_spack_to_env ".zshrc"
      shift
      ;;
    *)
      printf "Unrecognized Shell %s\n" "${arg}"
      exit 1
      ;;
  esac
done
}

# update spack and add to path
PHASE="updating spack and adding spack to path..."
echo "${PHASE}"
(cd "${APP_ROOT}" \
  && cd spack \
  && git checkout "${SPACK_RELEASE}" \
  && cd .. \
  && add_spack_to_envs "bash" "zsh"
)

echo "${SCRIPTNAME} completed succesfully" &
exit 0
