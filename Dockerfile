FROM ubuntu:groovy-20210325
#FROM ibmjava
################################################################################################
################################################################################################
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata xsltproc sshpass maven
ENV TZ=Asia/Kolkata
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN dpkg-reconfigure --frontend noninteractive tzdata
################################################################################################
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && \
    apt-get upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y git curl wget ca-certificates supervisor openjdk-11-jdk ansible && \
    curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash && \
    apt-get install -y git-lfs && \
    git lfs install && \
    rm -rf /var/lib/apt/lists/*
# #
################################################################################################
################################################################################################
################################################################################################
ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000
ARG http_port=8080
ARG agent_port=50000
ARG dbb_port=9443
ARG ANSIBLE_HOME=
ARG JENKINS_HOME=/var/jenkins_home
ARG DBB_HOME=/var/dbb_home
ARG DBB_VERSION=1.0.9
ARG REF=/usr/share/jenkins/ref
ARG KEYS_PATH=${KEYS_PATH:-/var/jenkins_home/.ssh}
ARG PRIVATE_KEY=$KEYS_PATH/id_rsa
ARG PUBLIC_KEY=${PRIVATE_KEY}.pub


ENV JENKINS_HOME $JENKINS_HOME
ENV JENKINS_SLAVE_AGENT_PORT ${agent_port}
ENV REF $REF
ENV KEYS_PATH=${KEYS_PATH:-/var/jenkins_home/.ssh}
ENV PRIVATE_KEY=$KEYS_PATH/id_rsa
ENV PUBLIC_KEY=${PRIVATE_KEY}.pub
# jenkins version being bundled in this docker image
ARG JENKINS_VERSION
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.284}

# jenkins.war checksum, download will be validated using it
ARG JENKINS_SHA=f014255f0a9375f9abefced07c88525a01ffcb478bd3f76c93d42f1d91ef1d44

# Can be used to customize where jenkins.war get downloaded from
ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war

ENV JENKINS_UC https://updates.jenkins.io
ENV JENKINS_UC_EXPERIMENTAL=https://updates.jenkins.io/experimental
ENV JENKINS_INCREMENTALS_REPO_MIRROR=https://repo.jenkins-ci.org/incrementals
################################################################################################
#########################################JENKINS################################################                                                 
################################################################################################

RUN mkdir -p $JENKINS_HOME \
    && mkdir -p $DBB_HOME \
    && chmod 777 $JENKINS_HOME \
    && chmod 777 $DBB_HOME
# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container,
# ensure you use the same uid
RUN chown ${uid}:${gid} $JENKINS_HOME \
    && groupadd -g ${gid} ${group} \
    && useradd -d "$JENKINS_HOME" -u ${uid} -g ${gid} -m -s /bin/bash ${user}
# RUN echo -e "jenkins ALL=(ALL) NOPASSWD:ALL" /etc/sudoers
# ###########Omit this line $$$$
# RUN echo "jenkins:jenkins" | chpasswd
##############################
# $REF (defaults to `/usr/share/jenkins/ref/`) contains all reference configuration we want
# to set on a fresh new installation. Use it to bundle additional plugins
# or config file with your custom jenkins Docker image.
RUN mkdir -p ${REF}/init.groovy.d
# Use tini as subreaper in Docker container to adopt zombie processes
ARG TINI_VERSION=v0.19.0
COPY tini_pub.gpg ${JENKINS_HOME}/tini_pub.gpg
RUN curl -fsSL https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-$(dpkg --print-architecture) -o /sbin/tini \
    && curl -fsSL https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-$(dpkg --print-architecture).asc -o /sbin/tini.asc \
    && gpg --no-tty --import ${JENKINS_HOME}/tini_pub.gpg \
    && gpg --verify /sbin/tini.asc \
    && rm -rf /sbin/tini.asc /root/.gnupg \
    && chmod +x /sbin/tini
# could use ADD but this one does not check Last-Modified header neither does it allow to control checksum
# see https://github.com/docker/docker/issues/8331
RUN curl -fsSL ${JENKINS_URL} -o /usr/share/jenkins/jenkins.war \
    && echo "${JENKINS_SHA}  /usr/share/jenkins/jenkins.war" | sha256sum -c -
RUN chown -R ${user} "$JENKINS_HOME" "$REF" 
# OpenShift gives a random uid for the user and some programs try to find a username from the /etc/passwd.
# Let user to fix it, but obviously this shouldn't be run outside OpenShift
RUN chmod ug+rw /etc/passwd
#
################################################################################################
################################IBM DBB Web Server##############################################                                                 
################################################################################################
## Removing DBB due to Open Java issue 

# RUN chown ${uid}:${gid} $DBB_HOME \
#     && chown -R ${user} "$DBB_HOME" \
#     && cd $DBB_HOME \
#     && curl -fsSL https://public.dhe.ibm.com/ibmdl/export/pub/software/htp/zos/aqua31/dbb/1.0.9/dbb-server-1.0.9.tar.gz -o /var/dbb_home/dbb-server-1.0.9.tar.gz  && \
#     tar -xvf dbb-server-1.0.9.tar.gz 
# RUN chmod +x /var/dbb_home/wlp/bin/
# COPY server.xml /var/dbb_home/wlp/usr/servers/dbb/
# RUN chmod 777 /var/dbb_home/wlp/usr/servers/dbb/server.xml
# RUN chmod 777 /var/dbb_home/wlp/usr/servers/
# COPY start.sh /usr/local/bin/start.sh
# RUN chmod +x /usr/local/bin/start.sh
#################################################################################################
COPY jenkins-support /usr/local/bin/jenkins-support
RUN chmod +x /usr/local/bin/jenkins-support
COPY jenkins.sh /usr/local/bin/jenkins.sh
RUN chmod +x /usr/local/bin/jenkins.sh
COPY tini-shim.sh /bin/tini
RUN chmod +x /bin/tini
# from a derived Dockerfile, can use `RUN plugins.sh active.txt` to setup ${REF}/plugins from a support bundle
COPY plugins.sh /usr/local/bin/plugins.sh
RUN chmod +x /usr/local/bin/plugins.sh
COPY install-plugins.sh /usr/local/bin/install-plugins.sh
RUN chmod +x /usr/local/bin/install-plugins.sh
# Copy further configuration files into the Docker image
COPY /supervisord.conf /etc/
RUN chmod 777 /etc/supervisord.conf
RUN mkdir -p /var/log/supervisord/ 
RUN chmod 777 /var/log
RUN chmod 777 /var/log/supervisord/ 

# VOLUME $DBB_HOME
##############################################################################
##############################################################################
##############################################################################
# Add SSH key to jenkins
USER ${user}
RUN mkdir -p /var/jenkins_home/.ssh \
    && /usr/bin/ssh-keygen -q -t rsa -N '' -f $PRIVATE_KEY \
    && chmod 700 $KEYS_PATH \
    && chmod 644 $PUBLIC_KEY \
    && chmod 600 $PRIVATE_KEY \
    && ssh-keyscan -t rsa github.com >> $KEYS_PATH/known_hosts \
    && ssh-keyscan -t rsa github.ibm.com >> $KEYS_PATH/known_hosts \
    && ssh-keyscan -t rsa 192.86.33.143 >> $KEYS_PATH/known_hosts \
    && ssh-keyscan -t rsa 192.86.33.53 >> $KEYS_PATH/known_hosts 
#    && ssh-keyscan -t rsa 198.86.33.174 >> $KEYS_PATH/known_hosts \
#    && ssh-keyscan -t rsa 198.86.33.83 >> $KEYS_PATH/known_hosts \
#    && ssh-keyscan -t rsa 198.81.193.67 >> $KEYS_PATH/known_hosts \
USER root
RUN mkdir -p /.ssh \
    && cp -r $KEYS_PATH/* /.ssh \
    && chown -R ${uid}:${gid} $KEYS_PATH \
    && chmod -R 777 /.ssh \
    # Ansible home setup
    && mkdir -p /.ansible \
    && chown -R ${uid}:${gid} /.ansible \
    && chmod -R 777 /.ansible \
    # Fix git path issue for mainframe(zEUS Lnk)
    && mkdir -p /etc/git/bin \
    && chmod -R +x /etc/git/bin \
    && ln -f -s /usr/bin/git /etc/git/bin/git
##############################################################################
##############################################################################
##############################################################################     
# # Jenkins home directory is a volume, so configuration and build history
# # can be persisted and survive image upgrades
VOLUME $JENKINS_HOME
# for main web interface:
EXPOSE ${http_port}
#
# will be used by attached slave agents:
EXPOSE ${agent_port}
#
# will be used by dbb web server:
# EXPOSE ${dbb_port}
######
USER ${user}
RUN ansible-galaxy collection install ibm.ibm_zos_core -p ${JENKINS_HOME} && \
    ansible-galaxy collection install ibm.ibm_zos_zosmf -p ${JENKINS_HOME} && \
    ansible-galaxy collection install ibm.ibm_zos_sysauto -p ${JENKINS_HOME} && \
    ansible-galaxy collection install ibm.ibm_zos_ims -p ${JENKINS_HOME} && \
    cd ${JENKINS_HOME} && mkdir zconbt && cd zconbt && \
    wget https://public.dhe.ibm.com/ibmdl/export/pub/software/htp/zos/updates/zconbt.zip && \
    jar -xf zconbt.zip 
    
USER root
RUN chown -R ${user} "$JENKINS_HOME" "$REF" 
######
ENTRYPOINT ["/sbin/tini", "--", "/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
# ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
