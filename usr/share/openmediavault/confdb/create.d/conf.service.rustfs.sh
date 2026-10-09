#!/usr/bin/env dash
#
# This file is part of OpenMediaVault.
#
# @license   https://www.gnu.org/licenses/gpl.html GPL Version 3
# @author    ${GITHUB_USER} <${GITHUB_USER}@users.noreply.github.com>
#
# OpenMediaVault is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.

set -e

. /usr/share/openmediavault/scripts/helper-functions

########################################################################
# Update the configuration.
# <config>
#   <services>
#     <rustfs>
#       <enable>0|1</enable>
#       <port>9000</port>
#       <consolePort>9001</consolePort>
#       <consoleEnable>0|1</consoleEnable>
#       <dataRef>uuid-or-empty</dataRef>
#       <accessKey>generated</accessKey>
#       <secretKey>generated</secretKey>
#       <logLevel>error</logLevel>
#       <extraOptions></extraOptions>
#     </rustfs>
#   </services>
# </config>
########################################################################

# Generate a random hex string of <bytes> bytes. The upstream default
# credentials (rustfsadmin) are never used, so a strong pair is created
# right away and can be rotated from the web interface later.
generate_secret() {
	od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'
}

if ! omv_config_exists "/config/services/rustfs"; then
	omv_config_add_node "/config/services" "rustfs"
	omv_config_add_key "/config/services/rustfs" "enable" "0"
	omv_config_add_key "/config/services/rustfs" "port" "9000"
	omv_config_add_key "/config/services/rustfs" "consolePort" "9001"
	omv_config_add_key "/config/services/rustfs" "consoleEnable" "1"
	omv_config_add_key "/config/services/rustfs" "dataRef" ""
	omv_config_add_key "/config/services/rustfs" "accessKey" "$(generate_secret 12)"
	omv_config_add_key "/config/services/rustfs" "secretKey" "$(generate_secret 24)"
	omv_config_add_key "/config/services/rustfs" "logLevel" "error"
	omv_config_add_key "/config/services/rustfs" "extraOptions" ""
fi

exit 0
