#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /distribution/Library/sync
#   Description: A simple synchronization library for two hosts
#   Author: Ondrej Moris <omoris@redhat.com>
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

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

    rlPhaseStartSetup    
        rlRun "rlImport ./sync" || rlDie
    rlPhaseEnd

    rlPhaseStartTest "Library loading"
        rlRun "test -n \"$syncSHARE\""
        rlRun "test -n \"$syncROLE\"" 
        rlRun "test -n \"$syncCLIENT\""
        rlRun "test -n \"$syncSERVER\""
        rlRun "test -n \"$syncTEST\""
        rlRun "test -n \"$syncME\""
        rlRun "test -n \"$syncOTHER\""
        rlRun "test -n \"$syncTIMEOUT\""
	    rlRun "test -n \"$syncSLEEP\""
	    rlRun "test -n \"$syncTTL\""
        rlRun "test -n \"$syncETH\""
        __syncMountShared
        rlRun "test -d \"$syncSHARE\""
        rlRun "[ $(find $syncSHARE -mtime +$syncTTL | wc -l) -eq 0 ]" 0
        __syncUmountShared
	    oldtimeout=$syncTIMEOUT
	    export syncTIMEOUT=180
    rlPhaseEnd

    rlPhaseStartTest "Roles (syncIsClient, syncIsServer, syncRun)"
        if [[ $(hostname -I) =~ $syncCLIENT ]]; then
            rlRun "syncIsClient" 0
    	    rlRun "syncIsServer" 1
    	else
    	    rlRun "syncIsClient" 1
    	    rlRun "syncIsServer" 0
    	fi
    	rlRun "syncRun wrong parameters" 255
        syncRun "CLIENT" "[[ \"$(hostname -I)\" =~ $syncCLIENT ]]" 0
        syncRun "CLIENT" "[[ \"$(hostname -I)\" =~ $syncSERVER ]]" 1
        syncRun "SERVER" "[[ \"$(hostname -I)\" =~ $syncCLIENT ]]" 1
        syncRun "SERVER" "[[ \"$(hostname -I)\" =~ $syncSERVER ]]" 0
    rlPhaseEnd

    rlPhaseStartTest "Flags and messaging (syncSet, syncExp, syncCheck)"
        rlRun "syncSet" 1
    	rlRun "syncSet !@#!#" 2
    	rlRun "syncSet CORRECT_FLAG" 0
    	rlRun "syncSet ANOTHER_CORRECT_FLAG" 0
    	rlRun "syncSet ANOTHER_MESSAGE_FLAG 'message'" 0
    	rlRun "syncSet MESSAGE_FLAG 'message'" 0
    	rlRun "syncExp" 2
    	rlRun "syncExp !@#!@#!" 2
    	export syncTIMEOUT=20
    	rlRun "syncExp MISSING_FLAG" 1
    	export syncTIMEOUT=180
    	rlRun "syncExp CORRECT_FLAG" 0
    	export syncTIMEOUT=20
    	rlRun "syncExp CORRECT_FLAG" 1
    	export syncTIMEOUT=180
    	rlRun "syncExp MESSAGE_FLAG >message" 0
    	rlRun "[ \"$(cat message)\" == \"message\" ]" 0
    	rlRun "syncCheck" 2
    	rlRun "syncCheck !@#!@#!" 2
    	rlRun "syncCheck MISSING_FLAG" 1
    	rlRun "syncCheck ANOTHER_CORRECT_FLAG" 0
    	rlRun "syncCheck ANOTHER_CORRECT_FLAG" 1
    	rlRun "syncCheck ANOTHER_MESSAGE_FLAG >message" 0
    	rlRun "[ \"$(cat message)\" == \"message\" ]" 0
    	rlRun "syncCheck ANOTHER_MESSAGE_FLAG" 1
    rlPhaseEnd

    rlPhaseStartTest "Synchronization (syncSynchronize)"
        rlRun "syncSynchronize" 0
    	time=$(date +%s)
    	rlRun "syncSet TIME $time" 0
    	rlRun "syncExp TIME >time" 0
        diff=$[$time-$(cat time)]
        [ $diff -lt 0 ] && diff=$[-1*$diff]
    	rlRun "[ $diff -lt $[2*$syncSLEEP] ]" 0
    rlPhaseEnd

    rlPhaseStartTest "syncIPv6 test"
        syncIPv6
    rlPhaseEnd

    rlPhaseStartTest "Data (syncPut & syncGet & syncGetNow)"
        rlRun "syncPut" 2
        rlRun "syncPut missing-file" 2
        rlRun "cp runtest.sh testdata" 0
        rlRun "syncPut testdata" 0
        rlRun "syncPut testdata" 1
        rlRun "syncGet" 2
        rlRun "syncGet testdata" 2
        rlRun "mv testdata testdata_orig" 0
        rlRun "syncGetNow testdata_wrong" 1
    	export syncTIMEOUT=20
        rlRun "syncGet testdata_wrong" 1
    	export syncTIMEOUT=180
        rlRun "syncGet testdata" 0
        rlRun "diff testdata testdata_orig" 0 
        rlRun "syncPut testdata" 0
        rlRun "rm -f testdata" 0
        rlRun "syncGetNow testdata" 0
        rlRun "diff testdata testdata_orig" 0 
        rlRun "rm -f testdata testdata_orig" 0
    	export syncTIMEOUT=20
        rlRun "syncGet testdata" 1
    rlPhaseEnd

    rlPhaseStartTest "Clean-up (syncClear)"
        rlRun "syncCleanUp" 0
        __syncMountShared
	    rlRun "[ $(ls -1 $syncSHARE/$syncTEST-$syncME-* | wc -l) -eq 0 ]" 0
        __syncUmountShared
    rlPhaseEnd

    rlPhaseStartCleanup
	    export syncTIMEOUT=$oldtimeout
    rlPhaseEnd

rlJournalPrintText

rlJournalEnd
