# Ensure that assigned uid has entry in /etc/passwd.

if [ `id -u` -ge 10000 ]; then
 cat /etc/passwd | sed -e "s/^shiny:/builder:/" > /tmp/passwd
 echo "shiny:x:`id -u`:`id -g`:,,,:/srv/shiny-server:/bin/bash" >> /tmp/passwd
 cat /tmp/passwd > /etc/passwd
 rm /tmp/passwd
 fi