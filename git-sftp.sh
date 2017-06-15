#!/usr/bin/env bash
#
# Copyright 2010-2017 Cloud Lu
#
# This is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# options
OPTIONS_SPEC="
-g,--git_address  	[Required]	Set git remote address
-n,--git_username	[Optional]	Set git username
-m,--git_password	[Optional]	Set git password
-s,--ssh_address	[Required]	Set ssh address
-u,--ssh_username	[Optional]	Set ssh username, default as root
-p,--ssh_password	[Optional]	Set ssh password
-p,--remote_path 	[Optional]	Set which path the compress file should be placed
-h,--help,-?  		Show helps
"

# config file path
CONFIG_FILE='git-sftp.conf'

# help function
usage(){
   echo "Usage: $0 OPTIONS"
   echo	
   echo "Command line options:"
   printf "${OPTIONS_SPEC}"
   echo
   echo "Example: "
   echo -e "\t $0 --git_address https://git.oschina.net/supergk/xcpe.git --git_username=livecn@163.com --git_password=12345678 --ssh_address=127.0.0.1 --ssh_username=root --ssh_password=12345678 --remote_path=/tmp"
   echo
   exit 
}

rawurlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"    # You can either set a return variable (FASTER) 
  REPLY="${encoded}"   #+or echo the result (EASIER)... or both... :p
}


echo " ******************** Load config ******************** "

if [ -e $CONFIG_FILE ]
then
	while read line
	do
		if [[ ${line:0:1} != '#' ]]
		then
			if echo $line | grep -F = &>/dev/null 
			then
				declare $(echo "$line" | cut -d '=' -f 1)=$(echo "$line" | cut -d '=' -f 2-)
			fi
		fi
	done < $CONFIG_FILE
	echo $CONFIG_FILE" is already loaded！ "
else
	echo $CONFIG_FILE" doesn't exists！ "
fi


# set variable from shell params
while test $# != 0
do
   case "$1" in

   -g=*|--git_address=*)
      git_address=${1#*=} ;;
   -g|--git_address)
      shift
      git_address=$1 ;;

   -n=*|--git_username=*)
      git_username=${1#*=} ;;
   -n|--git_username)
      shift
      git_username=$1 ;;

   -m=*|--git_password=*)
      git_password=${1#*=} ;;
   -m|--git_password)
      shift
      git_password=$1 ;;

   -s=*|--ssh_address=*)
      ssh_address=${1#*=} ;;
   -s|--ssh_address)
      shift
      ssh_address=$1 ;;

   -p=*|--remote_path=*)
      remote_path=${1#*=} ;;
   -p|--remote_path)
      shift
      remote_path=$1 ;;

   -u=*|--ssh_username=*)
      ssh_username=${1#*=} ;;
   -u|--ssh_username)
      shift
      ssh_username=$1 ;;

   -p=*|--ssh_password=*)
      ssh_password=${1#*=} ;;
   -p|--ssh_password)
      shift
      ssh_password=$1 ;;

   -h|--help|-?)
      usage ;;
   --)
      shift ;;
   *)
   esac
   shift
done


echo ""
echo " ******************** Starting ******************** "

while [ "$git_address" == "" ]; do
	read -p "Please input git address ! " git_address
done;

if [ "$git_username" == "" ]
then
	read -p "Please input git username ! [empty] " git_username
fi

if [ "$git_password" == "" ]
then
	read -s -p "Please input git password ! [empty] " git_password
fi

domian_path=${git_address#https://}

if [[ "$git_username" != "" && "$git_password" != "" ]]
then
	#git_username=${git_username/@/%40}
	git_username=$( rawurlencode $git_username )
	git_password=$( rawurlencode $git_password )
	git_address="https://"$git_username":"$git_password"@"$domian_path
elif [[ "$git_username" != "" ]]
then
	git_username=$( rawurlencode $git_username )
	git_address="https://"$git_username"@"$domian_path
fi

git_name=${git_address##*/}
dir_name=${git_name%%.*}

cd /tmp

tmpdir=`mktemp -d XXXXXXXX`

tar_file="$tmpdir.tar.gz"

echo ""
echo " ******************** Clone file into tmp directory ******************** "

git clone $git_address $tmpdir

if [ $? != 0 ]
then
	echo "Git clone project failed ! "
	exit 1
fi

tar -zcvf $tar_file $tmpdir

while [ "$ssh_address" == "" ]; do
	read -p "Please input ssh address ! " ssh_address
done;

if [ "$remote_path" == "" ]
then
	read -p "Please input which path the compress file should be placed ? [/tmp] " remote_path
fi

[[ "$remote_path" ]] || remote_path="/tmp"

if [ "$ssh_username" == "" ]
then
	read -p "Please input ssh username ! [root] " ssh_username
fi

[[ "$ssh_username" ]] || ssh_username="root"

while [ "$ssh_password" == "" ]; do
	read -s -p "Please input ssh password ! " ssh_password
done;

echo ""
echo " ******************** Upload to server by ssh Job ******************** "

/usr/bin/expect <<-EOF
	set timeout 12
	spawn scp $tar_file $ssh_username@$ssh_address:$remote_path
	expect {
		"yes/no" { send "yes\n"; exp_continue}
		"*password:" { send "$ssh_password\n" }
	}
	expect eof
	catch wait result
	exit [lindex \$result 3]
EOF

if [ $? != 0 ]
then
	echo ""
	echo "Upload compressed file to server failed!"
	exit
fi


echo ""
echo " ******************** Uncompress and move files Job ******************** "

declare remote_tmpdir=${dir_name}"."$RANDOM;

/usr/bin/expect <<-EOF
	set timeout 5
	spawn ssh $ssh_username@$ssh_address
	expect {
		"yes/no" { send "yes\n"; exp_continue}
		"password:" { send "$ssh_password\n" }
	}
	expect "]# "
	send "sleep 1 \n"
	send "cd $remote_path \n"
	send "test -d $dir_name && {
								echo '${dir_name} directory is not empty';
								mkdir ${remote_tmpdir};
								tar -zxvf $tar_file;
								mv $tmpdir/* ${remote_tmpdir};
								echo '';
								echo 'Uncompress file in ${remote_tmpdir} directory';
								echo ''; 
							} || { 
								mkdir $dir_name; 
								tar -zxvf $tar_file;
								mv $tmpdir/* $dir_name;
								echo '';
								echo 'Uncompress file in ${dir_name} directory';
								echo '';
							} \n"
	send "rm -rf $tmpdir \n"
	send "rm -rf $tar_file \n"
	expect eof
EOF

echo ""
echo " ******************** Delete tmp files ******************** "

rm -rf $tar_file
rm -rf $tmpdir

echo ""
echo " ******************** Finished ******************** "

exit 0


