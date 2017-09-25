# backup-toolkit
Collection of scripts for various backup scenarios.

**DISCLAIMER:**
I take no responsibility for anything you find here. You are on your own using this and there is no guarantee
that it will work for you. Please don't blame me for your damaged data - always test things like this on separated,
safe environment first. You have been warned.

## lvm-backup
Automation wrapper written in **Bash** to create backups of **LVM partitions**
(with [LVM snapshots](http://www.tldp.org/HOWTO/LVM-HOWTO/snapshots_backup.html)) using
**[Bup](https://github.com/bup/bup)**.

    One *script* to rule them all, one *script* to find them,
    One *script* to bring them all and in the darkness bind them.

#### Features
* Match volume groups and logical volumes to backup using **regex**.
* Specify directories/files to exclude from backup using **regex**.
* Define how much space should be retained on volume groups during snapshot creation phase.
* Set desired backup compression level (0-9) *(Bup feature)*.
* Generate backup recovery blocks to protect against disk errors *(Bup feature)*.
* Lower backup process priorities by wrapping them with **nice** and **ionice**.
* Print each indexed file with it's status (A, M, D, or space) *(Bup feature)*.
* Fancy, colorized console output.

#### Drawbacks
* Because of LVM management, this script requires **root** privileges.

#### Dependencies
* lvm2
* git
* bup
* par2

#### Usage

1) Initialize Bup repository in your backup target location (specify ``BUP_DIR`` variable):
```bash
BUP_DIR=/backup/.bup bup init
```

2) Customize ``lvm-backup.cfg`` configuration file with your volume groups, logical volumes, backup target, etc.
* **Hint:** You can create as many configuration files as you want - to control which one is used, pass
``--config=<file>`` flag.

3) Backup your data:
```bash
./lvm-backup.sh
```
* **Hint:** You can automate the backup procedure by passing ``--non-interactive`` flag (and, for example, run
it periodically using [*systemd timers*](https://wiki.archlinux.org/index.php/Systemd/Timers) or
old-fashioned *cron*).

4) Inspect your backup:
```bash
BUP_DIR=/backup/.bup bup ls -l --human-readable
```
Following command will print all your backups. You can use it pretty much the same as normal ``ls`` command to
browse the data structure.

5) Restore your data:
```bash
BUP_DIR=/backup/.bup bup restore -C /tmp/test /myhost-root/latest/.
```
This example will restore ``latest`` backup of ``root`` partition from ``myhost`` to ``/tmp/test`` (it's a good
practice to test your backups for your extra confidence).

For more restore examples see
[official *bup-restore* documentation](https://github.com/bup/bup/blob/master/Documentation/bup-restore.md).
