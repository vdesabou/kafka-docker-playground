#/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
for INSTALLER in $(env | grep INSTALLER_); do
        sudo yum install -y rsync
        cd /
        ID=$(id -u -n)
        KEY=$(echo $INSTALLER | awk -F '=' '{print $1}')
        COMPONENT=$(echo $KEY | awk -F '_' '{print tolower($2)}')
        URL=$(echo $INSTALLER | awk -F '=' '{print $2}')
        COMPONENT_DIR=/opt/$COMPONENT
        sudo rm -rf /opt/unpack
        sudo mkdir -p /opt/unpack
        sudo mkdir -p /opt/download
        sudo chown $ID /opt/unpack
        sudo chown $ID /opt/download
        DESTFILE=/opt/download/$COMPONENT.tar.gz
        if [ ! -f "$DESTFILE" ]; then
            wget $URL -O $DESTFILE
        fi
        tar xzf $DESTFILE -C /opt/unpack
        REL_CONF=${CONF_DIR#$COMPONENT_DIR/}
        SW_DIR="/opt/unpack/$(ls -1 /opt/unpack | head )"
        sudo rsync -ah --delete --exclude $REL_CONF $SW_DIR/ $COMPONENT_DIR
        sudo chown -R  $ID /opt/$COMPONENT
        rm -rf /opt/unpack
        cd -
done

call-next-plugin "$@"