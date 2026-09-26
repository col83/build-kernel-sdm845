https://raw.githubusercontent.com/backslashxx/KernelSU/refs/heads/master/website/docs/guide/how-to-build.md -

# How to build

::: warning
This document is for archival reference only and is no longer maintained.
Since KernelSU v3.0, we have dropped official support for GKI image mode for faster iteration and build speed. It is recommended to use `Ylarod/ddk` to build LKM.
:::

First, you should read the official Android documentation for building kernels:

1. [Build kernels](https://source.android.com/docs/setup/build/building-kernels)
2. [GKI release builds](https://source.android.com/docs/core/architecture/kernel/gki-release-builds)

::: warning
This page is for GKI devices; if you use an older kernel, please refer to [Integrate for non-GKI devices](how-to-integrate-for-non-gki).
:::

## Build kernel

### Sync the kernel source code

```sh
repo init -u https://android.googlesource.com/kernel/manifest
mv <kernel_manifest.xml> .repo/manifests
repo init -m manifest.xml
repo sync
```

The `<kernel_manifest.xml>` file is a manifest that uniquely identifies a build, allowing you to make it reproducible. To do this, you should download the manifest file from [GKI release builds](https://source.android.com/docs/core/architecture/kernel/gki-release-builds).

### Build

Please check the [Building kernels](https://source.android.com/docs/setup/build/building-kernels) first.

For example, to build an `aarch64` kernel image:

```sh
LTO=thin BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh
```

Don't forget to add the `LTO=thin` flag; otherwise, the build may fail if your computer has less than 24 GB of memory.

Starting from Android 13, the kernel is built by `bazel`:

```sh
tools/bazel build --config=fast //common:kernel_aarch64_dist
```

::: info
For some Android 14 kernels, to make Wi-Fi/Bluetooth work, it might be necessary to remove all GKI protected exports:

```sh
rm common/android/abi_gki_protected_exports_*
```
:::

## Build kernel with KernelSU

If you can successfully build the kernel, adding support for KernelSU will be relatively easy. In the root of kernel source directory, run any of the options listed below:

::: code-group

```sh[Latest tag (stable)]
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
```

```sh[main branch (dev)]
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s main
```

```sh[Select tag (such as v0.5.2)]
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s v0.5.2
```

:::

Then, rebuild the kernel and you will get a kernel image with KernelSU!


https://raw.githubusercontent.com/backslashxx/KernelSU/refs/heads/master/website/docs/guide/how-to-integrate-for-non-gki.md -

# Integrate for non-GKI devices

::: warning
This document is for archival reference only and is no longer maintained.
Since KernelSU v1.0, we have dropped official support for non-GKI devices.
:::

KernelSU can be integrated into non-GKI kernels and was backported to 4.14 and earlier versions.

Due to the fragmentation of non-GKI kernels, we don't have a universal way to build them; therefore, we cannot provide a non-GKI boot.img. However, you can build the kernel with KernelSU integrated on your own.

First, you should be able to build a bootable kernel from kernel source code. If the kernel isn't open source, then it is difficult to run KernelSU for your device.

If you're able to build a bootable kernel, there are two ways to integrate KernelSU into the kernel source code:

1. Automatically with `kprobe`
2. Manually

## Integrate with kprobe

KernelSU uses kprobe for its kernel hooks. If kprobe runs reliably on your kernel, we recommend integrating KernelSU this way.

First, add KernelSU to your kernel source tree:

```sh
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s v0.9.5
```

::: info
[KernelSU 1.0 and later versions no longer support non-GKI kernels](https://github.com/tiann/KernelSU/issues/1705). The last supported version is `v0.9.5`, so make sure to use the correct version.
:::

Then, you should check if kprobe is enabled in your kernel config. If it isn't, add these configs to it:

```txt
CONFIG_KPROBES=y
CONFIG_HAVE_KPROBES=y
CONFIG_KPROBE_EVENTS=y
```

Now, when you re-build your kernel, KernelSU should work correctly.

If you find that KPROBES is still not enabled, you can try enabling `CONFIG_MODULES`. If that doesn't solve the issue, use `make menuconfig` to search for other KPROBES dependencies.

However, if you encounter a bootloop after integrating KernelSU, this may indicate that the **kprobe is broken in your kernel**, which means that you should fix the kprobe bug or use another way.

::: tip HOW TO CHECK IF KPROBE IS BROKEN？
Comment out `ksu_sucompat_init()` and `ksu_ksud_init()` in `KernelSU/kernel/ksu.c`. If the device boots normally, kprobe may be broken.
:::

::: info HOW TO GET MODULE UMOUNT FEATURE WORKING ON PRE-GKI?
If your kernel is older than 5.9, you should backport `path_umount` to `fs/namespace.c`. This is required to get "Umount module" feature work correctly. If you don't backport `path_umount`, "Umount module" feature won't work. You can get more info on how to achieve this at the end of this page.
:::

## Manually modify the kernel source

If kprobe doesn't work on your kernel—either because of an upstream bug or because your kernel is older than 4.8—you can try the following approach:

First, add KernelSU to your kernel source tree:

```sh
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s v0.9.5
```

Keep in mind that, on some devices, your defconfig may be located at `arch/arm64/configs` or in other cases, it may be at `arch/arm64/configs/vendor/your_defconfig`. Regardless of the defconfig you're using, make sure to enable `CONFIG_KSU` with `y` to enable or `n` to disable it. For example, if you choose to enable it, your defconfig should contain the following string:

```txt
# KernelSU
CONFIG_KSU=y
```

Next, add KernelSU calls to the kernel source. Below are some patches for reference:

::: code-group

```diff[exec.c]
diff --git a/fs/exec.c b/fs/exec.c
index ac59664eaecf..bdd585e1d2cc 100644
--- a/fs/exec.c
+++ b/fs/exec.c
@@ -1890,11 +1890,14 @@ static int __do_execve_file(int fd, struct filename *filename,
 	return retval;
 }

+#ifdef CONFIG_KSU
+extern bool ksu_execveat_hook __read_mostly;
+extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,
+			void *envp, int *flags);
+extern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,
+				 void *argv, void *envp, int *flags);
+#endif
 static int do_execveat_common(int fd, struct filename *filename,
 			      struct user_arg_ptr argv,
 			      struct user_arg_ptr envp,
 			      int flags)
 {
+   #ifdef CONFIG_KSU
+	if (unlikely(ksu_execveat_hook))
+		ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);
+	else
+		ksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);
+   #endif
 	return __do_execve_file(fd, filename, argv, envp, flags, NULL);
 }
```
```diff[open.c]
diff --git a/fs/open.c b/fs/open.c
index 05036d819197..965b84d486b8 100644
--- a/fs/open.c
+++ b/fs/open.c
@@ -348,6 +348,8 @@ SYSCALL_DEFINE4(fallocate, int, fd, int, mode, loff_t, offset, loff_t, len)
 	return ksys_fallocate(fd, mode, offset, len);
 }

+#ifdef CONFIG_KSU
+extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,
+			 int *flags);
+#endif
 /*
  * access() needs to use the real uid/gid, not the effective uid/gid.
  * We do this by temporarily clearing all FS-related capabilities and
@@ -355,6 +357,7 @@ SYSCALL_DEFINE4(fallocate, int, fd, int, mode, loff_t, offset, loff_t, len)
  */
 long do_faccessat(int dfd, const char __user *filename, int mode)
 {
 	const struct cred *old_cred;
 	struct cred *override_cred;
 	struct path path;
 	struct inode *inode;
 	struct vfsmount *mnt;
 	int res;
 	unsigned int lookup_flags = LOOKUP_FOLLOW;
+   #ifdef CONFIG_KSU
+	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);
+   #endif
 
 	if (mode & ~S_IRWXO)	/* where's F_OK, X_OK, W_OK, R_OK? */
 		return -EINVAL;
```
```diff[read_write.c]
diff --git a/fs/read_write.c b/fs/read_write.c
index 650fc7e0f3a6..55be193913b6 100644
--- a/fs/read_write.c
+++ b/fs/read_write.c
@@ -434,10 +434,14 @@ ssize_t kernel_read(struct file *file, void *buf, size_t count, loff_t *pos)
 }
 EXPORT_SYMBOL(kernel_read);

+#ifdef CONFIG_KSU
+extern bool ksu_vfs_read_hook __read_mostly;
+extern int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,
+			size_t *count_ptr, loff_t **pos);
+#endif
 ssize_t vfs_read(struct file *file, char __user *buf, size_t count, loff_t *pos)
 {
 	ssize_t ret;
+   #ifdef CONFIG_KSU 
+	if (unlikely(ksu_vfs_read_hook))
+		ksu_handle_vfs_read(&file, &buf, &count, &pos);
+   #endif
+
 	if (!(file->f_mode & FMODE_READ))
 		return -EBADF;
 	if (!(file->f_mode & FMODE_CAN_READ))
```
```diff[stat.c]
diff --git a/fs/stat.c b/fs/stat.c
index 376543199b5a..82adcef03ecc 100644
--- a/fs/stat.c
+++ b/fs/stat.c
@@ -148,6 +148,8 @@ int vfs_statx_fd(unsigned int fd, struct kstat *stat,
 }
 EXPORT_SYMBOL(vfs_statx_fd);

+#ifdef CONFIG_KSU
+extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);
+#endif
+
 /**
  * vfs_statx - Get basic and extra attributes by filename
  * @dfd: A file descriptor representing the base dir for a relative filename
@@ -170,6 +172,7 @@ int vfs_statx(int dfd, const char __user *filename, int flags,
 	int error = -EINVAL;
 	unsigned int lookup_flags = LOOKUP_FOLLOW | LOOKUP_AUTOMOUNT;

+   #ifdef CONFIG_KSU
+	ksu_handle_stat(&dfd, &filename, &flags);
+   #endif
 	if ((flags & ~(AT_SYMLINK_NOFOLLOW | AT_NO_AUTOMOUNT |
 		       AT_EMPTY_PATH | KSTAT_QUERY_FLAGS)) != 0)
 		return -EINVAL;
```

:::

You should find the four functions in kernel source:

1. `do_faccessat`, usually in `fs/open.c`
2. `do_execveat_common`, usually in `fs/exec.c`
3. `vfs_read`, usually in `fs/read_write.c`
4. `vfs_statx`, usually in `fs/stat.c`

If your kernel doesn't have the `vfs_statx` function, use `vfs_fstatat` instead:

```diff
diff --git a/fs/stat.c b/fs/stat.c
index 068fdbcc9e26..5348b7bb9db2 100644
--- a/fs/stat.c
+++ b/fs/stat.c
@@ -87,6 +87,8 @@ int vfs_fstat(unsigned int fd, struct kstat *stat)
 }
 EXPORT_SYMBOL(vfs_fstat);

+#ifdef CONFIG_KSU
+extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);
+#endif
 int vfs_fstatat(int dfd, const char __user *filename, struct kstat *stat,
 		int flag)
 {
@@ -94,6 +96,8 @@ int vfs_fstatat(int dfd, const char __user *filename, struct kstat *stat,
 	int error = -EINVAL;
 	unsigned int lookup_flags = 0;
+   #ifdef CONFIG_KSU 
+	ksu_handle_stat(&dfd, &filename, &flag);
+   #endif
+
 	if ((flag & ~(AT_SYMLINK_NOFOLLOW | AT_NO_AUTOMOUNT |
 		      AT_EMPTY_PATH)) != 0)
 		goto out;
```

For kernels eariler than 4.17, if you cannot find `do_faccessat`, just go to the definition of the `faccessat` syscall and place the call there:

```diff
diff --git a/fs/open.c b/fs/open.c
index 2ff887661237..e758d7db7663 100644
--- a/fs/open.c
+++ b/fs/open.c
@@ -355,6 +355,9 @@ SYSCALL_DEFINE4(fallocate, int, fd, int, mode, loff_t, offset, loff_t, len)
 	return error;
 }

+#ifdef CONFIG_KSU
+extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,
+			        int *flags);
+#endif
+
 /*
  * access() needs to use the real uid/gid, not the effective uid/gid.
  * We do this by temporarily clearing all FS-related capabilities and
@@ -370,6 +373,8 @@ SYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)
 	int res;
 	unsigned int lookup_flags = LOOKUP_FOLLOW;
+   #ifdef CONFIG_KSU
+	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);
+   #endif
+
 	if (mode & ~S_IRWXO)	/* where's F_OK, X_OK, W_OK, R_OK? */
 		return -EINVAL;
```

### Safe Mode

To enable KernelSU's built-in Safe Mode, you should modify the `input_handle_event` function in `drivers/input/input.c`:

::: tip
It's strongly recommended to enable this feature, it's very useful for preventing bootloops!
:::

```diff
diff --git a/drivers/input/input.c b/drivers/input/input.c
index 45306f9ef247..815091ebfca4 100755
--- a/drivers/input/input.c
+++ b/drivers/input/input.c
@@ -367,10 +367,13 @@ static int input_get_disposition(struct input_dev *dev,
 	return disposition;
 }

+#ifdef CONFIG_KSU
+extern bool ksu_input_hook __read_mostly;
+extern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);
+#endif
+
 static void input_handle_event(struct input_dev *dev,
 			       unsigned int type, unsigned int code, int value)
 {
	int disposition = input_get_disposition(dev, type, code, &value);
+   #ifdef CONFIG_KSU
+	if (unlikely(ksu_input_hook))
+		ksu_handle_input_handle_event(&type, &code, &value);
+   #endif
 
 	if (disposition != INPUT_IGNORE_EVENT && type != EV_SYN)
 		add_input_randomness(type, code, value);
```

::: info ENTERING SAFE MODE ACCIDENTALLY?
If you're using manual integration and don't disable `CONFIG_KPROBES`, the user will be able to trigger Safe Mode by pressing the volume down button after booting! Therefore, if you're using manual integration, it's necessary to disable `CONFIG_KPROBES`!
:::

### Failed to execute `pm` in terminal?

You should modify `fs/devpts/inode.c`. Reference:

```diff
diff --git a/fs/devpts/inode.c b/fs/devpts/inode.c
index 32f6f1c68..d69d8eca2 100644
--- a/fs/devpts/inode.c
+++ b/fs/devpts/inode.c
@@ -602,6 +602,8 @@ struct dentry *devpts_pty_new(struct pts_fs_info *fsi, int index, void *priv)
        return dentry;
 }

+#ifdef CONFIG_KSU
+extern int ksu_handle_devpts(struct inode*);
+#endif
+
 /**
  * devpts_get_priv -- get private data for a slave
  * @pts_inode: inode of the slave
@@ -610,6 +612,7 @@ struct dentry *devpts_pty_new(struct pts_fs_info *fsi, int index, void *priv)
  */
 void *devpts_get_priv(struct dentry *dentry)
 {
+       #ifdef CONFIG_KSU
+       ksu_handle_devpts(dentry->d_inode);
+       #endif
        if (dentry->d_sb->s_magic != DEVPTS_SUPER_MAGIC)
                return NULL;
        return dentry->d_fsdata;
```

### How to backport path_umount

You can make the "Umount modules" feature work on pre-GKI kernels by manually backporting `path_umount` from 5.9. You can use this patch as reference:

```diff
--- a/fs/namespace.c
+++ b/fs/namespace.c
@@ -1739,6 +1739,39 @@ static inline bool may_mandlock(void)
 }
 #endif

+static int can_umount(const struct path *path, int flags)
+{
+	struct mount *mnt = real_mount(path->mnt);
+
+	if (flags & ~(MNT_FORCE | MNT_DETACH | MNT_EXPIRE | UMOUNT_NOFOLLOW))
+		return -EINVAL;
+	if (!may_mount())
+		return -EPERM;
+	if (path->dentry != path->mnt->mnt_root)
+		return -EINVAL;
+	if (!check_mnt(mnt))
+		return -EINVAL;
+	if (mnt->mnt.mnt_flags & MNT_LOCKED) /* Check optimistically */
+		return -EINVAL;
+	if (flags & MNT_FORCE && !capable(CAP_SYS_ADMIN))
+		return -EPERM;
+	return 0;
+}
+
+int path_umount(struct path *path, int flags)
+{
+	struct mount *mnt = real_mount(path->mnt);
+	int ret;
+
+	ret = can_umount(path, flags);
+	if (!ret)
+		ret = do_umount(mnt, flags);
+
+	/* we mustn't call path_put() as that would clear mnt_expiry_mark */
+	dput(path->dentry);
+	mntput_no_expire(mnt);
+	return ret;
+}
 /*
  * Now umount can handle mount points as well as block devices.
  * This is important for filesystems which use unnamed block devices.
```

Finally, build your kernel again, and KernelSU should work correctly.


https://raw.githubusercontent.com/backslashxx/KernelSU/refs/heads/master/kernel/setup.sh -

#!/bin/sh
set -eu

GKI_ROOT=$(pwd)

display_usage() {
    echo "Usage: $0 [--cleanup | <commit-or-tag>]"
    echo "  --cleanup:              Cleans up previous modifications made by the script."
    echo "  <commit-or-tag>:        Sets up or updates the KernelSU to specified tag or commit."
    echo "  -h, --help:             Displays this usage information."
    echo "  (no args):              Sets up or updates the KernelSU environment to the latest tagged version."
}

initialize_variables() {
    if test -d "$GKI_ROOT/common/drivers"; then
         DRIVER_DIR="$GKI_ROOT/common/drivers"
    elif test -d "$GKI_ROOT/drivers"; then
         DRIVER_DIR="$GKI_ROOT/drivers"
    else
         echo '[ERROR] "drivers/" directory not found.'
         exit 127
    fi

    DRIVER_MAKEFILE=$DRIVER_DIR/Makefile
    DRIVER_KCONFIG=$DRIVER_DIR/Kconfig
}

# Reverts modifications made by this script
perform_cleanup() {
    echo "[+] Cleaning up..."
    [ -L "$DRIVER_DIR/kernelsu" ] && rm "$DRIVER_DIR/kernelsu" && echo "[-] Symlink removed."
    grep -q "kernelsu" "$DRIVER_MAKEFILE" && sed -i '/kernelsu/d' "$DRIVER_MAKEFILE" && echo "[-] Makefile reverted."
    grep -q "drivers/kernelsu/Kconfig" "$DRIVER_KCONFIG" && sed -i '/drivers\/kernelsu\/Kconfig/d' "$DRIVER_KCONFIG" && echo "[-] Kconfig reverted."
    if [ -d "$GKI_ROOT/KernelSU" ]; then
        rm -rf "$GKI_ROOT/KernelSU" && echo "[-] KernelSU directory deleted."
    fi
}

# Sets up or update KernelSU environment
setup_kernelsu() {
    echo "[+] Setting up KernelSU..."
    test -d "$GKI_ROOT/KernelSU" || git clone https://github.com/backslashxx/KernelSU && echo "[+] Repository cloned."
    cd "$GKI_ROOT/KernelSU"
    git stash && echo "[-] Stashed current changes."
    if [ "$(git status | grep -Po 'v\d+(\.\d+)*' | head -n1)" ]; then
        git checkout main && echo "[-] Switched to main branch."
    fi
    git pull && echo "[+] Repository updated."
    if [ -z "${1-}" ]; then
        git checkout "$(git describe --abbrev=0 --tags)" && echo "[-] Checked out latest tag."
    else
        git checkout "$1" && echo "[-] Checked out $1." || echo "[-] Checkout default branch"
    fi
    cd "$DRIVER_DIR"
    ln -sf "$(realpath --relative-to="$DRIVER_DIR" "$GKI_ROOT/KernelSU/kernel")" "kernelsu" && echo "[+] Symlink created."

    # Add entries in Makefile and Kconfig if not already existing
    grep -q "kernelsu" "$DRIVER_MAKEFILE" || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> "$DRIVER_MAKEFILE" && echo "[+] Modified Makefile."
    grep -q "source \"drivers/kernelsu/Kconfig\"" "$DRIVER_KCONFIG" || sed -i "/endmenu/i\source \"drivers/kernelsu/Kconfig\"" "$DRIVER_KCONFIG" && echo "[+] Modified Kconfig."
    echo '[+] Done.'
}

# Process command-line arguments
if [ "$#" -eq 0 ]; then
    initialize_variables
    setup_kernelsu
elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    display_usage
elif [ "$1" = "--cleanup" ]; then
    initialize_variables
    perform_cleanup
else
    initialize_variables
    setup_kernelsu "$@"
fi


https://raw.githubusercontent.com/backslashxx/KernelSU/refs/heads/master/kernel/Makefile -

# NOTE: unity build. single unit.

obj-$(CONFIG_KSU) := ksu.o

CFLAGS_ksu.o += -I$(srctree)/security/selinux -I$(srctree)/security/selinux/include
CFLAGS_ksu.o += -I$(objtree)/security/selinux

KDIR := $(KDIR)
MDIR := $(realpath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

$(info -- KDIR: $(KDIR))
$(info -- MDIR: $(MDIR))

# compliant to last upstream kernel change as of aa08b39
CFLAGS_ksu.o += -DKSU_VERSION=32628

ifndef KSU_EXPECTED_SIZE
KSU_EXPECTED_SIZE := 0x033b
endif

ifndef KSU_EXPECTED_HASH
KSU_EXPECTED_HASH := c371061b19d8c7d7d6133c6a9bafe198fa944e50c1b31c9d8daa8d7f1fc2d2d6
endif

ifdef KSU_MANAGER_PACKAGE
CFLAGS_ksu.o += -DKSU_MANAGER_PACKAGE=\"$(KSU_MANAGER_PACKAGE)\"
$(info -- KernelSU Manager package name: $(KSU_MANAGER_PACKAGE))
endif

$(info -- KernelSU Manager signature size: $(KSU_EXPECTED_SIZE))
$(info -- KernelSU Manager signature hash: $(KSU_EXPECTED_HASH))

CFLAGS_ksu.o += -DEXPECTED_SIZE=$(KSU_EXPECTED_SIZE)
CFLAGS_ksu.o += -DEXPECTED_HASH=\"$(KSU_EXPECTED_HASH)\"

# uncommon, but wont hurt, check for 3-arg security_add_hooks
ifeq ($(shell grep -A1 "void security_add_hooks" $(srctree)/include/linux/lsm_hooks.h 2>/dev/null | grep -q lsm 2>/dev/null; echo $$?),0)
$(info -- KernelSU/compat: security_add_hooks v2 found!)
CFLAGS_ksu.o += -DKSU_COMPAT_SECURITY_ADD_HOOKS_V2
endif

# see security_delete_hooks
ifeq ($(shell grep -A5 "^struct security_hook_list" $(srctree)/include/linux/lsm_hooks.h 2>/dev/null | grep -q "struct hlist_node" 2>/dev/null; echo $$?),0)
$(info -- KernelSU/compat: security_hook_list - hlist_node found!)
CFLAGS_ksu.o += -DKSU_COMPAT_SECURITY_DELETE_HOOKS_HLIST
endif

ifeq ($(shell grep -q "^struct security_operations selinux_ops" $(srctree)/security/selinux/hooks.c; echo $$?),0)
$(info -- KernelSU/compat: exported selinux_ops found!)
CFLAGS_ksu.o += -DKSU_HAS_EXPORTED_SELINUX_OPS
endif

ifeq ($(shell grep -q " current_sid(void)" $(srctree)/security/selinux/include/objsec.h; echo $$?),0)
CFLAGS_ksu.o += -DKSU_COMPAT_HAS_CURRENT_SID
endif

ifeq ($(shell grep -q "struct selinux_state " $(srctree)/security/selinux/include/security.h; echo $$?),0)
CFLAGS_ksu.o += -DKSU_COMPAT_HAS_SELINUX_STATE
endif

ifeq ($(shell grep -q "struct type_datum \*\*type_val_to_struct;" $(srctree)/security/selinux/ss/policydb.h; echo $$?),0)
CFLAGS_ksu.o += -DKSU_TYPE_VAL_TO_STRUCT
endif

# half-assed-backport from 5.1
ifeq ($(shell grep -q "struct type_datum \*\*type_val_to_struct_array;" $(srctree)/security/selinux/ss/policydb.h; echo $$?),0)
CFLAGS_ksu.o += -DKSU_TYPE_VAL_TO_STRUCT_ARRAY
endif

ifeq ($(shell grep -q "^DEFINE_RWLOCK(policy_rwlock);" $(srctree)/security/selinux/ss/services.c; echo $$?),0)
$(info -- KernelSU/compat: exported policy_rwlock found!)
CFLAGS_ksu.o += -DKSU_COMPAT_HAS_EXPORTED_POLICY_RWLOCK
endif

ifeq ($(shell grep -q "cpus_ptr;" $(srctree)/include/linux/sched.h; echo $$?),0)
$(info -- KernelSU/compat: backported cpus_ptr found!)
CFLAGS_ksu.o += -DKSU_COMPAT_HAS_BACKPORTED_CPUS_PTR
endif

# branch link hook, do_faccessat
ifeq ($(shell grep "long do_faccessat" $(srctree)/fs/open.c 2>/dev/null | grep -q "flags" 2>/dev/null; echo $$?),0)
CFLAGS_ksu.o += -DKSU_HAS_FACCESSAT2
endif

# UL, look for read_iter on f_op struct
ifeq ($(shell grep -q "read_iter" $(srctree)/include/linux/fs.h 2>/dev/null; echo $$?),0)
$(info -- KernelSU/compat: f_op->read_iter found!)
CFLAGS_ksu.o += -DKSU_HAS_FOP_READ_ITER
endif

# UL, look for iterate_dir on ‎fs/readdir.c
ifeq ($(shell grep -q "^int iterate_dir" $(srctree)/fs/readdir.c 2>/dev/null; echo $$?),0)
$(info -- KernelSU/compat: iterate_dir found!)
CFLAGS_ksu.o += -DKSU_HAS_ITERATE_DIR
endif

CFLAGS_ksu.o += $(call cc-option, -Wno-declaration-after-statement)
CFLAGS_ksu.o += $(call cc-option, -Wno-implicit-function-declaration)
CFLAGS_ksu.o += $(call cc-option, -Wno-missing-prototypes)
CFLAGS_ksu.o += $(call cc-option, -Wno-strict-prototypes)
CFLAGS_ksu.o += $(call cc-option, -Wno-int-conversion)
CFLAGS_ksu.o += $(call cc-option, -Wno-int-to-pointer-cast)
CFLAGS_ksu.o += $(call cc-option, -Wno-pointer-to-int-cast)
CFLAGS_ksu.o += $(call cc-option, -Wno-unused-variable)
CFLAGS_ksu.o += $(call cc-option, -Wno-unused-function)
CFLAGS_ksu.o += $(call cc-option, -Wno-unused-label)
CFLAGS_ksu.o += $(call cc-option, -Wno-format)
CFLAGS_ksu.o += $(call cc-option, -Wno-macro-redefined)
CFLAGS_ksu.o += $(call cc-option, -Wno-incompatible-pointer-types-discards-qualifiers)
CFLAGS_ksu.o += $(call cc-option, -Wno-discarded-qualifiers)
CFLAGS_ksu.o += $(call cc-option, -Wno-deprecated-octal-literals)

# dont be too strict
CFLAGS_REMOVE_ksu.o += -Werror

# so we can see stack use atleast, as we disable all stack safety here
CFLAGS_ksu.o += $(call cc-option, -Wframe-larger-than=1024)

# to make sure we can use builtins
CFLAGS_REMOVE_ksu.o += -fno-builtin

# Os to O2, we dont care for anything else. O3 vs O2 codegen on hotpath is same.
ifeq ($(CONFIG_CC_OPTIMIZE_FOR_SIZE),y)
CFLAGS_REMOVE_ksu.o += -Oz
CFLAGS_REMOVE_ksu.o += -Os
CFLAGS_ksu.o += -O2
endif

# attempt to enable gnu17 up to gnu2y
# we skip setting gnu11 and such due to "error: initializer element is not constant" on gcc 4.9
# we skip gnu2x here due to its inconsistency
CFLAGS_ksu.o += $(call cc-option, -std=gnu17)
CFLAGS_ksu.o += $(call cc-option, -std=gnu23)
CFLAGS_ksu.o += $(call cc-option, -std=gnu2y)

#ifeq ($(shell $(CC) -v 2>&1 | grep -q 'clang'; echo $$?),0)
# $(info -- KernelSU/CC: clang!)
#endif

# always inline atomics
# clang and gcc CAN try to drop a runtime C11 atomics detector
# https://github.com/llvm/llvm-project/blob/main/llvm/test/CodeGen/AArch64/atomic-ops.ll
# however this is problematic to us as those cannot be linked to the kernel (e.g. __aarch64_cas4_acq, __aarch64_cas4_rel)
# so for LKM they just get plain ARMv8.0 atomics, not LSE / LSE2, even when the device is capable of LSE.
ifeq ($(CONFIG_ARM64),y)
CFLAGS_ksu.o += $(call cc-option, -mno-outline-atomics)
endif

# Optional: for LKM users, I recommend users to build it themselves with optimizations.
# you can get optimized codegen especially around atomics.
# hint: decode your own /proc/cpuinfo and check it here https://github.com/llvm/llvm-project/blob/main/llvm/lib/TargetParser/Host.cpp
# comment it out and put your cpu / arch here
# CFLAGS_ksu.o += -mcpu=cortex-a76 -mtune=cortex-a76

ifneq ($(CONFIG_KSU_DEBUG),y)
# strip, remove tracing / profiling
# comment out if proper backtrace is needed
CFLAGS_ksu.o += -g0 -fno-unwind-tables -fno-asynchronous-unwind-tables -fomit-frame-pointer
CFLAGS_ksu.o += $(call cc-option, -momit-leaf-frame-pointer)

# no profiling
CFLAGS_REMOVE_ksu.o += $(CC_FLAGS_FTRACE)
CFLAGS_REMOVE_ksu.o += -pg

# no need for stack init
CFLAGS_REMOVE_ksu.o += -ftrivial-auto-var-init=pattern
CFLAGS_REMOVE_ksu.o += -ftrivial-auto-var-init=zero
CFLAGS_REMOVE_ksu.o += -enable-trivial-auto-var-init-zero-knowing-it-will-be-removed-from-clang

# if cflags can be macro'd, this will be called 'TRUST_ME'
CFLAGS_ksu.o += -fno-stack-protector -fno-stack-check
CFLAGS_REMOVE_ksu.o += -fsanitize=shadow-call-stack
endif # CONFIG_KSU_DEBUG

# Native fallback targets matching the traditional out-of-tree build method
all:
	$(MAKE) -C $(KDIR) M=$(MDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(MDIR) clean

# Keep a new line here!! Because someone may append config




author's fork additional docs:

https://github.com/backslashxx/KernelSU/issues/5 -

This refactors original KSU hooks to replace deep kernel function hooks with targeted hooks.
This backports KernelSU [pr#1657](https://github.com/tiann/KernelSU/pull/1657) and having [pr#2084](https://github.com/tiann/KernelSU/pull/2084) elements (32-bit sucompat).
It reduces the scope of kernel function interception and still maintains full fucntionality.

### READ THIS FIRST:
- If you're somehow building for 6.8+ **NON-ARM64** make sure to also apply: https://github.com/backslashxx/KernelSU/issues/7
- if you're on a custom rom and wants to hide adb root on selinuxfs, install [this ksu module](https://github.com/backslashxx/small_module)
- on **ARM / ARM64**, enabling **CONFIG_KSU_TAMPER_SYSCALL_TABLE=y** allows you to skip the following hooks:
  - execve
  - sys_faccessat
  - sys_newfstatat
  - sys_newfstat ret_hook
  - sys_reboot
  - slow_avc_audit

- make sure to remove listed hooks when doing this!

- on 4.19 and newer ARM64 you can try **CONFIG_KSU_HACK_ARM64_BRANCH_LINK=y** instead and **SKIP ALL** these manual hooks below.

## 🟢 execve hook 
- for sucompat
- **choose one** which suits your kernel version
- if you have shit backported, use the hook similar to what's in your kernel.

<details>
  <summary>show patch/diff (3.19+ via do_execveat_common)</summary>
  
```patch
--- a/fs/exec.c
+++ b/fs/exec.c
@@ -1728,6 +1728,11 @@	 
/*
 * sys_execve() executes a new program.
 */
static int do_execveat_common(int fd, struct filename *filename,
			      struct user_arg_ptr argv,
			      struct user_arg_ptr envp,
			      int flags)
{
	char *pathbuf = NULL;
	struct linux_binprm *bprm;
	struct file *file;
	struct files_struct *displaced;
	int retval;

+#ifdef CONFIG_KSU
+	extern int ksu_handle_execveat(int *, struct filename **, void *, void *, int *);
+	ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);
+#endif

	if (IS_ERR(filename))
		return PTR_ERR(filename);

	/*
	 * We move the actual failure in case of RLIMIT_NPROC excess from
```

</details>

<details>
  <summary>show patch/diff (3.19+ via __do_execve_file)</summary>
  
```patch
--- fs/exec.c
+++ fs/exec.c
@@ -1921,11 +1921,20 @@
 
/*
 * sys_execve() executes a new program.
 */
static int __do_execve_file(int fd, struct filename *filename,
			    struct user_arg_ptr argv,
			    struct user_arg_ptr envp,
			    int flags, struct file *file)
{
	char *pathbuf = NULL;
	struct linux_binprm *bprm;
	struct files_struct *displaced;
	int retval;

+#ifdef CONFIG_KSU
+	extern int ksu_handle_execveat(int *, struct filename **, void *, void *, int *);
+	ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);
+#endif
+
	if (IS_ERR(filename))
		return PTR_ERR(filename);

	/*
```

</details>

<details>
  <summary>show patch/diff (3.18, via do_execve_common)</summary>

- for 3.18, we can repurpose upstream's do_execveat_common hook for do_execve_common
- no sys_execveat on <= 3.18, so this makes sense instead of hooking sys_execve + compat_sys_execve
- take note: **struct filename \*filename**
```patch
--- a/fs/exec.c
+++ b/fs/exec.c
/*
 * sys_execve() executes a new program.
 */
static int do_execve_common(struct filename *filename,
				struct user_arg_ptr argv,
				struct user_arg_ptr envp)
{
	struct linux_binprm *bprm;
	struct file *file;
	struct files_struct *displaced;
	int retval;

+#ifdef CONFIG_KSU
+	extern int ksu_handle_execveat(int *, struct filename **, void *, void *, int *);
+	ksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);
+#endif
+
	if (IS_ERR(filename))
		return PTR_ERR(filename);

	/*
	 * We move the actual failure in case of RLIMIT_NPROC excess from
	 * set*uid() to execve() because too many poorly written programs
 ```
</details>

<details>
  <summary>show patch/diff (3.0 - 3.10, via do_execve_common)</summary>

- for <= 3.10, this repo provides a handler for do_execve_common
- no sys_execveat on <= 3.18, so this makes sense instead of hooking sys_execve + compat_sys_execve
- take note: **const char \*filename**
```patch
--- a/fs/exec.c
+++ b/fs/exec.c
@@ -1615,6 +1615,12 @@ 
/*
 * sys_execve() executes a new program.
 */
static int do_execve_common(const char *filename,
				struct user_arg_ptr argv,
				struct user_arg_ptr envp)
{
	struct linux_binprm *bprm;
	struct file *file;
	struct files_struct *displaced;
	bool clear_in_exec;
	int retval;
	const struct cred *cred = current_cred();
+
+#ifdef CONFIG_KSU
+	extern int ksu_legacy_execve_sucompat(const char **, void *, void *);
+	ksu_legacy_execve_sucompat(&filename, (void *)&argv, (void *)&envp);
+#endif
+
	/*
	 * We move the actual failure in case of RLIMIT_NPROC excess from
	 * set*uid() to execve() because too many poorly written programs
 ```
</details>

## 🟢 sys_faccessat hook
- for sucompat
- from original guide
- hook **sys_faccessat** even if you have do_faccessat, this is for scope minimization.
- if you have shit backported, use the hook similar to what's in your kernel.

<details>
  <summary>show patch/diff (5.10+)</summary>
  
```patch
--- a/fs/open.c
+++ b/fs/open.c
@@ -483,6 +483,10 @@
 
 SYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)
 {
+#ifdef CONFIG_KSU
+	extern int ksu_handle_faccessat(int *, const char __user **, int *, int *);
+	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);
+#endif
 	return do_faccessat(dfd, filename, mode, 0);
 }
```
</details>
<details>
  <summary>show patch/diff (4.19+)</summary>
  
```patch
--- a/fs/open.c
+++ b/fs/open.c
@@ -483,6 +483,10 @@
 
 SYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)
 {
+#ifdef CONFIG_KSU
+	extern int ksu_handle_faccessat(int *, const char __user **, int *, int *);
+	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);
+#endif
 	return do_faccessat(dfd, filename, mode);
 }
```
</details>
<details>
  <summary>show patch/diff (4.14 and older)</summary>
  
```patch
--- a/fs/open.c
+++ b/fs/open.c
/*
 * access() needs to use the real uid/gid, not the effective uid/gid.
 * We do this by temporarily clearing all FS-related capabilities and
 * switching the fsuid/fsgid around to the real ones.
 */
SYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)
{
	const struct cred *old_cred;
	struct cred *override_cred;
	struct path path;
	struct inode *inode;
	int res;
	unsigned int lookup_flags = LOOKUP_FOLLOW;
 
+#ifdef CONFIG_KSU
+	extern int ksu_handle_faccessat(int *, const char __user **, int *, int *);
+	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);
+#endif
+
 	if (mode & ~S_IRWXO)	/* where's F_OK, X_OK, W_OK, R_OK? */
 		return -EINVAL;
 
```
</details>

## 🟢 sys_newfstatat hook
- for sucompat
- scope minimized
- you now have to hook **sys_newfstatat**, instead of vfs_statx()
- optionally hook **sys_fstatat64** if 32-bit su is needed.


<details>
  <summary>show patch/diff</summary>
  
```patch
--- a/fs/stat.c
+++ b/fs/stat.c
@@ -371,6 +371,11 @@ 
#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)
SYSCALL_DEFINE4(newfstatat, int, dfd, const char __user *, filename,
		struct stat __user *, statbuf, int, flag)
{
	struct kstat stat;
	int error;

+#ifdef CONFIG_KSU
+	extern int ksu_handle_stat(int *, const char __user **, int *);
+	ksu_handle_stat(&dfd, &filename, &flag);
+#endif

	error = vfs_fstatat(dfd, filename, &stat, flag);
	if (error)
		return error;
	return cp_new_stat(&stat, statbuf);
}
#endif

@@ -515,6 +520,11 @@
SYSCALL_DEFINE4(fstatat64, int, dfd, const char __user *, filename,
		struct stat64 __user *, statbuf, int, flag)
{
	struct kstat stat;
	int error;

+#ifdef CONFIG_KSU // for 32-bit
+	extern int ksu_handle_stat(int *, const char __user **, int *);
+	ksu_handle_stat(&dfd, &filename, &flag);
+#endif

	error = vfs_fstatat(dfd, filename, &stat, flag);
	if (error)
		return error;
	return cp_new_stat64(&stat, statbuf);
}
```

</details>

## 🟢 sys_newfstat ret_hook 
- needed for Android 16 and newer
- introduced upstream by [kernel: ksud: Refine rc injection, fix issue of Android Canary 2601](https://github.com/tiann/KernelSU/commit/df640917d11dd0eff1b34ea53ec3c0dc49667002)- 
- go to fs/stat.c and hook newfstat before it returns
- optionally hook **sys_fstat64** for 32-bit, 32-on-64. (likely not needed though)
- **DO NOT** WORRY about **#pragma GCC**, this also works on Clang.

<details>
  <summary>show patch/diff</summary>
  
```patch
diff --git a/fs/stat.c b/fs/stat.c
--- a/fs/stat.c
+++ b/fs/stat.c
@@ -386,6 +392,14 @@ 
SYSCALL_DEFINE2(newfstat, unsigned int, fd, struct stat __user *, statbuf)
{
	struct kstat stat;
	int error = vfs_fstat(fd, &stat);

	if (!error)
		error = cp_new_stat(&stat, statbuf);

+#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_KPROBES_KSUD)
+#pragma GCC diagnostic push
+#pragma GCC diagnostic ignored "-Wdeclaration-after-statement"
+	extern void ksu_handle_newfstat_ret(unsigned int *, struct stat __user **);
+	ksu_handle_newfstat_ret(&fd, &statbuf);
+#pragma GCC diagnostic pop
+#endif
+
	return error;
}
 
@@ -506,6 +520,14 @@
SYSCALL_DEFINE2(fstat64, unsigned long, fd, struct stat64 __user *, statbuf)
{
	struct kstat stat;
	int error = vfs_fstat(fd, &stat);

	if (!error)
		error = cp_new_stat64(&stat, statbuf);

+#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_KPROBES_KSUD) // for 32-bit
+#pragma GCC diagnostic push
+#pragma GCC diagnostic ignored "-Wdeclaration-after-statement"
+	extern void ksu_handle_fstat64_ret(unsigned long *, struct stat64 __user **);
+	ksu_handle_fstat64_ret(&fd, &statbuf);
+#pragma GCC diagnostic pop
+#endif
+
	return error;
}
```
</details>

## 🟢 sys_reboot hook 
- this is needed by new KernelSU supercall introduced at 12143
- just go to where sys_reboot is and hook right on its entry.

<details>
  <summary>show patch/diff (3.18+)</summary>
  
```patch
--- a/kernel/reboot.c
+++ b/kernel/reboot.c
@@ -284,6 +284,11 @@ 
SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,
		void __user *, arg)
{
	struct pid_namespace *pid_ns = task_active_pid_ns(current);
	char buffer[256];
	int ret = 0;

+#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_KPROBES_KSUD)
+	extern int ksu_handle_sys_reboot(int, int, unsigned int, void __user **);
+	ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);
+#endif

	/* We only trust the superuser with rebooting the system. */
	if (!ns_capable(pid_ns->user_ns, CAP_SYS_BOOT))
		return -EPERM;
```

</details>

<details>
  <summary>show patch/diff (3.0~3.10)</summary>
  
```patch
--- a/kernel/sys.c
+++ b/kernel/sys.c
@@ -463,6 +463,11 @@ 
  *
  * reboot doesn't sync: do that yourself before calling this.
  */
SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,
		void __user *, arg)
{
	struct pid_namespace *pid_ns = task_active_pid_ns(current);
	char buffer[256];
	int ret = 0;
 
+#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_KPROBES_KSUD)
+	extern int ksu_handle_sys_reboot(int, int, unsigned int, void __user **);
+	ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);
+#endif
+
 	/* We only trust the superuser with rebooting the system. */
 	if (!ns_capable(pid_ns->user_ns, CAP_SYS_BOOT))
 		return -EPERM;
```
</details>

## 🟡 policy_rwlock 
- this is **OPTIONAL**, nice to have but **NOT** required.
- ‼️ mostly only for 3.0 ~ 4.9, maybe 4.14
- most 4.14 kernels does **NOT** need this though (due to selinux_state backported by ACK)
- if you can't find it or too lazy don't bother with it
- basically you just remove "static" on policy_rwlock's definition

<details>
  <summary>show patch/diff</summary>
  
```patch
--- a/security/selinux/ss/services.c
+++ b/security/selinux/ss/services.c
@@ -74,7 +74,7 @@
 int selinux_android_netlink_route;
 int selinux_policycap_netpeer;
 int selinux_policycap_openperm;
 
-static DEFINE_RWLOCK(policy_rwlock);
+DEFINE_RWLOCK(policy_rwlock);
 
 static struct sidtab sidtab;
 struct policydb policydb;
```

</details>


https://github.com/backslashxx/KernelSU/issues/7 -

## NOTE: if you're on an ARM64 kernel you can try CONFIG_KSU_LSM_SECURITY_HOOKS=y, there is experimental support.

This requires building this tree's KernelSU kernel driver with **[CONFIG_KSU_LSM_SECURITY_HOOKS=n](https://github.com/tiann/KernelSU/commit/eae4393)**
This is so that we can replace those automated lsm hooks with manually hooked ones.

```patch
--- a/security/security.c
+++ b/security/security.c
@@ -1327,6 +1327,10 @@
  */
 int security_bprm_check(struct linux_binprm *bprm)
 {
+#ifdef CONFIG_KSU
+       extern int ksu_bprm_check(struct linux_binprm *bprm);
+       ksu_bprm_check(bprm);
+#endif
        return call_int_hook(bprm_check_security, bprm);
 }
 
@@ -2282,6 +2286,10 @@
int security_inode_rename(struct inode *old_dir, struct dentry *old_dentry,
                          struct inode *new_dir, struct dentry *new_dentry,
                          unsigned int flags)
{
+#ifdef CONFIG_KSU
+       extern int ksu_inode_rename(struct inode *, struct dentry *, struct inode *, struct dentry *);
+       ksu_inode_rename(old_dir, old_dentry, new_dir, new_dentry);
+#endif
	if (unlikely(IS_PRIVATE(d_backing_inode(old_dentry)) ||
		     (d_is_positive(new_dentry) &&
		      IS_PRIVATE(d_backing_inode(new_dentry)))))
		return 0;

	return call_int_hook(path_rename, old_dir, old_dentry, new_dir,
			     new_dentry, flags);
}
@@ -2871,6 +2879,10 @@
  */
 int security_file_permission(struct file *file, int mask)
{
+#ifdef CONFIG_KSU
+       extern int ksu_file_permission(struct file *, int);
+       ksu_file_permission(file, mask);
+#endif
        return call_int_hook(file_permission, file, mask);
}
 
@@ -3521,6 +3533,10 @@ 
 int security_task_fix_setuid(struct cred *new, const struct cred *old,
                             int flags)
{
+#ifdef CONFIG_KSU
+       extern int ksu_task_fix_setuid(struct cred *, const struct cred *, int);
+       ksu_task_fix_setuid(new, old, flags);
+#endif
        return call_int_hook(task_fix_setuid, new, old, flags);
 }
 
@@ -4364,6 +4380,11 @@
int security_setprocattr(int lsmid, const char *name, void *value, size_t size)
{
        struct lsm_static_call *scall;
 
+#ifdef CONFIG_KSU
+       extern int ksu_hide_setprocattr(const char *, void *, size_t);
+       ksu_hide_setprocattr(name, value, size);
+#endif
+
        lsm_for_each_hook(scall, setprocattr) {
                if (lsmid != 0 && lsmid != scall->hl->lsmid->id)
                        continue;
 ```




rm -rf drivers/kernelsu
rm drivers/kernelsu

rm -rf KernelSU
git clone -b staging https://github.com/backslashxx/KernelSU.git KernelSU/
cd KernelSU/
git config --unset-all remote.origin.fetch
git config --add remote.origin.fetch '+refs/heads/master:refs/remotes/origin/master'
git config --add remote.origin.fetch '+refs/heads/staging:refs/remotes/origin/staging'
git fetch --prune origin
git for-each-ref --format='%(refname)' refs/remotes/origin/ | grep -vE '^refs/remotes/origin/(HEAD|master|staging)$' | xargs -r -n1 git update-ref -d
git switch -c master origin/master
git branch -a
cd ../

ln -s ../KernelSU/kernel drivers/kernelsu
ls -ld drivers/kernelsu
readlink -f drivers/kernelsu
ls -l drivers/kernelsu/Kconfig
ls -l drivers/kernelsu/Makefile
ls -l drivers/kernelsu/ksu.c

grep -n "kernelsu" drivers/Makefile drivers/Kconfig

readlink drivers/kernelsu
git ls-files drivers/kernelsu | head

grep -n -A20 -B5 'config KSU' KernelSU/kernel/Kconfig
grep -n 'KSU' kernel/arch/arm64/configs/<config>

CONFIG_KSU=y
CONFIG_KSU_KPROBES_KSUD=n
CONFIG_KSU_FEATURE_ADBROOT=y
CONFIG_KSU_SHELL_HAS_SU_ALWAYS=y
CONFIG_KSU_HOSTSREDIRECT=y