#! /bin/sh 
#
# Copyright (c) 2000-2001,2003 Silicon Graphics, Inc.  All Rights Reserved.
# 
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
# 
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
# 
# Contact information: Silicon Graphics, Inc., 1500 Crittenden Lane,
# Mountain View, CA 94043, USA, or: http://www.sgi.com
#

# Get standard environment
. $PCP_DIR/etc/pcp.env

# Setup some default paths 

case "$PCP_PLATFORM" in
    linux)
	_logdir=/var/log
	_msgfil=messages
	;;

    irix)
	_logdir=/var/adm
	_msgfil=SYSLOG
	;;
esac

#
# Every supported server defines 10 variables which are used by addServer()
# and installFiles() to create a server specification for the weblog PMDA
# and a URL for the webping PMDA, respectively.
#
# access		The full path to the access log
# accessRegex		The regex for the access log
# errors		The full path to the error log
# errorRegex		The regex for the error log
# serverPath		The server path
# serverDesc		A desciption of the type of server
# serverName		The name for the server (must be unique)
# serverPort		Port the server is bound to
# docs			The full path to the document root
#			  "$noDocs"  - indicates there is no document root
# http			The URL for the server
# files			How to put the HTML files into the doc root
#			  "link"  - create a soft link
#			  "copy"  - copy the files
#			  "skip"  - do not create URLs for this server
#

do_logs=false
do_files=false
do_auto=false
do_verbose=false
debug=false
noDocs="???"
unknownDocs=""
docsDir="$PCP_DOC_DIR/pcpweb/"
link="pcpweb"
file1="index.html"
file2="planning.html"
file3="tasks.html"
pfx="  "
skipping="${pfx}skipping..."
tmp=/tmp/$$
trap "rm -f $tmp.*; exit" 0 1 2 3 15

# Duplicate entry check file
#
rm -f $tmp.dup
touch $tmp.dup

# pv 816562 - try to work around $PCP_DOC_DIR confusion
[ ! -x $docsDir -a -x /usr/pcp/doc/pcpweb/ ] && docsDir=/usr/pcp/doc/pcpweb/

LOCALHOSTNAME=`hostname`

# web server attribute names (global)
#
ATTRLIST="serverPort serverName docs access errors"

# look for netscape stuff here
#
NSROOTPATH="${NSROOTPATH-/usr/ns-home:/var/netscape/suitespot:/var/netscape/fasttrack}"

# the Netscape server types we know how to handle
#
NSTYPE="httpd https proxy"

# look for old outbox
#
OUTBOXPATH="${OUTBOXPATH-/var/mc-httpd}"

# look for old Netscape Proxy Servers here
#
NSPROXYPATH="${NSPROXYPATH-/var/ns-proxy}"

# look for NCSA servers here
#
NCSAPATH="${NCSAPATH-/var/www}"

# look for Zeus servers here
#
ZEUSPATH="${ZEUSPATH-/usr/local/zeus}"

# look for Squid Object caches here
#
SQUIDPATH="${SQUIDPATH-/usr/local/squid}"

# look for Apache servers here
# On Linux they live under /etc/httpd
# Apache from Irix Freeware keeps its stuff in /usr/freeware/apache/etc
# And by default it's in /usr/apache.
# On IRIX, the bundled Apache maintains its files below
# /var/sgi_apache/httpd-outbox
#
APACHEPATH="${APACHEPATH-/etc/httpd:/usr/freeware/apache:/usr/apache:/var/sgi_apache/httpd-outbox}"

# look for anonymous ftp here
#
FTPPATH="${FTPPATH:-$_logdir}"

# look for password file here (to determine ~ftp)
#
PASSWDPATH="${PASSWDPATH-/etc/passwd}"

# look for SYSLOG here
#
SYSLOGPATH="${SYSLOGPATH:-$_logdir/$_msgfil}"

# look for xferlog here (for wu_ftp)
# XFERLOG is default for wu_ftp
XFERLOG="${XFERLOG:-$_logdir/xferlog}"
# WUFTPLOG is used in sgi freeware wu_ftp
WUFTPLOG="${WUFTPLOG-$_logdir/wu-ftpd.log}"

_getLogFiles()
{
    $PCP_ECHO_PROG $PCP_ECHO_N "Full path to access log [$access] ""$PCP_ECHO_C"
    read ans
    if [ "X$ans" != "X" ]
    then
	access=$ans
	if [ ! -f $access ]
	then
	    echo "Warning: $access does not exist at this time."
	fi
    fi

    $PCP_ECHO_PROG $PCP_ECHO_N "Full path to error log [$errors] ""$PCP_ECHO_C"
    read ans
    if [ "X$ans" != "X" ]
    then
	errors=$ans
	if [ ! -f $errors ]
	then
	    echo "Warning: $errors does not exist at this time."
	fi
    fi
}

# _addServer_check
# 1: servername
# 2: other args for log file
# 3: server description
_addServer_check()
{
    if grep "$1" $tmp.dup > /dev/null 2>&1
    then
	echo "${pfx}Error: already found a server with the name \"$1\""
	if $do_auto
	then
	    echo "$skipping"
	else
	    $PCP_ECHO_PROG $PCP_ECHO_N "New name for server (or return to skip this server): ""$PCP_ECHO_C"
	    read ans
	    if [ "X$ans" != "X" ]
	    then
		if grep "$ans" $tmp.dup > /dev/null 2>&1
		then
		    echo "${pfx}Error: new server name already exists"
		    echo "$skipping"
		else
		    echo >> $logFile
		    echo "# $3." >> $logFile
		    echo "server $ans $2" >> $logFile
	 	    echo "$1" >> $tmp.dup
		fi
	    else
		echo "$skipping"
	    fi
	fi
    else
	echo >> $logFile
	echo "# $3." >> $logFile
	echo "server $1 $2" >> $logFile
 	echo "$1" >> $tmp.dup
    fi
}

_addServer()
{
    echo "Found $serverDesc at $serverPath"
    if [ \( -f "$access" -o -c "$access" \) -a \( -f "$errors" -o -c "$errors" \) ]
    then
	found="true"
	if [ "X$serverPort" = X ]
	then
	    echo "${pfx}identified as $serverName"
	    _addServer_check "$serverName" "on $accessRegex $access $errorRegex $errors" "$serverDesc"
	else
	    echo "${pfx}identified as $serverName:$serverPort"
	    _addServer_check "$serverName:$serverPort" "on $accessRegex $access $errorRegex $errors" "$serverDesc"
	fi
	echo
    else
	echo "${pfx}Error: log files are not in the expected place:"
	echo "${pfx}	$access"
        echo "${pfx}	$errors"
	if $do_auto
	then
	    echo "$skipping"
	else
	    echo
	    echo "Do you want to specify an alternate location for the log files"
	    $PCP_ECHO_PROG $PCP_ECHO_N "(otherwise this server will be ignored) [y] ""$PCP_ECHO_C"
	    read ans
	    if [ "X$ans" = "Xy" -o "X$ans" = "XY" -o "X$ans" = "X" ]
	    then
		_getLogFiles
		if [ "X$serverPort" = X ]
		then
		    _addServer_check "$serverName" "on $accessRegex $access $errorRegex $errors" "$serverDesc"
		else
		    _addServer_check "$serverName:$serverPort" "on $accessRegex $access $errorRegex $errors" "$serverDesc"
		fi
	    else
		echo "$skipping"
	    fi
	fi
	echo
    fi
}

_installFiles()
{
    
    echo
    echo "Found $serverDesc at $serverPath"
    if [ "$docs" != "$noDocs" ]
    then
	if [ "$docs" = "$unknownDocs" ]
	then
	    echo "${pfx}Error: unable to determine document root"
	    if $do_auto
	    then
	        echo "$skipping"
	    else
		echo
		$PCP_ECHO_PROG $PCP_ECHO_N "Path to document root (return to skip HTML link for this server): ""$PCP_ECHO_C"
		read ans
		if [ "X$ans" != "X" ]
		then
		    if [ -d $ans ]
		    then
			docs=$ans
		    else
			echo "\"$ans\" is not a directory."
		        echo "No link to HTML files will be created for this server."
		    fi
		fi
	    fi
	elif [ ! -d "$docs" ]
	then
	    echo "${pfx}Error: document root cannot be found at:"
	    echo "${pfx}	$docs"
	    if $do_auto
	    then
		docs=$unknownDocs
		echo "$skipping"
	    else
		echo
		echo "Path to document root (return to skip HTML link for this server)"
		$PCP_ECHO_PROG $PCP_ECHO_N "$docs: ""$PCP_ECHO_C"
		read ans
		if [ "X$ans" != "X" ]
		then
		    if [ -d $ans ]
		    then
			docs=$ans
		    else
			echo "${pfx}Error: \"$ans\" is not a directory."
		        docs=$unknownDocs
			echo "$skipping"
		    fi
		else
		    docs=$unknownDocs
		fi
 	    fi
	else
	    echo "${pfx}document root found at:"
	    echo "${pfx}$docs"
	fi

	if [ "$docs" != "$unknownDocs" ]
	then
	    if [ ! -f $docs/$link/$file1 -o ! -f $docs/$link/$file2 -o ! -f $docs/$link/$file3 ]
	    then
		if [ "$files" = "link" ]
		then
		    $PCP_ECHO_PROG $PCP_ECHO_N "Do you want a link to some sample HTML files created in this directory [y] ""$PCP_ECHO_C"
		elif [ "$files" = "copy" ]
		then
		    $PCP_ECHO_PROG $PCP_ECHO_N "Do you want some sample HTML files installed in this directory [y] ""$PCP_ECHO_C"
		fi

		read ans
		if [ "X$ans" = "Xy" -o "X$ans" = "XY" -o "X$ans" = "X" ]
		then
		    if [ "$files" = "link" ]
		    then
                        [ -L $docs/$link ] && rm -f $docs/$link
                        if [ -f $docs/$link ]
                        then
	                    echo "${pfx}Error: $docs/$link already exists."
	                    echo "$skipping"
                        else
			    ln -s $docsDir $docs/$link
                        fi
		    elif [ "$files" = "copy" ]
		    then
                        if [ ! -f $docs/$link -o -d $docs/$link ]
                        then 
		    	    install -v -F $docs/$link -m 444 -src $docsDir/$file1 $file1
		    	    install -v -F $docs/$link -m 444 -src $docsDir/$file2 $file2
		    	    install -v -F $docs/$link -m 444 -src $docsDir/$file3 $file3
                        else
	                    echo "${pfx}Error: $docs/$link is not a directory."
	                    echo "$skipping"
                        fi
		    fi

		    if [ "X$http" != X ]
		    then
			echo "$http/$link/$file1" >> $logFile
			echo "$http/$link/$file2" >> $logFile
			echo "$http/$link/$file3" >> $logFile
		    fi
		fi
	    else
	    	echo "${pfx}Note: the link to the sample HTML files already exists."
		if [ "X$http" != X ]
		then
		    echo "$http/$link/$file1" >> $logFile
		    echo "$http/$link/$file2" >> $logFile
		    echo "$http/$link/$file3" >> $logFile
		fi
	    fi
	else
	    if [ "$docs" != "$unknownDocs" ]
            then
                echo "$skipping"
            fi
	fi
    else
	echo "${pfx}Error: no document root, cannot install files."
	echo "$skipping"
    fi
    echo
}

_switchAction()
{
    if $do_verbose
    then
        echo "------------------------------------------------------------"
	echo "access      = $access"
	echo "accessRegex = $accessRegex"
	echo "errors      = $errors"
	echo "errorRegex  = $errorRegex"
	echo "serverPath  = $serverPath"
	echo "serverDesc  = $serverDesc"
	echo "serverName  = $serverName"
	echo "serverPort  = $serverPort"
	echo "docs        = $docs"
	echo "http        = $http"
	echo "files       = $files"
        echo "------------------------------------------------------------"
	echo
    fi

    if $do_logs
    then
    	_addServer
    else
        _installFiles
    fi
}

_scan_config()
{
    serverPort=
    serverName=
    errors=
    access=
    docs=

    eval `cat $* 2>/dev/null | $PCP_AWK_PROG '
NF == 2 && tolower($1) == "port"        { print "serverPort=" $2; next }
NF == 2 && tolower($1) == "errorlog"    { print "errors=" $2; next }
NF == 2 && tolower($1) == "servername"  { print "serverName=" $2; next }
tolower($1) == "init"   { for (i=1; i<=NF; i++) {
			    if (match($i, "^access=")) print $i
			    if (match($i, "^global=")) printf "access=%s ",substr($i,8,length($i)-7)
			  }
			  next
			}
tolower($0) ~ /fn="document-root"/ || tolower($0) ~ /fn=document-root/	{
			  for (i=1; i<=NF; i++) {
			    if (match($i, "^root=")) 
			      printf "docs=%s ",substr($i,6,length($i)-5)
			  }
			  next
			}'`
}

_netscape_extract()
{
    here=`pwd`
    echo >$tmp.ns
    for root in `echo "$NSROOTPATH" | sed -e 's/:/ /g'`
    do
	for type in $NSTYPE
	do
	    for dir in $root/$type-*
	    do
		[ -L "$dir" ] && continue
		if [ -d "$dir" ]
		then
		    cd $dir
		    check=`pwd`
		    cd $here
		    match=`grep "^$check " $tmp.ns`
		    if [ ! -z "$match" ]
		    then
			echo "$match $dir" | $PCP_AWK_PROG '
	{ if ($1 == $2) 
	    printf "The server at %s appears to be a link to %s which is already monitored as %s\n", $3, $2, $1
	  else if ($1 == $3) {
	    printf "The server at %s was already detected,\n", $1
	    printf "using the link %s. ", $2
	  }
	  else {
	    printf "The server at %s was already detected,\n", $1
	    printf "using the link %s.  The link %s,\n", $2, $3
	    printf "which is also to this server, will be ignored.\n"
	  }
	}'
		 	echo "$skipping"
			continue
		    fi
		    echo "$check $dir" >>$tmp.ns
		    access=
		    errors=
		    docs=
		    serverName=
		    serverPort=

		    if [ ! -f $dir/config/obj.conf ]
		    then
			echo "Found Netscape $type Server at $dir"
			echo "${pfx}Error: unable to find configuration file:"
			echo "${pfx}	$dir/config/obj.conf"
			echo "$skipping"
			echo
			continue
		    elif [ ! -f $dir/config/magnus.conf ]
		    then
			echo "Found Netscape $type Server at $dir"
			echo "${pfx}Error: unable to find configuration file:"
			echo "${pfx}	$dir/config/magnus.conf"
			echo "$skipping"
			echo
			continue
		    fi

		    _scan_config $dir/config/obj.conf $dir/config/magnus.conf

		    # fix server name as Netscape often adds a trailing '.'
		    serverName=`echo $serverName | sed -e 's/\.$//'`

		    if [ "X$serverName" = X -o "X$serverPort" = X ]
		    then
			echo "Found Netscape $type Server at $dir"
			echo "${pfx}Error: unable to determine server name or port from:"
			echo "${pfx}	$dir/config/magnus.conf"
			echo "$skipping"
			echo
			continue
		    fi

		    if [ "X$access" = X ]
		    then
			access=$dir/logs/access
			echo "Found Netscape $type Server at $dir"
			echo "${pfx}Warning: unable to determine access log name, assuming:"
			echo "${pfx}	$access"
			echo
		    fi

		    if [ "X$errors" = X ]
		    then
			errors=$dir/logs/errors
			echo "Found Netscape $type Server at $dir"
			echo "${pfx}Warning: unable to determine error log name, assuming:"
			echo "${pfx}	$errors"
			echo
		    fi

                    #
		    # figure out if this is a caching server or not
		    #
		    if [ -f $access ]
		    then
			num_lines=`wc -l $access | $PCP_AWK_PROG '{print $1}'`
			if [ $num_lines -gt 1 ]
			then
			    num_fields=`tail -n 1 $access | cut -f3 -d\" | wc -w`
			    if [ $num_fields -eq 11 ]
			    then
				accessRegex="NS_PROXY"
			    else
				accessRegex="CERN"
			    fi
			else
			    accessRegex="CERN"
			fi
		    fi

		    errorRegex="CERN_err"
		    serverPath="$dir"
		    serverDesc="Netscape $type Server"
		    http="GET http://$serverName:$serverPort"
		    files="link"

		    _switchAction
		fi
	    done
	done
    done
}

_zeus_extract()
{
    if [ -d $ZEUSPATH ]
    then
	if [ -f $ZEUSPATH/server.ini ]
	then
	    rm -f $tmp.zeus
	    touch $tmp.zeus
	    $PCP_AWK_PROG < $ZEUSPATH/server.ini -v hostname=$LOCALHOSTNAME -v out=$tmp.zeus -v ini=$ZEUSPATH/server.ini -F'=' '
BEGIN				{ mode = 0;
				  port = 0;
				  name = "";
				  access = "???";
				  errors = "???";
				  docs = "???";
				  host = hostname;
				}

/^port/			{ if (mode == 0)
			    port=$2;
			  next 
			}
$1 ~ /\[Admin/		{ mode = 1; next }
$1 ~ /\[Server/		{ if (mode == 2) {
			    printf("%s %s %s %d %s %s\n", name, access, errors, port, host, docs) > out;
			    name=""; access="???"; errors="???"; docs="???";
			    host = hostname
			  }
			  else
			    mode = 2;

			  i = match($1, " .*]");
			  if (i == 0) {
			    mode = 1
			  }
			  else {
			    name = substr($1, RSTART+1, RLENGTH-2);
			  }
			  next
			}
/^logdir/		{ if (mode == 2) {
			    access = sprintf("%s/transfer", $2);
			    errors = sprintf("%s/errors", $2);
			  }
			  next
			}
/^docroot/		{ if (mode == 2)
			    docs = $2; 
			  next
			}
/^ipname/		{ if (mode == 2)
			    host = $2;
			  next
			}
END			{ if (mode == 2)
			    printf("%s %s %s %d %s %s\n", name, access, errors, port, host, docs) > out;
			}'

	    if [ -f $tmp.zeus -a -s $tmp.zeus ]
	    then
	    	accessRegex=CERN
		errorRegex=CERN_err
		serverPath=$ZEUSPATH
		files=link
		lines=`wc -l $tmp.zeus | $PCP_AWK_PROG '{ print $1 }'`
		count=1
		while [ $count -le $lines ]
		do
		    eval `$PCP_AWK_PROG < $tmp.zeus -v line=$count '
NR == line 	{ printf("serverName=%s\naccess=%s\nerrors=%s\nserverPort=%d\nhttp=%s\ndocs=%s\n", $1, $2, $3, $4, $5, $6); exit }'`

		    serverDesc="Zeus Server $serverName"
		    serverName="zeus-$serverName"
		    http="GET http://$http:$serverPort"

		    if [ "X$access" = "X???" ]
		    then
		    	access=$ZEUSPATH/log/transfer
		    	echo "Found $serverDesc at $serverPath"
			echo "${pfx}Warning: unable to determine access log name, assuming:"
			echo "${pfx}	$access"
			echo
		    fi
		    if [ "X$errors" = "X???" ]
		    then
		    	errors=$ZEUSPATH/log/errors
		    	echo "Found $serverDesc at $serverPath"
			echo "${pfx}Warning: unable to determine error log name, assuming:"
			echo "${pfx}	$errors"
			echo
		    fi
		    if [ "X$docs" = "X???" ]
		    then
		    	docs=$ZEUSPATH/docroot
		    	echo "Found $serverDesc at $serverPath"
			echo "${pfx}Warning: unable to determine document root, assuming:"
			echo "${pfx}	$docs"
			echo
		    fi

		    _switchAction
		    count=`expr $count + 1`
		done
	    else
		echo "Found Zeus Server/s at $ZEUSPATH"
	        echo "${pfx}Error: could not detect any servers in configuration file:"
		echo "${pfx}	$ZEUSPATH/server.ini"
		echo "$skipping"
	    fi

	else
	    echo "Found Zeus Server at $ZEUSPATH"
	    echo "${pfx}Error: unable to find configuration file:"
	    echo "${pfx}	$ZEUSPATH/server.ini"
	    echo "$skipping"
	fi
    fi
}

_squid_extract()
{
    if [ -d $SQUIDPATH ]
    then
	if [ -f $SQUIDPATH/etc/squid.conf ]
	then
	    rm -f $tmp.squid
	    touch $tmp.squid
	    $PCP_AWK_PROG < $SQUIDPATH/etc/squid.conf -v hostname=${LOCALHOSTNAME} -v out=$tmp.squid '
BEGIN				{ port = 3128;
				  name = hostname;
				  access = "/usr/local/squid/logs/access.log";
				  errors = "/dev/null";
				  host = hostname;
				}

$1 == "emulate_httpd_log" { if ( $2 == "on" )
				mode = 1;
			  }
$1 == "cache_access_log"  { access = $2;
			  }
$1 == "http_port"         { port = $2;
			  }
$1 == "visible_hostname"  {  name = $2;
			  }
END			  { if (mode == 0)
			        printf("SQUID %s %s %s %d %s\n", name, access, errors, port, host) > out;
			    else
			        printf("CERN %s %s %s %d %s\n", name, access, errors, port, host) > out;
			  }'

	    if [ -f $tmp.squid -a -s $tmp.squid ]
	    then
	        grep CERN $tmp.squid >/dev/null
		if [ $? -eq 0 ]
		then
	    	    accessRegex=CERN
		else
                    accessRegex=SQUID
		fi
		errorRegex=CERN_err
		serverPath=$SQUIDPATH
		files=skip
		eval `$PCP_AWK_PROG < $tmp.squid '
{ printf("serverName=%s\naccess=%s\nerrors=%s\nserverPort=%d\nhttp=%s\n", $2, $3, $4, $5, $6); exit }'`

		    serverDesc="Squid Server $serverName"
		    serverName="squid-$serverName"
		    http="GET http://$http:$serverPort"
    		    docs=$noDocs

		    if [ "X$access" = "X???" ]
		    then
		    	access=$SQUIDPATH/log/transfer
		    	echo "Found $serverDesc at $serverPath"
			echo "${pfx}Warning: unable to determine access log name, assuming:"
			echo "${pfx}	$access"
			echo
		    fi
		    if [ "X$errors" = "X???" ]
		    then
		    	errors=$SQUIDPATH/log/errors
		    	echo "Found $serverDesc at $serverPath"
			echo "${pfx}Warning: unable to determine error log name, assuming:"
			echo "${pfx}	$errors"
			echo
		    fi

		    _switchAction
	    else
		echo "Found Squid Server/s at $SQUIDPATH"
	        echo "${pfx}Error: could not detect any servers in configuration file:"
		echo "${pfx}	$SQUIDPATH/squid.conf"
		echo "$skipping"
	    fi

	else
	    echo "Found Squid Server at $SQUIDPATH"
	    echo "${pfx}Error: unable to find configuration file:"
	    echo "${pfx}	$SQUIDPATH/squid.conf"
	    echo "$skipping"
	fi
    fi
}

_apache_extract()
{
    for apchroot in `echo $APACHEPATH | sed -e 's/:/ /g'`
    do
	$debug && echo "_apache_extract: apachroot=$apchroot"
	config=''
	if [ -f $apchroot/conf/httpd.conf ]
	then
	    config=$apchroot/conf/httpd.conf
	elif [ -f $apchroot/etc/httpd.conf ]
	then
	    config=$apchroot/etc/httpd.conf
	fi

	if [ ! -z "$config" ]
	then
	    $debug && echo "_apache_extract: config=$config"
	    cat $config  \
	    | sed -e's/#.*//' -e'/^$/d' \
	    | $PCP_AWK_PROG -v def=`hostname` '
		BEGIN { 
		    curnam=def;
		    names[def] = curnam;
		    ports[def] = 80;
		}
		$1 == "<VirtualHost" { 
		    sub(">", "", $2); 
		    n = split ($2, nm, ":");
		    if ( n == 1 ) {
			curnam=$2;
			port=ports[def];
		    } else {
			if ( length (nm[1]) ) {
			    curnam = nm[1];
			} else {
			    curnam = def;
			}
			if ( length (nm[2]) ) {
			    port = nm[2];
			} else {
			    port = ports[def];
			}
		    }
		    cn=sprintf("%s:%d", curnam, port);
		    names[cn] = curnam;
		    ports[cn] = port;
		    curnam = cn;
		}
		$1 == "ServerName" { names[curnam] = $2; }
		$1 == "Port" { ports[curnam] = $2; }
		$1 == "</VirtualHost>" { curnam=def; }
		$1 == "ErrorLog" { 
		    if ( match ($2, "/") != 1 ) {
			erlog[curnam] = sprintf ("%s/%s", "'$apchroot'", $2);
		    } else {
			erlog[curnam] = $2;
		    }
		}
		$1 == "TransferLog" {
		    if ( match ($2, "/") != 1 ) {
			tlog[curnam] = sprintf ("%s/%s", "'$apchroot'", $2);
		    } else {
			tlog[curnam] = $2;
		    }
		}
		$1 == "CustomLog" && ($3 == "common" || $3 == "combined") { 
		    if ( match ($2, "/") != 1 ) {
			tlog[curnam] = sprintf ("%s/%s", "'$apchroot'", $2);
		    } else {
			tlog[curnam] = $2;
		    }
		}
		END {
		    for ( n in names ) {
			 print names[n], ports[n], tlog[n], erlog[n]; 
		    }
		}'\
	     | while read serverName serverPort access errors ; do
		$debug && echo "_apache_extract: serverName=$serverName serverPort=$serverPort access=$access errors=$errors"
		if [ "$serverPort" = 443 ]
		then
		    # this is the SSL virtual server ... skip it until
		    # we understand how to find its log files ...
		    #
		    continue
		fi
		accessRegex=CERN
		errorRegex=CERN_err
		serverPath="$apchroot"
		serverDesc="Apache Server"

		docs=""
		for dir in conf etc
		do
		    for conf in srm.conf httpd.conf
		    do
			if [ -f "$apchroot/$dir/$conf" ]
			then
			    # TODO - need to be smarter here, may be many
			    # DocumentRoot control lines in more than one
			    # config file and more than one such line in
			    # each file ... need to understand how Apache
			    # really does this ... for the moment, first
			    # match wins
			    #
			    docs=`grep "^DocumentRoot" $apchroot/$dir/$conf \
			          | sed -e 's/"//g' \
					-e 1q \
				  | $PCP_AWK_PROG '{r=$2}END{print r}'`
			fi
			[ -n "$docs" ] && break
		    done
		done

		if [ -z "$docs" ]
		then
		    docs=$apchroot/htdocs
		    echo "Found $serverDesc at $serverPath"
		    echo "${pfx}Warning: unable to determine document root, assuming:"
		    echo "${pfx}	$docs"
		    echo
		elif [ ! -d $docs ]
		then
		    [ -d $apchroot/$docs ] && docs="$apchroot/$docs"
		fi

		_switchAction
	    done
	fi
    done
}

while [ $# -gt 0 ]
do
    case $1
    in

	-d)	# debug
	    debug=true
	    ;;

	-f) 	# install dummy HTML files in server document root
	    do_files=true
	    if [ $# -gt 1 ]
	    then
		shift
		logFile=$1
	    else
	    	echo "-f requires the name of log file"
		exit 1
	    fi
	    ;;

    	-l)	# generate pmdaweblog configuration file
	    do_logs=true
	    if [ $# -gt 1 ]
	    then
		shift
		logFile=$1
	    else
	    	echo "-l requires the name of log file"
		exit 1
	    fi
	    ;;

        -q)	# do not prompt for misconfigured servers
	    do_auto=true
	    ;;

	-v)	# verbose
	    do_verbose=true
	    ;;

	*)	# USAGE
	    echo "Usage: server.sh [-dqv] [-f logFile] [-l logFile]"
	    exit 1
	    ;;
    esac
    shift
done

if [ "X$do_logs" = "Xtrue" -a "X$do_files" = "Xtrue" ]
then
    echo "May only perform one of the two options at any one time"
    exit 1
fi

if [ "X$do_files" = "Xtrue" ]
then
    if [ ! -f $docsDir/$file1 -o ! -f $docsDir/$file2 -o ! -f $docsDir/$file3 ]
    then
    	echo "Some or all of the sample HTML files ($file1, $file2, $file3)"
	echo "are missing. Cannot continue!"
	exit 1
    fi
fi

_netscape_extract

# Another common place for Netscape servers

if [ -d $OUTBOXPATH ]
then
    access=$OUTBOXPATH/logs/access
    accessRegex="CERN"
    errors=$OUTBOXPATH/logs/errors
    errorRegex="CERN_err"
    serverPath=$OUTBOXPATH
    serverDesc="Outbox Server"
    serverName="outbox-$LOCALHOSTNAME"
    serverPort=
    docs="$OUTBOXPATH/html"
    http="GET http://$LOCALHOSTNAME"
    files="link"
    _switchAction
fi

# Netscape Proxy Server

if [ -d $NSPROXYPATH/logs ]
then
    access=$NSPROXYPATH/logs/access
    accessRegex="CERN"
    errors=$NSPROXYPATH/logs/errors
    errorRegex="CERN_err"
    serverPath=$NSPROXYPATH
    serverDesc="Old Netscape proxy Server"
    serverName="proxy-$LOCALHOSTNAME"
    serverPort=
    docs=$noDocs
    http=""
    files="skip"
    _switchAction
fi

# Netscape SOCKS Proxy Server

if [ -f $NSROOTPATH/proxy-server/logs/sockd ]
then
    access=$NSROOTPATH/proxy-server/logs/sockd
    accessRegex="NS_SOCKS"
    errors=/dev/null
    errorRegex="NS_SOCKS_err"
    serverPath=$NSROOTPATH/proxy-server
    serverDesc="Netscape SOCKS Proxy Server"
    serverName="socks-$LOCALHOSTNAME"
    serverPort=
    docs=$noDocs
    http=""
    files="skip"
    _switchAction

    if [ "$do_logs" = "true" ]
    then
	echo
	$PCP_ECHO_PROG $PCP_ECHO_N "Would you like to log SOCKS ftp transactions [y] ""$PCP_ECHO_C"
	read ans
	if [ "X$ans" = "Xy" -o "X$ans" = "XY" -o "X$ans" = "X" ]
	then
	    access=$NSROOTPATH/proxy-server/logs/sockd
	    accessRegex="NS_FTP"
	    errors=/dev/null
	    errorRegex="NS_FTP_err"
	    serverPath=$NSROOTPATH/proxy-server
	    serverDesc="FTP through Netscape SOCKS Server"
	    serverName="ftp-socks-$LOCALHOSTNAME"
 	    serverPort=
	    docs=$noDocs
	    http=""
	    files="skip"
	    _switchAction
	fi
    fi
fi

if [ -f $NSPROXYPATH/logs/sockd ]
then
    access=$NSPROXYPATH/logs/sockd
    accessRegex="NS_SOCKS"
    errors=/dev/null
    errorRegex="NS_SOCKS_err"
    serverPath=$NSPROXYPATH
    serverDesc="Netscape SOCKS Proxy Server"
    serverName="socks-$LOCALHOSTNAME"
    serverPort=
    docs=$noDocs
    http=""
    files="skip"
    _switchAction

    if [ "$do_logs" = "true" ]
    then
	echo
	$PCP_ECHO_PROG $PCP_ECHO_N "Would you like to log SOCKS ftp transactions [y] ""$PCP_ECHO_C"
	read ans
	if [ "X$ans" = "Xy" -o "X$ans" = "XY" -o "X$ans" = "X" ]
	then
	    access=$NSPROXYPATH/logs/sockd
	    accessRegex="NS_FTP"
	    errors=/dev/null
	    errorRegex="NS_FTP_err"
	    serverPath=$NSPROXYPATH
	    serverDesc="FTP through Netscape SOCKS Server"
	    serverName="ftp-socks-$LOCALHOSTNAME"
	    serverPort=
	    docs=$noDocs
	    http=""
	    files="skip"
	    _switchAction
	fi
    fi
fi

# NCSA (or derived) Server

if [ -d $NCSAPATH/server ]
then
    access=$NCSAPATH/server/logs/access_log
    accessRegex="CERN"
    errors=$NCSAPATH/server/logs/error_log
    errorRegex="CERN_err"
    serverPath=$NCSAPATH/server
    serverDesc="NCSA (or derived) Server"
    serverName="ncsa-$LOCALHOSTNAME"
    serverPort=
    docs="$NCSAPATH/htdocs"
    http="GET http://$LOCALHOSTNAME"
    files="link"
    _switchAction
fi

# Zeus Server

_zeus_extract

# Squid Server

_squid_extract

# Apache Server

_apache_extract

# Oracle Webserver

if [ "X$ORACLE_HOME" != X ]
then
    if [ -d $ORACLE_HOME/ows ]
    then
	serverPath=$ORACLE_HOME/ows
	for i in `ls $serverPath/log/sv*.log*`
	do
	    serverPort=`basename $i | sed 's/sv//' | sed 's/\.log//'`
	    access=$i
	    accessRegex="CERN"
	    errors="$serverPath/ows/log/sv$serverPort.err"
	    errorRegex="CERN_err"
	    serverDesc="Oracle Webserver"
	    serverName="ows-$serverPort"
	    docs="$serverPath/doc"
	    http="GET http://${LOCALHOSTNAME}:$serverPort"
	    files="link"
	    _switchAction
	done
    fi
fi

# Harvest Cache

if [ "X$HARVEST_HOME" != X ]
then
    serverPath=$HARVEST_HOME
    serverPort=80
    access=$serverPath/cache.access.log
    accessRegex="CERN"
    errors="$serverPath/cache.log"
    errorRegex="CERN_err"
    serverDesc="Harvest Cache"
    serverName="harvest-cache"
    docs="$noDocs"
    http=""
    files="skip"
    _switchAction
elif [ -d /usr/local/harvest ]
then
    serverPath=/usr/local/harvest
    serverPort=80
    access=$serverPath/cache.access.log
    accessRegex="CERN"
    errors="$serverPath/cache.log"
    errorRegex="CERN_err"
    serverDesc="Harvest Cache"
    serverName="harvest-cache"
    docs="$noDocs"
    http=""
    files="skip"
    _switchAction
fi

# FTP
if [ -n "$QUIET_INSTALL" ]; then
    ans=y
else
    echo
    if [ "$do_logs" = "true" ]
    then
	$PCP_ECHO_PROG $PCP_ECHO_N "Do you also want to monitor ftp transactions [y] ""$PCP_ECHO_C"
    else
	$PCP_ECHO_PROG $PCP_ECHO_N "Would you like the sample HTML files installed for anonymous ftp [y] ""$PCP_ECHO_C"
    fi
    read ans
fi

if [ "X$ans" = "Xy" -o "X$ans" = "XY" -o "X$ans" = "X" ]
then
    echo
    if [ -f $PASSWDPATH ]
    then
	if [ -n "$QUIET_INSTALL" ] ; then
	    ans=y
	else
	    $PCP_ECHO_PROG $PCP_ECHO_N "Do you want to monitor wu_ftp [n] ""$PCP_ECHO_C"
	    read ans
            echo
	fi
	if [ "X$ans" = "Xy" -o "X$ans" = "XY" ]
	then
	    wulog="$WUFTPLOG"
	    if [ -f "$WUFTPLOG" ]
	    then
		wulog="$WUFTPLOG"
	    elif [ -f "$XFERLOG" ]
	    then
		wulog="$XFERLOG"
	    else
		if $do_auto
		then
		    echo "${pfx}Error: log files are not in the expected place:"
		    echo "$pfx       $XFERLOG"
		    echo "$pfx    or $WUFTPLOG"
		    echo "$skipping"
		    wulog=""
		fi
	    fi

	    access="$wulog"
	    accessRegex="WU_FTP"
	    errors="$SYSLOGPATH"
	    errorRegex="WU_FTP_err"
	    serverDesc="WU_FTP Server"
	    serverName="wu_ftp"
	    serverPath=$FTPPATH
	    serverPort=
	else
	    access=$SYSLOGPATH
	    accessRegex="SYSLOG_FTP"
	    errors=$SYSLOGPATH
	    errorRegex="SYSLOG_FTP_err"
	    serverDesc="FTP Server"
	    serverName="ftpd"
	    serverPath=$FTPPATH
	    serverPort=
	fi

	if [ ! -z "$access" ]
	then
	    docs=""
	    docs=`$PCP_AWK_PROG -F: '$1 == "ftp" { print $6 "/pub"; exit }' < ${PASSWDPATH}`
	    if [ "X$docs" = X ]
	    then
		echo "Found FTP Server at $FTPPATH"
		echo "${pfx}Error: user ftp is not listed in the password file:"
		echo "${pfx}	$PASSWDPATH"
		echo "$skipping"
	    else
		http="GET ftp://$LOCALHOSTNAME/pub"
		files="copy"
		_switchAction
	    fi
	fi
    else
	echo "Found FTP Server at $FTPPATH"
	echo "${pfx}Error: unable to find password file:"
	echo "${pfx}	$PASSWDPATH"
	echo "$skipping"
    fi
fi

if $do_logs
then
    :
else
    [ -f "$logFile" ] && sort -u $logFile -o $logFile
fi
