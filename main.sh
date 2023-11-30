#!/bin/bash

#######
# Name: Linux Security Script for Debian and Redhat distributions
# Goal: Secure both Ubuntu and Redhat low-hanging fruit
# By: Tristan Stapert (aka tbird)
# Credits: @sour and others for good inspiration
#######

#######
# Goals and outcome (always growing. Initial ideas)
# 
# Set closer hosted repositories if possible
# Permission management
#   - Fix file permissions
#       - /etc/shadow
#       - /etc/gshadow
#       - /etc/passwd
#       - /etc/group
#       - /etc/sudoers
#   - lockdown SSH keys? 
#   - remove bad SUID bins?
# User audits
#   - Verify good users
#   - Remove bad admins
#   - Check sudoers
#   - Check groups
# Firewalls (using iptables primarily, maybe ufw)
#   - Evaluate open ports
#   - Configure initial rule list
#   - Manual verification and edit
#   - continue to next phase
# Some common configuration file hardening
#   - Harden SSH
#   - Harden FTP
# Updates and Upgrades!
#   - Last segment of code will do this due to time requirement
# Other subject to time allowance
#######

#######
# Colors for clear output
#######

blue='\e[1m'
red='\033[1;31m'
yellow='\033[1;33m'
green='\033[1;32m'
nocolor='\e[m'

good="${green}[+] ${nocolor}"
prompt="${yellow}[?] ${nocolor}"
warn="${yellow}[!] ${nocolor}"
error="${red}[#] ${nocolor}"

########
# Common Variables
########

# SET THIS WITH THE NEW BATCH PASSWORD!
password_change="Password2@"

########
# Reminder Flags
# If failure, turn on for end reminder
########
repo_changed=0
repo_update=0

########
# Common Functions
########

confirm() {
    while true; do
        echo -en "\t$1 (y/n): "
        read
        case $REPLY in 
            [yY]) return 0;;
               *) return 1;;
        esac
    done
}

#########
# INIT
#########

clear

echo -e "\tWelcome to the quick linux security script of Tbird. Hopefully this does something good!"
echo -e "\tThis does require an operator! please stand by and follow prompted tasks."

#* Verify root privileges
if [[ $EUID -ne 0 ]]; then
    echo -e "${error} MUST BE RUN AS ROOT!"
    exit 1
fi
# DEBUG
echo -e "${good} Welcome, root!"

#########
# Point Repositories at repo.ialab.dsu.edu for faster installations.
# Then run a quick update so that later package installs go fast
#########

if confirm "${prompt} Change repositories to DSU hosted collection?"; then

    #* Notify user that repositories are being dynamically adjusted
    echo -e "${good}Correcting repositories based on system active system information."
    os_id=$(cat /etc/os-release | awk -F= '/^ID=/{print $2}');

    #TODO Verify that all ubuntu test versions work with the repository change over!
    # ialab currently supports back to 14.04...
    #* Ubuntu related repository format
    if [[ "$os_id" == "ubuntu" ]]; then
        echo -e "${good}This is believed to be ${green}UBUNTU${nocolor}. We are configuring the sources.list and moving source.list.d"
        os_version=$(cat /etc/os-release | awk -F= '/VERSION_CODENAME=/{print $2}');
        # make backups
        repos="/etc/apt/sources.list"
        cp "$repos" "$repos.bak"
        mv "$repos.d" "$repos.d.bak"
        echo "deb http://repo.ialab.dsu.edu/ubuntu/ $os_version main restricted universe multiverse" > $repos
        echo "deb http://repo.ialab.dsu.edu/ubuntu/ $os_version-updates main restricted universe multiverse" >> $repos
        echo "deb http://repo.ialab.dsu.edu/ubuntu/ $os_version-backports main restricted universe multiverse" >> $repos
        echo "deb http://repo.ialab.dsu.edu/ubuntu/ $os_version-security main restricted universe multiverse" >> $repos


    #TODO Test that Debian format is working...
    #* Debian Format
    elif [[ "$os_id" == "debian" ]]; then
        echo -e "${good}This is believed to be ${green}DEBIAN${nocolor}. Now configuring sources.list and backing up old .list and .list.d"
        os_version=$(cat /etc/os-release | awk -F= '/VERSION_CODENAME=/{print $2}');
        # make backups
        repos="/etc/apt/sources.list"
        cp "$repos" "$repos.bak"
        mv "$repos.d" "$repos.d.bak"
        if [[ "$os_version" == "bookworm" || "$os_version" == "bullseye" || "$os_version" == "buster" ]]; then
            echo "deb http://repo.ialab.dsu.edu/debian/ $os_version main contrib non-free" > $repos
            echo "deb http://repo.ialab.dsu.edu/debian/ $os_version-updates main contrib non-free" >> $repos
            echo "deb http://repo.ialab.dsu.edu/debian/ $os_version-security main contrib non-free" >> $repos
        else
            echo -e "${warn}This release is older than the 'oldoldstable' release. Defaulting to archive repositories"
            echo "deb http://archive.debian.org/debian/ $os_version main contrib non-free" > $repos
            echo "deb http://archive.debian.org/debian/ $os_version-updates main contrib non-free" >> $repos
            echo "deb http://archive.debian.org/debian/ $os_version-security main contrib non-free" >> $repos
        fi

    #* Fedora/RHEL format
    elif [[ "$os_id" == "fedora" ]]; then
        # Initialize variables
        os_version=$(cat /etc/os-release | awk -F= '/VERSION_ID=/{print $2}');
        repos="/etc/yum.repos.d"
        dnfconf="/etc/dnf/dnf.conf"
        fedora="/etc/yum.repos.d/fedora.repo"
        updates="/etc/yum.repos.d/fedora-updates.repo"

        # Make backups. Moving repos directory to wipe potential bad
        mv "$repos" "$repos.bak"
        mkdir "$repos"
        cp "$dnfconf" "$dnfconf.bak"
        
        # fix dnf conf (easier)
        echo "[main]" > "$dnfconf"
        echo "gpgcheck=1" >> "$dnfconf"
        echo "installonly_limit=3" >> "$dnfconf"
        echo "clean_requirements_on_remove=true" >> "$dnfconf"

        echo -e "${warn}IAlab does not currently have repositories for fedora distributions older than 36. This will set to regular mirrors!"
        if [ "$os_version" -gt 35 ]; then
            echo -e "${good}This is believed to be ${green}FEDORA ${os_version}${nocolor}. We are configuring the /etc/dnf/dnf.conf /etc/yum.repos.d/ and backing up old for restore point."
        
            # now attempt to return to standard repositories!""
            # fedora.repo file
            echo "[fedora]" > "$fedora"
            echo 'name=Fedora $releasever - $basearch' >> "$fedora"
            echo 'baseurl=http://repo.ialab.dsu.edu/fedora/linux/releases/$releasever/Everything/$basearch/os/' >> "$fedora"
            echo 'enabled=1' >> "$fedora"

            # fedora-updates.repo file
            echo "[updates]" > "$updates"
            echo 'name=Fedora $releasever - $basearch - Updates' >> "$updates"
            echo 'baseurl=http://repo.ialab.dsu.edu/fedora/linux/updates/$releasever/Everything/$basearch/' >> "$updates"
            echo 'enabled=1' >> "$updates"
        else
            echo -e "${warn}This is believed to be ${green}FEDORA ${yellow}${os_version}${nocolor}. Setting up archive repositories."

            # now attempt to return to standard repositories!""
            # fedora.repo file
            echo "[fedora]" > "$fedora"
            echo 'name=Fedora $releasever - $basearch' >> "$fedora"
            echo 'baseurl=https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/$releasever/Everything/$basearch/os/' >> "$fedora"
            echo 'enabled=1' >> "$fedora"

            # fedora-updates.repo file
            echo "[updates]" > "$updates"
            echo 'name=Fedora $releasever - $basearch - Updates' >> "$updates"
            echo 'baseurl=https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/$releasever/Everything/$basearch/os/' >> "$updates"
            echo 'enabled=1' >> "$updates"
        fi

    #TODO Write one for CentOS. Probably similar situation to Fedora

    # Account for problematic distribution. Set error flag.
    else 
        echo -e "${error}Unexpected distribution. Script mishandle. UPDATE MANUALLY!"
        repo_changed=1 
    fi

    # Attempt to refresh repository information
    if which apt 2> /dev/null; then
        echo -e "${good}Using 'apt' to update repositories...."
        apt-get update
        echo -e "${good}DONE!"
    elif which dnf 2> /dev/null; then
        echo -e "${good}Using 'dnf' to update repositories...."
        dnf check-update
        echo -e "${good}DONE!"
    else
        echo -e "${error}Unable to identify package manager. UPDATE MANUALLY!"
        repo_update=1
    fi
fi


#########
# Verify good file permissions
#########
echo -e "${good}Next: Verify common configuration file permissions."
echo -e "${good}Backing up passwd, group, shadow, gshadow, sudoers"
cp "/etc/passwd" "/etc/passwd-"
cp "/etc/group" "/etc/group-"
cp "/etc/shadow" "/etc/shadow-"
cp "/etc/gshadow" "/etc/gshadow-"
cp "/etc/sudoers" "/etc/sudoers-"

echo -e "${good}Correcting root ownership and access permissions"
#* passwd file
chown root:root "/etc/passwd"
chmod 644 "/etc/passwd"

chown root:root "/etc/passwd-"
chmod 644 "/etc/passwd-"


#* group file
chown root:root "/etc/group"
chmod 644 "/etc/group"

chown root:root "/etc/group-"
chmod 644 "/etc/group-"

#* (g)shadow files. Try root:shadow. Fallback root:root
if grep -E "^shadow" "/etc/group"; then
    chown root:shadow "/etc/shadow"
    chown root:shadow "/etc/shadow-"
    chown root:shadow "/etc/gshadow"
    chown root:shadow "/etc/gshadow-"

else
    chown root:root "/etc/shadow"
    chown root:root "/etc/shadow-"
    chown root:root "/etc/gshadow"
    chown root:root "/etc/gshadow-"
fi

chmod 640 "/etc/shadow"
chmod 640 "/etc/shadow-"
chmod 640 "/etc/gshadow"
chmod 640 "/etc/gshadow-"


#* sudoers file and directory
chown root:root "/etc/sudoers"
chmod 440 "/etc/sudoers"

chown root:root "/etc/sudoers-"
chmod 440 "/etc/sudoers-"

chown -R root:root "/etc/sudoers.d/"
chmod -R 440 "/etc/sudoers.d/"
cp -r "/etc/sudoers.d/" "/etc/sudoers.d-/"
if confirm "${prompt}Remove includedir statement from sudoers?"; then
    sed -i '/includedir/d'
    echo -e "${warn}Removed includedir statements from active sudoers file"
fi
echo -e "${good}Finished with common account configuration files"

#########
# Fix Users
#########

#!TODO audit Users, Admins, and Groups 
echo -e "${good}Moving onto User Auditing"

#* Collect roster of current existing shell users
if confirm "${prompt}Have you provided a user list already?"; then
    #########
    # Concept: Verify good users are in current.
    #          Remaining good users will be added
    #          Remaining current users will be removed.
    #########
    good_users=($(sort -u userlist.txt))
    current_users=($(cat /etc/passwd | grep -v root | grep -E "/bin/.*sh" | cut -d: -f1 | sort -u))
    #DEBUG
    echo -e "${warn}Starting loop"
    for g in "${!good_users[@]}"; do
        for c in "${!current_users[@]}"; do
            #DEBUG
            echo -e "${warn}Checking user from good with current list"
            if [[ "${good_users[g]}" == "${current_users[c]}" ]]; then
                echo "${good}User ${good_users[g]} found!"
                unset "good_users[g]"
                unset "current_users[c]"
                break
            fi
        done
    done
    echo -e "${good}Users have been compared. Current statistics below v"
    echo -e "${warn}Missing ${green}good${nocolor} users:" "${good_users[@]}"
    echo -e "${warn}Extra ${red}shell${nocolor} users:" "${current_users[@]}"

    echo -e "${good}Adding missing users from userlist!"
    for u in "${good_users[@]}"; do
        useradd -m "$u"
        [ $? == 0 ] && echo -e "${good}User $u added!" || echo -e "${error}User $u failed to add!"
    done

    if confirm "${prompt}Remove the extra shell users on the system? (${current_users[@]})"; then
        for u in "${current_users[@]}"; do
            userdel -r "$u"
            [ $? == 0 ] && echo -e "${warn}User $u removed!" || echo -e "${error}User $u failed to remove!"
        done
    fi

    if confirm "${prompt}Change all shell user passwords?"; then
        echo -e "${warn}Changing all shell passwords to: $password_change"
        for u in $(cat /etc/passwd | grep -E "/bin/.*sh" | cut -d: -f1); do
            echo "$u:$password_change" | chpasswd;
        done
    fi
fi

echo -e "${good}User audit complete. Moving on to group audit!"


#########
# Fix Sudoers
#########

#TODO Remove NOPASSWD and #include. Also verify other sudo and wheel members

#########
# Stand up Firewalls
#########
