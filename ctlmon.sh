#!/bin/bash

#################################################
# CTLMON - Certificate Transparency Log Monitor #
#################################################

# Created by: John Marzella
# https://github.com/j-marz/ctlmon

# Search online Certificate Transparency Log service (http://crt.sh) for certificates issued to your domains
# Store certificate info in JSON document for historical records and alert on changes or newly issued certificates 

# Script logs to /var/log/syslog
# Changes to CTL logged in the respective domain directory

# terminate script on any errors
set -e

# static variables
config="ctlmon.conf"
dependencies=(mail curl jq logger diff)
domains="domains.txt"
script_name="ctlmon.sh"
syslog="/var/log/syslog"
timestamp="$(date '+%Y_%m_%d__%H_%M_%S')"
banner="CTLMON v0.1 - https://github.com/j-marz/ctlmon"

# import main configuration
source $config

# syslog function
function log {
	logger -t "CTLMON" "$1"
}

# check for dependencies
function dependency_check {
	log "checking dependencies"
	for dependency in "${dependencies[@]}"
		do
			if [ ! -x "$(command -v $dependency)" ]; then
		    	log "$dependency dependency does not exist - please install using 'apt-get install $dependency'"
		    	abort
			fi
		done
	log "dependency check completed succesfully"
}

# check if file exists
function file_check {
	log "checking files"
	if [ ! -f "$1" ]; then
		log "$1 not found - please create"
		abort
	fi
	log "file checks completed successfully"
}

# check if directory structure exists for the domain
function dir_check {
	if [ -d "results/$1" ]; then
	log "results/$1 directory found"
	echo "results/$1 directory found"
		if [ -d "results/$1/archive" ]; then
			log "results/$1/archive found"
			echo "results/$1/archive found"
		else
			log "results/$1/archive not found - this is required for certificate history"
			echo "results/$1/archive not found - this is required for certificate history"
			mkdir -p "results/$1/archive/"
			log "results/$1/archive/ created"
			echo "results/$1/archive/ created"
		fi
	else
		log "results/$1 directory not found - must be new domain or first run"
		echo "results/$1 directory not found - must be new domain or first run"
		mkdir -p "results/$1"
		log "results/$1 directory created"
		echo "results/$1 directory created"
		mkdir -p "results/$1/archive/"
		echo "results/$1/archive directory created"
	fi
}

# check HTTP response code from cURL
function check_rsp {
	if [ $1 -eq 200 ]; then
		log "http status code: $1 - certificates found for $domain"
		echo "http status code: $1 - certificates found for $domain"
	elif [ $1 -eq 404 ]; then
		log "http status code: $1 - no certificates found for $domain"
		echo "http status code: $1 - no certificates found for $domain"
		# should add retry here incase server error
		loop_control="continue"
	else 
		log "http status code: $1 - unknown response"
		echo "http status code: $1 - unknown response"
		# should add retry here incase server error
		loop_control="continue"
	fi
}

# check if results already exist and compare the differences
function process_results {
	# set file path variables
	existing_file="results/$domain/$domain.json"
	archive_file="results/$domain/archive/$domain_$timestamp.json"
	changelog="results/$domain/changelog.txt"
	if [ -f "$existing_file" ]; then
		log "previous results for $1 found - comparing sha256 hash"
		echo "previous results for $1 found - comparing sha256 hash"
		# calc sha256sum of crt.sh results
		new_hash="$(sha256sum $crtsh_results | awk -F "  " '{print $1}')"
		old_hash="$(sha256sum $existing_file | awk -F "  " '{print $1}')"
		if [ "$new_hash" = "$old_hash" ]; then
			log "results are identical for $domain - no new certificates found"
			echo "results are identical for $domain - no new certificates found"
			log "skipping remaining checks for $domain"
			echo "skipping remaining checks for $domain"
			loop_control="continue"
		else
			log "results are different for $domain - analysing new data"
			echo "results are different for $domain - analysing new data"
			cert_names="$(grep '^{' $crtsh_results | jq '.name_value' | awk -F '"' '{print $2}')"
			old_cert_names="$(grep '^{' $existing_file | jq '.name_value' | awk -F '"' '{print $2}')"
			diff_cert_names="$(diff $old_cert_names $cert_names | grep '>' | awk -F '> ' '{print $2}')"	#### needs to be reviewed
			new_cert_count="$(echo "$diff_cert_names" | wc -l)"
			log "$new_cert_count new certificates found for $domain"
			echo "$new_cert_count new certificates found for $domain"
			echo "$(date)" >> $changelog
			echo "------------------------------------" >> $changelog
			echo "$new_cert_count new certificates found for $domain" >> $changelog
			echo "$diff_cert_names" >> $changelog
			echo "" >> $changelog
			mv "$existing_file" "$archive_file"
			log "$existing_file moved to to $archive_file"
			mv "$crtsh_results" "$existing_file"
			log "$crtsh_results moved to $existing_file"
		fi
	else
		log "previous results for $1 not found - this is the first detection for $domain domain"
		echo "previous results for $1 not found - this is the first detection for $domain domain"
		cert_names="$(grep '^{' $crtsh_results | jq '.name_value' | awk -F '"' '{print $2}')"
		new_cert_count="$(echo "$cert_names" | wc -l)"
		log "$new_cert_count new certificates found for $domain"
		echo "$new_cert_count new certificates found for $domain"
		echo "$(date)" >> $changelog
		echo "------------------------------------" >> $changelog
		echo "$new_cert_count new certificates found for $domain" >> $changelog
		echo "$cert_names" >> $changelog
		echo "" >> $changelog
		mv "$crtsh_results" "$existing_file"
		log "$crtsh_results moved to $existing_file"
	fi
}

function abort {
	echo "something went wrong..."
	echo "please review $syslog"
	echo "script will abort in 5 seconds"
	sleep 5
	log "aborting $script_name script due to errors"
	exit
}

function finish {
	echo "$script_name has finished"
	log "$script_name finished"
	exit
}

# send email function
function send_email {
	# check email addresses in config
	if [ -z $recipient_email ]; then
		log "Recipient email missing from config - email notification will be skipped"
		echo "Recipient email missing from config - email notification will be skipped"
		loop_control="continue"
	elif [ -z $sender_email ]; then
		log "Sender email missing from config - email notification will be skipped"
		echo "Sender email missing from config - email notification will be skipped"
		loop_control="continue"
	else
		#### TO DO #### need to add options for SMTP auth, SMTP server and SMTP port
		email_subject="CTLMON alert for $domain domain"
		email_body="New certificates issued for $domain domain detected! \nReview the list of certificates below: \n\n$cert_names"
		# send the email
		echo -e "$email_body" | mail -s "$email_subject" \
			$recipient_email \
			-a From:$sender_email \
			-a X-Application:"$banner" \
			-a Content-Type:"text/plain"
		# log
		log "email sent to $recipient_email"
		echo "email sent to $recipient_email"
	fi
}

# ---------- script ----------

# start logging
log "$script_name started"

# check dependencies
dependency_check

# config file check
file_check "$config"
file_check "$domains"

# main loop
while read domain; do
	log "Domain: $domain"
	echo "Domain: $domain"
	# check if domain dir exists
	dir_check "$domain"
	log "Searching CTL for: $domain"
	echo "Searching CTL for: $domain"
	# avoid rate limiting with crt.sh - sleep for 1 second
	sleep 1
	# search for certs
	crtsh_results="/tmp/$domain.json"
	curl -w '\n%{http_code}\n' "https://crt.sh/?q=%.$domain&output=json" > $crtsh_results	# add newlines to separate status code from json response
	# check http status code
	declare -i crtsh_status	# only allow integer for http status code
	crtsh_status="$(tail -n 1 $crtsh_results)" # last line contains http_code from cURL
	check_rsp $crtsh_status
	# loop control for functions
		if [[ $loop_control = "continue" ]]; then
			# clear variable
			loop_control=""
			continue
		fi
	# analyse the crt.sh json and process files
	process_results
	# loop control for functions
		if [[ $loop_control = "continue" ]]; then
			# clear variable
			loop_control=""
			continue
		fi
	# send email notification
	send_email
	# loop control for functions
		if [[ $loop_control = "continue" ]]; then
			# clear variable
			loop_control=""
			continue
		fi
done < $domains

# done
finish