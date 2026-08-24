#!/usr/bin/env bats
#
# What the hook does with /var/lib/pacman/db.lck.
#
# The hook runs while pacman holds that lock, and it takes the lock out of the
# file system for the moment of the snapshot so that a rolled back system does
# not come back with a lock nobody owns. Everything here is about the window in
# which the lock is not where pacman left it: how long it lasts, what is in the
# snapshot, and what happens when pacman does not survive it.
#
# On 2026-08-22 one of those windows cost a machine two days of updates. The
# hook relocated the lock to /tmp, pacman ended while it was there and removed
# nothing, and the hook then moved the file back. The lock that came back
# belonged to no process, so every half-hourly unattended upgrade after it sat
# waiting for a transaction that had finished long ago, until the file was
# deleted by hand.

setup() {
    WORK="$BATS_TEST_TMPDIR"
    export WORK

    export ZFS_AUTOSNAP_PACMAN_DB_DIR="$WORK/pacman-db"
    export ZFS_AUTOSNAP_CONF="$WORK/zfs-autosnap.conf"
    export STUB_LOG="$WORK/zfs-calls"
    DB="$ZFS_AUTOSNAP_PACMAN_DB_DIR"
    LOCK="$DB/db.lck"
    ASIDE="$DB/db.lck.zfs-autosnap"

    SCRIPT="$BATS_TEST_DIRNAME/zfs-autosnap"
    export SCRIPT

    mkdir -p "$DB" "$WORK/bin"
    write_stubs
    PATH="$WORK/bin:$PATH"

    cat > "$ZFS_AUTOSNAP_CONF" <<EOF
dataset=testpool/ROOT/default
deleteSnapshots=true
maxSnapshots=3
snapshotDescription={zfs-autosnap} {test}
EOF
}

teardown() {
    # It is stopped, so nothing milder than KILL would reach it.
    [[ -e $WORK/reaperless.pid ]] && kill -KILL "$(<"$WORK/reaperless.pid")" 2>/dev/null
    return 0
}

write_stubs() {
    # findmnt only informs the script that this is not a Live CD.
    cat > "$WORK/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
echo zfs
EOF

    # The stub records, for every call the script makes, whether the lock was in
    # the file system at that moment and whether it was lying beside it. That
    # record is what the assertions read: it is the only way to see the state of
    # a window that is closed again by the time the script ends.
    cat > "$WORK/bin/zfs" <<'EOF'
#!/usr/bin/env bash
db=$ZFS_AUTOSNAP_PACMAN_DB_DIR
lock=absent; [[ -e $db/db.lck ]] && lock=present
aside=absent; [[ -e $db/db.lck.zfs-autosnap ]] && aside=present
echo "$1 lock=$lock aside=$aside" >>"$STUB_LOG"

case $1 in
    snapshot)
        [[ -n ${STUB_SNAPSHOT_HOOK:-} ]] && "$STUB_SNAPSHOT_HOOK"
        ;;
    list)
        # Five snapshots against a limit of three, so that two are deleted and
        # the deletion is visible in the record above.
        if [[ $2 == -t ]]; then
            for i in 1 2 3 4 5; do echo "testpool/ROOT/default@autosnap_$i"; done
        fi
        ;;
esac
exit 0
EOF

    # Stands in for pacman: it creates the lock the way pacman does, runs the
    # hook as its child, and then either dies without removing the lock or stays
    # to see what the hook returns.
    cat > "$WORK/bin/fake-pacman" <<'EOF'
#!/usr/bin/env bash
# Job control, so that the hook does not initiate with the interrupt signal
# already ignored, which is how a shell otherwise launches a background
# command. pacman initiates it with that signal at its default setting, and an
# interrupt is what the last test here pertains to.
set -m
echo $$ >"$WORK/pacman.pid"
: >"$ZFS_AUTOSNAP_PACMAN_DB_DIR/db.lck"
bash "$SCRIPT" >"$WORK/hook.out" 2>&1 &
hook=$!
echo "$hook" >"$WORK/hook.pid"

deadline=$((SECONDS + 30))
while [[ ! -e $WORK/in-snapshot ]] && ((SECONDS < deadline)); do sleep 0.02; done

case ${PACMAN_ROLE:-die} in
    die)
        # An upgrade that ends in the middle of the hook: pacman is gone and its
        # lock was not where it removed it from.
        kill -9 $$
        ;;
    interrupt-hook)
        kill -INT "$hook"
        touch "$WORK/release"
        wait "$hook"
        echo $? >"$WORK/hook.status"
        ;;
esac
EOF

    # Runs inside the stubbed snapshot, which is the one moment at which the
    # lock is out of the file system. It holds that window open until whatever
    # the test is about has happened.
    cat > "$WORK/bin/in-snapshot-hook" <<'EOF'
#!/usr/bin/env bash
touch "$WORK/in-snapshot"
pacman=$(<"$WORK/pacman.pid")
deadline=$((SECONDS + 30))

state() {
    local line
    [[ -r /proc/$pacman/stat ]] || return 1
    read -r line <"/proc/$pacman/stat" || return 1
    line=${line##*') '}
    printf '%s\n' "${line%% *}"
}

case ${SNAPSHOT_WAIT:-parent-gone} in
    parent-gone)
        while [[ -e /proc/$pacman ]] && ((SECONDS < deadline)); do sleep 0.02; done
        ;;
    parent-zombie)
        # Dead but not yet collected by its own parent. The process number
        # remains, so anything that simply counts process numbers sees a pacman
        # that is not there any more.
        while [[ $(state) != Z ]] && ((SECONDS < deadline)); do sleep 0.02; done
        ;;
    release)
        while [[ ! -e $WORK/release ]] && ((SECONDS < deadline)); do sleep 0.02; done
        ;;
esac
EOF

    # Leaves the fake pacman a zombie once it has killed itself. A shell
    # collects a background child of its own accord as soon as it dies, so the
    # only reliable way to keep the dead process around is a parent that cannot
    # run at all.
    cat > "$WORK/bin/reaperless-parent" <<'EOF'
#!/usr/bin/env bash
fake-pacman &
kill -STOP $$
EOF

    chmod +x "$WORK"/bin/*
}

wait_for_hook() {
    local deadline=$((SECONDS + 30)) pid
    while [[ ! -e $WORK/hook.pid ]] && ((SECONDS < deadline)); do sleep 0.02; done
    [[ -e $WORK/hook.pid ]] || { echo "the hook was never started"; return 1; }
    pid=$(<"$WORK/hook.pid")
    while [[ -e /proc/$pid ]] && ((SECONDS < deadline)); do sleep 0.02; done
    [[ -e /proc/$pid ]] && { echo "the hook did not finish"; return 1; }
    return 0
}

@test "the snapshot is taken with the lock out of the file system and beside the database" {
    # Out of the file system lies the point of the whole exercise. Beside the
    # database rather than in /tmp is what makes it a rename: /tmp is a
    # different file system on most installations, so moving there copies and
    # unlinks instead, which is neither atomic nor reversible without a second
    # copy.
    : >"$LOCK"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -qx 'snapshot lock=absent aside=present' "$STUB_LOG"
}

@test "the lock is back before the old snapshots are deleted" {
    # Deleting snapshots may take a long time on a full pool, and each second
    # of that delay would be a second during which nothing prevents a second
    # pacman from initiating a transaction. Only the snapshot itself needs to
    # see the file system without the lock.
    : >"$LOCK"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -qx 'destroy lock=present aside=absent' "$STUB_LOG"
}

@test "a completed run gives the lock back unchanged" {
    : >"$LOCK"
    local before after
    before=$(stat -c %i "$LOCK")
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -e "$LOCK" ]
    [ ! -e "$ASIDE" ]
    after=$(stat -c %i "$LOCK")
    # The same file, not a copy of it: pacman is holding this one open.
    [ "$before" = "$after" ]
}

@test "a run without a pacman lock does not invent one" {
    # The script is an ordinary command in /usr/bin and can be run by hand.
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -e "$LOCK" ]
    [ ! -e "$ASIDE" ]
}

@test "no lock is left behind when pacman dies during the snapshot" {
    # The failure on 2026-08-22. pacman removes its lock when it ends, and it
    # did that while the file was somewhere else, so putting the file back means
    # putting back a lock that nothing will ever remove.
    export STUB_SNAPSHOT_HOOK="$WORK/bin/in-snapshot-hook"
    export SNAPSHOT_WAIT=parent-gone
    export PACMAN_ROLE=die
    run fake-pacman
    wait_for_hook
    [ ! -e "$LOCK" ]
    [ ! -e "$ASIDE" ]
}

@test "no lock is left behind when pacman has died but has not been collected yet" {
    # Between dying and being collected by its parent, a process keeps its
    # number and its entry under /proc. That is the state pacman is in at the
    # moment the hook finishes, because the shell or the service manager above
    # it collects it only after that.
    export STUB_SNAPSHOT_HOOK="$WORK/bin/in-snapshot-hook"
    export SNAPSHOT_WAIT=parent-zombie
    export PACMAN_ROLE=die
    reaperless-parent >/dev/null 2>&1 &
    echo $! >"$WORK/reaperless.pid"
    disown
    wait_for_hook
    [ ! -e "$LOCK" ]
    [ ! -e "$ASIDE" ]
}

@test "an interrupted hook gives the lock back and reports the interruption" {
    # The other half of the same question: pacman is still there, so the lock
    # still has an owner and has to go back. The status matters because the hook
    # carries AbortOnFail, and bash leaves an interrupted script at 0, which
    # tells pacman to go ahead with an upgrade that has no snapshot behind it.
    export STUB_SNAPSHOT_HOOK="$WORK/bin/in-snapshot-hook"
    export SNAPSHOT_WAIT=release
    export PACMAN_ROLE=interrupt-hook
    run fake-pacman
    [ -e "$WORK/hook.status" ]
    [ "$(<"$WORK/hook.status")" -eq 130 ]
    [ -e "$LOCK" ]
    [ ! -e "$ASIDE" ]
}
