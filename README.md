# **Projet_Linux_HEH_25**
*2025 Linux Project Haute Ecole En Hainaut*

## Team
Our team is made of two Bac2 Student in CyberSecurity option  
- Kozlenko Anastasiia
- Deneyer Tom

## Hardware configuration
Our project is based on multiple virtual machines located in AWS Cloud (EC2)  
Here is a list of our virtual machines.
- DNS + NTP Server
- FTP + Web Server
- Backend Server
- Admin + Backup Server
- VPN for cloud access (using public ip elastic)

## Deployment
All setup scripts are totaly usable for a complete deployment of all services covered. The setup_server_base.sh must be used first then the others setup.

## Project structure
Here is how files are saved into thi repository, scripts, configs and docs... 
```text
    / (repo root)
    ├── README.md                          # You are Here
    ├── setup_env.sh
    ├── scripts/
    │   ├── setup_dns.sh
    │   ├── setup_ftp.sh
    │   ├── setup_web.sh
    |   ├── utils_add_user.sh
    |   ├── automation_backup.sh
    ├── configs/
    │   ├── dns/
    │   │   └── named.conf
    │   │   └── forward.tomananas.lan
    │   │   └── reverse.tomananas.lan
    │   ├── web/
    │   │   └── httpd.conf
    │   └── ftp/
    │       └── vsftpd.conf
    │   └── samba/
    │       └── smb.conf
    │   └── ntp/
    │       └── server_chronny.conf
    │       └── client_chronny.conf
    │   └── firewall/
    │       └── allservers...
    ├── docs/
    │   ├── netdata_dashboards/
    │   ├── netdata_emails_alerts/
```
### Environment Script
`setup_env.sh` is a bash script exporting all environments variables used in all other scripts, such as:   
- Network configurations
- Paths to important folders & files
- Names used
- Based variables for all scripts

### Scripts
All executable scripts must be placed into the `/scripts/` in this repository.  
Bash scripts can be executed on any virtual machines used during the projet.

Types of script:   
- setup_*service* : Full configuration of a *service* specified after the `setup_`  
- utils_*action* : Scripts used for specific automated *action* specified after the `utils_`

### Configs
All saved configuration files are saved into /configs/*service*  
.conf files must be placed into specified folder named with the *service* name (dns, ftp...).

### Docs 
All documentation files are placed into /docs/  
Reports, design docs, ressources and others...

## Bible
### Files and variables
Folders, files, simple variables and others must use *snake_case* convention. For instance:
**OKAY**   
- `my_local_variable`
- `/home/my_first_user_here/his_personal_folder/`
- `/backup/backup_name`   
**NOT OKAY**    
- `myLocalVariable`
- `/home/MYFIRSTUSERHERE/HisPersonalFolder`
- `/BACKUP/backup-name`   
   
Environment variables exported must be *UPPER_SNAKE_CASE* convention. For instance:
**OKAY**    
- `MY_VARIABLE`
- `SSH_PORT`
- `IPV4_GATEWAY`   
**NOT OKAY**
- `my_variable`
- `sshPort` 
- `Ipv4Gateway`   
   
### Git/Github
Commit must follow regular angular commit convention, please follow the link bellow for futher informations  
[Angular Commit Convention](https://www.conventionalcommits.org/en/v1.0.0-beta.4/)