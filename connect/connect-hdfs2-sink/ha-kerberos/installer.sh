#/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
for INSTALLER in $(env | grep INSTALLER_); do
        # https://techglimpse.com/failed-metadata-repo-appstream-centos-8/
        # Centos 8 is EOL BEGIN
        cd /etc/yum.repos.d/
        sudo sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
        sudo sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
        # https://serverfault.com/a/1093928
        sudo sed -i 's|baseurl=http://vault.centos.org|baseurl=http://vault.epel.cloud|g' /etc/yum.repos.d/CentOS-Linux-*
        # Centos 8 is EOL END
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