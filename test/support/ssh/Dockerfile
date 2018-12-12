FROM connesc/ssh-gateway
MAINTAINER Tiago Cardoso <cardoso_tiago@hotmail.com>

RUN apk add --no-cache shadow

RUN echo -e $'\n\
PermitRootLogin prohibit-password\n\
AllowAgentForwarding no\n\
X11Forwarding no\n\
PermitTTY yes\n\
LogLevel VERBOSE\n\
AllowTcpForwarding yes\n\
PermitEmptyPasswords yes\n\
PasswordAuthentication no\n\
PubkeyAuthentication yes\n' >> /etc/ssh/sshd_config 

RUN usermod --shell /bin/sh root
