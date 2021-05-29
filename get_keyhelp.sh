#!/bin/bash

#  _  __          _   _     _      (R)
# | |/ /___ _   _| |_| |___| |___
# | | /  -_) |_/ |  _  | -_) | _ \
# |_|\_\___|\__, |_| |_|___|_|  _/
#           |___/            |_|


## Usage: install_keyhelp.sh [options]
##
## Options:
##   -h, --help            Show this help
##   -v, --version         Print version info
##   --preferred-protocol  Preferred IP protocol for connections
##                         [Values: "none", "ipv4", "ipv6" | Default "ipv4"]
##   --debug               Get KeyHelp from debug release channel - do not do this ;)
##
## Try "php /home/keyhelp/www/keyhelp/install/install.php --help" for more options.
## All unknown arguments gets passed to the real installer.

#=======================================================================================================================
# Globals
#=======================================================================================================================

    # Setting PATH, important for OS >= Debian 10, when user switching to root with "su root" instead "su -"
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

    ARGV=$@
    PASS_ARGV=""
    INSTALLERVERSION=1
    DEBUG=false
    NON_INTERACTIVE=false
    PREFERRED_PROTOCOL="ipv4"
    USERNAME="keyhelp"
    HOMEDIR="/home/keyhelp/"
    INSTALLDIR="$HOMEDIR/www/keyhelp/"
    INSTALLFILE=$(readlink -m "$INSTALLDIR/install/install.php"); # remove unnecessary slashes

#=======================================================================================================================
# Functions | Common
#=======================================================================================================================

    # Prints a given error message and exit.
    #
    # param   string  The error message.
    # return  void
    function die()
    {
        echo -en "\033[1;31mERROR:\033[0m "
        echo -e "$*" >&2
        exit 1
    }

    # Prints a given message and highlight it as warning.
    #
    # param   string  The message.
    # return  void
    function warn()
    {
        echo -en "\033[1;33mWARNING:\033[0m "
        echo "$*" >&2
    }

    # Prints a given message and highlight it.
    #
    # param   string  The message
    # return  void
    function printHeadline()
    {
        echo -e "\033[1;32m$*\033[0m"
    }

#=======================================================================================================================
# Functions | Input / Arguments
#=======================================================================================================================

    # Parses command line arguments and store them in global variables.
    #
    # return  void
    function parse_args()
    {
        while [[ $# > 0 ]]
        do
            key="$1"
            case $key in
                -h|--help)
                    echo "$(grep '^##' "${BASH_SOURCE[0]}" | cut -c 4-)"
                    echo ""
                    exit 0
                    ;;
                -v|--version)
                    echo "Version: $INSTALLERVERSION"
                    echo "Copyright (C) `date +'%Y'` Keyweb AG"
                    exit 0
                    ;;
                --debug)
                    DEBUG=true
                    ;;
               --non-interactive)
                    NON_INTERACTIVE=true
                    # -> Pass to installer.
                    PASS_ARGV="$PASS_ARGV $key"
                    ;;
                --preferred-protocol)
                    value="$2"
                    PREFERRED_PROTOCOL=`sanitizePreferredProtocol $value`
                    shift
                    # -> Pass to installer.
                    PASS_ARGV="$PASS_ARGV $key $PREFERRED_PROTOCOL"
                    ;;
                --preferred-protocol=*)
                    value="${key#*=}"
                    PREFERRED_PROTOCOL=`sanitizePreferredProtocol $value`
                    # -> Pass to installer.
                    PASS_ARGV="$PASS_ARGV $key"
                    ;;
                *)
                    # Unknown argument
                    # -> Pass to installer.
                    PASS_ARGV="$PASS_ARGV $key"
                    ;;
            esac
            shift
        done
    }

    # Sanitizes the input of the --preferred-protocol parameter.
    #
    # param  string  The protocol ("ipv4", "ipv6", "none").
    function sanitizePreferredProtocol()
    {
        protocol=`echo $1 | awk '{print tolower($0)}'`
        if [ "$protocol" == "ipv4" ] || [ "$protocol" == "ipv6" ] || [ "$protocol" == "none" ]; then
            echo $protocol
        else
            echo "ipv4"
        fi
    }

#=======================================================================================================================
# Functions | Initial checks
#=======================================================================================================================

    # Checks, if current user has sudo privileges.
    # Terminates if it fails.
    #
    # return  void
    function check_root()
    {
        if [ `id -u` -ne 0 ]; then
            die "You need super-user privileges to install KeyHelp"
        fi
    }

    # Checks if a given OS string is supported by KeyHelp.
    # Terminates if it fails.
    #
    # return  void
    function check_supported_os()
    {
        local os=`get_os`

        # TODO: Check for non-interactive!
        #
        #if [ "$os" = 'Ubuntu_20.04' ]; then
        #    echo
        #    warn "The support for Ubuntu 20 is currently in closed BETA state. It should only be used for testing purpose."
        #    warn "You will not be able to proceed if you are not a BETA tester."
        #    echo "[CRTL] + [C] to cancel | [ENTER] to continue"
        #    read
        #fi

        if [ "$os" != 'Ubuntu_16.04' ] &&
           [ "$os" != 'Ubuntu_18.04' ] &&
           [ "$os" != 'Ubuntu_20.04' ] &&
           [ "$os" != 'Debian_9' ]     &&
           [ "$os" != 'Debian_10' ]; then

            die "Unsupported OS"
        fi
    }

    # Checks if the system is running with supported architectures.
    # Terminates if it fails.
    #
    # return  void
    function check_supported_architecture()
    {
        if [ `uname -m` = 'x86_64' ]; then
            return
        elif [ `uname -m` = 'aarch64' ] && [ `dpkg --print-architecture` = 'arm64' ]; then
            return
        fi

        die "Unsupported system architecture"
    }

    # Checks if dpkg is running.
    # Terminates if it is the case.
    #
    # return void
    function check_dpkg()
    {
        lsof /var/lib/dpkg/lock >/dev/null 2>&1

        if [ $? = 0 ]; then
            die "The package manager (dpkg) is running by an other process.\nPlease try again later or release the lock (not recommended)."
        fi
    }

#=======================================================================================================================
# Functions | Receive system information
#=======================================================================================================================

    # Returns the current OS name and version.
    #
    # return  string  Format eg. "Ubuntu_18.04", "Debian_10"
    function get_os()
    {
        local distro
        local version

        if [ `uname -s` = 'Linux' ] && [ -e '/etc/debian_version' ]; then
            if [ -e '/etc/lsb-release' ]; then
                # Mostly Ubuntu, but also Debian can have it too.
                . /etc/lsb-release
                distro="$DISTRIB_ID"
                version="$DISTRIB_RELEASE"
            else
                distro="Debian"
                version=`head -n 1 /etc/debian_version`
            fi

            if [ $distro = "Debian" ]; then
                version=`echo $version | grep -o "^[0-9]\+"`
            fi
        else
            echo 'false'
        fi

        echo ${distro}_$version
    }


    # Reads the main version number of installed PHP.
    #
    # return  string  Main version number (eg 7.0, 7.4)
    function get_php_version()
    {
        local php=`php -v | grep -oP "^PHP\s[0-9]\.[0-9]*" | cut -d" " -f2`

        if [ -z "$php" ]; then
            die "PHP version check failed"
        fi

        echo $php
    }

#=======================================================================================================================
# Functions | System setup
#=======================================================================================================================

    # Creates the 'keyhelp' system user.
    #
    # return  void
    function create_keyhelp_user()
    {
        local shell="/bin/false"

        if ! id -u $USERNAME >/dev/null 2>&1
        then
            useradd --home-dir $HOMEDIR -M --shell $shell $USERNAME
        else
            usermod --home $HOMEDIR --shell $shell $USERNAME
        fi

        mkdir -p $HOMEDIR
        chown --recursive $USERNAME:$USERNAME $HOMEDIR
    }

    # Installs ca-certificates bundle to prevent failing wget calls (otherwise use "no-check-certificate").
    #
    # return  void
    function install_ca_certificates()
    {
        apt-get -y -qq install ca-certificates
    }

    # Installs PHP/-packages, needed for launching the KeyHelp installation routine.
    #
    # return  void
    function install_php()
    {
        rm -rf /var/lib/apt/lists/*
        apt-get -qq update

        case `get_os` in
            "Ubuntu_16.04"|"Debian_9")
                apt-get install -y -qq php php-mysqlnd php-intl php-mbstring php7.0-readline
                phpenmod mbstring
                ;;
            "Ubuntu_18.04")
                apt-get install -y -qq php php7.2-mysql php-intl php-mbstring php7.2-readline
                phpenmod mbstring
                ;;
            "Ubuntu_20.04")
                apt-get install -y -qq php php7.4-mysql php-intl php-mbstring php7.4-readline
                phpenmod mbstring
                ;;
            "Debian_10")
                apt-get install -y -qq php php-mysql php-intl php-mbstring php-readline
                phpenmod mbstring
                ;;
            *)
                die "Unsupported OS"
                ;;
        esac

        apt-get -y autoremove
        apt-get clean
    }

    # Installs ionCube and activate it.
    #
    # return  void
    function install_ioncube()
    {
        local archive="/tmp/ioncube.tar.gz"
        local ioncubeIniPath="/etc/php/`get_php_version`/mods-available/ioncube.ini"

        # Download
        case `dpkg --print-architecture` in
            "amd64")
                local downloadUrl="https://misaka91.coding.net/p/cdn/d/cdn/git/raw/master/Keyhelp/ioncube_loaders_lin_x86-64.tar.gz"
                ;;
            "arm64")
                local downloadUrl="https://misaka91.coding.net/p/cdn/d/cdn/git/raw/master/Keyhelp/ioncube_loaders_lin_aarch64.tar.gz"
                ;;
            *)
                die "Unsupported system architecture"
                ;;
        esac

        wget --prefer-family="$PREFERRED_PROTOCOL" --quiet --show-progress --no-check-certificate --output-document $archive $downloadUrl

        # Extract
        local extractTo="/usr/local"
        mkdir -p $extractTo
        tar -xzf $archive -C $extractTo

        local soFile="$extractTo/ioncube/ioncube_loader_lin_`get_php_version`.so"

        chown --recursive root:root $(dirname $soFile)

        # Setup ioncube.ini.
        echo "; configuration by KeyHelp"   >  $ioncubeIniPath
        echo "; priority=01"                >> $ioncubeIniPath
        echo "zend_extension=$soFile"       >> $ioncubeIniPath

        # Enable ioncube.ini
        # First perform dismod, in case the installer is called multiple times.
        phpdismod ioncube
        phpenmod ioncube
    }

    # Downloads KeyHelp, extract content to INSTALLDIR, change file owner.
    #
    # return  void
    function download_keyhelp()
    {
        #
        # !!! wget with --no-check-certificate
        # Debian doesn't know Let's Encrypt CA?
        #

        if [ "$DEBUG" = 'true' ]; then
            local release_channel='&release_channel=debug';
        else
            local release_channel='';
        fi

        local get_version="http://pot.napoi.cn/get_version.php?encode=plain&php_version=`get_php_version`$release_channel"

        declare -A release_info
        release_info[error]=true
        release_info[error_msg]='Invalid response. / Server not reachable.'

        # Contact server and load release info.
        while read line
        do
            local key=`echo $line | awk -F= '{print $1}'`
            local value=`echo $line | awk -F= '{print $2}'`

            if [ -n "$key" ]; then
                release_info[$key]=$value
            fi
        done < <(wget --prefer-family="$PREFERRED_PROTOCOL" --quiet --no-check-certificate -O- $get_version)

        if [ ${release_info[error]} == true ]; then
            die "An error occured: ${release_info[error_msg]}"
        fi

        # Download
        local archive="/tmp/keyhelp.tar.gz"
        wget --prefer-family="$PREFERRED_PROTOCOL" --quiet --show-progress --no-check-certificate --output-document $archive ${release_info[download]}

        # Check checksum.
        if [ -n ${release_info[sha1]} ]; then

            local sha1_is=`sha1sum /tmp/keyhelp.tar.gz | cut -d ' ' -f 1`

            if [ "${release_info[sha1]}" != "$sha1_is" ]; then
                die 'Checksum check failed - please try again / contact support!'
            fi

        else
            warn 'Skipping checksum check, sha1 not defined.'
        fi

        # Extract.
        mkdir -p $INSTALLDIR
        rm -rf $INSTALLDIR/*
        tar -xzf $archive -C $INSTALLDIR
        chmod 0755 $INSTALLDIR  # after un-tar, chmod will be 0775

        # Deploy dummy license.
        local licensefile="$INSTALLDIR/license.txt"
        echo "W A R N I N G - Do NOT move, edit or delete this file!"   >  $licensefile
        echo ""                                                         >> $licensefile
        echo "------ LICENSE FILE DATA -------"                         >> $licensefile
        echo "2301477U5cioXgY8rtNjO1XMMIuGzKru"                         >> $licensefile
        echo "RkVT2ca1dp/+/yL/9yO3Q4Rb5wQ5wobp"                         >> $licensefile
        echo "Ma7kSLinHn2VDds3HEdL1u8/I41P3Lie"                         >> $licensefile
        echo "61Dvewf+Gb6h8Pk0rR9xQBtIvHSn423c"                         >> $licensefile
        echo "MeLTgjKRmaPCF2Cc9HZXkCFaGwGIJD2n"                         >> $licensefile
        echo "1kRfwhUTWhcyuYjmcGZL/b65Z2EmMfeM"                         >> $licensefile
        echo "d5LB+jAAI8vq0qjrOV+a1uTkfjCM8TMe"                         >> $licensefile
        echo "+xd9tfzQ0bnExQq="                                         >> $licensefile
        echo "--------------------------------"                         >> $licensefile
        chmod 0600 $licensefile

        chown --recursive $USERNAME:$USERNAME $HOMEDIR
    }

#=======================================================================================================================
# Program
#=======================================================================================================================

    parse_args $ARGV

    printHeadline "You are about to install KeyHelp.";

    printHeadline "Running system checks...";
    check_root
    check_supported_os
    check_supported_architecture
    check_dpkg

    printHeadline "Installing certificates..."
    install_ca_certificates

    printHeadline "Installing PHP..."
    install_php

    printHeadline "Installing KeyHelp..."
    create_keyhelp_user
    download_keyhelp

    printHeadline "Installing ionCube..."
    install_ioncube

    printHeadline "Run $INSTALLFILE --installer-version $INSTALLERVERSION $PASS_ARGV" | sed 's/\(admin-password[= ]\)[^ ]*\( .*\)/\1\*\*\*\*\*\*\2/'
    php $INSTALLFILE --installer-version $INSTALLERVERSION $PASS_ARGV