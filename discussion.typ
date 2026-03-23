= Canonical Technical Take-Home Exercise

Author: Yushun Tang

Repository: #link("https://github.com/sudoytang/canonical-take-home")

#line()

= Exercise 1: Bootable Linux via QEMU

== Approach

The script downloads a pre-built AMD64 kernel from the Debian bookworm netboot
mirror, builds a minimal initramfs, packages it into a bootable ISO with a GRUB
EFI bootloader, and runs it under QEMU with OVMF UEFI firmware.

Steps performed by `run.sh`:

+ *Dependency check*: installs `curl`, `gcc`, `cpio`, `grub-efi-amd64-bin`,
  `xorriso`, `mtools`, `qemu-system-x86`, and `ovmf` via `apt` if not present.
+ *Kernel*: downloaded from the Debian bookworm netboot image
  (`debian-installer/amd64/linux`). No kernel compilation required.
+ *Init binary*: a minimal C program is compiled statically with `gcc -static`.
  It writes `"hello world\n"` to stdout via a raw `write()` syscall, then loops
  forever with `pause()`. No shell, no login, no session management.
+ *Initramfs*: the init binary is packed with `cpio` + `gzip` into
  `initramfs.img`. This is the entire root filesystem.
+ *Bootable ISO*: `grub-mkrescue` assembles a GRUB EFI ISO containing the
  kernel and initramfs. `grub.cfg` sets `timeout=0` and passes
  `console=ttyS0 quiet` so output appears on the serial console.
+ *QEMU*: boots the ISO with `-bios OVMF.fd` (UEFI firmware), `-cdrom`, and
  `-nographic` so all output goes to the terminal.

== Assumptions

- Host is Ubuntu 24.04 (or Debian-based) with `apt` available.
- Internet access is available to download the kernel and packages.
- The script runs in its working directory; all artifacts are written to
  `work/` and `out/` subdirectories, which are excluded from version control.
- `sudo` is used only for `apt-get`; if already running as root, it is skipped.
- OVMF is installed to the standard path `/usr/share/ovmf/OVMF.fd`.

#pagebreak()

= Exercise 2: Shred Tool in Go

== Implementation

`Shred(path string) error` in `shred.go`:

+ Calls `os.Stat` to obtain the file size.
+ Loops 3 times: fills a `[]byte` buffer of the same size with
  cryptographically random data via `crypto/rand`, opens the file with
  `O_WRONLY`, writes the buffer, calls `Sync()` to flush to the device,
  then closes the file.
+ Calls `os.Remove` to delete the file.

`crypto/rand` is used instead of `math/rand` because a cryptographically
secure random source makes the overwritten content harder to predict or reverse.

== Test Cases

=== Implemented

- *Normal file*: a file with text content is shredded and no longer exists
  afterwards.
- *Non-existent file*: passing a path that does not exist returns a not-exist
  error.
- *Empty file*: a zero-byte file is handled without error and deleted.
  `make([]byte, 0)` and `io.ReadFull` on an empty buffer are both no-ops.
- *No permission*: a file with mode `000` causes `Shred` to return a permission
  error. The test restores permissions and shreds the file afterwards for
  cleanup. Does not behave as expected when run as root.
- *Directory path*: passing a directory path returns an error (`EISDIR` on
  Linux when opening with `O_WRONLY`).
- *Symbolic link*: `Shred` follows the symlink, overwrites the target file 3
  times, and removes the symlink. The target file itself is not deleted. This
  is a known limitation documented in the test.

=== Not Implemented

- *Verify 3 overwrite passes*: the file is deleted at the end, so intermediate
  states cannot be observed externally without mocking OS syscalls.
- *Disk full*: requires a real or emulated full filesystem; the error originates
  at the OS level.
- *Binary files*: `Shred` operates on raw bytes and does not distinguish between
  text and binary content, so this is already covered by the happy-path test.
- *Root user*: the no-permission test will not behave as expected when run as
  root, since root bypasses file permission checks.

== Use Cases

`Shred` is useful when sensitive data must be removed from disk in a way that
makes recovery difficult:

- Deleting private keys, credentials, or tokens after use.
- Clearing temporary files containing personal data before application exit.
- Compliance scenarios where data retention policies require provable deletion
  (e.g. GDPR, HIPAA).
- Secure cleanup before decommissioning a storage device.

== Advantages

- Simple API: a single `Shred(path)` call handles overwriting and deletion.
- No external dependencies: uses only the Go standard library.
- Effective on HDDs: overwriting the same sectors once is sufficient to prevent
  recovery on modern magnetic drives; three passes exceeds current NIST
  guidelines.

== Drawbacks

- *Ineffective on SSDs*: flash storage uses wear leveling, which redirects
  writes to the same logical address to new physical pages. The original pages
  are not erased until the SSD's garbage collector reclaims them, potentially
  leaving the original data recoverable at the hardware level.

- *Ineffective on copy-on-write filesystems*: filesystems such as btrfs and ZFS
  never overwrite existing blocks, so the original data remains on disk until
  old blocks are reclaimed.

- *Journal and page cache*: journaling filesystems (ext4, NTFS) may retain
  copies of data in the journal. `Sync()` flushes kernel buffers to the device
  but cannot control SSD-internal caching.

- *Symlink behavior*: when passed a symlink, `Shred` overwrites the target file
  but only removes the symlink. The target file continues to exist with its
  content replaced by random data.

- *No atomicity*: if the process is interrupted mid-shred, the file may be left
  in a partially overwritten state.

- *True secure deletion* on modern hardware requires full-disk encryption
  (so raw blocks are already ciphertext) or hardware-level commands such as
  ATA Secure Erase or NVMe Sanitize.
