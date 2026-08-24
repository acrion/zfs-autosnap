# zfs-autosnap

This Arch Linux package automatically creates and manages ZFS snapshots before system upgrades. It is designed to protect your system by creating reliable snapshots prior to major package updates, triggered by a Pacman hook.

## Features

- **Automatic ZFS snapshots**  
  Creates snapshots of a specified dataset before performing system upgrades.  

- **Snapshot description tagging**  
  Lets you set a custom autosnap:description for easy identification of snapshots.  

- **Automatic cleanup**  
  Deletes older snapshots beyond a user-defined limit to keep your snapshot history uncluttered.  

- **Pacman lock file handling**  
  Shifts the Pacman lock file (`/var/lib/pacman/db.lck`) to the side for the duration of the snapshot, ensuring that a system reverted to that snapshot does not come back holding a lock belonging to nobody. The file is put back promptly once the snapshot is established, and it is removed instead of reinstated if Pacman itself fails to survive the snapshot. Within the snapshot the lock exists under the name `db.lck.zfs-autosnap`, which Pacman ignores and which may be erased post-rollback.  

- **Configurable behavior**  
  The `/etc/zfs-autosnap.conf` file allows you to enable or disable snapshot creation, set custom dataset names, limit the number of snapshots, and more.

## Configuration

Edit `/etc/zfs-autosnap.conf` to match your preferences. For example:

- `skipAutosnap` (boolean) – Set to **true** to skip snapshot creation.  
- `dataset` (string) – Your ZFS dataset name (default is `ditana-root/ROOT/default`).  
- `snapshotDescription` (string) – Custom description for identifying snapshots.  
- `deleteSnapshots` (boolean) – Enables or disables automatic deletion of older snapshots.  
- `maxSnapshots` (integer) – Maximum number of autosnap snapshots to keep.

## Additional Information

For details on listing ZFS snapshots and performing rollbacks, see the [Ditana GNU/Linux Best Practices](https://ditana.org/docs/design-philosophy/best-practices/automatic-system-snapshots/#zfs).

## Acknowledgments

- **Marko Gobin ([gobonja on GitLab](https://gitlab.com/gobonja))**  
  Many thanks to Marko Gobin for creating [timeshift-autosnap](https://gitlab.com/gobonja/timeshift-autosnap), which served as the foundation for this project.  

## Contributing

Contributions, suggestions, and bug reports are warmly welcomed! Feel free to open an issue or submit a pull request on GitHub.
