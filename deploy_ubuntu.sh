#!/bin/bash

############################################
#     VARIABLES
############################################
source .env
ADD_USER_TO_SUDOERS=1

SET_USER_PASSWORD=1
SET_ROOT_PASSWORD=1

INSTALL_EXTRA_TOOLS=1

DISABLE_IPV6=1

INSTALL_DOCKER=1
INSTALL_PYTHON=0
INSTALL_NPM=1
INSTALL_CLINE=1 # requires INSTALL_NPM

INSTALL_REPO_CONFIGS=0 # requires INSTALL_SSH
INSTALL_REPO_SCRIPTS=0 # requires INSTALL_SSH

CONFIG_GIT=0

############################################
# END OF USER editable section
############################################

# ANSI color macros
BLACK='\e[30m'
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
MAGENTA='\e[35m'
CYAN='\e[36m'
WHITE='\e[37m'
RESET='\e[0m'

display_banner() {
    local text="$*"
    echo -e "${GREEN}########################################${RESET}"
    echo -e "${GREEN}#     ${YELLOW}${text}${RESET}"
    echo -e "${GREEN}########################################${RESET}"
}

############################################
#     ENVIRONMENT DETECTION
############################################
# Detect the Windows environment this script is running in:
#   ENV_TYPE="wsl"     -> Windows Subsystem for Linux
#   ENV_TYPE="windows" -> Windows native (MSYS2 / Git Bash / Cygwin)
#   ENV_TYPE="linux"   -> regular (non-Windows) Linux
ENV_TYPE="linux"
if [ -n "$WSL_DISTRO_NAME" ] || [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    ENV_TYPE="wsl"
elif [ -n "$MSYSTEM" ] || [ -n "$CYGWIN" ]; then
    ENV_TYPE="windows"
else
    case "$(uname -o 2>/dev/null)" in
        Mingw*|Cygwin*) ENV_TYPE="windows" ;;
    esac
fi

display_banner "Detected environment: $ENV_TYPE"

############################################
#     ADD_USER_TO_SUDOERS
############################################
if [ "$ADD_USER_TO_SUDOERS" = 1 ]; then
    display_banner ADD_USER_TO_SUDOERS
    # Create a dedicated directive under /etc/sudoers.d granting passwordless sudo to the current user
    echo "$USER    ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$USER" > /dev/null
    sudo chmod 0440 "/etc/sudoers.d/$USER"
    sudo visudo -c -f "/etc/sudoers.d/$USER" || { sudo rm -f "/etc/sudoers.d/$USER"; echo "ERROR: invalid sudoers directive - removed /etc/sudoers.d/$USER" >&2; exit 1; }
fi

############################################
#     SET_USER_PASSWORD
############################################
if [ "$SET_USER_PASSWORD" = 1 ]; then
    display_banner SET_USER_PASSWORD
    if [ -z "$USER_PASSWORD" ]; then
        echo -e "${RED}ERROR: USER_PASSWORD is not defined in .env${RESET}" >&2
        exit 1
    fi
    echo -e New password for user ${CYAN}${USER}${RESET}: ${RED}${USER_PASSWORD}${RESET}
    # chpasswd reads user:password pairs from stdin - fully non-interactive
    printf '%s\n' "$USER:$USER_PASSWORD" | sudo chpasswd
fi

############################################
#     SET_ROOT_PASSWORD
############################################
if [ "$SET_ROOT_PASSWORD" = 1 ]; then
    display_banner SET_ROOT_PASSWORD
    if [ -z "$ROOT_PASSWORD" ]; then
        echo -e "${RED}ERROR: ROOT_PASSWORD is not defined in .env${RESET}" >&2
        exit 1
    fi
    echo -e New password for user ${CYAN}root${RESET}: ${RED}${ROOT_PASSWORD}${RESET}
    printf '%s\n' "root:$ROOT_PASSWORD" | sudo chpasswd
fi

############################################
#     DISABLE_IPV6
############################################
if [ "$DISABLE_IPV6" = 1 ]; then
    display_banner DISABLE_IPV6
    # Prevent the ipv6 kernel module from loading at boot (takes effect next boot)
    printf 'alias net-pf-10 off\noptions ipv6 off\n' | sudo tee /etc/modprobe.d/disable-ipv6.conf > /dev/null
    # Disable IPv6 at kernel level: persistent config, applied to the running system too
    printf 'net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1\nnet.ipv6.conf.lo.disable_ipv6 = 1\n' | sudo tee /etc/sysctl.d/99-disable-ipv6.conf > /dev/null
    sudo sysctl -p /etc/sysctl.d/99-disable-ipv6.conf
fi

############################################
#     UPDATE PACKAGES
############################################
display_banner UPDATE PACKAGES
sudo apt update
sudo apt upgrade -y

############################################
#     BASIC TOOLS
############################################
display_banner BASIC TOOLS
sudo apt install nano curl htop grep ncdu dos2unix net-tools -y

############################################
#     INSTALL_EXTRA_TOOLS
############################################
if [ "$INSTALL_EXTRA_TOOLS" = 1 ]; then
    display_banner "INSTALL_EXTRA_TOOLS"
    sudo apt install wget git lazygit mc btop rar unrar zip links2 traceroute iperf -y
    curl -fsSL https://herdr.dev/install.sh | sh
fi

############################################
#     INSTALL_DOCKER
############################################
if [ "$INSTALL_DOCKER" = 1 ] && [ "$ENV_TYPE" = "linux" ]; then
    display_banner INSTALL_DOCKER
    # https://docs.docker.com/engine/install/ubuntu/
    sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc | cut -f1)

    # Add Docker's official GPG key:
    sudo apt update
    sudo apt install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
    Types: deb
    URIs: https://download.docker.com/linux/ubuntu
    Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
    Components: stable
    Architectures: $(dpkg --print-architecture)
    Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update
    sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
elif [ "$INSTALL_DOCKER" = 1 ] && [ "$ENV_TYPE" = "wsl" ]; then
    display_banner "INSTALL_DOCKER - WSL"
    echo -e "${YELLOW}WARNING: in WSL, Docker must run from the Windows side (Docker Desktop) with WSL integration enabled for this distro.${RESET}"
    echo -e "${YELLOW}  Without it, the 'docker' command will not be found inside this distro. Reference:${RESET}"
    echo -e "${YELLOW}  https://stackoverflow.com/questions/72483632/ubuntu-error-the-command-docker-could-not-be-found-in-this-wsl-2-distro${RESET}"
fi

# # missing add ssh keys

############################################
#     INSTALL_NPM
############################################
if [ "$INSTALL_NPM" = 1 ]; then
    display_banner INSTALL_NPM
    sudo apt install npm -y

    ############################################
    #     INSTALL_CLINE
    ############################################
    if [ "$INSTALL_CLINE" = 1 ]; then
        display_banner INSTALL_CLINE
        sudo npm install -g cline -y
    fi
fi

############################################
#     AUTOREMOVE
############################################
display_banner AUTOREMOVE
sudo apt autoremove -y