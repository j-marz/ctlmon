# CTLMON
Certificate Transparency Log Monitor

Search online Certificate Transparency Log service (http://crt.sh) for certificates issued to your domains.
Store certificate info in JSON documents for historical records and alert on changes or newly issued certificates via email.

## Dependencies
* mail
* curl
* jq
* logger
* diff
* local SMTP server (e.g. sendmail or postfix)

Install all dependencies on Ubuntu using `sudo apt-get install mailutils curl diffutils jq sendmail`

## Usage
1. Populate configuration in `ctlmon.conf`
2. Populate domains in `domains.txt`
2. Run `./ctlmon.sh`

## Automate
Add the following cron job using `crontab -e` to run the script automatically at 9:00AM every day
`0 9 * * * ./ctlmon.sh > /dev/null`