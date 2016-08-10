# Ubuntu-Xenial-Security
Ubuntu Xenial Security Hardening with Documentation.

To enforce the security settings and policies for Ubuntu Xenial,
a bash script was developed. The script makes the following changes
to the system:

Installs needed packages

Sets Auto-installation of security updates via cronjob

Enforces AppArmor

Secures the bootloader

Disables AppPort

Disables unwanted services

Disables unneeded kernel modules

Disables unneeded file systems

Secures Mounts

Disables unwanded and potentially dangerous protocols

Disables creation of user and system core dumps

Configures sysctl parameters

Configures user security limits

Removes suid bits from certain executables

Sets global system umask to 027

Locks up CTRL+ALT+DEL

Disables root logins - Locks out root account

Secures user and services hosts files

Configures Banners

Configures TCP Wrappers

Applies account password policy

Removes unneeded users

Secures Apache Server

Secure NFS Server

Secures SSHD server

Locks up cronjobs for users other than root

Configures UFW

Disables IPV6

Configures secure DNS resolvers

Secures NTP Client

Configures logrotate

Enforces auditd rules

Enables RKHUNTER

Enables CLAMAV

Sets AIDE

Tasks that required interactive input from the user, such as keys 
from OSSIM Server or setting Splunk forwarder to an indexing server, 
where skipped intentionally, but the user can easily set them up by 
copy-pasting the commands from the appropriate sections of the 
documentation, to the system console.

Script and documentation based heavily on RHEL7 Security Guide
(https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/pdf/Security_Guide/Red_Hat_Enterprise_Linux-7-Security_Guide-en-US.pdf) and https://github.com/konstruktoid/hardening, among others.
