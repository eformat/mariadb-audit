# MariaDB Audit using the OpenShift Sidecar Logger

## Scenario

This example uses the mariadb audit plugin and the sidecar logging container to audit database activity.

* Sidecar container - https://github.com/eformat/openshift-sidecar-logger 
* MariaDB audit plugin links:
  - https://mariadb.com/resources/blog/introducing-mariadb-audit-plugin
  - https://mariadb.com/kb/en/library/mariadb-audit-plugin-system-variables/
  - https://mariadb.com/kb/en/library/mariadb-audit-plugin-log-format/
  - https://mariadb.com/kb/en/library/mariadb-audit-plugin-installation/
  
#### MariaDB Image Details

This example uses the supported Red Hat MariaDB image `registry.access.redhat.com/rhscl-beta/mariadb-102-rhel7` which has the audit plugin shared library in the base image - but it is not configured for use initially.

A list of installed plugins can be found:

```
docker run -it --link foo-db --rm registry.access.redhat.com/rhscl-beta/mariadb-102-rhel7 sh -c 'exec mysql -h"$FOO_DB_PORT_3306_TCP_ADDR" -P"$FOO_DB_PORT_3306_TCP_PORT" -uroot -p"my-secret-pw"'

MariaDB [(none)]> SHOW GLOBAL VARIABLES LIKE 'plugin_dir';
+---------------+----------------------------------------------------+
| Variable_name | Value                                              |
+---------------+----------------------------------------------------+
| plugin_dir    | /opt/rh/rh-mariadb102/root/usr/lib64/mysql/plugin/ |
+---------------+----------------------------------------------------+
1 row in set (0.01 sec)

bash-4.2$ ls /opt/rh/rh-mariadb102/root/usr/lib64/mysql/plugin
adt_null.so		   file_key_management.so    mypluglib.so
auth_0x0100.so		   ha_archive.so	     mysql_clear_password.so
auth_ed25519.so		   ha_blackhole.so	     qa_auth_client.so
auth_gssapi.so		   ha_connect.so	     qa_auth_interface.so
auth_gssapi_client.so	   ha_example.so	     qa_auth_server.so
auth_pam.so		   ha_federated.so	     query_cache_info.so
auth_socket.so		   ha_federatedx.so	     query_response_time.so
auth_test_plugin.so	   ha_sphinx.so		     semisync_master.so
client_ed25519.so	   ha_spider.so		     semisync_slave.so
daemon_example.ini	   ha_test_sql_discovery.so  server_audit.so
debug_key_management.so    handlersocket.so	     sha256_password.so
dialog.so		   libdaemon_example.so      simple_password_check.so
dialog_examples.so	   locales.so		     sql_errlog.so
example_key_management.so  metadata_lock_info.so     wsrep_info.so
```

You can manually configure the plugin by doing:

```
INSTALL PLUGIN server_audit SONAME 'server_audit.so';
SET GLOBAL server_audit_events = 'CONNECT,QUERY,TABLE';
SET GLOBAL server_audit_output_type = 'file';
SET GLOBAL server_audit_logging = 'ON';

MariaDB [(none)]> SHOW GLOBAL VARIABLES LIKE '%server_audit%';
+-------------------------------+-----------------------+
| Variable_name                 | Value                 |
+-------------------------------+-----------------------+
| server_audit_events           | CONNECT,QUERY,TABLE   |
| server_audit_excl_users       |                       |
| server_audit_file_path        | server_audit.log      |
| server_audit_file_rotate_now  | OFF                   |
| server_audit_file_rotate_size | 1000000               |
| server_audit_file_rotations   | 9                     |
| server_audit_incl_users       |                       |
| server_audit_logging          | OFF                   |
| server_audit_mode             | 0                     |
| server_audit_output_type      | file                  |
| server_audit_query_log_limit  | 1024                  |
| server_audit_syslog_facility  | LOG_USER              |
| server_audit_syslog_ident     | mysql-server_auditing |
| server_audit_syslog_info      |                       |
| server_audit_syslog_priority  | LOG_INFO              |
+-------------------------------+-----------------------+
15 rows in set (0.01 sec)
```

The MariaDB audit plugin only allows audit to be collected via `syslog` or `file`. This example uses the following customisations:

* enables the audit plugin by default using `docker/audit.cnf` file
* sends `server_audit.log` file entries to the container `STDOUT` so it is available to `oc logs` (see the `docker/rr.sh` script)

#### Log Audit Configuration

The sidecar container git repository has details of the `configmap` settings. For this example, we are monitoring the following container and filter pattern (which matches the start of each mariadb audit log entry):

```
  container_name: 'mariadb'
  grep_pattern: '\d{8}\s\d{2}:\d{2}:\d{2},[a-z0-9_-]+,'
```

Ensure you have your logging REST endpoint available for batch log collection.

#### Running the example

Build a custom MariDB image in OpenShift:

```
git clone this repository
cd docker
oc import-image registry.access.redhat.com/rhscl-beta/mariadb-102-rhel7 --confirm -n openshift
oc new-build -n openshift --name=my-mariadb --strategy=docker --binary
oc start-build -n openshift my-mariadb --from-file=. --follow
```

Create a project in OpenShift as a normnal user

```
oc new-project mariab-audit-example --display-name="MariaDB Audit Example" --description="MariaDB Audit Example"
```

Allow the namespace `default` system account view access (this is so the `oc` command in the sidecar can read container logs)

```
oc policy add-role-to-user view system:serviceaccount:$(oc project -q):default
```

Create the `configmap` that configures the sidecar container:

```
oc apply -f config-map.yml
```

Create the `secret` that configures the usernames and passwords for the mariadb, set these to your liking before creating the secret:

```
These are Base64 encoded in the secret:
  database-name: sampledb
  database-password: MxX1pfysqfBamWWQ
  database-root-password: TFnIpHobSKh8XHcp
  database-user: userRQK
```

```
oc apply -f secret.yml
```

Create the `service` for the database port:

```
oc apply -f service.yml
```

Create the `deploymentconfig` for the mariadb application pod (it uses ephemaral storage)

```
oc apply -f deployment-config.yml
```

#### Rollout a new configuration

Update the `ConfigMap` and redeploy the example pod

```
oc apply -f config-map.yml
oc rollout latest mariadb
```

#### Testing

You should see the readiness check already in the mariadb pod log:

```
20171019 00:36:10,mariadb-6-rz342,userRQK,127.0.0.1,67,0,CONNECT,sampledb,,0
20171019 00:36:10,mariadb-6-rz342,userRQK,127.0.0.1,67,94,QUERY,sampledb,'select @@version_comment limit 1',0
20171019 00:36:10,mariadb-6-rz342,userRQK,127.0.0.1,67,95,QUERY,sampledb,'SELECT 1',0
20171019 00:36:10,mariadb-6-rz342,userRQK,127.0.0.1,67,0,DISCONNECT,sampledb,,0
```

You can login to the database remotely:

```
oc exec $(oc get pods -lapp=mariadb --template='{{range .items}}{{.metadata.name}}{{end}}') -c mariadb -i -t -- bash -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -h 127.0.0.1 -u $MYSQL_USER -D $MYSQL_DATABASE'
```

This will appear in the mariadb pod logs and be collected in the batch log server endpoint.


