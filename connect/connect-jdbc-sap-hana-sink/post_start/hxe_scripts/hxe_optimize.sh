#!/bin/bash 

#
# This script must be run under "<SID>adm" login.
#


#
# Get SID from current user login <sid>adm
#
getSID() {
	HXE_ADM=`whoami`
	if echo $HXE_ADM | grep 'adm$' > /dev/null; then
		HXE_SID=`echo $HXE_ADM | cut -c1-3 | tr '[:lower:]' '[:upper:]'`
		if [ ! -d /hana/shared/${HXE_SID} ]; then
			echo "You login as \"$HXE_ADM\"; but /hana/shared/${HXE_SID} does not exist."
			exit 1
		fi
	else
		echo "You need to run this from \"<sid>adm\" login."
		exit 1
        fi
}


#
# Check if executables in path
#
checkEnv() {
	if ! which HDB >& /dev/null; then
		echo "Cannot find \"HDB\" executable in path.  Check if HANA is correctly installed."
		exit 1
	fi

	if ! which hdbsql >& /dev/null; then
		echo "Cannot find \"hdbsql\" executable in path.  Check if HANA is correctly installed."
		exit 1
	fi
}

#
# Check what servers are installed and running
#
checkServer() {
	local hdbinfo_output=$(HDB info)
	if echo ${hdbinfo_output} | grep hdbnameserver >& /dev/null; then
		HAS_SERVER=1
		if echo ${hdbinfo_output} | grep "/hana/shared/${HXE_SID}/xs/router" >& /dev/null; then
			HAS_XSA=1
		fi
	else
		echo
		echo "Cannot find running HANA server.  Please start HANA with \"HDB start\" command."
		exit 1
	fi
}

#
# Check if this XSC image
#
checkXSC() {
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM _SYS_REPO.DELIVERY_UNITS"
	SQL_OUTPUT=`trim ${SQL_OUTPUT}`
	if [ $SQL_OUTPUT -gt 0 -a $HAS_XSA -ne 1 ]; then
		HAS_XSC=1
	fi
}

#
# Check if tenant database exits
hasDatabase() {
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) from \"PUBLIC\".\"M_DATABASES\" WHERE DATABASE_NAME='${1}'"
	SQL_OUTPUT=`trim ${SQL_OUTPUT}`
	if [ "${SQL_OUTPUT}" == "1" ]; then
		return 0
	fi

	return 1
}

#
# Prompt instance number
#
promptInstanceNumber() {
	if [ -n "$HANA_INSTANCE" ] && [ -d /hana/shared/${HXE_SID}/HDB${HANA_INSTANCE} ] ; then
		return
	fi

	local num=""
	if [ ! -d "/hana/shared/${HXE_SID}/HDB${HANA_INSTANCE}" ]; then
		HANA_INSTANCE=""
		for i in /hana/shared/${HXE_SID}/HDB?? ; do
			num=`echo "$i" | cut -c21-22`
			if [[ ${num} =~ ^[0-9]+$ ]] ; then
				HANA_INSTANCE="$num"
				break
			fi
		done
	fi

	while [ 1 ]; do
		read -p "Enter HANA instance number [${HANA_INSTANCE}]: " num

		if [ -z "${num}" ]; then
			if [ -z "${HANA_INSTANCE}" ]; then
				continue
			else
				num="${HANA_INSTANCE}"
			fi
		fi

		if ! [[ ${num} =~ ^[0-9]+$ ]] ; then
			echo
			echo "\"$num\" is not a number.  Enter a number between 00 and 99."
			echo
			continue
		elif [ ${num} -ge 0 -a ${num} -le 99 ]; then
			if [[ ${num} =~ ^[0-9]$ ]] ; then
				num="0${num}"
			fi

			if [ ! -d "/hana/shared/${HXE_SID}/HDB${num}" ]; then
				echo
				echo "Instance ${num} does not exist in SID \"$HXE_SID\" (/hana/shared/${HXE_SID}/HDB${num})."
				echo
				continue
			else
				HANA_INSTANCE="${num}"
				break
			fi
		else
			echo
			echo "Invalid number.  Enter a number between 00 and 99."
			echo
			continue
		fi
	done
}


# Prompt user password
# arg 1: user name
# arg 2: variable name to store password value
#
promptPwd() {
	local pwd=""
	while [ 1 ]; do
		read -r -s -p "Enter ${1} password : " pwd
		if [ -z "$pwd" ]; then
			echo
			echo "Invalid empty password. Please re-enter."
			echo
		else
			break
		fi
	done

	echo
	eval $2=\$pwd

	echo
}


#
# Prompt new user password
# arg 1: user name
# arg 2: variable name to store password value
#
promptNewPwd() {
	local msg=""
	local showPolicy=0
	local pwd=""
	local confirm_pwd=""
	echo
	echo "Password must be at least 8 characters in length.  It must contain at least"
	echo "1 uppercase letter, 1 lowercase letter, and 1 number.  Special characters"
	echo "are allowed, except \\ (backslash), ' (single quote), \" (double quotes),"
	echo "\` (backtick), and \$ (dollar sign)."
	echo
	while [ 1 ] ; do
		read -r -s -p "Enter new password for \"${1}\": " pwd
		echo

		if [ `echo "${pwd}" | wc -c` -le 8 ]; then
			msg="too short"
			showPolicy=1
		fi
		if ! echo "${pwd}" | grep "[A-Z]" >& /dev/null; then
			if [ -z "$msg" ]; then
				msg="missing uppercase letter"
			else
				msg="$msg, missing uppercase letter"
			fi
			showPolicy=1
		fi
		if ! echo "${pwd}" | grep "[a-z]" >& /dev/null; then
			if [ -z "$msg" ]; then
				msg="missing lowercase letter"
			else
				msg="$msg, missing lowercase letter"
			fi
			showPolicy=1
		fi
		if ! echo "${pwd}" | grep "[0-9]" >& /dev/null; then
			if [ -z "$msg" ]; then
				msg="missing a number"
			else
				msg="$msg, missing a number"
			fi
			showPolicy=1
		fi
		if echo "$pwd" | grep -F '\' >& /dev/null; then
			if [ -z "$msg" ]; then
				msg="\\ (backslash) not allowed"
			else
				msg="$msg, \\ (backslash) not allowed"
			fi
			showPolicy=1
		fi
		if echo "$pwd" | grep -F "'" >& /dev/null; then
			if [ -z "$msg" ]; then
				msg="' (single quote) not allowed"
			else
				msg="$msg, ' (single quote) not allowed"
			fi
			showPolicy=1
		fi
		if echo "$pwd" | grep -F '"' >& /dev/null; then
			if [ -z "$msg" ]; then
				msg="\" (double quotes) not allowed"
			else
				msg="$msg, \" (double quotes) not allowed"
			fi
			showPolicy=1
		fi
		if echo "$pwd" | grep -F '`' >& /dev/null; then
			if [ -z "$msg" ]; then
				msg="\` (backtick) not allowed"
			else
				msg="$msg, \` (backtick) not allowed"
			fi
			showPolicy=1
		fi
		if echo "$pwd" | grep -F '$' >& /dev/null; then
			if [ -z "$msg" ]; then
				msg="\$ (dollar sign) not allowed"
			else
				msg="$msg, \$ (dollar sign) not allowed"
			fi
			showPolicy=1
		fi
		if [ $showPolicy -eq 1 ]; then
			echo
			echo "Invalid password: ${msg}." | fold -w 80 -s
			echo
			echo "Password must meet all of the following criteria:"
			echo "- 8 or more letters"
			echo "- At least 1 uppercase letter"
			echo "- At least 1 lowercase letter"
			echo "- At least 1 number"
			echo
			echo "Special characters are optional; except \\ (backslash), ' (single quote),"
			echo "\" (double quotes), \` (backtick), and \$ (dollar sign)."
			echo
			msg=""
			showPolicy=0
			continue
		fi

		read -r -s -p "Enter new confirm password for \"${1}\": " confirm_pwd
		echo
		if [ "${pwd}" != "${confirm_pwd}" ]; then
			echo
			echo "Passwords do not match."
			echo
			continue
		fi

		eval $2=\$pwd

		break;
	done
}

#
# Prompt proxy host and port
#
promptProxyInfo() {
	if [ $SETUP_PROXY -eq 1 -a -n "$PROXY_HOST" -a -n "$PROXY_PORT" ]; then
		return
	fi

	getSystemHTTPProxy

	local prompt_msg="Do you need to use proxy server to access the internet? [N] : "
	if [ -n "$SYSTEM_PROXY_HOST" ]; then
		prompt_msg="Do you need to use proxy server to access the internet? [Y] : "
	fi
	while [ 1 ] ; do
		read -p "$prompt_msg" tmp
		if [ "$tmp" == "Y" -o "$tmp" == "y" ] || [ -z "$tmp" -a -n "$SYSTEM_PROXY_HOST" ]; then
			SETUP_PROXY=1
			break
		elif [ "$tmp" == "N" -o "$tmp" == "n" ] || [ -z "$tmp" -a -z "$SYSTEM_PROXY_HOST" ]; then
			SETUP_PROXY=0
			return
		else
			echo "Invalid input.  Enter \"Y\" or \"N\"."
		fi
	done

	# Proxy host
	while [ 1 ]; do
		read -p "Enter proxy host name [$SYSTEM_PROXY_HOST]: " tmp
		if [ -z "$tmp" ]; then
			if [ -n "$SYSTEM_PROXY_HOST" ]; then
				tmp="$SYSTEM_PROXY_HOST"
			else
				continue
			fi
		fi
		if ! $(isValidHostName "$tmp"); then
			echo
			echo "\"$tmp\" is not a valid host name or IP address."
			echo
		else
			PROXY_HOST="$tmp"
			break
		fi
	done

	# Proxy port
	while [ 1 ]; do
		read -p "Enter proxy port number [$SYSTEM_PROXY_PORT]: " tmp
		if [ -z "$tmp" ]; then
			if [ -n "$SYSTEM_PROXY_PORT" ]; then
				tmp="$SYSTEM_PROXY_PORT"
			else
				continue
			fi
		fi
		if ! $(isValidPort "$tmp"); then
			echo
			echo "\"$tmp\" is not a valid port number."
			echo "Enter number between 1 and 65535."
			echo
		else
			PROXY_PORT="$tmp"
			break
		fi
	done

	# No proxy hosts
	read -p "Enter comma separated domains that do not need proxy [$SYSTEM_NO_PROXY_HOST]: " tmp
	if [ -z "$tmp" ]; then
		NO_PROXY_HOST="$SYSTEM_NO_PROXY_HOST"
	else
		NO_PROXY_HOST="$tmp"
		NO_PROXY_HOST="$(addLocalHostToNoProxy "$NO_PROXY_HOST")"
	fi
}

#
formatNoProxyHost() {
	if [ -z "$1" ]; then
		return
	fi

	local no_ph=""
	IFS=',' read -ra hlist <<< "$1"
	for i in "${hlist[@]}"; do
		tmp=$(trim "$i")
		if [ -n "${tmp}" ]; then
			if [[ "${tmp}" =~ ^[0-9]+\. ]] || [[ "${tmp}" =~ [Ll][Oo][Cc][Aa][Ll][Hh][Oo][Ss][Tt] ]]; then
				no_ph="${no_ph}|${tmp}"
			elif echo ${tmp} | grep -i "^${HOST_NAME}$" >& /dev/null; then
				no_ph="${no_ph}|${tmp}"
			elif echo ${tmp} | grep -i "^${HOST_NAME}\.?*" >& /dev/null; then
				no_ph="${no_ph}|${tmp}"
			elif [[ "${tmp}" =~ ^\. ]]; then
				no_ph="${no_ph}|*${tmp}"
			else
				no_ph="${no_ph}|*.${tmp}"
			fi
		fi
	done
	echo ${no_ph} | sed 's/^|//'
}

#
# Get the system proxy host and port
#
getSystemHTTPProxy() {
	local url="$https_proxy"
	local is_https_port=1

	if [ -z "$url" ]; then
		url="$http_proxy"
		is_https_port=0
	fi
	if [ -z "$url" ] && [ -f /etc/sysconfig/proxy ]; then
		url=`grep ^HTTPS_PROXY /etc/sysconfig/proxy | cut -d'=' -f2`
		is_https_port=1
	fi
	if [ -z "$url" ] && [ -f /etc/sysconfig/proxy ]; then
		url=`grep ^HTTP_PROXY /etc/sysconfig/proxy | cut -d'=' -f2`
		is_https_port=0
	fi

	url="${url%\"}"
	url="${url#\"}"
	url="${url%\'}"
        url="${url#\'}"

	if [ -z "$url" ]; then
		SETUP_PROXY=0
		return
	fi

	# Get proxy host
	SYSTEM_PROXY_HOST=$url
	if echo $url | grep -i '^http' >& /dev/null; then
		SYSTEM_PROXY_HOST=`echo $url | cut -d '/' -f3 | cut -d':' -f1`
	else
		SYSTEM_PROXY_HOST=`echo $url | cut -d '/' -f1 | cut -d':' -f1`
	fi

	if [ -n "${SYSTEM_PROXY_HOST}" ]; then
		SETUP_PROXY=1
	fi

	# Get proxy port
	if echo $url | grep -i '^http' >& /dev/null; then
		if echo $url | cut -d '/' -f3 | grep ':' >& /dev/null; then
			SYSTEM_PROXY_PORT=`echo $url | cut -d '/' -f3 | cut -d':' -f2`
		elif [ $is_https_port -eq 1 ]; then
			SYSTEM_PROXY_PORT="443"
		else
			SYSTEM_PROXY_PORT="80"
		fi
	else
		if echo $url | cut -d '/' -f1 | grep ':' >& /dev/null; then
			SYSTEM_PROXY_PORT=`echo $url | cut -d '/' -f1 | cut -d':' -f2`
		elif [ $is_https_port -eq 1 ]; then
			SYSTEM_PROXY_PORT="443"
		else
			SYSTEM_PROXY_PORT="80"
		fi
        fi

	# Get no proxy hosts
	SYSTEM_NO_PROXY_HOST="$no_proxy"
	if [ -z "$SYSTEM_NO_PROXY_HOST" ] && [ -f /etc/sysconfig/proxy ]; then
		SYSTEM_NO_PROXY_HOST=`grep ^NO_PROXY /etc/sysconfig/proxy | cut -d'=' -f2`
		SYSTEM_NO_PROXY_HOST="${SYSTEM_NO_PROXY_HOST%\"}"
		SYSTEM_NO_PROXY_HOST="${SYSTEM_NO_PROXY_HOST#\"}"
		SYSTEM_NO_PROXY_HOST="${SYSTEM_NO_PROXY_HOST%\'}"
		SYSTEM_NO_PROXY_HOST="${SYSTEM_NO_PROXY_HOST#\'}"
	fi
	if [ -z "$SYSTEM_NO_PROXY_HOST" ] && [ -f /etc/sysconfig/proxy ]; then
		SYSTEM_NO_PROXY_HOST=`grep ^no_proxy /etc/sysconfig/proxy | cut -d'=' -f2`
		SYSTEM_NO_PROXY_HOST="${SYSTEM_NO_PROXY_HOST%\"}"
		SYSTEM_NO_PROXY_HOST="${SYSTEM_NO_PROXY_HOST#\"}"
		SYSTEM_NO_PROXY_HOST="${SYSTEM_NO_PROXY_HOST%\'}"
		SYSTEM_NO_PROXY_HOST="${SYSTEM_NO_PROXY_HOST#\'}"
	fi
	if [[ -n "$SYSTEM_NO_PROXY_HOST" ]]; then
		SYSTEM_NO_PROXY_HOST="$(addLocalHostToNoProxy "$SYSTEM_NO_PROXY_HOST")"
	fi
}

addLocalHostToNoProxy() {
	if [ -z "$1" ]; then
		return
	fi

	local no_ph=$1
	local has_localhost=0
	local has_localhost_name=0
	local has_localhost_ip=0

	IFS=',' read -ra hlist <<< "$no_ph"
	for i in "${hlist[@]}"; do
		tmp=$(trim "$i")
		if [ -n "${tmp}" ]; then
			if [[ "${tmp}" =~ [Ll][Oo][Cc][Aa][Ll][Hh][Oo][Ss][Tt] ]]; then
				has_localhost=1
			elif echo ${tmp} | grep -i "^${HOST_NAME}$" >& /dev/null; then
				has_localhost_name=1
			elif [[ "$tmp" == "127.0.0.1" ]]; then
				has_localhost_ip=1
			fi
		fi
	done

	if [ $has_localhost_ip -eq 0 ]; then
		no_ph="127.0.0.1, ${no_ph}"
	fi
	if [ $has_localhost_name -eq 0 ]; then
		no_ph="${HOST_NAME}, ${no_ph}"
	fi
	if [ $has_localhost -eq 0 ]; then
		no_ph="localhost, ${no_ph}"
	fi

	echo ${no_ph}
}

isValidHostName() {
	local hostname_regex='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
	echo "$1" | egrep $hostname_regex >& /dev/null
}


isValidPort() {
	if [[ $1 =~ ^[0-9]?+$ ]]; then
		if [ $1 -ge 1 ] && [ $1 -le 65535 ]; then
			return 0
		else
			return 1
		fi
	else
		return 1
	fi
}


#
# Execute SQL statement and store output to SQL_OUTPUT
# $1 - instance #
# $2 - database
# $3 - user
# $4 - password
# $5 - SQL
execSQL() {
	local db="$2"
	local db_lc=`echo "$2" | tr '[:upper:]' '[:lower:]'`
	local key="${system_store_key}"
	if [ "${db_lc}" == "systemdb" ]; then
		db="SystemDB"
	else
		key="${tenant_store_key}"
	fi
	local sql="$5"
	if [ $RUN_IN_DOCKER -ne 1 ]; then
		SQL_OUTPUT=`/usr/sap/${HXE_SID}/HDB${1}/exe/hdbsql -a -x -i ${1} -d ${db} -u ${3} -p ${4} ${sql} 2>&1`
	else
		SQL_OUTPUT=`/usr/sap/${HXE_SID}/HDB${1}/exe/hdbsql -a -x -i ${1} -d ${db} -U ${key} -B UTF8 ${sql} 2>&1`
	fi
	if [ $? -ne 0 ]; then
		# Strip out password string
		if [ -n "${4}" ]; then
			sql=`echo "${sql}" | sed "s/${4}/********/g"`
		fi
		if [ -n "${SYSTEM_PWD}" ]; then
			sql=`echo "${sql}" | sed "s/${SYSTEM_PWD}/********/g"`
		fi
		if [ -n "${TEL_ADMIN_PWD}" ]; then
			sql=`echo "${sql}" | sed "s/${TEL_ADMIN_PWD}/********/g"`
		fi
		if [ -n "${XSA_ADMIN_PWD}" ]; then
			sql=`echo "${sql}" | sed "s/${XSA_ADMIN_PWD}/********/g"`
		fi
		if [ -n "${XSA_DEV_PWD}" ]; then
			sql=`echo "${sql}" | sed "s/${XSA_DEV_PWD}/********/g"`
		fi
		echo "hdbsql $db => ${sql}"
		echo "${SQL_OUTPUT}"
		exit 1
	fi
}

setWebIDEProxy() {
	#xs set-env di-local-npm-registry UPSTREAM_LINK http://registry.npmjs.org/
	#xs set-env di-local-npm-registry SAPUPSTREAM_LINK https://npm.sap.com/

	if [ $SETUP_PROXY -eq 1 ] && [ $HAS_XSA -eq 1 ]; then
		echo "Set proxy for WEB_IDE..."
		echo "Check/Wait for di-local-npm-registry and di-core apps to start.  This may take a while..."
		xs wait-for-apps --timeout 3600 --apps "di-local-npm-registry,di-core"
		if [ $? -ne 0 ]; then
			echo
			echo "Waiting for apps to start has timeout."
			exit 1
		fi

		if [ -n "${PROXY_PORT}" ]; then
			xs set-env di-local-npm-registry HTTP_PROXY http://${PROXY_HOST}:${PROXY_PORT}
		else
			xs set-env di-local-npm-registry HTTP_PROXY http://${PROXY_HOST}
		fi
		if [ $? -ne 0 ]; then
			exit 1
		fi
		xs set-env di-local-npm-registry NO_PROXY "${NO_PROXY_HOST}"
		if [ $? -ne 0 ]; then
			exit 1
		fi

		xs restage di-local-npm-registry
		if [ $? -ne 0 ]; then
			exit 1
		fi
		xs restart di-local-npm-registry
		if [ $? -ne 0 ]; then
			exit 1
		fi

		xs set-env di-core JBP_CONFIG_JAVA_OPTS "[java_opts: \"-Dhttp.proxyHost=${PROXY_HOST} -Dhttp.proxyPort=${PROXY_PORT} -Dhttp.nonProxyHosts='$(formatNoProxyHost "$NO_PROXY_HOST")'\"]"
		if [ $? -ne 0 ]; then
			exit 1
		fi

		xs restage di-core
		if [ $? -ne 0 ]; then
			exit 1
		fi
		xs restart di-core
		if [ $? -ne 0 ]; then
			exit 1
		fi
	fi
}

#Create role collections for webide
createRoleCollections() {
	echo "Create role collections for WEB_IDE..."

	xs_path=/hana/shared/${HXE_SID}/xs/bin
	export PATH=$PATH:$xs_path
	ENV_PARAMS=`xs env xsa-cockpit`

	#authentication (get token)
	CLIENT_ID=`echo "$ENV_PARAMS" | grep "clientid" | cut -d'"' -f4`
	CLIENT_SECRET=`echo "$ENV_PARAMS" | grep "clientsecret" | cut -d'"' -f4`
	UAA_URL=`echo "$ENV_PARAMS" | grep "uaa-security" -m1 | cut -d'"' -f4`

	if [ -z "$CLIENT_ID" -o -z "$CLIENT_SECRET" -o -z "$UAA_URL" ]; then
		echo "Failed to get xsa-cockpit environment variables."
		echo "$ENV_PARAMS"
		exit 1
	fi

	TOKEN=`curl -s -S --max-time 300 --insecure -u ${CLIENT_ID}:${CLIENT_SECRET} --data-urlencode "password=${XSA_ADMIN_PWD}" "${UAA_URL}/oauth/token?grant_type=password&username=XSA_ADMIN" | cut -d'"' -f4`
	if [ -z "$TOKEN" ]; then
		echo "Failed to get token."
		exit 1
	fi

	DEVX_DEV_RT=WebIDE_Developer
	DEVX_DEV_RT_DESCR="Web IDE Developer"
	DEVX_DEV_RC_DESCR="Web%20IDE%20Developer%20Role%20Collection"

	DEVX_ADMIN_RT=WebIDE_Administrator
	DEVX_ADMIN_RT_DESCR="Web IDE Administrator"
	DEVX_ADMIN_RC_DESCR="Web%20IDE%20Administrator%20Role%20Collection"

	HRTT_DEV_RT=xsac_hrtt_developer_template
	HRTT_DEV_RT_DESCR="xsac_hrtt_developer_template"

	roles=`curl -s -S --max-time 180 --insecure -H "Authorization: Bearer $TOKEN" -X GET "${UAA_URL}/sap/rest/authorization/rolecollections/DEVX_DEVELOPER/roles"`
	if [ "$roles" == "{}" ]; then
		devx_env=`xs env di-core`
		app_name=`echo "$devx_env" | grep "xsappname" | cut -d'"' -f4`

		hrtt_env=`xs env hrtt-core`
		hrtt_app_name=`echo "$hrtt_env" | grep "xsappname" | cut -d'"' -f4`

		devx_role="'{\"roleTemplateName\":\"$DEVX_DEV_RT\",\"roleTemplateAppId\":\"$app_name\",\"name\":\"$DEVX_DEV_RT\",\"identityZone\":\"uaa\",\"attributeList\":null,\"description\":\"$DEVX_DEV_RT_DESCR\",\"version\":\"\"}'"

		devx_admin_role="'{\"roleTemplateName\":\"$DEVX_ADMIN_RT\",\"roleTemplateAppId\":\"$app_name\",\"name\":\"$DEVX_ADMIN_RT\",\"identityZone\":\"uaa\",\"attributeList\":null,\"description\":\"$DEVX_ADMIN_RT_DESCR\",\"version\":\"\"}'"

		hrtt_dev_role="'{\"roleTemplateName\":\"$HRTT_DEV_RT\",\"roleTemplateAppId\":\"$hrtt_app_name\",\"name\":\"$HRTT_DEV_RT\",\"identityZone\":\"uaa\",\"attributeList\":null,\"description\":\"$HRTT_DEV_RT_DESCR\",\"version\":\"\"}'"

		curl -s -S --max-time 180 --insecure -H "Authorization: Bearer $TOKEN"  -H "Content-Type: application/json" -X POST "${UAA_URL}/sap/rest/authorization/rolecollections/DEVX_DEVELOPER?description=$DEVX_DEV_RC_DESCR"

		curl -s -S --max-time 180 --insecure -H "Authorization: Bearer $TOKEN"  -H "Content-Type: application/json" -X POST "${UAA_URL}/sap/rest/authorization/rolecollections/DEVX_ADMINISTRATOR?description=$DEVX_ADMIN_RC_DESCR"

		my_command=`echo curl -s -S --max-time 180 --insecure -H \"Authorization: Bearer $TOKEN\"  -H \"Content-Type: application/json\" -X PUT -d $devx_role \"${UAA_URL}/sap/rest/authorization/rolecollections/DEVX_DEVELOPER/roles\"`
		eval $my_command

		my_command=`echo curl -s -S --max-time 180 --insecure -H \"Authorization: Bearer $TOKEN\"  -H \"Content-Type: application/json\" -X PUT -d $hrtt_dev_role \"${UAA_URL}/sap/rest/authorization/rolecollections/DEVX_DEVELOPER/roles\"`
		eval $my_command

		my_command=`echo curl -s -S --max-time 180 --insecure -H \"Authorization: Bearer $TOKEN\"  -H \"Content-Type: application/json\" -X PUT -d $devx_admin_role \"${UAA_URL}/sap/rest/authorization/rolecollections/DEVX_ADMINISTRATOR/roles\"`
		eval $my_command
	fi
}

#
# Deploys the di-builder for webide
#
builderDeployment() {
	echo "Deploy di-builder for WEB_IDE..."

	XS_PATH=/hana/shared/${HXE_SID}/xs/bin

	export PATH=$PATH:$XS_PATH

	DI_CORE_URL=$(xs app --urls di-core)
	ENV_PARAMS=`xs env di-core`

	#authentication (get token)
	CLIENT_ID=`echo "$ENV_PARAMS" | grep "clientid" | cut -d'"' -f4`
	CLIENT_SECRET=`echo "$ENV_PARAMS" | grep "clientsecret" | cut -d'"' -f4`
	UAA_URL=`echo "$ENV_PARAMS" | grep "uaa-security" -m1 | cut -d'"' -f4`

	if [ -z "$CLIENT_ID" -o -z "$CLIENT_SECRET" -o -z "$UAA_URL" ]; then
		echo "$ENV_PARAMS"
		echo
		echo "Failed to get di-core environment variables."
		exit 1
	fi

	TOKEN=`curl -s -S --max-time 300 --insecure --noproxy ${HOST_NAME} -u ${CLIENT_ID}:${CLIENT_SECRET} --data-urlencode "password=${XSA_ADMIN_PWD}" "${UAA_URL}/oauth/token?grant_type=password&username=XSA_ADMIN" | cut -d'"' -f4`
	if [ -z "$TOKEN" ]; then
		echo "$TOKEN"
		echo
		echo "Failed to get token"
		exit 1
	fi
	#Get space id for $DEV_SPACE_NAME (And retry for 20 minutes in case di-core isn't running yet)
	TICKER=0
	RESPONSE_SPACE_ID_LEN=0
	echo -n "Waiting for di-core to start..."
	while [ $RESPONSE_SPACE_ID_LEN -ne 36 ] && [ $TICKER -lt 80 ] ; do
		RESPONSE=$(curl -s -S --max-time 180 --insecure --noproxy $HOST_NAME -H "Accept: application/json" -H "Authorization: Bearer ${TOKEN}" $DI_CORE_URL/admin/builder/installed_builders)
		SPACE_ID=`echo "$RESPONSE" | tr "}" "\n" | grep "spaceName\":\"$DEV_SPACE_NAME" | cut -d'"' -f12`
		RESPONSE_SPACE_ID_LEN=${#SPACE_ID}
		if [ $RESPONSE_SPACE_ID_LEN -ne 36 ] ; then
			echo -n "."
			sleep 15s
		else
			echo
			echo "di-core has started"
		fi
		TICKER=$(($TICKER + 1))
	done
	if [ $RESPONSE_SPACE_ID_LEN -ne 36 ] ; then
		echo
		echo "$RESPONSE"
		echo
		echo "di-core failed to start."
		exit 1
	fi
	echo "Deploying builder to space $DEV_SPACE_NAME with id $SPACE_ID..."
	B_RES=$(curl -s -S --max-time 900 --insecure --noproxy $HOST_NAME -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -d '{"force":true}' $DI_CORE_URL/admin/builder/install/$SPACE_ID)

	#check that the builder deployment started
	RES_CHECK=`echo "$B_RES" | cut -d'"' -f12`
	if [ "$RES_CHECK" == "status" ] ; then
		echo "Builder deployment started."
		WORKING="true"
	else
		echo "$B_RES"
		echo
		echo "Builder deployment request failed!"
		exit 1
	fi

	#wait for status successful (or for 20 minutes to go by)
	echo -n "Wait for builder to deploy..."
	TICKER=0
	STATUS=""
	while [ "$WORKING" == "true" ] && [ $TICKER -lt 240 ] ; do
		sleep 15s
		TICKER=$(($TICKER + 1))
		S_RESPONSE=$(curl -s -S --max-time 180 --insecure --noproxy $HOST_NAME -H "Accept: application/json" -H "Authorization: Bearer ${TOKEN}" $DI_CORE_URL/admin/builder/status/$SPACE_ID)
		STATUS=`echo "$S_RESPONSE" | cut -d'"' -f14`
		if [ "$STATUS" == "IN_PROGRESS" ] ; then
			echo -n "."
		elif [[ "$STATUS" == "FAILED" || "$STATUS" == "UNKNOWN" ]] ; then
			echo
			echo "$S_RESPONSE"
			echo
			echo "Retry to deploy builder."
			HDB stop
			sleep 60s
			HDB start
			sleep 600s
                        HOST_NAME=`hostname`
                        DI_CORE_URL=$(xs app --urls di-core)
                        ENV_PARAMS=`xs env di-core`
                        CLIENT_ID=`echo "$ENV_PARAMS" | grep "clientid" | cut -d'"' -f4`
                        CLIENT_SECRET=`echo "$ENV_PARAMS" | grep "clientsecret" | cut -d'"' -f4`
                        UAA_URL=`echo "$ENV_PARAMS" | grep "uaa-security" -m1 | cut -d'"' -f4`
                        TOKEN=`curl -s -S --max-time 300 --insecure --noproxy ${HOST_NAME} -u ${CLIENT_ID}:${CLIENT_SECRET} --data-urlencode "password=${XSA_ADMIN_PWD}" "${UAA_URL}/oauth/token?grant_type=password&username=XSA_ADMIN" | cut -d'"' -f4`

			BUILDER_RES=$(curl -s -S --max-time 900 --insecure --noproxy $HOST_NAME -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -d '{"force":true}' $DI_CORE_URL/admin/builder/install/$SPACE_ID)
			if [ $TICKER -ge 80 ] ; then
				WORKING="false"
				exit 1
			fi
			continue
		elif [ "$STATUS" == "SUCCESSFUL" ] ; then
			echo
			echo "Successfully deployed builder in space $DEV_SPACE_NAME."
			WORKING="false"
		else
                        HOST_NAME=`hostname`
                        DI_CORE_URL=$(xs app --urls di-core)
                        ENV_PARAMS=`xs env di-core`
                        CLIENT_ID=`echo "$ENV_PARAMS" | grep "clientid" | cut -d'"' -f4`
                        CLIENT_SECRET=`echo "$ENV_PARAMS" | grep "clientsecret" | cut -d'"' -f4`
                        UAA_URL=`echo "$ENV_PARAMS" | grep "uaa-security" -m1 | cut -d'"' -f4`
                        TOKEN=`curl -s -S --max-time 300 --insecure --noproxy ${HOST_NAME} -u ${CLIENT_ID}:${CLIENT_SECRET} --data-urlencode "password=${XSA_ADMIN_PWD}" "${UAA_URL}/oauth/token?grant_type=password&username=XSA_ADMIN" | cut -d'"' -f4`

                        BUILDER_RES=$(curl -s -S --max-time 900 --insecure --noproxy $HOST_NAME -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -d '{"force":true}' $DI_CORE_URL/admin/builder/install/$SPACE_ID)
		fi
	done
	if [ "$STATUS" != "SUCCESSFUL" ] ; then
		echo
		echo "$S_RESPONSE"
		echo
		echo "Failed to deploy builder."
		exit 1
	fi
}

waitForXsController() {
         local retry=3600
         local status=1

         echo -n "Wait for XS controller READY ..."
         while [ $retry -gt 0 ]; do
             currentXsControllerState=$(xs curl v2/info | grep state | awk -F: '{print $2}' | sed -e 's/ //g;s/"//g;s/,//g')
             if [ "$currentXsControllerState" == "READY" ]; then
                 status=0
                 break
             else
                 echo -n "Waiting for the controller"
                 sleep 30s
                 retry=$(($retry - 30))
             fi
         done

         echo

         if [ $status -ne 0 ]; then
                 echo
                 echo "xs controller is not READY.  Please check HANA has started."
                 exit 1
         fi
}
#Execute scripts to add and configure required xsa users and stop services
#that do not need to be running
postProcessXSA() {
	if [ $HAS_XSA -ne 1 ]; then
		return
	fi

	# Reduce memory footprint by storing all lob data on disk
	echo "Reduce memory footprint by storing all lob data on disk..."
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER TABLE \"SYS_XS_RUNTIME\".\"BLOBSTORE\" ALTER (\"VALUE\" BLOB MEMORY THRESHOLD 0)"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM') SET ('memoryobjects', 'unload_upper_bound') = '838860800' with reconfigure"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM') SET ('memoryobjects', 'unused_retention_period' ) = '60' with reconfigure"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM') SET ('memoryobjects', 'unused_retention_period_check_interval' ) = '60' with reconfigure"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM') SET ('memorymanager', 'gc_unused_memory_threshold_abs' ) = '1024' with reconfigure"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "DROP FULLTEXT INDEX _sys_repo.\"FTI_ACTIVE_OBJECT_CDATA\""
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "CREATE FULLTEXT INDEX _sys_repo.\"FTI_ACTIVE_OBJECT_CDATA\" ON \"_SYS_REPO\".\"ACTIVE_OBJECT\"(\"CDATA\" ) LANGUAGE DETECTION ('EN') ASYNC PHRASE INDEX RATIO 0.0 SEARCH ONLY OFF FAST PREPROCESS OFF TOKEN SEPARATORS '\\/;,.:-_()[]<>!?*@+{}=\"&#\$~|'"

	# Enable repository
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM') SET ('repository', 'enable_repository') = 'TRUE' WITH RECONFIGURE"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('nameserver.ini', 'SYSTEM') SET ('repository', 'enable_repository') = 'TRUE'  WITH RECONFIGURE"

	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('nameserver.ini', 'SYSTEM') SET ('session', 'idle_connection_timeout') = '60' WITH RECONFIGURE;"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM') SET ('session', 'idle_connection_timeout') = '60' WITH RECONFIGURE;"

	waitForXsController
	output=`xs login -u xsa_admin -p ${XSA_ADMIN_PWD} -s ${SPACE_NAME}`
	if [ $? -ne 0 ]; then
		echo "${output}"
		echo
		echo "Cannot login to XSA services.  Please check HANA has started and login/password are correct."
		exit 1
	fi

	setWebIDEProxy

	#Create role collections for webide
	createRoleCollections
	echo

	#Change password policy
	echo "Change password policy..."
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION('nameserver.ini','SYSTEM') SET ('password policy','maximum_password_lifetime') = '365' WITH RECONFIGURE"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION('nameserver.ini','SYSTEM') SET ('password policy','maximum_unused_initial_password_lifetime') = '365' WITH RECONFIGURE"

	#Creating xsa_dev user and assigning role collection
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM USERS WHERE USER_NAME='XSA_DEV'"
	SQL_OUTPUT=`trim ${SQL_OUTPUT}`
	if [ "$SQL_OUTPUT" != "1" ]; then
		echo "Create XSA_DEV user..."
		execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "CREATE USER XSA_DEV PASSWORD \"${XSA_DEV_PWD}\" NO FORCE_FIRST_PASSWORD_CHANGE SET PARAMETER XS_RC_XS_CONTROLLER_USER = 'XS_CONTROLLER_USER' , XS_RC_DEVX_DEVELOPER = 'DEVX_DEVELOPER', XS_RC_XS_AUTHORIZATION_ADMIN = 'XS_AUTHORIZATION_ADMIN'"
	fi

	#altering the xsa_admin user to assign the role collection
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER USER XSA_ADMIN SET PARAMETER XS_RC_XS_CONTROLLER_USER = 'XS_CONTROLLER_USER', XS_RC_DEVX_ADMIN = 'DEVX_ADMINISTRATOR', XS_RC_XS_AUTHORIZATION_ADMIN = 'XS_AUTHORIZATION_ADMIN', XS_RC_DEVX_DEVELOPER = 'DEVX_DEVELOPER'"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER USER XSA_DEV SET PARAMETER XS_RC_XS_CONTROLLER_USER = 'XS_CONTROLLER_USER' , XS_RC_DEVX_DEVELOPER = 'DEVX_DEVELOPER', XS_RC_XS_AUTHORIZATION_ADMIN = 'XS_AUTHORIZATION_ADMIN'"

	echo "Set space roles in \"$SPACE_NAME\" space in \"${ORG_NAME}\" org..."
	space_users=`xs space-users ${ORG_NAME} ${SPACE_NAME}`
	if [ $? -ne 0 ]; then
		echo "$space_users"
		echo "Cannot get space users."
		exit 1
	fi
	if ! echo "$space_users" | grep ^SpaceDeveloper | grep XSA_ADMIN >& /dev/null; then
		xs set-space-role XSA_ADMIN ${ORG_NAME} $SPACE_NAME SpaceDeveloper
		if [ $? -ne 0 ]; then
			exit 1
		fi
	fi
	if ! echo "$space_users" | grep ^SpaceAuditor | grep XSA_ADMIN >& /dev/null; then
		xs set-space-role XSA_ADMIN ${ORG_NAME} $SPACE_NAME SpaceAuditor
		if [ $? -ne 0 ]; then
			exit 1
		fi
	fi
	if ! echo "$space_users" | grep ^SpaceAuditor | grep XSA_DEV >& /dev/null; then
		xs set-space-role XSA_DEV ${ORG_NAME} $SPACE_NAME SpaceAuditor
		if [ $? -ne 0 ]; then
			exit 1
		fi
	fi

	echo "Set space roles in \"$DEV_SPACE_NAME\" space in \"${ORG_NAME}\" org..."
	space_users=`xs space-users ${ORG_NAME} ${DEV_SPACE_NAME}`
	if [ $? -ne 0 ]; then
		echo "$space_users"
		echo "Cannot get space users."
		exit 1
	fi
	if ! echo "$space_users" | grep ^SpaceDeveloper | grep XSA_ADMIN >& /dev/null; then
		xs set-space-role XSA_ADMIN ${ORG_NAME} $DEV_SPACE_NAME SpaceDeveloper
		if [ $? -ne 0 ]; then
			exit 1
		fi
	fi
	if ! echo "$space_users" | grep ^SpaceDeveloper | grep XSA_DEV >& /dev/null; then
		xs set-space-role XSA_DEV ${ORG_NAME} $DEV_SPACE_NAME SpaceDeveloper
		if [ $? -ne 0 ]; then
			exit 1
		fi
	fi

	#Cockpit
	org_users=`xs org-users ${ORG_NAME}`
	if [ $? -ne 0 ]; then
		echo "$org_users"
		echo "Cannot get org users."
		exit 1
	fi
	if ! echo "$org_users" | grep ^OrgManager | grep XSA_ADMIN >& /dev/null; then
		xs set-org-role XSA_ADMIN ${ORG_NAME} OrgManager
		if [ $? -ne 0 ]; then
			exit 1
		fi
	fi

	#Deploys the di-builder for webide
	builderDeployment

	# Stop apps
	stopApps
    
    	#Cleanup extra app instances
	cleanupApps
}

#
# Cycle through the services of an MTA and either stop them or start them
# Note: need "action" variable defined
#
processMTA() {
	rowNum=0
	startAppsRowNum=9999999
	while read row; do
		appName=`echo $row | cut -d' ' -f1`
		if [ "$rowNum" -ge "$startAppsRowNum" ]; then
			if [ -n "$appName" ] ; then
				if [ "$action" == "stop" ]; then
					echo "Stopping ${appName}..."
				else
					echo "Starting ${appName}..."
				fi
				output=`xs $action $appName`
				if [ $? -ne 0 ]; then
					echo "${output}"
					exit 1
				fi
			else
				#if the $appName variable is blank we have reached the end of the app section
				#This happens because there is a Services section after the Apps: section
				break
			fi
		else
			if [ "$appName" == "Apps:" ]; then
				startAppsRowNum=$(($rowNum+3))
			fi
		fi
		rowNum=$(($rowNum + 1))
	done
}

#
# Cleans up each individual app by removing its crashed and stopped apps
# arg1 - multiline list of app names
cleanupEachApp     () {
    while read appName; do
        echo "Cleaning up instances of $appName pass 1..."
        #Clean up the crashed instances
        output=$(xs delete-app-instances $appName --crashed -f)
        if [ $? -ne 0 ]; then
            echo "${output}"
            echo
            echo "Failed to delete crashed instances for $appName."
            exit 1
            fi
            
        #Clean up the stopped instances 
        echo "Cleaning up stopped instances of $appName pass 2..."        
        output=$(xs delete-app-instances $appName --stopped -f)
        if [ $? -ne 0 ]; then
            echo "${output}"
            echo
            echo "Failed to delete stopped instances for $appName."
            exit 1
            fi     
    done        
}

#
# Cleanup apps
# This function removes any apps that crashed or instances of apps that were started.
cleanupApps() {

	echo "Cleanup stopped applications..."
	output=`xs login -u xsa_admin -p ${XSA_ADMIN_PWD} -s SAP`
	if [ $? -ne 0 ]; then
		echo "${output}"
		echo
		echo "Cannot login to XSA services.  Please check HANA has started and login/password are correct."
		exit 1
        fi

	#loop through xs apps and perform a function call on each.
    xs apps | \
    #xs apps returns 6 lines of header
    awk '{if ((NR>6) && (length($0) > 1)) {print $1}}' | \
    # Call the cleanup command with the list of app names
    cleanupEachApp  
}


#
# Stop apps
# This function turns off a few mtas to free up some memory for HXE to run.
stopApps() {
	# "stop" or "start" apps
	action=stop

	echo "Stop applications..."
	output=`xs login -u xsa_admin -p ${XSA_ADMIN_PWD} -s SAP`
	if [ $? -ne 0 ]; then
		echo "${output}"
		echo
		echo "Cannot login to XSA services.  Please check HANA has started and login/password are correct."
		exit 1
        fi

	#stop all the apps for jobscheduler
	xs mta com.sap.xs.jobscheduler | processMTA

	#stop all the apps for messaging service
	xs mta com.sap.xs.messaging-service.xsac.mess.srv | processMTA

	echo "Stopping di-space-enablement-ui..."
	output=`xs stop di-space-enablement-ui`
	if [ $? -ne 0 ]; then
		echo "${output}"
		exit 1
	fi

	#stop all the apps for devx
#	xs mta com.sap.devx.webide | processMTA
#	xs mta com.sap.devx.di.builder | processMTA

#	echo "Stopping sap-portal-services..."
#	output=`xs stop sap-portal-services`
#	if [ $? -ne 0 ]; then
#		echo "${output}"
#		exit 1
#	fi
}

#
# Wait for apps to start
#
waitAppsStarted() {
	if [ $HAS_XSA -ne 1 ]; then
		return
	fi

	echo "Login to XSA services..."
	output=`xs login -u xsa_admin -p ${XSA_ADMIN_PWD} -s ${SPACE_NAME}`
	if [ $? -ne 0 ]; then
		echo "${output}"
		echo
		echo "Cannot login to XSA services.  Please check HANA has started and login/password are correct."
		exit 1
	fi

	echo "Check/Wait for all apps to start.  This may take a while..."
	output=`xs wait-for-apps --timeout 3600 --all-instances --space ${SPACE_NAME}`
	if [ $? -ne 0 ]; then
		echo "${output}"
		echo
		echo "Waiting for apps to start has timeout."
		exit 1
	fi
}


#
# Grant activated role
#
grantActivatedRole() {
	local role_name=""
	local retry=300
	local granted=0
	local role_list=(
		sap.hana.xs.admin.roles::HTTPDestViewer
		sap.hana.xs.admin.roles::SQLCCAdministrator
		sap.hana.xs.debugger::Debugger
	)

	if [ $HAS_XSA -eq 1 -o $HAS_XSC -eq 1 ]; then
		for role_name in "${role_list[@]}"; do
			echo "Grant activated role \"${role_name}\" to SYSTEM on SystemDB database..."
			retry=300
			granted=0
			while [ $retry -gt 0 ]; do
				execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM ROLES WHERE ROLE_NAME='${role_name}'"
				SQL_OUTPUT=`trim ${SQL_OUTPUT}`
				if [ "$SQL_OUTPUT" == "1" ]; then
					execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "CALL GRANT_ACTIVATED_ROLE ('${role_name}','SYSTEM')"
					granted=1
					break
				fi
				sleep 10s
				retry=$(($retry - 10))
			done
			if [ $granted -eq 0 ]; then
				echo
				echo "Warning: Waiting for activated role \"${role_name}\" to be available has timed out."
				echo "Please execute this command manually in SystemDB database:"
				echo "	CALL GRANT_ACTIVATED_ROLE ('${role_name}','SYSTEM')"
				echo
			fi
		done

		if [ $HAS_TENANT_DB -eq 1 ]; then
			for role_name in "${role_list[@]}"; do
				echo "Grant activated role \"${role_name}\" to SYSTEM on ${HXE_SID} database..."
				retry=300
				granted=0
				while [ $retry -gt 0 ]; do
					execSQL ${HANA_INSTANCE} ${HXE_SID} SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM ROLES WHERE ROLE_NAME='${role_name}'"
					SQL_OUTPUT=`trim ${SQL_OUTPUT}`
					if [ "$SQL_OUTPUT" == "1" ]; then
						execSQL ${HANA_INSTANCE} ${HXE_SID} SYSTEM ${SYSTEM_PWD} "CALL GRANT_ACTIVATED_ROLE ('${role_name}','SYSTEM')"
						granted=1
						break
					fi
					sleep 10s
					retry=$(($retry - 10))
				done
				if [ $granted -eq 0 ]; then
					echo
					echo "Warning: Waiting for activated role \"${role_name}\" to be available has timed out."
					echo "Please execute this command manually in ${HXE_SID} database:"
					echo "	CALL GRANT_ACTIVATED_ROLE ('${role_name}','SYSTEM')"
					echo
				fi
			done
		fi

		echo "Set system configuration wdisp/system_auto_configuration=true in webdispatcher.ini..."
		execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('webdispatcher.ini', 'system') SET('profile', 'wdisp/system_auto_configuration') = 'true' WITH RECONFIGURE;"
	fi
}

#
# Remove uneeded files
#
removePostInstallFiles() {
	# remove tomcat war files
	rm -f /hana/shared/${HXE_SID}/xs/uaaserver/tomcat/webapps/hdi-broker.war
	rm -f /hana/shared/${HXE_SID}/xs/uaaserver/tomcat/webapps/sapui5.war
	rm -f /hana/shared/${HXE_SID}/xs/uaaserver/tomcat/webapps/uaa-security.war

	# Delete the DataQuality directory
	rm -rf /hana/shared/${HXE_SID}/exe/${PLATFORM}/HDB*/DataQuality
}

#
# Register Cockpit resource
#
registerDB() {
	local status=0
	if [ $HAS_XSA -eq 1 ]; then
		# Drop trigger
		execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM TRIGGERS \
 WHERE TRIGGERS.SCHEMA_NAME='_SYS_TELEMETRY' \
 AND TRIGGERS.TRIGGER_NAME='CLIENT_INSERT_TRIG'"
		SQL_OUTPUT=`trim ${SQL_OUTPUT}`
		if [ "$SQL_OUTPUT" == "1" ]; then
			execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "DROP TRIGGER _SYS_TELEMETRY.CLIENT_INSERT_TRIG"
		fi
		execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM TRIGGERS \
 WHERE TRIGGERS.SCHEMA_NAME='_SYS_TELEMETRY' \
 AND TRIGGERS.TRIGGER_NAME='CLIENT_UPDATE_TRIG'"
		SQL_OUTPUT=`trim ${SQL_OUTPUT}`
		if [ "$SQL_OUTPUT" == "1" ]; then
			execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "DROP TRIGGER _SYS_TELEMETRY.CLIENT_UPDATE_TRIG"
		fi

		if [ $DO_NOT_REGISTER_RESOURCE -ne 1 ]; then
			echo "Register SystemDB database HDB resource with Cockpit..."
			${PROG_DIR}/register_cockpit.sh -action register -d SystemDB <<-EOF
SYSTEM
$SYSTEM_PWD
XSA_ADMIN
$XSA_ADMIN_PWD
TEL_ADMIN
$TEL_ADMIN_PWD
$HANA_INSTANCE
EOF
			if [ $? -ne 0 ]; then
				echo
				echo "Failed to register SystemDB database HDB resource with Cockpit."
				status=1
			fi
		fi

		if [ $HAS_TENANT_DB -eq 1 ]; then
			# Drop trigger
			execSQL ${HANA_INSTANCE} ${HXE_SID} SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM TRIGGERS \
 WHERE TRIGGERS.SCHEMA_NAME='_SYS_TELEMETRY' \
 AND TRIGGERS.TRIGGER_NAME='CLIENT_INSERT_TRIG'"
			SQL_OUTPUT=`trim ${SQL_OUTPUT}`
			if [ "$SQL_OUTPUT" == "1" ]; then
				execSQL ${HANA_INSTANCE} ${HXE_SID} SYSTEM ${SYSTEM_PWD} "DROP TRIGGER _SYS_TELEMETRY.CLIENT_INSERT_TRIG"
			fi
			execSQL ${HANA_INSTANCE} ${HXE_SID} SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM TRIGGERS \
 WHERE TRIGGERS.SCHEMA_NAME='_SYS_TELEMETRY' \
 AND TRIGGERS.TRIGGER_NAME='CLIENT_UPDATE_TRIG'"
			SQL_OUTPUT=`trim ${SQL_OUTPUT}`
			if [ "$SQL_OUTPUT" == "1" ]; then
				execSQL ${HANA_INSTANCE} ${HXE_SID} SYSTEM ${SYSTEM_PWD} "DROP TRIGGER _SYS_TELEMETRY.CLIENT_UPDATE_TRIG"
			fi
			if [ $DO_NOT_REGISTER_RESOURCE -ne 1 ]; then
				echo "Register ${HXE_SID} database HDB resource with Cockpit..."
				${PROG_DIR}/register_cockpit.sh -action register -d ${HXE_SID} <<-EOF
SYSTEM
$SYSTEM_PWD
XSA_ADMIN
$XSA_ADMIN_PWD
TEL_ADMIN
$TEL_ADMIN_PWD
$HANA_INSTANCE
EOF
				if [ $? -ne 0 ]; then
					echo
					echo "Failed to register ${HXE_SID} database HDB resource."
					status=1
				fi
			fi
		fi

		# Setup proxy
		if [ $SETUP_PROXY -eq 1 ]; then
			echo "Set proxy in Cockpit..."
			${PROG_DIR}/register_cockpit.sh -action config_proxy -proxy_action enable_http <<-EOF
XSA_ADMIN
${XSA_ADMIN_PWD}
${HANA_INSTANCE}
${PROXY_HOST}
${PROXY_PORT}
${NO_PROXY_HOST}
EOF
			if [ $? -ne 0 ]; then
				echo
				echo "Failed to set proxy in Cockpit."
				status=1
			fi
		fi
	elif [ -d "/hana/shared/${HXE_SID}/telemetryClient" ]; then
                if [ $DO_NOT_REGISTER_RESOURCE -ne 1 ]; then
                        echo "Register SystemDB database HDB resource with Telemetry Client..."
                        ${PROG_DIR}/register_db.sh -action register -d SystemDB <<-EOF
SYSTEM
$SYSTEM_PWD
TEL_ADMIN
$TEL_ADMIN_PWD
$HANA_INSTANCE
EOF
                        if [ $? -ne 0 ]; then
                                echo
                                echo "Failed to register SystemDB database HDB resource with Telemetry Client."
                                status=1
                        fi
                fi
                if [ $HAS_TENANT_DB -eq 1 ]; then
                        if [ $DO_NOT_REGISTER_RESOURCE -ne 1 ]; then
                                echo "Register ${HXE_SID} database HDB resource with Telemetry Client..."
                                ${PROG_DIR}/register_db.sh -action register -d ${HXE_SID} <<-EOF
SYSTEM
$SYSTEM_PWD
TEL_ADMIN
$TEL_ADMIN_PWD
$HANA_INSTANCE
EOF
                                if [ $? -ne 0 ]; then
                                        echo
                                        echo "Failed to register ${HXE_SID} database HDB resource with Telemetry Client."
                                        status=1
                                fi
                        fi
                fi

                # Setup proxy
                if [ $SETUP_PROXY -eq 1 ]; then
                        echo "Set proxy in Cockpit..."
                        ${PROG_DIR}/register_db.sh -action config_proxy -proxy_action enable_http <<-EOF
${PROXY_HOST}
${PROXY_PORT}
${NO_PROXY_HOST}
EOF
                        if [ $? -ne 0 ]; then
                                echo
                                echo "Failed to set proxy with Telemetry Client."
                                status=1
                        fi
                fi
	fi

		

	if [ $status -ne 0 ]; then
		exit 1
	fi
}

#
# Setup telemetry
#
setupTelemetry() {
       if [ $HAS_XSA -ne 1 ] && [ -d "/hana/shared/${HXE_SID}/telemetryClient" ]; then
		export CATALINA_HOME=/hana/shared/${HXE_SID}/telemetryClient/tomcat
		export JRE_HOME=/hana/shared/${HXE_SID}/telemetryClient/jre
		/hana/shared/${HXE_SID}/telemetryClient/tomcat/bin/catalina.sh start
		if [ $? -ne 0 ]; then
			echo
			echo "Failed to start tomcat server"
			exit 1
		fi

		if [ $DO_NOT_REGISTER_RESOURCE -ne 1 ]; then
			sleep 30
			echo "Initialize telemetry client..."
			${PROG_DIR}/register_db.sh -action init_service <<-EOF
SYSTEM
$SYSTEM_PWD
$HANA_INSTANCE
EOF
			if [ $? -ne 0 ]; then
				echo
				echo "Failed to initialize Telemetry Client"
				exit 1
			fi
		fi
	fi

	if [ $HAS_XSA -ne 1 ] && [ ! -d "/hana/shared/${HXE_SID}/telemetryClient" ]; then
		return	
	fi

	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM USERS WHERE USER_NAME='TEL_ADMIN'"
	SQL_OUTPUT=`trim ${SQL_OUTPUT}`
	if [ "$SQL_OUTPUT" != "1" ]; then
		# Create telemetry technical user on SystemDB database
		echo "Create telemetry technical user \"TEL_ADMIN\" on \"SystemDB\" database..."
		execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "CREATE USER TEL_ADMIN PASSWORD \"${TEL_ADMIN_PWD}\" NO FORCE_FIRST_PASSWORD_CHANGE"
		execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER USER TEL_ADMIN DISABLE PASSWORD LIFETIME"
		execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA \"_SYS_TELEMETRY\" TO TEL_ADMIN"
		execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "GRANT SELECT ON SCHEMA \"_SYS_STATISTICS\" TO TEL_ADMIN"
		execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "GRANT CATALOG READ TO TEL_ADMIN"
	fi

	if [ $HAS_TENANT_DB -eq 1 ]; then
		sleep 30
		execSQL ${HANA_INSTANCE} ${HXE_SID} SYSTEM ${SYSTEM_PWD} "SELECT COUNT(*) FROM USERS WHERE USER_NAME='TEL_ADMIN'"
		SQL_OUTPUT=`trim ${SQL_OUTPUT}`
		if [ "$SQL_OUTPUT" != "1" ]; then
			# Create telemetry technical user on tenant database
			echo "Create telemetry technical user \"TEL_ADMIN\" on \"${HXE_SID}\" database..."
			execSQL ${HANA_INSTANCE} ${HXE_SID} SYSTEM ${SYSTEM_PWD} "CREATE USER TEL_ADMIN PASSWORD \"${TEL_ADMIN_PWD}\" NO FORCE_FIRST_PASSWORD_CHANGE"
			execSQL ${HANA_INSTANCE} ${HXE_SID} SYSTEM ${SYSTEM_PWD} "ALTER USER TEL_ADMIN DISABLE PASSWORD LIFETIME"
			execSQL ${HANA_INSTANCE} ${HXE_SID} SYSTEM ${SYSTEM_PWD} "GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA \"_SYS_TELEMETRY\" TO TEL_ADMIN"
			execSQL ${HANA_INSTANCE} ${HXE_SID} SYSTEM ${SYSTEM_PWD} "GRANT SELECT ON SCHEMA \"_SYS_STATISTICS\" TO TEL_ADMIN"
			execSQL ${HANA_INSTANCE} ${HXE_SID} SYSTEM ${SYSTEM_PWD} "GRANT CATALOG READ TO TEL_ADMIN"
		fi
	fi

	echo "Change telemetry URL for \"SystemDB\" database..."
	${PROG_DIR}/hxe_telemetry.sh -d SystemDB -i ${HANA_INSTANCE} -u TEL_ADMIN -c "${TEL_URL}" <<-EOF
${TEL_ADMIN_PWD}
EOF
	if [ $? -ne 0 ]; then
		exit 1
	fi

	if [ $HAS_TENANT_DB -eq 1 ]; then
		echo "Change telemetry URL for \"${HXE_SID}\" database..."
		${PROG_DIR}/hxe_telemetry.sh -d ${HXE_SID} -i ${HANA_INSTANCE} -u TEL_ADMIN -c "${TEL_URL}" <<-EOF
${TEL_ADMIN_PWD}
EOF
		if [ $? -ne 0 ]; then
			exit 1
		fi
	fi
}

postProcessServer() {

	# Enable debugger in workbench
	echo "Enable debugger in workbench..."
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('nameserver.ini','SYSTEM') set ('debugger','enabled') = 'true' WITH RECONFIGURE;"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('nameserver.ini','SYSTEM') set ('httpserver','developer_mode') = 'true' WITH RECONFIGURE;"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM ALTER CONFIGURATION ('nameserver.ini','SYSTEM') set ('debugger','listenport') = '3${HANA_INSTANCE}08' WITH RECONFIGURE;"

	echo "Enable statistics server..."
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "alter system alter configuration('nameserver.ini','SYSTEM') SET ('statisticsserver','active') = 'true' with reconfigure"

	# Include diserver in startup for server-only
	if [ $HAS_XSA -eq 0 ]; then
		# SAP_RETRIEVAL_PATH=/hana/shared/${HXE_SID}/HDB${HANA_INSTANCE}/hxehost
		echo "Enable diserver server..."
		if ! grep '^\[diserver\]' $SAP_RETRIEVAL_PATH/daemon.ini >& /dev/null; then
			cat >> ${SAP_RETRIEVAL_PATH}/daemon.ini <<-EOF

[diserver]
instances = 1
EOF
		fi
	fi
	
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "alter system alter configuration ('global.ini', 'SYSTEM') SET ('public_hostname_resolution', 'use_default_route') = 'ip' with reconfigure"
}

collectGarbage() {
	echo "Do garbage collection..."

	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM SAVEPOINT"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM RECLAIM LOG"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM RECLAIM DATAVOLUME 105 DEFRAGMENT"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM RECLAIM VERSION SPACE"
	execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM CLEAR SQL PLAN CACHE"

	server_list="hdbnameserver hdbindexserver hdbcompileserver hdbpreprocessor hdbdiserver"
	if [ $HAS_XSA -eq 1 ]; then
		server_list="hdbnameserver hdbindexserver hdbcompileserver hdbpreprocessor hdbdiserver hdbwebdispatcher"
	fi
	hdbinfo_output=`HDB info`
	for server in $server_list; do
		if echo $hdbinfo_output | grep "${server}" >& /dev/null; then
			echo "Collect garbage on \"${server}\"..."
			output=`/usr/sap/${HXE_SID}/HDB${HANA_INSTANCE}/exe/hdbcons -e ${server} "mm gc -f"`
			if [ $? -ne 0 ]; then
				echo "${output}"
			fi
			echo "Shrink resource container memory on \"${server}\"..."
			output=`/usr/sap/${HXE_SID}/HDB${HANA_INSTANCE}/exe/hdbcons -e ${server} "resman shrink"`
			if [ $? -ne 0 ]; then
				echo "${output}"
			fi
		fi
	done

	echo "Reclaim data volume on hdbnameserver..."
	output=`/usr/sap/${HXE_SID}/HDB${HANA_INSTANCE}/exe/hdbcons -e hdbnameserver "dvol reclaim -o 105"`
	if echo "$output" | grep -i error >& /dev/null; then
		echo "${output}"
	fi

	echo "Reclaim data volume on hdbindexserver..."
	output=`/usr/sap/${HXE_SID}/HDB${HANA_INSTANCE}/exe/hdbcons -e hdbindexserver "dvol reclaim -o 105"`
	if echo "$output" | grep -i error >& /dev/null; then
		echo "${output}"
	fi

	echo "Release free log segments on hdbnameserver..."
	output=`/usr/sap/${HXE_SID}/HDB${HANA_INSTANCE}/exe/hdbcons -e hdbnameserver "log release"`
	if echo "$output" | grep -i error >& /dev/null; then
		echo "${output}"
	fi

	echo "Release free log segments on hdbindexserver..."
	output=`/usr/sap/${HXE_SID}/HDB${HANA_INSTANCE}/exe/hdbcons -e hdbindexserver "log release"`
	if echo "$output" | grep -i error >& /dev/null; then
		echo "${output}"
	fi
}

startTenantDB() {
	if [ $HAS_TENANT_DB -eq 1 ]; then
		echo "Start \"${HXE_SID}\" tenant database. This may take a while..."
		execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM START DATABASE ${HXE_SID}"
	fi
}

stopTenantDB() {
	if [ $HAS_TENANT_DB -eq 1 ]; then
		echo "Stop \"${HXE_SID}\" tenant database..."
		execSQL ${HANA_INSTANCE} SystemDB SYSTEM ${SYSTEM_PWD} "ALTER SYSTEM STOP DATABASE ${HXE_SID}"
	fi
}

# Check if server user/password valid
# $1 - database
# $2 - user
# $3 - password
checkHDBUserPwd() {
	output=$(/usr/sap/${HXE_SID}/HDB${HANA_INSTANCE}/exe/hdbsql -a -x -quiet 2>&1 <<-EOF
\c -i ${HANA_INSTANCE} -d $1 -u $2 -p $3
EOF
)
	if [ $? -ne 0 ]; then
		echo
		echo "$output"
		echo
		echo "Cannot login to \"$1\" database with \"$2\" user."
		if echo "$output" | grep -i "authentication failed" >& /dev/null; then
			echo "Please check if password is correct."
			echo
			return 1
		else
			echo "Please check if the database is running."
			echo
			exit 1
		fi
	fi

	return 0
}

# Trim leading and trailing spaces
trim()
{
	trimmed="$1"
	trimmed=${trimmed%% }
	trimmed=${trimmed## }
	echo "$trimmed"
}

#########################################################
# Main
#########################################################
PROG_DIR=`dirname $0`
PROG_NAME=`basename $0`

# Platform
if [ `uname -m` == "ppc64le" ]; then
        PLATFORM="linuxppc64le"
else
        PLATFORM="linuxx86_64"
fi

HOST_NAME=`basename $SAP_RETRIEVAL_PATH`
HAS_SERVER=0
HAS_XSC=0
HAS_XSA=0
HXE_SID="HXE"
HXE_ADM="hxeadm"
HANA_INSTANCE=""

HAS_TENANT_DB=0

SYSTEM_PWD=""
TEL_ADMIN_PWD=""
XSA_ADMIN_PWD=""
XSA_DEV_PWD=""

SETUP_PROXY=0
SYSTEM_PROXY_HOST=""
SYSTEM_PROXY_PORT=""
SYSTEM_NO_PROXY_HOST=""
PROXY_HOST=""
PROXY_PORT=""
NO_PROXY_HOST=""

TEL_URL="https://telemetry.cloud.sap"

ORG_NAME="HANAExpress"
SPACE_NAME="SAP"
DEV_SPACE_NAME="development"

DO_NOT_REGISTER_RESOURCE=0
RUN_IN_DOCKER=0
declare -r system_store_key=us_key_systemdb
declare -r tenant_store_key=us_key_tenantdb

getSID

checkEnv

checkServer

#
# Parse argument
#
if [ $# -gt 0 ]; then
	PARSED_OPTIONS=`getopt -n "$PROG_NAME" -a -o di:p: --long tp:,xsap:,xsadevp:,ph:,pp:,nph:,no_reg,org_name: -- "$@"`
	if [ $? -ne 0 -o "$#" -eq 0 ]; then
		exit 1
	fi

	# Process command line arguments
	eval set -- "$PARSED_OPTIONS"
	while true
	do
		case "$1" in
		-d)	RUN_IN_DOCKER=1
			shift;;
		-i)
			HANA_INSTANCE="$2"
			shift 2;;
		-p)
			SYSTEM_PWD="$2"
			shift 2;;
		-tp|--tp)
			TEL_ADMIN_PWD="$2"
			shift 2;;
		-xsap|--xsap)
			XSA_ADMIN_PWD="$2"
			shift 2;;
		-xsadevp|--xsadevp)
			XSA_DEV_PWD="$2"
			shift 2;;
		-ph|--ph)
			PROXY_HOST="$2"
			SETUP_PROXY=1
			if ! $(isValidHostName "$PROXY_HOST"); then
				echo
				echo "\"$PROXY_HOST\" is not a valid host name or IP address."
				exit 1
			fi
			shift 2;;
		-pp|--pp)
			PROXY_PORT="$2"
			SETUP_PROXY=1
			if ! $(isValidPort "$PROXY_PORT"); then
				echo
				echo "\"$PROXY_PORT\" is not a valid port number."
				echo "Enter number between 1 and 65535."
				exit 1
			fi
			shift 2;;
		-nph|--nph)
			NO_PROXY_HOST="$2"
			shift 2;;
		-no_reg|--no_reg)
			DO_NOT_REGISTER_RESOURCE=1
			shift 1;;
		-org_name|--org_name)
			ORG_NAME="$2"
			shift 2;;
		--)
			shift
			break;;
		*)
			echo "Invalid \"$1\" argument."
			exit 1
		esac
	done
fi

if [ $RUN_IN_DOCKER -eq 1 ]; then
	HXE_SID="${SAPSYSTEMNAME}"
	HANA_INSTANCE="${TINSTANCE}"
	SYSTEM_PWD="manager"
	TEL_ADMIN_PWD="manager"
	XSA_ADMIN_PWD="manager"
	XSA_DEV_PWD="manager"
fi

promptInstanceNumber

if [ -z "$SYSTEM_PWD" ]; then
	promptPwd "System database user (SYSTEM)" "SYSTEM_PWD"
	while ! checkHDBUserPwd SystemDB SYSTEM ${SYSTEM_PWD}; do
		promptPwd "System database user (SYSTEM)" "SYSTEM_PWD"
	done
fi

# Prompt new telemetry technical and XSA user/password 
if [ -z "$TEL_ADMIN_PWD" ]; then
	# Without this, VM build will enter in password rule unmatch dead loop!
	if [ $HAS_XSA -eq 1 ]; then
		promptNewPwd "Telemetry technical user (TEL_ADMIN)" "TEL_ADMIN_PWD"
	fi
fi

echo " "

if [ $HAS_XSA -eq 1 ]; then
	if [ -z "$XSA_ADMIN_PWD" ]; then
		promptPwd "XSA administrative user (XSA_ADMIN)" "XSA_ADMIN_PWD"
		while ! checkHDBUserPwd SystemDB XSA_ADMIN ${XSA_ADMIN_PWD}; do
			promptPwd "XSA administrative user (XSA_ADMIN)" "XSA_ADMIN_PWD"
		done
	fi
	if [ -z "$XSA_DEV_PWD" ]; then
		promptNewPwd "XSA development user (XSA_DEV)" "XSA_DEV_PWD"
	fi
fi
if [ -z "$PROXY_HOST" -o -z "$PROXY_PORT" ] && [ $RUN_IN_DOCKER -ne 1 ]; then
	promptProxyInfo
fi

checkXSC

if hasDatabase ${HXE_SID}; then
	HAS_TENANT_DB=1
fi

startTenantDB

waitAppsStarted

setupTelemetry

postProcessServer

postProcessXSA

grantActivatedRole

removePostInstallFiles

registerDB

collectGarbage

echo "HDB is successfully optimized."
