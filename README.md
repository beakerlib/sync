# NAME

distribution/sync - a simple synchronization library for two hosts

# DESCRIPTION

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

# GLOBAL VARIABLES

- syncETH (set automatically, immutable)

    NIC device which is used as a default route for machine IPv4/6 
    address stored in syncME. This is useful, for instance, when 
    sniffing traffic via tcpdump.

- syncETHv6

    This is IPv6 variant of syncETH.

- syncCLIENT (set automatically, immutable)

    IP address of the CLIENT. By default, IPv4 is preferred over IPv6
    address.

- syncCLIENTv6 (set automatically, immutable)

    IPv6 address of the CLIENT. If the CLIENT has no IPv6 address of
    a global scope, syncCLIENTv6 is empty.

- syncME (set automatically, immutable)

    IP address of the actual machine running the test. By default, 
    IPv4 is preferred over IPv6 address.

- syncMEv6 (set automatically, immutable)

    IPv6 address of the actual machine running the test. If the machine
    has no IPv6 address of a global scope, syncMEv6 is empty.

- syncOTHER (set automatically, immutable)

    IP address of the other machine running the test. By default, IPv4
    address is preferred over IPv6 address.

- syncOTHERv6 (set automatically, immutable)

    IPv6 address of the other machine running the test. If the machine
    has no IPv6 address of a global scope, syncMEv6 is empty.

- syncSERVER (set automatically, immutable)

    IP address of the SERVER. By default, IPv4 address is preferred
    over IPv6 address.

- syncSERVERv6 (set automatically, immutable)

    IPv6 address of the SERVER. If the SERVER has no IPv6 address of
    a global scope, syncSERVERv6 is empty.

- syncROLE (set automatically, immutable)

    A role in a mutual communication played by the actual machine - 
    either CLIENT or SERVER.

- syncTEST (set automatically, immutable)

    Unique test identifier (e.g. its name). By default, it is derived 
    from TEST variable exported in Makefile. If there is no Makefile 
    then it is derived from the test directory.

- syncSHARE (mandatory, must be set by user)

    A directory pointing to the storage of all synchronization data 
    used during communication. The directory must be accessible from
    both client and server all the time with read/write access. In 
    general, the safest bet is to mount some NFS mount point before 
    the testing. The is no default value and setting this variable 
    is mandatory.

- syncSLEEP (optional, 5 seconds by default)

    A time (in seconds) to sleep during doing synchronization queries.
    In other words, whenever a client or server waits for the other 
    side to set the flag of upload some data, it iteratively checks 
    for those flags or data on synchronization storage, syncSLEEP
    variable represents sleep time (in seconds) between those checks.

- syncTIMEOUT (optional, 1800 seconds / 30 minutes by default)

    A maximum time (in seconds) to wait for a synchronization flags or
    data, this value should be considerably high. Notice that when 
    waiting hits the syncTIMEOUT limit it fails and the rest of the 
    test on both sides fails as well. The important is that the test
    will be to clean-up phases eventually (as long as the time limit
    of the test is not yet reached).

- syncTTL (optional, 480 minutes / 8 hours by default)

    Represents "Time To Live" (in minutes) of synchronization flags and
    data in the synchronization storage. All flags and data which are
    older will be automatically removed during library loading. 
    The purpose of this is to make sure that data are not piling up in
    the synchronization storage over time.

# FUNCTIONS

## syncIsClient

Check if this host is CLIENT. If so, returns 0, otherwise 1.

## syncIsServer

Check if this host is SERVER. If so, returns 0, otherwise 1.

## syncRun who what

Execute commands given in 'what' by rlRun on 'who' which can be
either CLIENT or SERVER. For instance, the following three commands
are equivalent:

    * syncRun "CLIENT" -s "date" 0 "Printing date on CLIENT"

    * syncIsClient && rlRun -s "date" 0 "Printing date on CLIENT"

    * if [ "$syncROLE" == "CLIENT" ]; then
        rlRun -s "date" 0 "Printing date on CLIENT"
      fi

Return an exit code of rlRun and 255 in case of error.

## syncCleanUp

Removes all test synchronization data created by the other side of
the connection. This function should be called only in clean-up 
phase as the last sync function.

Return 0.

## syncSynchronize

Synchronize both sides of the connection Both sides waits for each
other so that time on CLIENT and SERVER right after the return from
the function is within 2\*$syncSLEEP. Returns 0.

## syncSet flag \[value\]

Raise a flag represented by a file in the shared synchronization
storage. If an optional second parameter is given, it is written
into the flag file. If the second parameter is '-', a stdin is 
written into the flag file. Return 0 if the flag is successfully
created and a non-zero otherwise.

## syncExp flag

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

## syncCheck flag

Check if a flag represented by a file in the shared synchronization
storage is raised. If so, 0 is returned and flag message (if any) is
printed to the standard output. If a flag is not yet raised 1 is 
returned or 2 in case of errors.

## syncPut file

Stores a file in the shared sychnronization storage. A file should
have unique basename. Return 0 if a file is stored successfully, 1 
if a file with the same basename is already stored and 2 in case of
other errors.

## syncGet file

Waiting while a file appears in the shared sychnronization
storage, then the file is taken. Return 0 if a file is taken
correctly, 1 if waiting is terminated (tiemout reached, see 
syncTIMEOUT global variable) and 2 in case of other errors.

## syncGetNow file

Get a file from the shared sychnronization storage immediately.
Return 0 if a file is taken correctly, 1 if a file was not present
at the moment and 2 in case of other errors.

## syncIPv6

Function tries to determine IPv6 addresses from NICs and set
variables syncCLIENTv6, syncSERVERv6, syncMEv6, syncOTHERv6. 
If function fails, non-zero return code is returned.

# AUTHORS

- Ondrej Moris <omoris@redhat.com>
- Dalibor Pospisil <dapospis@redhat.com>
- Jaroslav Aster <jaster@redhat.com>
