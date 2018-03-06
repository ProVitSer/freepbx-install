#!/bin/bash
###########################################################################
#             Debian/Asterisk 13/FreePBX 13 Install Script                #
###########################################################################

WORK_DIR=/usr/src/
host=$(hostname -i)

echo "-----Сейчас будет выполнена процедура установки программной АТС -----"
echo "-------------------Необходимо подключение к Интернет_------------------------"
echo "------------------Если Вы готовы к установке, нажмите "y" -------------------"
echo "------Если Вы запустили скрипт случайно, нажмите любую клавишу для выхода----"

###########################################################################
#Получаем y для продлжения установки, n для выхода из установщика
echo "(y/n)?"
read YN_INPUT
if [ "$YN_INPUT" = y -o "$YN_INPUT" = Y ]; then
    echo "Запускается процедура установки"
else echo "Установка отменена"
fi 
###########################################################################
 
###########################################################################
#Проверка на версию 8 Debian. Иные дистрибутивы данным скриптом не поддерживаются. 
DEBIAN_VERSION=$(/bin/cat /etc/debian_version | awk 'BEGIN {FS="."}{print $1}')
if [ "$DEBIAN_VERSION" != "8" ]; then
echo "Это не Debian 8. Установщик вынужден выйти."
exit 1
else echo '' ; echo "Определена версия Debian $DEBIAN_VERSION"
fi
###########################################################################


###########################################################################
#Проверка на доступность Интернет, в частности downloads.asterisk.com
if ping -c 3 downloads.asterisk.org > /dev/null
then 
echo ''
echo "Подключение к Интернет имеется"
else echo "Подключение к Интернет отсутствует или нестабильно. Установщик вынужден выйти"
exit 1
fi
read -p "Нажмите Enter для продолжения..."
###########################################################################

###########################################################################
#Обновляем системные пакеты
apt-get update
apt-get -y upgrade
###########################################################################

###########################################################################
echo "Устанавливаем MySQL"
export DEBIAN_FRONTEND="noninteractive"
debconf-set-selections <<< "mysql-server mysql-server/root_password password "
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password "
apt-get -y install mysql-server
service mysql restart
###########################################################################

###########################################################################
echo "Устанавливаем зависимости для сборки"
apt-get install -y build-essential linux-headers-`uname -r` openssh-server apache2
apt-get install -y mysql-client bison flex php5 php5-curl php5-cli php5-mysql php-pear php5-gd curl sox
apt-get install -y libncurses5-dev libssl-dev libmysqlclient-dev mpg123 libxml2-dev libnewt-dev sqlite3
apt-get install -y libsqlite3-dev pkg-config automake libtool autoconf git unixodbc-dev uuid uuid-dev
apt-get install -y libasound2-dev libogg-dev libvorbis-dev libcurl4-openssl-dev libical-dev libneon27-dev libsrtp0-dev
apt-get install -y libspandsp-dev sudo libmyodbc subversion mc tcpdump ntpdate fail2ban
###########################################################################

###########################################################################
echo "Синхронизуем время на сервере..."
/etc/init.d/ntp stop
/usr/sbin/ntpdate ru.pool.ntp.org
/etc/init.d/ntp start
/usr/sbin/update-rc.d ntp defaults
echo
###########################################################################

###########################################################################
#Cкачиваем Asterisk 13, Jansson, Pjproject
echo "Качаем пакеты для сборки..."
cd $WORK_DIR
wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-13-current.tar.gz
wget -O jansson.tar.gz https://github.com/akheron/jansson/archive/v2.7.tar.gz
wget http://www.pjsip.org/release/2.4/pjproject-2.4.tar.bz2
###########################################################################

###########################################################################
echo "Pjproject"
cd $WORK_DIR
tar -xjvf pjproject-2.4.tar.bz2
rm -f pjproject-2.4.tar.bz2
cd pjproject-2.4
CFLAGS='-DPJ_HAS_IPV6=1' ./configure --enable-shared --disable-sound --disable-resample --disable-video --disable-opencore-amr
make dep
make
make install
###########################################################################

###########################################################################
echo "Jansson"
cd $WORK_DIR
tar vxfz jansson.tar.gz
rm -f jansson.tar.gz
cd jansson-*
autoreconf -i
./configure
make
make install
###########################################################################

###########################################################################
# Устанавлиаем Asterisk
echo "Asterisk"
cd $WORK_DIR/asterisk
tar xzvf $WORK_DIR/asterisk-13-current.tar.gz
cd asterisk-*
contrib/scripts/get_mp3_source.sh 
contrib/scripts/install_prereq install 
make clean
./configure
make menuselect.makeopts
menuselect/menuselect  --enable res_rtp_asterisk --enable res_fax --enable CORE-SOUNDS-RU-WAV --enable app_meetme menuselect.makeopts
make && make install && make config && ldconfig
sed -i 's/defaultlanguage = en/defaultlanguage = ru/' /etc/asterisk/asterisk.conf
sed -i 's/;language=en/language=ru/' /etc/asterisk/*.conf
sed -i "s|#AST_USER=\"asterisk\"|AST_USER=\"asterisk\"|" /etc/default/asterisk
sed -i "s|#AST_GROUP=\"dialout\"|AST_GROUP=\"dialout\"|" /etc/default/asterisk
###########################################################################


###########################################################################

echo "Права Asterisk"
useradd -m asterisk
chown asterisk. /var/run/asterisk
chown -R asterisk. /etc/asterisk
chown -R asterisk. /var/{lib,log,spool}/asterisk
chown -R asterisk. /usr/lib/asterisk
###########################################################################


echo "net.ipv4.conf.all.arp_ignore = 1" >> /etc/sysctl.conf

###########################################################################
#Вносим изменения в Apache
sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php5/apache2/php.ini
cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf_orig
sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf
sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
a2enmod rewrite
service apache2 restart
###########################################################################

###########################################################################
#Настраиваем ODBC
cat >> /etc/odbcinst.ini << EOF
[MySQL]
Description = ODBC for MySQL
Driver = /usr/lib/x86_64-linux-gnu/odbc/libmyodbc.so
Setup = /usr/lib/x86_64-linux-gnu/odbc/libodbcmyS.so
FileUsage = 1
  
EOF

cat >> /etc/odbc.ini << EOF
[MySQL-asteriskcdrdb]
Description=MySQL connection to 'asteriskcdrdb' database
driver=MySQL
server=localhost
database=asteriskcdrdb
Port=3306
Socket=/var/run/mysqld/mysqld.sock
option=3
  
EOF
###########################################################################

###########################################################################
# Устанавлиаем FreePBX
cd /usr/src
wget http://mirror.freepbx.org/modules/packages/freepbx/freepbx-13.0-latest.tgz
tar vxfz freepbx-13.0-latest.tgz
rm -f freepbx-13.0-latest.tgz
cd freepbx
./start_asterisk start
./install -n
###########################################################################

safe_asterisk
sleep 10

###########################################################################
#Устанавливаем дополнительные модули FreePBX
fwconsole ma downloadinstall callwaiting backup blacklist callforward fax ivr queues ringgroups setcid timeconditions
fwconsole restart
sleep 10
###########################################################################


echo "---------------------------------------------------------------------------"
echo "---------------------------------------------------------------------------"
echo "----------------------Установка завершена!!!-------------------------------"
echo "---------------------------------------------------------------------------"
echo "---------------------------------------------------------------------------"
echo "----Для настройки используте web-интерфейс - http://"$host"/admin ---"
echo "---------------------------------------------------------------------------"
echo "---------------------------------------------------------------------------"

exit 0
