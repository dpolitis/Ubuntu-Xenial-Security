#!/usr/bin/env bash
################################################################################
################################################################################
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
################################################################################
################################################################################
# Script tries to harden a default setup of Ubuntu Server 16.04LTS
# All configuration parameters lie in the begining of the file, 
# in terms of global variables (Capitalized). Fell free to change
# the configuration according to your needs. Only change if you know
# what you're doing..You have been warned!
################################################################################
# CONFIGURATION STARTS HERE
################################################################################
ADDUSER='/etc/adduser.conf'
APACHE2DFILE='/etc/apache2/conf-available/custom_secure.conf'
AUDITDCONF='/etc/audit/auditd.conf'
AUDITRULES='/etc/audit/rules.d/hardening.rules'
COMMONPASSWD='/etc/pam.d/common-password'
COMMONACCOUNT='/etc/pam.d/common-account'
COMMONAUTH='/etc/pam.d/common-auth'
COREDUMPCONF='/etc/systemd/coredump.conf'
DEBIAN_FRONTEND='noninteractive'
DEFAULTGRUB='/etc/default/grub'
DISABLEFS='/etc/modprobe.d/disablemnt.conf'
DISABLEMOD='/etc/modprobe.d/disablemod.conf'
DISABLENET='/etc/modprobe.d/disablenet.conf'
EXPECT='/usr/bin/expect'
FW_LOCAL='127.0.0.1'
GRUB_PASSPHRASE='password'
GRUB_SUPERUSER='myuser'
JOURNALDCONF='/etc/systemd/journald.conf'
LIMITSCONF='/etc/security/limits.conf'
LOGINDCONF='/etc/systemd/logind.conf'
LOGINDEFS='/etc/login.defs'
LOGROTATE='/etc/logrotate.conf'
MKPASSWD='/usr/bin/grub-mkpasswd-pbkdf2'
MOD='bluetooth firewire-core net-pf-31 soundcore thunderbolt usb-midi'
MODSEC='/etc/modsecurity/modsecurity.conf'
PACKAGES="acct aide-common apache2 apparmor-profiles apparmor-utils auditd \
clamav clamdscan clamav-daemon debsums expect fail2ban git haveged \
libapache2-mod-security2 libapache2-mod-evasive libpam-cracklib \
libpam-tmpdir nfs-kernel-server openssh-server rkhunter samba $VM"
PAMLOGIN='/etc/pam.d/login'
RESOLVEDCONF='/etc/systemd/resolved.conf'
RKHUNTERCONF='/etc/default/rkhunter'
SECURITYACCESS='/etc/security/access.conf'
SERVER='Y'
SSHDFILE='/etc/ssh/sshd_config'
SSH_GROUPS='sudo'
SYSCTL='/etc/sysctl.conf'
SYSTEMCONF='/etc/systemd/system.conf'
TERM='linux'
TIMESYNCD='/etc/systemd/timesyncd.conf'
UFWDEFAULT='/etc/default/ufw'
USERADD='/etc/default/useradd'
USERCONF='/etc/systemd/user.conf'
UNW_PROT='dccp sctp rds tipc'
UNW_SERVICES='rpcbind'
UNW_FS='cramfs freevxfs jffs2 hfs hfsplus squashfs udf vfat'
VERBOSE='Y'
VM=''
################################################################################
# CONFIGURATION ENDS HERE
# Do not change anything below this line!
################################################################################
# Prepare ENV (OK)
export TERM
export DEBIAN_FRONTEND
################################################################################
# Check that we have bare minimum..(OK)
if [ $EUID -ne 0 ]; then
    echo "This script must be run with root privileges."
    echo
    exit 1
fi

if ! lsb_release -i | grep 'Ubuntu'; then
    echo "Unsupported Linux distribution. Only Ubuntu Supported"
    echo
    exit 1
fi

if ! ps -p $$ | grep -i bash; then
    echo "Please install bash to continue.."
    echo
    exit 1
fi

if ! [ -x "$(which systemctl)" ]; then
	echo "systemctl required. Unsupported setup.."
    echo
	exit 1
fi

if ! test -f "$UFWDEFAULT"; then
    echo "$UFWDEFAULT firewall config file not found."

    if ! dpkg -l | grep ufw 2> /dev/null 1>&2; then
    	echo 'Please install ufw package to continue.'
    fi
    exit 1
fi

echo "End of Pre-Flight checks.."
# End of Pre-Flight checks..
################################################################################
# Set paths(OK)
echo "Setting paths..."

sed -i 's/PATH=.*/PATH=\"\/usr\/local\/bin:\/usr\/bin:\/bin"/' /etc/environment

cat > /etc/profile.d/initpath.sh <<EOF
#!/bin/bash

if [[ $EUID -eq 0 ]];
  then
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  else
    export PATH=/usr/local/bin:/usr/bin:/bin
fi
EOF

chown root:root /etc/profile.d/initpath.sh
chmod 0644 /etc/profile.d/initpath.sh
################################################################################
# Install needed packages(OK)
if [[ $VERBOSE == "Y" ]]; then
    APT_ENV='-y'
else
    APT_ENV='-qq -y'
fi

APT="apt-get $APT_ENV"

echo "Updating the package index files..."
$APT update

echo "Upgrading installed packages..."
$APT upgrade

echo "Installing base packages..."

# Are we running a VM?
if dmidecode -q --type system | grep -i vmware; then
    VM="open-vm-tools"
fi

if dmidecode -q --type system | grep -i virtualbox; then
    VM="virtualbox-guest-dkms virtualbox-guest-utils"
fi

for deb in $PACKAGES; do
    $APT install --no-install-recommends "$deb"
done
################################################################################
# Install security updates via cronjob(OK)
cat > /etc/cron.weekly/apt-security-updates <<EOF
echo "**************" >> /var/log/apt-security-updates
date >> /var/log/apt-security-updates
aptitude update >> /var/log/apt-security-updates
aptitude safe-upgrade -o Aptitude::Delete-Unused=false --assume-yes --target-release `lsb_release -cs`-security >> /var/log/apt-security-updates
echo "Security updates (if any) installed"
EOF

chmod +x /etc/cron.weekly/apt-security-updates

cat > /etc/logrotate.d/apt-security-updates <<EOF
/var/log/apt-security-updates {
        rotate 2
        weekly
        size 250k
        compress
        notifempty
}
EOF
################################################################################
# Enforce AppArmor(OK)
echo "Enforcing apparmor profiles..."

find /etc/apparmor.d/ -maxdepth 1 -type f -exec aa-enforce {} \;
aa-complain /etc/apparmor.d/usr.sbin.rsyslogd
################################################################################
# Secure bootloader(OK)
echo "Securing bootloader..."

expect_script(){
    cat <<EOF
    log_user 0
    spawn  ${MKPASSWD}
    sleep 0.33
    expect  "Enter password: " {
        send "$GRUB_PASSPHRASE"
        send "\n"
    }
    sleep 0.33
    expect "Reenter password: " {
        send "$GRUB_PASSPHRASE"
        send "\n"
    }
    sleep 0.33
    expect eof {
        puts "\$expect_out(buffer)"
    }
    exit 0
EOF
}

if [ -n "$GRUB_PASSPHRASE" ]; then
    sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="--users $GRUB_SUPERUSER"/' "$DEFAULTGRUB"
    echo "set superusers=$GRUB_SUPERUSER" >> /etc/grub.d/40_custom
    GRUB_PASS=$(expect_script "$1" | $EXPECT | sed -e "/^\r$/d" -e "/^$/d" -e "s/.* \(.*\)/\1/")
    echo "password_pbkdf2 $GRUB_SUPERUSER $GRUB_PASS" >> /etc/grub.d/40_custom
    echo 'export superusers' >> /etc/grub.d/40_custom
fi
################################################################################
# Disable AppPort(OK)
echo "Disabling apport"

sed -i 's/enabled=.*/enabled=0/' /etc/default/apport
systemctl mask apport.service

if [[ $VERBOSE == "Y" ]]; then
    systemctl status apport.service --no-pager
    echo
fi
################################################################################
# Disable unwanted services(OK)
echo "Disabling unwanted services"

for disable in $UNW_SERVICES; do
    systemctl disable $disable
done
################################################################################
# Disable unneeded kernel modules(OK)
echo "Disabling unwanted kernel modules"

for disable in $MOD; do
    if ! grep -q "$disable" "$DISABLEMOD" 2> /dev/null; then
        echo "install $disable /bin/true" >> "$DISABLEMOD"
    fi
done

if [[ $SERVER == "Y" ]]; then
    echo "install usb-storage /bin/true" >> "$DISABLEMOD"
fi
################################################################################
# Disable unneeded file systems(OK)
echo "Disabling unneeded file systems"
for disable in $UNW_FS; do
    if ! grep -q "$disable" "$DISABLEFS" 2> /dev/null; then
        echo "install $disable /bin/true" >> "$DISABLEFS"
    fi
done
################################################################################
# Securing Mounts(OK)
echo "Securing mounts"

cat > /etc/systemd/system/tmp.mount <<EOF
# /etc/systemd/system/default.target.wants/tmp.mount -> ../tmp.mount

[Unit]
Description=Temporary Directory
Documentation=man:hier(7)
Before=local-fs.target

[Mount]
What=tmpfs
Where=/tmp
Type=tmpfs
Options=mode=1777,strictatime,nosuid,nodev
EOF

sed -i '/floppy/d' /etc/fstab

if [ -e /etc/systemd/system/tmp.mount ]; then
    sed -i '/^\/tmp/d' /etc/fstab

    for t in $(mount | grep -e "[[:space:]]/tmp[[:space:]]" -e \
    "[[:space:]]/var/tmp[[:space:]]" -e "[[:space:]]/dev/shm[[:space:]]" \ | awk '{print $3}'); do
        umount "$t"
    done

    sed -i '/[[:space:]]\/tmp[[:space:]]/d' /etc/fstab

    ln -s /etc/systemd/system/tmp.mount /etc/systemd/system/default.target.wants/tmp.mount
    sed -i 's/Options=.*/Options=mode=1777,strictatime,nodev,nosuid/' /etc/systemd/system/tmp.mount

    cp /etc/systemd/system/tmp.mount /etc/systemd/system/var-tmp.mount
    sed -i 's/\/tmp/\/var\/tmp/g' /etc/systemd/system/var-tmp.mount
    ln -s /etc/systemd/system/var-tmp.mount /etc/systemd/system/default.target.wants/var-tmp.mount

    cp /etc/systemd/system/tmp.mount /etc/systemd/system/dev-shm.mount
    sed -i 's/\/tmp/\/dev\/shm/g' /etc/systemd/system/dev-shm.mount
    ln -s /etc/systemd/system/dev-shm.mount /etc/systemd/system/default.target.wants/dev-shm.mount
    sed -i 's/Options=.*/Options=mode=1777,strictatime,noexec,nosuid/' /etc/systemd/system/dev-shm.mount

    chmod 0644 /etc/systemd/system/tmp.mount
    chmod 0644 /etc/systemd/system/var-tmp.mount
    chmod 0644 /etc/systemd/system/dev-shm.mount

    systemctl daemon-reload
else
    echo '/etc/systemd/system/tmp.mount was not found.'
fi
################################################################################
# Disable unwanded and potentially dangerous protocols(OK)
echo "Disabling unwanded protocols.."
for disable in $UNW_PROT; do
    if ! grep -q "$disable" "$DISABLENET" 2> /dev/null; then
        echo "install $disable /bin/true" >> "$DISABLENET"
    fi
done
################################################################################
# Disable core dumps(OK)
echo "Disabling coredump"
sed -i 's/^#DumpCore=.*/DumpCore=no/' "$SYSTEMCONF"
sed -i 's/^#CrashShell=.*/CrashShell=no/' "$SYSTEMCONF"
sed -i 's/^#DefaultLimitCORE=.*/DefaultLimitCORE=0/' "$SYSTEMCONF"
sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE=100/' "$SYSTEMCONF"
sed -i 's/^#DefaultLimitNPROC=.*/DefaultLimitNPROC=100/' "$SYSTEMCONF"

sed -i 's/^#DefaultLimitCORE=.*/DefaultLimitCORE=0/' "$USERCONF"
sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE=100/' "$USERCONF"
sed -i 's/^#DefaultLimitNPROC=.*/DefaultLimitNPROC=100/' "$USERCONF"

systemctl daemon-reload

if test -f "$COREDUMPCONF"; then
    echo "Fixing Systemd/coredump.conf"
    sed -i 's/^#Storage=.*/Storage=none/' "$COREDUMPCONF"

    systemctl restart systemd-journald

    if [[ $VERBOSE == "Y" ]]; then
        systemctl status systemd-journald --no-pager
        echo
    fi
fi
################################################################################
# Configure sysctl parameters(OK)
echo "Configuring sysctl parameters..."

cat > $SYSCTL <<EOF
#
# /etc/sysctl.conf - Configuration file for setting system variables
# See /etc/sysctl.d/ for additional system variables.
# See sysctl.conf (5) for information.
#
# Documentation:
# "Draft Red Hat 7 STIG Version 1, Release 0.1"
# "Guide to the Secure Configuration of Red Hat Enterprise Linux 5"
# "CIS Ubuntu 12.04 LTS Server Benchmark v1.0.0"
# https://wiki.ubuntu.com/Security/Features
#

fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
kernel.core_uses_pid = 1
kernel.kptr_restrict = 2
kernel.panic = 60
kernel.panic_on_oops = 60
kernel.perf_event_paranoid = 2
kernel.randomize_va_space = 2
kernel.sysrq = 0
kernel.yama.ptrace_scope = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.default.rp_filter= 1
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.ip_forward = 0
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 5
net.ipv4.tcp_timestamps = 0
net.ipv4.conf.all.forwarding = 0
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.all.use_tempaddr = 2
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_ra = 0
net.ipv6.conf.default.accept_ra_defrtr = 0
net.ipv6.conf.default.accept_ra_pinfo = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.default.autoconf = 0
net.ipv6.conf.default.dad_transmits = 0
net.ipv6.conf.default.max_addresses = 1
net.ipv6.conf.default.router_solicitations = 0
net.ipv6.conf.default.use_tempaddr = 2
net.ipv6.conf.eth0.accept_ra_rtr_pref = 0
net.ipv6.conf.all.forwarding = 0
net.netfilter.nf_conntrack_max = 2000000
net.netfilter.nf_conntrack_tcp_loose = 0
EOF

sed -i '/net.ipv6.conf.eth0.accept_ra_rtr_pref/d' "$SYSCTL"

for i in $(arp -n -a | awk '{print $NF}' | sort | uniq); do
    echo "net.ipv6.conf.$i.accept_ra_rtr_pref = 0" >> "$SYSCTL"
done

echo 1048576 > /sys/module/nf_conntrack/parameters/hashsize

chmod 0600 "$SYSCTL"
systemctl restart systemd-sysctl

if [[ $VERBOSE == "Y" ]]; then
    systemctl status systemd-sysctl --no-pager
    echo
fi
################################################################################
# Configure user security limits(OK)
echo "Setting limits..."

sed -i 's/^# End of file*//' "$LIMITSCONF"
echo "* hard maxlogins 10" >> "$LIMITSCONF"
echo "* hard core 0" >> "$LIMITSCONF"
echo "* soft nproc 100" >> "$LIMITSCONF"
echo "* hard nproc 150" >> "$LIMITSCONF"
echo "# End of file" >> "$LIMITSCONF"
################################################################################
# Remove suid bits(OK)
echo "Removing suid bits"

for p in /bin/fusermount /bin/mount /bin/ping /bin/ping6 /bin/su /bin/umount \
         /usr/bin/bsd-write /usr/bin/chage /usr/bin/chfn /usr/bin/chsh \
         /usr/bin/mlocate /usr/bin/mtr /usr/bin/newgrp /usr/bin/pkexec \
         /usr/bin/traceroute6.iputils /usr/bin/wall /usr/sbin/pppd;
do
    if [ -e "$p" ]; then
        oct=$(stat -c "%a" $p |sed 's/^4/0/')
        ug=$(stat -c "%U %G" $p)
        dpkg-statoverride --remove $p 2> /dev/null
        dpkg-statoverride --add "$ug" "$oct" $p 2> /dev/null
        chmod -s $p
    fi
done

for SHELL in $(cat /etc/shells); do
    if [ -x "$SHELL" ]; then
        chmod -s "$SHELL"
    fi
done
################################################################################
# Set umask(OK)
echo "Setting umask..."
sed -i 's/umask 022/umask 027/g' /etc/init.d/rc

if ! grep -q -i "umask" "/etc/profile" 2> /dev/null; then
    echo "umask 027" >> /etc/profile
fi

if ! grep -q -i "umask" "/etc/bash.bashrc" 2> /dev/null; then
    echo "umask 027" >> /etc/bash.bashrc
fi
################################################################################
# Lock up CTRL+ALT+DEL(OK)
echo "Lockup Ctrl-alt-delete"

systemctl mask ctrl-alt-del.target

if [[ $VERBOSE == "Y" ]]; then
    systemctl status ctrl-alt-del.target --no-pager
    echo
fi
################################################################################
# Disable root logins(OK)
echo "Disabling root logins..."

sed -i 's/^#+ : root : 127.0.0.1/+ : root : 127.0.0.1/' "$SECURITYACCESS"
echo '' > /etc/securetty
################################################################################
# Secure user and services host files(OK)
echo "Securing .rhosts and hosts.equiv"

for dir in $(awk -F ":" '{print $6}' /etc/passwd); do
    find "$dir" \( -name "hosts.equiv" -o -name ".rhosts" \) -exec rm -f {} \; 2> /dev/null
done
    
if [[ -f /etc/hosts.equiv ]]; then
    rm /etc/hosts.equiv
fi
################################################################################
# Configure Banners(OK)
echo "Configuring Banners..."

for f in /etc/issue /etc/issue.net /etc/motd; do
    TEXT="\nAuthorized users only. All activity may be monitored and reported.\n"
    echo -e "$TEXT" > $f
done
################################################################################
# Configure TCP Wrappers(OK)
echo "Configuring TCP Wrappers"

if [[ $SERVER == "Y" ]]; then
    echo "sshd : ALL : ALLOW" > /etc/hosts.allow
fi
echo "ALL: LOCAL, 127.0.0.1" >> /etc/hosts.allow
echo "ALL: PARANOID" > /etc/hosts.deny
chmod 644 /etc/hosts.allow
chmod 644 /etc/hosts.deny
################################################################################
# Configure logindefs(OK)
echo "Configuring logindefs..."

sed -i 's/^.*LOG_OK_LOGINS.*/LOG_OK_LOGINS\t\tyes/' "$LOGINDEFS"
sed -i 's/^UMASK.*/UMASK\t\t077/' "$LOGINDEFS"
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\t\t7/' "$LOGINDEFS"
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t\t30/' "$LOGINDEFS"
sed -i 's/DEFAULT_HOME.*/DEFAULT_HOME no/' "$LOGINDEFS"
sed -i 's/USERGROUPS_ENAB.*/USERGROUPS_ENAB no/' "$LOGINDEFS"
sed -i 's/^# SHA_CRYPT_MAX_ROUNDS.*/SHA_CRYPT_MAX_ROUNDS\t\t10000/' "$LOGINDEFS"
################################################################################
# Configure loginconf(OK)
echo "Configuring logind..."

sed -i 's/^#KillUserProcesses=no/KillUserProcesses=1/' "$LOGINDCONF"
sed -i 's/^#KillExcludeUsers=root/KillExcludeUsers=root/' "$LOGINDCONF"
sed -i 's/^#IdleAction=ignore/IdleAction=lock/' "$LOGINDCONF"
sed -i 's/^#IdleActionSec=30min/IdleActionSec=15min/' "$LOGINDCONF"
sed -i 's/^#RemoveIPC=yes/RemoveIPC=yes/' "$LOGINDCONF"

systemctl daemon-reload
################################################################################
# Locking new user shell by default(OK)
echo "Setting new user settings..."

sed -i 's/DSHELL=.*/DSHELL=\/bin\/false/' "$ADDUSER"
sed -i 's/SHELL=.*/SHELL=\/bin\/false/' "$USERADD"
sed -i 's/^# INACTIVE=.*/INACTIVE=35/' "$USERADD"
################################################################################
# Apply account password policy(OK)
echo "Applying Account password Policy..."

sed -i 's/^password[\t].*.pam_cracklib.*/password\trequired\t\t\tpam_cracklib.so retry=3 maxrepeat=3 minlen=15 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1 difok=8/' "$COMMONPASSWD"
sed -i 's/try_first_pass sha512.*/try_first_pass sha512 remember=5/' "$COMMONPASSWD"
sed -i 's/nullok_secure//' "$COMMONAUTH"

if ! grep tally "$COMMONAUTH"; then
    sed -i '/^$/a auth required pam_tally.so file=/var/log/faillog deny=5 unlock_time=900' "$COMMONAUTH"
    sed -i '/pam_tally.so/d' "$COMMONACCOUNT"
    echo 'account required pam_tally.so reset' >> "$COMMONACCOUNT"
fi

sed -i 's/pam_lastlog.so.*/pam_lastlog.so showfailed/' "$PAMLOGIN"
sed -i 's/delay=.*/delay=4000000/' "$PAMLOGIN"
################################################################################
# Lock out root account(OK)
echo "Locking out root account..."

usermod -L root

if [[ $VERBOSE == "Y" ]]; then
    passwd -S root
    echo
fi
################################################################################
# Remove unneeded users(OK)
echo "Removing unwanted users"

for users in games gnats irc list news uucp; do
    userdel -r "$users" 2> /dev/null
done
################################################################################
# Secure Apache(OK)
chmod 511 /usr/sbin/apache2
chown 0:0 /usr/sbin/apache2
chattr +i /etc/apache2/apache2.conf

a2dismod autoindex

cat > "$APACHE2DFILE" <<EOF
<Directory />
  Order Deny,Allow
  Deny from all
  Options None
  AllowOverride None
</Directory>

<Directory /var/www/>
    Order Allow,Deny
    Allow from all
    Options +FollowSymLinks -Indexes +IncludesNoExec
    AllowOverride None
    Require all granted
</Directory>

ServerSignature Off
ServerTokens Prod
TraceEnable Off
EOF

a2enconf custom_secure

# Enable mod_security
mv /etc/modsecurity/modsecurity.conf-recommended $MODSEC
sed -i 's/.*SecRuleEngine.*/SecRuleEngine On/' "$MODSEC"
sed -i 's/.*SecRequestBodyLimit.*/SecRequestBodyLimit 16384000/' "$MODSEC"
sed -i 's/.*SecRequestBodyInMemoryLimit.*/SecRequestBodyInMemoryLimit 16384000/' "$MODSEC"

wget -O /tmp/SpiderLabs-owasp-modsecurity-crs.tar.gz https://github.com/SpiderLabs/owasp-modsecurity-crs/tarball/master
cd /tmp
tar -zxvf ./SpiderLabs-owasp-modsecurity-crs.tar.gz
cp -R SpiderLabs-owasp-modsecurity-crs-*/* /etc/modsecurity/
rm -R SpiderLabs-owasp-modsecurity-crs-*
mv /etc/modsecurity/modsecurity_crs_10_setup.conf.example /etc/modsecurity/modsecurity_crs_10_setup.conf

cd /etc/modsecurity/base_rules
for f in * ; do sudo ln -s /etc/modsecurity/base_rules/$f /etc/modsecurity/activated_rules/$f ; done
cd /etc/modsecurity/optional_rules
for f in * ; do sudo ln -s /etc/modsecurity/optional_rules/$f /etc/modsecurity/activated_rules/$f ; done

cat > /etc/apache2/mods-available/security2.conf <<EOF
<IfModule security2_module>
        # Default Debian dir for modsecurity's persistent data
        SecDataDir /var/cache/modsecurity

        # Include all the *.conf files in /etc/modsecurity.
        # Keeping your local configuration in that directory
        # will allow for an easy upgrade of THIS file and
        # make your life easier
        IncludeOptional /etc/modsecurity/*.conf
        IncludeOptional /etc/modsecurity/activated_rules/*.conf
</IfModule>
EOF

# Enable mod_evasive
mkdir /var/log/mod_evasive
chown www-data:www-data /var/log/mod_evasive/

cat > /etc/apache2/mods-available/evasive.conf <<EOF
<ifmodule mod_evasive20.c>
   DOSHashTableSize 3097
   DOSPageCount  2
   DOSSiteCount  50
   DOSPageInterval 1
   DOSSiteInterval  1
   DOSBlockingPeriod  10
   DOSLogDir   /var/log/mod_evasive
   DOSEmailNotify  root@localhost
   DOSWhitelist   127.0.0.1
</ifmodule>
EOF

a2enmod ssl evasive security2 headers
service apache2 restart

# Enable fail2ban
cat >> /etc/fail2ban/jail.d/defaults-debian.conf <<EOF

[apache-modsecurity]
enabled = true

[apache-shellshock]
enabled = true
EOF

service fail2ban restart
################################################################################
# Secure NFS(OK)
echo "Enabling Kerberos Authentication fos NFS4"
sed -i 's/.*NEED_SVCGSSD=.*/NEED_SVCGSSD=yes/' /etc/default/nfs-kernel-server
################################################################################
# Configure sshd server(OK)
echo "Configuring sshd..."

cp "$SSHDFILE" "$SSHDFILE-$(date +%s)"

sed -i '/HostKey.*ssh_host_dsa_key.*/d' "$SSHDFILE"
sed -i 's/.*AuthenticationMethods.*/AuthenticationMethods publickey,gssapi-with-mic publickey,keyboard-interactive/' "$SSHDFILE"
sed -i 's/.*X11Forwarding.*/X11Forwarding no/' "$SSHDFILE"
sed -i 's/.*Port.*/Port 1027/' "$SSHDFILE"
sed -i 's/.*LoginGraceTime.*/LoginGraceTime 20/' "$SSHDFILE"
sed -i 's/.*PermitRootLogin.*/PermitRootLogin no/' "$SSHDFILE"
sed -i 's/.*KeyRegenerationInterval.*/KeyRegenerationInterval 1800/' "$SSHDFILE"
sed -i 's/.*UsePrivilegeSeparation.*/UsePrivilegeSeparation sandbox/' "$SSHDFILE"
sed -i 's/.*LogLevel.*/LogLevel VERBOSE/' "$SSHDFILE"
sed -i 's/.*UseLogin.*/UseLogin no/' "$SSHDFILE"
sed -i 's/.*Banner.*/Banner \/etc\/issue.net/' "$SSHDFILE"
sed -i 's/.*Subsystem sftp.*/Subsystem sftp \/usr\/lib\/ssh\/sftp-server -f AUTHPRIV -l INFO/' "$SSHDFILE"

if ! grep -q "AllowGroups" "$SSHDFILE" 2> /dev/null; then
    echo "AllowGroups $SSH_GROUPS" >> "$SSHDFILE"
fi

if ! grep -q "MaxAuthTries" "$SSHDFILE" 2> /dev/null; then
    echo "MaxAuthTries 4" >> "$SSHDFILE"
fi

if ! grep -q "ClientAliveInterval" "$SSHDFILE" 2> /dev/null; then
    echo "ClientAliveInterval 300" >> "$SSHDFILE"
fi

if ! grep -q "ClientAliveCountMax" "$SSHDFILE" 2> /dev/null; then
    echo "ClientAliveCountMax 0" >> "$SSHDFILE"
fi

if ! grep -q "PermitUserEnvironment" "$SSHDFILE" 2> /dev/null; then
    echo "PermitUserEnvironment no" >> "$SSHDFILE"
fi

if ! grep -q "KexAlgorithms" "$SSHDFILE" 2> /dev/null; then
    echo 'KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256' >> "$SSHDFILE"
fi

if ! grep -q "Ciphers" "$SSHDFILE" 2> /dev/null; then
    echo 'Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes256-ctr' >> "$SSHDFILE"
fi

if ! grep -q "Macs" "$SSHDFILE" 2> /dev/null; then
    echo 'Macs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256' >> "$SSHDFILE"
fi

if ! grep -q "MaxSessions" "$SSHDFILE" 2> /dev/null; then
    echo "MaxSessions 2" >> "$SSHDFILE"
fi

if ! grep -q "UseDNS" "$SSHDFILE" 2> /dev/null; then
    echo "UseDNS yes" >> "$SSHDFILE"
fi

# Fail2Ban is already enabled by default for sshd
# Restarting Service
systemctl restart sshd.service

if [[ $VERBOSE == "Y" ]]; then
    systemctl status sshd.service --no-pager
    echo
fi
################################################################################
# Lock up cronjobs(OK)
echo "Locking up cronjobs..."

rm /etc/cron.deny 2> /dev/null
rm /etc/at.deny 2> /dev/null

echo 'root' > /etc/cron.allow
echo 'root' > /etc/at.allow

chown root:root /etc/cron*
chmod og-rwx /etc/cron*

chown root:root /etc/at*
chmod og-rwx /etc/at*

systemctl mask atd.service
systemctl stop atd.service
systemctl daemon-reload

sed -i 's/^#cron./cron./' /etc/rsyslog.d/50-default.conf

if [[ $VERBOSE == "Y" ]]; then
    systemctl status atd.service --no-pager
    echo
fi
################################################################################
# Configure UFW(OK)
echo "Configuring Firewall.."
sed -i 's/IPT_SYSCTL=.*/IPT_SYSCTL=\/etc\/sysctl\.conf/' "$UFWDEFAULT"
ufw --force enable

for ip in $FW_LOCAL; do
    ufw allow log from "$ip" to any port 1027 proto tcp # SSH
done

if [[ $SERVER == "Y" ]]; then
    ufw allow proto tcp from any to any port 1027 #SSH
    ufw allow http
    ufw allow samba
    ufw allow nfs
fi

if [[ $VERBOSE == "Y" ]]; then
    systemctl status ufw.service --no-pager
    ufw status verbose
    echo
fi
################################################################################
# Disable IPV6(OK)
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="ipv6.disable=1"/' "$DEFAULTGRUB"
update-grub

sed '/udp6/d' /etc/netconfig
sed '/tcp6/d' /etc/netconfig 
################################################################################
# Configure DNS resolvers(OK)
echo "Confuguring DNS..."

dnsarray=( $(grep nameserver /etc/resolv.conf | sed 's/nameserver//g') )
dnslist=${dnsarray[@]}

sed -i "s/^#DNS=.*/DNS=$dnslist/" "$RESOLVEDCONF"
sed -i "s/^#FallbackDNS=.*/FallbackDNS=8.8.8.8 8.8.4.4/" "$RESOLVEDCONF"
sed -i "s/^#DNSSEC=.*/DNSSEC=allow-downgrade/" "$RESOLVEDCONF"
sed -i '/^hosts:/ s/files dns/files resolve dns/' /etc/nsswitch.conf

systemctl daemon-reload

if [[ $VERBOSE == "Y" ]]; then
    systemctl status resolvconf.service --no-pager
    echo
fi
################################################################################
# Securing NTP(OK)
echo "Securing NTP..."

LATENCY="50"
SERVERS="4"
APPLY="YES"
CONF="$TIMESYNCD"
SERVERARRAY=()
FALLBACKARRAY=()
TMPCONF=$(mktemp --tmpdir ntpconf.XXXXX)

if [[ -z "$NTPSERVERPOOL" ]]; then
    NTPSERVERPOOL="0.ubuntu.pool.ntp.org 1.ubuntu.pool.ntp.org \
    2.ubuntu.pool.ntp.org 3.ubuntu.pool.ntp.org pool.ntp.org"
fi

echo "[Time]" > "$TMPCONF"

PONG="ping -c2"

for s in $(dig +noall +answer +nocomments $NTPSERVERPOOL | awk '{print $5}'); do
    if [[ $NUMSERV -ge $SERVERS ]]; then
        break
    fi

    PINGSERV=$($PONG "$s" | grep 'rtt min/avg/max/mdev' | awk -F "/" '{printf "%.0f\n",$6}')
    if [[ $PINGSERV -gt "1" && $PINGSERV -lt "$LATENCY" ]]; then
        OKSERV=$(nslookup "$s"|grep "name = " | awk '{print $4}'|sed 's/.$//')
        if [[ $OKSERV && $NUMSERV -lt $SERVERS && ! (( $(grep "$OKSERV" "$TMPCONF") )) ]]; then
            echo "$OKSERV has latency < $LATENCY"
            SERVERARRAY+=("$OKSERV")
            ((NUMSERV++))
        fi
    fi
done

for l in $NTPSERVERPOOL; do
    if [[ $FALLBACKSERV -le "2" ]]; then
        FALLBACKARRAY+=("$l")
        ((FALLBACKSERV++))
    else
        break
    fi
done

    if [[ ${#SERVERARRAY[@]} -le "2" ]]; then
        for s in $(echo "$NTPSERVERPOOL" | awk '{print $(NF-1),$NF}'); do
            SERVERARRAY+=("$s")
        done
    fi

    echo "NTP=${SERVERARRAY[@]}" >> "$TMPCONF"
    echo "FallbackNTP=${FALLBACKARRAY[@]}" >> "$TMPCONF"

    if [[ $APPLY = "YES" ]]; then
        cat "$TMPCONF" > "$CONF"
        systemctl restart systemd-timesyncd
        rm "$TMPCONF"
    else
        echo "Configuration saved to $TMPCONF."
    fi

    if [[ $VERBOSE == "Y" ]]; then
        systemctl status systemd-timesyncd --no-pager
        echo
    fi
################################################################################
# Configure logrotate(OK)
echo "Configuring logrotate..."

cat > "$LOGROTATE" <<EOF
# see "man logrotate" for details
# rotate log files daily
daily

# use the syslog group by default, since this is the owning group
# of /var/log/syslog.
su root syslog

# keep 7 days worth of backlogs
rotate 7

# create new (empty) log files after rotating old ones
create

# use date as a suffix of the rotated file
dateext

# compressed log files
compress

# use xz to compress
compresscmd /usr/bin/xz
uncompresscmd /usr/bin/unxz
compressext .xz

# packages drop log rotation information into this directory
include /etc/logrotate.d

# no packages own wtmp and btmp -- we'll rotate them here
/var/log/wtmp {
    monthly
    create 0664 root utmp
    minsize 1M
    rotate 1
}

/var/log/btmp {
    missingok
    monthly
    create 0600 root utmp
    rotate 1
}

# system-specific logs may be also be configured here.
EOF

sed -i 's/^#Storage=.*/Storage=persistent/' "$JOURNALDCONF"
sed -i 's/^#ForwardToSyslog=.*/ForwardToSyslog=yes/' "$JOURNALDCONF"
sed -i 's/^#Compress=.*/Compress=yes/' "$JOURNALDCONF"

systemctl restart systemd-journald

if [[ $VERBOSE == "Y" ]]; then
    systemctl status systemd-journald --no-pager
    echo
fi
################################################################################
# Enforcing auditd rules
echo "Enforcing Auditd rules..."
sed -i 's/^action_mail_acct =.*/action_mail_acct = root/' "$AUDITDCONF"
sed -i 's/^admin_space_left_action = .*/admin_space_left_action = halt/' "$AUDITDCONF"
sed -i 's/^max_log_file_action =.*/max_log_file_action = keep_logs/' "$AUDITDCONF"
sed -i 's/^space_left_action =.*/space_left_action = email/' "$AUDITDCONF"
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="ipv6.disable=1 audit=1"/' "$DEFAULTGRUB"

cat > /etc/audit/audit.rules <<EOF
## Remove any existing rules
-D

## Buffer Size
-b 8192

## Failure Mode
-f 2

## Audit the audit logs 
-w /var/log/audit/ -k auditlog

## Auditd configuration
-w /etc/audit/ -p wa -k auditconfig
-w /etc/libaudit.conf -p wa -k auditconfig
-w /etc/audisp/ -p wa -k audispconfig

## Monitor for use of audit management tools
-w /sbin/auditctl -p x -k audittools
-w /sbin/auditd -p x -k audittools

## Monitor AppArmor configuration changes
-w /etc/apparmor/ -p wa -k apparmor
-w /etc/apparmor.d/ -p wa -k apparmor

## Monitor usage of AppArmor tools
-w /sbin/apparmor_parser -p x -k apparmor_tools
-w /usr/sbin/aa-complain -p x -k apparmor_tools
-w /usr/sbin/aa-disable -p x -k apparmor_tools
-w /usr/sbin/aa-enforce -p x -k apparmor_tools

## Monitor Systemd configuration changes
-w /etc/systemd/ -p wa -k systemd
-w /lib/systemd/ -p wa -k systemd

## Monitor usage of systemd tools
-w /bin/systemctl -p x -k systemd_tools
-w /bin/journalctl -p x -k systemd_tools 

## Special files
-a always,exit -F arch=b64 -S mknod -S mknodat -k specialfiles

## Mount operations
-a always,exit -F arch=b64 -S mount -S umount2 -k mount 

## Changes to the time
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -S clock_settime -k time

## Cron configuration & scheduled jobs
-w /etc/cron.allow -p wa -k cron
-w /etc/cron.deny -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /etc/cron.daily/ -p wa -k cron
-w /etc/cron.hourly/ -p wa -k cron
-w /etc/cron.monthly/ -p wa -k cron
-w /etc/cron.weekly/ -p wa -k cron
-w /etc/crontab -p wa -k cron
-w /var/spool/cron/crontabs/ -k cron

## User, group, password databases
-w /etc/group -p wa -k etcgroup
-w /etc/passwd -p wa -k etcpasswd
-w /etc/gshadow -k etcgroup
-w /etc/shadow -k etcpasswd
-w /etc/security/opasswd -k opasswd

## Monitor usage of passwd
-w /usr/bin/passwd -p x -k passwd_modification

## Monitor for use of tools to change group identifiers
-w /usr/sbin/groupadd -p x -k group_modification
-w /usr/sbin/groupmod -p x -k group_modification
-w /usr/sbin/addgroup -p x -k group_modification
-w /usr/sbin/useradd -p x -k user_modification
-w /usr/sbin/usermod -p x -k user_modification
-w /usr/sbin/adduser -p x -k user_modification

## Monitor module tools
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules

## Login configuration and information
-w /etc/login.defs -p wa -k login
-w /etc/securetty -p wa -k login
-w /var/log/faillog -p wa -k login
-w /var/log/lastlog -p wa -k login
-w /var/log/tallylog -p wa -k login

## Network configuration
-w /etc/hosts -p wa -k hosts
-w /etc/network/ -p wa -k network

## System startup scripts
-w /etc/inittab -p wa -k init
-w /etc/init.d/ -p wa -k init
-w /etc/init/ -p wa -k init

## Library search paths
-w /etc/ld.so.conf -p wa -k libpath

## Local time zone
-w /etc/localtime -p wa -k localtime

## Time zone configuration
-w /etc/timezone -p wa -k timezone

## Kernel parameters
-w /etc/sysctl.conf -p wa -k sysctl

## Modprobe configuration
-w /etc/modprobe.conf -p wa -k modprobe
-w /etc/modprobe.d/ -p wa -k modprobe
-w /etc/modules -p wa -k modprobe

# Module manipulations.
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules

## PAM configuration
-w /etc/pam.d/ -p wa -k pam
-w /etc/security/limits.conf -p wa -k pam
-w /etc/security/pam_env.conf -p wa -k pam
-w /etc/security/namespace.conf -p wa -k pam
-w /etc/security/namespace.init -p wa -k pam

## Postfix configuration
-w /etc/aliases -p wa -k mail
-w /etc/postfix/ -p wa -k mail

## SSH configuration
-w /etc/ssh/sshd_config -k sshd

## Changes to hostname
-a exit,always -F arch=b64 -S sethostname -k hostname

## Changes to issue
-w /etc/issue -p wa -k etcissue
-w /etc/issue.net -p wa -k etcissue

## Capture all failures to access on critical elements
-a exit,always -F arch=b64 -S open -F dir=/etc -F success=0 -k unauthedfileaccess
-a exit,always -F arch=b64 -S open -F dir=/bin -F success=0 -k unauthedfileaccess
-a exit,always -F arch=b64 -S open -F dir=/sbin -F success=0 -k unauthedfileaccess
-a exit,always -F arch=b64 -S open -F dir=/usr/bin -F success=0 -k unauthedfileaccess
-a exit,always -F arch=b64 -S open -F dir=/usr/sbin -F success=0 -k unauthedfileaccess
-a exit,always -F arch=b64 -S open -F dir=/var -F success=0 -k unauthedfileaccess
-a exit,always -F arch=b64 -S open -F dir=/home -F success=0 -k unauthedfileaccess
-a exit,always -F arch=b64 -S open -F dir=/root -F success=0 -k unauthedfileaccess
-a exit,always -F arch=b64 -S open -F dir=/srv -F success=0 -k unauthedfileaccess
-a exit,always -F arch=b64 -S open -F dir=/tmp -F success=0 -k unauthedfileaccess

## Monitor for use of process ID change (switching accounts) applications
-w /bin/su -p x -k priv_esc
-w /usr/bin/sudo -p x -k priv_esc
-w /etc/sudoers -p rw -k priv_esc

## Monitor usage of commands to change power state
-w /sbin/shutdown -p x -k power
-w /sbin/poweroff -p x -k power
-w /sbin/reboot -p x -k power
-w /sbin/halt -p x -k power

## Monitor admins accessing user files.
-a always,exit -F dir=/home/ -F uid=0 -C auid!=obj_uid -k admin_user_home

## Monitor changes and executions in /tmp and /var/tmp.
-w /tmp/ -p wxa -k tmp
-w /var/tmp/ -p wxa -k tmp

## Make the configuration immutable
-e 2
EOF

sed -i "s/arch=b64/arch=$(uname -m)/g" /etc/audit/audit.rules
cp /etc/audit/audit.rules "$AUDITRULES"
update-grub 2> /dev/null

systemctl enable auditd
systemctl restart auditd.service

if [[ $VERBOSE == "Y" ]]; then
    systemctl status auditd.service --no-pager
    echo
fi
################################################################################
# Enable RKHUNTER(OK)
echo "Enabling rkhunter..."

sed -i 's/^CRON_DAILY_RUN=.*/CRON_DAILY_RUN="yes"/' "$RKHUNTERCONF"
sed -i 's/^APT_AUTOGEN=.*/APT_AUTOGEN="yes"/' "$RKHUNTERCONF"

rkhunter --propupd
################################################################################
# Enable CLAMAV(OK)
echo "Enabling CLAMAV..."
service clamav-daemon start
freshclam
service clamav-freshclam start

echo > /etc/cron.daily/user_clamscan <<EOF
#!/bin/bash
SCAN_DIR="/home"
LOG_FILE="/var/log/clamav/user_clamscan.log"
/usr/bin/clamscan -i -r $SCAN_DIR >> $LOG_FILE
EOF

chmod +x /etc/cron.daily/user_clamscan
################################################################################
# Disable Prelinking(OK)
 echo "Disabling Prelink for AIDE..."

if dpkg -l | grep prelink 1> /dev/null; then
    "$(which prelink)" -ua 2> /dev/null
    "$APT" purge prelink
fi
################################################################################
# Secure AIDE Configuration(OK)
echo "Securing Aide..."

sed -i 's/^Checksums =.*/Checksums = sha512/' /etc/aide/aide.conf
################################################################################
# Set AIDE Postinstall(OK)
echo "Building AIDE initial db, this will take a while..."

aideinit --yes
cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

echo "Enabling AIDE check daily..."

cat > /etc/systemd/system/aidecheck.service <<EOF
[Unit]
Description=Aide Check

[Service]
Type=simple
ExecStart=/usr/bin/aide.wrapper --check

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/aidecheck.timer <<EOF
[Unit]
Description=Aide check every day at midnight

[Timer]
OnCalendar=*-*-* 00:00:00
Unit=aidecheck.service

[Install]
WantedBy=multi-user.target
EOF

chmod 0644 /etc/systemd/system/aidecheck.*

systemctl reenable aidecheck.timer
systemctl start aidecheck.timer
systemctl daemon-reload

if [[ $VERBOSE == "Y" ]]; then
    systemctl status aidecheck.timer --no-pager
    echo
fi
################################################################################
# Remove unused packages(OK)
echo "Removing unused packages..."

$APT purge expect

if [[ $SERVER == "Y" ]]; then
    echo "Removing X-Window System"
    $APT purge x-window-system-core
    echo
fi

$APT clean
$APT autoclean
$APT autoremove
################################################################################
# Check systemddelta(OK)
if [[ $VERBOSE == "Y" ]]; then
    echo "Checking systemd-delta..."
    systemd-delta --no-pager
    echo
fi
################################################################################
# check if reboot is required(OK)
if [ -f /var/run/reboot-required ]; then
    cat /var/run/reboot-required
fi

echo
