#!/bin/bash

# Ram selection sanitization
if ! echo "$MC_RAM" | grep -Eq '^[0-9]+[MG]$'; then
  if ! [ -z "$MC_RAM" ]
  then
    echo "\033[0;31mError: $MC_RAM is not a valid RAM format. Exiting... \033[0m" | tee server_cfg.txt
    exit 1
  fi
fi

# Declare supported Lazymc archs
lazymc_supported_archs="aarch64 x64 armv7"

# Getting arch from system
CPU_ARCH=$(uname -m)

# Adapt the answer in x86 case to support Lazymc url schema
[ $CPU_ARCH = "x86_64" ] && CPU_ARCH="x64"

# Check if Lazymc is supported for that arch, if not, continue disabling Lazymc
if ! echo "$lazymc_supported_archs" | grep -wq "$CPU_ARCH"
then
  echo "\033[0;31mWarning! Your CPU architecture ($CPU_ARCH) is not supported by Lazymc. Disabling it... \033[0m"
  LAZYMC_VERSION="disabled"
fi

# Enter server directory
cd mcserver

#display current config to the user and save to server_cfg.txt
echo ""
echo "\033[0;33mMinecraft server settings: \033[0m" | tee server_cfg.txt
echo "" | tee -a server_cfg.txt
echo "Minecraft Version= \033[0;33m$MC_VERSION\033[0m" | tee -a server_cfg.txt
echo "Lazymc version= \033[0;33m$LAZYMC_VERSION\033[0m" | tee -a server_cfg.txt
echo "Server provider= \033[0;33m$SERVER_PROVIDER\033[0m" | tee -a server_cfg.txt
# echo "Server build= \033[0;33m$SERVER_BUILD\033[0m" | tee -a server_cfg.txt
echo "Dedicated RAM= \033[0;33m${MC_RAM:-"Not specified."}\033[0m" | tee -a server_cfg.txt
echo "Java options= \033[0;33m${JAVA_OPTS:-"Not specified."}\033[0m" | tee -a server_cfg.txt
echo ""
echo "\033[0;33mCurrent configuration saved to mcserver/server_cfg.txt \033[0m"
echo ""

#give user time to read
sleep 1

# Lazymc setup handler
if [ "$LAZYMC_VERSION" = "disabled" ]
then
  echo "\033[0;33mSkipping lazymc download... \033[0m"
  echo ""
else
  if [ "$LAZYMC_VERSION" = "latest" ]
  then
    LAZYMC_VERSION=$(wget -qO - https://api.github.com/repos/timvisee/lazymc/releases/latest | jq -r .tag_name | cut -c 2-)
    if [ -z "$LAZYMC_VERSION" ]
    then
      echo "\033[0;31mError: Could not get latest version of lazymc. Exiting... \033[0m" | tee server_cfg.txt
      exit 1
    fi
  fi
  LAZYMC_URL="https://github.com/timvisee/lazymc/releases/download/v$LAZYMC_VERSION/lazymc-v$LAZYMC_VERSION-linux-$CPU_ARCH"
  status_code=$(curl -s -o /dev/null -w '%{http_code}' ${LAZYMC_URL})
  if [ "$status_code" -ne 302 ]
  then
    echo "\033[0;31mError: Lazymc $LAZYMC_VERSION version does not exist or is not available. Exiting... \033[0m" | tee server_cfg.txt
    exit 1
  fi
  echo "\033[0;33mDownloading lazymc $LAZYMC_VERSION... \033[0m"
  echo ""
  wget -qO lazymc ${LAZYMC_URL}
  chmod +x lazymc
fi

# Declaring supported types
allowed_modded_type="fabric forge"
allowed_servers_type="paper purpur"

# Determine server type
if [ "$SERVER_PROVIDER" = "paper" ]
then
    SERVER_TYPE="servers"
else
    echo "\033[0;31mError: $SERVER_PROVIDER is not supported. Exiting... \033[0m" | tee server_cfg.txt
    exit 1
fi

# Get latest version
if [ ${MC_VERSION} = latest ]
then
  echo "\033[0;33mGetting latest Minecraft version... \033[0m"
  echo ""
  if ! MC_VERSION=$(wget -qO - https://fill.papermc.io/v3/projects/paper | jq -r '.versions | to_entries[0] | .value[0]')
  then
    echo "\033[0;31mError: Could not get latest version of Minecraft. Exiting... \033[0m" | tee server_cfg.txt
    exit 1
  fi
else
  if wget -O - https://fill.papermc.io/v3/projects/paper/versions/${MC_VERSION}/builds | jq -e '.ok == false' > /dev/null 2>&1; then
    echo "\033[0;31mError: Minecraft version $MC_VERSION does not exist or is not available. Exiting... \033[0m" | tee server_cfg.txt
    exit 1
  fi
fi


# FETCH JAR API - thx to centrojars.com
PAPERMC_URL=$(wget -qO - https://fill.papermc.io/v3/projects/paper/versions/${MC_VERSION}/builds | jq -r 'first(.[] | select(.channel == "STABLE") | .downloads."server:default".url) // "null"')
if [ "${PAPERMC_URL}" = "null" ]; then
  echo "\033[0;31mError: There is no build available for Minecraft version $MC_VERSION. Exiting... \033[0m" | tee server_cfg.txt
  exit 1
fi
API_FETCH_JAR=${PAPERMC_URL}

# Set the jar file name
JAR_NAME=${SERVER_PROVIDER}-${MC_VERSION}-${SERVER_BUILD}.jar

# Update jar if necessary
if [ ! -e ${JAR_NAME} ]
then
  # Remove old server jar(s)
  echo "\033[0;33mRemoving old server jars... \033[0m"
  echo ""
  rm -f *.jar
fi

# Download new server jar
echo "\033[0;33mDownloading $JAR_NAME \033[0m"
echo ""
if ! curl -o ${JAR_NAME} -sS ${API_FETCH_JAR}
then
  echo "\033[0;31mError: Jar URL does not exist or is not available. Exiting... \033[0m" | tee server_cfg.txt
  exit 1
fi


# Determine run command
if [ -z "$RUN_COMMAND" ]; then
  RUN_COMMAND="java ${JAVA_OPTS} -jar $JAR_NAME nogui"
else
  echo "\033[0;33mUsing custom run command... \033[0m"
fi


# Generate eula.txt if necessary
if [ ! -e eula.txt ]
then
  echo "\033[0;33mGenerating eula.txt \033[0m"
  echo ""
  if ! echo "eula=true" > eula.txt
  then
    echo "\033[0;31mError: Could not generate eula.txt. Exiting... \033[0m" | tee server_cfg.txt
    exit 1
  fi
fi

# Generate server.properties if not present, Prevents the server from failing to start on first run
if [ ! -e server.properties ]
then
  echo "\033[0;33mGenerating server.properties \033[0m"
  echo ""
  touch server.properties
fi

# Add RAM options to Java options if necessary
echo "\033[0;33mSetting Java arguments... \033[0m"
echo ""
if [ ! -z "${MC_RAM}" ]
then
  JAVA_OPTS="-Xms512M -Xmx${MC_RAM} ${JAVA_OPTS}"
else
  JAVA_OPTS="-Xms512M ${JAVA_OPTS}"
fi

# Generate lazymc.toml if necessary
if [ ! -e lazymc.toml ] && [ ! "$LAZYMC_VERSION" = "disabled" ]
then
  echo "\033[0;33mGenerating lazymc.toml \033[0m"
  echo ""
  if ! ./lazymc config generate
  then
    echo "\033[0;31mError: Could not generate lazymc.toml. Exiting... \033[0m" | tee server_cfg.txt
    exit 1
  fi
fi

# Add new values to lazymc.toml
if [ ! "$LAZYMC_VERSION" = "disabled" ]
then
  echo "\033[0;33mUpdating lazymc.toml with latest details... \033[0m"
  echo ""
  # Check if the comment is already present in the file
  if ! grep -q "mcserver-lazymc-docker" lazymc.toml;
  then
    # Add the comment to the file
    sed -i '/Command to start the server/i # Managed by mcserver-lazymc-docker, please do not edit this!' lazymc.toml
  fi
  if ! sed -i "s~command = .*~command = \"$RUN_COMMAND\"~" lazymc.toml
  then
    echo "\033[0;31mError: Could not update lazymc.toml. Exiting... \033[0m" | tee server_cfg.txt
    exit 1
  fi
fi

# Server launch handler
if [ "$LAZYMC_VERSION" = "disabled" ]
then
  # Start directly the server when lazymc is disabled
  echo "\033[0;33mStarting the server! \033[0m"
  echo ""
  if ! $RUN_COMMAND
  then
    echo "\033[0;31mError: Could not start the server. Exiting... \033[0m" | tee server_cfg.txt
    exit 1
  fi
else
  echo "\033[0;33mStarting the server! \033[0m"
  echo ""
  if ! ./lazymc start
  then
    echo "\033[0;31mError: Could not start the server. Exiting... \033[0m" | tee server_cfg.txt
    exit 1
  fi
fi