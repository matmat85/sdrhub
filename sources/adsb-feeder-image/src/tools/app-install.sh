#!/bin/bash

# install the adsb-setup app, the config files, and the services for use of
# the adsb-feeder on top of another OS.
# the script assumes that the dependencies are installed by the caller

USAGE="
 $0 arguments
  -s srcdir      # the git checkout parent dir
  -b branch      # the branch to use (default: main)
  -t tag         # alternatively the tag to use
  -f             # finish an install on DietPi using dietpi-software
  -l source      # install an existing checkout without cloning, switching or deleting it
  -n             # install files without starting services (configure before first boot)
"

ROOT_REQUIRED="
 $0 needs to be run with superuser permissions, typically as
 sudo bash $0 arguments
"

# simple way to provide a message and exit with an error code
exit_message() {
    echo "$1"
    exit 1
}

get_distro() {
    local distro="unknown"
    grep -i fedora /etc/os-release &> /dev/null && distro="fedora"
    grep -i centos /etc/os-release &> /dev/null && distro="fedora"
    grep -i suse /etc/os-release &> /dev/null && distro="suse"
    grep -i debian /etc/os-release &> /dev/null && distro="debian"
    echo $distro
}

[ "$(id -u)" != "0" ] && exit_message "$ROOT_REQUIRED"

APP_DIR="/opt/adsb"
BRANCH=""
GIT_PARENT_DIR=""
TAG=""
FINISH_DIETPI=""
LOCAL_SOURCE=""
NO_START=""

while (( $# ))
do
    case $1 in
        '-s') shift; GIT_PARENT_DIR=$1
            ;;
        '-b') shift; BRANCH=$1
            ;;
        '-t') shift; TAG=$1
            ;;
        '-f') FINISH_DIETPI="1"
            ;;
        '-l') [[ $# -ge 2 && -n "$2" ]] || exit_message "-l requires a source directory"
            shift; LOCAL_SOURCE=$1
            ;;
        '-n') NO_START="1"
            ;;
        *) exit_message "$USAGE"
    esac
    shift
done

if [[ $FINISH_DIETPI == "1" ]] ; then
    # are we just finishing up the install from dietpi-software?
    if [[ -d /boot/dietpi && -f /boot/dietpi/.version ]] ; then
        # shellcheck disable=SC1091
        source /boot/dietpi/.version
        OS="DietPi ${G_DIETPI_VERSION_CORE}.${G_DIETPI_VERSION_SUB}"
        echo "app-install from $OS" > ${APP_DIR}/adsb.im.previous-version
        # and for now that's all we need
        exit 0
    else
        exit_message "do not use '-f' outside of installing via dietpi-software on DietPi"
    fi
fi

if [[ -n "$LOCAL_SOURCE" ]] ; then
    [[ -z "$BRANCH" && -z "$TAG" && -z "$GIT_PARENT_DIR" && -z "$FINISH_DIETPI" ]] || exit_message "Do not combine -l with -s, -b, -t or -f"
    LOCAL_SOURCE=$(cd "$LOCAL_SOURCE" && pwd) || exit_message "Local source directory does not exist"
    [[ -f "$LOCAL_SOURCE/src/get_version.sh" && -d "$LOCAL_SOURCE/src/modules/adsb-feeder/filesystem/root/opt/adsb" ]] || exit_message "Local source is not an adsb-feeder-image checkout"
fi

if [[ $GIT_PARENT_DIR == '' && $LOCAL_SOURCE == '' ]] ; then
    GIT_PARENT_DIR=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf $GIT_PARENT_DIR" EXIT
fi
if [[ $TAG == '' && $BRANCH == '' ]] ; then
    BRANCH="main"
elif [[ $TAG != '' && $BRANCH != '' ]] ; then
    exit_message "Please set either branch or tag, not both"
fi
if [[ ! -d "$APP_DIR" ]] ; then
    if ! mkdir -p "$APP_DIR" ; then
        exit_message "failed to create $APP_DIR"
    fi
fi
if [[ ! -d "$APP_DIR"/config ]] ; then
    mkdir -p "$APP_DIR"/config
fi

distro=$(get_distro)
echo "You appear to be on a ${distro}-style distribution"

# now that we know that there isn't anything obviously wrong with
# the command line arguments, let's check if all the dependencies
# are installed
# - Python 3.9 or later and Flask 2 or later
# - git
# - docker
# - docker compose
missing=""
if which python3 &> /dev/null ; then
	python3 -c "import sys; sys.exit(sys.version_info < (3, 9))" &> /dev/null || missing="python3 "
	python3 -c "import requests" &>/dev/null || missing+="python3-requests "
	python3 -c "import flask" &>/dev/null || missing+="python3-flask "
    python3 -c "import cryptography" &>/dev/null || missing+="python3-cryptography "
	python3 -c "import sys; from importlib.metadata import version; sys.exit(int(version('Flask').split('.')[0]) < 2)" &> /dev/null || missing+="python3-flask "
else
	missing="python3 python3-flask python3-requests python3-cryptography "
fi
which git &> /dev/null || missing+="git "
if which docker &> /dev/null ; then
	 ! docker compose version &> /dev/null && ! docker-compose version &> /dev/null && missing+="docker-compose "
else
    if [ "$distro" == "debian" ]; then
        missing+="docker.io docker-compose "
    else
        missing+="docker docker-compose "
    fi
fi

if ! which lsusb &> /dev/null; then
    missing+="usbutils "
fi

if [[ $missing != "" ]] ; then
	inst=""
        [ "$distro" == "fedora" ] && inst="dnf install -y"
        [ "$distro" == "suse" ] && inst="zypper install -y"
        [ "$distro" == "debian" ] && inst="apt-get install -y"

    if grep -qs -e docker <<< "$missing" && command -v docker-compose &>/dev/null; then
        echo "It seems the docker-compose provided by your OS doesn't work correctly, please install docker using the packages provided by docker using this script"
        echo
        echo "curl https://get.docker.com/ | sudo bash"
        echo
        echo "Once it is finished, rerun this install script"
    else
        echo "Please install the missing packages before re-running this script:"
        echo
        echo "$inst $missing"
    fi
	exit 1
fi

if (( $(docker --version | cut -d ' ' -f3 | cut -d '.' -f1) < 21 )); then
    echo "The docker provided by your OS is too old, please install docker using this script via the docker.com repository"
    echo
    echo "curl https://get.docker.com/ | sudo bash"
    echo
    echo "Once it is finished, rerun this install script"
    exit 1
fi

# ok, now we should have all we need, let's get started

if [[ -n "$LOCAL_SOURCE" ]] ; then
    CHECKOUT_DIR="$LOCAL_SOURCE"
else
    CHECKOUT_DIR="$GIT_PARENT_DIR/adsb-feeder"
    if ! git clone 'https://github.com/dirkhh/adsb-feeder-image.git' "$CHECKOUT_DIR" ; then
        exit_message "cannot check out the git repo to ${GIT_PARENT_DIR}"
    fi
    cd "$CHECKOUT_DIR" || exit_message "can't find $CHECKOUT_DIR"
    if [[ $BRANCH != '' ]] ; then
        if ! git checkout "$BRANCH" ; then
            exit_message "cannot check out the branch ${BRANCH}"
        fi
    else
        if ! git checkout "$TAG" ; then
            exit_message "cannot check out the tag ${TAG}"
        fi
    fi
fi

# determine the version
SRC_ROOT="${CHECKOUT_DIR}/src/modules/adsb-feeder/filesystem/root"
cd "$SRC_ROOT" || exit_message "can't cd to $SRC_ROOT"
ADSB_IM_VERSION=$(bash "${CHECKOUT_DIR}/src/get_version.sh")

# copy the software in place
cp -a "${SRC_ROOT}/opt/adsb/"* "${APP_DIR}/" || exit_message "cannot install application files"
for service in "${SRC_ROOT}/usr/lib/systemd/system/"*; do
    [[ $(basename "$service") == adsb-bootstrap.service ]] && continue
    cp -a "$service" "/usr/lib/systemd/system/" || exit_message "cannot install service $service"
done
if [[ -z "$LOCAL_SOURCE" ]] ; then
    rm -rf "${GIT_PARENT_DIR}/adsb-feeder"
fi

# set the 'image name' and version that are shown in the footer of the Web UI
cd "$APP_DIR" || exit_message "can't cd to $APP_DIR"
if [[ -d /boot/dietpi ]] ; then
    if [[ -f /boot/dietpi/.version ]] ; then
        # shellcheck disable=SC1091
        source /boot/dietpi/.version
        OS="DietPi ${G_DIETPI_VERSION_CORE}.${G_DIETPI_VERSION_SUB}"
    else
        OS="DietPi"
    fi
elif [[ -f /etc/dist_variant ]] ; then
    OS=$(</etc/dist_variant)
elif [[ -f /etc/os-release ]] ; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ $PRETTY_NAME != '' ]] ; then
        OS="$PRETTY_NAME"
    elif [[ $NAME != '' ]] ; then
        OS="$NAME"
    else
        OS="unrecognized OS"
    fi
else
    OS="unrecognized OS"
fi
echo "app-install" > ${APP_DIR}/adsb.im.previous-version
echo "ADS-B Feeder app running on ${OS}" > feeder-image.name
echo "$ADSB_IM_VERSION" > adsb.im.version
touch ${APP_DIR}/app.adsb.feeder.image

cd ${APP_DIR}/config || exit_message "can't find ${APP_DIR}/config"
{
    cat ${APP_DIR}/docker.image.versions
    echo "_ADSBIM_BASE_VERSION=$(cat ${APP_DIR}/adsb.im.version)"
    echo "_ADSBIM_CONTAINER_VERSION=$(cat ${APP_DIR}/adsb.im.version)"
    echo "AF_WEBPORT=1099"
    echo "AF_TAR1090_PORT=1090"
    echo "AF_UAT978_PORT=1091"
    echo "AF_PIAWAREMAP_PORT=1092"
    echo "AF_PIAWARESTAT_PORT=1093"
    echo "AF_DAZZLE_PORT=1094"
 } >> .env

# run the final steps of the setup and then enable the services
systemctl daemon-reload
readarray -t services_enable < /opt/adsb/misc/services
if [[ "$NO_START" == "1" ]]; then
    systemctl enable "${services_enable[@]}"
else
    systemctl enable --now "${services_enable[@]}"
    # Pull the key containers while the user completes setup.
    systemd-run -u adsb-docker-pull bash ${APP_DIR}/docker-pull.sh
fi

echo "done installing"
echo "you can uninstall this software by running"
echo "sudo bash ${APP_DIR}/app-uninstall"
echo ""
local_ip=$(ip route get 1 | grep -oP 'src \K\S+')
echo "you can access the web interface at http://localhost:1099 or http://${local_ip}:1099"
