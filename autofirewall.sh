#!/bin/bash

# TODO: Make sure only critical notifications appear
# TODO : Make it so that this script runs only when I'm connected to the college wifi, check for some unique identifier that
# differentiates the other networks from college's
# TODO: Handle edge cases like wrong passwords, password expire and over limit
# TODO: Try to give a notification when connected to a VPN (can consider that as connected to a non college network)

# URL for the captive portal login page
LOGIN_URL="http://172.15.15.1:1000/login?0263b3a631633500"

# Credentials
USERNAME="Username"
PASSWORD="Password"

# Log file
LOG_FILE="$HOME/autofirewall.log"

# Function to log and send notifications
log_and_notify() {
	local message="$1"
	local urgency="$2" # urgency for notifications (low, normal, critical)

	# Log the message to the log file
	echo "$(date): $message" >>"$LOG_FILE"

	# Send notification using notify-send
	notify-send -u "$urgency" "AutoFirewall" "$message"
}

do_login_and_get_keepalive() {
	# Log startup
	log_and_notify "Starting AutoFirewall script..." "normal"

	# 1. Get the Captive Portal page and extract 'magic' token from the response
	MAGIC=$(curl -s "$LOGIN_URL" --insecure | grep -oP 'name="magic" value="\K[^"]+')

	# Check if we got the magic token
	if [ -z "$MAGIC" ]; then
		log_and_notify "Error: Could not retrieve 'magic' token. Captive portal might be down." "critical"
		exit 1
	fi

	log_and_notify "Magic token retrieved: $MAGIC" "normal"

	# 2. Perform the login by sending the POST request with username, password, and magic token
	LOGIN_RESPONSE=$(curl -i -s -X POST "http://172.15.15.1:1000/" \
		-H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8' \
		-H 'Content-Type: application/x-www-form-urlencoded' \
		-H 'Origin: http://172.15.15.1:1000' \
		-H "Referer: $LOGIN_URL" \
		-H 'Connection: keep-alive' \
		--data-urlencode "4Tredir=$LOGIN_URL" \
		--data-urlencode "magic=$MAGIC" \
		--data-urlencode "username=$USERNAME" \
		--data-urlencode "password=$PASSWORD" \
		--insecure)

	# 3. Extract the Location header from the login response (which contains the keepalive URL)
	KEEPALIVE_URL=$(echo "$LOGIN_RESPONSE" | grep -oP 'Location: \K[^ ]+')

	if [ -z "$KEEPALIVE_URL" ]; then
		log_and_notify "Error: Could not retrieve keepalive URL. Login might have failed." "critical"
		exit 1
	fi

	CLEANED_URL=$(echo "$KEEPALIVE_URL" | tr -d '\r\n' | tr -d '\n')
	echo -e $CLEANED_URL

	log_and_notify "Keepalive URL retrieved: $CLEANED_URL" "normal"

}

CLEANED_URL=$(do_login_and_get_keepalive)

# 4. (Optional) Keep the session alive by periodically sending keepalive requests
while true; do
	# Capture the HTTP status code
	HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}\n" $CLEANED_URL)

	# Log the curl output for debugging

	# Log the HTTP status code
	echo "$(date): HTTP Status Code: $HTTP_STATUS" >>"$LOG_FILE"

	# Check the HTTP status code and decide if it's an error
	if [[ $HTTP_STATUS -ge 200 && $HTTP_STATUS -lt 400 ]]; then
		# Success: status code 2xx or 3xx
		log_and_notify "Session kept alive successfully with HTTP status code $HTTP_STATUS. Waiting for 5 minutes before the next keepalive request..." "normal"
	else
		# Failure: status code 4xx or 5xx
		log_and_notify "Error: Failed to send keepalive request. HTTP status code: $HTTP_STATUS. Check your network connection." "critical"

		CLEANED_URL=$(do_login_and_get_keepalive)
	fi

	# Sleep for 5 minutes (300 seconds)
	sleep 300
done
