#!/bin/bash
# <https://www.gnu.org/prep/maintain/html_node/License-Notices-for-Other-Files.html>
# Copyright 2023, Pacstall development team
#
# Copying and distribution of this file, with or without modification, are permitted in any medium without royalty, provided the copyright notice and this notice are preserved. This file is offered as-is, without any warranty.

shopt -s nullglob dotglob # To include hidden files

function err() {
    printf '\033[1;31m[ERR]\033[0m: %s\n' "${*}" >&2
}

function inf() {
    printf '\033[1;32m[INFO]\033[0m: %s\n' "${*}"
}

function sub() {
    echo -e "\033[1;35m   [>]\033[0m: ${*}"
}

function cmd() {
    printf '\033[1;33m[CMD]\033[0m: %s\n' "${*}"
}

function yes_or_no() {
    local yn
    while :; do
        read -r -p "${*} [y/n]: " yn
        case "${yn}" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
        esac
    done
}

function checks::is_pacstall_installed() {
    if ! command -v pacstall &> /dev/null; then
        err "Pacstall is not installed!"
        return 1
    else
        return 0
    fi
}

function checks::anything_installed() {
    local pkgs=()
    mapfile -t pkgs < <(pacstall -L)
    if [[ -z ${pkgs[*]} ]]; then
        err "Nothing installed yet!"
        return 1
    else
        return 0
    fi
}

function checks::pacver() {
    local pacver=()
    mapfile -d ' ' -t pacver < <(pacstall -V)
    if [[ ${pacver[0]} != "4.0.0" ]]; then
        err "You are not running >=4.0.0! Rerun this script after updating from ${pacver[0]}"
        return 1
    fi
    return 0
}

function checks::old_files() {
    local old_files=(/var/log/pacstall/metadata/*)
    if ((${#old_files[@]} > 0)); then
        err "'/var/log/pacstall/metadata' still has files in it! Maybe update did not move the rest"
        return 1
    fi
    return 0
}

inf "Running pre-conversion checks"
checks::is_pacstall_installed || exit 1
sub "Pacstall is installed"
checks::pacver || exit 1
sub "Pacstall is >=4.0.0"
checks::anything_installed || exit 1
sub "Pacstall has installed packages"
checks::old_files || {
    if yes_or_no "Do you want me to attempt to move the rest"; then
        inf "Attempting to move the rest of the files"
        sudo mkdir -p /var/lib/pacstall/metadata/
        sudo mv -v /var/log/pacstall/metadata/* /var/lib/pacstall/metadata/ || { err "'mv' failed to move files, bailing out!" && exit 1; }
    else
        err "Exiting at your request"
        exit 1
    fi
}
sub "Package metadata are in the correct places"
inf "Everything looks good, proceeding"

mapfile -t pkgs < <(pacstall -L)
if [[ -z ${pkgs[*]} ]]; then exit 1; fi
for pkg in "${pkgs[@]}"; do
    if [[ ${pkg} == *-deb ]]; then
        continue
    fi
    sub "Converting \033[4;36m${pkg}\033[0m..."
    unset _name _gives &> /dev/null
    source "/var/lib/pacstall/metadata/${pkg}" || { err "Could not source '/var/lib/pacstall/metadata/${pkg}'" && exit 1; }
    if [[ -z ${_name} ]]; then
        err "'_name' variable not defined!!!!"
        if yes_or_no "Do you want to continue to the next package"; then
            continue
        else
            exit 1
        fi
    fi
    cmd "sudo sed -i \"s|/var/log/pacstall/metadata/${_name}|/var/lib/pacstall/metadata/${_name}|g\" \"/var/lib/dpkg/info/${_gives:-$_name}.postrm\""
    sudo sed -i "s|/var/log/pacstall/metadata/${_name}|/var/lib/pacstall/metadata/${_name}|g" "/var/lib/dpkg/info/${_gives:-$_name}.postrm"
done
