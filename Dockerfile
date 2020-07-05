FROM ibmjava:latest
################################################################################################
################################################################################################
################################################################################################
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y git curl wget ca-certificates supervisor && \
    curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash && \
    apt-get install -y git-lfs && \
    git lfs install && \
    rm -rf /var/lib/apt/lists/*
################################################################################################
################################################################################################
################################################################################################
ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000
ARG http_port=8080
ARG agent_port=50000
ARG dbb_port=9080
ARG JENKINS_HOME=/var/jenkins_home
ARG DBB_HOME=/var/dbb_home
ARG DBB_VERSION=1.0.9
ARG REF=/usr/share/jenkins/ref

ENV JENKINS_HOME $JENKINS_HOME
ENV JENKINS_SLAVE_AGENT_PORT ${agent_port}
ENV REF $REF

# jenkins version being bundled in this docker image
ARG JENKINS_VERSION
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.176.2}

# jenkins.war checksum, download will be validated using it
ARG JENKINS_SHA=33a6c3161cf8de9c8729fd83914d781319fd1569acf487c7b1121681dba190a5

# Can be used to customize where jenkins.war get downloaded from
ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war

ENV JENKINS_UC https://updates.jenkins.io
ENV JENKINS_UC_EXPERIMENTAL=https://updates.jenkins.io/experimental
ENV JENKINS_INCREMENTALS_REPO_MIRROR=https://repo.jenkins-ci.org/incrementals

################################################################################################
#########################################JENKINS################################################                                                 
################################################################################################
# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container,
# ensure you use the same uid
RUN mkdir -p $JENKINS_HOME \
    mkdir -p $DBB_HOME  \
    && chown ${uid}:${gid} $JENKINS_HOME \
    && chown ${uid}:${gid} $DBB_HOME \
    && groupadd -g ${gid} ${group} \
    && useradd -d "$JENKINS_HOME" -u ${uid} -g ${gid} -m -s /bin/bash ${user}

# Jenkins home directory is a volume, so configuration and build history
# can be persisted and survive image upgrades
VOLUME $JENKINS_HOME
VOLUME $DBB_HOME
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
RUN chown -R ${user} "$JENKINS_HOME" "$REF" "$DBB_HOME"
#
# for main web interface:
EXPOSE ${http_port}

# will be used by attached slave agents:
EXPOSE ${agent_port}
#
# will be used by dbb web server:
EXPOSE ${dbb_port}
#
################################################################################################
################################IBM DBB Web Server##############################################                                                 
################################################################################################
RUN cd /var/dbb_home/ && \
    curl -fsSL https://public.dhe.ibm.com/ibmdl/export/pub/software/htp/zos/aqua31/dbb/1.0.9/dbb-server-1.0.9.tar.gz -o /var/dbb_home/dbb-server-1.0.9.tar.gz  && \
    tar -xvf dbb-server-1.0.9.tar.gz 

COPY server.xml /var/dbb_home/wlp/usr/servers/dbb/
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh
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
RUN mkdir -p /var/log/supervisord/ 
#
#  USER ${user}
#
#
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]