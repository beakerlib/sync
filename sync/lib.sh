#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /distribution/Library/sync
#   Description: A simple synchronization library for two hosts
#   Authors: Ondrej Moris <omoris@redhat.com>
#            Dalibor Pospisil <dapospis@redhat.com>
#            Jaroslav Aster <jaster@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2012 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   library-prefix = sync
#   library-version = 9
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Library package requirements.
syncREQUIRES="bind-utils"

# Synchronization counter.
syncCOUNT=0

# Pattern for valid filename representing flag.
syncFLAG_PATTERN="^[A-Za-z0-9_-]*$"

# Logging prefix.
syncPREFIX="sync"

# Internal variables.
__syncSHAREDMODE=""

true <<'=cut'
=pod

=head1 NAME

distribution/sync - a simple synchronization library for two hosts

=head1 DESCRIPTION

This is a simple synchronization library for multihost testing for
two hosts. It provides signal setting and waiting as well as mutual
synchronization or message and data exchange.

A single host specified either by its hostname or IP address in 
a variable CLIENTS or SERVERS is referred to as CLIENT or SERVER, 
respectively. This library requires CLIENTS and SERVERS variables
to be set.

Please notice that this library requires storage accessible from both
CLIENT and SERVER for all synchronization flags and data (see syncSHARE
variable below).

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 GLOBAL VARIABLES

=over

=item syncETH (set automatically)

NIC device which is used as a default route for machine IPv4/6 
address stored in syncME. This is useful, for instance, when 
sniffing traffic via tcpdump.

=item syncETHv6

This is IPv6 variant of syncETH.

=item syncCLIENT (set automatically)

IP address of the CLIENT. By default, IPv4 is preferred over IPv6
address.

=item syncCLIENTv6 (set automatically)

IPv6 address of the CLIENT. If the CLIENT has no IPv6 address of
a global scope, syncCLIENTv6 is empty.

=item syncME (set automatically)

IP address of the actual machine running the test. By default, 
IPv4 is preferred over IPv6 address.

=item syncMEv6 (set automaticall)

IPv6 address of the actual machine running the test. If the machine
has no IPv6 address of a global scope, syncMEv6 is empty.

=item syncOTHER (set automatically)

IP address of the other machine running the test. By default, IPv4
address is preferred over IPv6 address.

=item syncOTHERv6 (set automatically)

IPv6 address of the other machine running the test. If the machine
has no IPv6 address of a global scope, syncMEv6 is empty.

=item syncSERVER (set automatically)

IP address of the SERVER. By default, IPv4 address is preferred
over IPv6 address.

=item syncSERVERv6 (set automatically)

IPv6 address of the SERVER. If the SERVER has no IPv6 address of
a global scope, syncSERVERv6 is empty.

=item syncROLE (set automatically)

A role in a mutual communication played by the actual machine - 
either CLIENT or SERVER.

=item syncTEST (set automatically)

Unique test identifier (e.g. its name). By default, it is derived 
from TEST variable exported in Makefile. If there is no Makefile 
then it is derived from the test directory.

=item syncSHARE (mandatory, no default)

A directory pointing to the storage of all synchronization data 
used during communication. The directory must be accessible from
both client and server all the time with read/write access. In 
general, the safest bet is to mount some NFS mount point before 
the testing. The is no default value and setting this variable 
is mandatory.

=item syncSLEEP (optional, 5 seconds by default)

A time (in seconds) to sleep during doing synchronization queries.
In other words, whenever a client or server waits for the other 
side to set the flag of upload some data, it iteratively checks 
for those flags or data on synchronization storage, syncSLEEP
variable represents sleep time (in seconds) between those checks.

=item syncTIMEOUT (optional, 1800 seconds / 30 minutes by default)

A maximum time (in seconds) to wait for a synchronization flags or
data, this value should be considerably high. Notice that when 
waiting hits the syncTIMEOUT limit it fails and the rest of the 
test on both sides fails as well. The important is that the test
will be to clean-up phases eventually (as long as the time limit
of the test is not yet reached).

=item syncTTL (optional, 480 minutes / 8 hours by default)

Represents "Time To Live" (in minutes) of synchronization flags and
data in the synchronization storage. All flags and data which are
older will be automatically removed during library loading. 
The purpose of this is to make sure that data are not piling up in
the synchronization storage over time.

=back

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Private Functions - used only within lib.sh
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# These two private functions are called before (mount) and after
# (umount) working with shared storage. By default they are not
# doing anything but they can be overriden to perform task such as
# read-only / read-write remounting if needed.

type __syncMountShared || function __syncMountShared { return 0; }
type __syncUmountShared || function __syncUmountShared { return 0; }

function __syncGet {

    local mode=$1

    shift

    if [ -z "$1" ]; then
        rlLogError "${syncPREFIX}: Missing file!"
        return 2
    fi

    if [ -e "$1" ]; then
        rlLogError "${syncPREFIX}: File $1 already exists in current directory!"
        return 2
    fi

    __syncMountShared
    rlLog "${syncPREFIX}: $syncROLE is waiting for file $1"
    local timer=0
    local rc=0
    while ! ls ${syncSHARE}/${syncTEST}-${syncOTHER}-${syncME}-${1}.sync >/dev/null 2>&1; do
        sleep $syncSLEEP
        timer=$[$timer+$syncSLEEP]

        if [ $mode == "noblock" ]; then
            rlLogError "${syncPREFIX}: File $1 not available!"
            rc=1
            break
        fi

        if [ $timer -gt $syncTIMEOUT ]; then
            rlLogError "${syncPREFIX}: Waiting terminated (timeout expired)!"
            rc=1
            break
        fi
    done
    if [ $rc -eq 0 ]; then
        mv ${syncSHARE}/${syncTEST}-${syncOTHER}-${syncME}-${1}.sync $1
        if [ ! -f $1 ]; then
            rlLogError "${syncPREFIX}: $syncROLE cannot store $1!"
            rc=2
        else
            rlLog "${syncPREFIX}: $syncROLE got file $1"
        fi
    fi
    __syncUmountShared

    return $rc
}

function __syncGetIPv6AddressFromDevice() {
    local device="$1"

    if [ -n "$device" ]; then
        ip address show dev "$device" | grep 'inet6' | grep 'scope global' | head -n 1 | sed 's/^.*inet6 \([^ \/]\+\).*$/\1/'
    else
        printf ""
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Public Functions - exported by the library
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 FUNCTIONS

=head2 syncIsClient

Check if this host is CLIENT. If so, returns 0, otherwise 1.

=cut

function syncIsClient {
    [ $syncROLE == "CLIENT" ] && return 0 || return 1
}

true <<'=cut'
=pod

=head2 syncIsServer

Check if this host is SERVER. If so, returns 0, otherwise 1.

=cut

function syncIsServer {
    [ $syncROLE == "SERVER" ] && return 0 || return 1
}

true <<'=cut'
=pod

=head2 syncRun who what

Execute commands given in 'what' by rlRun on 'who' which can be
either CLIENT or SERVER. For instance, the following three commands
are equivalent:

 * syncRun "CLIENT" -s "date" 0 "Printing date on CLIENT"

 * syncIsClient && rlRun -s "date" 0 "Printing date on CLIENT"

 * if [ "$syncROLE" == "CLIENT" ]; then
     rlRun -s "date" 0 "Printing date on CLIENT"
   fi

Return an exit code of rlRun and 255 in case of error.

=cut

function syncRun {
    if [ "$1" == "$syncROLE" ]; then
        shift 1
        rlRun "$@"
        return $?
    elif [ "$1" != "CLIENT" ] && [ "$1" != "SERVER" ]; then
        rlLogError "${syncPREFIX}: Missing role!"
        return 255

    fi
    return 0
}

true <<'=cut'
=pod

=head2 syncCleanUp

Removes all test synchronization data created by the other side of
the connection. This function should be called only in clean-up 
phase as the last sync function.

Return 0.

=cut

function syncCleanUp {
    rlLog "${syncPREFIX}: $syncROLE clears all sync data from other side" 0
    rm -f ${syncSHARE}/${syncTEST}-${syncOTHER}-${syncME}-*.sync
    sleep $syncSLEEP
    return 0
}

true <<'=cut'
=pod

=head2 syncSynchronize

Synchronize both sides of the connection Both sides waits for each
other so that time on CLIENT and SERVER right after the return from
the function is within 2*$syncSLEEP. Returns 0.

=cut

function syncSynchronize {

    syncCOUNT=$[$syncCOUNT + 1]

    rlLog "$syncPREFIX: Synchronizing CLIENT & SERVER"
    syncIsClient && syncSet  "I_SYNC_$syncCOUNT"
    syncIsServer && syncSet  "R_SYNC_$syncCOUNT"
    syncIsClient && syncExp "R_SYNC_$syncCOUNT"
    syncIsServer && syncExp "I_SYNC_$syncCOUNT"
    rlLog "$syncPREFIX: CLIENT & SERVER synchronized"

    return 0
}

true <<'=cut'
=pod

=head2 syncSet flag [value]

Raise a flag represented by a file in the shared synchronization
storage. If an optional second parameter is given, it is written
into the flag file. If the second parameter is '-', a stdin is 
written into the flag file. Return 0 if the flag is successfully
created and a non-zero otherwise.

=cut

function syncSet {

    local rc=0

    if [ -z "$1" ]; then
        rlLogError "${syncPREFIX}: Missing flag!"
        return 1
    fi

    if ! [[ "$1" =~ $syncFLAG_PATTERN ]]; then
        rlLogError "${syncPREFIX}: Incorrect flag (must match ${syncFLAG_PATTERN})!"
        return 2
    fi

    __syncMountShared
    rlLogDebug "${syncPREFIX}: Creating ${syncSHARE}/${syncTEST}-${syncME}-${syncOTHER}-${1}.sync"
    if ! touch ${syncSHARE}/${syncTEST}-${syncME}-${syncOTHER}-${1}.sync ; then
        rlLogError "${syncPREFIX}: Cannot create flag $1!"
        rc=2
    else
        if [[ "$2" == "-" ]]; then
            (
              echo -n "S_T_D_I_N:"
              cat -
            ) > ${syncSHARE}/${syncTEST}-${syncME}-${syncOTHER}-${1}.partial.sync
            if [ $? -ne 0 ]; then
                rlLogError "${syncPREFIX}: Cannot write flag!"
                rc=3
            else
                mv ${syncSHARE}/${syncTEST}-${syncME}-${syncOTHER}-${1}.partial.sync ${syncSHARE}/${syncTEST}-${syncME}-${syncOTHER}-${1}.sync
                if [ $? -ne 0 ]; then
                    rlLogError "${syncPREFIX}: Cannot write flag!"
                    rc=3
                else
                    rlLog "${syncPREFIX}: $syncROLE set flag $1 with a content"
                fi
            fi
        elif [ -n "$2" ]; then
            echo "$2" > ${syncSHARE}/${syncTEST}-${syncME}-${syncOTHER}-${1}.sync
            if [ $? -ne 0 ]; then
                rlLogError "${syncPREFIX}: Cannot write flag!"
                rc=3
            else
                rlLog "${syncPREFIX}: $syncROLE set flag $1 with message \"$2\""
            fi
        else
            rlLog "${syncPREFIX}: $syncROLE set flag $1"
        fi
    fi
    __syncUmountShared
    sleep $syncSLEEP

    return $rc
}

true <<'=cut'
=pod

=head2 syncExp flag

Waiting for a flag represented by a file in the shared
synchronization storage. If it contains some content, it is printed
to the standard output. The raised flag is removed afterwards. 
Waiting is termined when synchronization timeout (syncTIMEOUT) is
reached.

Waiting may be also unblocked by a user intervention in two ways:
  1. using /tmp/syncSet - this behaves the same as it would be set
     by syncSet() function including the value processing (touch or
     put a value in the file),
  2. using /tmp/syncBreak - this is a premanent setting which will
     unblock all future syncExp() function calls untils the test is
     executed again (just touch the file).

Return 0 when the flag is raised, 1 in case of timeout, 3 in case
of user's permanent unblock, and 2 in case of other errors.

=cut

function syncExp {

    local rc=0

    if [[ -z "$1" ]]; then
        rlLogError "${syncPREFIX}: Missing flag!"
        return 2
    fi

    if ! [[ "$1" =~ $syncFLAG_PATTERN ]]; then
        rlLogError "${syncPREFIX}: Incorrect flag (must match ${syncFLAG_PATTERN})!"
        return 2
    fi

    __syncMountShared
    rlLog "${syncPREFIX}: $syncROLE is waiting for flag $1"
    local matching_file
    local timer=0
    while :; do
        [[ -e /tmp/syncBreak ]] && {
            rlLogError "detected user's permanent break"
            return 3
        }
        for matching_file in "${syncSHARE}/${syncTEST}-${syncOTHER}-${syncME}-${1}.sync" "/tmp/syncSet"; do
          ls "$matching_file" >/dev/null 2>&1 && break 2
        done
        sleep $syncSLEEP
        timer=$[$timer+$syncSLEEP]
        if [ $timer -gt $syncTIMEOUT ]; then
            rlLogError "${syncPREFIX}: Waiting terminated (timeout expired)!"
            rc=1
            break
        fi
    done
    if [ $rc -eq 0 ]; then
        if [[ -s "$matching_file" ]]; then
            local message=$(head -c 10 "$matching_file")
            if [[ "$message" == "S_T_D_I_N:" ]]; then
              rlLog "${syncPREFIX}: $syncROLE got flag $1 with message a content"
              tail -c +11 "$matching_file"
            else
              message=$(cat "$matching_file")
              rlLog "${syncPREFIX}: $syncROLE got flag $1 with message \"$message\""
              echo "$message"
            fi
        else
            rlLog "${syncPREFIX}: $syncROLE got flag $1"
        fi
        rm -f $matching_file
    fi
    __syncUmountShared

    return $rc
}

true <<'=cut'
=pod

=head2 syncCheck flag

Check if a flag represented by a file in the shared synchronization
storage is raised. If so, 0 is returned and flag message (if any) is
printed to the standard output. If a flag is not yet raised 1 is 
returned or 2 in case of errors.

=cut

function syncCheck {

    local rc=0

    if [ -z "$1" ]; then
        rlLogError "${syncPREFIX}: Missing flag!"
        return 2
    fi

    if ! [[ "$1" =~ $syncFLAG_PATTERN ]]; then
        rlLogError "${syncPREFIX}: Incorrect flag (must match ${syncFLAG_PATTERN})!"
        return 2
    fi

    __syncMountShared
    rlLog "${syncPREFIX}: $syncROLE is checking flag $1"
    if ls ${syncSHARE}/${syncTEST}-${syncOTHER}-${syncME}-${1}.sync >/dev/null 2>&1; then
        if [ -s ${syncSHARE}/${syncTEST}-${syncOTHER}-${syncME}-${1}.sync ]; then
            local message=$(cat ${syncSHARE}/${syncTEST}-${syncOTHER}-${syncME}-${1}.sync)
            rlLog "${syncPREFIX}: $syncROLE got flag $1 with message \"$message\""
            echo $message
        else
            rlLog "${syncPREFIX}: $syncROLE got flag $1"
        fi
        rm -f ${syncSHARE}/${syncTEST}-${syncOTHER}-${syncME}-${1}.sync
    else
        rlLog "${syncPREFIX}: $syncROLE did not get flag $1"
        rc=1
    fi
    __syncUmountShared

    return $rc
}

true <<'=cut'
=pod

=head2 syncPut file

Stores a file in the shared sychnronization storage. A file should
have unique basename. Return 0 if a file is stored successfully, 1 
if a file with the same basename is already stored and 2 in case of
other errors.

=cut

function syncPut {

    local rc=0

    if [ -z "$1" ] || [ ! -f "$1" ]; then
        rlLogError "${syncPREFIX}: Missing file!"
        return 2
    fi

    __syncMountShared
    local T=$(basename $1)
    if ls ${syncSHARE}/${syncTEST}-${syncME}-${syncOTHER}-${T}.sync >/dev/null 2>&1; then
        rlLogError "${syncPREFIX}: File $T is already stored!"
        rc=1
    else
        cp $1 ${syncSHARE}/${syncTEST}-${syncME}-${syncOTHER}-${T}.sync
        if ! ls ${syncSHARE}/${syncTEST}-${syncME}-${syncOTHER}-${T}.sync >/dev/null 2>&1; then
            rlLogError "${syncPREFIX}: $syncROLE cannot put $T"
            rc=2
        else
            rlLog "${syncPREFIX}: $syncROLE put file $T"
        fi
    fi
    __syncUmountShared

    return $rc
}

true <<'=cut'
=pod

=head2 syncGet file

Waiting while a file appears in the shared sychnronization
storage, then the file is taken. Return 0 if a file is taken
correctly, 1 if waiting is terminated (tiemout reached, see 
syncTIMEOUT global variable) and 2 in case of other errors.

=cut

function syncGet {

    __syncGet "block" $@

    return $?
}

true <<'=cut'
=pod

=head2 syncGetNow file

Get a file from the shared sychnronization storage immediately.
Return 0 if a file is taken correctly, 1 if a file was not present
at the moment and 2 in case of other errors.

=cut

function syncGetNow {

    __syncGet "noblock" $@

    return $?
}

true <<'=cut'
=pod

=head2 syncIPv6

Function tries to determine IPv6 addresses from NICs and set
variables syncCLIENTv6, syncSERVERv6, syncMEv6, syncOTHERv6. 
If function fails, non-zero return code is returned.

=cut

function syncIPv6 {

    rlLog "========== OLD SETTINGS =========="
    rlLog "syncCLIENTv6 = ${syncCLIENTv6}"
    rlLog "syncSERVERv6 = ${syncSERVERv6}"
    rlLog "syncOTHERv6 = ${syncOTHERv6}"
    rlLog "syncMEv6 = ${syncMEv6}"
    rlLog "========== OLD SETTINGS =========="

    if syncIsClient; then
        syncCLIENTv6="$(__syncGetIPv6AddressFromDevice "$syncETHv6")"
        syncMEv6="$syncCLIENTv6"

        rlRun "syncSERVERv6=$(syncExp SERVERv6)"
        rlRun "syncSet CLIENTv6 ${syncCLIENTv6}"

        syncOTHERv6="$syncSERVERv6"
    fi

    if syncIsServer; then
        syncSERVERv6="$(__syncGetIPv6AddressFromDevice "$syncETHv6")"
        syncMEv6="$syncSERVERv6"

        rlRun "syncSet SERVERv6 ${syncSERVERv6}"
        rlRun "syncCLIENTv6=$(syncExp CLIENTv6)"

        syncOTHERv6="$syncCLIENTv6"
    fi

    rlLog "========== NEW SETTINGS =========="
    rlLog "syncCLIENTv6 = ${syncCLIENTv6}"
    rlLog "syncSERVERv6 = ${syncSERVERv6}"
    rlLog "syncOTHERv6 = ${syncOTHERv6}"
    rlLog "syncMEv6 = ${syncMEv6}"
    rlLog "========== NEW SETTINGS =========="

    if [ -z "$syncCLIENTv6" ] || [ -z "$syncSERVERv6" ] || [ -z "$syncMEv6" ] || [ -z "$syncOTHERv6" ]; then
        rlLogError "IPv6 addresses are not properly set."
        return 1
    else
        return 0
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Initialization & Verification
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   This is an initialization and verification callback which will
#   be called by rlImport after sourcing the library. The function
#   returns 0 only when the library is ready to serve.

function syncLibraryLoaded {

    # Attempt to import internal environment where the following
    # is set:
    #
    # - syncSHARE variable
    # - __syncMountShared() function
    # - __syncUmountShared() function
    #
    # Is is expected to fail without access to internal network and
    # it only means that syncSHARE need to be set.
    rlImport "distribution/sync-internal"

    # Check package requirements.
    if rlIsRHEL "7"; then
        pkg_tool="yum"
    else
        pkg_tool="dnf"
    fi
    $pkg_tool install -y $syncREQUIRES --skip-broken
    for R in $syncREQUIRES; do        
        rlAssertRpm $R || return 1
    done

    # Setting defaults for optional global variables.
    [ -z "$syncSLEEP" ] && syncSLEEP=5
    rlLog "$syncPREFIX: Setting syncSLEEP to $syncSLEEP seconds"

    [ -z "$syncTIMEOUT" ] && syncTIMEOUT=7200
    rlLog "$syncPREFIX: Setting syncTIMEOUT to $syncTIMEOUT seconds"

    if [ -z "$syncTEST" ]; then
        if [ -z "$TEST" ]; then
            # If TEST is not set via Makefile, use directory name.
            TEST=$(pwd | awk -F '/' '{print $NF}')
        fi
        syncTEST=$( echo $TEST | tr '/' '_' | tr ' ' '_' )
        rlLog "$syncPREFIX: Setting syncTEST to $syncTEST"
    fi

    [ -z "$syncTTL" ] && syncTTL=600
    rlLog "$syncPREFIX: Setting syncTTL to $syncTTL minutes"

    # Checking that the following global variables are not set,
    # They need to be set by the library!
    if [ -n "$syncME" ]; then
        rlLogError "$syncPREFIX: Setting syncME is not allowed!"
        return 1
    fi
    if [ -n "$syncOTHER" ]; then
        rlLogError "$syncPREFIX: Setting syncOTHER is not allowed!"
        return 1
    fi
    if [ -n "$syncETH" ]; then
        rlLogError "$syncPREFIX: Setting syncETH is not allowed!"
        return 1
    fi
    if [ -n "$syncCLIENT" ]; then
        rlLogError "$syncPREFIX: Setting syncCLIENT is not allowed!"
        return 1
    fi
    if [ -n "$syncSERVER" ]; then
        rlLogError "$syncPREFIX: Setting syncSERVER is not allowed!"
        return 1
    fi

    # Setting roles.
    #
    # In TMT roles are defined in FMF metadata and hence we need to
    # propagate them to CLIENTS and SERVERS. Roles server and client
    # must be used in TMT plan.
    [ -n "${SERVERS}" ] || export SERVERS=${TMT_GUESTS[server.hostname]}
    [ -n "${CLIENTS}" ] || export CLIENTS=${TMT_GUESTS[client.hostname]}

    # In Beaker we have CLIENTS and SERVERS variables set, we expect each
    # of them to contain exactly one hostname or IP address.
    if [ $(echo "$CLIENTS" | wc -w) -eq 1 ]; then

        # IPv4/6 address of SERVER
        local clientIPV=4

        if [[ $CLIENTS =~ ^[0-9.]+$ ]]; then
            syncCLIENT=$CLIENTS
            syncCLIENTv6=""
        elif [[ $CLIENTS =~ ^[0-9A-Fa-f.:]+$ ]]; then
            syncCLIENT=$CLIENTS
            syncCLIENTv6=$CLIENTS
            clientIPV=6
        else
            if getent hosts -s files $CLIENTS; then
                syncCLIENT=$( getent hosts -s files $CLIENTS | awk '{print $1}' | head -1 )
            else
                syncCLIENT=$( host $CLIENTS | sed 's/^.*address\s\+//' | head -1 )
            fi

            if ! [[ $syncCLIENT =~ ^[0-9.]+$ ]] && \
                [[ $syncCLIENT =~ ^[0-9A-Fa-f.:]+$ ]]; then
                syncCLIENTv6=$syncCLIENT
                clientIPV=6
            else
                syncCLIENTv6=$( host $CLIENTS | grep "IPv6" | sed 's/^.*IPv6 address\s\+//' | head -1 )
            fi
        fi
        syncCLIENT_IP="$syncCLIENT"
        syncCLIENT_IPv6="$syncCLIENTv6"
        rlLog "$syncPREFIX: Setting syncCLIENT and syncCLIENT_IP to \"$syncCLIENT\""
        rlLog "$syncPREFIX: Setting syncCLIENTv6 and syncCLIENT_IPv6 to \"$syncCLIENTv6\""
        syncCLIENT_HOSTNAME="$(host $syncCLIENT_IP | sed 's/^.*pointer\s\+//;s/\.$//' | head -1; exit $PIPESTATUS)" \
          || syncCLIENT_HOSTNAME=$CLIENTS
        rlLog "$syncPREFIX: Setting syncCLIENT_HOSTNAME to \"$syncCLIENT_HOSTNAME\""
    else
        rlLogError "$syncPREFIX: Variable CLIENTS must contain exactly one entry!"
        return 1
    fi

    if [ $(echo "$SERVERS" | wc -w) -eq 1 ]; then

        # IPv4/6 address of SERVER
        local serverIPV=4

        if [[ $SERVERS =~ ^[0-9.]+$ ]]; then
            syncSERVER=$SERVERS
            syncSERVERv6=""
        elif [[ $SERVERS =~ ^[0-9A-Fa-f.:]+$ ]]; then
            syncSERVER=$SERVERS
            syncSERVERv6=$SERVERS
            serverIPV=6
        else
            if getent hosts -s files $SERVERS; then
                syncSERVER=$( getent hosts -s files $SERVERS | awk '{print $1}' | head -1 )
            else
                syncSERVER=$( host $SERVERS | sed 's/^.*address\s\+//' | head -1 )
            fi
            if ! [[ $syncSERVER =~ ^[0-9.]+$ ]] && \
                [[ $syncSERVER =~ ^[0-9A-Fa-f.:]+$ ]]; then
                syncSERVERv6=$syncSERVERS
                serverIPV=6
            else
                syncSERVERv6=$( host $SERVERS | grep "IPv6" | sed 's/^.*IPv6 address\s\+//' | head -1 )
            fi
        fi
        syncSERVER_IP="$syncSERVER"
        syncSERVER_IPv6="$syncSERVERv6"
        rlLog "$syncPREFIX: Setting syncSERVER and syncSERVER_IP to \"$syncSERVER\""
        rlLog "$syncPREFIX: Setting syncSERVERv6 and syncSERVER_IPv6 to \"$syncSERVERv6\""
        syncSERVER_HOSTNAME="$(host $syncSERVER_IP | sed 's/^.*pointer\s\+//;s/\.$//' | head -1; exit $PIPESTATUS)" \
          || syncSERVER_HOSTNAME=$SERVERS
        rlLog "$syncPREFIX: Setting syncSERVER_HOSTNAME to \"$syncSERVER_HOSTNAME\""
    else
        rlLogError "$syncPREFIX: Variable SERVERS must contain exactly one entry!"
        return 1
    fi

    # Resolving which end of a communication is this host.
    syncETH="$(ip -4 -o route list | grep 'default' | head -1 | sed 's/^.* dev \([^ ]\+\) .*$/\1/')"
    syncETHv6="$(ip -6 -o route list | grep 'default' | head -1 | sed 's/^.* dev \([^ ]\+\) .*$/\1/')"
    if [ -z "$syncETH" ]; then
        rlLogError "${syncPREFIX}: Cannot determine NIC for default route!"
        return 1
    else
        rlLog "${syncPREFIX}: Setting syncETH to \"${syncETH}\""
        rlLog "${syncPREFIX}: Setting syncETHv6 to \"${syncETHv6}\""
    fi

    local me4="$(ip -f inet a s dev ${syncETH} | grep inet | awk '{ print $2; }' | sed 's/\/.*$//')"
    local me6="$(ip -f inet6 a s dev ${syncETHv6} | grep 'inet6' | grep -v 'scope link' | awk '{ print $2; }' | sed 's/\/.*$//')"

    if [ "$me4" = "$syncCLIENT" ] || [ "$me6" = "$syncCLIENT" ]; then
        syncROLE="CLIENT"
        syncME="$syncCLIENT"
        syncOTHER="$syncSERVER"
        syncMEv6="$syncCLIENTv6"
        syncOTHERv6="$syncSERVERv6"
        syncME_HOSTNAME="$syncCLIENT_HOSTNAME"
        syncOTHER_HOSTNAME="$syncSERVER_HOSTNAME"
        syncME_IP="$syncCLIENT"
        syncOTHER_IP="$syncSERVER"
        syncME_IPv6="$syncCLIENTv6"
        syncOTHER_IPv6="$syncSERVERv6"
    elif [ "$me4" = "$syncSERVER" ] || [ "$me6" = "$syncSERVER" ]; then
        syncROLE="SERVER"
        syncME="$syncSERVER"
        syncOTHER="$syncCLIENT"
        syncMEv6="$syncSERVERv6"
        syncOTHERv6="$syncCLIENTv6"
        syncME_HOSTNAME="$syncSERVER_HOSTNAME"
        syncOTHER_HOSTNAME="$syncCLIENT_HOSTNAME"
        syncME_IP="$syncSERVER"
        syncOTHER_IP="$syncCLIENT"
        syncME_IPv6="$syncSERVERv6"
        syncOTHER_IPv6="$syncCLIENTv6"
    else
        rlLogError "${syncPREFIX}: Cannot determined communication sides!"
        return 1
    fi

    # Ready to go.
    rlLog "${syncPREFIX}: Setting syncROLE to \"${syncROLE}\""
    rlLog "${syncPREFIX}: Setting syncME and syncME_IP to \"${syncME}\""
    rlLog "${syncPREFIX}: Setting syncMEv6 and syncME_IPv6 to \"${syncMEv6}\""
    rlLog "${syncPREFIX}: Setting syncOTHER and syncOTHER_IP to \"${syncOTHER}\""
    rlLog "${syncPREFIX}: Setting syncOTHERv6 and syncOTHER_IPv6 to \"${syncOTHERv6}\""
    rlLog "${syncPREFIX}: Setting syncME_HOSTNAME to \"${syncME_HOSTNAME}\""
    rlLog "${syncPREFIX}: Setting syncOTHER_HOSTNAME to \"${syncOTHER_HOSTNAME}\""

    # It must be possible to create a file in the storage location.
    if [ -z "$syncSHARE" ]; then
        rlLogError "${syncPREFIX}: syncSHARE is not set!"
        return 1
    fi
    if ! __syncMountShared; then
        rlLogError "$syncPREFIX: __syncMountShared() failed!"
        return 1
    fi        
    local rnd=$( cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c6 )
    if ! touch "${syncSHARE}/${syncTEST}_${rnd}" || \
       ! rm -f "${syncSHARE}/${syncTEST}_${rnd}"; then
        rlLogError "${syncPREFIX}: Cannot create test flag in ${syncSHARE}!"
        return 1
    fi

    # Cleaning orphaned flags and data in the storage.
    for f in $(find $syncSHARE -name '*.sync' -mmin +$syncTTL); do
        rlLog "$syncPREFIX: Clean-up - $f is orphaned, removing"
        rm -f $f
    done
    rlLog "$syncPREFIX: Shared synchronization storage cleared"

    # Initial storage clean-up (data related to this execution).
    rlLog "${syncPREFIX}: $syncROLE clears all its data"
    rm -f ${syncSHARE}/${syncTEST}-${syncME}-${syncOTHER}-*.sync /tmp/syncSet /tmp/syncBreak
    if ! __syncUmountShared; then
        rlLogError "$syncPREFIX: __syncUmountShared() failed!"
        return 1
    fi
    
    rlLog ""
    rlLog "$syncPREFIX: CLIENT is $CLIENTS ($syncCLIENT)"
    rlLog "$syncPREFIX: SERVER is $SERVERS ($syncSERVER)"
    rlLog ""
    rlLog "$syncPREFIX: This test runs as $syncROLE"

    if [[ -n "$syncOTHER_IP" ]]; then
      if ping -c 1 $syncOTHER_IP > /dev/null; then
        rlLogInfo    "$syncPREFIX: check IPv4 connection (ping) ............ OK"
      else
        rlLogWarning "$syncPREFIX: check IPv4 connection (ping) ............ could not reach the other side using IPv4"
      fi
    else
      rlLogWarning   "$syncPREFIX: check IPv4 connection (ping) ............ skipped due to missing IPv4"
    fi

    if [[ -n "$syncOTHER_IPv6" ]]; then
      if ping -c 1 $syncOTHER_IPv6 > /dev/null; then
        rlLogInfo    "$syncPREFIX: check IPv6 connection (ping) ............ OK"
      else
        rlLogWarning "$syncPREFIX: check IPv6 connection (ping) ............ could not reach the other side using IPv6"
      fi
    else
      rlLogWarning   "$syncPREFIX: check IPv6 connection (ping) ............ skipped due to missing IPv6"
    fi

    if [[ -n "$syncOTHER_HOSTNAME" ]]; then
      if ping -c 1 $syncOTHER_HOSTNAME > /dev/null; then
        rlLogInfo    "$syncPREFIX: check connection using hostname (ping) .. OK"
      else
        rlLogWarning "$syncPREFIX: check connection using hostname (ping) .. could not reach the other side using hostname"
      fi
    else
      rlLogWarning   "$syncPREFIX: check connection using hostname (ping) .. skipped due to missing hostname"
    fi

    return 0
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Authors
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 AUTHORS

=over

=item *

Ondrej Moris <omoris@redhat.com>
Dalibor Pospisil <dapospis@redhat.com>
Jaroslav Aster <jaster@redhat.com>

=back

=cut
