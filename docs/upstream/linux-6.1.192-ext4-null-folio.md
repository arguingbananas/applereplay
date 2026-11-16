# linux 6.1.192: NULL dereference in ext4_mb_load_buddy_gfp() (backport assumes ERR_PTR)

Draft bug report, for Debian (package `src:linux`, version 6.1.192-1) and the
stable kernel maintainers (stable@vger.kernel.org, linux-ext4@vger.kernel.org).
Found and reproduced on 2026-11-15/16 while building applereplay.

## Summary

Since 6.1.192, ext4 dereferences NULL in `ext4_mb_load_buddy_gfp()` whenever a
block group's buddy or bitmap page is not in the page cache. The oops leaves
the jbd2 transaction held, so every later write to the filesystem hangs
(systemd, journald, anything that writes). 6.1.190 is not affected.

On a machine with little memory the buddy cache is evicted easily: on an
original Apple TV (i686, 233 MB) it happened 6 minutes after boot, on a plain
`mktemp -d`.

## Cause

6.1.192 took these ext4 commits from mainline:

- `e6b6cbe9f2fb` ext4: convert some BUG_ON's in mballoc to use WARN_RATELIMITED instead
- `1c0f0e2b9b69` ext4: delete redundant calculations in ext4_mb_get_buddy_page_lock()
- `d34e4fd4e73f` ext4: convert bd_bitmap_page to bd_bitmap_folio (upstream 99b150d84e49, Stable-dep-of bdc56a9c46b2)
- `862483175d3d` ext4: convert bd_buddy_page to bd_buddy_folio (upstream 5eea586b47f0, Stable-dep-of bdc56a9c46b2)
- `a3a7d360252c` ext4: fix e4b bitmap inconsistency reports (upstream bdc56a9c46b2)
- `a8d83471c560` ext4: fix error pointer dereference in ext4_mb_load_buddy_gfp() (upstream c6a6c9694aad)

The folio conversions call `__filemap_get_folio()` and check the result with
`IS_ERR()` only, as is right in mainline since 6.4, where it returns an
ERR_PTR on failure. In 6.1, `__filemap_get_folio()` still returns NULL: for a
lookup without `FGP_CREAT` whenever the folio isn't cached, and for
`FGP_CREAT` when allocation fails. In 6.1.192's `ext4_mb_load_buddy_gfp()`:

```c
folio = __filemap_get_folio(inode->i_mapping, pnum, FGP_ACCESSED, 0);
if (IS_ERR(folio) || !folio_test_uptodate(folio) || folio_test_locked(folio)) {
```

With an uncached page, `folio` is NULL, `IS_ERR(NULL)` is false, and
`folio_test_uptodate(NULL)` faults. The same pattern is in the buddy half of
the function and in `ext4_mb_get_buddy_page_lock()`.

## Oops (6.1.192-1, i686)

```
BUG: kernel NULL pointer dereference, address: 00000000
#PF: supervisor read access in kernel mode
#PF: error_code(0x0000) - not-present page
Oops: 0000 [#1] PREEMPT SMP PTI
CPU: 0 PID: 18481 Comm: rm Not tainted 6.1.0-55-686-pae #1  Debian 6.1.192-1
Hardware name: Apple Inc. AppleTV1,1/Mac-F4228DC8, BIOS    ATV11.88Z.00DA.B01.0812010735 12/01/08
EIP: ext4_mb_load_buddy_gfp+0xa2/0x360 [ext4]
EAX: 00000000 EBX: 00000000 ...
Call Trace:
 ext4_free_blocks+0x3cc/0xb80 [ext4]
 ext4_ext_remove_space+0x7da/0x1490 [ext4]
 ext4_ext_truncate+0xd2/0xe0 [ext4]
 ext4_truncate+0x31d/0x500 [ext4]
 ext4_evict_inode+0x2d7/0x700 [ext4]
```

The second time, the same fault came through `ext4_mb_regular_allocator`
(allocation, from `mktemp`). Afterwards jbd2, systemd-journald and every
writer sit in D state (`wait_transaction_locked`); only a power cycle helps.
Filesystem: ext4 with 4 KiB blocks (so the buddy needs its own page),
`metadata_csum`, `orphan_file`, on a USB stick.

## Reproducer

As root, on an ext4 filesystem, with 6.1.192:

```sh
d=$(mktemp -d /var/tmp/repro.XXXXXX)
for i in $(seq 100); do head -c 262144 /dev/urandom > "$d/f$i"; done; sync
echo 3 > /proc/sys/vm/drop_caches
rm -rf "$d"; sync
```

The cache drop evicts the buddy cache; the next block allocation or free in
that group oopses. On 6.1.190 it completes in seconds.

## Suggested fix

For 6.1.y, either drop the two folio conversions and the commits that depend
on them, or make the converted call sites treat NULL as the 6.1 API means it:
a lookup returning NULL is "not cached" (go on to the `FGP_CREAT` path) and
an `FGP_CREAT` call returning NULL is `-ENOMEM`. The stable-dep pull of
99b150d84e49 and 5eea586b47f0 assumed mainline's ERR_PTR convention from
"mm: return an ERR_PTR from __filemap_get_folio" (6.4), which 6.1 lacks.

## Workaround

Stay on 6.1.190 (Debian's `linux-image-6.1.0-54-686-pae`, 6.1.190-1).
