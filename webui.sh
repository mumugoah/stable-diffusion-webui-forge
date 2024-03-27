#!/usr/bin/env bash
#################################################
# Please do not make any changes to this file,  #
# change the variables in webui-user.sh instead #
#################################################

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# 环境准备
apt-get update
apt-get install ffmpeg libsm6 libxext6  -y

# If run from macOS, load defaults from webui-macos-env.sh
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ -f "$SCRIPT_DIR"/webui-macos-env.sh ]]
        then
        source "$SCRIPT_DIR"/webui-macos-env.sh
    fi
fi

# Read variables from webui-user.sh
# shellcheck source=/dev/null
if [[ -f "$SCRIPT_DIR"/webui-user.sh ]]
then
    source "$SCRIPT_DIR"/webui-user.sh
fi

# If $venv_dir is "-", then disable venv support
use_venv=0
if [[ $venv_dir == "-" ]]; then
  use_venv=0
fi

# Set defaults
# Install directory without trailing slash
if [[ -z "${install_dir}" ]]
then
    install_dir="$SCRIPT_DIR"
fi

# Name of the subdirectory (defaults to stable-diffusion-webui)
if [[ -z "${clone_dir}" ]]
then
    clone_dir="stable-diffusion-webui"
fi

# python3 executable
if [[ -z "${python_cmd}" ]]
then
    python_cmd="python3"
fi

# git executable
if [[ -z "${GIT}" ]]
then
    export GIT="git"
else
    export GIT_PYTHON_GIT_EXECUTABLE="${GIT}"
fi

# python3 venv without trailing slash (defaults to ${install_dir}/${clone_dir}/venv)
if [[ -z "${venv_dir}" ]] && [[ $use_venv -eq 1 ]]
then
    venv_dir="venv"
fi

if [[ -z "${LAUNCH_SCRIPT}" ]]
then
    LAUNCH_SCRIPT="launch.py"
fi

# this script cannot be run as root by default
can_run_as_root=1

# read any command line flags to the webui.sh script
while getopts "f" flag > /dev/null 2>&1
do
    case ${flag} in
        f) can_run_as_root=1;;
        *) break;;
    esac
done

# Disable sentry logging
export ERROR_REPORTING=FALSE

# Do not reinstall existing pip packages on Debian/Ubuntu
export PIP_IGNORE_INSTALLED=0

# Pretty print
delimiter="################################################################"

printf "\n%s\n" "${delimiter}"
printf "\e[1m\e[32mInstall script for stable-diffusion + Web UI\n"
printf "\e[1m\e[34mTested on Debian 11 (Bullseye), Fedora 34+ and openSUSE Leap 15.4 or newer.\e[0m"
printf "\n%s\n" "${delimiter}"

# Do not run as root
if [[ $(id -u) -eq 0 && can_run_as_root -eq 0 ]]
then
    printf "\n%s\n" "${delimiter}"
    printf "\e[1m\e[31mERROR: This script must not be launched as root, aborting...\e[0m"
    printf "\n%s\n" "${delimiter}"
    exit 1
else
    printf "\n%s\n" "${delimiter}"
    printf "Running on \e[1m\e[32m%s\e[0m user" "$(whoami)"
    printf "\n%s\n" "${delimiter}"
fi

if [[ $(getconf LONG_BIT) = 32 ]]
then
    printf "\n%s\n" "${delimiter}"
    printf "\e[1m\e[31mERROR: Unsupported Running on a 32bit OS\e[0m"
    printf "\n%s\n" "${delimiter}"
    exit 1
fi

if [[ -d .git ]]
then
    printf "\n%s\n" "${delimiter}"
    printf "Repo already cloned, using it as install directory"
    printf "\n%s\n" "${delimiter}"
    install_dir="${PWD}/../"
    clone_dir="${PWD##*/}"
fi

# Check prerequisites
gpu_info=$(lspci 2>/dev/null | grep -E "VGA|Display")
case "$gpu_info" in
    *"Navi 1"*)
        export HSA_OVERRIDE_GFX_VERSION=10.3.0
        if [[ -z "${TORCH_COMMAND}" ]]
        then
            pyv="$(${python_cmd} -c 'import sys; print(".".join(map(str, sys.version_info[0:2])))')"
            if [[ $(bc <<< "$pyv <= 3.10") -eq 1 ]] 
            then
                # Navi users will still use torch 1.13 because 2.0 does not seem to work.
                export TORCH_COMMAND="pip install --pre torch torchvision --index-url https://download.pytorch.org/whl/nightly/rocm5.6"
            else
                printf "\e[1m\e[31mERROR: RX 5000 series GPUs must be using at max python 3.10, aborting...\e[0m"
                exit 1
            fi
        fi
    ;;
    *"Navi 2"*) export HSA_OVERRIDE_GFX_VERSION=10.3.0
    ;;
    *"Navi 3"*) [[ -z "${TORCH_COMMAND}" ]] && \
         export TORCH_COMMAND="pip install --pre torch torchvision --index-url https://download.pytorch.org/whl/nightly/rocm5.7"
    ;;
    *"Renoir"*) export HSA_OVERRIDE_GFX_VERSION=9.0.0
        printf "\n%s\n" "${delimiter}"
        printf "Experimental support for Renoir: make sure to have at least 4GB of VRAM and 10GB of RAM or enable cpu mode: --use-cpu all --no-half"
        printf "\n%s\n" "${delimiter}"
    ;;
    *)
    ;;
esac
if ! echo "$gpu_info" | grep -q "NVIDIA";
then
    if echo "$gpu_info" | grep -q "AMD" && [[ -z "${TORCH_COMMAND}" ]]
    then
        export TORCH_COMMAND="pip install torch==2.0.1+rocm5.4.2 torchvision==0.15.2+rocm5.4.2 --index-url https://download.pytorch.org/whl/rocm5.4.2"
    elif echo "$gpu_info" | grep -q "Huawei" && [[ -z "${TORCH_COMMAND}" ]]
    then
        export TORCH_COMMAND="pip install torch==2.1.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu; pip install torch_npu"
    
    fi
fi

for preq in "${GIT}" "${python_cmd}"
do
    if ! hash "${preq}" &>/dev/null
    then
        printf "\n%s\n" "${delimiter}"
        printf "\e[1m\e[31mERROR: %s is not installed, aborting...\e[0m" "${preq}"
        printf "\n%s\n" "${delimiter}"
        exit 1
    fi
done

if [[ $use_venv -eq 1 ]] && ! "${python_cmd}" -c "import venv" &>/dev/null
then
    printf "\n%s\n" "${delimiter}"
    printf "\e[1m\e[31mERROR: python3-venv is not installed, aborting...\e[0m"
    printf "\n%s\n" "${delimiter}"
    exit 1
fi

cd "${install_dir}"/ || { printf "\e[1m\e[31mERROR: Can't cd to %s/, aborting...\e[0m" "${install_dir}"; exit 1; }
if [[ -d "${clone_dir}" ]]
then
    cd "${clone_dir}"/ || { printf "\e[1m\e[31mERROR: Can't cd to %s/%s/, aborting...\e[0m" "${install_dir}" "${clone_dir}"; exit 1; }
else
    printf "\n%s\n" "${delimiter}"
    printf "Clone stable-diffusion-webui"
    printf "\n%s\n" "${delimiter}"
    "${GIT}" clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "${clone_dir}"
    cd "${clone_dir}"/ || { printf "\e[1m\e[31mERROR: Can't cd to %s/%s/, aborting...\e[0m" "${install_dir}" "${clone_dir}"; exit 1; }
fi

# Try using TCMalloc on Linux
prepare_tcmalloc() {
    if [[ "${OSTYPE}" == "linux"* ]] && [[ -z "${NO_TCMALLOC}" ]] && [[ -z "${LD_PRELOAD}" ]]; then
        # check glibc version
        LIBC_VER=$(echo $(ldd --version | awk 'NR==1 {print $NF}') | grep -oP '\d+\.\d+')
        echo "glibc version is $LIBC_VER"
        libc_vernum=$(expr $LIBC_VER)
        # Since 2.34 libpthread is integrated into libc.so
        libc_v234=2.34
        # Define Tcmalloc Libs arrays
        TCMALLOC_LIBS=("libtcmalloc(_minimal|)\.so\.\d" "libtcmalloc\.so\.\d")
        # Traversal array
        for lib in "${TCMALLOC_LIBS[@]}"
        do
            # Determine which type of tcmalloc library the library supports
            TCMALLOC="$(PATH=/usr/sbin:$PATH ldconfig -p | grep -P $lib | head -n 1)"
            TC_INFO=(${TCMALLOC//=>/})
            if [[ ! -z "${TC_INFO}" ]]; then
                echo "Check TCMalloc: ${TC_INFO}"
                # Determine if the library is linked to libpthread and resolve undefined symbol: pthread_key_create
                if [ $(echo "$libc_vernum < $libc_v234" | bc) -eq 1 ]; then
                    # glibc < 2.34 pthread_key_create into libpthread.so. check linking libpthread.so...
                    if ldd ${TC_INFO[2]} | grep -q 'libpthread'; then
                        echo "$TC_INFO is linked with libpthread,execute LD_PRELOAD=${TC_INFO[2]}"
                        # set fullpath LD_PRELOAD (To be on the safe side)
                        export LD_PRELOAD="${TC_INFO[2]}"
                        break
                    else
                        echo "$TC_INFO is not linked with libpthread will trigger undefined symbol: pthread_Key_create error"
                    fi
                else
                    # Version 2.34 of libc.so (glibc) includes the pthread library IN GLIBC. (USE ubuntu 22.04 and modern linux system and WSL)
                    # libc.so(glibc) is linked with a library that works in ALMOST ALL Linux userlands. SO NO CHECK!
                    echo "$TC_INFO is linked with libc.so,execute LD_PRELOAD=${TC_INFO[2]}"
                    # set fullpath LD_PRELOAD (To be on the safe side)
                    export LD_PRELOAD="${TC_INFO[2]}"
                    break
                fi
            fi
        done
        if [[ -z "${LD_PRELOAD}" ]]; then
            printf "\e[1m\e[31mCannot locate TCMalloc. Do you have tcmalloc or google-perftool installed on your system? (improves CPU memory usage)\e[0m\n"
        fi
    fi
}

KEEP_GOING=1
export SD_WEBUI_RESTART=tmp/restart
while [[ "$KEEP_GOING" -eq "1" ]]; do
    if [[ ! -z "${ACCELERATE}" ]] && [ ${ACCELERATE}="True" ] && [ -x "$(command -v accelerate)" ]; then
        printf "\n%s\n" "${delimiter}"
        printf "Accelerating launch.py..."
        printf "\n%s\n" "${delimiter}"
        prepare_tcmalloc
        accelerate launch --num_cpu_threads_per_process=6 "${LAUNCH_SCRIPT}" "$@"
    else
        printf "\n%s\n" "${delimiter}"
        printf "Launching launch.py..."
        printf "\n%s\n" "${delimiter}"
        prepare_tcmalloc
        "${python_cmd}" -u "${LAUNCH_SCRIPT}" "--listen --port 3200 --enable-insecure-extension-access"
    fi

    if [[ ! -f tmp/restart ]]; then
        KEEP_GOING=0
    fi
done
