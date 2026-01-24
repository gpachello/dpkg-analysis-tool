# dpkg-analysis-tool

Dependency impact analysis tool for **dpkg/apt** on Debian-based systems.

This project provides a **safe, non-destructive way** to analyze what would happen if installed packages were purged from a system. It is designed to help understand **dependency impact**, **critical components**, and **system minimalism efforts** *before* taking any irreversible actions.

> ⚠️ **Important**: This tool does **NOT** remove packages. It relies exclusively on `apt-get -s` (simulation mode).

---

## Motivation

When attempting to reduce, harden, or specialize a Debian system (servers, VMs, containers, appliances), the main challenge is not *how* to remove packages, but **understanding the consequences**.

Removing the wrong package can:

* Break the boot process
* Remove networking
* Leave the system unmanageable

This tool was created to answer a simple but critical question:

> **"If I purge this package, what else goes with it?"**

It also introduces the concept of **explicitly protected packages**, beyond Debian's own `Essential: yes` flag.

---

## Design Principles

* **Analysis first, action later**
* **No destructive operations**
* **Explicit protection layers**
* **Human-readable output**
* **Shell-first, no unnecessary abstractions**

JSON, databases, or complex formats are deliberately avoided unless they provide *real, measurable value*.

---

## Features

* Enumerates all installed packages using `dpkg-query`
* Simulates `apt-get purge` for each package
* Counts dependent packages that would be removed
* Detects and skips:

  * `Essential: yes` packages
  * Whitelisted packages
  * Critical packages grouped by category
* Produces a consolidated **summary report**
* Generates per-package simulation logs

---

## Protection Layers

Packages can be excluded from purge simulation for different reasons:

### 1. Essential Packages

Detected automatically via:

```
dpkg-query -W -f='${Essential}'
```

Reported as:

```
package-name : skip [ESSENTIAL]
```

---

### 2. Whitelist

Manually defined list of packages that must never be considered for removal.

**Example (`whitelist.txt`):**

```
nano
openssh-server
qemu-guest-agent
```

Reported as:

```
nano : skip [WHITELIST]
```

---

### 3. Critical Packages (Categorized)

Packages that are not necessarily marked as `Essential`, but are **functionally critical**.

**Example (`critical.txt`):**

```
busybox:kernel
grub-pc:boot
ifupdown:network
```

Reported as:

```
busybox : skip [critical:KERNEL]
```

Categories are informational and help during review and auditing.

---

## Output

### Summary File

Generated at:

```
purge-sim/summary.txt
```

Example:

```
linux-image-amd64 : skip [critical:KERNEL]
nano : skip [WHITELIST]
libssl3t64 : 1 dependent packages
```

### Per-package Logs

Each simulated purge produces a log file:

```
purge-sim/<package>.log
```

Containing the raw output of:

```
apt-get -s purge <package>
```

---

## Typical Use Cases

* Debian system minimization
* VM and container footprint analysis
* Security hardening reviews
* Learning and teaching Debian dependency mechanics
* Pre-flight checks before aggressive cleanup

---

## References & Inspiration

* Debian Wiki – Reduce Debian:
  [https://wiki.debian.org/ReduceDebian](https://wiki.debian.org/ReduceDebian)

This project is inspired by the philosophy of **understanding the system before modifying it**.

---

## What's Next

The `summary.txt` file will vary depending on the system context, such as bare-metal, virtual machine (VMware, Hyper-V, Proxmox, QEMU), or container. Each environment results in a different set of installed packages.

What should be preserved and what can be purged depends entirely on the administrator’s criteria and requirements.

Based on `summary.txt`, the administrator can manually build a `safe-list.txt` file, explicitly listing the packages selected for removal.

Finally, a simple script can read `safe-list.txt` and execute `apt-get -y purge`, processing each package line by line.

> This approach prioritizes transparency, auditability, and context-aware decision making over automation.

---

## License

MIT License

---

## Disclaimer

This tool performs **analysis only**.

Any actual removal of packages is **entirely the user's responsibility**.

Always test on non-production systems first.
