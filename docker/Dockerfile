FROM registry.access.redhat.com/rhscl-beta/mariadb-102-rhel7
COPY audit.cnf /etc/opt/rh/rh-mariadb102/my.cnf.d/
COPY rr.sh /tmp/rr.sh
COPY runme.sh /tmp/runme.sh
ENTRYPOINT ["container-entrypoint"]
CMD ["/tmp/runme.sh"]
